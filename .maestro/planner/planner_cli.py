"""Enhanced planner CLI module for maestro.

Integrates pattern analysis, task enrichment, and task linking
into the /maestro.plan command.
"""

from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional, Dict, Any
import json
import logging

from .pattern_analyzer import CodebasePatternAnalyzer, AnalysisScope
from .pattern_matcher import PatternMatcher
from .task_enricher import TaskEnricher, RawTask, EnrichedTask
from .task_linker import TaskLinker, TaskChain
from .task_sizing import TaskSizingValidator, Task as SizingTask
from .config import ConfigLoader, PlannerConfig


logger = logging.getLogger(__name__)


@dataclass
class PlanResult:
    """Result of enhanced planning."""
    enriched_tasks: List[EnrichedTask]
    chain: Optional[TaskChain]
    pattern_analysis_summary: Dict[str, Any]
    constitution_fallback_used: bool
    performance_metrics: Dict[str, Any]


class EnhancedPlanner:
    """Enhanced planner that generates detailed task specifications."""

    def __init__(self, config: Optional[PlannerConfig] = None):
        """Initialize the enhanced planner.
        
        Args:
            config: Optional planner configuration
        """
        self.config = config or ConfigLoader().load()
        
        # Initialize components
        self.analyzer = CodebasePatternAnalyzer()
        self.matcher = PatternMatcher()
        self.enricher = TaskEnricher(self.matcher)
        self.linker = TaskLinker()
        self.validator = TaskSizingValidator()
        
        # Performance monitoring
        self.metrics = {
            'phase_times': {},
            'cache_hits': 0,
            'cache_misses': 0,
        }

    def plan(self, feature_id: str, raw_tasks: List[RawTask]) -> PlanResult:
        """Generate an enhanced plan for a feature.
        
        Args:
            feature_id: ID of the feature to plan
            raw_tasks: List of raw task descriptions
            
        Returns:
            PlanResult with enriched tasks and chain
        """
        import time
        start_time = time.time()
        
        # Phase 1: Pattern Analysis
        phase_start = time.time()
        patterns = self._analyze_codebase(feature_id)
        self.metrics['phase_times']['analysis_ms'] = int((time.time() - phase_start) * 1000)
        
        # Phase 2: Pattern Matching
        phase_start = time.time()
        matched_patterns = self._match_patterns(patterns)
        self.metrics['phase_times']['matching_ms'] = int((time.time() - phase_start) * 1000)
        
        # Phase 3: Task Enrichment
        phase_start = time.time()
        enriched_tasks = self._enrich_tasks(raw_tasks, matched_patterns)
        self.metrics['phase_times']['enrichment_ms'] = int((time.time() - phase_start) * 1000)
        
        # Phase 4: Task Linking
        phase_start = time.time()
        chain = self._link_tasks(enriched_tasks)
        self.metrics['phase_times']['linking_ms'] = int((time.time() - phase_start) * 1000)
        
        # Phase 5: Validation
        phase_start = time.time()
        validation_result = self._validate_tasks(enriched_tasks)
        self.metrics['phase_times']['validation_ms'] = int((time.time() - phase_start) * 1000)
        
        # Total time
        self.metrics['total_ms'] = int((time.time() - start_time) * 1000)
        
        return PlanResult(
            enriched_tasks=enriched_tasks,
            chain=chain,
            pattern_analysis_summary={
                'total_patterns': len(patterns),
                'matched_patterns': len(matched_patterns),
                'files_analyzed': len(set(p.file_path for p in patterns)),
            },
            constitution_fallback_used=len(patterns) == 0,
            performance_metrics=self.metrics,
        )

    def _analyze_codebase(self, feature_id: str) -> List[Any]:
        """Analyze the codebase for patterns.
        
        Args:
            feature_id: Feature being planned
            
        Returns:
            List of CodePattern objects
        """
        logger.info(f"Analyzing codebase for feature: {feature_id}")
        
        scope = AnalysisScope(
            directories=self.config.analyzer.scope.directories,
            file_patterns=self.config.analyzer.scope.include_patterns,
            exclude_patterns=self.config.analyzer.scope.exclude_patterns,
        )
        
        patterns = self.analyzer.analyze(feature_id, scope)
        
        logger.info(f"Found {len(patterns)} patterns in codebase")
        return patterns

    def _match_patterns(self, patterns: List[Any]) -> List[Any]:
        """Match patterns against constitution.
        
        Args:
            patterns: CodePattern objects
            
        Returns:
            MatchedPattern objects
        """
        logger.info("Matching patterns against constitution")
        
        if not patterns:
            # Fallback to constitution-only patterns
            logger.info("No codebase patterns found, using constitution fallback")
            self.metrics['cache_misses'] += 1
            return self.matcher.get_fallback_patterns()
        
        matched = self.matcher.match_patterns(patterns)
        logger.info(f"Matched {len(matched)} patterns")
        return matched

    def _enrich_tasks(
        self, 
        raw_tasks: List[RawTask], 
        patterns: List[Any]
    ) -> List[EnrichedTask]:
        """Enrich raw tasks with code examples.
        
        Args:
            raw_tasks: Tasks to enrich
            patterns: Matched patterns
            
        Returns:
            EnrichedTask objects
        """
        logger.info(f"Enriching {len(raw_tasks)} tasks")
        
        enriched = []
        for task in raw_tasks:
            # Validate size
            sizing_task = SizingTask(description=task.description)
            result = self.validator.validate_size(sizing_task)
            
            # Add size to task before enrichment
            task_with_size = RawTask(
                title=task.title,
                description=task.description,
                scope={'size': result.size, **task.scope} if task.scope else {'size': result.size}
            )
            
            enriched_task = self.enricher.enrich(task_with_size, patterns)
            enriched.append(enriched_task)
        
        logger.info(f"Enriched {len(enriched)} tasks")
        return enriched

    def _link_tasks(self, tasks: List[EnrichedTask]) -> TaskChain:
        """Link tasks with dependencies.
        
        Args:
            tasks: Enriched tasks
            
        Returns:
            TaskChain with dependencies
        """
        logger.info(f"Linking {len(tasks)} tasks")
        
        chain = self.linker.link_tasks(tasks)
        
        logger.info(f"Created {len(chain.dependencies)} dependencies")
        return chain

    def _validate_tasks(self, tasks: List[EnrichedTask]) -> Dict[str, Any]:
        """Validate tasks meet requirements.
        
        Args:
            tasks: Tasks to validate
            
        Returns:
            Validation result
        """
        is_valid, oversized = self.linker.validate_task_size(tasks)
        
        return {
            'is_valid': is_valid,
            'oversized_tasks': oversized,
            'all_xs_or_s': all(t.size in ['XS', 'S'] for t in tasks),
        }

    def export_plan(
        self, 
        result: PlanResult, 
        output_path: Optional[Path] = None,
        format: str = 'json'
    ) -> str:
        """Export plan to file or string.
        
        Args:
            result: Plan result to export
            output_path: Optional output file path
            format: Output format ('json' or 'text')
            
        Returns:
            Exported plan as string (or empty if written to file)
        """
        if format == 'json':
            data = {
                'tasks': [
                    {
                        'id': t.id,
                        'title': t.title,
                        'description': t.description,
                        'size': t.size,
                        'files_to_modify': [
                            {
                                'path': f.path,
                                'change_type': f.change_type,
                                'code_example': f.code_example[:200] + '...' if len(f.code_example) > 200 else f.code_example,
                            }
                            for f in t.files_to_modify
                        ],
                        'acceptance_criteria': t.acceptance_criteria,
                    }
                    for t in result.enriched_tasks
                ],
                'chain': {
                    'tasks': result.chain.tasks if result.chain else [],
                    'dependencies': [
                        {'from': d.from_task, 'to': d.to_task, 'reason': d.reason}
                        for d in result.chain.dependencies if result.chain
                    ],
                } if result.chain else None,
                'summary': result.pattern_analysis_summary,
                'performance': result.performance_metrics,
            }
            
            json_str = json.dumps(data, indent=2)
            
            if output_path:
                output_path.write_text(json_str)
                logger.info(f"Plan exported to {output_path}")
                return ""
            
            return json_str
        
        elif format == 'text':
            lines = [
                "# Enhanced Plan",
                "",
                f"Total Tasks: {len(result.enriched_tasks)}",
                f"Patterns Found: {result.pattern_analysis_summary.get('total_patterns', 0)}",
                f"Constitution Fallback: {result.constitution_fallback_used}",
                "",
                "## Tasks",
                "",
            ]
            
            for task in result.enriched_tasks:
                lines.append(f"### {task.title} ({task.size})")
                lines.append("")
                lines.append(task.description)
                lines.append("")
                lines.append("**Files:**")
                for ref in task.files_to_modify:
                    lines.append(f"- {ref.path} ({ref.change_type})")
                lines.append("")
            
            text = "\n".join(lines)
            
            if output_path:
                output_path.write_text(text)
                return ""
            
            return text
        
        else:
            raise ValueError(f"Unknown format: {format}")


def create_planner(config_path: Optional[Path] = None) -> EnhancedPlanner:
    """Factory function to create an enhanced planner.
    
    Args:
        config_path: Optional path to config file
        
    Returns:
        Configured EnhancedPlanner instance
    """
    config = ConfigLoader(config_path).load() if config_path else None
    return EnhancedPlanner(config)
