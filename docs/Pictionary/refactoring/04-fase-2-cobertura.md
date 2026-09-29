# Fase 2 — Cobertura alta sobre o código existente

**Status: 🔄 em andamento** — ver [09-estado-atual.md](09-estado-atual.md)

Objetivo: transformar o código atual em algo **seguro de refatorar**. Os testes desta fase
descrevem o comportamento **de hoje**, não o desejado. Onde o comportamento de hoje é
errado, o teste registra o fato com `// BUG(Rn):` e a correção vira commit `fix:` próprio.

## Metas

| Alvo | Mínimo | Racional |
|---|---|---|
| `drawly_core` | 90% | superfície pequena, é o contrato de rede |
| `drawing_board` domain + util | 90% | `bucket_fill`, `Stroke`, `UndoRedoStack` são pura lógica e o coração do produto |
| `drawing_board` presentation | 70% | widget/golden cobre o que importa; o resto é layout |
| app `lib/` | 85% em models/VM | páginas grandes ficam em widget test de fumaça |
| `backend-go/src` | 80% | regra de jogo inteira mora aqui |

## Ordem de ataque (maior risco × menor custo primeiro)

### 2.1 · `drawing_board` — lógica pura
Sem rede, sem widget, retorno imediato.

- `bucket_fill.dart` (278 linhas, o algoritmo mais complexo do repositório): fill em canvas
  vazio, contido por borda fechada, vazamento por borda aberta, respeito a `maxPixels`,
  círculo/quadrado/polígono preenchidos e vazados, `BucketStroke` prévio como barreira,
  expansão pós-fill proporcional à espessura do traço.
- `Stroke.fromJson` / `toJson` — round-trip dos 7 tipos, `fillPixels` ausente, `sides`
  e `filled` default, `strokeType` desconhecido caindo em `normal`.
- `UndoRedoStack` — undo/redo/clear, invalidação da pilha de redo ao desenhar,
  `rxCanRedo`, e o listener registrado no construtor.
- `calculateClampedPolygonRadius` — dentro, fora e exatamente no limite do canvas.
- `DrawingToolExtensions.strokeType` / `.cursor` — tabela completa.
- `OffsetExtensions` — ida e volta do escalonamento.

### 2.2 · `drawly_core`
- Todos os DTOs: `toJson` completo, herança (`RoomUserDTO` inclui `roomName` do pai).
- `ErrorDTO.fromJson` com ação inválida → `ArgumentError`.
- `SocketManager` **via a costura**: `on`/`off` (inclusive múltiplos listeners no mesmo
  evento e remoção do último), `emit`, `emitWithAck` sucesso / formato inválido / timeout,
  `clearListeners`.
- Teste de contrato `SocketEvents` ↔ `contracts.go`.

### 2.3 · App — models e controllers
- `Message.fromJson` com ícone desconhecido, `getIcon`/`getColor` por variante.
  ⚠️ `copyWith(icon: null)` **não limpa** o campo (`icon ?? this.icon`). É a semântica
  padrão de `copyWith` em Dart, mas contraria a expectativa do teste original.
  Registrar como `// BUG(A7)` e decidir na fase 3 (sentinela vs. `clearIcon`).
- `Answer.fromJson` herdando de `Message` + `isCorrect`.
- `Participant.fromJson`, incluindo `userAvatar` nulo.
- ViewModels com `FakeRealtimeGateway`: recebimento de `game:turn:new`, `chat:message`,
  `chat:answer:result`, `room:participants:update`; payload emitido em `sendMessage` /
  `sendAnswer`; `_joinGameRoom` com ack de sucesso, de falha e com exceção.
- `startCountdown` com `fake_async` (já existe; ampliar para cancelamento e reinício).

### 2.4 · Widget + golden
- **Reescrever os goldens de gesto.** Hoje eles dependem do eco do servidor (achado R9)
  e capturam canvas vazio. O novo desenho:
  - **golden** = semeia `rxAllStrokes` com strokes determinísticos e compara pixels.
    Testa o *painter*, que é o que realmente desenha.
  - **interação** = simula o gesto e verifica `rxCurrentStroke` + o payload emitido no
    `FakeRealtimeGateway`. Testa o *input*, sem depender de pixel.
  Isso separa duas responsabilidades que hoje estão fundidas em um único golden frágil.
- `HotkeyListener` — undo/redo por atalho, por plataforma.
- Fumaça de `DrawGameRoomSelectionPage`, `AnswersChatView`, `MessagesChatView`,
  `AllParticipants`: renderiza, reage a evento, não vaza no `dispose`.

### 2.5 · Backend Go
Os 13 arquivos existentes voltaram a rodar na fase 0, mas cobrem pouco. Adicionar:

- `Room`: `addParticipant`/`removeParticipant` (inclusive o último), `advanceTurn` pulando
  desconectados, `advanceTurn` sem ninguém conectado, `getParticipants` ordenando por
  score com desempate estável por `PreviousOrder`.
- `getCorrectAnswerRank` — **teste que expõe R2** (ordem de mapa) rodando N vezes e
  exigindo estabilidade. Deve falhar hoje; vira `fix:` separado.
- `hasEveryoneAnsweredCorrectly` com `getCurrentDrawer() == nil` — **expõe R3** (panic).
- `parseStroke` — todos os campos ausentes/errados, `filled` e `fillPixels` opcionais.
- `Drawing` — add/undo/redo/clear e a interação entre eles.
- `handleGuessAnswerChat` — pontuação, bônus, score do desenhista, avanço de turno quando
  todos acertam.
- `disconnectParticipant` — remoção após tolerância, e reconexão dentro da tolerância
  cancelando a remoção.
- Todo o pacote sob `-race` para expor R5.

## Regras desta fase

1. Teste que precisa de `sleep` real está errado: `fake_async` no Dart, variável de
   duração no Go.
2. Nenhum teste toca rede. Se precisou, falta uma costura.
3. Fixture vive em `test/support/`, nunca duplicada.
4. Golden só se regenera após inspeção visual do diff em `failures/`.
5. Um teste que falha por bug real **permanece falhando** até o commit `fix:`; não se
   ajusta a asserção para o comportamento errado. Se for bloquear o CI, marque
   `skip: 'BUG(Rn) — ver docs/.../01-achados.md'` com o link.

## Critério de saída

- [ ] metas de cobertura atingidas (pisos já travados — ver 09-estado-atual.md)
- [x] `./scripts/test.sh` verde (Dart + Go com `-race`)
- [ ] cada bug P1 do documento de achados tem um teste que o demonstra
- [x] nenhum teste depende de rede, disco ou relógio real

## Já executado

- [x] 2.1 `drawing_board` — Stroke (round-trip dos 7 tipos), extensões, polígono
- [x] 2.2 `drawly_core` — DTOs, `RealtimeSubscriptions`, fake, contrato Dart↔Go
- [x] 2.3 app — models e os dois ViewModels de chat com `FakeRealtimeGateway`
- [x] 2.4 goldens reescritos: render semeando `rxAllStrokes`, input verificando emissão
- [x] `drawly_design_system` — widgets (6,1% → 42,3%)
- [x] 2.5 parcial — `Room`, turnos, placar, desconexão, registro de salas

## Pendente

- [ ] 2.5 restante — `handleJoinRoom`, `handleGuessAnswerChat`, `startTurnTimer`
- [ ] `canvas_side_bar.dart` (552 linhas, maior buraco do `drawing_board`)
- [ ] `AllParticipants` e `DrawGameRoomSelectionPage`
- [ ] `SocketManager` com um duplo do `socket_io_client`
