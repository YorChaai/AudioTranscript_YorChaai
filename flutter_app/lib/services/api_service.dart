import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'package:http_parser/http_parser.dart';
import '../config/api_config.dart';

class MultipartRequestWithProgress extends http.MultipartRequest {
  final void Function(int bytes, int totalBytes)? onProgress;

  MultipartRequestWithProgress(super.method, super.url, {this.onProgress});

  @override
  http.ByteStream finalize() {
    final byteStream = super.finalize();
    if (onProgress == null) return byteStream;

    final total = contentLength;
    int bytes = 0;

    final transformer = StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (data, sink) {
        bytes += data.length;
        onProgress!(bytes, total);
        sink.add(data);
      },
      handleDone: (sink) {
        sink.close();
      },
      handleError: (error, stackTrace, sink) {
        sink.addError(error, stackTrace);
      },
    );

    return http.ByteStream(byteStream.transform(transformer));
  }
}

/// service utama untuk semua HTTP request ke Flask server
class ApiService {
  static String get _base => ApiConfig.baseUrl;
  static final _client = ApiClient();

  // ===== HELPERS =====

  static String _encodePath(String path) {
    if (path.isEmpty) return '';
    return path.split('/').map((s) => Uri.encodeComponent(s)).join('/');
  }

  static Future<Map<String, dynamic>> _processResponse(http.Response res) async {
    return await compute((str) => jsonDecode(str) as Map<String, dynamic>, res.body);
  }

  // ===== HEALTH CHECK =====

  static Future<Map<String, dynamic>> healthCheck() async {
    try {
      final res = await _client
          .get(Uri.parse('$_base/health'))
          .timeout(const Duration(seconds: 5));
      return await _processResponse(res);
    } catch (e) {
      throw Exception('Tidak bisa terhubung ke server: $e');
    }
  }

  static Future<Map<String, dynamic>> systemHealthDetails() async {
    try {
      final res = await _client
          .get(Uri.parse('$_base/system/health-details'))
          .timeout(const Duration(seconds: 8));
      return await _processResponse(res);
    } catch (e) {
      throw Exception('Gagal memuat status kesehatan sistem: $e');
    }
  }

  // ===== AUDIO =====

