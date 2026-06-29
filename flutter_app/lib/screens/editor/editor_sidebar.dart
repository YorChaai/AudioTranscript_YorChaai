import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../widgets/app_scrollbar.dart';
import '../../providers/editor_provider.dart';
import '../../providers/sort_provider.dart';
import '../../widgets/sort_menu.dart';
import '../../utils/ui_utils.dart';

class EditorSidebar extends StatelessWidget {
  final bool isMobile;
  final String? selectedFile;
  final ValueChanged<String> onFileSelected;
  final VoidCallback onRefresh;
  final ScrollController listScrollController;
  final ScrollController mobileScrollController;

  const EditorSidebar({
    super.key,
    required this.isMobile,
    required this.selectedFile,
    required this.onFileSelected,
    required this.onRefresh,
    required this.listScrollController,
    required this.mobileScrollController,
  });

  List<Map<String, dynamic>> _getSortedFiles(EditorProvider prov, SortProvider sortProv) {
    final list = List<Map<String, dynamic>>.from(prov.files);
    list.sort((a, b) {
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
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<EditorProvider>();
    final sortProv = context.watch<SortProvider>();

    if (isMobile) {
      return RefreshIndicator(
        onRefresh: () async => onRefresh(),
        child: AppScrollbar(
          controller: mobileScrollController,
          child: CustomScrollView(
            controller: mobileScrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.paddingLarge),
                  child: _buildHeaderSection(sortProv),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppConstants.paddingLarge),
                  child: _buildBreadcrumb(prov),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.paddingLarge, 
                  vertical: AppConstants.paddingSmall
                ),
                sliver: SliverToBoxAdapter(
                  child: _buildFileListPanel(prov, sortProv, isMobile: true),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppConstants.paddingLarge)),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppConstants.paddingLarge),
            child: _buildHeaderSection(sortProv),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppConstants.paddingLarge),
            child: _buildBreadcrumb(prov),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          Expanded(child: _buildFileListPanel(prov, sortProv, isMobile: false)),
        ],
      ),
    );
  }

  Widget _buildHeaderSection(SortProvider sortProv) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.editorColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.edit_note_rounded, color: AppTheme.editorColor, size: 24),
        ),
        const SizedBox(width: AppConstants.paddingMedium),
        const Expanded(
            child: Text('Text Editor',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        SortMenu(
          sortBy: sortProv.sortBy,
          sortAscending: sortProv.sortAscending,
          onSortByChanged: (value) => sortProv.setSortBy(value),
          onSortOrderChanged: (value) => sortProv.setSortOrder(value),
        ),
        IconButton(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded, size: 20),
        ),
      ],
    );
  }

  Widget _buildBreadcrumb(EditorProvider prov) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.paddingMedium, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(
        children: [
          if (prov.currentPath.isNotEmpty)
            InkWell(
              onTap: () => prov.goBack(),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_rounded, size: 18, color: AppTheme.editorColor),
                  SizedBox(width: 4),
                  Text('Kembali', style: TextStyle(fontSize: 13, color: AppTheme.editorColor)),
                  SizedBox(width: 12),
                ],
              ),
            ),
          InkWell(
            onTap: prov.currentPath.isNotEmpty ? () => prov.goToRoot() : null,
            child: Text(
              '📁 root',
              style: TextStyle(
                fontSize: 13,
                color: prov.currentPath.isNotEmpty ? AppTheme.editorColor : AppTheme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (prov.currentPath.isNotEmpty) ...[
            const Text(' / ', style: TextStyle(color: AppTheme.textMuted)),
            Expanded(
              child: Text(
                prov.currentPath,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFileListPanel(EditorProvider prov, SortProvider sortProv, {required bool isMobile}) {
    if (prov.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(AppConstants.paddingExtraLarge),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (prov.files.isEmpty && prov.folders.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppConstants.paddingExtraLarge),
        child: Center(
          child: Text('Tidak ada file transcript', style: TextStyle(color: AppTheme.textMuted)),
        ),
      );
    }

    final sortedFiles = _getSortedFiles(prov, sortProv);

    if (isMobile) {
      return Container(
        decoration: BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.dividerColor),
        ),
        child: Column(
          children: [
            ...prov.folders.map((f) => _buildFolderTile(f, prov)),
            ...sortedFiles.map((f) => _buildFileTile(f)),
          ],
        ),
      );
    }

    return AppScrollbar(
      controller: listScrollController,
      child: ListView.separated(
        controller: listScrollController,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: prov.folders.length + sortedFiles.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
        itemBuilder: (context, index) {
          if (index < prov.folders.length) {
            return _buildFolderTile(prov.folders[index], prov);
          }
          return _buildFileTile(sortedFiles[index - prov.folders.length]);
        },
      ),
    );
  }

  Widget _buildFolderTile(Map<String, dynamic> folder, EditorProvider prov) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppConstants.paddingMedium, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppTheme.browserColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.folder_rounded,
          size: 18,
          color: AppTheme.browserColor,
        ),
      ),
      title: Text(
        folder['name'] ?? 'Folder',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppTheme.textPrimary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${folder['file_count'] ?? 0} files',
        style: const TextStyle(
          fontSize: 11,
          color: AppTheme.textMuted,
        ),
      ),
      onTap: () => prov.navigateTo(folder['path']),
    );
  }

  Widget _buildFileTile(Map<String, dynamic> fileData) {
    final file = fileData['path'] as String;
    final isSelected = file == selectedFile;
    final labelStr = fileData['label'] ?? 'single';
    final sizeStr = UiUtils.formatSize(fileData['size'] as int? ?? 0);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppConstants.paddingMedium, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: (isSelected ? AppTheme.editorColor : AppTheme.textMuted).withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.description_rounded,
          size: 18,
          color: isSelected ? AppTheme.editorColor : AppTheme.textMuted,
        ),
      ),
      title: Text(
        fileData['name'] as String,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          color: isSelected ? AppTheme.editorColor : AppTheme.textPrimary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '$labelStr · $sizeStr',
        style: const TextStyle(
          fontSize: 11,
          color: AppTheme.textMuted,
        ),
      ),
      selected: isSelected,
      selectedTileColor: AppTheme.editorColor.withOpacity(0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: () => onFileSelected(file),
    );
  }
}
