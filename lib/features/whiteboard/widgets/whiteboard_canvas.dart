import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../state/whiteboard_provider.dart';
import '../models/board_element.dart';
import '../models/stroke_element.dart';
import '../models/shape_element.dart';
import '../models/image_element.dart';
import '../models/document_element.dart';
import '../models/text_element.dart';
import '../models/table_element.dart';
import '../models/mind_map_element.dart';
import '../../../widgets/pptx_viewer.dart';

class WhiteboardCanvas extends StatefulWidget {
  const WhiteboardCanvas({super.key});

  @override
  State<WhiteboardCanvas> createState() => _WhiteboardCanvasState();
}

class _WhiteboardCanvasState extends State<WhiteboardCanvas> {
  // =========================================================================
  // TUNABLE GESTURE-ERASER & PALM DETECTION CONSTANTS
  // =========================================================================
  // Diagnostics panel dekhna ho to isko `kDebugMode` kar do.
  // NOTE: debug build bahut slow hota hai, lag test hamesha `flutter run --profile` me karo.
  static final bool kDebugPointerInfo = false;

  static const double kPanelWidthMm = 1895.0; // 75" panel physical width in mm
  static const double kPalmRadiusMajorMin = 9.0; // finger/thick nib = 4.7, backhand = 19.9, palm = 31.3
  static const double kPalmSizeMin = 0.008; // finger/thick nib = 0.0047, backhand = 0.0178, palm = 0.0295
  static const int kPalmClusterMinPoints = 3;
  static const double kPalmClusterRadiusMaxMm = 150.0;
  static const bool kTwoPointerRule = false;
  static const int kPointerFreshMs = 250;
  // Resting palm ko jaldi "stale" na maane, isliye 500 -> 800
  static const int kPointerStaleMs = 800;
  static const int kPruneThrottleMs = 40;
  static const int kWatchdogMs = 100;
  static const double kGestureMinMovePx = 2.0;
  static const int kPalmCancelTimeWindowMs = 300;
  static const double kStaticGestureEraserRadius = 60.0;

  final Map<int, BoardElement> _activeElements = {};
  final Map<int, Offset> _eraserPositions = {};
  final Map<int, Offset> _lastEraserPositions = {};
  final Map<int, Offset> _smoothedDeltas = {};
  final Map<int, Offset> _tipOffsets = {};
  final Map<int, PointerEvent> _pointers = {};
  final Map<int, DateTime> _pointerDownTimes = {};
  final Map<int, DateTime> _lastSeen = {};
  final Map<int, Map<String, dynamic>> _nativeTouchHints = {};
  StreamSubscription? _touchHintSubscription;
  int _cancelEventCount = 0;
  int _prunedGhostCount = 0;
  int _nativePointerCount = 0;
  String _lastCancelInfo = 'None';
  DateTime? _lastPalmSeen;
  DateTime _lastPrune = DateTime.fromMillisecondsSinceEpoch(0);

  /// pointerId -> jis mind-map node ke andar pen shuru hua
  final Map<int, ({String mmId, String nodeId})> _mmStrokeTargets = {};
  int? _panPointerId;

  Path? _currentLasso;
  bool _isUsingGestureEraser = false;

  // Gesture eraser (palm/backhand) state: sab pointers ka ek hi centroid
  Offset? _gestureCenter;
  Offset? _gestureLastCenter;
  Offset? _pendingErase;
  bool _eraseScheduled = false;

  // Repaint coalescing
  bool _pulseScheduled = false;

  Timer? _watchdog;
  double _screenWidth = 1920.0;
  RenderBox? _box;

  // displayElements memoization
  Iterable<BoardElement>? _displaySource;
  List<BoardElement> _displayCache = const [];
  int _displayCacheVersion = -1;
  bool _displayCacheOverlay = false;
  int _displayCachePage = -1;
  int _displayCacheLen = -1;

