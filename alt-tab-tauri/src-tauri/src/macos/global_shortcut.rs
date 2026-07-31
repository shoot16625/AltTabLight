use cocoa::base::{id, nil};
use core_foundation::base::TCFType;
use core_foundation::string::CFString;
use once_cell::sync::Lazy;
use std::ffi::c_void;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use tauri::Emitter;

use crate::models::preferences::{ShortcutConfig, key_code, modifier_flag, modifier_keycodes};

const KVK_ESCAPE: i64 = 53;
const FLAG_SHIFT: u64 = 1 << 17;

// CGEvent types
const EVENT_FLAGS_CHANGED: u32 = 12;
const EVENT_KEY_DOWN: u32 = 10;
const EVENT_TAP_DISABLED_BY_TIMEOUT: u32 = 0xFFFFFFFE;
const EVENT_TAP_DISABLED_BY_USER_INPUT: u32 = 0xFFFFFFFF;

static SWITCHER_ACTIVE: AtomicBool = AtomicBool::new(false);
static CURRENT_HELD_FLAG: AtomicU64 = AtomicU64::new(0);
static EVENT_TAP: Lazy<Mutex<Option<usize>>> = Lazy::new(|| Mutex::new(None));
static APP_HANDLE: Lazy<Mutex<Option<tauri::AppHandle>>> = Lazy::new(|| Mutex::new(None));

/// Configured (modifier flag, modifier keycodes) pairs, e.g. [(1<<19, [58, 61])]
static MODIFIERS: Lazy<Mutex<Vec<(u64, Vec<i64>)>>> =
    Lazy::new(|| Mutex::new(vec![(1 << 19, vec![58, 61])]));
/// Configured "next window" key codes, e.g. [48] (Tab)
static NEXT_KEYS: Lazy<Mutex<Vec<i64>>> = Lazy::new(|| Mutex::new(vec![48]));

extern "C" {
    fn CGEventTapCreate(
        tap: u32,
        place: u32,
        options: u32,
        events_of_interest: u64,
        callback: *const c_void,
        user_info: *const c_void,
    ) -> id;

    fn CFMachPortCreateRunLoopSource(
        allocator: *const c_void,
        port: id,
        order: isize,
    ) -> id;

    fn CFRunLoopGetCurrent() -> id;
    fn CFRunLoopAddSource(run_loop: id, source: id, mode: id);
    fn CFRunLoopRun();
    fn CGEventTapEnable(tap: id, enable: bool);
    fn CGEventGetIntegerValueField(event: id, field: u32) -> i64;
    fn CGEventGetFlags(event: id) -> u64;
}

fn event_key_code(event: id) -> i64 {
    unsafe { CGEventGetIntegerValueField(event, 9) }
}

fn event_flags(event: id) -> u64 {
    unsafe { CGEventGetFlags(event) }
}

