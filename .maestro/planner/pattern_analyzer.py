"""CodebasePatternAnalyzer - Scans codebase and extracts patterns.

This module provides functionality to analyze codebases and extract patterns
using tree-sitter or regex-based parsing for multiple languages.
"""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional
import fnmatch
import re
import uuid


@dataclass
class CodePattern:
    """Represents a code pattern extracted from the codebase.
    
    Attributes:
        id: Unique identifier for the pattern
        file_path: Path to the file containing the pattern
        language: Programming language (e.g., 'python', 'typescript', 'go')
        pattern_type: Type of pattern (e.g., 'function', 'class', 'import')
        signature: The pattern signature (e.g., function signature, class name)
        example_code: Example code snippet showing the pattern
        context: Additional context about the pattern
        confidence: Confidence score (0.0 to 1.0) based on pattern quality
        tags: List of tags for categorization
    """
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    file_path: str = ""
    language: str = ""
    pattern_type: str = ""
    signature: str = ""
    example_code: str = ""
    context: str = ""
    confidence: float = 0.0
    tags: list[str] = field(default_factory=list)

    def __post_init__(self):
        """Validate confidence score is within bounds."""
        if not 0.0 <= self.confidence <= 1.0:
            raise ValueError(f"Confidence must be between 0.0 and 1.0, got {self.confidence}")


@dataclass
class AnalysisScope:
    """Configuration for codebase analysis scope.
    
    Attributes:
        directories: List of directories to scan
        file_patterns: Glob patterns for files to include (e.g., ['*.py', '*.ts'])
        exclude_patterns: Patterns for files/directories to exclude
        max_file_size: Maximum file size in bytes (default 1MB)
    """
    directories: list[str] = field(default_factory=list)
    file_patterns: list[str] = field(default_factory=lambda: ['*.py', '*.ts', '*.js', '*.go', '*.rs'])
    exclude_patterns: list[str] = field(default_factory=lambda: [
        'node_modules', '.git', '__pycache__', '*.pyc', '.venv', 'venv',
        'dist', 'build', 'target', '.cargo'
    ])
    max_file_size: int = 1_048_576  # 1MB


