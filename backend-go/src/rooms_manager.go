package main

var (
	rooms        = make(map[string]*Room)
	roomDrawings = make(map[string]*Drawing)
	roomUsers    = make(map[string]*RoomUser)
)

func newRoom(name string) *Room {
	return &Room{
		Name:                             name,
		Participants:                     make(map[string]*Participant),
		ParticipantsWhoAnsweredCorrectly: make(map[string]bool),
	}
}

// createRoom registra uma sala nova, se ainda não existir.
//
// Requer stateMu.
func createRoom(io Broadcaster, client ClientConn, roomName string) {
	if _, exists := rooms[roomName]; !exists {
		rooms[roomName] = newRoom(roomName)
		roomDrawings[roomName] = &Drawing{}
		emitRoomList(io) // Atualiza a lista de salas
		client.Emit(EventRoomCreated, map[string]interface{}{"roomName": roomName})
	}
}

// deleteRoom remove a sala e libera seus recursos.
//
// Requer stateMu.
func deleteRoom(roomName string) {
	room, exists := rooms[roomName]
	if exists {
		cancelActiveTimer(room)
		room.IsGameStarted = false
		delete(rooms, roomName)
		delete(roomDrawings, roomName)
	}
}

// getRoomNames lista os nomes das salas ativas.
//
// Requer stateMu.
func getRoomNames() []string {
	names := make([]string, 0, len(rooms))
	for name := range rooms {
		names = append(names, name)
	}
	return names
}
