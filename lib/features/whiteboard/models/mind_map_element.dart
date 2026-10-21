import 'dart:math';
import 'package:flutter/material.dart';
import 'board_element.dart';

/// Mind map ke on-canvas buttons jo painter draw karta hai aur board tap par hit-test karta hai.
enum MindMapAction { addChild, addParent, addSibling, menu, toggle }

class MindMapHit {
  final MindMapAction action;
  final String nodeId;
  const MindMapHit(this.action, this.nodeId);
}

class MindMapNode {
  String id;
  String text;
  bool collapsed;
  Color fillColor; // Teal (#00BFA5)
  Color textColor; // Blue/Dark text
  List<MindMapNode> children;

  double width;
  double height;
  Offset relativeOffset;

  /// Handwriting strokes, NODE-LOCAL coordinates (node ke top-left se).
  List<List<Offset>> strokes;

  /// Corresponding stroke colors for each handwriting stroke.
  List<Color> strokeColors;

  /// Text ki max width. Painter me bhi isi constant se wrap karo.
  static const double kMaxTextW = 220.0;

  MindMapNode({
    required this.id,
    this.text = '',
    this.collapsed = false,
    this.fillColor = const Color(0xFF00BFA5),
    this.textColor = const Color(0xFF1E3A8A),
    List<MindMapNode>? children,
    this.width = 130.0,
    this.height = 55.0,
    this.relativeOffset = Offset.zero,
    List<List<Offset>>? strokes,
    List<Color>? strokeColors,
  }) : children = children ?? [],
       strokes = strokes ?? [],
       strokeColors = strokeColors ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'collapsed': collapsed,
    'fillColor': fillColor.toARGB32(),
    'textColor': textColor.toARGB32(),
    'children': children.map((c) => c.toJson()).toList(),
    'width': width,
    'height': height,
    'relativeOffset': {'dx': relativeOffset.dx, 'dy': relativeOffset.dy},
    'strokes': strokes
        .map((s) => s.map((p) => {'x': p.dx, 'y': p.dy}).toList())
        .toList(),
    'strokeColors': strokeColors.map((c) => c.toARGB32()).toList(),
  };

  factory MindMapNode.fromJson(Map<String, dynamic> json) {
    return MindMapNode(
      id: json['id'],
      text: json['text'] ?? '',
      collapsed: json['collapsed'] ?? false,
      fillColor: Color(json['fillColor'] ?? 0xFF00BFA5),
      textColor: Color(json['textColor'] ?? 0xFF1E3A8A),
      children:
          (json['children'] as List?)
              ?.map((c) => MindMapNode.fromJson(c))
              .toList() ??
          [],
      width: json['width']?.toDouble() ?? 130.0,
      height: json['height']?.toDouble() ?? 55.0,
      relativeOffset: json['relativeOffset'] != null
          ? Offset(
              json['relativeOffset']['dx']?.toDouble() ?? 0.0,
              json['relativeOffset']['dy']?.toDouble() ?? 0.0,
            )
          : Offset.zero,
      strokes:
          (json['strokes'] as List?)
              ?.map(
                (s) => (s as List)
                    .map(
                      (p) => Offset(
                        p['x']?.toDouble() ?? 0.0,
                        p['y']?.toDouble() ?? 0.0,
                      ),
                    )
                    .toList(),
              )
              .toList() ??
          [],
      strokeColors:
          (json['strokeColors'] as List?)
              ?.map((c) => Color(c as int))
              .toList() ??
          [],
    );
  }

  /// Deep copy (undo/redo snapshots ke liye).
  MindMapNode clone() => MindMapNode.fromJson(toJson());

  /// Finds a node by id anywhere in the subtree.
  MindMapNode? findNode(String targetId) {
    if (id == targetId) return this;
    for (final child in children) {
      final found = child.findNode(targetId);
      if (found != null) return found;
    }
    return null;
  }

  /// Finds the parent node of a node by id.
  MindMapNode? findParentOf(String targetId) {
    for (final child in children) {
      if (child.id == targetId) return this;
      final found = child.findParentOf(targetId);
      if (found != null) return found;
    }
    return null;
  }

  /// Dynamic size calculation based on text and handwriting stroke bounds
  void recalculateSize() {
    double textW = 0.0;
    double textH = 0.0;
    if (text.isNotEmpty) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(fontSize: 15.0, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout(maxWidth: kMaxTextW);
      textW = textPainter.width + 36.0;
      textH = textPainter.height + 24.0;
    }

    double strokeW = 0.0;
    double strokeH = 0.0;
    if (strokes.isNotEmpty) {
      double minX = double.infinity;
      double maxX = -double.infinity;
      double minY = double.infinity;
      double maxY = -double.infinity;

      for (final stroke in strokes) {
        for (final p in stroke) {
          minX = min(minX, p.dx);
          maxX = max(maxX, p.dx);
          minY = min(minY, p.dy);
          maxY = max(maxY, p.dy);
        }
      }

      // Left edge se bahar gayi writing ko andar shift karo
      if (minX < 12.0 && minX.isFinite) {
        final dxShift = 15.0 - minX;
        for (final stroke in strokes) {
          for (int i = 0; i < stroke.length; i++) {
            stroke[i] = Offset(stroke[i].dx + dxShift, stroke[i].dy);
          }
        }
        maxX += dxShift;
      }

      if (maxX.isFinite) {
        strokeW = maxX + 35.0; // Box width expands to enclose writing
      }
      if (maxY.isFinite) {
        strokeH = maxY + 24.0; // Box height expands to enclose writing
      }
    }

    width = max(130.0, max(textW, strokeW));
    height = max(55.0, max(textH, strokeH));

    if (!collapsed) {
      for (final child in children) {
        child.recalculateSize();
      }
    }
  }
}

