import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../widgets/whiteboard_canvas.dart';
import '../widgets/toolbar.dart';
import '../widgets/object_handles.dart';
import '../widgets/page_switcher.dart';
import '../widgets/slide_overview_sidebar.dart';
import '../services/board_storage_service.dart';
import '../state/whiteboard_provider.dart';

class WhiteboardScreen extends StatefulWidget {
  const WhiteboardScreen({super.key});

  @override
  State<WhiteboardScreen> createState() => _WhiteboardScreenState();
}

class _WhiteboardScreenState extends State<WhiteboardScreen> {
  final GlobalKey _canvasKey = GlobalKey();
  final BoardStorageService _storageService = BoardStorageService();
  bool _isSidebarOpen = false;

  @override
  void initState() {
    super.initState();
    // Ensure immersive mode is active when screen starts
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _handleSave() async {
    // Yeh screen ka asli context/messenger hai — dialog se pehle capture karo
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Export Board', style: TextStyle(color: Colors.white)),
        content: const Text('Choose a format to save your slide.', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                final path = await _storageService.exportToImage(_canvasKey);
                if (mounted) {
                  scaffoldMessenger.showSnackBar(const SnackBar(backgroundColor: Colors.green, content: Text('Image saved successfully!')));
                }
              } catch (e) {
                if (mounted) {
                  scaffoldMessenger.showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text('Failed to save image: $e')));
                }
              }
            },
            child: const Text(
              'Save as PNG',
              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                final path = await _storageService.exportToPdf(_canvasKey);
                if (path != null && mounted) {
                  scaffoldMessenger.showSnackBar(const SnackBar(backgroundColor: Colors.green, content: Text('PDF saved successfully!')));
                }
              } catch (e) {
                if (mounted) {
                  scaffoldMessenger.showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text('Failed to save PDF: $e')));
                }
              }
            },
            child: const Text(
              'Save as PDF',
              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _handleExit() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Exit App?', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to close the app?', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => SystemNavigator.pop(),
            child: const Text('Exit', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      bottom: false,
      child: Scaffold(
        backgroundColor: Colors.grey[900],
        body: Stack(
          children: [
            Consumer<WhiteboardProvider>(
              builder: (context, provider, _) => RepaintBoundary(
                key: _canvasKey,
                child: Container(color: provider.canvasBackgroundColor, child: const WhiteboardCanvas()),
              ),
            ),
            const ObjectHandles(),
            if (_isSidebarOpen) ...[
              // Backdrop barrier to close sidebar when tapping anywhere on the whiteboard screen
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) {
                    if (_isSidebarOpen) {
                      setState(() => _isSidebarOpen = false);
                    }
                  },
                  child: Container(color: Colors.transparent),
                ),
              ),
              Positioned(
                top: 10,
                right: 20,
                bottom: 65,
                child: SlideOverviewSidebar(onClose: () => setState(() => _isSidebarOpen = false)),
              ),
            ],
            Positioned(bottom: 10, left: 0, right: 0, child: Center(child: const WhiteboardToolbar())),
            Positioned(
              bottom: 10,
              right: 30,
              child: PageSwitcher(
                onPageCountTap: () => setState(() => _isSidebarOpen = !_isSidebarOpen),
              ),
            ),
            Positioned(
              bottom: 10,
              left: 24,
              child: _CircularActionButton(
                icon: LucideIcons.logOut,
                label: 'EXIT',
                accentColor: const Color(0xFFF97316), // Warm Orange
                onTap: _handleExit,
              ),
            ),
            Positioned(
              bottom: 10,
              left: 78,
              child: _CircularActionButton(
                icon: LucideIcons.save,
                label: 'SAVE',
                accentColor: const Color(0xFF10B981), // Emerald Green
                onTap: _handleSave,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircularActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accentColor;
  final VoidCallback onTap;

  const _CircularActionButton({
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
         
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: accentColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: accentColor, size: 16),
            const SizedBox(height: 1),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 7.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
