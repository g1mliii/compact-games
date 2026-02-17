use std::path::Path;

use super::super::algorithm::CompressionAlgorithm;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum CompressionBucket {
    Incompressible,
    LikelyCompressible,
    ModeratelyCompressible,
    LikelyUncompressed,
    Unknown,
}

pub(super) const INCOMPRESSIBLE_RATIO_NUM: u64 = 5;
pub(super) const INCOMPRESSIBLE_RATIO_DEN: u64 = 1000; // 0.5%
pub(super) const UNKNOWN_RATIO_NUM: u64 = 80;
pub(super) const UNKNOWN_RATIO_DEN: u64 = 1000; // 8%
pub(super) const COMPRESSIBLE_RATIO_NUM: u64 = 350;
pub(super) const COMPRESSIBLE_RATIO_DEN: u64 = 1000; // 35%
pub(super) const MODERATELY_COMPRESSIBLE_RATIO_NUM: u64 = 180;
pub(super) const MODERATELY_COMPRESSIBLE_RATIO_DEN: u64 = 1000; // 18%
pub(super) const LIKELY_UNCOMPRESSED_RATIO_NUM: u64 = 350;
pub(super) const LIKELY_UNCOMPRESSED_RATIO_DEN: u64 = 1000; // 35%

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
            // Unity assets (already compressed)
            | "unity3d"
            | "resource"
            | "ress"
            // Source Engine textures (DXT compressed)
            | "vtf"
    ) {
        return CompressionBucket::Incompressible;
    }

    // ModeratelyCompressible: Binary game assets (18% compression)
    if matches!(
        ext,
        // Unreal Engine
        "uasset" | "umap" | "uexp" | "ushaderbytecode"
        // Unity Engine
        | "prefab" | "asset" | "mat" | "controller"
        // Source Engine
        | "bsp" | "nav" | "mdl"
        // Bethesda (Creation Engine)
        | "esm" | "esp" | "nif"
        // CryEngine
        | "cgf" | "cga" | "chr"
        // Generic game assets
        | "mesh" | "anim" | "skeleton" | "material"
        // Scene/level files
        | "scene" | "level" | "map"
    ) {
        return CompressionBucket::ModeratelyCompressible;
    }

    // LikelyUncompressed: Text-based or uncompressed archives (35% compression)
    if matches!(
        ext,
        // Unreal Engine bulk data
        "ubulk"
        // Source Engine archives
        | "vpk"
        // Bethesda archives
        | "bsa" | "ba2"
        // Godot (text-based)
        | "tscn" | "tres" | "import"
        // 3D model text formats
        | "obj" | "mtl" | "gltf"
        // Material definitions (text)
        | "vmt"
    ) {
        return CompressionBucket::LikelyUncompressed;
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
        CompressionBucket::ModeratelyCompressible => (
            MODERATELY_COMPRESSIBLE_RATIO_NUM,
            MODERATELY_COMPRESSIBLE_RATIO_DEN,
        ),
        CompressionBucket::LikelyUncompressed => {
            (LIKELY_UNCOMPRESSED_RATIO_NUM, LIKELY_UNCOMPRESSED_RATIO_DEN)
        }
        CompressionBucket::Unknown => (UNKNOWN_RATIO_NUM, UNKNOWN_RATIO_DEN),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bucket_for(path: &str) -> CompressionBucket {
        compression_bucket(Path::new(path))
    }

    #[test]
    fn classifies_unreal_binary_assets_as_moderately_compressible() {
        assert_eq!(
            bucket_for("C:\\Games\\Deadlock\\content.uasset"),
            CompressionBucket::ModeratelyCompressible
        );
        assert_eq!(
            bucket_for("C:\\Games\\Deadlock\\map.umap"),
            CompressionBucket::ModeratelyCompressible
        );
    }

    #[test]
    fn classifies_uncompressed_archives_as_likely_uncompressed() {
        assert_eq!(
            bucket_for("C:\\Games\\Source\\pak01.vpk"),
            CompressionBucket::LikelyUncompressed
        );
        assert_eq!(
            bucket_for("C:\\Games\\Bethesda\\archive.ba2"),
            CompressionBucket::LikelyUncompressed
        );
    }

    #[test]
    fn keeps_known_already_compressed_formats_in_incompressible_bucket() {
        assert_eq!(
            bucket_for("C:\\Games\\Unity\\sharedassets.resource"),
            CompressionBucket::Incompressible
        );
        assert_eq!(
            bucket_for("C:\\Games\\Source\\texture.vtf"),
            CompressionBucket::Incompressible
        );
    }

    #[test]
    fn classifies_text_assets_as_likely_compressible() {
        assert_eq!(
            bucket_for("C:\\Games\\Godot\\project.tscn"),
            CompressionBucket::LikelyUncompressed
        );
        assert_eq!(
            bucket_for("C:\\Games\\Shaders\\shader.hlsl"),
            CompressionBucket::LikelyCompressible
        );
    }

    #[test]
    fn unknown_or_extensionless_files_fall_back_to_unknown_bucket() {
        assert_eq!(
            bucket_for("C:\\Games\\Mystery\\blob.customext"),
            CompressionBucket::Unknown
        );
        assert_eq!(
            bucket_for("C:\\Games\\Mystery\\README"),
            CompressionBucket::Unknown
        );
    }

    #[test]
    fn ratio_parts_match_bucket_defaults() {
        assert_eq!(
            compression_ratio_parts(Path::new("file.uasset")),
            (
                MODERATELY_COMPRESSIBLE_RATIO_NUM,
                MODERATELY_COMPRESSIBLE_RATIO_DEN
            )
        );
        assert_eq!(
            compression_ratio_parts(Path::new("file.vpk")),
            (LIKELY_UNCOMPRESSED_RATIO_NUM, LIKELY_UNCOMPRESSED_RATIO_DEN)
        );
    }
}
