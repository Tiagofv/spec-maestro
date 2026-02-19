"""Tests for the PatternMatcher class."""

import sys
from pathlib import Path
from unittest.mock import MagicMock, mock_open, patch

import pytest

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent / ".maestro"))

from planner.pattern_matcher import (
    CodePattern,
    ConfidenceLevel,
    ConflictSeverity,
    ConstitutionalRule,
    MatchedPattern,
    PatternConflict,
    PatternMatcher,
)


class TestConstitutionalRule:
    """Tests for the ConstitutionalRule dataclass."""

    def test_rule_creation(self):
        """Test creating a constitutional rule."""
        rule = ConstitutionalRule(
            section="1.1",
            title="Core Architecture",
            content="Test content",
            line_number=10,
        )
        assert rule.section == "1.1"
        assert rule.title == "Core Architecture"
        assert rule.content == "Test content"
        assert rule.line_number == 10
        assert rule.priority == 1


class TestCodePattern:
    """Tests for the CodePattern dataclass."""

    def test_pattern_creation(self):
        """Test creating a code pattern."""
        pattern = CodePattern(
            name="test_pattern",
            pattern_type="architecture",
            location="src/test.py",
            description="A test pattern",
            metadata={"key": "value"},
        )
        assert pattern.name == "test_pattern"
        assert pattern.pattern_type == "architecture"
        assert pattern.location == "src/test.py"
        assert pattern.description == "A test pattern"
        assert pattern.metadata == {"key": "value"}

    def test_pattern_creation_without_metadata(self):
        """Test creating a pattern without metadata."""
        pattern = CodePattern(
            name="simple_pattern",
            pattern_type="naming",
            location="src/main.py",
            description="Simple pattern",
        )
        assert pattern.metadata == {}


class TestMatchedPattern:
    """Tests for the MatchedPattern dataclass."""

    def test_matched_pattern_creation(self):
        """Test creating a matched pattern."""
        pattern = CodePattern(
            name="test",
            pattern_type="test",
            location="test.py",
            description="Test",
        )
        rule = ConstitutionalRule(
            section="1.1",
            title="Test Rule",
            content="Content",
            line_number=1,
        )
        matched = MatchedPattern(
            pattern=pattern,
            matched_rules=[rule],
            confidence=0.85,
            is_fallback=False,
        )
        assert matched.pattern == pattern
        assert len(matched.matched_rules) == 1
        assert matched.confidence == 0.85
        assert not matched.is_fallback
        assert not matched.has_conflicts

    def test_confidence_bounds(self):
        """Test confidence is clamped to [0, 1]."""
        pattern = CodePattern(
            name="test",
            pattern_type="test",
            location="test.py",
            description="Test",
        )
        # Test upper bound
        matched = MatchedPattern(
            pattern=pattern,
            matched_rules=[],
            confidence=1.5,
            is_fallback=False,
        )
        assert matched.confidence == 1.0

        # Test lower bound
        matched = MatchedPattern(
            pattern=pattern,
            matched_rules=[],
            confidence=-0.5,
            is_fallback=False,
        )
        assert matched.confidence == 0.0

    def test_has_conflicts_property(self):
        """Test the has_conflicts property."""
        pattern = CodePattern(
            name="test",
            pattern_type="test",
            location="test.py",
            description="Test",
        )
        conflict = PatternConflict(
            pattern=pattern,
            rule=None,
            severity=ConflictSeverity.MINOR,
            description="Test conflict",
        )
        matched = MatchedPattern(
            pattern=pattern,
            matched_rules=[],
            confidence=0.5,
            is_fallback=False,
            conflicts=[conflict],
        )
        assert matched.has_conflicts


class TestPatternMatcherInit:
    """Tests for PatternMatcher initialization."""

    def test_default_constitution_path(self):
        """Test default constitution path."""
        matcher = PatternMatcher()
        assert matcher.constitution_path == Path(".maestro/constitution.md")
        assert not matcher._loaded

    def test_custom_constitution_path(self):
        """Test custom constitution path."""
        matcher = PatternMatcher("/custom/path/constitution.md")
        assert matcher.constitution_path == Path("/custom/path/constitution.md")


