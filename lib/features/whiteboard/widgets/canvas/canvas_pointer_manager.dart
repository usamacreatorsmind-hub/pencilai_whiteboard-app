import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/board_element.dart';
import '../../models/stroke_element.dart';
import '../../state/whiteboard_provider.dart';

/// Manages multi-touch pointer state, palm rejection algorithms, gesture erasing,
/// native touch hint event channels, and watchdog cleanup timers for [WhiteboardCanvas].
class CanvasPointerManager {
  static final bool kDebugPointerInfo = false;

  static const double kPanelWidthMm = 1895.0; // 75" panel physical width in mm
  static const double kPalmRadiusMajorMin =
      13.0; // 13mm physical radius (26mm contact width = Palm)
  static const double kPalmSizeMin = 0.14; // 14% sensor contact area
  static const double kBackhandRadiusMin =
      9.5; // 9.5mm physical radius (19mm contact width = Knuckles/backhand)
  static const double kBackhandSizeMin = 0.06; // 6% sensor contact area
  static const int kPalmClusterMinPoints = 2;
  static const double kPalmClusterRadiusMaxMm = 160.0;
  static const int kPointerFreshMs = 250;
  static const int kPointerStaleMs = 800;
  static const int kPruneThrottleMs = 40;
  static const int kWatchdogMs = 100;
  static const int kPalmCancelTimeWindowMs = 300;
  static const double kStaticGestureEraserRadius = 60.0;
  static const int kGestureEraserGraceMs =
      200; // Grace period before resetting eraser

  /// Stale timeout for pointers that are physically still on the panel
  /// (Flutter sends no move events for a stationary palm, so the short
  /// [kPointerStaleMs] would wrongly drop it and break the eraser latch).
  static const int kHeldPointerStaleMs = 4000;

  /// Once hardware reports all contacts lifted, leftover (ghost) pointers that
  /// did not receive their up event are cleared after this short delay.
  static const int kLiftedGhostMs = 120;

  final Map<int, BoardElement> activeElements = {};
  final Map<int, Offset> eraserPositions = {};
  final Map<int, Offset> lastEraserPositions = {};
  final Map<int, Offset> smoothedDeltas = {};
  final Map<int, PointerEvent> pointers = {};
  final Map<int, DateTime> pointerDownTimes = {};
  final Map<int, DateTime> lastSeen = {};
  final Map<int, Map<String, dynamic>> nativeTouchHints = {};

  /// Pointers that were detected as palm/backhand at least once in their
  /// lifetime. Contact radius often shrinks while the palm slides, so a palm
  /// stays a palm until it is lifted (prevents eraser dropping out mid-sweep).
  final Set<int> palmPointerIds = {};

  /// True once the native touch-hint channel has delivered any event.
  bool _nativeHintsActive = false;

  /// Time when native layer reported all contacts lifted (null while touching).
  DateTime? _nativeAllLiftedAt;

  StreamSubscription? _touchHintSubscription;
  Timer? _eraserResetTimer;
  int cancelEventCount = 0;
  int prunedGhostCount = 0;
  int nativePointerCount = 0;
  String lastCancelInfo = 'None';
  DateTime? lastPalmSeen;
  DateTime _lastPrune = DateTime.fromMillisecondsSinceEpoch(0);

  /// pointerId -> mind-map target node
  final Map<int, ({String mmId, String nodeId})> mmStrokeTargets = {};
  int? panPointerId;

  Path? currentLasso;
  bool isUsingGestureEraser = false;

  // Gesture eraser centroid state
  Offset? gestureCenter;
  Offset? gestureLastCenter;
  Offset? pendingErase;

  /// Whether the gesture eraser circle indicator should currently be visible.
  /// Automatically becomes false when touches lift and grace period expires,
  /// preventing the eraser circle from getting permanently stuck on canvas.
  bool get isEraserCircleVisible {
    if (!isUsingGestureEraser || gestureCenter == null) return false;
    if (pointers.isNotEmpty) return true;
    final last = lastPalmSeen;
    if (last == null) return false;
    return DateTime.now().difference(last).inMilliseconds <
        kGestureEraserGraceMs;
  }

  // Tool eraser (toolbox eraser) single unified state
  final Set<int> toolEraserPointerIds = {};
  Offset? toolEraserCenter;
  Offset? toolEraserLastCenter;
  DateTime? lastToolEraserSeen;
  DateTime? lastToolEraserTime;
  Timer? _toolEraserResetTimer;