class MindMapElement extends BoardElement {
  MindMapNode root;
  Size size;
  String selectedNodeId;

  MindMapElement({
    required super.id,
    required super.position,
    required this.root,
    required this.size,
    String? selectedNodeId,
    super.rotation,
    super.scale,
    super.docPage,
  }) : selectedNodeId = selectedNodeId ?? root.id;

  // ---------------------------------------------------------------------------
  // Layout constants (painter bhi INHI ko use kare)
  // ---------------------------------------------------------------------------
  static const double kPad = 30.0; // element ke har side ka padding
  static const double kHGap = 70.0; // parent -> child horizontal gap
  static const double kVGap = 20.0; // siblings ke beech vertical gap

  // Button positions (painter bhi inhi ko use kare)
  static const double kHBtnGap = 16.0; // left/right "+" ka node edge se gap
  static const double kVBtnGap = 16.0; // top "..." / bottom "+" ka gap
  static const double kToggleX =
      40.0; // collapse/expand button: node right + 40 (connector line par)
  static const double kHitR = 20.0; // "+" / "..." buttons ka tap radius
  static const double kToggleHitR =
      16.0; // collapse/expand button ka tap radius

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------
  @override
  Map<String, dynamic> toJson() => {
    'type': 'mindmap',
    'id': id,
    'position': {'dx': position.dx, 'dy': position.dy},
    'rotation': rotation,
    'scale': scale,
    'docPage': docPage,
    'root': root.toJson(),
    'width': size.width,
    'height': size.height,
    'selectedNodeId': selectedNodeId,
  };

  factory MindMapElement.fromJson(Map<String, dynamic> json) {
    final root = MindMapNode.fromJson(json['root']);
    return MindMapElement(
      id: json['id'],
      position: Offset(json['position']['dx'], json['position']['dy']),
      rotation: json['rotation']?.toDouble() ?? 0.0,
      scale: json['scale']?.toDouble() ?? 1.0,
      docPage: json['docPage'],
      root: root,
      size: Size(
        json['width']?.toDouble() ?? 450.0,
        json['height']?.toDouble() ?? 300.0,
      ),
      selectedNodeId: json['selectedNodeId'] ?? root.id,
    );
  }

