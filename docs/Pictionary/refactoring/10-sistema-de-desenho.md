# 10 — Sistema de desenho: protocolo, modelo e render

> Plano executável do refactor do desenho. Detalha o que os docs
> [05](05-fase-3-arquitetura-dart.md) (3.1 R9/R13, 3.2 passo 5, 3.3) e
> [06](06-fase-4-arquitetura-go.md) (4.3, 4.7) deixaram em aberto para o canvas.
> Quando um passo daqui conclui, o item correspondente lá é marcado.

---

## A decisão em uma página

| Eixo | Decisão |
|---|---|
| **Contrato** | Os 6 eventos de desenho viram 2: `drawing:op` (lote de operações, sobe e desce) e `drawing:snapshot` (estado inteiro, servidor → **um** socket). Pontos viajam como inteiros em décimos de pixel lógico, em array plano. Sem `{dx,dy}`, sem cor como objeto, sem `roomName` no caminho quente, **nunca** `fillPixels`. |
| **Autoridade** | Só o desenhista do turno atual pode emitir. O servidor valida remetente, turno, ids e limites; rejeição devolve `error` + snapshot ao remetente. Undo/redo/clear sobem como comandos e descem como fatos (`remove`, re-inserção, `clear`). |
| **Eco** | O desenhista pinta local na hora (echo otimista, R9) e **não** recebe o próprio eco (`client.To(room)`). Corta os pacotes descendentes de N para N−1 e elimina o `_awaitingBucketAck`. |
| **Determinismo** | Quantização na origem: o desenhista guarda os mesmos inteiros que envia. Todo peer tem dados bit a bit iguais, logo o balde — calculado localmente por cada peer — dá o mesmo resultado em todos. |
| **Render** | Duas camadas: traços concluídos num `RepaintBoundary` que só repinta quando a lista muda, traço em andamento numa camada própria. `Path` cacheado por stroke. Balde vira um `Path` de spans (um `drawPath`, não 140 mil `drawRect`). |
| **Balde** | Raster tipado (`Uint32List`) amostrado no centro da célula + flood fill 4-conexo por scanline — **já em andamento na árvore de trabalho** (sessão paralela, não commitado), com os testes do R13 reescritos. O plano acrescenta o que falta: entradas inteiras (determinismo entre peers), spans como representação e a função no domínio. |
| **Offline** | Nunca emitir desconectado. Ao reconectar, o snapshot do servidor substitui o estado local. O que foi desenhado offline se perde, por definição. |

Números medidos hoje × alvo (seção 9): 47 → 9 bytes por ponto, 245 → ≤ 90 bytes por
flush, 176 KB → ≤ 40 KB por snapshot de um turno inteiro, N → N−1 pacotes descendentes por
operação, broadcast do snapshot para a sala inteira → só para quem entrou.

---

## 1. Diagnóstico medido

Cada linha é um problema verificado no código atual, não uma opinião. Os números vêm de um
script `dart` que serializa payloads como o app faz (seção 9 explica como reproduzir).

| # | Problema | Onde | Evidência |
|---|---|---|---|
| D1 | **Ponto custa 47 bytes.** `{"dx":75.46272798898713,"dy":169.7655802826502}` — double completo porque o `Listener` fica dentro do `Transform.scale` e entrega coordenadas com 16 casas. | `stroke.dart` `toJson`, `socket_dtos.dart` | flush de 4 pontos = **245 B**; `stroke:start` = **218 B** (cor como 5 campos + `colorSpace`); snapshot de 60 s desenhando = **176 KB** |
| D2 | **Eco ao remetente.** `io.To(room).Emit` inclui o desenhista, que depende do eco para ver o próprio traço (R9). É o que obriga a gambiarra `_awaitingBucketAck`. | `events.go` `handleStartStrokeDrawing` | numa sala de 2, metade do tráfego descendente é o desenhista recebendo o que acabou de enviar |
| D3 | **Snapshot em broadcast.** `emitDrawingState` usa `io.To(room)`: cada join ou reconexão de qualquer participante reenvia o desenho inteiro para **todos**, que reparseiam tudo e recomputam todos os baldes. | `events.go` `handleJoinRoom`, `io_emiters.go` | `rxAllStrokes.value = parsedStrokes` em todo cliente a cada join |
| D4 | **Qualquer socket desenha.** Nenhum handler de desenho verifica desenhista, turno ou `IsGameStarted`. Traços do turno anterior que chegam depois de `game:turn:new` entram no turno novo (bug já listado no MVP). | `events.go` | handlers só checam `roomDrawings[roomName]` existir |
| D5 | **Replay offline.** `socket_io_client` 3.0.2 guarda `emit` em `sendBuffer` enquanto desconectado e descarrega tudo ao reconectar. `lastPoints` não tem id: se anexa a *qualquer* último stroke. É a origem de "ao ressincronizar envia um monte de linhas aleatórias". | `socket.dart` l.197 e l.545 da lib; `drawing.go` `addStrokeLastPoints` | reproduzível: desenhar, cair, voltar |
| D6 | **Balde no render.** No último commit, um `drawRect` **por pixel** de `fillPixels` (até ~141 mil por balde), com `shouldRepaint => true` e repaint a cada movimento de ponteiro. **Em andamento na árvore de trabalho:** um `Path` de spans cacheado por stroke (`bucketFillPath` + `Expando`) resolve o `drawRect`; o `shouldRepaint => true` e o repaint total por frame continuam (D4). | `drawing_canvas.dart` `_DrawingCanvasPainter.paint` | `git diff` de `drawing_canvas.dart` |
| D7 | **Balde no cálculo.** No último commit, `Map<Offset, Color>` + `Set<Offset>` + `Queue<Offset>` com `Offset` boxed para 141 mil células. **Em andamento na árvore de trabalho:** raster `Uint32List` amostrado no centro da célula, fill 4-conexo por scanline, formas preenchidas por scanline — resolve o custo. O que **continua** em aberto: a saída ainda é `List<Offset>` boxed, e cada peer calcula sobre dados que **não** são idênticos — o desenhista tem os doubles originais, os outros têm o que voltou do JSON. Amostrar no centro da célula tolera diferenças pequenas; não garante igualdade. | `bucket_fill.dart` | `git diff` de `bucket_fill.dart`; TODO do MVP: "limite muito baixo" |
| D8 | **Traço em andamento é O(n²).** `addPoint` copia a lista inteira a cada ponto e cada cópia repinta todos os strokes da tela. | `current_stroke_value_notifier.dart` | `List<Offset>.from(value?.points)..add(point)` |
| D9 | **Largura depende da janela do desenhista.** `size: size / scale`: a mesma posição do slider gera larguras lógicas diferentes conforme o tamanho da janela, e os viewers veem espessura relativa diferente da do desenhista. | `drawing_canvas.dart` `onPointerDown` | slider 6 numa janela com `scale` 2,8 vira `w = 2.1` no wire |
| D10 | **Formas acumulam pontos inúteis.** Linha, quadrado, círculo e polígono usam só o primeiro e o último ponto, mas todos os pontos do arrasto são enviados, armazenados e devolvidos no snapshot. | `drawing_canvas.dart`, `drawing.go` | um círculo arrastado por 3 s ≈ 180 pontos |
| D11 | **Modelo frágil.** `Stroke` mutável (`fillPixels` sem `final`; `points` mutado in place pelo handler), sem `==`, com `DateTime.now()` (A7); `StrokeType` serializa por `toString()` (A8); `DrawingTool.fill` e `ToolType` mortos (R1). No Go, `Opacity uint8` recebe `uint8(opacityFloat64)`: opacidade 0,5 vira 0. | `stroke.dart`, `stroke.go` | — |
| D12 | **O backend compila contra stubs, não forks.** `backend-go/external/socket.io/socket/server.go` tem 47 linhas, `Emit` vazio e `ServeHandler` no-op (commit 12bd699, "stubs for offline builds"); o `replace` do `go.mod` aponta para eles e a lib real (v2.3.6) nem está no cache de módulos. Os testes passam `&socket.Server{}` porque nada acontece; o servidor real só existe sem o `replace`. O achado A10 está errado: não há delta para documentar, há stub para apagar. | `backend-go/external/`, `go.mod` | `go list -m` mostra `Replace → ./external/socket.io` |

