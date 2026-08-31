import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/job_status.dart';
import '../repositories/transcribe_repository.dart';

class UploadMediaTask {
  final File file;
  final String relativeSubfolder; // e.g. "Astronacci/02. Price Action"
  final String displayName;
  final int size;
  final bool isVideo;

  UploadMediaTask({
    required this.file,
    this.relativeSubfolder = '',
    String? displayName,
    int? size,
    this.isVideo = false,
  })  : displayName = displayName ?? file.path.split(Platform.pathSeparator).last,
        size = size ?? (file.existsSync() ? file.lengthSync() : 0);
}

/// Global State Management for Transcribe features using Provider
class TranscribeProvider extends ChangeNotifier {
  final TranscribeRepository _repository;

  TranscribeProvider({TranscribeRepository? repository}) 
      : _repository = repository ?? TranscribeRepository();

  List<Map<String, dynamic>> _audioFiles = [];
  List<Map<String, dynamic>> get audioFiles => _audioFiles;

  List<Map<String, dynamic>> _folders = [];
  List<Map<String, dynamic>> get folders => _folders;

  String _currentPath = '';
  String get currentPath => _currentPath;

  final List<String> _pathHistory = [];
  List<String> get pathHistory => _pathHistory;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // Transcribe Job State
  bool _transcribing = false;
  bool get transcribing => _transcribing;

  String? _jobId;
  String? get jobId => _jobId;

  double _progress = 0;
  double get progress => _progress;

  String _statusMessage = '';
  String get status => _statusMessage;

  String? _outputFile;
  String? get outputFile => _outputFile;

  DateTime? _batchStartTime;
  String _batchEta = '';
  String get batchEta => _batchEta;

  String _elapsedTime = '';
  String get elapsedTime => _elapsedTime;

  int _totalBatchFiles = 0;
  int get totalBatchFiles => _totalBatchFiles;

  int _currentFileIndex = 0;
  int get currentFileIndex => _currentFileIndex;

  StreamSubscription<Map<String, dynamic>>? _statusSubscription;

