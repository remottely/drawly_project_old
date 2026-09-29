package main

import (
	"testing"
)

func TestHandleClearDrawing(t *testing.T) {
	rooms = map[string]*Room{}
	roomDrawings = map[string]*Drawing{}

	rooms["room"] = newRoom("room")
	d := &Drawing{}
	d.addStroke(Stroke{Points: []Offset{{Dx: 0, Dy: 0}}})
	roomDrawings["room"] = d

	handleClearDrawing(fakeBroadcaster{}, &fakeClientConn{}, map[string]any{"roomName": "room"})
	if len(d.Strokes) != 0 {
		t.Fatalf("expected drawing to be cleared")
	}
}

func TestHandleUndoRedoDrawing(t *testing.T) {
	rooms = map[string]*Room{}
	roomDrawings = map[string]*Drawing{}

	rooms["room"] = newRoom("room")
	d := &Drawing{}
	stroke := Stroke{Points: []Offset{{Dx: 0, Dy: 0}}}
	d.addStroke(stroke)
	roomDrawings["room"] = d

	handleUndoDrawing(fakeBroadcaster{}, &fakeClientConn{}, map[string]any{"roomName": "room"})
	if len(d.Strokes) != 0 || len(d.BackupStrokes) != 1 {
		t.Fatalf("undo should move stroke to backup")
	}

	handleRedoDrawing(fakeBroadcaster{}, &fakeClientConn{}, map[string]any{"roomName": "room"})
	if len(d.Strokes) != 1 || len(d.BackupStrokes) != 0 {
		t.Fatalf("redo should restore stroke from backup")
	}
}

func TestHandleGuessAnswerChatAdvancesTurn(t *testing.T) {
	rooms = map[string]*Room{}
	roomDrawings = map[string]*Drawing{}
	wordsList = []string{"apple"}

	r := newRoom("room")
	drawer := &Participant{UserId: "d1", Username: "drawer", IsConnected: true}
	guesser := &Participant{UserId: "u1", Username: "user", IsConnected: true}
	r.addParticipant(drawer)
	r.addParticipant(guesser)
	r.CurrentDrawerTurnIndex = 0
	r.CurrentWord = "apple"
	r.IsGameStarted = true
	rooms["room"] = r
	roomDrawings["room"] = &Drawing{}

	handleGuessAnswerChat(fakeBroadcaster{}, &fakeClientConn{}, map[string]any{
		"roomName": "room",
		"userId":   "u1",
		"username": "user",
		"text":     "apple",
	})

	if r.Participants["u1"].Score == 0 {
		t.Fatalf("guesser score not updated")
	}
	if r.Participants["d1"].Score == 0 {
		t.Fatalf("drawer score not updated")
	}
	if r.ActiveTimer == nil {
		t.Fatalf("expected next turn timer to start")
	}
	if r.TurnCount == 0 {
		t.Fatalf("turn should advance")
	}
	r.ActiveTimer.Stop()
}
