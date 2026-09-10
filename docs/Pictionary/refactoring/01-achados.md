# Achados da Auditoria

Severidade: **P0** quebra o projeto · **P1** bug real ou risco de dado/corrida ·
**P2** dívida arquitetural · **P3** higiene.

---

## P0 — Bloqueadores (o projeto não construía)

### B1 · `flutter pub get` falhava na raiz
`pubspec.yaml` declarava `fluo` como path dependency para `../../packages/fluo-flutter-sdk`,
diretório inexistente. **Nenhum** comando Flutter funcionava no app.
O único uso real de `fluo` estava em `lib/main copy 2.dart` (arquivo morto).
→ Resolvido na fase 0.

### B2 · Os 13 arquivos de teste do Go nunca compilaram
Ficavam em `backend-go/tests/` declarando `package main`, mas Go trata cada diretório como
pacote próprio (`drawly-server/tests`). Todos os símbolos de `src/` eram `undefined`.
A suíte inteira do backend era **decorativa** — `go test ./...` sequer rodava.
→ Resolvido na fase 0.

### B3 · Suíte do `drawing_board` não compilava
`font_awesome_flutter ^10.6.0` estende `IconData`, que virou `final class` no Flutter
recente. Erro de compilação em cascata derrubava os 8 arquivos de teste do package.
O package usava a lib para **6 ícones**; o resto do arquivo já usava `Icons.*`.
→ Resolvido na fase 0 removendo a dependência.

### B4 · Arquivos mortos versionados
`lib/main copy.dart` (idêntico a `main.dart`), `lib/main copy 2.dart` (demo de `fluo`),
`lib/firebase_options copy 2.dart` (byte-idêntico ao original) e
`lib/firebase_options copy.dart` (difere em 1 `appId` web).
→ Removidos na fase 0.

---

## P1 — Bugs reais

### R1 · `ToolType.toString()` é recursão infinita
`packages/drawing_board/lib/src/domain/models/tool_type.dart`
```dart
@override
String toString() => toString().split('.').last;  // chama a si mesmo
```
Qualquer interpolação de um `ToolType` estoura a pilha. Mitigante: o enum é **código
morto** (zero referências no repositório). Ação: deletar.

### R2 · Rank de acerto é não-determinístico (Go)
`Room.getCorrectAnswerRank` calcula a posição iterando `map[string]bool`. A ordem de
iteração de mapa em Go é **aleatória por design**. Logo a pontuação de quem acerta em
2º/3º lugar varia entre execuções idênticas.
Correção: manter `[]string` ordenado por chegada.

### R3 · Panic com sala sem desenhista (Go)
`Room.hasEveryoneAnsweredCorrectly` faz `currentDrawer.UserId` sem checar nil, mas
`getCurrentDrawer()` retorna `nil` quando `CurrentDrawerTurnIndex == -1` (todos saíram).
É alcançável via desconexão em massa → panic derruba a goroutine.

### R4 · Type assertions sem `ok` derrubam handlers (Go)
`handleMessageChat` faz `data["userId"].(string)`, `data["username"].(string)`,
`data["text"].(string)` sem verificar. Payload malformado (ou malicioso) causa panic.
Mesmo padrão em `parseStroke` para `rawColor["a"].(float64)` etc.

### R5 · Data race no estado global (Go) — ✅ **corrigido**
`rooms`, `roomDrawings` e `roomUsers` eram mapas de pacote mutados por callbacks de socket
(goroutines distintas) e por `time.AfterFunc`. Sem mutex. Escrita concorrente em mapa Go
é crash, não corrupção silenciosa.

`go test -race` reproduziu a corrida de forma determinística no caminho de reconexão:
o handler marca `participant.IsConnected = true` enquanto a goroutine do timer de
tolerância lê o mesmo campo.

**Correção:** `stateMu` (`src/state_lock.go`) — um `sync.Mutex` adquirido nos pontos de
entrada (handlers e callbacks de timer, via `withState`). As funções internas assumem o
lock e estão marcadas com `// Requer stateMu.`; o mutex não é reentrante, então
`startTurnTimer` — que se reagenda sozinha — nunca o adquire.

Mutex único e grosso de propósito (KISS): as operações são curtas e em memória, várias
cruzam salas, e o gargalo real é a rede. Granularizar depois, se o perfil pedir.

O `RoomRegistry` da fase 4 continua valendo — ele elimina o estado *global*, que é um
problema diferente (poluição entre testes, ausência de dono). A corrida em si já foi paga.

### R6 · Timer do buffer de pontos nunca é cancelado — ✅ **corrigido**
`DrawingCanvas._startDrawingPointsBuffer()` criava `Timer.periodic(50ms)` sem guardar a
referência. Cada instância do canvas deixava um timer vivo para sempre, emitindo no
socket. `dispose()` não o cancelava porque não tinha como.

Descoberto pelo próprio `flutter_test`, que falha com *"A Timer is still pending even
after the widget tree was disposed"* — ou seja, **nenhum** teste de widget do canvas podia
passar enquanto o vazamento existisse.