  /// Whether the toolbox eraser circle indicator should currently be visible.
  /// Always shows ONLY 1 eraser circle (never multiple), and automatically
  /// hides when fingers lift and grace period expires, preventing it from getting stuck.
  bool get isToolEraserCircleVisible {
    if (toolEraserCenter == null) return false;
    if (pointers.isEmpty && toolEraserPointerIds.isEmpty) return false;
    final last = lastToolEraserSeen;
    if (last == null) return false;
    return DateTime.now().difference(last).inMilliseconds <
        kGestureEraserGraceMs;
  }

  bool _pulseScheduled = false;
  Timer? watchdog;
  double screenWidth = 1920.0;
  RenderBox? box;

  DateTime lastMoveLogTime = DateTime.now();
  final ValueNotifier<int> activeLayerPulse = ValueNotifier(0);

  void init(BuildContext context) {
    screenWidth = MediaQuery.sizeOf(context).width;
    _listenNativeTouchHints();
  }

  void updateDependencies(BuildContext context) {
    screenWidth = MediaQuery.sizeOf(context).width;
  }

  void dispose() {
    watchdog?.cancel();
    _eraserResetTimer?.cancel();
    _toolEraserResetTimer?.cancel();
    _touchHintSubscription?.cancel();
    activeLayerPulse.dispose();
  }

  void _listenNativeTouchHints() {
    if (Platform.isAndroid) {
      try {
        const channel = EventChannel('com.pencilai.whiteboard/touch_hints');
        _touchHintSubscription = channel.receiveBroadcastStream().listen((
          event,
        ) {
          if (event is Map) {
            _nativeHintsActive = true;
            final action = event['action'] as int?;
            if (action == 1 || action == 3) {
              // ACTION_UP or ACTION_CANCEL: touch contacts have ended
              nativePointerCount = 0;
              _nativeAllLiftedAt = DateTime.now();
              if (freshTouchPointers().isEmpty) {
                resetGestureEraser();
                resetToolEraser();
              }
            } else {
              _nativeAllLiftedAt = null;
              final cnt = event['pointerCount'] as int?;
              if (cnt != null) {
                nativePointerCount = cnt;
              }
            }
            if (event.containsKey('pointers')) {
              final ptrs = event['pointers'] as List?;
              if (ptrs != null) {
                for (var p in ptrs) {
                  if (p is Map) {
                    final pid = p['pointerId'] as int?;
                    if (pid != null) {
                      nativeTouchHints[pid] = Map<String, dynamic>.from(p);
                    }
                  }
                }
              }
            }
          }
        }, onError: (_) {});
      } catch (_) {}
    }
  }

  double get pxPerMm => screenWidth / kPanelWidthMm;
  double get twoPointerPalmDistanceMaxPx => kPalmClusterRadiusMaxMm * pxPerMm;
  double get palmClusterRadiusMaxPx => kPalmClusterRadiusMaxMm * pxPerMm;

  bool isTouchKind(PointerEvent e) => true;

  bool hasTouchDown() => pointers.isNotEmpty;

