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
  final List<String> selectedFiles;
  final ValueChanged<String> onToggleSelection;

  const TranscribeAudioGrid({
    super.key,
    required this.searchQuery,
    required this.gridScrollController,
    required this.selectedFiles,
    required this.onToggleSelection,
  });

  List<Map<String, dynamic>> _getFilteredFiles(TranscribeProvider prov, SortProvider sortProv) {
    var filteredFiles = prov.audioFiles.where((file) {
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
    if (prov.audioFiles.isEmpty && prov.folders.isEmpty) return _buildEmptyState();

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
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 300,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 2.5,
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
          'Belum ada file audio di server.\nUpload file baru untuk mulai.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      ),
    );
  }

  Widget _buildFolderItem(Map<String, dynamic> folder, TranscribeProvider prov) {
    return InkWell(
      onTap: () => prov.navigateTo(folder['path']),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.dividerColor),
        ),
        child: Row(
          children: [
            const Icon(Icons.folder_rounded, color: AppTheme.browserColor, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    folder['name'] ?? 'Folder',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${folder['file_count'] ?? 0} files',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
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
    final isSelected = selectedFiles.contains(filePath);
    final sizeStr = UiUtils.formatSize(file['size'] ?? 0);

    return InkWell(
      onTap: prov.transcribing ? null : () => onToggleSelection(filePath),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentBlue.withOpacity(0.1) : AppTheme.cardDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.accentBlue : AppTheme.dividerColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle : Icons.audio_file_outlined,
              color: isSelected ? AppTheme.accentBlue : AppTheme.textSecondary,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    file['name'] ?? 'Unknown',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sizeStr,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
