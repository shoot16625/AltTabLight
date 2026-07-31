#![allow(dead_code)]
mod commands;
mod macos;
mod models;

use parking_lot::RwLock;
use std::sync::Arc;

pub struct AppState {
    pub windows: RwLock<Vec<models::window_state::WindowState>>,
    pub apps: RwLock<Vec<models::app_state::AppState>>,
    pub visible_space_ids: RwLock<Vec<u64>>,
    pub frontmost_pid: RwLock<Option<i32>>,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            windows: RwLock::new(vec![]),
            apps: RwLock::new(vec![]),
            visible_space_ids: RwLock::new(vec![]),
            frontmost_pid: RwLock::new(None),
        }
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .manage(Arc::new(AppState::new()))
        .invoke_handler(tauri::generate_handler![
            commands::refresh_windows,
            commands::focus_window,
            commands::show_switcher,
            commands::hide_switcher,
            commands::check_accessibility_permission,
            commands::cycle_selection,
            commands::get_window_thumbnail,
        ])
        .setup(|app| {
            log::info!("AltTab Tauri app starting…");
            macos::tray::setup(app)?;

            // Start global shortcut listener (Option+Tab)
            let handle = app.handle().clone();
            macos::global_shortcut::start(handle);

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
