import '../services/api_service.dart';

class EditorRepository {
  Future<Map<String, dynamic>> listTranscripts({String path = ''}) async {
    return await ApiService.listTranscripts(path: path);
  }

  Future<Map<String, dynamic>> getTranscript(String filepath) async {
    return await ApiService.getTranscript(filepath);
  }

  Future<Map<String, dynamic>> updateTranscript(String filepath, String content) async {
    return await ApiService.updateTranscript(filepath, content);
  }

  Future<Map<String, dynamic>> convertToPdf(String filepath) async {
    return await ApiService.convertToPdf(filepath);
  }

  Future<List<int>> downloadFile(String filepath) async {
    return await ApiService.downloadFile(filepath);
  }
}
