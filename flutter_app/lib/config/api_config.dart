import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// konfigurasi API server
class ApiConfig {
  // ganti IP ini sesuai IP laptop kamu
  // cek di terminal: ipconfig -> IPv4 Address

  // Cek apakah API_URL disuplai lewat build --dart-define
  static const String _envApiUrl = String.fromEnvironment('API_URL');

  static String get _defaultHost {
    // Jika ada environment variable dari build_all.bat, gunakan itu
    if (_envApiUrl.isNotEmpty) {
      final uri = Uri.tryParse(_envApiUrl);
      if (uri != null) return uri.host;
    }

    if (kIsWeb) return '127.0.0.1';
    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) return '127.0.0.1';
    } catch (_) {}
    // Gunakan IP Address PC ini agar HP fisik bisa konek (sebagai fallback)
    return '192.168.68.52';
  }
  
  static int get _defaultPort {
    if (_envApiUrl.isNotEmpty) {
      final uri = Uri.tryParse(_envApiUrl);
      if (uri != null && uri.hasPort) return uri.port;
    }
    return 5000;
  }

  static String _host = _defaultHost;
  static int _port = _defaultPort;

  static String _cleanHost(String raw) {
    var trimmed = raw.trim();
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  static String get baseUrl {
    final clean = _cleanHost(_host);
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      return '$clean/api';
    }
    if (clean.contains(':')) {
      return 'http://$clean/api';
    }
    return 'http://$clean:$_port/api';
  }

  static String get serverUrl {
    final clean = _cleanHost(_host);
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      return clean;
    }
    if (clean.contains(':')) {
      return 'http://$clean';
    }
    return 'http://$clean:$_port';
  }

  static const String _prefHostKey = 'api_server_host';
  static const String _prefPortKey = 'api_server_port';

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedHost = prefs.getString(_prefHostKey);
      final savedPort = prefs.getInt(_prefPortKey);
      if (savedHost != null && savedHost.isNotEmpty) {
        _host = _cleanHost(savedHost);
      }
      if (savedPort != null && savedPort > 0) {
        _port = savedPort;
      }
    } catch (_) {}
  }

  static void setServer(String host, {int port = 5000}) {
    _host = _cleanHost(host);
    _port = port;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_prefHostKey, _host);
      prefs.setInt(_prefPortKey, _port);
    }).catchError((_) {});
  }

  static String get host => _host;
  static int get port => _port;

  /// timeout untuk request biasa
  static const Duration requestTimeout = Duration(seconds: 5);

  /// timeout untuk upload file besar
  static const Duration uploadTimeout = Duration(minutes: 10);

  /// interval health check (detik)
  static const int healthCheckInterval = 10;

  /// cek apakah running di desktop
  static bool get isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  /// cek apakah running di mobile
  static bool get isMobile {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  // AI API Keys
  static String geminiApiKey = '';
  static String claudeApiKey = '';
  static String grokApiKey = '';
  static String openaiApiKey = '';
}
