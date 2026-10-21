import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../models/chemical_element.dart';
import '../models/chemical_element_element.dart';
import '../state/whiteboard_provider.dart';

class PeriodicTableDialog extends StatefulWidget {
  final WhiteboardProvider provider;

  const PeriodicTableDialog({super.key, required this.provider});

  static Future<void> show(BuildContext context, WhiteboardProvider provider) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => PeriodicTableDialog(provider: provider),
    );
  }

  @override
  State<PeriodicTableDialog> createState() => _PeriodicTableDialogState();
}

class _PeriodicTableDialogState extends State<PeriodicTableDialog> {
  // By default, no elements are selected
  final Set<ChemicalElement> _selectedElements = {};
  ChemicalElement? _activePreviewElement;
  final Map<String, ChemicalElement> _elementGridMap = {};

  @override
  void initState() {
    super.initState();
    for (var el in kPeriodicElements) {
      _elementGridMap['${el.period}_${el.group}'] = el;
    }
  }

  void _toggleElementSelection(ChemicalElement el) {
    setState(() {
      if (_selectedElements.contains(el)) {
        _selectedElements.remove(el);
        if (_selectedElements.isNotEmpty) {
          _activePreviewElement = _selectedElements.last;
        } else {
          _activePreviewElement = null;
        }
      } else {
        _selectedElements.add(el);
        _activePreviewElement = el;
      }
    });
  }

  void _insertSelectedElementsOnCanvas() {
    if (_selectedElements.isEmpty) return;

    final screenSize = MediaQuery.of(context).size;
    const cardWidth = 150.0;
    const cardHeight = 175.0;
    const gap = 24.0;
    final count = _selectedElements.length;

    // Calculate total row width so cards are centered in viewport
    final totalWidth = count * cardWidth + (count - 1) * gap;
    final startScreenX = max(40.0, (screenSize.width - totalWidth) / 2.0);
    final startScreenY = max(40.0, (screenSize.height - cardHeight) / 2.0);

    final List<String> insertedIds = [];
    int idx = 0;
    for (var el in _selectedElements) {
      final screenPos = Offset(
        startScreenX + idx * (cardWidth + gap),
        startScreenY,
      );
      final canvasPos = widget.provider.screenToCanvas(screenPos);

      final boardElement = ChemicalElementElement.fromChemicalElement(
        el,
        id: const Uuid().v4(),
        position: canvasPos,
        size: const Size(cardWidth, cardHeight),
      );

      widget.provider.addElement(boardElement);
      insertedIds.add(boardElement.id);
      idx++;
    }

    // Multi-select all inserted elements together
    widget.provider.clearSelection();
    for (var id in insertedIds) {
      widget.provider.selectElement(id, multi: true);
    }
    widget.provider.setTool(WhiteboardTool.select);

    Navigator.of(context).pop();

    final symbolsText = _selectedElements.map((e) => e.symbol).join(', ');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
        ),
        content: Row(
          children: [
            const Icon(
              LucideIcons.checkCircle2,
              color: Color(0xFF38BDF8),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Inserted $count element${count > 1 ? "s" : ""} ($symbolsText) on canvas. You can draw, annotate, and move them.',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = min(screenSize.width * 0.94, 1020.0);
    final dialogHeight = min(screenSize.height * 0.94, 660.0);

    return Dialog(
      backgroundColor: const Color(0xFF0F172A), // Sleek obsidian slate
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1.2,
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: dialogHeight,
        ),
        child: Column(
          children: [
            // 1. Top Header Bar
            _buildHeaderBar(),

            const Divider(color: Colors.white12, height: 1),

            // 2. Main Periodic Table Grid View
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: _buildPeriodicTableGrid(),
              ),
            ),

            const Divider(color: Colors.white12, height: 1),

            // 3. Element Inspector & Multi-Selection Action Panel
            _buildElementInspector(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderBar() {
    final multiCount = _selectedElements.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF0284C7).withValues(alpha: 0.4),
              ),
            ),
            child: const Icon(
              LucideIcons.atom,
              color: Color(0xFF38BDF8),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Periodic Table',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                  if (multiCount > 0) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        '$multiCount Selected',
                        style: const TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                'Tap elements to select multiple & insert together on canvas',
                style: TextStyle(color: Colors.white60, fontSize: 11.5),
              ),
            ],
          ),
          const Spacer(),