---

## 2. Objetivos e não-objetivos

**Objetivos, em ordem de prioridade:**

1. Servidor como autoridade real do desenho (D4, D5).
2. Custo de rede e de servidor: bytes por ponto, pacotes por operação, alocação por pacote (D1, D2, D3, D10).
3. Fluidez de render com um balde na tela e um traço longo em andamento (D6, D8).
4. Balde determinístico entre peers e com critério explícito de borda (D7, R13).
5. Tudo testável sem rede, nos dois lados (D11, D12).

**Fora de escopo (YAGNI), com o motivo:**

| Descartado | Por quê |
|---|---|
| Frames binários / msgpack | JSON com inteiros já entrega ~5× menos bytes. Binário no socket.io vira pacote + attachments nas duas libs, e o Dart não fala msgpack. Se um dia a rede apertar, `PerMessageDeflate` do engine.io comprime JSON sem mudar uma linha do protocolo. |
| Delta encoding entre pacotes | Cada pacote deixaria de ser autocontido; um pacote rejeitado corrompe os seguintes. Ganho marginal em lotes de 4–6 pontos. |
| Balde calculado no servidor | Exigiria um segundo rasterizador, em Go, idêntico ao Dart. Divergência garantida. Fica no cliente, sobre dados idênticos. |
| Versionamento de protocolo | App e servidor sobem juntos (CLAUDE.md §8). Troca em um commit. |
| Suavização/interpolação nos viewers | Estética; medir depois. |
| Undo de `clear` | O modelo por ops permite adicionar depois; o MVP não pede. |
| Simplificação RDP no fim do traço | Thinning na entrada já corta o grosso. Só se medir. |
| Múltiplos desenhistas | O jogo tem um por turno; o protocolo assume isso e fica mais simples por causa disso. |

---

## 3. Decisões

