import 'dart:ui';

class Detection {
  final Rect box; // In normalized 0.0..1.0 coordinate space (left, top, width, height)
  final String label;
  final double confidence;
  final int classId;

  const Detection({
    required this.box,
    required this.label,
    required this.confidence,
    required this.classId,
  });
}
