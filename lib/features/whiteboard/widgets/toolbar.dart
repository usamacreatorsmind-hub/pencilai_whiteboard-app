import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../state/whiteboard_provider.dart';
import '../models/shape_element.dart';
import '../models/image_element.dart';
import '../models/stroke_element.dart';
import '../models/table_element.dart';
import '../models/mind_map_element.dart';
import '../services/document_import_service.dart';
import '../services/ppt_conversion_service.dart';
import 'table_picker_dialog.dart';
import 'periodic_table_dialog.dart';

class WhiteboardToolbar extends StatelessWidget {
  final VoidCallback? onOpenRuler;
  final VoidCallback? onOpenProtractor;
  final VoidCallback? onOpenSetSquare;
  final VoidCallback? onOpenCompass;

  const WhiteboardToolbar({
    super.key,
    this.onOpenRuler,
    this.onOpenProtractor,
    this.onOpenSetSquare,
    this.onOpenCompass,
  });

  void _showColorPicker(BuildContext context, WhiteboardProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick a color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: provider.currentColor,
            onColorChanged: provider.setColor,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showBackgroundColorPicker(
    BuildContext context,
    WhiteboardProvider provider,
  ) {
    Color tempSelectedColor = provider.canvasBackgroundColor;

    final List<Color> themeColors = [
      // Row 1
      const Color(0xFFE2E8F0),
      const Color(0xFFCBD5E1),
      const Color(0xFFD1FAE5),
      const Color(0xFF475569),
      const Color(0xFF1E293B),
      const Color(0xFF0F172A),
      // Row 2
      const Color(0xFF60A5FA),
      const Color(0xFF34D399),
      const Color(0xFFA3E635),
      const Color(0xFFFDE68A),
      const Color(0xFFF472B6),
      const Color(0xFF818CF8),
      // Row 3
      const Color(0xFF2563EB),
      const Color(0xFF059669),
      const Color(0xFF16A34A),
      const Color(0xFFD97706),
      const Color(0xFFDC2626),
      const Color(0xFF1E40AF),
      // Row 4
      const Color(0xFF111827),
      const Color(0xFF1F2937),
      const Color(0xFF111813),
      const Color(0xFF371D10),
      const Color(0xFF3F171B),
      const Color(0xFF0B132B),
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFFF8FAFC),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titlePadding: const EdgeInsets.only(top: 16),
          title: const Center(
            child: Text(
              'Background',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Color',
                  style: TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                // Color Grid (4 rows x 6 columns, compact)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.3,
                  ),
                  itemCount: themeColors.length,
                  itemBuilder: (context, index) {
                    final color = themeColors[index];
                    final isSelected = tempSelectedColor.value == color.value;

                    return GestureDetector(
                      onTap: () =>
                          setDialogState(() => tempSelectedColor = color),
                      child: Container(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF0D9488)
                                : Colors.black12,
                            width: isSelected ? 2.0 : 1.0,
                          ),
                        ),
                        child: isSelected
                            ? const Center(
                                child: Icon(
                                  Icons.check_circle,
                                  size: 16,
                                  color: Color(0xFF0D9488),
                                ),
                              )
                            : null,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF334155),
                side: const BorderSide(color: Color(0xFF94A3B8)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                minimumSize: const Size(70, 36),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                provider.setCanvasBackgroundColor(tempSelectedColor);
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D9488),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 8,
                ),
                minimumSize: const Size(70, 36),
                elevation: 0,
              ),
              child: const Text(
                'OK',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static final GlobalKey _penButtonKey = GlobalKey();

  void _showPenSettings(BuildContext context, WhiteboardProvider provider) {
    final RenderBox? renderBox =
        _penButtonKey.currentContext?.findRenderObject() as RenderBox?;
    Offset position = Offset.zero;
    Size buttonSize = Size.zero;
    if (renderBox != null) {
      position = renderBox.localToGlobal(Offset.zero);
      buttonSize = renderBox.size;
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'PenSettingsOverlay',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, animation, secondaryAnimation) {
        const double dialogWidth = 330.0;
        const double dialogHeight = 265.0;

        final screenSize = MediaQuery.of(context).size;
        double left =
            position.dx + (buttonSize.width / 2) - (dialogWidth / 2) + 35.0;
        left = left.clamp(12.0, screenSize.width - dialogWidth - 12.0);
        double top = position.dy - dialogHeight + 10.0;
        if (top < 12.0) top = 12.0;

        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: Material(
                color: Colors.transparent,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.85, end: 1.0),
                  duration: const Duration(milliseconds: 150),
                  builder: (context, scale, child) {
                    return Transform.scale(
                      scale: scale,
                      alignment: Alignment.bottomCenter,
                      child: child,
                    );
                  },
                  child: Container(
                    width: dialogWidth,
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFCBD5E1),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 16,
                          spreadRadius: 1,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: StatefulBuilder(
                      builder: (context, setDialogState) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Dual-Nib Top TabBar
                            Container(
                              height: 34,
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _PenProfileTab(
                                      title: 'Thin Pen',
                                      subtitle:
                                          '${provider.thinStrokeWidth.toInt()}px',
                                      color: provider.thinColor,
                                      isSelected:
                                          provider.activePenProfile ==
                                          PenProfile.thin,
                                      onTap: () {
                                        provider.setActivePenProfile(
                                          PenProfile.thin,
                                        );
                                        setDialogState(() {});
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: _PenProfileTab(
                                      title: 'Thick Pen',
                                      subtitle:
                                          '${provider.thickStrokeWidth.toInt()}px',
                                      color: provider.thickColor,
                                      isSelected:
                                          provider.activePenProfile ==
                                          PenProfile.thick,
                                      onTap: () {
                                        provider.setActivePenProfile(
                                          PenProfile.thick,
                                        );
                                        setDialogState(() {});
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),

                            // 2. Compact Pen Style Selector
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _PenTypeOption(
                                  label: 'Pen',
                                  icon: LucideIcons.pencil,
                                  color: Colors.blue,
                                  isSelected:
                                      provider.currentPenType == PenType.pen,
                                  onTap: () {
                                    provider.setPenType(PenType.pen);
                                    setDialogState(() {});
                                  },
                                ),
                                _PenTypeOption(
                                  label: 'Fountain',
                                  icon: LucideIcons.penTool,
                                  color: Colors.purple,
                                  isSelected:
                                      provider.currentPenType ==
                                      PenType.fountainPen,
                                  onTap: () {
                                    provider.setPenType(PenType.fountainPen);
                                    setDialogState(() {});
                                  },
                                ),
                                _PenTypeOption(
                                  label: 'Brush',
                                  icon: LucideIcons.paintbrush,
                                  color: Colors.orange,
                                  isSelected:
                                      provider.currentPenType == PenType.brush,
                                  onTap: () {
                                    provider.setPenType(PenType.brush);
                                    setDialogState(() {});
                                  },
                                ),
                                _PenTypeOption(
                                  label: 'Marker',
                                  icon: LucideIcons.highlighter,
                                  color: Colors.green,
                                  isSelected:
                                      provider.currentPenType == PenType.marker,
                                  onTap: () {
                                    provider.setPenType(PenType.marker);
                                    setDialogState(() {});
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // 3. Compact Thickness Slider & Preview
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Thickness',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: Color(0xFF334155),
                                  ),
                                ),
                                Text(
                                  '${provider.strokeWidth.toInt()}px',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: Colors.blue,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(
                              height: 26,
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: provider.currentColor,
                                  thumbColor: provider.currentColor,
                                  overlayColor: provider.currentColor
                                      .withValues(alpha: 0.2),
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                ),
                                child: Slider(
                                  value: provider.strokeWidth.clamp(
                                    provider.minStrokeWidth,
                                    provider.maxStrokeWidth,
                                  ),
                                  min: provider.minStrokeWidth,
                                  max: provider.maxStrokeWidth,
                                  onChanged: (value) {
                                    provider.setStrokeWidth(value);
                                    setDialogState(() {});
                                  },
                                ),
                              ),
                            ),
                            Container(
                              height: 18,
                              width: double.infinity,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Container(
                                height: provider.strokeWidth.clamp(1.0, 14.0),
                                width: 100,
                                decoration: BoxDecoration(
                                  color:
                                      provider.currentColor.value ==
                                          Colors.white.value
                                      ? const Color(0xFF1E293B)
                                      : provider.currentColor,
                                  borderRadius: BorderRadius.circular(
                                    provider.strokeWidth / 2,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // 4. Compact Colors Grid
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                ...[
                                  Colors.white,
                                  Colors.black,
                                  Colors.red,
                                  Colors.yellow,
                                  Colors.orange,
                                  Colors.brown,
                                  Colors.lightGreen,
                                  Colors.green,
                                  Colors.lightBlue,
                                  Colors.blue,
                                  Colors.purple,
                                ].map(
                                  (color) => _ColorButton(
                                    color: color,
                                    isSelected:
                                        provider.currentColor.value ==
                                        color.value,
                                    onTap: () {
                                      provider.setColor(color);
                                      setDialogState(() {});
                                    },
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () =>
                                      _showColorPicker(context, provider),
                                  child: Container(
                                    width: 25,
                                    height: 25,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFFCBD5E1),
                                      ),
                                      gradient: const LinearGradient(
                                        colors: [
                                          Colors.red,
                                          Colors.green,
                                          Colors.blue,
                                          Colors.yellow,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.colorize,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static final GlobalKey _toolboxButtonKey = GlobalKey();

  void _openPeriodicTable(BuildContext context, WhiteboardProvider provider) {
    PeriodicTableDialog.show(context, provider);
  }

  void _createMindMap(BuildContext context, WhiteboardProvider provider) {
    final screenSize =
        MediaQuery.maybeOf(context)?.size ?? const Size(1280, 720);
    final centerPos = provider.screenToCanvas(
      Offset(
        max(50.0, screenSize.width / 2 - 200),
        max(50.0, screenSize.height / 2 - 120),
      ),
    );

    final rootNode = MindMapNode(
      id: const Uuid().v4(),
      text: '',
      fillColor: const Color(0xFF00BFA5),
      children: [
        MindMapNode(
          id: const Uuid().v4(),
          text: '',
          fillColor: const Color(0xFF00BFA5),
        ),
        MindMapNode(
          id: const Uuid().v4(),
          text: '',
          fillColor: const Color(0xFF00BFA5),
        ),
        MindMapNode(
          id: const Uuid().v4(),
          text: '',
          fillColor: const Color(0xFF00BFA5),
        ),
      ],
    );

    final mindMapElement = MindMapElement(
      id: const Uuid().v4(),
      position: centerPos,
      root: rootNode,
      size: const Size(420, 260),
    );

    mindMapElement.updateLayout();

    provider.addElement(mindMapElement);
    provider.clearSelection();
    provider.setTool(WhiteboardTool.pen);
  }

  void _openTablePickerDialog(
    BuildContext context,
    WhiteboardProvider provider,
  ) {
    final screenSize =
        MediaQuery.maybeOf(context)?.size ?? const Size(1280, 720);

    showDialog(
      context: context,
      builder: (dialogCtx) => TablePickerDialog(
        onTableSelected: (rows, cols) {
          const cellW = 90.0;
          const cellH = 45.0;
          final tblW = cols * cellW;
          final tblH = rows * cellH;

          final posX = (screenSize.width - tblW) / 2;
          final posY = (screenSize.height - tblH) / 2;

          final tableElement = TableElement(
            id: const Uuid().v4(),
            position: provider.screenToCanvas(
              Offset(
                posX.clamp(20.0, max(20.0, screenSize.width - tblW)),
                posY.clamp(20.0, max(20.0, screenSize.height - tblH)),
              ),
            ),
            rows: rows,
            cols: cols,
            size: Size(tblW, tblH),
            color: provider.currentColor == Colors.white
                ? const Color(0xFF1E293B)
                : provider.currentColor,
            strokeWidth: provider.strokeWidth < 2.0
                ? 2.0
                : provider.strokeWidth,
          );

          provider.addElement(tableElement);
          provider.selectElement(tableElement.id);
          provider.setTool(WhiteboardTool.select);
        },
      ),
    );
  }

  void _showRulerSubMenu(BuildContext context, WhiteboardProvider provider) {
    final RenderBox? renderBox =
        _toolboxButtonKey.currentContext?.findRenderObject() as RenderBox?;
    Offset position = Offset.zero;
    Size buttonSize = Size.zero;
    if (renderBox != null) {
      position = renderBox.localToGlobal(Offset.zero);
      buttonSize = renderBox.size;
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'RulerSubMenu',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, animation, secondaryAnimation) {
        const double dialogWidth = 260.0;
        const double dialogHeight = 55.0;

        double left = position.dx + (buttonSize.width / 2) - (dialogWidth / 2);
        final screenSize = MediaQuery.of(context).size;
        left = left.clamp(12.0, screenSize.width - dialogWidth - 12.0);
        double top = position.dy - dialogHeight - 18.0;

        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: dialogWidth,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF64748B),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ToolboxOptionItem(
                        icon: LucideIcons.ruler,
                        label: 'Scale',
                        onTap: () {
                          Navigator.pop(context);
                          onOpenRuler?.call();
                        },
                      ),
                      _ToolboxOptionItem(
                        icon: LucideIcons.triangle,
                        label: 'Protractor',
                        onTap: () {
                          Navigator.pop(context);
                          onOpenProtractor?.call();
                        },
                      ),
                      _ToolboxOptionItem(
                        icon: LucideIcons.square,
                        label: 'Set Square',
                        onTap: () {
                          Navigator.pop(context);
                          onOpenSetSquare?.call();
                        },
                      ),
                      _ToolboxOptionItem(
                        icon: LucideIcons.compass,
                        label: 'Compass',
                        onTap: () {
                          Navigator.pop(context);
                          onOpenCompass?.call();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        );
      },
    );
  }

  void _showToolboxDialog(BuildContext context, WhiteboardProvider provider) {
    final RenderBox? renderBox =
        _toolboxButtonKey.currentContext?.findRenderObject() as RenderBox?;
    Offset position = Offset.zero;
    Size buttonSize = Size.zero;
    if (renderBox != null) {
      position = renderBox.localToGlobal(Offset.zero);
      buttonSize = renderBox.size;
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'ToolboxDialog',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, animation, secondaryAnimation) {
        const double dialogWidth = 290.0;
        const double dialogHeight = 52.0;

        double left = position.dx + (buttonSize.width / 2) - (dialogWidth / 2);
        final screenSize = MediaQuery.of(context).size;
        left = left.clamp(12.0, screenSize.width - dialogWidth - 12.0);
        double top = position.dy - dialogHeight - 18.0;

        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: dialogWidth,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFF64748B),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ToolboxOptionItem(
                        icon: LucideIcons.network,
                        label: 'MindMap',
                        onTap: () {
                          Navigator.pop(context);
                          _createMindMap(context, provider);
                        },
                      ),
                      _ToolboxOptionItem(
                        icon: LucideIcons.atom,
                        label: 'PeriodicTable',
                        onTap: () {
                          Navigator.pop(context);
                          _openPeriodicTable(context, provider);
                        },
                      ),
                      _ToolboxOptionItem(
                        icon: LucideIcons.ruler,
                        label: 'Ruler',
                        onTap: () {
                          Navigator.pop(context);
                          _showRulerSubMenu(context, provider);
                        },
                      ),
                      _ToolboxOptionItem(
                        icon: LucideIcons.table,
                        label: 'Table',
                        onTap: () {
                          Navigator.pop(context);
                          _openTablePickerDialog(context, provider);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        );
      },
    );
  }

  static final GlobalKey _eraserButtonKey = GlobalKey();

  void _showEraserSettings(BuildContext context, WhiteboardProvider provider) {
    final RenderBox? renderBox =
        _eraserButtonKey.currentContext?.findRenderObject() as RenderBox?;
    Offset position = Offset.zero;
    Size buttonSize = Size.zero;
    if (renderBox != null) {
      position = renderBox.localToGlobal(Offset.zero);
      buttonSize = renderBox.size;
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'EraserSettings',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, animation, secondaryAnimation) {
        const double dialogWidth = 200.0; // was 260
        const double dialogHeight = 118.0; // was 180

        double left = position.dx + (buttonSize.width / 2) - (dialogWidth / 2);
        final screenSize = MediaQuery.of(context).size;
        left = left.clamp(12.0, screenSize.width - dialogWidth - 12.0);
        double top = position.dy - dialogHeight - 8.0;

        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: Material(
                color: Colors.transparent,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.8, end: 1.0),
                  duration: const Duration(milliseconds: 150),
                  builder: (context, scale, child) {
                    return Transform.scale(
                      scale: scale,
                      alignment: Alignment.bottomCenter,
                      child: child,
                    );
                  },
                  child: Container(
                    width: dialogWidth,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFCBD5E1),
                        width: 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 12,
                          spreadRadius: 1,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: StatefulBuilder(
                      builder: (context, setDialogState) => Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Eraser Size',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                              Text(
                                '${provider.eraserSize.toInt()}px',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Color(0xFFF97316),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(
                            height: 28,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: const Color(0xFFF97316),
                                thumbColor: const Color(0xFFF97316),
                                overlayColor: const Color(
                                  0xFFF97316,
                                ).withValues(alpha: 0.2),
                                trackHeight: 2.5,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 7,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 14,
                                ),
                              ),
                              child: Slider(
                                value: provider.eraserSize.clamp(
                                  provider.minEraserSize,
                                  provider.maxEraserSize,
                                ),
                                min: provider.minEraserSize,
                                max: provider.maxEraserSize,
                                onChanged: (value) {
                                  provider.setEraserSize(value);
                                  setDialogState(() {});
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              // Compact realtime preview
                              Container(
                                height: 44,
                                width: 64,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Container(
                                  width: (provider.eraserSize * 0.6).clamp(
                                    10.0,
                                    32.0,
                                  ),
                                  height: (provider.eraserSize * 0.6).clamp(
                                    10.0,
                                    32.0,
                                  ),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFFFFFFFF),
                                        Color(0xFFF1F5F9),
                                      ],
                                    ),
                                    border: Border.all(
                                      color: const Color(0xFF94A3B8),
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.15,
                                        ),
                                        blurRadius: 5,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Icon(
                                      LucideIcons.eraser,
                                      color: const Color(0xFF64748B),
                                      size: (provider.eraserSize * 0.3).clamp(
                                        8.0,
                                        16.0,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 0,
                                  ),
                                  minimumSize: const Size(44, 26),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  'Done',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFF97316),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showShapePicker(BuildContext context, WhiteboardProvider provider) {
    showDialog(
      context: context,
      builder: (context) => Align(
        alignment: Alignment.bottomCenter,
        child: DefaultTabController(
          length: 2,
          child: AlertDialog(
            // bottom value se control karo ki kitna neeche chahiye
            insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            contentPadding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            titlePadding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            title: const TabBar(
              indicatorColor: Color(0xFF38BDF8),
              labelColor: Color(0xFF38BDF8),
              unselectedLabelColor: Colors.grey,
              labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              tabs: [
                Tab(
                  text: '2D Shapes',
                  icon: Icon(LucideIcons.shapes, size: 14),
                ),
                Tab(text: '3D Shapes', icon: Icon(LucideIcons.box, size: 14)),
              ],
            ),
            content: SizedBox(
              width: 290,
              height: 180,
              child: TabBarView(
                children: [
                  // 2D Shapes Tab
                  GridView.count(
                    crossAxisCount: 4,
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 2,
                    childAspectRatio: 1.2,
                    children: [
                      _ShapeTile(
                        name: 'Line',
                        type: ShapeType.line,
                        icon: LucideIcons.minus,
                        provider: provider,
                      ),
                      _ShapeTile(
                        name: 'Rect',
                        type: ShapeType.rectangle,
                        icon: LucideIcons.square,
                        provider: provider,
                      ),
                      _ShapeTile(
                        name: 'Circle',
                        type: ShapeType.circle,
                        icon: LucideIcons.circle,
                        provider: provider,
                      ),
                      _ShapeTile(
                        name: 'Arrow',
                        type: ShapeType.arrow,
                        icon: LucideIcons.moveRight,
                        provider: provider,
                      ),
                      _ShapeTile(
                        name: 'Triangle',
                        type: ShapeType.triangle,
                        icon: LucideIcons.triangle,
                        provider: provider,
                      ),
                      _ShapeTile(
                        name: 'Star',
                        type: ShapeType.star,
                        icon: LucideIcons.star,
                        provider: provider,
                      ),
                      _ShapeTile(
                        name: 'Diamond',
                        type: ShapeType.diamond,
                        icon: LucideIcons.gem,
                        provider: provider,
                      ),
                      _ShapeTile(
                        name: 'Pentagon',
                        type: ShapeType.pentagon,
                        icon: LucideIcons.pentagon,
                        provider: provider,
                      ),
                      _ShapeTile(
                        name: 'Hexagon',
                        type: ShapeType.hexagon,
                        icon: LucideIcons.hexagon,
                        provider: provider,
                      ),
                      _ShapeTile(
                        name: 'Right Tri',
                        type: ShapeType.rightTriangle,
                        icon: LucideIcons.triangleRight,
                        provider: provider,
                      ),
                      _ShapeTile(
                        name: 'Parallelogram',
                        type: ShapeType.parallelogram,
                        icon: LucideIcons.boxSelect,
                        provider: provider,
                      ),
                      _ShapeTile(
                        name: 'Heart',
                        type: ShapeType.heart,
                        icon: LucideIcons.heart,
                        provider: provider,
                      ),
                    ],
                  ),

                  // 3D Shapes Tab
                  GridView.count(
                    crossAxisCount: 3,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    childAspectRatio: 1.3,
                    children: [
                      _ShapeTile(
                        name: 'Cube 3D',
                        type: ShapeType.cube3d,
                        icon: LucideIcons.box,
                        provider: provider,
                      ),
                      _ShapeTile(
                        name: 'Cylinder 3D',
                        type: ShapeType.cylinder3d,
                        icon: LucideIcons.cylinder,
                        provider: provider,
                      ),
                      _ShapeTile(
                        name: 'Cone 3D',
                        type: ShapeType.cone3d,
                        icon: LucideIcons.cone,
                        provider: provider,
                      ),
                      _ShapeTile(
                        name: 'Pyramid 3D',
                        type: ShapeType.pyramid3d,
                        icon: LucideIcons.pyramid,
                        provider: provider,
                      ),
                      _ShapeTile(
                        name: 'Sphere 3D',
                        type: ShapeType.sphere3d,
                        icon: LucideIcons.globe,
                        provider: provider,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showClearConfirmation(
    BuildContext context,
    WhiteboardProvider provider,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Clear All?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will erase everything on the current page.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              provider.clearCurrentPage();
              Navigator.pop(context);
            },
            child: const Text('Clear All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage(
    BuildContext context,
    WhiteboardProvider provider,
  ) async {
    final screenSize = MediaQuery.of(context).size;
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      try {
        final bytes = await File(image.path).readAsBytes();
        final decodedImage = await decodeImageFromList(bytes);
        double natWidth = decodedImage.width.toDouble();
        double natHeight = decodedImage.height.toDouble();

        double aspectRatio = natWidth > 0 && natHeight > 0
            ? natWidth / natHeight
            : (screenSize.width / screenSize.height);

        // Edge-to-Edge from top, left, and right
        double width = screenSize.width;
        double height = width / aspectRatio;

        provider.addElement(
          ImageElement(
            id: const Uuid().v4(),
            position: provider.screenToCanvas(Offset.zero),
            imageUrl: image.path,
            size: Size(width, height),
          ),
        );
      } catch (e) {
        provider.addElement(
          ImageElement(
            id: const Uuid().v4(),
            position: provider.screenToCanvas(Offset.zero),
            imageUrl: image.path,
            size: Size(screenSize.width, screenSize.height - 70),
          ),
        );
      }
    }
  }

  Future<void> _pickDocument(
    BuildContext context,
    WhiteboardProvider provider,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final screenSize = MediaQuery.of(context).size;

    // Pre-warm Cloud Run server concurrently to eliminate cold-start delay
    PptConversionService.preWarmServer();

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'ppt', 'pptx', 'doc', 'docx', 'xls', 'xlsx'],
      );

      if (result != null && result.files.single.path != null) {
        final file = result.files.single;
        final statusNotifier = ValueNotifier<String>("Preparing document...");
        final progressNotifier = ValueNotifier<double>(0.0);

        // Show live progress dialog during slide extraction
        if (context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => PopScope(
              canPop: false,
              child: AlertDialog(
                backgroundColor: const Color(0xFF1E1E1E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                content: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.blueAccent),
                      const SizedBox(height: 20),
                      ValueListenableBuilder<String>(
                        valueListenable: statusNotifier,
                        builder: (context, status, _) => Text(
                          status,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ValueListenableBuilder<double>(
                        valueListenable: progressNotifier,
                        builder: (context, progress, _) =>
                            LinearProgressIndicator(
                              value: progress > 0 ? progress : null,
                              backgroundColor: Colors.white12,
                              color: Colors.blueAccent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        try {
          final importService = DocumentImportService();
          final pages = await importService.importDocumentToBoardPages(
            file: File(file.path!),
            fileName: file.name,
            targetScreenSize: screenSize,
            bottomToolbarHeight: 65.0,
            onProgress: (current, total, status) {
              statusNotifier.value = status;
              progressNotifier.value = current / total.toDouble();
            },
          );

          if (context.mounted) {
            Navigator.of(
              context,
              rootNavigator: true,
            ).pop(); // Close progress dialog
          }

          if (pages.isNotEmpty) {
            provider.importPages(pages);
          }
        } catch (e) {
          if (context.mounted) {
            Navigator.of(
              context,
              rootNavigator: true,
            ).pop(); // Close progress dialog
          }
          scaffoldMessenger.showSnackBar(
            SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text('Failed to import ${file.name}: $e'),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error picking document: $e");
    }
  }

  IconData _getShapeIcon(ShapeType type) {
    switch (type) {
      case ShapeType.line:
        return LucideIcons.minus;
      case ShapeType.rectangle:
        return LucideIcons.square;
      case ShapeType.circle:
        return LucideIcons.circle;
      case ShapeType.arrow:
        return LucideIcons.moveRight;
      case ShapeType.triangle:
      case ShapeType.rightTriangle:
        return LucideIcons.triangle;
      case ShapeType.star:
        return LucideIcons.star;
      case ShapeType.diamond:
        return LucideIcons.gem;
      case ShapeType.pentagon:
      case ShapeType.hexagon:
        return LucideIcons.hexagon;
      case ShapeType.parallelogram:
      case ShapeType.trapezoid:
        return LucideIcons.boxSelect;
      case ShapeType.heart:
        return LucideIcons.heart;
      case ShapeType.cube3d:
        return LucideIcons.box;
      case ShapeType.cylinder3d:
        return LucideIcons.cylinder;
      case ShapeType.cone3d:
        return LucideIcons.cone;
      case ShapeType.pyramid3d:
        return LucideIcons.pyramid;
      case ShapeType.sphere3d:
        return LucideIcons.globe;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<WhiteboardProvider>(context);
    final isLargeScreen = MediaQuery.of(context).size.width > 1200;
    final iconSize = isLargeScreen ? 20.0 : 17.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(
          0xFFE2E8F0,
        ), // Light frosted container matching image
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF64748B), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drawing Tools Group
            _ToolButton(
              key: _penButtonKey,
              icon: LucideIcons.pencil,
              label: 'Pen',
              isActive: provider.currentTool == WhiteboardTool.pen,
              iconSize: iconSize,
              onTap: () {
                if (provider.currentTool == WhiteboardTool.pen) {
                  _showPenSettings(context, provider);
                } else {
                  provider.setTool(WhiteboardTool.pen);
                }
              },
              onLongPress: () => _showPenSettings(context, provider),
            ),
            _ToolButton(
              key: _eraserButtonKey,
              icon: LucideIcons.eraser,
              label: 'Eraser',
              isActive: provider.currentTool == WhiteboardTool.eraser,
              iconSize: iconSize,
              onTap: () {
                if (provider.currentTool == WhiteboardTool.eraser) {
                  _showEraserSettings(context, provider);
                } else {
                  provider.setTool(WhiteboardTool.eraser);
                }
              },
              onLongPress: () => _showEraserSettings(context, provider),
            ),
            _ToolButton(
              icon: LucideIcons.trash2,
              label: 'Clear All',
              isActive: false,
              iconSize: iconSize,
              onTap: () => _showClearConfirmation(context, provider),
            ),
            _ToolButton(
              icon: LucideIcons.mousePointer2,
              label: 'Select',
              isActive: provider.currentTool == WhiteboardTool.select,
              iconSize: iconSize,
              onTap: () => provider.setTool(WhiteboardTool.select),
            ),
            _ToolButton(
              icon: LucideIcons.hand,
              label: 'Preview',
              isActive: provider.currentTool == WhiteboardTool.preview,
              iconSize: iconSize,
              onTap: () => provider.setTool(WhiteboardTool.preview),
            ),
            const VerticalDivider(
              color: Color(0xFFCBD5E1),
              width: 8,
              indent: 4,
              endIndent: 4,
            ),

            // Shape & Extras Group
            _ToolButton(
              icon: provider.currentTool == WhiteboardTool.shape
                  ? _getShapeIcon(provider.currentShapeType)
                  : LucideIcons.shapes,
              label: 'Shape',
              isActive: provider.currentTool == WhiteboardTool.shape,
              iconSize: iconSize,
              onTap: () => _showShapePicker(context, provider),
            ),
            _ToolButton(
              icon: LucideIcons.image,
              label: 'Image',
              isActive: false,
              iconSize: iconSize,
              onTap: () => _pickImage(context, provider),
            ),
            _ToolButton(
              icon: LucideIcons.fileText,
              label: 'PPT/PDF',
              isActive: false,
              iconSize: iconSize,
              onTap: () => _pickDocument(context, provider),
            ),
            _ToolButton(
              icon: LucideIcons.palette,
              label: 'Background',
              isActive: false,
              iconSize: iconSize,
              onTap: () => _showBackgroundColorPicker(context, provider),
            ),
            _ToolButton(
              key: _toolboxButtonKey,
              icon: LucideIcons.briefcase,
              label: 'Toolbox',
              isActive: false,
              iconSize: iconSize,
              onTap: () => _showToolboxDialog(context, provider),
            ),
            const VerticalDivider(
              color: Color(0xFFCBD5E1),
              width: 8,
              indent: 4,
              endIndent: 4,
            ),

            // History Group
            _ToolButton(
              icon: LucideIcons.undo2,
              label: 'Undo',
              isActive: false,
              iconSize: iconSize,
              onTap: provider.canUndo ? provider.undo : null,
            ),
            _ToolButton(
              icon: LucideIcons.redo2,
              label: 'Redo',
              isActive: false,
              iconSize: iconSize,
              onTap: provider.canRedo ? provider.redo : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final double iconSize;

  const _ToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.iconSize,
    this.color,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = onTap != null;

    Color defaultIconColor =
        color ??
        switch (label) {
          'Pen' => const Color(0xFF0EA5E9),
          'Eraser' => const Color(0xFFF97316),
          'Clear All' => const Color(0xFFEF4444),
          'Select' => const Color(0xFF06B6D4),
          'Shape' => const Color(0xFFA855F7),
          'Image' => const Color(0xFF22C55E),
          'PPT/PDF' => const Color(0xFFF59E0B),
          'Background' => const Color(0xFF10B981),
          'Tools' => const Color(0xFF38BDF8),
          'Undo' =>
            isEnabled ? const Color(0xFF334155) : const Color(0xFF94A3B8),
          'Redo' =>
            isEnabled ? const Color(0xFF334155) : const Color(0xFF94A3B8),
          _ => const Color(0xFF334155),
        };

    final iconColor = isActive ? const Color(0xFF38BDF8) : defaultIconColor;
    final textColor = isActive
        ? Colors.white
        : (isEnabled ? const Color(0xFF1E293B) : const Color(0xFF94A3B8));

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF0F172A) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isActive
              ? Border.all(color: const Color(0xFF38BDF8), width: 1.2)
              : null,
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.5),
                    blurRadius: 6,
                    spreadRadius: 0.5,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize, color: iconColor),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 8.5,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorButton extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorButton({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isWhite = color.value == Colors.white.value;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 25,
        height: 25,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? Colors.blue
                : (isWhite ? Colors.grey[400]! : Colors.grey[300]!),
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 3,
            ),
          ],
        ),
        child: isSelected
            ? Icon(
                Icons.check,
                color: isWhite ? Colors.black : Colors.white,
                size: 14,
              )
            : null,
      ),
    );
  }
}

class _PenTypeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _PenTypeOption({
    required this.label,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : Colors.grey[100],
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? color : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PenProfileTab extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _PenProfileTab({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: color.value == Colors.white.value
                    ? const Color(0xFF64748B)
                    : color,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              title,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 11,
                color: isSelected
                    ? const Color(0xFF0F172A)
                    : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.blue : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShapeTile extends StatelessWidget {
  final String name;
  final ShapeType type;
  final IconData icon;
  final WhiteboardProvider provider;

  const _ShapeTile({
    required this.name,
    required this.type,
    required this.icon,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected =
        provider.currentTool == WhiteboardTool.shape &&
        provider.currentShapeType == type;
    return InkWell(
      onTap: () {
        provider.setShapeType(type);
        provider.setTool(WhiteboardTool.shape);
        Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF38BDF8).withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFF38BDF8) : Colors.white70,
              size: 16,
            ),
            const SizedBox(height: 2),
            Text(
              name,
              style: TextStyle(
                color: isSelected ? const Color(0xFF38BDF8) : Colors.white60,
                fontSize: 9,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolboxOptionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToolboxOptionItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF0F172A)),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
