import '../services/api_service.dart';

class HistoryRepository {
  Future<Map<String, dynamic>> getHistory({int limit = 50}) async {
    return await ApiService.getHistory(limit: limit);
  }
}
