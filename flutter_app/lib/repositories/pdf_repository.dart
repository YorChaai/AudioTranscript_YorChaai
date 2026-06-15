import '../services/api_service.dart';

class PdfRepository {
  Future<Map<String, dynamic>> listTranscripts() async {
    return await ApiService.listTranscripts();
  }

  Future<Map<String, dynamic>> convertToPdf(String filepath) async {
    return await ApiService.convertToPdf(filepath);
  }

  Future<Map<String, dynamic>> listPdfs() async {
    return await ApiService.listPdfs();
  }

  Future<Map<String, dynamic>> mergePdfs() async {
    return await ApiService.mergePdfs();
  }

  Future<List<int>> downloadFile(String filepath) async {
    return await ApiService.downloadFile(filepath);
  }
}
