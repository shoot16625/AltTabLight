import React, { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";

interface ShortcutConfig {
  hold_modifier: string;
  next_window_key: string;
}

interface PreferencesStore {
  shortcut_count: number;
  shortcuts: ShortcutConfig[];
}

const MODIFIERS = ["⌥", "⌃", "⌘", "⇧"];
const KEYS = ["Tab", "`", "Space", "Enter", "Escape"];

const DEFAULTS: PreferencesStore = {
  shortcut_count: 2,
  shortcuts: [
    { hold_modifier: "⌥", next_window_key: "Tab" },
    { hold_modifier: "⌥", next_window_key: "`" },
    { hold_modifier: "⌥", next_window_key: "Tab" },
  ],
};

const SettingsWindow: React.FC = () => {
  const [prefs, setPrefs] = useState<PreferencesStore | null>(null);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    invoke<PreferencesStore>("get_preferences").then(setPrefs);
  }, []);

  if (!prefs) {
    return <div className="settings-loading">Loading…</div>;
  }

  const updateShortcut = (i: number, field: keyof ShortcutConfig, value: string) => {
    const shortcuts = prefs.shortcuts.map((s, idx) =>
      idx === i ? { ...s, [field]: value } : s,
    );
    setPrefs({ ...prefs, shortcuts });
    setSaved(false);
  };

  const save = async () => {
    await invoke("update_preferences", { prefs });
    setSaved(true);
  };

  const reset = async () => {
    setPrefs(DEFAULTS);
    await invoke("update_preferences", { prefs: DEFAULTS });
    setSaved(true);
  };

  const rows = prefs.shortcuts.slice(0, 3);

  return (
    <div className="settings-window">
      <h2>Shortcuts</h2>
      <p className="setting-description">
        Customize the global shortcut that shows the window switcher.
        Hold the modifier, then press the key.
      </p>

      {rows.map((sc, i) => (
        <div key={i} className="setting-row">
          <span>Shortcut {i + 1}</span>
          <div className="shortcut-picker">
            <select
              value={sc.hold_modifier}
              onChange={(e) => updateShortcut(i, "hold_modifier", e.target.value)}
            >
              {MODIFIERS.map((m) => (
                <option key={m} value={m}>{m}</option>
              ))}
            </select>
            <span className="plus">+</span>
            <select
              value={sc.next_window_key}
              onChange={(e) => updateShortcut(i, "next_window_key", e.target.value)}
            >
              {KEYS.map((k) => (
                <option key={k} value={k}>{k}</option>
              ))}
            </select>
          </div>
        </div>
      ))}

      <div className="settings-actions">
        <button className="settings-button primary" onClick={save}>Save</button>
        <button className="settings-button" onClick={reset}>Reset to defaults</button>
        {saved && <span className="saved-hint">Saved — takes effect immediately</span>}
      </div>
    </div>
  );
};

export default SettingsWindow;
