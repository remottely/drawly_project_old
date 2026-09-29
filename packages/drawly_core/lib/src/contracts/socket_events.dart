/// Fonte única de verdade dos nomes de evento do socket.
///
/// Espelhado em `backend-go/src/contracts.go`. Qualquer mudança aqui exige a
/// mudança correspondente do outro lado, no mesmo commit.
///
/// String literal de evento fora desta classe é bug: um typo vira um listener
/// que nunca dispara, sem erro de compilação nem de runtime.
abstract final class SocketEvents {
  // ── conexão ────────────────────────────────────────────────────────────────
  static const connect = 'connect';
  static const disconnect = 'disconnect';
  static const error = 'error';

  // ── sala ───────────────────────────────────────────────────────────────────
  static const roomCreate = 'room:create';
  static const roomCreated = 'room:created';
  static const roomJoin = 'room:join';
  static const roomLeave = 'room:leave';
  static const roomAll = 'room:all';
  static const roomParticipantsUpdate = 'room:participants:update';

  // ── desenho ────────────────────────────────────────────────────────────────
  static const drawingStrokeStart = 'drawing:stroke:start';
  static const drawingStrokeLastPoints = 'drawing:stroke:lastPoints';
  static const drawingStrokeAll = 'drawing:stroke:all';
  static const drawingClear = 'drawing:clear';
  static const drawingUndo = 'drawing:undo';
  static const drawingRedo = 'drawing:redo';

  // ── chat ───────────────────────────────────────────────────────────────────
  static const chatMessage = 'chat:message';
  static const chatAnswerGuess = 'chat:answer:guess';
  static const chatAnswerResult = 'chat:answer:result';

  // ── jogo ───────────────────────────────────────────────────────────────────
  static const gameTurnsStart = 'game:turns:start';
  static const gameTurnNew = 'game:turn:new';
  static const gameRanking = 'game:ranking';

  /// Todos os eventos declarados. Usado pelo teste de contrato que compara
  /// esta lista com a do backend Go.
  static const all = <String>[
    connect,
    disconnect,
    error,
    roomCreate,
    roomCreated,
    roomJoin,
    roomLeave,
    roomAll,
    roomParticipantsUpdate,
    drawingStrokeStart,
    drawingStrokeLastPoints,
    drawingStrokeAll,
    drawingClear,
    drawingUndo,
    drawingRedo,
    chatMessage,
    chatAnswerGuess,
    chatAnswerResult,
    gameTurnsStart,
    gameTurnNew,
    gameRanking,
  ];
}
