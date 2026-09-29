import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:drawing_board/src/domain/models/stroke.dart';
import 'package:drawing_board/src/util/polygon_utils.dart';
import 'package:drawly_design_system/drawly_design_system.dart';

/// Preenchimento do balde de tinta.
///
/// O canvas é tratado como uma grade de `width × height` células. A célula
/// `(x, y)` cobre o quadrado `[x, x+1) × [y, y+1)` — exatamente o retângulo que
/// o painter desenha para ela. Cada stroke é rasterizado amostrando o
/// **centro** da célula, `(x + 0.5, y + 0.5)`, contra a geometria que o
/// painter pinta:
///
/// * contorno (lápis, linha, borracha, formas vazadas): cápsula de raio
///   `size / 2` em volta de cada segmento — é o que `StrokeCap.round` +
///   `StrokeJoin.round` produzem;
/// * formas preenchidas: o interior da forma, sem contorno — o painter usa
///   `PaintingStyle.fill`, que não tem espessura;
/// * balde anterior: cada pixel preenchido, sem dilatação.
///
/// Amostrar no centro é o que casa o raster com o render anti-aliased: célula
/// coberta em mais da metade lê como borda, o resto lê como fundo. É isso que
/// leva o preenchimento até a borda sem fresta e sem invadir o traço.
///
/// O preenchimento em si é um flood fill **4-conexo** por scanline a partir de
/// [start], sobre as células com a mesma cor da célula inicial. A conexão de 4
/// é deliberada: uma linha fina em diagonal é uma cadeia de células adjacentes
/// só pela quina, e um fill 8-conexo atravessa essa cadeia.
///
/// [backgroundColor] é a cor das células que nenhum stroke pintou e a cor que a
/// borracha pinta — o mesmo papel que tem no painter. Clique fora do canvas
/// devolve lista vazia.
List<Offset> bucketFill({
  required Offset start,
  required List<Stroke> strokes,
  required Size canvasSize,
  Color backgroundColor = const Color(0x00000000),
}) {
  final width = canvasSize.width.ceil();
  final height = canvasSize.height.ceil();
  if (width <= 0 || height <= 0) return const [];

  final startX = start.dx.floor();
  final startY = start.dy.floor();
  if (startX < 0 || startY < 0 || startX >= width || startY >= height) {
    return const [];
  }

  final raster = _Raster(width, height, backgroundColor.toARGB32());
  for (final stroke in strokes) {
    raster.paint(stroke, canvasSize, backgroundColor);
  }
  return raster.floodFill(startX, startY);
}

/// Agrupa [pixels] em faixas horizontais de células consecutivas.
///
/// Cada [Rect] devolvido tem altura 1 e cobre `[x0, x1 + 1)` numa linha. Um
/// preenchimento de dezenas de milhares de pixels vira algumas centenas de
/// faixas, o que é o que torna viável desenhá-lo em uma única chamada.
List<Rect> bucketFillRuns(List<Offset> pixels) {
  final rows = <int, List<int>>{};
  for (final p in pixels) {
    (rows[p.dy.floor()] ??= []).add(p.dx.floor());
  }

  final runs = <Rect>[];
  for (final y in rows.keys.toList()..sort()) {
    final xs = rows[y]!..sort();
    var runStart = xs.first;
    var previous = runStart;
    for (var i = 1; i < xs.length; i++) {
      final x = xs[i];
      if (x <= previous + 1) {
        previous = x;
        continue;
      }
      runs.add(_run(runStart, previous, y));
      runStart = x;
      previous = x;
    }
    runs.add(_run(runStart, previous, y));
  }
  return runs;
}

/// O [Path] que o painter desenha para um [BucketStroke]: a união das faixas
/// de [bucketFillRuns].
Path bucketFillPath(List<Offset> pixels) {
  final path = Path();
  for (final run in bucketFillRuns(pixels)) {
    path.addRect(run);
  }
  return path;
}

Rect _run(int x0, int x1, int y) => Rect.fromLTWH(
      x0.toDouble(),
      y.toDouble(),
      (x1 - x0 + 1).toDouble(),
      1,
    );

/// Raio mínimo de um contorno.
///
/// Abaixo de meio pixel o Skia ainda pinta a linha (com cobertura parcial),
/// mas nenhum centro de célula estaria a menos de `size / 2` dela — o fill
/// atravessaria uma linha visível. Meio pixel garante que toda linha visível
/// marque ao menos uma célula por coluna/linha que cruza.
const double _minRadius = 0.5;

/// Segmentos mais longos que isso são fatiados antes de rasterizar, para que a
/// caixa envolvente de cada fatia fique pequena. A união das fatias (cada uma
/// com pontas redondas) é exatamente a cápsula inteira.
const double _chunkLength = 16;

