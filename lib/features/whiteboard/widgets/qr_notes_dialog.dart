import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/board_storage_service.dart';
import '../state/whiteboard_provider.dart';
import '../../auth/providers/auth_provider.dart';

class QrNotesDialog extends StatefulWidget {
  final GlobalKey canvasKey;

  const QrNotesDialog({super.key, required this.canvasKey});

  static Future<void> show(BuildContext context, GlobalKey canvasKey) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => QrNotesDialog(canvasKey: canvasKey),
    );
  }

  @override
  State<QrNotesDialog> createState() => _QrNotesDialogState();
}

class _QrNotesDialogState extends State<QrNotesDialog> {
  final BoardStorageService _storageService = BoardStorageService();

  bool _isLoading = true;
  String _statusMessage = 'Generating lesson notes PDF & QR code...';
  String? _downloadUrl;
  String? _errorMessage;
  int _pageCount = 1;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _compileAndUploadNotes();
    });
  }

  Future<void> _compileAndUploadNotes() async {
    if (!mounted) return;
    final provider = Provider.of<WhiteboardProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _pageCount = provider.pages.length;
      _statusMessage =
          'Compiling ${_pageCount > 1 ? "$_pageCount slides" : "slide"} into PDF...';
    });

    try {
      // 1. Generate Multi-Page PDF
      final pdfFile = await _storageService.generateMultiPagePdfFile(
        boundaryKey: widget.canvasKey,
        provider: provider,
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _statusMessage = 'Rendering slide $current of $total into PDF...';
            });
          }
        },
      );

      if (!mounted) return;
      setState(() {
        _statusMessage = 'Uploading notes to cloud...';
      });

      // 2. Upload to Firebase Storage
      final teacherId = auth.currentUid;
      final downloadUrl = await _storageService.uploadPdfToFirebaseStorage(
        pdfFile,
        teacherId,
      );

      if (downloadUrl == null || downloadUrl.isEmpty) {
        throw Exception(
          'Failed to retrieve cloud download link for the generated PDF.',
        );
      }

      if (mounted) {
        setState(() {
          _downloadUrl = downloadUrl;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error in QR Notes Generation: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Row(
              children: [
                const Icon(
                  LucideIcons.alertCircle,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Failed to generate QR Notes: $_errorMessage'),
                ),
              ],
            ),
          ),
        );
      }
    }
  }

  void _copyToClipboard() async {
    if (_downloadUrl == null) return;
    await Clipboard.setData(ClipboardData(text: _downloadUrl!));
    if (mounted) {
      setState(() => _copied = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF10B981),
          duration: Duration(seconds: 2),
          content: Text('Download link copied to clipboard!'),
        ),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    }
  }

  void _openInBrowser() async {
    if (_downloadUrl == null) return;
    try {
      final uri = Uri.parse(_downloadUrl!);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching PDF URL: $e');
    }
  }

  void _shareUrl() async {
    if (_downloadUrl == null) return;
    await Share.share(
      'Download our classroom notes PDF ($_pageCount slides): $_downloadUrl',
      subject: 'Classroom Whiteboard Notes PDF',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(
        0xFF1E293B,
      ), // Dark slate matching app design
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12), width: 1),
      ),
      elevation: 20,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: _isLoading
              ? _buildLoadingState()
              : _errorMessage != null
              ? _buildErrorState()
              : _buildQrCodeState(),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 10),
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB).withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF2563EB).withValues(alpha: 0.3),
            ),
          ),
          child: const Center(
            child: CircularProgressIndicator(
              strokeWidth: 3.0,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF38BDF8)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Generating Notes & QR Code...',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _statusMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 18),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white60,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          ),
          child: const Text('Cancel', style: TextStyle(fontSize: 12.5)),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            LucideIcons.alertTriangle,
            color: Colors.redAccent,
            size: 26,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Failed to Generate QR Code',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _errorMessage ??
              'An error occurred while compiling or uploading the PDF.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              child: const Text('Close', style: TextStyle(fontSize: 12.5)),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: _compileAndUploadNotes,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              icon: const Icon(LucideIcons.refreshCw, size: 14),
              label: const Text('Retry', style: TextStyle(fontSize: 12.5)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQrCodeState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    LucideIcons.scanLine,
                    color: Color(0xFF38BDF8),
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    '$_pageCount Slide${_pageCount > 1 ? "s" : ""} • PDF',
                    style: const TextStyle(
                      color: Color(0xFF34D399),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(LucideIcons.x, color: Colors.white70, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Close',
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Title
        const Text(
          'Scan to Download Notes',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 3),

        // Subtitle
        const Text(
          'Scan QR code with your phone camera',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60, fontSize: 11.5),
        ),
        const SizedBox(height: 12),

        // Crisp White QR Card
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: QrImageView(
            data: _downloadUrl!,
            version: QrVersions.auto,
            size: 155.0,
            backgroundColor: Colors.white,
            padding: const EdgeInsets.all(4),
            errorCorrectionLevel: QrErrorCorrectLevel.M,
          ),
        ),
        const SizedBox(height: 12),

        // Action Buttons Row (Copy Link, Open, Share)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildActionButton(
              icon: _copied ? LucideIcons.check : LucideIcons.copy,
              label: _copied ? 'Copied' : 'Copy Link',
              color: _copied ? const Color(0xFF10B981) : Colors.white70,
              onTap: _copyToClipboard,
            ),
            const SizedBox(width: 6),
            _buildActionButton(
              icon: LucideIcons.externalLink,
              label: 'Open',
              color: Colors.white70,
              onTap: _openInBrowser,
            ),
            const SizedBox(width: 6),
            _buildActionButton(
              icon: LucideIcons.share2,
              label: 'Share',
              color: Colors.white70,
              onTap: _shareUrl,
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Done Button
        SizedBox(
          width: double.infinity,
          height: 38,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Done',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
