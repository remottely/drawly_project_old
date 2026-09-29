import 'package:drawly_core/drawly_core.dart';
import 'package:drawly_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// O fake é infraestrutura de teste usada por todo o projeto: se ele estiver
/// errado, todos os testes que dependem dele mentem. Por isso ele também é
/// testado.
void main() {
  late FakeRealtimeGateway gateway;

  setUp(() => gateway = FakeRealtimeGateway());

  group('captura de emissões', () {
    test('registra o que foi emitido, na ordem', () {
      gateway
        ..emit(SocketEvents.roomCreate, {'roomName': 'a'})
        ..emit(SocketEvents.chatMessage, {'text': 'oi'});

      expect(gateway.emitted, hasLength(2));
      expect(gateway.emitted.first.event, SocketEvents.roomCreate);
      expect(gateway.emitted.last.event, SocketEvents.chatMessage);
    });

    test('emittedOn filtra por evento', () {
      gateway
        ..emit(SocketEvents.chatMessage, {'text': 'um'})
        ..emit(SocketEvents.roomCreate, {'roomName': 'a'})
        ..emit(SocketEvents.chatMessage, {'text': 'dois'});

      expect(gateway.emittedOn(SocketEvents.chatMessage), [
        {'text': 'um'},
        {'text': 'dois'},
      ]);
    });

    test('lastEmittedOn devolve a emissão mais recente', () {
      gateway
        ..emit(SocketEvents.chatMessage, {'text': 'antiga'})
        ..emit(SocketEvents.chatMessage, {'text': 'nova'});

      expect(gateway.lastEmittedOn(SocketEvents.chatMessage), {'text': 'nova'});
    });

    test('lastEmittedOn devolve null quando nada foi emitido', () {
      expect(gateway.lastEmittedOn(SocketEvents.chatMessage), isNull);
    });

    test('clearEmitted descarta o histórico e preserva os listeners', () {
      gateway
        ..on(SocketEvents.chatMessage, (_) {})
        ..emit(SocketEvents.chatMessage, {'text': 'oi'})
        ..clearEmitted();

      expect(gateway.emitted, isEmpty);
      expect(gateway.listenerCount(SocketEvents.chatMessage), 1);
    });
  });

  group('listeners', () {
    test('entrega o evento a todos os listeners registrados', () {
      final recebidos = <String>[];
      gateway
        ..on(SocketEvents.gameTurnNew, (_) => recebidos.add('a'))
        ..on(SocketEvents.gameTurnNew, (_) => recebidos.add('b'))
        ..emitServerEvent(SocketEvents.gameTurnNew, null);

      expect(recebidos, ['a', 'b']);
    });

    test('off remove apenas o listener indicado', () {
      final recebidos = <String>[];
      void manter(dynamic _) => recebidos.add('manter');
      void remover(dynamic _) => recebidos.add('remover');

      gateway
        ..on(SocketEvents.gameTurnNew, manter)
        ..on(SocketEvents.gameTurnNew, remover)
        ..off(SocketEvents.gameTurnNew, remover)
        ..emitServerEvent(SocketEvents.gameTurnNew, null);

      expect(recebidos, ['manter']);
    });

    test('off de listener não registrado é no-op', () {
      expect(
        () => gateway.off(SocketEvents.gameTurnNew, (_) {}),
        returnsNormally,
      );
    });

    test('um listener pode se desinscrever durante o próprio despacho', () {
      // Sem cópia defensiva no despacho isto lançaria ConcurrentModificationError.
      final recebidos = <String>[];
      late void Function(dynamic) listener;
      listener = (_) {
        recebidos.add('chamado');
        gateway.off(SocketEvents.gameTurnNew, listener);
      };

      gateway
        ..on(SocketEvents.gameTurnNew, listener)
        ..emitServerEvent(SocketEvents.gameTurnNew, null)
        ..emitServerEvent(SocketEvents.gameTurnNew, null);

      expect(recebidos, ['chamado']);
    });

    test('evento sem listeners não quebra', () {
      expect(
        () => gateway.emitServerEvent(SocketEvents.gameTurnNew, null),
        returnsNormally,
      );
    });
  });

  group('emitWithAck', () {
    test('devolve a resposta programada', () async {
      gateway.stubAck(SocketEvents.roomJoin, {'success': true, 'turn': 3});

      final response = await gateway.emitWithAck(SocketEvents.roomJoin, {
        'roomName': 'sala',
      });

      expect(response, {'success': true, 'turn': 3});
    });

    test('registra a emissão mesmo aguardando ack', () async {
      gateway.stubAck(SocketEvents.roomJoin, {'success': true});

      await gateway.emitWithAck(SocketEvents.roomJoin, {'roomName': 'sala'});

      expect(gateway.emittedOn(SocketEvents.roomJoin), [
        {'roomName': 'sala'},
      ]);
    });

    test('propaga a exceção programada', () async {
      gateway.stubAck(SocketEvents.roomJoin, Exception('servidor fora'));

      expect(
        () => gateway.emitWithAck(SocketEvents.roomJoin, const {}),
        throwsException,
      );
    });

    test('sem resposta programada falha por timeout, por padrão', () async {
      expect(
        () => gateway.emitWithAck(SocketEvents.roomJoin, const {}),
        throwsA(isA<RealtimeTimeoutException>()),
      );
    });

    test('com timeoutWhenUnanswered false o future fica pendente', () async {
      final pendingGateway = FakeRealtimeGateway(
        timeoutWhenUnanswered: false,
      );

      var completou = false;
      unawaited(
        pendingGateway
            .emitWithAck(SocketEvents.roomJoin, const {})
            .then((_) => completou = true)
            .catchError((_) => completou = true),
      );

      await Future<void>.delayed(Duration.zero);

      expect(
        completou,
        isFalse,
        reason: 'útil para testar estado de carregamento',
      );
    });
  });

  group('conexão', () {
    test('começa conectado', () {
      expect(gateway.isConnected, isTrue);
    });

    test('simulateDisconnect derruba a conexão e avisa os listeners', () {
      var avisado = false;
      gateway
        ..on(SocketEvents.disconnect, (_) => avisado = true)
        ..simulateDisconnect();

      expect(gateway.isConnected, isFalse);
      expect(avisado, isTrue);
    });

    test('simulateConnect restabelece a conexão e avisa os listeners', () {
      var avisado = false;
      gateway
        ..simulateDisconnect()
        ..on(SocketEvents.connect, (_) => avisado = true)
        ..simulateConnect();

      expect(gateway.isConnected, isTrue);
      expect(avisado, isTrue);
    });

    test('connect e disconnect diretos mudam o estado sem emitir evento', () {
      var avisos = 0;
      gateway
        ..on(SocketEvents.disconnect, (_) => avisos++)
        ..disconnect();

      expect(gateway.isConnected, isFalse);
      expect(avisos, 0);

      gateway.connect();
      expect(gateway.isConnected, isTrue);
    });
  });

  group('dispose', () {
    test('limpa os listeners e marca como descartado', () async {
      gateway.on(SocketEvents.chatMessage, (_) {});

      await gateway.dispose();

      expect(gateway.totalListenerCount, 0);
      expect(gateway.isDisposed, isTrue);
    });
  });

  group('EmittedEvent', () {
    test('é igual quando evento e payload coincidem', () {
      expect(
        const EmittedEvent('e', {'a': 1}),
        equals(const EmittedEvent('e', {'a': 1})),
      );
    });

    test('difere quando o payload muda', () {
      expect(
        const EmittedEvent('e', {'a': 1}),
        isNot(equals(const EmittedEvent('e', {'a': 2}))),
      );
    });

    test('difere quando o evento muda', () {
      expect(
        const EmittedEvent('a', {'x': 1}),
        isNot(equals(const EmittedEvent('b', {'x': 1}))),
      );
    });
  });
}

/// Evita o lint de future não aguardado sem importar `dart:async` só por isso.
void unawaited(Future<void> future) {}
