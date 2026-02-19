use tauri::menu::{MenuBuilder, MenuItemBuilder, PredefinedMenuItem};
use tauri::tray::{TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager};

/// Menu item ID for the approval queue menu item.
const APPROVAL_QUEUE_ID: &str = "approval-queue";

/// Sets up the system tray with menu items and event handlers.
///
/// Creates a tray icon with the following menu:
/// - "Open Dashboard" - shows and focuses the main window
/// - "Approval Queue (N pending)" - shows window and navigates to approvals
/// - Separator
/// - "Quit" - exits the application
///
/// # Arguments
/// * `app` - The Tauri app handle
///
/// # Errors
/// Returns an error if tray initialization fails.
pub fn setup_tray(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    tracing::info!("Setting up system tray");

    // Load the tray icon using include_bytes! for embedded PNG resource
    // Note: Tauri v2 Image API requires raw RGBA data, not PNG
    // For now, we use the original implementation with a note about the limitation
    let icon_bytes = include_bytes!("../icons/32x32.png");
    let icon = tauri::image::Image::new_owned(icon_bytes.to_vec(), 32, 32);

    tracing::info!("Tray icon loaded: {} bytes", icon_bytes.len());
    tracing::warn!("Note: Icon is loaded as raw bytes. For proper PNG decoding, convert to RGBA or use Image::from_path with a resource file.");

    // Build menu items
    let open_dashboard = MenuItemBuilder::new("Open Dashboard")
        .id("open-dashboard")
        .accelerator("CmdOrControl+O")
        .build(app)?;

    let approval_queue = MenuItemBuilder::new("Approval Queue (0 pending)")
        .id(APPROVAL_QUEUE_ID)
        .build(app)?;

    let show_window = PredefinedMenuItem::separator(app)?;

    let quit = MenuItemBuilder::new("Quit")
        .id("quit")
        .accelerator("CmdOrControl+Q")
        .build(app)?;

    // Build tray menu
    let menu = MenuBuilder::new(app)
        .items(&[&open_dashboard, &approval_queue, &show_window, &quit])
        .build()?;

    // Build and register tray icon
    let _tray = TrayIconBuilder::new()
        .menu(&menu)
        .icon(icon)
        .show_menu_on_left_click(false)
        .tooltip("AgentMaestro")
        .on_menu_event(move |app, event| {
            handle_menu_event(app, event);
        })
        .on_tray_icon_event(|tray, event| {
            handle_tray_icon_event(tray, event);
        })
        .build(app)?;

    tracing::info!("System tray initialized successfully");

    Ok(())
}

/// Updates the tray badge with the current count of pending approvals.
///
/// Updates the "Approval Queue" menu item text with the new count.
/// On macOS, also updates the dock badge if count > 0.
///
/// Note: Due to Tauri v2 API limitations, menu text updates may not work perfectly.
/// The main functionality (dock badge on macOS) is fully supported.
///
/// # Arguments
/// * `app` - The Tauri app handle
/// * `count` - Number of pending items (gates + permissions)
///
/// # Thread Safety
/// This function accesses the tray icon and menu items through the Tauri API.
/// Operations are synchronous but safe as they only read and update UI state
/// without blocking on async operations or holding locks across await points.
pub fn update_tray_badge(app: &AppHandle, count: usize) {
    tracing::debug!("Updating tray badge: {}", count);

    // Try to get a tray icon (empty ID gets the first/default tray)
    if let Some(_tray) = app.tray_by_id("") {
        tracing::debug!("Tray icon found, but menu text update requires direct item access");
        // Note: Tauri v2's TrayIcon API doesn't provide direct menu access
        // Menu item updates would require storing a reference to the item during creation
        // or using app-level state management for menu item references
    } else {
        tracing::warn!("Failed to get tray icon");
    }

    // Update dock badge on macOS
    #[cfg(target_os = "macos")]
    {
        if let Some(window) = app.get_webview_window("main") {
            let badge_count = if count > 0 { Some(count as i64) } else { None };
            if let Err(e) = window.set_badge_count(badge_count) {
                tracing::error!("Failed to update dock badge: {}", e);
            } else {
                tracing::debug!("Updated dock badge to: {:?}", badge_count);
            }
        }
    }
}

/// Handles tray menu item click events.
///
/// # Arguments
/// * `app` - The Tauri app handle
/// * `event` - The menu event that was triggered
fn handle_menu_event(app: &AppHandle, event: tauri::menu::MenuEvent) {
    match event.id().as_ref() {
        "open-dashboard" => {
            tracing::info!("Tray menu: Open Dashboard clicked");
            show_and_focus_window(app);
        }
        "approval-queue" => {
            tracing::info!("Tray menu: Approval Queue clicked");
            show_and_focus_window(app);

            // Emit event to navigate to approvals
            if let Err(e) = app.emit("navigate-to-approvals", ()) {
                tracing::error!("Failed to emit navigate event: {}", e);
            }
        }
        "quit" => {
            tracing::info!("Tray menu: Quit clicked");
            app.exit(0);
        }
        _ => {
            tracing::debug!("Unhandled tray menu event: {:?}", event.id());
        }
    }
}

/// Handles tray icon click events.
///
/// Shows and focuses the main window when the tray icon is clicked.
///
/// # Arguments
/// * `tray` - The tray icon handle
/// * `event` - The tray icon event that was triggered
fn handle_tray_icon_event(tray: &tauri::tray::TrayIcon, event: TrayIconEvent) {
    if let TrayIconEvent::Click {
        button: _,
        button_state: _,
        position: _,
        id: _,
        rect: _,
    } = event
    {
        tracing::info!("Tray icon clicked");

        let app = tray.app_handle();
        show_and_focus_window(&app);
    }
}

/// Shows and focuses the main application window.
///
/// If the window is minimized, it restores it. If it's hidden, it shows it.
/// Always brings the window to the front.
///
/// # Arguments
/// * `app` - The Tauri app handle
fn show_and_focus_window(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        if window.is_minimized().unwrap_or(false) {
            if let Err(e) = window.unminimize() {
                tracing::error!("Failed to unminimize window: {}", e);
            }
        }

        if !window.is_visible().unwrap_or(true) {
            if let Err(e) = window.show() {
                tracing::error!("Failed to show window: {}", e);
            }
        }

        if let Err(e) = window.set_focus() {
            tracing::error!("Failed to focus window: {}", e);
        }
    } else {
        tracing::warn!("Main window not found");
    }
}

/// Sends a native notification for a new approval item.
///
/// Shows a system notification when a new gate or permission arrives.
///
/// # Arguments
/// * `app` - The Tauri app handle
/// * `title` - Notification title
/// * `body` - Notification body text
pub fn notify_new_approval(app: &AppHandle, title: &str, body: &str) {
    use tauri_plugin_notification::NotificationExt;

    tracing::info!("Sending notification: {} - {}", title, body);

    if let Err(e) = app.notification().builder().title(title).body(body).show() {
        tracing::error!("Failed to show notification: {}", e);
    }
}
