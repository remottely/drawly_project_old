import 'package:drawing_board/drawing_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copyWith overrides provided fields', () {
    const options = DrawingCanvasOptions();
    final updated = options.copyWith(
      strokeColor: Colors.red,
      size: 5,
      fillShape: true,
    );

    expect(updated.strokeColor, Colors.red);
    expect(updated.size, 5);
    expect(updated.fillShape, true);
    expect(updated.currentTool, options.currentTool);
  });
}
