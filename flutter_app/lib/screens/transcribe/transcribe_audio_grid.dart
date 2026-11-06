import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../widgets/app_scrollbar.dart';
import '../../providers/transcribe_provider.dart';
import '../../providers/sort_provider.dart';
import '../../utils/ui_utils.dart';

class TranscribeAudioGrid extends StatelessWidget {
  final String searchQuery;
  final ScrollController gridScrollController;
  final bool isSelectionMode;
  final Set<String> selectedFiles;
  final Set<String> selectedFolders;
  final ValueChanged<String> onToggleFileSelection;
  final ValueChanged<String> onToggleFolderSelection;
  final ValueChanged<String> onFolderNavigate;
  final ValueChanged<String> onFileLongPress;
  final ValueChanged<String> onFolderLongPress;
  final void Function(String path, String name)? onRenameFile;
  final void Function(String path, String name)? onDeleteFile;
  final void Function(String path, String name)? onRenameFolder;
  final void Function(String path, String name)? onDeleteFolder;

  const TranscribeAudioGrid({
    super.key,
    required this.searchQuery,
    required this.gridScrollController,
    required this.isSelectionMode,
    required this.selectedFiles,
    required this.selectedFolders,
    required this.onToggleFileSelection,
    required this.onToggleFolderSelection,
    required this.onFolderNavigate,
    required this.onFileLongPress,
    required this.onFolderLongPress,
    this.onRenameFile,
    this.onDeleteFile,
    this.onRenameFolder,
    this.onDeleteFolder,
  });

