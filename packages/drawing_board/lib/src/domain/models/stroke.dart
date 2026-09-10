import 'package:drawly_design_system/drawly_design_system.dart';
import 'package:flutter/material.dart';

abstract class Stroke {
  Stroke({
    required this.points,
    this.color = Colors.black,
    this.size = 1,
    this.opacity = 1,
    this.strokeType = StrokeType.normal,
  });

  factory Stroke.fromJson(Map<String, dynamic> json) {
    // final points = (json['points'] as List<dynamic>)
    //     .map(
    //       (point) =>
    //           Offset(
    //(point as List<dynamic>)[0] as double, point[1] as double),
    //     )
    //     .toList();
    final points = (json['points'] as List<dynamic>)
        .map(
          (point) => Offset(
            (point as Map<String, dynamic>)['dx'] as double,
            point['dy'] as double,
          ),
        )
        .toList();
    final color = ColorUtils.fromJson(json['color'] as Map<String, dynamic>);
    final size = double.parse(json['size'].toString());
    final opacity = double.parse(json['opacity'].toString());
    final strokeType = StrokeType.fromString(json['strokeType'] as String);

    switch (strokeType) {
      case StrokeType.normal:
        return NormalStroke(
          points: points,
          color: color,
          size: size,
          opacity: opacity,
        );
      case StrokeType.eraser:
        return EraserStroke(
          points: points,
          color: color,
          size: size,
          opacity: opacity,
        );
      case StrokeType.line:
        return LineStroke(
          points: points,
          color: color,
          size: size,
          opacity: opacity,
        );
      case StrokeType.polygon:
        return PolygonStroke(
          points: points,
          sides: (json['sides'] as int?) ?? 3,
          color: color,
          size: size,
          opacity: opacity,
          filled: (json['filled'] as bool?) ?? false,
        );
      case StrokeType.circle:
        return CircleStroke(
          points: points,
          color: color,
          size: size,
          opacity: opacity,
          filled: (json['filled'] as bool?) ?? false,
        );
      case StrokeType.square:
        return SquareStroke(
          points: points,
          color: color,
          size: size,
          opacity: opacity,
          filled: (json['filled'] as bool?) ?? false,
        );
      case StrokeType.bucket:
        final fillPixelsJson =
            (json['fillPixels'] as List<dynamic>?) ?? const <dynamic>[];
        final fillPixels = fillPixelsJson
            .map(
              (p) => Offset(
                (p as Map<String, dynamic>)['dx'] as double,
                p['dy'] as double,
              ),
            )
            .toList();

        return BucketStroke(
          points: points,
          color: color,
          size: size,
          opacity: opacity,
          fillPixels: fillPixels,
        );
    }
  }

  final List<Offset> points;
  final Color color;
  final double size;
  final double opacity;
  final StrokeType strokeType;
  final DateTime createdAt = DateTime.now();

  Stroke copyWith({
    List<Offset>? points,
    Color? color,
    double? size,
    double? opacity,
  });

  Map<String, dynamic> toJson();

  bool get isEraser => strokeType == StrokeType.eraser;
  bool get isLine => strokeType == StrokeType.line;
  bool get isNormal => strokeType == StrokeType.normal;
}

class NormalStroke extends Stroke {
  NormalStroke({
    required super.points,
    super.color,
    super.size,
    super.opacity,
  }) : super(strokeType: StrokeType.normal);

  @override
  NormalStroke copyWith({
    List<Offset>? points,
    Color? color,
    double? size,
    double? opacity,
  }) {
    return NormalStroke(
      points: points ?? this.points,
      color: color ?? this.color,
      size: size ?? this.size,
      opacity: opacity ?? this.opacity,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'points':
          points.map((point) => {'dx': point.dx, 'dy': point.dy}).toList(),
      'color': color.toJson(),
      'size': size,
      'opacity': opacity,
      'strokeType': strokeType.toString(),
    };
  }
}

class EraserStroke extends Stroke {
  EraserStroke({
    required super.points,
    super.color,
    super.size,
    super.opacity,
  }) : super(strokeType: StrokeType.eraser);

  @override
  EraserStroke copyWith({
    List<Offset>? points,
    Color? color,
    double? size,
    double? opacity,
  }) {
    return EraserStroke(
      points: points ?? this.points,
      color: color ?? this.color,
      size: size ?? this.size,
      opacity: opacity ?? this.opacity,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'points':
          points.map((point) => {'dx': point.dx, 'dy': point.dy}).toList(),
      'color': color.toJson(),
      'size': size,
      'opacity': opacity,
      'strokeType': strokeType.toString(),
    };
  }
}

class LineStroke extends Stroke {
  LineStroke({
    required super.points,
    super.color,
    super.size,
    super.opacity,
  }) : super(strokeType: StrokeType.line);

  @override
  LineStroke copyWith({
    List<Offset>? points,
    Color? color,
    double? size,
    double? opacity,
  }) {
    return LineStroke(
      points: points ?? this.points,
      color: color ?? this.color,
      size: size ?? this.size,
      opacity: opacity ?? this.opacity,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'points':
          points.map((point) => {'dx': point.dx, 'dy': point.dy}).toList(),
      'color': color.toJson(),
      'size': size,
      'opacity': opacity,
      'strokeType': strokeType.toString(),
    };
  }
}

