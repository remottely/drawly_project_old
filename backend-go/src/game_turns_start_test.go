package main

import (
	"testing"
)

// TestHandleGameTurnsStartNotEnoughPlayers ensures the game does not start when player count is below minimum.
func TestHandleGameTurnsStartNotEnoughPlayers(t *testing.T) {
	rooms = map[string]*Room{}
	roomDrawings = map[string]*Drawing{}

	r := newRoom("room")
	r.addParticipant(&Participant{UserId: "u1", Username: "one", IsConnected: true})
	r.CurrentDrawerTurnIndex = 0
	rooms["room"] = r
	roomDrawings["room"] = &Drawing{}

	io := fakeBroadcaster{}
	client := &fakeClientConn{}

	handleGameTurnsStart(io, client, map[string]any{"roomName": "room"})

	if r.IsGameStarted {
		t.Fatalf("game should not start with only one participant")
	}
	if r.ActiveTimer != nil {
		t.Fatalf("timer should not start when players are insufficient")
	}
}

// TestHandleGameTurnsStartStartsGame verifies the game begins and timer is created when enough players exist.
func TestHandleGameTurnsStartStartsGame(t *testing.T) {
	rooms = map[string]*Room{}
	roomDrawings = map[string]*Drawing{}
	wordsList = []string{"apple"}

	r := newRoom("room")
	r.addParticipant(&Participant{UserId: "u1", Username: "one", IsConnected: true})
	r.addParticipant(&Participant{UserId: "u2", Username: "two", IsConnected: true})
	r.CurrentDrawerTurnIndex = -1
	rooms["room"] = r
	roomDrawings["room"] = &Drawing{}

	io := fakeBroadcaster{}
	client := &fakeClientConn{}

	handleGameTurnsStart(io, client, map[string]any{"roomName": "room"})

	if !r.IsGameStarted {
		t.Fatalf("game should be marked as started")
	}
	if r.ActiveTimer == nil {
		t.Fatalf("timer should be created when game starts")
	}
	if r.TurnCount == 0 {
		t.Fatalf("turn should advance when game starts")
	}

	r.ActiveTimer.Stop()
}
