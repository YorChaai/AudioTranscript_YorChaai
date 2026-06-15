import '../services/api_service.dart';

class FileBrowserRepository {
  Future<Map<String, dynamic>> browseFiles({String folder = ''}) async {
    return await ApiService.browseFiles(folder: folder);
  }
}
