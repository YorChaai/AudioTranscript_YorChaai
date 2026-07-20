import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/job_status.dart';
import '../repositories/transcribe_repository.dart';

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

  Future<Map<String, int>> uploadMediaBatch(List<File> files, {bool isVideo = false, void Function(int index, String fileName, double currentProgress)? onProgress}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    int successCount = 0;
    int failCount = 0;

    for (int i = 0; i < files.length; i++) {
      String fileName = files[i].path.split(Platform.pathSeparator).last;
      if (onProgress != null) {
        onProgress(i, fileName, 0.0);
      }
      
      try {
        void handleProgress(int bytes, int total) {
          if (onProgress != null && total > 0) {
            onProgress(i, fileName, bytes / total);
          }
        }

        if (isVideo) {
          await _repository.uploadVideoAndConvert(files[i], path: _currentPath, onProgress: handleProgress);
        } else {
          await _repository.uploadAudio(files[i], path: _currentPath, onProgress: handleProgress);
        }
        successCount++;
        
        if (onProgress != null) {
          onProgress(i, fileName, 1.0);
        }
      } catch (e) {
        failCount++;
      }
    }

    await loadAudioFiles();
    return {'success': successCount, 'failed': failCount};
  }

  Future<void> startTranscription({
    required List<String> files,
    required String language,
    required bool doTranslate,
    required String targetLang,
  }) async {
    _transcribing = true;
    _progress = 0;
    _statusMessage = 'Memulai batch (${files.length} file)...';
    _outputFile = null;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await _repository.startTranscribe(
        files: files,
        language: language,
        doTranslate: doTranslate,
        targetLang: targetLang,
      );

      _jobId = res['job_id'];
      
      _statusSubscription?.cancel();
      _statusSubscription = _repository.streamJobStatus(_jobId!).listen((data) {
        final job = JobStatus.fromJson(data);
        _progress = job.progress;
        _statusMessage = job.readableStatus;
        
        if (job.status == 'completed') {
          _finishJob(job.outputFile, '✅ Selesai!');
        } else if (job.status == 'failed' || job.status == 'error') {
          _errorJob(job.error ?? 'Terjadi kesalahan');
        } else if (job.status == 'cancelled') {
          _errorJob('🛑 Dibatalkan');
        }
        notifyListeners();
      }, onError: (e) {
        _errorJob('❌ Gagal menyambung stream: $e');
        notifyListeners();
      });

    } catch (e) {
      _errorJob('❌ Gagal memulai: $e');
      notifyListeners();
    }
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
    if (_jobId == null) return;
    try {
      await _repository.cancelTranscribe(_jobId!);
      _statusMessage = 'Membatalkan...';
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Gagal membatalkan: $e';
      notifyListeners();
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

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }
}
