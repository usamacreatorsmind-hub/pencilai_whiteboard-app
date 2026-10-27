import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';
import '../models/document_element.dart';
import '../models/stroke_element.dart';
import '../models/text_element.dart';
import '../services/ai_service.dart';
import '../services/board_storage_service.dart';
import '../services/translation_service.dart';
import '../state/whiteboard_provider.dart';
import 'settings_dialog.dart';

class TranslationDialog extends StatefulWidget {
  final WhiteboardProvider provider;

  const TranslationDialog({super.key, required this.provider});

  static Future<void> show(BuildContext context, WhiteboardProvider provider) {
    return showDialog(
      context: context,
      builder: (context) => TranslationDialog(provider: provider),
    );
  }

  @override
  State<TranslationDialog> createState() => _TranslationDialogState();
}

class _TranslationDialogState extends State<TranslationDialog> {
  SupportedLanguage? _sourceLang; // null = Auto-Detect
  late SupportedLanguage _targetLang;

  String _originalText = '';
  String _translatedText = '';
  bool _isLoadingText = true;
  bool _isTranslating = false;

  final Map<String, bool> _downloadedModels = {};
  final Map<String, bool> _isDownloading = {};

  @override
  void initState() {
    super.initState();
    final downloaded = widget.provider.downloadedTranslationLanguageItems;
    if (downloaded.isNotEmpty) {
      _targetLang = downloaded.firstWhere(
        (l) => l.code == 'hi',
        orElse: () => downloaded.first,
      );
    } else {
      _targetLang = TranslationService.supportedLanguages.firstWhere(
        (l) => l.code == 'hi',
        orElse: () => TranslationService.supportedLanguages[0],
      );
    }
    _extractAndTranslate();
    _checkModelDownloads();
  }

  Future<void> _checkModelDownloads() async {
    for (var lang in TranslationService.supportedLanguages) {
      final downloaded =
          widget.provider.isTranslationLanguageDownloaded(lang.code) ||
          await TranslationService().isModelDownloaded(lang.mlKitLanguage);
      if (mounted) {
        setState(() {
          _downloadedModels[lang.code] = downloaded;
        });
      }
    }
  }

