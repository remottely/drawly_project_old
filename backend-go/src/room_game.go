package main

import (
	"time"
)

var wordsList = []string{
	"r",
	// "gato", "cachorro", "casa", "carro", "árvore", "flor", "sol", "lua",
	// "livro", "avião", "rio", "montanha", "praia", "peixe", "pássaro",
	// "computador", "telefone", "cadeira", "mesa", "namorados", "corda",
	// "futebol", "bola", "cama", "travesseiro", "cobertor", "chave", "porta",
}

// afterFunc é o agendador usado pelo jogo. É uma variável de pacote para que o
// teste possa substituir o relógio real por um controlado, em vez de dormir.
var afterFunc = time.AfterFunc

func chooseRandomWord() string {
	if len(wordsList) == 0 {
		return "Nenhuma palavra disponível."
	}
	randomIndex := time.Now().UnixNano() % int64(len(wordsList))
	return wordsList[randomIndex]
}

// startTurnTimer encerra o turno atual e inicia o próximo.
//
// Requer stateMu: é chamada pelos handlers (que já travam) e pelos callbacks de
// timer (que travam via withState). Não adquire o lock por conta própria — o
// mutex não é reentrante e ela chama a si mesma pelo timer.
func startTurnTimer(io Broadcaster, roomName string, totalDuration uint32) {
	room, exists := rooms[roomName]
	if !exists {
		return
	}

	// Cancela o timer anterior, se existir
	cancelActiveTimer(room)

	room.advanceTurn()

	currentDrawer := validateCurrentDrawer(io, room, roomName)
	if currentDrawer == nil {
		return // Retorna se não houver desenhista válido
	}

	// Resetar estado para o novo turno
	room.resetCorrectAnswers()
	roomDrawings[roomName].clear()

	wordToDraw := chooseRandomWord()
	room.CurrentWord = wordToDraw

	io.ToRoom(roomName, EventGameTurnNew, Turn{
		Word:                  wordToDraw,
		Turn:                  room.TurnCount,
		TotalDuration:         totalDuration * 1000,
		CurrentDrawerUserId:   currentDrawer.UserId,
		CurrentDrawerUsername: currentDrawer.Username,
		IsGameStarted:         room.IsGameStarted,
	})

	io.ToRoom(roomName, EventRoomParticipantsUpdate, map[string]any{
		"participants": room.getParticipants(),
	})

	// Configura o novo timer
	room.ActiveTimer = afterFunc(time.Duration(totalDuration)*time.Second, func() {
		// Roda em goroutine própria: precisa adquirir o lock do estado.
		withState(func() {
			logInfo("Timer executado para a sala %s.\n", roomName)
			startTurnTimer(io, roomName, totalDuration)
		})
	})
	logInfo("Novo timer configurado para a sala %s.\n", roomName)
}
