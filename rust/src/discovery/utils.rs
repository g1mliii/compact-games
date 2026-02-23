mod dedupe;
mod game_info;
mod scanning;
mod stats;

pub use dedupe::merge_games;
pub use game_info::{
    build_game_info, build_game_info_with_mode, build_game_info_with_mode_and_stats_path,
};
pub(crate) use game_info::is_non_game_exe;
pub use scanning::{
    build_games_from_candidates, scan_all_platforms, scan_all_platforms_with_mode,
    scan_custom_paths, scan_custom_paths_with_mode, scan_game_subdirs,
};
pub use stats::{dir_stats, dir_stats_quick, DirStats};
