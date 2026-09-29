# CLAUDE.md — Drawly

Regras de engenharia do projeto. Este arquivo é normativo: quando o código diverge
daqui, o código está errado. Vale para humanos e para agentes.

Projeto **solo dev**. Toda regra abaixo passa pelo filtro **DRY / KISS / YAGNI**:
arquitetura robusta onde há risco real (contrato de rede, regra de jogo, render do
canvas), simples e direta onde não há.

---

## 1. Topologia do repositório

```
drawly_project/
├── lib/                        # app Flutter (composition root + features)
├── packages/
│   ├── drawly_core/            # contratos + transporte (sem UI)
│   ├── drawly_design_system/   # tokens visuais + widgets burros
│   └── drawing_board/          # feature-package: canvas de desenho
├── backend-go/
│   ├── src/                    # servidor socket.io (Go)
│   └── external/               # forks vendorizados (socket.io/engine.io/gommon)
└── docs/Pictionary/refactoring/# planejamento vivo da refatoração
```

### Regra de dependência (unidirecional, sem ciclos)

```
        drawly (app)
        ↙          ↘
 drawing_board → drawly_core
        ↘          ↙
     drawly_design_system
```

- `drawly_core` **não** importa Flutter material/widgets. Só `dart:*` e o cliente de socket.
- `drawly_design_system` **não** conhece domínio, socket, nem regra de jogo. Widget que
  recebe `roomName` ou fala com socket não pertence a ele.
- `drawing_board` **não** importa `package:drawly/*`. Uma feature-package nunca conhece o app.
- O app é o **único** lugar que pode compor tudo (composition root).

Toda dependência nova precisa passar nesse grafo. Se não passa, o código está na camada errada.

---

## 2. Arquitetura por camadas

Clean Architecture **pragmática**: 3 camadas, sem cerimônia inútil.

```
presentation/   widgets + controllers.  Sem regra de negócio, sem JSON, sem socket.
domain/         entidades + regras puras + interfaces de repositório. Zero imports de infra.
data/           repositórios concretos, DTOs, mapeadores, gateways. Implementa domain.
```

### O que é proibido

| Proibido | Por quê |
|---|---|
| `Widget`/`State` chamando `SocketManager` direto | acopla UI ao transporte; impede teste |
| `fromJson`/`toJson` dentro de `presentation/` | parsing é responsabilidade de `data/` |
| `ViewModel extends State<T>` | prende a lógica ao ciclo de vida do widget |
| String literal de evento fora de `SocketEvents` | typo vira no-op silencioso |
| Regra de pontuação/turno no cliente | o servidor é a autoridade |
| `import 'package:flutter/material.dart'` em `domain/` | domínio não conhece framework |

### Controllers

Controller é uma classe **normal**, não um `State`. Recebe suas dependências pelo
construtor, expõe estado por `ValueNotifier`/`ChangeNotifier` e tem `dispose()` próprio.

```dart
// ✗ ERRADO — atual
abstract class GamePageViewModel extends State<DrawGameRoomPage> { ... }

// ✓ CERTO
final class GameRoomController extends ChangeNotifier {
  GameRoomController({required GameRoomRepository repository}) : _repository = repository;
  final GameRoomRepository _repository;
  // ...
}
```

O widget instancia o controller em `initState`, escuta e chama `dispose()`. Nada além disso.

### Inversão de dependência no transporte

O `SocketManager` singleton com `localhost:5555` hardcoded no construtor é a raiz da
não-testabilidade do projeto. O contrato correto vive em `drawly_core`:

```dart
abstract interface class RealtimeGateway {
  void on(String event, RealtimeListener listener);
  void off(String event, RealtimeListener listener);
  void emit(String event, Map<String, dynamic> payload);
  Future<Map<String, dynamic>> emitWithAck(String event, Map<String, dynamic> payload);
  void connect();
  void disconnect();
  Future<void> dispose();
}
```