**Correção:** o timer virou o campo `_pointsBufferTimer`, cancelado no `dispose`.

### R7 · Listeners vazados
- `AnswersChatViewModel` registra `'game:turn:new'` e **nunca** remove no `dispose`.
- `DrawGameRoomPage` cria 8 `ValueNotifier` e descarta apenas 4 (`rxWord`,
  `rxCurrentDrawerUsername`, `rxIsGameStarted`, `rxTurn` vazam).
- `DrawlyApp._onErrorEvent` é `late final` atribuído dentro de um `Future`; se o widget
  for descartado antes, `dispose()` lê o campo não inicializado → `LateInitializationError`.

### R8 · `emitWithAck` deixa timer pendente
`SocketManager.emitWithAck` agenda `Future.delayed(timeout)` e não o cancela quando o ack
chega. Cada chamada segura um timer por 10s.

### R9 · O desenhista não vê o próprio traço
`_DrawingCanvasPainter.paint` só percorre `rxAllStrokes`; a linha que adicionaria
`rxCurrentStroke` está comentada com `// TODO(Kevin): do something here?`. Como
`rxAllStrokes` só é preenchido pelo **eco do servidor**, o traço aparece com latência de
ida e volta — e não aparece de forma alguma se o socket cair.
É também a razão de os goldens de gesto falharem sem servidor.

Decisão de arquitetura pendente: adotar **echo local otimista** (desenha na hora,
reconcilia com o eco) ou assumir servidor-autoritativo e mostrar estado de latência.
Recomendação: otimista, é o padrão do gênero.

### R10 · `chooseRandomWord` não é aleatório e tem 1 palavra
`time.Now().UnixNano() % len(wordsList)` não é distribuição uniforme, e `wordsList` tem
exatamente um elemento — `"r"`. As outras 28 palavras estão comentadas.

### R13 · O balde não casava com o que o painter desenha — ✅ **corrigido**
A raiz não era a "expansão pós-fill" (que era um no-op: só crescia para células vazias,
que o BFS já tinha visitado). Era o raster do `bucketFill` descrever uma geometria
diferente da que o painter pinta:

- amostrava o canto inteiro `(x, y)` em vez do centro `(x + 0.5, y + 0.5)` da célula que
  o painter desenha — daí a fresta de 1px do lado direito/inferior de toda borda;
- vizinhança de 8: vazava por qualquer linha fina em diagonal;
- balde anterior e formas preenchidas eram dilatados por `size / 2`, apesar de o painter
  desenhá-los sem contorno;
- `LineStroke` usava o caminho do arrasto, o painter só as extremidades;
- borracha virava parede em vez de apagar;
- no render, um `drawRect` por pixel a cada frame (com `shouldRepaint = true`) travava o
  app em preenchimentos grandes.

Correção: `bucket_fill.dart` reescrito como raster em `Uint32List` amostrado no centro
da célula, com cada tipo de stroke rasterizado exatamente como o painter o desenha
(cápsulas de raio `size / 2` para contornos, interior puro para formas preenchidas), flood
fill 4-conexo por scanline, e `BucketStroke` desenhado como um único `Path` de faixas
horizontais cacheado por identidade. Os quatro testes pulados foram substituídos por uma
suíte que deriva o conjunto esperado da geometria; um golden (`bucket_fill_circle`) fixa o
resultado visual.

### R14 · `bucketFill` parava antes de preencher a região inteira — ✅ **corrigido**
A busca em largura contabilizava coordenadas **fora do canvas** contra o orçamento de
`pixelLimit`:

```dart
if (!visited.add(normalized)) continue;   // contabiliza antes de validar
if (!inBounds(normalized)) continue;
```

Como a vizinhança de 8 gera coordenadas externas em toda a borda, o orçamento se esgotava
cedo. Num canvas 5×5 o preenchimento parava em 16 de 25 pixels; no canvas real
(500×281) sobrava uma faixa não preenchida junto às bordas.

**Correção:** validar limites antes de contabilizar. Duas linhas trocadas de ordem.

### R11 · O cliente cria a sala
`DrawGameRoomPage._initializeSocket()` chama `Tests.createRoom(widget.roomName)` **sempre**,
inclusive em release, porque `Tests.isTesting` é `const true`. Criação de sala é decisão de
servidor; hoje qualquer cliente cria qualquer sala ao entrar.

### R12 · Botões de debug no build de produção
`Tests.isTesting == true` renderiza dois `IconButton` de "simular desconexão" na app bar
do jogo. Vai para a loja.

---

## P2 — Dívida arquitetural

### A1 · Sem inversão de dependência no transporte
`SocketManager.instance` é singleton eager: o construtor privado já chama
`socket_io_client.io('http://localhost:5555', ...)` e `connect()`. Consequências:
- URL fixa — não há dev/staging/prod;
- qualquer teste que monte um widget abre socket real;
- impossível injetar fake;
- ordem de inicialização implícita.

É o **item de maior alavancagem** do plano inteiro.

