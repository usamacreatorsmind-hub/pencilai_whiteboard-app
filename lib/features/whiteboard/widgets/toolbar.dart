import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../state/whiteboard_provider.dart';
import '../models/board_page.dart';
import '../models/shape_element.dart';
import '../models/image_element.dart';
import '../models/document_element.dart';
import '../models/stroke_element.dart';
import '../services/document_import_service.dart';

class WhiteboardToolbar extends StatelessWidget {
  const WhiteboardToolbar({super.key});

  void _showColorPicker(BuildContext context, WhiteboardProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick a color'),
        content: SingleChildScrollView(
          child: ColorPicker(pickerColor: provider.currentColor, onColorChanged: provider.setColor),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))],
      ),
    );
  }

  void _showBackgroundColorPicker(BuildContext context, WhiteboardProvider provider) {
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          titlePadding: const EdgeInsets.only(top: 16),
          title: const Center(
            child: Text(
              'Background',
              style: TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.w600),
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
                  style: TextStyle(color: Color(0xFF334155), fontSize: 12, fontWeight: FontWeight.bold),
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
                      onTap: () => setDialogState(() => tempSelectedColor = color),
                      child: Container(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: isSelected ? const Color(0xFF0D9488) : Colors.black12, width: isSelected ? 2.0 : 1.0),
                        ),
                        child: isSelected ? const Center(child: Icon(Icons.check_circle, size: 16, color: Color(0xFF0D9488))) : null,
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                minimumSize: const Size(70, 36),
              ),
              child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                minimumSize: const Size(70, 36),
                elevation: 0,
              ),
              child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  void _showPenSettings(BuildContext context, WhiteboardProvider provider) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          contentPadding: EdgeInsets.zero,
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Container(
            width: 340,
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pen Style', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                // Pen Type Selector (Compact Row)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _PenTypeOption(
                      label: 'Pen',
                      icon: LucideIcons.pencil,
                      color: Colors.blue,
                      isSelected: provider.currentPenType == PenType.pen,
                      onTap: () {
                        provider.setPenType(PenType.pen);
                        setDialogState(() {});
                      },
                    ),
                    _PenTypeOption(
                      label: 'Fountain',
                      icon: LucideIcons.penTool,
                      color: Colors.purple,
                      isSelected: provider.currentPenType == PenType.fountainPen,
                      onTap: () {
                        provider.setPenType(PenType.fountainPen);
                        setDialogState(() {});
                      },
                    ),
                    _PenTypeOption(
                      label: 'Brush',
                      icon: LucideIcons.paintbrush,
                      color: Colors.orange,
                      isSelected: provider.currentPenType == PenType.brush,
                      onTap: () {
                        provider.setPenType(PenType.brush);
                        setDialogState(() {});
                      },
                    ),
                    _PenTypeOption(
                      label: 'Marker',
                      icon: LucideIcons.highlighter,
                      color: Colors.green,
                      isSelected: provider.currentPenType == PenType.marker,
                      onTap: () {
                        provider.setPenType(PenType.marker);
                        setDialogState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Thickness', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(
                      '${provider.strokeWidth.toInt()}px',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // Size Slider
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: provider.currentColor,
                    thumbColor: provider.currentColor,
                    overlayColor: provider.currentColor.withOpacity(0.2),
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: provider.strokeWidth,
                    min: 1,
                    max: 40,
                    onChanged: (value) {
                      provider.setStrokeWidth(value);
                      setDialogState(() {});
                    },
                  ),
                ),
                // Realtime Thickness Preview
                Container(
                  height: 36,
                  width: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Container(
                    height: provider.strokeWidth.clamp(1.0, 28.0),
                    width: 140,
                    decoration: BoxDecoration(
                      color: provider.currentColor.value == Colors.white.value ? Colors.grey[800] : provider.currentColor,
                      borderRadius: BorderRadius.circular(provider.strokeWidth / 2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Colors', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 10),
                // Color Grid (Compact)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
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
                        isSelected: provider.currentColor.value == color.value,
                        onTap: () {
                          provider.setColor(color);
                          setDialogState(() {});
                        },
                      ),
                    ),
                    // Custom Color Picker Button
                    GestureDetector(
                      onTap: () => _showColorPicker(context, provider),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                          gradient: const LinearGradient(
                            colors: [Colors.red, Colors.green, Colors.blue, Colors.yellow],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Icon(Icons.colorize, size: 18, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showShapePicker(BuildContext context, WhiteboardProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Select Shape', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 250,
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              _ShapeGridButton(
                icon: LucideIcons.minus,
                isSelected: provider.currentTool == WhiteboardTool.shape && provider.currentShapeType == ShapeType.line,
                onTap: () {
                  provider.setShapeType(ShapeType.line);
                  provider.setTool(WhiteboardTool.shape);
                  Navigator.pop(context);
                },
              ),
              _ShapeGridButton(
                icon: LucideIcons.square,
                isSelected: provider.currentTool == WhiteboardTool.shape && provider.currentShapeType == ShapeType.rectangle,
                onTap: () {
                  provider.setShapeType(ShapeType.rectangle);
                  provider.setTool(WhiteboardTool.shape);
                  Navigator.pop(context);
                },
              ),
              _ShapeGridButton(
                icon: LucideIcons.circle,
                isSelected: provider.currentTool == WhiteboardTool.shape && provider.currentShapeType == ShapeType.circle,
                onTap: () {
                  provider.setShapeType(ShapeType.circle);
                  provider.setTool(WhiteboardTool.shape);
                  Navigator.pop(context);
                },
              ),
              _ShapeGridButton(
                icon: LucideIcons.moveRight,
                isSelected: provider.currentTool == WhiteboardTool.shape && provider.currentShapeType == ShapeType.arrow,
                onTap: () {
                  provider.setShapeType(ShapeType.arrow);
                  provider.setTool(WhiteboardTool.shape);
                  Navigator.pop(context);
                },
              ),
              _ShapeGridButton(
                icon: LucideIcons.triangle,
                isSelected: provider.currentTool == WhiteboardTool.shape && provider.currentShapeType == ShapeType.triangle,
                onTap: () {
                  provider.setShapeType(ShapeType.triangle);
                  provider.setTool(WhiteboardTool.shape);
                  Navigator.pop(context);
                },
              ),
              _ShapeGridButton(
                icon: LucideIcons.star,
                isSelected: provider.currentTool == WhiteboardTool.shape && provider.currentShapeType == ShapeType.star,
                onTap: () {
                  provider.setShapeType(ShapeType.star);
                  provider.setTool(WhiteboardTool.shape);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showClearConfirmation(BuildContext context, WhiteboardProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Clear All?', style: TextStyle(color: Colors.white)),
        content: const Text('This will erase everything on the current page.', style: TextStyle(color: Colors.grey)),
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

  Future<void> _pickImage(BuildContext context, WhiteboardProvider provider) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      provider.addElement(
        ImageElement(id: const Uuid().v4(), position: const Offset(200, 200), imageUrl: image.path, size: const Size(400, 300)),
      );
    }
  }

  Future<void> _pickDocument(BuildContext context, WhiteboardProvider provider) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final screenSize = MediaQuery.of(context).size;
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ValueListenableBuilder<double>(
                        valueListenable: progressNotifier,
                        builder: (context, progress, _) => LinearProgressIndicator(
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
            Navigator.of(context, rootNavigator: true).pop(); // Close progress dialog
          }

          if (pages.isNotEmpty) {
            provider.importPages(pages);
          }
        } catch (e) {
          if (context.mounted) {
            Navigator.of(context, rootNavigator: true).pop(); // Close progress dialog
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
        return LucideIcons.triangle;
      case ShapeType.star:
        return LucideIcons.star;
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
        color: const Color(0xFFE2E8F0), // Light frosted container matching image
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF64748B), width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drawing Tools Group
            _ToolButton(
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
              icon: LucideIcons.eraser,
              label: 'Eraser',
              isActive: provider.currentTool == WhiteboardTool.eraser,
              iconSize: iconSize,
              onTap: () => provider.setTool(WhiteboardTool.eraser),
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
            const VerticalDivider(color: Color(0xFFCBD5E1), width: 8, indent: 4, endIndent: 4),

            // Shape & Extras Group
            _ToolButton(
              icon: provider.currentTool == WhiteboardTool.shape ? _getShapeIcon(provider.currentShapeType) : LucideIcons.shapes,
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
            const VerticalDivider(color: Color(0xFFCBD5E1), width: 8, indent: 4, endIndent: 4),

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
          'Undo' => isEnabled ? const Color(0xFF334155) : const Color(0xFF94A3B8),
          'Redo' => isEnabled ? const Color(0xFF334155) : const Color(0xFF94A3B8),
          _ => const Color(0xFF334155),
        };

    final iconColor = isActive ? const Color(0xFF38BDF8) : defaultIconColor;
    final textColor = isActive ? Colors.white : (isEnabled ? const Color(0xFF1E293B) : const Color(0xFF94A3B8));

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
          border: isActive ? Border.all(color: const Color(0xFF38BDF8), width: 1.2) : null,
          boxShadow: isActive ? [BoxShadow(color: const Color(0xFF38BDF8).withValues(alpha: 0.5), blurRadius: 6, spreadRadius: 0.5)] : null,
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

class _ShapeGridButton extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ShapeGridButton({required this.icon, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(color: isSelected ? Colors.blue : const Color(0xFF333333), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }
}

class _ColorButton extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorButton({required this.color, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? Colors.blue : Colors.grey[300]!, width: isSelected ? 3 : 1),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
        ),
        child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
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

  const _PenTypeOption({required this.label, required this.icon, required this.color, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : Colors.grey[100],
          border: Border.all(color: isSelected ? color : Colors.grey[300]!, width: isSelected ? 2 : 1),
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
