import 'package:drawing_board/drawing_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Os cenários alinham a geometria ao centro das células (`x + 0.5`), que é
/// onde o raster amostra. Assim o conjunto esperado é derivável no papel:
/// uma linha de espessura 1 passando por `x = 2.5` marca exatamente a coluna
/// 2, e nada mais.
Offset cell(int x, int y) => Offset(x.toDouble(), y.toDouble());

/// Todas as células do retângulo `[x0, x1] × [y0, y1]`, inclusivo.
Set<Offset> block(int x0, int y0, int x1, int y1) => {
      for (var y = y0; y <= y1; y++)
        for (var x = x0; x <= x1; x++) cell(x, y),
    };

/// Moldura quadrada a lápis, de `(from, from)` a `(to, to)`.
NormalStroke frame({
  required double from,
  required double to,
  double size = 1,
}) =>
    NormalStroke(
      points: [
        Offset(from, from),
        Offset(to, from),
        Offset(to, to),
        Offset(from, to),
        Offset(from, from),
      ],
      size: size,
    );

void main() {
  group('bucketFill', () {
    test('preenche o canvas inteiro quando não há strokes', () {
      final result = bucketFill(
        start: Offset.zero,
        strokes: const [],
        canvasSize: const Size(5, 5),
      );

      expect(result, unorderedEquals(block(0, 0, 4, 4)));
    });

    test('clique fora do canvas não preenche nada', () {
      for (final start in const [Offset(5, 2), Offset(2, 5), Offset(-1, 2)]) {
        final result = bucketFill(
          start: start,
          strokes: const [],
          canvasSize: const Size(5, 5),
        );

        expect(result, isEmpty, reason: 'start $start');
      }
    });

    test('para na borda de um traço fino', () {
      final result = bucketFill(
        start: const Offset(2.5, 2.5),
        strokes: [frame(from: 0.5, to: 5.5)],
        canvasSize: const Size(6, 6),
      );

      expect(result, unorderedEquals(block(1, 1, 4, 4)));
    });

    test('ponto inicial fracionário não desloca o preenchimento', () {
      final result = bucketFill(
        start: const Offset(1.2, 4.9),
        strokes: [frame(from: 0.5, to: 5.5)],
        canvasSize: const Size(6, 6),
      );

      expect(result, unorderedEquals(block(1, 1, 4, 4)));
    });

    test('chega até um traço espesso sem fresta e sem invadi-lo', () {
      // Espessura 6 em volta de x = 0 cobre [-3, 3]: as colunas 0..2 ficam
      // debaixo do traço e a 3 é a primeira livre. Em volta de x = 9 cobre
      // [6, 12]: a coluna 6 já é traço, a 5 é a última livre.
      final result = bucketFill(
        start: const Offset(4.5, 4.5),
        strokes: [frame(from: 0, to: 9, size: 6)],
        canvasSize: const Size(10, 10),
      );

      expect(result, unorderedEquals(block(3, 3, 5, 5)));
    });

    test('traço muito espesso segue a mesma regra', () {
      final result = bucketFill(
        start: const Offset(10, 10),
        strokes: [frame(from: 0, to: 19, size: 10)],
        canvasSize: const Size(20, 20),
      );

      expect(result, unorderedEquals(block(5, 5, 13, 13)));
    });

    test('não vaza por uma linha fina em diagonal', () {
      // A anti-diagonal (x + y = 5) vira uma cadeia de células ligadas só
      // pela quina. Um fill 8-conexo atravessaria; o 4-conexo fica do lado
      // de cima: o triângulo x + y < 5.
      final diagonal = LineStroke(
        points: const [Offset(0.5, 5.5), Offset(5.5, 0.5)],
      );

      final result = bucketFill(
        start: const Offset(0.5, 0.5),
        strokes: [diagonal],
        canvasSize: const Size(6, 6),
      );

      expect(result, hasLength(15));
      expect(result.every((p) => p.dx + p.dy < 5), isTrue);
    });

    test('clicar sobre um traço preenche o próprio traço', () {
      final wall = LineStroke(
        points: const [Offset(0.5, 2.5), Offset(4.5, 2.5)],
      );

      final result = bucketFill(
        start: const Offset(2.5, 2.5),
        strokes: [wall],
        canvasSize: const Size(5, 5),
      );

      expect(result, unorderedEquals(block(0, 2, 4, 2)));
    });

    test('linha reta usa só as extremidades, como o painter', () {
      // Os pontos intermediários são o caminho do arrasto; o painter traça a
      // reta entre o primeiro e o último. O raster precisa ver a mesma reta.
      final line = LineStroke(
        points: const [Offset(0.5, 2.5), Offset(2.5, 0.5), Offset(4.5, 2.5)],
      );

      final result = bucketFill(
        start: const Offset(2.5, 0.5),
        strokes: [line],
        canvasSize: const Size(5, 5),
      );

      expect(result, unorderedEquals(block(0, 0, 4, 1)));
    });

    test('a borracha abre passagem num traço', () {
      final wall = LineStroke(
        points: const [Offset(0.5, 2.5), Offset(4.5, 2.5)],
      );
      final eraser = EraserStroke(
        points: const [Offset(2.5, 0.5), Offset(2.5, 4.5)],
      );

      final result = bucketFill(
        start: const Offset(0.5, 0.5),
        strokes: [wall, eraser],
        canvasSize: const Size(5, 5),
      );

      expect(result, hasLength(21));
      expect(result, contains(cell(2, 2)));
      expect(result, contains(cell(0, 4)));
      expect(result, isNot(contains(cell(0, 2))));
    });

    test('traço da cor do fundo não é barreira', () {
      final invisible = LineStroke(
        points: const [Offset(0.5, 2.5), Offset(4.5, 2.5)],
        color: Colors.white,
      );

      final result = bucketFill(
        start: const Offset(0.5, 0.5),
        strokes: [invisible],
        canvasSize: const Size(5, 5),
        backgroundColor: Colors.white,
      );

      expect(result, hasLength(25));
    });

    test('forma com um só ponto ainda não é desenhada nem bloqueia', () {
      final justStarted = CircleStroke(points: const [Offset(2, 2)], size: 8);

      final result = bucketFill(
        start: const Offset(0.5, 0.5),
        strokes: [justStarted],
        canvasSize: const Size(5, 5),
      );

      expect(result, hasLength(25));
    });

    group('formas', () {
      test('quadrado vazado respeita a espessura do contorno', () {
        final square = SquareStroke(
          points: const [Offset(2, 2), Offset(6, 6)],
          size: 2,
        );

        final result = bucketFill(
          start: const Offset(3.5, 3.5),
          strokes: [square],
          canvasSize: const Size(8, 8),
        );

        expect(result, unorderedEquals(block(3, 3, 4, 4)));
      });

      test('quadrado preenchido não é dilatado pela espessura', () {
        // Com `filled`, o painter usa PaintingStyle.fill: a espessura não
        // existe. As células ocupadas são as de centro dentro de [2, 6].
        final square = SquareStroke(
          points: const [Offset(2, 2), Offset(6, 6)],
          size: 4,
          filled: true,
        );

        final result = bucketFill(
          start: const Offset(0.5, 0.5),
          strokes: [square],
          canvasSize: const Size(8, 8),
        );

        expect(result, hasLength(64 - 16));
        expect(result, containsAll([cell(1, 1), cell(1, 5), cell(6, 6)]));
        expect(result, isNot(contains(cell(2, 2))));
        expect(result, isNot(contains(cell(5, 5))));
      });

      test('círculo vazado: preenche até o anel sem vazar', () {
        // Centro (20, 20), raio 15, contorno de espessura 2: o anel ocupa
        // as células cujo centro dista entre 14 e 16 do centro.
        final circle = CircleStroke(
          points: const [Offset(5, 5), Offset(35, 35)],
          size: 2,
        );

        final result = bucketFill(
          start: const Offset(20, 20),
          strokes: [circle],
          canvasSize: const Size(40, 40),
        );

        double distance(Offset p) =>
            (Offset(p.dx + 0.5, p.dy + 0.5) - const Offset(20, 20)).distance;

        expect(result.every((p) => distance(p) < 14), isTrue);
        expect(result, containsAll([cell(20, 6), cell(33, 20)]));
        expect(result, isNot(contains(cell(20, 5))));
        expect(result, isNot(contains(cell(34, 20))));
      });

      test('círculo preenchido é barreira exata, sem dilatação', () {
        final disc = CircleStroke(
          points: const [Offset(5, 5), Offset(35, 35)],
          size: 10,
          filled: true,
        );

        final result = bucketFill(
          start: const Offset(0.5, 0.5),
          strokes: [disc],
          canvasSize: const Size(40, 40),
        );

        expect(result, contains(cell(20, 4)));
        expect(result, isNot(contains(cell(20, 5))));
      });

      test('polígono vazado usa os mesmos vértices do painter', () {
        // Triângulo de raio 10 (limitado pelo canvas) centrado em (10, 20):
        // vértice de cima em (10, 10), base em y = 25.
        final triangle = PolygonStroke(
          points: const [Offset(10, 2), Offset(10, 38)],
          sides: 3,
          size: 2,
        );

        final result = bucketFill(
          start: const Offset(10, 20),
          strokes: [triangle],
          canvasSize: const Size(40, 40),
        );

        bool insideTriangle(Offset p) {
          final cx = p.dx + 0.5;
          final cy = p.dy + 0.5;
          if (cy < 10 || cy > 25) return false;
          final halfWidth = (cy - 10) * 0.5773502691896257;
          return (cx - 10).abs() < halfWidth;
        }

        expect(result.every(insideTriangle), isTrue);
        expect(result, contains(cell(10, 14)));
        expect(result, isNot(contains(cell(10, 9))));
      });

      test('polígono preenchido é barreira exata', () {
        // Losango |x - 10| + |y - 20| <= 10.
        final diamond = PolygonStroke(
          points: const [Offset(10, 2), Offset(10, 38)],
          sides: 4,
          size: 4,
          filled: true,
        );

        final result = bucketFill(
          start: const Offset(0.5, 0.5),
          strokes: [diamond],
          canvasSize: const Size(40, 40),
        );

        expect(result, containsAll([cell(4, 12), cell(10, 9)]));
        expect(result, isNot(contains(cell(10, 20))));
        expect(result, isNot(contains(cell(9, 12))));
      });
    });

    group('baldes anteriores', () {
      test('são barreira pixel a pixel, sem dilatação', () {
        final column = BucketStroke(
          points: const [Offset(2, 0)],
          color: Colors.red,
          size: 10,
          fillPixels: block(2, 0, 2, 4).toList(),
        );

        final result = bucketFill(
          start: const Offset(0.5, 0.5),
          strokes: [column],
          canvasSize: const Size(5, 5),
        );

        expect(result, unorderedEquals(block(0, 0, 1, 4)));
      });

      test('clicar sobre um balde anterior repreenche a mesma região', () {
        final previous = BucketStroke(
          points: const [Offset.zero],
          color: Colors.red,
          fillPixels: block(0, 0, 1, 4).toList(),
        );

        final result = bucketFill(
          start: const Offset(1.5, 3.5),
          strokes: [previous],
          canvasSize: const Size(5, 5),
        );

        expect(result, unorderedEquals(block(0, 0, 1, 4)));
      });
    });
  });

  group('bucketFillRuns', () {
    test('agrupa pixels consecutivos por linha, em qualquer ordem', () {
      final runs = bucketFillRuns([
        cell(4, 0),
        cell(0, 1),
        cell(2, 0),
        cell(1, 0),
      ]);

      expect(runs, [
        const Rect.fromLTWH(1, 0, 2, 1),
        const Rect.fromLTWH(4, 0, 1, 1),
        const Rect.fromLTWH(0, 1, 1, 1),
      ]);
    });

    test('pixel repetido não quebra a faixa', () {
      final runs = bucketFillRuns([cell(1, 0), cell(1, 0), cell(2, 0)]);

      expect(runs, [const Rect.fromLTWH(1, 0, 2, 1)]);
    });

    test('lista vazia gera nenhuma faixa', () {
      expect(bucketFillRuns(const []), isEmpty);
    });
  });

  group('bucketFillPath', () {
    test('contém o centro de cada pixel e nada fora deles', () {
      final path = bucketFillPath([cell(0, 0), cell(1, 0), cell(0, 1)]);

      expect(path.contains(const Offset(0.5, 0.5)), isTrue);
      expect(path.contains(const Offset(1.5, 0.5)), isTrue);
      expect(path.contains(const Offset(0.5, 1.5)), isTrue);
      expect(path.contains(const Offset(1.5, 1.5)), isFalse);
    });
  });
}
