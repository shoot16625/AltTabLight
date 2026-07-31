use serde::{Deserialize, Serialize};

pub const MAX_SHORTCUT_COUNT: usize = 3;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ShortcutConfig {
    pub hold_modifier: String,
    pub next_window_key: String,
}

impl Default for ShortcutConfig {
    fn default() -> Self {
        Self {
            hold_modifier: "⌥".to_string(),
            next_window_key: "Tab".to_string(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PreferencesStore {
    pub shortcut_count: usize,
    pub shortcuts: Vec<ShortcutConfig>,
}

impl Default for PreferencesStore {
    fn default() -> Self {
        Self {
            shortcut_count: 2,
            shortcuts: vec![
                ShortcutConfig::default(),
                ShortcutConfig {
                    hold_modifier: "⌥".to_string(),
                    next_window_key: "`".to_string(),
                },
                ShortcutConfig::default(),
            ],
        }
    }
}

pub const MODIFIER_OPTIONS: [&str; 4] = ["⌥", "⌃", "⌘", "⇧"];
pub const KEY_OPTIONS: [&str; 5] = ["Tab", "`", "Space", "Enter", "Escape"];

/// Modifier symbol → CGEvent flag mask
pub fn modifier_flag(modifier: &str) -> Option<u64> {
    match modifier {
        "⌥" => Some(1 << 19), // kCGEventFlagMaskAlternate
        "⌃" => Some(1 << 18), // kCGEventFlagMaskControl
        "⌘" => Some(1 << 20), // kCGEventFlagMaskCommand
        "⇧" => Some(1 << 17), // kCGEventFlagMaskShift
        _ => None,
    }
}

/// Modifier symbol → Carbon keycodes emitted by flagsChanged for that modifier
pub fn modifier_keycodes(modifier: &str) -> &'static [i64] {
    match modifier {
        "⌥" => &[58, 61],   // left/right Option
        "⌃" => &[59, 62],   // left/right Control
        "⌘" => &[55, 54],   // left/right Command
        "⇧" => &[56, 60],   // left/right Shift
        _ => &[58, 61],
    }
}

/// Key name → Carbon virtual keycode
pub fn key_code(key: &str) -> Option<i64> {
    match key {
        "Tab" => Some(48),
        "`" => Some(50),
        "Space" => Some(49),
        "Enter" => Some(36),
        "Escape" => Some(53),
        _ => None,
    }
}