| Decisão | Por quê | Alternativa descartada |
|---|---|---|
| Inteiros em **décimos de pixel lógico** | 0,1 px em 500 lógicos é mais precisão do que qualquer tela mostra; 4 dígitos em JSON; canvas lógico não muda, goldens não mudam | grid 1280×720 (obrigaria escalar larguras e regerar goldens); doubles (47 B/ponto) |
| Um evento `drawing:op` com **lote** de ops | Um traço curto (hachura) vira 1 pacote em vez de 3; um lock e uma validação de desenhista por pacote no servidor | um evento por op (3 pacotes por traço curto) |
| Chave curta onde **repete** (por stroke/ponto), palavra inteira onde aparece **uma vez** por pacote | `p`, `c`, `w` repetem centenas de vezes num snapshot; `turn`, `ops`, `strokes` uma vez | tudo curto (ilegível em log); tudo longo (+40 % no snapshot) |
| Tipo do stroke e nome da op como **`.name`** de enum | Regra do CLAUDE.md §4; ~8 bytes por stroke, não por ponto; log legível | ints com tabela |
| `id` gerado **pelo cliente**, sequencial por turno, validado pelo servidor | Há um único escritor; `next` no snapshot permite continuar após reconexão; servidor rejeita `id != next` | id de servidor (exige ack antes do primeiro `points`); UUID (36 bytes por stroke) |
| Servidor **não** ecoa ao remetente | Desenhista já aplicou localmente; ordem garantida pelo TCP; qualquer divergência é corrigida por snapshot | eco + dedupe por id no cliente |
| Undo/redo sobem como **comando**, descem como **fato** | Viewers não precisam de pilha: `remove {id}` e re-inserção via `begin`+`end`. Só o servidor tem pilha de redo. | replicar a pilha em todos os clientes (hoje: dessincroniza ao reconectar) |
| `roomName` **fora** do payload de desenho | O servidor já sabe a sala do socket (`roomUsers[client.Id()]`); remove 25 bytes por pacote e a possibilidade de desenhar em sala alheia | manter |
| Quantizar **na origem** | Dados idênticos em todo peer é o que torna o balde local determinístico | recomputar com tolerância |
| Rasterizador do balde em **Dart puro** | Determinismo independe de Skia/Impeller/CanvasKit; mesmo código em toda plataforma | `toImage` + leitura de pixels (AA difere por backend) |
| Fill **4-conexo** | Uma linha fina em diagonal é uma cadeia de células ligadas só pela quina; um fill 8-conexo atravessa. Decisão já tomada na árvore de trabalho, com teste | 8-conexo (o teste antigo `fills diagonally connected area` foi reescrito) |
| Camada de traços concluídos em **`RepaintBoundary` + `Path` cacheado** | Elimina reconstrução de `Path` e repaint total por frame; sem `ui.Picture` manual até medir necessidade | `ui.Picture` manual (mais código pelo mesmo ganho) |
| Restaurar a lib socket.io **real** e apagar os stubs | Servidor que não serve não é servidor. O `Broadcaster` (4.3) é o seam que torna os stubs desnecessários | manter stubs e estender com `To` |

---

## 4. Contrato de rede v2

### 4.1 Espaço de coordenadas

- Canvas lógico continua **500 × 281,25** (16:9). `_canvasSize` não muda; golden nenhum muda.
- No wire, tudo é **inteiro em décimos** de pixel lógico:

| Campo | Faixa | Unidade |
|---|---|---|
| `x` | 0 … 5000 | décimo de px lógico |
| `y` | 0 … 2813 | décimo de px lógico |
| `w` (largura) | 10 … 800 | décimo de px lógico (1 … 80 px) |
| `a` (opacidade) | 10 … 100 | por cento |
| `c` (cor) | 0 … 16777215 | RGB 24 bits (`color.toARGB32() & 0xFFFFFF`) |
| `n` (lados) | 3 … 8 | — |

- Constantes e conversões vivem em `drawly_core/src/contracts/drawing_space.dart` e em
  `backend-go/src/contracts.go`, com teste de contrato comparando os dois.
- **Quantização na origem:** `pointerDown/Move` → `round(x * 10)` → esse inteiro é a verdade
  local e no wire. O render usa `x / 10`. O desenhista nunca desenha com o double original.

### 4.2 Eventos

| Evento | Direção | Payload | Substitui |
|---|---|---|---|
| `drawing:op` | cliente → servidor | `{"turn": 3, "ops": [...]}` | `drawing:stroke:start`, `drawing:stroke:lastPoints`, `drawing:undo`, `drawing:redo`, `drawing:clear` |
| `drawing:op` | servidor → sala (menos o remetente) | mesmo formato, já validado | idem |
| `drawing:snapshot` | servidor → **um** socket | `{"turn": 3, "next": 18, "strokes": [...]}` | `drawing:stroke:all` |
| `game:turn:new` | (existente) | — | implica canvas limpo em todo peer; o servidor zera o `Drawing` |

Seis eventos saem, dois entram. Os dois contratos (`SocketEvents.all` e `AllEvents`) e a seção
de protocolo do README mudam no mesmo commit.

### 4.3 Operações

| `op` | Sobe | Desce | Campos | Semântica | O servidor rejeita se |
|---|---|---|---|---|---|
| `begin` | ✓ | ✓ | `id`, `t`, `c`, `w`, `a`, `p`, [`f`], [`n`] | abre o stroke `id`; `p` traz o primeiro ponto (ou, na descida por redo, todos) | já há stroke aberto; `id != next`; campo fora da faixa; `f`/`n` em tipo que não os usa |
| `points` | ✓ | ✓ | `id`, `p` | anexa pontos (só `pencil`, `eraser`) | `id` não é o aberto; tipo não é livre; > 64 pontos; total > 4000 |
| `shape` | ✓ | ✓ | `id`, `p` | substitui o **segundo** ponto (só `line`, `square`, `circle`, `polygon`) | `id` não é o aberto; tipo não é forma; `p` ≠ 1 ponto |
| `end` | ✓ | ✓ | `id` | fecha o stroke; só então ele pode ser desfeito | `id` não é o aberto |
| `undo` | ✓ | — | — | servidor move o último concluído para a pilha de redo e desce `remove` | há stroke aberto; nada a desfazer |
| `redo` | ✓ | — | — | servidor devolve o topo do redo e desce `begin` (completo) + `end` | há stroke aberto; nada a refazer |
| `clear` | ✓ | ✓ | — | zera strokes e pilha de redo; não é desfazível | há stroke aberto |
| `remove` | — | ✓ | `id` | viewers removem o stroke `id` | — |

Regras transversais:

- Lote: 1 … 32 ops, aplicadas em ordem, **atômico** — a primeira op inválida rejeita o lote inteiro.
- Bucket: `begin` com `p = [x, y]` (a semente) seguido de `end`, no mesmo lote. Nunca há `points` de bucket.
- `begin` de qualquer tipo limpa a pilha de redo (mesma regra do `UndoRedoStack` de hoje).
- Um `begin` implícito não fecha o anterior: `end` é obrigatório. Estado do servidor é uma máquina de dois estados por sala: `idle` ↔ `drawing(id)`.

