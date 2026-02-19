"""Tests for CodebasePatternAnalyzer.

This module contains comprehensive tests for the pattern analyzer functionality,
including file scanning, pattern extraction, and edge cases.
"""

import sys
import tempfile
from pathlib import Path

# Add .maestro to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent / ".maestro"))

import pytest

from planner.pattern_analyzer import (
    CodebasePatternAnalyzer,
    CodePattern,
    AnalysisScope,
    create_default_analyzer,
)


class TestCodePattern:
    """Tests for the CodePattern dataclass."""

    def test_code_pattern_creation(self):
        """Test creating a CodePattern with all fields."""
        pattern = CodePattern(
            id="test-id",
            file_path="/path/to/file.py",
            language="python",
            pattern_type="function",
            signature="def my_function()",
            example_code="def my_function():\n    pass",
            context="Lines 1-2",
            confidence=0.85,
            tags=["python", "function"],
        )
        
        assert pattern.id == "test-id"
        assert pattern.file_path == "/path/to/file.py"
        assert pattern.language == "python"
        assert pattern.pattern_type == "function"
        assert pattern.signature == "def my_function()"
        assert pattern.example_code == "def my_function():\n    pass"
        assert pattern.context == "Lines 1-2"
        assert pattern.confidence == 0.85
        assert pattern.tags == ["python", "function"]

    def test_code_pattern_auto_id(self):
        """Test that CodePattern generates unique IDs automatically."""
        pattern1 = CodePattern(file_path="/path/to/file.py")
        pattern2 = CodePattern(file_path="/path/to/file2.py")
        
        assert pattern1.id != pattern2.id
        assert len(pattern1.id) > 0

    def test_code_pattern_confidence_validation(self):
        """Test that confidence scores are validated."""
        with pytest.raises(ValueError, match="Confidence must be between 0.0 and 1.0"):
            CodePattern(confidence=1.5)
        
        with pytest.raises(ValueError, match="Confidence must be between 0.0 and 1.0"):
            CodePattern(confidence=-0.1)

    def test_code_pattern_valid_confidence(self):
        """Test valid confidence scores."""
        pattern1 = CodePattern(confidence=0.0)
        assert pattern1.confidence == 0.0
        
        pattern2 = CodePattern(confidence=1.0)
        assert pattern2.confidence == 1.0
        
        pattern3 = CodePattern(confidence=0.5)
        assert pattern3.confidence == 0.5


class TestAnalysisScope:
    """Tests for the AnalysisScope dataclass."""

    def test_default_scope(self):
        """Test default AnalysisScope configuration."""
        scope = AnalysisScope()
        
        assert scope.directories == []
        assert '*.py' in scope.file_patterns
        assert '*.ts' in scope.file_patterns
        assert '*.go' in scope.file_patterns
        assert 'node_modules' in scope.exclude_patterns
        assert scope.max_file_size == 1_048_576

    def test_custom_scope(self):
        """Test custom AnalysisScope configuration."""
        scope = AnalysisScope(
            directories=["/src", "/tests"],
            file_patterns=["*.py"],
            exclude_patterns=["__pycache__"],
            max_file_size=500_000,
        )
        
        assert scope.directories == ["/src", "/tests"]
        assert scope.file_patterns == ["*.py"]
        assert scope.exclude_patterns == ["__pycache__"]
        assert scope.max_file_size == 500_000


