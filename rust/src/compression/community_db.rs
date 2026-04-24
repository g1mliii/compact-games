use std::collections::{BTreeMap, HashMap};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, LazyLock, RwLock};
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};

use super::algorithm::CompressionAlgorithm;
use crate::net::github_release_fetcher::{fetch_signed_release_asset, ReleaseJsonAsset};

const COMMUNITY_DB_FETCH_INTERVAL: Duration = Duration::from_secs(24 * 60 * 60);
const COMMUNITY_DB_FAILURE_RETRY_INTERVAL: Duration = Duration::from_secs(60 * 60);
const MAX_DB_BYTES: u64 = 8 * 1024 * 1024;
const USER_AGENT: &str = "CompactGames-CompressionDb/1";
pub(crate) const DEFAULT_COMMUNITY_DB_ENDPOINT: &str =
    "https://github.com/g1mliii/compact-games/releases/latest/download/compression_db.v1.json";
pub(crate) const DEFAULT_COMMUNITY_DB_BUNDLE_ENDPOINT: &str =
    "https://github.com/g1mliii/compact-games/releases/latest/download/compression_db.v1.bundle.json";

static COMMUNITY_DB: LazyLock<RwLock<CommunityDbState>> =
    LazyLock::new(|| RwLock::new(CommunityDbState::NotLoaded));

#[derive(Debug, Clone, PartialEq)]
pub struct CommunityEstimate {
    pub saved_ratio: f64,
    pub samples: u32,
}

