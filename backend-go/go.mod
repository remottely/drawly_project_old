module drawly-server

go 1.25.0

require github.com/zishang520/socket.io/v2 v2.3.6 // usa a versão 2.x

require (
	github.com/labstack/gommon v0.4.2
	github.com/zishang520/engine.io/v2 v2.2.5
)

require (
	github.com/andybalholm/brotli v1.1.1 // indirect
	github.com/go-task/slim-sprig v0.0.0-20230315185526-52ccab3ef572 // indirect
	github.com/google/pprof v0.0.0-20230821062121-407c9e7a662f // indirect
	github.com/gookit/color v1.5.4 // indirect
	github.com/gorilla/websocket v1.5.3 // indirect
	github.com/onsi/ginkgo/v2 v2.12.0 // indirect
	github.com/quic-go/qpack v0.5.1 // indirect
	github.com/quic-go/quic-go v0.48.2 // indirect
	github.com/quic-go/webtransport-go v0.0.0-20241018022711-4ac2c9250e66 // indirect
	github.com/vmihailenco/msgpack/v5 v5.4.1 // indirect
	github.com/vmihailenco/tagparser/v2 v2.0.0 // indirect
	github.com/xo/terminfo v0.0.0-20210125001918-ca9a967f8778 // indirect
	github.com/zishang520/engine.io-go-parser v1.2.7 // indirect
	github.com/zishang520/socket.io-go-parser/v2 v2.2.3 // indirect
	go.uber.org/mock v0.5.2 // indirect
	golang.org/x/crypto v0.54.0 // indirect
	golang.org/x/exp v0.0.0-20240506185415-9bf2ced13842 // indirect
	golang.org/x/mod v0.37.0 // indirect
	golang.org/x/net v0.56.0 // indirect
	golang.org/x/sync v0.22.0 // indirect
	golang.org/x/sys v0.47.0 // indirect
	golang.org/x/text v0.40.0 // indirect
	golang.org/x/tools v0.47.0 // indirect
)

// Indica que o módulo `github.com/zishang520/socket.io/v2` é local
replace github.com/labstack/gommon => ./external/labstack/gommon
