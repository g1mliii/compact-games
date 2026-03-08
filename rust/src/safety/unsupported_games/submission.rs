use std::fs;
use std::time::{SystemTime, UNIX_EPOCH};

use super::storage::{
    pending_report_payload_path, persist_sync_meta, report_submission_endpoint_path,
};
use super::types::{
    UnsupportedReportCandidate, UnsupportedReportPayload, UnsupportedReportPayloadFingerprint,
    UnsupportedSubmissionResponse, UnsupportedSyncMeta,
};
use super::{
    now_ms, COMMUNITY, EMBEDDED, REPORT_RECORDS, REPORT_STABILITY_WINDOW_MS,
    REPORT_SUBMISSION_INTERVAL_MS, SYNC_META,
};

fn build_submission_candidates_at(current_time_ms: u64) -> Vec<UnsupportedReportCandidate> {
    let community = match COMMUNITY.read() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    let records = match REPORT_RECORDS.read() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };

    let mut candidates = Vec::with_capacity(records.len());
    for (folder_name, record) in records.iter() {
        if !record.active {
            continue;
        }
        if EMBEDDED.contains(folder_name) || community.contains(folder_name) {
            continue;
        }
        if current_time_ms.saturating_sub(record.activated_at_ms) < REPORT_STABILITY_WINDOW_MS {
            continue;
        }

        candidates.push(UnsupportedReportCandidate {
            folder_name: folder_name.clone(),
            first_reported_at_ms: record.first_reported_at_ms,
            active_since_ms: record.activated_at_ms,
            last_reported_at_ms: record.last_reported_at_ms,
            last_withdrawn_at_ms: record.last_withdrawn_at_ms,
            report_count: record.report_count,
        });
    }

    candidates.sort_by(|left, right| left.folder_name.cmp(&right.folder_name));
    candidates
}

fn stable_payload_hash(bytes: &[u8]) -> String {
    let mut hash = 0xcbf29ce484222325u64;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    format!("{hash:016x}")
}

fn trimmed_non_empty(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return None;
    }
    Some(trimmed.to_string())
}

fn configured_submission_endpoint() -> Option<String> {
    #[cfg(test)]
    {
        let path = report_submission_endpoint_path().ok()?;
        let contents = fs::read_to_string(path).ok()?;
        trimmed_non_empty(&contents)
    }

    #[cfg(not(test))]
    {
        if let Ok(value) = std::env::var(super::REPORT_SUBMISSION_ENDPOINT_ENV) {
            if let Some(endpoint) = trimmed_non_empty(&value) {
                return Some(endpoint);
            }
        }

        let path = report_submission_endpoint_path().ok()?;
        let contents = fs::read_to_string(path).ok()?;
        trimmed_non_empty(&contents)
    }
}

fn generate_install_id() -> String {
    let seed = format!(
        "{}:{}:{}",
        std::process::id(),
        now_ms(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos()
    );
    format!("pp-{}", stable_payload_hash(seed.as_bytes()))
}

fn ensure_install_id() -> Result<String, String> {
    let mut meta = match SYNC_META.write() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };

    if let Some(existing) = meta.install_id.clone() {
        return Ok(existing);
    }

    let install_id = generate_install_id();
    meta.install_id = Some(install_id.clone());
    drop(meta);
    persist_sync_meta()?;
    Ok(install_id)
}

pub(super) fn should_submit_payload(
    meta: &UnsupportedSyncMeta,
    payload_hash: &str,
    current_time_ms: u64,
) -> bool {
    if meta.last_submitted_payload_hash.as_deref() == Some(payload_hash) {
        return false;
    }

    match meta.last_submitted_at_ms {
        None => true,
        Some(last_submitted_at_ms) => {
            current_time_ms.saturating_sub(last_submitted_at_ms) >= REPORT_SUBMISSION_INTERVAL_MS
        }
    }
}

fn reporter_token() -> Option<String> {
    match SYNC_META.read() {
        Ok(guard) => guard.reporter_token.clone(),
        Err(poisoned) => poisoned.into_inner().reporter_token.clone(),
    }
}

