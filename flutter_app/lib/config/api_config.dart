import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// konfigurasi API server
class ApiConfig {
  // ganti IP ini sesuai IP laptop kamu
  // cek di terminal: ipconfig -> IPv4 Address

  static String get _defaultHost {
    if (kIsWeb) return '127.0.0.1';
    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) return '127.0.0.1';
    } catch (_) {}
    // Gunakan IP Address PC ini agar HP fisik bisa konek (192.168.68.55)
    return '192.168.68.55';
  }
  static const int _defaultPort = 5000;

  static String _host = _defaultHost;

  static int _port = _defaultPort;

  static String get baseUrl {
    if (_host.startsWith('http://') || _host.startsWith('https://')) {
      // jika host sudah ada http/https, pakai langsung (abaikan port default jika tidak dipakaikan)
      // tapi biasanya user paste 'https://blabla.trycloudflare.com' -> jadi 'https://blabla.trycloudflare.com/api'
      if (_host.endsWith('/')) return '${_host}api';
      return '$_host/api';
    }
    return 'http://$_host:$_port/api';
  }

  static String get serverUrl {
    if (_host.startsWith('http://') || _host.startsWith('https://')) {
      if (_host.endsWith('/')) return _host.substring(0, _host.length - 1);
      return _host;
    }
    return 'http://$_host:$_port';
  }

  static void setServer(String host, {int port = 5000}) {
    _host = host;
    _port = port;
  }

  static String get host => _host;
  static int get port => _port;

  /// timeout untuk request biasa
  static const Duration requestTimeout = Duration(seconds: 30);

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
}
