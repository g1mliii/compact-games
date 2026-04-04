//! EXE icon extraction for cover-art fallback.
//!
//! Extracts the highest-resolution icon resource from a Windows executable
//! and returns it as PNG bytes. Used as a last-resort cover image when no
//! API artwork is available.

#[cfg(windows)]
pub(crate) mod platform {
    use std::mem;
    use std::path::Path;

    use windows::core::PCWSTR;
    use windows::Win32::Graphics::Gdi::{
        CreateCompatibleDC, DeleteDC, DeleteObject, GetDIBits, SelectObject, BITMAPINFO,
        BITMAPINFOHEADER, BI_RGB, DIB_RGB_COLORS,
    };
    use windows::Win32::UI::Shell::ExtractIconExW;
    use windows::Win32::UI::WindowsAndMessaging::{DestroyIcon, GetIconInfo, HICON, ICONINFO};

    /// Extract the largest icon from an EXE and return it as PNG bytes.
    pub fn extract(exe_path: &str) -> Option<Vec<u8>> {
        let path = Path::new(exe_path);
        if !path.is_file() {
            return None;
        }

        let wide_path: Vec<u16> = exe_path.encode_utf16().chain(std::iter::once(0)).collect();

        // Try to extract a large icon (48x48 or larger).
        let mut large_icon = HICON::default();
        let extracted = unsafe {
            ExtractIconExW(
                PCWSTR(wide_path.as_ptr()),
                0,
                Some(&mut large_icon),
                None,
                1,
            )
        };
        if extracted == 0 || large_icon.is_invalid() {
            return None;
        }

        let result = icon_to_png(large_icon);
        unsafe {
            let _ = DestroyIcon(large_icon);
        }
        result
    }

    fn icon_to_png(icon: HICON) -> Option<Vec<u8>> {
        unsafe {
            let mut icon_info: ICONINFO = mem::zeroed();
            let ok = GetIconInfo(icon, &mut icon_info);
            if ok.is_err() {
                return None;
            }

            // Clean up mask bitmap; we only need the color bitmap.
            if !icon_info.hbmMask.is_invalid() {
                let _ = DeleteObject(icon_info.hbmMask);
            }
            let color_bmp = icon_info.hbmColor;
            if color_bmp.is_invalid() {
                return None;
            }

            let hdc = CreateCompatibleDC(None);
            if hdc.is_invalid() {
                let _ = DeleteObject(color_bmp);
                return None;
            }
            let _old = SelectObject(hdc, color_bmp);

            // Query bitmap dimensions.
            let mut bmi: BITMAPINFO = mem::zeroed();
            bmi.bmiHeader.biSize = mem::size_of::<BITMAPINFOHEADER>() as u32;
            let got = GetDIBits(hdc, color_bmp, 0, 0, None, &mut bmi, DIB_RGB_COLORS);
            if got == 0 {
                let _ = DeleteDC(hdc);
                let _ = DeleteObject(color_bmp);
                return None;
            }

            let width = bmi.bmiHeader.biWidth;
            let height = bmi.bmiHeader.biHeight.abs();
            if width <= 0 || height <= 0 || width > 512 || height > 512 {
                let _ = DeleteDC(hdc);
                let _ = DeleteObject(color_bmp);
                return None;
            }

            // Request 32-bit BGRA, top-down.
            bmi.bmiHeader.biBitCount = 32;
            bmi.bmiHeader.biCompression = BI_RGB.0;
            bmi.bmiHeader.biHeight = -height; // top-down
            bmi.bmiHeader.biSizeImage = 0;

            let row_bytes = (width as usize) * 4;
            let buf_size = row_bytes * (height as usize);
            let mut pixels: Vec<u8> = vec![0u8; buf_size];

            let copied = GetDIBits(
                hdc,
                color_bmp,
                0,
                height as u32,
                Some(pixels.as_mut_ptr().cast()),
                &mut bmi,
                DIB_RGB_COLORS,
            );

            let _ = DeleteDC(hdc);
            let _ = DeleteObject(color_bmp);

            if copied == 0 {
                return None;
            }

            // Convert BGRA to RGBA in place.
            for chunk in pixels.chunks_exact_mut(4) {
                chunk.swap(0, 2); // B <-> R
            }

            Some(encode_png(width as u32, height as u32, &pixels))
        }
    }

