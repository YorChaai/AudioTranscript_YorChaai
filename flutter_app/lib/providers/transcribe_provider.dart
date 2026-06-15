import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
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

  // Transcribe State
  bool _transcribing = false;
  bool get transcribing => _transcribing;

  String? _jobId;
  String? get jobId => _jobId;

  double _progress = 0;
  double get progress => _progress;

  String _status = '';
  String get status => _status;

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

  Future<bool> uploadAudioFile(File file, {bool isVideo = false}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (isVideo) {
        await _repository.uploadVideoAndConvert(file, path: _currentPath);
      } else {
        await _repository.uploadAudio(file, path: _currentPath);
      }
      await loadAudioFiles(); // refresh list
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> startTranscribe({
    required List<String> files,
    required String language,
    required bool doTranslate,
    required String targetLang,
  }) async {
    _transcribing = true;
    _progress = 0;
    _status = 'Memulai batch (${files.length} file)...';
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
      _statusSubscription = _repository.streamJobStatus(_jobId!).listen((job) async {
        _progress = (job['progress'] ?? 0).toDouble();
        final newStatus = job['status'] ?? '';
        _status = _statusText(newStatus);
        
        if (newStatus == 'completed') {
          _statusSubscription?.cancel();
          _transcribing = false;
          _progress = 100;
          _outputFile = job['output_file'];
          _status = '✅ Selesai!';
        } else if (newStatus == 'failed' || newStatus == 'error') {
          _statusSubscription?.cancel();
          _transcribing = false;
          _errorMessage = job['error'] ?? 'Terjadi kesalahan';
          _status = '❌ Gagal';
        }
        notifyListeners();
      }, onError: (e) {
        _statusSubscription?.cancel();
        _transcribing = false;
        _errorMessage = e.toString();
        _status = '❌ Gagal menyambung stream';
        notifyListeners();
      });

    } catch (e) {
      _transcribing = false;
      _errorMessage = e.toString();
      _status = '❌ Gagal memulai';
      notifyListeners();
    }
  }

  Future<void> cancelTranscribe() async {
    if (_jobId == null) return;
    try {
      await _repository.cancelTranscribe(_jobId!);
    } catch (e) {
      _errorMessage = 'Gagal cancel: $e';
    } finally {
      _statusSubscription?.cancel();
      _transcribing = false;
      _status = 'Dibatalkan';
      notifyListeners();
    }
  }

  String _statusText(String st) {
    switch (st) {
      case 'pending': return 'Menunggu antrean...';
      case 'processing': return 'Sedang memproses...';
      case 'extracting_audio': return 'Ekstrak audio...';
      case 'completed': return '✅ Selesai!';
      case 'failed': return '❌ Gagal';
      default: return st;
    }
  }

  // ===== FOLDERS / PLAYLISTS =====
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
      
      if (res['errors'] != null) {
         final errors = res['errors'] as List;
         if (errors.isNotEmpty) {
           throw Exception("Gagal memindahkan file: ${errors.join(', ')}");
         }
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