### 4.4 Stroke no wire

```json
{"id": 17, "t": "pencil", "c": 0, "w": 60, "a": 100, "p": [1372, 2114, 1400, 2140]}
{"id": 18, "t": "circle", "c": 16711680, "w": 40, "a": 100, "f": 1, "p": [1000, 500, 2500, 1800]}
{"id": 19, "t": "polygon", "c": 255, "w": 40, "a": 60, "f": 0, "n": 5, "p": [...]}
{"id": 20, "t": "bucket", "c": 65280, "w": 10, "a": 100, "p": [1800, 1200]}
```

| Campo | Tipo | Regra |
|---|---|---|
| `id` | int ≥ 1 | crescente por turno; recomeça em 1 a cada `game:turn:new` |
| `t` | `.name` de `StrokeType` | `pencil`, `eraser`, `line`, `square`, `circle`, `polygon`, `bucket`. `normal` é renomeado para `pencil` |
| `c`, `w`, `a` | int | faixas da 4.1 |
| `f` | 0/1 | só `square`, `circle`, `polygon`; ausente = 0 |
| `n` | int | só `polygon` |
| `p` | int[] plano `[x0, y0, x1, y1, …]` | `pencil`/`eraser`: 1 … 4000 pontos; formas: 1 (recém-aberta) ou 2; `bucket`: exatamente 1 |

`fillPixels` **não existe** no wire, no DTO nem no snapshot. Vira regra ativa do
`check_architecture.sh`.

### 4.5 Exemplos com tamanho

Um flush de 50 ms com 4 pontos de lápis (hoje: 245 B):

```json
{"turn":3,"ops":[{"op":"points","id":17,"p":[1372,2114,1400,2140,1430,2190,1500,2220]}]}
```
88 B.

Uma hachura curta: começou e terminou dentro da mesma janela de 50 ms (hoje: 2 pacotes, ≈ 370 B — `stroke:start` + um `lastPoints`):

```json
{"turn":3,"ops":[
  {"op":"begin","id":21,"t":"pencil","c":0,"w":60,"a":100,"p":[1372,2114]},
  {"op":"points","id":21,"p":[1400,2140,1430,2190]},
  {"op":"end","id":21}
]}
```
1 pacote, 162 B.

Undo pelo desenhista e o que a sala recebe:

```json
↑ {"turn":3,"ops":[{"op":"undo"}]}
↓ {"turn":3,"ops":[{"op":"remove","id":21}]}
```

Snapshot para quem acabou de entrar, com 30 strokes de 120 pontos (hoje: 176 KB):
34,5 KB.

### 4.6 Regras do servidor

1. **Identidade pelo socket.** Sala e usuário vêm de `roomUsers[client.Id()]`. Socket sem sala: lote ignorado.
2. **Autoridade.** Aceita só se `room.IsGameStarted && sender == room.getCurrentDrawer().UserId && turn == room.TurnCount`.
3. **Estado por sala.** `Drawing{Turn, NextID, Open *Stroke, Strokes []Stroke, Redo []Stroke}`; `Stroke.Points []int32` plano. Zerado em `startTurnTimer`.
4. **Validação estrutural** no parse (`v, ok` em toda assertion; número JSON tem de ser integral e dentro da faixa) e **semântica** no `Apply` (máquina de estados da 4.3).
5. **Limites** (todos constantes em `contracts.go`, espelhados no Dart):

| Limite | Valor | Protege |
|---|---|---|
| ops por lote | 32 | CPU por pacote |
| pontos por `points` | 64 | idem |
| pontos por stroke | 4000 | memória por sala (≈ 66 s a 60 Hz depois do thinning: inalcançável num turno de 60 s) |
| strokes por turno | 1000 | memória por sala e tamanho do snapshot |
| lotes por segundo por socket | 60 | 3× a cadência nominal de 20/s |
| `maxHttpBufferSize` do engine.io | 64 KB (era 1 MB) | transporte; um lote máximo válido tem < 8 KB |

6. **Rejeição.** `error {message, action: ignore}` + `drawing:snapshot` ao remetente. O lote não é aplicado nem retransmitido. Nunca `panic`.
7. **Broadcast.** `client.To(room).Emit(EventDrawingOp, loteTipado)`: exclui o remetente e re-emite a struct validada, nunca o `map` cru.
8. **Snapshot** só para o socket que entrou: `client.Emit(EventDrawingSnapshot, …)`. Nunca `io.To(room)`.

### 4.7 Reconexão e offline

- Cliente **não emite** com `gateway.isConnected == false`. Ops geradas offline são descartadas na hora; nada fica em fila para o `sendBuffer` do socket.io descarregar depois.
- Em `connect`: limpa o estado local e faz o join; o `drawing:snapshot` que vem dentro do join é a verdade. O desenhista retoma ids de `next`.
- O snapshot chega **antes** do ack do join (o servidor emite dentro do handler). O controller adota `turn` do snapshot; o `startTurn` disparado pelo ack é idempotente quando o turno é o mesmo.
- Consequência assumida: o que o desenhista desenhou offline **se perde**. É o comportamento correto para um jogo em tempo real e é o que resolve D5 sem heurística.

---

## 5. Cliente Dart

Estrutura alvo em `packages/drawing_board/lib/src/`:

```
domain/
  models/stroke.dart            sealed Stroke + 7 subtipos, imutáveis, ==/hashCode, sem DateTime
  models/stroke_builder.dart    traço em andamento (mutável, growable)
  models/drawing_op.dart        sealed DrawingOp: Begin, Points, Shape, End, Undo, Redo, Clear, Remove
  models/drawing_state.dart     strokes + aberto + pilha de redo; apply(op) puro
  repositories/drawing_repository.dart   interface
  fill/bucket_fill.dart         rasterizador + flood fill (função pura)
data/
  drawing_codec.dart            encode/decode de lote, stroke e snapshot; quantização
  realtime_drawing_repository.dart       impl sobre RealtimeGateway
presentation/
  controllers/drawing_controller.dart    ChangeNotifier; único dono de estado e de I/O
  widgets/drawing_canvas.dart   input + 2 camadas de pintura
  widgets/canvas_side_bar.dart  burro: lê e escreve no controller
  views/drawing_board.dart      composição; recebe o controller pronto
```

### 5.1 Domínio

- `Stroke` guarda `points` como `List<int>` **em décimos** (a verdade do wire), não `Offset`.
  O domínio não importa Flutter (regra do CLAUDE.md); a conversão para `Offset` acontece uma
  vez, ao construir o `Path` cacheado na apresentação.
- `StrokeBuilder` é o único objeto mutável: acumula pontos do traço aberto sem copiar a lista
  (resolve D8) e produz um `Stroke` imutável no `end`.
- `DrawingState.apply(DrawingOp)` é **um reducer só**, usado pelos dois papéis: o desenhista
  aplica as próprias ops antes de enviar; o viewer aplica as que chegam. Se o servidor
  aceitou, os dois lados chegam ao mesmo estado porque rodaram o mesmo código sobre os mesmos
  inteiros. Tabela de testes: cada op × cada estado (`idle`, `drawing`, com/sem redo).
- `BucketStroke` guarda **só a semente**. O preenchimento é dado derivado: `bucketFill(strokesAnteriores, semente)`
  é função pura do domínio, e o resultado (spans) é cacheado na apresentação por `id`.

### 5.2 Dados

- `DrawingCodec`: `encodeBatch(turn, ops) → Map`, `decodeBatch(dynamic) → DecodedBatch?`,
  `decodeSnapshot(dynamic) → DrawingSnapshot?`. Tolerante: payload malformado devolve `null`
  e loga; nunca deixa exceção chegar ao widget (comportamento já travado por teste hoje).
- `RealtimeDrawingRepository(RealtimeGateway)`: `send(turn, ops)` (no-op se desconectado),
  `listen(onOps, onSnapshot, onConnect)`, `dispose()` via `RealtimeSubscriptions`.
- O package **não** conhece `game:turn:new`. Quem processa turno é o app, que chama
  `controller.startTurn(turn: n, isDrawer: b)`. `drawing_board` passa a depender só dos dois
  eventos de desenho.

### 5.3 `DrawingController`

```dart
final class DrawingController extends ChangeNotifier {
  DrawingController({
    required DrawingRepository repository,
    Duration flushInterval = const Duration(milliseconds: 50),
    Timer Function(Duration, void Function()) createTimer = _periodic,
  });

  // estado observável
  DrawingState get state;         int get turn;   bool get isDrawer;
  bool get canUndo;  bool get canRedo;
  DrawingToolOptions get tools;   // cor, largura, opacidade, ferramenta, filled, lados, grade

  // ciclo do turno
  void startTurn({required int turn, required bool isDrawer});  // idempotente no mesmo turno
  void applySnapshot(DrawingSnapshot s);

  // input (coordenadas lógicas, já dentro do canvas)
  void pointerDown(Offset p);  void pointerMove(Offset p);  void pointerUp();
  void bucketAt(Offset p);
  void undo();  void redo();  void clear();
}
```

Pipeline de um ponto: `Offset` → **thinning** (descarta se a distância ao último ponto
aceito for < 1 px lógico, exceto o último do traço) → **quantização** → `state.apply(op)`
local → enfileira a op → o timer de `flushInterval` envia o lote acumulado. Nada além do timer
emite; `end` viaja junto com os últimos `points`.

Invariantes que o controller garante (cada uma vira um teste com `FakeRealtimeGateway` +
`fake_async`):

- só emite se `isDrawer && repository.isConnected`;
- `id` sequencial por turno, continuado de `next` após snapshot;
- `undo`/`redo`/`clear` ignorados enquanto há traço aberto (inclusive por hotkey);
- `startTurn` com turno diferente zera estado, ferramentas e ids; com o mesmo turno, no-op;
- `dispose` cancela o timer, remove os listeners e descarta os notifiers.

### 5.4 Render

```
Stack
├── RepaintBoundary(CustomPaint(CommittedPainter))   // strokes concluídos + grade
└── CustomPaint(LivePainter)                          // só o traço aberto
```

- `CommittedPainter.shouldRepaint` compara um `revision` inteiro que o controller incrementa a
  cada mudança na lista concluída (`end`, `remove`, `clear`, snapshot). Enquanto alguém
  arrasta o lápis, essa camada não repinta.
- `Path` por stroke construído **uma vez** (cache por `id`, invalidado em `remove`/`clear`).
- `LivePainter` repinta a cada ponto, mas só desenha um `Path` incremental.
- Balde: `Path` com um `addRect` por span horizontal, `isAntiAlias = false`, um `drawPath`.
- Largura em unidades lógicas, sem `/ scale` (D9). O slider passa a significar "px lógicos".
- **Nenhum golden é regenerado.** Os goldens semeiam strokes com coordenadas e larguras
  explícitas e o painter dos tipos não-bucket não muda de lógica. Se algum divergir, é
  investigação, não `--update-goldens`. O único golden novo é `bucket_fill_circle.png` (balde dentro de um
  círculo fechado), que a árvore de trabalho já introduz.

### 5.5 Balde