extern "C" fn event_tap_callback(
    _refcon: *mut c_void,
    _proxy: id,
    event_type: u32,
    event: id,
) -> id {
    if event.is_null() {
        return std::ptr::null_mut();
    }

    match event_type {
        EVENT_TAP_DISABLED_BY_TIMEOUT | EVENT_TAP_DISABLED_BY_USER_INPUT => {
            if let Some(tap_ptr) = EVENT_TAP.lock().unwrap().clone() {
                unsafe { CGEventTapEnable(tap_ptr as id, true); }
            }
            event
        }
        EVENT_FLAGS_CHANGED => {
            let key = event_key_code(event);
            let flags = event_flags(event);
            let modifiers = MODIFIERS.lock().unwrap().clone();
            for (flag, keycodes) in modifiers {
                if !keycodes.contains(&key) { continue; }
                if flags & flag != 0 {
                    // hold modifier pressed
                    CURRENT_HELD_FLAG.store(flag, Ordering::SeqCst);
                } else {
                    // hold modifier released — focus selected window if switcher was open
                    let held = CURRENT_HELD_FLAG.swap(0, Ordering::SeqCst);
                    if held == flag && SWITCHER_ACTIVE.swap(false, Ordering::SeqCst) {
                        log::debug!("Hold shortcut released while switcher active -> focus");
                        if let Some(handle) = APP_HANDLE.lock().unwrap().clone() {
                            let _ = handle.emit("shortcut-release", ());
                        }
                    }
                }
                break;
            }
            event
        }
        EVENT_KEY_DOWN => {
            let key = event_key_code(event);
            let flags = event_flags(event);

            if key == KVK_ESCAPE && SWITCHER_ACTIVE.load(Ordering::SeqCst) {
                SWITCHER_ACTIVE.store(false, Ordering::SeqCst);
                if let Some(handle) = APP_HANDLE.lock().unwrap().clone() {
                    let _ = handle.emit("switcher-cancel", ());
                }
                return std::ptr::null_mut(); // swallow Escape
            }

            let held = CURRENT_HELD_FLAG.load(Ordering::SeqCst);
            if held != 0 && NEXT_KEYS.lock().unwrap().contains(&key) {
                let shift = flags & FLAG_SHIFT != 0;
                if SWITCHER_ACTIVE.load(Ordering::SeqCst) {
                    if let Some(handle) = APP_HANDLE.lock().unwrap().clone() {
                        let _ = handle.emit("cycle-selection", shift);
                    }
                } else {
                    SWITCHER_ACTIVE.store(true, Ordering::SeqCst);
                    if let Some(handle) = APP_HANDLE.lock().unwrap().clone() {
                        let _ = handle.emit("show-switcher", ());
                    }
                }
                return std::ptr::null_mut(); // swallow the key so it doesn't reach the app
            }

            event
        }
        _ => event,
    }
}

/// Applies the configured shortcuts to the event tap. Called at startup and on preference changes.
pub fn apply_shortcuts(configs: &[ShortcutConfig]) {
    let mut modifiers = Vec::new();
    let mut keys = Vec::new();
    for cfg in configs {
        if let Some(flag) = modifier_flag(&cfg.hold_modifier) {
            let keycodes = modifier_keycodes(&cfg.hold_modifier);
            if !modifiers.iter().any(|(f, _)| *f == flag) {
                modifiers.push((flag, keycodes.to_vec()));
            }
        }
        if let Some(code) = key_code(&cfg.next_window_key) {
            if !keys.contains(&code) {
                keys.push(code);
            }
        }
    }
    // Fall back to Option+Tab when nothing valid is configured
    if modifiers.is_empty() {
        modifiers.push((1 << 19, vec![58, 61]));
    }
    if keys.is_empty() {
        keys.push(48);
    }
    *MODIFIERS.lock().unwrap() = modifiers;
    *NEXT_KEYS.lock().unwrap() = keys;
    log::info!("Global shortcut config applied: {configs:?}");
}

/// Starts the global keyboard shortcut event tap on a dedicated thread.
pub fn start(app_handle: tauri::AppHandle) {
    *APP_HANDLE.lock().unwrap() = Some(app_handle.clone());

    std::thread::Builder::new()
        .name("alt-tab-global-shortcut".to_string())
        .spawn(move || unsafe {
            // keyDown | keyUp | flagsChanged
            let mask: u64 = (1 << 10) | (1 << 11) | (1 << 12);
            let tap = CGEventTapCreate(
                0,  // kCGHIDEventTap
                0,  // kCGHeadInsertEventTap
                1,  // kCGEventTapOptionDefault
                mask,
                event_tap_callback as *const c_void,
                std::ptr::null_mut(),
            );
            if tap == nil {
                log::error!("Failed to create CGEventTap (missing Accessibility permission?)");
                return;
            }
            let run_loop_source = CFMachPortCreateRunLoopSource(std::ptr::null_mut(), tap, 0);
            let run_loop = CFRunLoopGetCurrent();
            let common_modes = CFString::new("kCFRunLoopCommonModes");
            CFRunLoopAddSource(run_loop, run_loop_source, common_modes.as_concrete_TypeRef() as *mut c_void as id);
            CGEventTapEnable(tap, true);
            *EVENT_TAP.lock().unwrap() = Some(tap as usize);
            log::info!("Global shortcut event tap started");
            CFRunLoopRun();
        })
        .expect("failed to spawn global shortcut thread");
}

pub fn set_switcher_active(active: bool) {
    SWITCHER_ACTIVE.store(active, Ordering::SeqCst);
}
