import 'package:drawing_board/drawing_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bucket stroke keeps fill after new strokes are added', () {
    final border = NormalStroke(
      points: const [
        Offset(0, 0),
        Offset(4, 0),
        Offset(4, 4),
        Offset(0, 4),
        Offset(0, 0)
      ],
      color: Colors.black,
    );

    final fill = bucketFill(
      start: const Offset(2, 2),
      strokes: [border],
      canvasSize: const Size(5, 5),
    );

    final bucket = BucketStroke(
      points: const [Offset(2, 2)],
      color: Colors.red,
      fillPixels: fill,
    );

    final strokes = [border, bucket];

    // draw another stroke after bucket
    strokes.add(
      NormalStroke(points: const [Offset(1, 1)], color: Colors.black),
    );

    expect(bucket.fillPixels, fill);
  });
}
