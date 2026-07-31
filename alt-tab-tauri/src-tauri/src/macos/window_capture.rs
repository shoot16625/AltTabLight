use std::ffi::c_void;
use std::sync::Mutex;

static ACTIVE_CAPTURES: Mutex<u32> = Mutex::new(0);

#[derive(Debug, Clone)]
pub struct WindowCapture {
    pub window_id: u32,
    pub png_data: Vec<u8>,
    pub width: u32,
    pub height: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
struct CFRange {
    location: isize,
    length: isize,
}

const KCG_WINDOW_LIST_OPTION_ONSCREEN_ONLY: u32 = 1;
const KCG_WINDOW_LIST_OPTION_INCLUDING_WINDOW: u32 = 1 << 3;
const KCG_WINDOW_LIST_OPTION_EXCLUDE_DESKTOP: u32 = 1 << 4;
const KCG_NULL_WINDOW_ID: u32 = 0;
const KCF_STRING_ENCODING_UTF8: u32 = 0x08000100;
const KCF_NUMBER_SINT32: u32 = 3;
const KCF_NUMBER_FLOAT64: u32 = 6;
const KCG_BITMAP_BYTE_ORDER_32_LITTLE: u32 = 2 << 12;

extern "C" {
    fn CGWindowListCopyWindowInfo(option: u32, relative_to_window: u32) -> *mut c_void;
    fn CGWindowListCreateImage(
        screen_bounds: core_graphics::geometry::CGRect,
        list_option: u32,
        window_id: u32,
        image_option: u32,
    ) -> *mut c_void;
    fn CGImageGetWidth(image: *mut c_void) -> usize;
    fn CGImageGetHeight(image: *mut c_void) -> usize;
    fn CGImageGetBytesPerRow(image: *mut c_void) -> usize;
    fn CGImageGetBitmapInfo(image: *mut c_void) -> u32;
    fn CGImageGetDataProvider(image: *mut c_void) -> *mut c_void;
    fn CGDataProviderCopyData(provider: *mut c_void) -> *mut c_void;
    fn CFDataGetLength(data: *mut c_void) -> isize;
    fn CFDataGetBytes(data: *mut c_void, range: CFRange, buffer: *mut u8);
    fn CFArrayGetCount(array: *mut c_void) -> isize;
    fn CFArrayGetValueAtIndex(array: *mut c_void, index: isize) -> *mut c_void;
    fn CFDictionaryGetValue(dict: *mut c_void, key: *mut c_void) -> *mut c_void;
    fn CFStringCreateWithCString(alloc: *mut c_void, c_str: *const i8, encoding: u32) -> *mut c_void;
    fn CFStringGetLength(string: *mut c_void) -> isize;
    fn CFStringGetCString(string: *mut c_void, buffer: *mut i8, buffer_size: isize, encoding: u32) -> bool;
    fn CFNumberGetValue(number: *mut c_void, the_type: u32, value: *mut c_void) -> bool;
    fn CFRelease(object: *mut c_void);
}

fn cf_string(s: &str) -> *mut c_void {
    unsafe { CFStringCreateWithCString(std::ptr::null_mut(), s.as_ptr() as *const i8, KCF_STRING_ENCODING_UTF8) }
}

fn cf_string_to_string(s: *mut c_void) -> String {
    unsafe {
        if s.is_null() { return String::new(); }
        let len = CFStringGetLength(s);
        let max_len = len * 4 + 1;
        let mut buf = vec![0u8; max_len as usize];
        let ok = CFStringGetCString(s, buf.as_mut_ptr() as *mut i8, max_len, KCF_STRING_ENCODING_UTF8);
        if ok {
            String::from_utf8_lossy(&buf).trim_end_matches('\0').to_string()
        } else {
            String::new()
        }
    }
}

fn cf_number_f64(number: *mut c_void) -> f64 {
    unsafe {
        if number.is_null() { return 0.0; }
        let mut value: f64 = 0.0;
        CFNumberGetValue(number, KCF_NUMBER_FLOAT64, &mut value as *mut f64 as *mut c_void);
        value
    }
}

/// Finds the CGWindowID and bounds of the window owned by `pid` with the given title.
pub fn find_window(pid: i32, title: &str) -> Option<(u32, f64, f64, f64, f64)> {
    unsafe {
        let list = CGWindowListCopyWindowInfo(
            KCG_WINDOW_LIST_OPTION_ONSCREEN_ONLY | KCG_WINDOW_LIST_OPTION_EXCLUDE_DESKTOP,
            KCG_NULL_WINDOW_ID,
        );
        if list.is_null() { return None; }
        let count = CFArrayGetCount(list);

        let pid_key = cf_string("kCGWindowOwnerPID");
        let name_key = cf_string("kCGWindowName");
        let number_key = cf_string("kCGWindowNumber");
        let bounds_key = cf_string("kCGWindowBounds");

        let mut result = None;
        for i in 0..count {
            let dict = CFArrayGetValueAtIndex(list, i);
            if dict.is_null() { continue; }

            let pid_val = CFDictionaryGetValue(dict, pid_key);
            if pid_val.is_null() { continue; }
            let mut owner_pid: i32 = 0;
            CFNumberGetValue(pid_val, KCF_NUMBER_SINT32, &mut owner_pid as *mut i32 as *mut c_void);
            if owner_pid != pid { continue; }

            if !title.is_empty() {
                let name_val = CFDictionaryGetValue(dict, name_key);
                if !name_val.is_null() && cf_string_to_string(name_val) != title {
                    continue;
                }
            }

            let number_val = CFDictionaryGetValue(dict, number_key);
            let mut window_id: u32 = 0;
            if !number_val.is_null() {
                CFNumberGetValue(number_val, KCF_NUMBER_SINT32, &mut window_id as *mut u32 as *mut c_void);
            }

            let bounds_dict = CFDictionaryGetValue(dict, bounds_key);
            let mut bounds = (0.0, 0.0, 0.0, 0.0);
            if !bounds_dict.is_null() {
                let x_key = cf_string("X");
                let y_key = cf_string("Y");
                let w_key = cf_string("Width");
                let h_key = cf_string("Height");
                bounds = (
                    cf_number_f64(CFDictionaryGetValue(bounds_dict, x_key)),
                    cf_number_f64(CFDictionaryGetValue(bounds_dict, y_key)),
                    cf_number_f64(CFDictionaryGetValue(bounds_dict, w_key)),
                    cf_number_f64(CFDictionaryGetValue(bounds_dict, h_key)),
                );
                CFRelease(x_key);
                CFRelease(y_key);
                CFRelease(w_key);
                CFRelease(h_key);
            }

            result = Some((window_id, bounds.0, bounds.1, bounds.2, bounds.3));
            break;
        }

        CFRelease(pid_key);
        CFRelease(name_key);
        CFRelease(number_key);
        CFRelease(bounds_key);
        CFRelease(list);
        result
    }
}

/// Captures the window owned by `pid` with the given title and encodes it as a PNG.
pub fn capture_window_image(pid: i32, title: &str) -> Option<WindowCapture> {
    let (window_id, x, y, w, h) = find_window(pid, title)?;
    capture_window_image_by_id(window_id, x, y, w, h)
}

pub fn capture_window_image_by_id(window_id: u32, x: f64, y: f64, w: f64, h: f64) -> Option<WindowCapture> {
    increment_active_captures();
    let result = unsafe {
        let bounds = core_graphics::geometry::CGRect::new(
            &core_graphics::geometry::CGPoint::new(x, y),
            &core_graphics::geometry::CGSize::new(w, h),
        );
        let image = CGWindowListCreateImage(
            bounds,
            KCG_WINDOW_LIST_OPTION_INCLUDING_WINDOW,
            window_id,
            1, // kCGWindowImageOptionBoundsIgnoreFraming
        );
        if image.is_null() { return None; }

        let width = CGImageGetWidth(image);
        let height = CGImageGetHeight(image);
        let bytes_per_row = CGImageGetBytesPerRow(image);
        let bitmap_info = CGImageGetBitmapInfo(image);

        let provider = CGImageGetDataProvider(image);
        let data = CGDataProviderCopyData(provider);
        if data.is_null() { return None; }

        let data_len = CFDataGetLength(data);
        let mut raw = vec![0u8; data_len as usize];
        CFDataGetBytes(data, CFRange { location: 0, length: data_len }, raw.as_mut_ptr());

        // Convert to RGBA: little-endian 32-bit is BGRA, swap R and B
        let is_bgra = bitmap_info & 0x7000 == KCG_BITMAP_BYTE_ORDER_32_LITTLE;
        let mut rgba = vec![0u8; width * height * 4];
        let row_bytes = bytes_per_row.min(data_len as usize);
        for row in 0..height {
            let src = row * bytes_per_row;
            let dst = row * width * 4;
            let mut col = 0;
            while col < width && src + col * 4 + 3 < data_len as usize {
                let s = src + col * 4;
                let d = dst + col * 4;
                if is_bgra {
                    rgba[d] = raw[s + 2];
                    rgba[d + 1] = raw[s + 1];
                    rgba[d + 2] = raw[s];
                } else {
                    rgba[d] = raw[s];
                    rgba[d + 1] = raw[s + 1];
                    rgba[d + 2] = raw[s + 2];
                }
                rgba[d + 3] = if s + 3 < raw.len() { raw[s + 3] } else { 255 };
                col += 1;
            }
        }
        let _ = row_bytes;

        let png_data = encode_png(&rgba, width as u32, height as u32);

        CFRelease(data);
        CGImageRelease(image);

        Some(WindowCapture {
            window_id,
            png_data: png_data?,
            width: width as u32,
            height: height as u32,
        })
    };
    decrement_active_captures();
    result
}

fn encode_png(rgba: &[u8], width: u32, height: u32) -> Option<Vec<u8>> {
    let mut buf = Vec::new();
    {
        let mut encoder = png::Encoder::new(&mut buf, width, height);
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        let mut writer = encoder.write_header().ok()?;
        writer.write_image_data(rgba).ok()?;
    }
    Some(buf)
}

extern "C" {
    fn CGImageRelease(image: *mut c_void);
}

pub fn active_capture_count() -> u32 {
    *ACTIVE_CAPTURES.lock().unwrap()
}

pub fn increment_active_captures() {
    *ACTIVE_CAPTURES.lock().unwrap() += 1;
}

pub fn decrement_active_captures() {
    let mut lock = ACTIVE_CAPTURES.lock().unwrap();
    if *lock > 0 { *lock -= 1; }
}