final class _Raster {
  _Raster(this.width, this.height, int background)
      : cells = Uint32List(width * height)
          ..fillRange(0, width * height, background);

  final int width;
  final int height;

  /// Cor ARGB de cada célula, em row-major.
  final Uint32List cells;

  void paint(Stroke stroke, Size canvasSize, Color background) {
    final argb = stroke is EraserStroke
        ? background.toARGB32()
        : stroke.color.applyOpacity(stroke.opacity).toARGB32();
    final radius = max(stroke.size / 2, _minRadius);
    final points = stroke.points;

    if (stroke is BucketStroke) {
      for (final p in stroke.fillPixels) {
        _set(p.dx.floor(), p.dy.floor(), argb);
      }
      return;
    }

    if (stroke is LineStroke) {
      if (points.length >= 2) _capsule(points.first, points.last, radius, argb);
      return;
    }

    if (stroke is CircleStroke) {
      if (points.length < 2) return;
      final rect = Rect.fromPoints(points.first, points.last);
      if (stroke.filled) {
        _fillEllipse(rect, argb);
      } else {
        _polyline(_ellipseOutline(rect), radius, argb);
      }
      return;
    }

    if (stroke is SquareStroke) {
      if (points.length < 2) return;
      final rect = Rect.fromPoints(points.first, points.last);
      final corners = [
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft,
        rect.topLeft,
      ];
      if (stroke.filled) {
        _fillPolygon(corners, argb);
      } else {
        _polyline(corners, radius, argb);
      }
      return;
    }

    if (stroke is PolygonStroke) {
      if (points.length < 2) return;
      final vertices = _polygonOutline(stroke, canvasSize);
      if (stroke.filled) {
        _fillPolygon(vertices, argb);
      } else {
        _polyline(vertices, radius, argb);
      }
      return;
    }

    if (stroke is EraserStroke) {
      // O painter desenha a borracha como um path; um path só com `moveTo`
      // não tem nada para traçar.
      if (points.length >= 2) _polyline(points, radius, argb);
      return;
    }

    // Lápis (e qualquer stroke sem tratamento especial): um ponto vira um
    // disco, dois ou mais viram um path com pontas e junções redondas.
    if (points.length == 1) {
      _capsule(points.first, points.first, radius, argb);
    } else {
      _polyline(points, radius, argb);
    }
  }

  /// Flood fill 4-conexo por scanline a partir da célula `(sx, sy)`.
  List<Offset> floodFill(int sx, int sy) {
    final target = cells[sy * width + sx];
    final visited = Uint8List(width * height);
    final filled = <Offset>[];
    final seeds = <int>[sy * width + sx];

    bool matches(int index) => visited[index] == 0 && cells[index] == target;

    while (seeds.isNotEmpty) {
      final seed = seeds.removeLast();
      if (!matches(seed)) continue;

      final y = seed ~/ width;
      final row = y * width;
      var x0 = seed - row;
      var x1 = x0;
      while (x0 > 0 && matches(row + x0 - 1)) {
        x0--;
      }
      while (x1 < width - 1 && matches(row + x1 + 1)) {
        x1++;
      }

      for (var x = x0; x <= x1; x++) {
        visited[row + x] = 1;
        filled.add(Offset(x.toDouble(), y.toDouble()));
      }

      for (final ny in [y - 1, y + 1]) {
        if (ny < 0 || ny >= height) continue;
        final neighbourRow = ny * width;
        var inRun = false;
        for (var x = x0; x <= x1; x++) {
          final match = matches(neighbourRow + x);
          if (match && !inRun) seeds.add(neighbourRow + x);
          inRun = match;
        }
      }
    }
    return filled;
  }

  void _set(int x, int y, int argb) {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    cells[y * width + x] = argb;
  }

  void _polyline(List<Offset> points, double radius, int argb) {
    for (var i = 0; i < points.length - 1; i++) {
      _capsule(points[i], points[i + 1], radius, argb);
    }
  }

  /// Marca toda célula cujo centro está a até [radius] do segmento `a → b`.
  void _capsule(Offset a, Offset b, double radius, int argb) {
    final chunks = max(1, ((b - a).distance / _chunkLength).ceil());
    for (var i = 0; i < chunks; i++) {
      _capsuleChunk(
        Offset.lerp(a, b, i / chunks)!,
        Offset.lerp(a, b, (i + 1) / chunks)!,
        radius,
        argb,
      );
    }
  }

