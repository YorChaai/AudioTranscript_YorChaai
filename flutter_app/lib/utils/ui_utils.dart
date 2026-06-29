import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../config/constants.dart';

/// Utilities to enforce DRY principle for common UI tasks.
class UiUtils {
  /// Shows a standard SnackBar.
  static void showSnackBar(BuildContext context, String message, {bool isError = false}) {
    if (!context.mounted) return;
    
    // Hide current snackbar to prevent queuing too many
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.error : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Formats byte size into human readable string.
  static String formatSize(int bytes) {
    if (bytes < AppConstants.bytesInKB) return '$bytes B';
    if (bytes < AppConstants.bytesInMB) {
      return '${(bytes / AppConstants.bytesInKB).toStringAsFixed(1)} KB';
    }
    return '${(bytes / AppConstants.bytesInMB).toStringAsFixed(1)} MB';
  }

  /// Formats duration in seconds to MM:SS format.
  static String formatDuration(double durationInSeconds) {
    final int minutes = durationInSeconds ~/ 60;
    final int seconds = (durationInSeconds % 60).toInt();
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
