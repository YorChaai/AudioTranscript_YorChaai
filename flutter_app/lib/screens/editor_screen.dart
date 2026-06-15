import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/app_scrollbar.dart';
import '../providers/editor_provider.dart';
import '../providers/sort_provider.dart';
import '../services/api_service.dart';
import '../widgets/sort_menu.dart';

class EditorScreen extends StatefulWidget {
  final String? initialFilePath;

  const EditorScreen({super.key, this.initialFilePath});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  String? _selectedFile;
  bool _loadingContent = false;
  bool _saving = false;
  bool _hasChanges = false;
  bool _isLocked = true;
  final TextEditingController _editorController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _listScrollController = ScrollController();
  final ScrollController _mobileScrollController = ScrollController();

  EditorProvider get _prov => context.read<EditorProvider>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFiles();
    });
  }

  @override
  void dispose() {
    _editorController.dispose();
    _scrollController.dispose();
    _listScrollController.dispose();
    _mobileScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    await _prov.loadFiles();
    final files = _prov.files;
    if (files.isNotEmpty && _selectedFile == null) {
      if (widget.initialFilePath != null &&
          files.any((f) => f['path'] == widget.initialFilePath)) {
        setState(() {
          _selectedFile = widget.initialFilePath;
        });
        _loadFileContent(widget.initialFilePath!);
      } else if (mounted && Responsive.isWide(context)) {
        setState(() {
          _selectedFile = files.first['path'] as String;
        });
        _loadFileContent(files.first['path'] as String);
      }
    }
  }

  Future<void> _loadFileContent(String filepath) async {
    setState(() => _loadingContent = true);
    final content = await _prov.loadTranscriptContent(filepath);
    if (!mounted) return;

    if (content != null) {
      setState(() {
        _editorController.text = content;
        _hasChanges = false;
        _loadingContent = false;
      });
    } else {
      setState(() => _loadingContent = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_prov.errorMessage ?? 'Gagal memuat file')),
      );
    }
  }

  Future<void> _saveContent() async {
    if (_selectedFile == null) return;
    setState(() => _saving = true);
    final success =
        await _prov.saveTranscript(_selectedFile!, _editorController.text);
    if (!mounted) return;
    setState(() => _saving = false);
    if (success) {
      setState(() => _hasChanges = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perubahan berhasil disimpan di server!')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_prov.errorMessage ?? 'Gagal menyimpan')),
      );
    }
  }

  Future<void> _convertToPdf() async {
    if (_selectedFile == null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Converting to PDF...')));
    final pdfPath = await _prov.convertToPdf(_selectedFile!);
    if (!mounted) return;
    if (pdfPath != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Berhasil convert PDF! File: $pdfPath')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_prov.errorMessage ?? 'Gagal convert PDF')),
      );
    }
  }

  Future<void> _downloadFile(String filepath) async {
    try {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Mendownload...')));
      final bytes = await ApiService.downloadFile(filepath);
      final filename = filepath.split('/').last;

      // Save to Downloads folder logic (simplified)
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/$filename');
      await file.writeAsBytes(bytes);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File berhasil didownload ke ${file.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal download: $e')),
      );
    }
  }

  List<Map<String, dynamic>> _getSortedFiles(SortProvider sortProv) {
    final list = List<Map<String, dynamic>>.from(_prov.files);
    list.sort((a, b) {
      int result = 0;
      switch (sortProv.sortBy) {
        case 'date':
          final dateA = a['modified']?.toString() ?? '';
          final dateB = b['modified']?.toString() ?? '';
          result = dateA.compareTo(dateB);
          break;
        case 'type':
          final typeA =
              (a['name']?.toString() ?? '').split('.').last.toLowerCase();
          final typeB =
              (b['name']?.toString() ?? '').split('.').last.toLowerCase();
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

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final isWide = Responsive.isWide(context);
    final sortProv = context.watch<SortProvider>();

    return Consumer<EditorProvider>(
      builder: (context, prov, child) {
        return SafeArea(
          child: isWide
              ? _buildDesktopLayout(prov, sortProv)
              : _buildMobileLayout(prov, sortProv),
        );
      },
    );
  }

  Widget _buildDesktopLayout(EditorProvider prov, SortProvider sortProv) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 300,
          child: _buildSidebar(prov, sortProv, isMobile: false),
        ),
        const SizedBox(width: 24),
        Expanded(child: _buildEditor(prov)),
      ],
    );
  }

  Widget _buildMobileLayout(EditorProvider prov, SortProvider sortProv) {
    if (_selectedFile == null) {
      return _buildSidebar(prov, sortProv, isMobile: true);
    }
    return _buildEditor(prov);
  }

  Widget _buildSidebar(EditorProvider prov, SortProvider sortProv,
      {required bool isMobile}) {
    if (isMobile) {
      return RefreshIndicator(
        onRefresh: _loadFiles,
        child: AppScrollbar(
          controller: _mobileScrollController,
          child: CustomScrollView(
            controller: _mobileScrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _buildHeaderSection(sortProv),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildBreadcrumb(prov),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              sliver: SliverToBoxAdapter(
                child: _buildFileListPanel(prov, sortProv, isMobile: true),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
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
            padding: const EdgeInsets.all(20),
            child: _buildHeaderSection(sortProv),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
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
          child: const Icon(Icons.edit_note_rounded,
              color: AppTheme.editorColor, size: 24),
        ),
        const SizedBox(width: 16),
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
          onPressed: _loadFiles,
          icon: const Icon(Icons.refresh_rounded, size: 20),
        ),
      ],
    );
  }

  Widget _buildBreadcrumb(EditorProvider prov) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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

  Widget _buildFileListPanel(EditorProvider prov, SortProvider sortProv,
      {required bool isMobile}) {
    if (prov.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(32.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (prov.files.isEmpty && prov.folders.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32.0),
        child: Center(
          child: Text('Tidak ada file transcript',
              style: TextStyle(color: AppTheme.textMuted)),
        ),
      );
    }

    final sortedFiles = _getSortedFiles(sortProv);

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
      controller: _listScrollController,
      child: ListView.separated(
        controller: _listScrollController,
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
    final isSelected = file == _selectedFile;
    final labelStr = fileData['label'] ?? 'single';
    final sizeStr = _formatSize(fileData['size'] as int? ?? 0);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: (isSelected ? AppTheme.editorColor : AppTheme.textMuted)
              .withOpacity(0.15),
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
      onTap: () {
        setState(() => _selectedFile = file);
        _loadFileContent(file);
      },
    );
  }

  Widget _buildEditor(EditorProvider prov) {
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
            padding: EdgeInsets.fromLTRB(!Responsive.isWide(context) ? 12 : 20, 12, 12, 8),
            child: Row(
              children: [
                if (_selectedFile != null) ...[
                  if (!Responsive.isWide(context))
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => setState(() {
                        _selectedFile = null;
                        _editorController.clear();
                      }),
                      icon: const Icon(Icons.arrow_back_rounded),
                    )
                  else
                    const Icon(Icons.description_rounded,
                        size: 18, color: AppTheme.editorColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedFile!.split('/').last,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_hasChanges)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Unsaved',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.warning,
                              fontWeight: FontWeight.w600)),
                    ),
                  const SizedBox(width: 8),
                  _buildActionButtons(prov),
                ] else
                  const Expanded(
                    child: Text('Pilih file untuk diedit',
                        style: TextStyle(color: AppTheme.textSecondary)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildEditorArea(prov)),
        ],
      ),
    );
  }

  Widget _buildActionButtons(EditorProvider prov) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () => setState(() => _isLocked = !_isLocked),
          icon: Icon(
            _isLocked ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
            size: 20,
          ),
          tooltip: _isLocked ? 'Buka Kunci' : 'Kunci Teks',
          color: _isLocked ? AppTheme.textMuted : AppTheme.warning,
        ),
        IconButton(
          onPressed: _hasChanges && !_saving ? _showSaveDialog : null,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_rounded, size: 20),
          tooltip: 'Simpan',
          color: AppTheme.accentBlue,
        ),
        IconButton(
          onPressed:
              _selectedFile != null && !prov.isLoading ? _convertToPdf : null,
          icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
          tooltip: 'Convert ke PDF',
          color: AppTheme.pdfColor,
        ),
        IconButton(
          onPressed: _selectedFile != null
              ? () => _downloadFile(_selectedFile!)
              : null,
          icon: const Icon(Icons.download_rounded, size: 20),
          tooltip: 'Download TXT',
          color: AppTheme.accentCyan,
        ),
      ],
    );
  }

  Widget _buildEditorArea(EditorProvider prov) {
    if (_selectedFile == null) {
      return const Center(child: Text('Pilih file dari daftar'));
    }

    if (_loadingContent) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: AppScrollbar(
        controller: _scrollController,
        child: TextField(
          controller: _editorController,
          scrollController: _scrollController,
          readOnly: _isLocked,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              fontFamily: 'Consolas',
              color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            fillColor: Colors.transparent,
            filled: true,
            hintText: 'Mulai edit teks di sini...',
            hintStyle: TextStyle(color: AppTheme.textMuted),
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: (val) {
            if (!_hasChanges) setState(() => _hasChanges = true);
          },
        ),
      ),
    );
  }

  Future<void> _showSaveDialog() async {
    if (_selectedFile == null) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        title: const Text('Simpan File'),
        content: const Text('Pilih lokasi penyimpanan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _downloadFile(_selectedFile!);
            },
            child: const Text('Ke HP/Laptop'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _saveContent();
            },
            child: const Text('Ke Server'),
          ),
        ],
      ),
    );
  }
}
