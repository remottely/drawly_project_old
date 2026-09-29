import 'package:drawing_board/drawing_board.dart';
import 'package:drawly_core/drawly_core.dart';
import 'package:drawly_core/testing.dart';
import 'package:drawly_design_system/drawly_design_system.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter_test/flutter_test.dart';

import '../../support/stroke_fixtures.dart';

/// Estes testes separam duas responsabilidades que antes viviam fundidas em um
/// único golden de gesto — e por isso quebraram juntas:
///
///  * **render** — dado um conjunto de strokes, o canvas pinta os pixels certos.
///    Semeia `rxAllStrokes` diretamente, que é a fonte real do painter.
///  * **input** — dado um gesto, o canvas produz o stroke certo e emite o
///    payload certo. Verifica estado e emissão, sem depender de pixel.
///
/// O desenho antigo (gesto → golden) dependia do eco do servidor para que
/// qualquer coisa aparecesse na tela (achado R9): sem servidor, todo golden
/// capturava canvas vazio.
void main() {
  late FakeRealtimeGateway gateway;

  setUp(() {
    gateway = FakeRealtimeGateway();
    SocketManager.setInstanceForTesting(gateway);
  });

  tearDown(SocketManager.resetInstanceForTesting);

  group('render — o painter desenha o que está em rxAllStrokes', () {
    testWidgets('canvas vazio', (tester) async {
      await tester.pumpWidget(const _Harness());

      await expectLater(
        find.byType(DrawingCanvas),
        matchesGoldenFile('goldens/empty_canvas.png'),
      );
    });

    testWidgets('traço a lápis', (tester) async {
      await tester.pumpWidget(
        _Harness(
          strokes: [
            StrokeFixtures.normal(
              points: const [Offset(100, 60), Offset(300, 200)],
            ),
          ],
        ),
      );

      await expectLater(
        find.byType(DrawingCanvas),
        matchesGoldenFile('goldens/single_stroke_canvas.png'),
      );
    });

    testWidgets('traço com cor diferente', (tester) async {
      await tester.pumpWidget(
        _Harness(
          strokes: [
            StrokeFixtures.normal(
              points: const [Offset(100, 60), Offset(300, 200)],
              color: AppColors.redAccent,
            ),
          ],
        ),
      );

      await expectLater(
        find.byType(DrawingCanvas),
        matchesGoldenFile('goldens/single_stroke_canvas_with_diff_color.png'),
      );
    });

    testWidgets('linha reta', (tester) async {
      await tester.pumpWidget(
        _Harness(
          strokes: [
            StrokeFixtures.line(
              points: const [Offset(250, 20), Offset(250, 260)],
            ),
          ],
          tool: DrawingTool.line,
        ),
      );

      await expectLater(
        find.byType(DrawingCanvas),
        matchesGoldenFile('goldens/straight_line.png'),
      );
    });

    testWidgets('grade de guias ativa', (tester) async {
      await tester.pumpWidget(const _Harness(showGrid: true));

      await expectLater(
        find.byType(DrawingCanvas),
        matchesGoldenFile('goldens/ruler_tool_active.png'),
      );
    });

    testWidgets('borracha sobre um traço', (tester) async {
      await tester.pumpWidget(
        _Harness(
          strokes: [
            StrokeFixtures.normal(
              points: const [Offset(80, 60), Offset(400, 60)],
            ),
            StrokeFixtures.eraser(
              points: const [Offset(200, 40), Offset(200, 240)],
            ),
          ],
        ),
      );

      await expectLater(
        find.byType(DrawingCanvas),
        matchesGoldenFile('goldens/erase_stroke.png'),
      );
    });

    testWidgets('balde dentro de um círculo', (tester) async {
      // O que o usuário vê ao clicar dentro de uma forma: o interior inteiro
      // pintado, encostado no contorno, sem fresta e sem vazar para fora.
      final circle = StrokeFixtures.circle(
        points: const [Offset(150, 40), Offset(350, 240)],
      );
      final bucket = StrokeFixtures.bucket(
        points: const [Offset(250, 140)],
        color: AppColors.redAccent,
        fillPixels: bucketFill(
          start: const Offset(250, 140),
          strokes: [circle],
          canvasSize: DrawingCanvas.logicalSize,
        ),
      );

      await tester.pumpWidget(_Harness(strokes: [circle, bucket]));

      await expectLater(
        find.byType(DrawingCanvas),
        matchesGoldenFile('goldens/bucket_fill_circle.png'),
      );
    });

    for (final caso in _shapeCases) {
      testWidgets(caso.description, (tester) async {
        await tester.pumpWidget(
          _Harness(strokes: [caso.stroke], tool: caso.tool),
        );

        await expectLater(
          find.byType(DrawingCanvas),
          matchesGoldenFile('goldens/${caso.golden}.png'),
        );
      });
    }
  });

  group('input — o gesto produz o stroke e o payload certos', () {
    testWidgets('pressionar inicia um stroke do tipo da ferramenta atual', (
      tester,
    ) async {
      final rxCurrentStroke = CurrentStrokeValueNotifier();
      await tester.pumpWidget(_Harness(rxCurrentStroke: rxCurrentStroke));

      await tester.startGesture(
        tester.getCenter(find.byType(DrawingCanvas)),
      );
      await tester.pump();

      expect(rxCurrentStroke.value, isA<NormalStroke>());
      expect(rxCurrentStroke.hasStroke, isTrue);
    });

    testWidgets('pressionar emite drawing:stroke:start com a sala certa', (
      tester,
    ) async {
      await tester.pumpWidget(const _Harness());

      await tester.startGesture(
        tester.getCenter(find.byType(DrawingCanvas)),
      );
      await tester.pump();

      final payload = gateway.lastEmittedOn(SocketEvents.drawingStrokeStart);

      expect(payload, isNotNull);
      expect(payload!['roomName'], _Harness.roomName);
      expect(payload['stroke'], isA<Map<String, dynamic>>());
    });

    testWidgets('arrastar acumula pontos no stroke em progresso', (
      tester,
    ) async {
      final rxCurrentStroke = CurrentStrokeValueNotifier();
      await tester.pumpWidget(_Harness(rxCurrentStroke: rxCurrentStroke));

      final center = tester.getCenter(find.byType(DrawingCanvas));
      final gesture = await tester.startGesture(center);
      await gesture.moveTo(center + const Offset(20, 20));
      await gesture.moveTo(center + const Offset(40, 40));
      await tester.pump();

      expect(rxCurrentStroke.value!.points.length, greaterThan(1));
    });

    testWidgets('a ferramenta escolhida define o tipo do stroke', (
      tester,
    ) async {
      const casos = {
        DrawingTool.line: LineStroke,
        DrawingTool.square: SquareStroke,
        DrawingTool.circle: CircleStroke,
        DrawingTool.polygon: PolygonStroke,
        DrawingTool.eraser: EraserStroke,
      };

      for (final entry in casos.entries) {
        final rxCurrentStroke = CurrentStrokeValueNotifier();
        await tester.pumpWidget(
          // A key força um State novo a cada iteração; sem ela o Flutter
          // reaproveita o State anterior e o notifier novo nunca é ligado.
          _Harness(
            key: ValueKey(entry.key),
            tool: entry.key,
            rxCurrentStroke: rxCurrentStroke,
          ),
        );

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(DrawingCanvas)),
        );
        await tester.pump();

        expect(
          rxCurrentStroke.value.runtimeType,
          entry.value,
          reason: 'ferramenta ${entry.key.name}',
        );

        // Soltar encerra o stroke: rxCurrentStroke volta a null.
        await gesture.up();
        await tester.pump();

        expect(
          rxCurrentStroke.value,
          isNull,
          reason: 'soltar deve encerrar o stroke em progresso',
        );
      }
    });

    testWidgets('o balde emite o stroke sem fillPixels', (tester) async {
      // O preenchimento pode ter dezenas de milhares de pixels; mandá-lo pela
      // rede derrubaria a conexão. Cada peer recalcula localmente.
      await tester.pumpWidget(const _Harness(tool: DrawingTool.bucket));

      await tester.tapAt(tester.getCenter(find.byType(DrawingCanvas)));
      await tester.pump();

      final payload = gateway.lastEmittedOn(SocketEvents.drawingStrokeStart);
      final stroke = payload!['stroke']! as Map<String, dynamic>;

      expect(stroke['strokeType'], StrokeType.bucket.name);
      expect(stroke['fillPixels'], isEmpty);
    });

    testWidgets('o balde aparece na hora, já com os pixels calculados', (
      tester,
    ) async {
      final rxAllStrokes = ValueNotifier<List<Stroke>>([]);
      await tester.pumpWidget(
        _Harness(tool: DrawingTool.bucket, rxAllStrokes: rxAllStrokes),
      );

      await tester.tapAt(tester.getCenter(find.byType(DrawingCanvas)));
      await tester.pump();

      final bucket = rxAllStrokes.value.single as BucketStroke;
      final wholeCanvas = DrawingCanvas.logicalSize.width.ceil() *
          DrawingCanvas.logicalSize.height.ceil();
      expect(bucket.fillPixels, hasLength(wholeCanvas));
    });

    testWidgets('o eco do próprio balde não duplica o stroke', (tester) async {
      final rxAllStrokes = ValueNotifier<List<Stroke>>([]);
      await tester.pumpWidget(
        _Harness(tool: DrawingTool.bucket, rxAllStrokes: rxAllStrokes),
      );
      await tester.tapAt(tester.getCenter(find.byType(DrawingCanvas)));
      await tester.pump();
      final sent = gateway.lastEmittedOn(SocketEvents.drawingStrokeStart)!;

      gateway.emitServerEvent(SocketEvents.drawingStrokeStart, {
        'stroke': sent['stroke'],
      });
      await tester.pump();

      expect(rxAllStrokes.value, hasLength(1));
      final bucket = rxAllStrokes.value.single as BucketStroke;
      expect(bucket.fillPixels, isNotEmpty);
    });

    testWidgets(
        'o eco do balde preserva o stroke de outro peer que chegou antes',
        (tester) async {
      final rxAllStrokes = ValueNotifier<List<Stroke>>([]);
      await tester.pumpWidget(
        _Harness(tool: DrawingTool.bucket, rxAllStrokes: rxAllStrokes),
      );
      await tester.tapAt(tester.getCenter(find.byType(DrawingCanvas)));
      await tester.pump();
      final sent = gateway.lastEmittedOn(SocketEvents.drawingStrokeStart)!;

      gateway
        ..emitServerEvent(SocketEvents.drawingStrokeStart, {
          'stroke': StrokeFixtures.normal().toJson(),
        })
        ..emitServerEvent(SocketEvents.drawingStrokeStart, {
          'stroke': sent['stroke'],
        });
      await tester.pump();

      expect(rxAllStrokes.value, hasLength(2));
      expect(rxAllStrokes.value.first, isA<BucketStroke>());
      expect(rxAllStrokes.value.last, isA<NormalStroke>());
    });
  });

  group('sincronização — eventos do servidor', () {
    testWidgets('drawing:stroke:all substitui os strokes do canvas', (
      tester,
    ) async {
      final rxAllStrokes = ValueNotifier<List<Stroke>>([]);
      await tester.pumpWidget(_Harness(rxAllStrokes: rxAllStrokes));

      gateway.emitServerEvent(SocketEvents.drawingStrokeAll, {
        'strokes': [
          StrokeFixtures.normal().toJson(),
          StrokeFixtures.line().toJson(),
        ],
      });
      await tester.pump();

      expect(rxAllStrokes.value, hasLength(2));
      expect(rxAllStrokes.value.first, isA<NormalStroke>());
      expect(rxAllStrokes.value.last, isA<LineStroke>());
    });

    testWidgets('drawing:stroke:start anexa o stroke recebido', (tester) async {
      final rxAllStrokes = ValueNotifier<List<Stroke>>([]);
      await tester.pumpWidget(_Harness(rxAllStrokes: rxAllStrokes));

      gateway.emitServerEvent(SocketEvents.drawingStrokeStart, {
        'stroke': StrokeFixtures.normal().toJson(),
      });
      await tester.pump();

      expect(rxAllStrokes.value, hasLength(1));
    });

    testWidgets('balde de outro peer chega sem pixels e é preenchido aqui', (
      tester,
    ) async {
      final rxAllStrokes = ValueNotifier<List<Stroke>>([]);
      await tester.pumpWidget(_Harness(rxAllStrokes: rxAllStrokes));

      gateway.emitServerEvent(SocketEvents.drawingStrokeStart, {
        'stroke': StrokeFixtures.bucket().toJson(),
      });
      await tester.pump();

      final bucket = rxAllStrokes.value.single as BucketStroke;
      expect(bucket.fillPixels, isNotEmpty);
    });

    testWidgets('drawing:stroke:all recalcula cada balde contra os anteriores',
        (
      tester,
    ) async {
      final rxAllStrokes = ValueNotifier<List<Stroke>>([]);
      await tester.pumpWidget(_Harness(rxAllStrokes: rxAllStrokes));
      final circle = StrokeFixtures.circle(
        points: const [Offset(150, 40), Offset(350, 240)],
      );
      final insideCircle =
          StrokeFixtures.bucket(points: const [Offset(250, 140)]);

      gateway.emitServerEvent(SocketEvents.drawingStrokeAll, {
        'strokes': [circle.toJson(), insideCircle.toJson()],
      });
      await tester.pump();

      final bucket = rxAllStrokes.value.last as BucketStroke;
      final wholeCanvas = DrawingCanvas.logicalSize.width.ceil() *
          DrawingCanvas.logicalSize.height.ceil();
      expect(bucket.fillPixels, isNotEmpty);
      expect(
        bucket.fillPixels.length,
        lessThan(wholeCanvas),
        reason: 'o círculo que veio antes limita o preenchimento',
      );
    });

    testWidgets('drawing:stroke:lastPoints estende o último stroke', (
      tester,
    ) async {
      final rxAllStrokes = ValueNotifier<List<Stroke>>([
        StrokeFixtures.normal(points: const [Offset(10, 10)]),
      ]);
      await tester.pumpWidget(_Harness(rxAllStrokes: rxAllStrokes));

      gateway.emitServerEvent(SocketEvents.drawingStrokeLastPoints, {
        'strokeLastPoints': [
          {'dx': 20.0, 'dy': 20.0},
          {'dx': 30.0, 'dy': 30.0},
        ],
      });
      await tester.pump();

      expect(rxAllStrokes.value.single.points, hasLength(3));
    });

    testWidgets('lastPoints sem stroke anterior é ignorado', (tester) async {
      final rxAllStrokes = ValueNotifier<List<Stroke>>([]);
      await tester.pumpWidget(_Harness(rxAllStrokes: rxAllStrokes));

      gateway.emitServerEvent(SocketEvents.drawingStrokeLastPoints, {
        'strokeLastPoints': [
          {'dx': 1.0, 'dy': 1.0},
        ],
      });
      await tester.pump();

      expect(rxAllStrokes.value, isEmpty);
    });

    testWidgets('payload malformado não derruba o canvas', (tester) async {
      final rxAllStrokes = ValueNotifier<List<Stroke>>([]);
      await tester.pumpWidget(_Harness(rxAllStrokes: rxAllStrokes));

      gateway
        ..emitServerEvent(SocketEvents.drawingStrokeAll, {'strokes': 'lixo'})
        ..emitServerEvent(SocketEvents.drawingStrokeStart, {'stroke': 42})
        ..emitServerEvent(
          SocketEvents.drawingStrokeLastPoints,
          const <String, dynamic>{},
        );
      await tester.pump();

      expect(rxAllStrokes.value, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reconectar limpa o canvas para ressincronizar', (
      tester,
    ) async {
      final rxAllStrokes = ValueNotifier<List<Stroke>>([
        StrokeFixtures.normal(),
      ]);
      await tester.pumpWidget(_Harness(rxAllStrokes: rxAllStrokes));

      gateway.simulateConnect();
      await tester.pump();

      expect(rxAllStrokes.value, isEmpty);
    });
  });

  group('ciclo de vida', () {
    testWidgets('dispose remove todos os listeners registrados', (
      tester,
    ) async {
      await tester.pumpWidget(const _Harness());
      expect(gateway.totalListenerCount, greaterThan(0));

      await tester.pumpWidget(const SizedBox.shrink());

      expect(
        gateway.totalListenerCount,
        0,
        reason: 'nenhum listener pode sobreviver ao widget',
      );
    });
  });
}

