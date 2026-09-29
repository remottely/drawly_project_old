import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:drawing_board/src/src.dart';
import 'package:drawly_core/drawly_core.dart';
import 'package:drawly_design_system/drawly_design_system.dart';
import 'package:flutter/material.dart';
import '../../util/polygon_utils.dart';

const double _canvasSize = 500;

/// Cache do [Path] de cada [BucketStroke], por identidade.
///
/// `BucketStroke.fillPixels` é imutável, então o path derivado vale enquanto o
/// stroke existir — e some com ele, sem precisar de invalidação.
final _bucketFillPaths = Expando<Path>('bucketFillPath');

class DrawingCanvas extends StatefulWidget {
  const DrawingCanvas({
    required this.rxAllStrokes,
    required this.rxCurrentStroke,
    required this.options,
    // this.onDrawingStrokeChanged,
    required this.canvasGlobalKey,
    required this.username,
    required this.roomName,
    super.key,
    // this.rxBackgroundImage,
  })  : assert(
          username.length >= 3,
          'The username must be at least 3 characters long',
        ),
        assert(
          roomName.length >= 3,
          'The roomName must be at least 3 characters long',
        );

  /// Tamanho lógico do canvas, em unidades de desenho (16:9).
  ///
  /// Todo stroke é expresso nessas unidades; a tela só aplica um
  /// `Transform.scale` por cima. É também a grade do balde de tinta.
  static const Size logicalSize = Size(_canvasSize, _canvasSize / (16 / 9));

  final ValueNotifier<List<Stroke>> rxAllStrokes;
  // final ValueNotifier<ui.Image?>? rxBackgroundImage;
  final CurrentStrokeValueNotifier rxCurrentStroke;
  final DrawingCanvasOptions options;
  // final Function(Stroke?)? onDrawingStrokeChanged;
  final GlobalKey canvasGlobalKey;
  final String username;
  final String roomName;

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

abstract class DrawingCanvasViewModel extends State<DrawingCanvas> {
  CurrentStrokeValueNotifier get rxCurrentStroke => widget.rxCurrentStroke;
  ValueNotifier<List<Stroke>> get rxAllStrokes => widget.rxAllStrokes;

  final int _bufferDelay = 50;
  List<Offset> _pendingPoints = [];

  /// Baldes aplicados localmente cujo eco do servidor ainda não chegou.
  ///
  /// O balde é desenhado na hora (com os pixels já calculados) e enviado sem
  /// eles. Quando o eco volta, é reconhecido pelos campos que atravessam a
  /// rede e descartado — o stroke local já está na lista, na posição certa.
  /// Remover "o último" ao receber o eco removia o stroke de outro peer que
  /// tivesse chegado no meio tempo.
  final _pendingBuckets = <BucketStroke>[];

  /// Timer que esvazia o buffer de pontos periodicamente.
  ///
  /// Guardado em campo para poder ser cancelado no [dispose]: sem isso cada
  /// instância do canvas deixava um timer vivo para sempre, emitindo no socket
  /// mesmo depois de a tela sair.
  Timer? _pointsBufferTimer;

  final rxIsShowGrid = ValueNotifier<bool>(false);
  Color get strokeColor => widget.options.strokeColor;
  double get size => widget.options.size;
  double get opacity => widget.options.opacity;
  DrawingTool get currentTool => widget.options.currentTool;

  late final void Function(dynamic) _onConnectEvent;
  late final void Function(dynamic) _onAllStrokesDrawingEvent;
  late final void Function(dynamic) _onStrokeStartDrawingEvent;
  late final void Function(dynamic) _onStrokeLastPointsDrawingEvent;

  @override
  void initState() {
    super.initState();
    _initializeSocket();
    _startDrawingPointsBuffer();
  }

  @override
  void dispose() {
    _pointsBufferTimer?.cancel();
    _pointsBufferTimer = null;
    SocketManager.instance.off(SocketEvents.connect, _onConnectEvent);
    SocketManager.instance
        .off(SocketEvents.drawingStrokeAll, _onAllStrokesDrawingEvent);
    SocketManager.instance
        .off(SocketEvents.drawingStrokeStart, _onStrokeStartDrawingEvent);
    SocketManager.instance.off(
        SocketEvents.drawingStrokeLastPoints, _onStrokeLastPointsDrawingEvent);
    super.dispose();
  }

