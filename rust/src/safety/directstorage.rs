//! DirectStorage detection for game directories.
//!
//! Games using DirectStorage must NOT be compressed, as WOF
//! compression interferes with DirectStorage's GPU-direct I/O path.

use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

use walkdir::WalkDir;

use super::known_games::{is_known_directstorage_game, learn_directstorage_game};

const DIRECTSTORAGE_DLLS: &[&str] = &["dstorage.dll", "dstoragecore.dll"];
const DIRECTSTORAGE_MANIFESTS: &[&str] = &["directstorage.json", "dstorage.json"];
const PE_WHOLE_FILE_SCAN_MAX_BYTES: u64 = 64 * 1024 * 1024;
const PE_HEADER_SCAN_MAX_BYTES: u64 = 1024 * 1024;
const MAX_PE_IMPORT_DESCRIPTORS: usize = 2048;
const MAX_IMPORT_DLL_NAME_BYTES: usize = 260;

pub fn is_directstorage_game(game_path: &Path) -> bool {
    if !game_path.is_dir() {
        return false;
    }

    if is_known_directstorage_game(game_path) {
        log::info!(
            "DirectStorage detected via known-games database: {}",
            game_path.display()
        );
        return true;
    }

    for entry in WalkDir::new(game_path)
        .max_depth(3)
        .into_iter()
        .filter_map(|e| e.ok())
    {
        if let Some(name) = entry.file_name().to_str() {
            if DIRECTSTORAGE_DLLS
                .iter()
                .any(|dll| name.eq_ignore_ascii_case(dll))
            {
                log::info!(
                    "DirectStorage detected: {} in {}",
                    name,
                    game_path.display()
                );

                learn_directstorage_game(game_path);
                return true;
            }
            if DIRECTSTORAGE_MANIFESTS
                .iter()
                .any(|m| name.eq_ignore_ascii_case(m))
            {
                log::info!(
                    "DirectStorage manifest detected: {} in {}",
                    name,
                    game_path.display()
                );

                learn_directstorage_game(game_path);
                return true;
            }

            if is_pe_candidate(entry.path()) && pe_mentions_directstorage(entry.path()) {
                log::info!(
                    "DirectStorage PE marker detected: {} in {}",
                    entry.path().display(),
                    game_path.display()
                );

                learn_directstorage_game(game_path);
                return true;
            }
        }
    }

    false
}

fn is_pe_candidate(path: &Path) -> bool {
    path.extension().is_some_and(|extension| {
        extension.eq_ignore_ascii_case("exe") || extension.eq_ignore_ascii_case("dll")
    })
}

fn pe_mentions_directstorage(path: &Path) -> bool {
    let Ok(metadata) = path.metadata() else {
        return false;
    };
    if metadata.len() > PE_WHOLE_FILE_SCAN_MAX_BYTES {
        return pe_imports_directstorage_from_large_file(path, metadata.len());
    }

    let Ok(bytes) = std::fs::read(path) else {
        return false;
    };
    if !is_pe_file(&bytes) {
        return false;
    }

    pe_imports_directstorage(&bytes)
}

fn is_pe_file(bytes: &[u8]) -> bool {
    parse_pe(bytes).is_some()
}

#[derive(Clone, Copy)]
struct PeSection {
    virtual_address: u32,
    virtual_size: u32,
    raw_data_ptr: u32,
    raw_data_size: u32,
}

#[derive(Clone)]
struct PeLayout {
    sections: Vec<PeSection>,
    file_len: u64,
    image_base: u64,
    import_table_rva: u32,
    import_table_size: u32,
    delay_import_table_rva: u32,
    delay_import_table_size: u32,
}

struct PeView<'a> {
    bytes: &'a [u8],
    layout: PeLayout,
}

fn parse_pe(bytes: &[u8]) -> Option<PeView<'_>> {
    let layout = parse_pe_layout(bytes, bytes.len() as u64)?;
    Some(PeView { bytes, layout })
}

