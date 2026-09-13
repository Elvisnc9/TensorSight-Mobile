import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'bounding_box_painter.dart';
import 'detection_model.dart';
import 'image_preprocessor.dart';
import 'inference_service.dart';

class CameraInspectionScreen extends StatefulWidget {
  const CameraInspectionScreen({super.key});

  @override
  State<CameraInspectionScreen> createState() => _CameraInspectionScreenState();
}

class _CameraInspectionScreenState extends State<CameraInspectionScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  String? _errorMessage;

  final InferenceService _inferenceService = InferenceService();
  bool _isProcessing = false;
  List<Detection> _detections = [];
  int _latencyMs = 0;
  int _activeObjectCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAll();
  }

  Future<void> _initializeAll() async {
    await _initInferenceEngine();
    await _initCamera();
  }

  Future<void> _initInferenceEngine() async {
    try {
      await _inferenceService.initialize();
    } catch (e, stack) {
      debugPrint('Failed to initialize InferenceService: $e\n$stack');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopImageStream();
    _controller?.dispose();
    _inferenceService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _stopImageStream();
      cameraController.dispose();
      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = 'No camera hardware found on this device.';
          });
        }
        return;
      }

      final camera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isCameraInitialized = true;
        _errorMessage = null;
      });

      _startImageStream();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error initializing camera: ';
        });
      }
    }
  }

  void _startImageStream() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    controller.startImageStream((CameraImage image) {
      debugPrint("Frame received -> isProcessing: $_isProcessing, serviceReady: ${_inferenceService.isInitialized}");
      _processFrame(image);
    });
  }

  void _stopImageStream() {
    try {
      if (_controller != null && _controller!.value.isStreamingImages) {
        _controller!.stopImageStream();
      }
    } catch (_) {}
  }

  void _processFrame(CameraImage image) async {
    // Drop incoming frame immediately if previous inference is still in flight
    if (_isProcessing || !_inferenceService.isInitialized || !mounted) {
      return;
    }

    _isProcessing = true;
    final stopwatch = Stopwatch()..start();

    try {
      // Pack raw plane data safely for Isolate transmission
      final frameData = CameraFrameData(
        planes: image.planes.map((p) => Uint8List.fromList(p.bytes)).toList(),
        bytesPerRow: image.planes.map((p) => p.bytesPerRow).toList(),
        bytesPerPixel: image.planes.map((p) => p.bytesPerPixel).toList(),
        width: image.width,
        height: image.height,
        format: image.format.raw,
      );

      // Preprocess image off the UI thread via compute isolate into normalized 640x640 [1, 3, 640, 640]
      final Float32List inputTensor = await compute(preprocessCameraImage, frameData);

      if (!mounted) return;

      // Execute on-device ONNX runtime inference: [1, 3, 640, 640] -> [1, 84, 8400]
      final List<double> rawOutput = _inferenceService.runInference(inputTensor);

      stopwatch.stop();
      final int latency = stopwatch.elapsedMilliseconds;

      if (rawOutput.isNotEmpty && mounted) {
        // Decode 8400 candidate rows with 0.15 threshold for debug verification
        final List<Detection> detections = _inferenceService.decodeYoloOutput(
          rawOutput,
          confThreshold: 0.15,
          iouThreshold: 0.45,
        );

        setState(() {
          _detections = detections;
          _activeObjectCount = detections.length;
          _latencyMs = latency;
        });
      }
    } catch (e, stack) {
      debugPrint("Inference error: $e\n$stack");
    } finally {
      _isProcessing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        title: Text(
          'TensorSight Inspection',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: Stack(
        children: [
          _buildCameraBody(),
          _buildTelemetryPanel(),
        ],
      ),
    );
  }

  Widget _buildCameraBody() {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _initializeAll,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isCameraInitialized || _controller == null) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Camera sensor dimensions (rotated in portrait: width is height, height is width)
        final double previewWidth = _controller!.value.previewSize?.height ?? constraints.maxWidth;
        final double previewHeight = _controller!.value.previewSize?.width ?? constraints.maxHeight;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Live camera stream
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: previewWidth,
                height: previewHeight,
                child: CameraPreview(_controller!),
              ),
            ),
            // Real-time custom painter bounding box overlay
            CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: BoundingBoxPainter(
                detections: _detections,
                previewSize: Size(previewWidth, previewHeight),
                canvasSize: Size(constraints.maxWidth, constraints.maxHeight),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTelemetryPanel() {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 24,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22).withOpacity(0.88),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.12),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildMetricItem(
              icon: Icons.timer_outlined,
              label: 'Latency',
              value: ' ms',
              accentColor: _latencyMs > 100
                  ? const Color(0xFFFBBF24)
                  : const Color(0xFF00F0FF),
            ),
            Container(
              height: 28,
              width: 1,
              color: Colors.white.withOpacity(0.15),
            ),
            _buildMetricItem(
              icon: Icons.filter_center_focus_rounded,
              label: 'Detected',
              value: ' objs',
              accentColor: const Color(0xFF39FF14),
            ),
            Container(
              height: 28,
              width: 1,
              color: Colors.white.withOpacity(0.15),
            ),
            _buildMetricItem(
              icon: Icons.memory_rounded,
              label: 'Model',
              value: 'YOLOv8n',
              accentColor: const Color(0xFFB026FF),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricItem({
    required IconData icon,
    required String label,
    required String value,
    required Color accentColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: accentColor),
            const SizedBox(width: 5),
            Text(
              value,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.inter(
            color: const Color(0xFF94A3B8),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