  void _capsuleChunk(Offset a, Offset b, double radius, int argb) {
    // Célula x tem centro x + 0.5; está a até `radius` do segmento só se
    // x + 0.5 ∈ [min - radius, max + radius].
    final minX = max(0, (min(a.dx, b.dx) - radius - 0.5).floor());
    final maxX = min(width - 1, (max(a.dx, b.dx) + radius - 0.5).ceil());
    final minY = max(0, (min(a.dy, b.dy) - radius - 0.5).floor());
    final maxY = min(height - 1, (max(a.dy, b.dy) + radius - 0.5).ceil());

    final abx = b.dx - a.dx;
    final aby = b.dy - a.dy;
    final length2 = abx * abx + aby * aby;
    final radius2 = radius * radius;

    for (var y = minY; y <= maxY; y++) {
      final cy = y + 0.5;
      for (var x = minX; x <= maxX; x++) {
        final cx = x + 0.5;
        var t = 0.0;
        if (length2 > 0) {
          t = (((cx - a.dx) * abx + (cy - a.dy) * aby) / length2).clamp(0, 1);
        }
        final dx = cx - (a.dx + t * abx);
        final dy = cy - (a.dy + t * aby);
        if (dx * dx + dy * dy <= radius2) cells[y * width + x] = argb;
      }
    }
  }

  /// Marca toda célula cujo centro está dentro da elipse inscrita em [rect].
  void _fillEllipse(Rect rect, int argb) {
    final rx = rect.width / 2;
    final ry = rect.height / 2;
    if (rx <= 0 || ry <= 0) return;
    final center = rect.center;

    final minX = max(0, (rect.left - 0.5).ceil());
    final maxX = min(width - 1, (rect.right - 0.5).floor());
    final minY = max(0, (rect.top - 0.5).ceil());
    final maxY = min(height - 1, (rect.bottom - 0.5).floor());

    for (var y = minY; y <= maxY; y++) {
      final ny = (y + 0.5 - center.dy) / ry;
      for (var x = minX; x <= maxX; x++) {
        final nx = (x + 0.5 - center.dx) / rx;
        if (nx * nx + ny * ny <= 1) cells[y * width + x] = argb;
      }
    }
  }

  /// Marca toda célula cujo centro está dentro do polígono (par-ímpar), por
  /// scanline. [vertices] pode ou não repetir o primeiro vértice no fim.
  void _fillPolygon(List<Offset> vertices, int argb) {
    if (vertices.length < 3) return;

    var top = double.infinity;
    var bottom = double.negativeInfinity;
    for (final v in vertices) {
      top = min(top, v.dy);
      bottom = max(bottom, v.dy);
    }
    final minY = max(0, (top - 0.5).ceil());
    final maxY = min(height - 1, (bottom - 0.5).floor());

    final crossings = <double>[];
    for (var y = minY; y <= maxY; y++) {
      final cy = y + 0.5;
      crossings.clear();
      for (var i = 0; i < vertices.length; i++) {
        final p = vertices[i];
        final q = vertices[(i + 1) % vertices.length];
        if ((p.dy <= cy) == (q.dy <= cy)) continue;
        crossings.add(p.dx + (cy - p.dy) * (q.dx - p.dx) / (q.dy - p.dy));
      }
      crossings.sort();
      for (var i = 0; i + 1 < crossings.length; i += 2) {
        final x0 = max(0, (crossings[i] - 0.5).ceil());
        final x1 = min(width - 1, (crossings[i + 1] - 0.5).floor());
        for (var x = x0; x <= x1; x++) {
          cells[y * width + x] = argb;
        }
      }
    }
  }

  /// Contorno da elipse inscrita em [rect], como polilinha fechada com
  /// segmentos de cerca de um pixel — o erro de corda fica abaixo de 1/8 px.
  static List<Offset> _ellipseOutline(Rect rect) {
    final rx = rect.width / 2;
    final ry = rect.height / 2;
    final center = rect.center;
    final perimeter = 2 * pi * sqrt((rx * rx + ry * ry) / 2);
    final segments = max(perimeter.ceil(), 16);
    return [
      for (var i = 0; i <= segments; i++)
        Offset(
          center.dx + rx * cos(2 * pi * i / segments),
          center.dy + ry * sin(2 * pi * i / segments),
        ),
    ];
  }

  /// Vértices do polígono regular, com a mesma fórmula do painter (o primeiro
  /// vértice repetido no fim fecha o contorno, como faz `path.close()`).
  static List<Offset> _polygonOutline(PolygonStroke stroke, Size canvasSize) {
    final first = stroke.points.first;
    final last = stroke.points.last;
    final center = Offset((first.dx + last.dx) / 2, (first.dy + last.dy) / 2);
    final radius = calculateClampedPolygonRadius(
      firstPoint: first,
      lastPoint: last,
      canvasSize: canvasSize,
    );
    final angleStep = 2 * pi / stroke.sides;
    const startAngle = -pi / 2;
    return [
      for (var i = 0; i <= stroke.sides; i++)
        Offset(
          center.dx + radius * cos(startAngle + i * angleStep),
          center.dy + radius * sin(startAngle + i * angleStep),
        ),
    ];
  }
}
