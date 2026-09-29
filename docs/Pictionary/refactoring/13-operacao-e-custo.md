# 13 — Operação e custo

> Quarto doc da série. O doc 10 reduz bytes e pacotes; este transforma isso em conta de
> hospedagem previsível. Pressupõe G0 do doc 10 (lib socket.io real) e E3 do doc 11 (números).

---

## 1. Situação

| | Hoje |
|---|---|
| Artefato de deploy | nenhum: sem Dockerfile, sem Procfile, sem manifesto |
| Configuração | porta `:5555`, CORS com 8 `localhost`, `log.DEBUG = true`, durações — tudo hardcoded (H3) |
| Erro de `ListenAndServe` | ignorado (H4) |
| Shutdown | fecha o socket.io e sai; salas em andamento morrem sem aviso |
| Health check | não existe |
| Escala | processo único, estado em memória; nada impede subir dois, mas nada faz funcionar |
| CI | 3 jobs Dart/Go, sem build de imagem, sem deploy |

Nada disso é complexo. O risco é fazer na pressa e sem número.

---

## 2. Princípios

1. **Um binário, uma imagem, uma variável por decisão.** Tudo que varia entre dev/staging/prod
   é env var com default igual ao dev (CLAUDE.md §7).
2. **Estado é efêmero por design.** Partida cabe em memória e morre com o processo. Isso é
   uma *feature* de custo: zero banco, zero backup, zero migração. Persistir só o que o
   E5 (replay/denúncia) pedir, e em arquivo.
3. **Uma instância até o número dizer o contrário.** Socket.io exige *sticky session* para
   escalar horizontalmente; com estado em memória exige ainda que a sala viva numa instância
   só. Isso se resolve com roteamento por sala, não com Redis — e só quando uma instância
   não bastar.
4. **Capacidade calculada, não chutada.** O E3 dá ops/s, bytes/s e alocação por sala; daqui
   sai "N salas por vCPU" e o tamanho da máquina.

---

## 3. Etapas

### O1 · Configuração e ciclo de vida do processo

| Env var | Default | Uso |
|---|---|---|
| `DRAWLY_ADDR` | `:5555` | bind |
| `DRAWLY_CORS_ORIGINS` | `http://localhost:8081,…` | lista separada por vírgula |
| `DRAWLY_LOG_LEVEL` | `info` | `debug` liga o `log.DEBUG` do engine.io |
| `DRAWLY_TURN_SECONDS`, `DRAWLY_CHOOSE_SECONDS`, `DRAWLY_REVEAL_SECONDS`, `DRAWLY_ROUNDS`, `DRAWLY_HINT_SECONDS` | 60, 10, 5, 3, 20 | doc 12 |
| `DRAWLY_DISCONNECT_GRACE_SECONDS` | 5 | tolerância de reconexão |
| `DRAWLY_MAX_PLAYERS` | 8 | por sala |
| `DRAWLY_MAX_ROOMS` | 200 | recusa `room:create` acima disso: é o *circuit breaker* de custo |
| `DRAWLY_EXPVAR` | `false` | `/debug/vars` (doc 11, E3.3) |
| `DRAWLY_DEFLATE` | `false` | doc 11, E4.3 |

`internal/config` lê tudo uma vez, com validação (porta inválida, origem sem esquema →
falha na subida, não em runtime). `ListenAndServe` em goroutine com o erro num canal;
`main` sai com código ≠ 0 se a porta falhar (H4). Shutdown: `SIGTERM` → para de aceitar
`room:create` e `room:join` → emite `error {action: dialog}` "servidor reiniciando" para as
salas → espera até `DRAWLY_DRAIN_SECONDS` (30) ou até a última sala acabar → fecha.

`GET /healthz` (200 + `{rooms, uptime}`) e `GET /readyz` (503 durante o drain).

| Commit |
|---|
| `feat: load server configuration from environment variables with validation` |
| `fix: fail fast when the listener cannot bind` |
| `feat: drain rooms gracefully on shutdown and expose health endpoints` |

### O2 · Imagem e pipeline

