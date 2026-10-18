import 'dart:math';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/board_element.dart';
import '../models/board_page.dart';
import '../models/stroke_element.dart';
import '../models/shape_element.dart';
import '../models/image_element.dart';
import '../models/document_element.dart';
import '../models/text_element.dart';
import '../models/table_element.dart';
import '../models/mind_map_element.dart';
import '../services/ai_service.dart';
import '../services/board_storage_service.dart';
import '../widgets/whiteboard_canvas.dart';

enum WhiteboardTool { pen, eraser, shape, image, select, preview }

enum PenProfile { thin, thick }

abstract class Command {
  void execute(WhiteboardProvider provider);
  void undo(WhiteboardProvider provider);
}

class AddElementCommand extends Command {
  final BoardElement element;
  final int pageIndex;
  AddElementCommand(this.element, this.pageIndex);

  @override
  void execute(WhiteboardProvider provider) {
    provider.pages[pageIndex].elements.add(element);
  }

  @override
  void undo(WhiteboardProvider provider) {
    provider.pages[pageIndex].elements.removeWhere((e) => e.id == element.id);
  }
}

class RemoveElementsCommand extends Command {
  final List<BoardElement> elements;
  final int pageIndex;
  RemoveElementsCommand(this.elements, this.pageIndex);

  @override
  void execute(WhiteboardProvider provider) {
    final ids = elements.map((e) => e.id).toSet();
    provider.pages[pageIndex].elements.removeWhere((e) => ids.contains(e.id));
  }

  @override
  void undo(WhiteboardProvider provider) {
    provider.pages[pageIndex].elements.addAll(elements);
  }
}

enum HandleDirection { topLeft, topCenter, topRight, middleRight, bottomRight, bottomCenter, bottomLeft, middleLeft }

class MultiTransformCommand extends Command {
  final int pageIndex;
  final List<TransformData> transforms;

  MultiTransformCommand({required this.pageIndex, required this.transforms});

  @override
  void execute(WhiteboardProvider provider) {
    for (var data in transforms) {
      final element = provider.pages[pageIndex].elements.firstWhere((e) => e.id == data.id);
      element.position = data.newPos;
      element.rotation = data.newRot;
      element.scale = data.newScale;
      if (data.newSize != null) {
        if (element is ImageElement) element.size = data.newSize!;
        if (element is DocumentElement) element.size = data.newSize!;
      }
      _updateInternalPoints(element, data.newPos - data.oldPos);
      element.invalidateBounds();
      element.invalidatePath(); // Sync selection box and path
    }
  }

  @override
  void undo(WhiteboardProvider provider) {
    for (var data in transforms) {
      final element = provider.pages[pageIndex].elements.firstWhere((e) => e.id == data.id);
      element.position = data.oldPos;
      element.rotation = data.oldRot;
      element.scale = data.oldScale;
      if (data.oldSize != null) {
        if (element is ImageElement) element.size = data.oldSize!;
        if (element is DocumentElement) element.size = data.oldSize!;
      }
      _updateInternalPoints(element, data.oldPos - data.newPos);
      element.invalidateBounds();
      element.invalidatePath(); // Sync selection box and path
    }
  }

  void _updateInternalPoints(BoardElement element, Offset delta) {
    if (element is StrokeElement) {
      for (int i = 0; i < element.points.length; i++) {
        element.points[i] += delta;
      }
    } else if (element is ShapeElement) {
      element.endPoint += delta;
    }
  }
}

class TransformData {
  final String id;
  final Offset oldPos, newPos;
  final double oldRot, newRot;
  final double oldScale, newScale;
  final Size? oldSize, newSize;
  TransformData({
    required this.id,
    required this.oldPos,
    required this.newPos,
    required this.oldRot,
    required this.newRot,
    required this.oldScale,
    required this.newScale,
    this.oldSize,
    this.newSize,
  });
}

class ClearPageCommand extends Command {
  final List<BoardElement> removedElements;
  final int pageIndex;
  ClearPageCommand(this.removedElements, this.pageIndex);

  @override
  void execute(WhiteboardProvider provider) {
    provider.pages[pageIndex].elements.clear();
  }

  @override
  void undo(WhiteboardProvider provider) {
    provider.pages[pageIndex].elements.addAll(removedElements);
  }
}

class WhiteboardProvider extends ChangeNotifier {
  final List<BoardPage> _pages = [BoardPage(id: const Uuid().v4(), elements: [])];
  int _currentPageIndex = 0;
  int _boardVersion = 0;

  WhiteboardTool _currentTool = WhiteboardTool.pen;
  PenProfile _activePenProfile = PenProfile.thin;

  // Thin Pen Profile Settings
  Color _thinColor = Colors.black;
  PenType _thinPenType = PenType.pen;
  final Map<PenType, double> _thinPenStrokeWidths = {PenType.pen: 2.0, PenType.fountainPen: 2.0, PenType.brush: 2.0, PenType.marker: 2.0};

  // Thick Pen Profile Settings
  Color _thickColor = Colors.blue;
  PenType _thickPenType = PenType.pen;
  final Map<PenType, double> _thickPenStrokeWidths = {PenType.pen: 3.0, PenType.fountainPen: 3.0, PenType.brush: 3.0, PenType.marker: 3.0};

  double _nibRadiusThreshold = 1.5;
  double _lastDetectedRadius = 0.0;

  double _eraserSize = 60.0;
  ShapeType _currentShapeType = ShapeType.rectangle;

  final Set<String> _selectedElementIds = {};
  Path? _lassoPath;

  final List<Command> _undoStack = [];
  final List<Command> _redoStack = [];

  // Getters
  List<BoardPage> get pages => _pages;
  int get currentPageIndex => _currentPageIndex;
  BoardPage get currentPage => _pages[_currentPageIndex];
  int get boardVersion => _boardVersion;
  WhiteboardTool get currentTool => _currentTool;

