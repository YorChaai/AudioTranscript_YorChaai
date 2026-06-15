import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'package:http_parser/http_parser.dart';
import '../config/api_config.dart';

/// service utama untuk semua HTTP request ke Flask server
class ApiService {
  static String get _base => ApiConfig.baseUrl;
  static final _client = ApiClient();

  // ===== HEALTH CHECK =====

  static Future<Map<String, dynamic>> healthCheck() async {
    try {
      final res = await _client
          .get(Uri.parse('$_base/health'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        return await compute((str) => jsonDecode(str) as Map<String, dynamic>, res.body);
      }
      throw Exception('Server error: ${res.statusCode}');
    } catch (e) {
      throw Exception('Tidak bisa terhubung ke server: $e');
    }
  }

  // ===== AUDIO =====

  static Future<Map<String, dynamic>> listAudio({String path = ''}) async {
    final res = await _client
        .get(Uri.parse('$_base/audio/list${path.isNotEmpty ? "?path=$path" : ""}'))
        .timeout(ApiConfig.requestTimeout);
    return await compute((str) => jsonDecode(str) as Map<String, dynamic>, res.body);
  }

  static Future<Map<String, dynamic>> uploadAudio(File file, {String path = ''}) async {
    final req = http.MultipartRequest('POST', Uri.parse('$_base/audio/upload'));
    req.fields['path'] = path;
    req.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: MediaType('audio', file.path.split('.').last),
      ),
    );
    final streamRes = await _client.send(req).timeout(ApiConfig.uploadTimeout);
    final res = await http.Response.fromStream(streamRes);
    return await compute((str) => jsonDecode(str) as Map<String, dynamic>, res.body);
  }

  static Future<Map<String, dynamic>> uploadVideoAndConvertToMp3(
    File file, {String path = ''}
  ) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$_base/video/upload-convert'),
    );
    req.fields['path'] = path;
    req.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: MediaType('video', file.path.split('.').last),
      ),
    );
    final streamRes = await _client.send(req).timeout(ApiConfig.uploadTimeout);
    final res = await http.Response.fromStream(streamRes);
    return await compute((str) => jsonDecode(str) as Map<String, dynamic>, res.body);
  }

  // ===== FOLDERS / PLAYLISTS =====

  static Future<Map<String, dynamic>> createFolder(String name, {String path = ''}) async {
    final res = await _client.post(
      Uri.parse('$_base/folder/create'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'name': name,
        'path': path,
      }),
    ).timeout(ApiConfig.requestTimeout);
    return await compute((str) => jsonDecode(str) as Map<String, dynamic>, res.body);
  }

  static Future<Map<String, dynamic>> moveFiles(List<String> files, String targetPath) async {
    final res = await _client.post(
      Uri.parse('$_base/file/move'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'files': files,
        'targetPath': targetPath,
      }),
    ).timeout(ApiConfig.requestTimeout);
    return await compute((str) => jsonDecode(str) as Map<String, dynamic>, res.body);
  }

  // ===== TRANSCRIBE =====

  static Future<Map<String, dynamic>> startTranscribe({
    List<String>? audioFiles,
    String? audioFile, // backward compatibility
    String language = 'auto',
    bool translate = false,
    String targetLang = 'id',
  }) async {
    final List<String> files = audioFiles ?? (audioFile != null ? [audioFile] : []);
    final res = await _client
        .post(
          Uri.parse('$_base/transcribe'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'audio_files': files,
            'language': language,
            'translate': translate,
            'target_lang': targetLang,
          }),
        )
        .timeout(ApiConfig.requestTimeout);
    return await compute((str) => jsonDecode(str) as Map<String, dynamic>, res.body);
  }

  static Future<Map<String, dynamic>> getJobStatus(String jobId) async {
    final res = await _client
        .get(Uri.parse('$_base/transcribe/status/$jobId'))
        .timeout(ApiConfig.requestTimeout);
    return await compute((str) => jsonDecode(str) as Map<String, dynamic>, res.body);
  }

  static Stream<Map<String, dynamic>> streamJobStatus(String jobId) async* {
    final client = ApiClient();
    final request = http.Request('GET', Uri.parse('$_base/transcribe/stream/$jobId'));
    
    try {
      final response = await client.send(request);
      await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.startsWith('data: ')) {
          final jsonStr = line.substring(6).trim();
          if (jsonStr.isNotEmpty) {
            yield await compute((str) => jsonDecode(str) as Map<String, dynamic>, jsonStr);
          }
        }
      }
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>> cancelTranscribe(String jobId) async {
    final res = await _client
        .post(Uri.parse('$_base/transcribe/cancel/$jobId'))
        .timeout(ApiConfig.requestTimeout);
    return await compute((str) => jsonDecode(str) as Map<String, dynamic>, res.body);
  }

  // ===== TRANSCRIPTS =====

  static Future<Map<String, dynamic>> listTranscripts({String path = ''}) async {
    final uri = path.isNotEmpty
        ? Uri.parse('$_base/transcript/list?path=${Uri.encodeQueryComponent(path)}')
        : Uri.parse('$_base/transcript/list');
    final res = await _client
        .get(uri)
        .timeout(ApiConfig.requestTimeout);
    return await compute((str) => jsonDecode(str) as Map<String, dynamic>, res.body);
  }

  static Future<Map<String, dynamic>> getTranscript(String filepath) async {
    final encodedPath =
        filepath.split('/').map((s) => Uri.encodeComponent(s)).join('/');
    final res = await _client
        .get(Uri.parse('$_base/transcript/$encodedPath'))
        .timeout(ApiConfig.requestTimeout);
    return await compute((str) => jsonDecode(str) as Map<String, dynamic>, res.body);
  }

  static Future<Map<String, dynamic>> updateTranscript(
    String filepath,
    String content,
  ) async {
    final encodedPath =
        filepath.split('/').map((s) => Uri.encodeComponent(s)).join('/');
    final res = await _client
        .put(
          Uri.parse('$_base/transcript/$encodedPath'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'content': content}),
        )
        .timeout(ApiConfig.requestTimeout);
    return await compute((str) => jsonDecode(str) as Map<String, dynamic>, res.body);
  }

  // ===== SUMMARY =====

  static Future<Map<String, dynamic>> startSummary({
    required String txtFile,
    required String model,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/summary'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'txt_file': txtFile,
        'model': model,
      }),
    ).timeout(ApiConfig.requestTimeout);
    return await compute((str) => jsonDecode(str) as Map<String, dynamic>, res.body);
  }

  static Future<Map<String, dynamic>> listSummaries({String path = ''}) async {
    final uri = path.isNotEmpty
        ? Uri.parse('$_base/summary/list?path=${Uri.encodeQueryComponent(path)}')
        : Uri.parse('$_base/summary/list');
    final res = await _client
        .get(uri)
        .timeout(ApiConfig.requestTimeout);
    return await compute((str) => jsonDecode(str) as Map<String, dynamic>, res.body);
  }

  // ===== PDF =====

  static Future<Map<String, dynamic>> convertToPdf(String filepath) async {
    final res = await _client
        .post(
          Uri.parse('$_base/convert-pdf'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'filepath': filepath}),
        )
        .timeout(ApiConfig.requestTimeout);
    return await compute((str) => jsonDecode(str) as Map<String, dynamic>, res.body);
  }

  static Future<Map<String, dynamic>> listPdfs({String path = ''}) async {
    final uri = path.isNotEmpty
        ? Uri.parse('$_base/pdf/list?path=${Uri.encodeQueryComponent(path)}')
        : Uri.parse('$_base/pdf/list');
    final res = await _client
        .get(uri)
        .timeout(ApiConfig.requestTimeout);
    return await compute((str) => jsonDecode(str) as Map<String, dynamic>, res.body);
  }

  static Future<Map<String, dynamic>> mergePdfs() async {
    final res = await _client
        .post(Uri.parse('$_base/pdf/merge'))
        .timeout(const Duration(minutes: 5)); // lama kalau banyak pdf

    if (res.statusCode != 200) {
      throw Exception(json.decode(res.body)['error'] ?? 'Merge failed');
    }
    return await compute((str) => jsonDecode(str) as Map<String, dynamic>, res.body);
  }

  // ===== DOWNLOAD =====

  static Future<List<int>> downloadFile(String filepath) async {
    final encodedPath =
        filepath.split('/').map((s) => Uri.encodeComponent(s)).join('/');
    final res = await _client
        .get(Uri.parse('$_base/download/$encodedPath'))
        .timeout(ApiConfig.uploadTimeout);
    return res.bodyBytes;
  }

  static String getDownloadUrl(String filepath) {
    final encodedPath =
        filepath.split('/').map((s) => Uri.encodeComponent(s)).join('/');
    return '${ApiConfig.serverUrl}/api/download/$encodedPath';
  }

  // ===== HISTORY =====

  static Future<Map<String, dynamic>> getHistory({int limit = 50}) async {
    final res = await _client
        .get(Uri.parse('$_base/history?limit=$limit'))
        .timeout(ApiConfig.requestTimeout);
    return await compute((str) => jsonDecode(str) as Map<String, dynamic>, res.body);
  }

  // ===== FILE BROWSER =====

  static Future<Map<String, dynamic>> browseFiles({String folder = ''}) async {
    final res = await _client
        .get(
          Uri.parse(
            '$_base/files/browse${folder.isNotEmpty ? "?folder=$folder" : ""}',
          ),
        )
        .timeout(ApiConfig.requestTimeout);
    return await compute((str) => jsonDecode(str) as Map<String, dynamic>, res.body);
  }
}
