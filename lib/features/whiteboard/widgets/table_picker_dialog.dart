import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class TablePickerDialog extends StatefulWidget {
  final Function(int rows, int cols) onTableSelected;
  final int maxRows;
  final int maxCols;

  const TablePickerDialog({
    super.key,
    required this.onTableSelected,
    this.maxRows = 8,
    this.maxCols = 8,
  });

  @override
  State<TablePickerDialog> createState() => _TablePickerDialogState();
}

class _TablePickerDialogState extends State<TablePickerDialog> {
  int _selectedRows = 3;
  int _selectedCols = 3;

  static const double _cellSize = 28.0;
  static const double _cellSpacing = 4.0;

  void _updateSelection(Offset localPosition) {
    final double step = _cellSize + _cellSpacing;
    final int col = (localPosition.dx / step).floor() + 1;
    final int row = (localPosition.dy / step).floor() + 1;

    final clampedRows = row.clamp(1, widget.maxRows);
    final clampedCols = col.clamp(1, widget.maxCols);

    if (clampedRows != _selectedRows || clampedCols != _selectedCols) {
      setState(() {
        _selectedRows = clampedRows;
        _selectedCols = clampedCols;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0284C7); // Vibrant Blue Accent

    return Dialog(
      backgroundColor: const Color(0xFF1E293B), // Dark Slate Theme
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.15), width: 1.2),
      ),
      elevation: 12,
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(LucideIcons.table, color: primaryColor, size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Insert Table',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(LucideIcons.x, color: Colors.grey, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Selection Info Badge
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: primaryColor.withValues(alpha: 0.4), width: 1.0),
                ),
                child: Text(
                  '$_selectedRows × $_selectedCols Table',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Interactive Grid Selector
            Center(
              child: GestureDetector(
                onPanStart: (d) => _updateSelection(d.localPosition),
                onPanUpdate: (d) => _updateSelection(d.localPosition),
                onTapDown: (d) => _updateSelection(d.localPosition),
                child: SizedBox(
                  width: widget.maxCols * _cellSize + (widget.maxCols - 1) * _cellSpacing,
                  height: widget.maxRows * _cellSize + (widget.maxRows - 1) * _cellSpacing,
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: widget.maxRows * widget.maxCols,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: widget.maxCols,
                      crossAxisSpacing: _cellSpacing,
                      mainAxisSpacing: _cellSpacing,
                    ),
                    itemBuilder: (context, index) {
                      final row = (index ~/ widget.maxCols) + 1;
                      final col = (index % widget.maxCols) + 1;

                      final bool isSelected = row <= _selectedRows && col <= _selectedCols;

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        decoration: BoxDecoration(
                          color: isSelected ? primaryColor : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isSelected ? primaryColor : Colors.white.withValues(alpha: 0.2),
                            width: 1.0,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: primaryColor.withValues(alpha: 0.4),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ]
                              : null,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey.shade400,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onTableSelected(_selectedRows, _selectedCols);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                    child: const Text(
                      'Insert Table',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
