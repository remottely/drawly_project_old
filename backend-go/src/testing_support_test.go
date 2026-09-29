package main

import "time"

// veryLongDelay é usado quando um teste precisa de um timer que existe mas nunca
// dispara durante a execução.
const veryLongDelay = time.Hour

// resetGlobalState zera os três mapas globais do servidor.
//
// Enquanto o estado do jogo for global (achado R5/4.4), todo teste que os toca
// precisa limpá-los primeiro — senão a ordem de execução dos testes muda o
// resultado. Esta função existe para que essa limpeza seja feita em um lugar só;
// ela desaparece quando o RoomRegistry da fase 4 for introduzido.
func resetGlobalState() {
	rooms = make(map[string]*Room)
	roomDrawings = make(map[string]*Drawing)
	roomUsers = make(map[string]*RoomUser)
}

// participantWithScore monta um participante conectado com um score inicial.
func participantWithScore(userID string, score uint16) *Participant {
	return &Participant{
		UserId:      userID,
		Username:    "user-" + userID,
		IsConnected: true,
		Score:       score,
	}
}

// fakeBroadcaster e fakeClientConn substituem o socket.io real nos testes de
// handler: a regra de jogo fica testável sem abrir um socket, e sem depender
// de um *socket.Server/*socket.Socket real inicializado. Só main.go conhece a
// lib socket.io de verdade (via serverBroadcaster/socketClientConn).
type fakeBroadcaster struct{}

func (fakeBroadcaster) ToRoom(room, event string, payload any)       {}
func (fakeBroadcaster) ToClient(clientID, event string, payload any) {}
func (fakeBroadcaster) EmitAll(event string, payload any)            {}

type fakeClientConn struct {
	id string
}

func (c *fakeClientConn) ID() string                                         { return c.id }
func (c *fakeClientConn) Emit(event string, payload any)                     {}
func (c *fakeClientConn) Join(room string)                                   {}
func (c *fakeClientConn) Leave(room string)                                  {}
func (c *fakeClientConn) On(event string, handler func(args ...interface{})) {}
