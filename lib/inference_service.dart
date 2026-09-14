import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'detection_model.dart';
import 'image_preprocessor.dart';

class InferenceService {
  final OnnxRuntime _ort = OnnxRuntime();
  OrtSession? _session;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  // 80 COCO Class Dictionary
  static const List<String> cocoLabels = [
    'person', 'bicycle', 'car', 'motorcycle', 'airplane', 'bus', 'train', 'truck', 'boat',
    'traffic light', 'fire hydrant', 'stop sign', 'parking meter', 'bench', 'bird', 'cat',
    'dog', 'horse', 'sheep', 'cow', 'elephant', 'bear', 'zebra', 'giraffe', 'backpack',
    'umbrella', 'handbag', 'tie', 'suitcase', 'frisbee', 'skis', 'snowboard', 'sports ball',
    'kite', 'baseball bat', 'baseball glove', 'skateboard', 'surfboard', 'tennis racket',
    'bottle', 'wine glass', 'cup', 'fork', 'knife', 'spoon', 'bowl', 'banana', 'apple',
    'sandwich', 'orange', 'broccoli', 'carrot', 'hot dog', 'pizza', 'donut', 'cake',
    'chair', 'couch', 'potted plant', 'bed', 'dining table', 'toilet', 'tv', 'laptop',
    'mouse', 'remote', 'keyboard', 'cell phone', 'microwave', 'oven', 'toaster', 'sink',
    'refrigerator', 'book', 'clock', 'vase', 'scissors', 'teddy bear', 'hair drier',
    'toothbrush'
  ];

