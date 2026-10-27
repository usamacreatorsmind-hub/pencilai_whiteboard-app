import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';

class StorageLocation {
  final String title;
  final String path;
  final IconData icon;
  final bool isUsb;

  const StorageLocation({
    required this.title,
    required this.path,
    required this.icon,
    this.isUsb = false,
  });
}

class StorageBrowserDialog extends StatefulWidget {
  final Future<void> Function(File file, String fileName) onFileSelected;
  final VoidCallback onOpenSystemPicker;

  const StorageBrowserDialog({
    super.key,
    required this.onFileSelected,
    required this.onOpenSystemPicker,
  });

  @override
  State<StorageBrowserDialog> createState() => _StorageBrowserDialogState();
}

class _StorageBrowserDialogState extends State<StorageBrowserDialog> {
  final List<StorageLocation> _locations = [];
  bool _isLoadingLocations = true;
  bool _isLoadingFiles = false;

  Directory? _currentDir;
  List<FileSystemEntity> _currentEntities = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  static const List<String> _allowedExtensions = [
    'pdf',
    'ppt',
    'pptx',
    'doc',
    'docx',
    'xls',
    'xlsx',
  ];

  @override
  void initState() {
    super.initState();
    _loadStorageLocations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStorageLocations() async {
    setState(() => _isLoadingLocations = true);
    final List<StorageLocation> locs = [];

    // 1. Check Android /storage directory for USB drives and external volumes
    try {
      final storageDir = Directory('/storage');
      if (storageDir.existsSync()) {
        final entries = storageDir.listSync();
        for (final entry in entries) {
          if (entry is Directory) {
            final name = entry.path.split('/').last;
            // Ignore system symlinks and internal storage pointers
            if (name != 'emulated' && name != 'self' && name != 'knox') {
              locs.add(
                StorageLocation(
                  title: 'USB Drive ($name)',
                  path: entry.path,
                  icon: LucideIcons.hardDrive,
                  isUsb: true,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Note: /storage scan: $e');
    }

    // 2. Check /mnt for USB mounts on OEM boards (e.g. CVTE, MStar, Rockchip)
    try {
      final mntDir = Directory('/mnt');
      if (mntDir.existsSync()) {
        for (final entry in mntDir.listSync()) {
          if (entry is Directory) {
            final name = entry.path.split('/').last.toLowerCase();
            if (name.contains('usb') ||
                name.contains('udisk') ||
                name.contains('media_rw')) {
              if (name.contains('media_rw')) {
                try {
                  for (final sub in entry.listSync()) {
                    if (sub is Directory &&
                        !locs.any((l) => l.path == sub.path)) {
                      final subName = sub.path.split('/').last;
                      locs.add(
                        StorageLocation(
                          title: 'USB Storage ($subName)',
                          path: sub.path,
                          icon: LucideIcons.hardDrive,
                          isUsb: true,
                        ),
                      );
                    }
                  }
                } catch (_) {}
              } else if (!locs.any((l) => l.path == entry.path)) {
                locs.add(
                  StorageLocation(
                    title: 'USB Storage (${entry.path.split('/').last})',
                    path: entry.path,
                    icon: LucideIcons.hardDrive,
                    isUsb: true,
                  ),
                );
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Note: /mnt scan: $e');
    }

    // 3. Check path_provider getExternalStorageDirectories for USB mounts
    try {
      final extDirs = await getExternalStorageDirectories();
      if (extDirs != null) {
        for (final dir in extDirs) {
          final parts = dir.path.split('/');
          final androidIdx = parts.indexOf('Android');
          if (androidIdx > 0) {
            final rootPath = parts.sublist(0, androidIdx).join('/');
            if (rootPath != '/storage/emulated/0' &&
                !locs.any((l) => l.path == rootPath)) {
              final volName = parts[androidIdx - 1];
              locs.add(
                StorageLocation(
                  title: 'External Storage ($volName)',
                  path: rootPath,
                  icon: LucideIcons.hardDrive,
                  isUsb: true,
                ),
              );
            }
          }
        }
      }
    } catch (_) {}

    // 4. Primary Internal Storage & standard folders
    final internalPath = '/storage/emulated/0';
    if (Directory(internalPath).existsSync()) {
      locs.add(
        const StorageLocation(
          title: 'Internal Storage',
          path: '/storage/emulated/0',
          icon: LucideIcons.folder,
        ),
      );

      final dl = Directory('$internalPath/Download');
      if (dl.existsSync()) {
        locs.add(
          StorageLocation(
            title: 'Downloads',
            path: dl.path,
            icon: LucideIcons.download,
          ),
        );
      }

      final docs = Directory('$internalPath/Documents');
      if (docs.existsSync()) {
        locs.add(
          StorageLocation(
            title: 'Documents',
            path: docs.path,
            icon: LucideIcons.fileText,
          ),
        );
      }
    }

    // 5. Desktop platforms (macOS / Windows / Linux) fallback
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      final home =
          Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home != null) {
        locs.add(
          StorageLocation(
            title: 'Home Directory',
            path: home,
            icon: LucideIcons.folder,
          ),
        );
        final dl = Directory('$home/Downloads');
        if (dl.existsSync()) {
          locs.add(
            StorageLocation(
              title: 'Downloads',
              path: dl.path,
              icon: LucideIcons.download,
            ),
          );
        }
        final docs = Directory('$home/Documents');
        if (docs.existsSync()) {
          locs.add(
            StorageLocation(
              title: 'Documents',
              path: docs.path,
              icon: LucideIcons.fileText,
            ),
          );
        }
      }
      if (Platform.isMacOS && Directory('/Volumes').existsSync()) {
        try {
          for (final v in Directory('/Volumes').listSync()) {
            if (v is Directory && !v.path.endsWith('Macintosh HD')) {
              locs.add(
                StorageLocation(
                  title: 'USB / Volume (${v.path.split('/').last})',
                  path: v.path,
                  icon: LucideIcons.hardDrive,
                  isUsb: true,
                ),
              );
            }
          }
        } catch (_) {}
      }
    }

    // Default start directory: prefer first USB drive if available, else Downloads, else first available
    Directory? initialDir;
    final usbDrive = locs.where((l) => l.isUsb).firstOrNull;
    if (usbDrive != null && Directory(usbDrive.path).existsSync()) {
      initialDir = Directory(usbDrive.path);
    } else {
      final dl = locs.where((l) => l.title == 'Downloads').firstOrNull;
      if (dl != null && Directory(dl.path).existsSync()) {
        initialDir = Directory(dl.path);
      } else if (locs.isNotEmpty && Directory(locs.first.path).existsSync()) {
        initialDir = Directory(locs.first.path);
      }
    }

    if (mounted) {
      setState(() {
        _locations.clear();
        _locations.addAll(locs);
        _isLoadingLocations = false;
      });
      if (initialDir != null) {
        _navigateTo(initialDir);
      }
    }
  }

  void _navigateTo(Directory dir) {
    setState(() {
      _currentDir = dir;
      _isLoadingFiles = true;
    });

    try {
      final all = dir.listSync();
      final filtered = all.where((entity) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('.')) return false; // Hide dotfiles

        if (entity is Directory) {
          return true; // Always include folders
        } else if (entity is File) {
          final ext = name.contains('.')
              ? name.split('.').last.toLowerCase()
              : '';
          return _allowedExtensions.contains(ext);
        }
        return false;
      }).toList();

      // Sort: Folders first (A-Z), then Files (A-Z)
      filtered.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        final aName = a.path.split(Platform.pathSeparator).last.toLowerCase();
        final bName = b.path.split(Platform.pathSeparator).last.toLowerCase();
        return aName.compareTo(bName);
      });

      if (mounted) {
        setState(() {
          _currentEntities = filtered;
          _isLoadingFiles = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentEntities = [];
          _isLoadingFiles = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Cannot access folder: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _navigateUp() {
    if (_currentDir == null) return;
    final parent = _currentDir!.parent;
    if (parent.path != _currentDir!.path) {
      _navigateTo(parent);
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    final i = (log(bytes) / log(1024)).floor();
    final clampedIndex = i.clamp(0, suffixes.length - 1);
    return '${(bytes / pow(1024, clampedIndex)).toStringAsFixed(1)} ${suffixes[clampedIndex]}';
  }

  Widget _buildFileIcon(String ext) {
    switch (ext) {
      case 'ppt':
      case 'pptx':
        return Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFD97706).withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFF59E0B), width: 1.2),
          ),
          child: const Center(
            child: Icon(
              LucideIcons.fileText,
              color: Color(0xFFF59E0B),
              size: 24,
            ),
          ),
        );
      case 'pdf':
        return Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFDC2626).withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFEF4444), width: 1.2),
          ),
          child: const Center(
            child: Icon(
              LucideIcons.fileText,
              color: Color(0xFFEF4444),
              size: 24,
            ),
          ),
        );
      case 'doc':
      case 'docx':
        return Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB).withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF3B82F6), width: 1.2),
          ),
          child: const Center(
            child: Icon(
              LucideIcons.fileText,
              color: Color(0xFF3B82F6),
              size: 24,
            ),
          ),
        );
      default:
        return Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Center(
            child: Icon(LucideIcons.file, color: Colors.white70, size: 24),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = min(screenSize.width * 0.90, 880.0);
    final dialogHeight = min(screenSize.height * 0.88, 620.0);

    final displayEntities = _searchQuery.trim().isEmpty
        ? _currentEntities
        : _currentEntities.where((e) {
            final name = e.path
                .split(Platform.pathSeparator)
                .last
                .toLowerCase();
            return name.contains(_searchQuery.toLowerCase());
          }).toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: const Color(0xFF1E2127),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF374151), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header Bar
            _buildHeader(context),

            // Storage Locations Bar (USB, Internal, Downloads, Documents)
            _buildLocationsBar(),

            // Navigation Bar (Up button, Path breadcrumb, Search)
            _buildPathAndSearchBar(),

            const Divider(color: Color(0xFF374151), height: 1),

            // Content Area (Folder & Files list)
            Expanded(
              child: _isLoadingFiles
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Colors.blueAccent,
                      ),
                    )
                  : displayEntities.isEmpty
                  ? _buildEmptyState()
                  : _buildEntityList(displayEntities),
            ),

            const Divider(color: Color(0xFF374151), height: 1),

            // Bottom Tip and Action Bar
            _buildBottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF181A20),
        borderRadius: BorderRadius.vertical(top: Radius.circular(19)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              LucideIcons.folderOpen,
              color: Colors.blueAccent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Import PPT / PDF Document',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Browse USB drives or internal storage directly',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const Spacer(),
          // System File Manager button
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onOpenSystemPicker();
            },
            icon: const Icon(
              LucideIcons.smartphone,
              size: 16,
              color: Color(0xFF38BDF8),
            ),
            label: const Text(
              'System File Picker',
              style: TextStyle(
                color: Color(0xFF38BDF8),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF0284C7)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              backgroundColor: const Color(0xFF0369A1).withValues(alpha: 0.12),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(LucideIcons.x, color: Colors.white70, size: 20),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildLocationsBar() {
    if (_isLoadingLocations) {
      return const SizedBox(
        height: 52,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.blueAccent,
            ),
          ),
        ),
      );
    }

    if (_locations.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      color: const Color(0xFF14161C),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final loc in _locations) ...[
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ActionChip(
                  avatar: Icon(
                    loc.icon,
                    size: 16,
                    color: loc.isUsb
                        ? const Color(0xFF10B981)
                        : (_currentDir?.path == loc.path
                              ? Colors.white
                              : Colors.white70),
                  ),
                  label: Text(
                    loc.title,
                    style: TextStyle(
                      color: loc.isUsb
                          ? const Color(0xFF10B981)
                          : (_currentDir?.path == loc.path
                                ? Colors.white
                                : Colors.white70),
                      fontSize: 12.5,
                      fontWeight: loc.isUsb || _currentDir?.path == loc.path
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  backgroundColor: _currentDir?.path == loc.path
                      ? const Color(0xFF2563EB)
                      : (loc.isUsb
                            ? const Color(0xFF065F46).withValues(alpha: 0.3)
                            : const Color(0xFF262A34)),
                  side: BorderSide(
                    color: _currentDir?.path == loc.path
                        ? const Color(0xFF3B82F6)
                        : (loc.isUsb
                              ? const Color(0xFF10B981).withValues(alpha: 0.5)
                              : const Color(0xFF374151)),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  onPressed: () {
                    _navigateTo(Directory(loc.path));
                  },
                ),
              ),
            ],
            IconButton(
              icon: const Icon(
                LucideIcons.refreshCw,
                size: 16,
                color: Colors.white54,
              ),
              tooltip: 'Refresh USB Drives',
              onPressed: _loadStorageLocations,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPathAndSearchBar() {
    final currentPathStr = _currentDir?.path ?? 'Select Storage';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFF1E2127),
      child: Row(
        children: [
          // Up / Back button
          IconButton(
            icon: const Icon(
              LucideIcons.arrowUp,
              color: Colors.white,
              size: 20,
            ),
            tooltip: 'Up to parent folder',
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF2E333D),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _navigateUp,
          ),
          const SizedBox(width: 10),
          // Path breadcrumb
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF13151A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2E333D)),
              ),
              child: Text(
                currentPathStr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12.5,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Filter / Search input
          SizedBox(
            width: 190,
            height: 38,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Filter files...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                prefixIcon: const Icon(
                  LucideIcons.search,
                  color: Colors.white38,
                  size: 16,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          LucideIcons.x,
                          color: Colors.white54,
                          size: 14,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 8,
                ),
                filled: true,
                fillColor: const Color(0xFF13151A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF2E333D)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF2E333D)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.blueAccent),
                ),
              ),
              onChanged: (val) {
                setState(() => _searchQuery = val);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              LucideIcons.folderSearch,
              size: 48,
              color: Colors.white38,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'No PPT or PDF documents found in this folder',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Check your USB drive or tap "System File Picker" at the top',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildEntityList(List<FileSystemEntity> entities) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: entities.length,
      itemBuilder: (context, index) {
        final entity = entities[index];
        final name = entity.path.split(Platform.pathSeparator).last;

        if (entity is Directory) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Material(
              color: const Color(0xFF252932),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _navigateTo(entity),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF3B82F6,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Icon(
                            LucideIcons.folder,
                            color: Color(0xFF60A5FA),
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(
                        LucideIcons.chevronRight,
                        color: Colors.white38,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        // It is a File
        if (entity is! File) {
          return const SizedBox.shrink();
        }
        final file = entity;
        final ext = name.contains('.')
            ? name.split('.').last.toLowerCase()
            : '';
        int fileSize = 0;
        DateTime? modified;
        try {
          final stat = file.statSync();
          fileSize = stat.size;
          modified = stat.modified;
        } catch (_) {}

        final formattedSize = _formatFileSize(fileSize);
        final dateStr = modified != null
            ? '${modified.day}/${modified.month}/${modified.year}'
            : '';

        final isPpt = ext == 'ppt' || ext == 'pptx';
        final isPdf = ext == 'pdf';

        return Padding(
          padding: const EdgeInsets.only(bottom: 6.0),
          child: Material(
            color: const Color(0xFF22262E),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                Navigator.of(context).pop();
                widget.onFileSelected(file, name);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    _buildFileIcon(ext),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Text(
                                formattedSize,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11.5,
                                ),
                              ),
                              if (dateStr.isNotEmpty) ...[
                                const Text(
                                  ' • ',
                                  style: TextStyle(
                                    color: Colors.white30,
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  dateStr,
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onFileSelected(file, name);
                      },
                      icon: const Icon(LucideIcons.fileInput, size: 14),
                      label: const Text(
                        'Import',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isPpt
                            ? const Color(0xFFD97706)
                            : (isPdf
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFF2563EB)),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF181A20),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(19)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.info, color: Color(0xFF38BDF8), size: 16),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '💡 Smart Panel Tip: If tapping files in your panel\'s file manager only highlights them, tap "Import" directly here.',
              style: TextStyle(color: Colors.white70, fontSize: 11.5),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }
}