/// Um caso de golden por forma geométrica.
final _shapeCases = [
  (
    description: 'triângulo',
    golden: 'triangle',
    tool: DrawingTool.polygon,
    stroke: StrokeFixtures.polygon(
      points: const [Offset(250, 30), Offset(250, 250)],
    ),
  ),
  (
    description: 'octógono',
    golden: 'octagon',
    tool: DrawingTool.polygon,
    stroke: StrokeFixtures.polygon(
      sides: 8,
      points: const [Offset(250, 30), Offset(250, 250)],
    ),
  ),
  (
    description: 'octógono preenchido',
    golden: 'octagon_fill',
    tool: DrawingTool.polygon,
    stroke: StrokeFixtures.polygon(
      sides: 8,
      filled: true,
      points: const [Offset(250, 30), Offset(250, 250)],
    ),
  ),
  (
    description: 'círculo',
    golden: 'circle',
    tool: DrawingTool.circle,
    stroke: StrokeFixtures.circle(
      points: const [Offset(150, 40), Offset(350, 240)],
    ),
  ),
  (
    description: 'círculo preenchido',
    golden: 'circle_fill',
    tool: DrawingTool.circle,
    stroke: StrokeFixtures.circle(
      filled: true,
      points: const [Offset(150, 40), Offset(350, 240)],
    ),
  ),
  (
    description: 'quadrado',
    golden: 'square',
    tool: DrawingTool.square,
    stroke: StrokeFixtures.square(
      points: const [Offset(150, 40), Offset(350, 240)],
    ),
  ),
  (
    description: 'quadrado preenchido',
    golden: 'square_fill',
    tool: DrawingTool.square,
    stroke: StrokeFixtures.square(
      filled: true,
      points: const [Offset(150, 40), Offset(350, 240)],
    ),
  ),
];

