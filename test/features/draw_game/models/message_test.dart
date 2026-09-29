import 'package:drawly/features/draw_game/models/answer.dart';
import 'package:drawly/features/draw_game/models/message.dart';
import 'package:drawly/features/draw_game/models/participants.dart';
import 'package:drawly_design_system/drawly_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Message.fromJson', () {
    test('lê os campos obrigatórios', () {
      final message = Message.fromJson(const {
        'icon': 'info',
        'userId': 'u1',
        'username': 'kevin',
        'text': 'entrou',
      });

      expect(message.icon, MessageIconType.info);
      expect(message.userId, 'u1');
      expect(message.username, 'kevin');
      expect(message.text, 'entrou');
    });

    test('reconhece todos os tipos de ícone', () {
      for (final tipo in MessageIconType.values) {
        final message = Message.fromJson({
          'icon': tipo.name,
          'userId': 'u1',
          'username': 'kevin',
          'text': 'x',
        });

        expect(message.icon, tipo, reason: tipo.name);
      }
    });

    test('trata ícone desconhecido como ausente', () {
      // Tolerância proposital: um cliente antigo não pode quebrar porque o
      // servidor passou a mandar um ícone novo.
      final message = Message.fromJson(const {
        'icon': 'inexistente',
        'userId': 'u1',
        'username': 'kevin',
        'text': 'x',
      });

      expect(message.icon, isNull);
    });

    test('trata ícone nulo como ausente', () {
      final message = Message.fromJson(const {
        'icon': null,
        'userId': 'u1',
        'username': 'kevin',
        'text': 'x',
      });

      expect(message.icon, isNull);
    });
  });

  group('Message — aparência', () {
    test('info e check têm ícone próprio', () {
      expect(_message(MessageIconType.info).getIcon(), Icons.info);
      expect(_message(MessageIconType.check).getIcon(), Icons.check);
    });

    test('os demais tipos não têm ícone', () {
      const semIcone = [
        MessageIconType.waiting,
        MessageIconType.draw,
        MessageIconType.alert,
        MessageIconType.error,
      ];

      for (final tipo in semIcone) {
        expect(_message(tipo).getIcon(), isNull, reason: tipo.name);
      }
      expect(_message(null).getIcon(), isNull);
    });

    test('a cor acompanha o tipo de ícone', () {
      expect(_message(MessageIconType.info).getColor(), Colors.blue);
      expect(_message(MessageIconType.check).getColor(), Colors.green);
      expect(_message(null).getColor(), AppColors.greyAccent);
      expect(
        _message(MessageIconType.error).getColor(),
        AppColors.greyAccent,
        reason: 'tipos sem cor dedicada caem no cinza',
      );
    });
  });

  group('Message — igualdade', () {
    test('duas mensagens com os mesmos campos são iguais', () {
      expect(_message(MessageIconType.info), _message(MessageIconType.info));
    });

    test('mensagens com ícones diferentes não são iguais', () {
      expect(
        _message(MessageIconType.info),
        isNot(_message(MessageIconType.check)),
      );
    });
  });

  group('Message.copyWith', () {
    test('substitui apenas o que foi informado', () {
      final original = _message(MessageIconType.info);

      expect(original.copyWith(text: 'novo').text, 'novo');
      expect(original.copyWith(text: 'novo').userId, original.userId);
      expect(original.copyWith(userId: 'outro').text, original.text);
    });

    test('sem argumentos devolve um equivalente', () {
      final original = _message(MessageIconType.info);

      expect(original.copyWith(), original);
    });

    test('passar icon: null NÃO limpa o ícone', () {
      // Semântica padrão de copyWith em Dart (`icon ?? this.icon`): não há
      // como distinguir "não informado" de "informado como null". Documentado
      // aqui para que a mudança seja consciente, e não acidental.
      //
      // BUG(A7): decidir na fase 3 entre sentinela ou um `clearIcon()`
      // explícito. Ver docs/Pictionary/refactoring/01-achados.md.
      final original = _message(MessageIconType.info);

      expect(original.copyWith(icon: null).icon, MessageIconType.info);
    });
  });

  group('Answer', () {
    test('fromJson herda os campos de Message e lê isCorrect', () {
      final answer = Answer.fromJson(const {
        'icon': 'check',
        'userId': 'u1',
        'username': 'kevin',
        'text': 'gato',
        'isCorrect': true,
      });

      expect(answer.icon, MessageIconType.check);
      expect(answer.userId, 'u1');
      expect(answer.username, 'kevin');
      expect(answer.text, 'gato');
      expect(answer.isCorrect, isTrue);
    });

    test('fromJson lê palpite errado', () {
      final answer = Answer.fromJson(const {
        'icon': null,
        'userId': 'u1',
        'username': 'kevin',
        'text': 'cachorro',
        'isCorrect': false,
      });

      expect(answer.isCorrect, isFalse);
      expect(answer.icon, isNull);
    });

    test('é uma Message', () {
      expect(_answer(isCorrect: true), isA<Message>());
    });

    test('copyWith preserva isCorrect quando não informado', () {
      expect(
        _answer(isCorrect: true).copyWith(text: 'outro').isCorrect,
        isTrue,
      );
    });

    test('copyWith substitui isCorrect', () {
      expect(
        _answer(isCorrect: true).copyWith(isCorrect: false).isCorrect,
        isFalse,
      );
    });

    test('copyWith devolve um Answer, não uma Message', () {
      expect(_answer(isCorrect: true).copyWith(), isA<Answer>());
    });

    test('isCorrect participa da igualdade', () {
      expect(_answer(isCorrect: true), isNot(_answer(isCorrect: false)));
      expect(_answer(isCorrect: true), _answer(isCorrect: true));
    });
  });

  group('Participant.fromJson', () {
    test('lê todos os campos', () {
      final participant = Participant.fromJson(const {
        'userId': 'u1',
        'username': 'kevin',
        'userAvatar': 'avatar.png',
        'isLogged': true,
        'isConnected': true,
        'score': 120,
      });

      expect(participant.userId, 'u1');
      expect(participant.username, 'kevin');
      expect(participant.userAvatar, 'avatar.png');
      expect(participant.isLogged, isTrue);
      expect(participant.isConnected, isTrue);
      expect(participant.score, 120);
    });

    test('aceita avatar nulo', () {
      final participant = Participant.fromJson(const {
        'userId': 'u1',
        'username': 'kevin',
        'userAvatar': null,
        'isLogged': false,
        'isConnected': false,
        'score': 0,
      });

      expect(participant.userAvatar, isNull);
    });

    test('preserva o estado de desconectado', () {
      final participant = Participant.fromJson(const {
        'userId': 'u1',
        'username': 'kevin',
        'userAvatar': null,
        'isLogged': true,
        'isConnected': false,
        'score': 30,
      });

      expect(participant.isConnected, isFalse);
      expect(
        participant.score,
        30,
        reason: 'quem desconecta mantém a pontuação durante a tolerância',
      );
    });

    test('falha alto quando um campo obrigatório está ausente', () {
      // Melhor estourar em teste do que renderizar um participante meio nulo.
      expect(
        () => Participant.fromJson(const {'userId': 'u1'}),
        throwsA(isA<TypeError>()),
      );
    });
  });
}

Message _message(MessageIconType? icon) =>
    Message(icon: icon, userId: 'u1', username: 'kevin', text: 'texto');

Answer _answer({required bool isCorrect}) => Answer(
  icon: null,
  userId: 'u1',
  username: 'kevin',
  text: 'palpite',
  isCorrect: isCorrect,
);