class TestCodebasePatternAnalyzer:
    """Tests for the CodebasePatternAnalyzer class."""

    def test_analyzer_initialization(self):
        """Test analyzer can be initialized."""
        analyzer = CodebasePatternAnalyzer()
        assert analyzer is not None
        assert len(analyzer._compiled_patterns) > 0

    def test_analyze_empty_directories(self):
        """Test analyze with empty directories returns empty list."""
        analyzer = CodebasePatternAnalyzer()
        scope = AnalysisScope(directories=[])
        
        patterns = analyzer.analyze("feature-1", scope)
        
        assert patterns == []

    def test_analyze_nonexistent_directory(self):
        """Test analyze handles non-existent directories gracefully."""
        analyzer = CodebasePatternAnalyzer()
        scope = AnalysisScope(directories=["/nonexistent/path"])
        
        patterns = analyzer.analyze("feature-1", scope)
        
        assert patterns == []

    def test_analyze_empty_codebase(self):
        """Test analyze handles empty codebase gracefully."""
        with tempfile.TemporaryDirectory() as tmpdir:
            analyzer = CodebasePatternAnalyzer()
            scope = AnalysisScope(directories=[tmpdir])
            
            patterns = analyzer.analyze("feature-1", scope)
            
            assert patterns == []

    def test_scan_python_files(self):
        """Test scanning Python files."""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create test Python file
            py_file = Path(tmpdir) / "test_module.py"
            py_file.write_text("""
def my_function(param1: str) -> int:
    '''A test function.'''
    return len(param1)

class MyClass:
    '''A test class.'''
    
    def method(self):
        pass

import os
from pathlib import Path
""")
            
            analyzer = CodebasePatternAnalyzer()
            scope = AnalysisScope(
                directories=[tmpdir],
                file_patterns=["*.py"],
            )
            
            patterns = analyzer.analyze("feature-1", scope)
            
            assert len(patterns) > 0
            
            # Check function pattern
            func_patterns = [p for p in patterns if p.pattern_type == "function"]
            assert len(func_patterns) >= 2  # my_function and method
            
            # Check class pattern
            class_patterns = [p for p in patterns if p.pattern_type == "class"]
            assert len(class_patterns) >= 1
            assert any("MyClass" in p.signature for p in class_patterns)

    def test_scan_typescript_files(self):
        """Test scanning TypeScript files."""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create test TypeScript file
            ts_file = Path(tmpdir) / "test_module.ts"
            ts_file.write_text("""
export class UserService {
    async getUser(id: string): Promise<User> {
        return { id, name: 'Test' };
    }
}

export interface User {
    id: string;
    name: string;
}

import { Component } from 'react';
""")
            
            analyzer = CodebasePatternAnalyzer()
            scope = AnalysisScope(
                directories=[tmpdir],
                file_patterns=["*.ts"],
            )
            
            patterns = analyzer.analyze("feature-1", scope)
            
            assert len(patterns) > 0
            
            # Check class pattern
            class_patterns = [p for p in patterns if p.pattern_type == "class"]
            assert any("UserService" in p.signature for p in class_patterns)

    def test_scan_go_files(self):
        """Test scanning Go files."""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create test Go file
            go_file = Path(tmpdir) / "test_module.go"
            go_file.write_text("""
package main

import (
    "fmt"
    "os"
)

type User struct {
    ID   string
    Name string
}

type Stringer interface {
    String() string
}

func (u User) String() string {
    return u.Name
}

func main() {
    fmt.Println("Hello")
}
""")
            
            analyzer = CodebasePatternAnalyzer()
            scope = AnalysisScope(
                directories=[tmpdir],
                file_patterns=["*.go"],
            )
            
            patterns = analyzer.analyze("feature-1", scope)
            
            assert len(patterns) > 0
            
            # Check struct pattern
            struct_patterns = [p for p in patterns if p.pattern_type == "struct"]
            assert any("User" in p.signature for p in struct_patterns)

    def test_scan_rust_files(self):
        """Test scanning Rust files."""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create test Rust file
            rs_file = Path(tmpdir) / "test_module.rs"
            rs_file.write_text("""
use std::collections::HashMap;

pub struct Config {
    settings: HashMap<String, String>,
}

impl Config {
    pub fn new() -> Self {
        Config {
            settings: HashMap::new(),
        }
    }
}

pub trait Displayable {
    fn display(&self) -> String;
}

pub fn process_data(input: &str) -> String {
    input.to_string()
}
""")
            
            analyzer = CodebasePatternAnalyzer()
            scope = AnalysisScope(
                directories=[tmpdir],
                file_patterns=["*.rs"],
            )
            
            patterns = analyzer.analyze("feature-1", scope)
            
            assert len(patterns) > 0
            
            # Check struct pattern
            struct_patterns = [p for p in patterns if p.pattern_type == "struct"]
            assert any("Config" in p.signature for p in struct_patterns)

    def test_exclusion_patterns(self):
        """Test exclusion patterns work correctly."""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create included file
            included = Path(tmpdir) / "main.py"
            included.write_text("def included_func(): pass")
            
            # Create excluded directory with file
            excluded_dir = Path(tmpdir) / "node_modules"
            excluded_dir.mkdir()
            excluded_file = excluded_dir / "package.py"
            excluded_file.write_text("def excluded_func(): pass")
            
            analyzer = CodebasePatternAnalyzer()
            scope = AnalysisScope(
                directories=[tmpdir],
                file_patterns=["*.py"],
                exclude_patterns=["node_modules"],
            )
            
            patterns = analyzer.analyze("feature-1", scope)
            
            # Should only find the included function
            assert len(patterns) == 1
            assert patterns[0].signature == "included_func"

    def test_max_file_size(self):
        """Test max file size limit."""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create large file
            large_file = Path(tmpdir) / "large.py"
            large_file.write_text("x = 1\n" * 100000)  # Large content
            
            # Create small file
            small_file = Path(tmpdir) / "small.py"
            small_file.write_text("def small_func(): pass")
            
            analyzer = CodebasePatternAnalyzer()
            scope = AnalysisScope(
                directories=[tmpdir],
                file_patterns=["*.py"],
                max_file_size=100,  # Very small limit
            )
            
            patterns = analyzer.analyze("feature-1", scope)
            
            # Should only find small_func, not from large file
            assert len(patterns) == 1
            assert patterns[0].signature == "small_func"

    def test_confidence_score_calculation(self):
        """Test confidence scores are calculated appropriately."""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create test file with good patterns
            py_file = Path(tmpdir) / "quality.py"
            py_file.write_text("""
def well_documented_function(parameter1: str, parameter2: int) -> dict:
    '''
    This is a well-documented function with multiple parameters.
    
    Args:
        parameter1: First parameter description
        parameter2: Second parameter description
    
    Returns:
        A dictionary with results
    '''
    result = {
        'key1': parameter1,
        'key2': parameter2,
        'key3': 'some value',
        'key4': 42
    }
    return result

class WellDesignedClass:
    '''
    A well-designed class with proper documentation.
    This class follows good practices and has clear purpose.
    '''
    
    def __init__(self, name: str):
        self.name = name
        self.data = []
""")
            
            analyzer = CodebasePatternAnalyzer()
            scope = AnalysisScope(
                directories=[tmpdir],
                file_patterns=["*.py"],
            )
            
            patterns = analyzer.analyze("feature-1", scope)
            
            # All patterns should have reasonable confidence
            for pattern in patterns:
                assert 0.0 <= pattern.confidence <= 1.0
                # Well-formed patterns should have higher confidence
                if len(pattern.signature) > 3:
                    assert pattern.confidence > 0.3

    def test_pattern_tags(self):
        """Test pattern tags are generated correctly."""
        with tempfile.TemporaryDirectory() as tmpdir:
            py_file = Path(tmpdir) / "tags_test.py"
            py_file.write_text("""
def test_function():
    pass

class MyClass:
    pass

CONSTANT_VALUE = 42

class _PrivateClass:
    pass
""")
            
            analyzer = CodebasePatternAnalyzer()
            scope = AnalysisScope(directories=[tmpdir], file_patterns=["*.py"])
            
            patterns = analyzer.analyze("feature-1", scope)
            
            # Check tags are present
            for pattern in patterns:
                assert len(pattern.tags) >= 2
                assert pattern.language in pattern.tags
                assert pattern.pattern_type in pattern.tags
            
            # Check test tag
            test_funcs = [p for p in patterns if 'test' in p.tags]
            assert len(test_funcs) > 0
            
            # Check private tag
            private = [p for p in patterns if 'private' in p.tags]
            assert len(private) > 0

    def test_get_language(self):
        """Test language detection from file extensions."""
        analyzer = CodebasePatternAnalyzer()
        
        test_cases = [
            (Path("test.py"), "python"),
            (Path("test.ts"), "typescript"),
            (Path("test.tsx"), "typescript"),
            (Path("test.js"), "javascript"),
            (Path("test.jsx"), "javascript"),
            (Path("test.go"), "go"),
            (Path("test.rs"), "rust"),
            (Path("test.txt"), None),
            (Path("test"), None),
        ]
        
        for file_path, expected_lang in test_cases:
            result = analyzer._get_language(file_path)
            assert result == expected_lang, f"Failed for {file_path}"

    def test_is_excluded(self):
        """Test exclusion pattern matching."""
        analyzer = CodebasePatternAnalyzer()
        
        # Should be excluded
        assert analyzer._is_excluded(Path("/project/node_modules/test.py"), ["node_modules"])
        assert analyzer._is_excluded(Path("/project/.git/config"), [".git"])
        assert analyzer._is_excluded(Path("/project/__pycache__/test.pyc"), ["__pycache__"])
        
        # Should not be excluded
        assert not analyzer._is_excluded(Path("/project/src/test.py"), ["node_modules"])
        assert not analyzer._is_excluded(Path("/project/main.py"), ["test"])

    def test_factory_function(self):
        """Test the create_default_analyzer factory function."""
        analyzer = create_default_analyzer()
        assert isinstance(analyzer, CodebasePatternAnalyzer)


