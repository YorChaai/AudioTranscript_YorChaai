import 'package:flutter/material.dart';
import '../repositories/summary_repository.dart';

class SummaryProvider extends ChangeNotifier {
  final SummaryRepository _repository;

  SummaryProvider({SummaryRepository? repository}) : _repository = repository ?? SummaryRepository();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<Map<String, dynamic>> _files = [];
  List<Map<String, dynamic>> get files => _files;

  List<Map<String, dynamic>> _folders = [];
  List<Map<String, dynamic>> get folders => _folders;

  String _currentPath = '';
  String get currentPath => _currentPath;

  final List<String> _pathHistory = [];
  List<String> get pathHistory => _pathHistory;

  Future<void> loadFiles() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _repository.listTranscripts(path: _currentPath);
      _files = List<Map<String, dynamic>>.from(result['files'] ?? []);
      _folders = List<Map<String, dynamic>>.from(result['folders'] ?? []);
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> generateSummary({required String txtFile, required String model}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _repository.startSummary(txtFile: txtFile, model: model);
      return result['summary'] as String;
    } catch (e) {
      _errorMessage = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ===== FOLDER NAVIGATION =====
  void navigateTo(String path) {
    _pathHistory.add(_currentPath);
    _currentPath = path;
    loadFiles();
  }

  void goBack() {
    if (_pathHistory.isNotEmpty) {
      _currentPath = _pathHistory.removeLast();
      loadFiles();
    }
  }

  void goToRoot() {
    _pathHistory.clear();
    _currentPath = '';
    loadFiles();
  }
}
