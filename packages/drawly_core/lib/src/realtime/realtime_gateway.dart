/// Callback invocado quando um evento chega do servidor.
typedef RealtimeListener = void Function(dynamic data);

/// Contrato de transporte em tempo real.
///
/// Existe para inverter a dependência de I/O: quem consome fala com esta
/// interface, nunca com `socket_io_client`. Em produção o implementador é
/// `SocketManager`; em teste, `FakeRealtimeGateway`
/// (`package:drawly_core/testing.dart`).
abstract interface class RealtimeGateway {
  /// Se há uma conexão ativa com o servidor.
  bool get isConnected;

  /// Abre a conexão. Idempotente.
  void connect();

  /// Fecha a conexão. Idempotente.
  void disconnect();

  /// Registra [listener] para [event].
  ///
  /// Vários listeners podem observar o mesmo evento; todos são chamados na
  /// ordem de registro.
  void on(String event, RealtimeListener listener);

  /// Remove um [listener] específico de [event].
  ///
  /// Remover um listener não registrado é no-op.
  void off(String event, RealtimeListener listener);

  /// Envia [payload] ao servidor sem esperar resposta.
  void emit(String event, Map<String, dynamic> payload);

  /// Envia [payload] e aguarda o ack do servidor.
  ///
  /// Falha com [RealtimeTimeoutException] se o servidor não responder dentro de
  /// [timeout], e com [RealtimeProtocolException] se a resposta não for um
  /// `Map<String, dynamic>`.
  Future<Map<String, dynamic>> emitWithAck(
    String event,
    Map<String, dynamic> payload, {
    Duration timeout,
  });

  /// Remove todos os listeners e libera os recursos do transporte.
  Future<void> dispose();
}

/// O servidor não respondeu um [RealtimeGateway.emitWithAck] a tempo.
final class RealtimeTimeoutException implements Exception {
  const RealtimeTimeoutException(this.event, this.timeout);

  final String event;
  final Duration timeout;

  @override
  String toString() => 'RealtimeTimeoutException: sem resposta para "$event" '
      'em ${timeout.inMilliseconds}ms';
}

/// O servidor respondeu em um formato que não é o esperado.
final class RealtimeProtocolException implements Exception {
  const RealtimeProtocolException(this.event, this.received);

  final String event;
  final Object? received;

  @override
  String toString() =>
      'RealtimeProtocolException: resposta inválida para "$event", '
      'esperado Map<String, dynamic>, recebido ${received.runtimeType}';
}
