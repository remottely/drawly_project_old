# Fase 1 — Seams de testabilidade

**Status: ✅ concluída**

Objetivo: introduzir o **mínimo** de costuras necessárias para que a fase 2 consiga
cobrir o código existente. Nada aqui muda comportamento de produção.

> Por que seams vêm antes dos testes, se a regra é "teste antes de refatorar"?
> Porque código que abre socket no construtor de um singleton **não é testável**.
> Sem a costura não existe teste para proteger nada. É a exceção clássica de Feathers:
> a menor mudança possível que torna o código testável, feita com muito cuidado.
> Cada seam abaixo é *aditivo* — nenhum call site existente muda de comportamento.

---

## S1 · `RealtimeGateway` (Dart) — a costura principal

**Problema:** `SocketManager.instance` é `static final`, e o construtor privado já chama
`socket_io_client.io('http://localhost:5555')` + `connect()`. Qualquer teste que monte
`DrawingCanvas`, `AllParticipants`, `AnswersChatView`… abre socket real.

**Solução (3 partes, aditiva):**

1. Interface em `drawly_core/lib/src/realtime/realtime_gateway.dart`:
   ```dart
   typedef RealtimeListener = void Function(dynamic data);

   abstract interface class RealtimeGateway {
     bool get isConnected;
     void connect();
     void disconnect();
     void on(String event, RealtimeListener listener);
     void off(String event, RealtimeListener listener);
     void emit(String event, Map<String, dynamic> payload);
     Future<Map<String, dynamic>> emitWithAck(
       String event,
       Map<String, dynamic> payload, {
       Duration timeout,
     });
     Future<void> dispose();
   }
   ```

2. `SocketManager implements RealtimeGateway`, mantendo os nomes atuais
   (`onEvent`/`offEvent`) como *aliases* de `on`/`off` para não quebrar os 8 call sites.
   A instância passa a ser **lazy e substituível**:
   ```dart
   static RealtimeGateway? _instance;
   static RealtimeGateway get instance => _instance ??= SocketManager._internal();

   @visibleForTesting
   static set instance(RealtimeGateway gateway) => _instance = gateway;
   @visibleForTesting
   static void resetInstance() { _instance = null; }
   ```
   Lazy é o detalhe que importa: se o teste injeta o fake antes do primeiro acesso,
   o socket real **nunca é construído**.

3. `FakeRealtimeGateway` publicado em um entrypoint separado
   (`package:drawly_core/testing.dart`), fora do barrel principal — logo, removido por
   tree-shaking do app. Em memória, síncrono, determinístico:
   registra emissões, permite `emitServerEvent(...)` e programar respostas de ack.

**Ganho imediato:** todo widget e todo ViewModel do projeto vira testável sem rede.

**Não faz parte desta fase:** trocar os call sites por injeção via construtor.
Isso é a fase 3 — aqui só abrimos a porta.

---

## S2 · `SocketEvents` — contrato único de eventos

21 strings literais duplicadas entre Dart e Go (achado A4). Passam a viver em
`drawly_core/lib/src/contracts/socket_events.dart` e em `backend-go/src/contracts.go`,
com um teste de contrato garantindo que as duas listas coincidem.

Aditivo: as constantes são introduzidas e os call sites migram gradualmente. Nenhum
valor de string muda — logo, zero risco de protocolo.

---

## S3 · `AppConfig` — fim do host hardcoded

`http://localhost:5555` sai do construtor do `SocketManager` e vira:

```dart
abstract final class AppConfig {
  static const realtimeUrl = String.fromEnvironment(
    'DRAWLY_REALTIME_URL',
    defaultValue: 'http://localhost:5555',
  );
}
```

Default idêntico ao valor atual → comportamento inalterado em dev; e agora existe
staging/prod via `--dart-define`.

---

## S4 · Costuras no Go

Já parcialmente feito na fase 0:

- `disconnectParticipant(io, clientID string)` extraído de `handleParticipantDisconnect`
  — permite exercitar a lógica sem construir `*socket.Socket` (o campo `id` é privado
  na lib).
- `disconnectGraceDelay` virou variável de pacote — testes encurtam a tolerância em vez
  de dormir 6 segundos.

Falta nesta fase:

- `startTurnTimer` recebe a duração já como `time.Duration` e o agendamento passa por uma
  função de pacote substituível (`afterFunc = time.AfterFunc`), para o teste controlar o
  tempo sem `sleep`.
- Extrair de cada `handleXxx` um núcleo puro que recebe dados já validados e devolve o
  efeito desejado, deixando o handler como casca de parsing. Isso prepara o `Broadcaster`
  da fase 4 sem ainda introduzir a interface.

---

## S5 · Suporte de teste compartilhado

`test/support/` em cada package, com o mínimo:

| Arquivo | Conteúdo |
|---|---|
| `fake_realtime_gateway.dart` | reexport do fake de `drawly_core/testing.dart` |
| `stroke_fixtures.dart` | construtores de `Stroke` determinísticos por tipo |
| `payload_fixtures.dart` | mapas JSON válidos de cada evento, fonte única |

Regra: fixture nunca é copiada entre arquivos de teste (DRY vale para teste também).

---

## Critério de saída da fase 1

- [x] `RealtimeGateway` existe e `SocketManager` o implementa
- [x] `SocketManager.instance` é substituível e **lazy**
- [x] `FakeRealtimeGateway` disponível via `package:drawly_core/testing.dart`
- [x] `SocketEvents` declarado nos dois lados + teste de contrato
- [x] `AppConfig.realtimeUrl` em uso
- [x] Costuras de tempo no Go (`afterFunc`, `disconnectGraceDelay`)
- [x] Um teste-prova por costura, demonstrando que a costura funciona
- [x] Nenhuma mudança de comportamento observável

## O que a fase revelou

Duas coisas que só apareceram porque as costuras tornaram o código executável:

1. **A corrida do servidor era real e alcançável** (R5). O `-race` a reproduziu no
   caminho de reconexão. Corrigida aqui, fora do plano original — um gate de corrida
   permanentemente vermelho não é gate.
2. **Nenhum teste de widget do canvas podia passar** enquanto o `Timer.periodic` do
   buffer vazasse (R6): o `flutter_test` falha explicitamente com timer pendente.
   Corrigido.

Ambos tinham teste que falhava antes da correção.

## Além do planejado

- Os 21 literais de evento migraram para `SocketEvents` / `contracts.go` **nesta fase**,
  não gradualmente. O ganho de segurança justificou: nenhum valor de string mudou, e o
  teste de contrato passou a impedir divergência entre os dois lados.
- `emitWithAck` ganhou o cancelamento do timer de timeout (R8), que estava na fase 3 —
  era uma linha na mesma função que já estava sendo reescrita.