  void _initializeSocket() {
    _onConnectEvent = (_) {
      rxAllStrokes.value = [];
    };

    _onAllStrokesDrawingEvent = (data) {
      try {
        final allStrokes =
            (data as Map<String, dynamic>)['strokes'] as List<dynamic>? ?? [];
        final parsedStrokes = <Stroke>[];
        for (final raw in allStrokes) {
          final stroke = Stroke.fromJson(
            Map<String, dynamic>.from(raw as Map<String, dynamic>),
          );
          parsedStrokes.add(_withFill(stroke, parsedStrokes));
        }

        rxAllStrokes.value = parsedStrokes;
      } catch (e, stackTrace) {
        developer.log(
          'Error processing drawing:stroke:all event: $e',
          error: e,
          stackTrace: stackTrace,
        );
      }
    };

    _onStrokeStartDrawingEvent = (data) {
      try {
        final newStroke =
            (data as Map<String, dynamic>)['stroke'] as Map<String, dynamic>?;
        if (newStroke == null) return;

        final receivedStroke =
            Stroke.fromJson(Map<String, dynamic>.from(newStroke));

        if (receivedStroke is BucketStroke &&
            _consumePendingEcho(receivedStroke)) {
          return;
        }

        rxAllStrokes.value = List<Stroke>.from(rxAllStrokes.value)
          ..add(_withFill(receivedStroke, rxAllStrokes.value));
      } catch (e, stackTrace) {
        developer.log(
          'Error processing drawing:stroke:start event: $e',
          error: e,
          stackTrace: stackTrace,
        );
      }
    };

    _onStrokeLastPointsDrawingEvent = (data) {
      try {
        final strokeLastPoints = (data
            as Map<String, dynamic>)['strokeLastPoints'] as List<dynamic>?;
        if (strokeLastPoints == null) return;

        final receivedStrokeLastPoints = strokeLastPoints
            .map(
              (point) => Offset(
                (point as Map<String, dynamic>)['dx'] as double,
                point['dy'] as double,
              ),
            )
            .toList();

        if (rxAllStrokes.value.isEmpty) return;

        rxAllStrokes.value = List<Stroke>.from(rxAllStrokes.value)
          ..last.points.addAll(
                receivedStrokeLastPoints.where(
                  (point) => !rxAllStrokes.value.last.points.contains(point),
                ),
              );
      } catch (e, stackTrace) {
        developer.log(
          'Error processing drawing:stroke:lastPoints event: $e',
          error: e,
          stackTrace: stackTrace,
        );
      }
    };

    SocketManager.instance.on(SocketEvents.connect, _onConnectEvent);
    SocketManager.instance
        .on(SocketEvents.drawingStrokeAll, _onAllStrokesDrawingEvent);
    SocketManager.instance
        .on(SocketEvents.drawingStrokeStart, _onStrokeStartDrawingEvent);
    SocketManager.instance.on(
        SocketEvents.drawingStrokeLastPoints, _onStrokeLastPointsDrawingEvent);
  }

  double _calculateScale(BoxConstraints constraints) {
    final availableWidth = constraints.maxWidth;
    final availableHeight = constraints.maxHeight;

    final canvasWidth = availableWidth;
    final canvasHeight = availableWidth / (16 / 9);

    if (canvasHeight > availableHeight) {
      return availableHeight / (9 * (_canvasSize / 16));
    } else {
      return canvasWidth / _canvasSize;
    }
  }

  bool _isPointInsideCanvas(Offset point) {
    const canvasWidth = _canvasSize;
    const canvasHeight = _canvasSize / (16 / 9);

    return point.dx >= 0 &&
        point.dx <= canvasWidth &&
        point.dy >= 0 &&
        point.dy <= canvasHeight;
  }

  /// Starts a periodic timer to send points to the server
  void _startDrawingPointsBuffer() {
    _pointsBufferTimer = Timer.periodic(
      Duration(milliseconds: _bufferDelay),
      (_) => _sendBufferedDrawingPoints(),
    );
  }

