//! Single source of truth for game-name normalization.
//!
//! Folder names on disk carry release-site tags, scene-group tags, version
//! stamps, and language markers that are noise for both the card title and the
//! cover-art query. Discovery calls [`normalize_game_name`] directly; Dart
//! reaches the same function over FRB (`api::discovery::normalize_game_name`),
//! so a newly observed tag is a one-line change that both sides pick up and the
//! displayed title can never disagree with the name used for lookups.

/// Release-site and scene-group suffixes commonly found on extracted games.
const GAME_RELEASE_SUFFIXES: &[&str] = &[
    "steamgg.net",
    "steamrip",
    "fitgirl repack",
    "fitgirl",
    "dodi repack",
    "dodi",
    "elamigos",
    "codex",
    "plaza",
    "skidrow",
    "empress",
    "rune",
    "tenoke",
    "gog",
    "repack",
    "early access",
];

/// Suffixes that are also ordinary words ("The Empress", "Shadow Rune").
/// These strip only after an explicit separator, never after a plain space.
const AMBIGUOUS_GAME_RELEASE_SUFFIXES: &[&str] = &[
    "codex", "plaza", "skidrow", "empress", "rune", "tenoke", "gog",
];

/// Markers that make a bracketed fragment junk rather than part of the title.
/// `Example Adventure (2016)` keeps its year; `Example [MULTi7]` does not.
const JUNK_BRACKET_WORDS: &[&str] = &[
    "early access",
    "repack",
    "steamgg",
    "steamrip",
    "fitgirl",
    "dodi",
    "elamigos",
    "codex",
    "plaza",
    "skidrow",
    "empress",
    "rune",
    "tenoke",
    "gog",
    "multi",
    "language",
    "languages",
    "english",
    "spanish",
    "french",
    "german",
    "italian",
    "russian",
    "polish",
    "portuguese",
    "japanese",
    "korean",
    "chinese",
];

/// Strip release tags, version stamps, and bracketed junk from a game name.
///
/// Returns the trimmed input unchanged when normalization would empty it, so a
/// folder literally named "CODEX" keeps its name.
pub fn normalize_game_name(name: &str) -> String {
    let original = name.trim();
    if original.is_empty() {
        return original.to_owned();
    }

    let mut normalized = strip_junk_bracket_fragments(original);
    loop {
        let before = normalized.clone();
        normalized = normalized
            .trim_end_matches(is_release_separator)
            .trim()
            .to_owned();
        strip_release_suffix(&mut normalized);
        strip_trailing_version(&mut normalized);
        if normalized == before {
            break;
        }
    }

    let collapsed = collapse_separators(&normalized);
    if collapsed.is_empty() {
        original.to_owned()
    } else {
        collapsed
    }
}

/// Drop `[...]` / `(...)` fragments whose contents carry a junk marker.
fn strip_junk_bracket_fragments(name: &str) -> String {
    let mut result = String::with_capacity(name.len());
    let mut rest = name;

    while let Some(open_index) = rest.find(['[', '(']) {
        let open = rest.as_bytes()[open_index] as char;
        let close = if open == '[' { ']' } else { ')' };
        let after_open = &rest[open_index + 1..];
        // Nested brackets are not fragments; leave them for the title.
        let Some(close_offset) = after_open.find(close) else {
            break;
        };
        let contents = &after_open[..close_offset];
        let is_nested = contents.contains(open);

        result.push_str(&rest[..open_index]);
        if is_nested || !is_junk_bracket(contents) {
            result.push(open);
            result.push_str(contents);
            result.push(close);
        } else {
            result.push(' ');
        }
        rest = &after_open[close_offset + close.len_utf8()..];
    }

    result.push_str(rest);
    result
}

fn is_junk_bracket(contents: &str) -> bool {
    let lower = contents.to_ascii_lowercase();
    if has_version_marker(&lower) {
        return true;
    }
    JUNK_BRACKET_WORDS
        .iter()
        .any(|word| contains_word(&lower, word))
}

/// True when `lower` contains a `v1`/`version 1`/`build 1` style marker.
fn has_version_marker(lower: &str) -> bool {
    if let Some(rest) = word_after(lower, "build") {
        if rest
            .trim_start()
            .starts_with(|ch: char| ch.is_ascii_digit())
        {
            return true;
        }
    }
    for (index, _) in lower.match_indices('v') {
        if !is_word_start(lower, index) {
            continue;
        }
        let rest = &lower[index + 1..];
        let rest = rest.strip_prefix("ersion").unwrap_or(rest);
        if rest
            .trim_start()
            .starts_with(|ch: char| ch.is_ascii_digit())
        {
            return true;
        }
    }
    false
}

/// Remove one trailing release suffix, honouring the ambiguous-word rule.
fn strip_release_suffix(normalized: &mut String) {
    let lower = normalized.to_ascii_lowercase();
    for suffix in GAME_RELEASE_SUFFIXES {
        if !lower.ends_with(suffix) || normalized.len() == suffix.len() {
            continue;
        }
        let prefix = &normalized[..normalized.len() - suffix.len()];
        let has_boundary = if AMBIGUOUS_GAME_RELEASE_SUFFIXES.contains(suffix) {
            prefix
                .trim_end_matches(char::is_whitespace)
                .chars()
                .next_back()
                .is_some_and(is_strong_release_separator)
        } else {
            prefix.chars().next_back().is_some_and(is_release_separator)
        };
        if has_boundary {
            *normalized = prefix
                .trim_end_matches(is_release_separator)
                .trim()
                .to_owned();
            return;
        }
    }
}