class PolygonStroke extends Stroke {
  PolygonStroke({
    required super.points,
    required this.sides,
    this.filled = false,
    super.color,
    super.size,
    super.opacity,
  }) : super(strokeType: StrokeType.polygon);

  final int sides;
  final bool filled;

  @override
  PolygonStroke copyWith({
    List<Offset>? points,
    int? sides,
    Color? color,
    double? size,
    double? opacity,
    bool? filled,
  }) {
    return PolygonStroke(
      points: points ?? this.points,
      sides: sides ?? this.sides,
      color: color ?? this.color,
      size: size ?? this.size,
      opacity: opacity ?? this.opacity,
      filled: filled ?? this.filled,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'points':
          points.map((point) => {'dx': point.dx, 'dy': point.dy}).toList(),
      'sides': sides,
      'color': color.toJson(),
      'size': size,
      'opacity': opacity,
      'strokeType': strokeType.toString(),
      'filled': filled,
    };
  }
}

class CircleStroke extends Stroke {
  CircleStroke({
    required super.points,
    this.filled = false,
    super.color,
    super.size,
    super.opacity,
  }) : super(strokeType: StrokeType.circle);
  final bool filled;

  @override
  CircleStroke copyWith({
    List<Offset>? points,
    Color? color,
    double? size,
    double? opacity,
    bool? filled,
  }) {
    return CircleStroke(
      points: points ?? this.points,
      color: color ?? this.color,
      size: size ?? this.size,
      opacity: opacity ?? this.opacity,
      filled: filled ?? this.filled,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'points':
          points.map((point) => {'dx': point.dx, 'dy': point.dy}).toList(),
      'color': color.toJson(),
      'size': size,
      'opacity': opacity,
      'strokeType': strokeType.toString(),
      'filled': filled,
    };
  }
}

class SquareStroke extends Stroke {
  SquareStroke({
    required super.points,
    this.filled = false,
    super.color,
    super.size,
    super.opacity,
  }) : super(strokeType: StrokeType.square);
  final bool filled;

  @override
  SquareStroke copyWith({
    List<Offset>? points,
    Color? color,
    double? size,
    double? opacity,
    bool? filled,
  }) {
    return SquareStroke(
      points: points ?? this.points,
      color: color ?? this.color,
      size: size ?? this.size,
      opacity: opacity ?? this.opacity,
      filled: filled ?? this.filled,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'points':
          points.map((point) => {'dx': point.dx, 'dy': point.dy}).toList(),
      'color': color.toJson(),
      'size': size,
      'opacity': opacity,
      'strokeType': strokeType.toString(),
      'filled': filled,
    };
  }
}

enum StrokeType {
  normal,
  eraser,
  line,
  polygon,
  square,
  circle,
  bucket;

  static StrokeType fromString(String value) {
    switch (value) {
      case 'normal':
        return StrokeType.normal;
      case 'eraser':
        return StrokeType.eraser;
      case 'line':
        return StrokeType.line;
      case 'polygon':
        return StrokeType.polygon;
      case 'square':
        return StrokeType.square;
      case 'circle':
        return StrokeType.circle;
      case 'bucket':
        return StrokeType.bucket;
      default:
        return StrokeType.normal;
    }
  }

  @override
  String toString() {
    switch (this) {
      case StrokeType.normal:
        return 'normal';
      case StrokeType.eraser:
        return 'eraser';
      case StrokeType.line:
        return 'line';
      case StrokeType.polygon:
        return 'polygon';
      case StrokeType.square:
        return 'square';
      case StrokeType.circle:
        return 'circle';
      case StrokeType.bucket:
        return 'bucket';
    }
  }
}

class BucketStroke extends Stroke {
  BucketStroke({
    required super.points,
    super.color,
    super.size,
    super.opacity,
    this.fillPixels = const [],
  }) : super(strokeType: StrokeType.bucket);

  /// Pixels preenchidos quando o balde foi aplicado.
  ///
  /// Guardados para o preenchimento continuar estático mesmo quando novos
  /// strokes entram no canvas. Imutável: o painter cacheia o `Path` derivado
  /// desta lista por identidade do stroke, e trocar o conteúdo no lugar
  /// deixaria o cache e o desenho fora de sincronia. Use [copyWith].
  final List<Offset> fillPixels;

  @override
  BucketStroke copyWith({
    List<Offset>? points,
    Color? color,
    double? size,
    double? opacity,
    List<Offset>? fillPixels,
  }) {
    return BucketStroke(
      points: points ?? this.points,
      fillPixels: fillPixels ?? this.fillPixels,
      color: color ?? this.color,
      size: size ?? this.size,
      opacity: opacity ?? this.opacity,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'points':
          points.map((point) => {'dx': point.dx, 'dy': point.dy}).toList(),
      'color': color.toJson(),
      'size': size,
      'opacity': opacity,
      'strokeType': strokeType.toString(),
      'fillPixels': fillPixels.map((p) => {'dx': p.dx, 'dy': p.dy}).toList(),
    };
  }
}