  void _applyBucketFill(Offset position, double scale) {
    final stroke = BucketStroke(
      points: [position],
      color: strokeColor,
      size: size / scale,
      opacity: opacity,
      fillPixels: _computeFill(position, rxAllStrokes.value),
    );

    rxAllStrokes.value = List<Stroke>.from(rxAllStrokes.value)..add(stroke);
    _pendingBuckets.add(stroke);

    // O servidor recebe o balde sem os pixels: um preenchimento pode ter
    // dezenas de milhares deles, e o payload derrubaria a conexão. Cada peer
    // recalcula a partir da mesma lista de strokes.
    final payload = RoomDrawingStartStrokeDTO(
      roomName: widget.roomName,
      stroke: stroke.copyWith(fillPixels: const []),
    ).toJson();
    SocketManager.instance.emit(SocketEvents.drawingStrokeStart, payload);
  }

  List<Offset> _computeFill(Offset start, List<Stroke> strokes) => bucketFill(
        start: start,
        strokes: strokes,
        canvasSize: DrawingCanvas.logicalSize,
        backgroundColor: widget.options.backgroundColor,
      );

  /// Um balde que chegou pela rede sem pixels é preenchido aqui, contra os
  /// strokes que o antecedem em [previous]. Qualquer outro stroke passa direto.
  Stroke _withFill(Stroke stroke, List<Stroke> previous) {
    if (stroke is! BucketStroke || stroke.fillPixels.isNotEmpty) return stroke;
    return stroke.copyWith(
      fillPixels: _computeFill(stroke.points.first, previous),
    );
  }

  /// Reconhece o eco de um balde aplicado localmente e o retira da fila.
  ///
  /// Compara só o que atravessa a rede (ponto, cor, tamanho, opacidade): os
  /// pixels são descartados antes do envio.
  bool _consumePendingEcho(BucketStroke echo) {
    final index = _pendingBuckets.indexWhere(
      (pending) =>
          pending.points.first == echo.points.first &&
          pending.color.toARGB32() == echo.color.toARGB32() &&
          pending.size == echo.size &&
          pending.opacity == echo.opacity,
    );
    if (index < 0) return false;
    _pendingBuckets.removeAt(index);
    return true;
  }

  void _sendDrawingPointsStart() {
    if (rxCurrentStroke.value == null) return;

    final payload = RoomDrawingStartStrokeDTO(
      roomName: widget.roomName,
      stroke: rxCurrentStroke.value!,
    ).toJson();

    SocketManager.instance.emit(SocketEvents.drawingStrokeStart, payload);
    _pendingPoints.clear();
  }

  void _sendDrawingPointsEnd() {
    if (rxCurrentStroke.value?.points == null) return;

    rxCurrentStroke.clear();
    _pendingPoints.clear();
  }

