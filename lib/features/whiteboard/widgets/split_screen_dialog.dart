import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Mini overlay dialog for selecting Split Screen mode (2 Split, 3 Split, 4 Split)
class SplitScreenDialog extends StatelessWidget {
  final ValueChanged<int> onSelectSplit;

  const SplitScreenDialog({super.key, required this.onSelectSplit});

  static Future<void> show(
    BuildContext context, {
    required ValueChanged<int> onSelectSplit,
    Offset? anchorOffset,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black38,
      builder: (dialogContext) {
        return Stack(
          children: [
            Positioned(
              bottom: 72,
              left: anchorOffset?.dx ?? 150,
              child: Material(
                color: Colors.transparent,
                child: SplitScreenDialog(
                  onSelectSplit: (count) {
                    Navigator.of(dialogContext).pop();
                    onSelectSplit(count);
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    LucideIcons.columns2,
                    size: 16,
                    color: Color(0xFF0F172A),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Split Screen',
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(LucideIcons.x, size: 16, color: Color(0xFF64748B)),
                onPressed: () => Navigator.of(context).pop(),
                splashRadius: 14,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 3 Options: 2 Split, 3 Split, 4 Split
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSplitOption(
                context: context,
                splitCount: 2,
                label: '2 Split',
              ),
              _buildSplitOption(
                context: context,
                splitCount: 3,
                label: '3 Split',
              ),
              _buildSplitOption(
                context: context,
                splitCount: 4,
                label: '4 Split',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSplitOption({
    required BuildContext context,
    required int splitCount,
    required String label,
  }) {
    return InkWell(
      onTap: () => onSelectSplit(splitCount),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 68,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFCBD5E1), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Preview Graphic
            Container(
              height: 32,
              width: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(5),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
              child: Row(
                children: List.generate(splitCount, (index) {
                  return Expanded(
                    child: Container(
                      margin: EdgeInsets.only(
                        right: index < splitCount - 1 ? 1.5 : 0,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF334155),
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                          width: 0.5,
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 8,
                          height: 1.5,
                          decoration: BoxDecoration(
                            color: const Color(0xFF38BDF8),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
