import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CameraInspectionScreen extends StatelessWidget {
  const CameraInspectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
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
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2430),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF2E3440),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.videocam_rounded,
                size: 48,
                color: Color(0xFF38BDF8),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Camera Stream Ready',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Camera hardware permission granted successfully.\nReady for real-time edge processing.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: const Color(0xFF94A3B8),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