fn parse_pe_layout(bytes: &[u8], file_len: u64) -> Option<PeLayout> {
    if bytes.len() < 0x40 || bytes.get(0..2)? != b"MZ" {
        return None;
    }

    let pe_offset = read_u32(bytes, 0x3c)? as usize;
    if pe_offset.checked_add(24)? > bytes.len() || bytes.get(pe_offset..pe_offset + 4)? != b"PE\0\0"
    {
        return None;
    }

    let coff_offset = pe_offset + 4;
    let section_count = read_u16(bytes, coff_offset + 2)? as usize;
    let optional_header_size = read_u16(bytes, coff_offset + 16)? as usize;
    let optional_offset = coff_offset + 20;
    let optional_end = optional_offset.checked_add(optional_header_size)?;
    if optional_end > bytes.len() {
        return None;
    }

    let magic = read_u16(bytes, optional_offset)?;
    let (image_base, data_directories_offset) = match magic {
        0x10b => (
            read_u32(bytes, optional_offset + 28)? as u64,
            optional_offset + 96,
        ),
        0x20b => (
            read_u64(bytes, optional_offset + 24)?,
            optional_offset + 112,
        ),
        _ => return None,
    };
    if data_directories_offset.checked_add(14 * 8)? > optional_end {
        return None;
    }

    let import_table_rva = read_u32(bytes, data_directories_offset + 8)?;
    let import_table_size = read_u32(bytes, data_directories_offset + 12)?;
    let delay_import_table_rva = read_u32(bytes, data_directories_offset + 13 * 8)?;
    let delay_import_table_size = read_u32(bytes, data_directories_offset + 13 * 8 + 4)?;

    let section_table_offset = optional_end;
    let section_table_size = section_count.checked_mul(40)?;
    if section_table_offset.checked_add(section_table_size)? > bytes.len() {
        return None;
    }

    let mut sections = Vec::with_capacity(section_count);
    for index in 0..section_count {
        let offset = section_table_offset + index * 40;
        sections.push(PeSection {
            virtual_size: read_u32(bytes, offset + 8)?,
            virtual_address: read_u32(bytes, offset + 12)?,
            raw_data_size: read_u32(bytes, offset + 16)?,
            raw_data_ptr: read_u32(bytes, offset + 20)?,
        });
    }

    Some(PeLayout {
        sections,
        file_len,
        image_base,
        import_table_rva,
        import_table_size,
        delay_import_table_rva,
        delay_import_table_size,
    })
}

fn pe_imports_directstorage(bytes: &[u8]) -> bool {
    let Some(pe) = parse_pe(bytes) else {
        return false;
    };

    imports_directory_mentions_directstorage(&pe)
        || delay_imports_directory_mentions_directstorage(&pe)
}

fn imports_directory_mentions_directstorage(pe: &PeView<'_>) -> bool {
    let Some(import_offset) = pe.rva_to_offset(pe.layout.import_table_rva) else {
        return false;
    };
    if pe.layout.import_table_size == 0 {
        return false;
    }

    for index in 0..MAX_PE_IMPORT_DESCRIPTORS {
        let descriptor_offset = import_offset + index * 20;
        let Some(descriptor) = pe.bytes.get(descriptor_offset..descriptor_offset + 20) else {
            return false;
        };
        if descriptor.iter().all(|byte| *byte == 0) {
            return false;
        }

        let Some(name_rva) = read_u32(pe.bytes, descriptor_offset + 12) else {
            return false;
        };
        if dll_name_is_directstorage(pe, name_rva) {
            return true;
        }
    }

    false
}

