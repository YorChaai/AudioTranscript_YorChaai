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
  bool _isSelectionMode = false;
  final Set<String> _selectedFiles = {};
  final Set<String> _selectedFolders = {};
  final Map<String, Map<String, dynamic>> _selectedFileMetadata = {};
  final Map<String, Map<String, dynamic>> _selectedFolderMetadata = {};
  String _language = 'auto';
  bool _doTranslate = false;
  String _targetLang = 'id';
  int _beamSize = 2;
  
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
      if (mounted) {
        setState(() {
          _displayProgress = _progressAnimation?.value ?? context.read<TranscribeProvider>().progress;
        });
      }
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(isVideo ? Icons.video_library_rounded : Icons.audio_file_rounded, color: AppTheme.accentCyan, size: 22),
            const SizedBox(width: 10),
            Text(isVideo ? 'Upload Video ke MP3' : 'Upload Audio', style: const TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pilih metode pemilihan file yang ingin diunggah:',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              tileColor: AppTheme.backgroundDark,
              leading: const Icon(Icons.file_copy_rounded, color: AppTheme.accentCyan),
              title: const Text('1. Pilih Banyak File', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('Pilih satu atau banyak file terpisah dari file explorer', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                _pickFiles(isVideo, mode: 1);
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              tileColor: AppTheme.backgroundDark,
              leading: const Icon(Icons.folder_rounded, color: AppTheme.browserColor),
              title: const Text('2. Pilih Folder (Hanya 1 Level)', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('Membaca semua file audio langsung di dalam folder yang dipilih', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                _pickFiles(isVideo, mode: 2);
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              tileColor: AppTheme.backgroundDark,
              leading: const Icon(Icons.folder_special_rounded, color: AppTheme.accentBlue),
              title: const Text('3. Pilih Folder & Seluruh Subfoldernya', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('Membaca semua subfolder secara rekursif & menjaga struktur folder asli', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                _pickFiles(isVideo, mode: 3);
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              tileColor: AppTheme.backgroundDark,
              leading: const Icon(Icons.computer_rounded, color: AppTheme.accentCyan),
              title: const Text('4. 📂 Input Path Folder Server (Direct / Tanpa Upload)', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('Langsung memproses folder di PC server tanpa upload Wi-Fi (Persis Opsi 4 run.bat)', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                _openCustomFolderChooser(context.read<TranscribeProvider>());
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFiles(bool isVideo, {required int mode}) async {
    List<UploadMediaTask> selectedTasks = [];
    int skippedDuplicates = 0;

    const audioExts = ['.mp3', '.wav', '.m4a', '.flac', '.ogg', '.wma', '.aac'];
    const videoExts = ['.mp4', '.mov', '.mkv', '.avi', '.webm', '.mpeg', '.mpg', '.m4v'];

    try {
      final List<File> discoveredFiles = [];
      String? folderRootName;
      String? folderRootPath;

      if (mode == 1) {
        // Mode 1: Pick multiple individual files (Audio or Video)
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: isVideo
              ? ['mp4', 'mov', 'mkv', 'avi', 'webm', 'mpeg', 'mpg', 'm4v', 'mp3', 'wav', 'm4a', 'flac', 'ogg', 'wma', 'aac']
              : ['mp3', 'wav', 'm4a', 'flac', 'ogg', 'wma', 'aac', 'mp4', 'mov', 'mkv', 'avi', 'webm', 'mpeg', 'mpg', 'm4v'],
          allowMultiple: true,
        );
        if (result == null || result.files.isEmpty) return;

        for (final f in result.files) {
          if (f.path != null) discoveredFiles.add(File(f.path!));
        }
      } else if (mode == 2) {
        // Mode 2: Pick Single Folder (Non-recursive)
        String? directoryPath = await FilePicker.getDirectoryPath();
        if (directoryPath == null) return;

        final dir = Directory(directoryPath);
        folderRootName = dir.path.split(Platform.pathSeparator).last;
        folderRootPath = dir.path;
        final List<FileSystemEntity> entities = await dir.list(recursive: false).toList();

        for (var entity in entities) {
          if (entity is File) discoveredFiles.add(entity);
        }
      } else if (mode == 3) {
        // Mode 3: Pick Folder & All Subfolders (Recursive)
        String? directoryPath = await FilePicker.getDirectoryPath();
        if (directoryPath == null) return;

        final rootDir = Directory(directoryPath);
        folderRootName = rootDir.path.split(Platform.pathSeparator).last;
        folderRootPath = rootDir.path;
        final List<FileSystemEntity> entities = await rootDir.list(recursive: true).toList();

        for (var entity in entities) {
          if (entity is File) discoveredFiles.add(entity);
        }
      }

      // Smart Categorization & Deduplication:
      // If a folder has both Chapter1.mp3 and Chapter1.mp4, keep Chapter1.mp3 and skip Chapter1.mp4.
      final Map<String, UploadMediaTask> audioTasksMap = {};
      final Map<String, UploadMediaTask> videoTasksMap = {};

      for (final file in discoveredFiles) {
        final pathLower = file.path.toLowerCase();
        final isAudio = audioExts.any((ext) => pathLower.endsWith(ext));
        final isVid = videoExts.any((ext) => pathLower.endsWith(ext));

        if (!isAudio && !isVid) continue;

        String relativeSubfolder = '';
        String displayName = file.path.split(Platform.pathSeparator).last;

        if (folderRootPath != null && folderRootName != null) {
          if (mode == 2) {
            relativeSubfolder = folderRootName;
            displayName = '$folderRootName / $displayName';
          } else if (mode == 3) {
            final relPath = file.path.substring(folderRootPath.length).replaceAll('\\', '/');
            final trimmedRel = relPath.startsWith('/') ? relPath.substring(1) : relPath;
            final parts = trimmedRel.split('/');
            relativeSubfolder = parts.length > 1
                ? '$folderRootName/${parts.sublist(0, parts.length - 1).join('/')}'
                : folderRootName;
            displayName = '$folderRootName / $trimmedRel';
          }
        }

        final fileNameWithoutExt = file.path.split(Platform.pathSeparator).last.split('.').first.toLowerCase().trim();
        final dedupKey = '$relativeSubfolder/$fileNameWithoutExt';
        final fileSize = file.existsSync() ? file.lengthSync() : 0;

        if (isAudio) {
          audioTasksMap[dedupKey] = UploadMediaTask(
            file: file,
            relativeSubfolder: relativeSubfolder,
            displayName: displayName,
            size: fileSize,
            isVideo: false,
          );
        } else if (isVid) {
          videoTasksMap[dedupKey] = UploadMediaTask(
            file: file,
            relativeSubfolder: relativeSubfolder,
            displayName: displayName,
            size: fileSize,
            isVideo: true,
          );
        }
      }

      // Add all direct audio files
      selectedTasks.addAll(audioTasksMap.values);

      // Add video files ONLY if no audio file with the same name exists
      for (final entry in videoTasksMap.entries) {
        if (audioTasksMap.containsKey(entry.key)) {
          skippedDuplicates++;
        } else {
          selectedTasks.add(entry.value);
        }
      }
    } catch (e) {
      if (mounted) UiUtils.showSnackBar(context, 'Gagal membaca file/folder: $e', isError: true);
      return;
    }

    if (selectedTasks.isEmpty) {
      if (mounted) UiUtils.showSnackBar(context, 'Tidak ada file audio/video yang didukung ditemukan');
      return;
    }

    if (!mounted) return;
    _showUploadConfirmationDialog(selectedTasks, skippedDuplicates);
  }

  void _showUploadConfirmationDialog(List<UploadMediaTask> tasks, int skippedDuplicates) {
    List<UploadMediaTask> selectedForUpload = List.from(tasks);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final audioCount = selectedForUpload.where((t) => !t.isVideo).length;
            final videoCount = selectedForUpload.where((t) => t.isVideo).length;

            return AlertDialog(
              backgroundColor: AppTheme.cardDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.cloud_upload_rounded, color: AppTheme.accentCyan),
                  const SizedBox(width: 10),
                  Text(
                    'Konfirmasi Upload (${tasks.length} File)',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SizedBox(
                width: 650,
                height: 440,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundDark,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Terpilih: $audioCount Audio Langsung, $videoCount Video Ekstrak',
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  setStateDialog(() {
                                    if (selectedForUpload.length == tasks.length) {
                                      selectedForUpload.clear();
                                    } else {
                                      selectedForUpload = List.from(tasks);
                                    }
                                  });
                                },
                                child: Text(
                                  selectedForUpload.length == tasks.length ? 'Deselect All' : 'Select All',
                                  style: const TextStyle(color: AppTheme.accentCyan),
                                ),
                              ),
                            ],
                          ),
                          if (skippedDuplicates > 0) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.accentBlue.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppTheme.accentBlue.withOpacity(0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle_outline, color: AppTheme.accentCyan, size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    '⚡ $skippedDuplicates video duplikat dilewati (file audio MP3 sudah tersedia)',
                                    style: const TextStyle(color: AppTheme.accentCyan, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        itemCount: tasks.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 48),
                        itemBuilder: (context, index) {
                          final task = tasks[index];
                          final isSelected = selectedForUpload.contains(task);
                          
                          return CheckboxListTile(
                            dense: true,
                            secondary: Icon(
                              task.isVideo ? Icons.video_file_rounded : Icons.audio_file_rounded,
                              color: task.isVideo ? Colors.amber : AppTheme.accentCyan,
                              size: 24,
                            ),
                            title: Text(
                              task.displayName,
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: task.isVideo ? Colors.amber.withOpacity(0.15) : AppTheme.accentCyan.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    task.isVideo ? 'Ekstrak MP3' : 'Audio Langsung',
                                    style: TextStyle(
                                      color: task.isVideo ? Colors.amberAccent : AppTheme.accentCyan,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Folder: ${task.relativeSubfolder.isEmpty ? "Root" : task.relativeSubfolder} · ${UiUtils.formatSize(task.size)}',
                                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            value: isSelected,
                            activeColor: AppTheme.accentBlue,
                            checkColor: Colors.white,
                            side: const BorderSide(color: AppTheme.textSecondary),
                            onChanged: (val) {
                              setStateDialog(() {
                                if (val == true) {
                                  selectedForUpload.add(task);
                                } else {
                                  selectedForUpload.remove(task);
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
                  child: const Text('Batal', style: TextStyle(color: AppTheme.textMuted)),
                ),
                ElevatedButton(
                  onPressed: selectedForUpload.isEmpty ? null : () {
                    Navigator.pop(context);
                    _processMultipleUploads(selectedForUpload);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentBlue,
                    foregroundColor: Colors.white,
                  ),
                  child: Text('Proses ${selectedForUpload.length} File (Paralel)'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _processMultipleUploads(List<UploadMediaTask> tasks) async {
    final prov = context.read<TranscribeProvider>();
    
    final progressNotifier = ValueNotifier<Map<String, dynamic>>({
      'completed': 0,
      'total': tasks.length,
      'currentFile': tasks.first.displayName,
      'overallProgress': 0.0,
    });

    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: progressNotifier,
          builder: (context, progress, child) {
            final double overall = progress['overallProgress'] ?? 0.0;
            final int completed = progress['completed'] ?? 0;
            final int total = progress['total'] ?? tasks.length;
            final String fileName = progress['currentFile'] ?? '';

            return AlertDialog(
              backgroundColor: AppTheme.cardDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppTheme.dividerColor),
              ),
              title: const Row(
                children: [
                  Icon(Icons.bolt_rounded, color: AppTheme.accentCyan, size: 24),
                  SizedBox(width: 10),
                  Text(
                    'Memproses Upload Paralel...',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Selesai $completed dari $total file (3 Worker Paralel)',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    // Fixed-size container for current file so dialog never jumps/resizes
                    Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundDark.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.dividerColor.withOpacity(0.5)),
                      ),
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          const Icon(Icons.audio_file_outlined, color: AppTheme.accentBlue, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              fileName.isEmpty ? 'Mempersiapkan berkas...' : fileName,
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, height: 1.3),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: overall > 0.0 ? overall : null,
                        minHeight: 8,
                        backgroundColor: AppTheme.dividerColor,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accentBlue),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(overall * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(color: AppTheme.accentCyan, fontSize: 12, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.right,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    final results = await prov.uploadMediaBatch(
      tasks,
      maxConcurrent: 3,
      onProgress: (completed, total, currentFile, overallProgress) {
        progressNotifier.value = {
          'completed': completed,
          'total': total,
          'currentFile': currentFile,
          'overallProgress': overallProgress,
        };
      },
    );

    if (dialogContext != null && dialogContext!.mounted) {
      Navigator.pop(dialogContext!); // Close dialog securely
    }

    final successCount = results['success'] ?? 0;
    final failCount = results['failed'] ?? 0;
    
    if (!mounted) return;
    UiUtils.showSnackBar(
      context,
      'Upload selesai! $successCount file berhasil, $failCount gagal.',
      isError: failCount > 0,
    );
  }

  Future<void> _startTranscribe() async {
    if (_selectedFiles.isEmpty && _selectedFolders.isEmpty) {
      UiUtils.showSnackBar(context, 'Pilih minimal satu file atau folder audio terlebih dahulu');
      return;
    }
    await _showTranscribeWizardDialog();
  }

  Future<void> _executeTranscribe() async {
    await context.read<TranscribeProvider>().startTranscription(
      files: _selectedFiles.toList(),
      folderPaths: _selectedFolders.toList(),
      language: _language,
      doTranslate: _doTranslate,
      targetLang: _targetLang,
      beamSize: _beamSize,
    );

    if (!mounted) return;
    final prov = context.read<TranscribeProvider>();
    if (prov.errorMessage != null && !prov.transcribing) {
      UiUtils.showSnackBar(context, prov.errorMessage!, isError: true);
    }
  }

  Future<void> _showTranscribeWizardDialog() async {
    String tempLanguage = _language;
    bool tempTranslate = _doTranslate;
    String tempTargetLang = _targetLang;
    int tempBeamSize = _beamSize;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setWizardState) {
            final totalFiles = _selectedFiles.length;
            final totalFolders = _selectedFolders.length;

            return AlertDialog(
              backgroundColor: AppTheme.cardDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.transcribeColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: AppTheme.transcribeColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Text('Konfirmasi & Mulai Transkripsi', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.backgroundDark,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.dividerColor),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.playlist_play_rounded, color: AppTheme.accentCyan, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Akan memproses $totalFiles file ${totalFolders > 0 ? "dan $totalFolders folder" : ""}',
                                style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('1. Bahasa Asli Audio:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.backgroundDark,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.dividerColor),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: tempLanguage,
                            isExpanded: true,
                            dropdownColor: AppTheme.cardDark,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            items: const [
                              DropdownMenuItem(value: 'auto', child: Text('🌐 Auto-Detect (Otomatis)')),
                              DropdownMenuItem(value: 'id', child: Text('🇮🇩 Bahasa Indonesia (id)')),
                              DropdownMenuItem(value: 'en', child: Text('🇬🇧 English (en)')),
                              DropdownMenuItem(value: 'ja', child: Text('🇯🇵 Japanese (ja)')),
                              DropdownMenuItem(value: 'zh', child: Text('🇨🇳 Chinese (zh)')),
                              DropdownMenuItem(value: 'de', child: Text('🇩🇪 German (de)')),
                              DropdownMenuItem(value: 'es', child: Text('🇪🇸 Spanish (es)')),
                              DropdownMenuItem(value: 'fr', child: Text('🇫🇷 French (fr)')),
                              DropdownMenuItem(value: 'ko', child: Text('🇰🇷 Korean (ko)')),
                              DropdownMenuItem(value: 'ar', child: Text('🇸🇦 Arabic (ar)')),
                            ],
                            onChanged: (val) {
                              if (val != null) setWizardState(() => tempLanguage = val);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('2. Terjemahkan Hasil Transkripsi?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                          Switch(
                            value: tempTranslate,
                            activeColor: AppTheme.accentCyan,
                            onChanged: (val) => setWizardState(() => tempTranslate = val),
                          ),
                        ],
                      ),
                      if (tempTranslate) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.backgroundDark,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.dividerColor),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: tempTargetLang,
                              isExpanded: true,
                              dropdownColor: AppTheme.cardDark,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              items: const [
                                DropdownMenuItem(value: 'id', child: Text('🇮🇩 Bahasa Indonesia (id)')),
                                DropdownMenuItem(value: 'en', child: Text('🇬🇧 English (en)')),
                                DropdownMenuItem(value: 'ja', child: Text('🇯🇵 Japanese (ja)')),
                                DropdownMenuItem(value: 'zh-CN', child: Text('🇨🇳 Chinese (zh-CN)')),
                                DropdownMenuItem(value: 'de', child: Text('🇩🇪 German (de)')),
                                DropdownMenuItem(value: 'ko', child: Text('🇰🇷 Korean (ko)')),
                                DropdownMenuItem(value: 'ar', child: Text('🇸🇦 Arabic (ar)')),
                              ],
                              onChanged: (val) {
                                if (val != null) setWizardState(() => tempTargetLang = val);
                              },
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Text('3. Kualitas & Akurasi (Beam Size):', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Cepat (1)'),
                              selected: tempBeamSize == 1,
                              selectedColor: AppTheme.transcribeColor,
                              backgroundColor: AppTheme.backgroundDark,
                              labelStyle: TextStyle(color: tempBeamSize == 1 ? Colors.white : AppTheme.textMuted, fontSize: 12),
                              onSelected: (s) => setWizardState(() => tempBeamSize = 1),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Standar (2)'),
                              selected: tempBeamSize == 2,
                              selectedColor: AppTheme.transcribeColor,
                              backgroundColor: AppTheme.backgroundDark,
                              labelStyle: TextStyle(color: tempBeamSize == 2 ? Colors.white : AppTheme.textMuted, fontSize: 12),
                              onSelected: (s) => setWizardState(() => tempBeamSize = 2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Akurat (5)'),
                              selected: tempBeamSize == 5,
                              selectedColor: AppTheme.transcribeColor,
                              backgroundColor: AppTheme.backgroundDark,
                              labelStyle: TextStyle(color: tempBeamSize == 5 ? Colors.white : AppTheme.textMuted, fontSize: 12),
                              onSelected: (s) => setWizardState(() => tempBeamSize = 5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Batal', style: TextStyle(color: AppTheme.textMuted)),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('Mulai Transkripsi 🚀', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.transcribeColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    setState(() {
                      _language = tempLanguage;
                      _doTranslate = tempTranslate;
                      _targetLang = tempTargetLang;
                      _beamSize = tempBeamSize;
                    });
                    Navigator.pop(ctx, true);
                  },
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      await _executeTranscribe();
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
                const SizedBox(height: 8),
                _buildSelectionBar(prov),
                Expanded(
                  child: TranscribeAudioGrid(
                    searchQuery: _searchQuery,
                    gridScrollController: _gridScrollController,
                    isSelectionMode: _isSelectionMode,
                    selectedFiles: _selectedFiles,
                    selectedFolders: _selectedFolders,
                    onToggleFileSelection: _toggleFileSelection,
                    onToggleFolderSelection: _toggleFolderSelection,
                    onFolderNavigate: _onFolderNavigate,
                    onFileLongPress: _onFileLongPress,
                    onFolderLongPress: _onFolderLongPress,
                    onRenameFile: (path, name) => _showRenameDialog(currentPath: path, currentName: name, isFolder: false),
                    onDeleteFile: (path, name) => _confirmDeleteSingle(path: path, name: name, isFolder: false),
                    onRenameFolder: (path, name) => _showRenameDialog(currentPath: path, currentName: name, isFolder: true),
                    onDeleteFolder: (path, name) => _confirmDeleteSingle(path: path, name: name, isFolder: true),
                    onOpenCustomFolder: () => _openCustomFolderChooser(prov),
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
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildSelectionBar(prov),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverFillRemaining(
              hasScrollBody: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TranscribeAudioGrid(
                  searchQuery: _searchQuery,
                  gridScrollController: _gridScrollController,
                  isSelectionMode: _isSelectionMode,
                  selectedFiles: _selectedFiles,
                  selectedFolders: _selectedFolders,
                  onToggleFileSelection: _toggleFileSelection,
                  onToggleFolderSelection: _toggleFolderSelection,
                  onFolderNavigate: _onFolderNavigate,
                  onFileLongPress: _onFileLongPress,
                  onFolderLongPress: _onFolderLongPress,
                  onRenameFile: (path, name) => _showRenameDialog(currentPath: path, currentName: name, isFolder: false),
                  onDeleteFile: (path, name) => _confirmDeleteSingle(path: path, name: name, isFolder: false),
                  onRenameFolder: (path, name) => _showRenameDialog(currentPath: path, currentName: name, isFolder: true),
                  onDeleteFolder: (path, name) => _confirmDeleteSingle(path: path, name: name, isFolder: true),
                  onOpenCustomFolder: () => _openCustomFolderChooser(prov),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteSingle({required String path, required String name, required bool isFolder}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppTheme.error, size: 26),
            const SizedBox(width: 10),
            Text(
              isFolder ? 'Hapus Folder?' : 'Hapus File Audio?',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Apakah Anda yakin ingin menghapus ${isFolder ? "folder" : "file"} "$name"${isFolder ? " beserta seluruh isinya" : ""} secara permanen dari server?',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.error.withOpacity(0.35)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.error_outline_rounded, color: AppTheme.error, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Peringatan: Tindakan ini tidak dapat dibatalkan.',
                        style: TextStyle(color: AppTheme.error, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: const Text('Hapus Permanen'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirmed == true) {
      final prov = context.read<TranscribeProvider>();
      final res = await prov.deleteMedia(
        files: isFolder ? [] : [path],
        folders: isFolder ? [path] : [],
      );

      if (!mounted) return;
      if (res['status'] == 'ok') {
        setState(() {
          _selectedFiles.remove(path);
          _selectedFolders.remove(path);
          if (_selectedFiles.isEmpty && _selectedFolders.isEmpty) _isSelectionMode = false;
        });
        UiUtils.showSnackBar(context, 'Berhasil menghapus "$name".');
      } else {
        UiUtils.showSnackBar(context, 'Gagal menghapus: ${res['error'] ?? "Terjadi kesalahan"}', isError: true);
      }
    }
  }

  void _showRangeSelectionDialog(TranscribeProvider prov) {
    final allFiles = prov.displayFiles;
    if (allFiles.isEmpty) {
      UiUtils.showSnackBar(context, 'Tidak ada file audio dalam daftar saat ini');
      return;
    }

    final controller = TextEditingController();
    bool isExcludeMode = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppTheme.cardDark,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(
                  isExcludeMode ? Icons.remove_circle_outline_rounded : Icons.filter_list_rounded,
                  color: isExcludeMode ? AppTheme.error : AppTheme.accentCyan,
                ),
                const SizedBox(width: 10),
                Text(
                  isExcludeMode ? '🚫 Mode Pengecualian' : '🔢 Pilih Rentang File',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tersedia ${allFiles.length} file (No. 1 - ${allFiles.length}):',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('✅ Pilih File'),
                          selected: !isExcludeMode,
                          selectedColor: AppTheme.accentBlue,
                          backgroundColor: AppTheme.backgroundDark,
                          labelStyle: TextStyle(color: !isExcludeMode ? Colors.white : AppTheme.textMuted, fontSize: 12),
                          onSelected: (s) => setDialogState(() => isExcludeMode = false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('🚫 Lewati (Exclude)'),
                          selected: isExcludeMode,
                          selectedColor: AppTheme.error,
                          backgroundColor: AppTheme.backgroundDark,
                          labelStyle: TextStyle(color: isExcludeMode ? Colors.white : AppTheme.textMuted, fontSize: 12),
                          onSelected: (s) => setDialogState(() => isExcludeMode = true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: isExcludeMode ? 'Nomor file yang di-skip' : 'Nomor / Rentang file',
                      hintText: 'Contoh: 1-5, 8, 10-12 atau all',
                      hintStyle: const TextStyle(color: AppTheme.textMuted),
                      labelStyle: const TextStyle(color: AppTheme.accentCyan),
                      filled: true,
                      fillColor: AppTheme.backgroundDark,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '💡 Persis seperti run.bat: ketik rentang (2-6), pisah koma (1,3,5), atau "all".',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal', style: TextStyle(color: AppTheme.textMuted)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isExcludeMode ? AppTheme.error : AppTheme.accentCyan,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  final text = controller.text.trim();
                  if (text.isEmpty) return;

                  try {
                    final indices = _parseSelectionNumbers(text, allFiles.length);
                    setState(() {
                      _isSelectionMode = true;
                      if (isExcludeMode) {
                        _selectedFiles.clear();
                        for (int i = 0; i < allFiles.length; i++) {
                          final oneBased = i + 1;
                          if (!indices.contains(oneBased)) {
                            final path = allFiles[i]['path'] as String? ?? allFiles[i]['name'] as String;
                            _selectedFiles.add(path);
                          }
                        }
                      } else {
                        for (final num in indices) {
                          final idx = num - 1;
                          if (idx >= 0 && idx < allFiles.length) {
                            final path = allFiles[idx]['path'] as String? ?? allFiles[idx]['name'] as String;
                            _selectedFiles.add(path);
                          }
                        }
                      }
                      if (_selectedFiles.isEmpty && _selectedFolders.isEmpty) {
                        _isSelectionMode = false;
                      }
                    });
                    Navigator.pop(ctx);
                    UiUtils.showSnackBar(
                      context,
                      isExcludeMode
                          ? 'Dikecualikan ${indices.length} file. Total terpilih: ${_selectedFiles.length} file.'
                          : 'Berhasil memilih ${_selectedFiles.length} file.',
                    );
                  } catch (e) {
                    UiUtils.showSnackBar(context, 'Input tidak valid: $e', isError: true);
                  }
                },
                child: Text(isExcludeMode ? 'Terapkan Exclude' : 'Pilih File'),
              ),
            ],
          );
        },
      ),
    );
  }

  Set<int> _parseSelectionNumbers(String text, int maxNumber) {
    final cleaned = text.trim().toLowerCase();
    if (cleaned == 'all') {
      return List.generate(maxNumber, (i) => i + 1).toSet();
    }

    final Set<int> result = {};
    for (var chunk in cleaned.split(',')) {
      chunk = chunk.trim();
      if (chunk.isEmpty) continue;
      if (chunk.contains('-')) {
        final parts = chunk.split('-');
        if (parts.length != 2) throw Exception('Format rentang salah: $chunk');
        int start = int.parse(parts[0].trim());
        int end = int.parse(parts[1].trim());
        if (start > end) {
          final t = start;
          start = end;
          end = t;
        }
        for (int v = start; v <= end; v++) {
          if (v >= 1 && v <= maxNumber) {
            result.add(v);
          }
        }
      } else {
        final val = int.parse(chunk);
        if (val >= 1 && val <= maxNumber) {
          result.add(val);
        }
      }
    }
    return result;
  }

  Future<void> _openCustomFolderChooser(TranscribeProvider prov) async {
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final controller = TextEditingController(text: prov.customServerFolder ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.cardDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.folder_open_rounded, color: AppTheme.accentCyan, size: 22),
              const SizedBox(width: 10),
              Text(
                isDesktop ? 'Pilih / Buka Folder PC' : 'Buka Folder Server',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDesktop
                      ? 'Pilih folder di PC Anda. Aplikasi akan membaca file & subfolder secara bertingkat langsung tanpa upload.'
                      : 'Masukkan path folder di server PC Anda (Opsi 4 run.bat). Server akan langsung membaca file tanpa upload Wi-Fi.',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 16),
                if (isDesktop) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.folder_shared_rounded, color: Colors.white),
                      label: const Text('Jelajahi Lewat File Explorer...', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        final selectedDir = await FilePicker.getDirectoryPath();
                        if (selectedDir != null && selectedDir.isNotEmpty) {
                          controller.text = selectedDir;
                          setDialogState(() {});
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Row(
                    children: [
                      Expanded(child: Divider(color: AppTheme.dividerColor)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('atau ketik path manual', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                      ),
                      Expanded(child: Divider(color: AppTheme.dividerColor)),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: controller,
                  autofocus: !isDesktop,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Path Folder PC / Server',
                    hintText: isDesktop ? r'Contoh: D:\Kuliah\Rekaman atau C:\Users\...' : r'Contoh: D:\Audio atau /home/user/audio',
                    hintStyle: const TextStyle(color: AppTheme.textMuted),
                    labelStyle: const TextStyle(color: AppTheme.accentCyan),
                    filled: true,
                    fillColor: AppTheme.backgroundDark,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '💡 File langsung akan muncul, dan subfolder dapat diklik untuk masuk ke dalamnya secara bertingkat.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal', style: TextStyle(color: AppTheme.textMuted)),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.check_circle_rounded, size: 18),
              label: const Text('Buka Folder'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentCyan,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final path = controller.text.trim();
                if (path.isEmpty) return;
                Navigator.pop(ctx);

                final success = await prov.scanCustomFolder(path);
                if (!mounted) return;
                if (success) {
                  _clearSelection();
                  UiUtils.showSnackBar(
                    this.context,
                    '✅ Membuka ${prov.customServerFolder}: ${prov.customServerFiles.length} file & ${prov.customServerFolders.length} subfolder',
                  );
                } else {
                  UiUtils.showSnackBar(
                    this.context,
                    prov.errorMessage ?? 'Gagal membuka folder di server',
                    isError: true,
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSystemHealthDialog() async {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return FutureBuilder<Map<String, dynamic>>(
          future: ApiService.systemHealthDetails(),
          builder: (context, snapshot) {
            return AlertDialog(
              backgroundColor: AppTheme.cardDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.monitor_heart_rounded, color: AppTheme.transcribeColor, size: 24),
                  SizedBox(width: 10),
                  Text('Kesehatan Sistem & GPU', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator(color: AppTheme.transcribeColor)),
                      )
                    : snapshot.hasError
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('❌ Gagal memeriksa: ${snapshot.error}', style: const TextStyle(color: AppTheme.error)),
                          )
                        : _buildHealthDetails(snapshot.data ?? {}),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Tutup', style: TextStyle(color: AppTheme.accentCyan)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildHealthDetails(Map<String, dynamic> data) {
    final cuda = data['cuda_available'] == true;
    final gpuName = data['gpu_name'] ?? 'CPU';
    final vramTotal = data['vram_total_gb'] ?? 0.0;
    final vramFree = data['vram_free_gb'] ?? 0.0;
    final whisperExists = data['whisper_model_exists'] == true;
    final whisperPath = data['whisper_model_path'] ?? '-';
    final ffmpegOk = data['ffmpeg_ok'] == true;
    final pyVer = data['python_version'] ?? '-';

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHealthTile(
            icon: Icons.memory_rounded,
            title: 'GPU Akselerasi (CUDA)',
            subtitle: cuda ? '$gpuName\nVRAM Bebas: $vramFree GB / Total: $vramTotal GB' : 'CPU Mode (Tanpa Akselerasi CUDA)',
            isOk: cuda,
          ),
          const SizedBox(height: 8),
          _buildHealthTile(
            icon: Icons.psychology_rounded,
            title: 'Model Whisper (Offline)',
            subtitle: whisperExists ? 'Tersedia: $whisperPath' : 'Model belum diunduh / Tidak ditemukan',
            isOk: whisperExists,
          ),
          const SizedBox(height: 8),
          _buildHealthTile(
            icon: Icons.movie_creation_rounded,
            title: 'FFmpeg Audio Converter',
            subtitle: ffmpegOk ? 'Siap digunakan' : 'FFmpeg tidak ditemukan di server',
            isOk: ffmpegOk,
          ),
          const SizedBox(height: 8),
          _buildHealthTile(
            icon: Icons.terminal_rounded,
            title: 'Python Server',
            subtitle: 'Python $pyVer | Server Port 5000',
            isOk: true,
          ),
        ],
      ),
    );
  }

  Widget _buildHealthTile({required IconData icon, required String title, required String subtitle, required bool isOk}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isOk ? Colors.green.withOpacity(0.3) : AppTheme.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: isOk ? Colors.greenAccent : AppTheme.error, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          Icon(isOk ? Icons.check_circle_rounded : Icons.cancel_rounded, color: isOk ? Colors.greenAccent : AppTheme.error, size: 18),
        ],
      ),
    );
  }

  Widget _buildSidebar({required bool isMobile}) {
    final selectedFileList = _selectedFiles.map((p) {
      return _selectedFileMetadata[p] ?? {
        'name': p.split(RegExp(r'[\\/]')).last,
        'path': p,
      };
    }).toList();

    final selectedFolderList = _selectedFolders.map((p) {
      return _selectedFolderMetadata[p] ?? {
        'name': p.split(RegExp(r'[\\/]')).last,
        'path': p,
      };
    }).toList();

    return TranscribeSidebar(
      isMobile: isMobile,
      selectedFiles: _selectedFiles.toList(),
      selectedFolders: _selectedFolders.toList(),
      selectedFileDetails: selectedFileList,
      selectedFolderDetails: selectedFolderList,
      language: _language,
      doTranslate: _doTranslate,
      targetLang: _targetLang,
      beamSize: _beamSize,
      displayProgress: _displayProgress,
      listController: _sidebarListController,
      onLanguageChanged: (val) => setState(() => _language = val),
      onTranslateChanged: (val) => setState(() => _doTranslate = val),
      onTargetLangChanged: (val) => setState(() => _targetLang = val),
      onBeamSizeChanged: (val) => setState(() => _beamSize = val),
      onClearSelection: _clearSelection,
      onRemoveFile: (path) => setState(() {
        _selectedFiles.remove(path);
        _selectedFileMetadata.remove(path);
        if (_selectedFiles.isEmpty && _selectedFolders.isEmpty) _isSelectionMode = false;
      }),
      onRemoveFolder: (path) => setState(() {
        _selectedFolders.remove(path);
        _selectedFolderMetadata.remove(path);
        if (_selectedFiles.isEmpty && _selectedFolders.isEmpty) _isSelectionMode = false;
      }),
      onStartTranscribe: _startTranscribe,
      onUploadFile: _showUploadSourceDialog,
      onShowCreateFolder: () => _showCreateFolderDialog(context.read<TranscribeProvider>()),
      onShowMoveDialog: () => _showMoveDialog(context.read<TranscribeProvider>()),
      onShowFileInfo: _showFileInfo,
      onOpenCustomFolder: () => _openCustomFolderChooser(context.read<TranscribeProvider>()),
    );
  }

  void _toggleFileSelection(String filePath) {
    setState(() {
      if (_selectedFiles.contains(filePath)) {
        _selectedFiles.remove(filePath);
        _selectedFileMetadata.remove(filePath);
      } else {
        _selectedFiles.add(filePath);
        final prov = context.read<TranscribeProvider>();
        final f = prov.displayFiles.firstWhere(
          (item) => (item['path'] as String? ?? item['name'] as String) == filePath,
          orElse: () => {'name': filePath.split(RegExp(r'[\\/]')).last, 'path': filePath},
        );
        _selectedFileMetadata[filePath] = Map<String, dynamic>.from(f);
        _isSelectionMode = true;
      }
      if (_selectedFiles.isEmpty && _selectedFolders.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  void _toggleFolderSelection(String folderPath) {
    setState(() {
      if (_selectedFolders.contains(folderPath)) {
        _selectedFolders.remove(folderPath);
        _selectedFolderMetadata.remove(folderPath);
      } else {
        _selectedFolders.add(folderPath);
        final prov = context.read<TranscribeProvider>();
        final f = prov.displayFolders.firstWhere(
          (item) => (item['path'] as String? ?? item['name'] as String) == folderPath,
          orElse: () => {'name': folderPath.split(RegExp(r'[\\/]')).last, 'path': folderPath},
        );
        _selectedFolderMetadata[folderPath] = Map<String, dynamic>.from(f);
        _isSelectionMode = true;
      }
      if (_selectedFiles.isEmpty && _selectedFolders.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  void _onFileLongPress(String filePath) {
    _toggleFileSelection(filePath);
  }

  void _onFolderLongPress(String folderPath) {
    _toggleFolderSelection(folderPath);
  }

  void _onFolderNavigate(String folderPath) {
    final prov = context.read<TranscribeProvider>();
    if (prov.isCustomMode) {
      prov.navigateCustomFolder(folderPath);
    } else {
      prov.navigateTo(folderPath);
    }
  }

  void _selectAll(TranscribeProvider prov) {
    setState(() {
      _isSelectionMode = true;
      for (final f in prov.displayFiles) {
        final path = f['path'] as String? ?? f['name'] as String;
        _selectedFiles.add(path);
        _selectedFileMetadata[path] = Map<String, dynamic>.from(f);
      }
      for (final fld in prov.displayFolders) {
        final path = fld['path'] as String? ?? fld['name'] as String;
        _selectedFolders.add(path);
        _selectedFolderMetadata[path] = Map<String, dynamic>.from(fld);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedFiles.clear();
      _selectedFolders.clear();
      _selectedFileMetadata.clear();
      _selectedFolderMetadata.clear();
      _isSelectionMode = false;
    });
  }

  Future<void> _showRenameDialog({
    required String currentPath,
    required String currentName,
    required bool isFolder,
  }) async {
    final textCtrl = TextEditingController(text: currentName);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(isFolder ? Icons.folder_open_rounded : Icons.edit_note_rounded, color: AppTheme.accentCyan, size: 22),
            const SizedBox(width: 10),
            Text(
              isFolder ? 'Ubah Nama Folder' : 'Ubah Nama File',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Masukkan nama baru untuk ${isFolder ? "folder" : "file"}:',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textCtrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Nama baru...',
                hintStyle: const TextStyle(color: AppTheme.textSecondary),
                filled: true,
                fillColor: AppTheme.backgroundDark,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onSubmitted: (val) {
                final trimmed = val.trim();
                if (trimmed.isNotEmpty) Navigator.pop(ctx, trimmed);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Batal', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              final trimmed = textCtrl.text.trim();
              if (trimmed.isNotEmpty) Navigator.pop(ctx, trimmed);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Simpan Perubahan'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (newName != null && newName.isNotEmpty && newName != currentName) {
      final prov = context.read<TranscribeProvider>();
      final success = await prov.renameMedia(currentPath, newName);
      if (!mounted) return;
      if (success) {
        _clearSelection();
        UiUtils.showSnackBar(context, 'Nama berhasil diubah menjadi "$newName"');
      } else {
        UiUtils.showSnackBar(context, prov.errorMessage ?? 'Gagal mengubah nama', isError: true);
      }
    }
  }

  Future<void> _confirmDeleteSelected(TranscribeProvider prov) async {
    final fileCount = _selectedFiles.length;
    final folderCount = _selectedFolders.length;
    if (fileCount == 0 && folderCount == 0) return;

    final String itemDescription = (fileCount > 0 && folderCount > 0)
        ? '$fileCount file audio dan $folderCount folder'
        : (folderCount > 0
            ? '$folderCount folder beserta seluruh isinya'
            : '$fileCount file audio');

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.error, size: 28),
            SizedBox(width: 10),
            Text('Hapus Item Terpilih?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Apakah Anda yakin ingin menghapus $itemDescription ini secara permanen dari server?',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.error.withOpacity(0.35)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.error_outline_rounded, color: AppTheme.error, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Peringatan: File yang dihapus tidak dapat dipulihkan kembali.',
                        style: TextStyle(color: AppTheme.error, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: const Text('Hapus Permanen'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final filesToDelete = _selectedFiles.toList();
      final foldersToDelete = _selectedFolders.toList();

      final res = await prov.deleteMedia(
        files: filesToDelete,
        folders: foldersToDelete,
      );

      if (!mounted) return;
      _clearSelection();

      if (res['status'] == 'ok') {
        final totalDel = (res['deleted_files'] as List? ?? []).length + (res['deleted_folders'] as List? ?? []).length;
        UiUtils.showSnackBar(context, 'Berhasil menghapus $totalDel item dari server.');
      } else {
        UiUtils.showSnackBar(context, 'Gagal menghapus: ${res['error'] ?? "Terjadi kesalahan"}', isError: true);
      }
    }
  }

  Widget _buildSelectionBar(TranscribeProvider prov) {
    if (!_isSelectionMode && _selectedFiles.isEmpty && _selectedFolders.isEmpty) {
      return const SizedBox.shrink();
    }

    final totalSelected = _selectedFiles.length + _selectedFolders.length;
    final canRename = totalSelected == 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.accentBlue.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.accentBlue.withOpacity(0.35)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline_rounded, color: AppTheme.accentCyan, size: 18),
            const SizedBox(width: 8),
            Text(
              '$totalSelected item dipilih',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
            ),
            const SizedBox(width: 10),
            if (canRename) ...[
              Tooltip(
                message: 'Ubah Nama',
                child: InkWell(
                  onTap: () {
                    if (_selectedFolders.isNotEmpty) {
                      final fldPath = _selectedFolders.first;
                      final fld = prov.folders.firstWhere(
                        (f) => (f['path'] as String? ?? f['name'] as String) == fldPath,
                        orElse: () => {'name': fldPath.replaceAll('\\', '/').split('/').last, 'path': fldPath},
                      );
                      _showRenameDialog(currentPath: fldPath, currentName: fld['name'] ?? '', isFolder: true);
                    } else if (_selectedFiles.isNotEmpty) {
                      final fPath = _selectedFiles.first;
                      final file = prov.audioFiles.firstWhere(
                        (f) => (f['path'] as String? ?? f['name'] as String) == fPath,
                        orElse: () => {'name': fPath.replaceAll('\\', '/').split('/').last, 'path': fPath},
                      );
                      _showRenameDialog(currentPath: fPath, currentName: file['name'] ?? '', isFolder: false);
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.accentCyan.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.accentCyan.withOpacity(0.5)),
                    ),
                    child: const Icon(Icons.edit_rounded, size: 15, color: AppTheme.accentCyan),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (totalSelected > 0) ...[
              Tooltip(
                message: 'Hapus Permanen ($totalSelected)',
                child: InkWell(
                  onTap: () => _confirmDeleteSelected(prov),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.error.withOpacity(0.6)),
                    ),
                    child: const Icon(Icons.delete_forever_rounded, size: 15, color: AppTheme.error),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            TextButton(
              onPressed: () => _selectAll(prov),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Pilih Semua', style: TextStyle(color: AppTheme.accentCyan, fontSize: 12)),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              icon: const Icon(Icons.tune_rounded, size: 14, color: AppTheme.accentCyan),
              label: const Text('Rentang / Exclude', style: TextStyle(color: AppTheme.accentCyan, fontSize: 12)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => _showRangeSelectionDialog(prov),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: _clearSelection,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Batal', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(SortProvider sortProv, {bool isMobile = false}) {
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'File Audio Server',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              SortMenu(
                sortBy: sortProv.sortBy,
                sortAscending: sortProv.sortAscending,
                onSortByChanged: (value) => sortProv.setSortBy(value),
                onSortOrderChanged: (value) => sortProv.setSortOrder(value),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.tune_rounded, color: AppTheme.accentCyan, size: 20),
                onPressed: () => _showRangeSelectionDialog(context.read<TranscribeProvider>()),
                tooltip: 'Pilih Rentang / Exclude (1-5, all, dll)',
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.monitor_heart_rounded, color: AppTheme.transcribeColor, size: 20),
                onPressed: _showSystemHealthDialog,
                tooltip: 'Kesehatan Sistem & GPU',
              ),
              const SizedBox(width: 4),
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
          const SizedBox(height: 12),
          TextField(
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
        ],
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          'File Audio Server',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        SizedBox(
          width: 300,
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
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.tune_rounded, color: AppTheme.accentCyan, size: 20),
              onPressed: () => _showRangeSelectionDialog(context.read<TranscribeProvider>()),
              tooltip: 'Pilih Rentang / Exclude (1-5, all, dll)',
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.monitor_heart_rounded, color: AppTheme.transcribeColor, size: 20),
              onPressed: _showSystemHealthDialog,
              tooltip: 'Kesehatan Sistem & GPU',
            ),
            const SizedBox(width: 4),
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
    if (prov.isCustomMode) {
      final baseFolder = prov.customServerFolder ?? '';
      final baseFolderName = baseFolder.split(RegExp(r'[\\/]')).lastWhere((s) => s.isNotEmpty, orElse: () => baseFolder);
      final subpath = prov.customServerSubpath;
      final subpathParts = subpath.isNotEmpty ? subpath.split('/') : <String>[];

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.accentCyan.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.accentCyan.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            if (prov.customPathHistory.isNotEmpty || subpath.isNotEmpty) ...[
              InkWell(
                onTap: () => prov.goBackCustomFolder(),
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_rounded, size: 16, color: AppTheme.accentCyan),
                      SizedBox(width: 4),
                      Text('Kembali', style: TextStyle(fontSize: 12, color: AppTheme.accentCyan, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(width: 1, height: 18, color: AppTheme.dividerColor),
              const SizedBox(width: 8),
            ],
            const Icon(Icons.computer_rounded, size: 17, color: AppTheme.accentCyan),
            const SizedBox(width: 8),
            InkWell(
              onTap: subpath.isNotEmpty ? () => prov.scanCustomFolder(baseFolder, subpath: '') : null,
              borderRadius: BorderRadius.circular(4),
              child: Text(
                baseFolderName.isEmpty ? 'Folder PC' : baseFolderName,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: subpath.isNotEmpty ? AppTheme.accentCyan : Colors.white,
                  decoration: subpath.isNotEmpty ? TextDecoration.underline : TextDecoration.none,
                ),
              ),
            ),
            if (subpathParts.isNotEmpty) ...[
              for (int i = 0; i < subpathParts.length; i++) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text('/', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                ),
                InkWell(
                  onTap: (i < subpathParts.length - 1)
                      ? () => prov.scanCustomFolder(baseFolder, subpath: subpathParts.sublist(0, i + 1).join('/'))
                      : null,
                  child: Text(
                    subpathParts[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: (i == subpathParts.length - 1) ? FontWeight.bold : FontWeight.w500,
                      color: (i == subpathParts.length - 1) ? Colors.white : AppTheme.accentCyan,
                      decoration: (i < subpathParts.length - 1) ? TextDecoration.underline : TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ],
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.folder_open_rounded, size: 15, color: AppTheme.accentCyan),
              label: const Text('Ganti Folder', style: TextStyle(fontSize: 12, color: AppTheme.accentCyan)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => _openCustomFolderChooser(prov),
            ),
            const SizedBox(width: 6),
            ElevatedButton.icon(
              icon: const Icon(Icons.close_rounded, size: 14),
              label: const Text('Tutup (Ke Root)', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error.withOpacity(0.2),
                foregroundColor: AppTheme.error,
                side: const BorderSide(color: AppTheme.error, width: 1),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                visualDensity: VisualDensity.compact,
                elevation: 0,
              ),
              onPressed: () {
                _clearSelection();
                prov.clearCustomMode();
              },
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          ] else
            const Spacer(),
          ElevatedButton.icon(
            icon: const Icon(Icons.folder_open_rounded, size: 15),
            label: const Text('Buka Folder PC', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentCyan.withOpacity(0.15),
              foregroundColor: AppTheme.accentCyan,
              side: const BorderSide(color: AppTheme.accentCyan, width: 1),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              visualDensity: VisualDensity.compact,
              elevation: 0,
            ),
            onPressed: () => _openCustomFolderChooser(prov),
          ),
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
                    prov.moveFilesTo(_selectedFiles.toList(), selectedPath!).then((_) => _clearSelection());
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
