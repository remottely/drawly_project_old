import 'package:drawly/features/draw_game/chats/answers_chat/answers_chat_view.dart';
import 'package:drawly/features/draw_game/chats/message_chat/messages_chat_view.dart';
import 'package:drawly_core/drawly_core.dart';
import 'package:drawly_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Estes testes só são possíveis por causa da costura do [RealtimeGateway]:
/// antes, montar qualquer um destes widgets abria um socket real para
/// `localhost:5555` no construtor do singleton.
void main() {
  late FakeRealtimeGateway gateway;

  setUp(() {
    gateway = FakeRealtimeGateway();
    SocketManager.setInstanceForTesting(gateway);
  });

  tearDown(SocketManager.resetInstanceForTesting);

  group('MessagesChatView', () {
    testWidgets('exibe as mensagens que chegam do servidor', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MessagesChatView(
            userId: 'u1',
            username: 'kevin',
            roomName: 'sala',
            isCurrentDrawer: false,
          ),
        ),
      );

      gateway.emitServerEvent(SocketEvents.chatMessage, const {
        'icon': 'info',
        'userId': 'u2',
        'username': 'ana',
        'text': 'entrou',
      });
      await tester.pump();

      expect(_richText('entrou'), findsOneWidget);
    });

    testWidgets('acumula as mensagens na ordem de chegada', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MessagesChatView(
            userId: 'u1',
            username: 'kevin',
            roomName: 'sala',
            isCurrentDrawer: false,
          ),
        ),
      );

      for (final texto in ['primeira', 'segunda', 'terceira']) {
        gateway.emitServerEvent(SocketEvents.chatMessage, {
          'icon': null,
          'userId': 'u2',
          'username': 'ana',
          'text': texto,
        });
      }
      await tester.pump();

      expect(_richText('primeira'), findsOneWidget);
      expect(_richText('segunda'), findsOneWidget);
      expect(_richText('terceira'), findsOneWidget);
    });

    testWidgets('enviar emite chat:message com o payload completo', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const MessagesChatView(
            userId: 'u1',
            username: 'kevin',
            roomName: 'sala',
            isCurrentDrawer: false,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).first, 'olá pessoal');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(gateway.lastEmittedOn(SocketEvents.chatMessage), {
        'roomName': 'sala',
        'userId': 'u1',
        'username': 'kevin',
        'text': 'olá pessoal',
      });
    });

    testWidgets('não emite mensagem vazia', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MessagesChatView(
            userId: 'u1',
            username: 'kevin',
            roomName: 'sala',
            isCurrentDrawer: false,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).first, '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(gateway.emittedOn(SocketEvents.chatMessage), isEmpty);
    });

    testWidgets('dispose remove o listener de chat:message', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MessagesChatView(
            userId: 'u1',
            username: 'kevin',
            roomName: 'sala',
            isCurrentDrawer: false,
          ),
        ),
      );
      expect(gateway.listenerCount(SocketEvents.chatMessage), 1);

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));

      expect(gateway.listenerCount(SocketEvents.chatMessage), 0);
    });
  });

  group('AnswersChatView', () {
    Widget answersView() => _wrap(
      const AnswersChatView(
        userId: 'u1',
        username: 'kevin',
        roomName: 'sala',
        isCurrentDrawer: false,
        isGameStarted: true,
      ),
    );

    testWidgets('exibe os palpites que chegam do servidor', (tester) async {
      await tester.pumpWidget(answersView());

      gateway.emitServerEvent(SocketEvents.chatAnswerResult, const {
        'icon': null,
        'userId': 'u2',
        'username': 'ana',
        'text': 'cachorro',
        'isCorrect': false,
      });
      await tester.pump();

      expect(_richText('cachorro'), findsOneWidget);
    });

    testWidgets('enviar emite chat:answer:guess', (tester) async {
      await tester.pumpWidget(answersView());

      await tester.enterText(find.byType(TextField).first, 'gato');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(gateway.lastEmittedOn(SocketEvents.chatAnswerGuess), {
        'roomName': 'sala',
        'userId': 'u1',
        'username': 'kevin',
        'text': 'gato',
      });
    });

    testWidgets('um turno novo limpa os palpites anteriores', (tester) async {
      await tester.pumpWidget(answersView());

      gateway
        ..emitServerEvent(SocketEvents.chatAnswerResult, const {
          'icon': null,
          'userId': 'u2',
          'username': 'ana',
          'text': 'chute-antigo',
          'isCorrect': false,
        })
        ..emitServerEvent(SocketEvents.gameTurnNew, const <String, dynamic>{});
      await tester.pump();

      expect(_richText('chute-antigo'), findsNothing);
    });

    testWidgets('dispose remove o listener de chat:answer:result', (
      tester,
    ) async {
      await tester.pumpWidget(answersView());
      expect(gateway.listenerCount(SocketEvents.chatAnswerResult), 1);

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));

      expect(gateway.listenerCount(SocketEvents.chatAnswerResult), 0);
    });

    testWidgets('o vazamento de game:turn:new está presente hoje', (
      tester,
    ) async {
      // Trava o comportamento atual para que a correção de R7 apareça como uma
      // mudança deliberada, e não como um teste quebrando do nada.
      await tester.pumpWidget(answersView());
      await tester.pumpWidget(_wrap(const SizedBox.shrink()));

      expect(
        gateway.listenerCount(SocketEvents.gameTurnNew),
        1,
        reason: 'quando R7 for corrigido, este teste deve ser trocado por 0',
      );
    });
  });
}

/// As mensagens do chat são pintadas com RichText/TextSpan, que `find.text`
/// não enxerga sem `findRichText`.
Finder _richText(String text) => find.textContaining(text, findRichText: true);

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SizedBox(height: 400, child: child)));
