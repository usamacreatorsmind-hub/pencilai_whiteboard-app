import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pencilai_whitebaord_app/features/whiteboard/models/stroke_element.dart';
import 'package:pencilai_whitebaord_app/features/whiteboard/state/whiteboard_provider.dart';
import 'package:pencilai_whitebaord_app/features/whiteboard/widgets/canvas/canvas_pointer_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Multi-Finger Pen & Palm/Backhand Eraser Tests', () {
    late CanvasPointerManager manager;

    setUp(() {
      manager = CanvasPointerManager();
    });

    tearDown(() {
      manager.dispose();
    });

    testWidgets(
      '2 fingers, 3 fingers, 4 fingers with normal radius/size DO NOT trigger eraser mode',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                manager.init(context);
                return const SizedBox();
              },
            ),
          ),
        );

        final context = tester.element(find.byType(SizedBox));

        // Simulate 4 simultaneous fingertips
        final finger1 = const PointerDownEvent(
          pointer: 1,
          position: Offset(100, 100),
          radiusMajor: 3.0,
          radiusMinor: 2.5,
          size: 0.02,
        );
        manager.pointers[1] = finger1;
        manager.lastSeen[1] = DateTime.now();

        final finger2 = const PointerDownEvent(
          pointer: 2,
          position: Offset(130, 100),
          radiusMajor: 3.2,
          radiusMinor: 2.8,
          size: 0.025,
        );
        manager.pointers[2] = finger2;
        manager.lastSeen[2] = DateTime.now();

        final finger3 = const PointerDownEvent(
          pointer: 3,
          position: Offset(160, 100),
          radiusMajor: 3.5,
          radiusMinor: 2.6,
          size: 0.02,
        );
        manager.pointers[3] = finger3;
        manager.lastSeen[3] = DateTime.now();

        final finger4 = const PointerDownEvent(
          pointer: 4,
          position: Offset(190, 100),
          radiusMajor: 3.1,
          radiusMinor: 2.4,
          size: 0.022,
        );
        manager.pointers[4] = finger4;
        manager.lastSeen[4] = DateTime.now();

        // None of the fingers should be falsely identified as palm or backhand
        expect(manager.isPalm(finger1), isFalse);
        expect(manager.isPalm(finger2), isFalse);
        expect(manager.isPalm(finger3), isFalse);
        expect(manager.isPalm(finger4), isFalse);

        // 2 fingers, 3 fingers, and 4 fingers must NOT trigger eraser mode
        expect(manager.isEraserMode(finger1, context), isFalse);
        expect(manager.isEraserMode(finger2, context), isFalse);
        expect(manager.isEraserMode(finger3, context), isFalse);
        expect(manager.isEraserMode(finger4, context), isFalse);
      },
    );

    testWidgets(
      'Palm contact (radius >= 15.0 or size >= 0.16) DOES trigger eraser mode',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                manager.init(context);
                return const SizedBox();
              },
            ),
          ),
        );

        final context = tester.element(find.byType(SizedBox));

        // Palm with large radius (>= 15mm)
        final palmByRadius = const PointerDownEvent(
          pointer: 10,
          position: Offset(300, 300),
          radiusMajor: 16.0,
          radiusMinor: 14.0,
          size: 0.18,
        );
        expect(manager.isPalm(palmByRadius), isTrue);
        expect(manager.isEraserMode(palmByRadius, context), isTrue);

        // Palm with large size (>= 0.16)
        final palmBySize = const PointerDownEvent(
          pointer: 11,
          position: Offset(300, 300),
          size: 0.20,
        );
        expect(manager.isPalm(palmBySize), isTrue);
        expect(manager.isEraserMode(palmBySize, context), isTrue);
      },
    );

    testWidgets(
      'Backhand / knuckle contact (radius >= 11.0 or size >= 0.09) DOES trigger eraser mode',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                manager.init(context);
                return const SizedBox();
              },
            ),
          ),
        );

        final context = tester.element(find.byType(SizedBox));

        // Backhand contact (knuckles / edge of hand >= 11mm)
        final backhandByRadius = const PointerDownEvent(
          pointer: 20,
          position: Offset(400, 400),
          radiusMajor: 12.0,
          radiusMinor: 11.0,
          size: 0.10,
        );
        expect(manager.isPalm(backhandByRadius), isTrue);
        expect(manager.isEraserMode(backhandByRadius, context), isTrue);

        // Backhand contact by size (>= 0.09)
        final backhandBySize = const PointerDownEvent(
          pointer: 21,
          position: Offset(400, 400),
          size: 0.12,
        );
        expect(manager.isPalm(backhandBySize), isTrue);
        expect(manager.isEraserMode(backhandBySize, context), isTrue);
      },
    );

    testWidgets(
      'Native hardware palm hint (toolType == 5) triggers eraser mode',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                manager.init(context);
                return const SizedBox();
              },
            ),
          ),
        );

        final context = tester.element(find.byType(SizedBox));

        manager.nativeTouchHints[30] = {
          'toolType': 5, // TOOL_TYPE_PALM
          'isCanceled': false,
        };

        final hardwarePalm = const PointerDownEvent(
          pointer: 30,
          position: Offset(500, 500),
          radiusMajor: 3.0,
        );

        expect(manager.isPalm(hardwarePalm), isTrue);
        expect(manager.isEraserMode(hardwarePalm, context), isTrue);
      },
    );

    testWidgets(
      '5 fingers (whole hand) triggers eraser mode and maintains consistent actual radius without stretching',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                manager.init(context);
                return const SizedBox();
              },
            ),
          ),
        );

        final context = tester.element(find.byType(SizedBox));

        // Add 5 fingers (normal fingertip contact)
        for (int i = 1; i <= 5; i++) {
          final finger = PointerDownEvent(
            pointer: i,
            position: Offset(100.0 + i * 25, 200),
            radiusMajor: 2.5,
            size: 0.015,
          );
          manager.pointers[i] = finger;
          manager.lastSeen[i] = DateTime.now();
        }

        final fifthFinger = manager.pointers[5]!;

        // Individual fingers are not palms
        expect(manager.isPalm(fifthFinger), isFalse);

        // But all 5 fingers together trigger eraser mode!
        expect(manager.isEraserMode(fifthFinger, context), isTrue);

        // Eraser radius does NOT auto-stretch to 75.0, it remains fixed at actual eraser size (60.0)
        expect(
          manager.gestureEraseRadius(),
          equals(CanvasPointerManager.kStaticGestureEraserRadius),
        );

        // Smooth tracking follows hand without lagging behind
        final rawCenter = const Offset(150, 200);
        manager.gestureCenter = const Offset(140, 200);
        final smoothed = manager.smoothGestureCenter(rawCenter);
        expect(
          (smoothed - rawCenter).distance,
          lessThan(2.0),
          reason:
              'Smooth tracking should follow hand closely with zero dragging lag',
        );
      },
    );

    testWidgets(
      'Drawing with multiple fingers creates active pen strokes and normal finger movement does not trigger eraser mode',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                manager.init(context);
                return const SizedBox();
              },
            ),
          ),
        );

        final context = tester.element(find.byType(SizedBox));

        // User starts drawing with 3 fingers:
        final finger1 = const PointerDownEvent(
          pointer: 1,
          position: Offset(100, 100),
          radiusMajor: 3.0,
          size: 0.02,
        );
        final finger2 = const PointerDownEvent(
          pointer: 2,
          position: Offset(140, 100),
          radiusMajor: 3.0,
          size: 0.02,
        );
        final finger3 = const PointerDownEvent(
          pointer: 3,
          position: Offset(180, 100),
          radiusMajor: 3.0,
          size: 0.02,
        );

        manager.pointers[1] = finger1;
        manager.pointers[2] = finger2;
        manager.pointers[3] = finger3;
        manager.lastSeen[1] = DateTime.now();
        manager.lastSeen[2] = DateTime.now();
        manager.lastSeen[3] = DateTime.now();

        // Active stroke elements added for all 3 fingers
        manager.activeElements[1] = StrokeElement(
          id: 's1',
          position: const Offset(100, 100),
          points: [const Offset(100, 100)],
          color: Colors.black,
          strokeWidth: 4.0,
        );
        manager.activeElements[2] = StrokeElement(
          id: 's2',
          position: const Offset(140, 100),
          points: [const Offset(140, 100)],
          color: Colors.black,
          strokeWidth: 4.0,
        );
        manager.activeElements[3] = StrokeElement(
          id: 's3',
          position: const Offset(180, 100),
          points: [const Offset(180, 100)],
          color: Colors.black,
          strokeWidth: 4.0,
        );

        // While moving fingers, moving fingertip events MUST NOT enter eraser mode
        final moveEvent = const PointerMoveEvent(
          pointer: 1,
          position: Offset(105, 105),
          size: 0.03,
          radiusMajor: 3.5,
        );
        expect(manager.isEraserMode(moveEvent, context), isFalse);

        // Active strokes remain intact
        expect(manager.activeElements.length, equals(3));
        expect(manager.isUsingGestureEraser, isFalse);
      },
    );

    testWidgets(
      'Toolbox eraser: 2 or 4 fingers down always shows ONLY 1 single eraser circle at centroid',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                manager.init(context);
                return const SizedBox();
              },
            ),
          ),
        );

        final context = tester.element(find.byType(SizedBox));
        final provider = WhiteboardProvider();

        // 1. Put down 4 fingers simultaneously on canvas in toolbox eraser mode
        manager.pointers[1] = const PointerDownEvent(
          pointer: 1,
          position: Offset(100, 100),
        );
        manager.pointers[2] = const PointerDownEvent(
          pointer: 2,
          position: Offset(140, 100),
        );
        manager.pointers[3] = const PointerDownEvent(
          pointer: 3,
          position: Offset(180, 100),
        );
        manager.pointers[4] = const PointerDownEvent(
          pointer: 4,
          position: Offset(220, 100),
        );

        manager.handleToolEraserDown(
          1,
          const Offset(100, 100),
          provider,
          context,
          true,
        );
        manager.handleToolEraserDown(
          2,
          const Offset(140, 100),
          provider,
          context,
          true,
        );
        manager.handleToolEraserDown(
          3,
          const Offset(180, 100),
          provider,
          context,
          true,
        );
        manager.handleToolEraserDown(
          4,
          const Offset(220, 100),
          provider,
          context,
          true,
        );

        // Only 1 unified eraser center must be tracked (centroid: 160, 100)
        expect(manager.toolEraserPointerIds.length, equals(4));
        expect(manager.toolEraserCenter, isNotNull);
        expect(manager.toolEraserCenter!.dx, closeTo(160.0, 0.1));
        expect(manager.toolEraserCenter!.dy, closeTo(100.0, 0.1));
        expect(manager.isToolEraserCircleVisible, isTrue);

        // 2. Move 4 fingers together
        manager.handleToolEraserMove(
          1,
          const Offset(110, 120),
          provider,
          context,
          true,
        );
        manager.handleToolEraserMove(
          2,
          const Offset(150, 120),
          provider,
          context,
          true,
        );
        manager.handleToolEraserMove(
          3,
          const Offset(190, 120),
          provider,
          context,
          true,
        );
        manager.handleToolEraserMove(
          4,
          const Offset(230, 120),
          provider,
          context,
          true,
        );

        // Still exactly 1 unified eraser center
        expect(manager.toolEraserCenter, isNotNull);
        expect(manager.isToolEraserCircleVisible, isTrue);
      },
    );

    testWidgets(
      'Toolbox eraser: auto-dismisses immediately when fingers lift and does NOT stay stuck',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                manager.init(context);
                return const SizedBox();
              },
            ),
          ),
        );

        final context = tester.element(find.byType(SizedBox));
        final provider = WhiteboardProvider();

        // 4 fingers down
        for (int i = 1; i <= 4; i++) {
          final pos = Offset(100.0 + (i * 30), 100);
          manager.pointers[i] = PointerDownEvent(pointer: i, position: pos);
          manager.handleToolEraserDown(i, pos, provider, context, true);
        }
        expect(manager.isToolEraserCircleVisible, isTrue);

        // Lift fingers 1, 2, 3
        for (int i = 1; i <= 3; i++) {
          manager.handleToolEraserUp(i, provider, true);
          manager.forgetPointer(i);
        }
        // 1 finger still on screen -> 1 eraser still visible
        expect(manager.isToolEraserCircleVisible, isTrue);

        // Lift last finger 4
        manager.handleToolEraserUp(4, provider, true);
        manager.forgetPointer(4);

        // All fingers lifted -> eraser circle MUST auto dismiss immediately and NOT stay stuck
        expect(manager.toolEraserCenter, isNull);
        expect(manager.isToolEraserCircleVisible, isFalse);
      },
    );
  });
}
