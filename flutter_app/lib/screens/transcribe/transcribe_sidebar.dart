import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../widgets/app_scrollbar.dart';
import '../../providers/transcribe_provider.dart';
import '../../utils/ui_utils.dart';

class TranscribeSidebar extends StatelessWidget {
  final bool isMobile;
  final List<String> selectedFiles;
  final String language;
  final bool doTranslate;
  final String targetLang;
  final double displayProgress;
  final ScrollController listController;

  final ValueChanged<String> onLanguageChanged;
  final ValueChanged<bool> onTranslateChanged;
  final ValueChanged<String> onTargetLangChanged;
  final VoidCallback onClearSelection;
  final ValueChanged<String> onRemoveFile;
  final VoidCallback onStartTranscribe;
  final ValueChanged<bool> onUploadFile;
  final VoidCallback onShowCreateFolder;
  final VoidCallback onShowMoveDialog;
  final ValueChanged<Map<String, dynamic>> onShowFileInfo;

  const TranscribeSidebar({
    super.key,
    required this.isMobile,
    required this.selectedFiles,
    required this.language,
    required this.doTranslate,
    required this.targetLang,
    required this.displayProgress,
    required this.listController,
    required this.onLanguageChanged,
    required this.onTranslateChanged,
    required this.onTargetLangChanged,
    required this.onClearSelection,
    required this.onRemoveFile,
    required this.onStartTranscribe,
    required this.onUploadFile,
    required this.onShowCreateFolder,
    required this.onShowMoveDialog,
    required this.onShowFileInfo,
  });

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<TranscribeProvider>();
    final selectedDetails = prov.audioFiles.where((f) {
      final path = f['path'] as String? ?? f['name'] as String;
      return selectedFiles.contains(path);
    }).toList();