  /// NOTE: `root` same reference share hota hai. Undo/redo ke liye
  /// snapshot() / restore() use karo (deep copy).
  @override
  MindMapElement copyWith({
    String? id,
    Offset? position,
    double? rotation,
    double? scale,
    int? docPage,
    MindMapNode? root,
    Size? size,
    String? selectedNodeId,
  }) {
    return MindMapElement(
      id: id ?? this.id,
      position: position ?? this.position,
      rotation: rotation ?? this.rotation,
      scale: scale ?? this.scale,
      docPage: docPage ?? this.docPage,
      root: root ?? this.root,
      size: size ?? this.size,
      selectedNodeId: selectedNodeId ?? this.selectedNodeId,
    );
  }

  // ---------------------------------------------------------------------------
  // Undo / Redo snapshots
  // ---------------------------------------------------------------------------

  /// Current state ki deep copy. Har change se PEHLE undoStack me push karo.
  Map<String, dynamic> snapshot() => {
    'root': root.toJson(),
    'selectedNodeId': selectedNodeId,
    'positionDx': position.dx,
    'positionDy': position.dy,
  };

  /// Snapshot wapas load karo.
  void restore(Map<String, dynamic> snap) {
    root = MindMapNode.fromJson(Map<String, dynamic>.from(snap['root']));
    final sel = snap['selectedNodeId'] as String?;
    selectedNodeId = (sel != null && root.findNode(sel) != null)
        ? sel
        : root.id;
    updateLayout();
  }

  // ---------------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------------
  String newId() => DateTime.now().microsecondsSinceEpoch.toString();

  /// Node sizes + positions calculate karta hai, sab nodes ko positive
  /// coordinates me shift karta hai aur element ka size update karta hai.
  ///
  /// [anchorId] wale node ko screen par apni jagah rakha jata hai
  /// (default: root), taaki add/delete par poora map jump na kare.
  void updateLayout({String? anchorId}) {
    final anchorKey = anchorId ?? root.id;
    final oldAnchorOffset =
        root.findNode(anchorKey)?.relativeOffset ?? Offset.zero;

    root.recalculateSize();
    _computeNodeOffsets(root, Offset.zero);

    double minX = 0.0, maxX = root.width;
    double minY = 0.0, maxY = root.height;

    void calcBounds(MindMapNode n) {
      minX = min(minX, n.relativeOffset.dx);
      maxX = max(maxX, n.relativeOffset.dx + n.width);
      minY = min(minY, n.relativeOffset.dy);
      maxY = max(maxY, n.relativeOffset.dy + n.height);
      if (!n.collapsed) {
        for (final c in n.children) {
          calcBounds(c);
        }
      }
    }

    calcBounds(root);

    // Sab nodes ko shift karo taaki koi bhi negative / bounds ke bahar na jaye
    final shift = Offset(kPad - minX, kPad - minY);
    void applyShift(MindMapNode n) {
      n.relativeOffset = n.relativeOffset + shift;
      if (!n.collapsed) {
        for (final c in n.children) {
          applyShift(c);
        }
      }
    }

    applyShift(root);

    size = Size(maxX - minX + kPad * 2, maxY - minY + kPad * 2);

    // Anchor node screen par apni jagah se hile nahi (rotation = 0 maan kar)
    final newAnchor = root.findNode(anchorKey);
    if (newAnchor != null) {
      final delta = newAnchor.relativeOffset - oldAnchorOffset;
      position = position - delta * scale;
    }

    invalidateBounds();
  }