  PenProfile get activePenProfile => _activePenProfile;
  Color get thinColor => _thinColor;
  Color get thickColor => _thickColor;
  PenType get thinPenType => _thinPenType;
  PenType get thickPenType => _thickPenType;
  double get thinStrokeWidth => _thinPenStrokeWidths[_thinPenType] ?? 2.0;
  double get thickStrokeWidth => _thickPenStrokeWidths[_thickPenType] ?? 6.0;

  Color get currentColor => _activePenProfile == PenProfile.thin ? _thinColor : _thickColor;
  PenType get currentPenType => _activePenProfile == PenProfile.thin ? _thinPenType : _thickPenType;

  double get strokeWidth {
    final map = _activePenProfile == PenProfile.thin ? _thinPenStrokeWidths : _thickPenStrokeWidths;
    return map[currentPenType] ?? (_activePenProfile == PenProfile.thin ? 2.0 : 6.0);
  }

  double get eraserSize => _eraserSize;
  double get minEraserSize => 10.0;
  double get maxEraserSize => 60.0;

  double get minStrokeWidth {
    switch (currentPenType) {
      case PenType.marker:
        return 1.5;
      case PenType.pen:
      case PenType.fountainPen:
      case PenType.brush:
        return 1.0;
    }
  }

  double get maxStrokeWidth {
    switch (currentPenType) {
      case PenType.pen:
      case PenType.fountainPen:
        return _activePenProfile == PenProfile.thin ? 8.0 : 18.0;
      case PenType.brush:
        return _activePenProfile == PenProfile.thin ? 10.0 : 22.0;
      case PenType.marker:
        return _activePenProfile == PenProfile.thin ? 12.0 : 28.0;
    }
  }

  double get nibRadiusThreshold => _nibRadiusThreshold;
  double get lastDetectedRadius => _lastDetectedRadius;

  ShapeType get currentShapeType => _currentShapeType;
  Set<String> get selectedElementIds => _selectedElementIds;
  Path? get lassoPath => _lassoPath;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  DocumentElement? _activeOverlayDocument;
  bool _isDocumentOverlayOpen = false;
  bool _isDocumentOverlayMinimized = false;
  int _overlayCurrentPage = 1;
  int _overlayTotalPages = 1;
  Offset _overlayPosition = const Offset(150, 100);
  Size _overlaySize = const Size(480, 550);

  DocumentElement? get activeOverlayDocument => _activeOverlayDocument;
  bool get isDocumentOverlayOpen => _isDocumentOverlayOpen;
  bool get isDocumentOverlayMinimized => _isDocumentOverlayMinimized;
  int get overlayCurrentPage => _overlayCurrentPage;
  int get overlayTotalPages => _overlayTotalPages;
  Offset get overlayPosition => _overlayPosition;
  Size get overlaySize => _overlaySize;

  Color _canvasBackgroundColor = Colors.white;
  Color get canvasBackgroundColor => _canvasBackgroundColor;

  void setCanvasBackgroundColor(Color color) {
    _canvasBackgroundColor = color;
    _notify();
  }

  Offset _canvasPanOffset = Offset.zero;
  Offset get canvasPanOffset => _canvasPanOffset;



  // Screen (viewport) coords -> canvas (element) coords
  Offset screenToCanvas(Offset p) => p - _canvasPanOffset;

  /// Canvas coords -> screen coords
  Offset canvasToScreen(Offset p) => p + _canvasPanOffset;

  /// Screen ke center ka canvas coordinate. Naya element yahan insert karo.
  Offset viewportCenterOnCanvas(Size viewport) =>
      screenToCanvas(Offset(viewport.width / 2, viewport.height / 2));

  void panCanvas(Offset delta) {
    _canvasPanOffset += delta;
    notifyListeners(); // _notify() nahi: cache invalidate mat karo
  }

  void resetCanvasPan() {
    _canvasPanOffset = Offset.zero;
    _boardVersion++;
    _notify();
  }

  void openDocumentOverlay(DocumentElement doc) {
    _activeOverlayDocument = doc;
    _isDocumentOverlayOpen = true;
    _isDocumentOverlayMinimized = false;
    _overlayCurrentPage = 1;
    _overlayTotalPages = 10;
    _currentTool = WhiteboardTool.select;
    _notify();
  }

  void updateOverlayPageInfo(int page, int totalPages) {
    bool changed = false;
    if (page > 0 && _overlayCurrentPage != page) {
      _overlayCurrentPage = page;
      changed = true;
    }
    if (totalPages > 0 && _overlayTotalPages != totalPages) {
      _overlayTotalPages = totalPages;
      changed = true;
    }
    if (changed) _notify();
  }

  void toggleDocumentOverlayMinimize() {
    _isDocumentOverlayMinimized = !_isDocumentOverlayMinimized;
    _notify();
  }

  void setDocumentOverlayMinimized(bool minimized) {
    _isDocumentOverlayMinimized = minimized;
    _notify();
  }

  void updateActiveDocumentPreviewUrl(String url) {
    if (_activeOverlayDocument != null) {
      _activeOverlayDocument = _activeOverlayDocument!.copyWith(remotePreviewUrl: url);
      final index = currentPage.elements.indexWhere((e) => e.id == _activeOverlayDocument!.id);
      if (index != -1) {
        currentPage.elements[index] = _activeOverlayDocument!;
      }
      _notify();
    }
  }

  void closeDocumentOverlay() {
    _activeOverlayDocument = null;
    _isDocumentOverlayOpen = false;
    _isDocumentOverlayMinimized = false;
    _overlayCurrentPage = 1;
    _overlayTotalPages = 1;
    _notify();
  }

  void updateOverlayPosition(Offset pos) {
    _overlayPosition = pos;
    notifyListeners();
  }

  void updateOverlaySize(Size size) {
    _overlaySize = size;
    notifyListeners();
  }

  void _notify() {
    _boardVersion++;
    WhiteboardPainter.invalidateCache();
    notifyListeners();
  }