**Ponto de partida: o que já está na árvore de trabalho** (sessão paralela, não commitado):
`bucket_fill.dart` reescrito sobre um `_Raster` de `Uint32List`, amostrando o **centro** de
cada célula contra a geometria exata que o painter pinta (cápsula de raio `size/2` por
segmento; interior sem contorno para formas preenchidas; eraser escreve a cor de fundo);
flood fill **4-conexo** por scanline; `bucketFillRuns`/`bucketFillPath` transformam os pixels
em spans e num único `Path`, cacheado por identidade do stroke no painter. Os quatro testes do
R13 foram reescritos com conjuntos esperados exatos (geometria alinhada ao centro da célula) e
entra o golden `bucket_fill_circle.png`. Isso já responde ao R13 sem "expansão": amostrar no
centro é o que casa o raster com o render anti-aliased.

Esse commit entra **antes** de D6, como está. D6 não reescreve; consolida o que falta:

1. **Entrada inteira.** A função passa a receber strokes com pontos em décimos (5.1). Sem
   `double` no caminho, o resultado é idêntico em todo peer por construção — hoje o
   desenhista rasteriza os doubles originais e os viewers o que voltou do JSON.
2. **Spans como representação.** A saída vira `Int32List` de `[y, x0, x1]`, não
   `List<Offset>`: é o que o painter já consome e custa 12 bytes por faixa em vez de um
   objeto por pixel. `fillPixels` deixa de existir como campo; o `BucketStroke` guarda só a
   semente, e os spans ficam num cache da apresentação por `id`.
3. **Função no domínio.** `domain/fill/bucket_fill.dart`, pura; o painter só converte spans
   em `Path`.
4. **Teste de determinismo.** Mesma entrada → mesmos spans em duas execuções e após ida e
   volta pelo codec.
5. **`_pendingBuckets` some** em D3b: sem eco ao remetente não há eco para reconhecer.

Custo estimado (AOT): raster 141 k células; pior caso realista (eraser de 80 px sobre 4000
pontos) ≈ 25 M testes de distância, dezenas de ms — aceitável por clique. Se a medição no web
(dart2js) reprovar, o plano B é cache incremental do raster por turno (estampar strokes
conforme concluem; `remove`/`clear` reconstroem). Só se medir.

### 5.6 Ciclo de vida

| Recurso | Dono | Fecha em |
|---|---|---|
| timer de flush | `DrawingController` | `dispose()` |
| `RealtimeSubscriptions` dos 2 eventos + `connect` | `RealtimeDrawingRepository` | `dispose()` |
| notifiers de ferramenta | `DrawingController` | `dispose()` |
| `FocusNode` do `HotkeyListener` | widget | `dispose()` (hoje vaza) |
| cache de `Path` e de spans | `CommittedPainter`/controller | `remove`, `clear`, `startTurn` |

---

## 6. Servidor Go

### 6.0 Pré-requisito: a lib real (D12, 4.3, A10)

Nada do lado Go é real enquanto o `replace` apontar para os stubs, e os stubs não têm
`client.To`. Ordem obrigatória:

1. `Broadcaster` (doc 06, 4.3) com uma terceira operação:
   ```go
   type Broadcaster interface {
       ToRoom(room, event string, payload any)
       ToRoomExcept(room, clientID, event string, payload any)
       ToClient(clientID, event string, payload any)
   }
   ```
   **Todos** os handlers passam a recebê-lo (é mecânico: `io.To(room).Emit` → `ToRoom`,
   `client.Emit` → `ToClient`). Testes trocam `&socket.Server{}` por um `SpyBroadcaster`.
2. Remover os três `replace` do `go.mod`, apagar `backend-go/external/`, `go mod tidy`,
   `go build ./...` contra `socket.io/v2 v2.3.6` real. O adaptador `socketBroadcaster` é o
   único arquivo que importa a lib.
3. Smoke manual com dois navegadores (checklist na seção 8) — os handlers nunca rodaram
   contra a lib real dentro deste repositório.

Isso fecha D12 e reescreve A10: não há fork para documentar.

### 6.1 `Drawing` — regra pura (`internal/game` no alvo; `src/drawing.go` até a 4.2)

```go
type Drawing struct {
    Turn    uint8
    NextID  uint32
    Open    *Stroke
    Strokes []Stroke
    Redo    []Stroke
}

// Apply valida e aplica um lote; devolve as ops a retransmitir.
func (d *Drawing) Apply(batch OpBatch) ([]Op, error)
func (d *Drawing) Snapshot() Snapshot
func (d *Drawing) Reset(turn uint8)
```

Zero import de socket.io. Testes em tabela: cada op × cada estado, limites, atomicidade do
lote (lote com a 3ª op inválida deixa o estado intocado).

### 6.2 Parse — `ParseOpBatch(any) (OpBatch, error)`

Toda assertion com `ok`. Números JSON chegam como `float64`: devem ser integrais e caber na
faixa antes de virar `int32`/`uint8`. Limites estruturais (tamanho de lote, de `p`) aqui;
semânticos no `Apply`. Testes com o fixture compartilhado (seção 8).

### 6.3 Handler `drawing:op`

```
resolve roomUsers[client.Id()]           → sem sala: ignora
room, drawing := rooms[...], roomDrawings[...]
rate limit por socket                    → excede: descarta
ParseOpBatch(args[0])                    → erro: rejeita
autoridade (4.6 §2)                      → falha: rejeita
downstream, err := drawing.Apply(batch)  → erro: rejeita
b.ToRoomExcept(room, client, EventDrawingOp, downstream)
```

`rejeita` = `b.ToClient(id, EventError, ErrorDTO{…, Ignore})` + `b.ToClient(id, EventDrawingSnapshot, drawing.Snapshot())`.

### 6.4 Join e turno

- `handleJoinRoom`: `b.ToClient(joiner, EventDrawingSnapshot, …)` — só para quem entrou.
- `startTurnTimer`: `drawing.Reset(room.TurnCount)` — já limpa hoje; passa a zerar `NextID` e `Open`.

### 6.5 Custo por sala

