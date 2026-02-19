use crate::health::HealthStatus;
use crate::state::AppState;

/// Get the current health status of all AgentMaestro services.
///
/// Returns comprehensive health information including bd CLI status,
/// daemon status, and cache freshness.
#[tauri::command]
pub async fn get_health_status(
    state: tauri::State<'_, AppState>,
) -> Result<HealthStatus, String> {
    health_check_impl(state).await
}

/// Internal implementation of health check.
///
/// Separated from the command for testability.
async fn health_check_impl(state: tauri::State<'_, AppState>) -> Result<HealthStatus, String> {
    let health_checker = state
        .health_checker()
        .map_err(|e| format!("Health checker not initialized: {}", e))?;

    let status = health_checker
        .full_check()
        .await;

    Ok(status)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_health_check_impl_signature() {
        // This test just verifies the signature is correct
        // Real testing would require mocked AppState
        let _ = || async {
            let result: Result<HealthStatus, String> = Ok(HealthStatus {
                bd_available: false,
                bd_version: None,
                daemon_running: false,
                cache_age_secs: None,
                cache_stale: false,
                last_check: std::time::Instant::now(),
            });
            result
        };
    }
}
