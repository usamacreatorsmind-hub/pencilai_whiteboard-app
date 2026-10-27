import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/chemical_element_element.dart';

class ChemicalElementDrawer {
  static void draw(
    Canvas canvas,
    ChemicalElementElement element, {
    bool isSelected = false,
  }) {
    final rect = Rect.fromLTWH(
      element.position.dx,
      element.position.dy,
      element.size.width,
      element.size.height,
    );


    final double scaleX = element.size.width / 150.0;
    final double scaleY = element.size.height / 175.0;
    final double s = min(scaleX, scaleY).clamp(0.4, 4.0);

    final radius = Radius.circular(14.0 * s);
    final rrect = RRect.fromRectAndRadius(rect, radius);

    // 1. Drop shadow / Outer glow
    if (isSelected) {
      final glowPaint = Paint()
        ..color = const Color(0xFF38BDF8).withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.outer, 10.0 * s);
      canvas.drawRRect(rrect, glowPaint);
    } else {
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = MaskFilter.blur(BlurStyle.outer, 6.0 * s);
      canvas.drawRRect(rrect, shadowPaint);
    }

    // 2. Card Background
    final bgPaint = Paint()..color = const Color(0xFF0F172A);
    canvas.drawRRect(rrect, bgPaint);

    // 3. Category Tint Glow Gradient
    final gradientRect = Rect.fromLTWH(
      rect.left,
      rect.top,
      rect.width,
      rect.height * 0.45,
    );
    final headerGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        element.color.withValues(alpha: 0.28),
        element.color.withValues(alpha: 0.0),
      ],
    );
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      gradientRect,
      Paint()..shader = headerGradient.createShader(gradientRect),
    );
    canvas.restore();

    // 4. Card Border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (isSelected ? 2.5 : 1.8) * s
      ..color = isSelected
          ? const Color(0xFF38BDF8)
          : element.color.withValues(alpha: 0.85);
    canvas.drawRRect(rrect, borderPaint);

    // 5. Atomic Number (Top-Left)
    final numSpan = TextSpan(
      text: '${element.atomicNumber}',
      style: TextStyle(
        color: Colors.white,
        fontSize: 16.0 * s,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
    );
    final numPainter = TextPainter(
      text: numSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    numPainter.paint(
      canvas,
      Offset(rect.left + 10.0 * s, rect.top + 8.0 * s),
    );

    // 6. Atomic Mass (Top-Right)
    final massSpan = TextSpan(
      text: element.atomicMass,
      style: TextStyle(
        color: element.color,
        fontSize: 11.0 * s,
        fontWeight: FontWeight.w700,
      ),
    );
    final massPainter = TextPainter(
      text: massSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    massPainter.paint(
      canvas,
      Offset(
        rect.right - massPainter.width - 10.0 * s,
        rect.top + 10.0 * s,
      ),
    );

    // 7. Large Element Symbol (Center)
    final symSpan = TextSpan(
      text: element.symbol,
      style: TextStyle(
        color: Colors.white,
        fontSize: 44.0 * s,
        fontWeight: FontWeight.w900,
        letterSpacing: -1.0,
      ),
    );
    final symPainter = TextPainter(
      text: symSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    final symX = rect.left + (rect.width - symPainter.width) / 2.0;
    final symY = rect.top + 34.0 * s;
    symPainter.paint(canvas, Offset(symX, symY));

    // 8. Element Name (Below Symbol)
    final nameSpan = TextSpan(
      text: element.name,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.95),
        fontSize: 12.5 * s,
        fontWeight: FontWeight.bold,
      ),
    );
    final namePainter = TextPainter(
      text: nameSpan,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: rect.width - 16.0 * s);
    final nameX = rect.left + (rect.width - namePainter.width) / 2.0;
    final nameY = symY + symPainter.height - 2.0 * s;
    namePainter.paint(canvas, Offset(nameX, nameY));

    // 9. Category Pill / Badge (Bottom section)
    final catSpan = TextSpan(
      text: element.category.toUpperCase(),
      style: TextStyle(
        color: element.color,
        fontSize: 8.5 * s,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
      ),
    );
    final catPainter = TextPainter(
      text: catSpan,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: rect.width - 24.0 * s);

    final pillWidth = catPainter.width + 12.0 * s;
    final pillHeight = catPainter.height + 6.0 * s;
    final pillX = rect.left + (rect.width - pillWidth) / 2.0;
    final pillY = nameY + namePainter.height + 6.0 * s;

    final pillRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(pillX, pillY, pillWidth, pillHeight),
      Radius.circular(6.0 * s),
    );
    canvas.drawRRect(
      pillRRect,
      Paint()..color = element.color.withValues(alpha: 0.18),
    );
    canvas.drawRRect(
      pillRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 * s
        ..color = element.color.withValues(alpha: 0.45),
    );
    catPainter.paint(
      canvas,
      Offset(pillX + 6.0 * s, pillY + 3.0 * s),
    );

    // 10. Electron Configuration & State (At bottom)
    final configSpan = TextSpan(
      text: element.electronConfiguration,
      style: TextStyle(
        color: Colors.white60,
        fontSize: 9.0 * s,
        fontWeight: FontWeight.w500,
      ),
    );
    final configPainter = TextPainter(
      text: configSpan,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: rect.width - 16.0 * s);
    final configX = rect.left + (rect.width - configPainter.width) / 2.0;
    final configY = pillY + pillHeight + 5.0 * s;
    if (configY + configPainter.height <= rect.bottom - 4.0 * s) {
      configPainter.paint(canvas, Offset(configX, configY));
    }
  }
}
