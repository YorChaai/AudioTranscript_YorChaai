import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import '../config/theme.dart';
import '../config/api_config.dart';
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

  static const List<Map<String, dynamic>> _defaultCloudModels = [
    {
      'id': 'gemini-2.0-flash',
      'name': 'Google Gemini 2.0 Flash',
      'provider': 'gemini',
      'badge': 'Cepat & Gratis',
    },
    {
      'id': 'gemini-1.5-flash',
      'name': 'Google Gemini 1.5 Flash',
      'provider': 'gemini',
      'badge': 'Rekomendasi',
    },
    {
      'id': 'gemini-1.5-pro',
      'name': 'Google Gemini 1.5 Pro',
      'provider': 'gemini',
      'badge': 'Akurasi Tinggi',
    },
    {
      'id': 'claude-3-5-sonnet-20241022',
      'name': 'Claude 3.5 Sonnet',
      'provider': 'claude',
      'badge': 'Kualitas Terbaik',
    },
    {
      'id': 'claude-3-5-haiku-20241022',
      'name': 'Claude 3.5 Haiku',
      'provider': 'claude',
      'badge': 'Cepat & Ringan',
    },
    {
      'id': 'grok-2-latest',
      'name': 'xAI Grok 2',
      'provider': 'grok',
      'badge': 'Reasoning Cerdas',
    },
    {
      'id': 'grok-beta',
      'name': 'xAI Grok Beta',
      'provider': 'grok',
      'badge': 'Cepat',
    },
    {
      'id': 'gpt-4o-mini',
      'name': 'OpenAI GPT-4o Mini',
      'provider': 'openai',
      'badge': 'Hemat',
    },
    {
      'id': 'gpt-4o',
      'name': 'OpenAI GPT-4o',
      'provider': 'openai',
      'badge': 'Flagship',
    },
  ];

  String _selectedModel = 'gemini-2.0-flash';
  String _selectedProvider = 'gemini';
  String _customModelName = '';
  List<Map<String, dynamic>> _ollamaModels = [];
  List<Map<String, dynamic>> _cloudModels = List.from(_defaultCloudModels);
  bool _ollamaOnline = false;
  bool _loadingModels = false;

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadFiles();
    _loadSummaries();
    _loadModels();
    if (widget.initialFilePath != null) {
      _selectedFile = widget.initialFilePath;
      _loadContent(widget.initialFilePath!);
    }
  }

  Future<void> _loadModels() async {
    setState(() => _loadingModels = true);
    try {
      final res = await ApiService.getSummaryModels();
      final ollama = List<Map<String, dynamic>>.from(res['ollama_models'] ?? []);
      final cloud = List<Map<String, dynamic>>.from(res['cloud_models'] ?? []);
      final isOnline = res['ollama_online'] == true;

      setState(() {
        _ollamaModels = ollama;
        if (cloud.isNotEmpty) {
          _cloudModels = cloud;
        }
        _ollamaOnline = isOnline;
        _loadingModels = false;

        // If local Ollama has models, prefer selecting local Ollama model
        if (_ollamaModels.isNotEmpty && _selectedProvider == 'ollama') {
          if (!_ollamaModels.any((m) => m['name'] == _selectedModel)) {
            _selectedModel = _ollamaModels.first['name'];
          }
        }
      });
    } catch (e) {
      setState(() => _loadingModels = false);
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

  String? _getApiKeyForProvider(String provider) {
    switch (provider.toLowerCase()) {
      case 'gemini':
        return ApiConfig.geminiApiKey;
      case 'claude':
        return ApiConfig.claudeApiKey;
      case 'grok':
        return ApiConfig.grokApiKey;
      case 'openai':
        return ApiConfig.openaiApiKey;
      default:
        return null;
    }
  }

  Widget _buildApiKeyInputRow(String label, String provider, TextEditingController controller, String docUrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              docUrl,
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: true,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Paste $provider API Key...',
            isDense: true,
            prefixIcon: const Icon(Icons.key_rounded, size: 16),
            suffixIcon: IconButton(
              icon: const Icon(Icons.paste_rounded, size: 16),
              tooltip: 'Paste',
              onPressed: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                if (data?.text != null) {
                  controller.text = data!.text!.trim();
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showAllApiKeysDialog({String? focusProvider}) async {
    final geminiController = TextEditingController(text: ApiConfig.geminiApiKey);
    final claudeController = TextEditingController(text: ApiConfig.claudeApiKey);
    final grokController = TextEditingController(text: ApiConfig.grokApiKey);
    final openaiController = TextEditingController(text: ApiConfig.openaiApiKey);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.vpn_key_rounded, color: AppTheme.accentCyan, size: 22),
            SizedBox(width: 10),
            Text('Kelola API Key Cloud AI', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Masukkan API Key untuk model Cloud AI yang ingin Anda gunakan. Kunci ini akan disimpan selama sesi aplikasi:',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 18),
                _buildApiKeyInputRow('🟣 Google Gemini API Key', 'gemini', geminiController, 'aistudio.google.com'),
                const SizedBox(height: 14),
                _buildApiKeyInputRow('🟠 Anthropic Claude API Key', 'claude', claudeController, 'console.anthropic.com'),
                const SizedBox(height: 14),
                _buildApiKeyInputRow('⚫ xAI Grok API Key', 'grok', grokController, 'console.x.ai'),
                const SizedBox(height: 14),
                _buildApiKeyInputRow('🟢 OpenAI API Key', 'openai', openaiController, 'platform.openai.com'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              ApiConfig.geminiApiKey = geminiController.text.trim();
              ApiConfig.claudeApiKey = claudeController.text.trim();
              ApiConfig.grokApiKey = grokController.text.trim();
              ApiConfig.openaiApiKey = openaiController.text.trim();
              Navigator.pop(ctx);
              setState(() {});
              if (mounted) {
                UiUtils.showSnackBar(context, '✅ API Key Cloud AI berhasil disimpan!');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentCyan,
              foregroundColor: Colors.white,
            ),
            child: const Text('Simpan Kunci'),
          ),
        ],
      ),
    );
  }

  Future<bool> _ensureApiKey(String provider) async {
    final key = _getApiKeyForProvider(provider);
    if (key != null && key.isNotEmpty) return true;
    await _showAllApiKeysDialog(focusProvider: provider);
    final updated = _getApiKeyForProvider(provider);
    return updated != null && updated.isNotEmpty;
  }

  Future<void> _showCustomModelDialog() async {
    final controller = TextEditingController(text: _customModelName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit_note_rounded, color: AppTheme.accentCyan, size: 22),
            SizedBox(width: 10),
            Text('Model Custom', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Masukkan nama model Ollama atau model lain yang terinstall di komputer Anda:',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Contoh: mistral:7b, deepseek-r1:8b, dll.',
                prefixIcon: Icon(Icons.memory_rounded, size: 18),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentCyan,
              foregroundColor: Colors.white,
            ),
            child: const Text('Gunakan'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        _customModelName = result;
        _selectedModel = result;
        _selectedProvider = 'ollama';
      });
    }
  }

  Future<void> _generateSummary() async {
    if (_selectedFile == null) return;

    if (_selectedModel.isEmpty) {
      UiUtils.showSnackBar(context, 'Pilih model terlebih dahulu!', isError: true);
      return;
    }

    // Check Cloud AI API Key if needed
    if (_selectedProvider == 'gemini' || _selectedProvider == 'grok' || _selectedProvider == 'openai') {
      final hasKey = await _ensureApiKey(_selectedProvider);
      if (!hasKey) {
        if (mounted) {
          UiUtils.showSnackBar(context, 'API Key diperlukan untuk menggunakan model cloud ini!', isError: true);
        }
        return;
      }
    }

    setState(() {
      _generating = true;
      _status = 'Memulai pembuatan ringkasan...';
    });

    try {
      final apiKey = _getApiKeyForProvider(_selectedProvider);
      final res = await ApiService.startSummary(
        txtFile: _selectedFile!,
        model: _selectedModel,
        provider: _selectedProvider,
        apiKey: apiKey,
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
            _loadSummaries();
            final outPath = statusRes['output_file'] as String?;
            if (outPath != null && outPath.isNotEmpty) {
              _loadContent(outPath);
            } else if (_selectedFile != null) {
              _loadContent(_selectedFile!);
            }
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
      final filename = filepath.replaceAll('\\', '/').split('/').last;

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
                  _selectedFile?.replaceAll('\\', '/').split('/').last ?? '',
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
    return Material(
      color: AppTheme.cardDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'File Transcript',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SortMenu(
                  sortBy: sortProv.sortBy,
                  sortAscending: sortProv.sortAscending,
                  onSortByChanged: (value) => sortProv.setSortBy(value),
                  onSortOrderChanged: (value) => sortProv.setSortOrder(value),
                ),
                IconButton(
                  onPressed: _loadFiles,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  tooltip: 'Refresh',
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
    return Material(
      color: Colors.transparent,
      child: ListTile(
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
      ),
    );
  }

  Widget _buildFolderTile(Map<String, dynamic> folder) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
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
      ),
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
    return Material(
      color: AppTheme.cardDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
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
                      _selectedFile!.replaceAll('\\', '/').split('/').last,
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
    final isCloudModel = _selectedProvider == 'gemini' || _selectedProvider == 'grok' || _selectedProvider == 'openai';

    // Prepare dynamic dropdown items
    final List<DropdownMenuItem<String>> dropdownItems = [];

    // --- 1. LOCAL OLLAMA MODELS ---
    dropdownItems.add(
      const DropdownMenuItem<String>(
        enabled: false,
        value: '__header_ollama__',
        child: Row(
          children: [
            Icon(Icons.computer_rounded, size: 16, color: AppTheme.accentCyan),
            SizedBox(width: 8),
            Text(
              'LOKAL OLLAMA (Dinamis)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppTheme.accentCyan,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );

    if (_ollamaModels.isEmpty) {
      dropdownItems.add(
        DropdownMenuItem<String>(
          enabled: false,
          value: '__no_ollama__',
          child: Padding(
            padding: const EdgeInsets.only(left: 12.0),
            child: Text(
              _ollamaOnline ? 'Belum ada model terinstall di Ollama' : 'Ollama Offline / Tidak Terdeteksi',
              style: const TextStyle(fontSize: 13, color: AppTheme.textMuted, fontStyle: FontStyle.italic),
            ),
          ),
        ),
      );
    } else {
      for (final m in _ollamaModels) {
        final name = m['name'] as String? ?? '';
        final display = m['display'] as String? ?? name;
        dropdownItems.add(
          DropdownMenuItem<String>(
            value: name,
            child: Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Row(
                children: [
                  const Icon(Icons.memory_rounded, size: 15, color: Colors.white70),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      display,
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    // --- 2. CLOUD AI MODELS (TEMPLATE / API TOKEN) ---
    dropdownItems.add(
      const DropdownMenuItem<String>(
        enabled: false,
        value: '__header_cloud__',
        child: Row(
          children: [
            Icon(Icons.cloud_rounded, size: 16, color: AppTheme.accentBlue),
            SizedBox(width: 8),
            Text(
              'CLOUD AI (Butuh API Key)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppTheme.accentBlue,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );

    for (final c in _cloudModels) {
      final id = c['id'] as String? ?? '';
      final name = c['name'] as String? ?? id;
      final badge = c['badge'] as String? ?? '';
      dropdownItems.add(
        DropdownMenuItem<String>(
          value: id,
          child: Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 15, color: AppTheme.accentBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (badge.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.accentBlue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(fontSize: 10, color: AppTheme.accentBlue),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // --- 3. CUSTOM MODEL OPTION ---
    dropdownItems.add(
      const DropdownMenuItem<String>(
        value: '__custom__',
        child: Padding(
          padding: EdgeInsets.only(left: 8.0),
          child: Row(
            children: [
              Icon(Icons.edit_note_rounded, size: 15, color: Colors.orangeAccent),
              SizedBox(width: 8),
              Text(
                '✏️ Input Model Lain...',
                style: TextStyle(fontSize: 13, color: Colors.orangeAccent),
              ),
            ],
          ),
        ),
      ),
    );

    final modelControl = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(
        children: [
          const Icon(Icons.psychology_rounded, size: 18, color: AppTheme.accentCyan),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: dropdownItems.any((item) => item.value == _selectedModel) ? _selectedModel : null,
                hint: Text(
                  _selectedModel.isNotEmpty ? _selectedModel : 'Pilih Model AI...',
                  style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
                isExpanded: true,
                dropdownColor: AppTheme.cardDark,
                items: dropdownItems,
                onChanged: (val) {
                  if (val == null) return;
                  if (val == '__custom__') {
                    _showCustomModelDialog();
                    return;
                  }

                  // Find provider for selected model
                  final cloudMatch = _cloudModels.firstWhere(
                    (c) => c['id'] == val,
                    orElse: () => <String, dynamic>{},
                  );

                  setState(() {
                    _selectedModel = val;
                    if (cloudMatch.isNotEmpty) {
                      _selectedProvider = cloudMatch['provider'] ?? 'gemini';
                      if (_getApiKeyForProvider(_selectedProvider)?.isNotEmpty != true) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _showAllApiKeysDialog(focusProvider: _selectedProvider);
                        });
                      }
                    } else {
                      _selectedProvider = 'ollama';
                    }
                  });
                },
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.vpn_key_rounded,
              size: 18,
              color: isCloudModel && _getApiKeyForProvider(_selectedProvider)?.isNotEmpty != true
                  ? AppTheme.warning
                  : AppTheme.accentCyan,
            ),
            tooltip: 'Kelola API Key Cloud AI (Gemini, Claude, Grok, OpenAI)',
            onPressed: () => _showAllApiKeysDialog(focusProvider: isCloudModel ? _selectedProvider : null),
          ),
          IconButton(
            icon: _loadingModels
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentCyan),
                  )
                : const Icon(Icons.refresh_rounded, size: 18, color: AppTheme.textSecondary),
            tooltip: 'Refresh Model Ollama Lokal',
            onPressed: _loadingModels ? null : _loadModels,
          ),
        ],
      ),
    );

    final generateButton = ElevatedButton.icon(
      onPressed: _generating ? null : _generateSummary,
      icon: _generating
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.auto_awesome_rounded, size: 18),
      label: Text(
        _generating ? 'Memproses...' : 'Generate Summary',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.accentCyan,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                    Expanded(child: modelControl),
                    const SizedBox(width: 12),
                    generateButton,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    modelControl,
                    const SizedBox(height: 10),
                    generateButton,
                  ],
                ),
        ),
        if (_generating)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentCyan),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_status, style: const TextStyle(color: AppTheme.accentCyan, fontSize: 13)),
                ),
              ],
            ),
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
                            return Material(
                              color: Colors.transparent,
                              child: ListTile(
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
                              ),
                            );
                          }
                          final file = _summaryFiles[index - _summaryFolders.length];
                          return Material(
                            color: Colors.transparent,
                            child: ListTile(
                              leading: const Icon(Icons.description_rounded, color: AppTheme.accentCyan),
                              title: Text(file['name']),
                              subtitle: Text(UiUtils.formatSize(file['size'] ?? 0)),
                              trailing: IconButton(
                                icon: const Icon(Icons.download_rounded, color: AppTheme.accentCyan),
                                onPressed: () => _downloadFile('summary/${file['path']}'),
                              ),
                              onTap: () => _downloadFile('summary/${file['path']}'),
                            ),
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
