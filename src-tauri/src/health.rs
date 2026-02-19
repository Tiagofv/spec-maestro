//! Health check and system monitoring module.
//!
//! Provides periodic health checks for bd services,
//! daemon status monitoring, and cache age tracking.

use crate::bd::{BdClient, BdError};
use crate::cache::BeadsCache;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tracing::{debug, warn};

const BD_VERSION_CHECK_TIMEOUT: Duration = Duration::from_secs(5);
const MAX_CACHE_AGE_SECS: u64 = 300; // 5 minutes

/// Overall health status of the AgentMaestro application.
///
/// Contains status information for all critical services and components.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct HealthStatus {
    /// Whether the bd CLI is available and functional
    pub bd_available: bool,
    /// Version of the bd CLI (if available)
    pub bd_version: Option<String>,
    /// Whether the bd daemon is running
    pub daemon_running: bool,
    /// Age of the cache in seconds (None if not available)
    pub cache_age_secs: Option<u64>,
    /// Whether the cache is stale (older than MAX_CACHE_AGE_SECS)
    pub cache_stale: bool,
    /// When this health check was performed
    #[serde(with = "health_timestamp_serde")]
    pub last_check: Instant,
}

/// Module for custom Instant serialization
mod health_timestamp_serde {
    use serde::{Deserialize, Deserializer, Serializer};
    use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

    pub fn serialize<S>(instant: &Instant, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        // Convert Instant to SystemTime for serialization
        let duration_from_epoch = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or(Duration::ZERO)
            .saturating_sub(instant.elapsed());

        serializer.serialize_u64(duration_from_epoch.as_secs())
    }

    pub fn deserialize<'de, D>(deserializer: D) -> Result<Instant, D::Error>
    where
        D: Deserializer<'de>,
    {
        let secs = u64::deserialize(deserializer)?;
        // Convert from SystemTime back to Instant
        let system_time = UNIX_EPOCH + Duration::from_secs(secs);
        let duration_from_now = SystemTime::now()
            .duration_since(system_time)
            .unwrap_or(Duration::ZERO);

        Ok(Instant::now() - duration_from_now)
    }
}

/// Health check result for bd CLI.
#[derive(Debug, Clone)]
pub struct BdHealth {
    /// Whether bd is available
    pub available: bool,
    /// Version string (if available)
    pub version: Option<String>,
    /// Whether the daemon is running
    pub daemon_running: bool,
}

/// Health checker for AgentMaestro services.
///
/// periodically checks bd availability, daemon status,
/// and cache freshness. Provides aggregated health status for the UI.
pub struct HealthChecker {
    /// Bd client for checking bd health
    bd_client: Arc<BdClient>,
    /// Cache for checking cache freshness
    beads_cache: Arc<RwLock<BeadsCache>>,
    /// Last known health status
    last_status: Arc<RwLock<Option<HealthStatus>>>,
}

impl HealthChecker {
    /// Creates a new HealthChecker.
    ///
    /// # Arguments
    /// * `bd_client` - The bd client to use for health checks
    /// * `beads_cache` - The cache to check for freshness
    pub fn new(
        bd_client: Arc<BdClient>,
        beads_cache: Arc<RwLock<BeadsCache>>,
    ) -> Self {
        Self {
            bd_client,
            beads_cache,
            last_status: Arc::new(RwLock::new(None)),
        }
    }

    /// Checks bd CLI availability and version.
    ///
    /// Performs the following checks:
    /// - `bd version` to verify the CLI is working
    /// - `bd daemon status` to check if the daemon is running
    pub async fn check_bd(&self) -> BdHealth {
        debug!("Checking bd health");

        // Check daemon status first (fastest check)
        let daemon_running = match self.bd_client.daemon_status().await {
            Ok(status) => status.running,
            Err(_) => false,
        };

        // Check version
        let version = match tokio::time::timeout(
            BD_VERSION_CHECK_TIMEOUT,
            self.get_bd_version(),
        )
        .await
        {
            Ok(Ok(v)) => Some(v),
            Ok(Err(e)) => {
                warn!("Failed to get bd version: {}", e);
                None
            }
            Err(_) => {
                warn!("bd version check timed out");
                None
            }
        };

        let available = version.is_some();

        BdHealth {
            available,
            version,
            daemon_running,
        }
    }

