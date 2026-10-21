import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../state/whiteboard_provider.dart';
import 'canvas/canvas_grid_painter.dart';

enum SettingsTab { main, background }

class SettingsDialog extends StatefulWidget {
  final SettingsTab initialTab;

  const SettingsDialog({super.key, this.initialTab = SettingsTab.background});

  static Future<void> show(
    BuildContext context, {
    SettingsTab initialTab = SettingsTab.background,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => SettingsDialog(initialTab: initialTab),
    );
  }

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late SettingsTab _currentTab;

  // Preset Colors matching the reference design
  static const List<({Color color, String name})> _lightPresets = [
    (color: Color(0xFFFFFFFF), name: 'Cloud White'),
    (color: Color(0xFFFDE8D7), name: 'Warm Peach'),
    (color: Color(0xFFE2F0D9), name: 'Soft Mint'),
    (color: Color(0xFFD0E8F2), name: 'Quiet blue'),
    (color: Color(0xFFE1D9F0), name: 'Soft Lavender'),
    (color: Color(0xFFFADCDD), name: 'Soft Rose'),
  ];

  static const List<({Color color, String name})> _darkPresets = [
    (color: Color(0xFF1E1E1E), name: 'Pitch Black'),
    (color: Color(0xFF36322E), name: 'Dark Charcoal'),
    (color: Color(0xFF21352A), name: 'Forest Green'),
    (color: Color(0xFF1D3557), name: 'Quiet blue'),
    (color: Color(0xFF2D2545), name: 'Midnight Violet'),
  ];

  // Grid options matching reference design (8 in row 1, 2 in row 2)
  static const List<CanvasGridType> _gridRow1 = [
    CanvasGridType.none,
    CanvasGridType.square,
    CanvasGridType.lined,
    CanvasGridType.dots,
    CanvasGridType.mixGrid,
    CanvasGridType.denseGrid,
    CanvasGridType.ruledNote,
    CanvasGridType.crossGrid,
  ];

  static const List<CanvasGridType> _gridRow2 = [
    CanvasGridType.columns,
    CanvasGridType.isometric,
  ];

