package main

import "testing"

func TestRemoveParticipantAdjustsTurn(t *testing.T) {
	r := newRoom("test")
	p1 := &Participant{UserId: "u1", Username: "one", IsConnected: true}
	p2 := &Participant{UserId: "u2", Username: "two", IsConnected: true}
	p3 := &Participant{UserId: "u3", Username: "three", IsConnected: true}
	r.addParticipant(p1)
	r.addParticipant(p2)
	r.addParticipant(p3)
	r.CurrentDrawerTurnIndex = 1 // p2 is current drawer

	r.removeParticipant("u3")
	if len(r.TurnQueue) != 2 {
		t.Fatalf("expected 2 participants after removal, got %d", len(r.TurnQueue))
	}
	if r.CurrentDrawerTurnIndex != 1 {
		t.Fatalf("expected drawer index 1, got %d", r.CurrentDrawerTurnIndex)
	}

	r.removeParticipant("u2") // remove current drawer
	if r.CurrentDrawerTurnIndex != 0 {
		t.Fatalf("expected drawer index to advance to 0, got %d", r.CurrentDrawerTurnIndex)
	}
	if r.getCurrentDrawer().UserId != "u1" {
		t.Fatalf("expected u1 to be current drawer")
	}

	r.removeParticipant("u1")
	if r.CurrentDrawerTurnIndex != -1 {
		t.Fatalf("expected -1 when no participants, got %d", r.CurrentDrawerTurnIndex)
	}
}

func TestAdvanceTurnSkipsDisconnected(t *testing.T) {
	r := newRoom("test")
	p1 := &Participant{UserId: "u1", Username: "one", IsConnected: true}
	p2 := &Participant{UserId: "u2", Username: "two", IsConnected: false}
	p3 := &Participant{UserId: "u3", Username: "three", IsConnected: true}
	r.addParticipant(p1)
	r.addParticipant(p2)
	r.addParticipant(p3)
	r.CurrentDrawerTurnIndex = 0

	r.advanceTurn()
	if r.getCurrentDrawer() != p3 {
		t.Fatalf("expected p3 to be drawer after skipping disconnected")
	}

	p1.IsConnected = false
	p3.IsConnected = false
	r.advanceTurn()
	if r.CurrentDrawerTurnIndex != -1 {
		t.Fatalf("expected -1 when no connected participants, got %d", r.CurrentDrawerTurnIndex)
	}
}