  void _sendBufferedDrawingPoints() {
    if (_pendingPoints.isEmpty) {
      return;
    }

    final payload = RoomDrawingStrokePointsDTO(
      roomName: widget.roomName,
      strokeLastPoints: _pendingPoints,
    ).toJson();

    SocketManager.instance.emit(SocketEvents.drawingStrokeLastPoints, payload);
    _pendingPoints.clear();
  }
}

class _DrawingCanvasState extends DrawingCanvasViewModel {
  @override
  Widget build(BuildContext context) {
    rxIsShowGrid.value = widget.options.showGrid;

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = _calculateScale(constraints);

        return Transform.scale(
          scale: scale,
          child: Center(
            child: DrawlyContainer(
              color: widget.options.backgroundColor,
              width: _canvasSize,
              height: _canvasSize / (16 / 9),
              child: MouseRegion(
                cursor: widget.options.currentTool.cursor,
                child: Listener(
                  onPointerDown: (details) {
                    final localPosition = details.localPosition;
                    if (_isPointInsideCanvas(localPosition)) {
                      // rxCurrentStroke.startStroke(
                      //   localPosition,
                      //   color: strokeColor,
                      //   size: size / scale, // TODO(Kevin): NOW
                      //   opacity: opacity,
                      //   type: currentTool.strokeType,
                      //   sides: widget.options.polygonSides,
                      //   filled: widget.options.fillShape,
                      // );
                      // _sendDrawingPointsStart();
                      // // rxAllStrokes.value = List<Stroke>.from(rxAllStrokes.value)
                      // //   ..last.points.add(localPosition);
                      // // widget.onDrawingStrokeChanged?
                      // // .call(rxCurrentStroke.value);
                      if (currentTool.isBucket) {
                        _applyBucketFill(localPosition, scale);
                      } else {
                        rxCurrentStroke.startStroke(
                          localPosition,
                          color: strokeColor,
                          size: size / scale,
                          opacity: opacity,
                          type: currentTool.strokeType,
                          sides: widget.options.polygonSides,
                          filled: widget.options.fillShape,
                        );
                        _pendingPoints = [localPosition];
                        _sendDrawingPointsStart();
                      }
                    }
                  },
                  onPointerMove: (details) {
                    final localPosition = details.localPosition;
                    if (_isPointInsideCanvas(localPosition)) {
                      if (currentTool.isBucket) {
                        return;
                      } else {
                        rxCurrentStroke.addPoint(localPosition);
                        _pendingPoints.add(localPosition);
                      }
                      // widget.onDrawingStrokeChanged?
                      // .call(rxCurrentStroke.value);
                    }
                  },
                  onPointerUp: (_) {
                    if (!currentTool.isBucket) {
                      _sendBufferedDrawingPoints();
                      _sendDrawingPointsEnd();
                    }
                    // if (rxCurrentStroke.hasStroke) {
                    //   _sendBufferedDrawingPoints();
                    //   // widget.onDrawingStrokeChanged?.call(null);
                    // }
                  },
                  child: RepaintBoundary(
                    key: widget.canvasGlobalKey,
                    child: CustomPaint(
                      isComplex: true,
                      painter: _DrawingCanvasPainter(
                        rxAllStrokes: rxAllStrokes,
                        rxCurrentStroke: rxCurrentStroke,
                        backgroundColor: widget.options.backgroundColor,
                        rxIsShowGrid: rxIsShowGrid,
                        // rxBackgroundImage: widget.rxBackgroundImage,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DrawingCanvasPainter extends CustomPainter {
  _DrawingCanvasPainter({
    this.rxAllStrokes,
    this.rxCurrentStroke,
    this.backgroundColor = Colors.white,
    this.rxIsShowGrid,
    // this.rxBackgroundImage,
  }) : super(
          repaint: Listenable.merge(
            [
              rxAllStrokes,
              rxCurrentStroke,
              rxIsShowGrid,
              // rxBackgroundImage,
            ],
          ),
        );
  final ValueNotifier<List<Stroke>>? rxAllStrokes;
  final CurrentStrokeValueNotifier? rxCurrentStroke;
  final Color backgroundColor;
  final ValueNotifier<bool>? rxIsShowGrid;
  // final ValueNotifier<ui.Image?>? rxBackgroundImage;

  @override
  void paint(Canvas canvas, Size size) {
    // if (rxBackgroundImage != null) {
    //   final backgroundImage = rxBackgroundImage!.value;

    //   if (backgroundImage != null) {
    //     canvas.drawImageRect(
    //       backgroundImage,
    //       Rect.fromLTWH(
    //         0,
    //         0,
    //         backgroundImage.width.toDouble(),
    //         backgroundImage.height.toDouble(),
    //       ),
    //       Rect.fromLTWH(0, 0, size.width, size.height),
    //       Paint(),
    //     );
    //   }
    // }

    final allStrokes = List<Stroke>.from(rxAllStrokes?.value ?? []);

    if (rxCurrentStroke?.hasStroke ?? false) {
      // TODO(Kevin): do something here?
      // allStrokes.add(rxCurrentStroke!.value!);
    }

    for (final stroke in allStrokes) {
      if (stroke.points.isEmpty) continue;

      final paint = Paint()
        ..color = stroke.color.applyOpacity(stroke.opacity)
        ..strokeWidth = stroke.size
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (stroke is NormalStroke) {
        if (stroke.points.length == 1) {
          final center = stroke.points.first;
          final radius = stroke.size / 2;
          canvas.drawCircle(center, radius, paint..style = PaintingStyle.fill);
        } else {
          final path = Path()
            ..moveTo(stroke.points.first.dx, stroke.points.first.dy);
          for (var i = 1; i < stroke.points.length; i++) {
            path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
          }
          canvas.drawPath(path, paint);
        }
      }

      if (stroke is EraserStroke) {
        final eraserPaint = Paint()
          ..color = backgroundColor
          ..strokeWidth = stroke.size
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;

        final path = Path()
          ..moveTo(stroke.points.first.dx, stroke.points.first.dy);
        for (var i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
        }
        canvas.drawPath(path, eraserPaint);
      }

      if (stroke is LineStroke) {
        if (stroke.points.length >= 2) {
          final firstPoint = stroke.points.first;
          final lastPoint = stroke.points.last;
          canvas.drawLine(firstPoint, lastPoint, paint);
        }
      }

      if (stroke is CircleStroke) {
        if (stroke.points.length >= 2) {
          final firstPoint = stroke.points.first;
          final lastPoint = stroke.points.last;
          final rect = Rect.fromPoints(firstPoint, lastPoint);
          paint.style =
              stroke.filled ? PaintingStyle.fill : PaintingStyle.stroke;
          canvas.drawOval(rect, paint);
        }
      }

      if (stroke is SquareStroke) {
        if (stroke.points.length >= 2) {
          final firstPoint = stroke.points.first;
          final lastPoint = stroke.points.last;
          final rect = Rect.fromPoints(firstPoint, lastPoint);
          paint.style =
              stroke.filled ? PaintingStyle.fill : PaintingStyle.stroke;
          canvas.drawRect(rect, paint);
        }
      }

      if (stroke is PolygonStroke) {
        if (stroke.points.length >= 2) {
          final firstPoint = stroke.points.first;
          final lastPoint = stroke.points.last;
          final center = Offset(
            (firstPoint.dx + lastPoint.dx) / 2,
            (firstPoint.dy + lastPoint.dy) / 2,
          );
          final radius = calculateClampedPolygonRadius(
            firstPoint: firstPoint,
            lastPoint: lastPoint,
            canvasSize: size,
          );
          final path = Path();
          final angleStep = (2 * pi) / stroke.sides;
          const startAngle = -pi / 2;

          path.moveTo(
            center.dx + radius * cos(startAngle),
            center.dy + radius * sin(startAngle),
          );

          for (var i = 1; i <= stroke.sides; i++) {
            final angle = startAngle + i * angleStep;
            final x = center.dx + radius * cos(angle);
            final y = center.dy + radius * sin(angle);
            path.lineTo(x, y);
          }

          path.close();
          paint.style =
              stroke.filled ? PaintingStyle.fill : PaintingStyle.stroke;
          canvas.drawPath(path, paint);
        }
      }

      if (stroke is BucketStroke) {
        // Um path por balde, cacheado por identidade do stroke: desenhar um
        // retângulo por pixel a cada frame travava o app em preenchimentos
        // grandes — o painter repinta a cada movimento do ponteiro.
        paint
          ..style = PaintingStyle.fill
          ..isAntiAlias = false;
        canvas.drawPath(
          _bucketFillPaths[stroke] ??= bucketFillPath(stroke.fillPixels),
          paint,
        );
      }
    }

    if (rxIsShowGrid?.value ?? false) {
      drawGrid(size, canvas);
    }
  }

  void drawGrid(Size size, Canvas canvas) {
    const gridStrokeWidth = 1.0;
    const gridSpacing = 50.0;
    const subGridSpacing = 10.0;
    const subGridStrokeWidth = 0.5;

    final gridPaint = Paint()
      ..color = Colors.red.applyOpacity(0.2)
      ..strokeWidth = gridStrokeWidth;

    final subGridPaint = Paint()
      ..color = Colors.red.applyOpacity(0.2)
      ..strokeWidth = subGridStrokeWidth;

    for (var y = 0.0; y <= size.height; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (var x = 0.0; x <= size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    for (var y = 0.0; y <= size.height; y += gridSpacing) {
      for (var subY = y;
          subY < y + gridSpacing && subY <= size.height;
          subY += subGridSpacing) {
        canvas.drawLine(
          Offset(0, subY),
          Offset(size.width, subY),
          subGridPaint,
        );
      }
    }

    for (var x = 0.0; x <= size.width; x += gridSpacing) {
      for (var subX = x;
          subX < x + gridSpacing && subX <= size.width;
          subX += subGridSpacing) {
        canvas.drawLine(
          Offset(subX, 0),
          Offset(subX, size.height),
          subGridPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
