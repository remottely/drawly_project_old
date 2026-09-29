# Arquitetura Alvo

Estado final pretendido ao término da fase 5. Serve de referência para revisar qualquer
PR: se a mudança não caminha para cá, ela precisa de justificativa.

---

## Visão macro

```
┌──────────────────────────── Flutter ────────────────────────────┐
│                                                                 │
│  presentation   widgets + controllers (ChangeNotifier)          │
│        │ depende de ↓                                           │
│  domain         entidades + regras puras + interfaces de repo   │
│        ↑ implementado por                                       │
│  data           repositórios · DTOs · mappers · gateway         │
│                                    │                            │
└────────────────────────────────────┼────────────────────────────┘
                                     │ RealtimeGateway
                              socket.io (contrato compartilhado)
                                     │
┌────────────────────────────────────┼────────────────────────────┐
│  transport      handlers: parse → game → broadcast              │
│        │                                                        │
│  registry       RoomRegistry (mutex) — dono de todo o estado    │
│        │                                                        │
│  game           Room · Turn · Score · Drawing · Stroke          │
│                 zero import de socket.io                        │
└──────────────────────────── Go ─────────────────────────────────┘
```

A seta que importa: **domain não aponta para ninguém**. Em ambos os lados.

---

## Regras invariantes

1. **Dependência aponta para dentro.** `presentation → domain ← data`. O domínio não
   conhece Flutter, JSON, socket, nem `SharedPreferences`.
2. **I/O sempre atrás de interface.** Rede, storage, relógio e aleatoriedade são
   injetados. Nada de singleton alcançável de qualquer lugar.
3. **Contrato de rede tem fonte única.** Nome de evento e formato de payload declarados
   uma vez de cada lado, com teste de contrato ligando os dois.
4. **Servidor é autoridade.** Cliente prediz (echo otimista) e reconcilia; nunca decide
   pontuação, turno ou existência de sala.
5. **Estado mutável compartilhado é protegido.** No Go, um dono com mutex. No Dart, um
   controller com ciclo de vida explícito.
6. **Tudo que abre, fecha.** Notifier, controller, timer, listener, subscription.

---

## Estrutura de diretórios alvo

```
drawly_project/
├── lib/
│   ├── main.dart
│   ├── app/                     drawly_app · app_config · di
│   ├── core/                    result · widgets compartilhados
│   └── features/
│       ├── auth/                domain · data · presentation
│       └── draw_game/           domain · data · presentation
│           ├── domain/entities/       Participant · Message · Answer · Turn
│           ├── domain/repositories/   interfaces
│           ├── data/dtos/             1 DTO por payload
│           ├── data/mappers/          DTO ↔ entidade
│           ├── data/repositories/     impl sobre RealtimeGateway
│           └── presentation/          controllers + widgets
├── packages/
│   ├── drawly_core/
│   │   ├── lib/drawly_core.dart
│   │   ├── lib/testing.dart           FakeRealtimeGateway (fora do barrel)
│   │   └── lib/src/
│   │       ├── contracts/             SocketEvents · payload schemas
│   │       └── realtime/              RealtimeGateway · SocketIoGateway
│   │                                  RealtimeSubscriptions
│   ├── drawly_design_system/          tokens + widgets burros, zero domínio
│   └── drawing_board/
│       ├── domain/                    Stroke (sealed) · DrawingTool · UndoRedoStack
│       ├── data/                      DTOs de desenho · DrawingRepository
│       └── presentation/              DrawingCanvas · painter · sidebar
├── backend-go/
│   ├── cmd/server/
│   └── internal/                      config · contracts · game · registry · transport
├── scripts/                           analyze · test · coverage · set_version
└── docs/Pictionary/
    ├── adr/
    └── refactoring/
```

---

## Decisões e seus porquês

| Decisão | Por quê | Alternativa descartada |
|---|---|---|
| `ChangeNotifier`/`ValueNotifier` | já no SDK, suficiente para o escopo, zero build_runner | bloc/riverpod — cerimônia sem ganho aqui |
| DI manual por construtor | grafo pequeno; explícito é mais legível que mágico | `get_it`/`injectable` |
| `fromJson`/`toJson` à mão | ~15 DTOs; codegen custa mais em build time do que economiza | `freezed`/`json_serializable` |
| 3 packages + scripts bash | fronteira já existe e funciona | melos |
| Estado do jogo em memória no Go | partida é efêmera, cabe em RAM | Redis/Postgres |
| Echo otimista no canvas | latência de rede em cada traço é inaceitável no gênero | manter servidor-autoritativo puro |
| `sealed class Stroke` | hierarquia fechada; garante `switch` exaustivo em compilação | manter `abstract` |

Todas revisáveis — mas por ADR, não por PR silencioso.

---

## Como validar que chegamos

Checks automatizáveis, não opinião:

```bash
# domínio não conhece framework
! grep -rn "package:flutter" lib/features/*/domain/

# widgets não falam com transporte
! grep -rn "SocketManager" lib/ packages/*/lib/src/presentation/

# nenhuma string de evento solta
! grep -rnE "'(room|game|chat|drawing):" --include="*.dart" lib/ packages/ \
    | grep -v socket_events.dart

# regra de jogo não conhece transporte
! grep -rn "socket.io" backend-go/internal/game/

# versões sincronizadas
./scripts/set_version.sh --check
```

Esses comandos entram no `analyze.sh`. Arquitetura que não é verificada é arquitetura que
já foi violada.
