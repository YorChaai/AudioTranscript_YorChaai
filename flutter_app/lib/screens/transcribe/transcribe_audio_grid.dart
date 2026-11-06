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
  final VoidCallback? onOpenCustomFolder;

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
    this.onOpenCustomFolder,
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
    if (prov.displayFiles.isEmpty && prov.displayFolders.isEmpty) {
      return _buildEmptyState(context, prov);
    }

    final filteredFiles = _getFilteredFiles(prov, sortProv);

    if (filteredFiles.isEmpty && prov.displayFolders.isEmpty) {
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
        itemCount: prov.displayFolders.length + filteredFiles.length,
        itemBuilder: (context, index) {
          if (index < prov.displayFolders.length) {
            return _buildFolderItem(prov.displayFolders[index], prov);
          }
          final file = filteredFiles[index - prov.displayFolders.length];
          return _buildFileItem(file, prov);
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, TranscribeProvider prov) {
    if (prov.isCustomMode) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.paddingExtraLarge),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_open_rounded, size: 52, color: AppTheme.accentCyan),
              const SizedBox(height: 14),
              const Text(
                'Tidak ada file audio langsung di folder ini.',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'Jika file berada di dalam subfolder, klik folder di atas untuk masuk,\natau kembali ke server root.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('Kembali ke Root (audio/)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.cardDark,
                  foregroundColor: AppTheme.accentCyan,
                  side: const BorderSide(color: AppTheme.accentCyan),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => prov.clearCustomMode(),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.paddingExtraLarge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.audio_file_outlined, size: 52, color: AppTheme.textMuted),
            const SizedBox(height: 14),
            const Text(
              'Belum ada file audio di server.',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Upload file audio/video baru, atau buka folder langsung dari PC server Anda.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            if (onOpenCustomFolder != null) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text('Buka Folder di PC / Server', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentCyan,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: onOpenCustomFolder,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFolderItem(Map<String, dynamic> folder, TranscribeProvider prov) {
    final folderPath = folder['path'] as String? ?? folder['name'] as String;
    final folderName = folder['name'] as String? ?? 'Folder';
    final isSelected = selectedFolders.contains(folderPath);
    final fileCount = folder['file_count'] ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.browserColor.withOpacity(0.18) : AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? AppTheme.browserColor : AppTheme.dividerColor,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: Row(
          children: [
            // 1. Checkbox khusus untuk memilih folder sekaligus
            Tooltip(
              message: isSelected ? 'Batal pilih folder' : 'Pilih seluruh folder untuk diproses',
              child: InkWell(
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                onTap: prov.transcribing ? null : () => onToggleFolderSelection(folderPath),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  child: Icon(
                    isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                    color: isSelected ? AppTheme.browserColor : AppTheme.textSecondary.withOpacity(0.7),
                    size: 22,
                  ),
                ),
              ),
            ),

            // 2. Klik pada ikon/nama folder SELALU masuk ke dalam folder
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: prov.transcribing ? null : () => onFolderNavigate(folderPath),
                onLongPress: prov.transcribing ? null : () => onToggleFolderSelection(folderPath),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_rounded, color: AppTheme.browserColor, size: 26),
                      const SizedBox(width: 8),
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
                              '$fileCount files',
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 3. Tombol panah masuk ke folder
            Tooltip(
              message: 'Masuk ke dalam folder',
              child: IconButton(
                icon: const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary, size: 22),
                onPressed: prov.transcribing ? null : () => onFolderNavigate(folderPath),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                visualDensity: VisualDensity.compact,
              ),
            ),

            // 4. Menu opsi folder
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
            const SizedBox(width: 4),
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
