# 12 — Ciclo do turno em volta do desenho

> Terceiro doc da série do desenho ([10](10-sistema-de-desenho.md) → [11](11-desenho-etapas-seguintes.md) → este).
> Cobre os três itens que o doc 11 marcou como fronteira: a palavra vazando para todos, a
> ausência de intervalo/escolha de palavra, e as dicas. Tudo aqui é **regra de jogo**, logo
> mora no servidor; o cliente só mostra estado (CLAUDE.md §2). Pressupõe o doc 06 (4.1, 4.3)
> e o E1 do doc 11.

---

## 1. O que está errado hoje, medido no código

| # | Problema | Onde |
|---|---|---|
| J1 | **A palavra vai para todos.** `Turn.Word` sai no `game:turn:new` para a sala inteira; o cliente só *esconde* para quem não desenha. Qualquer DevTools mostra a resposta. | `room_game.go` `startTurnTimer` |
| J2 | **Não existe fim de partida.** `startTurnTimer` se reagenda para sempre; `TurnCount` é `uint8` e dá a volta em 256. | `room_game.go` |
| J3 | **Bônus por tempo usa o número do turno.** `timeLeft := room.TurnCount` com o comentário "ajuste para obter o valor real". O bônus cresce com a partida, não com a rapidez. | `events.go` `handleGuessAnswerChat` |
| J4 | **Duração do turno hardcoded** em três chamadas (`60`), e o cliente compensa latência com `rxTotalDuration - 300` chutado. | `events.go`, `draw_game_room_page.dart` |
| J5 | **Sem intervalo entre turnos.** O `game:turn:new` do turno N+1 sai no mesmo instante em que o N acaba: ninguém vê a resposta, o placar do turno, nem quem desenha a seguir. | `room_game.go` |
| J6 | **Sem escolha de palavra nem dica.** `chooseRandomWord` sorteia 1 palavra de uma lista de 1 (R10); nenhum mecanismo de dica. | `room_game.go` |
| J7 | **Quem entra no meio do turno pode chutar mas não recebe a máscara da palavra**, e a regra de "todos acertaram" conta com ele (bug listado no MVP). | `events.go` `handleJoinRoom`, `room.go` |

---

## 2. Máquina de estados do turno (servidor)

```
lobby ──start──▶ choosing ──pick/timeout──▶ drawing ──all guessed/timeout──▶ reveal ──▶ choosing …
                                                                                   └─▶ over (rodadas esgotadas ou teto de pontos)
```

| Estado | Duração (default, env) | Quem age | O servidor emite |
|---|---|---|---|
| `lobby` | — | dono da sala dá start | `game:state` |
| `choosing` | 10 s | desenhista escolhe 1 de 3 | `game:turn:choose` **só ao desenhista** (3 palavras); `game:state` aos demais (quem desenha, sem palavras) |
| `drawing` | 60 s | desenhista desenha, outros chutam | `game:turn:new` ao desenhista (**com** palavra) e aos demais (**só máscara** `_ _ _ _ _`) |
| `reveal` | 5 s | ninguém | `game:turn:end` (palavra, quem acertou, pontos do turno) |
| `over` | — | — | `game:over` (ranking final); sala volta a `lobby` |

Regras:

- **Rodada** = cada participante conectado desenhou uma vez. Partida = `rounds` rodadas (default 3, env). Fim antecipado quando alguém atinge `maxScore` (opcional, 0 = desligado).
- Timeout de `choosing` escolhe a primeira palavra. Desenhista que cai em `choosing` ou `drawing` **encerra o turno** (vai para `reveal` sem pontos), não trava a sala.
- Quem entra em `drawing` recebe a máscara e as dicas já reveladas, pode chutar, e **conta** na regra "todos acertaram" só a partir do turno seguinte (J7).
- `TurnCount` vira `uint16` e passa a ser `rodada × turno`; o cliente mostra "Rodada 2/3".

Tudo isso é uma `TurnMachine` pura em `internal/game` (doc 06, 4.2), com `Scheduler` injetado
(doc 06, 4.5). Zero socket: o handler traduz transições em emissões via `Broadcaster`.

---

## 3. Contrato (adições, ambos os lados no mesmo commit)

