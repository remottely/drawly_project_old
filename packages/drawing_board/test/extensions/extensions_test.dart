import 'package:drawing_board/drawing_board.dart';
import 'package:drawing_board/src/util/polygon_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DrawingToolExtensions.strokeType', () {
    test('mapeia cada ferramenta para o tipo de traço correspondente', () {
      const esperado = {
        DrawingTool.pencil: StrokeType.normal,
        DrawingTool.fill: StrokeType.normal,
        DrawingTool.eraser: StrokeType.eraser,
        DrawingTool.line: StrokeType.line,
        DrawingTool.polygon: StrokeType.polygon,
        DrawingTool.square: StrokeType.square,
        DrawingTool.circle: StrokeType.circle,
        DrawingTool.bucket: StrokeType.bucket,
      };

      esperado.forEach((tool, strokeType) {
        expect(tool.strokeType, strokeType, reason: tool.name);
      });
    });

    test('cobre todas as ferramentas — nenhuma fica sem mapeamento', () {
      for (final tool in DrawingTool.values) {
        expect(() => tool.strokeType, returnsNormally, reason: tool.name);
      }
    });
  });

  group('DrawingToolExtensions.cursor', () {
    test('ferramentas de desenho usam cursor de precisão', () {
      const precisas = [
        DrawingTool.pencil,
        DrawingTool.line,
        DrawingTool.polygon,
        DrawingTool.square,
        DrawingTool.circle,
        DrawingTool.eraser,
        DrawingTool.bucket,
      ];

      for (final tool in precisas) {
        expect(tool.cursor, SystemMouseCursors.precise, reason: tool.name);
      }
    });

    test('a ferramenta fill usa cursor de clique', () {
      expect(DrawingTool.fill.cursor, SystemMouseCursors.click);
    });
  });

  group('DrawingTool — predicados', () {
    test('cada predicado é verdadeiro apenas para a própria ferramenta', () {
      final predicados = <DrawingTool, bool Function(DrawingTool)>{
        DrawingTool.pencil: (t) => t.isPencil,
        DrawingTool.fill: (t) => t.isFill,
        DrawingTool.line: (t) => t.isLine,
        DrawingTool.eraser: (t) => t.isEraser,
        DrawingTool.polygon: (t) => t.isPolygon,
        DrawingTool.square: (t) => t.isSquare,
        DrawingTool.circle: (t) => t.isCircle,
        DrawingTool.bucket: (t) => t.isBucket,
      };

      predicados.forEach((dona, predicado) {
        for (final tool in DrawingTool.values) {
          expect(
            predicado(tool),
            tool == dona,
            reason: 'predicado de ${dona.name} avaliado em ${tool.name}',
          );
        }
      });
    });
  });

  group('OffsetExtensions', () {
    const deviceSize = Size(400, 300);

    test('scaleToStandard converte da tela do dispositivo para o padrão', () {
      const point = Offset(200, 150); // centro do dispositivo

      final scaled = point.scaleToStandard(deviceSize);

      expect(scaled, const Offset(400, 300)); // centro do canvas padrão
    });

    test('scaleFromStandard converte do padrão para a tela do dispositivo', () {
      const point = Offset(400, 300); // centro do canvas padrão

      final scaled = point.scaleFromStandard(deviceSize);

      expect(scaled, const Offset(200, 150));
    });

    test('as duas conversões são inversas', () {
      const original = Offset(123, 77);

      final roundTrip =
          original.scaleToStandard(deviceSize).scaleFromStandard(deviceSize);

      expect(roundTrip.dx, closeTo(original.dx, 1e-9));
      expect(roundTrip.dy, closeTo(original.dy, 1e-9));
    });

    test('a origem não se move em nenhuma direção', () {
      expect(Offset.zero.scaleToStandard(deviceSize), Offset.zero);
      expect(Offset.zero.scaleFromStandard(deviceSize), Offset.zero);
    });

    test('um dispositivo do tamanho padrão não altera as coordenadas', () {
      const standard = Size(
        OffsetExtensions.standardWidth,
        OffsetExtensions.standardHeight,
      );
      const point = Offset(37, 91);

      expect(point.scaleToStandard(standard), point);
      expect(point.scaleFromStandard(standard), point);
    });
  });

  group('calculateClampedPolygonRadius', () {
    test('devolve o raio calculado quando o polígono cabe no canvas', () {
      const first = Offset(50, 50);
      const last = Offset(70, 50);

      final radius = calculateClampedPolygonRadius(
        firstPoint: first,
        lastPoint: last,
        canvasSize: const Size(200, 200),
      );

      expect(radius, 10); // metade da distância entre os pontos
    });

    test('limita o raio à borda mais próxima do canvas', () {
      // Arrastar de canto a canto pediria um raio maior que o canvas comporta.
      const canvasSize = Size(200, 100);

      final radius = calculateClampedPolygonRadius(
        firstPoint: Offset.zero,
        lastPoint: Offset(canvasSize.width, canvasSize.height),
        canvasSize: canvasSize,
      );

      expect(
        radius,
        canvasSize.height / 2,
        reason: 'a altura é a dimensão limitante',
      );
    });

    test('devolve zero quando os dois pontos coincidem', () {
      final radius = calculateClampedPolygonRadius(
        firstPoint: const Offset(30, 30),
        lastPoint: const Offset(30, 30),
        canvasSize: const Size(100, 100),
      );

      expect(radius, 0);
    });

    test('devolve raio não positivo quando o centro cai fora do canvas', () {
      // Protege contra desenhar um polígono "para fora" da área visível.
      final radius = calculateClampedPolygonRadius(
        firstPoint: const Offset(-100, -100),
        lastPoint: const Offset(-80, -80),
        canvasSize: const Size(100, 100),
      );

      expect(radius, lessThanOrEqualTo(0));
    });
  });
}