| Item | Hoje | Alvo |
|---|---|---|
| ponto em memória | `Offset{float64, float64}` = 16 B | 2 × `int32` = 8 B |
| decode de um flush de 4 pontos | 4 `map[string]any` + 8 `float64` boxed | 1 `[]any` de 8 números → `[]int32` |
| broadcast por op | re-encode de `map` cru, N destinos | encode de struct, N−1 destinos |
| snapshot no join | N encodes/envios | 1 |

---

## 7. Plano de execução

Cada linha é **um commit**, com a suíte verde antes e depois, e com o teste que trava o
comportamento escrito **antes** da mudança (CLAUDE.md §6). Formato de mensagem do §9.
A versão só sobe no último passo (`0.55.0+6`, via `set_version.sh`); até lá, as mensagens
levam `0.54.0+5`.

| # | Commit | O que muda | Teste que trava antes | Fecha |
|---|---|---|---|---|
| G0 | `refactor: route every go handler through a Broadcaster and drop the socket.io stubs` | 6.0 inteiro | `SpyBroadcaster` grava emissões; todo handler test migra | D12, A10, 4.3 |
| B0 | *(em andamento na árvore de trabalho, sessão paralela — fora da autoria deste plano)* balde sobre raster tipado, 4-conexo, `Path` cacheado, testes do R13 reescritos, golden novo | `bucket_fill.dart`, `drawing_canvas.dart`, `stroke.dart` (`fillPixels` final), testes | os próprios | R13, D6 (render) |
| D0 | `test: lock canvas side bar undo, redo and clear emissions` | só teste | — (é o próprio) | pendência da fase 2 |
| D1 | `refactor: make Stroke a sealed immutable value type` | `sealed`, `final`, `==`, sem `DateTime`, `StrokeType.name`, apaga `ToolType` e `DrawingTool.fill`; wire inalterado | round-trip dos 7 tipos (já existe) | A7, A8, R1 |
| C1 | `feat: declare the drawing op contract and coordinate space on both sides` | `SocketEvents.drawingOp/drawingSnapshot`, `DrawingSpace`, `DrawingOpCode`; consts Go; fixture compartilhado; eventos antigos continuam | testes de contrato (2 lados) leem o fixture | — |
| D2 | `feat: add the drawing op reducer and codec to drawing_board` | 5.1 + 5.2 sem ligar nos widgets | tabela op × estado; round-trip com fixture; budget de bytes | D1, D10, D11 |
| G1 | `feat: add the turn-scoped drawing op model to the go backend` | 6.1 + 6.2 sem ligar no `events.go` | tabela op × estado; parse com fixture; atomicidade | D4 (regra), D10 |
| G2 | `feat: handle drawing:op and send the snapshot only to the joining client` | 6.3 + 6.4; handlers antigos continuam registrados por um commit | handler com spy: autoridade, turno, except-sender, rejeição → snapshot, rate limit; `-race` | D2, D3, D4 |
| D3a | `feat: add a DrawingController that speaks the op protocol` | 5.3 + repositório, sem ligar nos widgets | invariantes da 5.3 com `FakeRealtimeGateway` + `fake_async` | D5, D8 |
| D3b | `feat: drive the drawing board with the controller and paint the local stroke immediately` | widgets sobre o controller; app compõe e chama `startTurn`; cliente passa a emitir `drawing:op`; some `DrawingCanvasViewModel`, `username`/`word` do `DrawingBoard` | goldens inalterados; testes de input passam a inspecionar o lote | R9, 3.2 passo 5 |
| C2 | `chore: remove the legacy drawing events from both contracts` | apaga 6 eventos, handlers e DTOs antigos; README (protocolo); regra `fillPixels` vira ativa no `check_architecture.sh` | testes de contrato | — |
| D4 | `perf: paint committed strokes in a cached layer with per-stroke paths` | 5.4 | teste: `shouldRepaint` falso durante `pointerMove`; goldens inalterados | D6 (render), D8 |
| D5 | `fix: define stroke width in logical units regardless of window scale` | remove `/ scale` | golden com `scale` ≠ 1 que hoje falha | D9 |
| D6 | `refactor: feed bucket fill with quantized strokes and keep only spans` | 5.5 itens 1–5, sobre B0 | os testes do R13 (já reescritos em B0) continuam verdes com entrada inteira; determinismo; spans | D7 (resto) |
| G3 | `feat: bound and rate limit drawing ops per socket` | tabela de limites da 4.6; `maxHttpBufferSize` 64 KB | um teste por limite | 4.7 |
| X1 | `docs: record the drawing protocol and refresh the findings and status` + `build: bump version to 0.55.0` | 01-achados (R9, R13, A7, A8, A10 → fechados; D9 novo), 05/06 checkboxes, 09-estado-atual, pisos de cobertura | `set_version.sh --check` | — |

Dependências: B0 antes de D6; G0 antes de G2; C1 antes de D2/G1; D2 e G1 antes de D3a/G2; D3b e G2 antes de
C2. D4, D5, D6 e G3 são independentes entre si depois de C2. Entre G2 e C2 o servidor fala os
dois protocolos — é a janela que permite testar o cliente novo contra o servidor novo sem
big-bang.

O que **não** entra aqui e continua nos docs 05/06: `RoomRegistry` (4.4), `Scheduler` (4.5),
extração de `internal/` (4.2). O `Drawing` novo nasce em `src/` e migra para `internal/game`
quando a 4.2 acontecer — ele já não importa socket.io, então a migração é mover arquivo.

---

## 8. Testes

