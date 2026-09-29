# 11 — Sistema de desenho: etapas seguintes

> Continuação de [10-sistema-de-desenho.md](10-sistema-de-desenho.md). Pressupõe os 15 commits
> de lá concluídos (protocolo v2, controller, render em camadas, balde determinístico, limites
> no servidor). Tudo aqui é **pós-refactor**: nada muda o wire sem passar pela seção 4 do doc 10.

Cada etapa tem um **gate** — o que precisa ser verdade para ela começar — e commits do tamanho
de um dia. Etapas com gate de medição só começam quando o número aparecer; até lá são
YAGNI documentado, não backlog.

| Etapa | Tema | Gate | Muda o wire? |
|---|---|---|---|
| E1 | Fase do turno dentro do desenho | doc 10 concluído | não (usa `turn`) |
| E2 | Paridade de ferramentas com o Gartic | E1 | não |
| E3 | Robustez, fuzz e observabilidade | doc 10 concluído | não |
| E4 | Performance condicionada a medição | números do E3 | E4.3 sim (opcional) |
| E5 | Replay, denúncia e exportação | E1, E3 | E5.1 adiciona campo interno no servidor |
| E6 | Toque e telas pequenas | E2 | não |

Fronteira com o jogo: três itens que o desenho **expõe** mas não resolve, e que pertencem ao
plano do jogo (fase 4): (a) `game:turn:new` manda a palavra para **todos**, inclusive quem
adivinha — é trapaça trivial; (b) não existe intervalo entre turnos nem escolha de palavra;
(c) dicas progressivas. O E1 prepara o cliente para (b) sem implementá-lo.

---

## E1 · Fase do turno dentro do desenho

**Problema.** O canvas só sabe `isCurrentDrawer`. Não há "entre turnos", "turno acabou",
"aguardando". Traços perto do fim do turno vazam para o seguinte (bug do MVP); o servidor
aceita op de quem já não é desenhista até o cliente processar `game:turn:new`.

**Modelo.** O controller ganha uma fase explícita, derivada do que o app lhe informa:

```dart
enum DrawingPhase { idle, drawing, locked }
// idle    → sem turno ativo: canvas visível, input ignorado
// drawing → este cliente é o desenhista do turno atual
// locked  → turno ativo, mas este cliente só assiste
```

`startTurn(turn:, isDrawer:)` já existe (doc 10, 5.3); ganha `endTurn()` (→ `idle`, fecha o
stroke aberto localmente **sem** emitir `end`, porque o servidor já zerou). Input fora de
`drawing` é descartado no controller, não no widget — testável sem árvore.

**Servidor.** `Drawing.Apply` já rejeita `turn != room.TurnCount`. Falta o caso "turno acabou
mas o próximo não começou": `startTurnTimer` passa a chamar `drawing.Reset` **antes** de
emitir `game:turn:new`, e entre o fim do timer e o próximo turno o `Room` fica em
`IsGameStarted && CurrentDrawerTurnIndex == -1` → toda op é rejeitada sem snapshot (não há
o que ressincronizar). Quando o jogo do doc 06 ganhar intervalo entre turnos, esse é o gancho.

| Commit | Teste que trava antes |
|---|---|
| `feat: gate drawing input on an explicit turn phase` | controller: op em `idle`/`locked` não altera estado nem emite; `endTurn` descarta o stroke aberto |
| `feat: reject drawing ops between the end of a turn and the next one` | Go: op depois do timer e antes do `advanceTurn` → rejeitada, sem snapshot |
| `fix: stop the local stroke when the turn changes mid-drag` | widget: `pointerUp` depois de `startTurn` não emite nada |

---

## E2 · Paridade de ferramentas com o Gartic

O conjunto de ferramentas já existe (lápis, borracha, linha, quadrado, círculo, polígono,
balde, cor, opacidade, tamanho, grade, undo/redo/clear). O que falta é **comportamento** que
todo jogador de Gartic espera. Nenhum item muda o wire: são regras de entrada no controller.