- Produção: `SocketIoGateway implements RealtimeGateway`, URL vinda de `AppConfig`.
- Teste: `FakeRealtimeGateway` em memória — sem rede, determinístico.
- Repositórios recebem `RealtimeGateway` por construtor. **Nunca** um singleton global.

---

## 3. Contrato de eventos (fonte única de verdade)

Todo evento socket.io é declarado **uma vez** em `packages/drawly_core/lib/src/contracts/socket_events.dart`
e espelhado em `backend-go/src/contracts.go`. String literal de evento em qualquer
outro arquivo é bug.

```dart
abstract final class SocketEvents {
  static const roomJoin = 'room:join';
  static const gameTurnNew = 'game:turn:new';
  // ...
}
```

Mudou um evento ou um campo de payload? Os **três** lados mudam no mesmo commit:
DTO Dart, struct Go, e os testes de contrato.

### DTOs

- `data/dtos/` — um DTO por payload, com `fromJson`/`toJson` **completos**. Não existe
  `fromJson` comentado: ou o payload é lido e o método existe, ou o DTO não deveria existir.
- Mapeamento DTO ↔ entidade de domínio fica em `data/mappers/`. A entidade não conhece JSON.
- DTO é `final class`, imutável, com `==`/`hashCode` (via `Equatable` ou manual).

---

## 4. Regras de código Dart

- Lint: `very_good_analysis`. `dart analyze` deve sair com **zero** issues. Warning não se acumula.
- `final class` por padrão. `sealed` para hierarquias fechadas (ex.: `Stroke`).
- Imutabilidade por padrão: campo `final`, `copyWith` quando precisar variar.
- **Nada de `DateTime.now()`, `Random()` ou `Timer` dentro de entidade/domínio.** Injete
  um `Clock`/`Random` se realmente precisar — senão o objeto é intestável.
- Toda hierarquia de valor (`Stroke`, `Message`, DTOs) implementa `==`/`hashCode`.
- `toString()` **nunca** é usado para serialização. Enum serializa por `.name` + parser
  explícito com fallback tratado.
- Código morto é deletado, não comentado. Git é o histórico.
- `TODO` sem dono e sem contexto é proibido. Formato: `// TODO(Kevin): <o quê> — <por quê>`.

### Ciclo de vida — checklist obrigatório

Todo `dispose()` fecha **tudo** que foi aberto no mesmo escopo:

- [ ] cada `ValueNotifier`/`ChangeNotifier` criado → `.dispose()`
- [ ] cada `TextEditingController`/`ScrollController` → `.dispose()`
- [ ] cada `Timer`/`Timer.periodic` → guardado em campo e `.cancel()`
- [ ] cada listener registrado no gateway → `off(...)`
- [ ] cada `StreamSubscription` → `.cancel()`

Listener registrado dentro de função `async` e removido em `dispose()` é bug de corrida
(`LateInitializationError`): registre de forma síncrona.

### Nomenclatura

- Prefixo `rx` só para `ValueNotifier` exposto pela camada de apresentação.
- Arquivos e diretórios em `snake_case`; um tipo público por arquivo.
- Barrels (`src.dart`, `widgets.dart`) exportam; não contêm lógica.

---

## 5. Regras de código Go

- Nada de `package main` monolítico. Estrutura alvo:
  `cmd/server/`, `internal/game/`, `internal/realtime/`, `internal/transport/`.
- **Estado compartilhado é sempre protegido.** `rooms`, `roomDrawings`, `roomUsers` são
  mapas globais mutados por múltiplas goroutines (callbacks do socket + `time.AfterFunc`).
  Isso é data race. Alvo: um `RoomRegistry` com `sync.RWMutex` (ou canal/actor), sem globais.
- `go test -race ./...` faz parte do gate. Sem exceção.
- **Zero type assertion sem `ok`.** `data["userId"].(string)` derruba a goroutine com
  payload malformado. Use sempre `v, ok := x.(T)` e responda erro ao cliente.