  // Setters
  void setActivePenProfile(PenProfile profile) {
    _activePenProfile = profile;
    _currentTool = WhiteboardTool.pen;
    _notify();
  }

  void setNibRadiusThreshold(double threshold) {
    _nibRadiusThreshold = threshold;
    _notify();
  }

  void autoDetectNibProfile(double radius, {bool isInvertedStylus = false}) {
    if (_currentTool != WhiteboardTool.pen) return;

    PenProfile targetProfile;
    if (isInvertedStylus) {
      targetProfile = PenProfile.thick;
    } else {
      if (radius > 6.0) return;
      if (radius > 0) {
        _lastDetectedRadius = radius;
      }
      targetProfile = radius > _nibRadiusThreshold ? PenProfile.thick : PenProfile.thin;
    }

    if (_activePenProfile != targetProfile) {
      _activePenProfile = targetProfile;
      _notify();
    }
  }

  void setTool(WhiteboardTool tool) {
    _currentTool = tool;
    if (tool != WhiteboardTool.select) clearSelection();
    _notify();
  }

  void setColor(Color color) {
    if (_activePenProfile == PenProfile.thin) {
      _thinColor = color;
    } else {
      _thickColor = color;
    }
    _notify();
  }

  void setStrokeWidth(double width) {
    final map = _activePenProfile == PenProfile.thin ? _thinPenStrokeWidths : _thickPenStrokeWidths;
    map[currentPenType] = width.clamp(minStrokeWidth, maxStrokeWidth);
    _notify();
  }

  void setEraserSize(double size) {
    _eraserSize = size.clamp(minEraserSize, maxEraserSize);
    _notify();
  }

  void setPenType(PenType type) {
    if (_activePenProfile == PenProfile.thin) {
      _thinPenType = type;
    } else {
      _thickPenType = type;
    }
    _currentTool = WhiteboardTool.pen;
    _notify();
  }

  void setShapeType(ShapeType type) {
    _currentShapeType = type;
    _notify();
  }

  // Selection Methods
  void selectElement(String? id, {bool multi = false}) {
    if (id == null) {
      if (!multi) clearSelection();
      return;
    }
    if (!multi) _selectedElementIds.clear();
    _selectedElementIds.add(id);
    _notify();
  }

  void clearSelection() {
    _selectedElementIds.clear();
    _lassoPath = null;
    _notify();
  }

  void updateLassoPath(Path? path) {
    _lassoPath = path;
    if (path != null) {
      // Find all elements whose center or any point is inside the lasso
      _selectedElementIds.clear();
      for (var element in currentPage.elements) {
        if (!_isInCurrentView(element)) continue;
        final bounds = element.getRawBounds();
        // Professional check: if the center of the element is within the lasso path
        if (path.contains(bounds.center)) {
          _selectedElementIds.add(element.id);
        } else if (element is StrokeElement) {
          // For strokes, check if any point is inside for a better feel
          for (var p in element.points) {
            if (path.contains(p)) {
              _selectedElementIds.add(element.id);
              break;
            }
          }
        }
      }
    }
    _notify();
  }

  // Commands
  void addElement(BoardElement element) {
    if (_isDocumentOverlayOpen && element.docPage == null) {
      element.docPage = _overlayCurrentPage;
    }
    final command = AddElementCommand(element, _currentPageIndex);
    _executeCommand(command);
  }

  void removeSelectedElements() {
    if (_selectedElementIds.isEmpty) return;
    final toRemove = currentPage.elements.where((e) => _selectedElementIds.contains(e.id)).toList();
    final command = RemoveElementsCommand(toRemove, _currentPageIndex);
    _executeCommand(command);
    clearSelection();
  }

  void updateSelectedElementsColor(Color color) {
    if (_selectedElementIds.isEmpty) return;
    for (int i = 0; i < currentPage.elements.length; i++) {
      final el = currentPage.elements[i];
      if (_selectedElementIds.contains(el.id)) {
        if (el is StrokeElement) {
          currentPage.elements[i] = el.copyWith(color: color);
        } else if (el is ShapeElement) {
          currentPage.elements[i] = el.copyWith(color: color);
        } else if (el is TextElement) {
          currentPage.elements[i] = el.copyWith(color: color);
        } else if (el is TableElement) {
          currentPage.elements[i] = el.copyWith(color: color);
        } else if (el is MindMapElement) {
          updateMindMapNodeColor(el.id, el.selectedNodeId, color);
        }
      }
    }
    _boardVersion++;
    _notify();
  }

  void clearCurrentPage() {
    if (currentPage.elements.isEmpty) return;
    final toRemove = List<BoardElement>.from(currentPage.elements);
    final command = ClearPageCommand(toRemove, _currentPageIndex);
    _executeCommand(command);
    clearSelection();
  }

  // Mind Map Helper Operations
  void addMindMapChildNode(String mindMapId) => _mutateMindMap(mindMapId, (el) => el.addChild(el.selectedNodeId));

  void addMindMapSiblingNode(String mindMapId) => _mutateMindMap(mindMapId, (el) => el.addSibling(el.selectedNodeId));
  // Board controller ke andar paste karo (jahan currentPage, _boardVersion, _notify() hain).
  // Imports: mind_map_element.dart

  // -----------------------------------------------------------------------------
  // State (controller ke fields me add karo)
  // -----------------------------------------------------------------------------

  /// "..." button dabne par UI ko popup kholne ke liye batata hai.
  /// Widget side par set karo: controller.onMindMapMenuRequested = (mmId, nodeId) { showMenu(...) };
  void Function(String mindMapId, String nodeId)? onMindMapMenuRequested;

  MindMapElement? _mmStrokeEl;
  String? _mmStrokeNodeId;
  List<Offset> _mmStrokePoints = [];

  /// Painter live preview ke liye (element-local coords).
  List<Offset> get mindMapLiveStroke => _mmStrokePoints;
  String? get mindMapLiveStrokeNodeId => _mmStrokeNodeId;

