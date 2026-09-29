# Fase 3 — Refatoração arquitetural (Dart)

**Status: ⏳** — depende da fase 2 concluída.

Cada passo abaixo é um commit. Cada passo mantém a suíte verde. Se a suíte não cobre o
que o passo toca, volte para a fase 2 antes de continuar.

---

## 3.1 · Corrigir os bugs P1 (antes de mover código)

Bug corrigido em código que ainda está no lugar antigo é mais fácil de revisar do que
bug corrigido no meio de uma mudança estrutural. Um commit `fix:` por item:

| Ordem | Achado | Correção |
|---|---|---|
| 1 | R1 | deletar `tool_type.dart` (código morto com `toString()` recursivo) |
| 2 | R6 | guardar o `Timer.periodic` do buffer e cancelar no `dispose` |
| 3 | R7 | remover listener de `game:turn:new` em `AnswersChatViewModel`; descartar os 4 `ValueNotifier` órfãos; registrar `_onErrorEvent` de forma síncrona |
| 4 | R8 | cancelar o timer de timeout do `emitWithAck` ao receber o ack |
| 5 | R11/R12 | `Tests.isTesting` → `kDebugMode`; parar de criar sala pelo cliente |
| 6 | R9 | decidir echo otimista e implementar (ver abaixo) |

### R9 em detalhe — echo local otimista

Hoje o traço só aparece quando o servidor devolve. Proposta:

1. O painter passa a pintar `rxCurrentStroke` por cima de `rxAllStrokes`.
2. Ao soltar o ponteiro, o stroke local é anexado a `rxAllStrokes` com uma marca
   `pendingId` (UUID gerado no cliente).
3. Quando o eco chega com o mesmo `pendingId`, substitui o local em vez de duplicar —
   generalizando o mecanismo que hoje existe só para bucket (`_awaitingBucketAck`).
4. Se o eco não chega em N segundos, o stroke local é marcado como não confirmado.

Requer um campo `id` no wire format → muda DTO Dart **e** struct Go no mesmo commit.

---

## 3.2 · Extrair camadas no app

Estrutura alvo por feature:

```
lib/
├── app/                        # composition root
│   ├── drawly_app.dart
│   ├── app_config.dart
│   └── di.dart                 # montagem manual, sem container
├── core/
│   ├── result.dart             # Result<T> — erro como valor, sem exception de fluxo
│   └── widgets/
└── features/draw_game/
    ├── domain/
    │   ├── entities/           # Participant, Message, Answer, Turn
    │   └── repositories/       # interfaces
    ├── data/
    │   ├── dtos/               # fromJson/toJson completos
    │   ├── mappers/            # DTO ↔ entidade
    │   └── repositories/       # implementações sobre RealtimeGateway
    └── presentation/
        ├── controllers/        # ChangeNotifier, testável isolado
        └── widgets/
```

Ordem de execução, uma feature por vez (chat é a menor — comece por ela):

1. **`chat`** — criar `ChatRepository` (interface + impl sobre `RealtimeGateway`),
   mover parsing para `data/`, transformar `MessagesChatViewModel` em
   `MessagesChatController extends ChangeNotifier`, injetar no widget.
2. **`answers`** — mesmo desenho; a regra "resposta correta do usuário atual" vai para
   o domínio.
3. **`participants`** — `ParticipantsRepository`.
4. **`game_room`** — o maior: `GameRoomController` com turno, countdown e join/leave.
   O countdown vira uma classe própria (`TurnCountdown`) com `Clock` injetável.
5. **`drawing_board`** — `DrawingRepository`; o `DrawingCanvasViewModel` some.

Regra durante a migração: a página antiga continua funcionando até o último commit da
feature. Nada de big-bang.

---

## 3.3 · Consolidar o modelo de domínio

- `Stroke` vira `sealed class` com `==`/`hashCode` e **sem** `createdAt` (achado A7).
  `sealed` deixa o `switch` do `fromJson` exaustivo em tempo de compilação.
- `StrokeType` serializa por `.name`; `toString()` volta ao padrão (achado A8).
- `Participant`, `Message`, `Answer` viram entidades imutáveis com `Equatable`.
- DTOs ganham os `fromJson` que hoje estão comentados — ou o DTO é deletado.
- Uma definição por conceito. `Participant` deixa de existir em dois lugares.

---

## 3.4 · Eliminar o boilerplate de listener (achado A6)

O padrão repetido 8× vira um helper único em `drawly_core`:

```dart
final class RealtimeSubscriptions {
  RealtimeSubscriptions(this._gateway);
  final RealtimeGateway _gateway;
  final _entries = <(String, RealtimeListener)>[];

  void on(String event, RealtimeListener listener) {
    _gateway.on(event, listener);
    _entries.add((event, listener));
  }

  void dispose() {
    for (final (event, listener) in _entries) {
      _gateway.off(event, listener);
    }
    _entries.clear();
  }
}
```

Um `dispose()` fecha tudo. Impossível esquecer um `off` — que é exatamente a origem de R7.

---

## 3.5 · Fronteira dos packages

- `drawly_design_system` não pode conhecer domínio. Auditar e mover o que violar.
- `drawing_board` não pode importar `package:drawly/*`.
- App para de depender de `socket_io_client` direto (`# TODO(Kevin): Remove this
  dependency` já registrado no `pubspec.yaml`); passa a falar só com `drawly_core`.
- `lib/testing/` sai do app (achado A11).

---

## Critério de saída

- [ ] bugs P1 corrigidos, cada um com o teste que falhava antes
- [ ] nenhum `ViewModel extends State`
- [ ] nenhum widget referencia `SocketManager`
- [ ] nenhum `fromJson` fora de `data/`
- [ ] nenhuma string literal de evento fora de `SocketEvents`
- [ ] grafo de dependência entre packages sem violação
- [ ] cobertura ≥ a da fase 2