- Handler não depende de `*socket.Server`. Depende de uma interface local:
  ```go
  type Broadcaster interface {
      ToRoom(room, event string, payload any)
      ToClient(clientID, event string, payload any)
  }
  ```
  Assim a regra de jogo é testável sem rede.
- Regra de jogo é **determinística**: nada de iterar `map` para calcular ordem/rank
  (a ordem de iteração de mapa em Go é aleatória por design). Use slice ordenado.
- Aleatoriedade real usa `math/rand`, não `time.Now().UnixNano() % n`.
- Configuração (porta, CORS, durações, `log.DEBUG`) vem de env var com default, nunca hardcoded.
- Erro retornado nunca é ignorado — inclusive `http.ListenAndServe`.

---

## 6. Testes

**Regra dura: nenhum refactor entra sem teste que cubra o comportamento alterado antes da mudança.**
Teste é a rede de segurança da refatoração; escrever depois é aceitar regressão silenciosa.

### Pirâmide

| Nível | Onde | O que cobre | Velocidade |
|---|---|---|---|
| Unit | `test/domain`, `test/data` | regras puras, mapeadores, DTOs | ms |
| Controller | `test/presentation` | controllers com `FakeRealtimeGateway` | ms |
| Widget | `test/presentation/widgets` | render + interação, sem rede | dezenas de ms |
| Golden | `packages/drawing_board/test/.../goldens` | pixels do canvas | centenas de ms |
| Go unit | `backend-go/src/*_test.go` | sala, turno, score, parsing | ms |

### Cobertura: piso e meta

`./scripts/coverage.sh` gateia dois números por módulo:

- **piso** — trava o nível já conquistado. Cair abaixo dele falha o build.
- **meta** — o alvo da refatoração. Ao atingir, promova o piso.

| Alvo | Meta |
|---|---|
| `drawly_core` | 90% |
| `drawing_board` | 90% |
| `drawly_design_system` | 60% |
| app `lib/` | 85% |
| `backend-go/src` | 80% |

Os pisos vigentes vivem em `scripts/coverage.sh`, com o motivo de cada distância
para a meta. Estado atual: [docs/Pictionary/refactoring/09-estado-atual.md](docs/Pictionary/refactoring/09-estado-atual.md).

Cobertura é piso, não objetivo. Cobrir linha sem asserção útil não conta.

### Regras

- Teste **não** toca rede, disco, relógio real ou `SharedPreferences` real. Injete fake.
- Nome do teste descreve comportamento, não implementação:
  `'não avança o turno quando o desenhista se reconecta dentro da tolerância'`.
- Um `expect` conceitual por teste. AAA (arrange/act/assert) explícito.
- Golden test só para o que é genuinamente visual (canvas). Golden **nunca** é regerado
  para "fazer passar": diferença de pixel é investigada, e só então `--update-goldens`.
- Teste com `sleep`/`Future.delayed` real é proibido — use `fake_async` (Dart) e
  variável de duração injetável (Go).
- Fakes ficam em `test/support/`, compartilhados, nunca duplicados por arquivo.

### Comandos

```bash
./scripts/analyze.sh              # format + analyze + go vet + invariantes de arquitetura
./scripts/test.sh                 # 4 módulos Dart + Go com -race
./scripts/coverage.sh             # cobertura por módulo, com piso e meta
./scripts/check_architecture.sh   # invariantes por grep (embutido no analyze)
./scripts/set_version.sh --check  # versões sincronizadas nos 5 pontos
./scripts/install_hooks.sh        # instala o hook que valida a mensagem de commit
```

`check_architecture.sh` separa **regras ativas** (bloqueiam o build) de **regras
pendentes** (informativas até a fase correspondente concluir). Conforme a refatoração
avança, cada regra migra de pendente para ativa — é assim que o progresso arquitetural
fica verificável em vez de declarado.

---

## 7. Configuração e ambientes

- Nenhum host, porta, chave ou flag hardcoded em código de produção.
  Dart: `--dart-define` lido por `AppConfig`. Go: env var com default.
