use std::path::Path;

use super::super::algorithm::CompressionAlgorithm;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum CompressionBucket {
    Incompressible,
    LikelyCompressible,
    Unknown,
}

pub(super) const INCOMPRESSIBLE_RATIO_NUM: u64 = 5;
pub(super) const INCOMPRESSIBLE_RATIO_DEN: u64 = 1000; // 0.5%
pub(super) const UNKNOWN_RATIO_NUM: u64 = 80;
pub(super) const UNKNOWN_RATIO_DEN: u64 = 1000; // 8%
pub(super) const COMPRESSIBLE_RATIO_NUM: u64 = 350;
pub(super) const COMPRESSIBLE_RATIO_DEN: u64 = 1000; // 35%

pub(super) fn algorithm_scale_num(algorithm: CompressionAlgorithm) -> u64 {
    match algorithm {
        CompressionAlgorithm::Xpress4K => 85,
        CompressionAlgorithm::Xpress8K => 100,
        CompressionAlgorithm::Xpress16K => 110,
        CompressionAlgorithm::Lzx => 125,
    }
}

pub(super) fn compression_bucket(path: &Path) -> CompressionBucket {
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_ascii_lowercase());
    let Some(ext) = ext.as_deref() else {
        return CompressionBucket::Unknown;
    };

    if matches!(
        ext,
        "pak"
            | "ucas"
            | "utoc"
            | "zip"
            | "7z"
            | "rar"
            | "gz"
            | "bz2"
            | "xz"
            | "zst"
            | "lz4"
            | "mp4"
            | "mkv"
            | "avi"
            | "webm"
            | "bik"
            | "bk2"
            | "png"
            | "jpg"
            | "jpeg"
            | "webp"
            | "dds"
            | "ktx"
            | "ktx2"
            | "ogg"
            | "mp3"
            | "opus"
            | "flac"
            | "wav"
            | "wem"
            | "dll"
            | "exe"
    ) {
        return CompressionBucket::Incompressible;
    }

    if matches!(
        ext,
        "txt"
            | "json"
            | "xml"
            | "ini"
            | "cfg"
            | "csv"
            | "log"
            | "hlsl"
            | "glsl"
            | "shader"
            | "lua"
            | "js"
            | "ts"
    ) {
        return CompressionBucket::LikelyCompressible;
    }

    CompressionBucket::Unknown
}

pub(super) fn compression_ratio_parts(path: &Path) -> (u64, u64) {
    match compression_bucket(path) {
        CompressionBucket::Incompressible => (INCOMPRESSIBLE_RATIO_NUM, INCOMPRESSIBLE_RATIO_DEN),
        CompressionBucket::LikelyCompressible => (COMPRESSIBLE_RATIO_NUM, COMPRESSIBLE_RATIO_DEN),
        CompressionBucket::Unknown => (UNKNOWN_RATIO_NUM, UNKNOWN_RATIO_DEN),
    }
}
