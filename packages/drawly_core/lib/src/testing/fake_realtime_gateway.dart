import 'dart:async';

import 'package:drawly_core/src/realtime/realtime_gateway.dart';
import 'package:meta/meta.dart';

/// Um evento emitido pelo cliente, capturado pelo fake.
@immutable
final class EmittedEvent {
  const EmittedEvent(this.event, this.payload);

  final String event;
  final Map<String, dynamic> payload;

  @override
  String toString() => 'EmittedEvent($event, $payload)';

  @override
  bool operator ==(Object other) =>
      other is EmittedEvent &&
      other.event == event &&
      _mapEquals(other.payload, payload);

  @override
  int get hashCode => Object.hash(event, payload.length);

  static bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}

/// [RealtimeGateway] em memória para testes.
///
/// Determinístico e síncrono: não abre socket, não usa relógio real e entrega
/// eventos imediatamente. Toda emissão do código sob teste fica registrada em
/// [emitted], e o teste simula o servidor com [emitServerEvent].
///
/// ```dart
/// final gateway = FakeRealtimeGateway();
/// SocketManager.setInstanceForTesting(gateway);
/// addTearDown(SocketManager.resetInstanceForTesting);
///
/// gateway.emitServerEvent(SocketEvents.chatMessage, {'text': 'oi'});
/// expect(gateway.emittedOn(SocketEvents.roomJoin), hasLength(1));
/// ```
final class FakeRealtimeGateway implements RealtimeGateway {
  /// Se `true`, [emitWithAck] falha com [RealtimeTimeoutException] quando não
  /// há resposta programada. Se `false` (default), o Future fica pendente —
  /// útil para testar estados de carregamento.
  FakeRealtimeGateway({this.timeoutWhenUnanswered = true});

  final bool timeoutWhenUnanswered;

  final Map<String, List<RealtimeListener>> _listeners = {};
  final List<EmittedEvent> _emitted = [];
  final Map<String, Object> _ackResponses = {};

  bool _connected = true;
  bool _disposed = false;

  // ── inspeção ───────────────────────────────────────────────────────────────

  /// Tudo que o código sob teste emitiu, na ordem.
  List<EmittedEvent> get emitted => List.unmodifiable(_emitted);

  /// As emissões de um evento específico.
  List<Map<String, dynamic>> emittedOn(String event) => _emitted
      .where((emission) => emission.event == event)
      .map((emission) => emission.payload)
      .toList();

  /// A última emissão de [event], ou `null` se não houve nenhuma.
  Map<String, dynamic>? lastEmittedOn(String event) {
    final matches = emittedOn(event);
    return matches.isEmpty ? null : matches.last;
  }

  /// Quantos listeners estão registrados para [event].
  ///
  /// Serve para provar que um `dispose()` removeu o que registrou.
  int listenerCount(String event) => _listeners[event]?.length ?? 0;

  /// Total de listeners registrados em todos os eventos.
  int get totalListenerCount =>
      _listeners.values.fold(0, (total, list) => total + list.length);

  /// Se [dispose] já foi chamado.
  bool get isDisposed => _disposed;

  /// Descarta o histórico de emissões, preservando os listeners.
  void clearEmitted() => _emitted.clear();

  // ── simulação do servidor ──────────────────────────────────────────────────

  /// Entrega [data] aos listeners de [event], como se viesse do servidor.
  void emitServerEvent(String event, dynamic data) {
    // Cópia defensiva: um listener pode se desinscrever durante o despacho.
    for (final listener in List<RealtimeListener>.from(
      _listeners[event] ?? const [],
    )) {
      listener(data);
    }
  }

  /// Programa a resposta de um [emitWithAck] em [event].
  ///
  /// Pode ser um `Map<String, dynamic>` (sucesso) ou um [Exception] (falha).
  void stubAck(String event, Object response) {
    _ackResponses[event] = response;
  }

  /// Simula queda de conexão, disparando o evento `disconnect`.
  void simulateDisconnect() {
    _connected = false;
    emitServerEvent('disconnect', null);
  }

  /// Simula reconexão, disparando o evento `connect`.
  void simulateConnect() {
    _connected = true;
    emitServerEvent('connect', null);
  }

  // ── RealtimeGateway ────────────────────────────────────────────────────────

  @override
  bool get isConnected => _connected;

  @override
  void connect() => _connected = true;

  @override
  void disconnect() => _connected = false;

  @override
  void on(String event, RealtimeListener listener) {
    _listeners.putIfAbsent(event, () => []).add(listener);
  }

  @override
  void off(String event, RealtimeListener listener) {
    final listeners = _listeners[event];
    if (listeners == null) return;

    listeners.remove(listener);
    if (listeners.isEmpty) _listeners.remove(event);
  }

  @override
  void emit(String event, Map<String, dynamic> payload) {
    _emitted.add(EmittedEvent(event, payload));
  }

  @override
  Future<Map<String, dynamic>> emitWithAck(
    String event,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    _emitted.add(EmittedEvent(event, payload));

    final response = _ackResponses[event];

    if (response is Map<String, dynamic>) {
      return Future.value(response);
    }
    if (response is Exception) {
      return Future.error(response);
    }
    if (timeoutWhenUnanswered) {
      return Future.error(RealtimeTimeoutException(event, timeout));
    }
    return Completer<Map<String, dynamic>>().future;
  }

  @override
  Future<void> dispose() async {
    _listeners.clear();
    _disposed = true;
  }
}
