import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

import '../providers/transcribe_provider.dart';
import '../config/theme.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/sort_menu.dart';
import '../providers/sort_provider.dart';
import '../services/api_service.dart';
import '../widgets/app_scrollbar.dart';

class TranscribeScreen extends StatefulWidget {
  const TranscribeScreen({super.key});

  @override
  State<TranscribeScreen> createState() => _TranscribeScreenState();
}

class _TranscribeScreenState extends State<TranscribeScreen>
    with SingleTickerProviderStateMixin {
  // Local state for forms
  final List<String> _selectedFiles = [];
  String _language = 'auto';
  bool _doTranslate = false;
  String _targetLang = 'id';
  final TextEditingController _searchController = TextEditingController();

  // Animation
  late AnimationController _progressAnimController;
  Animation<double>? _progressAnimation;
  double _displayProgress = 0;
  final ScrollController _sidebarListController = ScrollController();
  final ScrollController _gridScrollController = ScrollController();
  final ScrollController _mobileScrollController = ScrollController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _progressAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _progressAnimController.addListener(() {
      setState(() {
        _displayProgress = _progressAnimation?.value ??
            context.read<TranscribeProvider>().progress;
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<TranscribeProvider>().loadAudioFiles();
      }
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

  Future<void> _uploadFile({bool isVideo = false}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions:
          isVideo ? ['mp4', 'mkv', 'avi', 'mov'] : ['mp3', 'wav', 'm4a', 'ogg'],
    );
    if (result != null && result.files.single.path != null) {
      if (!mounted) return;
      final file = File(result.files.single.path!);
      final prov = context.read<TranscribeProvider>();
      final success = await prov.uploadAudioFile(file, isVideo: isVideo);

      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(isVideo
                  ? 'Video berhasil diupload & convert'
                  : 'Audio berhasil diupload')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(prov.errorMessage ?? 'Gagal upload')),
        );
      }
    }
  }

  Future<void> _startTranscribe() async {
    if (_selectedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih minimal satu file audio dulu')),
      );
      return;
    }
    await context.read<TranscribeProvider>().startTranscribe(
          files: _selectedFiles,
          language: _language,
          doTranslate: _doTranslate,
          targetLang: _targetLang,
        );

    if (!mounted) return;
    final prov = context.read<TranscribeProvider>();
    if (prov.errorMessage != null && !prov.transcribing) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(prov.errorMessage!),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final isWide = Responsive.isWide(context);
    final prov = context.watch<TranscribeProvider>();
    final sortProv = context.watch<SortProvider>();

    // Sync animation
    if (_progressAnimation == null || !_progressAnimController.isAnimating) {
      if (_displayProgress != prov.progress) {
        _animateProgressTo(prov.progress);
      }
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: SafeArea(
        child: isWide
            ? _buildDesktopLayout(prov, sortProv)
            : _buildMobileLayout(prov, sortProv),
      ),
    );
  }

  Widget _buildStatusPanel(TranscribeProvider prov) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: prov.outputFile != null
            ? AppTheme.success.withOpacity(0.1)
            : AppTheme.accentBlue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              prov.outputFile != null ? AppTheme.success : AppTheme.accentBlue,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                prov.outputFile != null ? Icons.check_circle : Icons.sync,
                color: prov.outputFile != null
                    ? AppTheme.success
                    : AppTheme.accentBlue,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  prov.status,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (prov.transcribing) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _displayProgress / 100,
                minHeight: 8,
                backgroundColor: AppTheme.dividerColor,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppTheme.accentBlue),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_displayProgress.toStringAsFixed(1)}%',
              textAlign: TextAlign.right,
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            TextButton.icon(
              onPressed: () {
                if (mounted) {
                  context.read<TranscribeProvider>().cancelTranscribe();
                }
              },
              icon: const Icon(Icons.cancel, color: AppTheme.error),
              label: const Text('Batalkan',
                  style: TextStyle(color: AppTheme.error)),
            ),
          ],
          if (prov.outputFile != null) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.edit_document),
              label: const Text('Buka Editor'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (mounted) {
                  context.go('/editor?file=${prov.outputFile}');
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDesktopLayout(TranscribeProvider prov, SortProvider sortProv) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(sortProv),
                const SizedBox(height: 16),
                _buildBreadcrumb(prov),
                const SizedBox(height: 16),
                Expanded(child: AppScrollbar(controller: _gridScrollController, child: _buildAudioContent(prov, sortProv))),
              ],
            ),
          ),
          const SizedBox(width: 32),
          SizedBox(
            width: 350,
            child: _buildSidebar(prov, isMobile: false),
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
                child: _buildSidebar(prov, isMobile: true),
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
          _buildAudioSliverContent(prov, sortProv),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
      ),
    ),
  );
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
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Cari file...',
              hintStyle: const TextStyle(color: AppTheme.textSecondary),
              prefixIcon:
                  const Icon(Icons.search, color: AppTheme.textSecondary),
              filled: true,
              fillColor: AppTheme.cardDark,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.dividerColor),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

  Widget _buildSidebar(TranscribeProvider prov, {required bool isMobile}) {
    // Get details of selected files
    final selectedDetails = prov.audioFiles.where((f) {
      final path = f['path'] as String? ?? f['name'] as String;
      return _selectedFiles.contains(path);
    }).toList();

    return Card(
      color: AppTheme.cardDark,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.dividerColor, width: 1),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Upload File',
              style: TextStyle(
                fontSize: isMobile ? 16 : 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            _buildUploadButton(
              icon: Icons.create_new_folder,
              label: 'Buat Playlist',
              onPressed: prov.transcribing ? null : () => _showCreateFolderDialog(prov),
            ),
            const SizedBox(height: 12),
            _buildUploadButton(
              icon: Icons.audio_file,
              label: 'Upload Audio',
              onPressed:
                  prov.transcribing ? null : () => _uploadFile(isVideo: false),
            ),
            const SizedBox(height: 12),
            _buildUploadButton(
              icon: Icons.video_file,
              label: isMobile ? 'Upload Video' : 'Upload Video (ke MP3)',
              onPressed:
                  prov.transcribing ? null : () => _uploadFile(isVideo: true),
            ),

            // DYNAMIC SELECTED FILES LIST
            if (selectedDetails.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Divider(color: AppTheme.dividerColor),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.playlist_add_check_rounded,
                      color: AppTheme.accentCyan, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '${selectedDetails.length} File Dipilih',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (_selectedFiles.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.drive_file_move, color: AppTheme.accentBlue),
                      tooltip: 'Pindah ke Playlist',
                      onPressed: () => _showMoveDialog(prov),
                    ),
                  TextButton(
                    onPressed: () => setState(() => _selectedFiles.clear()),
                    child: const Text('Clear', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: AppScrollbar(
                  controller: _sidebarListController,
                  child: ListView.separated(
                    controller: _sidebarListController,
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    itemCount: selectedDetails.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final f = selectedDetails[index];
                    final name = f['name'] ?? 'Unknown';
                    final size = _formatSize(f['size'] ?? 0);
                    final path = f['path'] as String? ?? f['name'] as String;

                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundDark.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppTheme.accentBlue.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.description_rounded,
                              size: 16, color: AppTheme.textMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  size,
                                  style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                          // INFO BUTTON
                          IconButton(
                            onPressed: () => _showFileInfo(f),
                            icon: const Icon(Icons.info_outline_rounded,
                                size: 16, color: AppTheme.accentCyan),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Informasi Lengkap',
                          ),
                          const SizedBox(width: 8),
                          // DELETE/REMOVE BUTTON
                          IconButton(
                            onPressed: () =>
                                setState(() => _selectedFiles.remove(path)),
                            icon: const Icon(Icons.close_rounded,
                                size: 16, color: AppTheme.error),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Hapus dari daftar',
                          ),
                        ],
                      ),
                    );
                  },
                  ),
                ),
              ),
            ],

            const Divider(height: 48, color: AppTheme.dividerColor),
            Text(
              'Pengaturan',
              style: TextStyle(
                fontSize: isMobile ? 16 : 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            _buildDropdown(
              label: 'Bahasa Audio',
              value: _language,
              items: const [
                DropdownMenuItem(value: 'auto', child: Text('Auto Detect')),
                DropdownMenuItem(value: 'id', child: Text('Indonesia')),
                DropdownMenuItem(value: 'en', child: Text('English (Inggris)')),
                DropdownMenuItem(value: 'ja', child: Text('Japanese (Jepang)')),
                DropdownMenuItem(value: 'ko', child: Text('Korean (Korea)')),
              ],
              onChanged: prov.transcribing
                  ? null
                  : (v) => setState(() => _language = v!),
            ),
            CheckboxListTile(
              title: const Text('Terjemahkan hasil?',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              value: _doTranslate,
              onChanged: prov.transcribing
                  ? null
                  : (v) => setState(() => _doTranslate = v ?? false),
              activeColor: AppTheme.accentBlue,
              checkColor: Colors.white,
              contentPadding: EdgeInsets.zero,
            ),
            if (_doTranslate) ...[
              const SizedBox(height: 8),
              _buildDropdown(
                label: 'Target Bahasa',
                value: _targetLang,
                items: const [
                  DropdownMenuItem(value: 'id', child: Text('Indonesia')),
                  DropdownMenuItem(
                      value: 'en', child: Text('English (Inggris)')),
                  DropdownMenuItem(
                      value: 'ja', child: Text('Japanese (Jepang)')),
                  DropdownMenuItem(value: 'ko', child: Text('Korean (Korea)')),
                ],
                onChanged: prov.transcribing
                    ? null
                    : (v) => setState(() => _targetLang = v!),
              ),
            ],
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: prov.transcribing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.play_arrow),
              label: Text(prov.transcribing
                  ? 'Sedang Memproses...'
                  : 'Mulai Transcribe'),
              style: ElevatedButton.styleFrom(
                backgroundColor: prov.transcribing
                    ? AppTheme.dividerColor
                    : AppTheme.accentBlue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: isMobile ? 16 : 20),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: prov.transcribing ? null : _startTranscribe,
            ),
            if (prov.transcribing || prov.outputFile != null) ...[
              const SizedBox(height: 24),
              _buildStatusPanel(prov),
            ],
          ],
        ),
      ),
    );
  }

  void _showFileInfo(Map<String, dynamic> file) {
    final name = file['name'] ?? 'Unknown';
    final size = _formatSize(file['size'] ?? 0);
    final modified = file['modified'] ?? '-';
    final path = file['path'] ?? '-';
    final format = name.split('.').last.toUpperCase();

    // DURATION FORMATTING
    String durationStr = '-';
    final rawDuration = file['duration'];
    if (rawDuration != null) {
      final double dur = (rawDuration is num) ? rawDuration.toDouble() : 0;
      final int minutes = dur ~/ 60;
      final int seconds = (dur % 60).toInt();
      durationStr =
          '$minutes:${seconds.toString().padLeft(2, '0')} ($dur detik)';
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
            Text('Detail File'),
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
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildUploadButton(
      {required IconData icon,
      required String label,
      VoidCallback? onPressed}) {
    return ElevatedButton.icon(
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.accentBlue.withOpacity(0.1),
        foregroundColor: Colors.white,
        side: const BorderSide(color: AppTheme.accentBlue, width: 1),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onPressed,
    );
  }

  Widget _buildDropdown(
      {required String label,
      required String value,
      required List<DropdownMenuItem<String>> items,
      ValueChanged<String?>? onChanged}) {
    return DropdownButtonFormField<String>(
      value: value,
      dropdownColor: AppTheme.cardDark,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _buildAudioContent(TranscribeProvider prov, SortProvider sortProv) {
    if (prov.isLoading) return const Center(child: CircularProgressIndicator());
    if (prov.audioFiles.isEmpty) return _buildEmptyState();

    return _buildAudioGrid(prov, sortProv);
  }

  Widget _buildAudioSliverContent(
      TranscribeProvider prov, SortProvider sortProv) {
    if (prov.isLoading) {
      return const SliverFillRemaining(
          child: Center(child: CircularProgressIndicator()));
    }
    if (prov.audioFiles.isEmpty) {
      return SliverFillRemaining(child: _buildEmptyState());
    }

    final filteredFiles = _getFilteredFiles(prov, sortProv);
    if (filteredFiles.isEmpty) {
      return const SliverFillRemaining(
          child: Center(
              child: Text('Tidak ada file yang cocok.',
                  style: TextStyle(color: AppTheme.textSecondary))));
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index < prov.folders.length) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildFolderItem(prov.folders[index], prov),
              );
            } else {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildFileItem(filteredFiles[index - prov.folders.length], index, prov),
              );
            }
          },
          childCount: prov.folders.length + filteredFiles.length,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _getFilteredFiles(
      TranscribeProvider prov, SortProvider sortProv) {
    var filteredFiles = prov.audioFiles.where((file) {
      final name = (file['name'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
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
    return filteredFiles;
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32.0),
        child: Text(
          'Belum ada file audio di server.\nUpload file baru untuk mulai.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      ),
    );
  }

  Widget _buildAudioGrid(TranscribeProvider prov, SortProvider sortProv) {
    var filteredFiles = prov.audioFiles.where((file) {
      final name = (file['name'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
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

    if (filteredFiles.isEmpty) {
      return const Center(
        child: Text(
          'Tidak ada file yang cocok dengan pencarian.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }

    return AppScrollbar(
      controller: _gridScrollController,
      child: GridView.builder(
        controller: _gridScrollController,
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
        return _buildFileItem(file, index, prov);
      },
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

  Widget _buildFileItem(
      Map<String, dynamic> file, int index, TranscribeProvider prov) {
    final filePath = file['path'] as String? ?? file['name'] as String;
    final isSelected = _selectedFiles.contains(filePath);
    final sizeStr = _formatSize(file['size'] ?? 0);

    return InkWell(
      onTap: prov.transcribing
          ? null
          : () {
              setState(() {
                if (isSelected) {
                  _selectedFiles.remove(filePath);
                } else {
                  _selectedFiles.add(filePath);
                }
              });
            },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accentBlue.withOpacity(0.1)
              : AppTheme.cardDark,
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
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sizeStr,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
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

  String _formatRelativePath(String currentPath, String targetPath, String targetName) {
    // Normalize paths to use forward slashes (fix for Windows backslash paths)
    String normCurrent = currentPath.replaceAll('\\', '/');
    String normTarget = targetPath.replaceAll('\\', '/');
    
    if (normCurrent.isEmpty) {
      if (normTarget.isEmpty) return 'root';
      return '/$targetName';
    }
    
    List<String> currentParts = normCurrent.split('/');
    List<String> targetParts = normTarget.isEmpty ? [] : normTarget.split('/');
    
    if (normTarget.isEmpty) {
      return '${List.filled(currentParts.length, '..../').join('')}root';
    }
    
    int common = 0;
    while (common < currentParts.length && common < targetParts.length && currentParts[common] == targetParts[common]) {
      common++;
    }
    
    int levelsUp = currentParts.length - common;
    if (levelsUp == 0) {
      return '/$targetName';
    } else {
      String dots = List.filled(levelsUp, '..../').join('');
      return '$dots$targetName';
    }
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
                    
                    if (prov.currentPath.isNotEmpty) {
                       allDestinations[''] = 'root';
                    }
                    
                    for (String p in prov.pathHistory) {
                       if (p.isNotEmpty) {
                          allDestinations[p] = p.split('/').last;
                       }
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
                          onTap: () {
                             setDialogState(() {
                               selectedPath = path;
                             });
                          },
                        );
                      }).toList(),
                    );
                  }
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context), 
                  child: const Text('Batal', style: TextStyle(color: Colors.white70))
                ),
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