fn delay_imports_directory_mentions_directstorage(pe: &PeView<'_>) -> bool {
    let Some(delay_offset) = pe.rva_to_offset(pe.layout.delay_import_table_rva) else {
        return false;
    };
    if pe.layout.delay_import_table_size == 0 {
        return false;
    }

    for index in 0..MAX_PE_IMPORT_DESCRIPTORS {
        let descriptor_offset = delay_offset + index * 32;
        let Some(descriptor) = pe.bytes.get(descriptor_offset..descriptor_offset + 32) else {
            return false;
        };
        if descriptor.iter().all(|byte| *byte == 0) {
            return false;
        }

        let Some(attributes) = read_u32(pe.bytes, descriptor_offset) else {
            return false;
        };
        let Some(name_address) = read_u32(pe.bytes, descriptor_offset + 4) else {
            return false;
        };
        let name_rva = if attributes & 1 == 1 {
            name_address
        } else {
            (name_address as u64)
                .checked_sub(pe.layout.image_base)
                .and_then(|rva| u32::try_from(rva).ok())
                .unwrap_or(name_address)
        };

        if dll_name_is_directstorage(pe, name_rva) {
            return true;
        }
    }

    false
}

fn dll_name_is_directstorage(pe: &PeView<'_>, name_rva: u32) -> bool {
    let Some(name_offset) = pe.rva_to_offset(name_rva) else {
        return false;
    };
    let Some(name) = read_ascii_c_string(pe.bytes, name_offset, MAX_IMPORT_DLL_NAME_BYTES) else {
        return false;
    };
    DIRECTSTORAGE_DLLS
        .iter()
        .any(|dll| name.eq_ignore_ascii_case(dll))
}

fn pe_imports_directstorage_from_large_file(path: &Path, file_len: u64) -> bool {
    let Ok(mut file) = File::open(path) else {
        return false;
    };
    let header_len = file_len.min(PE_HEADER_SCAN_MAX_BYTES) as usize;
    let Some(header) = read_file_at(&mut file, 0, header_len) else {
        return false;
    };
    let Some(layout) = parse_pe_layout(&header, file_len) else {
        return false;
    };

    imports_directory_mentions_directstorage_file(&mut file, &layout)
        || delay_imports_directory_mentions_directstorage_file(&mut file, &layout)
}

fn imports_directory_mentions_directstorage_file(file: &mut File, layout: &PeLayout) -> bool {
    let Some(import_offset) = layout.rva_to_offset(layout.import_table_rva) else {
        return false;
    };
    if layout.import_table_size == 0 {
        return false;
    }

    for index in 0..MAX_PE_IMPORT_DESCRIPTORS {
        let descriptor_offset = import_offset + index * 20;
        let Some(descriptor) = read_file_at(file, descriptor_offset, 20) else {
            return false;
        };
        if descriptor.iter().all(|byte| *byte == 0) {
            return false;
        }

        let Some(name_rva) = read_u32(&descriptor, 12) else {
            return false;
        };
        if dll_name_is_directstorage_file(file, layout, name_rva) {
            return true;
        }
    }

    false
}

fn delay_imports_directory_mentions_directstorage_file(file: &mut File, layout: &PeLayout) -> bool {
    let Some(delay_offset) = layout.rva_to_offset(layout.delay_import_table_rva) else {
        return false;
    };
    if layout.delay_import_table_size == 0 {
        return false;
    }

    for index in 0..MAX_PE_IMPORT_DESCRIPTORS {
        let descriptor_offset = delay_offset + index * 32;
        let Some(descriptor) = read_file_at(file, descriptor_offset, 32) else {
            return false;
        };
        if descriptor.iter().all(|byte| *byte == 0) {
            return false;
        }

        let Some(attributes) = read_u32(&descriptor, 0) else {
            return false;
        };
        let Some(name_address) = read_u32(&descriptor, 4) else {
            return false;
        };
        let name_rva = if attributes & 1 == 1 {
            name_address
        } else {
            (name_address as u64)
                .checked_sub(layout.image_base)
                .and_then(|rva| u32::try_from(rva).ok())
                .unwrap_or(name_address)
        };

        if dll_name_is_directstorage_file(file, layout, name_rva) {
            return true;
        }
    }

    false
}

