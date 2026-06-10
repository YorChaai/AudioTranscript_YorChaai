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
  String _searchQuery = '';

  // Animation
  late AnimationController _progressAnimController;
  Animation<double>? _progressAnimation;
  double _displayProgress = 0;

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
      context.read<TranscribeProvider>().loadAudioFiles();
    });
  }

  @override
  void dispose() {
    _progressAnimController.dispose();
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

    return SafeArea(
      child: isWide
          ? _buildDesktopLayout(prov, sortProv)
          : _buildMobileLayout(prov, sortProv),
    );
  }

  Widget _buildDesktopLayout(TranscribeProvider prov, SortProvider sortProv) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: _buildMainContent(prov, sortProv),
          ),
          const SizedBox(width: 32),
          SizedBox(
            width: 350,
            child: _buildSidebar(prov),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(TranscribeProvider prov, SortProvider sortProv) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSidebar(prov),
          const SizedBox(height: 24),
          // Use a fixed height for the content area in mobile to avoid unbounded height
          SizedBox(
            height: 600, // Reasonable height for mobile audio list
            child: _buildMainContent(prov, sortProv),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(TranscribeProvider prov) {
    return Card(
      color: AppTheme.cardDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.dividerColor, width: 1),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Upload File',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.audio_file),
              label: const Text('Upload Audio'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed:
                  prov.transcribing ? null : () => _uploadFile(isVideo: false),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.video_file),
              label: const Text('Upload Video (ke MP3)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed:
                  prov.transcribing ? null : () => _uploadFile(isVideo: true),
            ),
            const Divider(height: 48, color: AppTheme.dividerColor),
            const Text('Pengaturan',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _language,
              dropdownColor: AppTheme.cardDark,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Bahasa Audio',
                labelStyle: const TextStyle(color: AppTheme.textSecondary),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
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
            const SizedBox(height: 16),
            CheckboxListTile(
              title: const Text('Terjemahkan hasil?',
                  style: TextStyle(color: Colors.white)),
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
              DropdownButtonFormField<String>(
                value: _targetLang,
                dropdownColor: AppTheme.cardDark,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Target Bahasa',
                  labelStyle: const TextStyle(color: AppTheme.textSecondary),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
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
                padding: const EdgeInsets.symmetric(vertical: 20),
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
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentBlue),
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
              onPressed: () =>
                  context.read<TranscribeProvider>().cancelTranscribe(),
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
              onPressed: () => context.go('/editor?file=${prov.outputFile}'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMainContent(TranscribeProvider prov, SortProvider sortProv) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'File Audio Server',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
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
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.dividerColor),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            SortMenu(
              sortBy: sortProv.sortBy,
              sortAscending: sortProv.sortAscending,
              onSortByChanged: (value) => sortProv.setSortBy(value),
              onSortOrderChanged: (value) => sortProv.setSortOrder(value),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh, color: AppTheme.accentBlue),
              onPressed: () =>
                  context.read<TranscribeProvider>().loadAudioFiles(),
              tooltip: 'Refresh',
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (prov.isLoading)
          const Center(child: CircularProgressIndicator())
        else if (prov.audioFiles.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Text(
                'Belum ada file audio di server.\\nUpload file baru untuk mulai.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          )
        else
          Expanded(child: _buildAudioGrid(prov, sortProv)),
      ],
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

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 2.5,
      ),
      itemCount: filteredFiles.length,
      itemBuilder: (context, index) {
        final file = filteredFiles[index];
        return _buildFileItem(file, index, prov);
      },
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
                children: [
                  Text(
                    file['name'] ?? 'Unknown',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sizeStr,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
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
