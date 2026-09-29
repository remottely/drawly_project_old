import 'package:drawing_board/drawing_board.dart';
import 'package:drawly_design_system/drawly_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final baseJson = {
    'points': [
      {'dx': 0.0, 'dy': 0.0},
      {'dx': 1.0, 'dy': 1.0},
    ],
    'color': Colors.black.toJson(),
    'size': 2,
    'opacity': 1.0,
  };

  test('creates NormalStroke from json', () {
    final json = Map<String, dynamic>.from(baseJson)..['strokeType'] = 'normal';
    final stroke = Stroke.fromJson(json);
    expect(stroke, isA<NormalStroke>());
    expect(stroke.points.length, 2);
  });

  test('creates PolygonStroke with filled option', () {
    final json = Map<String, dynamic>.from(baseJson)
      ..['strokeType'] = 'polygon'
      ..['sides'] = 5
      ..['filled'] = true;
    final stroke = Stroke.fromJson(json);
    expect(stroke, isA<PolygonStroke>());
    final poly = stroke as PolygonStroke;
    expect(poly.sides, 5);
    expect(poly.filled, true);
  });

  test('creates BucketStroke including fillPixels', () {
    final json = Map<String, dynamic>.from(baseJson)
      ..['strokeType'] = 'bucket'
      ..['fillPixels'] = [
        {'dx': 2.0, 'dy': 2.0}
      ];
    final stroke = Stroke.fromJson(json);
    expect(stroke, isA<BucketStroke>());
    final bucket = stroke as BucketStroke;
    expect(bucket.fillPixels.length, 1);
    expect(bucket.fillPixels.first, const Offset(2, 2));
  });
}