### A2 · ViewModel acoplado ao `State`
`GamePageViewModel extends State<DrawGameRoomPage>`, `AnswersChatViewModel extends
State<AnswersChatView>`, `MessagesChatViewModel extends State<MessagesChatView>`,
`DrawingCanvasViewModel extends State<DrawingCanvas>`.
Testar a regra exige montar árvore de widgets. `test/countdown_test.dart` só funciona
porque instancia um `State` órfão — frágil e não generalizável.

### A3 · Ausência de camadas no app
`lib/features/` tem página, parsing de JSON, emissão de socket e regra de turno no mesmo
arquivo. Não existe `domain/`, `data/` nem repositório. `Message.fromJson` é chamado de
dentro de um callback de socket registrado por um `State`.

### A4 · Strings de evento espalhadas
21 literais distintos (`'room:join'`, `'game:turn:new'`, `'chat:answer:result'`,
`'drawing:stroke:lastPoints'`, …) duplicados entre Dart e Go, sem constante compartilhada.
Typo em qualquer lado = evento que nunca chega, sem erro.

### A5 · Modelo duplicado em 3 lugares sem fonte de verdade
`Participant` existe em `lib/features/draw_game/models/participants.dart` (Dart),
`packages/drawly_core/.../socket_dtos.dart` (`RoomUserDTO`, parcial) e
`backend-go/src/types.go` (Go). Metade dos `fromJson`/`toJson` está **comentada**.
Divergência é questão de tempo.

### A6 · Boilerplate de listener repetido 8×
O padrão `late final void Function(dynamic) _onXEvent;` + `onEvent` no `initState` +
`offEvent` no `dispose` aparece em 8 arquivos, com 3 variações sutilmente diferentes —
e é justamente onde estão os vazamentos R7.

### A7 · `Stroke` não é comparável e não é determinístico
`abstract class Stroke` tem `final DateTime createdAt = DateTime.now()` — campo não usado
em lugar nenhum, que torna toda instância única no tempo. Não há `==`/`hashCode`, então
teste de igualdade de stroke é impossível sem comparar campo a campo na mão.
`Stroke` também deveria ser `sealed` (a hierarquia é fechada e o `switch` do `fromJson`
já a trata como tal).

### A8 · Serialização via `toString()`
`StrokeType.toString()` é sobrescrito para devolver `'normal'`, `'eraser'`… e é isso que
vai no JSON. Acoplar wire format a `toString()` é frágil: qualquer refactor de debug quebra
o protocolo. Use `.name` + parser explícito.

### A9 · Backend inteiro em `package main`
11 arquivos, zero pacotes internos, zero interfaces. Handlers dependem de `*socket.Server`
concreto, por isso não são testáveis sem subir servidor.

### A10 · Forks vendorizados de bibliotecas de terceiros
`backend-go/external/` contém cópias de `socket.io`, `engine.io` e `gommon` amarradas por
`replace` no `go.mod`. Não há registro do porquê nem do delta em relação ao upstream.
É um custo de manutenção permanente e um risco de segurança (não recebe patch).
Ação: documentar o motivo do fork ou voltar ao upstream.

### A11 · `lib/testing/` é código de produção
Não é diretório de teste — é código compilado no app, importado por
`draw_game_room_page.dart`. Ver R11/R12.

### A12 · Golden tests testam o caminho quebrado
Os 12 goldens de gesto dependem de o traço aparecer via eco de servidor (R9). Sem
servidor, todos capturam canvas vazio. Precisam ser reescritos para semear `rxAllStrokes`
diretamente — que é a fonte real do render — e os gestos passam a ser verificados pelo
payload emitido, não por pixel.

---

## P3 — Higiene

| # | Item |
|---|---|
| H1 | ✅ **corrigido** — versões divergiam (raiz `0.53.5+4`, packages e Go `0.51.5`); hoje os cinco pontos sobem juntos em `0.54.0`, validado por `scripts/set_version.sh --check` |
| H2 | Sem CI, sem gate de lint, format ou cobertura |
| H3 | CORS com 8 origens `localhost` hardcoded; `log.DEBUG = true` fixo; porta fixa |
| H4 | Erro de `http.ListenAndServe` ignorado (`go http.ListenAndServe(...)`) |
| H5 | Dependências declaradas e não usadas em `drawing_board`: `file_picker`, `file_saver`, `image_picker`, `universal_html`, `url_launcher` (removidas na fase 0) |
| H6 | `analysis_options.yaml` da raiz exclui `firebase_options_dev.dart`/`_prod.dart`, arquivos que não existem |
| H7 | Comentários em 3 idiomas misturados (PT/EN) e blocos grandes de código comentado (`drawly_app.dart` tem 50 linhas mortas) |
| H8 | `README.md` tem 8 linhas e documenta um backend Node que não existe mais |
| H9 | `pubspec.yaml` raiz: `# TODO(Kevin): Remove this dependency` sobre `socket_io_client` — o app não deveria depender dele direto, só via `drawly_core` |
| H10 | `docs/Pictionary/Untitled.md` com 2078 linhas sem título nem estrutura |
| H11 | Sem autenticação real: `Authorization: 'Bearer token'` literal; servidor força `IsLogged: true` |
