import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/auth_provider.dart';
import '../../whiteboard/services/board_storage_service.dart';
import '../../whiteboard/state/whiteboard_provider.dart';

class ShareNotesDialog extends StatefulWidget {
  final GlobalKey canvasKey;

  const ShareNotesDialog({super.key, required this.canvasKey});

  static Future<void> show(BuildContext context, GlobalKey canvasKey) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => ShareNotesDialog(canvasKey: canvasKey),
    );
  }

  @override
  State<ShareNotesDialog> createState() => _ShareNotesDialogState();
}

class _ShareNotesDialogState extends State<ShareNotesDialog> {
  final BoardStorageService _storageService = BoardStorageService();

  bool _isGenerating = true;
  String? _statusText = 'Compiling slides into PDF...';
  File? _generatedPdfFile;
  String? _pdfDownloadUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _generateAndUploadPdf();
    });
  }

  Future<void> _generateAndUploadPdf() async {
    final whiteboardProvider = Provider.of<WhiteboardProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);

    try {
      setState(() {
        _isGenerating = true;
        _statusText = 'Compiling ${whiteboardProvider.pages.length} slide(s) into PDF...';
      });

      // 1. Generate multi-page PDF File
      final pdfFile = await _storageService.generateMultiPagePdfFile(boundaryKey: widget.canvasKey, provider: whiteboardProvider);

      setState(() {
        _statusText = 'Uploading notes to cloud...';
        _generatedPdfFile = pdfFile;
      });

      // 2. Upload to Firebase Storage for direct download link
      final teacherId = auth.currentUid;
      final url = await _storageService.uploadPdfToFirebaseStorage(pdfFile, teacherId);

      if (mounted) {
        setState(() {
          _pdfDownloadUrl = url;
          _isGenerating = false;
        });
      }
    } catch (e) {
      debugPrint('Error preparing PDF notes: $e');
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  String _formatPhoneNumber(String rawNumber) {
    String clean = rawNumber.replaceAll(RegExp(r'\D'), '');
    if (clean.length == 10) {
      return '91$clean';
    } else if (clean.startsWith('91') && clean.length == 12) {
      return clean;
    }
    return clean;
  }

  Future<void> _shareToWhatsAppIndividual({
    required String studentName,
    required String mobileNumber,
    required String teacherName,
    required String classroomName,
  }) async {
    String formattedPhone = _formatPhoneNumber(mobileNumber);
    String pdfText = _pdfDownloadUrl ?? 'Classroom Notes PDF';
    String message =
        "Hello $studentName 👋,\n\nHere are the whiteboard class notes from $teacherName (Classroom: $classroomName).\n\n📄 Download Notes PDF:\n$pdfText";

    if (formattedPhone.isNotEmpty) {
      final whatsappUrl = Uri.parse("https://wa.me/$formattedPhone?text=${Uri.encodeComponent(message)}");
      try {
        bool launched = await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
        if (!launched) {
          // Fallback to share sheet
          await Share.share(message);
        }
      } catch (e) {
        await Share.share(message);
      }
    } else {
      await Share.share(message);
    }
  }

  Future<void> _shareToWhatsAppGroup({required String teacherName, required String classroomName}) async {
    String pdfText = _pdfDownloadUrl ?? '';
    String textMessage =
        "Hello Students 👋,\n\nHere are today's whiteboard class notes from $teacherName (Classroom: $classroomName).\n\n📄 Notes Link: $pdfText";

    if (_generatedPdfFile != null && await _generatedPdfFile!.exists()) {
      await Share.shareXFiles([XFile(_generatedPdfFile!.path)], text: textMessage, subject: 'Class Notes - $classroomName');
    } else {
      await Share.share(textMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final whiteboardProvider = Provider.of<WhiteboardProvider>(context);

    final teacherName = auth.displayName;
    final classroomName = auth.activeClassroomName ?? 'Classroom';
    final students = auth.students;

    return Dialog(
      backgroundColor: const Color(0xFF262838),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.15), width: 1),
      ),
      child: Container(
        width: 580,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        padding: const EdgeInsets.all(20),
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
                    Icon(LucideIcons.share2, color: Color(0xFF38BDF8), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Share Class Notes on WhatsApp',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.x, color: Colors.grey, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Generating Progress or Preview Card
            if (_isGenerating) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    const CircularProgressIndicator(color: Color(0xFF38BDF8)),
                    const SizedBox(height: 16),
                    Text(
                      _statusText ?? 'Preparing PDF...',
                      style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ] else ...[
              // PDF Ready Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
                      child: const Icon(LucideIcons.fileCheck, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PDF Notes Ready!',
                            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${whiteboardProvider.pages.length} Slides compiled • ${_generatedPdfFile != null ? (_generatedPdfFile!.lengthSync() / 1024).toStringAsFixed(1) : "0"} KB',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Scrollable Content
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1-Click WhatsApp Group Share Button
                      ElevatedButton.icon(
                        onPressed: () => _shareToWhatsAppGroup(teacherName: teacherName, classroomName: classroomName),
                        icon: const Icon(LucideIcons.messageCircle, size: 18),
                        label: const Text(
                          'Share to Classroom WhatsApp Group (1-Click)',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366), // Official WhatsApp Green
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        'Send Individually to Classroom Students:',
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),

                      if (students.isEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
                          child: const Text(
                            'No students added to classroom yet. You can still use the 1-Click Group Share button above!',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ] else ...[
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: students.length,
                          itemBuilder: (context, index) {
                            final student = students[index];
                            final name = student['studentName'] ?? 'Student';
                            final phone = student['mobileNumber'] ?? '';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                                    child: Text(
                                      name.isNotEmpty ? name[0].toUpperCase() : 'S',
                                      style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                                        ),
                                        if (phone.isNotEmpty)
                                          Text('+91 $phone', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () => _shareToWhatsAppIndividual(
                                      studentName: name,
                                      mobileNumber: phone,
                                      teacherName: teacherName,
                                      classroomName: classroomName,
                                    ),
                                    icon: const Icon(LucideIcons.send, size: 13),
                                    label: const Text('Send PDF', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0284C7),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
