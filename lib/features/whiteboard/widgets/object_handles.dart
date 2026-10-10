import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../state/whiteboard_provider.dart';

class ObjectHandles extends StatefulWidget {
  const ObjectHandles({super.key});

  @override
  State<ObjectHandles> createState() => _ObjectHandlesState();
}

class _ObjectHandlesState extends State<ObjectHandles> {
  double _lastScale = 1.0;
  double _lastRotation = 0.0;

  static const Color handleAccent = Color(0xFF00C8AC); // Vibrant Cyan / Teal matching Reference UI

  void _showAiSelectionMenu(BuildContext context, WhiteboardProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bottomContext) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: const BoxDecoration(
          color: Color(0xFF1E293B), // Premium Slate dark background
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF8B5CF6).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(LucideIcons.sparkles, color: Color(0xFF8B5CF6), size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  'AI Assist for Selected Text',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(LucideIcons.x, color: Colors.grey, size: 20),
                  onPressed: () => Navigator.pop(bottomContext),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _AiOptionTile(
              title: 'Quick Quiz',
              subtitle: 'Generate MCQs based on selected text/notes',
              icon: LucideIcons.sparkle,
              color: const Color(0xFF10B981),
              onTap: () {
                Navigator.pop(bottomContext);
                provider.generateAiContent(type: 'Quick Quiz', isWholeDoc: false, forSelectedOnly: true);
              },
            ),
            const SizedBox(height: 10),
            _AiOptionTile(
              title: 'Homework',
              subtitle: 'Create homework assignments for selected topic',
              icon: LucideIcons.sparkles,
              color: const Color(0xFF38BDF8),
              onTap: () {
                Navigator.pop(bottomContext);
                provider.generateAiContent(type: 'Homework', isWholeDoc: false, forSelectedOnly: true);
              },
            ),
            const SizedBox(height: 10),
            _AiOptionTile(
              title: 'Summary',
              subtitle: 'Generate a detailed explanation & core talking points',
              icon: LucideIcons.star,
              color: const Color(0xFFF59E0B),
              onTap: () {
                Navigator.pop(bottomContext);
                provider.generateAiContent(type: 'Summary', isWholeDoc: false, forSelectedOnly: true);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<WhiteboardProvider>(context);
    final selectedIds = provider.selectedElementIds;
    if (selectedIds.isEmpty) return const SizedBox.shrink();

    final selectedElements = provider.currentPage.elements.where((e) => selectedIds.contains(e.id)).toList();
    if (selectedElements.isEmpty) return const SizedBox.shrink();

    // 1. Calculate Group Bounding Box
    Rect groupRect = selectedElements[0].getRawBounds();
    if (selectedElements.length == 1) {
      final e = selectedElements[0];
      groupRect = Rect.fromCenter(center: groupRect.center, width: groupRect.width * e.scale, height: groupRect.height * e.scale);
    } else {
      for (var i = 1; i < selectedElements.length; i++) {
        final e = selectedElements[i];
        final r = e.getRawBounds();
        final visualR = Rect.fromCenter(center: r.center, width: r.width * e.scale, height: r.height * e.scale);
        groupRect = groupRect.expandToInclude(visualR);
      }
    }

    final rect = groupRect;
    const padding = 10.0;
    const cornerHandleSize = 18.0;
    const stemHeight = 28.0;

    // Boundary positions for selection box
    final boxLeft = rect.left - padding;
    final boxRight = rect.right + padding;
    final boxTop = rect.top - padding;
    final boxBottom = rect.bottom + padding;
    final boxWidth = boxRight - boxLeft;
    final boxHeight = boxBottom - boxTop;
    final boxCenterX = rect.center.dx;

    return Stack(
      children: [
        // 1. Clean Cyan Dashed Bounding Box
        Positioned(
          left: boxLeft,
          top: boxTop,
          width: boxWidth,
          height: boxHeight,
          child: CustomPaint(painter: _DashedBorderPainter(color: handleAccent, strokeWidth: 1.8)),
        ),

        // 2. Center Drag & Pinch Scale Gesture Area
        Positioned(
          left: boxLeft,
          top: boxTop,
          width: boxWidth,
          height: boxHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onScaleStart: (details) {
              _lastScale = 1.0;
              _lastRotation = 0.0;
              provider.startTransform();
            },
            onScaleUpdate: (details) {
              final Offset delta = details.focalPointDelta;

              double scaleDelta = 0.0;
              if (details.scale != 1.0) {
                scaleDelta = details.scale - _lastScale;
                _lastScale = details.scale;
              }

              double rotationDelta = 0.0;
              if (details.rotation != 0.0) {
                rotationDelta = details.rotation - _lastRotation;
                _lastRotation = details.rotation;
              }

              provider.updateElementTransform(delta, rotationDelta, scaleDelta);
            },
            onScaleEnd: (details) {
              provider.endTransform();
            },
          ),
        ),

        // 3. Top Rotation Stem Line
        Positioned(
          left: boxCenterX - 1,
          top: boxTop - stemHeight,
          width: 2,
          height: stemHeight,
          child: CustomPaint(painter: _RotationStemPainter(color: handleAccent)),
        ),

        // 4. Top Rotation Handle Node (●)
        Positioned(
          left: boxCenterX - (cornerHandleSize / 2),
          top: boxTop - stemHeight - (cornerHandleSize / 2),
          child: _CornerNodeHandle(
            color: handleAccent,
            size: cornerHandleSize,
            onPanUpdate: (d) {
              final center = rect.center;
              final oldDir = (d.globalPosition - d.delta - center).direction;
              final newDir = (d.globalPosition - center).direction;
              provider.updateElementTransform(Offset.zero, newDir - oldDir, 0);
            },
            onPanStart: (_) => provider.startTransform(),
            onPanEnd: (_) => provider.endTransform(),
          ),
        ),

        // 5. Delete Action Handle (Top-Right Offset)
        Positioned(
          left: boxRight + 8,
          top: boxTop - 12,
          child: GestureDetector(
            onTap: () => provider.removeSelectedElements(),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.redAccent, width: 1.5),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.20), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: const Icon(LucideIcons.trash2, color: Colors.redAccent, size: 14),
            ),
          ),
        ),

        // 6. AI Assist Action Handle (Top-Right Offset next to Delete)
        Positioned(
          left: boxRight + 40,
          top: boxTop - 12,
          child: GestureDetector(
            onTap: () => _showAiSelectionMenu(context, provider),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF8B5CF6), width: 1.5),
                boxShadow: [BoxShadow(color: const Color(0xFF8B5CF6).withValues(alpha: 0.30), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: const Icon(LucideIcons.sparkles, color: Color(0xFF8B5CF6), size: 14),
            ),
          ),
        ),

