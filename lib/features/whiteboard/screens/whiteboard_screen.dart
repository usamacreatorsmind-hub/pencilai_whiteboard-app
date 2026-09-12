import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../widgets/whiteboard_canvas.dart';
import '../widgets/toolbar.dart';
import '../widgets/object_handles.dart';
import '../widgets/page_switcher.dart';
import '../services/board_storage_service.dart';

class WhiteboardScreen extends StatefulWidget {
  const WhiteboardScreen({super.key});

  @override
  State<WhiteboardScreen> createState() => _WhiteboardScreenState();
}

class _WhiteboardScreenState extends State<WhiteboardScreen> {
  final GlobalKey _canvasKey = GlobalKey();
  final BoardStorageService _storageService = BoardStorageService();

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
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      backgroundColor: Colors.green,
                      content: Text('Image saved successfully!'),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      backgroundColor: Colors.red,
                      content: Text('Failed to save image: $e'),
                    ),
                  );
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
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      backgroundColor: Colors.green,
                      content: Text('PDF saved successfully!'),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      backgroundColor: Colors.red,
                      content: Text('Failed to save PDF: $e'),
                    ),
                  );
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
            RepaintBoundary(
              key: _canvasKey,
              child: Container(color: Colors.white, child: const WhiteboardCanvas()),
            ),
            const ObjectHandles(),
            Positioned(bottom: 20, left: 0, right: 0, child: Center(child: const WhiteboardToolbar())),
            Positioned(bottom: 20, right: 30, child: const PageSwitcher()),
            Positioned(
              bottom: 20,
              left: 30,
              child: FloatingActionButton(
                heroTag: 'exit_btn',
                onPressed: _handleExit,
                backgroundColor: const Color(0xFF1E1E1E),
                child: const Icon(LucideIcons.logOut, color: Colors.white),
              ),
            ),
            Positioned(
              bottom: 20,
              left: 100,
              child: FloatingActionButton(
                heroTag: 'save_btn',
                onPressed: _handleSave,
                backgroundColor: const Color(0xFF1E1E1E),
                child: const Icon(LucideIcons.save, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
