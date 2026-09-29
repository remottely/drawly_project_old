import 'dart:io';

import 'package:drawly_core/drawly_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SocketEvents', () {
    test('não declara eventos duplicados', () {
      expect(SocketEvents.all.toSet(), hasLength(SocketEvents.all.length));
    });

    test('lista todas as constantes públicas declaradas', () {
      // Protege contra adicionar uma constante e esquecer de incluí-la em
      // `all` — o que faria o teste de contrato com o Go passar sem cobrir o
      // evento novo.
      final source = File(
        'lib/src/contracts/socket_events.dart',
      ).readAsStringSync();

      final declared = RegExp(r"static const \w+ = '([^']+)';")
          .allMatches(source)
          .map((match) => match.group(1)!)
          .toSet();

      expect(
        SocketEvents.all.toSet(),
        equals(declared),
        reason: 'SocketEvents.all deve conter exatamente as constantes '
            'declaradas no arquivo',
      );
    });

    test('nenhum nome de evento é vazio ou tem espaços', () {
      for (final event in SocketEvents.all) {
        expect(event, isNotEmpty);
        expect(event.trim(), equals(event), reason: 'evento "$event"');
      }
    });

    test('mantém o namespace por domínio', () {
      // O protocolo usa `dominio:acao`; as três exceções são os eventos nativos
      // do socket.io.
      const nativos = {
        SocketEvents.connect,
        SocketEvents.disconnect,
        SocketEvents.error,
      };

      for (final event in SocketEvents.all) {
        if (nativos.contains(event)) continue;
        expect(
          event,
          contains(':'),
          reason: 'evento de aplicação "$event" deveria ser namespaced',
        );
      }
    });
  });

  group('contrato com o backend Go', () {
    test('declara exatamente os mesmos eventos que contracts.go', () {
      final goSource = File(
        '../../backend-go/src/contracts.go',
      ).readAsStringSync();

      final goEvents = RegExp(r'Event\w+\s*=\s*"([^"]+)"')
          .allMatches(goSource)
          .map((match) => match.group(1)!)
          .toSet();

      expect(
        goEvents,
        isNotEmpty,
        reason:
            'nenhum evento encontrado em contracts.go — regex desatualizada?',
      );

      expect(
        SocketEvents.all.toSet(),
        equals(goEvents),
        reason: 'cliente e servidor divergiram no contrato de eventos: '
            'a mensagem simplesmente nunca chegaria, sem erro visível',
      );
    });
  });
}