        // --- 4 CORNER RESIZE HANDLES (Solid Cyan Circular Nodes matching Reference UI) ---

        // Top-Left Corner
        Positioned(
          left: boxLeft - (cornerHandleSize / 2),
          top: boxTop - (cornerHandleSize / 2),
          child: _CornerNodeHandle(
            color: handleAccent,
            size: cornerHandleSize,
            onPanUpdate: (d) => provider.resizeSelectedElement(HandleDirection.topLeft, d.delta),
            onPanStart: (_) => provider.startTransform(),
            onPanEnd: (_) => provider.endTransform(),
          ),
        ),

        // Top-Right Corner
        Positioned(
          left: boxRight - (cornerHandleSize / 2),
          top: boxTop - (cornerHandleSize / 2),
          child: _CornerNodeHandle(
            color: handleAccent,
            size: cornerHandleSize,
            onPanUpdate: (d) => provider.resizeSelectedElement(HandleDirection.topRight, d.delta),
            onPanStart: (_) => provider.startTransform(),
            onPanEnd: (_) => provider.endTransform(),
          ),
        ),

        // Bottom-Right Corner
        Positioned(
          left: boxRight - (cornerHandleSize / 2),
          top: boxBottom - (cornerHandleSize / 2),
          child: _CornerNodeHandle(
            color: handleAccent,
            size: cornerHandleSize,
            onPanUpdate: (d) => provider.resizeSelectedElement(HandleDirection.bottomRight, d.delta),
            onPanStart: (_) => provider.startTransform(),
            onPanEnd: (_) => provider.endTransform(),
          ),
        ),

        // Bottom-Left Corner
        Positioned(
          left: boxLeft - (cornerHandleSize / 2),
          top: boxBottom - (cornerHandleSize / 2),
          child: _CornerNodeHandle(
            color: handleAccent,
            size: cornerHandleSize,
            onPanUpdate: (d) => provider.resizeSelectedElement(HandleDirection.bottomLeft, d.delta),
            onPanStart: (_) => provider.startTransform(),
            onPanEnd: (_) => provider.endTransform(),
          ),
        ),
      ],
    );
  }
}

class _CornerNodeHandle extends StatelessWidget {
  final Color color;
  final double size;
  final Function(DragUpdateDetails)? onPanUpdate;
  final Function(DragStartDetails)? onPanStart;
  final Function(DragEndDetails)? onPanEnd;

  const _CornerNodeHandle({required this.color, required this.size, this.onPanUpdate, this.onPanStart, this.onPanEnd});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: onPanStart,
      onPanUpdate: onPanUpdate,
      onPanEnd: onPanEnd,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4, offset: const Offset(0, 2))],
        ),
      ),
    );
  }
}

class _AiOptionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _AiOptionTile({required this.title, required this.subtitle, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, color: Colors.grey, size: 18),
          ],
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _DashedBorderPainter({required this.color, this.strokeWidth = 1.8});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final RRect rrect = RRect.fromLTRBR(0, 0, size.width, size.height, const Radius.circular(4));
    final Path path = Path()..addRRect(rrect);

    const double dashWidth = 6.0;
    const double dashSpace = 4.0;

    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final Path extract = metric.extractPath(distance, distance + dashWidth);
        canvas.drawPath(extract, paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}

class _RotationStemPainter extends CustomPainter {
  final Color color;

  _RotationStemPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(size.width / 2, size.height), Offset(size.width / 2, 0), paint);
  }

  @override
  bool shouldRepaint(covariant _RotationStemPainter oldDelegate) => oldDelegate.color != color;
}