class TestLoadConstitution:
    """Tests for loading and parsing constitution."""

    def test_load_constitution_file_not_found(self):
        """Test loading non-existent constitution."""
        matcher = PatternMatcher("/nonexistent/constitution.md")
        with pytest.raises(FileNotFoundError):
            matcher.load_constitution()

    @patch("pathlib.Path.exists")
    @patch("pathlib.Path.read_text")
    def test_load_constitution_success(self, mock_read, mock_exists):
        """Test successfully loading constitution."""
        mock_exists.return_value = True
        mock_read.return_value = """
# Constitution

## 1. Architecture

Test architecture section.

### 1.1 Core Architecture

Core architecture details.

## 2. Standards

### 2.1 Naming

Naming conventions here.
"""

        matcher = PatternMatcher()
        rules = matcher.load_constitution()

        assert len(rules) == 3
        assert rules[0].section == "1"
        assert rules[0].title == "Architecture"
        assert rules[1].section == "1.1"
        assert rules[1].title == "Core Architecture"
        assert rules[2].section == "2.1"
        assert rules[2].title == "Naming"
        assert matcher._loaded

    @patch("pathlib.Path.exists")
    @patch("pathlib.Path.read_text")
    def test_parse_empty_constitution(self, mock_read, mock_exists):
        """Test parsing empty constitution."""
        mock_exists.return_value = True
        mock_read.return_value = ""

        matcher = PatternMatcher()
        rules = matcher.load_constitution()
        assert len(rules) == 0


class TestMatchPatterns:
    """Tests for pattern matching functionality."""

    @patch("pathlib.Path.exists")
    @patch("pathlib.Path.read_text")
    def test_match_patterns_with_rules(self, mock_read, mock_exists):
        """Test matching patterns against rules."""
        mock_exists.return_value = True
        mock_read.return_value = """
## 1. Architecture

Architecture patterns.

### 1.1 Core

Core architecture with domain layer.
"""

        matcher = PatternMatcher()
        patterns = [
            CodePattern(
                name="domain_layer",
                pattern_type="architecture",
                location="src/domain.py",
                description="Domain layer implementation",
            )
        ]

        matched = matcher.match_patterns(patterns)
        assert len(matched) == 1
        assert matched[0].pattern.name == "domain_layer"
        assert len(matched[0].matched_rules) > 0
        assert matched[0].confidence > 0

    @patch("pathlib.Path.exists")
    @patch("pathlib.Path.read_text")
    def test_match_patterns_empty_with_fallback(self, mock_read, mock_exists):
        """Test fallback when no patterns provided."""
        mock_exists.return_value = True
        mock_read.return_value = """
## 1. Architecture

Architecture patterns.
"""

        matcher = PatternMatcher()
        matched = matcher.match_patterns([], use_fallback=True)
        assert len(matched) > 0
        assert all(m.is_fallback for m in matched)

    @patch("pathlib.Path.exists")
    @patch("pathlib.Path.read_text")
    def test_match_patterns_empty_without_fallback(self, mock_read, mock_exists):
        """Test empty patterns without fallback."""
        mock_exists.return_value = True
        mock_read.return_value = """
## 1. Architecture

Architecture patterns.
"""

        matcher = PatternMatcher()
        matched = matcher.match_patterns([], use_fallback=False)
        assert len(matched) == 0

    @patch("pathlib.Path.exists")
    @patch("pathlib.Path.read_text")
    def test_match_single_pattern(self, mock_read, mock_exists):
        """Test matching a single pattern."""
        mock_exists.return_value = True
        mock_read.return_value = """
## 2. Standards

Code standards.

### 2.1 Naming

Naming conventions for files.
"""

        matcher = PatternMatcher()
        pattern = CodePattern(
            name="snake_case_file",
            pattern_type="naming",
            location="src/snake_case.py",
            description="Uses snake_case naming",
        )

        matched = matcher._match_single_pattern(pattern)
        assert matched.pattern == pattern
        assert matched.confidence > 0


class TestCalculateMatchScore:
    """Tests for match score calculation."""

    @patch("pathlib.Path.exists")
    @patch("pathlib.Path.read_text")
    def test_keyword_overlap_scoring(self, mock_read, mock_exists):
        """Test scoring based on keyword overlap."""
        mock_exists.return_value = True
        mock_read.return_value = """
## 1. Architecture

Domain layer patterns.
"""

        matcher = PatternMatcher()
        matcher.load_constitution()

        pattern = CodePattern(
            name="domain_service",
            pattern_type="architecture",
            location="src/domain/service.py",
            description="Domain layer service implementation",
        )

        rule = matcher.rules[0]
        score, matched = matcher._calculate_match_score(pattern, rule)
        assert matched
        assert score > 0

    @patch("pathlib.Path.exists")
    @patch("pathlib.Path.read_text")
    def test_type_specific_scoring(self, mock_read, mock_exists):
        """Test type-specific scoring."""
        mock_exists.return_value = True
        mock_read.return_value = """
## 2. Code Standards

### 2.2 Naming Conventions

Follow naming standards.
"""

        matcher = PatternMatcher()
        matcher.load_constitution()

        pattern = CodePattern(
            name="test_pattern",
            pattern_type="code_standard",
            location="src/test.py",
            description="Follows naming standards",
        )

        rule = matcher.rules[0]
        score, matched = matcher._calculate_match_score(pattern, rule)
        assert matched


