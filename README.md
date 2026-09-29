# Drawly

**Real-time multiplayer draw-and-guess game.** One player draws a secret word on a shared
canvas while everyone else races to guess it in the chat. Built with Flutter on the client
and Go + Socket.IO on the server.

> _"Desenhe, adivinhe e se divirta como nunca."_

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.29.2-02569B?logo=flutter)](https://flutter.dev)
[![Go](https://img.shields.io/badge/Go-1.23-00ADD8?logo=go)](https://go.dev)

---

## Table of contents

- [Features](#features)
- [Architecture](#architecture)
- [Project layout](#project-layout)
- [Getting started](#getting-started)
- [Running the app](#running-the-app)
- [Testing](#testing)
- [Socket protocol](#socket-protocol)
- [Known limitations](#known-limitations)
- [Contributing](#contributing)
- [License](#license)

---

## Features

- **Live shared canvas** — strokes stream point-by-point to every participant, so guessers
  watch the drawing appear in real time rather than at the end of a stroke.
- **Drawing toolkit** — pencil, line, ruler, spray, stamp, eraser and a flood-fill bucket,
  plus a color palette and adjustable stroke size.
- **Synchronized undo/redo** — the drawer's undo/redo stack is mirrored to every client.
- **Turn-based rounds** — the server picks a word, promotes the next drawer, and runs a
  countdown timer; when it expires the next turn starts automatically.
- **Two chats** — a free-form message chat and a guess chat that validates answers against
  the secret word without leaking it.
- **Scoring and ranking** — per-round scoring with a live participant list and end-of-game
  ranking.
- **Rooms** — create or join a named room; rooms hold 2–4 players and clean up after
  disconnects, including handing the turn over if the current drawer drops.
- **Cross-platform** — Android, iOS, web, macOS, Windows and Linux from one codebase.

## Architecture

```
┌─────────────────────────────┐          ┌──────────────────────────────┐
│  Flutter client             │          │  Go server (backend-go)      │
│                             │          │                              │
│  drawly (app shell)         │  Socket  │  rooms manager               │
│  ├── drawing_board  ────────┼══ .IO ══►│  turn timer + word picker    │
│  ├── drawly_core            │  :5555   │  drawing state per room      │
│  └── drawly_design_system   │          │  chat / guess validation     │
│                             │          │  scoring + ranking           │
│  Firebase Auth              │          │                              │
└─────────────────────────────┘          └──────────────────────────────┘
```

The server is authoritative: it owns the current word, whose turn it is, the round timer and
the canonical stroke list for each room. Late joiners get the full canvas replayed via
`drawing:stroke:all`.

> Clients currently render **only** what the server echoes back — including the drawer's own
> strokes, which appear after a full round trip. Optimistic local rendering is planned; see
> [known limitations](#known-limitations).

**Client stack** — Flutter 3.29.2 / Dart 3.7, `socket_io_client`, Firebase Auth for sign-in,
`very_good_analysis` for lints.

**Server stack** — Go 1.23 with `zishang520/socket.io` (vendored under `backend-go/external/`
via `replace` directives in `go.mod`, so no extra fetch step is needed).

## Project layout

```
drawly_project/
├── lib/                        # Flutter app shell
│   ├── features/
│   │   ├── auth/               # sign-in screen
│   │   └── draw_game/          # room selection, game room, chats, participants
│   ├── core/                   # shared widgets and logged-area scaffolding
│   └── testing/                # multi-window dev entrypoints (see .vscode/launch.json)
├── packages/
│   ├── drawing_board/          # canvas, tools, undo/redo stack, bucket fill
│   ├── drawly_core/            # socket manager, shared DTOs
│   └── drawly_design_system/   # theme, colors, reusable UI components
├── backend-go/
│   ├── src/                    # server: rooms, turns, drawing, chat, events
│   └── external/               # vendored socket.io / engine.io forks
├── test/                       # Flutter unit tests
├── scripts/                    # analyze, test, coverage, version, git hooks
├── .github/workflows/          # CI
└── docs/
    └── Pictionary/
        ├── refactoring/        # architecture audit and refactoring roadmap
        └── ...                 # design notes (Obsidian vault)
```

Engineering rules for the repository live in [CLAUDE.md](CLAUDE.md): layering, the realtime
contract, lifecycle checklists and the commit convention.

## Getting started

### Prerequisites

| Tool     | Version   | Notes                                          |
| -------- | --------- | ---------------------------------------------- |
| Flutter  | 3.29.2    | pinned in `.fvmrc` — [FVM](https://fvm.app) recommended |
| Dart SDK | ≥ 3.7.2   | ships with Flutter                             |
| Go       | ≥ 1.23.1  | for the server                                 |

### 1. Clone

```bash
git clone https://github.com/remottely/drawly_project.git
cd drawly_project
```

### 2. Start the server

```bash
cd backend-go
go run ./src
```

The server listens on **`:5555`** and serves the Socket.IO endpoint at `/socket.io/`.

> CORS is allowlisted for `http://localhost:8081` … `http://localhost:8088` in
> [backend-go/src/main.go](backend-go/src/main.go). If you run the web client on another
> port, add it there.

### 3. Configure Firebase

The committed [lib/firebase_options.dart](lib/firebase_options.dart) points at the
maintainers' Firebase project, which you will not have access to. Point the app at your own:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

This regenerates `firebase_options.dart` and the platform config files
(`android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`). Enable the
sign-in providers you want in the Firebase console. **Do not commit your own project's
credentials back to this repo.**

### 4. Install client dependencies

```bash
fvm flutter pub get      # or: flutter pub get
```

The three path-linked packages resolve their own dependencies too:

```bash
for module in packages/*/; do (cd "$module" && fvm flutter pub get); done
```

## Running the app

```bash
fvm flutter run                                   # default device
fvm flutter run -d chrome --web-port 8081         # web (port must be in the CORS list)
```

The client connects to `http://localhost:5555` by default. Point it elsewhere without
touching code:

```bash
fvm flutter run --dart-define=DRAWLY_REALTIME_URL=https://api.example.com
```

The value is read by `AppConfig` in
[app_config.dart](packages/drawly_core/lib/src/config/app_config.dart).

### Playing locally with multiple players

A room needs at least 2 players. [.vscode/launch.json](.vscode/launch.json) ships configs
named `8081`–`8088` that launch separate dev entrypoints from [lib/testing/](lib/testing/) on
different web ports, so you can run several players side by side on one machine. Launch two
of them and join the same room name.

### Release build

```bash
fvm flutter build appbundle --release --analyze-size --target-platform android-arm64
fvm flutter build web --release
```

## Testing

```bash
./scripts/analyze.sh     # format + analyze + go vet + architecture invariants
./scripts/test.sh        # all four Dart modules + Go with the race detector
./scripts/coverage.sh    # per-module coverage against a floor
```

Or per module:

```bash
fvm flutter test                              # app
(cd packages/drawing_board && fvm flutter test)
cd backend-go && go test -race ./src/...      # server
```

`-race` is part of the gate, not optional — it is what surfaced the data race in the shared
game state.

**Client** — DTO round-trips and the realtime contract, the stroke model, the flood-fill
bucket, undo/redo, drawing tools, and widget tests for the canvas and chats driven by an
in-memory `FakeRealtimeGateway` (no sockets are opened in tests).

**Server** — room lifecycle, turn rotation with disconnected players, scoreboard ordering,
guess handling, stroke parsing, disconnect grace period, and a contract test that fails if
the Dart and Go event lists ever diverge.

Golden tests for the canvas live in `packages/drawing_board/test/presentation/widgets/goldens/`.
When one fails, inspect the generated diff in the sibling `failures/` directory before
regenerating — a pixel difference is investigated, never rubber-stamped with
`--update-goldens`.

## Socket protocol

All communication runs over a single Socket.IO connection. Events are namespaced by domain.

**Client → server**

| Event                        | Purpose                                  |
| ---------------------------- | ---------------------------------------- |
| `room:create`                | Create a room and join it as host        |
| `room:join`                  | Join an existing room by name            |
| `room:leave`                 | Leave the current room                   |
| `game:turns:start`           | Start the round loop (host)              |
| `game:ranking`               | Request the current ranking              |
| `drawing:stroke:start`       | Begin a stroke (tool, color, size)       |
| `drawing:stroke:lastPoints`  | Stream the newest points of a stroke     |
| `drawing:undo` / `redo`      | Undo/redo the last stroke                |
| `drawing:clear`              | Clear the canvas                         |
| `chat:message`               | Send a chat message                      |
| `chat:answer:guess`          | Submit a guess for the secret word       |

**Server → client**

| Event                        | Purpose                                            |
| ---------------------------- | -------------------------------------------------- |
| `room:created` / `room:all`  | Room created / full room state                      |
| `room:list:update`           | Available rooms changed                             |
| `room:participants:update`   | Participant list, scores and connection status      |
| `room:error` / `error`       | Error with a suggested client action                |
| `game:turn:new`              | New turn: word, drawer, turn number, duration       |
| `game:ranking`               | Final or requested ranking                          |
| `drawing:stroke:start`       | Another player started a stroke                     |
| `drawing:stroke:lastPoints`  | Incremental stroke points                           |
| `drawing:stroke:all`         | Full canvas replay (late join / new turn)           |
| `drawing:undo` / `redo` / `clear` | Canvas state changes                           |
| `chat:message`               | Chat message broadcast                              |
| `chat:answer:result`         | Whether a guess was correct                         |

Errors carry an `action` hint (`nothing`, `retry`, `ignore`, `log`, `pop`, `dialog`) telling
the client how to react — see `ErrorDTO` in [backend-go/src/types.go](backend-go/src/types.go).

## Known limitations

These are open items — contributions welcome. Each one is tracked in
[docs/Pictionary/refactoring/01-achados.md](docs/Pictionary/refactoring/01-achados.md) with a
severity and a target phase, and most have a test marked `skip:` that demonstrates the
behaviour.

1. **The drawer does not see their own stroke until the server echoes it.** The painter
   renders only the server-confirmed stroke list, so drawing lags by a round trip — and shows
   nothing at all if the socket drops. Optimistic local rendering with reconciliation is the
   planned fix (`R9`).
2. **The word list is a placeholder.** `wordsList` in
   [backend-go/src/room_game.go](backend-go/src/room_game.go) contains a single stub word; the
   real Portuguese list is commented out just below it. Word selection also uses
   `time.Now().UnixNano() % n` rather than `math/rand` (`R10`).
3. **Scoring is not reproducible.** The rank of a correct guess is derived from Go map
   iteration order, which is randomised by design, so 2nd and 3rd place can swap between
   identical runs (`R2`).
4. **Firebase credentials are committed** and scoped to the maintainers' project. They should
   move out of version control.
5. **The client creates rooms.** Joining a room emits `room:create` first, from debug code
   that ships in release builds. Room creation belongs to the server (`R11`/`R12`).
6. **Malformed payloads can panic a handler.** Several server type assertions omit the `ok`
   check (`R4`), and one nil dereference is reachable when a room loses every drawer (`R3`).
7. **The architecture is mid-refactor.** ViewModels still extend `State`, widgets still reach
   for a global socket singleton, and the Go server still keeps game state in package-level
   maps. `./scripts/check_architecture.sh` lists these as *pending* rules; they become
   blocking as each phase lands.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, coding standards
and the pull request process. Open an issue first for anything substantial so we can agree on
the approach before you invest time in it.

## License

Released under the [MIT License](LICENSE).
