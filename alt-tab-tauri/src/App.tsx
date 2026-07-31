import { useState, useEffect, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import SwitcherPanel from "./components/SwitcherPanel";

export interface WindowEntry {
  id: string;
  title: string;
  app_name: string;
  app_bundle_id: string | null;
  pid: number;
  is_minimized: boolean;
  is_fullscreen: boolean;
  is_hidden: boolean;
  is_windowless_app: boolean;
}

interface SwitcherState {
  windows: WindowEntry[];
  selected_index: number;
  is_active: boolean;
}

async function cycle(direction: number, selectedIndex: number): Promise<number> {
  return invoke("cycle_selection", { direction, selectedIndex });
}

function App() {
  const [hasAccessibility, setHasAccessibility] = useState<boolean>(true);
  const [switcherState, setSwitcherState] = useState<SwitcherState>({
    windows: [],
    selected_index: 0,
    is_active: false,
  });

  const hideSwitcher = useCallback(async () => {
    setSwitcherState(prev => ({ ...prev, is_active: false }));
    try {
      await invoke("hide_switcher");
    } catch {
      // window may already be hidden
    }
    try {
      await getCurrentWindow().hide();
    } catch {
      // ignore
    }
  }, []);

  const focusSelected = useCallback(async () => {
    setSwitcherState(prev => {
      const win = prev.windows[prev.selected_index];
      if (win) {
        invoke("focus_window", { pid: win.pid, windowTitle: win.title }).catch(() => {});
      }
      return { ...prev, is_active: false };
    });
    await hideSwitcher();
  }, [hideSwitcher]);

  // Listen for backend events (global shortcut)
  useEffect(() => {
    let unlisteners: UnlistenFn[] = [];

    async function setupListeners() {
      unlisteners.push(await listen("show-switcher", async () => {
        const wins: WindowEntry[] = await invoke("refresh_windows");
        setSwitcherState({
          windows: wins,
          selected_index: 0,
          is_active: true,
        });
        try {
          await getCurrentWindow().show();
          await getCurrentWindow().setFocus();
        } catch {
          // window hidden / not focusable — fine
        }
      }));

      unlisteners.push(await listen<boolean>("cycle-selection", async (event) => {
        const direction = event.payload ? -1 : 1;
        setSwitcherState(prev => {
          if (!prev.is_active) return prev;
          cycle(direction, prev.selected_index).then(idx => {
            setSwitcherState(p => ({ ...p, selected_index: idx }));
          });
          return prev;
        });
      }));

      unlisteners.push(await listen("shortcut-release", async () => {
        await focusSelected();
      }));

      unlisteners.push(await listen("switcher-cancel", async () => {
        await hideSwitcher();
      }));
    }

    setupListeners();
    return () => {
      for (const un of unlisteners) un();
    };
  }, [focusSelected, hideSwitcher]);

  // Keyboard navigation (arrows, Enter, Escape)
  const handleKeyDown = useCallback(async (e: KeyboardEvent) => {
    if (!switcherState.is_active) return;

    switch (e.key) {
      case "Escape":
        e.preventDefault();
        await hideSwitcher();
        break;
      case "ArrowRight":
      case "ArrowDown":
        e.preventDefault();
        setSwitcherState(prev => {
          cycle(1, prev.selected_index).then(idx => {
            setSwitcherState(p => ({ ...p, selected_index: idx }));
          });
          return prev;
        });
        break;
      case "ArrowLeft":
      case "ArrowUp":
        e.preventDefault();
        setSwitcherState(prev => {
          cycle(-1, prev.selected_index).then(idx => {
            setSwitcherState(p => ({ ...p, selected_index: idx }));
          });
          return prev;
        });
        break;
      case "Enter":
        e.preventDefault();
        await focusSelected();
        break;
    }
  }, [switcherState, hideSwitcher, focusSelected]);

  useEffect(() => {
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [handleKeyDown]);

  useEffect(() => {
    invoke("check_accessibility_permission")
      .then((granted) => setHasAccessibility(granted as boolean))
      .catch(() => setHasAccessibility(false));
  }, []);

  return (
    <div className="app-root">
      {!hasAccessibility && (
        <div className="permission-banner">
          AltTab needs Accessibility permission to show windows.
          Open System Settings &gt; Privacy &amp; Security &gt; Accessibility and enable AltTab.
        </div>
      )}

      {switcherState.is_active && (
        <SwitcherPanel
          windows={switcherState.windows}
          selectedIndex={switcherState.selected_index}
          onSelect={(idx) => {
            setSwitcherState(prev => ({ ...prev, selected_index: idx }));
          }}
          onActivate={async (idx) => {
            setSwitcherState(prev => ({ ...prev, selected_index: idx }));
            await focusSelected();
          }}
        />
      )}
    </div>
  );
}

export default App;
