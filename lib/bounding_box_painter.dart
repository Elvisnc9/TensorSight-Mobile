import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'detection_model.dart';

class BoundingBoxPainter extends CustomPainter {
  final List<Detection> detections;
  final Size previewSize;
  final Size canvasSize;

  BoundingBoxPainter({
    required this.detections,
    required this.previewSize,
    required this.canvasSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty || canvasSize.width <= 0 || canvasSize.height <= 0) {
      return;
    }

    // Camera aspect ratio mapping onto canvas with BoxFit.cover
    final double cameraAspect = previewSize.width > 0 && previewSize.height > 0
        ? previewSize.width / previewSize.height
        : canvasSize.width / canvasSize.height;

    final double canvasAspect = canvasSize.width / canvasSize.height;

    double renderWidth = canvasSize.width;
    double renderHeight = canvasSize.height;
    double offsetX = 0.0;
    double offsetY = 0.0;

    if (canvasAspect > cameraAspect) {
      // Canvas is wider than camera stream; scaled by width
      renderWidth = canvasSize.width;
      renderHeight = canvasSize.width / cameraAspect;
      offsetY = (canvasSize.height - renderHeight) / 2.0;
    } else {
      // Canvas is taller than camera stream; scaled by height
      renderHeight = canvasSize.height;
      renderWidth = canvasSize.height * cameraAspect;
      offsetX = (canvasSize.width - renderWidth) / 2.0;
    }

    for (final detection in detections) {
      // detection.box contains normalized values [0.0..1.0] from model space (640x640)
      final rect = Rect.fromLTWH(
        offsetX + detection.box.left * renderWidth,
        offsetY + detection.box.top * renderHeight,
        detection.box.width * renderWidth,
        detection.box.height * renderHeight,
      );

      final Color neonColor = _getNeonColorForClass(detection.classId);

      // Neon outer glow
      final glowPaint = Paint()
        ..color = neonColor.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

      // Neon sharp inner border
      final strokePaint = Paint()
        ..color = neonColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;

      // Subtle translucent interior fill
      final fillPaint = Paint()
        ..color = neonColor.withOpacity(0.08)
        ..style = PaintingStyle.fill;

      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
      canvas.drawRRect(rrect, fillPaint);
      canvas.drawRRect(rrect, glowPaint);
      canvas.drawRRect(rrect, strokePaint);

      // Label & Confidence text: e.g. Laptop 92%
      final int confidencePercent = (detection.confidence * 100).round();
      final String badgeText = '${detection.label} $confidencePercent%';

      final textSpan = TextSpan(
        text: badgeText,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      const double badgePaddingH = 8.0;
      const double badgeHeight = 22.0;
      final double badgeWidth = textPainter.width + badgePaddingH * 2;

      final double badgeLeft = rect.left.clamp(0.0, canvasSize.width - badgeWidth);
      final double badgeTop = rect.top > badgeHeight + 4
          ? rect.top - badgeHeight - 4
          : rect.top + 4;

      final badgeRect = Rect.fromLTWH(badgeLeft, badgeTop, badgeWidth, badgeHeight);
      final badgeRRect = RRect.fromRectAndRadius(badgeRect, const Radius.circular(5));

      final badgePaint = Paint()..color = neonColor.withOpacity(0.92);
      canvas.drawRRect(badgeRRect, badgePaint);

      textPainter.paint(
        canvas,
        Offset(badgeLeft + badgePaddingH, badgeTop + (badgeHeight - textPainter.height) / 2.0),
      );
    }
  }

  Color _getNeonColorForClass(int classId) {
    const neonPalette = [
      Color(0xFF00F0FF), // Neon Cyan
      Color(0xFF39FF14), // Neon Green
      Color(0xFFFF073A), // Neon Red
      Color(0xFFFFE600), // Neon Yellow
      Color(0xFFB026FF), // Neon Purple
      Color(0xFFFF6EC7), // Neon Pink
      Color(0xFFFF9900), // Neon Orange
      Color(0xFF00FFCC), // Neon Mint
    ];
    return neonPalette[classId % neonPalette.length];
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.previewSize != previewSize ||
        oldDelegate.canvasSize != canvasSize;
  }
}
