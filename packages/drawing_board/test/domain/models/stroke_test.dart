import 'package:drawing_board/drawing_board.dart';
import 'package:drawly_design_system/drawly_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/stroke_fixtures.dart';

void main() {
  group('StrokeType', () {
    test('fromString reconhece todos os tipos', () {
      const esperado = {
        'normal': StrokeType.normal,
        'eraser': StrokeType.eraser,
        'line': StrokeType.line,
        'polygon': StrokeType.polygon,
        'square': StrokeType.square,
        'circle': StrokeType.circle,
        'bucket': StrokeType.bucket,
      };

      esperado.forEach((texto, tipo) {
        expect(StrokeType.fromString(texto), tipo, reason: texto);
      });
    });

    test('fromString cai em normal para valor desconhecido', () {
      // Tolerância proposital: um cliente antigo não deve quebrar ao receber um
      // tipo novo do servidor.
      expect(StrokeType.fromString('inexistente'), StrokeType.normal);
      expect(StrokeType.fromString(''), StrokeType.normal);
    });

    test('toString devolve o valor usado no wire format', () {
      for (final tipo in StrokeType.values) {
        expect(tipo.toString(), tipo.name, reason: tipo.name);
      }
    });

    test('fromString e toString são inversos', () {
      for (final tipo in StrokeType.values) {
        expect(StrokeType.fromString(tipo.toString()), tipo);
      }
    });
  });

  group('Stroke.fromJson', () {
    test('constrói a subclasse certa para cada strokeType', () {
      const esperado = <String, Type>{
        'normal': NormalStroke,
        'eraser': EraserStroke,
        'line': LineStroke,
        'polygon': PolygonStroke,
        'square': SquareStroke,
        'circle': CircleStroke,
        'bucket': BucketStroke,
      };

      esperado.forEach((tipo, classe) {
        final stroke = Stroke.fromJson(StrokeFixtures.json(strokeType: tipo));
        expect(stroke.runtimeType, classe, reason: tipo);
        expect(stroke.strokeType.name, tipo);
      });
    });

    test('preserva pontos, cor, tamanho e opacidade', () {
      final stroke = Stroke.fromJson(
        StrokeFixtures.json(strokeType: 'normal'),
      );

      expect(stroke.points, StrokeFixtures.points);
      expect(stroke.size, StrokeFixtures.size);
      expect(stroke.opacity, StrokeFixtures.opacity);
      expect(stroke.color.toJson(), StrokeFixtures.color.toJson());
    });

    test('aceita size e opacity vindos como int', () {
      // O servidor Go serializa números sem casa decimal como int no JSON.
      final json = StrokeFixtures.json(strokeType: 'normal')
        ..['size'] = 3
        ..['opacity'] = 1;

      final stroke = Stroke.fromJson(json);

      expect(stroke.size, 3.0);
      expect(stroke.opacity, 1.0);
    });

    test('aceita lista de pontos vazia', () {
      final json = StrokeFixtures.json(strokeType: 'normal', points: []);

      expect(Stroke.fromJson(json).points, isEmpty);
    });

    group('PolygonStroke', () {
      test('usa sides e filled do payload', () {
        final json = StrokeFixtures.json(strokeType: 'polygon')
          ..['sides'] = 8
          ..['filled'] = true;

        final stroke = Stroke.fromJson(json) as PolygonStroke;

        expect(stroke.sides, 8);
        expect(stroke.filled, isTrue);
      });

      test('assume triângulo não preenchido quando os campos faltam', () {
        final stroke =
            Stroke.fromJson(StrokeFixtures.json(strokeType: 'polygon'))
                as PolygonStroke;

        expect(stroke.sides, 3);
        expect(stroke.filled, isFalse);
      });
    });

    group('formas com preenchimento', () {
      test('circle e square respeitam filled', () {
        for (final tipo in ['circle', 'square']) {
          final json = StrokeFixtures.json(strokeType: tipo)..['filled'] = true;
          final stroke = Stroke.fromJson(json);

          final filled = stroke is CircleStroke
              ? stroke.filled
              : (stroke as SquareStroke).filled;

          expect(filled, isTrue, reason: tipo);
        }
      });

      test('circle e square assumem não preenchido por omissão', () {
        expect(
          (Stroke.fromJson(StrokeFixtures.json(strokeType: 'circle'))
                  as CircleStroke)
              .filled,
          isFalse,
        );
        expect(
          (Stroke.fromJson(StrokeFixtures.json(strokeType: 'square'))
                  as SquareStroke)
              .filled,
          isFalse,
        );
      });
    });

    group('BucketStroke', () {
      test('lê fillPixels quando presente', () {
        final json = StrokeFixtures.json(strokeType: 'bucket')
          ..['fillPixels'] = [
            {'dx': 2.0, 'dy': 3.0},
            {'dx': 4.0, 'dy': 5.0},
          ];

        final stroke = Stroke.fromJson(json) as BucketStroke;

        expect(stroke.fillPixels, [const Offset(2, 3), const Offset(4, 5)]);
      });

      test('aceita fillPixels ausente', () {
        // É o caso normal: o cliente envia o bucket sem os pixels (payload
        // gigante) e cada peer recalcula o preenchimento localmente.
        final stroke =
            Stroke.fromJson(StrokeFixtures.json(strokeType: 'bucket'))
                as BucketStroke;

        expect(stroke.fillPixels, isEmpty);
      });

      test('aceita fillPixels vazio explícito', () {
        final json = StrokeFixtures.json(strokeType: 'bucket')
          ..['fillPixels'] = <dynamic>[];

        expect((Stroke.fromJson(json) as BucketStroke).fillPixels, isEmpty);
      });
    });
  });

  group('round-trip toJson → fromJson', () {
    test('preserva o tipo e os campos comuns de todo stroke', () {
      for (final original in StrokeFixtures.oneOfEach) {
        final restored = Stroke.fromJson(original.toJson());

        expect(
          restored.runtimeType,
          original.runtimeType,
          reason: original.strokeType.name,
        );
        expect(restored.points, original.points);
        expect(restored.size, original.size);
        expect(restored.opacity, original.opacity);
        expect(restored.color.toJson(), original.color.toJson());
      }
    });

    test('preserva sides e filled do polígono', () {
      final original = StrokeFixtures.polygon(sides: 6, filled: true);
      final restored = Stroke.fromJson(original.toJson()) as PolygonStroke;

      expect(restored.sides, 6);
      expect(restored.filled, isTrue);
    });

    test('preserva filled de círculo e quadrado', () {
      final circle =
          Stroke.fromJson(StrokeFixtures.circle(filled: true).toJson())
              as CircleStroke;
      final square =
          Stroke.fromJson(StrokeFixtures.square(filled: true).toJson())
              as SquareStroke;

      expect(circle.filled, isTrue);
      expect(square.filled, isTrue);
    });

    test('preserva fillPixels do bucket', () {
      final original = StrokeFixtures.bucket(
        fillPixels: const [Offset(1, 1), Offset(2, 2)],
      );

      final restored = Stroke.fromJson(original.toJson()) as BucketStroke;

      expect(restored.fillPixels, original.fillPixels);
    });
  });

  group('toJson', () {
    test('serializa pontos como objetos {dx, dy}', () {
      final json = StrokeFixtures.normal().toJson();

      expect(json['points'], [
        {'dx': 10.0, 'dy': 10.0},
        {'dx': 40.0, 'dy': 40.0},
      ]);
    });

    test('inclui strokeType em todos os tipos', () {
      for (final stroke in StrokeFixtures.oneOfEach) {
        expect(
          stroke.toJson()['strokeType'],
          stroke.strokeType.name,
          reason: stroke.strokeType.name,
        );
      }
    });

    test('só as formas com preenchimento expõem "filled"', () {
      expect(StrokeFixtures.normal().toJson().containsKey('filled'), isFalse);
      expect(StrokeFixtures.line().toJson().containsKey('filled'), isFalse);
      expect(StrokeFixtures.polygon().toJson().containsKey('filled'), isTrue);
      expect(StrokeFixtures.circle().toJson().containsKey('filled'), isTrue);
      expect(StrokeFixtures.square().toJson().containsKey('filled'), isTrue);
    });
  });

  group('copyWith', () {
    test('substitui apenas o que foi informado e mantém o tipo', () {
      for (final original in StrokeFixtures.oneOfEach) {
        final copy = original.copyWith(size: 99);

        expect(copy.runtimeType, original.runtimeType);
        expect(copy.size, 99);
        expect(copy.points, original.points);
        expect(copy.opacity, original.opacity);
      }
    });

    test('sem argumentos preserva todos os campos', () {
      final original = StrokeFixtures.normal();
      final copy = original.copyWith();

      expect(copy.points, original.points);
      expect(copy.size, original.size);
      expect(copy.opacity, original.opacity);
      expect(copy.color, original.color);
    });

    test('polygon preserva sides e filled quando não informados', () {
      final original = StrokeFixtures.polygon(sides: 7, filled: true);
      final copy = original.copyWith(size: 1);

      expect(copy.sides, 7);
      expect(copy.filled, isTrue);
    });

    test('bucket preserva fillPixels quando não informados', () {
      final original = StrokeFixtures.bucket(
        fillPixels: const [Offset(5, 5)],
      );

      final copy = original.copyWith(size: 1);

      expect(copy.fillPixels, const [Offset(5, 5)]);
    });

    test('bucket aceita limpar fillPixels', () {
      // É o que o canvas faz antes de mandar o stroke ao servidor: manda sem os
      // pixels para o payload não estourar.
      final original = StrokeFixtures.bucket(
        fillPixels: const [Offset(5, 5)],
      );

      final leve = original.copyWith(fillPixels: const []);

      expect(leve.fillPixels, isEmpty);
      expect(original.fillPixels, hasLength(1), reason: 'não muta o original');
    });
  });

  group('predicados de tipo', () {
    test('isEraser, isLine e isNormal refletem o strokeType', () {
      expect(StrokeFixtures.eraser().isEraser, isTrue);
      expect(StrokeFixtures.line().isLine, isTrue);
      expect(StrokeFixtures.normal().isNormal, isTrue);

      expect(StrokeFixtures.normal().isEraser, isFalse);
      expect(StrokeFixtures.normal().isLine, isFalse);
      expect(StrokeFixtures.eraser().isNormal, isFalse);
    });
  });

  group('valores default', () {
    test('um stroke sem opções usa preto, tamanho 1 e opacidade cheia', () {
      final stroke = NormalStroke(points: const [Offset.zero]);

      expect(stroke.color, Colors.black);
      expect(stroke.size, 1);
      expect(stroke.opacity, 1);
    });
  });
}
