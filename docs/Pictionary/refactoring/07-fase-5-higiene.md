# Fase 5 — Higiene contínua

**Status: ⏳**

Sem automação, tudo o que as fases 0–4 conquistaram volta a apodrecer. Esta fase é o que
mantém o resultado.

---

## 5.1 · Scripts

Três scripts, sem ferramenta de monorepo (YAGNI para 3 packages):

| Script | Faz |
|---|---|
| `scripts/analyze.sh` | `dart format --set-exit-if-changed`, `flutter analyze` nos 4 módulos Dart, `gofmt -l`, `go vet` |
| `scripts/test.sh` | `flutter test` nos 4 módulos + `go test -race ./src/...` |
| `scripts/coverage.sh` | cobertura por módulo, merge dos `lcov.info`, relatório HTML, checagem do piso |

Saem com código ≠ 0 na primeira falha. São o gate local e o gate do CI — o mesmo comando,
para não existir "passa na minha máquina".

---

## 5.2 · CI

GitHub Actions, um workflow, dois jobs paralelos (`dart`, `go`), em push e PR:

```
analyze → test → coverage (falha se cair abaixo do piso)
```

Regras: sem `continue-on-error`, sem teste marcado como flaky tolerado. Teste instável é
bug de teste e entra na fila como qualquer outro.

---

## 5.3 · Sincronizar versões (achado H1) — ✅ concluído

Divergiam: raiz `0.53.5+4`, os 3 packages e o Go em `0.51.5`.

`scripts/set_version.sh <versão>` escreve nos 5 lugares de uma vez, e `--check` falha se
algum divergir. Versão divergente deixou de ser possível por descuido.

---

## 5.4 · Hook de commit

Hook local validando a mensagem contra o formato do [CLAUDE.md](../../../CLAUDE.md) §9:

```
^\d+\.\d+\.\d+(\+\d+)?; (feat|fix|refactor|test|perf|docs|style|build|ci|chore): .{1,60}$
```

E validando que a versão da mensagem bate com a do `pubspec.yaml` raiz.

---

## 5.5 · Documentação

- `README.md` (hoje 8 linhas descrevendo um backend Node que não existe mais): reescrever
  com arquitetura, como rodar app + servidor, como rodar testes.
- `docs/Pictionary/Untitled.md` (2078 linhas, sem título): triar — o que for decisão de
  produto vira documento nomeado, o resto sai.
- Um ADR curto por decisão estrutural, em `docs/Pictionary/adr/`. Candidatos imediatos:
  echo otimista vs. servidor-autoritativo (R9), manter ou remover os forks Go (A10),
  `ChangeNotifier` em vez de bloc/riverpod.

---

## 5.6 · Recorrente

| Cadência | Ação |
|---|---|
| a cada PR | `analyze.sh` + `test.sh` + cobertura não cai |
| mensal | `flutter pub outdated` / `go list -u -m all` e atualizar o que for seguro |
| a cada release | versões sincronizadas, CHANGELOG atualizado |
| trimestral | reavaliar forks em `external/`, revisar achados P2 ainda abertos |

---

## Critério de saída

- [ ] 3 scripts funcionando local e no CI
- [ ] CI verde e obrigatório no merge
- [ ] versões sincronizadas e validadas automaticamente
- [ ] hook de commit ativo
- [ ] README reescrito
- [ ] ADRs das 3 decisões estruturais