fn dll_name_is_directstorage_file(file: &mut File, layout: &PeLayout, name_rva: u32) -> bool {
    let Some(name_offset) = layout.rva_to_offset(name_rva) else {
        return false;
    };
    let Some(name) = read_ascii_c_string_file(file, name_offset, MAX_IMPORT_DLL_NAME_BYTES) else {
        return false;
    };
    DIRECTSTORAGE_DLLS
        .iter()
        .any(|dll| name.eq_ignore_ascii_case(dll))
}

impl PeView<'_> {
    fn rva_to_offset(&self, rva: u32) -> Option<usize> {
        self.layout.rva_to_offset(rva)
    }
}

impl PeLayout {
    fn rva_to_offset(&self, rva: u32) -> Option<usize> {
        if rva == 0 {
            return None;
        }

        for section in &self.sections {
            let section_size = section.virtual_size.max(section.raw_data_size);
            let section_end = section.virtual_address.checked_add(section_size)?;
            if rva < section.virtual_address || rva >= section_end {
                continue;
            }

            let offset = section
                .raw_data_ptr
                .checked_add(rva.checked_sub(section.virtual_address)?)?;
            let offset = usize::try_from(offset).ok()?;
            if (offset as u64) < self.file_len {
                return Some(offset);
            }
        }

        None
    }
}

fn read_ascii_c_string(bytes: &[u8], offset: usize, max_len: usize) -> Option<String> {
    let end = offset.checked_add(max_len)?.min(bytes.len());
    let slice = bytes.get(offset..end)?;
    let nul = slice.iter().position(|byte| *byte == 0)?;
    std::str::from_utf8(&slice[..nul]).ok().map(str::to_owned)
}

fn read_ascii_c_string_file(file: &mut File, offset: usize, max_len: usize) -> Option<String> {
    let bytes = read_file_at(file, offset, max_len)?;
    let nul = bytes.iter().position(|byte| *byte == 0)?;
    std::str::from_utf8(&bytes[..nul]).ok().map(str::to_owned)
}

fn read_file_at(file: &mut File, offset: usize, len: usize) -> Option<Vec<u8>> {
    file.seek(SeekFrom::Start(offset as u64)).ok()?;
    let mut bytes = vec![0; len];
    let read = file.read(&mut bytes).ok()?;
    if read == 0 {
        return None;
    }
    bytes.truncate(read);
    Some(bytes)
}

fn read_u16(bytes: &[u8], offset: usize) -> Option<u16> {
    let end = offset.checked_add(2)?;
    Some(u16::from_le_bytes(bytes.get(offset..end)?.try_into().ok()?))
}

fn read_u32(bytes: &[u8], offset: usize) -> Option<u32> {
    let end = offset.checked_add(4)?;
    Some(u32::from_le_bytes(bytes.get(offset..end)?.try_into().ok()?))
}

