use crate::macos::accessibility;
use crate::models::preferences::PreferencesStore;
use crate::models::{AppState as ModelAppState, WindowState};
use serde::Serialize;
use std::fs;
use std::path::PathBuf;
use std::sync::Arc;
use tauri::{Emitter, Manager, State};

fn prefs_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let dir = app.path().app_config_dir().map_err(|e| e.to_string())?;
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir.join("preferences.json"))
}

#[tauri::command]
pub fn get_preferences(app: tauri::AppHandle) -> PreferencesStore {
    let path = match prefs_path(&app) {
        Ok(p) => p,
        Err(_) => return PreferencesStore::default(),
    };
    fs::read_to_string(path)
        .ok()
        .and_then(|data| serde_json::from_str(&data).ok())
        .unwrap_or_default()
}

#[tauri::command]
pub fn update_preferences(app: tauri::AppHandle, prefs: PreferencesStore) -> Result<(), String> {
    let path = prefs_path(&app)?;
    let json = serde_json::to_string_pretty(&prefs).map_err(|e| e.to_string())?;
    fs::write(&path, json).map_err(|e| e.to_string())?;
    crate::macos::global_shortcut::apply_shortcuts(&prefs.shortcuts);
    log::info!("Preferences updated: {:?}", prefs.shortcuts);
    Ok(())
}

#[derive(Debug, Serialize)]
pub struct WindowEntry {
    pub id: String,
    pub title: String,
    pub app_name: String,
    pub app_bundle_id: Option<String>,
    pub pid: i32,
    pub is_minimized: bool,
    pub is_fullscreen: bool,
    pub is_hidden: bool,
    pub is_windowless_app: bool,
}

#[tauri::command]
pub fn refresh_windows(state: State<Arc<crate::AppState>>) -> Vec<WindowEntry> {
    let apps = accessibility::running_apps();
    let frontmost = accessibility::frontmost_app();
    *state.frontmost_pid.write() = frontmost.as_ref().map(|a| a.pid);

    let mut window_states: Vec<WindowState> = vec![];
    let mut app_states: Vec<ModelAppState> = vec![];

    for app in &apps {
        let element = accessibility::create_application_element(app.pid);
        let ax_windows = accessibility::get_window_list(element);

        let app_state = ModelAppState {
            pid: app.pid,
            bundle_identifier: app.bundle_id.clone(),
            localized_name: Some(app.name.clone()),
            is_hidden: app.is_hidden,
        };
        app_states.push(app_state.clone());

        if ax_windows.is_empty() {
            window_states.push(WindowState {
                id: format!("windowless-{}", app.pid),
                title: app.name.clone(),
                is_windowless_app: true,
                is_phantom: false,
                is_fullscreen: false,
                is_minimized: false,
                is_tabbed: false,
                is_on_all_spaces: true,
                space_ids: vec![],
                space_indexes: vec![],
                last_focus_order: i32::MAX,
                creation_order: 0,
                is_main_window: false,
            });
        } else {
            for win in &ax_windows {
                if let Some(info) = accessibility::get_window_info(*win) {
                    window_states.push(WindowState {
                        id: format!("{}-{}", app.pid, info.title),
                        title: info.title,
                        is_windowless_app: false,
                        is_phantom: false,
                        is_fullscreen: info.is_fullscreen,
                        is_minimized: info.is_minimized,
                        is_tabbed: false,
                        is_on_all_spaces: true,
                        space_ids: vec![],
                        space_indexes: vec![],
                        last_focus_order: i32::MAX,
                        creation_order: 0,
                        is_main_window: info.is_main,
                    });
                }
            }
        }
    }

    *state.windows.write() = window_states.clone();
    *state.apps.write() = app_states.clone();

    window_states
        .iter()
        .map(|w| {
            let app = app_states
                .iter()
                .find(|a| w.id.starts_with(&format!("{}-", a.pid)));
            WindowEntry {
                id: w.id.clone(),
                title: w.title.clone(),
                app_name: app.and_then(|a| a.localized_name.clone()).unwrap_or_default(),
                app_bundle_id: app.and_then(|a| a.bundle_identifier.clone()),
                pid: app.map(|a| a.pid).unwrap_or(-1),
                is_minimized: w.is_minimized,
                is_fullscreen: w.is_fullscreen,
                is_hidden: app.map(|a| a.is_hidden).unwrap_or(false),
                is_windowless_app: w.is_windowless_app,
            }
        })
        .collect()
}

