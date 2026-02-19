package version

import (
	"strings"
	"testing"
)

func TestString(t *testing.T) {
	s := String()
	if s == "" {
		t.Error("String() returned empty string")
	}
	if !strings.Contains(s, Version) {
		t.Errorf("String() %q does not contain version %q", s, Version)
	}
	if !strings.Contains(s, Commit) {
		t.Errorf("String() %q does not contain commit %q", s, Commit)
	}
}