| # | Comportamento | Regra | Hoje |
|---|---|---|---|
| E2.1 | **Clamp em vez de descarte** | ponto fora do canvas é projetado na borda antes de quantizar; o traço não quebra ao arrastar para fora e volta contínuo | `_isPointInsideCanvas` descarta; forma arrastada para fora some |
| E2.2 | **Shift restringe** | linha: ângulo múltiplo de 45°; quadrado: lados iguais; círculo: raio igual; polígono: já é regular | `onShiftPressed` existe e não faz nada |
| E2.3 | **Atalhos de ferramenta** | `P` lápis, `E` borracha, `L` linha, `R` quadrado, `C` círculo, `G` polígono, `B` balde, `[`/`]` tamanho, `-`/`+` lados, `Delete` clear (com confirmação de 1 s de pressão), `Ctrl/Cmd+Z`/`Y` já existem | só undo/redo |
| E2.4 | **Atalhos no web** | `Cmd+Z` no navegador: garantir foco no canvas ao entrar como desenhista e `preventDefault` via `Focus` + `Shortcuts`; teste em `TestWidgetsFlutterBinding` com `defaultTargetPlatform` web | bug listado no MVP |
| E2.5 | **Tamanho da borracha independente** | slider próprio; o `w` no wire já suporta até 80 px | comentado no sidebar |
| E2.6 | **Cursor mostra o pincel** | círculo do tamanho `w` sob o ponteiro, na camada viva, só para o desenhista | cursor `precise` |
| E2.7 | **Um ponteiro por vez** | o controller guarda o `pointer` id do `down`; `move`/`up` de outro id são ignorados (segundo dedo, palma) | dois dedos geram um traço cruzado |
| E2.8 | **Formas cortadas no canvas** | painter faz `clipRect` no canvas lógico; com E2.1 nenhum ponto sai, então isto é cinto e suspensório | forma pode pintar fora da área visível |
| E2.9 | **`FocusNode` do `HotkeyListener`** | descartado no `dispose` | vaza |

Todos os itens são testáveis no controller (E2.1, E2.2, E2.7) ou em widget test sem rede
(E2.3–E2.6, E2.9). Golden novo só para E2.6 (cursor), porque é visual.

| Commit |
|---|
| `feat: clamp pointer positions to the canvas instead of dropping them` |
| `feat: constrain shapes and lines while shift is held` |
| `feat: add keyboard shortcuts for every drawing tool` |
| `fix: make undo and redo shortcuts work on the web` |
| `feat: give the eraser its own size` |
| `feat: preview the brush size under the cursor` |
| `fix: ignore secondary pointers while a stroke is in progress` |
| `fix: dispose the hotkey listener focus node` |

---

## E3 · Robustez, fuzz e observabilidade

Sem número não há decisão de performance; sem fuzz não há garantia de `v, ok`. Esta etapa
produz os dois, sem dependência nova.

### E3.1 Fuzz do parser Go

`go test -fuzz=FuzzParseOpBatch` (fuzzing da stdlib) sobre `ParseOpBatch` e `Drawing.Apply`
com corpus semeado pelo fixture do doc 10. Invariantes: nunca `panic`; erro ⇒ estado
intocado; sucesso ⇒ toda coordenada dentro do espaço. Roda 30 s no CI, ilimitado à mão.

### E3.2 Benchmarks Go

`BenchmarkApplyPointsBatch`, `BenchmarkSnapshotEncode`, `BenchmarkParseOpBatch`. Números de
referência entram no `09-estado-atual.md`. São os números que decidem E4.

### E3.3 Métricas do servidor

`expvar` (stdlib) em `/debug/vars`, atrás de env var: por processo, `drawing_ops_total`,
`drawing_bytes_in_total`, `drawing_rejections_total{reason}`, `drawing_snapshots_total`,
`rooms_active`. Sem Prometheus, sem dependência: `curl` e `jq` bastam para um solo dev.

### E3.4 Overlay de debug no cliente

Atrás de `kDebugMode` (regra do CLAUDE.md §7): ops/s enviadas e recebidas, bytes/s, tamanho da
fila, tempo do último balde em ms, fase do turno. É como se mede E4.1 e E4.2 em aparelho real.

### E3.5 Testes de caos com o gateway falso

Sequências que hoje ninguém exercita, em `fake_async`:

- queda no meio do traço → reconexão → snapshot: stroke aberto some, ids continuam de `next`;
- snapshot chegando **antes** do ack do join (é a ordem real);
- `startTurn` do turno N+1 chegando enquanto há lote na fila do turno N → fila descartada;
- rejeição do servidor no meio de uma hachura → snapshot aplicado sem duplicar strokes.

| Commit |
|---|
| `test: fuzz the drawing op parser and reducer` |
| `test: add benchmarks for drawing op parsing, apply and snapshot encoding` |
| `feat: expose drawing counters through expvar behind an env flag` |
| `feat: add a debug overlay with drawing throughput and fill timings` |
| `test: cover reconnection and turn-change races in the drawing controller` |

---

## E4 · Performance condicionada a medição

Cada linha só vira trabalho quando o gate falhar. O que fazer já está decidido para não
decidir sob pressão.

