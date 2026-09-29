package main

import (
	"fmt"
	"testing"
)

// newTestRoom monta uma sala com N participantes conectados, todos com score 0.
func newTestRoom(t *testing.T, name string, userIDs ...string) *Room {
	t.Helper()

	room := newRoom(name)
	for _, id := range userIDs {
		room.addParticipant(&Participant{
			UserId:      id,
			Username:    "user-" + id,
			IsConnected: true,
		})
	}
	return room
}

// ─── addParticipant / removeParticipant ──────────────────────────────────────

func TestAddParticipantRegistersInMapAndQueue(t *testing.T) {
	room := newTestRoom(t, "sala", "a", "b")

	if len(room.Participants) != 2 {
		t.Fatalf("esperava 2 participantes no mapa, obtive %d", len(room.Participants))
	}
	if len(room.TurnQueue) != 2 {
		t.Fatalf("esperava 2 participantes na fila, obtive %d", len(room.TurnQueue))
	}
	if room.TurnQueue[0].UserId != "a" || room.TurnQueue[1].UserId != "b" {
		t.Fatalf("a fila deve preservar a ordem de entrada, obtive %v", room.TurnQueue)
	}
}

func TestRemoveParticipantDropsFromMapAndQueue(t *testing.T) {
	room := newTestRoom(t, "sala", "a", "b", "c")
	room.CurrentDrawerTurnIndex = 0

	room.removeParticipant("b")

	if _, exists := room.Participants["b"]; exists {
		t.Error("participante removido não deveria continuar no mapa")
	}
	if len(room.TurnQueue) != 2 {
		t.Fatalf("esperava 2 na fila, obtive %d", len(room.TurnQueue))
	}
	for _, p := range room.TurnQueue {
		if p.UserId == "b" {
			t.Error("participante removido não deveria continuar na fila")
		}
	}
}

func TestRemoveLastParticipantInvalidatesDrawerIndex(t *testing.T) {
	room := newTestRoom(t, "sala", "a")
	room.CurrentDrawerTurnIndex = 0

	room.removeParticipant("a")

	if room.CurrentDrawerTurnIndex != -1 {
		t.Fatalf("sem participantes o índice do desenhista deve ser -1, obtive %d",
			room.CurrentDrawerTurnIndex)
	}
	if room.getCurrentDrawer() != nil {
		t.Error("sem participantes não deve haver desenhista")
	}
}

func TestRemoveParticipantIsNoOpForUnknownUser(t *testing.T) {
	room := newTestRoom(t, "sala", "a", "b")
	room.CurrentDrawerTurnIndex = 0

	room.removeParticipant("fantasma")

	if len(room.TurnQueue) != 2 {
		t.Fatalf("remover usuário inexistente não deve mexer na fila, obtive %d",
			len(room.TurnQueue))
	}
}

// ─── advanceTurn ─────────────────────────────────────────────────────────────

func TestAdvanceTurnRotatesAndIncrementsCounter(t *testing.T) {
	room := newTestRoom(t, "sala", "a", "b", "c")
	room.CurrentDrawerTurnIndex = -1

	room.advanceTurn()
	if got := room.getCurrentDrawer().UserId; got != "a" {
		t.Fatalf("primeiro turno deveria ser de 'a', obtive %q", got)
	}
	if room.TurnCount != 1 {
		t.Fatalf("esperava TurnCount 1, obtive %d", room.TurnCount)
	}

	room.advanceTurn()
	if got := room.getCurrentDrawer().UserId; got != "b" {
		t.Fatalf("segundo turno deveria ser de 'b', obtive %q", got)
	}
}

func TestAdvanceTurnWrapsAround(t *testing.T) {
	room := newTestRoom(t, "sala", "a", "b")
	room.CurrentDrawerTurnIndex = 1 // último da fila

	room.advanceTurn()

	if got := room.getCurrentDrawer().UserId; got != "a" {
		t.Fatalf("deveria voltar ao início da fila, obtive %q", got)
	}
}

func TestAdvanceTurnSkipsDisconnectedParticipants(t *testing.T) {
	room := newTestRoom(t, "sala", "a", "b", "c")
	room.Participants["b"].IsConnected = false
	room.CurrentDrawerTurnIndex = 0 // 'a' desenhando

	room.advanceTurn()

	if got := room.getCurrentDrawer().UserId; got != "c" {
		t.Fatalf("deveria pular 'b' (desconectado) e ir para 'c', obtive %q", got)
	}
}

func TestAdvanceTurnIsNoOpOnEmptyQueue(t *testing.T) {
	room := newRoom("vazia")
	room.CurrentDrawerTurnIndex = -1

	room.advanceTurn()

	if room.TurnCount != 0 {
		t.Errorf("sala vazia não deve incrementar o turno, obtive %d", room.TurnCount)
	}
}

