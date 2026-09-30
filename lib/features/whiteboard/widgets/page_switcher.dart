import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../state/whiteboard_provider.dart';

class PageSwitcher extends StatelessWidget {
  final VoidCallback? onPageCountTap;

  const PageSwitcher({super.key, this.onPageCountTap});

  void _showDeleteConfirmation(BuildContext context, WhiteboardProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete Page?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to delete this page? This action cannot be undone.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              provider.deletePage(provider.currentPageIndex);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<WhiteboardProvider>(context);
    final isLargeScreen = MediaQuery.of(context).size.width > 1200;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0), // Light silver frosted container
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF64748B), width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Previous Page Button
          IconButton(
            icon: Icon(
              LucideIcons.chevronLeft,
              color: provider.currentPageIndex > 0 ? const Color(0xFF0284C7) : const Color(0xFF94A3B8),
              size: isLargeScreen ? 20 : 16,
            ),
            onPressed: provider.currentPageIndex > 0 ? () => provider.switchPage(provider.currentPageIndex - 1) : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 6),

          // Page Number Text (Tapping opens Slide Overview Sidebar)
          GestureDetector(
            onTap: onPageCountTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: Colors.black.withValues(alpha: 0.05)),
              child: Text(
                '${provider.currentPageIndex + 1} / ${provider.pages.length}',
                style: TextStyle(color: const Color(0xFF0F172A), fontSize: isLargeScreen ? 13 : 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Next Page Button
          IconButton(
            icon: Icon(
              LucideIcons.chevronRight,
              color: provider.currentPageIndex < provider.pages.length - 1 ? const Color(0xFF0284C7) : const Color(0xFF94A3B8),
              size: isLargeScreen ? 20 : 16,
            ),
            onPressed: provider.currentPageIndex < provider.pages.length - 1
                ? () => provider.switchPage(provider.currentPageIndex + 1)
                : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 10),

          // ADD PAGE Button Item
          GestureDetector(
            onTap: provider.addPage,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.plusSquare,
                    color: const Color(0xFF0D9488), // Teal/Mint
                    size: isLargeScreen ? 20 : 16,
                  ),
                ],
              ),
            ),
          ),

          // Delete Page Icon
          if (provider.pages.length > 1) ...[
            const SizedBox(width: 6),
            IconButton(
              icon: Icon(LucideIcons.trash2, color: Colors.redAccent, size: isLargeScreen ? 18 : 14),
              onPressed: () => _showDeleteConfirmation(context, provider),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ],
      ),
    );
  }
}
