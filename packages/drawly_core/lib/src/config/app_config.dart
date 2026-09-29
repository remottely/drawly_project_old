/// Configuração de ambiente.
///
/// Nenhum host, porta ou chave é hardcoded em código de produção: tudo vem de
/// `--dart-define`, com default igual ao valor de desenvolvimento.
///
/// ```bash
/// flutter run --dart-define=DRAWLY_REALTIME_URL=https://api.drawly.app
/// ```
abstract final class AppConfig {
  /// URL do servidor de tempo real.
  static const realtimeUrl = String.fromEnvironment(
    'DRAWLY_REALTIME_URL',
    defaultValue: 'http://localhost:5555',
  );

  /// Tentativas de reconexão antes de desistir.
  static const reconnectionAttempts = int.fromEnvironment(
    'DRAWLY_RECONNECTION_ATTEMPTS',
    defaultValue: 5,
  );

  /// Espera inicial entre tentativas de reconexão.
  static const reconnectionDelay = Duration(milliseconds: 2000);

  /// Teto da espera entre tentativas de reconexão.
  static const reconnectionDelayMax = Duration(milliseconds: 5000);

  /// Timeout default de um `emitWithAck`.
  static const ackTimeout = Duration(seconds: 10);
}
