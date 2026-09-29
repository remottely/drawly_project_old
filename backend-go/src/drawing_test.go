package main

// Tests for Drawing manipulation utilities and word selection.

import "testing"

// TestDrawingOperations verifies add, undo, redo and clear behaviors.
func TestDrawingOperations(t *testing.T) {
	d := &Drawing{}
	stroke1 := Stroke{Points: []Offset{{Dx: 0, Dy: 0}}}
	stroke2 := Stroke{Points: []Offset{{Dx: 1, Dy: 1}}}

	d.addStroke(stroke1)
	if len(d.Strokes) != 1 {
		t.Fatalf("expected 1 stroke, got %d", len(d.Strokes))
	}

	d.addStroke(stroke2)
	if len(d.Strokes) != 2 {
		t.Fatalf("expected 2 strokes, got %d", len(d.Strokes))
	}

	// Test addStrokeLastPoints
	d.addStrokeLastPoints([]Offset{{Dx: 2, Dy: 2}})
	if d.Strokes[1].Points[1].Dx != 2 {
		t.Fatalf("expected added point to second stroke")
	}

	// Test undo
	undone := d.undo()
	if undone == nil || len(d.Strokes) != 1 {
		t.Fatalf("undo failed to remove stroke")
	}
	if len(d.BackupStrokes) != 1 {
		t.Fatalf("undo failed to store backup stroke")
	}

	// Test redo
	redone := d.redo()
	if redone == nil || len(d.Strokes) != 2 {
		t.Fatalf("redo failed to restore stroke")
	}

	// Test clear
	d.clear()
	if len(d.Strokes) != 0 || len(d.BackupStrokes) != 0 {
		t.Fatalf("clear did not reset drawing")
	}
}

// TestChooseRandomWordSingleEntry ensures deterministic output with one entry.
func TestChooseRandomWordSingleEntry(t *testing.T) {
	wordsList = []string{"apple"}
	word := chooseRandomWord()
	if word != "apple" {
		t.Fatalf("expected 'apple', got %s", word)
	}
}

func TestChooseRandomWordEmpty(t *testing.T) {
	wordsList = []string{}
	word := chooseRandomWord()
	if word != "Nenhuma palavra disponível." {
		t.Fatalf("expected fallback message, got %s", word)
	}
}
