# Fase 4 — Refatoração arquitetural (Go)

**Status: ⏳** — depende da fase 2 (cobertura ≥80% no backend).

---

## 4.1 · Corrigir os bugs P1

| Ordem | Achado | Correção |
|---|---|---|
| 1 | R5 | proteger o estado global com `sync.RWMutex` — pré-requisito de tudo, e `-race` prova |
| 2 | R2 | `getCorrectAnswerRank` passa a usar slice ordenado por chegada, não iteração de mapa |
| 3 | R3 | `hasEveryoneAnsweredCorrectly` retorna `false` quando não há desenhista, em vez de deref nil |
| 4 | R4 | toda type assertion vira `v, ok := x.(T)` com erro devolvido ao cliente |
| 5 | R10 | `math/rand` e a lista de palavras completa restaurada |
| 6 | H4 | tratar o erro de `http.ListenAndServe` |

R5 primeiro **de propósito**: mexer em concorrência depois de mover arquivos é muito
mais difícil de revisar.

---

## 4.2 · Sair do `package main` monolítico

```
backend-go/
├── cmd/server/main.go            # só wiring: config, servidor, shutdown
└── internal/
    ├── config/                   # env vars com default
    ├── contracts/                # nomes de evento + payloads (espelha SocketEvents)
    ├── game/                     # Room, Participant, Drawing, Stroke, turnos, score
    │                             #   → zero import de socket.io. Testável puro.
    ├── registry/                 # RoomRegistry com mutex (substitui os 3 mapas globais)
    └── transport/                # handlers socket.io: parse → chama game → broadcast
```

Fronteira dura: `internal/game` **não** importa `socket.io`. Se importar, a regra de jogo
voltou a ser intestável.

Ordem: `game` primeiro (é o que tem valor e já terá cobertura), depois `registry`,
depois `transport`, `cmd` por último.

---

## 4.3 · `Broadcaster` — inverter a dependência de I/O

```go
type Broadcaster interface {
    ToRoom(room, event string, payload any)
    ToClient(clientID, event string, payload any)
}
```

Handlers passam a receber `Broadcaster` em vez de `*socket.Server`. Em produção, um
adaptador fino sobre socket.io; em teste, um `SpyBroadcaster` que grava as emissões.

Isso remove a última razão para um teste de backend precisar de servidor real, e é o que
permite testar de verdade `handleJoinRoom`, `handleGuessAnswerChat` e `startTurnTimer`.

---

## 4.4 · `RoomRegistry` — matar os globais

`rooms`, `roomDrawings` e `roomUsers` viram campos de um `RoomRegistry` com `RWMutex`,
instanciado no `main` e injetado. Ganhos: fim do estado global, fim da poluição entre
testes (hoje cada teste precisa reatribuir os três mapas na mão), e concorrência
controlada em um lugar só.

---

## 4.5 · Controle de tempo

`startTurnTimer` se agenda recursivamente via `time.AfterFunc`. Testar isso hoje exige
`sleep`. Alvo: uma interface `Scheduler` de uma função:

```go
type Scheduler interface {
    AfterFunc(d time.Duration, f func()) Timer
}
```

Produção usa `time`; teste usa um scheduler de tempo virtual que avança sob demanda.

---

## 4.6 · Decidir sobre os forks vendorizados (achado A10)

`external/socket.io`, `external/engine.io` e `external/labstack/gommon` estão presos por
`replace` no `go.mod`, sem nota do motivo.

Ação, nesta ordem:
1. `diff` contra a tag upstream correspondente para descobrir o delta real.
2. Se o delta for zero → remover `replace`, voltar ao upstream. Melhor resultado.
3. Se houver patch necessário → documentar em `backend-go/external/README.md` (o quê, por
   quê, e a issue upstream), e criar um lembrete de reavaliação.

Fork não documentado é dívida que ninguém consegue pagar depois.

---

## 4.7 · Configuração e segurança

- Porta, origens CORS, `log.DEBUG`, duração de turno e tolerância de reconexão vindas de
  env var com default.
- Handshake com token real em vez de `Authorization: Bearer token` literal; o servidor
  para de forçar `IsLogged: true` (achado H11).
- Limite de tamanho e validação de `fillPixels` — hoje um cliente pode mandar payload
  arbitrariamente grande (há um `SetMaxHttpBufferSize(1MB)`, mas nenhuma validação de
  domínio).

---

## Critério de saída

- [ ] `go test -race ./...` verde
- [ ] `internal/game` sem nenhum import de socket.io
- [ ] nenhuma variável global mutável
- [ ] nenhuma type assertion sem `ok`
- [ ] nenhum valor de configuração hardcoded
- [ ] `external/` com README explicando cada fork, ou removido
