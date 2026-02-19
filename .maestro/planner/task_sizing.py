"""Task sizing validator for ensuring tasks are XS or S only."""

from dataclasses import dataclass, field
from typing import List, Tuple, Optional
from enum import Enum
import re


class TaskSize(Enum):
    """Task size categories in minutes."""
    XS = "XS"  # 0-120 minutes (0-2 hours)
    S = "S"    # 121-360 minutes (2-6 hours)
    M = "M"    # 361-720 minutes (12+ hours) - REJECTED
    L = "L"    # 721+ minutes (20+ hours) - REJECTED


@dataclass
class Task:
    """Represents a task to be sized."""
    description: str
    scope: Optional[str] = None
    files: List[str] = field(default_factory=list)
    title: Optional[str] = None
    
    def __post_init__(self):
        if self.description is None:
            self.description = ""


@dataclass
class SizingResult:
    """Result of task sizing validation."""
    size: TaskSize
    minutes: int
    is_valid: bool
    suggestions: List[str] = field(default_factory=list)
    complexity_score: int = 0


class TaskSizingValidator:
    """Validates task sizes and suggests splitting for oversized tasks."""
    
    # Size limits in minutes
    XS_MAX = 120   # 2 hours
    S_MAX = 360    # 6 hours
    
    # Complexity keywords with weights
    HIGH_COMPLEXITY_KEYWORDS = {
        'refactor': 30,
        'architecture': 25,
        'redesign': 25,
        'migrate': 25,
        'rewrite': 25,
    }
    
    MEDIUM_COMPLEXITY_KEYWORDS = {
        'implement': 20,
        'create': 15,
        'build': 15,
        'design': 15,
        'integrate': 15,
        'configure': 10,
        'setup': 10,
    }
    
    LOW_COMPLEXITY_KEYWORDS = {
        'fix': 5,
        'update': 5,
        'add': 5,
        'remove': 5,
        'rename': 3,
        'typo': 2,
        'docs': 3,
        'documentation': 3,
    }
    
    # Ambiguous scope indicators
    AMBIGUITY_INDICATORS = [
        'etc', 'etc.', 'various', 'multiple', 'several', 'some',
        'and more', '...', 'and others', 'including but not limited',
    ]
    
    def __init__(self):
        """Initialize the validator."""
        pass
    
    def validate_size(self, task: Task) -> SizingResult:
        """
        Validate task size and return categorization with suggestions.
        
        Args:
            task: Task to validate
            
        Returns:
            SizingResult with size categorization and suggestions
        """
        complexity_score = self.estimate_complexity(task)
        minutes = self._score_to_minutes(complexity_score, task)
        
        # Determine size category
        if minutes <= self.XS_MAX:
            size = TaskSize.XS
            is_valid = True
        elif minutes <= self.S_MAX:
            size = TaskSize.S
            is_valid = True
        else:
            # Over S limit - need to determine if M or L
            if minutes <= 720:
                size = TaskSize.M
            else:
                size = TaskSize.L
            is_valid = False
        
        # Generate suggestions if invalid
        suggestions = []
        if not is_valid:
            suggestions = self.suggest_splits(task)
        elif size == TaskSize.S:
            # Even for valid S tasks, provide suggestions if close to limit
            if minutes > self.S_MAX * 0.8:
                suggestions.append(
                    f"Task is close to size limit ({minutes} min). "
                    "Consider if it can be split into smaller tasks."
                )
        
        return SizingResult(
            size=size,
            minutes=minutes,
            is_valid=is_valid,
            suggestions=suggestions,
            complexity_score=complexity_score
        )
    
    def estimate_complexity(self, task: Task) -> int:
        """
        Estimate task complexity based on description and scope.
        
        Args:
            task: Task to analyze
            
        Returns:
            Complexity score (higher = more complex)
        """
        score = 0
        description_lower = task.description.lower()
        
        # Score based on keywords
        score += self._score_keywords(description_lower)
        
        # Score based on number of files
        score += self._score_file_count(task.files)
        
        # Score based on description length and specificity
        score += self._score_description(task.description)
        
        # Score based on scope ambiguity
        score += self._score_scope_ambiguity(task)
        
        return score
    
    def suggest_splits(self, task: Task) -> List[str]:
        """
        Suggest ways to split an oversized task into smaller sub-tasks.
        
        Args:
            task: Task that exceeds size limits
            
        Returns:
            List of actionable splitting suggestions
        """
        suggestions = []
        
        # Check for multiple files
        if len(task.files) > 1:
            suggestions.append(
                f"Split by file: Create separate tasks for each of the {len(task.files)} files"
            )
            for i, file in enumerate(task.files[:3], 1):
                suggestions.append(f"  - Task {i}: Modify {file}")
            if len(task.files) > 3:
                suggestions.append(f"  - And {len(task.files) - 3} more file-specific tasks")
        
        # Check for multiple high-complexity keywords
        high_complexity_found = [
            kw for kw in self.HIGH_COMPLEXITY_KEYWORDS 
            if kw in task.description.lower()
        ]
        if len(high_complexity_found) > 1:
            suggestions.append(
                f"Split by operation: Separate '{', '.join(high_complexity_found)}' "
                "into individual tasks"
            )
        
        # Check for implementation + setup pattern
        desc_lower = task.description.lower()
        if 'implement' in desc_lower and ('setup' in desc_lower or 'configure' in desc_lower):
            suggestions.append(
                "Split setup from implementation: Create one task for setup/configuration, "
                "another for actual implementation"
            )
        
        # Check for "and" clauses that might indicate separable work
        if ' and ' in task.description.lower():
            parts = task.description.lower().split(' and ')
            if len(parts) >= 2:
                suggestions.append(
                    f"Split by action: The task mentions multiple actions. "
                    f"Consider splitting into {len(parts)} separate tasks"
                )
        
        # Scope-specific suggestions
        if task.scope:
            scope_lower = task.scope.lower()
            if any(indicator in scope_lower for indicator in self.AMBIGUITY_INDICATORS):
                suggestions.append(
                    "Clarify scope: Remove ambiguous terms like 'etc', 'various', 'multiple'. "
                    "Define exact deliverables"
                )
        
        # Fallback suggestion
        if not suggestions:
            suggestions.append(
                "General split strategy: Break task down by: "
                "(1) Setup/Configuration, "
                "(2) Core implementation, "
                "(3) Testing/Validation"
            )
        
        return suggestions
    
    def _score_keywords(self, description: str) -> int:
        """Score based on complexity keywords found in description."""
        score = 0
        
        for keyword, weight in self.HIGH_COMPLEXITY_KEYWORDS.items():
            if keyword in description:
                score += weight
        
        for keyword, weight in self.MEDIUM_COMPLEXITY_KEYWORDS.items():
            if keyword in description:
                score += weight
        
        for keyword, weight in self.LOW_COMPLEXITY_KEYWORDS.items():
            if keyword in description:
                score += weight
        
        return score
    
    def _score_file_count(self, files: List[str]) -> int:
        """Score based on number of files to modify."""
        file_count = len(files)
        
        if file_count == 0:
            # Ambiguous - no files specified
            return 20
        elif file_count == 1:
            return 10
        elif file_count <= 3:
            return 25
        elif file_count <= 5:
            return 40
        else:
            return 60
    
    def _score_description(self, description: str) -> int:
        """Score based on description length and specificity."""
        if not description or not description.strip():
            # Empty description is high risk
            return 50
        
        score = 0
        words = description.split()
        word_count = len(words)
        
        # Length-based scoring
        if word_count < 5:
            score += 30  # Very short description
        elif word_count < 10:
            score += 20
        elif word_count > 50:
            score += 10  # Long descriptions may indicate complexity
        
        # Check for specific technical terms that indicate clarity
        specific_terms = ['file', 'function', 'method', 'class', 'component', 'module']
        specificity_count = sum(1 for term in specific_terms if term in description.lower())
        if specificity_count == 0:
            score += 15  # Lack of specificity
        
        return score
    
    def _score_scope_ambiguity(self, task: Task) -> int:
        """Score based on scope clarity."""
        score = 0
        text_to_check = (task.scope or "") + " " + task.description
        text_lower = text_to_check.lower()
        
        # Check for ambiguity indicators
        for indicator in self.AMBIGUITY_INDICATORS:
            if indicator in text_lower:
                score += 20
                break  # Only count once
        
        # Check for vague quantifiers
        vague_patterns = [r'\bsome\b', r'\bseveral\b', r'\bmany\b', r'\bfew\b']
        for pattern in vague_patterns:
            if re.search(pattern, text_lower):
                score += 10
                break
        
        # No explicit scope increases risk
        if not task.scope:
            score += 15
        
        return score
    
    def _score_to_minutes(self, score: int, task: Task) -> int:
        """Convert complexity score to estimated minutes."""
        # Base conversion: score * 3 minutes per point
        minutes = score * 3
        
        # Minimum minutes for any task
        if minutes < 15:
            minutes = 15
        
        # Cap at reasonable maximum for calculation
        if minutes > 1440:  # 24 hours
            minutes = 1440
        
        return minutes
