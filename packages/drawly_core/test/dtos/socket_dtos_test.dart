import 'package:drawly_core/drawly_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RoomDTO', () {
    test('serializa apenas o nome da sala', () {
      expect(RoomDTO(roomName: 'sala').toJson(), {'roomName': 'sala'});
    });
  });

  group('RoomUserDTO', () {
    test('inclui os campos do pai e os próprios', () {
      final dto = RoomUserDTO(
        roomName: 'sala',
        userId: 'u1',
        username: 'kevin',
        userAvatar: 'avatar.png',
        isLogged: true,
      );

      expect(dto.toJson(), {
        'roomName': 'sala',
        'userId': 'u1',
        'username': 'kevin',
        'userAvatar': 'avatar.png',
        'isLogged': true,
      });
    });

    test('preserva userAvatar nulo em vez de omitir a chave', () {
      final dto = RoomUserDTO(
        roomName: 'sala',
        userId: 'u1',
        username: 'kevin',
        userAvatar: null,
        isLogged: false,
      );

      final json = dto.toJson();

      expect(json.containsKey('userAvatar'), isTrue);
      expect(json['userAvatar'], isNull);
    });

    test('é um RoomDTO', () {
      expect(
        RoomUserDTO(
          roomName: 'sala',
          userId: 'u1',
          username: 'kevin',
          userAvatar: null,
          isLogged: false,
        ),
        isA<RoomDTO>(),
      );
    });
  });

  group('RoomUserMessageDTO', () {
    test('serializa o payload de chat', () {
      final dto = RoomUserMessageDTO(
        roomName: 'sala',
        userId: 'u1',
        username: 'kevin',
        text: 'olá',
      );

      expect(dto.toJson(), {
        'roomName': 'sala',
        'userId': 'u1',
        'username': 'kevin',
        'text': 'olá',
      });
    });

    test('preserva texto vazio', () {
      final dto = RoomUserMessageDTO(
        roomName: 'sala',
        userId: 'u1',
        username: 'kevin',
        text: '',
      );

      expect(dto.toJson()['text'], '');
    });
  });

  group('RoomUserAnswerDTO', () {
    test('serializa o palpite', () {
      final dto = RoomUserAnswerDTO(
        roomName: 'sala',
        userId: 'u1',
        username: 'kevin',
        text: 'gato',
      );

      expect(dto.toJson(), {
        'roomName': 'sala',
        'userId': 'u1',
        'username': 'kevin',
        'text': 'gato',
      });
    });
  });

  group('ErrorDTO', () {
    test('faz round-trip de todas as ações', () {
      for (final action in ErrorActionType.values) {
        final original = ErrorDTO(message: 'falhou', action: action);
        final restored = ErrorDTO.fromJson(original.toJson());

        expect(restored.message, original.message);
        expect(restored.action, original.action, reason: 'ação ${action.name}');
      }
    });

    test('serializa a ação pelo nome do enum', () {
      final json = ErrorDTO(
        message: 'x',
        action: ErrorActionType.dialog,
      ).toJson();

      expect(json['action'], 'dialog');
    });

    test('rejeita ação desconhecida em vez de silenciar', () {
      expect(
        () => ErrorDTO.fromJson({'message': 'x', 'action': 'inexistente'}),
        throwsArgumentError,
      );
    });

    test('copyWith substitui apenas os campos informados', () {
      final original = ErrorDTO(
        message: 'original',
        action: ErrorActionType.retry,
      );

      expect(original.copyWith(message: 'novo').action, ErrorActionType.retry);
      expect(original.copyWith(message: 'novo').message, 'novo');
      expect(
        original.copyWith(action: ErrorActionType.pop).message,
        'original',
      );
    });

    test('copyWith sem argumentos preserva tudo', () {
      final original = ErrorDTO(message: 'm', action: ErrorActionType.log);
      final copy = original.copyWith();

      expect(copy.message, original.message);
      expect(copy.action, original.action);
    });
  });

  group('ErrorActionType', () {
    test('cobre as ações esperadas pelo backend', () {
      expect(ErrorActionType.values.map((e) => e.name), [
        'nothing',
        'retry',
        'ignore',
        'log',
        'pop',
        'dialog',
      ]);
    });
  });
}