- `Dockerfile` multi-stage: `golang:1.23` build com `CGO_ENABLED=0 -ldflags="-s -w"` →
  `gcr.io/distroless/static`. Imagem ≈ 10 MB, sem shell.
- Versão da imagem = `Version` do Go = versão do produto (CLAUDE.md §8); `set_version.sh`
  passa a escrever também a tag no workflow.
- CI: job `image` que builda e faz `docker run` + `curl /healthz` como smoke; publica no GHCR
  só em tag. Deploy é `git tag` → imagem → plataforma puxa.
- Plataforma: qualquer uma que rode um contêiner com WebSocket e sem *sleep* por
  inatividade — Fly.io, Railway ou uma VPS pequena. Critério de escolha: **preço por
  instância sempre ligada**, não *free tier* que dorme (a sala morre com o processo).
- Front (Flutter web): estático em CDN gratuito (Firebase Hosting já está no projeto), com
  `--dart-define=DRAWLY_REALTIME_URL` apontando para o backend.

| Commit |
|---|
| `build: add a distroless multi-stage image for the go server` |
| `ci: build the server image and smoke test its health endpoint` |
| `ci: publish the image on version tags` |

### O3 · Capacidade e orçamento

Com os benchmarks do E3 e o protocolo do doc 10, a conta por sala (4 jogadores, 60 s de
desenho contínuo):

| Grandeza | Estimativa | Origem |
|---|---|---|
| pacotes ↑ por sala | 20/s | flush de 50 ms |
| pacotes ↓ por sala | 60/s | 3 viewers |
| bytes ↓ por sala | ≈ 5 KB/s | 88 B × 60 |
| memória por sala | < 200 KB | 4000 pts × 1000 strokes × 8 B é o teto teórico; real ≈ 30 KB |
| CPU por sala | a medir (E3.2) | alvo: < 1 % de um vCPU |

Meta: **≥ 100 salas por vCPU / 512 MB**. Se o E3 mostrar menos, o gargalo é CPU de encode
(E4.3 desliga) ou lock global (E4.5). O `DRAWLY_MAX_ROOMS` é ajustado ao número medido, e o
`expvar` diz quando chegou perto.

Custo mensal alvo do MVP: **uma instância pequena sempre ligada + CDN grátis**. Sem banco,
sem Redis, sem fila. Cada serviço a mais entra com um gate escrito, como no E4.

### O4 · Mais de uma instância (gate: `rooms_active` > 80 % do máximo por > 1 h/dia)

Não é Redis. É **afinidade por sala**:

1. Um serviço de *lobby* (pode ser o mesmo binário em modo `lobby`) responde `room:create`/`room:join` com o `url` da instância dona da sala.
2. O cliente conecta o socket direto na instância indicada; o `AppConfig.realtimeUrl` passa a ser o lobby, e o gateway ganha `connectTo(url)`.
3. Instâncias se registram no lobby com `rooms_active`; a sala nova vai para a menos cheia.

Sem estado compartilhado, sem adapter, sem sticky session no balanceador. É mais simples e
mais barato que socket.io + Redis, e é o que o modelo "sala vive numa instância" já implica.
Só começa quando o gate disparar.

### O5 · Observação em produção

- Logs estruturados (`log/slog`, stdlib) em JSON, com `room`, `turn`, `userId` como campos.
  Nível por env. Nada de `fmt.Printf`.
- Um único alerta no começo: `/readyz` fora do ar por > 1 min.
- `expvar` ligado em produção atrás de rede interna, desligado por default.

| Commit |
|---|
| `refactor: replace ad-hoc logging with structured slog fields` |

---

## 4. Critério de saída

- `docker run` da imagem sobe, responde `/healthz`, aceita um join e derruba com `SIGTERM` sem deixar goroutine (teste com `-race` e `goleak`-style manual).
- Nenhuma constante de rede, tempo ou limite fora de `internal/config`.
- Versão da imagem, do Go, do app e dos packages iguais (`set_version.sh --check`).
- Número de salas por vCPU registrado no `09-estado-atual.md`, com a data e o commit do benchmark.
