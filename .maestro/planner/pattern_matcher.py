"""Pattern Matcher for constitution integration.

Matches discovered code patterns against constitutional rules and assigns
confidence scores based on alignment.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any


class ConfidenceLevel(Enum):
    """Confidence levels for pattern matching."""

    HIGH = 0.9
    MEDIUM = 0.7
    LOW = 0.5
    UNCERTAIN = 0.3
    NONE = 0.0


class ConflictSeverity(Enum):
    """Severity levels for pattern conflicts."""

    CRITICAL = "critical"
    MAJOR = "major"
    MINOR = "minor"
    WARNING = "warning"


@dataclass
class CodePattern:
    """Represents a discovered code pattern."""

    name: str
    pattern_type: str
    location: str
    description: str
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass
class ConstitutionalRule:
    """Represents a rule from the constitution."""

    section: str
    title: str
    content: str
    line_number: int
    priority: int = 1


@dataclass
class MatchedPattern:
    """Result of matching a pattern against constitution rules."""

    pattern: CodePattern
    matched_rules: list[ConstitutionalRule]
    confidence: float
    is_fallback: bool
    conflicts: list[PatternConflict] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)

    def __post_init__(self) -> None:
        """Validate confidence is within bounds."""
        self.confidence = max(0.0, min(1.0, self.confidence))

    @property
    def has_conflicts(self) -> bool:
        """Check if this match has any conflicts."""
        return len(self.conflicts) > 0


@dataclass
class PatternConflict:
    """Represents a conflict between a pattern and constitution."""

    pattern: CodePattern
    rule: ConstitutionalRule | None
    severity: ConflictSeverity
    description: str
    suggestion: str | None = None


class PatternMatcher:
    """Matches code patterns against constitutional rules.

    This class is responsible for:
    - Loading and parsing the project constitution
    - Matching discovered patterns against constitutional rules
    - Assigning confidence scores based on alignment
    - Providing fallback patterns when no codebase patterns exist
    - Flagging conflicts between constitution and codebase patterns
    """

    def __init__(self, constitution_path: str | Path | None = None) -> None:
        """Initialize the PatternMatcher.

        Args:
            constitution_path: Path to the constitution file. If None,
                defaults to .maestro/constitution.md
        """
        self.constitution_path = Path(
            constitution_path or ".maestro/constitution.md"
        )
        self.rules: list[ConstitutionalRule] = []
        self._loaded = False

    def load_constitution(self) -> list[ConstitutionalRule]:
        """Load and parse the constitution from markdown.

        Returns:
            List of parsed constitutional rules

        Raises:
            FileNotFoundError: If constitution file doesn't exist
        """
        if not self.constitution_path.exists():
            raise FileNotFoundError(
                f"Constitution not found at {self.constitution_path}"
            )

        content = self.constitution_path.read_text(encoding="utf-8")
        self.rules = self._parse_constitution(content)
        self._loaded = True
        return self.rules

    def _parse_constitution(self, content: str) -> list[ConstitutionalRule]:
        """Parse constitution markdown into rules.

        Extracts sections and subsections as rules with their content.

        Args:
            content: Raw markdown content

        Returns:
            List of constitutional rules
        """
        rules = []
        lines = content.split("\n")

        current_section = None
        current_title = None
        current_content_lines = []
        start_line = 0

        for i, line in enumerate(lines, 1):
            # Match section headers (## 1. Section Title)
            section_match = re.match(r"^##\s+(\d+)\.\s+(.+)$", line)
            # Match subsection headers (### 1.1 Subsection Title)
            subsection_match = re.match(r"^###\s+(\d+\.\d+)\s+(.+)$", line)

            if section_match or subsection_match:
                # Save previous rule if exists
                if current_section and current_title:
                    rules.append(
                        ConstitutionalRule(
                            section=current_section,
                            title=current_title,
                            content="\n".join(current_content_lines).strip(),
                            line_number=start_line,
                            priority=1 if "." not in current_section else 2,
                        )
                    )

                # Start new rule
                if section_match:
                    current_section = section_match.group(1)
                    current_title = section_match.group(2).strip()
                elif subsection_match:
                    current_section = subsection_match.group(1)
                    current_title = subsection_match.group(2).strip()

                current_content_lines = []
                start_line = i
            elif current_section is not None:
                current_content_lines.append(line)

        # Don't forget the last rule
        if current_section and current_title:
            rules.append(
                ConstitutionalRule(
                    section=current_section,
                    title=current_title,
                    content="\n".join(current_content_lines).strip(),
                    line_number=start_line,
                    priority=1 if "." not in current_section else 2,
                )
            )

        return rules

    def match_patterns(
        self,
        patterns: list[CodePattern],
        use_fallback: bool = False,
    ) -> list[MatchedPattern]:
        """Match code patterns against constitutional rules.

        Args:
            patterns: List of discovered code patterns
            use_fallback: Whether to use fallback patterns if empty

        Returns:
            List of matched patterns with confidence scores
        """
        if not self._loaded:
            self.load_constitution()

        if not patterns and use_fallback:
            return self.get_fallback_patterns()

        matched = []
        for pattern in patterns:
            match = self._match_single_pattern(pattern)
            matched.append(match)

        return matched

    def _match_single_pattern(self, pattern: CodePattern) -> MatchedPattern:
        """Match a single pattern against all rules.

        Args:
            pattern: The code pattern to match

        Returns:
            MatchedPattern with confidence and rules
        """
        matched_rules = []
        confidence_scores = []
        notes = []

        for rule in self.rules:
            score, matched = self._calculate_match_score(pattern, rule)
            if matched:
                matched_rules.append(rule)
                confidence_scores.append(score)
                if score >= ConfidenceLevel.HIGH.value:
                    notes.append(f"Strong alignment with {rule.section}: {rule.title}")

        # Calculate overall confidence
        if confidence_scores:
            confidence = sum(confidence_scores) / len(confidence_scores)
        else:
            confidence = ConfidenceLevel.NONE.value

        return MatchedPattern(
            pattern=pattern,
            matched_rules=matched_rules,
            confidence=confidence,
            is_fallback=False,
            conflicts=[],
            notes=notes,
        )

    def _calculate_match_score(
        self, pattern: CodePattern, rule: ConstitutionalRule
    ) -> tuple[float, bool]:
        """Calculate confidence score for a pattern-rule match.

        Uses keyword matching, section relevance, and pattern type alignment.

        Args:
            pattern: Code pattern to check
            rule: Constitutional rule to match against

        Returns:
            Tuple of (confidence_score, is_matched)
        """
        score = 0.0
        matched = False

        # Keywords from pattern and rule
        pattern_text = f"{pattern.name} {pattern.description} {pattern.pattern_type}"
        pattern_keywords = set(pattern_text.lower().split())
        rule_text = f"{rule.title} {rule.content}"
        rule_keywords = set(rule_text.lower().split())

        # Calculate keyword overlap
        common_keywords = pattern_keywords & rule_keywords
        if common_keywords:
            overlap_ratio = len(common_keywords) / max(
                len(pattern_keywords), len(rule_keywords)
            )
            score += overlap_ratio * 0.4
            matched = True

        # Type-specific matching
        type_scores = {
            "architecture": ["architecture", "layer", "dependency", "communication"],
            "code_standard": ["naming", "error handling", "testing", "standard"],
            "review": ["review", "checklist", "approval"],
            "domain": ["domain", "business logic", "constraint"],
        }

        for type_key, keywords in type_scores.items():
            if pattern.pattern_type.lower() == type_key:
                for keyword in keywords:
                    if keyword in rule_text.lower():
                        score += 0.15
                        matched = True

        # Priority boost
        if rule.priority == 1:
            score *= 1.1

        return min(score, 1.0), matched

    def get_fallback_patterns(self) -> list[MatchedPattern]:
        """Generate fallback patterns from constitution when no codebase patterns exist.

        Returns:
            List of MatchedPattern based on constitutional rules only
        """
        if not self._loaded:
            self.load_constitution()

        fallback_patterns = []

        for rule in self.rules:
            # Create synthetic pattern from rule
            pattern = CodePattern(
                name=f"fallback_{rule.section}",
                pattern_type="constitutional",
                location="constitution",
                description=rule.content[:200] if rule.content else rule.title,
                metadata={"source": "constitution", "rule_section": rule.section},
            )

            # Calculate base confidence for fallback
            base_confidence = ConfidenceLevel.MEDIUM.value
            if rule.priority == 1:
                base_confidence = ConfidenceLevel.HIGH.value

            matched = MatchedPattern(
                pattern=pattern,
                matched_rules=[rule],
                confidence=base_confidence,
                is_fallback=True,
                notes=[f"Fallback pattern from constitution section {rule.section}"],
            )
            fallback_patterns.append(matched)

        return fallback_patterns

    def flag_conflicts(
        self, matched_patterns: list[MatchedPattern]
    ) -> list[PatternConflict]:
        """Detect and flag conflicts between patterns and constitution.

        Args:
            matched_patterns: Previously matched patterns to check

        Returns:
            List of conflicts found
        """
        conflicts = []

        for matched in matched_patterns:
            # Check for low confidence (indicates potential conflict)
            if matched.confidence < ConfidenceLevel.LOW.value and not matched.is_fallback:
                conflict = PatternConflict(
                    pattern=matched.pattern,
                    rule=matched.matched_rules[0] if matched.matched_rules else None,
                    severity=ConflictSeverity.MINOR,
                    description=f"Low confidence match ({matched.confidence:.2f}) "
                    f"for pattern '{matched.pattern.name}'",
                    suggestion="Review pattern alignment with constitutional rules",
                )
                conflicts.append(conflict)
                matched.conflicts.append(conflict)

            # Check for naming convention violations
            if matched.pattern.pattern_type == "naming":
                naming_rules = [
                    r for r in matched.matched_rules if "naming" in r.title.lower()
                ]
                if not naming_rules:
                    conflict = PatternConflict(
                        pattern=matched.pattern,
                        rule=None,
                        severity=ConflictSeverity.WARNING,
                        description=f"Pattern '{matched.pattern.name}' may violate naming conventions",
                        suggestion="Check against section 2.2 naming conventions",
                    )
                    conflicts.append(conflict)
                    matched.conflicts.append(conflict)

            # Check for architectural boundary violations
            if matched.pattern.pattern_type == "import":
                layer_rules = [
                    r for r in matched.matched_rules if "layer" in r.title.lower()
                ]
                if not layer_rules and "domain" in matched.pattern.location:
                    conflict = PatternConflict(
                        pattern=matched.pattern,
                        rule=None,
                        severity=ConflictSeverity.CRITICAL,
                        description=f"Potential layer boundary violation in {matched.pattern.location}",
                        suggestion="Verify against section 1.3 dependency rules",
                    )
                    conflicts.append(conflict)
                    matched.conflicts.append(conflict)

        return conflicts

    def get_rule_by_section(self, section: str) -> ConstitutionalRule | None:
        """Get a specific rule by its section number.

        Args:
            section: Section number (e.g., "1.1", "2")

        Returns:
            The rule if found, None otherwise
        """
        for rule in self.rules:
            if rule.section == section:
                return rule
        return None

    def get_rules_by_category(self, category: str) -> list[ConstitutionalRule]:
        """Get all rules in a category.

        Args:
            category: Category prefix (e.g., "1", "2")

        Returns:
            List of rules in that category
        """
        return [r for r in self.rules if r.section.startswith(category)]
