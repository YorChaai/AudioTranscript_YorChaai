import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import '../config/api_config.dart';
import '../config/theme.dart';
import 'package:provider/provider.dart';
import '../services/connection_service.dart';
import '../widgets/app_scrollbar.dart';

class SettingsDialog {
  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const _SettingsDialogContent(),
    );
  }
}

class _SettingsDialogContent extends StatefulWidget {
  const _SettingsDialogContent();

  @override
  State<_SettingsDialogContent> createState() => _SettingsDialogContentState();
}

class _SettingsDialogContentState extends State<_SettingsDialogContent> {
  late TextEditingController urlController;
  late ScrollController scrollController;
  static bool _isHighRefreshRate = false;

  @override
  void initState() {
    super.initState();
    urlController = TextEditingController(text: ApiConfig.serverUrl);
    scrollController = ScrollController();
  }

  @override
  void dispose() {
    urlController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.settings_rounded, color: AppTheme.accentBlue),
          SizedBox(width: 12),
          Text('Settings'),
        ],
      ),
      content: AppScrollbar(
        controller: scrollController,
        child: SingleChildScrollView(
          controller: scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Server Connection',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'http://192.168.1.100:5000',
                  prefixIcon: Icon(Icons.link_rounded),
                  helperText: 'Masukkan alamat lengkap beserta port (jika ada).',
                  helperMaxLines: 2,
                ),
              ),
              if (Platform.isAndroid) ...[
                const SizedBox(height: 24),
                const Text(
                  'Tampilan',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('High Refresh Rate (90/120Hz)'),
                  subtitle: const Text('Bikin animasi & scrolling lebih mulus'),
                  value: _isHighRefreshRate,
                  activeColor: AppTheme.accentCyan,
                  onChanged: (val) async {
                    setState(() => _isHighRefreshRate = val);
                    try {
                      if (val) {
                        await FlutterDisplayMode.setHighRefreshRate();
                      } else {
                        final modes = await FlutterDisplayMode.supported;
                        final activeMode = await FlutterDisplayMode.active;
                        final defaultMode = modes.firstWhere(
                          (m) => m.refreshRate.round() == 60,
                          orElse: () => activeMode,
                        );
                        await FlutterDisplayMode.setPreferredMode(defaultMode);
                      }
                    } on PlatformException catch (e) {
                      debugPrint('Gagal mengubah refresh rate: $e');
                    }
                  },
                ),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: AppTheme.accentBlue,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Contoh IP Lokal:\nhttp://192.168.x.x:5000\nContoh Ngrok/Cloudflare:\nhttps://abcd.trycloudflare.com',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: () {
            final url = urlController.text.trim();
            if (url.isNotEmpty) {
              // Simpan langsung sebagai host
              ApiConfig.setServer(url);
              Provider.of<ConnectionService>(
                context,
                listen: false,
              ).checkConnection();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Server URL berhasil diubah')),
              );
            }
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
