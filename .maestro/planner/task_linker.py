"""TaskLinker - creates dependencies between related tasks."""

from dataclasses import dataclass, field
from typing import List, Dict, Set, Tuple, Optional, Any
from pathlib import Path
import graphlib


@dataclass
class Dependency:
    """Represents a dependency between tasks."""
    from_task: str
    to_task: str
    reason: str = ""


@dataclass
class TaskChain:
    """A chain of linked tasks with dependencies."""
    id: str
    feature_id: str
    tasks: List[str] = field(default_factory=list)
    dependencies: List[Dependency] = field(default_factory=list)
    
    def get_ready_tasks(self, completed: Set[str]) -> List[str]:
        """Get tasks that are ready to execute (all deps completed).
        
        Args:
            completed: Set of completed task IDs
            
        Returns:
            List of task IDs that can run now
        """
        ready = []
        for task in self.tasks:
            if task in completed:
                continue
            
            # Check if all dependencies are completed
            deps = self.get_blockers(task)
            if all(d in completed for d in deps):
                ready.append(task)
        
        return ready
    
    def get_blockers(self, task_id: str) -> List[str]:
        """Get tasks that block the given task.
        
        Args:
            task_id: Task to get blockers for
            
        Returns:
            List of blocking task IDs
        """
        blockers = []
        for dep in self.dependencies:
            if dep.to_task == task_id:
                blockers.append(dep.from_task)
        return blockers


