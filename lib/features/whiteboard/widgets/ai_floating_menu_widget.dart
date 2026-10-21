import 'dart:math';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../state/whiteboard_provider.dart';

/// Floating AI assistant button and contextual actions menu.
/// Features a rotating rainbow aura, pearl ceramic disc, and vector sparkles.
class AiFloatingMenuWidget extends StatefulWidget {
  const AiFloatingMenuWidget({super.key});

  @override
  State<AiFloatingMenuWidget> createState() => _AiFloatingMenuWidgetState();
}

class _AiFloatingMenuWidgetState extends State<AiFloatingMenuWidget>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<bool> _checkInternet(BuildContext context) async {
    final results = await Connectivity().checkConnectivity();
    if (!context.mounted) return false;
    if (results.contains(ConnectivityResult.none)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFDC2626),
          content: Text(
            'No Internet Connection',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(20),
        ),
      );
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 24,
      bottom: 100,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Expanded Menu Options (Quick Quiz, Homework, Summary)
          if (_isExpanded) ...[
            _buildMenuButton(
              title: 'Quick Quiz',
              icon: LucideIcons.sparkle,
              color: const Color(0xFF10B981), // Green sparkle
              onTap: () async {
                if (!await _checkInternet(context)) return;
                if (!context.mounted) return;
                setState(() => _isExpanded = false);
                context.read<WhiteboardProvider>().generateAiContent(
                  type: 'Quick Quiz',
                  isWholeDoc: false,
                );
              },
            ),
            const SizedBox(height: 10),
            _buildMenuButton(
              title: 'Homework',
              icon: LucideIcons.sparkles,
              color: const Color(0xFF0EA5E9), // Sky blue sparkle
              onTap: () async {
                if (!await _checkInternet(context)) return;
                if (!context.mounted) return;
                setState(() => _isExpanded = false);
                context.read<WhiteboardProvider>().generateAiContent(
                  type: 'Homework',
                  isWholeDoc: false,
                );
              },
            ),
            const SizedBox(height: 10),
            _buildMenuButton(
              title: 'Summary',
              icon: LucideIcons.star,
              color: const Color(0xFFF59E0B), // Warm amber sparkle
              onTap: () async {
                if (!await _checkInternet(context)) return;
                if (!context.mounted) return;
                setState(() => _isExpanded = false);
                context.read<WhiteboardProvider>().generateAiContent(
                  type: 'Summary',
                  isWholeDoc: false,
                );
              },
            ),
            const SizedBox(height: 12),
          ],

          // Main Floating AI Button / Close Button
          AnimatedBuilder(
            animation: _animController,
            builder: (context, _) {
              // Gentle breathing pulse animation for the button
              final double pulseScale = _isExpanded
                  ? 1.0
                  : (1.0 + sin(_animController.value * 2 * pi) * 0.025);

              return Transform.scale(
                scale: pulseScale,
                child: SizedBox(
                  width: 54,
                  height: 54,
                  child: CustomPaint(
                    painter: _RainbowRingPainter(
                      animationValue: _animController.value,
                    ),
                    child: Center(
                      child: GestureDetector(
                        onTap: () async {
                          if (_isExpanded) {
                            setState(() => _isExpanded = false);
                            return;
                          }
                          if (!await _checkInternet(context)) return;
                          if (!context.mounted) return;
                          setState(() => _isExpanded = true);
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const RadialGradient(
                              center: Alignment(-0.35, -0.45),
                              radius: 0.95,
                              colors: [
                                Color(0xFFFFFFFF),
                                Color(0xFFF8FAFC),
                                Color(0xFFEDF2F7),
                              ],
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.95),
                              width: 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF7C3AED).withValues(alpha: 0.22),
                                blurRadius: 12,
                                offset: const Offset(0, 3),
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.10),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Center(
                            child: _isExpanded
                                ? const Icon(
                                    LucideIcons.x,
                                    size: 20,
                                    color: Color(0xFF0F172A),
                                  )
                                : const SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: CustomPaint(
                                      painter: _AiSparklesPainter(
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMenuButton({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.18),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Mathematically smooth 3-Sparkle AI Constellation (Zero Pixelation Vector)
// -----------------------------------------------------------------------------
class _AiSparklesPainter extends CustomPainter {
  final Color color;

  const _AiSparklesPainter({this.color = const Color(0xFF0F172A)});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Star 1: Large Center-Left Star
    final p1 = _buildSparklePath(
      center: Offset(size.width * 0.44, size.height * 0.52),
      radius: size.width * 0.34,
      concavity: 0.20,
    );
    canvas.drawPath(p1, paint);

    // Star 2: Medium Top-Right Star
    final p2 = _buildSparklePath(
      center: Offset(size.width * 0.70, size.height * 0.35),
      radius: size.width * 0.17,
      concavity: 0.22,
    );
    canvas.drawPath(p2, paint);

    // Star 3: Small Bottom-Right Star
    final p3 = _buildSparklePath(
      center: Offset(size.width * 0.69, size.height * 0.70),
      radius: size.width * 0.13,
      concavity: 0.24,
    );
    canvas.drawPath(p3, paint);
  }

  Path _buildSparklePath({
    required Offset center,
    required double radius,
    required double concavity,
  }) {
    final path = Path();
    final cx = center.dx;
    final cy = center.dy;
    final r = radius;
    final ir = radius * concavity;

    path.moveTo(cx, cy - r);
    path.quadraticBezierTo(cx + ir, cy - ir, cx + r, cy);
    path.quadraticBezierTo(cx + ir, cy + ir, cx, cy + r);
    path.quadraticBezierTo(cx - ir, cy + ir, cx - r, cy);
    path.quadraticBezierTo(cx - ir, cy - ir, cx, cy - r);
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _AiSparklesPainter oldDelegate) =>
      oldDelegate.color != color;
}

// -----------------------------------------------------------------------------
// Animated Rainbow Spectrum Rotating Aura & Ring Painter
// -----------------------------------------------------------------------------
class _RainbowRingPainter extends CustomPainter {
  final double animationValue;

  const _RainbowRingPainter({required this.animationValue});

  static const List<Color> _rainbowColors = [
    Color(0xFF00F2FE), // Cyan
    Color(0xFF4FACFE), // Blue
    Color(0xFF7F00FF), // Violet
    Color(0xFFE100FF), // Neon Pink
    Color(0xFFFF0844), // Crimson
    Color(0xFFFFB199), // Warm Gold
    Color(0xFF00F260), // Lime Green
    Color(0xFF00F2FE), // Loop back to Cyan
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 2.0;

    final sweepGradient = SweepGradient(
      center: Alignment.center,
      colors: _rainbowColors,
      transform: GradientRotation(animationValue * 2 * pi),
    );

    final rect = Rect.fromCircle(center: center, radius: radius);

    // 1. Soft Outer Neon Glow
    final glowPaint = Paint()
      ..shader = sweepGradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);
    canvas.drawCircle(center, radius, glowPaint);

    // 2. Crisp Foreground Ring
    final ringPaint = Paint()
      ..shader = sweepGradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawCircle(center, radius, ringPaint);
  }

  @override
  bool shouldRepaint(covariant _RainbowRingPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue;
}
