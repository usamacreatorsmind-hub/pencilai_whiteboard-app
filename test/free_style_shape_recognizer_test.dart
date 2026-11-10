import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pencilai_whitebaord_app/features/whiteboard/models/shape_element.dart';
import 'package:pencilai_whitebaord_app/features/whiteboard/models/stroke_element.dart';
import 'package:pencilai_whitebaord_app/features/whiteboard/services/free_style_shape_recognizer.dart';
import 'package:pencilai_whitebaord_app/features/whiteboard/state/whiteboard_provider.dart';
import 'package:pencilai_whitebaord_app/features/whiteboard/widgets/toolbar.dart';
import 'package:pencilai_whitebaord_app/features/whiteboard/widgets/whiteboard_canvas.dart';

List<Offset> _samplePolygonStroke(
  List<Offset> vertices, {
  int stepsPerEdge = 10,
  double jitter = 0.0,
}) {
  final rand = Random(42);
  final points = <Offset>[];
  for (int i = 0; i < vertices.length; i++) {
    final a = vertices[i];
    final b = vertices[(i + 1) % vertices.length];
    for (int s = 0; s < stepsPerEdge; s++) {
      final t = s / stepsPerEdge;
      final jx = jitter > 0 ? (rand.nextDouble() - 0.5) * 2 * jitter : 0.0;
      final jy = jitter > 0 ? (rand.nextDouble() - 0.5) * 2 * jitter : 0.0;
      points.add(Offset.lerp(a, b, t)! + Offset(jx, jy));
    }
  }
  points.add(vertices.first);
  return points;
}

