import 'dart:typed_data';

class CameraFrameData {
  final List<Uint8List> planes;
  final List<int> bytesPerRow;
  final List<int?> bytesPerPixel;
  final int width;
  final int height;
  final int format; // 35 for YUV_420_888, 1 for BGRA/RGBA

  CameraFrameData({
    required this.planes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
    required this.width,
    required this.height,
    required this.format,
  });
}

/// Preprocesses raw camera image buffer to Float32List [1, 3, 640, 640] normalized to [0, 1].
/// Runs in a background isolate.
Float32List preprocessCameraImage(CameraFrameData frame) {
  const int targetSize = 640;
  final Float32List tensor = Float32List(1 * 3 * targetSize * targetSize);
  const int planeSize = targetSize * targetSize;

  final int width = frame.width;
  final int height = frame.height;

  // Scale factors mapping from target 640x640 back to frame dimensions
  final double scaleX = width / targetSize;
  final double scaleY = height / targetSize;

  final isYuv = frame.planes.length >= 3;

  if (isYuv) {
    final Uint8List yPlane = frame.planes[0];
    final Uint8List uPlane = frame.planes[1];
    final Uint8List vPlane = frame.planes[2];

    final int yRowStride = frame.bytesPerRow[0];
    final int uRowStride = frame.bytesPerRow[1];
    final int vRowStride = frame.bytesPerRow[2];

    final int uPixelStride = frame.bytesPerPixel[1] ?? 1;
    final int vPixelStride = frame.bytesPerPixel[2] ?? 1;

    for (int y = 0; y < targetSize; y++) {
      final int srcY = (y * scaleY).toInt().clamp(0, height - 1);
      final int yRowOffset = srcY * yRowStride;
      final int uvRowIndex = srcY >> 1;
      final int uRowOffset = uvRowIndex * uRowStride;
      final int vRowOffset = uvRowIndex * vRowStride;

      final int destRowOffset = y * targetSize;

      for (int x = 0; x < targetSize; x++) {
        final int srcX = (x * scaleX).toInt().clamp(0, width - 1);

        final int yVal = yPlane[yRowOffset + srcX];
        final int uvColIndex = srcX >> 1;
        final int uVal = uPlane[uRowOffset + uvColIndex * uPixelStride];
        final int vVal = vPlane[vRowOffset + uvColIndex * vPixelStride];

        // Standard BT.601 YUV to RGB integer arithmetic
        final int c = yVal - 16;
        final int d = uVal - 128;
        final int e = vVal - 128;

        int r = (298 * c + 409 * e + 128) >> 8;
        int g = (298 * c - 100 * d - 208 * e + 128) >> 8;
        int b = (298 * c + 516 * d + 128) >> 8;

        if (r < 0) r = 0; else if (r > 255) r = 255;
        if (g < 0) g = 0; else if (g > 255) g = 255;
        if (b < 0) b = 0; else if (b > 255) b = 255;

        final int destIndex = destRowOffset + x;
        // CHW layout: Red plane, Green plane, Blue plane
        tensor[destIndex] = r / 255.0;
        tensor[planeSize + destIndex] = g / 255.0;
        tensor[2 * planeSize + destIndex] = b / 255.0;
      }
    }
  } else {
    // BGRA / RGBA single plane format (typically iOS or certain cameras)
    final Uint8List plane = frame.planes[0];
    final int rowStride = frame.bytesPerRow[0];
    final int pixelStride = frame.bytesPerPixel[0] ?? 4;

    for (int y = 0; y < targetSize; y++) {
      final int srcY = (y * scaleY).toInt().clamp(0, height - 1);
      final int rowOffset = srcY * rowStride;
      final int destRowOffset = y * targetSize;

      for (int x = 0; x < targetSize; x++) {
        final int srcX = (x * scaleX).toInt().clamp(0, width - 1);
        final int pixelOffset = rowOffset + srcX * pixelStride;

        final int b = plane[pixelOffset];
        final int g = plane[pixelOffset + 1];
        final int r = plane[pixelOffset + 2];

        final int destIndex = destRowOffset + x;
        tensor[destIndex] = r / 255.0;
        tensor[planeSize + destIndex] = g / 255.0;
        tensor[2 * planeSize + destIndex] = b / 255.0;
      }
    }
  }

  return tensor;
}
