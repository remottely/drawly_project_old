package main

import (
	"testing"
	"time"
)

func TestCancelActiveTimer(t *testing.T) {
	r := &Room{}
	r.ActiveTimer = time.AfterFunc(time.Millisecond, func() {})
	cancelActiveTimer(r)
	if r.ActiveTimer != nil {
		t.Fatalf("expected timer to be nil after cancel")
	}
}

func TestGetParticipantsOrdering(t *testing.T) {
	r := newRoom("test")
	p1 := &Participant{UserId: "1", Username: "one", Score: 10, IsConnected: true}
	p2 := &Participant{UserId: "2", Username: "two", Score: 20, IsConnected: true, PreviousOrder: 1}
	p3 := &Participant{UserId: "3", Username: "three", Score: 20, IsConnected: true, PreviousOrder: 2}
	r.addParticipant(p1)
	r.addParticipant(p2)
	r.addParticipant(p3)

	ordered := r.getParticipants()
	if len(ordered) != 3 {
		t.Fatalf("expected 3 participants, got %d", len(ordered))
	}
	if ordered[0] != p2 || ordered[1] != p3 || ordered[2] != p1 {
		t.Fatalf("unexpected order on first call")
	}

	if p2.PreviousOrder != 0 || p3.PreviousOrder != 1 || p1.PreviousOrder != 2 {
		t.Fatalf("previous order not updated")
	}

	p1.Score = 30
	ordered = r.getParticipants()
	if ordered[0] != p1 {
		t.Fatalf("expected p1 to be first after score change")
	}
}

func TestDeleteRoomRemovesData(t *testing.T) {
	rooms = map[string]*Room{}
	roomDrawings = map[string]*Drawing{}

	r := newRoom("del")
	rooms["del"] = r
	roomDrawings["del"] = &Drawing{}
	r.ActiveTimer = time.AfterFunc(time.Millisecond, func() {})
	r.IsGameStarted = true

	deleteRoom("del")
	if _, ok := rooms["del"]; ok {
		t.Fatalf("room not deleted")
	}
	if _, ok := roomDrawings["del"]; ok {
		t.Fatalf("drawing not deleted")
	}
	if r.ActiveTimer != nil {
		t.Fatalf("timer not cancelled")
	}
	if r.IsGameStarted {
		t.Fatalf("game flag not reset")
	}
}

func TestGetRoomNames(t *testing.T) {
	rooms = map[string]*Room{}
	rooms["a"] = newRoom("a")
	rooms["b"] = newRoom("b")
	names := getRoomNames()
	if len(names) != 2 {
		t.Fatalf("expected 2 names, got %d", len(names))
	}
	foundA, foundB := false, false
	for _, n := range names {
		if n == "a" {
			foundA = true
		}
		if n == "b" {
			foundB = true
		}
	}
	if !foundA || !foundB {
		t.Fatalf("expected names 'a' and 'b'")
	}
}
