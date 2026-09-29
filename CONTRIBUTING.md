# Contributing to Drawly

Thanks for taking the time to contribute. This guide covers how to get the project running,
the conventions we follow, and how to get a change merged.

## Table of contents

- [Ways to contribute](#ways-to-contribute)
- [Development setup](#development-setup)
- [Repository structure](#repository-structure)
- [Coding standards](#coding-standards)
- [Tests](#tests)
- [Commits](#commits)
- [Pull requests](#pull-requests)
- [Reporting bugs](#reporting-bugs)

## Ways to contribute

- **Fix a known limitation.** The [Known limitations](README.md#known-limitations) section of
  the README lists concrete, self-contained items — a good place to start. Each maps to an
  entry in [docs/Pictionary/refactoring/01-achados.md](docs/Pictionary/refactoring/01-achados.md),
  usually with a `skip:`-marked test that already demonstrates the bug.
- **Report a bug** with clear reproduction steps.
- **Propose a feature.** Open an issue before writing code so we can agree on the approach.
- **Improve the docs.** Corrections to setup instructions or the socket protocol table are
  always welcome.

For anything beyond a small fix, open an issue first. It is much easier to align on direction
before the code exists than after.

## Development setup

### Prerequisites

- **Flutter 3.29.2** — pinned in `.fvmrc`. We recommend [FVM](https://fvm.app) so your local
  version matches the project:
  ```bash
  dart pub global activate fvm
  fvm install
  ```
- **Go ≥ 1.23.1**
- A **Firebase project** of your own (see below)

### Steps

```bash
git clone https://github.com/<your-username>/drawly_project.git
cd drawly_project

# 1. Server
cd backend-go && go run ./src   # listens on :5555

# 2. Firebase — generates lib/firebase_options.dart for YOUR project
dart pub global activate flutterfire_cli
flutterfire configure

# 3. Client
fvm flutter pub get
fvm flutter run -d chrome --web-port 8081
```

Then install the git hooks — one of them validates commit messages against the convention
below, so it saves you a rejected commit later:

```bash
./scripts/install_hooks.sh
```

### Never commit credentials

`flutterfire configure` writes files containing your own Firebase project's identifiers:

- `lib/firebase_options.dart`
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `macos/Runner/GoogleService-Info.plist`

Keep these out of your pull requests. Check `git status` before committing.

### Testing with more than one player

A room needs at least 2 players and holds at most 4. `.vscode/launch.json` defines configs
`8081`–`8088` that launch the dev entrypoints in `lib/testing/` on separate web ports. Start
two of them, join the same room name in both, and you have a playable game on one machine.

If you add a web port, add it to the CORS allowlist in `backend-go/src/main.go` too —
otherwise the connection is silently rejected.

## Repository structure

The Flutter side is a small monorepo of path-linked packages:

| Path                          | What lives there                                            |
| ----------------------------- | ----------------------------------------------------------- |
| `lib/`                        | App shell, routing, auth and game-room screens               |
| `packages/drawing_board/`     | Canvas rendering, drawing tools, undo/redo stack, bucket fill |
| `packages/drawly_core/`       | Socket manager and DTOs shared across the app                |
| `packages/drawly_design_system/` | Theme, colors and reusable widgets                       |
| `backend-go/src/`             | Go server: rooms, turns, drawing state, chat, scoring        |
| `backend-go/external/`        | Vendored socket.io / engine.io forks (`replace` in `go.mod`) |
| `scripts/`                    | Quality gates: analyze, test, coverage, version, hooks       |
| `docs/Pictionary/refactoring/`| Architecture audit and the phased refactoring roadmap        |

[CLAUDE.md](CLAUDE.md) is the normative rulebook for this repository — layering, the realtime
contract, lifecycle checklists, Go concurrency rules and the commit convention. When code and
CLAUDE.md disagree, the code is wrong.

**Put code in the lowest layer that makes sense.** Anything reusable by more than one screen
belongs in a package, not in `lib/`. `drawly_core` must not depend on
`drawly_design_system` — keep transport and UI separate.

If you change something that crosses the client/server boundary (a socket event, a DTO
field), update **both** sides in the same pull request, and update the protocol table in the
README.

## Coding standards

Run the whole gate with one command — it is the same one CI runs, so there is no
"works on my machine":

```bash
./scripts/analyze.sh
```

It checks formatting and analysis across all four Dart modules, `gofmt` and `go vet` on the
server, and the architecture invariants in `scripts/check_architecture.sh`.

### Dart

We use [`very_good_analysis`](https://pub.dev/packages/very_good_analysis) (see
`analysis_options.yaml`). Analyzer warnings should be fixed, not suppressed. If an ignore is
genuinely necessary, scope it to the line and explain why in a comment.

### Go

Keep shared game state under `stateMu` (see `backend-go/src/state_lock.go`) and never use a
type assertion without the `ok` form — a malformed payload must return an error, not panic.

Keep handler functions in the file that matches their domain — `room*.go`, `drawing.go`,
`events.go` — rather than growing `main.go`.

### Language

Code identifiers, documentation and commit messages are in **English**. In-game strings and
the word list are in **Portuguese (pt-BR)**, since that is the target audience. Existing
comments are a mix; new comments should be in English.

## Tests

```bash
./scripts/test.sh        # everything, including go test -race
./scripts/coverage.sh    # coverage against the per-module floor
```

Please add tests with your change:

- **Server logic** — room lifecycle, turn advancement, scoring, guess validation and stroke
  parsing are all unit-testable without a live socket. Follow the existing tests in
  `backend-go/src/*_test.go`; `resetGlobalState()` and `withState()` are the shared helpers.
- **Client** — models, DTO serialization and pure utilities (`bucket_fill`, `polygon_utils`,
  the undo/redo stack) should have unit tests. For anything that talks to the server, inject
  `FakeRealtimeGateway` from `package:drawly_core/testing.dart` — **no test may open a
  socket, touch the disk or use the real clock.**

Two rules that are easy to get wrong:

- Coverage has a **floor** per module, enforced by `scripts/coverage.sh`. It may not drop.
- If you find a bug the current code has, do not quietly adjust the assertion to match. Write
  the test that fails, mark it `skip:` with a pointer to
  `docs/Pictionary/refactoring/01-achados.md`, and fix it in its own `fix:` commit.

A pull request that changes behavior without touching a test will usually be asked for one.

## Commits

Conventional Commits, prefixed with the product version:

```
<version>; <type>: <imperative description in lowercase English>
```

```
0.54.0+5; feat: add spray tool opacity control
0.54.0+5; fix: keep turn timer running when the drawer reconnects
0.54.0+5; test: cover guess validation for accented words
0.54.0+5; docs: document the chat:answer:result payload
0.54.0+5; refactor: extract stroke serialization from events.go
0.55.0+6; chore: bump version
```

- The version is the product version **after** the commit, and must match `version:` in the
  root [pubspec.yaml](pubspec.yaml).
- Types: `feat` `fix` `refactor` `test` `perf` `docs` `style` `build` `ci` `chore`.
- Imperative mood, lowercase first letter, no trailing period, ≤ 60 characters.
- One commit, one intention. A refactor and a feature do not travel together.

`./scripts/install_hooks.sh` installs a `commit-msg` hook that enforces all of the above,
including the version match. Full rules in [CLAUDE.md](CLAUDE.md) §9.

Keep each commit focused on one logical change. Rebase to clean up "wip" commits before
opening a pull request.

### Versioning

The app, the three packages and the Go `Version` constant all move together:

```bash
./scripts/set_version.sh 0.55.0+6   # writes all five places
./scripts/set_version.sh --check    # CI runs this
```

## Pull requests

1. Fork the repo and branch from `master`:
   ```bash
   git checkout -b feat/my-change
   ```
2. Make your change, with tests.
3. Verify locally — the same commands CI runs:
   ```bash
   ./scripts/analyze.sh && ./scripts/test.sh && ./scripts/coverage.sh
   ```
4. Open the pull request against `master` and describe:
   - **what** changed and **why**
   - how you tested it (which platforms, how many players)
   - any protocol or DTO changes
   - screenshots or a short recording for UI changes

Keep pull requests small and single-purpose. A large refactor bundled with a bug fix is hard
to review and slow to merge.

## Reporting bugs

Open an issue including:

- what you expected versus what happened
- steps to reproduce, including how many players were in the room
- platform and version (`fvm flutter --version`, `go version`, OS, browser if on web)
- relevant server output — the Go server logs socket events and turn transitions
- any client console errors

Bugs that only appear with multiple players should say how many, and whether anyone
disconnected or joined mid-turn — those paths are the most fragile.

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE).
