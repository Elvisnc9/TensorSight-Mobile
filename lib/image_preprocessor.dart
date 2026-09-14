import 'dart:typed_data';

class CameraFrameData {
  final List<Uint8List> planes;
  final List<int> bytesPerRow;
  final List<int?> bytesPerPixel;
  final int width;
  final int height;
  final int format; // 35 for YUV_420_888, 1 for BGRA/RGBA
  final int rotation; // Sensor orientation in degrees (0, 90, 180, 270)

  CameraFrameData({
    required this.planes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
    required this.width,
    required this.height,
    required this.format,
    this.rotation = 90,
  });
}

class LetterboxInfo {
  final double scale;
  final double padX;
  final double padY;
  final double targetSize;

  const LetterboxInfo({
    required this.scale,
    required this.padX,
    required this.padY,
    this.targetSize = 640.0,
  });
}

class PreprocessResult {
  final Float32List tensor;
  final LetterboxInfo letterboxInfo;

  PreprocessResult({
    required this.tensor,
    required this.letterboxInfo,
  });
}

/// Preprocesses raw camera image buffer to Float32List [1, 3, 640, 640] normalized to [0, 1].
/// Handles camera sensor rotation (0, 90, 180, 270) in-loop and letterboxes with 114/255 padding.
PreprocessResult preprocessCameraImage(CameraFrameData frame) {
  const int targetSize = 640;
  const double fillVal = 114.0 / 255.0; // Ultralytics YOLO standard letterbox fill
  final Float32List tensor = Float32List(1 * 3 * targetSize * targetSize);
  const int planeSize = targetSize * targetSize;

  // Initialize tensor with letterbox gray color (114/255)
  tensor.fillRange(0, tensor.length, fillVal);

  final int rawWidth = frame.width;
  final int rawHeight = frame.height;
  final int rotation = frame.rotation;

  // Rotated frame dimensions
  final int rotWidth = (rotation == 90 || rotation == 270) ? rawHeight : rawWidth;
  final int rotHeight = (rotation == 90 || rotation == 270) ? rawWidth : rawHeight;

  // Uniform scale to fit rotWidth x rotHeight inside targetSize x targetSize
  final double scale = (targetSize / rotWidth < targetSize / rotHeight)
      ? targetSize / rotWidth
      : targetSize / rotHeight;

  final int scaledW = (rotWidth * scale).round().clamp(1, targetSize);
  final int scaledH = (rotHeight * scale).round().clamp(1, targetSize);

  final int padX = (targetSize - scaledW) ~/ 2;
  final int padY = (targetSize - scaledH) ~/ 2;

  final letterboxInfo = LetterboxInfo(
    scale: scale,
    padX: padX.toDouble(),
    padY: padY.toDouble(),
    targetSize: targetSize.toDouble(),
  );

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

    for (int dy = 0; dy < scaledH; dy++) {
      final int rotY = (dy / scale).toInt().clamp(0, rotHeight - 1);
      final int destY = padY + dy;
      final int destRowOffset = destY * targetSize;

      for (int dx = 0; dx < scaledW; dx++) {
        final int rotX = (dx / scale).toInt().clamp(0, rotWidth - 1);

        // Map (rotX, rotY) back to raw buffer (srcX, srcY) according to rotation
        int srcX, srcY;
        switch (rotation) {
          case 90:
            srcX = rotY;
            srcY = rawHeight - 1 - rotX;
            break;
          case 180:
            srcX = rawWidth - 1 - rotX;
            srcY = rawHeight - 1 - rotY;
            break;
          case 270:
            srcX = rawWidth - 1 - rotY;
            srcY = rotX;
            break;
          case 0:
          default:
            srcX = rotX;
            srcY = rotY;
            break;
        }

        srcX = srcX.clamp(0, rawWidth - 1);
        srcY = srcY.clamp(0, rawHeight - 1);

        final int yRowOffset = srcY * yRowStride;
        final int uvRowIndex = srcY >> 1;
        final int uRowOffset = uvRowIndex * uRowStride;
        final int vRowOffset = uvRowIndex * vRowStride;

        final int yVal = yPlane[yRowOffset + srcX];
        final int uvColIndex = srcX >> 1;
        final int uVal = uPlane[uRowOffset + uvColIndex * uPixelStride];
        final int vVal = vPlane[vRowOffset + uvColIndex * vPixelStride];

        // BT.601 YUV to RGB integer arithmetic
        final int c = yVal - 16;
        final int d = uVal - 128;
        final int e = vVal - 128;

        int r = (298 * c + 409 * e + 128) >> 8;
        int g = (298 * c - 100 * d - 208 * e + 128) >> 8;
        int b = (298 * c + 516 * d + 128) >> 8;

        if (r < 0) r = 0; else if (r > 255) r = 255;
        if (g < 0) g = 0; else if (g > 255) g = 255;
        if (b < 0) b = 0; else if (b > 255) b = 255;

        final int destIndex = destRowOffset + (padX + dx);
        tensor[destIndex] = r / 255.0;
        tensor[planeSize + destIndex] = g / 255.0;
        tensor[2 * planeSize + destIndex] = b / 255.0;
      }
    }
  } else {
    // Single plane BGRA / RGBA
    final Uint8List plane = frame.planes[0];
    final int rowStride = frame.bytesPerRow[0];
    final int pixelStride = frame.bytesPerPixel[0] ?? 4;

    for (int dy = 0; dy < scaledH; dy++) {
      final int rotY = (dy / scale).toInt().clamp(0, rotHeight - 1);
      final int destY = padY + dy;
      final int destRowOffset = destY * targetSize;

      for (int dx = 0; dx < scaledW; dx++) {
        final int rotX = (dx / scale).toInt().clamp(0, rotWidth - 1);

        int srcX, srcY;
        switch (rotation) {
          case 90:
            srcX = rotY;
            srcY = rawHeight - 1 - rotX;
            break;
          case 180:
            srcX = rawWidth - 1 - rotX;
            srcY = rawHeight - 1 - rotY;
            break;
          case 270:
            srcX = rawWidth - 1 - rotY;
            srcY = rotX;
            break;
          case 0:
          default:
            srcX = rotX;
            srcY = rotY;
            break;
        }

        srcX = srcX.clamp(0, rawWidth - 1);
        srcY = srcY.clamp(0, rawHeight - 1);

        final int pixelOffset = srcY * rowStride + srcX * pixelStride;

        final int b = plane[pixelOffset];
        final int g = plane[pixelOffset + 1];
        final int r = plane[pixelOffset + 2];

        final int destIndex = destRowOffset + (padX + dx);
        tensor[destIndex] = r / 255.0;
        tensor[planeSize + destIndex] = g / 255.0;
        tensor[2 * planeSize + destIndex] = b / 255.0;
      }
    }
  }

  return PreprocessResult(
    tensor: tensor,
    letterboxInfo: letterboxInfo,
  );
}