| Nível | O que | Onde |
|---|---|---|
| Unit Dart | `DrawingState.apply` (tabela op × estado); `DrawingCodec` round-trip; quantização; thinning; `bucketFill` (região, dilatação, determinismo, formas preenchidas, eraser como fundo) | `drawing_board/test/domain`, `test/data` |
| Budget | `encodeBatch` de 4 pontos ≤ 90 B; `begin` ≤ 100 B; snapshot de 30 × 120 pontos ≤ 40 KB. Guarda o formato contra regressão silenciosa | `drawing_board/test/data/drawing_codec_budget_test.dart` |
| Contrato | fixture `packages/drawly_core/test/fixtures/drawing_wire.json` com lotes válidos e inválidos. Dart: `encode(decode(x)) ≡ x` e inválidos → `null`. Go: `Parse(x)` ok/erro e `Encode(Parse(x)) ≡ x`. Comparação estrutural, não de string | `drawly_core/test/contracts`, `backend-go/src/contracts_test.go` |
| Controller | invariantes da 5.3 com `FakeRealtimeGateway` e `fake_async` | `drawing_board/test/presentation/controllers` |
| Widget/golden | render (inalterado) + input (inspeciona o lote emitido) + o golden do balde (já em B0) | `drawing_board/test/presentation/widgets` |
| Go unit | `Drawing.Apply` tabela; `ParseOpBatch`; handler com `SpyBroadcaster`; tudo sob `-race` | `backend-go/src/*_test.go` |

Fakes compartilhados: `FakeRealtimeGateway` (já existe), `SpyBroadcaster` (novo, em
`testing_support_test.go`), `StrokeFixtures` atualizado para inteiros.

Smoke manual (depois de G0 e de C2), dois navegadores na mesma sala:
lápis/eraser/linha/quadrado/círculo/polígono/balde aparecem no outro lado; undo/redo/clear;
entrar no meio do turno recebe o desenho; derrubar a rede do desenhista por 3 s, desenhar
offline, voltar: nada do offline aparece e o canvas dos dois bate; trocar de turno limpa os
dois; tentar desenhar sem ser o desenhista é ignorado.

---

## 9. Métricas de aceite

| Métrica | Hoje (medido) | Alvo | Como verificar |
|---|---|---|---|
| bytes por ponto | 47 | 9–11 | budget test |
| flush de 4 pontos | 245 B | ≤ 90 B | budget test |
| `begin` com 1 ponto | 218 B | ≤ 100 B | budget test |
| snapshot 30 × 120 pontos | 176 KB | ≤ 40 KB | budget test |
| pacotes por hachura curta | 2 | 1 | teste do controller (lote) |
| pontos armazenados por forma arrastada 3 s | ~180 | 2 | teste do reducer |
| destinos por op numa sala de N | N | N−1 | handler test com spy |
| destinos do snapshot no join | N | 1 | handler test com spy |
| `drawRect` por frame com um balde | até 141 k (último commit); 1 `drawPath` em B0 | 1 `drawPath` | golden do balde |
| repaint da camada concluída durante `pointerMove` | todo frame | 0 | teste de `shouldRepaint` |
| quem consegue desenhar | qualquer socket | só o desenhista do turno | handler test |
| balde igual em todos os peers | não garantido | garantido | teste de determinismo |

Os números de "hoje" saíram de um script `dart` de 40 linhas que monta os mesmos mapas que
`toJson` produz e mede `jsonEncode(...).length`; pontos gerados com `Random(42)` em
`[0, 500) × [0, 281)`. O budget test do D2 é a versão permanente desse script.

---

## 10. Riscos

| Risco | Mitigação |
|---|---|
| Handlers nunca rodaram contra a lib real neste repositório (D12) | G0 é o primeiro commit; smoke manual logo depois; `Broadcaster` isola a lib num arquivo |
| D3b é o maior commit e mexe em input, render e rede | controller inteiramente testado em D3a antes de ser ligado; servidor aceita os dois protocolos entre G2 e C2 |
| Balde lento no web (dart2js) | medir em D6; plano B é cache incremental do raster (5.5), não baixar resolução |
| Divergência de balde entre plataformas | impossível por construção: só inteiros, só Dart, sem leitura de GPU |
| Golden "divergindo" por causa da largura (D5) | o commit D5 é separado e carrega o golden que prova a mudança; nenhum outro golden é tocado |
| Trabalho paralelo no balde (sessão `drawly-project-42`) | Este plano não toca `bucket_fill.dart`, `drawing_canvas.dart` nem seus testes antes de B0 entrar; D6 consolida em cima, não reescreve. Conflito evitado por ordem, não por sorte |
| Snapshot grande em sala com turno longo | limites de 4000 pontos × 1000 strokes garantem teto; medir com o budget test |

---

## 11. Impacto nos documentos existentes

- [01-achados.md](01-achados.md): R9, R13, A7, A8 e A10 fecham; A10 é reescrito (stub, não fork); D9 e D12 entram como achados novos.
- [05-fase-3-arquitetura-dart.md](05-fase-3-arquitetura-dart.md): 3.1 itens R9 e R13, 3.2 passo 5 e 3.3 apontam para este doc.
- [06-fase-4-arquitetura-go.md](06-fase-4-arquitetura-go.md): 4.3 ganha `ToRoomExcept`; 4.6 vira "apagar os stubs"; 4.7 (limites de `fillPixels`) é substituído pela tabela da 4.6 daqui.
- [09-estado-atual.md](09-estado-atual.md): R13 sai da tabela de abertos quando B0 entrar; pisos de cobertura ao fim.
- `scripts/check_architecture.sh`: regras novas ativas em C2 — nenhum `fillPixels` fora de `domain/fill`; nenhum `'dx'` em `data/` nem em `backend-go/src`.
- `README.md`: seção de protocolo reescrita em C2.

Etapas posteriores ao refactor (fase do turno, paridade de ferramentas, observabilidade, performance por gate, replay): [11-desenho-etapas-seguintes.md](11-desenho-etapas-seguintes.md).
