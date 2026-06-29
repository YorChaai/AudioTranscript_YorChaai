import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/sort_menu.dart';
import '../widgets/app_scrollbar.dart';
import '../providers/sort_provider.dart';
import 'package:provider/provider.dart';
import '../utils/ui_utils.dart';

/// summary screen - buat dan edit ringkasan
class SummaryScreen extends StatefulWidget {
  final String? initialFilePath;

  const SummaryScreen({super.key, this.initialFilePath});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  List<Map<String, dynamic>> _files = [];
  List<Map<String, dynamic>> _folders = [];
  String _currentPath = '';
  final List<String> _pathHistory = [];
  bool _loading = true;
  String? _selectedFile;
  String? _content;
  bool _loadingContent = false;
  bool _saving = false;
  bool _hasChanges = false;
  bool _generating = false;
  bool _isLocked = true;
  String _status = '';
  
  // Results State
  List<Map<String, dynamic>> _summaryFiles = [];
  List<Map<String, dynamic>> _summaryFolders = [];
  bool _loadingSummaries = true;
  String _currentSummaryPath = '';
  final List<String> _summaryPathHistory = [];
  final ScrollController _resultsScrollController = ScrollController();

  final TextEditingController _editorController = TextEditingController();
  final ScrollController _listScrollController = ScrollController();
  final ScrollController _editorScrollController = ScrollController();
  final ScrollController _mobileScrollController = ScrollController();