  static double _computeSubtreeHeight(MindMapNode node, double vGap) {
    if (node.collapsed || node.children.isEmpty) {
      return node.height;
    }
    double childrenHeight = 0.0;
    for (int i = 0; i < node.children.length; i++) {
      childrenHeight += _computeSubtreeHeight(node.children[i], vGap);
      if (i < node.children.length - 1) {
        childrenHeight += vGap;
      }
    }
    return max(node.height, childrenHeight);
  }

  static void _computeNodeOffsets(MindMapNode node, Offset parentOffset) {
    node.relativeOffset = parentOffset;

    if (node.collapsed || node.children.isEmpty) return;

    double childrenTotalHeight = 0.0;
    final childSubtreeHeights = <double>[];

    for (int i = 0; i < node.children.length; i++) {
      final h = _computeSubtreeHeight(node.children[i], kVGap);
      childSubtreeHeights.add(h);
      childrenTotalHeight += h;
      if (i < node.children.length - 1) {
        childrenTotalHeight += kVGap;
      }
    }

    final parentCenterY = parentOffset.dy + node.height / 2;
    double currentY = parentCenterY - childrenTotalHeight / 2;
    final childX = parentOffset.dx + node.width + kHGap;

    for (int i = 0; i < node.children.length; i++) {
      final child = node.children[i];
      final childSubtreeH = childSubtreeHeights[i];
      final childY = currentY + (childSubtreeH / 2) - (child.height / 2);

      _computeNodeOffsets(child, Offset(childX, childY));

      currentY += childSubtreeH + kVGap;
    }
  }

  // ---------------------------------------------------------------------------
  // Tree operations
  // ---------------------------------------------------------------------------
  void addChild(String id) {
    final node = root.findNode(id);
    if (node == null) return;
    final child = MindMapNode(id: newId());
    node.children.add(child);
    node.collapsed = false; // collapsed ho toh expand karo
    selectedNodeId = child.id;
    updateLayout();
  }

  void addSibling(String id) {
    if (id == root.id) {
      addChild(id);
      return;
    }
    final parent = root.findParentOf(id);
    if (parent == null) return;
    final i = parent.children.indexWhere((c) => c.id == id);
    final sibling = MindMapNode(
      id: newId(),
      fillColor: const Color(0xFF00BFA5),
    );
    parent.children.insert(i + 1, sibling);
    selectedNodeId = sibling.id;
    updateLayout();
  }

  void addParent(String id) {
    final node = root.findNode(id);
    if (node == null) return;
    final newNode = MindMapNode(id: newId(), children: [node]);
    final parent = root.findParentOf(id);
    if (parent == null) {
      root = newNode; // root ke upar naya root
      selectedNodeId = newNode.id;
      updateLayout(anchorId: node.id); // purana root apni jagah par rahe
      return;
    }
    final i = parent.children.indexWhere((c) => c.id == id);
    parent.children[i] = newNode;
    selectedNodeId = newNode.id;
    updateLayout();
  }

  void deleteNode(String id) {
    final parent = root.findParentOf(id);
    if (parent == null) return; // root delete nahi hota
    parent.children.removeWhere((c) => c.id == id);
    selectedNodeId = parent.id;
    updateLayout();
  }

  void toggleCollapse(String id) {
    final node = root.findNode(id);
    if (node == null) return;
    node.collapsed = !node.collapsed;
    // Collapsed subtree ke andar selected node ho toh parent select karo
    if (node.collapsed && node.id != selectedNodeId) {
      final sel = node.findNode(selectedNodeId);
      if (sel != null) selectedNodeId = node.id;
    }
    updateLayout();
  }

  void updateText(String id, String text) {
    final node = root.findNode(id);
    if (node == null) return;
    node.text = text;
    updateLayout();
  }