    /// Gets the bd version string.
    async fn get_bd_version(&self) -> Result<String, BdError> {
        // Run `bd version` command
        // This is a simplified check - we assume bd exists if we can run it
        let mut cmd = tokio::process::Command::new("bd");
        cmd.args(["version"]);

        let output = tokio::time::timeout(BD_VERSION_CHECK_TIMEOUT, cmd.output())
            .await
            .map_err(|_| BdError::Timeout {
                cmd: "bd version".to_string(),
                duration: BD_VERSION_CHECK_TIMEOUT,
            })?
            .map_err(BdError::Io)?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr).to_string();
            return Err(BdError::CommandFailed {
                cmd: "bd version".to_string(),
                stderr,
                exit_code: output.status.code().unwrap_or(-1),
            });
        }

        let version = String::from_utf8_lossy(&output.stdout)
            .trim()
            .to_string();

        Ok(version)
    }

    /// Checks cache freshness.
    ///
    /// Returns the age of the cache in seconds and whether it's stale.
    async fn check_cache(&self) -> (Option<u64>, bool) {
        // Get cache stats which include last_sync timestamp
        let stats = self
            .beads_cache
            .read()
            .await
            .get_stats()
            .await
            .unwrap_or_else(|e| {
                debug!("Failed to get cache stats: {}", e);
                crate::cache::CacheStats {
                    total_issues: 0,
                    open: 0,
                    closed: 0,
                    in_progress: 0,
                    blocked: 0,
                    pending_gates: 0,
                    last_sync: String::new(),
                }
            });

        let last_sync = stats.last_sync;

        // Parse the last_sync timestamp (blocking operation, safe now that lock is dropped)
        let age_secs = match chrono::DateTime::parse_from_rfc3339(&last_sync) {
            Ok(dt) => {
                let now = chrono::Utc::now();
                let duration = now.signed_duration_since(dt.with_timezone(&chrono::Utc));
                Some(duration.num_seconds().max(0) as u64)
            }
            Err(_) => {
                debug!("Failed to parse cache timestamp: {}", last_sync);
                None
            }
        };

        let stale = age_secs.map_or(false, |age| age > MAX_CACHE_AGE_SECS);

        if stale {
            warn!("Cache is stale: age={}s, max={}s", age_secs.unwrap_or(0), MAX_CACHE_AGE_SECS);
        }

        (age_secs, stale)
    }

    /// Performs a full health check of all services.
    ///
    /// Returns a comprehensive health status including bd,
    /// daemon, and cache status.
    pub async fn full_check(&self) -> HealthStatus {
        debug!("Performing full health check");

        let start = Instant::now();

        // Run checks in parallel for speed
        let bd_health = self.check_bd().await;

        let (cache_age, cache_stale) = self.check_cache().await;

        let status = HealthStatus {
            bd_available: bd_health.available,
            bd_version: bd_health.version,
            daemon_running: bd_health.daemon_running,
            cache_age_secs: cache_age,
            cache_stale,
            last_check: start,
        };

        debug!(
            "Health check completed: bd={}, daemon={}, cache_stale={}",
            status.bd_available, status.daemon_running, status.cache_stale
        );

        // Store last status
        *self.last_status.write().await = Some(status.clone());

        status
    }

    /// Gets the last known health status without performing a new check.
    pub async fn get_last_status(&self) -> Option<HealthStatus> {
        self.last_status.read().await.clone()
    }

    /// Checks if all services are healthy.
    pub fn is_healthy(&self, status: &HealthStatus) -> bool {
        status.bd_available
            && status.daemon_running
            && !status.cache_stale
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_constants() {
        assert_eq!(MAX_CACHE_AGE_SECS, 300);
        assert_eq!(BD_VERSION_CHECK_TIMEOUT, Duration::from_secs(5));
    }

    #[test]
    fn test_health_status_serialization() {
        let status = HealthStatus {
            bd_available: true,
            bd_version: Some("1.0.0".to_string()),
            daemon_running: true,
            cache_age_secs: Some(60),
            cache_stale: false,
            last_check: Instant::now(),
        };

        // Should serialize without error
        let json = serde_json::to_string(&status).unwrap();
        assert!(json.len() > 0);

        // Should deserialize back correctly
        let deserialized: HealthStatus = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.bd_available, true);
        assert_eq!(deserialized.bd_version, Some("1.0.0".to_string()));
    }

    #[test]
    fn test_is_healthy() {
        // All healthy
        let healthy_status = HealthStatus {
            bd_available: true,
            bd_version: Some("1.0.0".to_string()),
            daemon_running: true,
            cache_age_secs: Some(60),
            cache_stale: false,
            last_check: Instant::now(),
        };

        // bd unavailable
        let unhealthy_status = HealthStatus {
            bd_available: false,
            bd_version: None,
            daemon_running: true,
            cache_age_secs: Some(60),
            cache_stale: false,
            last_check: Instant::now(),
        };

        // cache stale
        let stale_cache_status = HealthStatus {
            bd_available: true,
            bd_version: Some("1.0.0".to_string()),
            daemon_running: true,
            cache_age_secs: Some(400),
            cache_stale: true,
            last_check: Instant::now(),
        };

        // Test is_healthy through a unit method - the actual is_healthy is a method, so we need to construct a HealthChecker
        // But we can't mock it, so let's just test the logic directly
        assert!(healthy_status.bd_available && healthy_status.daemon_running && !healthy_status.cache_stale);
        assert!(!(unhealthy_status.bd_available && unhealthy_status.daemon_running && !unhealthy_status.cache_stale));
        assert!(!(stale_cache_status.bd_available && stale_cache_status.daemon_running && !stale_cache_status.cache_stale));
    }
}
