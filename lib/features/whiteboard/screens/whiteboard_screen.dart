import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../widgets/whiteboard_canvas.dart';
import '../widgets/toolbar.dart';
import '../widgets/object_handles.dart';
import '../widgets/page_switcher.dart';
import '../widgets/slide_overview_sidebar.dart';
import '../widgets/ai_floating_menu_widget.dart';
import '../widgets/ai_result_panel.dart';
import '../services/board_storage_service.dart';
import '../state/whiteboard_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/widgets/profile_dialog.dart';
import '../../auth/widgets/account_selection_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

class WhiteboardScreen extends StatefulWidget {
  const WhiteboardScreen({super.key});

  @override
  State<WhiteboardScreen> createState() => _WhiteboardScreenState();
}

class _WhiteboardScreenState extends State<WhiteboardScreen> {
  final GlobalKey _canvasKey = GlobalKey();
  final BoardStorageService _storageService = BoardStorageService();
  bool _isSidebarOpen = false;
  bool _dialogShown = false;
  bool _isConnected = true;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    // Ensure immersive mode is active when screen starts
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _checkInitialConnectivity();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final connected = !results.contains(ConnectivityResult.none);
      if (mounted && _isConnected != connected) {
        setState(() => _isConnected = connected);
      }
    });

    // Listen to AuthProvider for async account loading completion
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<WhiteboardProvider>(context, listen: false).canvasKey = _canvasKey;
      final auth = Provider.of<AuthProvider>(context, listen: false);
      auth.addListener(_onAuthStateChanged);
      _checkAndShowAccountSelection();
    });
  }

  Future<void> _checkInitialConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    final connected = !results.contains(ConnectivityResult.none);
    if (mounted) {
      setState(() => _isConnected = connected);
    }
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    auth.removeListener(_onAuthStateChanged);
    super.dispose();
  }

  void _onAuthStateChanged() {
    if (!_dialogShown && mounted) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.hasLoadedRecentAccounts && !auth.isLoggedIn) {
        _dialogShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            AccountSelectionDialog.show(context);
          }
        });
      }
    }
  }

  void _checkAndShowAccountSelection() {
    if (!_dialogShown && mounted) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.hasLoadedRecentAccounts && !auth.isLoggedIn) {
        _dialogShown = true;
        AccountSelectionDialog.show(context);
      }
    }
  }

  void _handleSave() async {
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
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _handleDirectWhatsAppShare();
            },
            icon: const Icon(LucideIcons.share2, size: 14),
            label: const Text('Share Notes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white),
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

  void _handleDirectWhatsAppShare() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final whiteboardProvider = Provider.of<WhiteboardProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);

    scaffoldMessenger.showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF25D366),
        content: Text('Generating notes PDF & preparing WhatsApp...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final pdfFile = await _storageService.generateMultiPagePdfFile(boundaryKey: _canvasKey, provider: whiteboardProvider);

      final teacherId = auth.currentUid;
      final pdfUrl = await _storageService.uploadPdfToFirebaseStorage(pdfFile, teacherId);

      final teacherName = auth.displayName;
      final classroomName = auth.activeClassroomName ?? 'Classroom';
      final textMessage =
          "Hello Students 👋,\n\nHere are the whiteboard class notes from $teacherName (Classroom: $classroomName).\n\n📄 Notes PDF Link: ${pdfUrl ?? 'Generated PDF Notes'}";

      // Copy text to clipboard so teacher can paste instantly even if browser landing page opens
      await Clipboard.setData(ClipboardData(text: textMessage));

      scaffoldMessenger.showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF25D366),
          content: Text('Notes copied to clipboard! Opening WhatsApp...'),
          duration: Duration(seconds: 2),
        ),
      );

      String whatsappUrlStr = "https://wa.me/?text=${Uri.encodeComponent(textMessage)}";

      if (auth.students.isNotEmpty) {
        final firstStudent = auth.students.first;
        final phone = firstStudent['mobileNumber'] ?? '';
        final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
        if (cleanPhone.length >= 10) {
          final targetPhone = cleanPhone.startsWith('91') ? cleanPhone : '91$cleanPhone';
          whatsappUrlStr = "https://wa.me/$targetPhone?text=${Uri.encodeComponent(textMessage)}";
        }
      }

      final uri = Uri.parse(whatsappUrlStr);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        final fallbackUri = Uri.parse("https://wa.me/?text=${Uri.encodeComponent(textMessage)}");
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error opening WhatsApp app/web: $e');
      if (mounted) {
        scaffoldMessenger.showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text('Failed to open WhatsApp: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      bottom: false,
      child: Scaffold(
        backgroundColor: Colors.grey[900],
        body: Column(
          children: [
            if (!_isConnected)
              Container(
                width: double.infinity,
                color: const Color(0xFFDC2626), // Red strip for No Internet Connection
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(LucideIcons.wifiOff, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'No Internet Connection',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  Consumer<WhiteboardProvider>(
                    builder: (context, provider, _) => RepaintBoundary(
                      key: _canvasKey,
                      child: Container(color: provider.canvasBackgroundColor, child: const WhiteboardCanvas()),
                    ),
                  ),
                  const ObjectHandles(),
                  const AiFloatingMenuWidget(),
                  const AiResultPanel(),
                  if (_isSidebarOpen) ...[
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
                  Positioned(bottom: 10, right: 30, child: PageSwitcher(onPageCountTap: () => setState(() => _isSidebarOpen = !_isSidebarOpen))),
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
                  Positioned(
                    bottom: 10,
                    left: 132,
                    child: Consumer<AuthProvider>(
                      builder: (context, auth, _) {
                        return _CircularActionButton(
                          icon: auth.isLoggedIn ? LucideIcons.userCheck : LucideIcons.user,
                          label: auth.displayName,
                          accentColor: const Color(0xFF38BDF8), // Sky Blue
                          onTap: () {
                            if (auth.isLoggedIn) {
                              ProfileDialog.show(context);
                            } else {
                              AccountSelectionDialog.show(context);
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircularActionButton extends StatelessWidget {
  final IconData? icon;
  final String? assetIconPath;
  final String label;
  final Color accentColor;
  final VoidCallback onTap;

  const _CircularActionButton({this.icon, this.assetIconPath, required this.label, required this.accentColor, required this.onTap});

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
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 3))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (assetIconPath != null)
              Image.asset(assetIconPath!, width: 18, height: 18)
            else if (icon != null)
              Icon(icon, color: accentColor, size: 16),
            const SizedBox(height: 1),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 7.5, fontWeight: FontWeight.bold, letterSpacing: 0.1),
            ),
          ],
        ),
      ),
    );
  }
}
