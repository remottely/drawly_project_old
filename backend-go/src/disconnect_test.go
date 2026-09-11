package main

import (
	"testing"
	"time"
)

// withShortGraceDelay encurta a tolerância de reconexão durante o teste.
//
// Sem esta costura o teste precisaria dormir 5 segundos reais — e o timer
// sobreviveria ao teste, tocando o estado global enquanto os testes seguintes
// rodam (é o que o -race acusava).
func withShortGraceDelay(t *testing.T, delay time.Duration) {
	t.Helper()
	original := disconnectGraceDelay
	disconnectGraceDelay = delay
	t.Cleanup(func() { disconnectGraceDelay = original })
}

// TestDisconnectMarksParticipantOffline verifica o efeito imediato da
// desconexão: o participante é marcado como offline e some do mapa de clientes,
// mas continua na sala durante a tolerância.
func TestDisconnectMarksParticipantOffline(t *testing.T) {
	resetGlobalState()
	withShortGraceDelay(t, veryLongDelay) // nunca dispara neste teste

	room := newRoom("room")
	participant := &Participant{UserId: "u1", Username: "one", IsConnected: true}
	room.addParticipant(participant)
	room.CurrentDrawerTurnIndex = 0
	rooms["room"] = room
	roomDrawings["room"] = &Drawing{}
	roomUsers["c1"] = &RoomUser{RoomName: "room", UserId: "u1", Username: "one"}

	disconnectParticipant(fakeBroadcaster{}, "c1")

	withState(func() {
		if _, exists := roomUsers["c1"]; exists {
			t.Error("o cliente deveria sair do mapa de usuários imediatamente")
		}
		if participant.IsConnected {
			t.Error("o participante deveria ser marcado como desconectado")
		}
		if _, stillInRoom := room.Participants["u1"]; !stillInRoom {
			t.Error("o participante não deve ser removido antes de esgotar a tolerância")
		}
	})
}

// TestDisconnectRemovesParticipantAfterGracePeriod verifica que, esgotada a
// tolerância sem reconexão, o participante sai da sala e a sala vazia é
// destruída.
func TestDisconnectRemovesParticipantAfterGracePeriod(t *testing.T) {
	resetGlobalState()
	withShortGraceDelay(t, 10*time.Millisecond)

	room := newRoom("room")
	participant := &Participant{UserId: "u1", Username: "one", IsConnected: true}
	room.addParticipant(participant)
	room.CurrentDrawerTurnIndex = 0
	rooms["room"] = room
	roomDrawings["room"] = &Drawing{}
	roomUsers["c1"] = &RoomUser{RoomName: "room", UserId: "u1", Username: "one"}

	disconnectParticipant(fakeBroadcaster{}, "c1")

	// A leitura passa pelo mesmo lock que o callback do timer usa: o estado é
	// compartilhado entre a goroutine do teste e a do time.AfterFunc.
	waitFor(t, func() bool {
		removed := false
		withState(func() {
			_, stillInRoom := room.Participants["u1"]
			removed = !stillInRoom
		})
		return removed
	}, "participante removido da sala após a tolerância")

	withState(func() {
		if _, exists := rooms["room"]; exists {
			t.Error("a sala deveria ser destruída ao ficar sem participantes")
		}
	})
}

// TestDisconnectKeepsParticipantWhenReconnected verifica que reconectar dentro
// da tolerância cancela a remoção.
//
// Regressão de R5: antes do stateMu, marcar IsConnected = true (o que o
// handleJoinRoom faz na goroutine do socket) enquanto o callback do
// time.AfterFunc lia o mesmo campo era data race — e `go test -race` derrubava
// este teste. Ele agora passa sob -race, o que é a prova de que o lock cobre o
// caminho de reconexão.
func TestDisconnectKeepsParticipantWhenReconnected(t *testing.T) {
	resetGlobalState()
	withShortGraceDelay(t, 30*time.Millisecond)

	room := newRoom("room")
	participant := &Participant{UserId: "u1", Username: "one", IsConnected: true}
	room.addParticipant(participant)
	room.CurrentDrawerTurnIndex = 0
	rooms["room"] = room
	roomDrawings["room"] = &Drawing{}
	roomUsers["c1"] = &RoomUser{RoomName: "room", UserId: "u1", Username: "one"}

	disconnectParticipant(fakeBroadcaster{}, "c1")

	// Reconexão: é isso que o handleJoinRoom faz ao reencontrar o participante —
	// e, como ele, sob o lock do estado.
	withState(func() { participant.IsConnected = true })

	time.Sleep(60 * time.Millisecond) // deixa a tolerância expirar

	withState(func() {
		if _, stillInRoom := room.Participants["u1"]; !stillInRoom {
			t.Error("quem reconecta dentro da tolerância não deve ser removido")
		}
	})
}

// TestDisconnectIsNoOpForUnknownClient garante que um disconnect de cliente que
// nunca entrou em sala não quebra nada.
func TestDisconnectIsNoOpForUnknownClient(t *testing.T) {
	resetGlobalState()
	withShortGraceDelay(t, veryLongDelay)

	disconnectParticipant(fakeBroadcaster{}, "cliente-desconhecido")

	withState(func() {
		if len(rooms) != 0 || len(roomUsers) != 0 {
			t.Error("desconexão de cliente desconhecido não deveria alterar o estado")
		}
	})
}

// waitFor faz polling até condition virar true, com timeout curto.
//
// Preferível a um sleep fixo: falha rápido quando o comportamento quebra e não
// desperdiça tempo quando funciona.
func waitFor(t *testing.T, condition func() bool, description string) {
	t.Helper()

	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if condition() {
			return
		}
		time.Sleep(2 * time.Millisecond)
	}
	t.Fatalf("timeout esperando: %s", description)
}