  String _selectedModel = 'qwen3:8b';
  final Map<String, String> _models = {
    'qwen2.5:72b': 'Qwen 2.5 72B',
    'qwen2.5:32b': 'Qwen 2.5 32B',
    'qwen3:30b': 'Qwen 3 30B',
    'qwen3:8b': 'Qwen 3 8B',
    'llama3.1:70b': 'Llama 3.1 70B',
  };

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadFiles();
    _loadSummaries();
    if (widget.initialFilePath != null) {
      _selectedFile = widget.initialFilePath;
      _loadContent(widget.initialFilePath!);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _editorController.dispose();
    _listScrollController.dispose();
    _editorScrollController.dispose();
    _mobileScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    setState(() => _loading = true);
    try {
      // Load transcripts and summaries
      final resultTranscripts = await ApiService.listTranscripts(path: _currentPath);
      setState(() {
        _files =
            List<Map<String, dynamic>>.from(resultTranscripts['files'] ?? []);
        _folders =
            List<Map<String, dynamic>>.from(resultTranscripts['folders'] ?? []);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadSummaries() async {
    setState(() => _loadingSummaries = true);
    try {
      final result = await ApiService.listSummaries(path: _currentSummaryPath);
      if (!mounted) return;
      setState(() {
        _summaryFiles = List<Map<String, dynamic>>.from(result['files'] ?? []);
        _summaryFolders = List<Map<String, dynamic>>.from(result['folders'] ?? []);
        _loadingSummaries = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingSummaries = false);
    }
  }

  Future<void> _loadContent(String filepath) async {
    setState(() {
      _loadingContent = true;
      _hasChanges = false;
    });
    try {
      final result = await ApiService.getTranscript(filepath);
      setState(() {
        _content = result['content'];
        _editorController.text = _content ?? '';
        _loadingContent = false;
        _selectedFile = filepath;
      });
    } catch (e) {
      setState(() => _loadingContent = false);
      if (mounted) {
        UiUtils.showSnackBar(context, 'Error: $e', isError: true);
      }
    }
  }

  Future<void> _saveContent() async {
    if (_selectedFile == null) return;
    setState(() => _saving = true);
    try {
      await ApiService.updateTranscript(_selectedFile!, _editorController.text);
      setState(() {
        _saving = false;
        _hasChanges = false;
        _content = _editorController.text;
      });
      if (mounted) {
        UiUtils.showSnackBar(context, '✅ Tersimpan!');
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        UiUtils.showSnackBar(context, '❌ Gagal simpan: $e', isError: true);
      }
    }
  }

  Future<void> _generateSummary() async {
    if (_selectedFile == null) return;
    setState(() {
      _generating = true;
      _status = 'Memulai pembuatan ringkasan...';
    });

    try {
      final res = await ApiService.startSummary(
        txtFile: _selectedFile!,
        model: _selectedModel,
      );
      final jobId = res['job_id'];

      // Start polling
      _pollTimer?.cancel();
      _pollTimer =
          Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
        try {
          final statusRes = await ApiService.getJobStatus(jobId);
          if (!mounted) {
            timer.cancel();
            return;
          }

          final status = statusRes['status'];
          final progress = statusRes['progress'] ?? 0;

          setState(() {
            _status = 'Proses: $status ($progress%)';
          });

          if (status == 'completed' || progress == 100) {
            timer.cancel();
            setState(() {
              _generating = false;
              _status = 'Selesai!';
            });
            // Auto reload content to see if summary was appended or created
            _loadContent(_selectedFile!);
            UiUtils.showSnackBar(context, '✅ Ringkasan berhasil dibuat!');
          } else if (status == 'failed' || statusRes['error'] != null) {
            timer.cancel();
            setState(() {
              _generating = false;
              _status = 'Gagal: ${statusRes["error"]}';
            });
            UiUtils.showSnackBar(context, '❌ Gagal: ${statusRes["error"]}', isError: true);
          }
        } catch (e) {
          // ignore network hiccups
        }
      });
    } catch (e) {
      setState(() => _generating = false);
      if (mounted) {
        UiUtils.showSnackBar(context, '❌ Gagal request: $e', isError: true);
      }
    }
  }

  Future<void> _downloadFile(String filepath) async {
    try {
      final bytes = await ApiService.downloadFile(filepath);
      final filename = filepath.split('/').last;

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes);

      final openResult = await OpenFile.open(file.path);

      if (mounted) {
        UiUtils.showSnackBar(
          context, 
          openResult.type == ResultType.done ? '✅ File dibuka: $filename' : '✅ File tersimpan: $filename'
        );
      }
    } catch (e) {
      if (mounted) {
        UiUtils.showSnackBar(context, '❌ Download gagal: $e', isError: true);
      }
    }
  }


  List<Map<String, dynamic>> _getSortedFiles(SortProvider sortProv) {
    final list = List<Map<String, dynamic>>.from(_files);
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

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (_selectedFile != null && _hasChanges && !_saving) _saveContent();
        },
      },
      child: Focus(
        autofocus: false,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              Container(
                color: AppTheme.surfaceDark,
                child: const TabBar(
                  indicatorColor: AppTheme.accentCyan,
                  labelColor: AppTheme.accentCyan,
                  unselectedLabelColor: AppTheme.textSecondary,
                  tabs: [
                    Tab(icon: Icon(Icons.auto_awesome), text: 'Convert'),
                    Tab(icon: Icon(Icons.description), text: 'Results'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildConvertTab(context),
                    _buildResultsTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConvertTab(BuildContext context) {
    final isWide = Responsive.isWide(context);
    final sortProv = context.watch<SortProvider>();

    return SafeArea(
      child:
          isWide ? _buildDesktopLayout(sortProv) : _buildMobileLayout(sortProv),
    );
  }

  Widget _buildDesktopLayout(SortProvider sortProv) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
            width: 300, child: Column(
              children: [
                _buildBreadcrumb(),
                const SizedBox(height: 12),
                Expanded(child: _buildFileListPanel(sortProv, isMobile: false)),
              ]
            )),
        const SizedBox(width: 24),
        Expanded(child: _buildEditorPanel()),
      ],
    );
  }

  Widget _buildMobileLayout(SortProvider sortProv) {
    if (_selectedFile == null || _content == null) {
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
                child: _buildHeader(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildBreadcrumb(),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              sliver: SliverToBoxAdapter(
                child: _buildFileListPanel(sortProv, isMobile: true),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
          ],
        ),
      ),
    );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              IconButton(
                onPressed: () => setState(() {
                  _selectedFile = null;
                  _content = null;
                }),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Expanded(
                child: Text(
                  _selectedFile?.split('/').last ?? '',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _buildActionButtons(),
            ],
          ),
        ),
        const Divider(height: 1),
        if (_selectedFile != null) _buildGenerationControls(),
        Expanded(child: _buildEditorArea()),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.accentCyan.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            color: AppTheme.accentCyan,
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI Summary',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              Text(
                'Buat ringkasan dari transcript',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFileListPanel(SortProvider sortProv, {required bool isMobile}) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
            child: Row(
              children: [
                const Text(
                  'File Transcript',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
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
            ),
          ),
          const Divider(height: 1),
          if (isMobile)
            _loading
                ? const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : (_files.isEmpty && _folders.isEmpty)
                    ? _buildEmptyState()
                    : Column(
                        children: [
                          ..._folders.map((f) => _buildFolderTile(f)),
                          ..._getSortedFiles(sortProv).map((file) => _buildFileTile(file)),
                        ],
                      )
          else
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : (_files.isEmpty && _folders.isEmpty)
                      ? _buildEmptyState()
                      : Builder(
                          builder: (context) {
                            final sortedFiles = _getSortedFiles(sortProv);
                            return AppScrollbar(
                              controller: _listScrollController,
                              child: ListView.separated(
                                controller: _listScrollController,
                                physics: const BouncingScrollPhysics(),
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                itemCount: _folders.length + sortedFiles.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1, indent: 56),
                                itemBuilder: (context, index) {
                                  if (index < _folders.length) {
                                    return _buildFolderTile(_folders[index]);
                                  }
                                  return _buildFileTile(sortedFiles[index - _folders.length]);
                                },
                              ),
                            );
                          },
                        ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.all(32.0),
            child: Column(
              children: [
                Icon(Icons.article_rounded,
                    size: 48, color: AppTheme.textMuted),
                SizedBox(height: 12),
                Text('Belum ada transcript',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileTile(Map<String, dynamic> file) {
    final isSelected = _selectedFile == file['path'];
    return ListTile(
      dense: true,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: (isSelected ? AppTheme.accentCyan : AppTheme.textMuted)
              .withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.description_rounded,
          color: isSelected ? AppTheme.accentCyan : AppTheme.textMuted,
          size: 18,
        ),
      ),
      title: Text(
        file['name'],
        style: TextStyle(
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          color: isSelected ? AppTheme.accentCyan : AppTheme.textPrimary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${file["label"]} · ${UiUtils.formatSize(file["size"] ?? 0)}',
        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
      ),
      selected: isSelected,
      selectedTileColor: AppTheme.accentCyan.withOpacity(0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: () => _loadContent(file['path']),
    );
  }

  Widget _buildFolderTile(Map<String, dynamic> folder) {
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
      onTap: () {
        setState(() {
          _pathHistory.add(_currentPath);
          _currentPath = folder['path'];
        });
        _loadFiles();
      },
    );
  }

  Widget _buildBreadcrumb() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(
        children: [
          if (_currentPath.isNotEmpty)
            InkWell(
              onTap: () {
                if (_pathHistory.isNotEmpty) {
                  setState(() {
                    _currentPath = _pathHistory.removeLast();
                  });
                  _loadFiles();
                }
              },
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_rounded, size: 18, color: AppTheme.accentCyan),
                  SizedBox(width: 4),
                  Text('Kembali', style: TextStyle(fontSize: 13, color: AppTheme.accentCyan)),
                  SizedBox(width: 12),
                ],
              ),
            ),
          InkWell(
            onTap: _currentPath.isNotEmpty ? () {
                setState(() {
                  _pathHistory.clear();
                  _currentPath = '';
                });
                _loadFiles();
            } : null,
            child: Text(
              '📁 root',
              style: TextStyle(
                fontSize: 13,
                color: _currentPath.isNotEmpty ? AppTheme.accentCyan : AppTheme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (_currentPath.isNotEmpty) ...[
            const Text(' / ', style: TextStyle(color: AppTheme.textMuted)),
            Expanded(
              child: Text(
                _currentPath,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEditorPanel() {
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
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
            child: Row(
              children: [
                if (_selectedFile != null) ...[
                  const Icon(Icons.description_rounded,
                      size: 18, color: AppTheme.accentCyan),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedFile!.split('/').last,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildActionButtons(),
                ] else
                  const Expanded(
                    child: Text('Pilih file untuk diringkas',
                        style: TextStyle(color: AppTheme.textSecondary)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_selectedFile != null) _buildGenerationControls(),
          Expanded(child: _buildEditorArea()),
        ],
      ),
    );
  }

  Widget _buildGenerationControls() {
    final isWide = Responsive.isWide(context);
    
    final modelDropdown = Row(
      children: [
        const Text("Model: "),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<String>(
            value: _selectedModel,
            isExpanded: true,
            dropdownColor: AppTheme.cardDark,
            underline: const SizedBox(),
            items: _models.entries.map((e) {
              return DropdownMenuItem(
                value: e.key,
                child: Text(e.value, style: const TextStyle(fontSize: 14)),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedModel = val);
              }
            },
          ),
        ),
      ],
    );

    final generateButton = ElevatedButton.icon(
      onPressed: _generating ? null : _generateSummary,
      icon: _generating
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.auto_awesome),
      label: Text(_generating ? 'Memproses...' : 'Generate Summary'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.accentCyan,
        foregroundColor: Colors.white,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: AppTheme.cardDark,
          padding: const EdgeInsets.all(12),
          child: isWide
              ? Row(
                  children: [
                    Expanded(child: modelDropdown),
                    const SizedBox(width: 12),
                    generateButton,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    modelDropdown,
                    const SizedBox(height: 12),
                    generateButton,
                  ],
                ),
        ),
        if (_generating)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Text(_status, style: const TextStyle(color: AppTheme.accentCyan)),
          ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildActionButtons() {
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
          tooltip: 'Simpan Teks Asli',
          color: AppTheme.accentBlue,
        ),
        IconButton(
          onPressed: _selectedFile != null
              ? () => _downloadFile(_selectedFile!)
              : null,
          icon: const Icon(Icons.download_rounded, size: 20),
          tooltip: 'Download',
          color: AppTheme.accentCyan,
        ),
      ],
    );
  }

  Widget _buildEditorArea() {
    if (_selectedFile == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 64, color: AppTheme.textMuted),
            SizedBox(height: 16),
            Text('Pilih file dari daftar',
                style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
          ],
        ),
      );
    }

    if (_loadingContent) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Theme(
        data: Theme.of(context).copyWith(
          scrollbarTheme: ScrollbarThemeData(
            thumbVisibility: WidgetStateProperty.all(false),
            trackVisibility: WidgetStateProperty.all(false),
            thickness: WidgetStateProperty.all(0),
          ),
        ),
        child: AppScrollbar(
          controller: _editorScrollController,
          child: TextField(
            controller: _editorController,
            scrollController: _editorScrollController,
            readOnly: _isLocked,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              fontFamily: 'Consolas',
              color: AppTheme.textPrimary,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              fillColor: Colors.transparent,
              filled: true,
              hintText: 'Teks transkripsi...',
              hintStyle: TextStyle(color: AppTheme.textMuted),
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (val) {
              if (!_hasChanges) setState(() => _hasChanges = true);
            },
          ),
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
        content: const Text('Pilih lokasi penyimpanan untuk file ini.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _saveContent();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
                foregroundColor: Colors.white),
            child: const Text('Ke Server'),
          ),
        ],
      ),
    );
  }
  Widget _buildResultsTab() {
    return Column(
      children: [
        _buildSummaryBreadcrumb(),
        Expanded(
          child: _loadingSummaries
              ? const Center(child: CircularProgressIndicator())
              : (_summaryFiles.isEmpty && _summaryFolders.isEmpty)
                  ? const Center(
                      child: Text('Belum ada summary',
                          style: TextStyle(color: AppTheme.textSecondary)))
                  : AppScrollbar(
                      controller: _resultsScrollController,
                      thumbVisibility: false,
                      child: ListView.separated(
                        controller: _resultsScrollController,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _summaryFolders.length + _summaryFiles.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
                        itemBuilder: (context, index) {
                          if (index < _summaryFolders.length) {
                            final folder = _summaryFolders[index];
                            return ListTile(
                              leading: const Icon(Icons.folder_rounded, color: AppTheme.browserColor),
                              title: Text(folder['name']),
                              subtitle: Text('${folder['file_count']} files'),
                              onTap: () {
                                setState(() {
                                  _summaryPathHistory.add(_currentSummaryPath);
                                  _currentSummaryPath = folder['path'];
                                });
                                _loadSummaries();
                              },
                            );
                          }
                          final file = _summaryFiles[index - _summaryFolders.length];
                          return ListTile(
                            leading: const Icon(Icons.description_rounded, color: AppTheme.accentCyan),
                            title: Text(file['name']),
                            subtitle: Text(UiUtils.formatSize(file['size'] ?? 0)),
                            trailing: IconButton(
                              icon: const Icon(Icons.download_rounded, color: AppTheme.accentCyan),
                              onPressed: () => _downloadFile('summary/${file['path']}'),
                            ),
                            onTap: () => _downloadFile('summary/${file['path']}'),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildSummaryBreadcrumb() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppTheme.backgroundDark,
        border: Border(bottom: BorderSide(color: AppTheme.dividerColor)),
      ),
      child: Row(
        children: [
          if (_currentSummaryPath.isNotEmpty)
            InkWell(
              onTap: () {
                if (_summaryPathHistory.isNotEmpty) {
                  setState(() {
                    _currentSummaryPath = _summaryPathHistory.removeLast();
                  });
                  _loadSummaries();
                }
              },
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_rounded, size: 18, color: AppTheme.accentCyan),
                  SizedBox(width: 4),
                  Text('Kembali', style: TextStyle(fontSize: 13, color: AppTheme.accentCyan)),
                  SizedBox(width: 12),
                ],
              ),
            ),
          InkWell(
            onTap: _currentSummaryPath.isNotEmpty ? () {
                setState(() {
                  _summaryPathHistory.clear();
                  _currentSummaryPath = '';
                });
                _loadSummaries();
            } : null,
            child: Text(
              '📁 root',
              style: TextStyle(
                fontSize: 13,
                color: _currentSummaryPath.isNotEmpty ? AppTheme.accentCyan : AppTheme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (_currentSummaryPath.isNotEmpty) ...[
            const Text(' / ', style: TextStyle(color: AppTheme.textMuted)),
            Expanded(
              child: Text(
                _currentSummaryPath,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const Spacer(),
          IconButton(
            onPressed: _loadSummaries,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          )
        ],
      ),
    );
  }
}
