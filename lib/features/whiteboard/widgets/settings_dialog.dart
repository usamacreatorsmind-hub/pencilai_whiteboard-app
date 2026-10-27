import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../services/translation_service.dart';
import '../state/whiteboard_provider.dart';
import 'canvas/canvas_grid_painter.dart';

enum SettingsTab { main, background, handwritingLanguage, translationLanguage }

class SettingsDialog extends StatefulWidget {
  final SettingsTab initialTab;

  const SettingsDialog({super.key, this.initialTab = SettingsTab.main});

  static Future<void> show(BuildContext context, {SettingsTab initialTab = SettingsTab.main}) {
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

  static const List<Color> themeBackgroundColors = [
    // Row 1
    Color(0xFFE5E8EC), Color(0xFFD2E4F6), Color(0xFFC4DFD6),
    Color(0xFF73777B), Color(0xFF2F3133), Color(0xFF121314),

    // Row 2
    Color(0xFF5CA3DF), Color(0xFF3DAE97), Color(0xFF7BBF37),
    Color(0xFFE0A96D), Color(0xFFC87B88), Color(0xFF5D62B1),

    // Row 3
    Color(0xFF0060CA), Color(0xFF007D49), Color(0xFF329202), // Selected ✓
    Color(0xFFD87D0E), Color(0xFFBA2D2D), Color(0xFF1C1582),

    // Row 4
    Color(0xFF0C0E12), Color(0xFF0F1410), Color(0xFF1B2A10),
    Color(0xFF3B2818), Color(0xFF2B1218), Color(0xFF111226),
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

  static const List<CanvasGridType> _gridRow2 = [CanvasGridType.columns, CanvasGridType.isometric];

  // Dialog dimensions
  static const double _kDialogMaxWidth = 480.0;
  static const double _kColorChipSize = 28.0;
  static const double _kGridTileSize = 28.0;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
  }

  void _openCustomColorPicker(BuildContext context, WhiteboardProvider provider) {
    Color pickerColor = provider.canvasBackgroundColor;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Choose Custom Background Color',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
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
              style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WhiteboardProvider>();
    final double dialogWidth = MediaQuery.sizeOf(context).width.clamp(320.0, _kDialogMaxWidth);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Center(
        child: Container(
          width: dialogWidth,
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.86),
          decoration: BoxDecoration(
            color: const Color(0xFFECEEF2), // Soft light grey frame matching photo
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.24), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          padding: const EdgeInsets.all(14),
          child: AnimatedSwitcher(duration: const Duration(milliseconds: 180), child: _buildCurrentPanel(context, provider)),
        ),
      ),
    );
  }

  Widget _buildCurrentPanel(BuildContext context, WhiteboardProvider provider) {
    switch (_currentTab) {
      case SettingsTab.main:
        return _buildMainSettingsPanel(context, provider);
      case SettingsTab.background:
        return _buildBackgroundPanel(context, provider);
      case SettingsTab.handwritingLanguage:
        return _buildHandwritingLanguagePanel(context, provider);
      case SettingsTab.translationLanguage:
        return _buildTranslationLanguagePanel(context, provider);
    }
  }

  // -------------------------------------------------------------------------
  // 1. Background Settings Panel (Exact image UI)
  // -------------------------------------------------------------------------
  Widget _buildBackgroundPanel(BuildContext context, WhiteboardProvider provider) {
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
                    Icon(LucideIcons.chevronLeft, size: 15, color: Color(0xFF2563EB)),
                    SizedBox(width: 2),
                    Text(
                      'Settings',
                      style: TextStyle(color: Color(0xFF2563EB), fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
            const Expanded(
              child: Center(
                child: Text(
                  'Background',
                  style: TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(LucideIcons.x, size: 17, color: Color(0xFF64748B)),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Close',
              splashRadius: 14,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Flexible(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Section 1: Background Color Tray (4 rows of 6 theme colors)
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
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                provider.canvasBackgroundImagePath != null
                                    ? 'Custom Image'
                                    : provider.canvasBackgroundColorName,
                                style: const TextStyle(
                                  color: Color(0xFF334155),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _buildRainbowPickerChip(
                                context,
                                provider,
                                isSelected: provider.canvasBackgroundImagePath == null &&
                                    !themeBackgroundColors.any((c) =>
                                        c.toARGB32() == provider.canvasBackgroundColor.toARGB32()),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // 4 Rows of 6 theme background colors
                      for (int row = 0; row < 4; row++) ...[
                        if (row > 0) const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            for (int col = 0; col < 6; col++) ...[
                              Builder(
                                builder: (context) {
                                  final color = themeBackgroundColors[row * 6 + col];
                                  final isSelected = provider.canvasBackgroundImagePath == null &&
                                      provider.canvasBackgroundColor.toARGB32() == color.toARGB32();
                                  return _buildColorChip(
                                    color: color,
                                    isSelected: isSelected,
                                    onTap: () => provider.setCanvasBackgroundColor(color),
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ],
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
                            provider.canvasGridType == CanvasGridType.none
                                ? 'No Grid'
                                : provider.canvasGridType.displayName,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Divider(
                        height: 1,
                        thickness: 0.8,
                        color: const Color(0xFFE2E8F0).withValues(alpha: 0.8),
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
                            const SizedBox(width: _kGridTileSize, height: _kGridTileSize),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                // Section 3: Custom Background Tray (Matching Reference Image)
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
                            'Custom',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            provider.canvasBackgroundImagePath != null ? 'Custom' : 'Background',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Divider(
                        height: 1,
                        thickness: 0.8,
                        color: const Color(0xFFE2E8F0).withValues(alpha: 0.8),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _buildCustomImagePickerButton(context, provider),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Reminder: Please select a jpg,\nbmp or png 3840*2160 image.',
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 10.5,
                                height: 1.35,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Custom Background Image Picker Button
  // -------------------------------------------------------------------------
  Widget _buildCustomImagePickerButton(BuildContext context, WhiteboardProvider provider) {
    final bool hasImage = provider.canvasBackgroundImagePath != null && File(provider.canvasBackgroundImagePath!).existsSync();

    return GestureDetector(
      onTap: () => _pickCustomBackgroundImage(context, provider),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 76,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: hasImage ? const Color(0xFF2563EB) : const Color(0xFFCBD5E1), width: hasImage ? 2.0 : 1.0),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 3, offset: const Offset(0, 1))],
        ),
        clipBehavior: Clip.antiAlias,
        child: hasImage
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(File(provider.canvasBackgroundImagePath!), fit: BoxFit.cover),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: () => provider.setCanvasBackgroundImagePath(null),
                      child: Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.70), shape: BoxShape.circle),
                        child: const Icon(LucideIcons.x, size: 11, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              )
            : const Center(child: Icon(LucideIcons.plus, size: 22, color: Color(0xFF1E293B))),
      ),
    );
  }

  Future<void> _pickCustomBackgroundImage(BuildContext context, WhiteboardProvider provider) async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'bmp']);
      if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
        final path = result.files.first.path!;
        provider.setCanvasBackgroundImagePath(path);
      }
    } catch (e) {
      debugPrint('Error picking custom background image: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to pick background image: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  // -------------------------------------------------------------------------
  // Color Chip Widget
  // -------------------------------------------------------------------------
  Widget _buildColorChip({required Color color, required bool isSelected, required VoidCallback onTap}) {
    final bool isLight = color.computeLuminance() > 0.45;
    final bool isWhiteOrVeryLight = color.computeLuminance() > 0.85;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: _kColorChipSize,
        height: _kColorChipSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: const Color(0xFF2563EB), width: 1.8) : null,
        ),
        padding: EdgeInsets.all(isSelected ? 1.8 : 0.0),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: isWhiteOrVeryLight ? Border.all(color: Colors.black.withValues(alpha: 0.12), width: 0.8) : null,
            boxShadow: [if (!isSelected) BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 2, offset: const Offset(0, 1))],
          ),
          child: isSelected
              ? Center(
                  child: Icon(
                    Icons.check,
                    size: 14,
                    color: isLight ? const Color(0xFF0F172A) : Colors.white,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Rainbow Custom Color Chip Widget
  // -------------------------------------------------------------------------
  Widget _buildRainbowPickerChip(BuildContext context, WhiteboardProvider provider, {required bool isSelected}) {
    return GestureDetector(
      onTap: () => _openCustomColorPicker(context, provider),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: _kColorChipSize,
        height: _kColorChipSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: const Color(0xFF2563EB), width: 1.8) : null,
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
          child: const Center(child: Icon(LucideIcons.pipette, size: 11, color: Colors.white)),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Grid Pattern Tile Widget
  // -------------------------------------------------------------------------
  Widget _buildGridTile({required CanvasGridType type, required bool isSelected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: _kGridTileSize,
        height: _kGridTileSize,
        decoration: BoxDecoration(
          color: const Color(0xFF22262E), // Dark rounded tile background
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? const Color(0xFF2563EB) : Colors.transparent, width: isSelected ? 1.8 : 1.0),
          boxShadow: isSelected
              ? [BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.35), blurRadius: 4, spreadRadius: 0.5)]
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
  // Helper: Custom Radio Circle matching reference design
  // -------------------------------------------------------------------------
  Widget _buildRadioCircle({required bool isSelected}) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: isSelected ? const Color(0xFF0D9488) : const Color(0xFF9CA3AF), width: 2.0),
      ),
      child: isSelected
          ? Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF0D9488)),
              ),
            )
          : null,
    );
  }

  // -------------------------------------------------------------------------
  // 2. Main Settings Panel (Matching Photo 1)
  // -------------------------------------------------------------------------
  Widget _buildMainSettingsPanel(BuildContext context, WhiteboardProvider provider) {
    return Column(
      key: const ValueKey('main_panel'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox(width: 28),
            const Text(
              'Settings',
              style: TextStyle(color: Color(0xFF1F2937), fontSize: 18, fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(LucideIcons.x, size: 20, color: Color(0xFF64748B)),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Close',
              splashRadius: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Scrollable content of cards
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Handwriting recognition language
                _buildCardNavigationTile(
                  title: 'Handwriting recognition language',
                  subtitle: provider.selectedHandwritingLanguage,
                  onTap: () => setState(() => _currentTab = SettingsTab.handwritingLanguage),
                ),
                const SizedBox(height: 10),

                // 2. Translation language
                _buildCardNavigationTile(
                  title: 'Translation language',
                  subtitle: 'Manage translation language models.',
                  onTap: () => setState(() => _currentTab = SettingsTab.translationLanguage),
                ),
                const SizedBox(height: 10),

                // 3. Background & Grid
                _buildCardNavigationTile(
                  title: 'Background & Grid',
                  subtitle: provider.canvasBackgroundImagePath != null
                      ? 'Custom Image'
                      : '${provider.canvasBackgroundColorName} • ${provider.canvasGridType == CanvasGridType.none ? "No Grid" : provider.canvasGridType.displayName}',
                  onTap: () => setState(() => _currentTab = SettingsTab.background),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCardNavigationTile({required String title, required String subtitle, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 1))],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: Color(0xFF1F2937), fontSize: 14.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, size: 20, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 3. Handwriting Recognition Language Panel (Matching Photo 2)
  // -------------------------------------------------------------------------
  Widget _buildHandwritingLanguagePanel(BuildContext context, WhiteboardProvider provider) {
    return Column(
      key: const ValueKey('handwriting_lang_panel'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header with back chevron and title
        Row(
          children: [
            IconButton(
              icon: const Icon(LucideIcons.chevronLeft, size: 22, color: Color(0xFF0D9488)),
              onPressed: () => setState(() => _currentTab = SettingsTab.main),
              tooltip: 'Back to Settings',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
            const Expanded(
              child: Text(
                'Handwriting recognition language',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF1F2937), fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(LucideIcons.x, size: 20, color: Color(0xFF64748B)),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Close',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Language List
        Flexible(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 1))],
            ),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: WhiteboardProvider.kHandwritingLanguages.length,
              separatorBuilder: (ctx, i) => Divider(height: 1, color: const Color(0xFFF1F5F9)),
              itemBuilder: (ctx, index) {
                final lang = WhiteboardProvider.kHandwritingLanguages[index];
                final isSelected =
                    provider.selectedHandwritingLanguage == lang.name ||
                    (lang.id == 'follow_system' && provider.selectedHandwritingLanguage.contains('Follow System'));
                final isDownloaded = provider.isHandwritingLanguageDownloaded(lang.id);
                final downloadProgress = provider.handwritingDownloadProgress[lang.id];
                final isDownloading = downloadProgress != null;

                return InkWell(
                  onTap: () {
                    if (isDownloaded) {
                      provider.setSelectedHandwritingLanguage(lang.name);
                    } else if (!isDownloading) {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Please download ${lang.displayName} model first before using.'),
                          backgroundColor: const Color(0xFF1F2937),
                          action: SnackBarAction(
                            label: 'Download',
                            textColor: const Color(0xFF38BDF8),
                            onPressed: () => provider.downloadHandwritingLanguage(lang.id),
                          ),
                        ),
                      );
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        _buildRadioCircle(isSelected: isSelected),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            lang.nativeName,
                            style: TextStyle(
                              color: const Color(0xFF1F2937),
                              fontSize: 15,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (isDownloading)
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(value: downloadProgress, strokeWidth: 2.2, color: const Color(0xFF0D9488)),
                          )
                        else if (isDownloaded)
                          IconButton(
                            icon: const Icon(LucideIcons.check, size: 20, color: Color(0xFF10B981)),
                            onPressed: () => provider.setSelectedHandwritingLanguage(lang.name),
                            tooltip: 'Model downloaded',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          )
                        else
                          IconButton(
                            icon: const Icon(LucideIcons.download, size: 20, color: Color(0xFF64748B)),
                            onPressed: () => provider.downloadHandwritingLanguage(lang.id),
                            tooltip: 'Download ${lang.name} model',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // 4. Translation Language Panel (Matching Photo 3)
  // -------------------------------------------------------------------------
  Widget _buildTranslationLanguagePanel(BuildContext context, WhiteboardProvider provider) {
    return Column(
      key: const ValueKey('translation_lang_panel'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header with back chevron and title
        Row(
          children: [
            IconButton(
              icon: const Icon(LucideIcons.chevronLeft, size: 22, color: Color(0xFF0D9488)),
              onPressed: () => setState(() => _currentTab = SettingsTab.main),
              tooltip: 'Back to Settings',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
            const Expanded(
              child: Text(
                'Translation language',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF1F2937), fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(LucideIcons.x, size: 20, color: Color(0xFF64748B)),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Close',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Translation Language List matching Photo 3
        Flexible(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 1))],
            ),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: TranslationService.supportedLanguages.length,
              separatorBuilder: (ctx, i) => Divider(height: 1, color: const Color(0xFFF1F5F9)),
              itemBuilder: (ctx, index) {
                final lang = TranslationService.supportedLanguages[index];
                final isDownloaded = provider.isTranslationLanguageDownloaded(lang.code);
                final downloadProgress = provider.translationDownloadProgress[lang.code];
                final isDownloading = downloadProgress != null;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          lang.nativeName,
                          style: const TextStyle(color: Color(0xFF1F2937), fontSize: 15, fontWeight: FontWeight.w400),
                        ),
                      ),
                      if (isDownloading)
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(value: downloadProgress, strokeWidth: 2.2, color: const Color(0xFF0D9488)),
                        )
                      else if (isDownloaded)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Text(
                              'Installed',
                              style: TextStyle(color: Color(0xFF10B981), fontSize: 11.5, fontWeight: FontWeight.w600),
                            ),
                            SizedBox(width: 4),
                            Icon(LucideIcons.check, size: 18, color: Color(0xFF10B981)),
                          ],
                        )
                      else
                        IconButton(
                          icon: const Icon(LucideIcons.download, size: 20, color: Color(0xFF64748B)),
                          onPressed: () => provider.downloadTranslationLanguage(lang),
                          tooltip: 'Download ${lang.name} model',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
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
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint..strokeWidth = 0.5);
        }
        for (double y = 4; y < size.height; y += 4.5) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint..strokeWidth = 0.5);
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
              ..color = isMajor ? const Color(0xFF38BDF8) : Colors.white.withValues(alpha: 0.25)
              ..strokeWidth = isMajor ? 0.8 : 0.5,
          );
        }
        for (double y = 3; y < size.height; y += 4.5) {
          final isMajor = (y / 4.5).round() % 3 == 0;
          canvas.drawLine(
            Offset(0, y),
            Offset(size.width, y),
            Paint()
              ..color = isMajor ? const Color(0xFF38BDF8) : Colors.white.withValues(alpha: 0.25)
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
          canvas.drawLine(Offset(x, 0), Offset(x - size.height * 0.6, size.height), linePaint);
          canvas.drawLine(Offset(x - 16, 0), Offset(x - 16 + size.height * 0.6, size.height), linePaint);
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _GridTilePainter oldDelegate) => oldDelegate.type != type;
}

typedef _GridTileThumbnailPainter = _GridTilePainter;
