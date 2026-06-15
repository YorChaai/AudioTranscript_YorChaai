import 'package:flutter/material.dart';
import '../repositories/history_repository.dart';

class HistoryProvider extends ChangeNotifier {
  final HistoryRepository _repository;

  HistoryProvider({HistoryRepository? repository}) : _repository = repository ?? HistoryRepository();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> get history => _history;

  Future<void> loadHistory({int limit = 50}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _repository.getHistory(limit: limit);
      _history = List<Map<String, dynamic>>.from(result['history'] ?? []);
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