/// Monta um [DrawingCanvas] isolado, com os notifiers expostos ao teste.
class _Harness extends StatefulWidget {
  const _Harness({
    super.key,
    this.strokes = const [],
    this.tool = DrawingTool.pencil,
    this.showGrid = false,
    this.rxAllStrokes,
    this.rxCurrentStroke,
  });

  static const roomName = 'sala-de-teste';
  static const username = 'kevin';

  final List<Stroke> strokes;
  final DrawingTool tool;
  final bool showGrid;
  final ValueNotifier<List<Stroke>>? rxAllStrokes;
  final CurrentStrokeValueNotifier? rxCurrentStroke;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late final ValueNotifier<List<Stroke>> _rxAllStrokes;
  late final CurrentStrokeValueNotifier _rxCurrentStroke;

  @override
  void initState() {
    super.initState();
    _rxAllStrokes =
        widget.rxAllStrokes ?? ValueNotifier<List<Stroke>>(widget.strokes);
    if (widget.rxAllStrokes != null && widget.strokes.isNotEmpty) {
      _rxAllStrokes.value = widget.strokes;
    }
    _rxCurrentStroke = widget.rxCurrentStroke ?? CurrentStrokeValueNotifier();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        // O painter repinta por conta própria (Listenable.merge no repaint),
        // mas o AnimatedBuilder replica como o DrawingBoard real compõe.
        body: AnimatedBuilder(
          animation: Listenable.merge([_rxAllStrokes, _rxCurrentStroke]),
          builder: (context, _) {
            return DrawingCanvas(
              canvasGlobalKey: GlobalKey(),
              rxCurrentStroke: _rxCurrentStroke,
              rxAllStrokes: _rxAllStrokes,
              options: DrawingCanvasOptions(
                currentTool: widget.tool,
                showGrid: widget.showGrid,
              ),
              username: _Harness.username,
              roomName: _Harness.roomName,
            );
          },
        ),
      ),
    );
  }
}