  // Compact dimensions
  static const double _kDialogMaxWidth = 350.0;
  static const double _kColorChipSize = 28.0;
  static const double _kGridTileSize = 28.0;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
  }

  void _openCustomColorPicker(
    BuildContext context,
    WhiteboardProvider provider,
  ) {
    Color pickerColor = provider.canvasBackgroundColor;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Choose Custom Background Color',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (c) {
              pickerColor = c;
              provider.setCanvasBackgroundColor(c);
            },
            paletteType: PaletteType.hsvWithHue,
            enableAlpha: false,
            displayThumbColor: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Done',
              style: TextStyle(
                color: Color(0xFF38BDF8),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WhiteboardProvider>();
    final double dialogWidth = MediaQuery.sizeOf(
      context,
    ).width.clamp(260.0, _kDialogMaxWidth);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Center(
        child: Container(
          width: dialogWidth,
          decoration: BoxDecoration(
            color: const Color(0xFFE5E7EB), // Soft light grey frame
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(10),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _currentTab == SettingsTab.background
                ? _buildBackgroundPanel(context, provider)
                : _buildMainSettingsPanel(context, provider),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 1. Background Settings Panel (Exact image UI)
  // -------------------------------------------------------------------------
  Widget _buildBackgroundPanel(
    BuildContext context,
    WhiteboardProvider provider,
  ) {
    return Column(
      key: const ValueKey('background_panel'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Header
        Row(
          children: [
            InkWell(
              onTap: () => setState(() => _currentTab = SettingsTab.main),
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.chevronLeft,
                      size: 15,
                      color: Color(0xFF2563EB),
                    ),
                    SizedBox(width: 2),
                    Text(
                      'Settings',
                      style: TextStyle(
                        color: Color(0xFF2563EB),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Expanded(
              child: Center(
                child: Text(
                  'Background',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(
                LucideIcons.x,
                size: 17,
                color: Color(0xFF64748B),
              ),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Close',
              splashRadius: 14,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Section 1: Background Color Tray
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Background',
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    provider.canvasBackgroundColorName,
                    style: const TextStyle(
                      color: Color(0xFF334155),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Row 1: Light colors (6 circles)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: _lightPresets.map((preset) {
                  return _buildColorChip(
                    color: preset.color,
                    isSelected: provider.canvasBackgroundColor == preset.color,
                    onTap: () =>
                        provider.setCanvasBackgroundColor(preset.color),
                  );
                }).toList(),
              ),
              const SizedBox(height: 6),

              // Row 2: Dark colors (5 circles) + Rainbow Color Wheel
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ..._darkPresets.map((preset) {
                    return _buildColorChip(
                      color: preset.color,
                      isSelected:
                          provider.canvasBackgroundColor == preset.color,
                      onTap: () =>
                          provider.setCanvasBackgroundColor(preset.color),
                    );
                  }),
                  _buildRainbowPickerChip(
                    context,
                    provider,
                    isSelected:
                        !_lightPresets.any(
                          (p) => p.color == provider.canvasBackgroundColor,
                        ) &&
                        !_darkPresets.any(
                          (p) => p.color == provider.canvasBackgroundColor,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // Section 2: Grid Pattern Tray
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Grid',
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    provider.canvasGridType.displayName,
                    style: const TextStyle(
                      color: Color(0xFF334155),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Row 1: 8 grid tiles
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: _gridRow1.map((type) {
                  return _buildGridTile(
                    type: type,
                    isSelected: provider.canvasGridType == type,
                    onTap: () => provider.setCanvasGridType(type),
                  );
                }).toList(),
              ),
              const SizedBox(height: 6),

              // Row 2: 2 grid tiles aligned to match columns 1 & 2 of Row 1
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildGridTile(
                    type: _gridRow2[0],
                    isSelected: provider.canvasGridType == _gridRow2[0],
                    onTap: () => provider.setCanvasGridType(_gridRow2[0]),
                  ),
                  _buildGridTile(
                    type: _gridRow2[1],
                    isSelected: provider.canvasGridType == _gridRow2[1],
                    onTap: () => provider.setCanvasGridType(_gridRow2[1]),
                  ),
                  for (int i = 0; i < 6; i++)
                    const SizedBox(
                      width: _kGridTileSize,
                      height: _kGridTileSize,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Color Chip Widget
  // -------------------------------------------------------------------------
  Widget _buildColorChip({
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final bool isWhiteOrVeryLight = color.computeLuminance() > 0.85;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: _kColorChipSize,
        height: _kColorChipSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(color: const Color(0xFF2563EB), width: 1.8)
              : null,
        ),
        padding: EdgeInsets.all(isSelected ? 1.8 : 0.0),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: isWhiteOrVeryLight
                ? Border.all(
                    color: Colors.black.withValues(alpha: 0.12),
                    width: 0.8,
                  )
                : null,
            boxShadow: [
              if (!isSelected)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Rainbow Custom Color Chip Widget
  // -------------------------------------------------------------------------
  Widget _buildRainbowPickerChip(
    BuildContext context,
    WhiteboardProvider provider, {
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () => _openCustomColorPicker(context, provider),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: _kColorChipSize,
        height: _kColorChipSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(color: const Color(0xFF2563EB), width: 1.8)
              : null,
        ),
        padding: EdgeInsets.all(isSelected ? 1.8 : 0.0),
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              colors: [
                Color(0xFFFF0000),
                Color(0xFFFF8800),
                Color(0xFFFFFF00),
                Color(0xFF00FF00),
                Color(0xFF00FFFF),
                Color(0xFF0000FF),
                Color(0xFFFF00FF),
                Color(0xFFFF0000),
              ],
            ),
          ),
          child: const Center(
            child: Icon(LucideIcons.pipette, size: 11, color: Colors.white),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Grid Pattern Tile Widget
  // -------------------------------------------------------------------------
  Widget _buildGridTile({
    required CanvasGridType type,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: _kGridTileSize,
        height: _kGridTileSize,
        decoration: BoxDecoration(
          color: const Color(0xFF22262E), // Dark rounded tile background
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? const Color(0xFF2563EB) : Colors.transparent,
            width: isSelected ? 1.8 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.35),
                    blurRadius: 4,
                    spreadRadius: 0.5,
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4.5),
          child: CustomPaint(painter: _GridTileThumbnailPainter(type: type)),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 2. Main Settings Panel
  // -------------------------------------------------------------------------
  Widget _buildMainSettingsPanel(
    BuildContext context,
    WhiteboardProvider provider,
  ) {
    return Column(
      key: const ValueKey('main_panel'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(LucideIcons.settings, size: 20, color: Color(0xFF0F172A)),
                SizedBox(width: 8),
                Text(
                  'Settings',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(
                LucideIcons.x,
                size: 18,
                color: Color(0xFF64748B),
              ),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Close',
              splashRadius: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Background category tile
        _buildSettingNavTile(
          icon: LucideIcons.palette,
          iconColor: const Color(0xFF2563EB),
          title: 'Background & Grid',
          subtitle:
              '${provider.canvasBackgroundColorName} • ${provider.canvasGridType.displayName}',
          onTap: () => setState(() => _currentTab = SettingsTab.background),
        ),
        const SizedBox(height: 8),

        // Pen & Stylus category tile
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  LucideIcons.penTool,
                  color: Color(0xFF10B981),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Auto Nib Detection',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 1),
                    Text(
                      'Thin / Thick stylus tip auto-detect',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.85,
                child: Switch(
                  value: provider.isAutoNibDetectionEnabled,
                  onChanged: (v) => provider.setAutoNibDetectionEnabled(v),
                  activeThumbColor: const Color(0xFF2563EB),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // About category tile
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  LucideIcons.info,
                  color: Color(0xFF8B5CF6),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PencilAI Whiteboard',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 1),
                    Text(
                      'Version 1.0.0 • 75" Panel & Stylus Optimized',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingNavTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Thumbnail Painter for miniature preview inside each grid tile
// ---------------------------------------------------------------------------
class _GridTilePainter extends CustomPainter {
  final CanvasGridType type;

  const _GridTilePainter({required this.type});

  @override
  void paint(Canvas canvas, Size size) {
    if (type == CanvasGridType.none) return;

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.40)
      ..strokeWidth = 0.7;

    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.60)
      ..style = PaintingStyle.fill;

    switch (type) {
      case CanvasGridType.none:
        break;

      case CanvasGridType.square:
        for (double x = 6; x < size.width; x += 7.5) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
        }
        for (double y = 6; y < size.height; y += 7.5) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
        }
        break;

      case CanvasGridType.denseGrid:
        for (double x = 4; x < size.width; x += 4.5) {
          canvas.drawLine(
            Offset(x, 0),
            Offset(x, size.height),
            linePaint..strokeWidth = 0.5,
          );
        }
        for (double y = 4; y < size.height; y += 4.5) {
          canvas.drawLine(
            Offset(0, y),
            Offset(size.width, y),
            linePaint..strokeWidth = 0.5,
          );
        }
        break;

      case CanvasGridType.lined:
        for (double y = 6; y < size.height; y += 6) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
        }
        break;

      case CanvasGridType.dots:
        for (double x = 5.5; x < size.width; x += 6.0) {
          for (double y = 5.5; y < size.height; y += 6.0) {
            canvas.drawCircle(Offset(x, y), 0.8, dotPaint);
          }
        }
        break;

      case CanvasGridType.mixGrid:
        // Blueprint style
        for (double x = 3; x < size.width; x += 4.5) {
          final isMajor = (x / 4.5).round() % 3 == 0;
          canvas.drawLine(
            Offset(x, 0),
            Offset(x, size.height),
            Paint()
              ..color = isMajor
                  ? const Color(0xFF38BDF8)
                  : Colors.white.withValues(alpha: 0.25)
              ..strokeWidth = isMajor ? 0.8 : 0.5,
          );
        }
        for (double y = 3; y < size.height; y += 4.5) {
          final isMajor = (y / 4.5).round() % 3 == 0;
          canvas.drawLine(
            Offset(0, y),
            Offset(size.width, y),
            Paint()
              ..color = isMajor
                  ? const Color(0xFF38BDF8)
                  : Colors.white.withValues(alpha: 0.25)
              ..strokeWidth = isMajor ? 0.8 : 0.5,
          );
        }
        break;

      case CanvasGridType.ruledNote:
        for (double y = 6; y < size.height; y += 6) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
        }
        canvas.drawLine(
          const Offset(7.5, 0),
          Offset(7.5, size.height),
          Paint()
            ..color = const Color(0xFFEF4444).withValues(alpha: 0.75)
            ..strokeWidth = 0.8,
        );
        break;

      case CanvasGridType.crossGrid:
        const double arm = 1.3;
        for (double x = 5.5; x < size.width; x += 7.0) {
          for (double y = 5.5; y < size.height; y += 7.0) {
            canvas.drawLine(Offset(x - arm, y), Offset(x + arm, y), linePaint);
            canvas.drawLine(Offset(x, y - arm), Offset(x, y + arm), linePaint);
          }
        }
        break;

      case CanvasGridType.columns:
        for (double x = 5.5; x < size.width; x += 5.5) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
        }
        break;

      case CanvasGridType.isometric:
        for (double y = 5; y < size.height; y += 6) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
        }
        for (double x = 0; x < size.width + 16; x += 7.5) {
          canvas.drawLine(
            Offset(x, 0),
            Offset(x - size.height * 0.6, size.height),
            linePaint,
          );
          canvas.drawLine(
            Offset(x - 16, 0),
            Offset(x - 16 + size.height * 0.6, size.height),
            linePaint,
          );
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _GridTilePainter oldDelegate) =>
      oldDelegate.type != type;
}

typedef _GridTileThumbnailPainter = _GridTilePainter;
