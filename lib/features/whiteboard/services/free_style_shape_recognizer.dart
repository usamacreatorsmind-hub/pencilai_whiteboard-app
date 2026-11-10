import 'dart:math';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/shape_element.dart';
import '../models/stroke_element.dart';

/// Result of classifying a single freehand stroke into a clean geometric shape.
class RecognizedFreeStyleShape {
  final ShapeType shapeType;
  final Offset start;
  final Offset end;

  const RecognizedFreeStyleShape({
    required this.shapeType,
    required this.start,
    required this.end,
  });
}

/// Offline geometric classifier that snaps rough freehand strokes into clean
/// geometric [ShapeElement] instances (Line, Arrow, Circle/Oval, Square/Rect,
/// Triangle, Right Triangle, Diamond, Pentagon, Hexagon, Star).
class FreeStyleShapeRecognizer {
  FreeStyleShapeRecognizer._();

  static const int _kSampleCount = 64;

  /// Analyzes [stroke] and returns a clean [ShapeElement] if it reliably
  /// matches a geometric shape, or `null` if it appears to be freehand ink.
  static ShapeElement? recognize(StrokeElement stroke) {
    final classified = classifyPoints(stroke.points);
    if (classified == null) return null;

    return ShapeElement(
      id: const Uuid().v4(),
      position: classified.start,
      shapeType: classified.shapeType,
      endPoint: classified.end,
      color: stroke.color,
      strokeWidth: stroke.strokeWidth,
      showDimensions: true,
      docPage: stroke.docPage,
    );
  }

  /// Classifies raw stroke [points] into a [RecognizedFreeStyleShape], or returns
  /// `null` for tiny taps or unrecognized non-shape scribbles.
  @visibleForTesting
  static RecognizedFreeStyleShape? classifyPoints(List<Offset> rawPoints) {
    if (rawPoints.length < 4) return null;

    final bounds = _computeBounds(rawPoints);
    final double diag = hypot(bounds.width, bounds.height);
    if (max(bounds.width, bounds.height) < 24.0) return null;

    final double pathLength = _polylineLength(rawPoints);
    if (pathLength < 24.0) return null;

    final double startEndDist = (rawPoints.first - rawPoints.last).distance;
    final bool isClosed = startEndDist <= max(32.0, diag * 0.30);

    if (!isClosed) {
      return _classifyOpenStroke(rawPoints, pathLength, startEndDist);
    }

    if (bounds.width < 16.0 && bounds.height < 16.0) return null;
    return _classifyClosedStroke(rawPoints, bounds, diag);
  }

  static RecognizedFreeStyleShape? _classifyOpenStroke(
    List<Offset> points,
    double pathLength,
    double startEndDist,
  ) {
    final samples = _resamplePolyline(points, 36);
    if (samples.length < 4) return null;

    // 1. Check Straight Line fit
    if (startEndDist >= 20.0) {
      final double maxPerp = _maxPerpendicularDistance(
        samples,
        points.first,
        points.last,
      );
      if (maxPerp / startEndDist <= 0.11 &&
          pathLength / startEndDist <= 1.22) {
        final snappedEnd = _snapAxisIfClose(points.first, points.last);
        return RecognizedFreeStyleShape(
          shapeType: ShapeType.line,
          start: points.first,
          end: snappedEnd,
        );
      }
    }

    // 2. Check Single-Stroke Arrow (straight shaft to farthest point + sharp head fold)
    int tipIdx = 0;
    double maxDistFromStart = 0.0;
    for (int i = 1; i < samples.length; i++) {
      final d = (samples[i] - samples.first).distance;
      if (d > maxDistFromStart) {
        maxDistFromStart = d;
        tipIdx = i;
      }
    }
    if (maxDistFromStart >= 30.0 &&
        tipIdx >= (samples.length * 0.45).round() &&
        tipIdx <= samples.length - 4) {
      final tip = samples[tipIdx];
      final shaft = samples.sublist(0, tipIdx + 1);
      final double shaftMaxPerp = _maxPerpendicularDistance(
        shaft,
        samples.first,
        tip,
      );
      final double headDist = (samples.last - tip).distance;
      final Offset shaftDir = (tip - samples.first) / maxDistFromStart;
      final Offset headVec = samples.last - tip;
      final double dot =
          headVec.dx * shaftDir.dx + headVec.dy * shaftDir.dy;
      // Arrowhead wing must fold sharply back (dot < 0) without overshooting shaft
      if (shaftMaxPerp / maxDistFromStart <= 0.14 &&
          headDist >= max(10.0, maxDistFromStart * 0.10) &&
          headDist <= maxDistFromStart * 0.48 &&
          dot < -headDist * 0.35) {
        final snappedTip = _snapAxisIfClose(samples.first, tip);
        return RecognizedFreeStyleShape(
          shapeType: ShapeType.arrow,
          start: samples.first,
          end: snappedTip,
        );
      }
    }

    return null;
  }

