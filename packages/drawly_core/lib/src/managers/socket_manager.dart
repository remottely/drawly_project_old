import 'dart:async';
import 'dart:developer' as developer;

import 'package:drawly_core/src/config/app_config.dart';
import 'package:drawly_core/src/contracts/socket_events.dart';
import 'package:drawly_core/src/realtime/realtime_gateway.dart';
import 'package:meta/meta.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io_client;

/// Implementação de [RealtimeGateway] sobre `socket_io_client`.
///
/// A instância é **lazy** e substituível: enquanto ninguém acessar
/// [SocketManager.instance], nenhum socket é aberto. É isso que permite a um
/// teste injetar um fake antes do primeiro acesso e nunca tocar a rede.
class SocketManager implements RealtimeGateway {
  SocketManager._internal() {
    _initializeSocket();
  }

  static RealtimeGateway? _instance;

  /// Gateway em uso pelo app.
  ///
  /// Construído sob demanda no primeiro acesso, ou substituído por
  /// [setInstanceForTesting].
  static RealtimeGateway get instance =>
      _instance ??= SocketManager._internal();

  /// Substitui o gateway global. Apenas para teste.
  @visibleForTesting
  // ignore: use_setters_to_change_properties
  static void setInstanceForTesting(RealtimeGateway gateway) {
    _instance = gateway;
  }

  /// Restaura o gateway global ao estado não inicializado. Apenas para teste.
  @visibleForTesting
  static void resetInstanceForTesting() {
    _instance = null;
  }

  late final socket_io_client.Socket _socket;
  final Map<String, List<RealtimeListener>> _eventListeners = {};

  @override
  bool get isConnected => _socket.connected;

  void _initializeSocket() {
    _socket = socket_io_client.io(
      AppConfig.realtimeUrl,
      socket_io_client.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setExtraHeaders({'Authorization': 'Bearer token'})
          .build(),
    );

    _socket.io.options?['reconnectionAttempts'] =
        AppConfig.reconnectionAttempts;
    _socket.io.options?['reconnectionDelay'] =
        AppConfig.reconnectionDelay.inMilliseconds;
    _socket.io.options?['reconnectionDelayMax'] =
        AppConfig.reconnectionDelayMax.inMilliseconds;

    on(SocketEvents.connect, (_) => developer.log('Connected to server'));
    on(
      SocketEvents.disconnect,
      (_) => developer.log('Disconnected from server'),
    );

    connect();
  }

  @override
  void connect() {
    if (!_socket.connected) {
      _socket.connect();
    }
  }

  @override
  void disconnect() {
    if (_socket.connected) {
      _socket.disconnect();
    }
  }

  @override
  void on(String event, RealtimeListener listener) {
    final listeners = _eventListeners.putIfAbsent(event, () => [])
      ..add(listener);

    // Registra no socket apenas uma vez por evento; o fan-out é nosso, para que
    // [off] possa remover um listener específico sem derrubar os demais.
    if (listeners.length == 1) {
      _socket.on(event, (data) {
        // Cópia defensiva: um listener pode se remover durante o despacho.
        for (final listener in List<RealtimeListener>.from(
          _eventListeners[event] ?? const [],
        )) {
          listener(data);
        }
      });
    }
  }

  @override
  void off(String event, RealtimeListener listener) {
    final listeners = _eventListeners[event];
    if (listeners == null) return;

    listeners.remove(listener);

    if (listeners.isEmpty) {
      _eventListeners.remove(event);
      _socket.off(event);
    }
  }

  @override
  void emit(String event, Map<String, dynamic> payload) {
    _socket.emit(event, payload);
  }

  @override
  Future<Map<String, dynamic>> emitWithAck(
    String event,
    Map<String, dynamic> payload, {
    Duration timeout = AppConfig.ackTimeout,
  }) {
    final completer = Completer<Map<String, dynamic>>();

    // Guardado para ser cancelado no ack: sem isso, cada chamada segura um
    // timer vivo até o fim do timeout mesmo em caso de sucesso.
    late final Timer timeoutTimer;

    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(RealtimeTimeoutException(event, timeout));
      }
    });

    _socket.emitWithAck(
      event,
      payload,
      ack: (dynamic response) {
        timeoutTimer.cancel();
        if (completer.isCompleted) return;

        if (response is Map<String, dynamic>) {
          completer.complete(response);
        } else {
          completer.completeError(RealtimeProtocolException(event, response));
        }
      },
    );

    return completer.future;
  }

  @override
  Future<void> dispose() async {
    for (final event in _eventListeners.keys) {
      _socket.off(event);
    }
    _eventListeners.clear();
    _socket.dispose();
  }
}