  static Future<Map<String, dynamic>> scanCustomPath(String folderPath, {String subpath = '', bool recursive = false}) async {
    final res = await _client.post(
      Uri.parse('$_base/audio/scan-custom-path'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'folder_path': folderPath,
        'subpath': subpath,
        'recursive': recursive,
      }),
    ).timeout(const Duration(seconds: 30));
    return await _processResponse(res);
  }

  static Future<Map<String, dynamic>> listAudio({String path = ''}) async {
    final query = path.isNotEmpty ? "?path=${Uri.encodeQueryComponent(path)}" : "";
    final res = await _client
        .get(Uri.parse('$_base/audio/list$query'))
        .timeout(ApiConfig.requestTimeout);
    return await _processResponse(res);
  }

  static Future<Map<String, dynamic>> uploadAudio(File file, {String path = '', void Function(int bytes, int totalBytes)? onProgress}) async {
    return _uploadMultipart('$_base/audio/upload', file, 'audio', path: path, onProgress: onProgress);
  }

  static Future<Map<String, dynamic>> uploadVideoAndConvertToMp3(
    File file, {String path = '', void Function(int bytes, int totalBytes)? onProgress}
  ) async {
    return _uploadMultipart('$_base/video/upload-convert', file, 'video', path: path, onProgress: onProgress);
  }

  static Future<Map<String, dynamic>> _uploadMultipart(
    String url, File file, String type, {String path = '', void Function(int bytes, int totalBytes)? onProgress}
  ) async {
    final req = MultipartRequestWithProgress('POST', Uri.parse(url), onProgress: onProgress);
    req.fields['path'] = path;
    req.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: MediaType(type, file.path.split('.').last),
      ),
    );
    final streamRes = await _client.send(req).timeout(ApiConfig.uploadTimeout);
    final res = await http.Response.fromStream(streamRes);
    return await _processResponse(res);
  }

  // ===== FOLDERS / PLAYLISTS =====

  static Future<Map<String, dynamic>> createFolder(String name, {String path = ''}) async {
    final res = await _client.post(
      Uri.parse('$_base/folder/create'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'name': name, 'path': path}),
    ).timeout(ApiConfig.requestTimeout);
    return await _processResponse(res);
  }

  static Future<Map<String, dynamic>> moveFiles(List<String> files, String targetPath) async {
    final res = await _client.post(
      Uri.parse('$_base/file/move'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'files': files, 'targetPath': targetPath}),
    ).timeout(ApiConfig.requestTimeout);
    return await _processResponse(res);
  }

  static Future<Map<String, dynamic>> renameMedia(String path, String newName) async {
    final res = await _client.post(
      Uri.parse('$_base/file/rename'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'path': path, 'newName': newName}),
    ).timeout(ApiConfig.requestTimeout);
    return await _processResponse(res);
  }

  static Future<Map<String, dynamic>> deleteMedia({
    List<String>? files,
    List<String>? folders,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/file/delete'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'files': files ?? [],
        'folders': folders ?? [],
      }),
    ).timeout(ApiConfig.requestTimeout);
    return await _processResponse(res);
  }

  // ===== TRANSCRIBE =====

  static Future<Map<String, dynamic>> startTranscribe({
    List<String>? audioFiles,
    String? audioFile,
    List<String>? folderPaths,
    String language = 'auto',
    bool translate = false,
    String targetLang = 'id',
    int beamSize = 2,
  }) async {
    final List<String> files = audioFiles ?? (audioFile != null ? [audioFile] : []);
    final body = <String, dynamic>{
      'audio_files': files,
      'language': language,
      'translate': translate,
      'target_lang': targetLang,
      'beam_size': beamSize,
    };
    if (folderPaths != null && folderPaths.isNotEmpty) {
      body['folder_paths'] = folderPaths;
    }
    final res = await _client.post(
      Uri.parse('$_base/transcribe'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    ).timeout(ApiConfig.requestTimeout);
    return await _processResponse(res);
  }

  static Future<Map<String, dynamic>> getJobStatus(String jobId) async {
    final res = await _client
        .get(Uri.parse('$_base/transcribe/status/$jobId'))
        .timeout(ApiConfig.requestTimeout);
    return await _processResponse(res);
  }

  static Stream<Map<String, dynamic>> streamJobStatus(String jobId) async* {
    final streamClient = ApiClient();
    final request = http.Request('GET', Uri.parse('$_base/transcribe/stream/$jobId'));
    
    try {
      final response = await streamClient.send(request);
      await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.startsWith('data: ')) {
          final jsonStr = line.substring(6).trim();
          if (jsonStr.isNotEmpty) {
            yield await compute((str) => jsonDecode(str) as Map<String, dynamic>, jsonStr);
          }
        }
      }
    } finally {
      streamClient.close();
    }
  }

  static Future<Map<String, dynamic>> cancelTranscribe(String jobId) async {
    final res = await _client
        .post(Uri.parse('$_base/transcribe/cancel/$jobId'))
        .timeout(ApiConfig.requestTimeout);
    return await _processResponse(res);
  }

  // ===== TRANSCRIPTS =====

  static Future<Map<String, dynamic>> listTranscripts({String path = ''}) async {
    final query = path.isNotEmpty ? "?path=${Uri.encodeQueryComponent(path)}" : "";
    final res = await _client
        .get(Uri.parse('$_base/transcript/list$query'))
        .timeout(ApiConfig.requestTimeout);
    return await _processResponse(res);
  }

  static Future<Map<String, dynamic>> getTranscript(String filepath) async {
    final res = await _client
        .get(Uri.parse('$_base/transcript/${_encodePath(filepath)}'))
        .timeout(ApiConfig.requestTimeout);
    return await _processResponse(res);
  }

  static Future<Map<String, dynamic>> updateTranscript(
    String filepath,
    String content,
  ) async {
    final res = await _client.put(
      Uri.parse('$_base/transcript/${_encodePath(filepath)}'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'content': content}),
    ).timeout(ApiConfig.requestTimeout);
    return await _processResponse(res);
  }

  // ===== SUMMARY =====

  static Future<Map<String, dynamic>> getSummaryModels() async {
    final res = await _client
        .get(Uri.parse('$_base/summary/models'))
        .timeout(ApiConfig.requestTimeout);
    return await _processResponse(res);
  }

  static Future<Map<String, dynamic>> startSummary({
    required String txtFile,
    required String model,
    String? provider,
    String? apiKey,
  }) async {
    final body = <String, dynamic>{
      'txt_file': txtFile,
      'model': model,
    };
    if (provider != null) body['provider'] = provider;
    if (apiKey != null && apiKey.isNotEmpty) body['api_key'] = apiKey;

    final res = await _client.post(
      Uri.parse('$_base/summary'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    ).timeout(ApiConfig.requestTimeout);
    return await _processResponse(res);
  }

  static Future<Map<String, dynamic>> listSummaries({String path = ''}) async {
    final query = path.isNotEmpty ? "?path=${Uri.encodeQueryComponent(path)}" : "";
    final res = await _client
        .get(Uri.parse('$_base/summary/list$query'))
        .timeout(ApiConfig.requestTimeout);
    return await _processResponse(res);
  }

  // ===== PDF =====

  static Future<Map<String, dynamic>> convertToPdf(String filepath) async {
    final res = await _client.post(
      Uri.parse('$_base/convert-pdf'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'filepath': filepath}),
    ).timeout(ApiConfig.requestTimeout);
    return await _processResponse(res);
  }

  static Future<Map<String, dynamic>> listPdfs({String path = ''}) async {
    final query = path.isNotEmpty ? "?path=${Uri.encodeQueryComponent(path)}" : "";
    final res = await _client
        .get(Uri.parse('$_base/pdf/list$query'))
        .timeout(ApiConfig.requestTimeout);
    return await _processResponse(res);
  }

  static Future<Map<String, dynamic>> mergePdfs() async {
    final res = await _client
        .post(Uri.parse('$_base/pdf/merge'))
        .timeout(const Duration(minutes: 5));
    return await _processResponse(res);
  }

  // ===== DOWNLOAD =====

  static Future<List<int>> downloadFile(String filepath) async {
    final res = await _client
        .get(Uri.parse('$_base/download/${_encodePath(filepath)}'))
        .timeout(ApiConfig.uploadTimeout);
    return res.bodyBytes;
  }

  static String getDownloadUrl(String filepath) {
    return '${ApiConfig.serverUrl}/api/download/${_encodePath(filepath)}';
  }

  // ===== HISTORY =====

  static Future<Map<String, dynamic>> getHistory({int limit = 50}) async {
    final res = await _client
        .get(Uri.parse('$_base/history?limit=$limit'))
        .timeout(ApiConfig.requestTimeout);
    return await _processResponse(res);
  }

  // ===== FILE BROWSER =====

  static Future<Map<String, dynamic>> browseFiles({String folder = ''}) async {
    final query = folder.isNotEmpty ? "?folder=$folder" : "";
    final res = await _client
        .get(Uri.parse('$_base/files/browse$query'))
        .timeout(ApiConfig.requestTimeout);
    return await _processResponse(res);
  }
}