          // Close Button
          IconButton(
            icon: const Icon(LucideIcons.x, color: Colors.white70, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodicTableGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = max(constraints.maxWidth, 880.0);
        final colWidth = (totalWidth - (17 * 4.0)) / 18.0;
        final cellHeight = colWidth * 1.18;

        List<Widget> gridRows = [];

        // Periods 1 to 7
        for (int period = 1; period <= 7; period++) {
          List<Widget> rowCells = [];
          for (int group = 1; group <= 18; group++) {
            // Check for Lanthanide / Actinide placeholders at (6, 3) and (7, 3)
            if (period == 6 && group == 3) {
              rowCells.add(
                _buildSeriesPlaceholderCell(
                  label: '57-71',
                  subLabel: 'La-Lu',
                  color: const Color(0xFFEC4899),
                  width: colWidth,
                  height: cellHeight,
                  onTap: () {
                    final la = kPeriodicElements.firstWhere(
                      (e) => e.atomicNumber == 57,
                    );
                    _toggleElementSelection(la);
                  },
                ),
              );
              continue;
            }

            if (period == 7 && group == 3) {
              rowCells.add(
                _buildSeriesPlaceholderCell(
                  label: '89-103',
                  subLabel: 'Ac-Lr',
                  color: const Color(0xFFD946EF),
                  width: colWidth,
                  height: cellHeight,
                  onTap: () {
                    final ac = kPeriodicElements.firstWhere(
                      (e) => e.atomicNumber == 89,
                    );
                    _toggleElementSelection(ac);
                  },
                ),
              );
              continue;
            }

            final element = _elementGridMap['${period}_$group'];
            if (element != null) {
              rowCells.add(
                _buildElementCell(element, width: colWidth, height: cellHeight),
              );
            } else {
              // Empty spacer
              rowCells.add(SizedBox(width: colWidth, height: cellHeight));
            }
          }

          gridRows.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: rowCells,
              ),
            ),
          );
        }

        // Gap before Lanthanide & Actinide rows
        gridRows.add(const SizedBox(height: 12));

        // Period 8: Lanthanides (cols 3 to 17)
        gridRows.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 2 empty columns (groups 1 and 2)
                SizedBox(width: colWidth),
                SizedBox(width: colWidth),
                // 15 Lanthanide elements (57 to 71)
                for (int group = 3; group <= 17; group++)
                  _elementGridMap['8_$group'] != null
                      ? _buildElementCell(
                          _elementGridMap['8_$group']!,
                          width: colWidth,
                          height: cellHeight,
                        )
                      : SizedBox(width: colWidth),
                // 1 empty column at end
                SizedBox(width: colWidth),
              ],
            ),
          ),
        );

        // Period 9: Actinides (cols 3 to 17)
        gridRows.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 2 empty columns
                SizedBox(width: colWidth),
                SizedBox(width: colWidth),
                // 15 Actinide elements (89 to 103)
                for (int group = 3; group <= 17; group++)
                  _elementGridMap['9_$group'] != null
                      ? _buildElementCell(
                          _elementGridMap['9_$group']!,
                          width: colWidth,
                          height: cellHeight,
                        )
                      : SizedBox(width: colWidth),
                // 1 empty column at end
                SizedBox(width: colWidth),
              ],
            ),
          ),
        );

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: totalWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: gridRows,
            ),
          ),
        );
      },
    );
  }

  Widget _buildElementCell(
    ChemicalElement el, {
    required double width,
    required double height,
  }) {
    final isSelected = _selectedElements.contains(el);
    final isActivePreview =
        _activePreviewElement?.atomicNumber == el.atomicNumber;
    final catColor = el.categoryColor;

    return GestureDetector(
      onTap: () {
        _toggleElementSelection(el);
      },
      onDoubleTap: () {
        setState(() {
          _selectedElements.add(el);
          _activePreviewElement = el;
        });
        _insertSelectedElementsOnCanvas();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: isSelected
              ? catColor.withValues(alpha: 0.38)
              : catColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF38BDF8)
                : (isActivePreview
                      ? Colors.white70
                      : catColor.withValues(alpha: 0.45)),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.5),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Atomic number
                Text(
                  '${el.atomicNumber}',
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),

                // Element Symbol
                Center(
                  child: Text(
                    el.symbol,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),

                // Compact Name
                Text(
                  el.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 7.2,
                    fontWeight: FontWeight.w500,
                    height: 1.0,
                  ),
                ),
              ],
            ),

            // Small check badge when selected
            if (isSelected)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: const BoxDecoration(
                    color: Color(0xFF38BDF8),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 7, color: Colors.black),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeriesPlaceholderCell({
    required String label,
    required String subLabel,
    required Color color,
    required double width,
    required double height,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1.0),
        ),
        padding: const EdgeInsets.all(2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 8.5,
                fontWeight: FontWeight.bold,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subLabel,
              style: TextStyle(
                color: color.withValues(alpha: 0.8),
                fontSize: 7.5,
                fontWeight: FontWeight.w600,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildElementInspector() {
    final selectedCount = _selectedElements.length;
    final el = _activePreviewElement;

    // Empty state: No element selected yet
    if (el == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withValues(alpha: 0.8),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: const Icon(
                LucideIcons.mousePointerClick,
                color: Color(0xFF38BDF8),
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'No Element Selected',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Tap any chemical element above to preview and select for whiteboard',
                  style: TextStyle(color: Colors.white54, fontSize: 11.5),
                ),
              ],
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                disabledBackgroundColor: Colors.white12,
                disabledForegroundColor: Colors.white38,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(LucideIcons.plusCircle, size: 17),
              label: const Text(
                'Select Elements',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    final catColor = el.categoryColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.8),
      ),
      child: Row(
        children: [
          // Enlarged Element Card
          Container(
            width: 66,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: catColor, width: 1.8),
              boxShadow: [
                BoxShadow(
                  color: catColor.withValues(alpha: 0.3),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${el.atomicNumber}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      el.atomicMass,
                      style: TextStyle(
                        color: catColor,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  el.symbol,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
                Text(
                  el.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),

          // Element Metadata & Selected Elements Chips
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Row: Active Element Title & Category
                Row(
                  children: [
                    Text(
                      '${el.name} (${el.symbol})',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: catColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: catColor.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Text(
                        el.category,
                        style: TextStyle(
                          color: catColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),

                    // If multiple selected, show "Clear Selection"
                    if (selectedCount > 1)
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _selectedElements.clear();
                            _activePreviewElement = null;
                          });
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(LucideIcons.trash2, size: 12),
                        label: const Text(
                          'Clear Selection',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),

                // Selected Elements Chips Row (if multiple) OR Metadata Info (if single)
                if (selectedCount > 1) ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _selectedElements.map((selectedEl) {
                        final isPreview =
                            selectedEl.atomicNumber == el.atomicNumber;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () {
                              setState(
                                () => _activePreviewElement = selectedEl,
                              );
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isPreview
                                    ? selectedEl.categoryColor.withValues(
                                        alpha: 0.35,
                                      )
                                    : Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isPreview
                                      ? Colors.white
                                      : selectedEl.categoryColor.withValues(
                                          alpha: 0.5,
                                        ),
                                  width: isPreview ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    selectedEl.symbol,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    selectedEl.name,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  GestureDetector(
                                    onTap: () {
                                      _toggleElementSelection(selectedEl);
                                    },
                                    child: const Icon(
                                      LucideIcons.x,
                                      size: 11,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ] else ...[
                  Wrap(
                    spacing: 12,
                    children: [
                      _buildMetaItem('Atomic Number', '${el.atomicNumber}'),
                      _buildMetaItem('Weight', '${el.atomicMass} u'),
                      _buildMetaItem('Config', el.electronConfiguration),
                      _buildMetaItem('State', el.state),
                      _buildMetaItem('P/G', 'P: ${el.period} • G: ${el.group}'),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 14),

          // Primary Insert Button
          ElevatedButton.icon(
            onPressed: selectedCount > 0
                ? _insertSelectedElementsOnCanvas
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.white12,
              disabledForegroundColor: Colors.white38,
              elevation: 4,
              shadowColor: const Color(0xFF2563EB).withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(LucideIcons.plusCircle, size: 17),
            label: Text(
              selectedCount <= 1
                  ? (selectedCount == 1
                        ? 'Insert ${el.symbol} on Board'
                        : 'Select Element')
                  : 'Insert $selectedCount Elements',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaItem(String title, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$title: ',
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