class CodebasePatternAnalyzer:
    """Analyzes codebase files to extract code patterns.
    
    Supports multiple languages and uses configurable scope for scanning.
    Extracts patterns with confidence scores and provides metadata.
    """

    # Language extensions mapping
    LANGUAGE_EXTENSIONS = {
        '.py': 'python',
        '.ts': 'typescript',
        '.tsx': 'typescript',
        '.js': 'javascript',
        '.jsx': 'javascript',
        '.go': 'go',
        '.rs': 'rust',
    }

    # Pattern extraction regex for each language
    PATTERNS = {
        'python': {
            'function': r'^(?:async\s+)?def\s+(\w+)\s*\(([^)]*)\)(?:\s*->\s*[^:]+)?:',
            'class': r'^class\s+(\w+)(?:\([^)]*\))?:',
            'import': r'^(?:from\s+([\w.]+)\s+import|import\s+([\w.]+))',
            'decorator': r'^@(\w+(?:\.[\w]+)*)',
        },
        'typescript': {
            'function': r'(?:export\s+)?(?:async\s+)?(?:function\s+(\w+)|const\s+(\w+)\s*=\s*(?:async\s+)?(?:\([^)]*\)|<[^>]*>)\s*=>)',
            'class': r'(?:export\s+)?(?:abstract\s+)?class\s+(\w+)(?:\s+extends\s+\w+)?(?:\s+implements\s+[^{]+)?',
            'interface': r'(?:export\s+)?interface\s+(\w+)(?:\s+extends\s+\w+)?',
            'import': r'^import\s+(?:type\s+)?\{?[^}]*\}?\s*from\s+[\'"]([^\'"]+)[\'"]',
        },
        'javascript': {
            'function': r'(?:export\s+)?(?:async\s+)?(?:function\s*(\w*)|const\s+(\w+)\s*=\s*(?:async\s+)?(?:\([^)]*\)\s*=>))',
            'class': r'(?:export\s+)?class\s+(\w+)(?:\s+extends\s+\w+)?',
            'import': r'^import\s+(?:\{[^}]*\}|\w+)\s*from\s+[\'"]([^\'"]+)[\'"]',
        },
        'go': {
            'function': r'^func\s+(?:\([^)]*\)\s+)?(\w+)\s*\(([^)]*)\)',
            'struct': r'^type\s+(\w+)\s+struct',
            'interface': r'^type\s+(\w+)\s+interface',
            'import': r'^import\s+(?:\(\s*)?[\'"]([^\'"]+)[\'"]',
        },
        'rust': {
            'function': r'^(?:pub\s+)?(?:async\s+)?(?:unsafe\s+)?fn\s+(\w+)\s*<[^>]*>?\s*\(([^)]*)\)',
            'struct': r'^(?:pub\s+)?struct\s+(\w+)(?:<[^>]*>)?',
            'trait': r'^(?:pub\s+)?trait\s+(\w+)(?:<[^>]*>)?',
            'impl': r'^(?:pub\s+)?impl(?:<[^>]*>)?\s+(?:\w+\s+for\s+)?(\w+)',
            'import': r'^use\s+([\w:]+)',
        },
    }

    def __init__(self):
        """Initialize the analyzer."""
        self._compiled_patterns: dict[str, dict[str, re.Pattern]] = {}
        self._compile_patterns()

    def _compile_patterns(self) -> None:
        """Compile regex patterns for performance."""
        for lang, patterns in self.PATTERNS.items():
            self._compiled_patterns[lang] = {
                name: re.compile(pattern, re.MULTILINE)
                for name, pattern in patterns.items()
            }

    def analyze(
        self,
        feature_id: str,
        scope: Optional[AnalysisScope] = None
    ) -> list[CodePattern]:
        """Analyze codebase and extract patterns.
        
        Args:
            feature_id: Identifier for the feature being analyzed
            scope: Analysis configuration. Uses defaults if not provided.
            
        Returns:
            List of CodePattern objects with extracted patterns
            
        Raises:
            ValueError: If scope configuration is invalid
        """
        if scope is None:
            scope = AnalysisScope()

        # Validate scope
        if not scope.directories:
            # If no directories specified, return empty list (graceful handling)
            return []

        patterns: list[CodePattern] = []
        
        for directory in scope.directories:
            dir_path = Path(directory)
            if not dir_path.exists():
                continue
            
            files = self._scan_files(dir_path, scope)
            for file_path in files:
                file_patterns = self._extract_patterns_from_file(file_path, scope)
                patterns.extend(file_patterns)

        return patterns

    def _scan_files(self, directory: Path, scope: AnalysisScope) -> list[Path]:
        """Scan directory for files matching patterns.
        
        Args:
            directory: Directory to scan
            scope: Analysis scope configuration
            
        Returns:
            List of file paths that match the criteria
        """
        files: list[Path] = []
        
        for pattern in scope.file_patterns:
            matched_files = directory.rglob(pattern)
            for file_path in matched_files:
                # Check exclusion patterns
                if self._is_excluded(file_path, scope.exclude_patterns):
                    continue
                
                # Check file size
                try:
                    if file_path.stat().st_size > scope.max_file_size:
                        continue
                except (OSError, IOError):
                    continue
                
                files.append(file_path)
        
        return files

    def _is_excluded(self, file_path: Path, exclude_patterns: list[str]) -> bool:
        """Check if file should be excluded based on patterns.
        
        Args:
            file_path: Path to check
            exclude_patterns: List of exclusion patterns
            
        Returns:
            True if file should be excluded
        """
        path_str = str(file_path)
        parts = file_path.parts
        
        for pattern in exclude_patterns:
            # Check if any part of the path matches
            for part in parts:
                if fnmatch.fnmatch(part, pattern):
                    return True
            
            # Also check full path
            if fnmatch.fnmatch(path_str, f'*{pattern}*'):
                return True
        
        return False

    def _get_language(self, file_path: Path) -> Optional[str]:
        """Determine language from file extension.
        
        Args:
            file_path: File to check
            
        Returns:
            Language identifier or None if unsupported
        """
        ext = file_path.suffix.lower()
        return self.LANGUAGE_EXTENSIONS.get(ext)

    def _extract_patterns_from_file(
        self,
        file_path: Path,
        scope: AnalysisScope
    ) -> list[CodePattern]:
        """Extract patterns from a single file.
        
        Args:
            file_path: File to analyze
            scope: Analysis scope configuration
            
        Returns:
            List of patterns found in the file
        """
        language = self._get_language(file_path)
        if not language:
            return []

        try:
            content = file_path.read_text(encoding='utf-8', errors='ignore')
        except (OSError, IOError):
            return []

        patterns: list[CodePattern] = []
        lines = content.split('\n')
        
        lang_patterns = self._compiled_patterns.get(language, {})
        
        for pattern_type, regex in lang_patterns.items():
            for match in regex.finditer(content):
                # Get the matched signature
                groups = [g for g in match.groups() if g is not None]
                signature = groups[0] if groups else match.group(0).strip()
                
                # Extract example code (surrounding context)
                start_pos = match.start()
                end_pos = match.end()
                
                # Find line numbers
                start_line = content[:start_pos].count('\n') + 1
                end_line = content[:end_pos].count('\n') + 1
                
                # Extract context (3 lines before and after)
                context_start = max(0, start_line - 4)
                context_end = min(len(lines), end_line + 3)
                example_lines = lines[context_start:context_end]
                example_code = '\n'.join(example_lines).strip()
                
                # Truncate if too long
                if len(example_code) > 500:
                    example_code = example_code[:497] + '...'
                
                # Calculate confidence
                confidence = self._calculate_confidence(
                    pattern_type, signature, example_code, language
                )
                
                # Generate tags
                tags = self._generate_tags(pattern_type, language, signature)
                
                pattern = CodePattern(
                    file_path=str(file_path),
                    language=language,
                    pattern_type=pattern_type,
                    signature=signature,
                    example_code=example_code,
                    context=f"Lines {start_line}-{end_line}",
                    confidence=confidence,
                    tags=tags,
                )
                patterns.append(pattern)
        
        return patterns

    def _calculate_confidence(
        self,
        pattern_type: str,
        signature: str,
        example_code: str,
        language: str
    ) -> float:
        """Calculate confidence score for a pattern.
        
        Higher scores for:
        - Well-formed signatures
        - Longer, more complete examples
        - Known language patterns
        - Complex signatures (indicates more context)
        
        Args:
            pattern_type: Type of pattern
            signature: Extracted signature
            example_code: Example code snippet
            language: Programming language
            
        Returns:
            Confidence score between 0.0 and 1.0
        """
        score = 0.5  # Base score
        
        # Bonus for well-formed signatures
        if signature and len(signature) > 2:
            score += 0.1
        
        # Bonus for longer, more complete examples
        if len(example_code) > 100:
            score += 0.1
        if len(example_code) > 300:
            score += 0.1
        
        # Bonus for supported languages
        if language in self.LANGUAGE_EXTENSIONS.values():
            score += 0.1
        
        # Pattern type specific bonuses
        if pattern_type in ('function', 'class', 'struct'):
            score += 0.1
        
        # Penalty for very short signatures (might be noise)
        if len(signature) < 3:
            score -= 0.2
        
        return max(0.0, min(1.0, score))

    def _generate_tags(self, pattern_type: str, language: str, signature: str) -> list[str]:
        """Generate tags for categorization.
        
        Args:
            pattern_type: Type of pattern
            language: Programming language
            signature: Pattern signature
            
        Returns:
            List of tags
        """
        tags = [language, pattern_type]
        
        # Add visibility tags based on naming conventions
        if signature.startswith('_'):
            tags.append('private')
        elif signature.startswith('__'):
            tags.append('dunder')
        elif signature.isupper():
            tags.append('constant')
        
        # Add type-specific tags
        if pattern_type == 'function':
            if signature.startswith('test_'):
                tags.append('test')
            elif signature.startswith('get_') or signature.startswith('set_'):
                tags.append('accessor')
        
        return tags


def create_default_analyzer() -> CodebasePatternAnalyzer:
    """Factory function to create a default analyzer instance.
    
    Returns:
        Configured CodebasePatternAnalyzer instance
    """
    return CodebasePatternAnalyzer()