| Evento | Direção | Payload | Nota |
|---|---|---|---|
| `game:state` | ↓ sala | `{phase, round, rounds, turn, drawerUserId, endsAt, wordMask, hints}` | estado completo; é o que o snapshot de sala entrega ao join |
| `game:turn:choose` | ↓ desenhista | `{words: [a, b, c], endsAt}` | só o desenhista recebe as palavras |
| `game:word:pick` | ↑ | `{index}` | validado: fase `choosing`, remetente = desenhista |
| `game:turn:new` | ↓ | desenhista: `{…, word}`; demais: `{…, wordMask}` | **duas emissões**, `ToClient` + `ToRoomExcept` — é o que fecha J1 |
| `game:hint` | ↓ sala (menos desenhista e quem já acertou) | `{index, letter}` | revelação progressiva |
| `game:turn:end` | ↓ sala | `{word, scores: [{userId, delta}], nextDrawerUserId}` | tela de `reveal` |
| `game:over` | ↓ sala | `{ranking}` | substitui o `game:ranking` sob demanda |

`endsAt` é **timestamp do servidor** (ms Unix). O cliente calcula o restante contra o relógio
local corrigido por um offset medido no join (`emitWithAck` de `time:sync` devolvendo `now`).
Some o `- 300` chutado (J4) e o timer deixa de dessincronizar entre salas (item do MVP).

Dicas: a cada `hintInterval` (default 20 s, env) o servidor revela uma letra **determinística**
(`rand` semeado por `roomName + turn`, testável) até `maxHints` (default `len/3`). Quem já
acertou recebe a palavra inteira, não dicas.

Pontuação (J3), toda no servidor e em `internal/game/score.go`:

```
acertador: base(rank) + bonus(restante)   base = 100 − 20·(rank−1), mínimo 10
                                           bonus = restante_ms / duração_ms · 50
desenhista: 100 / (participantes − 1) por acerto
```

`rank` sai de uma slice ordenada por chegada (fecha R2).

---

## 4. Cliente

`GameRoomController` (doc 05, 3.2 passo 4) absorve a fase: `phase`, `round/rounds`,
`endsAt`, `wordMask`, `hints`, `word` (só desenhista). Chama `drawing.startTurn` /
`drawing.endTurn` (doc 11, E1) nas transições. A página vira três *overlays* sobre o mesmo
canvas: escolha de palavra (desenhista), "Fulano está escolhendo…" (demais), tela de reveal
com a palavra e os pontos do turno. Chat de respostas bloqueia fora de `drawing`.

Nada de regra: o cliente não sabe quantos pontos vale um acerto nem quando o turno acaba —
só desenha o que `game:state` diz.

---

## 5. Commits

| # | Commit | Teste que trava antes | Fecha |
|---|---|---|---|
| T1 | `feat: send the word only to the drawer and a mask to everyone else` | handler com spy: duas emissões, a da sala sem `word` | J1 |
| T2 | `refactor: extract a pure turn state machine with an injected scheduler` | tabela transição × evento; timeouts sem dormir | J2, J5, 4.5 |
| T3 | `feat: add the choosing and reveal phases with a configurable turn duration` | máquina + handler: pick válido/inválido, timeout escolhe a primeira | J4, J5, J6 |
| T4 | `fix: base the guess bonus on time left instead of the turn number` | score: mesmo rank, mais restante ⇒ mais pontos | J3 |
| T5 | `feat: reveal letter hints on a deterministic schedule` | seed fixa ⇒ mesma sequência; quem acertou não recebe dica | J6 |
| T6 | `feat: end the game after the configured rounds and emit the final ranking` | rodada completa; `over` volta a `lobby`; teto de pontos | J2 |
| T7 | `feat: sync the client clock with the server and drive countdowns by endsAt` | controller com `Clock` falso; offset aplicado | J4 |
| T8 | `feat: let late joiners guess without blocking the everyone-guessed rule` | join em `drawing` recebe máscara e dicas; não conta neste turno | J7 |
| T9 | `feat: pick words from themed lists loaded from a file` | lista carregada por env; R10 fechado com `math/rand` | R10 |

Dependências: T1 é independente e é o mais urgente (trapaça). T2 antes de T3/T5/T6/T8.
T7 independente. T9 independente.

---

## 6. Critério de saída

- Nenhum payload para quem adivinha contém a palavra, provado por teste de handler.
- Partida termina; `TurnCount` nunca dá a volta.
- Duração, rodadas, intervalo de dica e teto de pontos vêm de env var com default.
- Todo timer do turno é testado com `Scheduler` virtual, sem `sleep`.
- O cliente não contém nenhuma constante de pontuação nem de duração.
