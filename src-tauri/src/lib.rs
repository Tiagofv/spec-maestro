pub mod bd;
pub mod cache;
pub mod commands;
pub mod events;
pub mod health;
pub mod state;
mod tray;

use commands::{
    assign_issue, create_issue, get_cached_epic, get_cached_issue, get_dashboard_stats,
    get_dag, get_epic_status, get_health_status,
    get_issue, get_pending_gates, get_bd_health,
    list_epics, list_gates, list_issues, list_ready, list_workspaces,
    resolve_gate, start_bd_daemon, switch_workspace, update_issue_status,
};
use events::DashboardEvent;
use events::EventSource;
use state::AppState;
use std::time::Duration;
use tauri::{Emitter, Manager};
use tokio::time::interval;
use tracing::{error, info};
use tracing_subscriber::{fmt, EnvFilter};
use tray::setup_tray;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    // Initialize tracing
    fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new("info,agent_maestro=debug")),
        )
        .with_target(true)
        .with_thread_ids(true)
        .with_file(true)
        .with_line_number(true)
        .init();

    tracing::info!("Starting AgentMaestro");

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_notification::init())
        .setup(|app| {
            // Initialize shared application state inside setup where Tokio runtime is available
            let app_state = AppState::new().expect("Failed to initialize app state");

            let health_checker = app_state.health_checker().unwrap_or_else(|e| {
                panic!("Failed to get health checker: {}", e);
            });

            app.manage(app_state);

            // Set up system tray
            setup_tray(app.handle()).map_err(|e| {
                tracing::error!("Failed to setup system tray: {}", e);
                e
            })?;

            // Start background health monitoring task
            let app_handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                let mut last_known_health: Option<crate::health::HealthStatus> = None;
                let mut health_interval = interval(Duration::from_secs(30));

                loop {
                    health_interval.tick().await;

                    let current_health = health_checker.full_check().await;

                    // Emit HealthChanged event if health status changed
                    if last_known_health.as_ref() != Some(&current_health) {
                        info!(
                            "Health status changed: bd={}, daemon={}, cache_stale={}",
                            current_health.bd_available,
                            current_health.daemon_running,
                            current_health.cache_stale
                        );

                        let event = DashboardEvent::HealthChanged {
                            source: EventSource::Bd,
                            health: current_health.clone(),
                        };

                        if let Err(e) = app_handle.emit("dashboard-event", event) {
                            error!("Failed to emit HealthChanged event: {}", e);
                        }

                        last_known_health = Some(current_health);
                    }
                }
            });

            info!("Background health monitoring started (30s interval)");

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            // bd commands
            list_issues,
            get_issue,
            list_ready,
            list_gates,
            resolve_gate,
            get_dag,
            get_epic_status,
            list_workspaces,
            switch_workspace,
            get_dashboard_stats,
            get_bd_health,
            start_bd_daemon,
            get_cached_issue,
            list_epics,
            get_cached_epic,
            get_pending_gates,
            update_issue_status,
            assign_issue,
            create_issue,
            // health commands
            get_health_status,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