  Future<void> loadAudioFiles() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _repository.listAudio(path: _currentPath);
      _audioFiles = List<Map<String, dynamic>>.from(result['files'] ?? []);
      _folders = List<Map<String, dynamic>>.from(result['folders'] ?? []);
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> uploadMedia(File file, {bool isVideo = false}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (isVideo) {
        await _repository.uploadVideoAndConvert(file, path: _currentPath);
      } else {
        await _repository.uploadAudio(file, path: _currentPath);
      }
      await loadAudioFiles();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, int>> uploadMediaBatch(
    List<UploadMediaTask> tasks, {
    bool isVideo = false,
    int maxConcurrent = 3,
    void Function(int completed, int total, String currentFile, double overallProgress)? onProgress,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    if (tasks.isEmpty) {
      _isLoading = false;
      notifyListeners();
      return {'success': 0, 'failed': 0};
    }

    int successCount = 0;
    int failCount = 0;
    int completedCount = 0;
    final totalTasks = tasks.length;
    final progressMap = <int, double>{};

    void updateOverallProgress(String latestFileName) {
      double totalFraction = 0.0;
      for (int i = 0; i < totalTasks; i++) {
        totalFraction += progressMap[i] ?? 0.0;
      }
      final overallProgress = (totalFraction / totalTasks).clamp(0.0, 1.0);
      onProgress?.call(completedCount, totalTasks, latestFileName, overallProgress);
    }

    // Process tasks concurrently with safe worker limit (default: 3)
    final poolSize = maxConcurrent.clamp(1, 4);
    int nextTaskIndex = 0;

    Future<void> worker() async {
      while (true) {
        int index;
        UploadMediaTask task;
        if (nextTaskIndex >= totalTasks) break;
        index = nextTaskIndex++;
        task = tasks[index];

        progressMap[index] = 0.0;
        updateOverallProgress(task.displayName);

        try {
          void handleProgress(int bytes, int total) {
            if (total > 0) {
              progressMap[index] = (bytes / total).clamp(0.0, 0.99);
              updateOverallProgress(task.displayName);
            }
          }

          String targetPath = _currentPath;
          if (task.relativeSubfolder.isNotEmpty) {
            targetPath = _currentPath.isNotEmpty
                ? '$_currentPath/${task.relativeSubfolder}'
                : task.relativeSubfolder;
          }

          final shouldConvertVideo = task.isVideo || isVideo;
          if (shouldConvertVideo) {
            await _repository.uploadVideoAndConvert(task.file, path: targetPath, onProgress: handleProgress);
          } else {
            await _repository.uploadAudio(task.file, path: targetPath, onProgress: handleProgress);
          }

          successCount++;
          progressMap[index] = 1.0;
        } catch (e) {
          failCount++;
          progressMap[index] = 1.0;
        } finally {
          completedCount++;
          updateOverallProgress(task.displayName);
        }
      }
    }

    final workers = List.generate(poolSize, (_) => worker());
    await Future.wait(workers);

    await loadAudioFiles();
    return {'success': successCount, 'failed': failCount};
  }

  Future<void> startTranscription({
    required List<String> files,
    List<String>? folderPaths,
    required String language,
    required bool doTranslate,
    required String targetLang,
    int beamSize = 2,
  }) async {
    _transcribing = true;
    _progress = 0;
    final totalCount = files.length + (folderPaths?.length ?? 0);
    _statusMessage = 'Memulai batch ($totalCount item dipilih)...';
    _outputFile = null;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await _repository.startTranscribe(
        files: files,
        folderPaths: folderPaths,
        language: language,
        doTranslate: doTranslate,
        targetLang: targetLang,
        beamSize: beamSize,
      );

      final List<String> jobIds = (res['job_ids'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          (res['job_id'] != null ? [res['job_id'].toString()] : []);

      if (jobIds.isEmpty) {
        _errorJob('Tidak ada job yang dibuat.');
        notifyListeners();
        return;
      }

      _trackBatchJobs(jobIds, jobIds.length);
    } catch (e) {
      _errorJob('❌ Gagal memulai: $e');
      notifyListeners();
    }
  }

  void _trackBatchJobs(List<String> jobIds, int totalFiles) {
    int currentJobIndex = 0;
    _batchStartTime = DateTime.now();
    _totalBatchFiles = totalFiles;
    _currentFileIndex = 1;
    _batchEta = 'Menghitung estimasi...';
    _elapsedTime = '00:00';

    void monitorCurrentJob() {
      if (currentJobIndex >= jobIds.length) {
        _finishJob(_outputFile, '✅ Seluruh batch ($totalFiles file) selesai!');
        notifyListeners();
        return;
      }

      _jobId = jobIds[currentJobIndex];
      _statusSubscription?.cancel();
      _statusSubscription = _repository.streamJobStatus(_jobId!).listen((data) {
        final job = JobStatus.fromJson(data);
        final fileIndex = currentJobIndex + 1;
        _currentFileIndex = fileIndex;
        final baseProgress = (currentJobIndex / jobIds.length) * 100;
        final jobWeightedProgress = (job.progress / 100) * (100 / jobIds.length);
        _progress = (baseProgress + jobWeightedProgress).clamp(0.0, 100.0);
        
        _statusMessage = '[$fileIndex/$totalFiles] ${job.readableStatus}';
        if (job.outputFile != null) {
          _outputFile = job.outputFile;
        }

        // Calculate live ETA for entire batch
        if (_batchStartTime != null) {
          final elapsed = DateTime.now().difference(_batchStartTime!);
          final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
          final s = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
          _elapsedTime = elapsed.inHours > 0 ? '${elapsed.inHours}:$m:$s' : '$m:$s';

          if (_progress > 1.5) {
            final totalEstSeconds = (elapsed.inSeconds / (_progress / 100));
            final remSeconds = (totalEstSeconds - elapsed.inSeconds).clamp(0, 86400).toInt();
            if (remSeconds < 60) {
              _batchEta = '~$remSeconds detik';
            } else if (remSeconds < 3600) {
              final remM = remSeconds ~/ 60;
              final remS = remSeconds % 60;
              _batchEta = '~$remM menit ${remS > 0 ? "$remS detik" : ""}';
            } else {
              final remH = remSeconds ~/ 3600;
              final remM = (remSeconds % 3600) ~/ 60;
              _batchEta = '~$remH jam $remM menit';
            }
          }
        }

        if (job.status == 'completed') {
          currentJobIndex++;
          monitorCurrentJob();
        } else if (job.status == 'failed' || job.status == 'error') {
          _errorMessage = 'File $fileIndex error: ${job.error ?? "Gagal"}';
          currentJobIndex++;
          monitorCurrentJob();
        } else if (job.status == 'cancelled') {
          _errorJob('🛑 Dibatalkan');
        }
        notifyListeners();
      }, onError: (e) {
        _errorJob('❌ Gagal menyambung stream: $e');
        notifyListeners();
      });
    }

    monitorCurrentJob();
  }

  void _finishJob(String? out, String msg) {
    _statusSubscription?.cancel();
    _transcribing = false;
    _progress = 100;
    _outputFile = out;
    _statusMessage = msg;
  }

  void _errorJob(String err) {
    _statusSubscription?.cancel();
    _transcribing = false;
    _errorMessage = err;
    _statusMessage = '❌ Gagal';
  }

  Future<void> cancelTranscription() async {
    _statusSubscription?.cancel();
    _transcribing = false;
    _progress = 0;
    _statusMessage = '🛑 Transkripsi dibatalkan';
    _batchEta = '';
    notifyListeners();

    if (_jobId != null) {
      try {
        await _repository.cancelTranscribe(_jobId!);
      } catch (e) {
        // Silent catch as UI state is already cleanly reset
      }
    }
  }

  // ===== NAVIGATION =====

  void navigateTo(String path) {
    _pathHistory.add(_currentPath);
    _currentPath = path;
    loadAudioFiles();
  }

  void goBack() {
    if (_pathHistory.isNotEmpty) {
      _currentPath = _pathHistory.removeLast();
      loadAudioFiles();
    }
  }

  void goToRoot() {
    _pathHistory.clear();
    _currentPath = '';
    loadAudioFiles();
  }

  // ===== FOLDERS / PLAYLISTS =====

  Future<bool> createPlaylist(String name) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _repository.createFolder(name, path: _currentPath);
      await loadAudioFiles();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> moveFilesTo(List<String> filePaths, String targetPath) async {
    _isLoading = true;
    notifyListeners();
    try {
      final res = await _repository.moveFiles(filePaths, targetPath);
      
      if (res['errors'] != null && (res['errors'] as List).isNotEmpty) {
         throw Exception("Gagal memindahkan file: ${(res['errors'] as List).join(', ')}");
      }
      
      await loadAudioFiles();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> renameMedia(String path, String newName) async {
    _isLoading = true;
    notifyListeners();
    try {
      final res = await _repository.renameMedia(path, newName);
      if (res['status'] == 'ok') {
        await loadAudioFiles();
        return true;
      }
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>> deleteMedia({List<String>? files, List<String>? folders}) async {
    _isLoading = true;
    notifyListeners();
    try {
      final res = await _repository.deleteMedia(files: files, folders: folders);
      await loadAudioFiles();
      return res;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return {'status': 'error', 'error': e.toString()};
    }
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }
}
