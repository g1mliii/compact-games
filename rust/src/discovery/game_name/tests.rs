use super::normalize_game_name;

#[test]
fn strips_site_and_scene_suffixes_case_insensitively() {
    assert_eq!(
        normalize_game_name("Cyberpunk 2077 - SteamGG.NET"),
        "Cyberpunk 2077"
    );
    assert_eq!(
        normalize_game_name("Sample Adventure - steamgg.net"),
        "Sample Adventure"
    );
    assert_eq!(
        normalize_game_name("Example Quest - FitGirl Repack"),
        "Example Quest"
    );
    assert_eq!(
        normalize_game_name("Demo Racing Game SteamRIP"),
        "Demo Racing Game"
    );
    assert_eq!(
        normalize_game_name("Fictional Strategy Game-TENOKE"),
        "Fictional Strategy Game"
    );
    assert_eq!(normalize_game_name("Example - DODI Repack"), "Example");
    assert_eq!(normalize_game_name("Example-EMPRESS"), "Example");
    assert_eq!(
        normalize_game_name("Sample Adventure - RUNE"),
        "Sample Adventure"
    );
}

#[test]
fn removes_trailing_versions_and_junk_metadata() {
    assert_eq!(normalize_game_name("Example Game v1.2.3"), "Example Game");
    assert_eq!(
        normalize_game_name("Example Game v1.2.3-hotfix2"),
        "Example Game"
    );
    assert_eq!(
        normalize_game_name("Example Game - Build 12345"),
        "Example Game"
    );
    assert_eq!(
        normalize_game_name("Example Game version 1.2"),
        "Example Game"
    );
    assert_eq!(
        normalize_game_name("Example Game - Early Access"),
        "Example Game"
    );
    assert_eq!(normalize_game_name("Example Game - GOG"), "Example Game");
    assert_eq!(
        normalize_game_name("Example Game [v1.2.3 MULTi7]"),
        "Example Game"
    );
    assert_eq!(
        normalize_game_name("Example Game (English FitGirl Repack)"),
        "Example Game"
    );
    assert_eq!(
        normalize_game_name("Example Game [Build 998] - CODEX"),
        "Example Game"
    );
}

#[test]
fn preserves_meaningful_title_text_and_punctuation() {
    assert_eq!(normalize_game_name("Sample45"), "Sample45");
    assert_eq!(normalize_game_name("Sample-Game 2"), "Sample-Game 2");
    assert_eq!(
        normalize_game_name("Example Adventure (2016)"),
        "Example Adventure (2016)"
    );
    assert_eq!(normalize_game_name("CODEX"), "CODEX");
    assert_eq!(normalize_game_name("The Empress"), "The Empress");
    assert_eq!(normalize_game_name("Shadow Rune"), "Shadow Rune");
    assert_eq!(normalize_game_name("Central Plaza"), "Central Plaza");
    // A bare version stamp has no title to keep, so it survives untouched.
    assert_eq!(normalize_game_name("v1.2.3"), "v1.2.3");
}

#[test]
fn collapses_noisy_separators_and_whitespace() {
    assert_eq!(
        normalize_game_name("  Example   Game  |  - SteamRIP  "),
        "Example Game"
    );
    assert_eq!(normalize_game_name("Example_Game"), "Example Game");
    assert_eq!(normalize_game_name(""), "");
    assert_eq!(normalize_game_name("   "), "");
}