#[derive(Debug, Clone, PartialEq)]
pub enum CommunityLookup {
    Hit(CommunityEstimate),
    Pending,
    Miss,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct CommunityCompressionDatabase {
    pub version: u32,
    #[serde(default)]
    pub generated_at: String,
    #[serde(default)]
    pub source: String,
    #[serde(default)]
    pub entries: BTreeMap<String, CommunityCompressionEntry>,
    #[serde(default)]
    pub aliases: BTreeMap<String, String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct CommunityCompressionEntry {
    pub name: String,
    #[serde(default)]
    pub folder_name: Option<String>,
    #[serde(default)]
    pub samples: u32,
    #[serde(default)]
    pub ratios: CommunityAlgorithmRatios,
    #[serde(default)]
    pub ratio_samples: CommunityAlgorithmSamples,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct CommunityAlgorithmRatios {
    #[serde(default)]
    pub xpress4k: Option<f64>,
    #[serde(default)]
    pub xpress8k: Option<f64>,
    #[serde(default)]
    pub xpress16k: Option<f64>,
    #[serde(default)]
    pub lzx: Option<f64>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct CommunityAlgorithmSamples {
    #[serde(default)]
    pub xpress4k: Option<u32>,
    #[serde(default)]
    pub xpress8k: Option<u32>,
    #[serde(default)]
    pub xpress16k: Option<u32>,
    #[serde(default)]
    pub lzx: Option<u32>,
}

#[derive(Debug, Clone, Default)]
struct CommunityDbIndex {
    entries: HashMap<String, CommunityCompressionEntry>,
    aliases: HashMap<String, String>,
}

#[derive(Debug, Clone)]
enum CommunityDbState {
    NotLoaded,
    Fetching,
    Loaded(Arc<CommunityDbIndex>),
    Unavailable { retry_after: Instant },
}

#[derive(Debug, Clone)]
pub struct GameLookupContext<'a> {
    pub steam_app_id: Option<u32>,
    pub game_name: Option<&'a str>,
    pub game_path: &'a Path,
}

pub fn lookup(context: GameLookupContext<'_>, algorithm: CompressionAlgorithm) -> CommunityLookup {
    let index = match current_index_or_warm_up() {
        CommunityDbReadiness::Ready(index) => index,
        CommunityDbReadiness::Pending => return CommunityLookup::Pending,
        CommunityDbReadiness::Unavailable => return CommunityLookup::Miss,
    };
    lookup_in_index(&index, context, algorithm)
        .map(CommunityLookup::Hit)
        .unwrap_or(CommunityLookup::Miss)
}

enum CommunityDbReadiness {
    Ready(Arc<CommunityDbIndex>),
    Pending,
    Unavailable,
}

/// Warm up the community DB cache without blocking the caller. Returns the
/// current index if already loaded, otherwise kicks off a background fetch
/// (at most one at a time) and returns `None`. Callers fall back to the
/// heuristic estimator and will pick up the community data on a later call.
fn current_index_or_warm_up() -> CommunityDbReadiness {
    {
        let Ok(guard) = COMMUNITY_DB.read() else {
            return CommunityDbReadiness::Unavailable;
        };
        match &*guard {
            CommunityDbState::Loaded(index) => {
                return CommunityDbReadiness::Ready(index.clone());
            }
            CommunityDbState::Fetching => return CommunityDbReadiness::Pending,
            CommunityDbState::Unavailable { retry_after } if Instant::now() < *retry_after => {
                return CommunityDbReadiness::Unavailable;
            }
            _ => {}
        }
    }

    let Ok(mut guard) = COMMUNITY_DB.write() else {
        return CommunityDbReadiness::Unavailable;
    };
    match &*guard {
        CommunityDbState::Loaded(index) => return CommunityDbReadiness::Ready(index.clone()),
        CommunityDbState::Fetching => return CommunityDbReadiness::Pending,
        CommunityDbState::Unavailable { retry_after } if Instant::now() < *retry_after => {
            return CommunityDbReadiness::Unavailable;
        }
        _ => {}
    }
    *guard = CommunityDbState::Fetching;
    drop(guard);
    spawn_warm_up();
    CommunityDbReadiness::Pending
}

fn spawn_warm_up() {
    std::thread::Builder::new()
        .name("community-db-warmup".to_string())
        .spawn(|| {
            let next_state = match fetch_and_build_index() {
                Ok(index) => CommunityDbState::Loaded(Arc::new(index)),
                Err(error) => {
                    log::warn!("Community compression DB unavailable: {error}");
                    CommunityDbState::Unavailable {
                        retry_after: Instant::now() + COMMUNITY_DB_FAILURE_RETRY_INTERVAL,
                    }
                }
            };
            if let Ok(mut guard) = COMMUNITY_DB.write() {
                *guard = next_state;
            }
        })
        .ok();
}

fn fetch_and_build_index() -> Result<CommunityDbIndex, String> {
    let cache_path = community_db_cache_path()?;
    let db: CommunityCompressionDatabase = fetch_signed_release_asset(ReleaseJsonAsset {
        asset_url: DEFAULT_COMMUNITY_DB_ENDPOINT,
        bundle_url: DEFAULT_COMMUNITY_DB_BUNDLE_ENDPOINT,
        cache_path: &cache_path,
        ttl: COMMUNITY_DB_FETCH_INTERVAL,
        user_agent: USER_AGENT,
        max_body_bytes: MAX_DB_BYTES,
    })?;
    build_index(db)
}

fn lookup_in_index(
    index: &CommunityDbIndex,
    context: GameLookupContext<'_>,
    algorithm: CompressionAlgorithm,
) -> Option<CommunityEstimate> {
    let keys = lookup_keys(context);
    for key in keys {
        let canonical = index.aliases.get(&key).map(String::as_str).unwrap_or(&key);
        let Some(entry) = index.entries.get(canonical) else {
            continue;
        };
        let Some(saved_ratio) = ratio_for_algorithm(&entry.ratios, algorithm) else {
            continue;
        };
        let samples =
            samples_for_algorithm(&entry.ratio_samples, algorithm).unwrap_or(entry.samples);
        if samples == 0 {
            continue;
        }
        return Some(CommunityEstimate {
            saved_ratio: saved_ratio.clamp(0.0, 0.95),
            samples,
        });
    }
    None
}

fn build_index(db: CommunityCompressionDatabase) -> Result<CommunityDbIndex, String> {
    if db.version != 1 {
        return Err(format!(
            "Unsupported community compression DB version: {}",
            db.version
        ));
    }

    let entries = db.entries.into_iter().collect();
    let aliases = db.aliases.into_iter().collect();
    Ok(CommunityDbIndex { entries, aliases })
}

fn lookup_keys(context: GameLookupContext<'_>) -> Vec<String> {
    let mut keys = Vec::with_capacity(3);
    if let Some(app_id) = context.steam_app_id {
        keys.push(format!("steam:{app_id}"));
    }
    if let Some(folder) = context.game_path.file_name().and_then(|name| name.to_str()) {
        if let Some(normalized) = normalize_key_text(folder) {
            keys.push(format!("folder:{normalized}"));
        }
    }
    if let Some(name) = context.game_name.and_then(normalize_key_text) {
        keys.push(format!("name:{name}"));
    }
    keys
}

fn normalize_key_text(value: &str) -> Option<String> {
    let mut normalized = String::with_capacity(value.len());
    let mut pending_space = false;
    for ch in value.chars().flat_map(char::to_lowercase) {
        if ch.is_ascii_alphanumeric() {
            if pending_space && !normalized.is_empty() {
                normalized.push(' ');
            }
            normalized.push(ch);
            pending_space = false;
        } else {
            pending_space = true;
        }
    }
    (!normalized.is_empty()).then_some(normalized)
}

fn ratio_for_algorithm(
    ratios: &CommunityAlgorithmRatios,
    algorithm: CompressionAlgorithm,
) -> Option<f64> {
    match algorithm {
        CompressionAlgorithm::Xpress4K => ratios.xpress4k,
        CompressionAlgorithm::Xpress8K => ratios.xpress8k,
        CompressionAlgorithm::Xpress16K => ratios.xpress16k,
        CompressionAlgorithm::Lzx => ratios.lzx,
    }
}

fn samples_for_algorithm(
    samples: &CommunityAlgorithmSamples,
    algorithm: CompressionAlgorithm,
) -> Option<u32> {
    match algorithm {
        CompressionAlgorithm::Xpress4K => samples.xpress4k,
        CompressionAlgorithm::Xpress8K => samples.xpress8k,
        CompressionAlgorithm::Xpress16K => samples.xpress16k,
        CompressionAlgorithm::Lzx => samples.lzx,
    }
}

fn community_db_cache_path() -> Result<PathBuf, String> {
    #[cfg(test)]
    {
        Ok(std::env::temp_dir().join("compact-games-community-db-tests.json"))
    }

    #[cfg(not(test))]
    {
        let config_dir = dirs::config_dir().ok_or_else(|| "no config dir".to_string())?;
        let compact_games_dir = config_dir.join("compact_games");
        fs::create_dir_all(&compact_games_dir)
            .map_err(|e| format!("Failed to create config dir: {e}"))?;
        Ok(compact_games_dir.join("compression_db.v1.json"))
    }
}

#[cfg(test)]
pub fn replace_database_for_tests(db: CommunityCompressionDatabase) {
    let index = build_index(db).expect("test database should be valid");
    let mut guard = COMMUNITY_DB.write().expect("community DB lock");
    *guard = CommunityDbState::Loaded(Arc::new(index));
}

#[cfg(test)]
pub fn clear_database_for_tests() {
    let _ = fs::remove_file(community_db_cache_path().expect("test cache path"));
    let mut guard = COMMUNITY_DB.write().expect("community DB lock");
    *guard = CommunityDbState::NotLoaded;
}

#[cfg(test)]
pub fn mark_unavailable_for_tests() {
    let mut guard = COMMUNITY_DB.write().expect("community DB lock");
    *guard = CommunityDbState::Unavailable {
        retry_after: Instant::now() + COMMUNITY_DB_FAILURE_RETRY_INTERVAL,
    };
}

#[cfg(test)]
pub fn mark_fetching_for_tests() {
    let mut guard = COMMUNITY_DB.write().expect("community DB lock");
    *guard = CommunityDbState::Fetching;
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_entry() -> CommunityCompressionEntry {
        CommunityCompressionEntry {
            name: "Team Fortress 2".to_string(),
            folder_name: Some("Team Fortress 2".to_string()),
            samples: 47,
            ratios: CommunityAlgorithmRatios {
                xpress4k: Some(0.29),
                xpress8k: Some(0.32),
                xpress16k: None,
                lzx: Some(0.42),
            },
            ratio_samples: CommunityAlgorithmSamples {
                xpress4k: Some(11),
                xpress8k: Some(8),
                xpress16k: None,
                lzx: Some(28),
            },
        }
    }

    #[test]
    fn parses_schema_and_looks_up_steam_id() {
        let mut entries = BTreeMap::new();
        entries.insert("steam:440".to_string(), test_entry());
        replace_database_for_tests(CommunityCompressionDatabase {
            version: 1,
            generated_at: String::new(),
            source: String::new(),
            entries,
            aliases: BTreeMap::new(),
        });

        let hit = lookup(
            GameLookupContext {
                steam_app_id: Some(440),
                game_name: Some("Ignored"),
                game_path: Path::new(r"C:\Games\Ignored"),
            },
            CompressionAlgorithm::Xpress4K,
        );

        let CommunityLookup::Hit(hit) = hit else {
            panic!("steam lookup should hit");
        };
        assert_eq!(hit.samples, 11);
        assert!((hit.saved_ratio - 0.29).abs() < f64::EPSILON);
    }

    #[test]
    fn uses_alias_fallback_for_unique_folder_name() {
        let mut entries = BTreeMap::new();
        entries.insert("steam:440".to_string(), test_entry());
        let mut aliases = BTreeMap::new();
        aliases.insert(
            "folder:team fortress 2".to_string(),
            "steam:440".to_string(),
        );
        replace_database_for_tests(CommunityCompressionDatabase {
            version: 1,
            generated_at: String::new(),
            source: String::new(),
            entries,
            aliases,
        });

        let hit = lookup(
            GameLookupContext {
                steam_app_id: None,
                game_name: None,
                game_path: Path::new(r"C:\Steam\steamapps\common\Team Fortress 2"),
            },
            CompressionAlgorithm::Lzx,
        );

        let CommunityLookup::Hit(hit) = hit else {
            panic!("folder alias should hit");
        };
        assert_eq!(hit.samples, 28);
        assert!((hit.saved_ratio - 0.42).abs() < f64::EPSILON);
    }

    #[test]
    fn misses_without_matching_ratio() {
        let mut entries = BTreeMap::new();
        entries.insert("steam:440".to_string(), test_entry());
        replace_database_for_tests(CommunityCompressionDatabase {
            version: 1,
            generated_at: String::new(),
            source: String::new(),
            entries,
            aliases: BTreeMap::new(),
        });

        let hit = lookup(
            GameLookupContext {
                steam_app_id: Some(440),
                game_name: None,
                game_path: Path::new(r"C:\Games\TF2"),
            },
            CompressionAlgorithm::Xpress16K,
        );

        assert_eq!(hit, CommunityLookup::Miss);
    }

    #[test]
    fn unavailable_state_falls_back_without_fetch_retry() {
        mark_unavailable_for_tests();

        let hit = lookup(
            GameLookupContext {
                steam_app_id: Some(440),
                game_name: Some("Team Fortress 2"),
                game_path: Path::new(r"C:\Games\Team Fortress 2"),
            },
            CompressionAlgorithm::Xpress8K,
        );

        assert_eq!(hit, CommunityLookup::Miss);
    }

    #[test]
    fn fetching_state_reports_pending() {
        mark_fetching_for_tests();

        let hit = lookup(
            GameLookupContext {
                steam_app_id: Some(440),
                game_name: Some("Team Fortress 2"),
                game_path: Path::new(r"C:\Games\Team Fortress 2"),
            },
            CompressionAlgorithm::Xpress8K,
        );

        assert_eq!(hit, CommunityLookup::Pending);
    }
}
