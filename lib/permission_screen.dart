import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'camera_inspection_screen.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen>
    with WidgetsBindingObserver {
  bool _isChecking = true;
  bool _isPermanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInitialPermission();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkSilentlyOnResume();
    }
  }

  Future<void> _checkSilentlyOnResume() async {
    final status = await Permission.camera.status;
    if (status.isGranted && mounted) {
      _navigateToCamera();
    } else if (mounted) {
      setState(() {
        _isPermanentlyDenied = status.isPermanentlyDenied;
      });
    }
  }

  Future<void> _checkInitialPermission() async {
    final status = await Permission.camera.status;
    if (!mounted) return;

    if (status.isGranted) {
      _navigateToCamera();
    } else {
      setState(() {
        _isChecking = false;
        _isPermanentlyDenied = status.isPermanentlyDenied;
      });
      _showGlassmorphicPermissionModal();
    }
  }

  void _navigateToCamera() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const CameraInspectionScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Future<void> _handlePermissionRequest() async {
    final status = await Permission.camera.request();
    if (!mounted) return;

    if (status.isGranted) {
      _navigateToCamera();
    } else {
      setState(() {
        _isPermanentlyDenied = status.isPermanentlyDenied;
      });
    }
  }

  void _showGlassmorphicPermissionModal() {
    showModalBottomSheet(
      context: context,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (modalContext) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              decoration: BoxDecoration(
                color: const Color(0xFF1E232E).withOpacity(0.82),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withOpacity(0.2),
                    width: 1.2,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.28),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withOpacity(0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF38BDF8).withOpacity(0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.camera_alt_outlined,
                      color: Color(0xFF38BDF8),
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Camera Access Required',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'TensorSight processes live video frames locally on-device for real-time edge computer vision inference. No video or frames are transmitted to external servers.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      height: 1.5,
                      color: const Color(0xFFCBD5E1),
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(modalContext).pop();
                        _handlePermissionRequest();
                      },
                      child: Text(
                        'Grant Camera Access',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.of(modalContext).pop(),
                    child: Text(
                      'Not Now',
                      style: GoogleFonts.inter(
                        color: const Color(0xFF94A3B8),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28.0),
            child: _isChecking
                ? const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E232E),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF334155),
                          ),
                        ),
                        child: Icon(
                          _isPermanentlyDenied
                              ? Icons.no_photography_outlined
                              : Icons.camera_alt_rounded,
                          size: 42,
                          color: _isPermanentlyDenied
                              ? const Color(0xFFF87171)
                              : const Color(0xFF38BDF8),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _isPermanentlyDenied
                            ? 'Camera Permission Blocked'
                            : 'Camera Permission Needed',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _isPermanentlyDenied
                            ? 'Camera permission has been permanently denied. Please open system settings to enable camera access for TensorSight.'
                            : 'TensorSight requires camera access for on-device real-time object detection.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          height: 1.5,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(height: 32),
                      if (_isPermanentlyDenied)
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF38BDF8),
                              foregroundColor: const Color(0xFF0F172A),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.settings_rounded, size: 18),
                            label: Text(
                              'Open Settings',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            onPressed: () async {
                              await openAppSettings();
                            },
                          ),
                        )
                      else ...[
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _showGlassmorphicPermissionModal,
                            child: Text(
                              'Enable Camera',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
