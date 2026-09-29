package main

import (
	"testing"
)

func TestParsePointsSuccess(t *testing.T) {
	raw := []interface{}{
		map[string]interface{}{"dx": 1.0, "dy": 2.0},
		map[string]interface{}{"dx": -3.5, "dy": 4.2},
	}
	points, err := parsePoints(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(points) != 2 {
		t.Fatalf("expected 2 points, got %d", len(points))
	}
	if points[0].Dx != 1.0 || points[0].Dy != 2.0 {
		t.Errorf("unexpected first point: %+v", points[0])
	}
	if points[1].Dx != -3.5 || points[1].Dy != 4.2 {
		t.Errorf("unexpected second point: %+v", points[1])
	}
}

func TestParsePointsInvalid(t *testing.T) {
	raw := []interface{}{
		map[string]interface{}{"dx": 1.0}, // missing dy
	}
	if _, err := parsePoints(raw); err == nil {
		t.Fatalf("expected error for invalid points")
	}
}

func TestParseStrokeSuccess(t *testing.T) {
	raw := map[string]any{
		"points": []any{
			map[string]any{"dx": 0.0, "dy": 0.0},
			map[string]any{"dx": 1.0, "dy": 1.0},
		},
		"color": map[string]any{
			"a":          1.0,
			"r":          0.0,
			"g":          0.0,
			"b":          0.0,
			"colorSpace": "ColorSpace.sRGB",
		},
		"size":       2.0,
		"opacity":    255.0,
		"strokeType": "normal",
		"filled":     true,
	}
	stroke, err := parseStroke(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(stroke.Points) != 2 || stroke.Points[1].Dx != 1.0 {
		t.Errorf("parsed points not as expected: %+v", stroke.Points)
	}
	if stroke.Color.R != 0.0 || stroke.Size != 2.0 {
		t.Errorf("unexpected stroke fields: %+v", stroke)
	}
	if stroke.StrokeType != normal {
		t.Errorf("expected stroke type %s, got %s", normal, stroke.StrokeType)
	}
	if stroke.Filled == nil || *stroke.Filled != true {
		t.Errorf("expected filled true, got %+v", stroke.Filled)
	}
}

func TestParseStrokeInvalidType(t *testing.T) {
	raw := map[string]any{
		"points":     []any{map[string]any{"dx": 0.0, "dy": 0.0}},
		"color":      map[string]any{"a": 1.0, "r": 1.0, "g": 1.0, "b": 1.0, "colorSpace": "ColorSpace.sRGB"},
		"size":       1.0,
		"opacity":    255.0,
		"strokeType": "invalid",
	}
	if _, err := parseStroke(raw); err == nil {
		t.Fatalf("expected error for invalid stroke type")
	}
}