StrokeElement _strokeFrom(List<Offset> points, {Color color = Colors.blue}) {
  return StrokeElement(
    id: 'test_stroke',
    position: points.first,
    points: points,
    color: color,
    strokeWidth: 4.0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FreeStyleShapeRecognizer geometric accuracy tests', () {
    test('recognizes shaky hand-drawn circle as square-snapped ShapeType.circle', () {
      final rand = Random(7);
      const center = Offset(300, 240);
      final pts = <Offset>[];
      for (int i = 0; i <= 40; i++) {
        final angle = (i / 40) * 2 * pi;
        final rx = 80.0 + (rand.nextDouble() - 0.5) * 10.0;
        final ry = 76.0 + (rand.nextDouble() - 0.5) * 10.0;
        pts.add(Offset(center.dx + rx * cos(angle), center.dy + ry * sin(angle)));
      }

      final shape = FreeStyleShapeRecognizer.recognize(_strokeFrom(pts));
      expect(shape, isNotNull);
      expect(shape!.shapeType, equals(ShapeType.circle));
      expect(shape.color, equals(Colors.blue));
      expect(shape.strokeWidth, equals(4.0));
      final rect = Rect.fromPoints(shape.position, shape.endPoint);
      // Nearly circular bounding box snaps width == height
      expect((rect.width - rect.height).abs(), lessThan(1.0));
    });

    test('recognizes wide hand-drawn oval as elliptical ShapeType.circle', () {
      final pts = <Offset>[];
      for (int i = 0; i <= 44; i++) {
        final angle = (i / 44) * 2 * pi;
        pts.add(Offset(300 + 130 * cos(angle), 220 + 60 * sin(angle)));
      }

      final shape = FreeStyleShapeRecognizer.recognize(_strokeFrom(pts));
      expect(shape, isNotNull);
      expect(shape!.shapeType, equals(ShapeType.circle));
      final rect = Rect.fromPoints(shape.position, shape.endPoint);
      expect(rect.width, greaterThan(rect.height * 1.8));
    });

    test('recognizes shaky square and wide rectangle cleanly', () {
      final squarePts = _samplePolygonStroke(
        const [
          Offset(100, 100),
          Offset(240, 104),
          Offset(236, 238),
          Offset(102, 242),
        ],
        jitter: 4.0,
      );
      final square = FreeStyleShapeRecognizer.recognize(_strokeFrom(squarePts));
      expect(square, isNotNull);
      expect(square!.shapeType, equals(ShapeType.rectangle));
      final sqRect = Rect.fromPoints(square.position, square.endPoint);
      expect((sqRect.width - sqRect.height).abs(), lessThan(1.0));

      final rectPts = _samplePolygonStroke(
        const [
          Offset(100, 100),
          Offset(340, 102),
          Offset(338, 210),
          Offset(102, 208),
        ],
        jitter: 3.5,
      );
      final rect = FreeStyleShapeRecognizer.recognize(_strokeFrom(rectPts));
      expect(rect, isNotNull);
      expect(rect!.shapeType, equals(ShapeType.rectangle));
      final rBounds = Rect.fromPoints(rect.position, rect.endPoint);
      expect(rBounds.width, greaterThan(rBounds.height * 1.8));
    });

    test('recognizes equilateral triangle and bottom-left right triangle', () {
      final triPts = _samplePolygonStroke(
        const [
          Offset(200, 90),
          Offset(290, 230),
          Offset(110, 232),
        ],
        jitter: 3.5,
      );
      final tri = FreeStyleShapeRecognizer.recognize(_strokeFrom(triPts));
      expect(tri, isNotNull);
      expect(tri!.shapeType, equals(ShapeType.triangle));

      final rightTriPts = _samplePolygonStroke(
        const [
          Offset(120, 100),
          Offset(122, 240),
          Offset(270, 238),
        ],
        jitter: 2.5,
      );
      final rightTri = FreeStyleShapeRecognizer.recognize(_strokeFrom(rightTriPts));
      expect(rightTri, isNotNull);
      expect(rightTri!.shapeType, equals(ShapeType.rightTriangle));
    });

    test('recognizes diamond, pentagon, hexagon, and star', () {
      final diamondPts = _samplePolygonStroke(
        const [
          Offset(200, 100),
          Offset(290, 190),
          Offset(200, 280),
          Offset(110, 190),
        ],
        jitter: 3.0,
      );
      expect(
        FreeStyleShapeRecognizer.recognize(_strokeFrom(diamondPts))?.shapeType,
        equals(ShapeType.diamond),
      );

      final pentVertices = List.generate(5, (i) {
        final a = (i * 2 * pi) / 5 - pi / 2;
        return Offset(250 + 90 * cos(a), 200 + 90 * sin(a));
      });
      expect(
        FreeStyleShapeRecognizer.recognize(
          _strokeFrom(_samplePolygonStroke(pentVertices, jitter: 2.5)),
        )?.shapeType,
        equals(ShapeType.pentagon),
      );

      final hexVertices = List.generate(6, (i) {
        final a = (i * 2 * pi) / 6 - pi / 2;
        return Offset(250 + 90 * cos(a), 200 + 90 * sin(a));
      });
      expect(
        FreeStyleShapeRecognizer.recognize(
          _strokeFrom(_samplePolygonStroke(hexVertices, jitter: 2.5)),
        )?.shapeType,
        equals(ShapeType.hexagon),
      );

      final starVertices = List.generate(10, (i) {
        final a = (i * pi) / 5 - pi / 2;
        final r = i.isEven ? 95.0 : 38.0;
        return Offset(250 + r * cos(a), 200 + r * sin(a));
      });
      expect(
        FreeStyleShapeRecognizer.recognize(
          _strokeFrom(_samplePolygonStroke(starVertices, stepsPerEdge: 6)),
        )?.shapeType,
        equals(ShapeType.star),
      );
    });

    test('recognizes straight line (with axis snap) and single-stroke arrow', () {
      final linePts = List.generate(
        18,
        (i) => Offset(100.0 + i * 12.0, 200.0 + (i % 2 == 0 ? 1.5 : -1.5)),
      );
      final line = FreeStyleShapeRecognizer.recognize(_strokeFrom(linePts));
      expect(line, isNotNull);
      expect(line!.shapeType, equals(ShapeType.line));
      expect((line.position.dy - line.endPoint.dy).abs(), lessThan(0.01));

      // Single-stroke rightward arrow (shaft -> tip -> folded wing)
      final arrowPts = <Offset>[];
      for (int i = 0; i <= 16; i++) {
        arrowPts.add(Offset(100.0 + i * 10.0, 200.0));
      }
      arrowPts.addAll(const [
        Offset(248.0, 188.0),
        Offset(236.0, 178.0),
      ]);
      final arrow = FreeStyleShapeRecognizer.recognize(_strokeFrom(arrowPts));
      expect(arrow, isNotNull);
      expect(arrow!.shapeType, equals(ShapeType.arrow));
      expect(arrow.endPoint.dx, greaterThan(240.0));
    });

    test('returns null for tiny accidental taps or messy wavy scribbles', () {
      final tiny = _strokeFrom(const [Offset(10, 10), Offset(14, 12), Offset(16, 13), Offset(18, 14)]);
      expect(FreeStyleShapeRecognizer.recognize(tiny), isNull);

      final wave = <Offset>[];
      for (int i = 0; i < 40; i++) {
        wave.add(Offset(80.0 + i * 7.0, 200.0 + 35.0 * sin(i * 0.8)));
      }
      expect(FreeStyleShapeRecognizer.recognize(_strokeFrom(wave)), isNull);
    });
  });

  group('Free Style Shape UI & Canvas integration tests', () {
    testWidgets('selecting Free Style Shape in picker lets pen stroke auto-convert to clean circle with undo', (tester) async {
      final provider = WhiteboardProvider();
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<WhiteboardProvider>.value(
          value: provider,
          child: const MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  SizedBox(width: 800, height: 600, child: WhiteboardCanvas()),
                  Align(alignment: Alignment.bottomCenter, child: WhiteboardToolbar()),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Open Shape Picker and tap "Free Style Shape (Auto Convert)"
      await tester.tap(find.text('Shape'));
      await tester.pumpAndSettle();
      expect(find.text('Free Style Shape (Auto Convert)'), findsOneWidget);

      await tester.tap(find.text('Free Style Shape (Auto Convert)'));
      await tester.pumpAndSettle();

      expect(provider.currentTool, equals(WhiteboardTool.shape));
      expect(provider.isFreeStyleShape, isTrue);

      // Draw a rough circle freehand on the canvas
      const center = Offset(380, 250);
      final gesture = await tester.startGesture(center + const Offset(75, 0));
      for (int i = 1; i <= 28; i++) {
        final a = (i / 28) * 2 * pi;
        await gesture.moveTo(center + Offset(75 * cos(a), 72 * sin(a)));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await gesture.up();
      await tester.pump();

      expect(provider.currentPage.elements.length, equals(1));
      final created = provider.currentPage.elements.first;
      expect(created, isA<ShapeElement>());
      expect((created as ShapeElement).shapeType, equals(ShapeType.circle));

      // Undo removes the converted shape cleanly
      provider.undo();
      expect(provider.currentPage.elements, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}

