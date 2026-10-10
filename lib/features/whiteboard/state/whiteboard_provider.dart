import 'dart:math';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/board_element.dart';
import '../models/board_page.dart';
import '../models/stroke_element.dart';
import '../models/shape_element.dart';
import '../models/image_element.dart';
import '../models/document_element.dart';
import '../services/ai_service.dart';
import '../services/board_storage_service.dart';

enum WhiteboardTool { pen, eraser, shape, image, select }

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
  Color _currentColor = Colors.black;
  final Map<PenType, double> _penStrokeWidths = {PenType.pen: 2.0, PenType.fountainPen: 2.0, PenType.brush: 2.0, PenType.marker: 2.0};
  double _eraserSize = 25.0;
  PenType _currentPenType = PenType.pen;
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
  Color get currentColor => _currentColor;
  double get strokeWidth => _penStrokeWidths[_currentPenType] ?? 2.0;
  double get eraserSize => _eraserSize;

  double get minStrokeWidth {
    switch (_currentPenType) {
      case PenType.marker:
        return 1.5;
      case PenType.pen:
      case PenType.fountainPen:
      case PenType.brush:
        return 1.0;
    }
  }

  double get maxStrokeWidth {
    switch (_currentPenType) {
      case PenType.pen:
        return 6.0;
      case PenType.fountainPen:
        return 6.0;
      case PenType.brush:
        return 8.0;
      case PenType.marker:
        return 10.0;
    }
  }

  PenType get currentPenType => _currentPenType;
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
    notifyListeners();
  }

  // Setters
  void setTool(WhiteboardTool tool) {
    _currentTool = tool;
    if (tool != WhiteboardTool.select) clearSelection();
    _notify();
  }

  void setColor(Color color) {
    _currentColor = color;
    _notify();
  }

  void setStrokeWidth(double width) {
    _penStrokeWidths[_currentPenType] = width.clamp(minStrokeWidth, maxStrokeWidth);
    _notify();
  }

  void setEraserSize(double size) {
    _eraserSize = size.clamp(10.0, 30.0);
    _notify();
  }

  void setPenType(PenType type) {
    _currentPenType = type;
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
        if (_isDocumentOverlayOpen && element.docPage != _overlayCurrentPage) continue;
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

  void clearCurrentPage() {
    if (currentPage.elements.isEmpty) return;
    final toRemove = List<BoardElement>.from(currentPage.elements);
    final command = ClearPageCommand(toRemove, _currentPageIndex);
    _executeCommand(command);
    clearSelection();
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

  // ... Partial Erase and Hit Testing ...
  void partialErase(Offset position, double radius, {Offset? lastPos}) {
    List<BoardElement> toRemove = [];
    List<BoardElement> toAdd = [];
    bool changed = false;

    final Offset p1 = lastPos ?? position;
    final Offset p2 = position;

    final Rect eraserBox = Rect.fromPoints(p1, p2).inflate(radius);

    for (var element in List.from(currentPage.elements)) {
      if (_isDocumentOverlayOpen && element.docPage != _overlayCurrentPage) continue;

      // Fast Spatial Filter: Bounding box check
      final rawBounds = element.getRawBounds();
      final visualBounds = Rect.fromCenter(
        center: rawBounds.center,
        width: rawBounds.width * element.scale,
        height: rawBounds.height * element.scale,
      );

      // If eraser area doesn't even touch the element's box, skip it
      if (!eraserBox.overlaps(visualBounds)) continue;

      if (element is StrokeElement) {
        List<List<Offset>> segments = _splitStrokePointsSegment(element.points, p1, p2, radius);

        if (segments.length != 1 || segments[0].length != element.points.length) {
          toRemove.add(element);
          for (var seg in segments) {
            if (seg.length > 1) {
              toAdd.add(
                element.copyWith(
                  id: const Uuid().v4(),
                  points: seg,
                  position: seg.first,
                  docPage: _isDocumentOverlayOpen ? _overlayCurrentPage : element.docPage,
                ),
              );
            }
          }
          changed = true;
        }
      } else if (element is ShapeElement) {
        if (element.shapeType == ShapeType.line || element.shapeType == ShapeType.arrow) {
          if (_distToSegment(position, element.position, element.endPoint) < radius ||
              _distToSegment(p1, element.position, element.endPoint) < radius) {
            toRemove.add(element);
            List<Offset> linePoints = _interpolatePoints(element.position, element.endPoint);
            List<List<Offset>> segments = _splitStrokePointsSegment(linePoints, p1, p2, radius);
            for (var seg in segments) {
              if (seg.length > 1) {
                toAdd.add(
                  StrokeElement(
                    id: const Uuid().v4(),
                    position: seg.first,
                    points: seg,
                    color: element.color,
                    strokeWidth: element.strokeWidth,
                  ),
                );
              }
            }
            changed = true;
          }
        } else {
          final rect = Rect.fromPoints(element.position, element.endPoint);
          if (rect.inflate(radius).contains(position) || rect.inflate(radius).contains(p1)) {
            toRemove.add(element);
            changed = true;
          }
        }
      }
    }

    if (changed) {
      for (var e in toRemove) {
        currentPage.elements.removeWhere((x) => x.id == e.id);
      }
      currentPage.elements.addAll(toAdd);
      _notify();
    }
  }

  List<List<Offset>> _splitStrokePointsSegment(List<Offset> points, Offset segA, Offset segB, double radius) {
    if (points.isEmpty) return [];

    List<List<Offset>> result = [];
    List<Offset>? currentSegment;

    final double radiusSq = radius * radius;

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      bool inside = _distToSegmentSquared(p, segA, segB) < radiusSq;

      if (inside) {
        if (currentSegment != null && currentSegment.isNotEmpty) {
          result.add(currentSegment);
          currentSegment = null;
        }
      } else {
        currentSegment ??= [];
        currentSegment.add(p);
      }
    }

    if (currentSegment != null && currentSegment.isNotEmpty) {
      result.add(currentSegment);
    }
    return result;
  }

  double _distToSegmentSquared(Offset p, Offset v, Offset w) {
    double l2 = (v - w).distanceSquared;
    if (l2 == 0.0) return (p - v).distanceSquared;
    double t = ((p.dx - v.dx) * (w.dx - v.dx) + (p.dy - v.dy) * (w.dy - v.dy)) / l2;
    t = t.clamp(0.0, 1.0);
    final proj = Offset(v.dx + t * (w.dx - v.dx), v.dy + t * (w.dy - v.dy));
    return (p - proj).distanceSquared;
  }

  List<Offset> _interpolatePoints(Offset start, Offset end) {
    List<Offset> points = [];
    double dist = (end - start).distance;
    int steps = (dist / 2).ceil();
    for (int i = 0; i <= steps; i++) {
      points.add(Offset.lerp(start, end, i / steps)!);
    }
    return points;
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

    _undoStack.clear();
    _redoStack.clear();
    clearSelection();
    _notify();
  }

  void addPage() {
    _pages.add(BoardPage(id: const Uuid().v4(), elements: []));
    _currentPageIndex = _pages.length - 1;
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
    _notify();
  }

  void switchPage(int index) {
    _currentPageIndex = index;
    clearSelection();
    _notify();
  }

  // Hit Testing
  BoardElement? hitTest(Offset localPosition, {double threshold = 25.0}) {
    for (var element in currentPage.elements.reversed) {
      if (_isDocumentOverlayOpen && element.docPage != _overlayCurrentPage) continue;
      if (element is StrokeElement) {
        for (var point in element.points) {
          if ((point - localPosition).distance < threshold) return element;
        }
      } else if (element is ShapeElement) {
        if (element.shapeType == ShapeType.line || element.shapeType == ShapeType.arrow) {
          if (_distToSegment(localPosition, element.position, element.endPoint) < threshold) {
            return element;
          }
        } else {
          final rect = Rect.fromPoints(element.position, element.endPoint);
          if (rect.inflate(threshold / 2).contains(localPosition)) return element;
        }
      } else if (element is ImageElement) {
        final rect = element.getRawBounds();
        if (rect.contains(localPosition)) return element;
      }
    }
    return null;
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
            element.position = Offset((screenSize.width - newW) / 2, (screenSize.height - newH) / 2);
            _fullScreenImages.add(elementId);
          } else {
            final defSize = _defaultImageSizes[elementId];
            if (defSize != null) {
              element.size = defSize;
              element.position = Offset((screenSize.width - defSize.width) / 2, (screenSize.height - defSize.height) / 2);
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
}
