"""TaskEnricher - adds code examples and file references to tasks."""

from dataclasses import dataclass, field
from typing import List, Optional, Dict, Any
from pathlib import Path


@dataclass
class FileReference:
    """Represents a file that needs to be modified."""
    path: str
    change_type: str  # 'create', 'modify', 'delete'
    code_example: str = ""
    pattern_reference: str = ""


@dataclass 
class EnrichedTask:
    """A task enriched with code examples and file references."""
    id: str
    title: str
    description: str
    size: str  # 'XS' or 'S'
    files_to_modify: List[FileReference] = field(default_factory=list)
    dependencies: List[str] = field(default_factory=list)
    blocked_by: List[str] = field(default_factory=list)
    constitution_rules: List[str] = field(default_factory=list)
    estimated_effort: str = ""
    acceptance_criteria: List[str] = field(default_factory=list)


@dataclass
class RawTask:
    """A raw task before enrichment."""
    title: str
    description: str
    scope: Optional[Dict[str, Any]] = None


class TaskEnricher:
    """Enriches raw tasks with code examples and file references."""

    def __init__(self, pattern_matcher=None):
        """Initialize the enricher.
        
        Args:
            pattern_matcher: Optional PatternMatcher instance for pattern lookup
        """
        self.pattern_matcher = pattern_matcher

    def enrich(self, task: RawTask, patterns: List[Any]) -> EnrichedTask:
        """Enrich a raw task with code examples and file references.
        
        Args:
            task: Raw task to enrich
            patterns: List of CodePattern objects from analysis
            
        Returns:
            EnrichedTask with code examples and file references
        """
        # Extract file references from task description and patterns
        file_refs = self.extract_file_references(task, patterns)
        
        # Generate code examples for the task
        code_examples = self.generate_code_examples(task, patterns, file_refs)
        
        # Determine task size based on complexity
        size = self._estimate_size(task, file_refs)
        
        # Extract acceptance criteria from description
        acceptance_criteria = self._extract_acceptance_criteria(task.description)
        
        enriched = EnrichedTask(
            id=self._generate_task_id(task.title),
            title=task.title,
            description=task.description,
            size=size,
            files_to_modify=file_refs,
            acceptance_criteria=acceptance_criteria,
            estimated_effort=f"{size} (task requires focused implementation)"
        )
        
        # Add code examples to file references
        for ref in enriched.files_to_modify:
            if ref.path in code_examples:
                ref.code_example = code_examples[ref.path]
        
        return enriched

    def extract_file_references(
        self, 
        task: RawTask, 
        patterns: List[Any]
    ) -> List[FileReference]:
        """Extract file references from task and patterns.
        
        Args:
            task: Raw task to analyze
            patterns: Available patterns from codebase analysis
            
        Returns:
            List of FileReference objects
        """
        references = []
        
        # Extract explicit file mentions from description
        mentioned_files = self._extract_file_mentions(task.description)
        
        for file_path in mentioned_files:
            change_type = self._determine_change_type(file_path, task.description)
            pattern_ref = self._find_matching_pattern(file_path, patterns)
            
            ref = FileReference(
                path=file_path,
                change_type=change_type,
                pattern_reference=pattern_ref
            )
            references.append(ref)
        
        # Also add files from patterns if they're relevant
        for pattern in patterns:
            if self._is_pattern_relevant(pattern, task.description):
                if not any(r.path == pattern.file_path for r in references):
                    ref = FileReference(
                        path=pattern.file_path,
                        change_type='modify',
                        pattern_reference=f"{pattern.pattern_type}: {pattern.signature}"
                    )
                    references.append(ref)
        
        return references

    def generate_code_examples(
        self,
        task: RawTask,
        patterns: List[Any],
        file_refs: List[FileReference]
    ) -> Dict[str, str]:
        """Generate code examples for the task.
        
        Args:
            task: Raw task
            patterns: Available patterns
            file_refs: File references for this task
            
        Returns:
            Dict mapping file paths to code examples
        """
        examples = {}
        
        for ref in file_refs:
            # Find matching pattern for this file
            matching_pattern = None
            for pattern in patterns:
                if pattern.file_path == ref.path:
                    matching_pattern = pattern
                    break
            
            if matching_pattern and matching_pattern.example_code:
                # Use actual code from codebase
                example = self._format_code_example(
                    matching_pattern.example_code,
                    matching_pattern.language,
                    is_working_code=True
                )
                examples[ref.path] = example
            else:
                # Generate pattern-based example
                example = self._generate_pattern_example(task, ref)
                if example:
                    examples[ref.path] = example
        
        return examples

    def _format_code_example(
        self, 
        code: str, 
        language: str,
        is_working_code: bool = True
    ) -> str:
        """Format a code example with proper markdown.
        
        Args:
            code: The code to format
            language: Programming language
            is_working_code: Whether this is actual working code
            
        Returns:
            Formatted code example string
        """
        source = "Based on actual codebase" if is_working_code else "Pattern template"
        
        return f"""```
```{language}
{code}
```

{source}"""

    def _generate_pattern_example(self, task: RawTask, ref: FileReference) -> str:
        """Generate a pattern-based code example when no actual code exists.
        
        Args:
            task: The task context
            ref: File reference
            
        Returns:
            Generated code example or empty string
        """
        # Determine what kind of code to generate based on file extension
        ext = Path(ref.path).suffix
        
        if ref.change_type == 'create':
            if ext == '.py':
                return self._generate_python_scaffold(ref.path)
            elif ext in ['.ts', '.tsx', '.js', '.jsx']:
                return self._generate_typescript_scaffold(ref.path)
        
        return ""

    def _generate_python_scaffold(self, file_path: str) -> str:
        """Generate Python file scaffold.
        
        Args:
            file_path: Path to the file
            
        Returns:
            Python code scaffold
        """
        module_name = Path(file_path).stem
        
        return f"""```python
\"\"\"
{module_name} module.

Add module description here.
\"\"\"

from typing import Optional


class {module_name.title().replace('_', '')}:
    \"\"\"Main class for {module_name}.\"\"\"
    
    def __init__(self):
        self._initialized = False
    
    def process(self, data):
        \"\"\"Process the given data.\"\"\"
        # Implementation here
        pass
```"""

    def _generate_typescript_scaffold(self, file_path: str) -> str:
        """Generate TypeScript file scaffold.
        
        Args:
            file_path: Path to the file
            
        Returns:
            TypeScript code scaffold
        """
        module_name = Path(file_path).stem
        
        return f"""```typescript
interface {module_name.title()}Config {{
  option?: string;
}}

class {module_name.title()} {{
  private config: {module_name.title()}Config;
  
  constructor(config: {module_name.title()}Config = {{}}) {{
    this.config = config;
  }}
  
  process(data: unknown): unknown {{
    // Implementation here
    return data;
  }}
}}

export {{ {module_name.title()} }};
```"""

    def _extract_file_mentions(self, description: str) -> List[str]:
        """Extract file path mentions from description.
        
        Args:
            description: Task description
            
        Returns:
            List of file paths mentioned
        """
        import re
        
        # Common file path patterns
        patterns = [
            r'[\w/\\]+\.(py|ts|tsx|js|jsx|go|rs|yaml|json|md)',
            r'[\w/\\]+/[\w/\\]+\.(py|ts|tsx|js|jsx|go|rs|yaml|json|md)',
        ]
        
        files = set()
        for pattern in patterns:
            matches = re.findall(pattern, description)
            files.update(matches)
        
        return list(files)

    def _determine_change_type(self, file_path: str, description: str) -> str:
        """Determine if a file should be created, modified, or deleted.
        
        Args:
            file_path: Path to the file
            description: Task description
            
        Returns:
            'create', 'modify', or 'delete'
        """
        desc_lower = description.lower()
        
        if 'create' in desc_lower or 'new' in desc_lower or 'add' in desc_lower:
            return 'create'
        elif 'delete' in desc_lower or 'remove' in desc_lower:
            return 'delete'
        else:
            return 'modify'

    def _find_matching_pattern(self, file_path: str, patterns: List[Any]) -> str:
        """Find a pattern that matches the given file.
        
        Args:
            file_path: Path to find matching pattern for
            patterns: Available patterns
            
        Returns:
            Pattern reference string or empty string
        """
        for pattern in patterns:
            if pattern.file_path == file_path:
                return f"{pattern.pattern_type}: {pattern.signature}"
        return ""

    def _is_pattern_relevant(self, pattern: Any, description: str) -> bool:
        """Check if a pattern is relevant to the task.
        
        Args:
            pattern: Pattern to check
            description: Task description
            
        Returns:
            True if pattern is relevant
        """
        desc_lower = description.lower()
        
        # Check if any tags or pattern type matches description keywords
        for tag in pattern.tags:
            if tag in desc_lower:
                return True
        
        if pattern.pattern_type in desc_lower:
            return True
            
        return False

    def _estimate_size(self, task: RawTask, file_refs: List[FileReference]) -> str:
        """Estimate task size based on complexity.
        
        Args:
            task: Raw task
            file_refs: Number of files to modify
            
        Returns:
            'XS' or 'S'
        """
        # Simple heuristic: XS for 1-2 files, S for 3+
        if len(file_refs) <= 2:
            return 'XS'
        return 'S'

    def _extract_acceptance_criteria(self, description: str) -> List[str]:
        """Extract acceptance criteria from description.
        
        Args:
            description: Task description
            
        Returns:
            List of acceptance criteria
        """
        criteria = []
        
        # Look for bullet points or numbered lists
        import re
        
        # Match bullet points
        bullets = re.findall(r'[-*]\s*([^\n]+)', description)
        criteria.extend([c.strip() for c in bullets if c.strip()])
        
        # Match numbered items
        numbered = re.findall(r'\d+\.\s*([^\n]+)', description)
        criteria.extend([n.strip() for n in numbered if n.strip()])
        
        return criteria[:10]  # Limit to 10 criteria

    def _generate_task_id(self, title: str) -> str:
        """Generate a task ID from title.
        
        Args:
            title: Task title
            
        Returns:
            Generated task ID
        """
        import hashlib
        # Create short hash from title
        hash_obj = hashlib.md5(title.encode())
        return f"task-{hash_obj.hexdigest()[:8]}"
