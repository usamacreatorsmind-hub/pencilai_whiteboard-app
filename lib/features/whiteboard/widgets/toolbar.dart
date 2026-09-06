import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../state/whiteboard_provider.dart';
import '../models/shape_element.dart';
import '../models/image_element.dart';

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

  void _showPenSettings(BuildContext context, WhiteboardProvider provider) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          contentPadding: EdgeInsets.zero,
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Container(
            width: 400,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Brush Size', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 10),
                // Size Slider
                Row(
                  children: [
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: provider.currentColor,
                          thumbColor: provider.currentColor,
                          overlayColor: provider.currentColor.withOpacity(0.2),
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
                    ),
                    Text(provider.strokeWidth.toInt().toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('Colors', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 15),
                // Color Grid
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
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
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                          gradient: const LinearGradient(
                            colors: [Colors.red, Colors.green, Colors.blue, Colors.yellow],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Icon(Icons.colorize, size: 20, color: Colors.white),
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
              child: const Text(
                'Done',
                style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSizePicker(BuildContext context, WhiteboardProvider provider) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Brush Size', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
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
                  Text(provider.strokeWidth.toInt().toString(), style: const TextStyle(color: Colors.white, fontSize: 18)),
                ],
              ),
              const SizedBox(height: 16),
              // Preview circle
              Container(
                width: provider.strokeWidth,
                height: provider.strokeWidth,
                decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done', style: TextStyle(color: Colors.blue)),
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
    final iconSize = isLargeScreen ? 22.0 : 18.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E), // Dark background like the image
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))],
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
            const VerticalDivider(color: Colors.white24, width: 8, indent: 6, endIndent: 6),

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
            const VerticalDivider(color: Colors.white24, width: 8, indent: 6, endIndent: 6),

            // History Group
            _ToolButton(
              icon: LucideIcons.undo2,
              label: 'Undo',
              isActive: false,
              iconSize: iconSize,
              color: provider.canUndo ? Colors.white : Colors.white38,
              onTap: provider.canUndo ? provider.undo : null,
            ),
            _ToolButton(
              icon: LucideIcons.redo2,
              label: 'Redo',
              isActive: false,
              iconSize: iconSize,
              color: provider.canRedo ? Colors.white : Colors.white38,
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
    final textColor = isActive ? Colors.white : Colors.white60;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue.withOpacity(0.9) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize, color: color ?? textColor),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 9,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                letterSpacing: 0.2,
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