// ─── getParticipants (ordenação do placar) ───────────────────────────────────

func TestGetParticipantsSortsByScoreDescending(t *testing.T) {
	room := newTestRoom(t, "sala", "a", "b", "c")
	room.Participants["a"].Score = 10
	room.Participants["b"].Score = 30
	room.Participants["c"].Score = 20

	ordered := room.getParticipants()

	want := []string{"b", "c", "a"}
	for i, id := range want {
		if ordered[i].UserId != id {
			t.Fatalf("posição %d: esperava %q, obtive %q", i, id, ordered[i].UserId)
		}
	}
}

func TestGetParticipantsIsStableAcrossCalls(t *testing.T) {
	// Empate no score: a ordem deve ser determinística entre chamadas, apesar de
	// os participantes virem de um map (cuja iteração em Go é aleatória).
	room := newTestRoom(t, "sala", "a", "b", "c", "d")

	first := room.getParticipants()
	baseline := make([]string, len(first))
	for i, p := range first {
		baseline[i] = p.UserId
	}

	for attempt := 0; attempt < 50; attempt++ {
		current := room.getParticipants()
		for i, p := range current {
			if p.UserId != baseline[i] {
				t.Fatalf("ordenação instável na tentativa %d: %v virou %v",
					attempt, baseline, current)
			}
		}
	}
}

func TestGetParticipantsWritesBackPreviousOrder(t *testing.T) {
	room := newTestRoom(t, "sala", "a", "b")
	room.Participants["a"].Score = 5

	ordered := room.getParticipants()

	if ordered[0].PreviousOrder != 0 || ordered[1].PreviousOrder != 1 {
		t.Fatalf("PreviousOrder deve refletir a posição atual, obtive %d e %d",
			ordered[0].PreviousOrder, ordered[1].PreviousOrder)
	}
}

// ─── respostas corretas ──────────────────────────────────────────────────────

func TestHasEveryoneAnsweredCorrectlyIgnoresDrawer(t *testing.T) {
	room := newTestRoom(t, "sala", "drawer", "guesser")
	room.CurrentDrawerTurnIndex = 0

	if room.hasEveryoneAnsweredCorrectly() {
		t.Error("ninguém acertou ainda; não deveria retornar true")
	}

	room.participantCorrectAnswer("guesser")

	if !room.hasEveryoneAnsweredCorrectly() {
		t.Error("o único palpiteiro acertou; o desenhista não deve ser exigido")
	}
}

func TestHasEveryoneAnsweredCorrectlyIgnoresDisconnected(t *testing.T) {
	room := newTestRoom(t, "sala", "drawer", "online", "offline")
	room.CurrentDrawerTurnIndex = 0
	room.Participants["offline"].IsConnected = false

	room.participantCorrectAnswer("online")

	if !room.hasEveryoneAnsweredCorrectly() {
		t.Error("participante desconectado não deve travar o avanço do turno")
	}
}

// TestHasEveryoneAnsweredCorrectlyWithoutDrawer cobre o caso em que todos saíram
// e não há desenhista.
//
// BUG(R3): hoje isto entra em panic — hasEveryoneAnsweredCorrectly desreferencia
// o retorno de getCurrentDrawer() sem checar nil, e getCurrentDrawer() retorna
// nil quando CurrentDrawerTurnIndex == -1. Ver docs/Pictionary/refactoring/01-achados.md.
func TestHasEveryoneAnsweredCorrectlyWithoutDrawer(t *testing.T) {
	t.Skip("BUG(R3): panic por nil deref — corrigir na fase 4, item 4.1")

	room := newTestRoom(t, "sala", "a")
	room.CurrentDrawerTurnIndex = -1

	if room.hasEveryoneAnsweredCorrectly() {
		t.Error("sem desenhista não faz sentido considerar o turno concluído")
	}
}

func TestResetCorrectAnswersClearsState(t *testing.T) {
	room := newTestRoom(t, "sala", "drawer", "guesser")
	room.CurrentDrawerTurnIndex = 0
	room.participantCorrectAnswer("guesser")

	room.resetCorrectAnswers()

	if room.hasEveryoneAnsweredCorrectly() {
		t.Error("após o reset ninguém deveria constar como tendo acertado")
	}
}

