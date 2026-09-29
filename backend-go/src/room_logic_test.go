package main

import "testing"

func TestGetCorrectAnswerRank(t *testing.T) {
	r := newRoom("test")
	rank1 := r.getCorrectAnswerRank("u1")
	if rank1 != 1 {
		t.Fatalf("expected rank 1, got %d", rank1)
	}
	// calling again for same user should return same rank
	rankRepeat := r.getCorrectAnswerRank("u1")
	if rankRepeat != 1 {
		t.Fatalf("expected rank 1 on repeat, got %d", rankRepeat)
	}
	rank2 := r.getCorrectAnswerRank("u2")
	if rank2 != 2 {
		t.Fatalf("expected rank 2, got %d", rank2)
	}
}

func TestHasEveryoneAnsweredCorrectly(t *testing.T) {
	r := newRoom("test")
	// Add participants
	p1 := &Participant{UserId: "u1", Username: "one", IsConnected: true}
	p2 := &Participant{UserId: "u2", Username: "two", IsConnected: true}
	p3 := &Participant{UserId: "u3", Username: "three", IsConnected: true}
	r.addParticipant(p1)
	r.addParticipant(p2)
	r.addParticipant(p3)
	r.CurrentDrawerTurnIndex = 0 // p1 is drawer
	// Initially, no one answered
	if r.hasEveryoneAnsweredCorrectly() {
		t.Fatalf("should not be true when no answers")
	}
	// p2 answers correctly
	r.participantCorrectAnswer("u2")
	if r.hasEveryoneAnsweredCorrectly() {
		t.Fatalf("should not be true yet")
	}
	// p3 disconnects
	p3.IsConnected = false
	if !r.hasEveryoneAnsweredCorrectly() {
		t.Fatalf("expected true when only drawer and disconnected participants remaining")
	}
	// reset and check when both p2 and p3 answered
	p3.IsConnected = true
	r.resetCorrectAnswers()
	r.participantCorrectAnswer("u2")
	r.participantCorrectAnswer("u3")
	if !r.hasEveryoneAnsweredCorrectly() {
		t.Fatalf("expected true when all connected participants answered")
	}
}
