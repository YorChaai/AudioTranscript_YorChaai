import 'package:flutter/material.dart';
import '../repositories/pdf_repository.dart';

class PdfProvider extends ChangeNotifier {
  final PdfRepository _repository;

  PdfProvider({PdfRepository? repository}) : _repository = repository ?? PdfRepository();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<Map<String, dynamic>> _txtFiles = [];
  List<Map<String, dynamic>> get txtFiles => _txtFiles;

  List<Map<String, dynamic>> _pdfFiles = [];
  List<Map<String, dynamic>> get pdfFiles => _pdfFiles;

  Future<void> loadTxtFiles() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _repository.listTranscripts();
      _txtFiles = List<Map<String, dynamic>>.from(result['files'] ?? []);
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadPdfFiles() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _repository.listPdfs();
      _pdfFiles = List<Map<String, dynamic>>.from(result['files'] ?? []);
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> convertTxtToPdf(String filepath) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.convertToPdf(filepath);
      await loadPdfFiles();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> mergeAllPdfs() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.mergePdfs();
      await loadPdfFiles();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