| # | Gate (medido em E3) | Ação | Commit |
|---|---|---|---|
| E4.1 | balde > 50 ms no web (dart2js) ou > 16 ms em AOT, no pior caso realista | cache incremental do raster por turno: estampar cada stroke ao concluir; `remove`/`clear`/snapshot reconstroem | `perf: keep an incremental raster of committed strokes for bucket fill` |
| E4.2 | jank visível no viewer com lotes de 50 ms | interpolar os pontos recebidos ao longo dos 50 ms seguintes na camada viva (só visual; o estado não muda) | `perf: interpolate incoming points on the live layer` |
| E4.3 | bytes/s por sala acima do orçamento de hospedagem | ligar `PerMessageDeflate` no engine.io (env var) — zero mudança de protocolo; medir CPU antes de manter | `build: enable per-message deflate behind an env flag` |
| E4.4 | snapshot médio > 100 KB | simplificação Ramer–Douglas–Peucker **no servidor**, no `end`, com ε = 0,3 px lógico; o desenhista já pintou o original, os viewers já receberam os pontos — só o snapshot encolhe | `perf: simplify finished strokes before storing them` |
| E4.5 | contenção no `stateMu` acima de X % do tempo de handler | lock por sala (já previsto no doc 06, 4.4) — `RoomRegistry` primeiro | (doc 06) |
| E4.6 | GC pressure no cliente por `List<int>` de pontos | `Int32List` crescente no `StrokeBuilder` com dobra de capacidade | `perf: back the stroke builder with a growable typed list` |

Fora daqui, sem gate que justifique: frames binários, delta encoding, balde no servidor
(motivos no doc 10, seção 2).

---

## E5 · Replay, denúncia e exportação

O log de ops **é** o formato de replay. Nada precisa ser inventado; precisa ser guardado.

### E5.1 Carimbo de tempo no servidor

`Drawing` guarda, por op aceita, `ms` desde o início do turno (campo interno do servidor,
**não** vai no `drawing:op` para viewers). Custa 4 bytes por op na memória da sala. Quando o
turno acaba, `Drawing` vira `TurnRecord{room, turn, drawer, word, ops}` numa fila em memória
limitada (últimos N turnos por sala, N configurável, default 3).

### E5.2 Denunciar desenho

`report:drawing {turn}` → o servidor pega o `TurnRecord`, serializa (mesmo codec do
snapshot + `ms`) e entrega ao destino configurado (arquivo em disco no MVP; webhook depois).
Sem UI de moderação neste plano: quem modera reproduz o replay num `DrawingBoard` em modo
leitura, alimentando ops com o mesmo `DrawingController` — o reducer é o mesmo, o render é o
mesmo, logo o replay é fiel por construção.

### E5.3 Exportar PNG

`RenderRepaintBoundary.toImage` já existe (comentado no sidebar). Passa a capturar **só a
camada concluída** em `devicePixelRatio` e entregar via share sheet do sistema. Traz uma
dependência de volta (`share_plus` ou `file_saver`): decidir uma, documentar no pubspec, e só
quando E5.1 estiver feito — para o PNG e o replay saírem da mesma fonte.

| Commit |
|---|
| `feat: timestamp accepted drawing ops and keep the last turns per room` |
| `feat: report a drawing by turn and persist its op log` |
| `feat: replay a turn record on a read-only drawing board` |
| `feat: export the finished drawing as PNG` |

---

## E6 · Toque e telas pequenas

O espaço lógico (500 × 281,25) não muda; o que muda é o que fica em volta dele.

- Sidebar vira **barra inferior** abaixo de 600 px de largura, com alvos de toque ≥ 44 px;
  cor e tamanho em *bottom sheet*.
- `Transform.scale` continua; o canvas ocupa a largura inteira em retrato e a altura
  inteira em paisagem (`_calculateScale` já faz isso; falta teste com `tester.view`).
- Palma e segundo dedo: E2.7 já cobre.
- `MouseRegion`/cursor só em plataformas com mouse.

| Commit |
|---|
| `feat: lay the tool bar out below the canvas on narrow screens` |
| `test: cover canvas scaling in portrait and landscape viewports` |

---

## Critério de saída de cada etapa

- E1: nenhum traço atravessa turno, provado por teste Go e por teste do controller.
- E2: toda ferramenta tem atalho, toda restrição tem teste no controller, nenhum golden regenerado.
- E3: fuzz no CI, benchmarks registrados no `09-estado-atual.md`, overlay e `expvar` desligados por default.
- E4: só o que o gate mandou; cada ação com o número de antes e de depois no commit.
- E5: replay de um turno gravado bate pixel a pixel com o golden do turno original.
- E6: suíte de widget roda nos três viewports (desktop, retrato, paisagem).

Continuação: o ciclo do turno em volta do desenho em [12-ciclo-do-turno.md](12-ciclo-do-turno.md) e operação/custo em [13-operacao-e-custo.md](13-operacao-e-custo.md).