  void requestRepaint(bool mounted) {
    if (_pulseScheduled) return;
    _pulseScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _pulseScheduled = false;
      if (mounted) activeLayerPulse.value++;
    });
  }

  List<PointerEvent> freshTouchPointers() {
    final now = DateTime.now();
    return pointers.values.where((e) {
      if (!isTouchKind(e)) return false;
      final lastTime = lastSeen[e.pointer];
      if (lastTime == null) return false;
      return now.difference(lastTime).inMilliseconds < kPointerFreshMs;
    }).toList();
  }

  void forgetPointer(int pid) {
    if (panPointerId == pid) {
      panPointerId = null;
    }
    mmStrokeTargets.remove(pid);
    pointers.remove(pid);
    toolEraserPointerIds.remove(pid);
    eraserPositions.remove(pid);
    lastEraserPositions.remove(pid);
    pointerDownTimes.remove(pid);
    lastSeen.remove(pid);
    nativeTouchHints.remove(pid);
    smoothedDeltas.remove(pid);
    palmPointerIds.remove(pid);
    final active = activeElements.remove(pid);
    if (active is StrokeElement) {
      active.disposeLive();
    }
    if (toolEraserPointerIds.isEmpty && toolEraserCenter != null) {
      resetToolEraser();
    }
  }

  void pruneStalePointers({bool force = false}) {
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastPrune).inMilliseconds < kPruneThrottleMs) {
      return;
    }
    _lastPrune = now;

    final bool hardwareLifted =
        _nativeHintsActive && _nativeAllLiftedAt != null;
    final bool hardwareTouching =
        _nativeHintsActive && !hardwareLifted && nativePointerCount > 0;

    final toRemove = <int>[];
    for (var entry in lastSeen.entries) {
      final int idleMs = now.difference(entry.value).inMilliseconds;
      int staleMs;
      if (hardwareLifted && !activeElements.containsKey(entry.key)) {
        // Hardware says every finger/palm is off the panel -> clear ghosts fast
        // (pen strokes in progress keep the normal timeout so they never get lost).
        staleMs = kLiftedGhostMs;
      } else if (hardwareTouching) {
        // Contacts are physically down (e.g. palm held still) -> keep them.
        staleMs = kHeldPointerStaleMs;
      } else {
        staleMs = kPointerStaleMs;
      }
      if (idleMs > staleMs) {
        toRemove.add(entry.key);
      }
    }
    for (var pid in toRemove) {
      forgetPointer(pid);
      prunedGhostCount++;
    }
    if (toRemove.isNotEmpty) {
      activeLayerPulse.value++;
    }
  }

  void cancelGestureEraserReset() {
    _eraserResetTimer?.cancel();
    _eraserResetTimer = null;
  }

  void scheduleGestureEraserReset() {
    _eraserResetTimer?.cancel();
    _eraserResetTimer = Timer(
      const Duration(milliseconds: kGestureEraserGraceMs),
      () {
        if (freshTouchPointers().isEmpty) {
          pruneStalePointers(force: true);
          resetGestureEraser();
        }
      },
    );
  }

  void resetGestureEraser() {
    cancelGestureEraserReset();
    isUsingGestureEraser = false;
    eraserPositions.clear();
    lastEraserPositions.clear();
    gestureCenter = null;
    gestureLastCenter = null;
    pendingErase = null;
    lastPalmSeen = null;
    lastEraseTime = null;
    nativePointerCount = 0;
    activeLayerPulse.value++;
  }

  void cancelToolEraserReset() {
    _toolEraserResetTimer?.cancel();
    _toolEraserResetTimer = null;
  }

  void scheduleToolEraserReset() {
    _toolEraserResetTimer?.cancel();
    _toolEraserResetTimer = Timer(
      const Duration(milliseconds: kGestureEraserGraceMs),
      () {
        if (freshTouchPointers().isEmpty || toolEraserPointerIds.isEmpty) {
          pruneStalePointers(force: true);
          resetToolEraser();
        }
      },
    );
  }

  void resetToolEraser() {
    cancelToolEraserReset();
    toolEraserCenter = null;
    toolEraserLastCenter = null;
    lastToolEraserSeen = null;
    lastToolEraserTime = null;
    toolEraserPointerIds.clear();
    eraserPositions.clear();
    lastEraserPositions.clear();
    activeLayerPulse.value++;
  }

  Offset _calculateToolEraserCentroid([Offset? fallback]) {
    Offset center = Offset.zero;
    int count = 0;
    for (final pid in toolEraserPointerIds) {
      final pos = eraserPositions[pid];
      if (pos != null) {
        center += pos;
        count++;
      }
    }
    if (count == 0) return fallback ?? Offset.zero;
    return center / count.toDouble();
  }

  void handleToolEraserDown(
    int pointerId,
    Offset localPos,
    WhiteboardProvider provider,
    BuildContext context,
    bool isMounted,
  ) {
    cancelToolEraserReset();
    toolEraserPointerIds.add(pointerId);
    eraserPositions[pointerId] = localPos;
    lastEraserPositions[pointerId] = localPos;
    lastToolEraserSeen = DateTime.now();

    final centroid = _calculateToolEraserCentroid(localPos);
    toolEraserCenter = centroid;

    final prev = toolEraserLastCenter ?? centroid;
    provider.partialErase(centroid, provider.eraserSize, lastPos: prev);
    toolEraserLastCenter = centroid;
    lastToolEraserTime = DateTime.now();

    requestRepaint(isMounted);
  }

  void handleToolEraserMove(
    int pointerId,
    Offset localPos,
    WhiteboardProvider provider,
    BuildContext context,
    bool isMounted,
  ) {
    cancelToolEraserReset();
    toolEraserPointerIds.add(pointerId);
    eraserPositions[pointerId] = localPos;
    lastEraserPositions[pointerId] = localPos;
    lastToolEraserSeen = DateTime.now();

    final rawCenter = _calculateToolEraserCentroid(localPos);

    // Responsive hand tracking with smoothing
    final prev = toolEraserCenter;
    Offset smoothed = rawCenter;
    if (prev != null) {
      final dist = (rawCenter - prev).distance;
      if (dist < 80.0 && dist >= 0.5) {
        final factor = (dist / 12.0).clamp(0.85, 0.98);
        smoothed = Offset.lerp(prev, rawCenter, factor)!;
      }
    }
    toolEraserCenter = smoothed;

    final prevErase = toolEraserLastCenter;
    final now = DateTime.now();
    final elapsedMs = lastToolEraserTime == null
        ? 999
        : now.difference(lastToolEraserTime!).inMilliseconds;
    final double dist =
        prevErase == null ? 999 : (smoothed - prevErase).distance;

    if (prevErase == null || dist >= 6.0 || (elapsedMs >= 16 && dist >= 2.0)) {
      provider.partialErase(
        smoothed,
        provider.eraserSize,
        lastPos: prevErase ?? smoothed,
      );
      toolEraserLastCenter = smoothed;
      lastToolEraserTime = now;
    }

    requestRepaint(isMounted);
  }

  void finishToolEraser(WhiteboardProvider provider, bool isMounted) {
    final curr = toolEraserCenter;
    final prev = toolEraserLastCenter;
    if (curr != null && prev != null && (curr - prev).distance > 0.5) {
      provider.partialErase(curr, provider.eraserSize, lastPos: prev);
      toolEraserLastCenter = curr;
    }
  }

  void handleToolEraserUp(
    int pointerId,
    WhiteboardProvider provider,
    bool isMounted,
  ) {
    toolEraserPointerIds.remove(pointerId);
    eraserPositions.remove(pointerId);
    lastEraserPositions.remove(pointerId);

    if (toolEraserPointerIds.isEmpty || freshTouchPointers().isEmpty) {
      finishToolEraser(provider, isMounted);
      scheduleToolEraserReset();
      if (pointers.isEmpty) {
        resetToolEraser();
      }
    } else {
      final remainingCenter = _calculateToolEraserCentroid();
      toolEraserCenter = remainingCenter;
      toolEraserLastCenter = remainingCenter;
      lastToolEraserSeen = DateTime.now();
    }

    requestRepaint(isMounted);
  }

  void startWatchdog(bool Function() isMounted) {
    watchdog ??= Timer.periodic(const Duration(milliseconds: kWatchdogMs), (_) {
      if (!isMounted()) return;
      pruneStalePointers(force: true);

      final hadGestureState = isUsingGestureEraser || gestureCenter != null;
      if (hadGestureState) {
        final freshCount = freshTouchPointers().length;
        if (freshCount == 0) {
          final lastSeenTime = lastPalmSeen;
          final elapsed = lastSeenTime != null
              ? DateTime.now().difference(lastSeenTime).inMilliseconds
              : 999;
          if (elapsed >= kGestureEraserGraceMs) {
            pruneStalePointers(force: true);
            resetGestureEraser();
          }
        }
      }



      final hadToolState =
          toolEraserCenter != null || toolEraserPointerIds.isNotEmpty;
      if (hadToolState) {
        final freshCount = freshTouchPointers().length;
        if (freshCount == 0 ||
            pointers.isEmpty ||
            toolEraserPointerIds.isEmpty) {
          final lastSeenTime = lastToolEraserSeen;
          final elapsed = lastSeenTime != null
              ? DateTime.now().difference(lastSeenTime).inMilliseconds
              : 999;
          if (elapsed >= kGestureEraserGraceMs || pointers.isEmpty) {
            pruneStalePointers(force: true);
            resetToolEraser();
          }
        }
      }

      if (pointers.isEmpty &&
          !isUsingGestureEraser &&
          gestureCenter == null &&
          toolEraserCenter == null) {
        watchdog?.cancel();
        watchdog = null;
      }
    });
  }

  double effectiveRadius(PointerEvent e) {
    final double pxMm = pxPerMm > 0 ? pxPerMm : 1.0;
    double rPixels = max(e.radiusMajor, e.radiusMinor);
    final hint = nativeTouchHints[e.pointer];
    if (hint != null) {
      final tm = hint['touchMajor'] as double?;
      if (tm != null && tm > 0) {
        final half = tm / 2.0;
        if (half > rPixels) rPixels = half;
      }
    }
    if (rPixels <= 0 && e.size > 0) {
      rPixels = e.size * 100.0;
    }
    // Scale screen pixels to physical millimeters
    return rPixels / pxMm;
  }

  bool isPalm(PointerEvent e) {
    // 0. Sticky: once a pointer was a palm, it stays a palm until lifted
    if (palmPointerIds.contains(e.pointer)) return true;
    final bool detected = _detectPalm(e);
    if (detected) palmPointerIds.add(e.pointer);
    return detected;
  }

  bool _detectPalm(PointerEvent e) {
    // 1. Native platform hardware palm hint
    final hint = nativeTouchHints[e.pointer];
    if (hint != null && (hint['toolType'] == 5 || hint['isCanceled'] == true)) {
      return true;
    }

    final double r = effectiveRadius(e);
    final double sz = e.size;

    // 2. Full palm contact:
    // Physical radius >= 15.0mm (30mm contact width) OR size >= 0.16
    if (r >= kPalmRadiusMajorMin || sz >= kPalmSizeMin) {
      return true;
    }

    // 3. Backhand / knuckle / edge of hand:
    // Physical radius >= 11.0mm (22mm contact width) OR (radius >= 10.0mm AND size >= 0.09)
    if (r >= kBackhandRadiusMin || (r >= 10.0 && sz >= kBackhandSizeMin)) {
      return true;
    }

    return false;
  }

  bool isEraserMode(PointerEvent event, BuildContext context) {
    pruneStalePointers();

    final now = DateTime.now();
    final freshTouches = freshTouchPointers();
    final allPointers = pointers.values.toList();
    final touchCount = max(freshTouches.length, allPointers.length);

    // Latch: if already in gesture eraser mode and touch is still active OR within grace period:
    if (isUsingGestureEraser) {
      if (freshTouches.isNotEmpty || pointers.isNotEmpty) {
        lastPalmSeen = now;
        return true;
      }
      final lastSeenTime = lastPalmSeen;
      if (lastSeenTime != null &&
          now.difference(lastSeenTime).inMilliseconds < kGestureEraserGraceMs) {
        return true;
      }
      resetGestureEraser();
    }

    // 1. Whole hand / 5 or more fingers:
    // When user places 5 or more fingers (or their whole hand) on the panel,
    // immediately enable erase mode.
    // (Note: 1, 2, 3, and 4 fingers draw as pen strokes and do NOT trigger erase)
    if (touchCount >= 5 ||
        (nativePointerCount >= 5 && freshTouches.length >= 2)) {
      lastPalmSeen = now;
      return true;
    }

    // 2. Palm or backhand detection:
    if (isPalm(event)) {
      lastPalmSeen = now;
      return true;
    }

    if (freshTouches.any(isPalm) || allPointers.any(isPalm)) {
      lastPalmSeen = now;
      return true;
    }

    if (isUsingGestureEraser) {
      resetGestureEraser();
    }

    return false;
  }

  Offset getCanvasLocalPos(PointerEvent event, BuildContext context) {
    box ??= context.findRenderObject() as RenderBox?;
    final b = box;
    Offset rawPos;
    if (b != null && b.attached) {
      rawPos = b.globalToLocal(event.position);
    } else {
      rawPos = event.localPosition;
    }

    final provider = Provider.of<WhiteboardProvider>(context, listen: false);
    return rawPos - provider.canvasPanOffset;
  }

  double gestureEraseRadius([WhiteboardProvider? provider]) {
    // Shows and uses the exact actual size of the eraser (default 60.0 or configured eraserSize)
    // with NO auto-stretching or fluctuating based on pointer counts.
    return provider?.eraserSize ?? kStaticGestureEraserRadius;
  }

  Offset gestureEraseCentroid(Offset fallback, BuildContext context) {
    Offset center = Offset.zero;
    int count = 0;
    final now = DateTime.now();
    for (final p in pointers.values) {
      if (!isTouchKind(p)) continue;
      final seen = lastSeen[p.pointer];
      // Keep recent touch contacts active within 400ms without flickering
      if (seen != null && now.difference(seen).inMilliseconds > 400) {
        continue;
      }
      center += getCanvasLocalPos(p, context);
      count++;
    }
    if (count == 0) return fallback;
    return center / count.toDouble();
  }

  /// Adaptive EMA filter with responsive hand tracking:
  /// Follows hand sweeps in real-time with 0ms drag lag / sticking,
  /// while smoothing out sub-pixel multi-touch micro-jitter.
  Offset smoothGestureCenter(Offset raw) {
    final prev = gestureCenter;
    if (prev == null) return raw;
    final d = (raw - prev).distance;
    // Fast jump/teleport across large screen area (snap directly without trailing)
    if (d > 80.0) return raw;
    // Sub-pixel sensor noise gate
    if (d < 0.5) return prev;
    // Highly responsive and smooth tracking:
    // Follows hand with zero drag lag while absorbing touch sensor micro-jitter
    final factor = (d / 12.0).clamp(0.85, 0.98);
    return Offset.lerp(prev, raw, factor)!;
  }

  DateTime? lastEraseTime;

  /// Real-time smooth gesture erase movement handler.
  /// Visual eraser circle updates instantly on EVERY micro-event at 60-120Hz,
  /// while heavy partialErase operations are executed when moved >= 8px or at ~60Hz (>= 16ms),
  /// guaranteeing continuous capsule sweep without UI choke or skipping.
  void handleGestureEraseMove(
    Offset rawCenter,
    WhiteboardProvider provider,
    BuildContext context,
    bool isMounted,
  ) {
    if (!isUsingGestureEraser) return;

    cancelGestureEraserReset();

    final smoothed = smoothGestureCenter(rawCenter);
    gestureCenter = smoothed;

    final prev = gestureLastCenter;

    if (prev == null) {
      gestureLastCenter = smoothed;
      lastEraseTime = DateTime.now();
      provider.partialErase(
        smoothed,
        gestureEraseRadius(provider),
        lastPos: smoothed,
      );
      activeLayerPulse.value++;
      return;
    }

    final now = DateTime.now();
    final elapsedMs = lastEraseTime == null
        ? 999
        : now.difference(lastEraseTime!).inMilliseconds;
    final double dist = (smoothed - prev).distance;

    // Erase execution:
    // Execute capsule erase when moved >= 8.0 pixels OR elapsed >= 16ms (60 FPS throttle with dist >= 2px).
    // This caps erase frequency to ~60Hz maximum, preventing UI choke on high-frequency multi-touch panels,
    // while guaranteeing complete capsule coverage without leaving gaps or lagging behind.
    if (dist >= 8.0 || (elapsedMs >= 16 && dist >= 2.0)) {
      provider.partialErase(
        smoothed,
        gestureEraseRadius(provider),
        lastPos: prev,
      );
      gestureLastCenter = smoothed;
      lastEraseTime = now;
    }

    // Always update visual eraser circle instantly in real-time
    activeLayerPulse.value++;
  }

  void finishGestureErase(WhiteboardProvider provider, bool isMounted) {
    if (!isUsingGestureEraser) return;
    final curr = gestureCenter;
    final prev = gestureLastCenter;
    if (curr != null && prev != null && (curr - prev).distance > 0.5) {
      provider.partialErase(curr, gestureEraseRadius(provider), lastPos: prev);
      gestureLastCenter = curr;
    }
  }

  void queueGestureErase(Offset center, BuildContext context, bool isMounted) {
    handleGestureEraseMove(
      center,
      context.read<WhiteboardProvider>(),
      context,
      isMounted,
    );
  }

  void flushPendingErase(WhiteboardProvider provider) {
    finishGestureErase(provider, true);
  }

  void switchToEraserMode(
    Offset initialPos,
    WhiteboardProvider provider,
    BuildContext context,
    bool isMounted,
  ) {
    cancelGestureEraserReset();
    isUsingGestureEraser = true;

    final toDrop = activeElements.keys.toList();
    for (final id in toDrop) {
      final e = activeElements.remove(id);
      if (e is StrokeElement) e.disposeLive();
    }

    eraserPositions.clear();
    lastEraserPositions.clear();

    final c = gestureEraseCentroid(initialPos, context);
    gestureCenter = c;
    gestureLastCenter = c;
    lastEraseTime = DateTime.now();
    pendingErase = null;
    provider.partialErase(c, gestureEraseRadius(provider), lastPos: c);
    activeLayerPulse.value++;
  }
}
