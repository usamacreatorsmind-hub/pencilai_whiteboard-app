import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../state/whiteboard_provider.dart';

class PageSwitcher extends StatelessWidget {
  const PageSwitcher({super.key});

  void _showDeleteConfirmation(BuildContext context, WhiteboardProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete Page?', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to delete this page? This action cannot be undone.',
            style: TextStyle(color: Colors.grey)),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(LucideIcons.chevronLeft, color: Colors.white, size: isLargeScreen ? 26 : 20),
            onPressed: provider.currentPageIndex > 0 ? () => provider.switchPage(provider.currentPageIndex - 1) : null,
          ),
          Text(
            '${provider.currentPageIndex + 1} / ${provider.pages.length}',
            style: TextStyle(color: Colors.white, fontSize: isLargeScreen ? 18 : 14, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: Icon(LucideIcons.chevronRight, color: Colors.white, size: isLargeScreen ? 26 : 20),
            onPressed: provider.currentPageIndex < provider.pages.length - 1
                ? () => provider.switchPage(provider.currentPageIndex + 1)
                : null,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(LucideIcons.plusSquare, color: Colors.blue, size: isLargeScreen ? 26 : 20),
            onPressed: provider.addPage,
          ),
          if (provider.pages.length > 1)
            IconButton(
              icon: Icon(LucideIcons.trash2, color: Colors.redAccent, size: isLargeScreen ? 26 : 20),
              onPressed: () => _showDeleteConfirmation(context, provider),
            ),
        ],
      ),
    );
  }
}
