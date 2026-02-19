use crate::bd::BdClient;
use crate::cache::BeadsCache;
use crate::health::HealthChecker;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::RwLock;

/// Shared application state for Tauri commands.
///
/// Holds all long-lived components that need to be shared across command handlers.
/// Uses `Arc` for thread-safe reference counting and `RwLock` for interior
/// mutability where needed.
pub struct AppState {
    /// Client for interacting with the bd CLI tool.
    pub bd_client: Arc<RwLock<BdClient>>,

    /// In-memory cache for bd issues, gates, and epics.
    pub beads_cache: Arc<RwLock<BeadsCache>>,

    /// Health checker for monitoring bd and cache status.
    pub health_checker: Arc<HealthChecker>,
}

impl AppState {
    /// Creates a new AppState.
    ///
    /// Initializes bd client using the current directory as workspace.
    ///
    /// # Errors
    /// Returns an error if any component cannot be initialized.
    pub fn new() -> Result<Self, Box<dyn std::error::Error>> {
        // Get current directory as default workspace for bd
        let workspace_path = std::env::current_dir()
            .map_err(|e| format!("Failed to get current directory: {}", e))?;

        tracing::info!(
            "Using current directory as bd workspace: {:?}",
            workspace_path
        );

        let bd_client_inner = BdClient::new(workspace_path)?;
        let bd_client_for_services = Arc::new(bd_client_inner.clone());
        let bd_client = Arc::new(RwLock::new(bd_client_inner));
        let beads_cache = BeadsCache::new()?;

        let health_checker = Arc::new(HealthChecker::new(
            bd_client_for_services,
            Arc::clone(&beads_cache),
        ));

        tracing::info!("AppState initialized with bd client and health checker");

        Ok(Self {
            bd_client,
            beads_cache,
            health_checker,
        })
    }

    /// Creates a new AppState with a custom bd workspace.
    ///
    /// # Arguments
    /// * `workspace` - Path to the bd workspace directory
    ///
    /// # Errors
    /// Returns an error if any component cannot be initialized.
    pub fn with_workspace(
        workspace: PathBuf,
    ) -> Result<Self, Box<dyn std::error::Error>> {
        tracing::info!("Using custom bd workspace: {:?}", workspace);

        let bd_client_inner = BdClient::new(workspace.clone())?;
        let bd_client_for_services = Arc::new(bd_client_inner.clone());
        let bd_client = Arc::new(RwLock::new(bd_client_inner));
        let beads_cache = BeadsCache::new()?;

        let health_checker = Arc::new(HealthChecker::new(
            bd_client_for_services,
            Arc::clone(&beads_cache),
        ));

        tracing::info!(workspace = ?workspace, "AppState initialized with custom workspace and health checker");

        Ok(Self {
            bd_client,
            beads_cache,
            health_checker,
        })
    }

    /// Gets a reference to the health checker.
    pub fn health_checker(&self) -> Result<Arc<HealthChecker>, String> {
        Ok(Arc::clone(&self.health_checker))
    }

    /// Switches the bd client to a new workspace.
    pub async fn switch_bd_client(&self, workspace: std::path::PathBuf) -> Result<(), String> {
        let new_client = BdClient::new(workspace)
            .map_err(|e| format!("Failed to create BdClient: {}", e))?;
        let mut bd_client = self.bd_client.write().await;
        *bd_client = new_client;
        Ok(())
    }
}