fn submit_report_payload(
    endpoint: &str,
    reporter_token: Option<&str>,
    payload_json: &str,
) -> Result<Option<String>, String> {
    const TIMEOUT_SECS: u64 = 15;

    let agent = ureq::Agent::new_with_config(
        ureq::config::Config::builder()
            .timeout_global(Some(std::time::Duration::from_secs(TIMEOUT_SECS)))
            .build(),
    );

    let mut request = agent
        .post(endpoint)
        .header("Content-Type", "application/json")
        .header("User-Agent", "PressPlay-Unsupported-Reports/1");
    if let Some(reporter_token) = reporter_token {
        request = request.header("X-PressPlay-Reporter-Token", reporter_token);
    }

    let mut response = request
        .send(payload_json)
        .map_err(|e| format!("HTTP request failed: {e}"))?;
    let response_body = response
        .body_mut()
        .read_to_string()
        .map_err(|e| format!("Failed to read unsupported report response body: {e}"))?;

    if response_body.trim().is_empty() {
        return Ok(None);
    }

    let response: UnsupportedSubmissionResponse = serde_json::from_str(&response_body)
        .map_err(|e| format!("Invalid unsupported report response JSON: {e}"))?;

    Ok(response
        .reporter_id
        .and_then(|value| trimmed_non_empty(&value)))
}

fn mark_payload_submitted(
    payload_hash: &str,
    submitted_at_ms: u64,
    reporter_token: Option<String>,
) -> Result<(), String> {
    let mut meta = match SYNC_META.write() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    meta.last_submitted_at_ms = Some(submitted_at_ms);
    meta.last_submitted_payload_hash = Some(payload_hash.to_string());
    if let Some(reporter_token) = reporter_token {
        meta.reporter_token = Some(reporter_token);
    }
    drop(meta);
    persist_sync_meta()
}

pub(super) fn sync_report_collection_inner(app_version: &str) -> Result<u32, String> {
    let normalized_version = if app_version.trim().is_empty() {
        "unknown".to_string()
    } else {
        app_version.trim().to_string()
    };
    let install_id = ensure_install_id()?;
    let generated_at_ms = now_ms();
    let reports = build_submission_candidates_at(generated_at_ms);
    let payload = UnsupportedReportPayload {
        install_id: install_id.clone(),
        app_version: normalized_version.clone(),
        generated_at_ms,
        reports,
    };
    let payload_fingerprint = UnsupportedReportPayloadFingerprint {
        install_id: &install_id,
        app_version: &normalized_version,
        reports: &payload.reports,
    };
    let fingerprint_bytes = serde_json::to_vec(&payload_fingerprint)
        .map_err(|e| format!("Failed to encode payload fingerprint: {e}"))?;
    let payload_hash = stable_payload_hash(&fingerprint_bytes);
    let payload_path = pending_report_payload_path()
        .map_err(|e| format!("Failed to resolve payload path: {e}"))?;
    let should_persist = !payload_path.exists()
        || match SYNC_META.read() {
            Ok(guard) => {
                guard.last_prepared_payload_hash.as_deref() != Some(payload_hash.as_str())
                    || guard.last_prepared_app_version.as_deref()
                        != Some(normalized_version.as_str())
            }
            Err(poisoned) => {
                let guard = poisoned.into_inner();
                guard.last_prepared_payload_hash.as_deref() != Some(payload_hash.as_str())
                    || guard.last_prepared_app_version.as_deref()
                        != Some(normalized_version.as_str())
            }
        };
    let submission_endpoint = configured_submission_endpoint();
    let should_submit = if submission_endpoint.is_some() {
        match SYNC_META.read() {
            Ok(guard) => should_submit_payload(&guard, &payload_hash, generated_at_ms),
            Err(poisoned) => {
                let guard = poisoned.into_inner();
                should_submit_payload(&guard, &payload_hash, generated_at_ms)
            }
        }
    } else {
        false
    };
    let payload_json = if should_persist || should_submit {
        Some(
            serde_json::to_string(&payload)
                .map_err(|e| format!("Failed to encode payload: {e}"))?,
        )
    } else {
        None
    };

    if should_persist {
        let payload_json = payload_json
            .as_deref()
            .ok_or_else(|| "Missing payload JSON for persistence".to_string())?;
        crate::utils::atomic_write(&payload_path, payload_json.as_bytes())
            .map_err(|e| format!("Failed to persist report payload: {e}"))?;

        let mut meta = match SYNC_META.write() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        meta.last_prepared_at_ms = Some(generated_at_ms);
        meta.last_prepared_app_version = Some(normalized_version);
        meta.last_prepared_payload_hash = Some(payload_hash.clone());
        drop(meta);
        persist_sync_meta()?;
    }

    if should_submit {
        let payload_json = payload_json
            .as_deref()
            .ok_or_else(|| "Missing payload JSON for submission".to_string())?;
        let reporter_token = reporter_token();
        if let Some(endpoint) = submission_endpoint {
            match submit_report_payload(&endpoint, reporter_token.as_deref(), payload_json) {
                Ok(reporter_token) => {
                    mark_payload_submitted(&payload_hash, generated_at_ms, reporter_token)?;
                }
                Err(error) => {
                    log::warn!("Failed to submit unsupported report payload: {error}");
                }
            }
        }
    }

    Ok(payload.reports.len() as u32)
}