class TestPatternExtractionEdgeCases:
    """Tests for edge cases in pattern extraction."""

    def test_empty_file(self):
        """Test handling of empty files."""
        with tempfile.TemporaryDirectory() as tmpdir:
            empty_file = Path(tmpdir) / "empty.py"
            empty_file.write_text("")
            
            analyzer = CodebasePatternAnalyzer()
            scope = AnalysisScope(directories=[tmpdir], file_patterns=["*.py"])
            
            patterns = analyzer.analyze("feature-1", scope)
            
            assert patterns == []

    def test_binary_file(self):
        """Test handling of binary files."""
        with tempfile.TemporaryDirectory() as tmpdir:
            binary_file = Path(tmpdir) / "binary.py"
            binary_file.write_bytes(b"\x00\x01\x02\x03")
            
            analyzer = CodebasePatternAnalyzer()
            scope = AnalysisScope(directories=[tmpdir], file_patterns=["*.py"])
            
            # Should not crash
            patterns = analyzer.analyze("feature-1", scope)
            
            assert patterns == []

    def test_unicode_content(self):
        """Test handling of Unicode content."""
        with tempfile.TemporaryDirectory() as tmpdir:
            unicode_file = Path(tmpdir) / "unicode.py"
            unicode_file.write_text("""
def function_with_unicode_🎉():
    """Docstring with unicode: ñ, é, 中"""
    pass
""", encoding='utf-8')
            
            analyzer = CodebasePatternAnalyzer()
            scope = AnalysisScope(directories=[tmpdir], file_patterns=["*.py"])
            
            patterns = analyzer.analyze("feature-1", scope)
            
            assert len(patterns) > 0

    def test_nested_directories(self):
        """Test scanning nested directory structures."""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create nested structure
            nested = Path(tmpdir) / "src" / "components" / "ui"
            nested.mkdir(parents=True)
            
            nested_file = nested / "button.py"
            nested_file.write_text("def render_button(): pass")
            
            analyzer = CodebasePatternAnalyzer()
            scope = AnalysisScope(directories=[tmpdir], file_patterns=["*.py"])
            
            patterns = analyzer.analyze("feature-1", scope)
            
            assert len(patterns) == 1
            assert "render_button" in patterns[0].signature

    def test_multiple_languages_in_scope(self):
        """Test scanning multiple languages in same scope."""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create files in different languages
            (Path(tmpdir) / "main.py").write_text("def py_func(): pass")
            (Path(tmpdir) / "main.ts").write_text("function tsFunc() {}")
            (Path(tmpdir) / "main.go").write_text("func goFunc() {}")
            
            analyzer = CodebasePatternAnalyzer()
            scope = AnalysisScope(
                directories=[tmpdir],
                file_patterns=["*.py", "*.ts", "*.go"],
            )
            
            patterns = analyzer.analyze("feature-1", scope)
            
            assert len(patterns) >= 3
            
            languages = {p.language for p in patterns}
            assert "python" in languages
            assert "typescript" in languages
            assert "go" in languages


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