/// Remove a trailing `v1.2.3`, `version 1.2.3`, or `build 12345` stamp.
fn strip_trailing_version(normalized: &mut String) {
    let trimmed = normalized.trim_end();

    // "Example Game v1.2.3-hotfix2" — the stamp can contain separators, so it
    // is matched from its `v` to the end rather than as a trailing token.
    for (index, _) in trimmed.match_indices(['v', 'V']) {
        let preceded_by_separator = trimmed[..index]
            .chars()
            .next_back()
            .is_some_and(is_release_separator);
        if !preceded_by_separator || !is_version_token(&trimmed[index..]) {
            continue;
        }
        *normalized = trimmed[..index]
            .trim_end_matches(is_release_separator)
            .to_owned();
        return;
    }

    // "Example Game - Build 12345" / "Example Game version 1.2"
    let Some((head, last)) = split_last_token(trimmed) else {
        return;
    };
    if !is_numeric_token(last) {
        return;
    }
    if let Some((prefix, keyword)) = split_last_token(head) {
        if keyword.eq_ignore_ascii_case("build") || keyword.eq_ignore_ascii_case("version") {
            *normalized = prefix.to_owned();
        }
    }
}

/// Split off the last separator-delimited token, with the head already trimmed
/// of trailing separators. Returns `None` when there is no separator, so a name
/// that is only a version stamp is left alone.
fn split_last_token(value: &str) -> Option<(&str, &str)> {
    let trimmed = value.trim_end();
    let split_at = trimmed.rfind(is_release_separator)?;
    let token = &trimmed[split_at + trimmed[split_at..].chars().next()?.len_utf8()..];
    if token.is_empty() {
        return None;
    }
    let head = trimmed[..split_at].trim_end_matches(is_release_separator);
    if head.is_empty() {
        return None;
    }
    Some((head, token))
}

/// `v1`, `v1.2.3`, `v1.2.3-hotfix2` — a `v` prefix is required, so a bare
/// number stays part of the title ("Sample-Game 2").
fn is_version_token(token: &str) -> bool {
    let lower = token.to_ascii_lowercase();
    let Some(rest) = lower.strip_prefix('v') else {
        return false;
    };
    let rest = rest.strip_prefix("ersion").unwrap_or(rest);
    let mut chars = rest.chars();
    if !chars.next().is_some_and(|ch| ch.is_ascii_digit()) {
        return false;
    }

    // Digits and dots, then at most one trailing qualifier ("-hotfix2").
    let mut seen_tail = false;
    for ch in chars {
        if ch.is_ascii_digit() || ch == '.' {
            continue;
        }
        if ch.is_ascii_alphanumeric() || (!seen_tail && matches!(ch, '-' | '_')) {
            seen_tail = true;
            continue;
        }
        return false;
    }
    true
}

fn is_numeric_token(token: &str) -> bool {
    !token.is_empty()
        && token.chars().all(|ch| ch.is_ascii_digit() || ch == '.')
        && token.chars().any(|ch| ch.is_ascii_digit())
}

/// Collapse pipe/underscore runs and whitespace, then trim edge separators.
fn collapse_separators(value: &str) -> String {
    let spaced: String = value
        .chars()
        .map(|ch| if matches!(ch, '|' | '_') { ' ' } else { ch })
        .collect();
    let collapsed = spaced.split_whitespace().collect::<Vec<_>>().join(" ");
    collapsed.trim_matches(is_release_separator).to_owned()
}

fn contains_word(haystack_lower: &str, needle: &str) -> bool {
    haystack_lower.match_indices(needle).any(|(index, _)| {
        is_word_start(haystack_lower, index) && is_word_end(haystack_lower, index + needle.len())
    })
}

fn word_after<'a>(haystack_lower: &'a str, needle: &str) -> Option<&'a str> {
    haystack_lower
        .match_indices(needle)
        .find(|(index, _)| is_word_start(haystack_lower, *index))
        .map(|(index, _)| &haystack_lower[index + needle.len()..])
}

fn is_word_start(value: &str, index: usize) -> bool {
    value[..index]
        .chars()
        .next_back()
        .is_none_or(|ch| !ch.is_alphanumeric())
}

fn is_word_end(value: &str, index: usize) -> bool {
    value[index..]
        .chars()
        .next()
        .is_none_or(|ch| !ch.is_alphanumeric())
}

pub(crate) fn is_release_separator(ch: char) -> bool {
    ch.is_whitespace() || matches!(ch, '-' | '–' | '—' | '_' | '|' | ':')
}

fn is_strong_release_separator(ch: char) -> bool {
    matches!(ch, '-' | '–' | '—' | '_' | '|' | ':')
}

#[cfg(test)]
mod tests;