  DateTime _lastMoveLogTime = DateTime.now();
  final ValueNotifier<int> _activeLayerPulse = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _listenNativeTouchHints();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screenWidth = MediaQuery.sizeOf(context).width;
  }

  void _listenNativeTouchHints() {
    if (Platform.isAndroid) {
      try {
        const channel = EventChannel('com.pencilai.whiteboard/touch_hints');
        _touchHintSubscription = channel.receiveBroadcastStream().listen((event) {
          if (event is Map) {
            final cnt = event['pointerCount'] as int?;
            if (cnt != null) {
              _nativePointerCount = cnt;
            }
            if (event.containsKey('pointers')) {
              final pointers = event['pointers'] as List?;
              if (pointers != null) {
                for (var p in pointers) {
                  if (p is Map) {
                    final pid = p['pointerId'] as int?;
                    if (pid != null) {
                      _nativeTouchHints[pid] = Map<String, dynamic>.from(p);
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

  @override
  void dispose() {
    _watchdog?.cancel();
    _touchHintSubscription?.cancel();
    _activeLayerPulse.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  double get _pxPerMm => _screenWidth / kPanelWidthMm;
  double get _twoPointerPalmDistanceMaxPx => 50.0 * _pxPerMm;
  double get _palmClusterRadiusMaxPx => kPalmClusterRadiusMaxMm * _pxPerMm;

  bool _isTouchKind(PointerEvent e) => e.kind != PointerDeviceKind.stylus;

  bool _hasTouchDown() => _pointers.values.any(_isTouchKind);

  /// Repaint ko ek frame me sirf ek baar chalata hai (palm = 5-10 pointers).
  void _requestRepaint() {
    if (_pulseScheduled) return;
    _pulseScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _pulseScheduled = false;
      if (mounted) _activeLayerPulse.value++;
    });
  }

  List<PointerEvent> _freshTouchPointers() {
    final now = DateTime.now();
    return _pointers.values.where((e) {
      if (!_isTouchKind(e)) return false;
      final lastTime = _lastSeen[e.pointer];
      if (lastTime == null) return false;
      return now.difference(lastTime).inMilliseconds < kPointerFreshMs;
    }).toList();
  }

  // MindMap Helpers
  Iterable<MindMapElement> _visibleMindMaps(WhiteboardProvider provider) sync* {
    final page = provider.isDocumentOverlayOpen ? provider.overlayCurrentPage : null;
    final els = provider.currentPage.elements;
    for (int i = els.length - 1; i >= 0; i--) {
      final el = els[i];
      if (el is MindMapElement && el.docPage == page) yield el;
    }
  }

  MindMapElement? _findMindMapById(WhiteboardProvider provider, String id) {
    for (final el in provider.currentPage.elements) {
      if (el.id == id && el is MindMapElement) return el;
    }
    return null;
  }

  Offset _mmLocal(MindMapElement el, Offset p) {
    var q = p;
    if (el.rotation != 0 || el.scale != 1.0) {
      final c = el.getRawBounds().center;
      final d = q - c;
      final cosA = cos(-el.rotation);
      final sinA = sin(-el.rotation);
      final r = Offset(d.dx * cosA - d.dy * sinA, d.dx * sinA + d.dy * cosA) / el.scale;
      q = c + r;
    }
    return q - el.position;
  }

  ({MindMapElement el, MindMapNode node})? _mindMapNodeAt(Offset p, WhiteboardProvider provider, {double inflate = 0}) {
    for (final el in _visibleMindMaps(provider)) {
      final n = el.nodeAt(_mmLocal(el, p), inflate: inflate);
      if (n != null) return (el: el, node: n);
    }
    return null;
  }

  bool _handleMindMapButtons(Offset p, WhiteboardProvider provider) {
    for (final el in _visibleMindMaps(provider)) {
      final hit = el.hitTestAction(_mmLocal(el, p));
      if (hit == null) continue;

      switch (hit.action) {
        case MindMapAction.addChild:
          el.selectedNodeId = hit.nodeId;
          provider.addMindMapChildNode(el.id);
          break;
        case MindMapAction.addParent:
          el.selectedNodeId = hit.nodeId;
          provider.addMindMapParentNode(el.id);
          break;
        case MindMapAction.addSibling:
          el.selectedNodeId = hit.nodeId;
          provider.addMindMapSiblingNode(el.id);
          break;
        case MindMapAction.toggle:
          provider.toggleMindMapNodeCollapse(el.id, hit.nodeId);
          break;
        case MindMapAction.menu:
          el.selectedNodeId = hit.nodeId;
          if (hit.nodeId == el.root.id) provider.selectElement(el.id);
          provider.deleteMindMapNode(el.id);
          break;
      }
      return true;
    }
    return false;
  }

  /// Ek pointer ka saara state saaf karta hai (live stroke dispose ke saath).
  void _forgetPointer(int pid) {
    if (_panPointerId == pid) {
      _panPointerId = null;
    }
    _mmStrokeTargets.remove(pid);
    _pointers.remove(pid);
    _eraserPositions.remove(pid);
    _lastEraserPositions.remove(pid);
    _pointerDownTimes.remove(pid);
    _lastSeen.remove(pid);
    _nativeTouchHints.remove(pid);
    _smoothedDeltas.remove(pid);
    _tipOffsets.remove(pid);
    final active = _activeElements.remove(pid);
    if (active is StrokeElement) {
      active.disposeLive();
    }
  }

  void _pruneStalePointers({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastPrune).inMilliseconds < kPruneThrottleMs) return;
    _lastPrune = now;

    final toRemove = <int>[];
    for (var entry in _lastSeen.entries) {
      if (now.difference(entry.value).inMilliseconds > kPointerStaleMs) {
        toRemove.add(entry.key);
      }
    }
    for (var pid in toRemove) {
      _forgetPointer(pid);
      _prunedGhostCount++;
    }

    if (_nativePointerCount > 0) {
      final nonStylusPointers = _pointers.entries.where((e) => _isTouchKind(e.value)).toList();
      if (nonStylusPointers.length > _nativePointerCount) {
        nonStylusPointers.sort((a, b) {
          final timeA = _lastSeen[a.key] ?? DateTime.fromMillisecondsSinceEpoch(0);
          final timeB = _lastSeen[b.key] ?? DateTime.fromMillisecondsSinceEpoch(0);
          return timeA.compareTo(timeB);
        });
        final excess = nonStylusPointers.length - _nativePointerCount;
        for (int i = 0; i < excess; i++) {
          _forgetPointer(nonStylusPointers[i].key);
          _prunedGhostCount++;
        }
      }
    }
  }

  void _resetGestureEraser() {
    _isUsingGestureEraser = false;
    _eraserPositions.clear();
    _lastEraserPositions.clear();
    _gestureCenter = null;
    _gestureLastCenter = null;
    _pendingErase = null;
    _lastPalmSeen = null;
  }

  /// Koi event na aaye tab bhi ghost pointers hata deta hai aur stuck eraser circle band karta hai.
  void _startWatchdog() {
    _watchdog ??= Timer.periodic(const Duration(milliseconds: kWatchdogMs), (_) {
      if (!mounted) return;
      _pruneStalePointers(force: true);
      final hadEraserState = _isUsingGestureEraser || _gestureCenter != null;
      if (!_hasTouchDown() && hadEraserState) {
        _resetGestureEraser();
        _activeLayerPulse.value++;
      }
      if (_pointers.isEmpty) {
        _watchdog?.cancel();
        _watchdog = null;
      }
    });
  }

  bool _isPalm(PointerEvent e) {
    if (e.kind == PointerDeviceKind.stylus) return false;
    final double major = max(e.radiusMajor, e.radiusMinor);
    return major >= kPalmRadiusMajorMin || e.size >= kPalmSizeMin;
  }

  bool _isEraserMode(PointerEvent event) {
    if (event.kind == PointerDeviceKind.stylus) return false;

    _pruneStalePointers();

    final now = DateTime.now();

    // Latch: jab tak koi touch down hai, gesture eraser band nahi hoga.
    // Eraser tab band hoga jab up/cancel aaye ya watchdog ghost hata de.
    if (_isUsingGestureEraser && _hasTouchDown()) {
      _lastPalmSeen = now;
      return true;
    }

    final freshTouches = _freshTouchPointers();

    if (freshTouches.any(_isPalm)) {
      _lastPalmSeen = now;
      return true;
    }

    if (freshTouches.length >= kPalmClusterMinPoints) {
      final clusterPx = _palmClusterRadiusMaxPx;
      double maxDist = 0.0;
      for (int i = 0; i < freshTouches.length; i++) {
        for (int j = i + 1; j < freshTouches.length; j++) {
          final d = (_getCanvasLocalPos(freshTouches[i]) - _getCanvasLocalPos(freshTouches[j])).distance;
          if (d > maxDist) maxDist = d;
        }
      }
      if (maxDist < clusterPx) {
        _lastPalmSeen = now;
        return true;
      }
    }

    if (kTwoPointerRule && freshTouches.length == 2) {
      final d = (_getCanvasLocalPos(freshTouches[0]) - _getCanvasLocalPos(freshTouches[1])).distance;
      if (d < _twoPointerPalmDistanceMaxPx) {
        _lastPalmSeen = now;
        return true;
      }
    }

    if (_isUsingGestureEraser) {
      _resetGestureEraser();
    }

    return false;
  }

  Offset _getCanvasLocalPos(PointerEvent event) {
    _box ??= context.findRenderObject() as RenderBox?;
    final box = _box;
    Offset rawPos;
    if (box != null && box.attached) {
      rawPos = box.globalToLocal(event.position);
    } else {
      rawPos = event.localPosition;
    }

    final provider = Provider.of<WhiteboardProvider>(context, listen: false);
    return rawPos - provider.canvasPanOffset;
  }

  double _gestureEraseRadius() => kStaticGestureEraserRadius;

  /// Saare touch pointers (palm ke sabhi fragments) ka centroid.
  Offset _gestureEraseCentroid(Offset fallback) {
    Offset center = Offset.zero;
    int count = 0;
    for (final p in _pointers.values) {
      if (!_isTouchKind(p)) continue;
      center += _getCanvasLocalPos(p);
      count++;
    }
    if (count == 0) return fallback;
    return center / count.toDouble();
  }

  // -------------------------------------------------------------------------
  // Gesture erase (frame me ek baar)
  // -------------------------------------------------------------------------

  void _queueGestureErase(Offset center) {
    _pendingErase = center;
    _gestureCenter = center; // overlay circle turant follow kare
    if (_eraseScheduled) return;
    _eraseScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _eraseScheduled = false;
      if (!mounted) return;
      _flushPendingErase(context.read<WhiteboardProvider>());
      _activeLayerPulse.value++;
    });
  }

  void _flushPendingErase(WhiteboardProvider provider) {
    final c = _pendingErase;
    _pendingErase = null;
    if (c == null || !_isUsingGestureEraser) return;
    final prev = _gestureLastCenter;
    if (prev != null && (c - prev).distance < kGestureMinMovePx) {
      return; // microscopic jitter skip
    }
    provider.partialErase(c, _gestureEraseRadius(), lastPos: prev ?? c);
    _gestureLastCenter = c;
  }

  void _switchToEraserMode(WhiteboardProvider provider) {
    _isUsingGestureEraser = true;

    // Sirf touch wali in-progress strokes discard karo, stylus ki nahi.
    final toDrop = _activeElements.keys.where((id) {
      final p = _pointers[id];
      return p == null || _isTouchKind(p);
    }).toList();
    for (final id in toDrop) {
      final e = _activeElements.remove(id);
      if (e is StrokeElement) e.disposeLive();
    }

    _eraserPositions.clear();
    _lastEraserPositions.clear();

    final c = _gestureEraseCentroid(_gestureCenter ?? Offset.zero);
    _gestureCenter = c;
    _gestureLastCenter = c;
    _pendingErase = null;
    provider.partialErase(c, _gestureEraseRadius(), lastPos: c);
    _requestRepaint();
  }

  // -------------------------------------------------------------------------
  // Pointer handlers
  // -------------------------------------------------------------------------

  void _onPointerDown(PointerDownEvent event, WhiteboardProvider provider) {
    _startWatchdog();
    _pruneStalePointers(force: true);
    _lastSeen[event.pointer] = DateTime.now();
    _pointerDownTimes[event.pointer] = DateTime.now();
    _pointers[event.pointer] = event;

    if (kDebugPointerInfo) {
      debugPrint(
        'DOWN: kind=${event.kind} dev=${event.device} id=${event.pointer} '
        'rMajor=${event.radiusMajor.toStringAsFixed(1)} rMinor=${event.radiusMinor.toStringAsFixed(1)} '
        'size=${event.size.toStringAsFixed(4)} press=${event.pressure.toStringAsFixed(2)} '
        'active=${_pointers.length}',
      );
    }
    final localPos = _getCanvasLocalPos(event);
    final pointerId = event.pointer;
    _smoothedDeltas[pointerId] = Offset.zero;
    _tipOffsets[pointerId] = Offset.zero;

    if (provider.currentTool == WhiteboardTool.preview) {
      _panPointerId ??= pointerId;
      return;
    }

    // 1. MindMap buttons: element select ho ya na ho, pen/select dono me kaam kare
    if (!_isPalm(event) && _handleMindMapButtons(localPos, provider)) {
      _requestRepaint();
      return;
    }

    if (provider.currentTool == WhiteboardTool.eraser) {
      _eraserPositions[pointerId] = localPos;
      _lastEraserPositions[pointerId] = localPos;
      provider.partialErase(localPos, provider.eraserSize, lastPos: localPos);
      _requestRepaint();
      return;
    }

    if (_isEraserMode(event)) {
      if (!_isUsingGestureEraser) {
        _switchToEraserMode(provider);
      } else {
        _queueGestureErase(_gestureEraseCentroid(localPos));
      }
      return;
    }

    if (provider.currentTool == WhiteboardTool.select) {
      if (_activeElements.isEmpty) {
        final hit = provider.hitTest(localPos);
        if (hit != null) {
          if (hit is MindMapElement) {
            final n = hit.nodeAt(_mmLocal(hit, localPos));
            if (n != null && hit.selectedNodeId != n.id) {
              hit.selectedNodeId = n.id;
              provider.refreshBoard(); // warna cached picture me selection border update nahi hota
            }
          }
          provider.selectElement(hit.id, multi: provider.selectedElementIds.contains(hit.id));
        } else {
          _currentLasso = Path()..moveTo(localPos.dx, localPos.dy);
          provider.clearSelection();
          _requestRepaint();
        }
      }
      return;
    }

    final id = const Uuid().v4();
    final docPage = provider.isDocumentOverlayOpen ? provider.overlayCurrentPage : null;
    if (provider.currentTool == WhiteboardTool.pen) {
      _detectNib(event, provider);

      // Pen kisi node ke andar se shuru hua -> node select + stroke us node ki hogi
      final startHit = _mindMapNodeAt(localPos, provider, inflate: 6);
      if (startHit != null) {
        _mmStrokeTargets[pointerId] = (mmId: startHit.el.id, nodeId: startHit.node.id);
        if (startHit.el.selectedNodeId != startHit.node.id) {
          startHit.el.selectedNodeId = startHit.node.id;
          provider.refreshBoard();
        }
      }

      _activeElements[pointerId] = StrokeElement(
        id: id,
        position: localPos,
        points: [localPos],
        color: provider.currentColor,
        strokeWidth: provider.strokeWidth,
        penType: provider.currentPenType,
        docPage: docPage,
      );
    } else if (provider.currentTool == WhiteboardTool.shape) {
      _activeElements[pointerId] = ShapeElement(
        id: id,
        position: localPos,
        shapeType: provider.currentShapeType,
        endPoint: localPos,
        color: provider.currentColor,
        strokeWidth: provider.strokeWidth,
        docPage: docPage,
      );
    } else if (provider.currentTool == WhiteboardTool.eraser) {
      _eraserPositions[pointerId] = localPos;
      _lastEraserPositions[pointerId] = localPos;
      provider.partialErase(localPos, provider.eraserSize, lastPos: localPos);
    }
    _requestRepaint();
  }

  void _detectNib(PointerEvent event, WhiteboardProvider provider) {
    double effectiveRadius = event.radiusMajor;
    if (event.radiusMinor > 0 && event.radiusMajor > 0) {
      effectiveRadius = (event.radiusMajor + event.radiusMinor) / 2.0;
    }
    if (effectiveRadius == 0 && event.size > 0) {
      effectiveRadius = event.size * 100.0;
    }
    final isInvertedStylus = event.kind == PointerDeviceKind.invertedStylus;
    provider.autoDetectNibProfile(effectiveRadius, isInvertedStylus: isInvertedStylus);
  }

  void _onPointerMove(PointerMoveEvent event, WhiteboardProvider provider) {
    _pointers[event.pointer] = event;
    _lastSeen[event.pointer] = DateTime.now();
    _processSinglePointerMove(event, provider);
  }

  void _processSinglePointerMove(PointerMoveEvent event, WhiteboardProvider provider) {
    _pruneStalePointers();
    final pointerId = event.pointer;
    final localPos = _getCanvasLocalPos(event);

    if (provider.currentTool == WhiteboardTool.preview) {
      if (event.pointer == _panPointerId) {
        provider.panCanvas(event.delta);
      }
      _requestRepaint();
      return;
    }

    if (kDebugPointerInfo && DateTime.now().difference(_lastMoveLogTime).inMilliseconds > 100) {
      debugPrint('MOVE: pointers=${_pointers.length} fresh=${_freshTouchPointers().length} eraserMode=$_isUsingGestureEraser');
      _lastMoveLogTime = DateTime.now();
    }

    // Eraser check sabse pehle: palm ke radius se nib-profile kharab na ho.
    if (_isEraserMode(event)) {
      if (!_isUsingGestureEraser) {
        _switchToEraserMode(provider);
        return;
      }
      _queueGestureErase(_gestureEraseCentroid(localPos));
      return;
    }

    if (provider.currentTool == WhiteboardTool.pen) {
      _detectNib(event, provider);
    }

    if (provider.currentTool == WhiteboardTool.select && _currentLasso != null) {
      _currentLasso!.lineTo(localPos.dx, localPos.dy);
      provider.updateLassoPath(_currentLasso);
      _requestRepaint();
      return;
    }

    if (provider.currentTool == WhiteboardTool.eraser || _eraserPositions.containsKey(pointerId)) {
      final prevPos = _lastEraserPositions[pointerId] ?? localPos;
      _eraserPositions[pointerId] = localPos;
      _lastEraserPositions[pointerId] = localPos;
      provider.partialErase(localPos, provider.eraserSize, lastPos: prevPos);
      _requestRepaint();
      return;
    }

    final active = _activeElements[pointerId];
    if (active == null) return;

    if (active is StrokeElement) {
      if (active.addPoint(localPos)) {
        active.predictedTip = null;
        _requestRepaint();
      }
    } else if (active is ShapeElement) {
      _activeElements[pointerId] = active.copyWith(endPoint: localPos)..invalidateBounds();
      _requestRepaint();
    }
  }

  void _onPointerUp(PointerUpEvent event, WhiteboardProvider provider) {
    _pruneStalePointers(force: true);
    if (kDebugPointerInfo) {
      debugPrint('UP: id=${event.pointer} remaining=${_pointers.length - 1}');
    }
    final pointerId = event.pointer;

    // Pending erase (agar frame se pehle up aa gaya) turant flush karo.
    if (_isUsingGestureEraser) {
      _flushPendingErase(provider);
    }

    final bool wasGestureEraser = _isUsingGestureEraser;
    final mmTarget = _mmStrokeTargets[pointerId];
    final element = _activeElements.remove(pointerId);
    _forgetPointer(pointerId);

    if (!_hasTouchDown()) {
      _resetGestureEraser();
    }

    if (provider.currentTool == WhiteboardTool.select) {
      if (_currentLasso != null) {
        _currentLasso!.close();
        provider.updateLassoPath(_currentLasso);
        _currentLasso = null;
        provider.updateLassoPath(null);
      }
      _requestRepaint();
      return;
    }

    // Touch stroke gesture-eraser ke dauran drop; stylus stroke hamesha commit.
    final bool dropElement = wasGestureEraser && _isTouchKind(event);
    if (element != null && !dropElement) {
      if (element is StrokeElement && element.points.length > 1) {
        element.invalidatePath();

        // Pen node ke andar se shuru hua tha -> stroke node me save, node resize
        if (mmTarget != null) {
          final mm = _findMindMapById(provider, mmTarget.mmId);
          final node = mm?.root.findNode(mmTarget.nodeId);
          if (mm != null && node != null) {
            mm.addStroke(node.id, element.points.map((p) => _mmLocal(mm, p)).toList(), color: element.color);
            mm.selectedNodeId = node.id;
            element.disposeLive();
            provider.refreshBoard();
            _requestRepaint();
            return;
          }
        }

        provider.addElement(element);
        WhiteboardPainter.appendElementToCache(element, provider.boardVersion);
      } else if (element is ShapeElement) {
        if ((element.position - element.endPoint).distance > 5) {
          provider.addElement(element);
          WhiteboardPainter.appendElementToCache(element, provider.boardVersion);
        }
      } else if (element is StrokeElement) {
        element.disposeLive();
      }
    } else if (element is StrokeElement) {
      element.disposeLive();
    }
    _requestRepaint();
  }

  void _onPointerCancel(PointerCancelEvent event, WhiteboardProvider provider) {
    _pruneStalePointers(force: true);
    _cancelEventCount++;
    final pointerId = event.pointer;
    final localPos = _getCanvasLocalPos(event);

    final downTime = _pointerDownTimes[pointerId];
    final durationMs = downTime != null ? DateTime.now().difference(downTime).inMilliseconds : 999;
    final hint = _nativeTouchHints[pointerId];

    final bool isPalmCancel =
        durationMs < kPalmCancelTimeWindowMs && (_isPalm(event) || (hint != null && (hint['isCanceled'] == true || hint['toolType'] == 5)));

    _lastCancelInfo = 'id=$pointerId dur=${durationMs}ms palm=$isPalmCancel';
    if (kDebugPointerInfo) {
      debugPrint('CANCEL: $_lastCancelInfo totalCount=$_cancelEventCount');
    }

    if (_isUsingGestureEraser) {
      _flushPendingErase(provider);
    }

    if (isPalmCancel) {
      provider.partialErase(localPos, _gestureEraseRadius(), lastPos: localPos);
    }

    _forgetPointer(pointerId); // active element bhi dispose ho jata hai

    if (!_hasTouchDown()) {
      _resetGestureEraser();
    }
    _requestRepaint();
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  List<BoardElement> _displayElementsFor(Iterable<BoardElement> elements, int version, bool overlay, int page) {
    final len = elements.length;
    if (identical(_displaySource, elements) &&
        _displayCacheVersion == version &&
        _displayCacheOverlay == overlay &&
        _displayCachePage == page &&
        _displayCacheLen == len) {
      return _displayCache;
    }
    _displaySource = elements;
    _displayCacheVersion = version;
    _displayCacheOverlay = overlay;
    _displayCachePage = page;
    _displayCacheLen = len;
    _displayCache = overlay ? elements.where((e) => e.docPage == page).toList() : elements.where((e) => e.docPage == null).toList();
    return _displayCache;
  }

  Widget _eraserCircle({
    required double radius,
    required double borderWidth,
    required double minIcon,
    required double maxIcon,
    required double iconFactor,
  }) {
    final diameter = radius * 2.0;
    // Blur shadow raster thread par mehnga hota hai, isliye hata diya.
    return RepaintBoundary(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFFFFF), Color(0xFFF1F5F9)],
          ),
          border: Border.all(color: const Color(0xFF94A3B8), width: borderWidth),
        ),
        child: Center(
          child: Icon(LucideIcons.eraser, color: const Color(0xFF64748B), size: (diameter * iconFactor).clamp(minIcon, maxIcon)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Selector<WhiteboardProvider, (int, Set<String>, Path?, WhiteboardTool, bool, int, Offset)>(
      selector: (context, provider) => (
        provider.boardVersion,
        provider.selectedElementIds,
        provider.lassoPath,
        provider.currentTool,
        provider.isDocumentOverlayOpen,
        provider.overlayCurrentPage,
        provider.canvasPanOffset,
      ),
      builder: (context, data, _) {
        final provider = context.read<WhiteboardProvider>();
        final elements = provider.currentPage.elements;
        final selectedIds = data.$2;
        final lassoPath = data.$3;
        final currentTool = data.$4;
        final isOverlayOpen = data.$5;
        final overlayCurrentPage = data.$6;
        final panOffset = data.$7;

        final displayElements = _displayElementsFor(elements, data.$1, isOverlayOpen, overlayCurrentPage);

        final shouldIgnoreTouches = isOverlayOpen && currentTool == WhiteboardTool.select;

        return IgnorePointer(
          ignoring: shouldIgnoreTouches,
          child: Listener(
            onPointerDown: (e) => _onPointerDown(e, provider),
            onPointerMove: (e) => _onPointerMove(e, provider),
            onPointerUp: (e) => _onPointerUp(e, provider),
            onPointerCancel: (e) => _onPointerCancel(e, provider),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    isComplex: true,
                    willChange: false,
                    foregroundPainter: WhiteboardPainter(
                      elements: displayElements,
                      activeElements: const [],
                      lassoPath: null,
                      selectedIds: selectedIds,
                      version: data.$1,
                      panOffset: panOffset,
                    ),
                    size: Size.infinite,
                    child: Transform.translate(
                      offset: panOffset,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ...displayElements.whereType<ImageElement>().map((img) {
                            final rawRect = img.getRawBounds();
                            final visualRect = Rect.fromCenter(
                              center: rawRect.center,
                              width: rawRect.width * img.scale,
                              height: rawRect.height * img.scale,
                            );
                            return Positioned(
                              left: visualRect.left,
                              top: visualRect.top,
                              width: visualRect.width,
                              height: visualRect.height,
                              child: Transform.rotate(
                                angle: img.rotation,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: [
                                      BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4)),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: img.imageUrl.startsWith('http')
                                        ? Image.network(
                                            img.imageUrl,
                                            fit: BoxFit.contain,
                                            filterQuality: FilterQuality.high,
                                            errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 50),
                                          )
                                        : Image.file(
                                            File(img.imageUrl),
                                            fit: BoxFit.contain,
                                            filterQuality: FilterQuality.high,
                                            errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 50),
                                          ),
                                  ),
                                ),
                              ),
                            );
                          }),
                          ...displayElements.whereType<DocumentElement>().map((doc) {
                            final rawRect = doc.getRawBounds();
                            final visualRect = Rect.fromCenter(
                              center: rawRect.center,
                              width: rawRect.width * doc.scale,
                              height: rawRect.height * doc.scale,
                            );

                            final lowerPath = doc.filePath.toLowerCase();
                            final lowerName = doc.fileName.toLowerCase();
                            final isPptx =
                                lowerPath.endsWith('.pptx') ||
                                lowerName.endsWith('.pptx') ||
                                lowerPath.endsWith('.ppt') ||
                                lowerName.endsWith('.ppt');

                            Widget content;
                            if (isPptx) {
                              content = PptxViewer(file: File(doc.filePath), size: visualRect.size, slideIndex: doc.docPage ?? 0);
                            } else {
                              content = Container(
                                color: Colors.white,
                                padding: const EdgeInsets.all(12),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.description, size: 48, color: Colors.blueAccent),
                                      const SizedBox(height: 8),
                                      Text(
                                        doc.fileName,
                                        style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 14),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }

                            return Positioned(
                              left: visualRect.left,
                              top: visualRect.top,
                              width: visualRect.width,
                              height: visualRect.height,
                              child: Transform.rotate(
                                angle: doc.rotation,
                                child: ClipRRect(borderRadius: BorderRadius.circular(4), child: content),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
                // Live (active strokes / lasso) layer
                RepaintBoundary(
                  child: ValueListenableBuilder<int>(
                    valueListenable: _activeLayerPulse,
                    builder: (context, _, _) {
                      return CustomPaint(
                        isComplex: false,
                        willChange: true,
                        painter: WhiteboardPainter(
                          elements: const [],
                          activeElements: _activeElements.values.toList(),
                          lassoPath: lassoPath ?? _currentLasso,
                          selectedIds: const {},
                          panOffset: panOffset,
                        ),
                        size: Size.infinite,
                      );
                    },
                  ),
                ),
                // Eraser circle overlay
                ValueListenableBuilder<int>(
                  valueListenable: _activeLayerPulse,
                  builder: (context, _, _) {
                    if (_isUsingGestureEraser) {
                      final center = _gestureCenter;
                      if (center == null) return const SizedBox.shrink();
                      final r = _gestureEraseRadius();
                      return Positioned(
                        left: center.dx + panOffset.dx - r, // <-- ADD pan
                        top: center.dy + panOffset.dy - r,  // <-- ADD pan
                        child: _eraserCircle(radius: r, borderWidth: 2.2, minIcon: 24, maxIcon: 48, iconFactor: 0.45),
                      );
                    }

                    if (provider.currentTool != WhiteboardTool.eraser || _eraserPositions.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    final double radius = provider.eraserSize;
                    return Stack(
                      children: _eraserPositions.values.map((pos) {
                        return Positioned(
                          left: pos.dx + panOffset.dx - radius, // <-- ADD pan
                          top: pos.dy + panOffset.dy - radius,  // <-- ADD pan
                          child: _eraserCircle(radius: radius, borderWidth: 1.8, minIcon: 12, maxIcon: 32, iconFactor: 0.42),
                        );
                      }).toList(),
                    );
                  },
                ),
                if (kDebugPointerInfo)
                  ValueListenableBuilder<int>(valueListenable: _activeLayerPulse, builder: (context, _, _) => _buildDebugPointerOverlay()),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDebugPointerOverlay() {
    if (!kDebugPointerInfo) return const SizedBox.shrink();

    final mq = MediaQuery.of(context);
    final pxMm = _pxPerMm;
    final freshPointers = _freshTouchPointers();
    final msSincePalm = _lastPalmSeen != null ? DateTime.now().difference(_lastPalmSeen!).inMilliseconds : -1;

    return Positioned(
      top: 12,
      right: 12,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.all(10),
          width: 340,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.7), width: 1.5),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.bug_report, color: Colors.cyanAccent, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Touch & Palm Diagnostics (Round 4)',
                    style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ],
              ),
              const Divider(color: Colors.white24, height: 10),
              Text(
                'Screen: ${mq.size.width.toStringAsFixed(0)}x${mq.size.height.toStringAsFixed(0)} | DPR: ${mq.devicePixelRatio.toStringAsFixed(1)} | px/mm: ${pxMm.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.amberAccent, fontSize: 9, fontFamily: 'monospace'),
              ),
              Text(
                'Fresh: ${freshPointers.length} | Raw: ${_pointers.length} | GhostPruned: $_prunedGhostCount | NativeCnt: $_nativePointerCount',
                style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w600),
              ),
              Text(
                'EraserMode: $_isUsingGestureEraser | MsSincePalm: ${msSincePalm >= 0 ? "${msSincePalm}ms" : "none"}',
                style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 9.5, fontWeight: FontWeight.w600),
              ),
              Text(
                'Cancels: $_cancelEventCount | Last: $_lastCancelInfo',
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 9, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 6),
              ...freshPointers.map((p) {
                final isP = _isPalm(p);
                final hint = _nativeTouchHints[p.pointer];
                final nativeStr = hint != null ? 'Native: tool=${hint['toolType']} cnl=${hint['isCanceled']}' : 'Native: --';
                final String reason = isP
                    ? (max(p.radiusMajor, p.radiusMinor) >= kPalmRadiusMajorMin ? "Radius" : "Size")
                    : (freshPointers.length >= kPalmClusterMinPoints ? "Cluster" : "Finger");
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '#${p.pointer} | ${p.kind.name} | R:${max(p.radiusMajor, p.radiusMinor).toStringAsFixed(1)} | Sz:${p.size.toStringAsFixed(4)} | Palm:$isP ($reason)\n $nativeStr',
                    style: TextStyle(color: isP ? Colors.yellowAccent : Colors.lightGreenAccent, fontSize: 9, fontFamily: 'monospace'),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// PAINTER (logic unchanged)
// ===========================================================================

class WhiteboardPainter extends CustomPainter {
  final List<BoardElement> elements;
  final List<BoardElement> activeElements;
  final Path? lassoPath;
  final Set<String> selectedIds;
  final int version;
  final Offset panOffset;

  static ui.Picture? _cachedElementsPicture;
  static int _cachedVersion = -1;
  static int _cachedElementCount = -1;
  static Size _cachedSize = Size.zero;
  static Set<String> _cachedSelectedIds = const {};

  final Paint _strokePaint = Paint()
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true
    ..filterQuality = FilterQuality.high
    ..style = PaintingStyle.stroke;

  final Paint _fillPaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill;

  WhiteboardPainter({
    required this.elements,
    required this.activeElements,
    this.lassoPath,
    required this.selectedIds,
    this.version = 0,
    this.panOffset = Offset.zero,
  });

  @override
  bool shouldRepaint(covariant WhiteboardPainter oldDelegate) {
    return oldDelegate.version != version ||
        oldDelegate.elements != elements ||
        oldDelegate.activeElements != activeElements ||
        oldDelegate.lassoPath != lassoPath ||
        oldDelegate.selectedIds != selectedIds ||
        oldDelegate.panOffset != panOffset;
  }

  static void invalidateCache() {
    _cachedElementsPicture?.dispose();
    _cachedElementsPicture = null;
    _cachedVersion = -1;
    _cachedElementCount = -1;
  }

  static void appendElementToCache(BoardElement newElement, int version) {
    if (_cachedElementsPicture != null && _cachedSize != Size.zero) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      canvas.drawPicture(_cachedElementsPicture!);

      final painter = WhiteboardPainter(elements: const [], activeElements: const [], selectedIds: const {}, version: version);
      painter._drawElement(canvas, newElement);

      _cachedElementsPicture?.dispose();
      _cachedElementsPicture = recorder.endRecording();
      _cachedElementCount++;
      _cachedVersion = version;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(panOffset.dx, panOffset.dy);
    try {
      if (elements.isNotEmpty) {
        final bool isCacheValid =
            _cachedElementsPicture != null &&
            _cachedVersion == version &&
            _cachedElementCount == elements.length &&
            _cachedSize == size &&
            _cachedSelectedIds.length == selectedIds.length &&
            _cachedSelectedIds.containsAll(selectedIds);

        if (isCacheValid) {
          canvas.drawPicture(_cachedElementsPicture!);
        } else {
          final recorder = ui.PictureRecorder();
          final recorderCanvas = Canvas(recorder);

          for (var element in elements) {
            _drawElement(recorderCanvas, element);
          }

          _cachedElementsPicture?.dispose();
          _cachedElementsPicture = recorder.endRecording();
          _cachedVersion = version;
          _cachedElementCount = elements.length;
          _cachedSize = size;
          _cachedSelectedIds = Set.from(selectedIds);

          canvas.drawPicture(_cachedElementsPicture!);
        }
      }

      for (var element in activeElements) {
        _drawElement(canvas, element, isActive: true);
      }

      if (lassoPath != null) {
        canvas.drawPath(lassoPath!, _fillPaint..color = Colors.blue.withValues(alpha: 0.05));
        _strokePaint
          ..color = Colors.blue.withValues(alpha: 0.5)
          ..strokeWidth = 1.5;
        _drawDashedPath(canvas, lassoPath!, _strokePaint);
      }
    } finally {
      canvas.restore();
    }
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    const dashWidth = 8.0;
    const dashSpace = 6.0;
    for (var metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final Path extract = metric.extractPath(distance, distance + dashWidth);
        canvas.drawPath(extract, paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  void _drawElement(Canvas canvas, BoardElement element, {bool isActive = false}) {
    if (element is ImageElement || element is DocumentElement) return;

    final isSelected = selectedIds.contains(element.id);
    final hasTransform = element.rotation != 0 || element.scale != 1.0;

    if (hasTransform) {
      canvas.save();
      final rawBounds = element.getRawBounds();
      final center = rawBounds.center;
      canvas.translate(center.dx, center.dy);
      canvas.rotate(element.rotation);
      canvas.scale(element.scale);
      canvas.translate(-center.dx, -center.dy);
    }

    if (element is StrokeElement) {
      if (isSelected) {
        _strokePaint
          ..maskFilter = null
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = element.color
          ..strokeWidth = element.strokeWidth;

        if (element.points.length == 1) {
          canvas.drawCircle(element.points[0], element.strokeWidth / 2, _fillPaint..color = element.color);
        } else if (element.points.length > 1) {
          canvas.drawPath(element.path, _strokePaint);
          final p1 = element.points[element.points.length - 2];
          final p2 = element.points[element.points.length - 1];
          final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
          canvas.drawLine(mid, p2, _strokePaint);
          if (isActive && element.predictedTip != null) {
            canvas.drawLine(p2, element.predictedTip!, _strokePaint);
          }
        }
      } else {
        // Not selected - render based on penType with high fidelity
        switch (element.penType) {
          case PenType.pen:
            _strokePaint
              ..maskFilter = null
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..color = element.color
              ..strokeWidth = element.strokeWidth;

            if (element.points.length == 1) {
              canvas.drawCircle(element.points[0], element.strokeWidth / 2, _fillPaint..color = element.color);
            } else if (element.points.length > 1) {
              canvas.drawPath(element.path, _strokePaint);
              if (isActive) {
                final p1 = element.points[element.points.length - 2];
                final p2 = element.points.last;
                final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
                canvas.drawLine(mid, p2, _strokePaint);
              }
            }
            break;

          case PenType.fountainPen:
            if (element.points.length == 1) {
              canvas.drawCircle(element.points[0], element.strokeWidth / 2, _fillPaint..color = element.color);
            } else if (element.points.length > 1) {
              final calligraphyPaint = Paint()
                ..style = PaintingStyle.stroke
                ..strokeCap = StrokeCap.round
                ..strokeJoin = StrokeJoin.round
                ..color = element.color;

              final points = element.points;
              final n = points.length;
              final List<double> smoothedWidths = element.cachedWidths;

              if (n == 2) {
                calligraphyPaint.strokeWidth = (smoothedWidths[0] + smoothedWidths[1]) / 2;
                canvas.drawLine(points[0], points[1], calligraphyPaint);
              } else {
                for (var i = 0; i < n - 1; i++) {
                  final pA = points[i];
                  final pB = points[i + 1];
                  final m1 = i == 0 ? pA : Offset((pA.dx + pB.dx) / 2, (pA.dy + pB.dy) / 2);
                  final m2 = (i == n - 2 && !isActive)
                      ? pB
                      : Offset((pB.dx + points[min(i + 2, n - 1)].dx) / 2, (pB.dy + points[min(i + 2, n - 1)].dy) / 2);

                  final segmentPath = Path()
                    ..moveTo(m1.dx, m1.dy)
                    ..quadraticBezierTo(pB.dx, pB.dy, m2.dx, m2.dy);

                  calligraphyPaint.strokeWidth = (smoothedWidths[i] + smoothedWidths[i + 1]) / 2;
                  canvas.drawPath(segmentPath, calligraphyPaint);
                }
              }

              if (isActive && points.length >= 2) {
                final lastP = points.last;
                final prevP = points[points.length - 2];
                final midP = Offset((prevP.dx + lastP.dx) / 2, (prevP.dy + lastP.dy) / 2);
                calligraphyPaint.strokeWidth = smoothedWidths.last;
                canvas.drawLine(midP, lastP, calligraphyPaint);
              }
            }
            break;

          case PenType.brush:
            if (element.points.length == 1) {
              final brushDot = Paint()
                ..style = PaintingStyle.fill
                ..color = element.color;
              canvas.drawCircle(element.points[0], element.strokeWidth / 2, brushDot);
            } else if (element.points.length > 1) {
              final brushPaint = Paint()
                ..style = PaintingStyle.stroke
                ..strokeCap = StrokeCap.round
                ..strokeJoin = StrokeJoin.round
                ..color = element.color;

              final totalPoints = element.points.length;
              const int taperCount = 5;

              for (var i = 0; i < totalPoints - 1; i++) {
                final p1 = element.points[i];
                final p2 = element.points[i + 1];

                double taper = 1.0;
                if (i < taperCount) {
                  taper = (i + 1) / taperCount;
                } else if (!isActive && i >= totalPoints - taperCount) {
                  taper = (totalPoints - i) / taperCount;
                }
                final dynamicWidth = element.strokeWidth * (0.5 + taper * 0.5);

                brushPaint.strokeWidth = dynamicWidth.clamp(1.0, element.strokeWidth * 1.15);
                canvas.drawLine(p1, p2, brushPaint);
              }

              if (isActive && element.points.length >= 2) {
                final lastP = element.points.last;
                final prevP = element.points[element.points.length - 2];
                final midP = Offset((prevP.dx + lastP.dx) / 2, (prevP.dy + lastP.dy) / 2);
                brushPaint.strokeWidth = element.strokeWidth;
                canvas.drawLine(midP, lastP, brushPaint);
              }
            }
            break;

          case PenType.marker:
            final markerWidth = element.strokeWidth;
            _strokePaint
              ..maskFilter = null
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..strokeWidth = markerWidth
              ..color = element.color.withValues(alpha: 0.40);

            if (element.points.length == 1) {
              canvas.drawCircle(element.points[0], markerWidth / 2, _fillPaint..color = element.color.withValues(alpha: 0.40));
            } else if (element.points.length > 1) {
              canvas.drawPath(element.path, _strokePaint);
              if (isActive) {
                final p1 = element.points[element.points.length - 2];
                final p2 = element.points.last;
                final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
                canvas.drawLine(mid, p2, _strokePaint);
              }
            }
            break;
        }
      }
    } else if (element is ShapeElement) {
      _strokePaint
        ..color = element.color
        ..strokeWidth = element.strokeWidth
        ..maskFilter = null;

      switch (element.shapeType) {
        case ShapeType.line:
          canvas.drawLine(element.position, element.endPoint, _strokePaint);
          break;
        case ShapeType.rectangle:
          canvas.drawRect(Rect.fromPoints(element.position, element.endPoint), _strokePaint);
          break;
        case ShapeType.circle:
          final rect = Rect.fromPoints(element.position, element.endPoint);
          canvas.drawOval(rect, _strokePaint);
          break;
        case ShapeType.arrow:
          _drawArrow(canvas, element.position, element.endPoint, _strokePaint);
          break;
        case ShapeType.triangle:
          _drawTriangle(canvas, element.position, element.endPoint, _strokePaint);
          break;
        case ShapeType.star:
          _drawStar(canvas, element.position, element.endPoint, _strokePaint);
          break;
        case ShapeType.diamond:
          _drawDiamond(canvas, element.position, element.endPoint, _strokePaint);
          break;
        case ShapeType.pentagon:
          _drawPolygon(canvas, element.position, element.endPoint, 5, _strokePaint);
          break;
        case ShapeType.hexagon:
          _drawPolygon(canvas, element.position, element.endPoint, 6, _strokePaint);
          break;
        case ShapeType.rightTriangle:
          _drawRightTriangle(canvas, element.position, element.endPoint, _strokePaint);
          break;
        case ShapeType.parallelogram:
          _drawParallelogram(canvas, element.position, element.endPoint, _strokePaint);
          break;
        case ShapeType.trapezoid:
          _drawTrapezoid(canvas, element.position, element.endPoint, _strokePaint);
          break;
        case ShapeType.heart:
          _drawHeart(canvas, element.position, element.endPoint, _strokePaint);
          break;
        case ShapeType.cube3d:
          _drawCube3D(canvas, element.position, element.endPoint, _strokePaint);
          break;
        case ShapeType.cylinder3d:
          _drawCylinder3D(canvas, element.position, element.endPoint, _strokePaint);
          break;
        case ShapeType.cone3d:
          _drawCone3D(canvas, element.position, element.endPoint, _strokePaint);
          break;
        case ShapeType.pyramid3d:
          _drawPyramid3D(canvas, element.position, element.endPoint, _strokePaint);
          break;
        case ShapeType.sphere3d:
          _drawSphere3D(canvas, element.position, element.endPoint, _strokePaint);
          break;
      }

      if (isActive || element.showDimensions) {
        _drawEnhancedDimensions(canvas, element, isActive);
      }
    } else if (element is TextElement) {
      final textSpan = TextSpan(
        text: element.text,
        style: TextStyle(color: element.color, fontSize: element.fontSize, fontWeight: FontWeight.w600, fontFamily: element.fontFamily),
      );
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      textPainter.layout();
      textPainter.paint(canvas, element.position);
    } else if (element is TableElement) {
      final tbl = element;
      final rect = Rect.fromLTWH(tbl.position.dx, tbl.position.dy, tbl.size.width, tbl.size.height);

      // Header row background tint
      if (tbl.rows > 0) {
        final headerHeight = tbl.size.height / tbl.rows;
        final headerRect = Rect.fromLTWH(tbl.position.dx, tbl.position.dy, tbl.size.width, headerHeight);
        canvas.drawRect(headerRect, Paint()..color = tbl.color.withValues(alpha: 0.08));
      }

      final gridPaint = Paint()
        ..color = tbl.color
        ..strokeWidth = tbl.strokeWidth
        ..style = PaintingStyle.stroke;

      // Outer table border
      canvas.drawRect(rect, gridPaint);

      // Horizontal row divider lines
      final rowH = tbl.size.height / tbl.rows;
      for (int r = 1; r < tbl.rows; r++) {
        final y = tbl.position.dy + r * rowH;
        canvas.drawLine(Offset(tbl.position.dx, y), Offset(tbl.position.dx + tbl.size.width, y), gridPaint);
      }

      // Vertical column divider lines
      final colW = tbl.size.width / tbl.cols;
      for (int c = 1; c < tbl.cols; c++) {
        final x = tbl.position.dx + c * colW;
        canvas.drawLine(Offset(x, tbl.position.dy), Offset(x, tbl.position.dy + tbl.size.height), gridPaint);
      }
    } else if (element is MindMapElement) {
      _drawMindMapNodeTree(canvas, element, element.root, element.position);
    }

    if (hasTransform) {
      canvas.restore();
    }
  }

  void _drawMindMapNodeTree(Canvas canvas, MindMapElement mm, MindMapNode node, Offset basePos) {
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
      final parentRight = Offset(localPos.dx + node.width, localPos.dy + node.height / 2);
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
    final nodeRect = Rect.fromLTWH(localPos.dx, localPos.dy, node.width, node.height);
    final nodeRRect = RRect.fromRectAndRadius(nodeRect, const Radius.circular(10.0));
    final isSelected = (mm.selectedNodeId == node.id);

    // Box Background Fill (Teal #00BFA5)
    canvas.drawRRect(nodeRRect, Paint()..color = node.fillColor);

    if (isSelected) {
      // Single clean light blue border around box
      final lightBlueBorderRRect = RRect.fromRectAndRadius(nodeRect.inflate(3.5), const Radius.circular(13.0));
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
          style: TextStyle(color: node.textColor, fontSize: 15.0, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      textPainter.layout(maxWidth: max(10.0, min(MindMapNode.kMaxTextW, node.width - 16.0)));
      textPainter.paint(
        canvas,
        Offset(localPos.dx + (node.width - textPainter.width) / 2, localPos.dy + (node.height - textPainter.height) / 2),
      );
    }

    // 4. Handwriting
    if (node.strokes.isNotEmpty) {
      for (int i = 0; i < node.strokes.length; i++) {
        final stroke = node.strokes[i];
        final strokeColor = (i < node.strokeColors.length) ? node.strokeColors[i] : node.textColor;

        if (stroke.length > 1) {
          final strokePaint = Paint()
            ..color = strokeColor
            ..strokeWidth = 2.5
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round;

          final path = Path()..moveTo(localPos.dx + stroke[0].dx, localPos.dy + stroke[0].dy);
          for (int j = 1; j < stroke.length; j++) {
            path.lineTo(localPos.dx + stroke[j].dx, localPos.dy + stroke[j].dy);
          }
          canvas.drawPath(path, strokePaint);
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
      canvas.drawLine(Offset(c.dx - 3.5, c.dy), Offset(c.dx + 3.5, c.dy), iconPaint); // "-"
      if (node.collapsed) {
        canvas.drawLine(Offset(c.dx, c.dy - 3.5), Offset(c.dx, c.dy + 3.5), iconPaint); // "+"
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
        canvas.drawLine(Offset(c.dx - 3.8, c.dy), Offset(c.dx + 3.8, c.dy), plusPaint);
        canvas.drawLine(Offset(c.dx, c.dy - 3.8), Offset(c.dx, c.dy + 3.8), plusPaint);
      }

      // "..." (delete)
      final top = basePos + mm.btnCenter(node, MindMapAction.menu);
      canvas.drawCircle(top, 8.5, btnPaint);
      canvas.drawCircle(top, 8.5, borderPaint);
      canvas.drawCircle(Offset(top.dx - 3.0, top.dy), 1.0, dotPaint);
      canvas.drawCircle(top, 1.0, dotPaint);
      canvas.drawCircle(Offset(top.dx + 3.0, top.dy), 1.0, dotPaint);

      plus(MindMapAction.addParent);
      plus(MindMapAction.addChild);
      if (!identical(node, mm.root)) plus(MindMapAction.addSibling); // root ka sibling nahi hota
    }

    // 7. Children (collapsed ho toh skip)
    if (showChildren) {
      for (final child in node.children) {
        _drawMindMapNodeTree(canvas, mm, child, basePos);
      }
    }
  }

  void _drawEnhancedDimensions(Canvas canvas, ShapeElement element, bool isActive) {
    final start = element.position;
    final end = element.endPoint;
    final rect = Rect.fromPoints(start, end);

    switch (element.shapeType) {
      case ShapeType.rectangle:
        _drawRectangleDimensions(canvas, rect);
        break;
      case ShapeType.circle:
        _drawCircleDimensions(canvas, rect);
        break;
      case ShapeType.triangle:
        _drawTriangleDimensions(canvas, start, end);
        break;
      case ShapeType.line:
        final dx = end.dx - start.dx;
        final dy = end.dy - start.dy;
        final length = Offset(dx, dy).distance;
        final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);

        double angle = atan2(dy, dx);
        if (angle > pi / 2 || angle < -pi / 2) angle += pi;

        _drawText(canvas, mid, length.toStringAsFixed(1), rotate: angle);
        break;
      case ShapeType.arrow:
      case ShapeType.star:
      default:
        break;
    }
  }

  void _drawRectangleDimensions(Canvas canvas, Rect rect) {
    final width = rect.width.abs();
    final height = rect.height.abs();
    final wStr = (width / 10).toStringAsFixed(1);
    final hStr = (height / 10).toStringAsFixed(1);

    _drawText(canvas, Offset(rect.left + rect.width / 2, rect.top - 15), wStr);
    _drawText(canvas, Offset(rect.left + rect.width / 2, rect.bottom + 15), wStr);
    _drawText(canvas, Offset(rect.left - 25, rect.top + rect.height / 2), hStr, rotate: -pi / 2);
    _drawText(canvas, Offset(rect.right + 25, rect.top + rect.height / 2), hStr, rotate: pi / 2);
  }

  void _drawCircleDimensions(Canvas canvas, Rect rect) {
    final center = rect.center;
    final radiusX = rect.width.abs() / 2;
    final radiusY = rect.height.abs() / 2;
    final rStr = (radiusX / 10).toStringAsFixed(1);

    final dashPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final hPath = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(center.dx + radiusX, center.dy);
    _drawDashedPath(canvas, hPath, dashPaint);
    _drawText(canvas, Offset(center.dx + radiusX / 2, center.dy - 10), rStr);

    final vPath = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(center.dx, center.dy + radiusY);
    _drawDashedPath(canvas, vPath, dashPaint);
    _drawText(canvas, Offset(center.dx - 25, center.dy + radiusY / 2), rStr, rotate: -pi / 2);
  }

  void _drawTriangleDimensions(Canvas canvas, Offset start, Offset end) {
    final rect = Rect.fromPoints(start, end);
    final apex = Offset(rect.left + rect.width / 2, rect.top);
    final bottomRight = Offset(rect.right, rect.bottom);
    final bottomLeft = Offset(rect.left, rect.bottom);

    void drawSideLen(Offset p1, Offset p2, bool isBottom) {
      final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
      final dist = (p1 - p2).distance;
      double angle = atan2(p2.dy - p1.dy, p2.dx - p1.dx);

      if (angle > pi / 2 || angle < -pi / 2) {
        angle += pi;
      }

      final normalOffset = isBottom ? 18.0 : 15.0;
      final normal = Offset(-sin(angle), cos(angle)) * normalOffset;

      _drawText(canvas, mid + normal, (dist / 10).toStringAsFixed(1), rotate: angle);
    }

    drawSideLen(bottomLeft, apex, false);
    drawSideLen(apex, bottomRight, false);
    drawSideLen(bottomRight, bottomLeft, true);
  }

  void _drawText(Canvas canvas, Offset position, String text, {double rotate = 0, double fontSize = 12}) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(color: Colors.black, fontSize: fontSize, fontWeight: FontWeight.normal),
    );
    final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
    textPainter.layout();

    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(rotate);
    textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
    canvas.restore();
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(end.dx, end.dy);
    canvas.drawPath(path, paint);
  }

  void _drawTriangle(Canvas canvas, Offset start, Offset end, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    final path = Path()
      ..moveTo(rect.centerLeft.dx + rect.width / 2, rect.top)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawStar(Canvas canvas, Offset start, Offset end, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    final center = rect.center;
    final radius = rect.width / 2;
    final innerRadius = radius / 2.5;
    const points = 5;

    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final angle = (i * pi) / points - pi / 2;
      final r = i.isEven ? radius : innerRadius;
      final x = center.dx + r * cos(angle);
      final y = center.dy + r * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawDiamond(Canvas canvas, Offset start, Offset end, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    final path = Path()
      ..moveTo(rect.center.dx, rect.top)
      ..lineTo(rect.right, rect.center.dy)
      ..lineTo(rect.center.dx, rect.bottom)
      ..lineTo(rect.left, rect.center.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawPolygon(Canvas canvas, Offset start, Offset end, int sides, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    final center = rect.center;
    final radius = min(rect.width.abs(), rect.height.abs()) / 2;
    final path = Path();
    for (var i = 0; i < sides; i++) {
      final angle = (i * 2 * pi) / sides - pi / 2;
      final x = center.dx + radius * cos(angle);
      final y = center.dy + radius * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawRightTriangle(Canvas canvas, Offset start, Offset end, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    final path = Path()
      ..moveTo(rect.left, rect.top)
      ..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.right, rect.bottom)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawParallelogram(Canvas canvas, Offset start, Offset end, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    final offset = rect.width * 0.2;
    final path = Path()
      ..moveTo(rect.left + offset, rect.top)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right - offset, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawTrapezoid(Canvas canvas, Offset start, Offset end, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    final offset = rect.width * 0.25;
    final path = Path()
      ..moveTo(rect.left + offset, rect.top)
      ..lineTo(rect.right - offset, rect.top)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawHeart(Canvas canvas, Offset start, Offset end, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    final width = rect.width;
    final height = rect.height;
    final path = Path()
      ..moveTo(rect.center.dx, rect.top + height * 0.3)
      ..cubicTo(rect.center.dx + width * 0.5, rect.top - height * 0.1, rect.right, rect.top + height * 0.4, rect.center.dx, rect.bottom)
      ..cubicTo(
        rect.left,
        rect.top + height * 0.4,
        rect.center.dx - width * 0.5,
        rect.top - height * 0.1,
        rect.center.dx,
        rect.top + height * 0.3,
      );
    canvas.drawPath(path, paint);
  }

  void _drawCube3D(Canvas canvas, Offset start, Offset end, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    final w = rect.width;
    final h = rect.height;
    final dx = w * 0.3;
    final dy = h * 0.3;

    final front = Rect.fromLTWH(rect.left, rect.top + dy, w - dx, h - dy);
    final back = Rect.fromLTWH(rect.left + dx, rect.top, w - dx, h - dy);

    canvas.drawRect(front, paint);
    canvas.drawRect(back, paint);

    canvas.drawLine(front.topLeft, back.topLeft, paint);
    canvas.drawLine(front.topRight, back.topRight, paint);
    canvas.drawLine(front.bottomLeft, back.bottomLeft, paint);
    canvas.drawLine(front.bottomRight, back.bottomRight, paint);
  }

  void _drawCylinder3D(Canvas canvas, Offset start, Offset end, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    final cx = rect.center.dx;
    final topY = rect.top + rect.height * 0.15;
    final botY = rect.bottom - rect.height * 0.15;
    final rx = rect.width / 2;
    final ry = rect.height * 0.15;

    canvas.drawOval(Rect.fromCenter(center: Offset(cx, topY), width: rx * 2, height: ry * 2), paint);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, botY), width: rx * 2, height: ry * 2), paint);

    canvas.drawLine(Offset(cx - rx, topY), Offset(cx - rx, botY), paint);
    canvas.drawLine(Offset(cx + rx, topY), Offset(cx + rx, botY), paint);
  }

  void _drawCone3D(Canvas canvas, Offset start, Offset end, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    final cx = rect.center.dx;
    final apex = Offset(cx, rect.top);
    final botY = rect.bottom;
    final rx = rect.width / 2;
    final ry = rect.height * 0.15;

    canvas.drawOval(Rect.fromCenter(center: Offset(cx, botY), width: rx * 2, height: ry * 2), paint);
    canvas.drawLine(apex, Offset(cx - rx, botY), paint);
    canvas.drawLine(apex, Offset(cx + rx, botY), paint);
  }

  void _drawPyramid3D(Canvas canvas, Offset start, Offset end, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    final apex = Offset(rect.center.dx, rect.top);
    final tl = rect.topLeft + Offset(0, rect.height * 0.3);
    final tr = rect.topRight + Offset(0, rect.height * 0.3);
    final bl = rect.bottomLeft;
    final br = rect.bottomRight;

    final path = Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(bl.dx, bl.dy)
      ..close();
    canvas.drawPath(path, paint);

    canvas.drawLine(tl, apex, paint);
    canvas.drawLine(tr, apex, paint);
    canvas.drawLine(bl, apex, paint);
    canvas.drawLine(br, apex, paint);
  }

  void _drawSphere3D(Canvas canvas, Offset start, Offset end, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    canvas.drawOval(rect, paint);
    final center = rect.center;
    final rx = rect.width / 2;
    final ry = rect.height / 2;

    canvas.drawArc(Rect.fromCenter(center: center, width: rx, height: ry * 2), 0, pi, false, paint);
    canvas.drawArc(Rect.fromCenter(center: center, width: rx * 2, height: ry), pi / 2, pi, false, paint);
  }
}
