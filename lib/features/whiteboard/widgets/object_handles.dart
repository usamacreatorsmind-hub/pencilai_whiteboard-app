import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../state/whiteboard_provider.dart';

class ObjectHandles extends StatelessWidget {
  const ObjectHandles({super.key});

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
       groupRect = Rect.fromCenter(
         center: groupRect.center, 
         width: groupRect.width * e.scale, 
         height: groupRect.height * e.scale,
       );
    } else {
      for (var i = 1; i < selectedElements.length; i++) {
        final e = selectedElements[i];
        final r = e.getRawBounds();
        final visualR = Rect.fromCenter(
          center: r.center, 
          width: r.width * e.scale, 
          height: r.height * e.scale,
        );
        groupRect = groupRect.expandToInclude(visualR);
      }
    }

    final rect = groupRect;
    final isLargeScreen = MediaQuery.of(context).size.width > 1200;
    final handleSize = isLargeScreen ? 36.0 : 28.0;
    final iconSize = isLargeScreen ? 20.0 : 16.0;
    final padding = isLargeScreen ? 16.0 : 8.0;

    return Stack(
      children: [
        // Selection Outline with rounded corners and glow
        Positioned(
          left: rect.left - padding,
          top: rect.top - padding,
          width: rect.width + (padding * 2),
          height: rect.height + (padding * 2),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.blue.withOpacity(0.8), 
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.15),
                  blurRadius: 10,
                  spreadRadius: 2,
                )
              ],
            ),
          ),
        ),
        
        // Move area
        Positioned(
          left: rect.left - padding,
          top: rect.top - padding,
          width: rect.width + (padding * 2),
          height: rect.height + (padding * 2),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (d) => provider.startTransform(),
            onPanUpdate: (d) => provider.updateElementTransform(d.delta, 0, 0),
            onPanEnd: (d) => provider.endTransform(),
          ),
        ),

        // Delete handle (Top Right)
        Positioned(
          left: rect.right + padding - (handleSize / 2),
          top: rect.top - padding - (handleSize / 2),
          child: _SelectionHandle(
            icon: LucideIcons.trash2,
            color: Colors.redAccent,
            size: handleSize,
            iconSize: iconSize,
            onTap: () => provider.removeSelectedElements(),
          ),
        ),

        // Rotate handle (Top Center)
        Positioned(
          left: rect.center.dx - (handleSize / 2),
          top: rect.top - padding - handleSize - 10,
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

        // Resize handle (Bottom Right)
        Positioned(
          left: rect.right + padding - (handleSize / 2),
          top: rect.bottom + padding - (handleSize / 2),
          child: _SelectionHandle(
            icon: LucideIcons.maximize2,
            color: Colors.blue,
            size: handleSize,
            iconSize: iconSize,
            onPanUpdate: (d) {
              final center = rect.center;
              final handlePos = Offset(rect.right, rect.bottom);
              final vector = handlePos - center;
              if (vector.distance > 0) {
                final unitVector = Offset(vector.dx / vector.distance, vector.dy / vector.distance);
                final dotProduct = d.delta.dx * unitVector.dx + d.delta.dy * unitVector.dy;
                final scaleDelta = dotProduct / 150.0;
                provider.updateElementTransform(Offset.zero, 0, scaleDelta);
              }
            },
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
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Icon(icon, color: color, size: iconSize),
      ),
    );
  }
}
