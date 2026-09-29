package main

// Fonte única de verdade dos nomes de evento do socket, lado servidor.
//
// Espelha packages/drawly_core/lib/src/contracts/socket_events.dart.
// Qualquer mudança aqui exige a mudança correspondente do lado Dart, no mesmo
// commit. O teste de contrato (contracts_test.go) compara as duas listas.
const (
	// conexão
	EventConnect    = "connect"
	EventDisconnect = "disconnect"
	EventError      = "error"

	// sala
	EventRoomCreate             = "room:create"
	EventRoomCreated            = "room:created"
	EventRoomJoin               = "room:join"
	EventRoomLeave              = "room:leave"
	EventRoomAll                = "room:all"
	EventRoomParticipantsUpdate = "room:participants:update"

	// desenho
	EventDrawingStrokeStart      = "drawing:stroke:start"
	EventDrawingStrokeLastPoints = "drawing:stroke:lastPoints"
	EventDrawingStrokeAll        = "drawing:stroke:all"
	EventDrawingClear            = "drawing:clear"
	EventDrawingUndo             = "drawing:undo"
	EventDrawingRedo             = "drawing:redo"

	// chat
	EventChatMessage      = "chat:message"
	EventChatAnswerGuess  = "chat:answer:guess"
	EventChatAnswerResult = "chat:answer:result"

	// jogo
	EventGameTurnsStart = "game:turns:start"
	EventGameTurnNew    = "game:turn:new"
	EventGameRanking    = "game:ranking"
)

// AllEvents lista todos os eventos declarados, na mesma ordem de
// SocketEvents.all no lado Dart.
var AllEvents = []string{
	EventConnect,
	EventDisconnect,
	EventError,
	EventRoomCreate,
	EventRoomCreated,
	EventRoomJoin,
	EventRoomLeave,
	EventRoomAll,
	EventRoomParticipantsUpdate,
	EventDrawingStrokeStart,
	EventDrawingStrokeLastPoints,
	EventDrawingStrokeAll,
	EventDrawingClear,
	EventDrawingUndo,
	EventDrawingRedo,
	EventChatMessage,
	EventChatAnswerGuess,
	EventChatAnswerResult,
	EventGameTurnsStart,
	EventGameTurnNew,
	EventGameRanking,
}