  List<Map<String, dynamic>> _getFilteredFiles(TranscribeProvider prov, SortProvider sortProv) {
    var filteredFiles = prov.displayFiles.where((file) {
      final name = (file['name'] ?? '').toString().toLowerCase();
      return name.contains(searchQuery.toLowerCase());
    }).toList();

    filteredFiles.sort((a, b) {
      int result = 0;
      switch (sortProv.sortBy) {
        case 'date':
          final dateA = a['modified']?.toString() ?? '';
          final dateB = b['modified']?.toString() ?? '';
          result = dateA.compareTo(dateB);
          break;
        case 'type':
          final typeA = (a['name']?.toString() ?? '').split('.').last.toLowerCase();
          final typeB = (b['name']?.toString() ?? '').split('.').last.toLowerCase();
          result = typeA.compareTo(typeB);
          break;
        case 'size':
          final sizeA = a['size'] as int? ?? 0;
          final sizeB = b['size'] as int? ?? 0;
          result = sizeA.compareTo(sizeB);
          break;
        case 'name':
        default:
          final nameA = (a['name']?.toString() ?? '').toLowerCase();
          final nameB = (b['name']?.toString() ?? '').toLowerCase();
          result = nameA.compareTo(nameB);
          break;
      }
      return sortProv.sortAscending ? result : -result;
    });
    return filteredFiles;
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<TranscribeProvider>();
    final sortProv = context.watch<SortProvider>();

    if (prov.isLoading) return const Center(child: CircularProgressIndicator());
    if (prov.displayFiles.isEmpty && prov.folders.isEmpty) return _buildEmptyState();

    final filteredFiles = _getFilteredFiles(prov, sortProv);

    if (filteredFiles.isEmpty && prov.folders.isEmpty) {
      return const Center(
        child: Text(
          'Tidak ada file yang cocok dengan pencarian.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }

    return AppScrollbar(
      controller: gridScrollController,
      child: GridView.builder(
        controller: gridScrollController,
        padding: const EdgeInsets.only(bottom: 24),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 320,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 74,
        ),
        itemCount: prov.folders.length + filteredFiles.length,
        itemBuilder: (context, index) {
          if (index < prov.folders.length) {
            return _buildFolderItem(prov.folders[index], prov);
          }
          final file = filteredFiles[index - prov.folders.length];
          return _buildFileItem(file, prov);
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(AppConstants.paddingExtraLarge),
        child: Text(
          'Belum ada file audio di server.\nUpload file atau folder untuk mulai.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      ),
    );
  }

  Widget _buildFolderItem(Map<String, dynamic> folder, TranscribeProvider prov) {
    final folderPath = folder['path'] as String? ?? folder['name'] as String;
    final folderName = folder['name'] as String? ?? 'Folder';
    final isSelected = selectedFolders.contains(folderPath);

    return InkWell(
      onTap: prov.transcribing
          ? null
          : () {
              if (isSelectionMode) {
                onToggleFolderSelection(folderPath);
              } else {
                onFolderNavigate(folderPath);
              }
            },
      onLongPress: prov.transcribing ? null : () => onFolderLongPress(folderPath),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.browserColor.withOpacity(0.15) : AppTheme.cardDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.browserColor : AppTheme.dividerColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            if (isSelectionMode) ...[
              Icon(
                isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                color: isSelected ? AppTheme.browserColor : AppTheme.textSecondary,
                size: 22,
              ),
              const SizedBox(width: 8),
            ],
            const Icon(Icons.folder_rounded, color: AppTheme.browserColor, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    folderName,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${folder['file_count'] ?? 0} files',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (!isSelectionMode)
              SizedBox(
                width: 28,
                height: 28,
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, size: 18, color: AppTheme.textMuted),
                  color: AppTheme.cardDark,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onSelected: (val) {
                    if (val == 'rename') {
                      onRenameFolder?.call(folderPath, folderName);
                    } else if (val == 'delete') {
                      onDeleteFolder?.call(folderPath, folderName);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded, size: 16, color: AppTheme.accentCyan),
                          SizedBox(width: 8),
                          Text('Ubah Nama', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_forever_rounded, size: 16, color: AppTheme.error),
                          SizedBox(width: 8),
                          Text('Hapus Folder', style: TextStyle(color: AppTheme.error, fontSize: 12)),
                        ],
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

  Widget _buildFileItem(Map<String, dynamic> file, TranscribeProvider prov) {
    final filePath = file['path'] as String? ?? file['name'] as String;
    final fileName = file['name'] as String? ?? 'Unknown';
    final isSelected = selectedFiles.contains(filePath);
    final sizeStr = UiUtils.formatSize(file['size'] ?? 0);
    final isVideo = file['is_video'] == true;
    final durationSec = file['duration'] as num?;
    String durationStr = '';
    if (durationSec != null && durationSec > 0) {
      final d = durationSec.toInt();
      final h = d ~/ 3600;
      final m = (d % 3600) ~/ 60;
      final s = d % 60;
      durationStr = h > 0
          ? ' • ${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
          : ' • ${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }

    return InkWell(
      onTap: prov.transcribing ? null : () => onToggleFileSelection(filePath),
      onLongPress: prov.transcribing ? null : () => onFileLongPress(filePath),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentBlue.withOpacity(0.15) : AppTheme.cardDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.accentBlue : AppTheme.dividerColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            if (isSelectionMode) ...[
              Icon(
                isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                color: isSelected ? AppTheme.accentBlue : AppTheme.textSecondary,
                size: 22,
              ),
              const SizedBox(width: 8),
            ],
            Icon(
              isSelected
                  ? Icons.check_circle_rounded
                  : (isVideo ? Icons.video_file_rounded : Icons.audio_file_outlined),
              color: isSelected
                  ? AppTheme.accentBlue
                  : (isVideo ? AppTheme.accentCyan : AppTheme.textSecondary),
              size: 28,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileName,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$sizeStr$durationStr',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (!isSelectionMode)
              SizedBox(
                width: 28,
                height: 28,
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, size: 18, color: AppTheme.textMuted),
                  color: AppTheme.cardDark,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onSelected: (val) {
                    if (val == 'rename') {
                      onRenameFile?.call(filePath, fileName);
                    } else if (val == 'delete') {
                      onDeleteFile?.call(filePath, fileName);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded, size: 16, color: AppTheme.accentCyan),
                          SizedBox(width: 8),
                          Text('Ubah Nama', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_forever_rounded, size: 16, color: AppTheme.error),
                          SizedBox(width: 8),
                          Text('Hapus File', style: TextStyle(color: AppTheme.error, fontSize: 12)),
                        ],
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
