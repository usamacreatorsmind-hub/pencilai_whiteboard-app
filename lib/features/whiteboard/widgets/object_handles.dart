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
    final isLargeScreen = MediaQuery.of(context).size.width > 1200;
    final handleSize = isLargeScreen ? 34.0 : 26.0;
    final sideHandleSize = isLargeScreen ? 28.0 : 22.0;
    final iconSize = isLargeScreen ? 18.0 : 14.0;
    final sideIconSize = isLargeScreen ? 16.0 : 12.0;
    final padding = isLargeScreen ? 14.0 : 6.0;

    // Boundary positions for selection box
    final boxLeft = rect.left - padding;
    final boxRight = rect.right + padding;
    final boxTop = rect.top - padding;
    final boxBottom = rect.bottom + padding;
    final boxCenterX = rect.center.dx;
    final boxCenterY = rect.center.dy;

    return Stack(
      children: [
        // Selection Outline with rounded corners and glow
        Positioned(
          left: boxLeft,
          top: boxTop,
          width: boxRight - boxLeft,
          height: boxBottom - boxTop,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.8), width: 1.5),
              boxShadow: [BoxShadow(color: Colors.blue.withValues(alpha: 0.15), blurRadius: 10, spreadRadius: 2)],
            ),
          ),
        ),

        // Multi-touch 2-Finger Pinch Scale, Twist Rotate, and Drag Move area
        Positioned(
          left: boxLeft,
          top: boxTop,
          width: boxRight - boxLeft,
          height: boxBottom - boxTop,
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

        // Delete handle (Top Right - Offset above)
        Positioned(
          left: boxRight + 4.0,
          top: boxTop - handleSize - 8.0,
          child: _SelectionHandle(
            icon: LucideIcons.trash2,
            color: Colors.redAccent,
            size: handleSize,
            iconSize: iconSize,
            onTap: () => provider.removeSelectedElements(),
          ),
        ),

        // Rotate handle (Top Center - Offset above)
        Positioned(
          left: boxCenterX - (handleSize / 2),
          top: boxTop - handleSize - 10.0,
          child: _SelectionHandle(
            icon: LucideIcons.rotateCw,
            color: Colors.blue,
            size: handleSize,
            iconSize: iconSize,
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

        // --- 8 DIRECTIONAL RESIZE HANDLES ---

        // 1. Top-Left Corner
        Positioned(
          left: boxLeft - (handleSize / 2),
          top: boxTop - (handleSize / 2),
          child: _SelectionHandle(
            icon: LucideIcons.scaling,
            color: Colors.blue,
            size: handleSize,
            iconSize: iconSize,
            onPanUpdate: (d) => provider.resizeSelectedElement(HandleDirection.topLeft, d.delta),
            onPanStart: (_) => provider.startTransform(),
            onPanEnd: (_) => provider.endTransform(),
          ),
        ),

        // 2. Top-Center Side
        Positioned(
          left: boxCenterX - (sideHandleSize / 2),
          top: boxTop - (sideHandleSize / 2),
          child: _SelectionHandle(
            icon: LucideIcons.chevronsUpDown,
            color: Colors.indigoAccent,
            size: sideHandleSize,
            iconSize: sideIconSize,
            onPanUpdate: (d) => provider.resizeSelectedElement(HandleDirection.topCenter, d.delta),
            onPanStart: (_) => provider.startTransform(),
            onPanEnd: (_) => provider.endTransform(),
          ),
        ),

        // 3. Top-Right Corner
        Positioned(
          left: boxRight - (handleSize / 2),
          top: boxTop - (handleSize / 2),
          child: _SelectionHandle(
            icon: LucideIcons.scaling,
            color: Colors.blue,
            size: handleSize,
            iconSize: iconSize,
            onPanUpdate: (d) => provider.resizeSelectedElement(HandleDirection.topRight, d.delta),
            onPanStart: (_) => provider.startTransform(),
            onPanEnd: (_) => provider.endTransform(),
          ),
        ),

        // 4. Middle-Right Side
        Positioned(
          left: boxRight - (sideHandleSize / 2),
          top: boxCenterY - (sideHandleSize / 2),
          child: _SelectionHandle(
            icon: LucideIcons.chevronsLeftRight,
            color: Colors.indigoAccent,
            size: sideHandleSize,
            iconSize: sideIconSize,
            onPanUpdate: (d) => provider.resizeSelectedElement(HandleDirection.middleRight, d.delta),
            onPanStart: (_) => provider.startTransform(),
            onPanEnd: (_) => provider.endTransform(),
          ),
        ),

        // 5. Bottom-Right Corner
        Positioned(
          left: boxRight - (handleSize / 2),
          top: boxBottom - (handleSize / 2),
          child: _SelectionHandle(
            icon: LucideIcons.scaling,
            color: Colors.blue,
            size: handleSize,
            iconSize: iconSize,
            onPanUpdate: (d) => provider.resizeSelectedElement(HandleDirection.bottomRight, d.delta),
            onPanStart: (_) => provider.startTransform(),
            onPanEnd: (_) => provider.endTransform(),
          ),
        ),

        // 6. Bottom-Center Side
        Positioned(
          left: boxCenterX - (sideHandleSize / 2),
          top: boxBottom - (sideHandleSize / 2),
          child: _SelectionHandle(
            icon: LucideIcons.chevronsUpDown,
            color: Colors.indigoAccent,
            size: sideHandleSize,
            iconSize: sideIconSize,
            onPanUpdate: (d) => provider.resizeSelectedElement(HandleDirection.bottomCenter, d.delta),
            onPanStart: (_) => provider.startTransform(),
            onPanEnd: (_) => provider.endTransform(),
          ),
        ),

        // 7. Bottom-Left Corner
        Positioned(
          left: boxLeft - (handleSize / 2),
          top: boxBottom - (handleSize / 2),
          child: _SelectionHandle(
            icon: LucideIcons.scaling,
            color: Colors.blue,
            size: handleSize,
            iconSize: iconSize,
            onPanUpdate: (d) => provider.resizeSelectedElement(HandleDirection.bottomLeft, d.delta),
            onPanStart: (_) => provider.startTransform(),
            onPanEnd: (_) => provider.endTransform(),
          ),
        ),

        // 8. Middle-Left Side
        Positioned(
          left: boxLeft - (sideHandleSize / 2),
          top: boxCenterY - (sideHandleSize / 2),
          child: _SelectionHandle(
            icon: LucideIcons.chevronsLeftRight,
            color: Colors.indigoAccent,
            size: sideHandleSize,
            iconSize: sideIconSize,
            onPanUpdate: (d) => provider.resizeSelectedElement(HandleDirection.middleLeft, d.delta),
            onPanStart: (_) => provider.startTransform(),
            onPanEnd: (_) => provider.endTransform(),
          ),
        ),
      ],
    );
  }
}

class _SelectionHandle extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;
  final VoidCallback? onTap;
  final Function(DragUpdateDetails)? onPanUpdate;
  final Function(DragStartDetails)? onPanStart;
  final Function(DragEndDetails)? onPanEnd;

  const _SelectionHandle({
    required this.icon,
    required this.color,
    required this.size,
    required this.iconSize,
    this.onTap,
    this.onPanUpdate,
    this.onPanStart,
    this.onPanEnd,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onPanStart: onPanStart,
      onPanUpdate: onPanUpdate,
      onPanEnd: onPanEnd,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Icon(icon, color: color, size: iconSize),
      ),
    );
  }
}