  // -----------------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------------

  MindMapElement? _findMindMap(String id) {
    for (final el in currentPage.elements) {
      if (el.id == id && el is MindMapElement) return el;
    }
    return null;
  }

  /// Ek hi jagah: find -> (undo snapshot) -> change -> version++ -> notify
  void _mutateMindMap(String id, void Function(MindMapElement el) change) {
    final el = _findMindMap(id);
    if (el == null) return;

    // TODO: yahan apne undo system me snapshot push karo, e.g.
    // _pushUndo(mindMapId: id, snapshot: el.snapshot());

    change(el); // element ke methods khud updateLayout() call karte hain
    _boardVersion++;
    _notify();
  }

  // -----------------------------------------------------------------------------
  // Node operations
  // -----------------------------------------------------------------------------

  void addMindMapParentNode(String mindMapId) => _mutateMindMap(mindMapId, (el) => el.addParent(el.selectedNodeId));

  void toggleMindMapNodeCollapse(String mindMapId, String nodeId) {
    _mutateMindMap(mindMapId, (el) {
      final node = el.root.findNode(nodeId);
      if (node != null && node.children.isNotEmpty) {
        el.toggleCollapse(nodeId);
      }
    });
  }

  void deleteMindMapNode(String mindMapId) {
    final el = _findMindMap(mindMapId);
    if (el == null) return;

    // Root delete = poora mind map element delete
    if (el.selectedNodeId == el.root.id) {
      removeSelectedElements();
      return;
    }
    _mutateMindMap(mindMapId, (e) => e.deleteNode(e.selectedNodeId));
  }

  void updateMindMapNodeText(String mindMapId, String nodeId, String newText) {
    _mutateMindMap(mindMapId, (el) => el.updateText(nodeId, newText));
  }

  void updateMindMapNodeColor(String mindMapId, String nodeId, Color color) {
    _mutateMindMap(mindMapId, (el) {
      final node = el.root.findNode(nodeId);
      if (node != null) node.fillColor = color; // layout badalne ki zaroorat nahi
    });
  }

  // -----------------------------------------------------------------------------
  // Pointer handling (pen / select tool ke pointer handler me SABSE PEHLE call karo)
  //
  // Har method true return karta hai agar mind map ne event consume kar liya.
  // true aaye toh normal pen stroke / selection logic MAT chalao.
  //
  // Assumption: el.position = element ka top-left (canvas coords), rotation = 0.
  // -----------------------------------------------------------------------------

  /// [allowStroke] = true jab pen tool active ho (node ke andar likhna).
  bool mindMapPointerDown(Offset canvasPoint, {bool allowStroke = true}) {
    for (final el in currentPage.elements.reversed) {
      if (el is! MindMapElement) continue;

      final local = (canvasPoint - el.position) / el.scale;
      final bounds = (Offset.zero & el.size).inflate(MindMapElement.kHitR);
      if (!bounds.contains(local)) continue;

      // 1) On-canvas buttons (+ / ... / collapse)
      final hit = el.hitTestAction(local);
      if (hit != null) {
        if (hit.action == MindMapAction.menu) {
          el.selectedNodeId = hit.nodeId;
          _boardVersion++;
          _notify();
          onMindMapMenuRequested?.call(el.id, hit.nodeId);
        } else {
          _mutateMindMap(el.id, (e) => e.performAction(hit));
        }
        return true;
      }

      // 2) Node par touch: select karo, pen active ho toh stroke shuru
      final node = el.nodeAt(local);
      if (node != null) {
        el.selectedNodeId = node.id;
        if (allowStroke) {
          _mmStrokeEl = el;
          _mmStrokeNodeId = node.id;
          _mmStrokePoints = [local];
        }
        _boardVersion++;
        _notify();
        return true;
      }
    }
    return false;
  }

  bool mindMapPointerMove(Offset canvasPoint) {
    final el = _mmStrokeEl;
    if (el == null) return false;
    _mmStrokePoints.add((canvasPoint - el.position) / el.scale);
    _notify(); // live preview; version++ ki zaroorat nahi
    return true;
  }

  bool mindMapPointerUp() {
    final el = _mmStrokeEl;
    final nodeId = _mmStrokeNodeId;
    if (el == null || nodeId == null) return false;

    final pts = _mmStrokePoints;
    _mmStrokeEl = null;
    _mmStrokeNodeId = null;
    _mmStrokePoints = [];

    if (pts.length >= 2) {
      // Yahin node resize hota hai (addStroke -> updateLayout)
      _mutateMindMap(el.id, (e) => e.addStroke(nodeId, pts));
    } else {
      _boardVersion++;
      _notify();
    }
    return true;
  }

  void refreshBoard() {
    _boardVersion++;
    _notify();
  }

  // Multi-Transformation
  final Map<String, TransformData> _startTransforms = {};

  void startTransform() {
    _startTransforms.clear();
    for (var id in _selectedElementIds) {
      final e = currentPage.elements.firstWhere((el) => el.id == id);
      Size? elementSize;
      if (e is ImageElement) elementSize = e.size;
      if (e is DocumentElement) elementSize = e.size;

      _startTransforms[id] = TransformData(
        id: id,
        oldPos: e.position,
        newPos: e.position,
        oldRot: e.rotation,
        newRot: e.rotation,
        oldScale: e.scale,
        newScale: e.scale,
        oldSize: elementSize,
        newSize: elementSize,
      );
    }
  }

