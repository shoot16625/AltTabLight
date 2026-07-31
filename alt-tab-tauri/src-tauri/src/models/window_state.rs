use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct WindowState {
    pub id: String,
    pub is_phantom: bool,
    pub is_windowless_app: bool,
    pub is_fullscreen: bool,
    pub is_minimized: bool,
    pub is_tabbed: bool,
    pub is_on_all_spaces: bool,
    pub space_ids: Vec<u64>,
    pub space_indexes: Vec<i32>,
    pub last_focus_order: i32,
    pub creation_order: i32,
    pub title: String,
    pub is_main_window: bool,
}

impl Default for WindowState {
    fn default() -> Self {
        Self {
            id: String::new(),
            is_phantom: false,
            is_windowless_app: false,
            is_fullscreen: false,
            is_minimized: false,
            is_tabbed: false,
            is_on_all_spaces: true,
            space_ids: vec![],
            space_indexes: vec![],
            last_focus_order: i32::MAX,
            creation_order: 0,
            title: String::new(),
            is_main_window: false,
        }
    }
}
