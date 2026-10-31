import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../state/whiteboard_provider.dart';
import '../models/image_element.dart';
import '../models/document_element.dart';
import '../../../widgets/pptx_viewer.dart';

class SlideOverviewSidebar extends StatelessWidget {
  final VoidCallback onClose;

  const SlideOverviewSidebar({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<WhiteboardProvider>(context);
    final pages = provider.pages;
    final currentIndex = provider.currentPageIndex;
    final bool showDeleteButton = pages.length > 1;
    final double sidebarWidth = showDeleteButton ? 260.0 : 205.0;
    // Check if any page contains document slides
    final docPage = pages.firstWhere(
      (p) => p.elements.any((e) => e is ImageElement && e.isDocumentSlide),
      orElse: () => provider.currentPage,
    );
    final List<ImageElement> docSlides = docPage.elements
        .whereType<ImageElement>()
        .where((e) => e.isDocumentSlide)
        .toList();
    final bool isDocMode = docSlides.length > 1;
    final int docPageIndex = pages.indexOf(docPage);

    final int extraPagesCount = isDocMode && pages.length > 1
        ? pages.length - 1
        : 0;
    final int totalItems = isDocMode
        ? (docSlides.length + extraPagesCount)
        : pages.length;

    return Container(
      margin: const EdgeInsets.only(right: 8, bottom: 4),
      width: sidebarWidth,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 18,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            // Header Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF242424),
                border: Border(
                  bottom: BorderSide(color: Colors.white12, width: 1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(
                        LucideIcons.layers,
                        size: 15,
                        color: Colors.blueAccent,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Slide Overview',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.white70,
                    ),
                    onPressed: onClose,
                    tooltip: 'Close Sidebar',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Slide Thumbnails ListView
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: totalItems,
                itemBuilder: (context, index) {
                  final bool isDocSlide = isDocMode && index < docSlides.length;

                  ImageElement? slideImage;
                  DocumentElement? docElement;
                  bool isSelected = false;
                  VoidCallback? onTap;
                  bool showItemDelete = false;
                  VoidCallback? onDelete;

                  if (isDocSlide) {
                    slideImage = docSlides[index];
                    isSelected =
                        (currentIndex == docPageIndex &&
                        index == provider.currentDocumentSlideIndex);
                    onTap = () {
                      if (currentIndex != docPageIndex) {
                        provider.switchPage(docPageIndex);
                      }
                      provider.jumpToDocumentSlide(index);
                    };
                  } else {
                    final int pageIdx = isDocMode
                        ? (index -
                              docSlides.length +
                              (docPageIndex == 0 ? 1 : 0))
                        : index;
                    if (pageIdx < pages.length) {
                      final page = pages[pageIdx];
                      isSelected = pageIdx == currentIndex;
                      try {
                        slideImage = page.elements
                            .whereType<ImageElement>()
                            .firstOrNull;
                        docElement = page.elements
                            .whereType<DocumentElement>()
                            .firstOrNull;
                      } catch (_) {}
                      onTap = () => provider.switchPage(pageIdx);
                      if (pages.length > 1) {
                        showItemDelete = true;
                        onDelete = () => provider.deletePage(pageIdx);
                      }
                    }
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Thumbnail Card
                        GestureDetector(
                          onTap: onTap,
                          child: Container(
                            height: 110,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.tealAccent
                                    : Colors.transparent,
                                width: isSelected ? 2.5 : 1.0,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: isSelected
                                      ? Colors.tealAccent.withValues(alpha: 0.3)
                                      : Colors.black26,
                                  blurRadius: isSelected ? 6 : 3,
                                  spreadRadius: isSelected ? 1 : 0,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (slideImage != null)
                                    Image.file(
                                      File(slideImage.imageUrl),
                                      fit: BoxFit.cover,
                                      errorBuilder: (c, e, s) => Container(
                                        color: Colors.grey[200],
                                        child: const Center(
                                          child: Icon(
                                            Icons.broken_image_rounded,
                                            size: 24,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ),
                                    )
                                  else if (docElement != null &&
                                      (docElement.filePath
                                              .toLowerCase()
                                              .endsWith('.pptx') ||
                                          docElement.filePath
                                              .toLowerCase()
                                              .endsWith('.ppt')))
                                    IgnorePointer(
                                      child: PptxViewer(
                                        file: File(docElement.filePath),
                                        slideIndex: docElement.docPage ?? 0,
                                      ),
                                    )
                                  else
                                    Container(
                                      color: Colors.white,
                                      child: Center(
                                        child: Text(
                                          'Slide ${index + 1}',
                                          style: const TextStyle(
                                            color: Colors.black87,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Slide Number Badge (Top-Left)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.teal : Colors.black87,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),

                        // Delete X Button (Top-Right)
                        if (showItemDelete && onDelete != null)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: GestureDetector(
                              onTap: onDelete,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.redAccent,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 11,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