  void resizeSelectedElement(HandleDirection direction, Offset delta) {
    if (_selectedElementIds.isEmpty) return;

    final selectedElements = currentPage.elements.where((e) => _selectedElementIds.contains(e.id)).toList();
    if (selectedElements.isEmpty) return;

    // 1. Calculate Group Bounds and Group Center
    Rect groupRect = selectedElements[0].getRawBounds();
    if (selectedElements.length == 1) {
      final e = selectedElements[0];
      groupRect = Rect.fromCenter(center: groupRect.center, width: groupRect.width * e.scale, height: groupRect.height * e.scale);
    } else {
      for (var i = 1; i < selectedElements.length; i++) {
        final e = selectedElements[i];
        final r = e.getRawBounds();
        final visualR = Rect.fromCenter(center: r.center, width: r.width * e.scale, height: r.height * e.scale);
        groupRect = groupRect.expandToInclude(visualR);
      }
    }

    final double groupW = max(20.0, groupRect.width);
    final double groupH = max(20.0, groupRect.height);

    // 2. Compute Scale Factor for the entire Group
    double scaleFactor = 1.0;
    switch (direction) {
      case HandleDirection.bottomRight:
      case HandleDirection.topRight:
      case HandleDirection.middleRight:
        scaleFactor = 1.0 + (delta.dx / groupW);
        break;
      case HandleDirection.bottomLeft:
      case HandleDirection.topLeft:
      case HandleDirection.middleLeft:
        scaleFactor = 1.0 - (delta.dx / groupW);
        break;
      case HandleDirection.bottomCenter:
        scaleFactor = 1.0 + (delta.dy / groupH);
        break;
      case HandleDirection.topCenter:
        scaleFactor = 1.0 - (delta.dy / groupH);
        break;
    }

    scaleFactor = scaleFactor.clamp(0.2, 5.0);
    if (scaleFactor == 1.0) return;

    final Offset groupCenter = groupRect.center;

    // 3. Apply Group Scaling to ALL selected elements
    for (var element in selectedElements) {
      if (selectedElements.length > 1) {
        // Shift element position relative to group center so elements spread/shrink proportionally
        final Offset currentCenter = element.getRawBounds().center;
        final Offset relativePos = currentCenter - groupCenter;
        final Offset newRelativePos = relativePos * scaleFactor;
        final Offset posDelta = newRelativePos - relativePos;

        element.position += posDelta;
        _updateInternalPoints(element, posDelta);
      }

      if (element is ImageElement) {
        element.size = Size(max(20.0, element.size.width * scaleFactor), max(20.0, element.size.height * scaleFactor));
      } else if (element is DocumentElement) {
        element.size = Size(max(20.0, element.size.width * scaleFactor), max(20.0, element.size.height * scaleFactor));
      } else if (element is TextElement) {
        element.size = Size(max(20.0, element.size.width * scaleFactor), max(20.0, element.size.height * scaleFactor));
        element.fontSize = (element.fontSize * scaleFactor).clamp(8.0, 200.0);
      } else if (element is TableElement) {
        element.size = Size(max(40.0, element.size.width * scaleFactor), max(30.0, element.size.height * scaleFactor));
      } else if (element is ShapeElement) {
        final center = element.getRawBounds().center;
        element.position = center + (element.position - center) * scaleFactor;
        element.endPoint = center + (element.endPoint - center) * scaleFactor;
      } else if (element is StrokeElement) {
        element.scale = (element.scale * scaleFactor).clamp(0.1, 10.0);
        element.invalidatePath();
      }

      element.invalidateBounds();
    }
    _notify();
  }

  void updateElementTransform(Offset delta, double rotationDelta, double scaleDelta) {
    Offset? groupCenter;
    if (_selectedElementIds.length > 1) {
      groupCenter = _getSelectionCenter();
    }

    // Convert additive scaleDelta to a multiplicative factor for the group
    // This ensures all elements scale proportionally regardless of their individual scales
    final double scaleFactor = 1.0 + scaleDelta;

    for (var id in _selectedElementIds) {
      final element = currentPage.elements.firstWhere((e) => e.id == id);

      // 1. Scale relative to group center
      if (groupCenter != null && scaleDelta != 0) {
        final Offset currentCenter = element.getRawBounds().center;
        final Offset relativePos = currentCenter - groupCenter;

        // Move the element center proportionally
        final Offset newRelativePos = relativePos * scaleFactor;
        final Offset posDelta = newRelativePos - relativePos;

        element.position += posDelta;
        _updateInternalPoints(element, posDelta);
      }

      // 2. Rotate relative to group center
      if (groupCenter != null && rotationDelta != 0) {
        final Offset currentCenter = element.getRawBounds().center;
        final Offset relativePos = currentCenter - groupCenter;

        final double cosTheta = cos(rotationDelta);
        final double sinTheta = sin(rotationDelta);

        final double newX = relativePos.dx * cosTheta - relativePos.dy * sinTheta;
        final double newY = relativePos.dx * sinTheta + relativePos.dy * cosTheta;

        final Offset newRelativePos = Offset(newX, newY);
        final Offset posDelta = newRelativePos - relativePos;

        element.position += posDelta;
        _updateInternalPoints(element, posDelta);

        // Also update individual rotation
        element.rotation += rotationDelta;
      } else if (groupCenter == null) {
        // Individual rotation if only one element
        element.rotation += rotationDelta;
      }

      // 3. Translation (Move)
      element.position += delta;
      _updateInternalPoints(element, delta);

      // 4. Individual scale property
      // Multiplicative scaling prevents distortion in groups
      element.scale = (element.scale * scaleFactor).clamp(0.1, 10.0);
      if (element is TextElement && scaleDelta != 0.0) {
        element.size = Size(max(20.0, element.size.width * scaleFactor), max(20.0, element.size.height * scaleFactor));
        element.fontSize = (element.fontSize * scaleFactor).clamp(8.0, 200.0);
      } else if (element is TableElement && scaleDelta != 0.0) {
        element.size = Size(max(40.0, element.size.width * scaleFactor), max(30.0, element.size.height * scaleFactor));
      }

      element.invalidateBounds();
      element.invalidatePath(); // Sync the selection box and path during drag
    }
    _notify();
  }

  void _updateInternalPoints(BoardElement element, Offset delta) {
    if (element is StrokeElement) {
      for (int i = 0; i < element.points.length; i++) {
        element.points[i] += delta;
      }
    } else if (element is ShapeElement) {
      element.endPoint += delta;
    }
  }