#[tauri::command]
pub fn focus_window(pid: i32, window_title: String) -> bool {
    let element = accessibility::create_application_element(pid);
    let windows = accessibility::get_window_list(element);
    for win in &windows {
        if let Some(info) = accessibility::get_window_info(*win) {
            if info.title == window_title {
                accessibility::focus_window(*win);
                return true;
            }
        }
    }
    if let Some(first_win) = windows.first() {
        accessibility::focus_window(*first_win);
        return true;
    }
    false
}

#[tauri::command]
pub fn show_switcher(app_handle: tauri::AppHandle) -> Result<(), String> {
    let window = app_handle.get_webview_window("switcher").or_else(|| {
        tauri::WebviewWindowBuilder::new(
            &app_handle,
            "switcher",
            tauri::WebviewUrl::App("index.html".into()),
        )
        .title("AltTab Switcher")
        .inner_size(800.0, 400.0)
        .resizable(false)
        .decorations(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .center()
        .visible(false)
        .build()
        .ok()
    });

    let Some(window) = window else {
        return Err("failed to create switcher window".into());
    };

    crate::macos::global_shortcut::set_switcher_active(true);
    window.show().map_err(|e: tauri::Error| e.to_string())?;
    window.set_focus().map_err(|e: tauri::Error| e.to_string())?;

    window.emit("show-switcher", ()).map_err(|e: tauri::Error| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub fn hide_switcher(app_handle: tauri::AppHandle) -> Result<(), String> {
    crate::macos::global_shortcut::set_switcher_active(false);
    if let Some(window) = app_handle.get_webview_window("switcher") {
        window.hide().map_err(|e: tauri::Error| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
pub fn show_settings(app_handle: tauri::AppHandle) -> Result<(), String> {
    let window = app_handle.get_webview_window("settings").or_else(|| {
        tauri::WebviewWindowBuilder::new(
            &app_handle,
            "settings",
            tauri::WebviewUrl::App("index.html".into()),
        )
        .title("AltTab Settings")
        .inner_size(480.0, 360.0)
        .resizable(false)
        .center()
        .build()
        .ok()
    });

    let Some(window) = window else {
        return Err("failed to create settings window".into());
    };

    window.show().map_err(|e: tauri::Error| e.to_string())?;
    window.set_focus().map_err(|e: tauri::Error| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub fn check_accessibility_permission() -> bool {
    accessibility::is_accessibility_trusted()
}

#[tauri::command]
pub fn cycle_selection(
    state: State<Arc<crate::AppState>>,
    direction: i32,
    selected_index: usize,
) -> usize {
    let windows = state.windows.read();
    let visible_indices: Vec<usize> = windows
        .iter()
        .enumerate()
        .filter(|(_, w)| !w.is_phantom)
        .map(|(i, _)| i)
        .collect();

    if visible_indices.is_empty() { return selected_index; }
    let current_pos = visible_indices.iter().position(|&i| i == selected_index);
    match current_pos {
        Some(pos) => {
            let new_pos = if direction > 0 {
                (pos + direction as usize) % visible_indices.len()
            } else {
                let abs_step = (-direction) as usize;
                if abs_step > pos {
                    visible_indices.len() - (abs_step - pos) % visible_indices.len()
                } else {
                    pos - abs_step
                }
            };
            visible_indices[new_pos]
        }
        None => visible_indices[0],
    }
}

#[derive(Debug, Serialize)]
pub struct ThumbnailResult {
    pub png_base64: String,
    pub width: u32,
    pub height: u32,
}

#[tauri::command]
pub fn get_window_thumbnail(pid: i32, window_title: String) -> Option<ThumbnailResult> {
    let capture = crate::macos::window_capture::capture_window_image(pid, &window_title)?;
    Some(ThumbnailResult {
        png_base64: base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &capture.png_data),
        width: capture.width,
        height: capture.height,
    })
}
