use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::App;

pub fn setup(app: &mut App) -> tauri::Result<()> {
    let settings_item = MenuItem::with_id(app, "settings", "Customize Shortcut…", true, None::<&str>)?;
    let quit_item = MenuItem::with_id(app, "quit", "Quit AltTab", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&settings_item, &quit_item])?;

    let tray_builder = TrayIconBuilder::with_id("main-tray")
        .menu(&menu)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "settings" => {
                let _ = crate::commands::show_settings(app.clone());
            }
            "quit" => {
                app.exit(0);
            }
            _ => {}
        });

    let tray_builder = if let Some(icon) = app.default_window_icon() {
        tray_builder.icon(icon.clone())
    } else {
        tray_builder
    };

    tray_builder.build(app)?;
    log::info!("Tray icon created");
    Ok(())
}
