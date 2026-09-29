import 'package:drawly_core/drawly_core.dart';
import 'package:drawly_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeRealtimeGateway gateway;
  late RealtimeSubscriptions subscriptions;

  setUp(() {
    gateway = FakeRealtimeGateway();
    subscriptions = RealtimeSubscriptions(gateway);
  });

  group('RealtimeSubscriptions', () {
    test('registra o listener no gateway', () {
      subscriptions.on(SocketEvents.chatMessage, (_) {});

      expect(gateway.listenerCount(SocketEvents.chatMessage), 1);
      expect(subscriptions.length, 1);
    });

    test('entrega os eventos do servidor ao listener registrado', () {
      final received = <dynamic>[];
      subscriptions.on(SocketEvents.chatMessage, received.add);

      gateway.emitServerEvent(SocketEvents.chatMessage, {'text': 'oi'});

      expect(received, [
        {'text': 'oi'},
      ]);
    });

    test('dispose remove todas as inscrições de uma vez', () {
      subscriptions
        ..on(SocketEvents.chatMessage, (_) {})
        ..on(SocketEvents.gameTurnNew, (_) {})
        ..on(SocketEvents.roomParticipantsUpdate, (_) {});

      expect(gateway.totalListenerCount, 3);

      subscriptions.dispose();

      expect(
        gateway.totalListenerCount,
        0,
        reason: 'este é exatamente o vazamento que o padrão manual causava',
      );
      expect(subscriptions.length, 0);
    });

    test('dispose é idempotente', () {
      subscriptions.on(SocketEvents.chatMessage, (_) {});

      subscriptions
        ..dispose()
        ..dispose();

      expect(gateway.totalListenerCount, 0);
    });

    test('dispose só remove o que este escopo registrou', () {
      void outsider(dynamic _) {}
      gateway.on(SocketEvents.chatMessage, outsider);

      subscriptions
        ..on(SocketEvents.chatMessage, (_) {})
        ..dispose();

      expect(
        gateway.listenerCount(SocketEvents.chatMessage),
        1,
        reason: 'o listener de outro escopo deve sobreviver',
      );
    });

    test('vários listeners no mesmo evento são todos chamados', () {
      final chamadas = <String>[];
      subscriptions
        ..on(SocketEvents.gameTurnNew, (_) => chamadas.add('primeiro'))
        ..on(SocketEvents.gameTurnNew, (_) => chamadas.add('segundo'));

      gateway.emitServerEvent(SocketEvents.gameTurnNew, null);

      expect(chamadas, ['primeiro', 'segundo']);
    });

    test('off remove uma inscrição específica antes do dispose', () {
      final recebidos = <String>[];
      void manter(dynamic _) => recebidos.add('manter');
      void remover(dynamic _) => recebidos.add('remover');

      subscriptions
        ..on(SocketEvents.gameTurnNew, manter)
        ..on(SocketEvents.gameTurnNew, remover)
        ..off(SocketEvents.gameTurnNew, remover);

      gateway.emitServerEvent(SocketEvents.gameTurnNew, null);

      expect(recebidos, ['manter']);
      expect(subscriptions.length, 1);
    });

    test('dispose após off não tenta remover a inscrição já removida', () {
      void listener(dynamic _) {}

      subscriptions
        ..on(SocketEvents.gameTurnNew, listener)
        ..off(SocketEvents.gameTurnNew, listener)
        ..dispose();

      expect(gateway.totalListenerCount, 0);
    });
  });
}
