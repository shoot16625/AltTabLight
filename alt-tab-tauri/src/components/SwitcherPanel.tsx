import React, { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import type { WindowEntry } from "../App";

interface SwitcherPanelProps {
  windows: WindowEntry[];
  selectedIndex: number;
  onSelect: (index: number) => void;
  onActivate: (index: number) => void;
}

interface ThumbnailResult {
  png_base64: string;
  width: number;
  height: number;
}

const SwitcherPanel: React.FC<SwitcherPanelProps> = ({
  windows,
  selectedIndex,
  onSelect,
  onActivate,
}) => {
  const [thumbnails, setThumbnails] = useState<Record<string, ThumbnailResult>>({});

  // Fetch thumbnails for visible windows, sequentially to avoid hammering WindowServer
  useEffect(() => {
    let cancelled = false;
    async function loadThumbnails() {
      for (const win of windows) {
        if (cancelled || win.is_windowless_app) continue;
        try {
          const result: ThumbnailResult = await invoke("get_window_thumbnail", {
            pid: win.pid,
            windowTitle: win.title,
          });
          if (result && !cancelled) {
            setThumbnails(prev => {
              if (prev[win.id] === result) return prev;
              return { ...prev, [win.id]: result };
            });
          }
        } catch {
          // window not capturable (missing screen-recording permission, etc.)
        }
      }
    }
    setThumbnails({});
    loadThumbnails();
    return () => {
      cancelled = true;
    };
  }, [windows]);

  const win = windows[selectedIndex];

  return (
    <div className="switcher-panel">
      <div className="windows-grid">
        {windows.length === 0 && (
          <div className="no-windows">No windows found</div>
        )}
        {windows.map((w, idx) => {
          const thumb = thumbnails[w.id];
          return (
            <div
              key={w.id}
              className={`window-tile ${idx === selectedIndex ? "selected" : ""}`}
              onClick={() => onActivate(idx)}
              onMouseEnter={() => onSelect(idx)}
              tabIndex={0}
            >
              <div className="window-thumbnail">
                {thumb ? (
                  <img
                    src={`data:image/png;base64,${thumb.png_base64}`}
                    alt={w.title}
                    className="thumbnail-img"
                  />
                ) : (
                  <div className="thumbnail-placeholder">
                    <span className="app-icon">
                      {(w.app_name || "?").charAt(0).toUpperCase()}
                    </span>
                  </div>
                )}
              </div>
              <div className="window-info">
                <div className="window-title" title={w.title}>
                  {w.title || w.app_name}
                </div>
                <div className="window-app-name">{w.app_name}</div>
              </div>
              {(w.is_minimized || w.is_fullscreen) && (
                <div className="window-badges">
                  {w.is_minimized && <span className="badge minimized">-</span>}
                  {w.is_fullscreen && <span className="badge fullscreen">F</span>}
                </div>
              )}
            </div>
          );
        })}
      </div>

      <div className="switcher-footer">
        {win && (
          <span className="footer-info">
            {win.app_name} — {win.title}
          </span>
        )}
        <span className="footer-hint">
          Tab: cycle · Enter: focus · Esc: cancel
        </span>
      </div>
    </div>
  );
};

export default SwitcherPanel;
