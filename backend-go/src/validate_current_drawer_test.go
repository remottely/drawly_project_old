package main

import (
	"testing"
)

// TestValidateCurrentDrawerReturnsDrawer ensures the current drawer is returned
// when the room has a valid drawer configured.
func TestValidateCurrentDrawerReturnsDrawer(t *testing.T) {
	room := newRoom("a")
	p := &Participant{UserId: "1", Username: "one", IsConnected: true}
	room.addParticipant(p)
	room.CurrentDrawerTurnIndex = 0

	srv := fakeBroadcaster{}
	got := validateCurrentDrawer(srv, room, room.Name)
	if got != p {
		t.Fatalf("expected %v, got %v", p, got)
	}
}

// TestValidateCurrentDrawerNoDrawer verifies that nil is returned when no
// current drawer exists for the room.
func TestValidateCurrentDrawerNoDrawer(t *testing.T) {
	room := newRoom("a")

	srv := fakeBroadcaster{}
	got := validateCurrentDrawer(srv, room, room.Name)
	if got != nil {
		t.Fatalf("expected nil, got %v", got)
	}
}
