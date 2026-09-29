import 'package:drawly_core/src/realtime/realtime_gateway.dart';

/// Agrupa as inscrições de um escopo (widget, controller) para que um único
/// [dispose] as remova todas.
///
/// Substitui o padrão manual repetido pelo projeto — um campo
/// `late final void Function(dynamic) _onXEvent` por evento, registro no
/// `initState` e remoção no `dispose` — que era a origem dos listeners vazados.
///
/// ```dart
/// final _subscriptions = RealtimeSubscriptions(gateway);
///
/// void _listen() {
///   _subscriptions
///     ..on(SocketEvents.gameTurnNew, _onTurn)
///     ..on(SocketEvents.chatMessage, _onMessage);
/// }
///
/// @override
/// void dispose() {
///   _subscriptions.dispose();
///   super.dispose();
/// }
/// ```
final class RealtimeSubscriptions {
  RealtimeSubscriptions(this._gateway);

  final RealtimeGateway _gateway;
  final List<_Subscription> _subscriptions = [];

  /// Quantidade de inscrições ativas. Útil em teste para provar que o
  /// [dispose] realmente limpou tudo.
  int get length => _subscriptions.length;

  /// Registra [listener] em [event] e passa a rastreá-lo.
  void on(String event, RealtimeListener listener) {
    _gateway.on(event, listener);
    _subscriptions.add(_Subscription(event, listener));
  }

  /// Remove uma inscrição específica antes do [dispose].
  void off(String event, RealtimeListener listener) {
    _subscriptions.removeWhere(
      (subscription) =>
          subscription.event == event && subscription.listener == listener,
    );
    _gateway.off(event, listener);
  }

  /// Remove todas as inscrições. Idempotente.
  void dispose() {
    for (final subscription in _subscriptions) {
      _gateway.off(subscription.event, subscription.listener);
    }
    _subscriptions.clear();
  }
}

final class _Subscription {
  const _Subscription(this.event, this.listener);

  final String event;
  final RealtimeListener listener;
}