class TaskLinker:
    """Links tasks with explicit dependencies."""

    # Strategies for detecting dependencies
    DEPENDENCY_STRATEGIES = [
        'creation_order',
        'imports',
        'shared_resources',
        'interface_implementation',
        'test_dependency',
    ]

    def __init__(self):
        """Initialize the task linker."""
        self.strategies_enabled = {
            'creation_order': True,
            'imports': True,
            'shared_resources': True,
            'interface_implementation': True,
            'test_dependency': True,
        }

    def link_tasks(
        self, 
        tasks: List[Any], 
        config: Optional[Dict] = None
    ) -> TaskChain:
        """Link tasks with dependencies.
        
        Args:
            tasks: List of EnrichedTask objects
            config: Optional configuration for strategies
            
        Returns:
            TaskChain with linked tasks and dependencies
        """
        if config:
            self.strategies_enabled.update(config)
        
        dependencies = []
        
        # Apply each enabled strategy
        if self.strategies_enabled.get('creation_order'):
            dependencies.extend(self._apply_creation_order_strategy(tasks))
        
        if self.strategies_enabled.get('imports'):
            dependencies.extend(self._apply_import_strategy(tasks))
        
        if self.strategies_enabled.get('shared_resources'):
            dependencies.extend(self._apply_shared_resource_strategy(tasks))
        
        if self.strategies_enabled.get('interface_implementation'):
            dependencies.extend(self._apply_interface_strategy(tasks))
        
        if self.strategies_enabled.get('test_dependency'):
            dependencies.extend(self._apply_test_strategy(tasks))
        
        # Remove duplicates and validate
        dependencies = self._deduplicate_dependencies(dependencies)
        
        # Validate no cycles
        self._validate_no_cycles(dependencies, [t.id for t in tasks])
        
        return TaskChain(
            id=f"chain-{len(tasks)}",
            feature_id=tasks[0].id.split('-')[0] if tasks else "",
            tasks=[t.id for t in tasks],
            dependencies=dependencies,
        )

    def detect_dependencies(
        self, 
        task: Any, 
        all_tasks: List[Any]
    ) -> List[Tuple[str, str]]:
        """Detect dependencies for a single task.
        
        Args:
            task: Task to find dependencies for
            all_tasks: All tasks to check against
            
        Returns:
            List of (blocking_task_id, dependent_task_id) tuples
        """
        dependencies = []
        
        for other_task in all_tasks:
            if other_task.id == task.id:
                continue
            
            # Check various dependency conditions
            if self._depends_on(task, other_task):
                dependencies.append((other_task.id, task.id))
        
        return dependencies

    def _depends_on(self, task: Any, potential_blocker: Any) -> bool:
        """Check if task depends on potential_blocker.
        
        Args:
            task: Task that would be dependent
            potential_blocker: Task that might block
            
        Returns:
            True if there's a dependency
        """
        task_files = set(ref.path for ref in task.files_to_modify)
        blocker_files = set(ref.path for ref in potential_blocker.files_to_modify)
        
        # If blocker creates a file that task modifies, there's a dependency
        for ref in potential_blocker.files_to_modify:
            if ref.change_type == 'create':
                if any(blocker_file in task_file for task_file in task_files 
                       for blocker_file in [ref.path]):
                    return True
        
        return False

    def _apply_creation_order_strategy(
        self, 
        tasks: List[Any]
    ) -> List[Dependency]:
        """Apply creation order dependency strategy.
        
        Tasks that create files should complete before tasks that modify them.
        
        Args:
            tasks: List of tasks
            
        Returns:
            List of dependencies
        """
        dependencies = []
        
        # Group tasks by file
        file_tasks: Dict[str, List[Tuple[str, Any]]] = {}
        for task in tasks:
            for ref in task.files_to_modify:
                if ref.path not in file_tasks:
                    file_tasks[ref.path] = []
                file_tasks[ref.path].append((task.id, task))
        
        # Create dependencies: create -> modify
        for file_path, task_list in file_tasks.items():
            create_tasks = [t for t in task_list if t[1].files_to_modify[0].change_type == 'create']
            modify_tasks = [t for t in task_list if t[1].files_to_modify[0].change_type == 'modify']
            
            for create_task_id, _ in create_tasks:
                for modify_task_id, _ in modify_tasks:
                    dependencies.append(Dependency(
                        from_task=create_task_id,
                        to_task=modify_task_id,
                        reason=f"create_order: {file_path} must be created before modification"
                    ))
        
        return dependencies

    def _apply_import_strategy(
        self, 
        tasks: List[Any]
    ) -> List[Dependency]:
        """Apply import-based dependency strategy.
        
        If task A imports from file B, task B's implementation should complete first.
        
        Args:
            tasks: List of tasks
            
        Returns:
            List of dependencies
        """
        dependencies = []
        
        for task in tasks:
            task_files = set(ref.path for ref in task.files_to_modify)
            
            # Check other tasks
            for other_task in tasks:
                if other_task.id == task.id:
                    continue
                
                other_files = [ref.path for ref in other_task.files_to_modify]
                
                # Simple heuristic: if file names suggest dependency
                for task_file in task_files:
                    for other_file in other_files:
                        if self._is_import_dependent(task_file, other_file):
                            dependencies.append(Dependency(
                                from_task=other_task.id,
                                to_task=task.id,
                                reason=f"import: {task_file} likely depends on {other_file}"
                            ))
        
        return dependencies

    def _is_import_dependent(self, file1: str, file2: str) -> bool:
        """Check if file1 likely imports from file2.
        
        Args:
            file1: Potentially importing file
            file2: Potentially imported file
            
        Returns:
            True if there's likely an import relationship
        """
        # Same directory imports
        p1 = Path(file1)
        p2 = Path(file2)
        
        if p1.parent == p2.parent:
            # Same directory - check module names
            return p1.stem != p2.stem
        
        # Check for common patterns like utils, helpers, etc.
        common_dirs = {'utils', 'helpers', 'lib', 'core', 'common'}
        if common_dirs.intersection(set(p1.parts)) & common_dirs.intersection(set(p2.parts)):
            return True
        
        return False

    def _apply_shared_resource_strategy(
        self, 
        tasks: List[Any]
    ) -> List[Dependency]:
        """Apply shared resource dependency strategy.
        
        Tasks using shared resources (config, database) may have ordering constraints.
        
        Args:
            tasks: List of tasks
            
        Returns:
            List of dependencies
        """
        # Shared resources that might need ordering
        shared_patterns = [
            'config',
            'settings',
            'database',
            'db',
            'schema',
            'migration',
        ]
        
        dependencies = []
        
        for i, task in enumerate(tasks):
            task_files = [ref.path.lower() for ref in task.files_to_modify]
            
            # Check against other tasks
            for j, other_task in enumerate(tasks[:i]):
                other_files = [ref.path.lower() for ref in other_task.files_to_modify]
                
                # If both touch shared resources, order matters
                task_uses_shared = any(any(p in f for p in shared_patterns) for f in task_files)
                other_uses_shared = any(any(p in f for p in shared_patterns) for f in other_files)
                
                if task_uses_shared and other_uses_shared:
                    dependencies.append(Dependency(
                        from_task=other_task.id,
                        to_task=task.id,
                        reason="shared_resource: both tasks access shared resources"
                    ))
        
        return dependencies

    def _apply_interface_strategy(
        self, 
        tasks: List[Any]
    ) -> List[Dependency]:
        """Apply interface/implementation dependency strategy.
        
        Interface definitions should complete before implementations.
        
        Args:
            tasks: List of tasks
            
        Returns:
            List of dependencies
        """
        dependencies = []
        
        for task in tasks:
            task_files = [ref.path for ref in task.files_to_modify]
            
            # Check for interface files
            for file_path in task_files:
                if 'interface' in Path(file_path).stem.lower() or 'interface' in file_path.lower():
                    # This task defines an interface - other tasks implementing it depend on it
                    for other_task in tasks:
                        if other_task.id == task.id:
                            continue
                        other_files = [ref.path for ref in other_task.files_to_modify]
                        # Check if other task implements this interface
                        if any(self._is_implementation(file_path, of) for of in other_files):
                            dependencies.append(Dependency(
                                from_task=task.id,
                                to_task=other_task.id,
                                reason=f"interface: {file_path} interface before implementation"
                            ))
        
        return dependencies

    def _is_implementation(self, interface_file: str, impl_file: str) -> bool:
        """Check if impl_file implements interface_file.
        
        Args:
            interface_file: Path to interface file
            impl_file: Path to potential implementation
            
        Returns:
            True if impl_file implements interface_file
        """
        # Simple heuristic: similar names in same or nearby directories
        int_stem = Path(interface_file).stem.replace('interface', '').replace('Interface', '')
        impl_stem = Path(impl_file).stem.replace('impl', '').replace('Impl', '')
        
        return int_stem.lower() in impl_stem.lower() or impl_stem.lower() in int_stem.lower()

    def _apply_test_strategy(
        self, 
        tasks: List[Any]
    ) -> List[Dependency]:
        """Apply test dependency strategy.
        
        Implementation tasks should complete before their tests.
        
        Args:
            tasks: List of tasks
            
        Returns:
            List of dependencies
        """
        dependencies = []
        
        for task in tasks:
            # Skip if already a test task
            if 'test' in task.title.lower():
                continue
            
            task_files = set(Path(ref.path).stem for ref in task.files_to_modify)
            
            for other_task in tasks:
                if other_task.id == task.id:
                    continue
                
                # Check if other is a test for this task
                if 'test' not in other_task.title.lower():
                    continue
                
                other_files = [Path(ref.path).stem for ref in other_task.files_to_modify]
                
                # Check if test file name matches implementation
                if any(tf in of.replace('test', '').replace('.test', '') for tf in task_files for of in other_files):
                    dependencies.append(Dependency(
                        from_task=task.id,
                        to_task=other_task.id,
                        reason="test: implementation before tests"
                    ))
        
        return dependencies

    def _deduplicate_dependencies(
        self, 
        dependencies: List[Dependency]
    ) -> List[Dependency]:
        """Remove duplicate dependencies.
        
        Args:
            dependencies: List of dependencies
            
        Returns:
            Deduplicated list
        """
        seen = set()
        unique = []
        
        for dep in dependencies:
            key = (dep.from_task, dep.to_task)
            if key not in seen:
                seen.add(key)
                unique.append(dep)
        
        return unique

    def _validate_no_cycles(
        self, 
        dependencies: List[Dependency],
        task_ids: List[str]
    ) -> None:
        """Validate that there are no circular dependencies.
        
        Args:
            dependencies: List of dependencies
            task_ids: All task IDs
            
        Raises:
            ValueError: If circular dependencies detected
        """
        # Build graph
        graph: Dict[str, Set[str]] = {tid: set() for tid in task_ids}
        
        for dep in dependencies:
            if dep.from_task in graph and dep.to_task in graph:
                graph[dep.from_task].add(dep.to_task)
        
        # Try to detect cycles using graphlib
        try:
            ts = graphlib.TopologicalSorter(graph)
            ts.prepare()
        except graphlib.CycleError as e:
            raise ValueError(f"Circular dependency detected: {e}")

    def validate_task_size(
        self, 
        tasks: List[Any], 
        max_size: str = 'S'
    ) -> Tuple[bool, List[str]]:
        """Validate that all tasks are within size limits.
        
        Args:
            tasks: List of tasks
            max_size: Maximum allowed size ('XS' or 'S')
            
        Returns:
            Tuple of (is_valid, list of oversized task IDs)
        """
        oversized = []
        
        for task in tasks:
            if task.size > max_size:
                oversized.append(task.id)
        
        return (len(oversized) == 0, oversized)
