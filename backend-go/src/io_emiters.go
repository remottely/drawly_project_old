package main

import (
	"sort"
)

// Requer stateMu.
func emitRoomList(io Broadcaster) {
	io.EmitAll(EventRoomAll, map[string]any{
		"allRooms": getRoomNames(),
	})
}

func emitDrawingState(io Broadcaster, roomName string, drawing *Drawing) {
	io.ToRoom(roomName, EventDrawingStrokeAll, map[string]interface{}{
		"strokes": drawing.Strokes,
	})
}

func emitJoinMessage(io Broadcaster, roomName, userId, username string) {
	icon := "info"
	message := Message{
		Icon:     &icon,
		UserId:   userId,
		Username: username,
		Text:     "entrou",
	}
	io.ToRoom(roomName, EventChatMessage, message)
}

func emitRoomError(io Broadcaster, roomName string, message string, action ErrorActionType) {
	io.ToRoom(roomName, EventError, ErrorDTO{
		Message: message,
		Action:  action,
	})
}

// Requer stateMu.
func emitRanking(io Broadcaster, roomName string) {
	room, exists := rooms[roomName]
	if !exists {
		return
	}

	// Calcular ranking
	ranking := make([]map[string]any, 0)
	participants := room.getParticipants()

	for _, participant := range participants {
		ranking = append(ranking, map[string]any{
			"username": participant.Username,
			"score":    participant.Score,
		})
	}

	// Ordenar por pontuação decrescente
	sort.Slice(ranking, func(i, j int) bool {
		return ranking[i]["score"].(uint16) > ranking[j]["score"].(uint16)
	})

	io.ToRoom(roomName, EventGameRanking, map[string]any{
		"ranking": ranking,
	})
}