  Offset _getSelectionCenter() {
    if (_selectedElementIds.isEmpty) return Offset.zero;
    final selected = currentPage.elements.where((e) => _selectedElementIds.contains(e.id)).toList();

    Rect bounds = selected[0].getRawBounds();
    bounds = Rect.fromCenter(center: bounds.center, width: bounds.width * selected[0].scale, height: bounds.height * selected[0].scale);

    for (int i = 1; i < selected.length; i++) {
      final e = selected[i];
      final r = e.getRawBounds();
      final visualR = Rect.fromCenter(center: r.center, width: r.width * e.scale, height: r.height * e.scale);
      bounds = bounds.expandToInclude(visualR);
    }
    return bounds.center;
  }

  void endTransform() {
    if (_startTransforms.isEmpty) return;

    final List<TransformData> transforms = [];
    for (var id in _selectedElementIds) {
      final e = currentPage.elements.firstWhere((el) => el.id == id);
      final start = _startTransforms[id]!;
      Size? currentSize;
      if (e is ImageElement) currentSize = e.size;
      if (e is DocumentElement) currentSize = e.size;

      transforms.add(
        TransformData(
          id: id,
          oldPos: start.oldPos,
          newPos: e.position,
          oldRot: start.oldRot,
          newRot: e.rotation,
          oldScale: start.oldScale,
          newScale: e.scale,
          oldSize: start.oldSize,
          newSize: currentSize,
        ),
      );
    }

    final command = MultiTransformCommand(pageIndex: _currentPageIndex, transforms: transforms);
    _undoStack.add(command);
    _redoStack.clear();
    _startTransforms.clear();
    notifyListeners();
  }

  // ===========================================================================
  // PARTIAL ERASE (optimized)
  //
  // Pehle: sweep ko chhote steps me todta tha, har step par poori elements list
  // copy hoti thi, aur har step par _notify() (= boardVersion++) chalta tha.
  // Ab: ek call = ek single pass, koi list copy nahi, aur sirf tab ek _notify()
  // jab kuch sach me erase hua. Z-order bhi preserve hota hai (erased stroke ke
  // tukde usi jagah rehte hain, top par nahi jaate).
  // ===========================================================================

  /// Jo elements abhi canvas par dikh rahe hain wahi erase/hit hone chahiye.
  /// Overlay band hai to docPage == null wale, open hai to current overlay page wale.
  bool _isInCurrentView(BoardElement e) {
    return _isDocumentOverlayOpen ? e.docPage == _overlayCurrentPage : e.docPage == null;
  }

  void partialErase(Offset position, double radius, {Offset? lastPos}) {
    final Offset p1 = lastPos ?? position;
    final Offset p2 = position;
    final double radiusSq = radius * radius;
    final Rect eraserBox = Rect.fromPoints(p1, p2).inflate(radius);

    final elements = currentPage.elements;
    final Map<String, List<BoardElement>> replacements = {};
    List<Offset>? samples; // sirf shapes ke liye, lazily banta hai

    for (final element in elements) {
      if (element is! StrokeElement && element is! ShapeElement) continue;
      if (!_isInCurrentView(element)) continue;

      // Fast spatial filter (raw points ke saath match karta hai)
      if (!eraserBox.overlaps(element.getRawBounds().inflate(1.0))) continue;

      if (element is StrokeElement) {
        final segments = _splitStroke(element.points, p1, p2, radiusSq);
        if (segments == null) continue; // kuch touch nahi hua

        final List<BoardElement> pieces = [];
        for (final seg in segments) {
          if (seg.length > 1) {
            pieces.add(
              element.copyWith(
                id: const Uuid().v4(),
                points: seg,
                position: seg.first,
                docPage: _isDocumentOverlayOpen ? _overlayCurrentPage : element.docPage,
              ),
            );
          }
        }
        replacements[element.id] = pieces;
      } else if (element is ShapeElement) {
        if (element.shapeType == ShapeType.line || element.shapeType == ShapeType.arrow) {
          final linePoints = _interpolatePoints(element.position, element.endPoint);
          final segments = _splitStroke(linePoints, p1, p2, radiusSq);
          if (segments == null) continue;

          final List<BoardElement> pieces = [];
          for (final seg in segments) {
            if (seg.length > 1) {
              pieces.add(
                StrokeElement(
                  id: const Uuid().v4(),
                  position: seg.first,
                  points: seg,
                  color: element.color,
                  strokeWidth: element.strokeWidth,
                  docPage: element.docPage,
                ),
              );
            }
          }
          replacements[element.id] = pieces;
        } else {
          samples ??= _sweepSamples(p1, p2, radius);
          final inflated = Rect.fromPoints(element.position, element.endPoint).inflate(radius);
          bool hit = false;
          for (final s in samples) {
            if (inflated.contains(s)) {
              hit = true;
              break;
            }
          }
          if (hit) replacements[element.id] = const [];
        }
      }
    }

    if (replacements.isEmpty) return; // kuch nahi hua: no rebuild, no repaint

    // Order preserve karte hue ek hi baar me list rebuild
    final List<BoardElement> rebuilt = [];
    for (final e in elements) {
      final r = replacements[e.id];
      if (r == null) {
        rebuilt.add(e);
      } else {
        rebuilt.addAll(r);
      }
    }
    elements
      ..clear()
      ..addAll(rebuilt);

    _notify(); // poore erase call ke liye sirf ek notify
  }

