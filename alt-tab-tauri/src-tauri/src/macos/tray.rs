use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::App;

pub fn setup(app: &mut App) -> tauri::Result<()> {
    let quit_item = MenuItem::with_id(app, "quit", "Quit AltTab", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&quit_item])?;

    let mut tray_builder = TrayIconBuilder::with_id("main-tray")
        .menu(&menu)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "quit" => {
                app.exit(0);
            }
            _ => {}
        });

    if let Some(icon) = app.default_window_icon() {
        tray_builder = tray_builder.icon(icon.clone());
    }

    tray_builder.build(app)?;
    log::info!("Tray icon created");
    Ok(())
}
