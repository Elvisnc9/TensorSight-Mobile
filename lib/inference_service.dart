import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';
import 'detection_model.dart';

class InferenceService {
  OrtSession? _session;
  OrtRunOptions? _runOptions;
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

  /// Copies assets/models/yolov8n.onnx to getApplicationDocumentsDirectory()
  /// and returns the local absolute file path for the C++ native engine.
  Future<String> _resolveModelFilePath() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final modelFile = File('/yolov8n.onnx');

    // Only copy if not already cached or empty
    if (!await modelFile.exists() || await modelFile.length() == 0) {
      final ByteData data = await rootBundle.load('assets/models/yolov8n.onnx');
      final Uint8List bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      await modelFile.writeAsBytes(bytes, flush: true);
    }

    return modelFile.path;
  }

  /// Initializes ONNX Runtime environment and loads YOLOv8n session from the local file path.
  Future<void> initialize() async {
    if (_isInitialized) return;

    OrtEnv.instance.init();
    _runOptions = OrtRunOptions();

    final sessionOptions = OrtSessionOptions();
    final String localModelPath = await _resolveModelFilePath();
    final File modelFile = File(localModelPath);

    // Initialize session directly from local file path
    _session = OrtSession.fromFile(modelFile, sessionOptions);
    _isInitialized = true;
  }

  /// Passes [inputTensor] with shape [1, 3, 640, 640] to the ONNX session
  /// Returns raw flattened float output list corresponding to [1, 84, 8400]
  List<double> runInference(Float32List inputTensor) {
    if (!_isInitialized || _session == null || _runOptions == null) {
      throw StateError('InferenceService is not initialized');
    }

    final inputShape = [1, 3, 640, 640];
    final inputOrtValue = OrtValueTensor.createTensorWithDataList(
      inputTensor,
      inputShape,
    );

    final inputName = _session!.inputNames.isNotEmpty
        ? _session!.inputNames.first
        : 'images';

    final inputs = {inputName: inputOrtValue};
    final outputs = _session!.run(_runOptions!, inputs);

    // Free native input memory
    inputOrtValue.release();

    if (outputs.isEmpty || outputs.first == null) {
      return [];
    }

    final firstOutput = outputs.first!;
    final dynamic rawValue = firstOutput.value;

    // Free native output memory
    firstOutput.release();

    if (rawValue is List) {
      if (rawValue.isNotEmpty && rawValue.first is List) {
        return _flattenRecursive(rawValue);
      }
      return rawValue.cast<double>();
    }

    return [];
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
  /// filters candidates with maxScore > 0.45, and applies Non-Maximum Suppression (IoU >= 0.45).
  List<Detection> decodeYoloOutput(
    List<double> output, {
    double confThreshold = 0.45,
    double iouThreshold = 0.45,
  }) {
    const int numCandidates = 8400;
    const int numClasses = 80;
    const double modelInputSize = 640.0;

    if (output.length < 84 * numCandidates) {
      return [];
    }

    final List<Detection> candidates = [];

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

      if (maxScore > confThreshold && bestClassId >= 0) {
        final double cx = output[0 * numCandidates + col];
        final double cy = output[1 * numCandidates + col];
        final double w = output[2 * numCandidates + col];
        final double h = output[3 * numCandidates + col];

        // Convert [cx, cy, w, h] to normalized coordinates [0.0 .. 1.0]
        final double normLeft = ((cx - w / 2.0) / modelInputSize).clamp(0.0, 1.0);
        final double normTop = ((cy - h / 2.0) / modelInputSize).clamp(0.0, 1.0);
        final double normWidth = (w / modelInputSize).clamp(0.0, 1.0);
        final double normHeight = (h / modelInputSize).clamp(0.0, 1.0);

        final label = bestClassId < cocoLabels.length
            ? cocoLabels[bestClassId]
            : 'class_';

        // Capitalize first letter for display (e.g., 'laptop' -> 'Laptop')
        final displayLabel = label.isNotEmpty
            ? ''
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

  void dispose() {
    _session?.release();
    _runOptions?.release();
    _session = null;
    _runOptions = null;
    _isInitialized = false;
  }
}
