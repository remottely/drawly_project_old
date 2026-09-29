package main_test

// import (
// 	"net/http"
// 	"testing"
// 	"time"

// 	// "drawly-server/src/app"

// 	"github.com/stretchr/testify/assert"
// 	"github.com/zishang520/socket.io/v2/socket"
// )

// func TestRoomLeave(t *testing.T) {
// 	// Configuração do servidor Socket.IO
// 	io := socket.NewServer(nil, nil)
// 	defer io.Close(nil)

// 	http.Handle("/socket.io/", io.ServeHandler(nil))
// 	go http.ListenAndServe(":5555", nil)

// 	// como eu importo a struct Room e Drawing do pacote main?
// 	rooms := map[string]*Room{}
// 	roomDrawings := map[string]*Drawing{}

// 	io.On("connection", func(clients ...interface{}) {
// 		client := clients[0].(*socket.Socket)

// 		// Evento: Criar Sala
// 		client.On("room:create", func(args ...interface{}) {
// 			data := args[0].(map[string]interface{})
// 			roomName := data["roomName"].(string)
// 			if _, exists := rooms[roomName]; !exists {
// 				rooms[roomName] = NewRoom(roomName)
// 				roomDrawings[roomName] = &Drawing{}
// 				io.Emit("room:list:update", map[string]interface{}{
// 					"rooms": getRoomNames(),
// 				})
// 			}
// 		})

// 		// Evento: Entrar na Sala
// 		client.On("room:join", func(args ...interface{}) {
// 			data := args[0].(map[string]interface{})
// 			roomName := data["roomName"].(string)
// 			userId := data["userId"].(string)
// 			username := data["username"].(string)

// 			room, exists := rooms[roomName]
// 			if !exists {
// 				client.Emit("room:error", "Room does not exist")
// 				return
// 			}

// 			participant := &Participant{
// 				UserId:      userId,
// 				Username:    username,
// 				IsLogged:    true,
// 				IsConnected: true,
// 			}
// 			room.AddParticipant(participant)
// 			client.Join(socket.Room(roomName))
// 			io.To(socket.Room(roomName)).Emit("room:participants:update", map[string]interface{}{
// 				"participants": room.GetParticipants(),
// 			})
// 		})

// 		// Evento: Sair da Sala
// 		client.On("room:leave", func(args ...interface{}) {
// 			data := args[0].(map[string]interface{})
// 			roomName := data["roomName"].(string)
// 			userId := data["userId"].(string)

// 			if room, exists := rooms[roomName]; exists {
// 				room.RemoveParticipant(userId)
// 				client.Leave(socket.Room(roomName))

// 				io.To(socket.Room(roomName)).Emit("room:participants:update", map[string]interface{}{
// 					"participants": room.GetParticipants(),
// 				})

// 				if len(room.GetParticipants()) == 0 {
// 					delete(rooms, roomName)
// 					delete(roomDrawings, roomName)
// 					io.Emit("room:list:update", map[string]interface{}{
// 						"rooms": getRoomNames(),
// 					})
// 				}
// 			}
// 		})
// 	})

// 	// Configuração do cliente Socket.IO
// 	client, err := socket.NewClient("http://localhost:5555", nil)
// 	assert.NoError(t, err)
// 	defer client.Close()

// 	var participantsUpdated bool
// 	var roomListUpdated bool

// 	client.On("room:participants:update", func(data ...interface{}) {
// 		participantsUpdated = true
// 	})

// 	client.On("room:list:update", func(data ...interface{}) {
// 		roomListUpdated = true
// 	})

// 	// Conecta ao servidor
// 	err = client.Connect()
// 	assert.NoError(t, err)

// 	// Criar sala
// 	client.Emit("room:create", map[string]interface{}{
// 		"roomName": "testRoom",
// 	})
// 	time.Sleep(500 * time.Millisecond)

// 	// Entrar na sala
// 	client.Emit("room:join", map[string]interface{}{
// 		"roomName": "testRoom",
// 		"userId":   "user1",
// 		"username": "User 1",
// 	})
// 	time.Sleep(500 * time.Millisecond)

// 	// Sair da sala
// 	client.Emit("room:leave", map[string]interface{}{
// 		"roomName": "testRoom",
// 		"userId":   "user1",
// 	})
// 	time.Sleep(500 * time.Millisecond)

// 	// Verificações
// 	assert.True(t, participantsUpdated, "Expected room:participants:update to be emitted")
// 	assert.True(t, roomListUpdated, "Expected room:list:update to be emitted")
// }
