package main

import "sync"

// stateMu protege todo o estado mutável compartilhado do servidor: os mapas
// globais (rooms, roomDrawings, roomUsers) e tudo que é alcançável a partir
// deles (Room, Participant, Drawing).
//
// Por que um mutex único e grosso, e não um por sala:
//
//   - as operações são curtas e puramente em memória (nenhuma I/O sob o lock);
//   - várias operações cruzam salas (emitRoomList, deleteRoom) e precisariam de
//     ordenação de locks para evitar deadlock;
//   - o gargalo real do servidor é a rede, não a contenção deste mutex.
//
// KISS: um lock correto vale mais que vários locks sutilmente errados. Se o
// perfil mostrar contenção, granularizar depois — com o -race como rede.
//
// # Disciplina de uso (mutex NÃO é reentrante)
//
// O lock é adquirido apenas nos pontos de entrada:
//
//   - cada handler de evento do socket (handleXxx);
//   - cada callback de timer (time.AfterFunc).
//
// Funções internas — métodos de Room/Drawing, startTurnTimer, emit*, deleteRoom
// — assumem o lock já adquirido e NUNCA o adquirem. Toda função nessa condição
// está marcada com o comentário "Requer stateMu.".
var stateMu sync.Mutex

// withState executa fn com o estado global travado.
//
// Usado pelos callbacks de timer, que rodam em goroutine própria e são a origem
// das corridas com os handlers.
func withState(fn func()) {
	stateMu.Lock()
	defer stateMu.Unlock()
	fn()
}
