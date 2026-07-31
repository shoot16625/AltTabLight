use objc::{class, msg_send, sel, sel_impl};
use cocoa::base::{id, nil};

#[derive(Debug, Clone)]
pub struct WindowInfo {
    pub title: String,
    pub pid: i32,
    pub window_id: u32,
    pub is_minimized: bool,
    pub is_fullscreen: bool,
    pub is_main: bool,
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

#[derive(Debug, Clone)]
pub struct AppInfo {
    pub pid: i32,
    pub name: String,
    pub bundle_id: Option<String>,
    pub is_hidden: bool,
}

extern "C" {
    fn AXIsProcessTrusted() -> bool;
    fn AXUIElementCopyMultipleAttributeValues(
        element: id, attributes: id, flags: u32, values: *mut id,
    ) -> i32;
    fn AXUIElementGetPid(element: id, pid: *mut i32) -> i32;
    fn AXUIElementPerformAction(element: id, action: id) -> i32;
    fn AXUIElementSetAttributeValue(element: id, attribute: id, value: id) -> i32;
}

fn nsstring(s: &str) -> id {
    unsafe {
        let ns_str: id = msg_send![class!(NSString), alloc];
        msg_send![ns_str, initWithUTF8String: s.as_ptr() as *const i8]
    }
}

pub fn is_accessibility_trusted() -> bool {
    unsafe { AXIsProcessTrusted() }
}

pub fn running_apps() -> Vec<AppInfo> {
    unsafe {
        let workspace: id = msg_send![class!(NSWorkspace), sharedWorkspace];
        let apps: id = msg_send![workspace, runningApplications];
        if apps == nil { return vec![]; }
        let count: u64 = msg_send![apps, count];
        let mut results = Vec::with_capacity(count as usize);
        for i in 0..count {
            let app: id = msg_send![apps, objectAtIndex: i];
            let policy: i32 = msg_send![app, activationPolicy];
            if policy != 0 { continue; }
            let pid: i32 = msg_send![app, processIdentifier];
            let name: id = msg_send![app, localizedName];
            let name_str: String = if name != nil {
                let cstr: *const i8 = msg_send![name, UTF8String];
                if cstr.is_null() { String::new() }
                else { std::ffi::CStr::from_ptr(cstr).to_string_lossy().into_owned() }
            } else { String::new() };
            let bundle: id = msg_send![app, bundleIdentifier];
            let bundle_id = if bundle != nil {
                let cstr: *const i8 = msg_send![bundle, UTF8String];
                if cstr.is_null() { None }
                else { Some(std::ffi::CStr::from_ptr(cstr).to_string_lossy().into_owned()) }
            } else { None };
            let is_hidden: bool = msg_send![app, isHidden];
            results.push(AppInfo { pid, name: name_str, bundle_id, is_hidden });
        }
        results
    }
}

pub fn frontmost_app() -> Option<AppInfo> {
    unsafe {
        let workspace: id = msg_send![class!(NSWorkspace), sharedWorkspace];
        let app: id = msg_send![workspace, frontmostApplication];
        if app == nil { return None; }
        let pid: i32 = msg_send![app, processIdentifier];
        let name: id = msg_send![app, localizedName];
        let name_str: String = if name != nil {
            let cstr: *const i8 = msg_send![name, UTF8String];
            if cstr.is_null() { String::new() }
            else { std::ffi::CStr::from_ptr(cstr).to_string_lossy().into_owned() }
        } else { String::new() };
        let bundle: id = msg_send![app, bundleIdentifier];
        let bundle_id = if bundle != nil {
            let cstr: *const i8 = msg_send![bundle, UTF8String];
            if cstr.is_null() { None }
            else { Some(std::ffi::CStr::from_ptr(cstr).to_string_lossy().into_owned()) }
        } else { None };
        let is_hidden: bool = msg_send![app, isHidden];
        Some(AppInfo { pid, name: name_str, bundle_id, is_hidden })
    }
}

pub fn create_application_element(pid: i32) -> id {
    unsafe { msg_send![class!(AXUIElement), elementWithPID: pid] }
}

pub fn get_window_list(element: id) -> Vec<id> {
    unsafe {
        let attrs: id = msg_send![class!(NSArray), arrayWithObject: nsstring("AXWindows")];
        let mut values: id = nil;
        let result = AXUIElementCopyMultipleAttributeValues(element, attrs, 0, &mut values);
        if result != 0 || values.is_null() { return vec![]; }
        let count: u64 = msg_send![values, count];
        if count == 0 { return vec![]; }
        let mut windows = Vec::with_capacity(count as usize);
        for i in 0..count {
            let window: id = msg_send![values, objectAtIndex: i];
            windows.push(window);
        }
        windows
    }
}

pub fn get_window_info(window: id) -> Option<WindowInfo> {
    unsafe {
        let attrs: id = msg_send![class!(NSArray), arrayWithObjects: &[
            nsstring("AXTitle"),
            nsstring("AXMinimized"),
            nsstring("AXFullScreen"),
            nsstring("AXMain"),
            nsstring("AXPosition"),
            nsstring("AXSize"),
        ] count: 6];

        let mut values: id = nil;
        let result = AXUIElementCopyMultipleAttributeValues(window, attrs, 0, &mut values);
        if result != 0 || values.is_null() { return None; }

        let get_str = |i: u64| -> Option<String> {
            let val: id = msg_send![values, objectAtIndex: i];
            if val.is_null() { return None; }
            let cstr: *const i8 = msg_send![val, UTF8String];
            if cstr.is_null() { Some(String::new()) }
            else { Some(std::ffi::CStr::from_ptr(cstr).to_string_lossy().into_owned()) }
        };
        let get_bool = |i: u64| -> bool {
            let val: id = msg_send![values, objectAtIndex: i];
            if val.is_null() { false } else { msg_send![val, boolValue] }
        };

        let title = get_str(0)?;
        let is_minimized = get_bool(1);
        let is_fullscreen = get_bool(2);
        let is_main = get_bool(3);

        let pos_val: id = msg_send![values, objectAtIndex: 4];
        let (x, y) = if pos_val.is_null() { (0.0, 0.0) } else {
            let point: cocoa::foundation::NSPoint = msg_send![pos_val, pointValue];
            (point.x, point.y)
        };

        let size_val: id = msg_send![values, objectAtIndex: 5];
        let (width, height) = if size_val.is_null() { (0.0, 0.0) } else {
            let size: cocoa::foundation::NSSize = msg_send![size_val, sizeValue];
            (size.width, size.height)
        };

        let mut pid: i32 = 0;
        AXUIElementGetPid(window, &mut pid);

        Some(WindowInfo { title, pid, window_id: 0, is_minimized, is_fullscreen, is_main, x, y, width, height })
    }
}

pub fn focus_window(window: id) {
    unsafe {
        let raise_action = nsstring("AXRaise");
        AXUIElementPerformAction(window, raise_action);
        let app: id = msg_send![window, valueForAttribute: nsstring("AXParent")];
        if !app.is_null() {
            let frontmost = nsstring("AXFrontmost");
            let yes: id = msg_send![class!(NSNumber), numberWithBool: true];
            AXUIElementSetAttributeValue(app, frontmost, yes);
        }
    }
}
