use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AppState {
    pub pid: i32,
    pub bundle_identifier: Option<String>,
    pub localized_name: Option<String>,
    pub is_hidden: bool,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            pid: -1,
            bundle_identifier: None,
            localized_name: None,
            is_hidden: false,
        }
    }
}
