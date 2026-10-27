import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/mind_map_element.dart';

/// Helper class for drawing mindmap nodes, connectors, action buttons, expand/collapse toggles, and handwriting strokes on a [Canvas].
class MindMapDrawer {
  MindMapDrawer._();

  /// Renders a [MindMapElement] starting from its root or specified node.
  static void drawMindMapNodeTree(
    Canvas canvas,
    MindMapElement mm,
    MindMapNode node,
    Offset basePos,
  ) {
    final localPos = basePos + node.relativeOffset;
    final hasChildren = node.children.isNotEmpty;
    final showChildren = hasChildren && !node.collapsed;

    final branchPaint = Paint()
      ..color = node.fillColor
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 1. Connector lines
    if (hasChildren) {
      final parentRight = Offset(
        localPos.dx + node.width,
        localPos.dy + node.height / 2,
      );
      final midX = parentRight.dx + MindMapElement.kToggleX;

      // stem: parent -> toggle button (collapsed ho tab bhi line dikhe)
      canvas.drawLine(parentRight, Offset(midX, parentRight.dy), branchPaint);

      if (showChildren) {
        final first = node.children.first;
        final last = node.children.last;
        final firstY = basePos.dy + first.relativeOffset.dy + first.height / 2;
        final lastY = basePos.dy + last.relativeOffset.dy + last.height / 2;

        // trunk
        canvas.drawLine(Offset(midX, firstY), Offset(midX, lastY), branchPaint);

        // branches
        for (final child in node.children) {
          final cp = basePos + child.relativeOffset;
          final cy = cp.dy + child.height / 2;
          canvas.drawLine(Offset(midX, cy), Offset(cp.dx, cy), branchPaint);
        }
      }
    }

    // 2. Node box
    final nodeRect = Rect.fromLTWH(
      localPos.dx,
      localPos.dy,
      node.width,
      node.height,
    );
    final nodeRRect = RRect.fromRectAndRadius(
      nodeRect,
      const Radius.circular(10.0),
    );
    final isSelected = (mm.selectedNodeId == node.id);

    // Box Background Fill (Teal #00BFA5)
    canvas.drawRRect(nodeRRect, Paint()..color = node.fillColor);

    if (isSelected) {
      // Single clean light blue border around box
      final lightBlueBorderRRect = RRect.fromRectAndRadius(
        nodeRect.inflate(3.5),
        const Radius.circular(13.0),
      );
      canvas.drawRRect(
        lightBlueBorderRRect,
        Paint()
          ..color =
              const Color(0xFF38BDF8) // Crisp Light Blue (#38BDF8)
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke,
      );
    } else {
      // Unselected box border
      canvas.drawRRect(
        nodeRRect,
        Paint()
          ..color = node.fillColor.withValues(alpha: 0.8)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke,
      );
    }

    // 3. Text
    if (node.text.isNotEmpty) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: node.text,
          style: TextStyle(
            color: node.textColor,
            fontSize: 15.0,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      textPainter.layout(
        maxWidth: max(10.0, min(MindMapNode.kMaxTextW, node.width - 16.0)),
      );
      textPainter.paint(
        canvas,
        Offset(
          localPos.dx + (node.width - textPainter.width) / 2,
          localPos.dy + (node.height - textPainter.height) / 2,
        ),
      );
    }

    // 4. Handwriting
    if (node.strokes.isNotEmpty) {
      for (int i = 0; i < node.strokes.length; i++) {
        final stroke = node.strokes[i];
        final strokeColor = (i < node.strokeColors.length)
            ? node.strokeColors[i]
            : node.textColor;

        if (stroke.length > 1) {
          final strokePaint = Paint()
            ..color = strokeColor
            ..strokeWidth = 2.5
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round;

          final path = Path()
            ..moveTo(localPos.dx + stroke[0].dx, localPos.dy + stroke[0].dy);
          for (int j = 1; j < stroke.length; j++) {
            path.lineTo(localPos.dx + stroke[j].dx, localPos.dy + stroke[j].dy);
          }
          canvas.drawPath(path, strokePaint);
        } else if (stroke.length == 1) {
          final dotPaint = Paint()
            ..color = strokeColor
            ..style = PaintingStyle.fill;
          canvas.drawCircle(
            Offset(localPos.dx + stroke[0].dx, localPos.dy + stroke[0].dy),
            1.5,
            dotPaint,
          );
        }
      }
    }

    // 5. Collapse / expand button (+ / -) connector line par
    if (hasChildren) {
      final c = basePos + mm.btnCenter(node, MindMapAction.toggle);
      canvas.drawCircle(c, 7.5, Paint()..color = Colors.white);
      canvas.drawCircle(
        c,
        7.5,
        Paint()
          ..color = const Color(0xFF64748B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      final iconPaint = Paint()
        ..color = const Color(0xFF334155)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(c.dx - 3.5, c.dy),
        Offset(c.dx + 3.5, c.dy),
        iconPaint,
      ); // "-"
      if (node.collapsed) {
        canvas.drawLine(
          Offset(c.dx, c.dy - 3.5),
          Offset(c.dx, c.dy + 3.5),
          iconPaint,
        ); // "+"
      }
    }

    // 6. Selected node ke action buttons
    if (isSelected) {
      final btnPaint = Paint()..color = const Color(0xFF2563EB);
      final borderPaint = Paint()
        ..color = const Color(0xFF1E40AF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      final dotPaint = Paint()..color = Colors.white;
      final plusPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      void plus(MindMapAction a) {
        final c = basePos + mm.btnCenter(node, a);
        canvas.drawCircle(c, 8.5, btnPaint);
        canvas.drawCircle(c, 8.5, borderPaint);
        canvas.drawLine(
          Offset(c.dx - 3.8, c.dy),
          Offset(c.dx + 3.8, c.dy),
          plusPaint,
        );
        canvas.drawLine(
          Offset(c.dx, c.dy - 3.8),
          Offset(c.dx, c.dy + 3.8),
          plusPaint,
        );
      }


      // "..." (delete)
      final top = basePos + mm.btnCenter(node, MindMapAction.menu);
      canvas.drawCircle(top, 8.5, btnPaint);
      canvas.drawCircle(top, 8.5, borderPaint);
      canvas.drawCircle(Offset(top.dx - 3.0, top.dy), 1.0, dotPaint);
      canvas.drawCircle(top, 1.0, dotPaint);
      canvas.drawCircle(Offset(top.dx + 3.0, top.dy), 1.0, dotPaint);

      plus(MindMapAction.addParent); // Left: add box on left
      plus(MindMapAction.addChild); // Right: add box on right
      plus(MindMapAction.addSibling); // Bottom: add box on bottom
    }

    // 7. Children (collapsed ho toh skip)
    if (showChildren) {
      for (final child in node.children) {
        drawMindMapNodeTree(canvas, mm, child, basePos);
      }
    }
  }
}