// TestGetCorrectAnswerRankIsDeterministic exercita a ordem de chegada dos
// acertos, que define quantos pontos cada jogador ganha.
//
// BUG(R2): getCorrectAnswerRank calcula a posição iterando um map, e a ordem de
// iteração de map em Go é aleatória por design. Logo o rank do 2º e do 3º
// colocado varia entre execuções idênticas — a pontuação do jogo não é
// reproduzível. Ver docs/Pictionary/refactoring/01-achados.md.
func TestGetCorrectAnswerRankIsDeterministic(t *testing.T) {
	t.Skip("BUG(R2): rank derivado de iteração de map — corrigir na fase 4, item 4.1")

	for attempt := 0; attempt < 50; attempt++ {
		room := newTestRoom(t, "sala", "drawer", "first", "second", "third")
		room.CurrentDrawerTurnIndex = 0

		ranks := map[string]uint8{}
		for _, id := range []string{"first", "second", "third"} {
			ranks[id] = room.getCorrectAnswerRank(id)
		}

		expected := map[string]uint8{"first": 1, "second": 2, "third": 3}
		for id, want := range expected {
			if ranks[id] != want {
				t.Fatalf("tentativa %d: %s deveria ter rank %d, obtive %d",
					attempt, id, want, ranks[id])
			}
		}
	}
}

func TestGetCorrectAnswerRankFirstAnswerIsOne(t *testing.T) {
	room := newTestRoom(t, "sala", "drawer", "guesser")
	room.CurrentDrawerTurnIndex = 0

	if rank := room.getCorrectAnswerRank("guesser"); rank != 1 {
		t.Fatalf("o primeiro a acertar deve ter rank 1, obtive %d", rank)
	}
}

func TestGetCorrectAnswerRankIsIdempotentForSameUser(t *testing.T) {
	room := newTestRoom(t, "sala", "drawer", "guesser")
	room.CurrentDrawerTurnIndex = 0

	first := room.getCorrectAnswerRank("guesser")
	second := room.getCorrectAnswerRank("guesser")

	if first != second {
		t.Fatalf("consultar o rank duas vezes deve dar o mesmo valor: %d vs %d",
			first, second)
	}
}

// ─── registro de salas ───────────────────────────────────────────────────────

func TestDeleteRoomClearsDrawingAndTimer(t *testing.T) {
	resetGlobalState()

	room := newTestRoom(t, "sala", "a")
	room.IsGameStarted = true
	room.ActiveTimer = afterFunc(veryLongDelay, func() {})
	rooms["sala"] = room
	roomDrawings["sala"] = &Drawing{Strokes: []Stroke{{}}}

	deleteRoom("sala")

	if _, exists := rooms["sala"]; exists {
		t.Error("a sala deveria ter sido removida do registro")
	}
	if _, exists := roomDrawings["sala"]; exists {
		t.Error("o desenho da sala deveria ter sido removido")
	}
	if room.ActiveTimer != nil {
		t.Error("o timer ativo deveria ter sido cancelado")
	}
	if room.IsGameStarted {
		t.Error("o jogo deveria ser marcado como não iniciado")
	}
}

func TestDeleteRoomIsNoOpForUnknownRoom(t *testing.T) {
	resetGlobalState()

	deleteRoom("inexistente") // não deve entrar em panic

	if len(rooms) != 0 {
		t.Errorf("esperava registro vazio, obtive %d salas", len(rooms))
	}
}

func TestGetRoomNamesListsEveryRoom(t *testing.T) {
	resetGlobalState()
	rooms["a"] = newRoom("a")
	rooms["b"] = newRoom("b")

	names := getRoomNames()

	if len(names) != 2 {
		t.Fatalf("esperava 2 nomes, obtive %d (%v)", len(names), names)
	}
	found := map[string]bool{}
	for _, name := range names {
		found[name] = true
	}
	for _, want := range []string{"a", "b"} {
		if !found[want] {
			t.Errorf("nome de sala %q ausente em %v", want, names)
		}
	}
}

func TestChooseRandomWordAlwaysReturnsSomething(t *testing.T) {
	// Não asserta distribuição: hoje wordsList tem um único elemento e o sorteio
	// usa time.Now().UnixNano()%n, que não é aleatório (BUG(R10)). O contrato
	// mínimo garantido é: nunca devolver string vazia.
	for i := 0; i < 20; i++ {
		if word := chooseRandomWord(); word == "" {
			t.Fatalf("iteração %d: palavra vazia", i)
		}
	}
}

func TestChooseRandomWordHandlesEmptyList(t *testing.T) {
	original := wordsList
	t.Cleanup(func() { wordsList = original })

	wordsList = nil

	if word := chooseRandomWord(); word == "" {
		t.Error("com lista vazia deve devolver a mensagem de fallback, não string vazia")
	}
}

func TestRoomNamesFormatting(t *testing.T) {
	// Guarda contra regressão no formato usado em logs/erros de sala cheia.
	got := fmt.Sprintf("Room %s is full. Maximum %d players allowed.", "sala", MaxPlayers)
	want := "Room sala is full. Maximum 4 players allowed."
	if got != want {
		t.Fatalf("mensagem de sala cheia mudou:\n  obtive %q\n  esperava %q", got, want)
	}
}
