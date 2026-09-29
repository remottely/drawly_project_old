package main

import "testing"

func TestParseStrokeTypeValid(t *testing.T) {
	types := []string{"normal", "eraser", "line", "polygon", "square", "circle", "bucket"}
	for _, tt := range types {
		st, err := ParseStrokeType(tt)
		if err != nil {
			t.Fatalf("unexpected error for %s: %v", tt, err)
		}
		if string(st) != tt {
			t.Fatalf("expected %s got %s", tt, st)
		}
	}
}

func TestParseStrokeTypeInvalid(t *testing.T) {
	if _, err := ParseStrokeType("unknown"); err == nil {
		t.Fatalf("expected error for invalid type")
	}
}
