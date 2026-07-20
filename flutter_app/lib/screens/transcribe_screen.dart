import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../config/theme.dart';
import '../config/constants.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/sort_menu.dart';
import '../widgets/app_scrollbar.dart';
import '../providers/transcribe_provider.dart';
import '../providers/sort_provider.dart';
import '../services/api_service.dart';
import '../utils/ui_utils.dart';

import 'transcribe/transcribe_sidebar.dart';
import 'transcribe/transcribe_audio_grid.dart';

class TranscribeScreen extends StatefulWidget {
  const TranscribeScreen({super.key});

  @override
  State<TranscribeScreen> createState() => _TranscribeScreenState();
}

class _TranscribeScreenState extends State<TranscribeScreen> with SingleTickerProviderStateMixin {
  final List<String> _selectedFiles = [];
  String _language = 'auto';
  bool _doTranslate = false;
  String _targetLang = 'id';
  
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  late AnimationController _progressAnimController;
  Animation<double>? _progressAnimation;
  double _displayProgress = 0;

  final ScrollController _sidebarListController = ScrollController();
  final ScrollController _gridScrollController = ScrollController();
  final ScrollController _mobileScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _progressAnimController = AnimationController(
      vsync: this,
      duration: AppConstants.animationFast,
    );
    _progressAnimController.addListener(() {
      setState(() {
        _displayProgress = _progressAnimation?.value ?? context.read<TranscribeProvider>().progress;
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<TranscribeProvider>().loadAudioFiles();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _progressAnimController.dispose();
    _sidebarListController.dispose();
    _gridScrollController.dispose();
    _mobileScrollController.dispose();
    super.dispose();
  }

  void _animateProgressTo(double target) {
    if (!mounted) return;
    _progressAnimation = Tween<double>(
      begin: _displayProgress,
      end: target,
    ).animate(CurvedAnimation(
      parent: _progressAnimController,
      curve: Curves.easeOut,
    ));
    _progressAnimController.forward(from: 0);
  }

  Future<void> _showUploadSourceDialog(bool isVideo) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        title: Text(isVideo ? 'Upload Video' : 'Upload Audio', style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_copy, color: AppTheme.accentBlue),
              title: const Text('Pilih File (Bisa pilih banyak)', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickFiles(isVideo, fromFolder: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder, color: AppTheme.accentBlue),
              title: const Text('Pilih Folder', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickFiles(isVideo, fromFolder: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFiles(bool isVideo, {required bool fromFolder}) async {
    List<File> selectedFiles = [];
    
    if (fromFolder) {
      String? directoryPath = await FilePicker.getDirectoryPath();
      if (directoryPath == null) return;
      
      final dir = Directory(directoryPath);
      final allowedExts = isVideo ? ['.mp4', '.mkv', '.avi', '.mov'] : ['.mp3', '.wav', '.m4a', '.ogg'];
      
      try {
        final List<FileSystemEntity> entities = await dir.list(recursive: true).toList();
        for (var entity in entities) {
          if (entity is File) {
            final ext = entity.path.toLowerCase();
            if (allowedExts.any((e) => ext.endsWith(e))) {
              selectedFiles.add(entity);
            }
          }
        }
      } catch (e) {
        if (mounted) UiUtils.showSnackBar(context, 'Gagal membaca folder: $e', isError: true);
        return;
      }
    } else {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: isVideo ? ['mp4', 'mkv', 'avi', 'mov'] : ['mp3', 'wav', 'm4a', 'ogg'],
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;
      
      selectedFiles = result.files.where((f) => f.path != null).map((f) => File(f.path!)).toList();
    }
    
    if (selectedFiles.isEmpty) {
      if (mounted) UiUtils.showSnackBar(context, 'Tidak ada file media ditemukan');
      return;
    }
    
    if (!mounted) return;
    _showUploadConfirmationDialog(selectedFiles, isVideo);
  }

  void _showUploadConfirmationDialog(List<File> files, bool isVideo) {
    List<File> selectedForUpload = List.from(files);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: AppTheme.cardDark,
              title: const Text('Pilih File untuk Diupload', style: TextStyle(color: Colors.white)),
              content: SizedBox(
                width: 600,
                height: 400,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundDark,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(isVideo ? Icons.video_file : Icons.audio_file, color: AppTheme.accentBlue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Ditemukan ${files.length} file. Pilih yang ingin diproses.',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setStateDialog(() {
                                if (selectedForUpload.length == files.length) {
                                  selectedForUpload.clear();
                                } else {
                                  selectedForUpload = List.from(files);
                                }
                              });
                            },
                            child: Text(
                              selectedForUpload.length == files.length ? 'Deselect All' : 'Select All',
                              style: const TextStyle(color: AppTheme.accentCyan),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.builder(
                        itemCount: files.length,
                        itemBuilder: (context, index) {
                          final file = files[index];
                          final fileName = file.path.split(Platform.pathSeparator).last;
                          final isSelected = selectedForUpload.contains(file);
                          
                          return CheckboxListTile(
                            title: Text(fileName, style: const TextStyle(color: Colors.white, fontSize: 13)),
                            value: isSelected,
                            activeColor: AppTheme.accentBlue,
                            checkColor: Colors.white,
                            side: const BorderSide(color: AppTheme.textSecondary),
                            onChanged: (val) {
                              setStateDialog(() {
                                if (val == true) {
                                  selectedForUpload.add(file);
                                } else {
                                  selectedForUpload.remove(file);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: selectedForUpload.isEmpty ? null : () {
                    Navigator.pop(context);
                    _processMultipleUploads(selectedForUpload, isVideo);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentBlue),
                  child: Text('Proses ${selectedForUpload.length} File'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _processMultipleUploads(List<File> files, bool isVideo) async {
    final prov = context.read<TranscribeProvider>();
    
    final progressNotifier = ValueNotifier<Map<String, dynamic>>({
      'index': 0,
      'total': files.length,
      'fileName': files.first.path.split(Platform.pathSeparator).last,
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: progressNotifier,
          builder: (context, progress, child) {
            return AlertDialog(
              backgroundColor: AppTheme.cardDark,
              title: const Text('Mengunggah File...', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Memproses ${progress['index'] + 1} dari ${progress['total']}', style: const TextStyle(color: Colors.white)),
                  const SizedBox(height: 8),
                  Text(progress['fileName'], style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  if (progress['currentProgress'] != null) ...[
                    LinearProgressIndicator(
                      value: progress['currentProgress'] >= 1.0 ? null : progress['currentProgress'],
                      backgroundColor: AppTheme.dividerColor,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accentBlue),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      progress['currentProgress'] >= 1.0
                          ? (isVideo 
                              ? 'Mengonversi ke MP3 (Mohon tunggu, proses ini butuh waktu sesuai durasi video)...' 
                              : 'Menyimpan file...')
                          : '${(progress['currentProgress'] * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  ] else ...[
                    const LinearProgressIndicator(
                      backgroundColor: AppTheme.dividerColor,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentBlue),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );

    final results = await prov.uploadMediaBatch(
      files,
      isVideo: isVideo,
      onProgress: (index, fileName, currentProgress) {
        progressNotifier.value = {
          'index': index,
          'total': files.length,
          'fileName': fileName,
          'currentProgress': currentProgress,
        };
      },
    );

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // Close dialog

    final successCount = results['success'] ?? 0;
    final failCount = results['failed'] ?? 0;
    
    UiUtils.showSnackBar(
      context,
      'Selesai! $successCount berhasil, $failCount gagal.',
      isError: failCount > 0,
    );
  }

  Future<void> _startTranscribe() async {
    if (_selectedFiles.isEmpty) {
      UiUtils.showSnackBar(context, 'Pilih minimal satu file audio dulu');
      return;
    }
    await context.read<TranscribeProvider>().startTranscription(
      files: _selectedFiles,
      language: _language,
      doTranslate: _doTranslate,
      targetLang: _targetLang,
    );

    if (!mounted) return;
    final prov = context.read<TranscribeProvider>();
    if (prov.errorMessage != null && !prov.transcribing) {
      UiUtils.showSnackBar(context, prov.errorMessage!, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = Responsive.isWide(context);
    final prov = context.watch<TranscribeProvider>();
    final sortProv = context.watch<SortProvider>();

    if (_progressAnimation == null || !_progressAnimController.isAnimating) {
      if (_displayProgress != prov.progress) {
        _animateProgressTo(prov.progress);
      }
    }

    return SafeArea(
      child: isWide ? _buildDesktopLayout(prov, sortProv) : _buildMobileLayout(prov, sortProv),
    );
  }

  Widget _buildDesktopLayout(TranscribeProvider prov, SortProvider sortProv) {
    return Padding(
      padding: const EdgeInsets.all(AppConstants.paddingExtraLarge),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(sortProv),
                const SizedBox(height: AppConstants.paddingMedium),
                _buildBreadcrumb(prov),
                const SizedBox(height: AppConstants.paddingMedium),
                Expanded(
                  child: TranscribeAudioGrid(
                    searchQuery: _searchQuery,
                    gridScrollController: _gridScrollController,
                    selectedFiles: _selectedFiles,
                    onToggleSelection: _toggleFileSelection,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppConstants.paddingExtraLarge),
          SizedBox(
            width: 350,
            child: _buildSidebar(isMobile: false),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(TranscribeProvider prov, SortProvider sortProv) {
    return RefreshIndicator(
      onRefresh: () => context.read<TranscribeProvider>().loadAudioFiles(),
      child: AppScrollbar(
        controller: _mobileScrollController,
        child: CustomScrollView(
          controller: _mobileScrollController,
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: _buildSidebar(isMobile: true),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildHeader(sortProv, isMobile: true),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildBreadcrumb(prov),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            SliverFillRemaining(
              hasScrollBody: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TranscribeAudioGrid(
                  searchQuery: _searchQuery,
                  gridScrollController: _gridScrollController,
                  selectedFiles: _selectedFiles,
                  onToggleSelection: _toggleFileSelection,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar({required bool isMobile}) {
    return TranscribeSidebar(
      isMobile: isMobile,
      selectedFiles: _selectedFiles,
      language: _language,
      doTranslate: _doTranslate,
      targetLang: _targetLang,
      displayProgress: _displayProgress,
      listController: _sidebarListController,
      onLanguageChanged: (val) => setState(() => _language = val),
      onTranslateChanged: (val) => setState(() => _doTranslate = val),
      onTargetLangChanged: (val) => setState(() => _targetLang = val),
      onClearSelection: () => setState(() => _selectedFiles.clear()),
      onRemoveFile: (path) => setState(() => _selectedFiles.remove(path)),
      onStartTranscribe: _startTranscribe,
      onUploadFile: _showUploadSourceDialog,
      onShowCreateFolder: () => _showCreateFolderDialog(context.read<TranscribeProvider>()),
      onShowMoveDialog: () => _showMoveDialog(context.read<TranscribeProvider>()),
      onShowFileInfo: _showFileInfo,
    );
  }

  void _toggleFileSelection(String filePath) {
    setState(() {
      if (_selectedFiles.contains(filePath)) {
        _selectedFiles.remove(filePath);
      } else {
        _selectedFiles.add(filePath);
      }
    });
  }

  Widget _buildHeader(SortProvider sortProv, {bool isMobile = false}) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'File Audio Server',
          style: TextStyle(
            fontSize: isMobile ? 20 : 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        SizedBox(
          width: isMobile ? double.infinity : 300,
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Cari file...',
              hintStyle: const TextStyle(color: AppTheme.textSecondary),
              prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
              filled: true,
              fillColor: AppTheme.cardDark,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.dividerColor),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SortMenu(
              sortBy: sortProv.sortBy,
              sortAscending: sortProv.sortAscending,
              onSortByChanged: (value) => sortProv.setSortBy(value),
              onSortOrderChanged: (value) => sortProv.setSortOrder(value),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh, color: AppTheme.accentBlue),
              onPressed: () {
                if (mounted) {
                  context.read<TranscribeProvider>().loadAudioFiles();
                }
              },
              tooltip: 'Refresh',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBreadcrumb(TranscribeProvider prov) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
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
                  Icon(Icons.arrow_back_rounded, size: 18, color: AppTheme.accentBlue),
                  SizedBox(width: 4),
                  Text('Kembali', style: TextStyle(fontSize: 13, color: AppTheme.accentBlue)),
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
                color: prov.currentPath.isNotEmpty ? AppTheme.accentBlue : AppTheme.textPrimary,
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

  void _showCreateFolderDialog(TranscribeProvider prov) {
    final tc = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        title: const Text('Buat Playlist Baru', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: tc,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Nama Playlist', hintStyle: TextStyle(color: AppTheme.textSecondary)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          TextButton(
            onPressed: () async {
              if (tc.text.isNotEmpty) {
                Navigator.pop(context);
                await prov.createPlaylist(tc.text);
              }
            },
            child: const Text('Buat'),
          ),
        ],
      ),
    );
  }

  void _showFileInfo(Map<String, dynamic> file) {
    final name = file['name'] ?? 'Unknown';
    final size = UiUtils.formatSize(file['size'] ?? 0);
    final modified = file['modified'] ?? '-';
    final path = file['path'] ?? '-';
    final format = name.split('.').last.toUpperCase();

    String durationStr = '-';
    final rawDuration = file['duration'];
    if (rawDuration != null) {
      final double dur = (rawDuration is num) ? rawDuration.toDouble() : 0;
      durationStr = '${UiUtils.formatDuration(dur)} ($dur detik)';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: AppTheme.accentCyan),
            SizedBox(width: 10),
            Text('Detail File', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Nama File', name),
            _buildInfoRow('Durasi', durationStr),
            _buildInfoRow('Ukuran', size),
            _buildInfoRow('Format', format),
            _buildInfoRow('Terakhir Diubah', modified),
            _buildInfoRow('Path di Server', path),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 13)),
        ],
      ),
    );
  }

  String _formatRelativePath(String currentPath, String targetPath, String targetName) {
    String normCurrent = currentPath.replaceAll('\\', '/');
    String normTarget = targetPath.replaceAll('\\', '/');
    
    if (normCurrent.isEmpty) {
      if (normTarget.isEmpty) return 'root';
      return '/$targetName';
    }
    
    List<String> currentParts = normCurrent.split('/');
    List<String> targetParts = normTarget.isEmpty ? [] : normTarget.split('/');
    
    if (normTarget.isEmpty) return '${List.filled(currentParts.length, '..../').join('')}root';
    
    int common = 0;
    while (common < currentParts.length && common < targetParts.length && currentParts[common] == targetParts[common]) {
      common++;
    }
    
    int levelsUp = currentParts.length - common;
    if (levelsUp == 0) return '/$targetName';
    
    return '${List.filled(levelsUp, '..../').join('')}$targetName';
  }

  void _showMoveDialog(TranscribeProvider prov) {
    showDialog(
      context: context,
      builder: (context) {
        String? selectedPath;
        
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.cardDark,
              title: const Text('Pindah ke Playlist', style: TextStyle(color: Colors.white)),
              content: SizedBox(
                width: double.maxFinite,
                child: FutureBuilder<Map<String, dynamic>>(
                  future: ApiService.listAudio(path: ''),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
                    }
                    
                    final rootFolders = (snapshot.data?['folders'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                    final Map<String, String> allDestinations = {};
                    
                    if (prov.currentPath.isNotEmpty) allDestinations[''] = 'root';
                    for (String p in prov.pathHistory) {
                       if (p.isNotEmpty) allDestinations[p] = p.split('/').last;
                    }
                    for (var f in rootFolders) {
                       allDestinations[f['path'] as String] = f['name'] as String;
                    }
                    for (var f in prov.folders) {
                       allDestinations[f['path'] as String] = f['name'] as String;
                    }
                    allDestinations.remove(prov.currentPath);

                    return ListView(
                      shrinkWrap: true,
                      children: allDestinations.entries.map((e) {
                        final path = e.key;
                        final name = e.value;
                        final displayTitle = _formatRelativePath(prov.currentPath, path, name);
                        final isRoot = path.isEmpty;
                        final isSelected = selectedPath == path;
                        
                        return ListTile(
                          leading: Icon(isRoot ? Icons.home : Icons.folder, color: isRoot ? AppTheme.accentCyan : AppTheme.browserColor),
                          title: Text(displayTitle, style: TextStyle(color: isSelected ? AppTheme.accentBlue : Colors.white, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
                          selected: isSelected,
                          selectedTileColor: AppTheme.accentBlue.withOpacity(0.1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          onTap: () => setDialogState(() => selectedPath = path),
                        );
                      }).toList(),
                    );
                  }
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal', style: TextStyle(color: Colors.white70))),
                ElevatedButton(
                  onPressed: selectedPath == null ? null : () {
                    Navigator.pop(context);
                    prov.moveFilesTo(_selectedFiles, selectedPath!).then((_) => setState(() => _selectedFiles.clear()));
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentBlue),
                  child: const Text('Pindah', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          }
        );
      },
    );
  }
}