  /// Initializes ONNX Runtime and loads YOLOv8n directly from the Flutter asset bundle.
  /// flutter_onnxruntime handles asset resolution internally, so there's no need to
  /// manually copy the model into the app documents directory (unlike the old
  /// `onnxruntime` package's OrtSession.fromFile approach).
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint("Creating ONNX session from asset: assets/models/yolov8n.onnx");
      _session = await _ort.createSessionFromAsset('assets/models/yolov8n.onnx');
      _isInitialized = true;
      debugPrint(
        "OrtSession initialized successfully. "
        "Inputs: ${_session?.inputNames}, Outputs: ${_session?.outputNames}",
      );
    } catch (e, stack) {
      debugPrint("Failed to initialize OrtSession: $e\n$stack");
      rethrow;
    }
  }

  /// Passes [inputTensor] with shape [1, 3, 640, 640] to the ONNX session.
  /// Returns raw flattened double list corresponding to [1, 84, 8400].
  Future<List<double>> runInference(Float32List inputTensor) async {
    if (!_isInitialized || _session == null) {
      throw StateError('InferenceService is not initialized');
    }

    final inputShape = [1, 3, 640, 640];
    final inputName = _session!.inputNames.isNotEmpty
        ? _session!.inputNames.first
        : 'images';
    final outputName = _session!.outputNames.isNotEmpty
        ? _session!.outputNames.first
        : null;

    // flutter_onnxruntime's OrtValue.fromList takes (data, shape) — note the
    // argument order is reversed from the old onnxruntime package's
    // OrtValueTensor.createTensorWithDataList(data, shape), which is the same
    // order coincidentally, but double-check if you copy from other examples.
    final inputValue = await OrtValue.fromList(inputTensor, inputShape);
    final inputs = {inputName: inputValue};

    Map<String, OrtValue> outputs = {};
    try {
      outputs = await _session!.run(inputs);

      if (outputName == null || !outputs.containsKey(outputName)) {
        return [];
      }

      final rawList = await outputs[outputName]!.asList();
      // asList() returns a flattened (or nested, depending on platform) list —
      // normalize defensively either way.
      return _flattenRecursive(rawList);
    } finally {
      // Free native memory for both input and output tensors.
      await inputValue.dispose();
      for (final value in outputs.values) {
        await value.dispose();
      }
    }
  }

  List<double> _flattenRecursive(List list) {
    final List<double> result = [];
    void flatten(dynamic item) {
      if (item is List) {
        for (final sub in item) {
          flatten(sub);
        }
      } else if (item is num) {
        result.add(item.toDouble());
      }
    }
    flatten(list);
    return result;
  }

  /// Decodes [1, 84, 8400] YOLOv8 outputs:
  /// Transposes columns to 8400 rows of 84 elements (cx, cy, w, h + 80 class confidence scores),
  /// filters candidates with maxScore > confThreshold, and applies Non-Maximum Suppression (IoU >= 0.45).
  /// If [letterboxInfo] is provided, letterbox padding is subtracted to normalize accurately.
  List<Detection> decodeYoloOutput(
    List<double> output, {
    double confThreshold = 0.40,
    double iouThreshold = 0.45,
    LetterboxInfo? letterboxInfo,
  }) {
    const int numCandidates = 8400;
    const int numClasses = 80;
    const double modelInputSize = 640.0;

    if (output.length < 84 * numCandidates) {
      debugPrint("Output tensor length too short: ${output.length} vs expected ${84 * numCandidates}");
      return [];
    }

    final List<Detection> candidates = [];
    double overallMaxConfidence = 0.0;
    String topLabel = "none";

    final double padX = letterboxInfo?.padX ?? 0.0;
    final double padY = letterboxInfo?.padY ?? 0.0;
    final double unpaddedW = modelInputSize - 2 * padX;
    final double unpaddedH = modelInputSize - 2 * padY;

    // Output is column-major: row r, col c -> index = r * 8400 + c
    // r=0: cx, r=1: cy, r=2: w, r=3: h, r=4..83: classes
    for (int col = 0; col < numCandidates; col++) {
      double maxScore = 0.0;
      int bestClassId = -1;

      for (int c = 0; c < numClasses; c++) {
        final double score = output[(4 + c) * numCandidates + col];
        if (score > maxScore) {
          maxScore = score;
          bestClassId = c;
        }
      }

      if (maxScore > overallMaxConfidence) {
        overallMaxConfidence = maxScore;
        topLabel = (bestClassId >= 0 && bestClassId < cocoLabels.length)
            ? cocoLabels[bestClassId]
            : "unknown";
      }

      if (maxScore > confThreshold && bestClassId >= 0) {
        final double cx = output[0 * numCandidates + col];
        final double cy = output[1 * numCandidates + col];
        final double w = output[2 * numCandidates + col];
        final double h = output[3 * numCandidates + col];

        final double boxLeft = cx - w / 2.0;
        final double boxTop = cy - h / 2.0;

        // Subtract letterbox padding and normalize relative to the unpadded frame
        final double normLeft = ((boxLeft - padX) / unpaddedW).clamp(0.0, 1.0);
        final double normTop = ((boxTop - padY) / unpaddedH).clamp(0.0, 1.0);
        final double normWidth = (w / unpaddedW).clamp(0.0, 1.0);
        final double normHeight = (h / unpaddedH).clamp(0.0, 1.0);

        final label = bestClassId < cocoLabels.length
            ? cocoLabels[bestClassId]
            : "class_$bestClassId";

        final displayLabel = label.isNotEmpty
            ? '${label[0].toUpperCase()}${label.substring(1)}'
            : label;

        candidates.add(
          Detection(
            box: Rect.fromLTWH(normLeft, normTop, normWidth, normHeight),
            label: displayLabel,
            confidence: maxScore,
            classId: bestClassId,
          ),
        );
      }
    }

    debugPrint("Tensor output shape: [1, 84, 8400], Max confidence found: ${overallMaxConfidence.toStringAsFixed(4)} ($topLabel), Candidates: ${candidates.length}");

    return _nonMaximumSuppression(candidates, iouThreshold);
  }

  List<Detection> _nonMaximumSuppression(
    List<Detection> boxes,
    double iouThreshold,
  ) {
    boxes.sort((a, b) => b.confidence.compareTo(a.confidence));

    final List<Detection> selected = [];
    final List<bool> active = List<bool>.filled(boxes.length, true);

    for (int i = 0; i < boxes.length; i++) {
      if (!active[i]) continue;

      final current = boxes[i];
      selected.add(current);

      for (int j = i + 1; j < boxes.length; j++) {
        if (!active[j]) continue;

        if (current.classId == boxes[j].classId) {
          final double iou = _calculateIoU(current.box, boxes[j].box);
          if (iou >= iouThreshold) {
            active[j] = false;
          }
        }
      }
    }

    return selected;
  }

  double _calculateIoU(Rect a, Rect b) {
    final double left = max(a.left, b.left);
    final double top = max(a.top, b.top);
    final double right = min(a.right, b.right);
    final double bottom = min(a.bottom, b.bottom);

    final double intersectionWidth = max(0.0, right - left);
    final double intersectionHeight = max(0.0, bottom - top);
    final double intersectionArea = intersectionWidth * intersectionHeight;

    final double areaA = a.width * a.height;
    final double areaB = b.width * b.height;
    final double unionArea = areaA + areaB - intersectionArea;

    if (unionArea <= 0.0) return 0.0;
    return intersectionArea / unionArea;
  }

  Future<void> dispose() async {
    await _session?.close();
    _session = null;
    _isInitialized = false;
  }
}