  Future<void> _downloadLanguagePack(SupportedLanguage lang) async {
    setState(() {
      _isDownloading[lang.code] = true;
    });
    final success = await widget.provider.downloadTranslationLanguage(lang);
    if (mounted) {
      setState(() {
        _isDownloading[lang.code] = false;
        if (success) {
          _downloadedModels[lang.code] = true;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Downloaded ${lang.name} (${lang.nativeName}) language pack for offline use.'
                : 'Could not download ${lang.name} pack.',
          ),
          backgroundColor: success ? const Color(0xFF10B981) : Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _extractAndTranslate() async {
    setState(() {
      _isLoadingText = true;
      _isTranslating = true;
    });

    String extracted = '';
    final selectedIds = widget.provider.selectedElementIds;
    final selectedElements = widget.provider.currentPage.elements
        .where((e) => selectedIds.contains(e.id))
        .toList();

    for (var el in selectedElements) {
      if (el is TextElement) {
        extracted = el.text;
        break;
      } else if (el is DocumentElement) {
        extracted = el.fileName.split('.').first;
        break;
      }
    }

    if (extracted.isEmpty && selectedElements.isNotEmpty) {
      final imageBytes = await BoardStorageService()
          .captureSelectedElementsBytes(selectedElements);
      if (imageBytes != null) {
        final recognized = await AiService().recognizeHandwriting(
          imageBytes: imageBytes,
          language: widget.provider.selectedHandwritingLanguage,
        );
        if (recognized.isNotEmpty &&
            !recognized.startsWith('Error') &&
            !recognized.startsWith('⚠️')) {
          extracted = recognized;
        }
      }
    }

    if (extracted.isEmpty) {
      if (mounted) {
        setState(() {
          _originalText = 'No text detected';
          _translatedText = '';
          _isLoadingText = false;
          _isTranslating = false;
        });
      }
      return;
    }

    _originalText = extracted.trim();

    final translated = await TranslationService().translateText(
      text: _originalText,
      sourceLang: _sourceLang,
      targetLang: _targetLang,
    );

    if (mounted) {
      setState(() {
        _translatedText = translated;
        _isLoadingText = false;
        _isTranslating = false;
      });
    }
  }

  Future<void> _updateTranslation() async {
    if (_originalText.isEmpty) return;
    setState(() => _isTranslating = true);

    final translated = await TranslationService().translateText(
      text: _originalText,
      sourceLang: _sourceLang,
      targetLang: _targetLang,
    );

    if (mounted) {
      setState(() {
        _translatedText = translated;
        _isTranslating = false;
      });
    }
  }

  void _applyTranslation({bool replace = true}) {
    if (_translatedText.isEmpty) return;

    final selectedIds = widget.provider.selectedElementIds;
    final selectedElements = widget.provider.currentPage.elements
        .where((e) => selectedIds.contains(e.id))
        .toList();

    Rect bounds = selectedElements.isNotEmpty
        ? selectedElements[0].getRawBounds()
        : const Rect.fromLTWH(100, 100, 150, 50);

    Color color = Colors.black;
    if (selectedElements.isNotEmpty) {
      final first = selectedElements[0];
      if (first is StrokeElement) color = first.color;
      if (first is TextElement) color = first.color;
    }

    final newPosition = replace
        ? Offset(bounds.left, bounds.top)
        : Offset(bounds.left, bounds.bottom + 16);

    final translatedElement = TextElement(
      id: const Uuid().v4(),
      position: newPosition,
      text: _translatedText,
      color: color,
      fontSize: (bounds.height * 0.7).clamp(20.0, 72.0),
      size: Size(bounds.width * 1.2, bounds.height * 1.1),
      docPage: widget.provider.isDocumentOverlayOpen
          ? widget.provider.overlayCurrentPage
          : null,
    );

    if (replace) {
      widget.provider.removeSelectedElements();
    }

    widget.provider.addElement(translatedElement);
    widget.provider.selectElement(translatedElement.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D9488).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    LucideIcons.languages,
                    color: Color(0xFF2DD4BF),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Translate Text',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(LucideIcons.x, color: Colors.grey, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Fast Downloaded Models Quick Bar
            Builder(
              builder: (context) {
                final downloadedLangs = widget.provider.downloadedTranslationLanguageItems;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(LucideIcons.zap, size: 14, color: Color(0xFF2DD4BF)),
                            const SizedBox(width: 5),
                            Text(
                              'Downloaded Models (${downloadedLangs.length})',
                              style: const TextStyle(
                                color: Color(0xFF2DD4BF),
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        InkWell(
                          onTap: () {
                            Navigator.of(context).pop();
                            SettingsDialog.show(context, initialTab: SettingsTab.translationLanguage);
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              children: [
                                Text(
                                  'Manage',
                                  style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                                SizedBox(width: 2),
                                Icon(LucideIcons.externalLink, size: 11, color: Color(0xFF38BDF8)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (downloadedLangs.isNotEmpty)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: downloadedLangs.map((lang) {
                            final isSelected = _targetLang.code == lang.code;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6.0),
                              child: InkWell(
                                onTap: () {
                                  setState(() => _targetLang = lang);
                                  _updateTranslation();
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFF0D9488) : const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isSelected ? const Color(0xFF2DD4BF) : Colors.white24,
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isSelected ? LucideIcons.check : LucideIcons.zap,
                                        size: 11,
                                        color: isSelected ? Colors.white : const Color(0xFF2DD4BF),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        lang.nativeName,
                                        style: TextStyle(
                                          color: isSelected ? Colors.white : Colors.white70,
                                          fontSize: 11.5,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: const Text(
                          'No models downloaded yet. Tap "Manage" to download offline translation models.',
                          style: TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),

            // Language Selector Row (Source -> Target)
            Row(
              children: [
                // Source Language Box
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Source Language',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<SupportedLanguage?>(
                            value: _sourceLang,
                            dropdownColor: const Color(0xFF0F172A),
                            isExpanded: true,
                            icon: const Icon(
                              LucideIcons.chevronDown,
                              color: Colors.grey,
                              size: 16,
                            ),
                            items: [
                              const DropdownMenuItem<SupportedLanguage?>(
                                value: null,
                                child: Text(
                                  'Auto-Detect',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              ...TranslationService.supportedLanguages.map(
                                (l) => DropdownMenuItem<SupportedLanguage?>(
                                  value: l,
                                  child: Text(
                                    '${l.nativeName} (${l.name})',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (val) {
                              setState(() => _sourceLang = val);
                              _updateTranslation();
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Icon(
                    LucideIcons.arrowRight,
                    color: Colors.grey,
                    size: 16,
                  ),
                ),

                // Target Language Box
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Target Language',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF0D9488),
                            width: 1.2,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<SupportedLanguage>(
                            value: _targetLang,
                            dropdownColor: const Color(0xFF0F172A),
                            isExpanded: true,
                            icon: const Icon(
                              LucideIcons.chevronDown,
                              color: Color(0xFF2DD4BF),
                              size: 16,
                            ),
                            items: TranslationService.supportedLanguages.map((
                              l,
                            ) {
                              final isDownloaded =
                                  _downloadedModels[l.code] ?? false;
                              final isDownloading =
                                  _isDownloading[l.code] ?? false;

                              return DropdownMenuItem<SupportedLanguage>(
                                value: l,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        l.nativeName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    if (isDownloading)
                                      const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.8,
                                          color: Colors.teal,
                                        ),
                                      )
                                    else if (!isDownloaded)
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(
                                          LucideIcons.download,
                                          color: Colors.grey,
                                          size: 14,
                                        ),
                                        onPressed: () =>
                                            _downloadLanguagePack(l),
                                      )
                                    else
                                      const Icon(
                                        LucideIcons.check,
                                        color: Color(0xFF10B981),
                                        size: 15,
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _targetLang = val);
                                _updateTranslation();
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Source Text & Translation Result Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _isLoadingText
                              ? 'Reading text...'
                              : 'Original: "$_originalText"',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_isTranslating)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: Color(0xFF2DD4BF),
                          ),
                        ),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 16),
                  Text(
                    _translatedText.isEmpty
                        ? 'Translating...'
                        : _translatedText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _translatedText.isEmpty
                        ? null
                        : () => _applyTranslation(replace: false),
                    icon: const Icon(LucideIcons.plus, size: 14),
                    label: const Text(
                      'Add as New Note',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D9488),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _translatedText.isEmpty
                        ? null
                        : () => _applyTranslation(replace: true),
                    icon: const Icon(LucideIcons.check, size: 14),
                    label: const Text(
                      'Replace Original',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
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