fn read_u64(bytes: &[u8], offset: usize) -> Option<u64> {
    let end = offset.checked_add(8)?;
    Some(u64::from_le_bytes(bytes.get(offset..end)?.try_into().ok()?))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn empty_dir_is_not_directstorage() {
        let dir = TempDir::new().unwrap();
        assert!(!is_directstorage_game(dir.path()));
    }

    #[test]
    fn dir_with_dstorage_dll_is_detected() {
        let dir = TempDir::new().unwrap();
        std::fs::write(dir.path().join("dstorage.dll"), b"fake").unwrap();
        assert!(is_directstorage_game(dir.path()));
    }

    #[test]
    fn detection_is_case_insensitive() {
        let dir = TempDir::new().unwrap();
        std::fs::write(dir.path().join("DStorage.DLL"), b"fake").unwrap();
        assert!(is_directstorage_game(dir.path()));
    }

    #[test]
    fn nonexistent_path_returns_false() {
        assert!(!is_directstorage_game(Path::new(
            r"C:\__nonexistent_compact_games_test__"
        )));
    }

    #[test]
    fn beyond_max_depth_not_detected() {
        let dir = TempDir::new().unwrap();

        let deep = dir.path().join("a").join("b").join("c");
        std::fs::create_dir_all(&deep).unwrap();
        std::fs::write(deep.join("dstorage.dll"), b"fake").unwrap();
        assert!(!is_directstorage_game(dir.path()));
    }

    #[test]
    fn at_max_depth_is_detected() {
        let dir = TempDir::new().unwrap();

        let deep = dir.path().join("a").join("b");
        std::fs::create_dir_all(&deep).unwrap();
        std::fs::write(deep.join("dstorage.dll"), b"fake").unwrap();
        assert!(is_directstorage_game(dir.path()));
    }

    #[test]
    fn manifest_detection() {
        let dir = TempDir::new().unwrap();
        std::fs::write(dir.path().join("directstorage.json"), b"{}").unwrap();
        assert!(is_directstorage_game(dir.path()));
    }

    #[test]
    fn dstorage_json_detection() {
        let dir = TempDir::new().unwrap();
        std::fs::write(dir.path().join("DStorage.JSON"), b"{}").unwrap();
        assert!(is_directstorage_game(dir.path()));
    }

    #[test]
    fn dstoragecore_dll_detection() {
        let dir = TempDir::new().unwrap();
        std::fs::write(dir.path().join("DStorageCore.dll"), b"fake").unwrap();
        assert!(is_directstorage_game(dir.path()));
    }

    #[test]
    fn directstorage_pe_import_detection() {
        let dir = TempDir::new().unwrap();
        std::fs::write(
            dir.path().join("game.exe"),
            minimal_pe_with_import("DStorage.dll"),
        )
        .unwrap();
        assert!(is_directstorage_game(dir.path()));
    }

    #[test]
    fn directstorage_pe_delay_import_detection() {
        let dir = TempDir::new().unwrap();
        std::fs::write(
            dir.path().join("game.exe"),
            minimal_pe_with_delay_import("dstoragecore.dll"),
        )
        .unwrap();
        assert!(is_directstorage_game(dir.path()));
    }

    #[test]
    fn large_pe_import_detection_reads_imports_without_whole_file_scan() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("large-game.exe");
        let mut file = std::fs::OpenOptions::new()
            .create(true)
            .truncate(true)
            .write(true)
            .open(&path)
            .unwrap();
        std::io::Write::write_all(&mut file, &minimal_pe_with_import("dstorage.dll")).unwrap();
        file.set_len(PE_WHOLE_FILE_SCAN_MAX_BYTES + 1).unwrap();
        drop(file);

        assert!(is_directstorage_game(dir.path()));
    }

    #[test]
    fn generic_storage_strings_do_not_trigger_pe_detection() {
        let mut pe = minimal_pe();
        write_bytes(
            &mut pe,
            0x500,
            b"ConnectedStorage\0StorageBuffer\0SaveStorage\0",
        );
        assert!(!pe_mentions_directstorage_bytes_for_test(&pe));
    }

    #[test]
    fn filesystem_detection_learns_game() {
        use super::super::known_games::is_known_directstorage_game;
        use std::time::{SystemTime, UNIX_EPOCH};

        let dir = TempDir::new().unwrap();
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let unique_name = format!("UnknownGame_{}", nanos);
        let game_dir = dir.path().join(&unique_name);
        std::fs::create_dir(&game_dir).unwrap();
        std::fs::write(game_dir.join("dstorage.dll"), b"fake").unwrap();

        assert!(!is_known_directstorage_game(&game_dir));

        assert!(is_directstorage_game(&game_dir));

        assert!(is_known_directstorage_game(&game_dir));

        assert!(is_directstorage_game(&game_dir));
    }

    fn pe_mentions_directstorage_bytes_for_test(bytes: &[u8]) -> bool {
        is_pe_file(bytes) && pe_imports_directstorage(bytes)
    }

    fn minimal_pe_with_import(dll_name: &str) -> Vec<u8> {
        let mut pe = minimal_pe();
        let import_descriptor_rva = 0x1000;
        let dll_name_rva = 0x1040;
        set_data_directory(&mut pe, 1, import_descriptor_rva, 0x28);
        write_u32_le(&mut pe, 0x400 + 12, dll_name_rva);
        write_bytes(&mut pe, 0x440, dll_name.as_bytes());
        pe[0x440 + dll_name.len()] = 0;
        pe
    }

    fn minimal_pe_with_delay_import(dll_name: &str) -> Vec<u8> {
        let mut pe = minimal_pe();
        let delay_descriptor_rva = 0x1080;
        let dll_name_rva = 0x10c0;
        set_data_directory(&mut pe, 13, delay_descriptor_rva, 0x40);
        write_u32_le(&mut pe, 0x480, 1);
        write_u32_le(&mut pe, 0x480 + 4, dll_name_rva);
        write_bytes(&mut pe, 0x4c0, dll_name.as_bytes());
        pe[0x4c0 + dll_name.len()] = 0;
        pe
    }

    fn minimal_pe() -> Vec<u8> {
        let mut pe = vec![0_u8; 0x1400];
        write_bytes(&mut pe, 0, b"MZ");
        write_u32_le(&mut pe, 0x3c, 0x80);
        write_bytes(&mut pe, 0x80, b"PE\0\0");

        let coff = 0x84;
        write_u16_le(&mut pe, coff, 0x8664);
        write_u16_le(&mut pe, coff + 2, 1);
        write_u16_le(&mut pe, coff + 16, 0xf0);

        let optional = 0x98;
        write_u16_le(&mut pe, optional, 0x20b);
        write_u64_le(&mut pe, optional + 24, 0x140000000);

        let section = optional + 0xf0;
        write_bytes(&mut pe, section, b".rdata\0\0");
        write_u32_le(&mut pe, section + 8, 0x1000);
        write_u32_le(&mut pe, section + 12, 0x1000);
        write_u32_le(&mut pe, section + 16, 0x1000);
        write_u32_le(&mut pe, section + 20, 0x400);

        pe
    }

    fn set_data_directory(pe: &mut [u8], index: usize, rva: u32, size: u32) {
        let data_directories = 0x98 + 112;
        let offset = data_directories + index * 8;
        write_u32_le(pe, offset, rva);
        write_u32_le(pe, offset + 4, size);
    }

    fn write_bytes(pe: &mut [u8], offset: usize, value: &[u8]) {
        pe[offset..offset + value.len()].copy_from_slice(value);
    }

    fn write_u16_le(pe: &mut [u8], offset: usize, value: u16) {
        write_bytes(pe, offset, &value.to_le_bytes());
    }

    fn write_u32_le(pe: &mut [u8], offset: usize, value: u32) {
        write_bytes(pe, offset, &value.to_le_bytes());
    }

    fn write_u64_le(pe: &mut [u8], offset: usize, value: u64) {
        write_bytes(pe, offset, &value.to_le_bytes());
    }
}

#[cfg(test)]
mod property_tests {
    use super::*;
    use proptest::prelude::*;
    use tempfile::TempDir;

    proptest! {

        #[test]
        fn detection_is_deterministic(has_ds in proptest::bool::ANY) {
            let dir = TempDir::new().unwrap();
            if has_ds {
                std::fs::write(dir.path().join("dstorage.dll"), b"fake").unwrap();
            }
            let first = is_directstorage_game(dir.path());
            let second = is_directstorage_game(dir.path());
            prop_assert_eq!(first, second);
        }


        #[test]
        fn non_ds_files_no_false_positive(
            prefix in "[a-zA-Z]{1,8}",
        ) {
            let dir = TempDir::new().unwrap();
            let name = format!("{prefix}_other.dll");
            std::fs::write(dir.path().join(&name), b"data").unwrap();
            // Only real DS filenames should match
            let is_ds = name.eq_ignore_ascii_case("dstorage.dll")
                || name.eq_ignore_ascii_case("dstoragecore.dll");
            prop_assert_eq!(is_directstorage_game(dir.path()), is_ds);
        }
    }
}
