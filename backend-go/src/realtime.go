package main

import "github.com/zishang520/socket.io/v2/socket"

// Broadcaster é a superfície de emissão que os handlers de evento precisam do
// servidor de tempo real: mandar para uma sala, para um cliente específico ou
// para todo mundo. Handler nunca depende de *socket.Server diretamente — só o
// adaptador de produção (serverBroadcaster) conhece a lib socket.io, então a
// regra de jogo é testável com um fake, sem rede.
type Broadcaster interface {
	ToRoom(room, event string, payload any)
	ToClient(clientID, event string, payload any)
	EmitAll(event string, payload any)
}

// ClientConn é a superfície que os handlers precisam de uma conexão de
// cliente: identidade, emissão direta e entrada/saída de sala. Mesma lógica do
// Broadcaster: handler depende disto, não de *socket.Socket.
type ClientConn interface {
	ID() string
	Emit(event string, payload any)
	Join(room string)
	Leave(room string)
	On(event string, handler func(args ...interface{}))
}

// serverBroadcaster adapta *socket.Server para Broadcaster.
type serverBroadcaster struct {
	io *socket.Server
}

func newBroadcaster(io *socket.Server) Broadcaster {
	return &serverBroadcaster{io: io}
}

func (b *serverBroadcaster) ToRoom(room, event string, payload any) {
	b.io.To(socket.Room(room)).Emit(event, payload)
}

// ToClient manda para um único cliente. Funciona porque todo socket entra
// automaticamente numa sala com o nome do seu próprio id ao conectar.
func (b *serverBroadcaster) ToClient(clientID, event string, payload any) {
	b.io.To(socket.Room(clientID)).Emit(event, payload)
}

func (b *serverBroadcaster) EmitAll(event string, payload any) {
	b.io.Emit(event, payload)
}

// socketClientConn adapta *socket.Socket para ClientConn.
type socketClientConn struct {
	socket *socket.Socket
}

func newClientConn(s *socket.Socket) ClientConn {
	return &socketClientConn{socket: s}
}

func (c *socketClientConn) ID() string { return string(c.socket.Id()) }

func (c *socketClientConn) Emit(event string, payload any) { c.socket.Emit(event, payload) }

func (c *socketClientConn) Join(room string) { c.socket.Join(socket.Room(room)) }

func (c *socketClientConn) Leave(room string) { c.socket.Leave(socket.Room(room)) }

func (c *socketClientConn) On(event string, handler func(args ...interface{})) {
	c.socket.On(event, func(args ...interface{}) { handler(args...) })
}