    /// Minimal PNG encoder (uncompressed IDAT via zlib stored blocks).
    fn encode_png(width: u32, height: u32, rgba: &[u8]) -> Vec<u8> {
        let mut out = Vec::with_capacity(rgba.len() + 1024);

        // PNG signature
        out.extend_from_slice(&[137, 80, 78, 71, 13, 10, 26, 10]);

        // IHDR
        let mut ihdr = Vec::with_capacity(13);
        ihdr.extend_from_slice(&width.to_be_bytes());
        ihdr.extend_from_slice(&height.to_be_bytes());
        ihdr.push(8); // bit depth
        ihdr.push(6); // color type: RGBA
        ihdr.push(0); // compression
        ihdr.push(0); // filter
        ihdr.push(0); // interlace
        write_chunk(&mut out, b"IHDR", &ihdr);

        // IDAT — build raw deflate (stored blocks) wrapping filtered scanlines.
        let row_len = (width as usize) * 4 + 1; // filter byte + pixel data
        let raw_size = row_len * (height as usize);

        // Use zlib stored blocks: 2-byte zlib header + stored blocks + 4-byte adler32.
        let mut zlib_data = Vec::with_capacity(raw_size + 64);
        zlib_data.extend_from_slice(&[0x78, 0x01]); // zlib header (deflate, no compression)

        let mut scanline_data = Vec::with_capacity(raw_size);
        for y in 0..(height as usize) {
            scanline_data.push(0); // filter: None
            let start = y * (width as usize) * 4;
            let end = start + (width as usize) * 4;
            scanline_data.extend_from_slice(&rgba[start..end]);
        }

        let mut offset = 0;
        while offset < scanline_data.len() {
            let remaining = scanline_data.len() - offset;
            let block_size = remaining.min(65535);
            let is_final = offset + block_size >= scanline_data.len();
            zlib_data.push(if is_final { 0x01 } else { 0x00 });
            zlib_data.extend_from_slice(&(block_size as u16).to_le_bytes());
            zlib_data.extend_from_slice(&(!(block_size as u16)).to_le_bytes());
            zlib_data.extend_from_slice(&scanline_data[offset..offset + block_size]);
            offset += block_size;
        }

        let adler = adler32(&scanline_data);
        zlib_data.extend_from_slice(&adler.to_be_bytes());

        write_chunk(&mut out, b"IDAT", &zlib_data);
        write_chunk(&mut out, b"IEND", &[]);

        out
    }

    fn write_chunk(out: &mut Vec<u8>, chunk_type: &[u8; 4], data: &[u8]) {
        out.extend_from_slice(&(data.len() as u32).to_be_bytes());
        out.extend_from_slice(chunk_type);
        out.extend_from_slice(data);
        let mut crc_data = Vec::with_capacity(4 + data.len());
        crc_data.extend_from_slice(chunk_type);
        crc_data.extend_from_slice(data);
        out.extend_from_slice(&crc32(&crc_data).to_be_bytes());
    }

    fn crc32(data: &[u8]) -> u32 {
        let mut crc: u32 = 0xFFFF_FFFF;
        for &byte in data {
            crc ^= byte as u32;
            for _ in 0..8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB8_8320;
                } else {
                    crc >>= 1;
                }
            }
        }
        crc ^ 0xFFFF_FFFF
    }

    fn adler32(data: &[u8]) -> u32 {
        let mut a: u32 = 1;
        let mut b: u32 = 0;
        for &byte in data {
            a = (a + byte as u32) % 65521;
            b = (b + a) % 65521;
        }
        (b << 16) | a
    }
}

/// Extract the icon from an EXE file and return PNG bytes.
///
/// Returns `None` if the EXE has no icon resource, the file does not exist,
/// or any Win32 call fails. This is a synchronous, best-effort operation.
#[flutter_rust_bridge::frb(sync)]
pub fn extract_exe_icon(exe_path: String) -> Option<Vec<u8>> {
    #[cfg(windows)]
    {
        platform::extract(&exe_path)
    }
    #[cfg(not(windows))]
    {
        let _ = exe_path;
        None
    }
}
