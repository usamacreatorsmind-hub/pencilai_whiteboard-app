import 'dart:io';
import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../widgets/pptx_viewer.dart';
import '../models/board_element.dart';
import '../models/document_element.dart';
import '../models/image_element.dart';
import '../models/mind_map_element.dart';
import '../models/shape_element.dart';
import '../models/stroke_element.dart';
import '../state/whiteboard_provider.dart';
import 'canvas/canvas_pointer_manager.dart';
import 'canvas/whiteboard_painter.dart';
export 'canvas/whiteboard_painter.dart';

/// Main interactive whiteboard canvas widget handling touch events, drawing tools
/// element selection, and overlay layers.
class WhiteboardCanvas extends StatefulWidget {
  const WhiteboardCanvas({super.key});

  @override
  State<WhiteboardCanvas> createState() => _WhiteboardCanvasState();
}

class _WhiteboardCanvasState extends State<WhiteboardCanvas> {
  final CanvasPointerManager _pointerManager = CanvasPointerManager();

  // Per-stroke nib detection state (pointerId -> tracker)
  final Map<int, _NibTrack> _nibTracks = {};
  static const int _kNibDecideMs = 150; // initial voting window
  static const int _kNibThickStreak =
      3; // consecutive thick readings to upgrade later

  // displayElements memoization
  Iterable<BoardElement>? _displaySource;
  List<BoardElement> _displayCache = const [];
  int _displayCacheVersion = -1;
  bool _displayCacheOverlay = false;
  int _displayCachePage = -1;
  int _displayCacheLen = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _pointerManager.init(context);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pointerManager.updateDependencies(context);
  }

  @override
  void dispose() {
    _pointerManager.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // MindMap Helpers
  // -------------------------------------------------------------------------

  Iterable<MindMapElement> _visibleMindMaps(WhiteboardProvider provider) sync* {
    final page = provider.isDocumentOverlayOpen
        ? provider.overlayCurrentPage
        : null;
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
      final r =
          Offset(d.dx * cosA - d.dy * sinA, d.dx * sinA + d.dy * cosA) /
          el.scale;
      q = c + r;
    }
    return q - el.position;
  }

  ({MindMapElement el, MindMapNode node})? _mindMapNodeAt(
    Offset p,
    WhiteboardProvider provider, {
    double inflate = 0,
  }) {
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

  // -------------------------------------------------------------------------
  // Pointer handlers
  // -------------------------------------------------------------------------

  void _onPointerDown(PointerDownEvent event, WhiteboardProvider provider) {
    _pointerManager.cancelGestureEraserReset();
    _pointerManager.cancelToolEraserReset();
    _pointerManager.startWatchdog(() => mounted);
    _pointerManager.pruneStalePointers(force: true);
    _pointerManager.lastSeen[event.pointer] = DateTime.now();
    _pointerManager.pointerDownTimes[event.pointer] = DateTime.now();
    _pointerManager.pointers[event.pointer] = event;

    if (CanvasPointerManager.kDebugPointerInfo) {
      debugPrint(
        'DOWN: kind=${event.kind} dev=${event.device} id=${event.pointer} '
        'rMajor=${event.radiusMajor.toStringAsFixed(1)} rMinor=${event.radiusMinor.toStringAsFixed(1)} '
        'size=${event.size.toStringAsFixed(4)} press=${event.pressure.toStringAsFixed(2)} '
        'active=${_pointerManager.pointers.length}',
      );
    }
    final localPos = _pointerManager.getCanvasLocalPos(event, context);
    final pointerId = event.pointer;
    _pointerManager.smoothedDeltas[pointerId] = Offset.zero;

    if (provider.currentTool == WhiteboardTool.preview) {
      _pointerManager.panPointerId ??= pointerId;
      return;
    }

    if (provider.activeSmartPenStroke != null) {
      provider.clearActiveSmartPenStroke();
    }

    if (!_pointerManager.isPalm(event) &&
        _handleMindMapButtons(localPos, provider)) {
      _pointerManager.requestRepaint(mounted);
      return;
    }

    if (provider.currentTool == WhiteboardTool.eraser) {
      _pointerManager.handleToolEraserDown(
        pointerId,
        localPos,
        provider,
        context,
        mounted,
      );
      return;
    }

    if (_pointerManager.isEraserMode(event, context)) {
      if (!_pointerManager.isUsingGestureEraser) {
        _pointerManager.switchToEraserMode(
          localPos,
          provider,
          context,
          mounted,
        );
      } else {
        final centroid = _pointerManager.gestureEraseCentroid(
          localPos,
          context,
        );
        _pointerManager.handleGestureEraseMove(
          centroid,
          provider,
          context,
          mounted,
        );
      }
      return;
    }

    if (provider.currentTool == WhiteboardTool.select) {
      if (_pointerManager.activeElements.isEmpty) {
        final hit = provider.hitTest(localPos);
        if (hit != null) {
          if (hit is MindMapElement) {
            final n = hit.nodeAt(_mmLocal(hit, localPos));
            if (n != null && hit.selectedNodeId != n.id) {
              hit.selectedNodeId = n.id;
              provider.refreshBoard();
            }
          }
          provider.selectElement(
            hit.id,
            multi: provider.selectedElementIds.contains(hit.id),
          );
        } else {
          _pointerManager.currentLasso = Path()
            ..moveTo(localPos.dx, localPos.dy);
          provider.clearSelection();
          _pointerManager.requestRepaint(mounted);
        }
      }
      return;
    }

    final id = const Uuid().v4();
    final docPage = provider.isDocumentOverlayOpen
        ? provider.overlayCurrentPage
        : null;
    if (provider.currentTool == WhiteboardTool.pen) {
      _nibTracks[pointerId] = _NibTrack();
      _detectNib(event, provider);

      final startHit = _mindMapNodeAt(localPos, provider, inflate: 6);
      if (startHit != null) {
        _pointerManager.mmStrokeTargets[pointerId] = (
          mmId: startHit.el.id,
          nodeId: startHit.node.id,
        );
        if (startHit.el.selectedNodeId != startHit.node.id) {
          startHit.el.selectedNodeId = startHit.node.id;
          provider.refreshBoard();
        }
      }

      _pointerManager.activeElements[pointerId] = StrokeElement(
        id: id,
        position: localPos,
        points: [localPos],
        color: provider.currentColor,
        strokeWidth: provider.strokeWidth,
        penType: provider.currentPenType,
        docPage: docPage,
      );
    } else if (provider.currentTool == WhiteboardTool.shape) {
      _pointerManager.activeElements[pointerId] = ShapeElement(
        id: id,
        position: localPos,
        shapeType: provider.currentShapeType,
        endPoint: localPos,
        color: provider.currentColor,
        strokeWidth: provider.strokeWidth,
        docPage: docPage,
      );
    }
    _pointerManager.requestRepaint(mounted);
  }

  /// Contact radius — same formula as the original calibration (1.5 threshold).
  double _nibRadiusOf(PointerEvent event) {
    double r = event.radiusMajor;
    if (event.radiusMinor > 0 && event.radiusMajor > 0) {
      r = (event.radiusMajor + event.radiusMinor) / 2.0;
    }
    if (r <= 0 && event.size > 0) {
      r = event.size * 100.0;
    }
    return r;
  }

  /// Robust real-time per-stroke nib detection.
  ///
  /// * radius 0 frames (tip not settled yet) are ignored, never forced to thin.
  /// * During the first [_kNibDecideMs] the profile is decided by voting:
  ///   thick if >= 2 readings (or the only reading) are above threshold.
  ///   A single noisy spike can't flip it, and a thick nib is caught fast.
  /// * After the window, the stroke can still be UPGRADED to thick if
  ///   [_kNibThickStreak] consecutive thick readings arrive (late settle /
  ///   pressed harder). It is never downgraded mid-stroke (prevents flicker).
  /// * Large radii (thick nib pressed hard) count as thick, up to palm size.
  /// Returns true if the active profile changed.
  bool _detectNib(PointerEvent event, WhiteboardProvider provider) {
    if (!provider.isAutoNibDetectionEnabled) return false;
    final t = _nibTracks[event.pointer];
    if (t == null) return false;

    if (event.kind == PointerDeviceKind.invertedStylus) {
      return provider.applyDetectedNib(PenProfile.thick, 0);
    }

    final r = _nibRadiusOf(event);
    if (r <= 0 || r >= CanvasPointerManager.kBackhandRadiusMin) return false;

    final thr = provider.nibRadiusThreshold;
    final isThick = r > thr;
    t.valid++;
    if (isThick) {
      t.thickCount++;
    }
    // Late-upgrade streak only counts clearly-thick readings (margin above threshold)
    if (r > thr + 0.25) {
      t.thickStreak++;
    } else {
      t.thickStreak = 0;
    }

    final downTime = _pointerManager.pointerDownTimes[event.pointer];
    final elapsed = downTime == null
        ? 0
        : DateTime.now().difference(downTime).inMilliseconds;

    // Early lock: if 3 valid readings are all thin, lock thin immediately without waiting 150ms.
    if (!t.locked &&
        (elapsed > _kNibDecideMs || (t.valid >= 3 && t.thickCount == 0))) {
      t.locked = true;
    }

    PenProfile? target;
    if (!t.locked) {
      final needed = t.valid == 1 ? 1 : 2;
      target = t.thickCount >= needed ? PenProfile.thick : PenProfile.thin;
    } else if (provider.activePenProfile == PenProfile.thin &&
        t.thickStreak >= _kNibThickStreak) {
      target = PenProfile.thick; // late upgrade
    }
    if (target == null || target == provider.activePenProfile) return false;
    return provider.applyDetectedNib(target, r);
  }

  void _forgetNib(int pid) => _nibTracks.remove(pid);

  void _onPointerMove(PointerMoveEvent event, WhiteboardProvider provider) {
    _pointerManager.pointers[event.pointer] = event;
    _pointerManager.lastSeen[event.pointer] = DateTime.now();
    _processSinglePointerMove(event, provider);
  }

  void _processSinglePointerMove(
    PointerMoveEvent event,
    WhiteboardProvider provider,
  ) {
    _pointerManager.pruneStalePointers();
    final pointerId = event.pointer;
    final localPos = _pointerManager.getCanvasLocalPos(event, context);

    if (provider.currentTool == WhiteboardTool.preview) {
      if (event.pointer == _pointerManager.panPointerId) {
        provider.panCanvas(event.delta);
      }
      _pointerManager.requestRepaint(mounted);
      return;
    }

    if (CanvasPointerManager.kDebugPointerInfo &&
        DateTime.now()
                .difference(_pointerManager.lastMoveLogTime)
                .inMilliseconds >
            100) {
      debugPrint(
        'MOVE: pointers=${_pointerManager.pointers.length} fresh=${_pointerManager.freshTouchPointers().length} eraserMode=${_pointerManager.isUsingGestureEraser}',
      );
      _pointerManager.lastMoveLogTime = DateTime.now();
    }

    if (provider.currentTool == WhiteboardTool.eraser ||
        _pointerManager.toolEraserPointerIds.contains(pointerId)) {
      _pointerManager.handleToolEraserMove(
        pointerId,
        localPos,
        provider,
        context,
        mounted,
      );
      return;
    }

    if (_pointerManager.isEraserMode(event, context)) {
      if (!_pointerManager.isUsingGestureEraser) {
        _pointerManager.switchToEraserMode(
          localPos,
          provider,
          context,
          mounted,
        );
        return;
      }
      final centroid = _pointerManager.gestureEraseCentroid(localPos, context);
      _pointerManager.handleGestureEraseMove(
        centroid,
        provider,
        context,
        mounted,
      );
      return;
    }

    if (provider.currentTool == WhiteboardTool.pen) {
      final profileChanged = _detectNib(event, provider);

      // Nib detected/changed while the tip was settling -> restyle the live stroke
      // so it draws with the correct nib's colour & size from the first point.
      final active = _pointerManager.activeElements[pointerId];
      if (profileChanged && active is StrokeElement) {
        active.updateStyling(
          newColor: provider.currentColor,
          newStrokeWidth: provider.strokeWidth,
          newPenType: provider.currentPenType,
        );
        _pointerManager.requestRepaint(mounted);
      }
    }

    if (provider.currentTool == WhiteboardTool.select &&
        _pointerManager.currentLasso != null) {
      _pointerManager.currentLasso!.lineTo(localPos.dx, localPos.dy);
      provider.setLassoPath(_pointerManager.currentLasso);
      _pointerManager.requestRepaint(mounted);
      return;
    }

    final active = _pointerManager.activeElements[pointerId];
    if (active == null) return;

    if (active is StrokeElement) {
      if (active.addPoint(localPos)) {
        active.predictedTip = null;
        _pointerManager.requestRepaint(mounted);
      }
    } else if (active is ShapeElement) {
      _pointerManager.activeElements[pointerId] = active.copyWith(
        endPoint: localPos,
      )..invalidateBounds();
      _pointerManager.requestRepaint(mounted);
    }
  }

  void _onPointerUp(PointerUpEvent event, WhiteboardProvider provider) {
    _pointerManager.pruneStalePointers(force: true);
    if (CanvasPointerManager.kDebugPointerInfo) {
      debugPrint(
        'UP: id=${event.pointer} remaining=${_pointerManager.pointers.length - 1}',
      );
    }
    final pointerId = event.pointer;

    if (_pointerManager.isUsingGestureEraser) {
      _pointerManager.flushPendingErase(provider);
      _pointerManager.scheduleGestureEraserReset();
    }

    if (provider.currentTool == WhiteboardTool.eraser ||
        _pointerManager.toolEraserPointerIds.contains(pointerId)) {
      _pointerManager.handleToolEraserUp(pointerId, provider, mounted);
    }

    final bool wasGestureEraser = _pointerManager.isUsingGestureEraser;
    final mmTarget = _pointerManager.mmStrokeTargets[pointerId];
    final element = _pointerManager.activeElements.remove(pointerId);
    _pointerManager.forgetPointer(pointerId);
    _forgetNib(pointerId);

    if (!_pointerManager.hasTouchDown() ||
        _pointerManager.freshTouchPointers().isEmpty) {
      _pointerManager.scheduleGestureEraserReset();
      _pointerManager.scheduleToolEraserReset();
    }
    if (_pointerManager.pointers.isEmpty) {
      _pointerManager.resetToolEraser();
    }

    if (provider.currentTool == WhiteboardTool.select) {
      if (_pointerManager.currentLasso != null) {
        final lasso = _pointerManager.currentLasso!;
        lasso.close();
        provider.completeLassoSelection(lasso);
        _pointerManager.currentLasso = null;
      }
      _pointerManager.requestRepaint(mounted);
      return;
    }

    final downTime = _pointerManager.pointerDownTimes[pointerId];
    final durationMs = downTime != null
        ? DateTime.now().difference(downTime).inMilliseconds
        : 999;
    final bool isQuickPalm =
        durationMs < CanvasPointerManager.kPalmCancelTimeWindowMs &&
        _pointerManager.isPalm(event);
    final bool dropElement =
        wasGestureEraser ||
        _pointerManager.isUsingGestureEraser ||
        (isQuickPalm &&
            (element is! StrokeElement || element.points.length <= 2));
    if (element != null && !dropElement) {
      if (element is StrokeElement && element.points.length > 1) {
        element.invalidatePath();

        if (mmTarget != null) {
          final mm = _findMindMapById(provider, mmTarget.mmId);
          final node = mm?.root.findNode(mmTarget.nodeId);
          if (mm != null && node != null) {
            mm.addStroke(
              node.id,
              element.points.map((p) => _mmLocal(mm, p)).toList(),
              color: element.color,
            );
            mm.selectedNodeId = node.id;
            element.disposeLive();
            provider.refreshBoard();
            _pointerManager.requestRepaint(mounted);
            return;
          }
        }

        provider.addElement(element);
        WhiteboardPainter.appendElementToCache(element, provider.boardVersion);

        if (element.penType == PenType.smartPen && !element.isDotOrTap) {
          provider.setActiveSmartPenStroke(element);
        }
      } else if (element is ShapeElement) {
        if ((element.position - element.endPoint).distance > 5) {
          provider.addElement(element);
          WhiteboardPainter.appendElementToCache(
            element,
            provider.boardVersion,
          );
        }
      } else if (element is StrokeElement) {
        element.disposeLive();
      }
    } else if (element is StrokeElement) {
      element.disposeLive();
    }
    _pointerManager.requestRepaint(mounted);
  }

  void _onPointerCancel(PointerCancelEvent event, WhiteboardProvider provider) {
    _pointerManager.pruneStalePointers(force: true);
    _pointerManager.cancelEventCount++;
    final pointerId = event.pointer;
    _forgetNib(pointerId);
    final localPos = _pointerManager.getCanvasLocalPos(event, context);

    final downTime = _pointerManager.pointerDownTimes[pointerId];
    final durationMs = downTime != null
        ? DateTime.now().difference(downTime).inMilliseconds
        : 999;
    final hint = _pointerManager.nativeTouchHints[pointerId];

    final bool isPalmCancel =
        durationMs < CanvasPointerManager.kPalmCancelTimeWindowMs &&
        (hint != null && (hint['isCanceled'] == true || hint['toolType'] == 5));

    _pointerManager.lastCancelInfo =
        'id=$pointerId dur=${durationMs}ms palm=$isPalmCancel';
    if (CanvasPointerManager.kDebugPointerInfo) {
      debugPrint(
        'CANCEL: ${_pointerManager.lastCancelInfo} totalCount=${_pointerManager.cancelEventCount}',
      );
    }

    if (_pointerManager.isUsingGestureEraser) {
      _pointerManager.flushPendingErase(provider);
    }

    if (provider.currentTool == WhiteboardTool.eraser ||
        _pointerManager.toolEraserPointerIds.contains(pointerId)) {
      _pointerManager.handleToolEraserUp(pointerId, provider, mounted);
    }

    if (isPalmCancel) {
      provider.partialErase(
        localPos,
        _pointerManager.gestureEraseRadius(provider),
        lastPos: localPos,
      );
    }

    _pointerManager.forgetPointer(pointerId);

    if (provider.currentTool == WhiteboardTool.select &&
        _pointerManager.currentLasso != null) {
      _pointerManager.currentLasso = null;
      provider.setLassoPath(null);
    }

    if (_pointerManager.isUsingGestureEraser ||
        !_pointerManager.hasTouchDown() ||
        _pointerManager.freshTouchPointers().isEmpty) {
      _pointerManager.scheduleGestureEraserReset();
      _pointerManager.scheduleToolEraserReset();
    }
    if (_pointerManager.pointers.isEmpty) {
      _pointerManager.resetToolEraser();
    }
    _pointerManager.requestRepaint(mounted);
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  List<BoardElement> _displayElementsFor(
    Iterable<BoardElement> elements,
    int version,
    bool overlay,
    int page,
  ) {
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
    _displayCache = overlay
        ? elements.where((e) => e.docPage == page).toList()
        : elements.where((e) => e.docPage == null).toList();
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
    return RepaintBoundary(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(
            color: const Color(0xFF2563EB),
            width: borderWidth,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 12,
              spreadRadius: 2,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Icon(
            LucideIcons.eraser,
            color: const Color(0xFF2563EB),
            size: (diameter * iconFactor).clamp(minIcon, maxIcon),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Selector<
      WhiteboardProvider,
      (int, Set<String>, Path?, WhiteboardTool, bool, int, Offset)
    >(
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

        final displayElements = _displayElementsFor(
          elements,
          data.$1,
          isOverlayOpen,
          overlayCurrentPage,
        );
        final shouldIgnoreTouches =
            isOverlayOpen && currentTool == WhiteboardTool.select;

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
                          ...displayElements.whereType<ImageElement>().map((
                            img,
                          ) {
                            final rawRect = img.getRawBounds();
                            final visualRect = Rect.fromCenter(
                              center: rawRect.center,
                              width: rawRect.width * img.scale,
                              height: rawRect.height * img.scale,
                            );
                            final bool isPlain =
                                img.isTransparent ||
                                img.imageUrl.contains('smart_obj');
                            final imageWidget = img.imageUrl.startsWith('http')
                                ? Image.network(
                                    img.imageUrl,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.high,
                                    errorBuilder: (c, e, s) => const Icon(
                                      Icons.broken_image,
                                      size: 50,
                                    ),
                                  )
                                : Image.file(
                                    File(img.imageUrl),
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.high,
                                    errorBuilder: (c, e, s) => const Icon(
                                      Icons.broken_image,
                                      size: 50,
                                    ),
                                  );

                            return Positioned(
                              left: visualRect.left,
                              top: visualRect.top,
                              width: visualRect.width,
                              height: visualRect.height,
                              child: Transform.rotate(
                                angle: img.rotation,
                                child: isPlain
                                    ? imageWidget
                                    : Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.25,
                                              ),
                                              blurRadius: 12,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          child: imageWidget,
                                        ),
                                      ),
                              ),
                            );
                          }),
                          ...displayElements.whereType<DocumentElement>().map((
                            doc,
                          ) {
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
                              content = PptxViewer(
                                file: File(doc.filePath),
                                size: visualRect.size,
                                slideIndex: doc.docPage ?? 0,
                              );
                            } else {
                              content = Container(
                                color: Colors.white,
                                padding: const EdgeInsets.all(12),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.description,
                                        size: 48,
                                        color: Colors.blueAccent,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        doc.fileName,
                                        style: const TextStyle(
                                          color: Colors.black87,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
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
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: content,
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
                // Live active strokes layer
                RepaintBoundary(
                  child: ValueListenableBuilder<int>(
                    valueListenable: _pointerManager.activeLayerPulse,
                    builder: (context, _, _) {
                      return CustomPaint(
                        isComplex: false,
                        willChange: true,
                        painter: WhiteboardPainter(
                          elements: const [],
                          activeElements: _pointerManager.activeElements.values
                              .toList(),
                          lassoPath: lassoPath ?? _pointerManager.currentLasso,
                          selectedIds: const {},
                          panOffset: panOffset,
                        ),
                        size: Size.infinite,
                      );
                    },
                  ),
                ),
                // Eraser circle overlay
                Positioned.fill(
                  child: IgnorePointer(
                    child: ValueListenableBuilder<int>(
                      valueListenable: _pointerManager.activeLayerPulse,
                      builder: (context, _, _) {
                        if (_pointerManager.isEraserCircleVisible) {
                          final center = _pointerManager.gestureCenter;
                          if (center == null) return const SizedBox.shrink();
                          final r = _pointerManager.gestureEraseRadius(
                            provider,
                          );
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                left: center.dx + panOffset.dx - r,
                                top: center.dy + panOffset.dy - r,
                                child: _eraserCircle(
                                  radius: r,
                                  borderWidth: 2.2,
                                  minIcon: 24,
                                  maxIcon: 48,
                                  iconFactor: 0.45,
                                ),
                              ),
                            ],
                          );
                        }

                        if (provider.currentTool == WhiteboardTool.eraser &&
                            _pointerManager.isToolEraserCircleVisible) {
                          final center = _pointerManager.toolEraserCenter;
                          if (center == null) return const SizedBox.shrink();
                          final double radius = provider.eraserSize;
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                left: center.dx + panOffset.dx - radius,
                                top: center.dy + panOffset.dy - radius,
                                child: _eraserCircle(
                                  radius: radius,
                                  borderWidth: 1.8,
                                  minIcon: 12,
                                  maxIcon: 32,
                                  iconFactor: 0.42,
                                ),
                              ),
                            ],
                          );
                        }

                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                if (CanvasPointerManager.kDebugPointerInfo)
                  ValueListenableBuilder<int>(
                    valueListenable: _pointerManager.activeLayerPulse,
                    builder: (context, _, _) => _buildDebugPointerOverlay(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDebugPointerOverlay() {
    if (!CanvasPointerManager.kDebugPointerInfo) return const SizedBox.shrink();

    final mq = MediaQuery.of(context);
    final pxMm = _pointerManager.pxPerMm;
    final freshPointers = _pointerManager.freshTouchPointers();
    final msSincePalm = _pointerManager.lastPalmSeen != null
        ? DateTime.now()
              .difference(_pointerManager.lastPalmSeen!)
              .inMilliseconds
        : -1;

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
            border: Border.all(
              color: Colors.cyanAccent.withValues(alpha: 0.7),
              width: 1.5,
            ),
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
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.white24, height: 10),
              Text(
                'Screen: ${mq.size.width.toStringAsFixed(0)}x${mq.size.height.toStringAsFixed(0)} | DPR: ${mq.devicePixelRatio.toStringAsFixed(1)} | px/mm: ${pxMm.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
              Text(
                'Fresh: ${freshPointers.length} | Raw: ${_pointerManager.pointers.length} | GhostPruned: ${_pointerManager.prunedGhostCount} | NativeCnt: ${_pointerManager.nativePointerCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'EraserMode: ${_pointerManager.isUsingGestureEraser} | MsSincePalm: ${msSincePalm >= 0 ? "${msSincePalm}ms" : "none"}',
                style: const TextStyle(
                  color: Colors.lightGreenAccent,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Cancels: ${_pointerManager.cancelEventCount} | Last: ${_pointerManager.lastCancelInfo}',
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 6),
              ...freshPointers.map((p) {
                final isP = _pointerManager.isPalm(p);
                final hint = _pointerManager.nativeTouchHints[p.pointer];
                final nativeStr = hint != null
                    ? 'Native: tool=${hint['toolType']} cnl=${hint['isCanceled']}'
                    : 'Native: --';
                final bool isB =
                    max(p.radiusMajor, p.radiusMinor) >=
                        CanvasPointerManager.kBackhandRadiusMin ||
                    p.size >= CanvasPointerManager.kBackhandSizeMin;
                final String reason = isP
                    ? (max(p.radiusMajor, p.radiusMinor) >=
                              CanvasPointerManager.kPalmRadiusMajorMin
                          ? "Palm"
                          : (isB ? "Backhand" : "Size"))
                    : "Finger";
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '#${p.pointer} | ${p.kind.name} | R:${max(p.radiusMajor, p.radiusMinor).toStringAsFixed(1)} | Sz:${p.size.toStringAsFixed(4)} | Palm:$isP ($reason)\n $nativeStr',
                    style: TextStyle(
                      color: isP
                          ? Colors.yellowAccent
                          : Colors.lightGreenAccent,
                      fontSize: 9,
                      fontFamily: 'monospace',
                    ),
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

/// Per-stroke nib detection tracker.
class _NibTrack {
  int valid = 0; // readings with a usable radius
  int thickCount = 0; // readings above threshold
  int thickStreak = 0; // consecutive clearly-thick readings
  bool locked = false; // initial voting window finished
}
