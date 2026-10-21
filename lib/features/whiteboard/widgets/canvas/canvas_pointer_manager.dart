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
  static const double kPalmRadiusMajorMin = 12.0;
  static const double kPalmSizeMin = 0.08;
  static const double kBackhandRadiusMin = 6.5;
  static const double kBackhandSizeMin = 0.045;
  static const int kPalmClusterMinPoints = 2;
  static const double kPalmClusterRadiusMaxMm = 160.0;
  static const bool kTwoPointerRule = true;
  static const int kPointerFreshMs = 250;
  static const int kPointerStaleMs = 800;
  static const int kPruneThrottleMs = 40;
  static const int kWatchdogMs = 100;
  static const double kGestureMinMovePx = 2.0;
  static const int kPalmCancelTimeWindowMs = 300;
  static const double kStaticGestureEraserRadius = 60.0;

  final Map<int, BoardElement> activeElements = {};
  final Map<int, Offset> eraserPositions = {};
  final Map<int, Offset> lastEraserPositions = {};
  final Map<int, Offset> smoothedDeltas = {};
  final Map<int, Offset> tipOffsets = {};
  final Map<int, PointerEvent> pointers = {};
  final Map<int, DateTime> pointerDownTimes = {};
  final Map<int, DateTime> lastSeen = {};
  final Map<int, Map<String, dynamic>> nativeTouchHints = {};

  StreamSubscription? _touchHintSubscription;
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
            final cnt = event['pointerCount'] as int?;
            if (cnt != null) {
              nativePointerCount = cnt;
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
    eraserPositions.remove(pid);
    lastEraserPositions.remove(pid);
    pointerDownTimes.remove(pid);
    lastSeen.remove(pid);
    nativeTouchHints.remove(pid);
    smoothedDeltas.remove(pid);
    tipOffsets.remove(pid);
    final active = activeElements.remove(pid);
    if (active is StrokeElement) {
      active.disposeLive();
    }
  }

  void pruneStalePointers({bool force = false}) {
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastPrune).inMilliseconds < kPruneThrottleMs) {
      return;
    }
    _lastPrune = now;

    final toRemove = <int>[];
    for (var entry in lastSeen.entries) {
      if (now.difference(entry.value).inMilliseconds > kPointerStaleMs) {
        toRemove.add(entry.key);
      }
    }
    for (var pid in toRemove) {
      forgetPointer(pid);
      prunedGhostCount++;
    }
  }

  void resetGestureEraser() {
    isUsingGestureEraser = false;
    eraserPositions.clear();
    lastEraserPositions.clear();
    gestureCenter = null;
    gestureLastCenter = null;
    pendingErase = null;
    lastPalmSeen = null;
    activeLayerPulse.value++;
  }

  void startWatchdog(bool Function() isMounted) {
    watchdog ??= Timer.periodic(const Duration(milliseconds: kWatchdogMs), (_) {
      if (!isMounted()) return;
      pruneStalePointers(force: true);
      final hadEraserState = isUsingGestureEraser || gestureCenter != null;
      if (!hasTouchDown() && hadEraserState) {
        resetGestureEraser();
      }
      if (pointers.isEmpty) {
        watchdog?.cancel();
        watchdog = null;
      }
    });
  }

  double effectiveRadius(PointerEvent e) {
    double r = max(e.radiusMajor, e.radiusMinor);
    if (r <= 0 && e.size > 0) {
      r = e.size * 100.0;
    }
    final hint = nativeTouchHints[e.pointer];
    if (hint != null) {
      final tm = hint['touchMajor'] as double?;
      if (tm != null && tm > 0) {
        final half = tm / 2.0;
        if (half > r) r = half;
      }
    }
    return r;
  }

  bool isPalm(PointerEvent e) {
    // 1. Native platform hardware palm hint
    final hint = nativeTouchHints[e.pointer];
    if (hint != null && (hint['toolType'] == 5 || hint['isCanceled'] == true)) {
      return true;
    }

    final double r = effectiveRadius(e);
    final double sz = e.size;

    // 2. Full palm contact: radius >= 12.0 or size >= 0.08
    if (r >= kPalmRadiusMajorMin || sz >= kPalmSizeMin) return true;

    // 3. Backhand / knuckle / edge of hand: radius >= 6.5 or size >= 0.045
    if (r >= kBackhandRadiusMin || sz >= kBackhandSizeMin) return true;

    return false;
  }

  bool isEraserMode(PointerEvent event, BuildContext context) {
    pruneStalePointers();

    final now = DateTime.now();

    // Latch: if already in gesture eraser mode and touch is still active, stay in eraser mode
    if (isUsingGestureEraser && (hasTouchDown() || pointers.isNotEmpty)) {
      lastPalmSeen = now;
      return true;
    }

    final freshTouches = freshTouchPointers();
    final allPointers = pointers.values.toList();

    // 1. Single contact palm or backhand threshold
    if (isPalm(event) || freshTouches.any(isPalm) || allPointers.any(isPalm)) {
      lastPalmSeen = now;
      return true;
    }

    // 2. Multi-touch cluster: 2 or more touches within cluster distance (160mm) is always an eraser gesture!
    final touchList = freshTouches.isNotEmpty ? freshTouches : allPointers;
    if (touchList.length >= 2) {
      final clusterPx = palmClusterRadiusMaxPx;
      double maxDist = 0.0;
      for (int i = 0; i < touchList.length; i++) {
        for (int j = i + 1; j < touchList.length; j++) {
          final d = (touchList[i].position - touchList[j].position).distance;
          if (d > maxDist) maxDist = d;
        }
      }
      if (maxDist <= clusterPx) {
        lastPalmSeen = now;
        return true;
      }
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

  double gestureEraseRadius() => kStaticGestureEraserRadius;

  Offset gestureEraseCentroid(Offset fallback, BuildContext context) {
    Offset center = Offset.zero;
    int count = 0;
    final now = DateTime.now();
    for (final p in pointers.values) {
      if (!isTouchKind(p)) continue;
      final seen = lastSeen[p.pointer];
      // Only include fresh pointers active in the last 120ms (ignores ghost/dead touches)
      if (seen != null && now.difference(seen).inMilliseconds > 120) {
        continue;
      }
      center += getCanvasLocalPos(p, context);
      count++;
    }
    if (count == 0) return fallback;
    return center / count.toDouble();
  }

  /// Adaptive Exponential Moving Average (EMA) filter:
  /// Eliminates multi-touch noise and jumps when fingers land or lift,
  /// while tracking fast intentional sweeps instantly without dragging lag.
  Offset smoothGestureCenter(Offset raw) {
    final prev = gestureCenter;
    if (prev == null) return raw;
    final d = (raw - prev).distance;
    // Fast jump/teleport across large screen area (snap directly without trailing)
    if (d > 160.0) return raw;
    // Sub-pixel sensor noise gate
    if (d < 0.25) return prev;
    // Adaptive EMA filter:
    // Small jitter gets smooth damping (~0.45)
    // Faster intentional swipe gets swift tracking (~0.75) with zero perceived lag
    final factor = (d / 40.0).clamp(0.45, 0.75);
    return Offset.lerp(prev, raw, factor)!;
  }

  /// Real-time smooth gesture erase movement handler.
  /// Synchronously executes partialErase when distance threshold is reached
  /// with 0ms frame lag, and throttles visual indicator repaints to vsync.
  void handleGestureEraseMove(
    Offset rawCenter,
    WhiteboardProvider provider,
    BuildContext context,
    bool isMounted,
  ) {
    if (!isUsingGestureEraser) return;

    final smoothed = smoothGestureCenter(rawCenter);
    gestureCenter = smoothed;

    final prev = gestureLastCenter;
    if (prev == null) {
      gestureLastCenter = smoothed;
      provider.partialErase(smoothed, gestureEraseRadius(), lastPos: smoothed);
      requestRepaint(isMounted);
      return;
    }

    final double dist = (smoothed - prev).distance;
    if (dist >= kGestureMinMovePx) {
      // Direct synchronous erase with zero frame delay!
      provider.partialErase(smoothed, gestureEraseRadius(), lastPos: prev);
      gestureLastCenter = smoothed;
      requestRepaint(isMounted);
    } else {
      // Sub-threshold movement: smoothly update visual eraser circle
      requestRepaint(isMounted);
    }
  }

  void finishGestureErase(WhiteboardProvider provider, bool isMounted) {
    if (!isUsingGestureEraser) return;
    final curr = gestureCenter;
    final prev = gestureLastCenter;
    if (curr != null && prev != null && (curr - prev).distance > 0.5) {
      provider.partialErase(curr, gestureEraseRadius(), lastPos: prev);
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
    WhiteboardProvider provider,
    BuildContext context,
    bool isMounted,
  ) {
    isUsingGestureEraser = true;

    final toDrop = activeElements.keys.toList();
    for (final id in toDrop) {
      final e = activeElements.remove(id);
      if (e is StrokeElement) e.disposeLive();
    }

    eraserPositions.clear();
    lastEraserPositions.clear();

    final c = gestureEraseCentroid(gestureCenter ?? Offset.zero, context);
    gestureCenter = c;
    gestureLastCenter = c;
    pendingErase = null;
    provider.partialErase(c, gestureEraseRadius(), lastPos: c);
    requestRepaint(isMounted);
  }
}
