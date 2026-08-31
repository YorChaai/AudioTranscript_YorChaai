import 'package:flutter/material.dart';
import '../repositories/file_browser_repository.dart';

class FileBrowserProvider extends ChangeNotifier {
  final FileBrowserRepository _repository;

  FileBrowserProvider({FileBrowserRepository? repository}) : _repository = repository ?? FileBrowserRepository();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> get items => _items;
  
  String _currentPath = '';
  String get currentPath => _currentPath;

  Future<void> browseFiles({String folder = ''}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _repository.browseFiles(folder: folder);
      _items = List<Map<String, dynamic>>.from(result['items'] ?? []);
      _currentPath = (result['current'] ?? result['current_path'])?.toString() ?? folder;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
