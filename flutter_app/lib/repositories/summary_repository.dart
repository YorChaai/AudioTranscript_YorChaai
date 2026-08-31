import '../services/api_service.dart';

class SummaryRepository {
  Future<Map<String, dynamic>> listTranscripts({String path = ''}) async {
    return await ApiService.listTranscripts(path: path);
  }

  Future<Map<String, dynamic>> getSummaryModels() async {
    return await ApiService.getSummaryModels();
  }

  Future<Map<String, dynamic>> startSummary({
    required String txtFile,
    required String model,
    String? provider,
    String? apiKey,
  }) async {
    return await ApiService.startSummary(
      txtFile: txtFile,
      model: model,
      provider: provider,
      apiKey: apiKey,
    );
  }
}
