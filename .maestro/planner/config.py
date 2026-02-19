"""Configuration loader for maestro planner.

Loads and validates configuration from .maestro/config.yaml.
"""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional
import yaml


@dataclass
class AnalyzerScope:
    """Configuration for analyzer scope."""
    directories: list[str] = field(default_factory=lambda: ['src', 'lib', 'app'])
    include_patterns: list[str] = field(default_factory=list)
    exclude_patterns: list[str] = field(default_factory=list)


@dataclass
class PatternConfig:
    """Configuration for pattern detection."""
    min_confidence: float = 0.7
    max_patterns_per_file: int = 10
    max_file_size: int = 1048576  # 1MB


@dataclass
class CacheConfig:
    """Configuration for pattern caching."""
    enabled: bool = True
    ttl_minutes: int = 60
    cache_dir: str = ".maestro/cache/patterns"
    max_cache_size_mb: int = 100


@dataclass
class PerformanceConfig:
    """Configuration for performance tuning."""
    parallel_workers: int = 4
    timeout_seconds: int = 300
    incremental: bool = False


@dataclass
class TaskSizingConfig:
    """Configuration for task sizing."""
    enforce_xs_s_only: bool = True
    xs_max_minutes: int = 120
    s_max_minutes: int = 360
    complexity_weights: dict[str, int] = field(default_factory=lambda: {
        'high': 30,
        'medium': 15,
        'low': 5
    })


@dataclass
class AnalyzerConfig:
    """Configuration for the analyzer."""
    scope: AnalyzerScope = field(default_factory=AnalyzerScope)


@dataclass
class PlannerConfig:
    """Main configuration for the planner."""
    analyzer: AnalyzerConfig = field(default_factory=AnalyzerConfig)
    patterns: PatternConfig = field(default_factory=PatternConfig)
    cache: CacheConfig = field(default_factory=CacheConfig)
    performance: PerformanceConfig = field(default_factory=PerformanceConfig)
    task_sizing: TaskSizingConfig = field(default_factory=TaskSizingConfig)


class ConfigLoader:
    """Loads and manages maestro configuration."""

    def __init__(self, config_path: Optional[Path] = None):
        """Initialize the config loader.
        
        Args:
            config_path: Path to config file. Defaults to .maestro/config.yaml
        """
        self.config_path = config_path or Path(".maestro/config.yaml")
        self._config: Optional[PlannerConfig] = None

    def load(self) -> PlannerConfig:
        """Load configuration from file.
        
        Returns:
            PlannerConfig instance with loaded settings
            
        Raises:
            FileNotFoundError: If config file doesn't exist
            yaml.YAMLError: If config file is invalid
        """
        if not self.config_path.exists():
            return PlannerConfig()

        with open(self.config_path, 'r') as f:
            data = yaml.safe_load(f) or {}

        planner_data = data.get('planner', {})
        
        # Parse scope
        scope_data = planner_data.get('analyzer', {}).get('scope', {})
        scope = AnalyzerScope(
            directories=scope_data.get('directories', ['src', 'lib', 'app']),
            include_patterns=scope_data.get('include_patterns', []),
            exclude_patterns=scope_data.get('exclude_patterns', [])
        )

        # Parse patterns config
        patterns_data = planner_data.get('patterns', {})
        patterns = PatternConfig(
            min_confidence=patterns_data.get('min_confidence', 0.7),
            max_patterns_per_file=patterns_data.get('max_patterns_per_file', 10),
            max_file_size=patterns_data.get('max_file_size', 1048576)
        )

        # Parse cache config
        cache_data = planner_data.get('cache', {})
        cache = CacheConfig(
            enabled=cache_data.get('enabled', True),
            ttl_minutes=cache_data.get('ttl_minutes', 60),
            cache_dir=cache_data.get('cache_dir', '.maestro/cache/patterns'),
            max_cache_size_mb=cache_data.get('max_cache_size_mb', 100)
        )

        # Parse performance config
        perf_data = planner_data.get('performance', {})
        performance = PerformanceConfig(
            parallel_workers=perf_data.get('parallel_workers', 4),
            timeout_seconds=perf_data.get('timeout_seconds', 300),
            incremental=perf_data.get('incremental', False)
        )

        # Parse task sizing config
        sizing_data = planner_data.get('task_sizing', {})
        task_sizing = TaskSizingConfig(
            enforce_xs_s_only=sizing_data.get('enforce_xs_s_only', True),
            xs_max_minutes=sizing_data.get('xs_max_minutes', 120),
            s_max_minutes=sizing_data.get('s_max_minutes', 360),
            complexity_weights=sizing_data.get('complexity_weights', {
                'high': 30,
                'medium': 15,
                'low': 5
            })
        )

        self._config = PlannerConfig(
            analyzer=AnalyzerConfig(scope=scope),
            patterns=patterns,
            cache=cache,
            performance=performance,
            task_sizing=task_sizing
        )

        return self._config

    def get(self) -> PlannerConfig:
        """Get loaded configuration, loading if necessary.
        
        Returns:
            PlannerConfig instance
        """
        if self._config is None:
            self._config = self.load()
        return self._config


def load_planner_config(config_path: Optional[Path] = None) -> PlannerConfig:
    """Convenience function to load planner configuration.
    
    Args:
        config_path: Optional path to config file
        
    Returns:
        PlannerConfig instance
    """
    loader = ConfigLoader(config_path)
    return loader.load()
