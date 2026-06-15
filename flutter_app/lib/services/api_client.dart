import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/api_exception.dart';

class ApiClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  static const String apiKey = 'YORCHAAI_SECRET_KEY'; // Hardcoded for now per Task 7.2

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers['X-Api-Key'] = apiKey;
    try {
      final response = await _inner.send(request);
      
      // Global error interception
      if (response.statusCode >= 400) {
        // Read the stream to get error message
        final respStr = await response.stream.bytesToString();
        String errorMessage = 'Terjadi kesalahan pada server';
        
        try {
          final json = jsonDecode(respStr);
          if (json is Map && json.containsKey('error')) {
            errorMessage = json['error'];
          } else if (json is Map && json.containsKey('message')) {
            errorMessage = json['message'];
          }
        } catch (_) {
          // If not json, use raw string if not too long
          if (respStr.isNotEmpty && respStr.length < 100) {
            errorMessage = respStr;
          }
        }
        
        throw ApiException(
          errorMessage, 
          statusCode: response.statusCode, 
          details: respStr
        );
      }
      return response;
    } on SocketException catch (e) {
      throw ApiException('Tidak dapat terhubung ke server. Pastikan server Python berjalan.', details: e.toString());
    } on TimeoutException catch (_) {
      throw ApiException('Koneksi ke server timeout (terlalu lama).');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Terjadi kesalahan jaringan yang tidak diketahui: $e');
    }
  }
}
