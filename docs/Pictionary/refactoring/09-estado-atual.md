# Estado Atual

Retrato do repositório ao término das fases 0 e 1, com a fase 2 parcialmente executada.
Atualize este arquivo ao concluir cada fase.

---

## Antes × depois

| | Antes | Depois |
|---|---|---|
| `flutter pub get` na raiz | ❌ falhava (`fluo` inexistente) | ✅ resolve |
| Testes Go | ❌ 13 arquivos nunca compilaram | ✅ compilam e rodam |
| Testes `drawing_board` | ❌ package não compilava | ✅ 110 passando, 0 skip |
| Testes `drawly_core` | 2 arquivos, 11 testes | ✅ 49 testes |
| Testes `drawly_design_system` | 2 testes | ✅ 21 testes |
| Testes do app | 3 arquivos, socket real | ✅ 34 testes, sem rede |
| `go test -race` | ❌ nem compilava | ✅ verde |
| Cobertura efetiva | ~0% (nada rodava) | ver tabela abaixo |
| CI | inexistente | ✅ 3 jobs |
| Versões | 3 valores divergentes | ✅ sincronizadas |
| Strings de evento | 21 literais espalhados | ✅ contrato único, verificado nos 2 lados |

## Cobertura

`./scripts/coverage.sh` — o **piso** trava o nível conquistado (falha se cair); a
**meta** é o alvo da fase 2.

| Módulo | Atual | Piso | Meta |
|---|---|---|---|
| `drawly_core` | 60,3% | 60% | 90% |
| `drawing_board` | 68,1% | 60% | 90% |
| `drawly_design_system` | 42,3% | 40% | 60% |
| app | 36,2% | 35% | 85% |
| `backend-go` | 51,1% | 50% | 80% |

O que falta para chegar às metas:

- **`drawly_core`** — o `SocketManager` é ~60% do package e precisa de um duplo do
  `socket_io_client` para ser exercitado. Naturalmente coberto quando a fase 3 mover os
  consumidores para injeção por construtor.
- **`drawing_board`** — `canvas_side_bar.dart` (552 linhas de UI) ainda sem teste.
- **app** — as páginas grandes só saem do zero quando virarem controllers testáveis (3.2).
- **`backend-go`** — os handlers só ficam plenamente testáveis com o `Broadcaster` (4.3).

## Bugs corrigidos com teste que falhava antes

| Achado | O que era | Como apareceu |
|---|---|---|
| R5 | data race no estado do jogo | `go test -race` no caminho de reconexão |
| R6 | `Timer.periodic` do canvas nunca cancelado | `flutter_test`: *"A Timer is still pending…"* |
| R8 | `emitWithAck` segurava um timer por 10s mesmo em sucesso | reescrita do `SocketManager` |
| R14 | `bucketFill` parava antes de preencher tudo | teste que já existia e nunca havia rodado |
| R13 | balde com fresta/vazamento na borda e render que travava | raster amostrado no centro da célula + golden `bucket_fill_circle` |

## Bugs conhecidos e ainda abertos

Cada um tem teste que o demonstra, marcado com `skip:` apontando para
[01-achados.md](01-achados.md). São dívida **rastreada**, não esquecida.

| Achado | O que é | Fase |
|---|---|---|
| R2 | rank de acerto derivado de iteração de map (Go) | 4.1 |
| R3 | panic quando a sala fica sem desenhista | 4.1 |
| R4 | type assertions sem `ok` derrubam handlers | 4.1 |
| R7 | listeners e notifiers vazados no app | 3.1 |
| R9 | o desenhista não vê o próprio traço | 3.1 |
| R10 | `chooseRandomWord` não é aleatório e tem 1 palavra | 4.1 |
| R11/R12 | cliente cria sala; UI de debug em release | 3.1 |
| A7 | `copyWith(icon: null)` não limpa o campo | 3.3 |

## Costuras criadas (fase 1)

| Costura | Onde | Destrava |
|---|---|---|
| `RealtimeGateway` | `drawly_core/src/realtime/` | testar qualquer widget sem rede |
| `SocketManager.setInstanceForTesting` | instância lazy e substituível | injetar o fake antes do primeiro acesso |
| `FakeRealtimeGateway` | `package:drawly_core/testing.dart` | simular servidor e inspecionar emissões |
| `RealtimeSubscriptions` | `drawly_core/src/realtime/` | um `dispose` fecha todos os listeners |
| `SocketEvents` + `contracts.go` | contrato nos dois lados | teste que compara as duas listas |
| `AppConfig` | `drawly_core/src/config/` | dev/staging/prod por `--dart-define` |
| `stateMu` / `withState` | `backend-go/src/state_lock.go` | estado do jogo sem corrida |
| `disconnectGraceDelay`, `afterFunc` | `backend-go/src/` | testar tempo sem dormir |

## Ferramentas

```bash
./scripts/analyze.sh          # format + analyze + vet + invariantes de arquitetura
./scripts/test.sh             # 4 módulos Dart + Go com -race
./scripts/coverage.sh         # cobertura por módulo, com piso
./scripts/check_architecture.sh   # invariantes por grep (também roda no analyze)
./scripts/set_version.sh --check  # versões sincronizadas nos 5 pontos
./scripts/install_hooks.sh    # hook que valida a mensagem de commit
```

`check_architecture.sh` separa **regras ativas** (bloqueiam) de **regras pendentes**
(informativas até a fase correspondente concluir). À medida que a refatoração avança,
regras migram de pendente para ativa — é assim que o progresso fica verificável em vez
de declarado.

## Próximo passo

Fase 2, seção 2.5: subir o backend Go para 80% cobrindo `handleJoinRoom`,
`handleGuessAnswerChat` e `startTurnTimer`. São os três que concentram a regra de jogo e
os três que a fase 4 vai reestruturar — cobri-los primeiro é o que torna a fase 4 segura.
