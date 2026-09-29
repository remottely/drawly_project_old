import 'package:drawing_board/drawing_board.dart';
import 'package:drawly_design_system/drawly_design_system.dart';
import 'package:flutter/material.dart';

/// Fixtures determinísticas de [Stroke], compartilhadas por toda a suíte.
///
/// Fonte única: um teste que precise de um stroke pega daqui, nunca monta o
/// seu. Assim, mudar o formato de serialização quebra em um lugar só.
abstract final class StrokeFixtures {
  /// Dois pontos em diagonal — suficiente para exercitar qualquer forma.
  static const points = [Offset(10, 10), Offset(40, 40)];

  /// Cópia mutável de uma lista de pontos.
  ///
  /// `Stroke.points` é `final`, mas o conteúdo é mutado no lugar pelo handler de
  /// `drawing:stroke:lastPoints` (`..last.points.addAll(...)`). Passar uma lista
  /// `const` para uma fixture faria o teste falhar com UnsupportedError por um
  /// motivo que não existe em produção — lá a lista sempre nasce de um
  /// `List<Offset>.from(...)` no `fromJson`.
  static List<Offset> _growable(List<Offset>? points) =>
      List<Offset>.from(points ?? StrokeFixtures.points);

  static const color = Colors.black;
  static const size = 4.0;
  static const opacity = 1.0;

  static NormalStroke normal({List<Offset>? points, Color? color}) =>
      NormalStroke(
        points: _growable(points),
        color: color ?? StrokeFixtures.color,
        size: size,
        opacity: opacity,
      );

  static EraserStroke eraser({List<Offset>? points}) => EraserStroke(
        points: _growable(points),
        color: color,
        size: size,
        opacity: opacity,
      );

  static LineStroke line({List<Offset>? points}) => LineStroke(
        points: _growable(points),
        color: color,
        size: size,
        opacity: opacity,
      );

  static PolygonStroke polygon({
    int sides = 3,
    bool filled = false,
    List<Offset>? points,
  }) =>
      PolygonStroke(
        points: _growable(points),
        sides: sides,
        filled: filled,
        color: color,
        size: size,
        opacity: opacity,
      );

  static CircleStroke circle({bool filled = false, List<Offset>? points}) =>
      CircleStroke(
        points: _growable(points),
        filled: filled,
        color: color,
        size: size,
        opacity: opacity,
      );

  static SquareStroke square({bool filled = false, List<Offset>? points}) =>
      SquareStroke(
        points: _growable(points),
        filled: filled,
        color: color,
        size: size,
        opacity: opacity,
      );

  static BucketStroke bucket({
    List<Offset>? points,
    List<Offset> fillPixels = const [],
    Color? color,
  }) =>
      BucketStroke(
        points: _growable(points ?? const [Offset(20, 20)]),
        fillPixels: fillPixels,
        color: color ?? StrokeFixtures.color,
        size: size,
        opacity: opacity,
      );

  /// Um exemplar de cada tipo de stroke — usado nos testes que precisam varrer
  /// a hierarquia inteira (round-trip de JSON, por exemplo).
  static List<Stroke> get oneOfEach => [
        normal(),
        eraser(),
        line(),
        polygon(),
        circle(),
        square(),
        bucket(),
      ];

  /// JSON mínimo válido de um stroke, para montar variações em teste.
  static Map<String, dynamic> json({
    required String strokeType,
    List<Offset>? points,
  }) =>
      {
        'points': (points ?? StrokeFixtures.points)
            .map((point) => {'dx': point.dx, 'dy': point.dy})
            .toList(),
        'color': color.toJson(),
        'size': size,
        'opacity': opacity,
        'strokeType': strokeType,
      };
}