  /// Points ko eraser capsule (p1->p2, radius) ke hisaab se todta hai.
  /// Agar koi point capsule ke andar nahi hai to null return karta hai (koi change nahi).
  List<List<Offset>>? _splitStroke(List<Offset> points, Offset a, Offset b, double radiusSq) {
    if (points.isEmpty) return null;

    final double vx = b.dx - a.dx;
    final double vy = b.dy - a.dy;
    final double l2 = vx * vx + vy * vy;

    bool inside(Offset p) {
      if (l2 == 0.0) {
        final dx = p.dx - a.dx;
        final dy = p.dy - a.dy;
        return dx * dx + dy * dy < radiusSq;
      }
      double t = ((p.dx - a.dx) * vx + (p.dy - a.dy) * vy) / l2;
      t = t.clamp(0.0, 1.0);
      final dx = p.dx - (a.dx + t * vx);
      final dy = p.dy - (a.dy + t * vy);
      return dx * dx + dy * dy < radiusSq;
    }

    int first = -1;
    for (int i = 0; i < points.length; i++) {
      if (inside(points[i])) {
        first = i;
        break;
      }
    }
    if (first == -1) return null;

    final List<List<Offset>> result = [];
    List<Offset>? current;

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      if (i >= first && inside(p)) {
        if (current != null && current.isNotEmpty) {
          result.add(current);
          current = null;
        }
      } else {
        current ??= [];
        current.add(p);
      }
    }
    if (current != null && current.isNotEmpty) {
      result.add(current);
    }
    return result;
  }

  /// p1 -> p2 ke beech ke sample points (shapes ke liye, taaki lambi sweep me gap na rahe).
  List<Offset> _sweepSamples(Offset p1, Offset p2, double radius) {
    final double dist = (p2 - p1).distance;
    if (dist <= 0.0) return [p1];
    final int steps = max(1, (dist / (radius * 0.5)).ceil());
    return [for (int i = 0; i <= steps; i++) Offset.lerp(p1, p2, i / steps)!];
  }

  List<Offset> _interpolatePoints(Offset start, Offset end) {
    final double dist = (end - start).distance;
    final int steps = max(1, (dist / 2).ceil());
    return [for (int i = 0; i <= steps; i++) Offset.lerp(start, end, i / steps)!];
  }

  void _executeCommand(Command command) {
    command.execute(this);
    _undoStack.add(command);
    _redoStack.clear();
    _notify();
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    final command = _undoStack.removeLast();
    command.undo(this);
    _redoStack.add(command);
    _notify();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    final command = _redoStack.removeLast();
    command.execute(this);
    _undoStack.add(command);
    _notify();
  }

  // Page Management
  void importPages(List<BoardPage> newPages) {
    if (newPages.isEmpty) return;

    if (_pages.length == 1 && _pages[0].elements.isEmpty) {
      _pages.clear();
      _pages.addAll(newPages);
      _currentPageIndex = 0;
    } else {
      final startIndex = _pages.length;
      _pages.addAll(newPages);
      _currentPageIndex = startIndex;
    }

    _canvasPanOffset = Offset.zero;
    _undoStack.clear();
    _redoStack.clear();
    clearSelection();
    _notify();
  }

  void addPage() {
    _pages.add(BoardPage(id: const Uuid().v4(), elements: []));
    _currentPageIndex = _pages.length - 1;
    _canvasPanOffset = Offset.zero;
    _undoStack.clear();
    _redoStack.clear();
    _notify();
  }

  void deletePage(int index) {
    if (_pages.length <= 1) return;
    _pages.removeAt(index);
    if (_currentPageIndex >= _pages.length) {
      _currentPageIndex = _pages.length - 1;
    }
    _canvasPanOffset = Offset.zero;
    clearSelection();
    _notify();
  }

  void switchPage(int index) {
    _currentPageIndex = index;
    _canvasPanOffset = Offset.zero;
    clearSelection();
    _notify();
  }

  BoardElement? hitTest(Offset localPosition, {double threshold = 25.0}) {
    for (var element in currentPage.elements.reversed) {
      if (!_isInCurrentView(element)) continue;

      if (element is StrokeElement) {
        for (var point in element.points) {
          if ((point - localPosition).distance < threshold) return element;
        }
      } else if (element is ShapeElement) {
        if (element.shapeType == ShapeType.line || element.shapeType == ShapeType.arrow) {
          if (_distToSegment(localPosition, element.position, element.endPoint) < threshold) return element;
        } else {
          final rect = Rect.fromPoints(element.position, element.endPoint);
          if (rect.inflate(threshold / 2).contains(localPosition)) return element;
        }
      } else if (element is MindMapElement) {
        final local = _toElementLocal(element, localPosition)- element.position;
        if (element.nodeAt(local, inflate: 8) != null) return element;
      } else if (element is ImageElement ||
          element is DocumentElement ||
          element is TableElement ||
          element is TextElement) {
        final local = _toElementLocal(element, localPosition) - element.position;
        final raw = element.getRawBounds();
        if ((Offset.zero & raw.size).inflate(6).contains(local)) return element;
      }
    }
    return null;
  }

  /// Point ko element ke rotation/scale ke hisaab se element-space me laata hai
  /// (canvas ke _mmLocal jaisa hi).
  Offset _toElementLocal(BoardElement el, Offset p) {
    var q = p;
    if (el.rotation != 0 || el.scale != 1.0) {
      final c = el.getRawBounds().center;
      final d = q - c;
      final cosA = cos(-el.rotation);
      final sinA = sin(-el.rotation);
      q = c + Offset(d.dx * cosA - d.dy * sinA, d.dx * sinA + d.dy * cosA) / el.scale;
    }
    return q;
  }

  double _distToSegment(Offset p, Offset v, Offset w) {
    double l2 = (v - w).distanceSquared;
    if (l2 == 0.0) return (p - v).distance;
    double t = ((p.dx - v.dx) * (w.dx - v.dx) + (p.dy - v.dy) * (w.dy - v.dy)) / l2;
    t = t.clamp(0.0, 1.0);
    return (p - Offset(v.dx + t * (w.dx - v.dx), v.dy + t * (w.dy - v.dy))).distance;
  }

  final Map<String, Size> _defaultImageSizes = {};
  final Set<String> _fullScreenImages = {};

  void toggleImageFullScreen(String elementId, Size screenSize) {
    for (var page in _pages) {
      for (var element in page.elements) {
        if (element.id == elementId && element is ImageElement) {
          if (!_defaultImageSizes.containsKey(elementId)) {
            _defaultImageSizes[elementId] = element.size;
          }

          bool isFull = _fullScreenImages.contains(elementId);
          if (!isFull) {
            final natW = element.size.width;
            final natH = element.size.height;
            final aspect = natW > 0 && natH > 0 ? natW / natH : 1.33;

            double targetW = screenSize.width * 0.90;
            double targetH = screenSize.height * 0.90;
            double newW, newH;

            if (targetW / targetH > aspect) {
              newH = targetH;
              newW = newH * aspect;
            } else {
              newW = targetW;
              newH = newW / aspect;
            }

            element.size = Size(newW, newH);
            element.position = Offset((screenSize.width - newW) / 2, (screenSize.height - newH) / 2)- _canvasPanOffset;
            _fullScreenImages.add(elementId);
          } else {
            final defSize = _defaultImageSizes[elementId];
            if (defSize != null) {
              element.size = defSize;
              element.position = Offset((screenSize.width - defSize.width) / 2, (screenSize.height - defSize.height) / 2)- _canvasPanOffset;
            }
            _fullScreenImages.remove(elementId);
          }
          element.invalidateBounds();
          _notify();
          return;
        }
      }
    }
  }

  // --- AI FEATURES ---
  final AiService _aiService = AiService();
  GlobalKey? canvasKey;
  bool _isAiPanelOpen = false;
  bool _isAiLoading = false;
  String _aiResultText = '';
  String _aiTitle = '';

  bool get isAiPanelOpen => _isAiPanelOpen;
  bool get isAiLoading => _isAiLoading;
  String get aiResultText => _aiResultText;
  String get aiTitle => _aiTitle;

  void toggleAiPanel(bool open) {
    _isAiPanelOpen = open;
    _notify();
  }

  Future<void> generateAiContent({required String type, required bool isWholeDoc, bool forSelectedOnly = false}) async {
    _isAiPanelOpen = true;
    _isAiLoading = true;
    _aiTitle = type;
    _aiResultText = '';
    _notify();

    StringBuffer contentBuffer = StringBuffer();
    List<String> imagePaths = [];

    if (forSelectedOnly && _selectedElementIds.isNotEmpty) {
      contentBuffer.writeln('--- Selected Content from Slide ${_currentPageIndex + 1} ---');
      final selectedElements = currentPage.elements.where((e) => _selectedElementIds.contains(e.id)).toList();
      for (var el in selectedElements) {
        if (el is ImageElement && el.imageUrl.isNotEmpty) {
          imagePaths.add(el.imageUrl);
        } else if (el is DocumentElement) {
          contentBuffer.writeln(el.fileName);
        } else if (el is StrokeElement) {
          contentBuffer.writeln('Handwritten text/drawing stroke.');
        }
      }
      if (imagePaths.isEmpty && canvasKey != null) {
        final canvasImagePath = await BoardStorageService().captureCanvasToTempFile(canvasKey!);
        if (canvasImagePath != null) {
          imagePaths.add(canvasImagePath);
        }
      }
    } else if (isWholeDoc) {
      for (int i = 0; i < _pages.length; i++) {
        contentBuffer.writeln('--- Slide ${i + 1} ---');
        for (var el in _pages[i].elements) {
          if (el is ImageElement && el.imageUrl.isNotEmpty) {
            imagePaths.add(el.imageUrl);
          } else if (el is DocumentElement) {
            contentBuffer.writeln(el.fileName);
          }
        }
      }
    } else {
      contentBuffer.writeln('--- Slide ${_currentPageIndex + 1} ---');
      for (var el in currentPage.elements) {
        if (el is ImageElement && el.imageUrl.isNotEmpty) {
          imagePaths.add(el.imageUrl);
        } else if (el is DocumentElement) {
          contentBuffer.writeln(el.fileName);
        }
      }
    }

    String contentText = contentBuffer.toString().trim();

    // If no slide images or documents were found, but canvasKey is available, capture the current canvas (freehand writing/drawings)!
    if (imagePaths.isEmpty && canvasKey != null) {
      final canvasImagePath = await BoardStorageService().captureCanvasToTempFile(canvasKey!);
      if (canvasImagePath != null) {
        imagePaths.add(canvasImagePath);
        contentBuffer.writeln('Handwritten notes / drawings on whiteboard canvas.');
      }
    }

    if (contentText.isEmpty && imagePaths.isEmpty) {
      contentText = isWholeDoc
          ? 'Educational presentation with ${_pages.length} slides.'
          : 'Educational teaching slide ${_currentPageIndex + 1}.';
    }

    // Limit to max 5 slide images per prompt to avoid payload limit
    if (imagePaths.length > 5) {
      imagePaths = imagePaths.sublist(0, 5);
    }

    String result = '';
    if (type == 'Quick Quiz') {
      result = await _aiService.generateQuickQuiz(contentText, imagePaths: imagePaths);
    } else if (type == 'Homework') {
      result = await _aiService.generateHomework(contentText, imagePaths: imagePaths);
    } else if (type == 'Summary') {
      result = await _aiService.generateSummary(contentText, imagePaths: imagePaths);
    }

    _aiResultText = result;
    _isAiLoading = false;
    _notify();
  }


  /// Naya element ko abhi screen par jo dikh raha hai uske center me rakhta hai.
  /// Table, MindMap, Image, PPT/PDF, Text, Shape sab ke liye chalta hai.
  void addElementCenteredInView(BoardElement el, Size viewport) {
    final target = viewportCenterOnCanvas(viewport);
    final delta = target - el.getRawBounds().center;
    el.position += delta;
    _updateInternalPoints(el, delta); // stroke/shape ke points bhi shift
    el.invalidateBounds();
    addElement(el);
  }
}