- `lib/testing/` **não** vai para release. Helpers de debug ficam atrás de
  `kDebugMode`, nunca de uma `const isTesting = true`.
- Hoje `DrawGameRoomPage` chama `Tests.createRoom(...)` no join — o cliente cria a sala.
  Isso é dívida crítica: criação de sala é decisão de servidor.

---

## 8. Versionamento

Uma versão para o produto inteiro. App, os três packages e a constante `Version` do Go
sobem **juntos**, no mesmo commit. Versão divergente é bug de release, não flexibilidade.

`./scripts/set_version.sh <versão>` escreve nos cinco lugares de uma vez; o `--check`
falha se algum divergir, e roda no CI.

`MAJOR.MINOR.PATCH+BUILD`, semântico. `BUILD` incrementa a cada artefato publicado.

---

## 9. Convenção de commits

Formato obrigatório:

```
<versão>; <tipo>: <descrição no imperativo, em inglês, minúscula>
```

Exemplo canônico:

```
0.53.5+4; chore: remove legacy Node.js backend version implementation
```

Regras:

- `<versão>` é exatamente a versão do produto **após** o commit (igual ao `version:` do
  `pubspec.yaml` raiz). Se o commit sobe versão, use a nova.
- `;` seguido de um espaço. Depois `<tipo>: `.
- Descrição no **imperativo**, **inglês**, **minúscula inicial**, **sem ponto final**,
  máximo 72 caracteres na primeira linha.
- Um commit = uma intenção. Refactor e feature não viajam juntos.
- Corpo (opcional) separado por linha em branco, explicando **por quê**, não o quê.

Tipos permitidos:

| Tipo | Uso |
|---|---|
| `feat` | novo comportamento visível ao usuário |
| `fix` | correção de bug |
| `refactor` | muda estrutura sem mudar comportamento |
| `test` | adiciona ou corrige teste |
| `perf` | melhora de performance |
| `docs` | documentação |
| `style` | formatação, sem efeito em código |
| `build` | dependências, pubspec, go.mod, scripts de build |
| `ci` | pipeline |
| `chore` | manutenção, remoção de código morto |

Exemplos válidos:

```
0.54.0+5; feat: add reconnect grace period indicator to the room header
0.54.0+5; fix: prevent stroke buffer timer from leaking on canvas dispose
0.54.0+5; refactor: extract RealtimeGateway interface from SocketManager
0.54.0+5; test: cover room turn rotation with disconnected participants
0.54.0+5; build: drop font_awesome_flutter in favour of material icons
```

Exemplos inválidos:

```
fix: bug                                   → falta versão
0.54.0+5 fix: bug                          → falta ';'
0.54.0+5; Fix: Corrige o bug.              → tipo capitalizado, PT-BR, ponto final
0.54.0+5; feat: add scoring and refactor room registry and fix timer
                                           → múltiplas intenções
```

---

## 10. Definition of Done

Uma mudança só está pronta quando **todos** os itens passam:

- [ ] `./scripts/analyze.sh` limpo (format + analyze + `go vet`)
- [ ] `./scripts/test.sh` verde, incluindo `-race`
- [ ] cobertura não caiu
- [ ] comportamento novo tem teste; bug corrigido tem teste que falhava antes
- [ ] nenhum `dispose`/`cancel`/`off` faltando no diff
- [ ] nenhuma string literal de evento nova
- [ ] versão sincronizada nos 5 pontos (raiz, 3 packages, Go)
- [ ] commit no formato da seção 9

---

## 11. Estado atual e plano

O planejamento executável vive em [docs/Pictionary/refactoring/](docs/Pictionary/refactoring/).
Comece por [00-overview.md](docs/Pictionary/refactoring/00-overview.md).

Ordem inegociável: **destravar build → seams de testabilidade → cobertura → refatorar**.
Refatorar antes da cobertura é apostar que nada quebra.