  static RecognizedFreeStyleShape? _classifyClosedStroke(
    List<Offset> rawPoints,
    Rect bounds,
    double diag,
  ) {
    final closedLoop = List<Offset>.from(rawPoints)..add(rawPoints.first);
    final pts = _resamplePolyline(closedLoop, _kSampleCount);
    if (pts.length < 16) return null;

    // Require minimum perimeter consistency so tight zigzag scribbles aren't misread.
    final double loopPerimeter = _polylineLength(pts);
    if (loopPerimeter < diag * 1.4 || min(bounds.width, bounds.height) < 12.0) {
      return null;
    }

    final Rect ellipseRect = _fitCircleOrRectBounds(
      bounds,
      squareMinRatio: 0.76,
      squareMaxRatio: 1.32,
    );
    final Rect squareOrRect = _fitCircleOrRectBounds(
      bounds,
      squareMinRatio: 0.78,
      squareMaxRatio: 1.28,
    );

    final double circleRms = _ellipseNormalizedRms(pts, ellipseRect, diag);
    final bool goodAngularSweep = _angularSweepRatio(pts, bounds.center) >= 0.78;

    // Simplified closed polygon for corner / polygon / star inspection
    final poly = _simplifyClosedPolygon(pts, diag * 0.042);
    final double polyRms = poly.length >= 3
        ? _polygonTemplateRms(pts, poly, diag)
        : 1.0;
    final double rectRms = _polygonTemplateRms(
      pts,
      _rectVertices(bounds),
      diag,
    );
    final double diamondRms = _polygonTemplateRms(
      pts,
      _diamondVertices(bounds),
      diag,
    );
    final double starRms = _polygonTemplateRms(
      pts,
      _starVertices(bounds),
      diag,
    );

    // 1. Check 5-Point Star first when radial peaks strongly alternate inner/outer
    if (_looksLikeStar(pts, bounds) && starRms <= 0.10) {
      return RecognizedFreeStyleShape(
        shapeType: ShapeType.star,
        start: squareOrRect.topLeft,
        end: squareOrRect.bottomRight,
      );
    }

    // 2. Check Triangle (arbitrary orientation 3-vertex polygon with straight edges)
    if (poly.length == 3) {
      if (polyRms <= 0.09 &&
          polyRms < circleRms * 0.78 &&
          polyRms < rectRms * 0.80) {
        final ShapeType triType = _isBottomLeftRightTriangle(poly)
            ? ShapeType.rightTriangle
            : ShapeType.triangle;
        return RecognizedFreeStyleShape(
          shapeType: triType,
          start: bounds.topLeft,
          end: bounds.bottomRight,
        );
      }
    }

    // 3. Compare Circle/Ellipse vs Rectangle vs Diamond vs Pentagon vs Hexagon
    final double rawEllipseRms = _ellipseNormalizedRms(pts, bounds, diag);
    final candidates = <({ShapeType type, Rect rect, double rms})>[];

    if (goodAngularSweep) {
      candidates.add((
        type: ShapeType.circle,
        rect: ellipseRect,
        rms: rawEllipseRms,
      ));
    }

    if (poly.length >= 4 && poly.length <= 6) {
      candidates.add((
        type: ShapeType.rectangle,
        rect: squareOrRect,
        rms: rectRms,
      ));
      candidates.add((
        type: ShapeType.diamond,
        rect: bounds,
        rms: diamondRms,
      ));
    }

    if (poly.length == 5 &&
        polyRms <= 0.045 &&
        polyRms < rawEllipseRms * 0.72) {
      candidates.add((
        type: ShapeType.pentagon,
        rect: squareOrRect,
        rms: polyRms,
      ));
    }

    if (poly.length == 6 &&
        polyRms <= 0.042 &&
        polyRms < rawEllipseRms * 0.72) {
      candidates.add((
        type: ShapeType.hexagon,
        rect: squareOrRect,
        rms: polyRms,
      ));
    }

    // Also inspect upward-triangle fallback when poly had 4 vertices with 1 tiny corner
    final double upTriRms = _polygonTemplateRms(
      pts,
      _upwardTriangleVertices(bounds),
      diag,
    );
    if ((poly.length == 3 || poly.length == 4) &&
        upTriRms < rectRms * 0.75 &&
        upTriRms < circleRms * 0.75) {
      candidates.add((
        type: ShapeType.triangle,
        rect: bounds,
        rms: upTriRms,
      ));
    }

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) => a.rms.compareTo(b.rms));
    final best = candidates.first;

    if (best.rms > 0.115) return null;

    return RecognizedFreeStyleShape(
      shapeType: best.type,
      start: best.rect.topLeft,
      end: best.rect.bottomRight,
    );
  }

  static bool _isBottomLeftRightTriangle(List<Offset> tri) {
    if (tri.length != 3) return false;
    for (int i = 0; i < 3; i++) {
      final a = tri[(i + 2) % 3] - tri[i];
      final b = tri[(i + 1) % 3] - tri[i];
      final denom = a.distance * b.distance;
      if (denom < 1e-6) continue;
      final double cosAngle = (a.dx * b.dx + a.dy * b.dy) / denom;
      // Right angle within ~18 degrees
      if (cosAngle.abs() <= 0.31) {
        final bool aAxis =
            a.dx.abs() < a.dy.abs() * 0.35 || a.dy.abs() < a.dx.abs() * 0.35;
        final bool bAxis =
            b.dx.abs() < b.dy.abs() * 0.35 || b.dy.abs() < b.dx.abs() * 0.35;
        if (aAxis && bAxis) {
          // Verify the right-angle vertex sits in the lower-left quadrant of the triangle
          final bounds = _computeBounds(tri);
          return tri[i].dx <= bounds.center.dx && tri[i].dy >= bounds.center.dy;
        }
      }
    }
    return false;
  }

  static bool _looksLikeStar(List<Offset> pts, Rect bounds) {
    final center = bounds.center;
    final radii = pts.map((p) => (p - center).distance).toList();
    final double mean = radii.reduce((a, b) => a + b) / radii.length;
    if (mean < 8.0) return false;
    double variance = 0.0;
    for (final r in radii) {
      variance += (r - mean) * (r - mean);
    }
    final double coeffVar = sqrt(variance / radii.length) / mean;
    if (coeffVar < 0.20) return false;

    int peaks = 0;
    final int n = radii.length;
    for (int i = 0; i < n; i++) {
      final prev = radii[(i - 2 + n) % n];
      final curr = radii[i];
      final next = radii[(i + 2) % n];
      if (curr > prev * 1.08 && curr > next * 1.08 && curr > mean * 1.12) {
        peaks++;
      }
    }
    // Resampled peaks around 5 star arms allow minor double-hits near tips
    return peaks >= 4 && peaks <= 8;
  }

  static Offset _snapAxisIfClose(Offset start, Offset end) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    const double tan6Deg = 0.1051;
    if (dy.abs() <= dx.abs() * tan6Deg) {
      return Offset(end.dx, start.dy);
    }
    if (dx.abs() <= dy.abs() * tan6Deg) {
      return Offset(start.dx, end.dy);
    }
    return end;
  }

  static Rect _fitCircleOrRectBounds(
    Rect bounds, {
    required double squareMinRatio,
    required double squareMaxRatio,
  }) {
    if (bounds.height <= 0) return bounds;
    final double aspect = bounds.width / bounds.height;
    if (aspect >= squareMinRatio && aspect <= squareMaxRatio) {
      final double side = (bounds.width + bounds.height) * 0.5;
      return Rect.fromCenter(
        center: bounds.center,
        width: side,
        height: side,
      );
    }
    return bounds;
  }

  static double _ellipseNormalizedRms(
    List<Offset> pts,
    Rect rect,
    double diag,
  ) {
    final double rx = max(1.0, rect.width * 0.5);
    final double ry = max(1.0, rect.height * 0.5);
    final center = rect.center;
    double sumSq = 0.0;
    for (final p in pts) {
      final dx = p.dx - center.dx;
      final dy = p.dy - center.dy;
      final double normR = hypot(dx / rx, dy / ry);
      if (normR < 1e-6) {
        sumSq += min(rx, ry) * min(rx, ry);
      } else {
        final double projX = center.dx + dx / normR;
        final double projY = center.dy + dy / normR;
        final double dist = hypot(p.dx - projX, p.dy - projY);
        sumSq += dist * dist;
      }
    }
    return sqrt(sumSq / pts.length) / max(1.0, diag);
  }

  static double _angularSweepRatio(List<Offset> pts, Offset center) {
    const int buckets = 16;
    final hit = List<bool>.filled(buckets, false);
    for (final p in pts) {
      final angle = atan2(p.dy - center.dy, p.dx - center.dx) + pi;
      final idx = ((angle / (2 * pi)) * buckets).floor().clamp(0, buckets - 1);
      hit[idx] = true;
    }
    final count = hit.where((h) => h).length;
    return count / buckets;
  }

  static double _polygonTemplateRms(
    List<Offset> pts,
    List<Offset> poly,
    double diag,
  ) {
    if (poly.length < 2) return 1.0;
    double sumSq = 0.0;
    for (final p in pts) {
      double minDist = double.infinity;
      for (int i = 0; i < poly.length; i++) {
        final a = poly[i];
        final b = poly[(i + 1) % poly.length];
        final d = _pointToSegmentDistance(p, a, b);
        if (d < minDist) minDist = d;
      }
      sumSq += minDist * minDist;
    }
    return sqrt(sumSq / pts.length) / max(1.0, diag);
  }

  static List<Offset> _rectVertices(Rect r) => [
    r.topLeft,
    r.topRight,
    r.bottomRight,
    r.bottomLeft,
  ];

  static List<Offset> _diamondVertices(Rect r) => [
    Offset(r.center.dx, r.top),
    Offset(r.right, r.center.dy),
    Offset(r.center.dx, r.bottom),
    Offset(r.left, r.center.dy),
  ];

  static List<Offset> _upwardTriangleVertices(Rect r) => [
    Offset(r.center.dx, r.top),
    r.bottomRight,
    r.bottomLeft,
  ];

  static List<Offset> _starVertices(Rect r) {
    final center = r.center;
    final radius = r.width * 0.5;
    final innerRadius = radius / 2.5;
    const points = 5;
    return List.generate(points * 2, (i) {
      final angle = (i * pi) / points - pi / 2;
      final rad = i.isEven ? radius : innerRadius;
      return Offset(
        center.dx + rad * cos(angle),
        center.dy + rad * sin(angle),
      );
    });
  }

  static List<Offset> _simplifyClosedPolygon(
    List<Offset> pts,
    double epsilon,
  ) {
    if (pts.length <= 3) return pts;
    // Split closed loop at the pair of vertices farthest apart so endpoints don't create fake cuts.
    int maxIdx = 1;
    double maxDist = 0.0;
    for (int i = 1; i < pts.length; i++) {
      final d = (pts[i] - pts[0]).distance;
      if (d > maxDist) {
        maxDist = d;
        maxIdx = i;
      }
    }
    final part1 = _rdp(pts.sublist(0, maxIdx + 1), epsilon);
    final part2 = _rdp([...pts.sublist(maxIdx), pts.first], epsilon);
    final combined = [...part1, ...part2.skip(1)];
    if (combined.length > 1 &&
        (combined.first - combined.last).distance < epsilon * 0.5) {
      combined.removeLast();
    }

    // Merge near-collinear consecutive edges (< 22 degrees turn)
    bool merged = true;
    while (merged && combined.length > 3) {
      merged = false;
      for (int i = 0; i < combined.length; i++) {
        final prev = combined[(i - 1 + combined.length) % combined.length];
        final curr = combined[i];
        final next = combined[(i + 1) % combined.length];
        final v1 = curr - prev;
        final v2 = next - curr;
        if (v1.distance < epsilon * 0.6) {
          combined.removeAt(i);
          merged = true;
          break;
        }
        final double denom = v1.distance * v2.distance;
        if (denom > 1e-6) {
          final double cosTurn = (v1.dx * v2.dx + v1.dy * v2.dy) / denom;
          if (cosTurn > 0.925) {
            // < ~22.3 deg bend
            combined.removeAt(i);
            merged = true;
            break;
          }
        }
      }
    }
    return combined;
  }

  static List<Offset> _rdp(List<Offset> points, double epsilon) {
    if (points.length <= 2) return points;
    double maxDist = 0.0;
    int index = 0;
    final start = points.first;
    final end = points.last;
    for (int i = 1; i < points.length - 1; i++) {
      final d = _pointToSegmentDistance(points[i], start, end);
      if (d > maxDist) {
        maxDist = d;
        index = i;
      }
    }
    if (maxDist > epsilon) {
      final left = _rdp(points.sublist(0, index + 1), epsilon);
      final right = _rdp(points.sublist(index), epsilon);
      return [...left.take(left.length - 1), ...right];
    }
    return [start, end];
  }

  static Rect _computeBounds(List<Offset> pts) {
    double minX = pts.first.dx;
    double maxX = pts.first.dx;
    double minY = pts.first.dy;
    double maxY = pts.first.dy;
    for (final p in pts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  static double _polylineLength(List<Offset> pts) {
    double len = 0.0;
    for (int i = 1; i < pts.length; i++) {
      len += (pts[i] - pts[i - 1]).distance;
    }
    return len;
  }

  static List<Offset> _resamplePolyline(List<Offset> pts, int count) {
    final total = _polylineLength(pts);
    if (total < 1e-6 || pts.length < 2) return List<Offset>.from(pts);
    final double step = total / (count - 1);
    final resampled = <Offset>[pts.first];
    double accumulated = 0.0;
    final src = List<Offset>.from(pts);
    int i = 1;
    while (i < src.length) {
      final prev = src[i - 1];
      final curr = src[i];
      final segLen = (curr - prev).distance;
      if (accumulated + segLen >= step) {
        final t = (step - accumulated) / segLen;
        final nextPt = Offset(
          prev.dx + t * (curr.dx - prev.dx),
          prev.dy + t * (curr.dy - prev.dy),
        );
        resampled.add(nextPt);
        src.insert(i, nextPt);
        accumulated = 0.0;
        i++;
      } else {
        accumulated += segLen;
        i++;
      }
    }
    while (resampled.length < count) {
      resampled.add(pts.last);
    }
    return resampled.take(count).toList();
  }

  static double _maxPerpendicularDistance(
    List<Offset> pts,
    Offset a,
    Offset b,
  ) {
    double best = 0.0;
    for (final p in pts) {
      final d = _pointToSegmentDistance(p, a, b);
      if (d > best) best = d;
    }
    return best;
  }

  static double _pointToSegmentDistance(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq < 1e-9) return (p - a).distance;
    final t = (((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / lenSq).clamp(
      0.0,
      1.0,
    );
    final proj = Offset(a.dx + t * dx, a.dy + t * dy);
    return (p - proj).distance;
  }

  static double hypot(double a, double b) => sqrt(a * a + b * b);
}
