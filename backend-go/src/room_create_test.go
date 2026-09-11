package main

import (
	"testing"
)

// TestCreateRoomAddsEntries verifies that createRoom initializes room and drawing maps only once.
func TestCreateRoomAddsEntries(t *testing.T) {
	rooms = map[string]*Room{}
	roomDrawings = map[string]*Drawing{}

	io := fakeBroadcaster{}
	client := &fakeClientConn{}

	createRoom(io, client, "room")

	if _, ok := rooms["room"]; !ok {
		t.Fatalf("room was not created")
	}
	if _, ok := roomDrawings["room"]; !ok {
		t.Fatalf("room drawing was not created")
	}

	// Calling again should not duplicate entries.
	createRoom(io, client, "room")
	if len(rooms) != 1 || len(roomDrawings) != 1 {
		t.Fatalf("createRoom should be idempotent")
	}
}