  /// Handwriting stroke node me save karo with exact active pen color.
  /// [elementLocalPoints] = element-local coords: (canvasPoint - position) / scale
  void addStroke(
    String nodeId,
    List<Offset> elementLocalPoints, {
    Color? color,
  }) {
    final n = root.findNode(nodeId);
    if (n == null || elementLocalPoints.length < 2) return;
    n.strokes.add(elementLocalPoints.map((p) => p - n.relativeOffset).toList());
    n.strokeColors.add(color ?? n.textColor);
    updateLayout(); // yahi node ko resize karta hai
  }

  // ---------------------------------------------------------------------------
  // Hit testing (painted buttons ke liye)
  // ---------------------------------------------------------------------------

  /// Button ka center (element-local coords). Painter aur hit-test dono yahi use karein.
  Offset btnCenter(MindMapNode n, MindMapAction a) {
    final r = Rect.fromLTWH(
      n.relativeOffset.dx,
      n.relativeOffset.dy,
      n.width,
      n.height,
    );
    switch (a) {
      case MindMapAction.addChild:
        return Offset(r.right + kHBtnGap, r.center.dy);
      case MindMapAction.addParent:
        return Offset(r.left - kHBtnGap, r.center.dy);
      case MindMapAction.addSibling:
        return Offset(r.center.dx, r.bottom + kVBtnGap);
      case MindMapAction.menu:
        return Offset(r.center.dx, r.top - kVBtnGap);
      case MindMapAction.toggle:
        return Offset(r.right + kToggleX, r.center.dy);
    }
  }

  /// [local] = element-local point: (canvasPoint - position) / scale
  MindMapHit? hitTestAction(Offset local) {
    bool near(MindMapNode n, MindMapAction a) {
      final r = a == MindMapAction.toggle ? kToggleHitR : kHitR;
      return (btnCenter(n, a) - local).distance <= r;
    }

    // 1) Selected node ke buttons sabse pehle (Left, Right, Bottom, Delete)
    final sel = root.findNode(selectedNodeId);
    if (sel != null) {
      final actions = <MindMapAction>[
        MindMapAction.menu,
        MindMapAction.addChild,
        MindMapAction.addParent,
        MindMapAction.addSibling,
      ];
      for (final a in actions) {
        if (near(sel, a)) return MindMapHit(a, sel.id);
      }
    }

    // 2) Collapse / expand buttons (sirf visible nodes)
    MindMapHit? found;
    void walk(MindMapNode n) {
      if (found != null) return;
      if (n.children.isNotEmpty && near(n, MindMapAction.toggle)) {
        found = MindMapHit(MindMapAction.toggle, n.id);
        return;
      }
      if (!n.collapsed) {
        for (final c in n.children) {
          walk(c);
        }
      }
    }

    walk(root);
    return found;
  }

  /// Element-local point par kaunsa node hai (visible nodes me se).
  MindMapNode? nodeAt(Offset local, {double inflate = 0}) {
    MindMapNode? found;
    void walk(MindMapNode n) {
      final r = Rect.fromLTWH(
        n.relativeOffset.dx,
        n.relativeOffset.dy,
        n.width,
        n.height,
      ).inflate(inflate);
      if (r.contains(local)) found = n;
      if (!n.collapsed) {
        for (final c in n.children) {
          walk(c);
        }
      }
    }

    walk(root);
    return found;
  }

  /// Button tap execute karo. `menu` ke liye UI (popup) board/widget kholega.
  /// Returns true agar tree badla (taaki caller save/notify kare).
  bool performAction(MindMapHit hit) {
    switch (hit.action) {
      case MindMapAction.addChild:
        addChild(hit.nodeId);
        return true;
      case MindMapAction.addParent:
        addParent(hit.nodeId);
        return true;
      case MindMapAction.addSibling:
        addSibling(hit.nodeId);
        return true;
      case MindMapAction.toggle:
        toggleCollapse(hit.nodeId);
        return true;
      case MindMapAction.menu:
        return false; // popup menu UI side se kholo -> Delete => deleteNode(id)
    }
  }
}