class TestGetFallbackPatterns:
    """Tests for fallback pattern generation."""

    @patch("pathlib.Path.exists")
    @patch("pathlib.Path.read_text")
    def test_fallback_patterns_created(self, mock_read, mock_exists):
        """Test fallback patterns are created from rules."""
        mock_exists.return_value = True
        mock_read.return_value = """
## 1. Architecture

Architecture rules.

### 1.1 Core

Core rules.
"""

        matcher = PatternMatcher()
        fallback = matcher.get_fallback_patterns()

        assert len(fallback) == 2
        assert all(m.is_fallback for m in fallback)
        assert all(m.confidence >= ConfidenceLevel.MEDIUM.value for m in fallback)

    @patch("pathlib.Path.exists")
    @patch("pathlib.Path.read_text")
    def test_fallback_pattern_priority(self, mock_read, mock_exists):
        """Test priority affects fallback confidence."""
        mock_exists.return_value = True
        mock_read.return_value = """
## 1. Main Section

Main section.

### 1.1 Sub Section

Sub section.
"""

        matcher = PatternMatcher()
        fallback = matcher.get_fallback_patterns()

        # Main section should have higher confidence
        main_section = [f for f in fallback if f.pattern.name == "fallback_1"][0]
        assert main_section.confidence == ConfidenceLevel.HIGH.value


class TestFlagConflicts:
    """Tests for conflict detection and flagging."""

    @patch("pathlib.Path.exists")
    @patch("pathlib.Path.read_text")
    def test_low_confidence_conflict(self, mock_read, mock_exists):
        """Test detecting low confidence conflicts."""
        mock_exists.return_value = True
        mock_read.return_value = "## 1. Test\n\nTest content."

        matcher = PatternMatcher()
        pattern = CodePattern(
            name="mismatch",
            pattern_type="unknown",
            location="src/test.py",
            description="Unrelated description",
        )

        matched = MatchedPattern(
            pattern=pattern,
            matched_rules=[],
            confidence=0.2,
            is_fallback=False,
        )

        conflicts = matcher.flag_conflicts([matched])
        assert len(conflicts) > 0
        assert conflicts[0].severity == ConflictSeverity.MINOR

    @patch("pathlib.Path.exists")
    @patch("pathlib.Path.read_text")
    def test_naming_convention_conflict(self, mock_read, mock_exists):
        """Test detecting naming convention conflicts."""
        mock_exists.return_value = True
        mock_read.return_value = "## 2. Standards\n\nStandards content."

        matcher = PatternMatcher()
        pattern = CodePattern(
            name="BadNaming",
            pattern_type="naming",
            location="src/BadNaming.py",
            description="Bad naming pattern",
        )

        matched = MatchedPattern(
            pattern=pattern,
            matched_rules=[],
            confidence=0.5,
            is_fallback=False,
        )

        conflicts = matcher.flag_conflicts([matched])
        naming_conflicts = [c for c in conflicts if "naming" in c.description.lower()]
        assert len(naming_conflicts) > 0

    @patch("pathlib.Path.exists")
    @patch("pathlib.Path.read_text")
    def test_layer_boundary_conflict(self, mock_read, mock_exists):
        """Test detecting layer boundary conflicts."""
        mock_exists.return_value = True
        mock_read.return_value = "## 1. Architecture\n\nLayer rules."

        matcher = PatternMatcher()
        pattern = CodePattern(
            name="bad_import",
            pattern_type="import",
            location="src/domain/bad_import.py",
            description="Bad import in domain",
        )

        matched = MatchedPattern(
            pattern=pattern,
            matched_rules=[],
            confidence=0.5,
            is_fallback=False,
        )

        conflicts = matcher.flag_conflicts([matched])
        critical = [c for c in conflicts if c.severity == ConflictSeverity.CRITICAL]
        assert len(critical) > 0