    return Card(
      color: AppTheme.cardDark,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.dividerColor, width: 1),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? AppConstants.paddingMedium : AppConstants.paddingLarge),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
              'Upload File',
              style: TextStyle(
                fontSize: isMobile ? 16 : 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: AppConstants.paddingMedium),
            _buildUploadButton(
              icon: Icons.create_new_folder,
              label: 'Buat Playlist',
              onPressed: prov.transcribing ? null : onShowCreateFolder,
            ),
            const SizedBox(height: 12),
            _buildUploadButton(
              icon: Icons.audio_file,
              label: 'Upload Audio',
              onPressed: prov.transcribing ? null : () => onUploadFile(false),
            ),
            const SizedBox(height: 12),
            _buildUploadButton(
              icon: Icons.video_file,
              label: isMobile ? 'Upload Video' : 'Upload Video (ke MP3)',
              onPressed: prov.transcribing ? null : () => onUploadFile(true),
            ),

            if (selectedDetails.isNotEmpty) ...[
              const SizedBox(height: AppConstants.paddingLarge),
              const Divider(color: AppTheme.dividerColor),
              const SizedBox(height: 12),
              _buildSelectedFilesHeader(),
              const SizedBox(height: 8),
              _buildSelectedFilesList(selectedDetails),
            ],

            const Divider(height: 48, color: AppTheme.dividerColor),
            Text(
              'Pengaturan',
              style: TextStyle(
                fontSize: isMobile ? 16 : 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: AppConstants.paddingMedium),
            _buildSettings(prov),
            const SizedBox(height: AppConstants.paddingExtraLarge),
            _buildStartButton(prov),
            if (prov.transcribing || prov.outputFile != null) ...[
              const SizedBox(height: AppConstants.paddingLarge),
              _buildStatusPanel(prov, context),
            ],
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildSelectedFilesHeader() {
    return Row(
      children: [
        const Icon(Icons.playlist_add_check_rounded, color: AppTheme.accentCyan, size: 20),
        const SizedBox(width: 8),
        Text(
          '${selectedFiles.length} File Dipilih',
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        if (selectedFiles.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.drive_file_move, color: AppTheme.accentBlue),
            tooltip: 'Pindah ke Playlist',
            onPressed: onShowMoveDialog,
          ),
        TextButton(
          onPressed: onClearSelection,
          child: const Text('Clear', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildSelectedFilesList(List<Map<String, dynamic>> selectedDetails) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      child: AppScrollbar(
        controller: listController,
        child: ListView.separated(
          controller: listController,
          shrinkWrap: true,
          physics: const BouncingScrollPhysics(),
          itemCount: selectedDetails.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final f = selectedDetails[index];
            final name = f['name'] ?? 'Unknown';
            final size = UiUtils.formatSize(f['size'] ?? 0);
            final path = f['path'] as String? ?? f['name'] as String;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.backgroundDark.withOpacity(0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.accentBlue.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description_rounded, size: 16, color: AppTheme.textMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          size,
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => onShowFileInfo(f),
                    icon: const Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.accentCyan),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Informasi Lengkap',
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => onRemoveFile(path),
                    icon: const Icon(Icons.close_rounded, size: 16, color: AppTheme.error),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Hapus dari daftar',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSettings(TranscribeProvider prov) {
    return Column(
      children: [
        _buildDropdown(
          label: 'Bahasa Audio',
          value: language,
          items: const [
            DropdownMenuItem(value: 'auto', child: Text('Auto Detect')),
            DropdownMenuItem(value: 'id', child: Text('Indonesia')),
            DropdownMenuItem(value: 'en', child: Text('English (Inggris)')),
            DropdownMenuItem(value: 'ja', child: Text('Japanese (Jepang)')),
            DropdownMenuItem(value: 'ko', child: Text('Korean (Korea)')),
          ],
          onChanged: prov.transcribing ? null : (v) => onLanguageChanged(v!),
        ),
        CheckboxListTile(
          title: const Text('Terjemahkan hasil?', style: TextStyle(color: Colors.white, fontSize: 14)),
          value: doTranslate,
          onChanged: prov.transcribing ? null : (v) => onTranslateChanged(v ?? false),
          activeColor: AppTheme.accentBlue,
          checkColor: Colors.white,
          contentPadding: EdgeInsets.zero,
        ),
        if (doTranslate) ...[
          const SizedBox(height: 8),
          _buildDropdown(
            label: 'Target Bahasa',
            value: targetLang,
            items: const [
              DropdownMenuItem(value: 'id', child: Text('Indonesia')),
              DropdownMenuItem(value: 'en', child: Text('English (Inggris)')),
              DropdownMenuItem(value: 'ja', child: Text('Japanese (Jepang)')),
              DropdownMenuItem(value: 'ko', child: Text('Korean (Korea)')),
            ],
            onChanged: prov.transcribing ? null : (v) => onTargetLangChanged(v!),
          ),
        ],
      ],
    );
  }

  Widget _buildStartButton(TranscribeProvider prov) {
    return ElevatedButton.icon(
      icon: prov.transcribing
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.play_arrow),
      label: Text(prov.transcribing ? 'Sedang Memproses...' : 'Mulai Transcribe'),
      style: ElevatedButton.styleFrom(
        backgroundColor: prov.transcribing ? AppTheme.dividerColor : AppTheme.accentBlue,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(vertical: isMobile ? 16 : 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: prov.transcribing ? null : onStartTranscribe,
    );
  }

  Widget _buildStatusPanel(TranscribeProvider prov, BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.paddingMedium),
      decoration: BoxDecoration(
        color: prov.outputFile != null ? AppTheme.success.withOpacity(0.1) : AppTheme.accentBlue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: prov.outputFile != null ? AppTheme.success : AppTheme.accentBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                prov.outputFile != null ? Icons.check_circle : Icons.sync,
                color: prov.outputFile != null ? AppTheme.success : AppTheme.accentBlue,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  prov.status,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (prov.transcribing) ...[
            const SizedBox(height: AppConstants.paddingMedium),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: displayProgress / 100,
                minHeight: 8,
                backgroundColor: AppTheme.dividerColor,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accentBlue),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${displayProgress.toStringAsFixed(1)}%',
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            TextButton.icon(
              onPressed: () => context.read<TranscribeProvider>().cancelTranscribe(),
              icon: const Icon(Icons.cancel, color: AppTheme.error),
              label: const Text('Batalkan', style: TextStyle(color: AppTheme.error)),
            ),
          ],
          if (prov.outputFile != null) ...[
            const SizedBox(height: AppConstants.paddingMedium),
            ElevatedButton.icon(
              icon: const Icon(Icons.edit_document),
              label: const Text('Buka Editor'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
                foregroundColor: Colors.white,
              ),
              onPressed: () => context.go('/editor?file=${prov.outputFile}'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUploadButton({required IconData icon, required String label, VoidCallback? onPressed}) {
    return ElevatedButton.icon(
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.accentBlue.withOpacity(0.1),
        foregroundColor: Colors.white,
        side: const BorderSide(color: AppTheme.accentBlue, width: 1),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onPressed,
    );
  }

  Widget _buildDropdown({required String label, required String value, required List<DropdownMenuItem<String>> items, ValueChanged<String?>? onChanged}) {
    return DropdownButtonFormField<String>(
      value: value,
      dropdownColor: AppTheme.cardDark,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}
