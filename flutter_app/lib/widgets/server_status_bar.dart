import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/connection_service.dart';
import '../config/theme.dart';
import '../screens/settings_dialog.dart';

/// status bar koneksi server - tampil di header
class ServerStatusBar extends StatelessWidget {
  final bool? compact;
  const ServerStatusBar({super.key, this.compact});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = compact ?? (screenWidth < 360);

    return Consumer<ConnectionService>(
      builder: (context, conn, _) {
        final isConnected = conn.isConnected;
        final isChecking = conn.isChecking;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => conn.checkConnection(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 8 : 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isChecking
                      ? AppTheme.warning.withOpacity(0.15)
                      : isConnected
                      ? AppTheme.success.withOpacity(0.15)
                      : AppTheme.error.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isChecking
                        ? AppTheme.warning.withOpacity(0.3)
                        : isConnected
                        ? AppTheme.success.withOpacity(0.3)
                        : AppTheme.error.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isChecking)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.warning,
                        ),
                      )
                    else
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isConnected ? AppTheme.success : AppTheme.error,
                          boxShadow: [
                            BoxShadow(
                              color:
                                  (isConnected ? AppTheme.success : AppTheme.error)
                                      .withOpacity(0.5),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(width: 6),
                    Text(
                      isChecking
                          ? (isCompact ? '...' : 'Connecting...')
                          : isConnected
                          ? (isCompact ? 'Online' : 'Server Online')
                          : (isCompact ? 'Offline' : 'Server Offline'),
                      style: TextStyle(
                        fontSize: isCompact ? 11 : 12,
                        fontWeight: FontWeight.w600,
                        color: isChecking
                            ? AppTheme.warning
                            : isConnected
                            ? AppTheme.success
                            : AppTheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => SettingsDialog.show(context),
                child: const Padding(
                  padding: EdgeInsets.all(6.0),
                  child: Icon(
                    Icons.settings_rounded,
                    color: Colors.white54,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}


