"""Unit tests for TaskSizingValidator."""

import pytest
import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../..'))

from .maestro.planner.task_sizing import (
    TaskSizingValidator,
    Task,
    TaskSize,
    SizingResult
)


class TestTaskSizingValidator:
    """Test cases for TaskSizingValidator."""
    
    def setup_method(self):
        """Set up validator for each test."""
        self.validator = TaskSizingValidator()
    
    # ========== Test Task Size Categorization ==========
    
    def test_empty_description_returns_high_score(self):
        """Empty description should score high due to ambiguity."""
        task = Task(description="")
        result = self.validator.validate_size(task)
        
        assert result.complexity_score > 50
        assert result.minutes > 0
    
    def test_very_short_description_scores_high(self):
        """Very short descriptions should score higher."""
        task = Task(description="Fix bug")
        result = self.validator.validate_size(task)
        
        assert result.complexity_score >= 30
    
    def test_xs_task_with_simple_fix(self):
        """Simple fix task should be XS."""
        task = Task(
            description="Fix typo in README",
            scope="Update documentation",
            files=["README.md"]
        )
        result = self.validator.validate_size(task)
        
        assert result.size == TaskSize.XS
        assert result.is_valid is True
        assert result.minutes <= 120
    
    def test_s_task_with_implementation(self):
        """Implementation task should be S."""
        task = Task(
            description="Implement user login validation",
            scope="Add form validation for login",
            files=["auth.py", "forms.py"]
        )
        result = self.validator.validate_size(task)
        
        assert result.size == TaskSize.S
        assert result.is_valid is True
        assert result.minutes <= 360
    
    def test_m_task_gets_rejected(self):
        """Tasks exceeding S limit should be rejected as M."""
        task = Task(
            description="Refactor entire authentication system and redesign database schema",
            scope="Complete system overhaul",
            files=["auth.py", "models.py", "views.py", "serializers.py", "tests.py"]
        )
        result = self.validator.validate_size(task)
        
        assert result.size == TaskSize.M
        assert result.is_valid is False
    
    def test_l_task_gets_rejected(self):
        """Very large tasks should be rejected as L."""
        task = Task(
            description="Refactor entire application architecture, migrate database, "
                       "redesign UI, implement new authentication, and create comprehensive tests",
            scope="Complete platform rebuild",
            files=["file1.py", "file2.py", "file3.py", "file4.py", "file5.py", 
                   "file6.py", "file7.py", "file8.py"]
        )
        result = self.validator.validate_size(task)
        
        assert result.size == TaskSize.L
        assert result.is_valid is False
    
    # ========== Test Complexity Scoring ==========
    
    def test_high_complexity_keywords(self):
        """High complexity keywords should increase score."""
        task = Task(description="Refactor the authentication system")
        score = self.validator.estimate_complexity(task)
        
        assert score >= 30  # At least "refactor" keyword weight
    
    def test_medium_complexity_keywords(self):
        """Medium complexity keywords should increase score."""
        task = Task(description="Implement user registration")
        score = self.validator.estimate_complexity(task)
        
        assert score >= 20  # At least "implement" keyword weight
    
    def test_low_complexity_keywords(self):
        """Low complexity keywords should increase score slightly."""
        task = Task(description="Fix the login bug")
        score = self.validator.estimate_complexity(task)
        
        assert score >= 5  # At least "fix" keyword weight
    
    def test_multiple_keywords_additive(self):
        """Multiple keywords should add to score."""
        task = Task(description="Implement and refactor the user system")
        score = self.validator.estimate_complexity(task)
        
        # Should have both implement (20) and refactor (30)
        assert score >= 50
    
    def test_file_count_scoring(self):
        """File count should affect complexity score."""
        # No files specified
        task_no_files = Task(description="Fix bug")
        score_no_files = self.validator.estimate_complexity(task_no_files)
        assert score_no_files >= 20  # Ambiguous penalty
        
        # One file
        task_one_file = Task(description="Fix bug", files=["bug.py"])
        score_one_file = self.validator.estimate_complexity(task_one_file)
        assert score_one_file >= 10
        
        # Many files
        task_many_files = Task(
            description="Fix bug", 
            files=["f1.py", "f2.py", "f3.py", "f4.py", "f5.py", "f6.py"]
        )
        score_many_files = self.validator.estimate_complexity(task_many_files)
        assert score_many_files >= 60
    
    def test_description_length_scoring(self):
        """Description length should affect score."""
        # Very short
        task_short = Task(description="Fix")
        score_short = self.validator.estimate_complexity(task_short)
        assert score_short >= 30
        
        # Normal
        task_normal = Task(description="Fix the login authentication bug in user module")
        score_normal = self.validator.estimate_complexity(task_normal)
        assert score_normal >= 0
    
    def test_scope_ambiguity_scoring(self):
        """Ambiguous scope should increase score."""
        task_ambiguous = Task(
            description="Update files",
            scope="Update various files and etc"
        )
        score_ambiguous = self.validator.estimate_complexity(task_ambiguous)
        assert score_ambiguous >= 20  # Ambiguity penalty
        
        task_clear = Task(
            description="Update files",
            scope="Update user.py and auth.py"
        )
        score_clear = self.validator.estimate_complexity(task_clear)
        assert score_clear >= 0
    
    def test_no_scope_penalty(self):
        """Missing scope should increase score."""
        task_no_scope = Task(description="Implement feature")
        score_no_scope = self.validator.estimate_complexity(task_no_scope)
        assert score_no_scope >= 15
    
    # ========== Test Splitting Suggestions ==========
    
    def test_suggest_split_by_files(self):
        """Should suggest splitting by files when multiple files."""
        task = Task(
            description="Update authentication",
            files=["auth.py", "models.py", "views.py"]
        )
        suggestions = self.validator.suggest_splits(task)
        
        assert any("file" in s.lower() for s in suggestions)
    
    def test_suggest_split_by_operations(self):
        """Should suggest splitting by multiple operations."""
        task = Task(description="Refactor and migrate the database")
        suggestions = self.validator.suggest_splits(task)
        
        assert any("operation" in s.lower() or "separate" in s.lower() for s in suggestions)
    
    def test_suggest_split_implementation_setup(self):
        """Should suggest splitting implementation from setup."""
        task = Task(description="Implement feature and setup configuration")
        suggestions = self.validator.suggest_splits(task)
        
        assert any("setup" in s.lower() and "implementation" in s.lower() for s in suggestions)
    
    def test_suggest_split_by_action(self):
        """Should suggest splitting by 'and' clauses."""
        task = Task(description="Create user model and create login form")
        suggestions = self.validator.suggest_splits(task)
        
        assert any("action" in s.lower() or "multiple" in s.lower() for s in suggestions)
    
    def test_suggest_clarify_scope(self):
        """Should suggest clarifying ambiguous scope."""
        task = Task(
            description="Update code",
            scope="Update various files etc"
        )
        suggestions = self.validator.suggest_splits(task)
        
        assert any("clarify" in s.lower() or "ambiguous" in s.lower() for s in suggestions)
    
    def test_fallback_suggestion(self):
        """Should provide fallback suggestion when no specific splits found."""
        task = Task(description="Do work")
        suggestions = self.validator.suggest_splits(task)
        
        assert len(suggestions) > 0
        assert any("general" in s.lower() or "strategy" in s.lower() for s in suggestions)
    
    # ========== Test Edge Cases ==========
    
    def test_none_description_handled(self):
        """None description should be handled gracefully."""
        task = Task(description=None)  # type: ignore
        result = self.validator.validate_size(task)
        
        assert result.size is not None
        assert result.minutes >= 0
    
    def test_whitespace_description(self):
        """Whitespace-only description should score high."""
        task = Task(description="   \n\t  ")
        result = self.validator.validate_size(task)
        
        assert result.complexity_score >= 50
    
    def test_case_insensitive_keyword_matching(self):
        """Keywords should be matched case-insensitively."""
        task_upper = Task(description="REFACTOR the code")
        task_lower = Task(description="refactor the code")
        
        score_upper = self.validator.estimate_complexity(task_upper)
        score_lower = self.validator.estimate_complexity(task_lower)
        
        assert score_upper == score_lower
    
    def test_suggestion_for_s_near_limit(self):
        """Should provide warning suggestion for S tasks near limit."""
        # Create a task that will be S and near the limit
        task = Task(
            description="Implement comprehensive authentication system with user roles",
            scope="Complete auth module",
            files=["auth.py", "models.py", "views.py", "forms.py"]
        )
        result = self.validator.validate_size(task)
        
        if result.size == TaskSize.S and result.minutes > 288:  # > 80% of 360
            assert len(result.suggestions) > 0
    
    def test_minutes_calculation(self):
        """Minutes should be calculated from score."""
        task = Task(description="Fix typo")
        result = self.validator.validate_size(task)
        
        # Minimum minutes should be 15
        assert result.minutes >= 15
    
    def test_complexity_score_in_result(self):
        """Result should include complexity score."""
        task = Task(description="Test task")
        result = self.validator.validate_size(task)
        
        assert hasattr(result, 'complexity_score')
        assert isinstance(result.complexity_score, int)
    
    def test_task_dataclass_creation(self):
        """Task dataclass should be created correctly."""
        task = Task(
            description="Test description",
            scope="Test scope",
            files=["file1.py", "file2.py"],
            title="Test Title"
        )
        
        assert task.description == "Test description"
        assert task.scope == "Test scope"
        assert task.files == ["file1.py", "file2.py"]
        assert task.title == "Test Title"
    
    def test_sizing_result_creation(self):
        """SizingResult dataclass should be created correctly."""
        result = SizingResult(
            size=TaskSize.XS,
            minutes=60,
            is_valid=True,
            suggestions=["suggestion1"],
            complexity_score=20
        )
        
        assert result.size == TaskSize.XS
        assert result.minutes == 60
        assert result.is_valid is True
        assert result.suggestions == ["suggestion1"]
        assert result.complexity_score == 20


class TestTaskSizeEnum:
    """Test cases for TaskSize enum."""
    
    def test_enum_values(self):
        """TaskSize enum should have correct values."""
        assert TaskSize.XS.value == "XS"
        assert TaskSize.S.value == "S"
        assert TaskSize.M.value == "M"
        assert TaskSize.L.value == "L"
    
    def test_enum_comparison(self):
        """TaskSize enum values should be comparable."""
        assert TaskSize.XS == TaskSize.XS
        assert TaskSize.XS != TaskSize.S


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
