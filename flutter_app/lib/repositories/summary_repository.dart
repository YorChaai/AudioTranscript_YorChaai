import '../services/api_service.dart';

class SummaryRepository {
  Future<Map<String, dynamic>> listTranscripts({String path = ''}) async {
    return await ApiService.listTranscripts(path: path);
  }

  Future<Map<String, dynamic>> startSummary({required String txtFile, required String model}) async {
    return await ApiService.startSummary(txtFile: txtFile, model: model);
  }
}
