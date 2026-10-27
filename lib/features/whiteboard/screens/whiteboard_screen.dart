import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../widgets/whiteboard_canvas.dart';
import '../widgets/toolbar.dart';
import '../widgets/object_handles.dart';
import '../widgets/smart_pen_suggestion_widget.dart';
import '../widgets/slide_overview_sidebar.dart';
import '../widgets/ai_floating_menu_widget.dart';
import '../widgets/ai_result_panel.dart';
import '../widgets/ruler_widget.dart';
import '../widgets/protractor_widget.dart';
import '../widgets/setsquare_widget.dart';
import '../widgets/compass_widget.dart';
import '../models/stroke_element.dart';
import '../models/image_element.dart';
import '../models/document_element.dart';
import 'package:uuid/uuid.dart';
import '../services/board_storage_service.dart';
import '../state/whiteboard_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/widgets/profile_dialog.dart';
import '../../auth/widgets/account_selection_dialog.dart';
import '../widgets/qr_notes_dialog.dart';
import '../widgets/settings_dialog.dart';
import '../widgets/page_switcher.dart';
import '../widgets/split_screen_dialog.dart';
import '../widgets/split_screen_view.dart';
import '../widgets/canvas/canvas_grid_painter.dart';
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
  bool _showRuler = false;
  bool _showProtractor = false;
  bool _showSetSquare = false;
  bool _showCompass = false;
  bool _isConnected = true;
  bool _isSplitScreenActive = false;
  int _splitCount = 2;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    // Ensure immersive mode is active when screen starts
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _checkInitialConnectivity();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      final connected = !results.contains(ConnectivityResult.none);
      if (mounted && _isConnected != connected) {
        setState(() => _isConnected = connected);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<WhiteboardProvider>(context, listen: false).canvasKey =
          _canvasKey;
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
    super.dispose();
  }

  void _handleLoginOrProfile() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.isLoggedIn) {
      ProfileDialog.show(context);
    } else {
      AccountSelectionDialog.show(context);
    }
  }

  /// Global (screen) points -> canvas coords (pan hata ke)
  List<Offset> _toCanvasPoints(List<Offset> globalPoints) {
    final renderBox =
        _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return const [];
    final provider = Provider.of<WhiteboardProvider>(context, listen: false);
    return globalPoints
        .map((gp) => provider.screenToCanvas(renderBox.globalToLocal(gp)))
        .toList();
  }

  void _addStrokeFromGlobal(List<Offset> globalPoints) {
    final pts = _toCanvasPoints(globalPoints);
    if (pts.length < 2) return;
    final provider = Provider.of<WhiteboardProvider>(context, listen: false);
    provider.addElement(
      StrokeElement(
        id: const Uuid().v4(),
        position: pts.first,
        points: pts,
        color: provider.currentColor,
        strokeWidth: provider.strokeWidth,
        penType: provider.currentPenType,
        docPage: provider.isDocumentOverlayOpen
            ? provider.overlayCurrentPage
            : null,
      ),
    );
  }

  void _handleSave() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Export Board',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Choose a format to save your slide.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await _storageService.exportToImage(_canvasKey);
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
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _handleDirectWhatsAppShare();
            },
            icon: const Icon(LucideIcons.share2, size: 14),
            label: const Text(
              'Share Notes',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
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
        content: const Text(
          'Are you sure you want to close the app?',
          style: TextStyle(color: Colors.grey),
        ),
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

  void _showMenuPopup(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (menuContext) => Stack(
        children: [
          Positioned(
            bottom: 70,
            left: 24,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 200,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9), // Light background
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Consumer<AuthProvider>(
                      builder: (context, auth, _) {
                        final bool isLoggedIn = auth.isLoggedIn;
                        return _buildMenuItem(
                          menuContext,
                          isLoggedIn
                              ? LucideIcons.userCheck
                              : LucideIcons.logIn,
                          isLoggedIn ? auth.displayName : 'Login',
                          () {
                            Navigator.pop(menuContext);
                            _handleLoginOrProfile();
                          },
                        );
                      },
                    ),
                    const Divider(height: 1, color: Colors.black12),
                    _buildMenuItem(
                      menuContext,
                      LucideIcons.filePlus,
                      'New',
                      () {
                        Navigator.pop(menuContext);
                        _handleNewBoard();
                      },
                    ),
                    _buildMenuItem(
                      menuContext,
                      LucideIcons.folderOpen,
                      'Open',
                      () {
                        Navigator.pop(menuContext);
                        _handleOpenFile();
                      },
                    ),
                    _buildMenuItem(menuContext, LucideIcons.save, 'Save', () {
                      Navigator.pop(menuContext);
                      _handleSave();
                    }),
                    _buildMenuItem(
                      menuContext,
                      LucideIcons.fileText,
                      'Save as',
                      () {
                        Navigator.pop(menuContext);
                        _handleSaveAs();
                      },
                    ),
                    _buildMenuItem(
                      menuContext,
                      LucideIcons.scanLine,
                      'Scan',
                      () {
                        Navigator.pop(menuContext);
                        _handleScan();
                      },
                    ),
                    const Divider(height: 1, color: Colors.black12),
                    _buildMenuItem(
                      menuContext,
                      LucideIcons.settings,
                      'Settings',
                      () {
                        Navigator.pop(menuContext);
                        _showSettingsDialog(context);
                      },
                    ),
                    const Divider(height: 1, color: Colors.black12),
                    _buildMenuItem(menuContext, LucideIcons.logOut, 'Exit', () {
                      Navigator.pop(menuContext);
                      _handleExit();
                    }, isRed: true),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    SettingsDialog.show(context);
  }

  void _showSplitScreenDialog(BuildContext context) {
    SplitScreenDialog.show(
      context,
      anchorOffset: const Offset(24, 0),
      onSelectSplit: (count) {
        setState(() {
          _isSplitScreenActive = true;
          _splitCount = count;
        });
      },
    );
  }

  Widget _buildMenuItem(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool isRed = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isRed ? Colors.red : const Color(0xFF334155),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isRed ? Colors.red : const Color(0xFF1E293B),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleNewBoard() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('New Board', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Do you want to save your current work before starting a new board?',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _handleSave();
            },
            child: const Text('Save', style: TextStyle(color: Colors.blue)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              final provider = Provider.of<WhiteboardProvider>(
                context,
                listen: false,
              );
              provider.clearCurrentPage();
            },
            child: const Text(
              'Don\'t Save',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _handleOpenFile() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final provider = Provider.of<WhiteboardProvider>(context, listen: false);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.any,
      );
      if (result != null && result.files.isNotEmpty) {
        final picked = result.files.single;
        final fileName = picked.name;
        final ext = (picked.extension ??
                (fileName.contains('.') ? fileName.split('.').last : ''))
            .toLowerCase();

        const allowedExts = [
          'jpg',
          'png',
          'jpeg',
          'pdf',
          'ppt',
          'pptx',
          'doc',
          'docx',
        ];


        if (!allowedExts.contains(ext)) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFFD97706),
              content: Text('Unsupported format: .$ext. Please select an image or document.'),
              duration: const Duration(seconds: 4),
            ),
          );
          return;
        }

        String? filePath = picked.path;
        if (filePath == null && picked.bytes != null) {
          final tempDir = await getTemporaryDirectory();
          final tempFile = File(
            '${tempDir.path}/opened_${DateTime.now().millisecondsSinceEpoch}_$fileName',
          );
          await tempFile.writeAsBytes(picked.bytes!);
          filePath = tempFile.path;
        }

        if (filePath == null || !File(filePath).existsSync()) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text('Could not access selected file.'),
            ),
          );
          return;
        }

        if (ext == 'jpg' || ext == 'png' || ext == 'jpeg') {
          provider.addElement(
            ImageElement(
              id: const Uuid().v4(),
              position: provider.screenToCanvas(Offset.zero),
              imageUrl: filePath,
              size: const Size(600, 450),
            ),
          );
        } else {
          provider.addElement(
            DocumentElement(
              id: const Uuid().v4(),
              position: provider.screenToCanvas(Offset.zero),
              filePath: filePath,
              fileName: fileName,
              size: const Size(600, 800),
            ),
          );
        }
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text('File opened successfully!'),
          ),
        );
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Failed to open file: $e'),
        ),
      );
    }
  }

  void _handleSaveAs() {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController(
      text: 'Whiteboard_${DateTime.now().millisecondsSinceEpoch}',
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Save As', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'File Name',
            labelStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.grey),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.blue),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              final fileName = controller.text.trim();
              Navigator.pop(context);
              if (fileName.isNotEmpty) {
                try {
                  await _storageService.exportToImage(_canvasKey);
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      backgroundColor: Colors.green,
                      content: Text('Saved as "$fileName" successfully!'),
                    ),
                  );
                } catch (e) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      backgroundColor: Colors.red,
                      content: Text('Failed to save: $e'),
                    ),
                  );
                }
              }
            },
            child: const Text(
              'Save',
              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _handleScan() {
    QrNotesDialog.show(context, _canvasKey);
  }

  void _handleDirectWhatsAppShare() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final whiteboardProvider = Provider.of<WhiteboardProvider>(
      context,
      listen: false,
    );
    final auth = Provider.of<AuthProvider>(context, listen: false);

    scaffoldMessenger.showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF25D366),
        content: Text('Generating notes PDF & preparing WhatsApp...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final pdfFile = await _storageService.generateMultiPagePdfFile(
        boundaryKey: _canvasKey,
        provider: whiteboardProvider,
      );

      final teacherId = auth.currentUid;
      final pdfUrl = await _storageService.uploadPdfToFirebaseStorage(
        pdfFile,
        teacherId,
      );

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

      String whatsappUrlStr =
          "https://wa.me/?text=${Uri.encodeComponent(textMessage)}";

      if (auth.students.isNotEmpty) {
        final firstStudent = auth.students.first;
        final phone = firstStudent['mobileNumber'] ?? '';
        final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
        if (cleanPhone.length >= 10) {
          final targetPhone = cleanPhone.startsWith('91')
              ? cleanPhone
              : '91$cleanPhone';
          whatsappUrlStr =
              "https://wa.me/$targetPhone?text=${Uri.encodeComponent(textMessage)}";
        }
      }

      final uri = Uri.parse(whatsappUrlStr);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        final fallbackUri = Uri.parse(
          "https://wa.me/?text=${Uri.encodeComponent(textMessage)}",
        );
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error opening WhatsApp app/web: $e');
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Failed to open WhatsApp: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isSplitScreenActive) {
      return SplitScreenView(
        splitCount: _splitCount,
        onExit: () => setState(() => _isSplitScreenActive = false),
      );
    }

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
                color: const Color(
                  0xFFDC2626,
                ), // Red strip for No Internet Connection
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(LucideIcons.wifiOff, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'No Internet Connection',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Consumer<WhiteboardProvider>(
                    builder: (context, provider, _) {
                      final hasCustomBg =
                          provider.canvasBackgroundImagePath != null &&
                          File(provider.canvasBackgroundImagePath!).existsSync();

                      return RepaintBoundary(
                        key: _canvasKey,
                        child: Container(
                          decoration: hasCustomBg
                              ? BoxDecoration(
                                  color: provider.canvasBackgroundColor,
                                  image: DecorationImage(
                                    image: FileImage(
                                      File(provider.canvasBackgroundImagePath!),
                                    ),
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : BoxDecoration(
                                  color: provider.canvasBackgroundColor,
                                ),
                          child: CustomPaint(
                            painter: CanvasGridPainter(
                              backgroundColor: hasCustomBg
                                  ? Colors.transparent
                                  : provider.canvasBackgroundColor,
                              gridType: provider.canvasGridType,
                              panOffset: provider.canvasPanOffset,
                            ),
                            child: const WhiteboardCanvas(),
                          ),
                        ),
                      );
                    },
                  ),
                  const ObjectHandles(),
                  const SmartPenSuggestionWidget(),
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
                      child: SlideOverviewSidebar(
                        onClose: () => setState(() => _isSidebarOpen = false),
                      ),
                    ),
                  ],
                  Positioned(
                    bottom: 10,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: WhiteboardToolbar(
                        onOpenRuler: () => setState(() => _showRuler = true),
                        onOpenProtractor: () =>
                            setState(() => _showProtractor = true),
                        onOpenSetSquare: () =>
                            setState(() => _showSetSquare = true),
                        onOpenCompass: () =>
                            setState(() => _showCompass = true),
                      ),
                    ),
                  ),
                  if (_showRuler)
                    RulerWidget(
                      initialPosition: Offset(
                        MediaQuery.of(context).size.width / 2 - 220,
                        MediaQuery.of(context).size.height / 2 - 55,
                      ),
                      onClose: () => setState(() => _showRuler = false),
                      onDrawLine: (points) {
                        _addStrokeFromGlobal(points);
                      },
                    ),
                  if (_showProtractor)
                    ProtractorWidget(
                      initialPosition: Offset(
                        MediaQuery.of(context).size.width / 2 - 180,
                        MediaQuery.of(context).size.height / 2 - 95,
                      ),
                      onClose: () => setState(() => _showProtractor = false),
                      onDrawAngle: (shape) {
                        _addStrokeFromGlobal(shape.strokePoints);
                        if (shape.markerPoints.isNotEmpty) {
                          _addStrokeFromGlobal(shape.markerPoints);
                        }
                      },
                    ),
                  if (_showSetSquare)
                    SetSquareWidget(
                      initialPosition: Offset(
                        MediaQuery.of(context).size.width / 2 - 140,
                        MediaQuery.of(context).size.height / 2 - 100,
                      ),
                      onClose: () => setState(() => _showSetSquare = false),
                      onDrawLine: (points) {
                        _addStrokeFromGlobal(points);
                      },
                    ),
                  if (_showCompass)
                    CompassWidget(
                      initialPosition: Offset(
                        MediaQuery.of(context).size.width / 2 - 130,
                        MediaQuery.of(context).size.height / 2 - 130,
                      ),
                      onClose: () => setState(() => _showCompass = false),
                      onDrawArc: (points) {
                        _addStrokeFromGlobal(points);
                      },
                    ),
                  Positioned(
                    bottom: 10,
                    right: 30,
                    child: PageSwitcher(
                      onPageCountTap: () =>
                          setState(() => _isSidebarOpen = !_isSidebarOpen),
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    left: 24,
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: const Color(0xFFCBD5E1),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.16),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Menu Button
                          InkWell(
                            onTap: () => _showMenuPopup(context),
                            borderRadius: BorderRadius.circular(10),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 2,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    LucideIcons.menu,
                                    size: 17,
                                    color: Color(0xFF334155),
                                  ),
                                  SizedBox(height: 1),
                                  Text(
                                    'Menu',
                                    style: TextStyle(
                                      color: Color(0xFF334155),
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 22,
                            color: const Color(0xFFCBD5E1),
                          ),
                          // SplitScreen Button
                          InkWell(
                            onTap: () => _showSplitScreenDialog(context),
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 2,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 5.5,
                                        height: 14,
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: const Color(0xFF334155),
                                            width: 1.4,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      Container(
                                        width: 5.5,
                                        height: 14,
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: const Color(0xFF334155),
                                            width: 1.4,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 1.5),
                                  const Text(
                                    'SplitScreen',
                                    style: TextStyle(
                                      color: Color(0xFF334155),
                                      fontSize: 9.0,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
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