class TestUtilityMethods:
    """Tests for utility methods."""

    @patch("pathlib.Path.exists")
    @patch("pathlib.Path.read_text")
    def test_get_rule_by_section(self, mock_read, mock_exists):
        """Test getting rule by section number."""
        mock_exists.return_value = True
        mock_read.return_value = """
## 1. First

First section.

### 1.1 Sub

Subsection.
"""

        matcher = PatternMatcher()
        matcher.load_constitution()

        rule = matcher.get_rule_by_section("1")
        assert rule is not None
        assert rule.title == "First"

        rule = matcher.get_rule_by_section("1.1")
        assert rule is not None
        assert rule.title == "Sub"

        rule = matcher.get_rule_by_section("999")
        assert rule is None

    @patch("pathlib.Path.exists")
    @patch("pathlib.Path.read_text")
    def test_get_rules_by_category(self, mock_read, mock_exists):
        """Test getting rules by category."""
        mock_exists.return_value = True
        mock_read.return_value = """
## 1. First

First.

### 1.1 Sub

Sub.

## 2. Second

Second.
"""

        matcher = PatternMatcher()
        matcher.load_constitution()

        cat1 = matcher.get_rules_by_category("1")
        assert len(cat1) == 2  # 1 and 1.1

        cat2 = matcher.get_rules_by_category("2")
        assert len(cat2) == 1

        cat999 = matcher.get_rules_by_category("999")
        assert len(cat999) == 0


class TestConfidenceLevels:
    """Tests for confidence level enum."""

    def test_confidence_values(self):
        """Test confidence level values."""
        assert ConfidenceLevel.HIGH.value == 0.9
        assert ConfidenceLevel.MEDIUM.value == 0.7
        assert ConfidenceLevel.LOW.value == 0.5
        assert ConfidenceLevel.UNCERTAIN.value == 0.3
        assert ConfidenceLevel.NONE.value == 0.0


class TestConflictSeverity:
    """Tests for conflict severity enum."""

    def test_severity_values(self):
        """Test severity level values."""
        assert ConflictSeverity.CRITICAL.value == "critical"
        assert ConflictSeverity.MAJOR.value == "major"
        assert ConflictSeverity.MINOR.value == "minor"
        assert ConflictSeverity.WARNING.value == "warning"


class TestIntegration:
    """Integration tests for full workflow."""

    @patch("pathlib.Path.exists")
    @patch("pathlib.Path.read_text")
    def test_full_workflow(self, mock_read, mock_exists):
        """Test complete workflow from loading to matching."""
        mock_exists.return_value = True
        mock_read.return_value = """
# Project Constitution

## 1. Architecture Principles

Core architecture description.

### 1.1 Layer Separation

Domain layer must not import Infrastructure.

## 2. Code Standards

### 2.1 Naming Conventions

Files must use snake_case.

## 3. Review Requirements

All code must be reviewed.
"""

        matcher = PatternMatcher()

        # Load constitution
        rules = matcher.load_constitution()
        assert len(rules) == 4

        # Create patterns
        patterns = [
            CodePattern(
                name="domain_service",
                pattern_type="architecture",
                location="src/domain/service.py",
                description="Domain layer service",
            ),
            CodePattern(
                name="my_module",
                pattern_type="naming",
                location="src/my_module.py",
                description="Uses snake_case naming",
            ),
        ]

        # Match patterns
        matched = matcher.match_patterns(patterns)
        assert len(matched) == 2

        # Check first pattern has good confidence
        assert matched[0].confidence > 0

        # Flag conflicts
        conflicts = matcher.flag_conflicts(matched)
        # May or may not have conflicts depending on matching

        # Get fallback
        fallback = matcher.get_fallback_patterns()
        assert len(fallback) == 4  # Same as number of rules

    @patch("pathlib.Path.exists")
    @patch("pathlib.Path.read_text")
    def test_accuracy_for_known_rules(self, mock_read, mock_exists):
        """Test >80% accuracy for known rules (acceptance criteria)."""
        mock_exists.return_value = True
        mock_read.return_value = """
## 1. Architecture

Domain layer architecture.

### 1.1 Dependencies

Domain must not import Infrastructure.

## 2. Naming

Snake case naming conventions.
"""

        matcher = PatternMatcher()
        matcher.load_constitution()

        # Test patterns that should match rules
        test_cases = [
            (
                CodePattern(
                    name="domain_entity",
                    pattern_type="architecture",
                    location="src/domain/entity.py",
                    description="Domain layer entity",
                ),
                True,  # Should match
            ),
            (
                CodePattern(
                    name="snake_case_module",
                    pattern_type="naming",
                    location="src/snake_case_module.py",
                    description="Uses snake_case naming",
                ),
                True,  # Should match
            ),
        ]

        correct = 0
        for pattern, should_match in test_cases:
            matched = matcher._match_single_pattern(pattern)
            has_match = len(matched.matched_rules) > 0
            if has_match == should_match:
                correct += 1

        accuracy = correct / len(test_cases)
        assert accuracy >= 0.8, f"Accuracy {accuracy} is below 80%"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
