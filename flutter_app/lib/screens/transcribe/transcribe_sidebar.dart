import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../widgets/app_scrollbar.dart';
import '../../providers/transcribe_provider.dart';
import '../../providers/language_provider.dart';
import '../../utils/ui_utils.dart';

class TranscribeSidebar extends StatelessWidget {
  final bool isMobile;
  final List<String> selectedFiles;
  final List<String> selectedFolders;
  final String language;
  final bool doTranslate;
  final String targetLang;
  final int beamSize;
  final double displayProgress;
  final ScrollController listController;

  final ValueChanged<String> onLanguageChanged;
  final ValueChanged<bool> onTranslateChanged;
  final ValueChanged<String> onTargetLangChanged;
  final ValueChanged<int> onBeamSizeChanged;
  final VoidCallback onClearSelection;
  final ValueChanged<String> onRemoveFile;
  final ValueChanged<String>? onRemoveFolder;
  final VoidCallback onStartTranscribe;
  final ValueChanged<bool> onUploadFile;
  final VoidCallback onShowCreateFolder;
  final VoidCallback onShowMoveDialog;
  final ValueChanged<Map<String, dynamic>> onShowFileInfo;

  const TranscribeSidebar({
    super.key,
    required this.isMobile,
    required this.selectedFiles,
    this.selectedFolders = const [],
    required this.language,
    required this.doTranslate,
    required this.targetLang,
    this.beamSize = 2,
    required this.displayProgress,
    required this.listController,
    required this.onLanguageChanged,
    required this.onTranslateChanged,
    required this.onTargetLangChanged,
    required this.onBeamSizeChanged,
    required this.onClearSelection,
    required this.onRemoveFile,
    this.onRemoveFolder,
    required this.onStartTranscribe,
    required this.onUploadFile,
    required this.onShowCreateFolder,
    required this.onShowMoveDialog,
    required this.onShowFileInfo,
  });

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<TranscribeProvider>();
    final langProv = context.watch<LanguageProvider>();

    final selectedDetails = prov.audioFiles.where((f) {
      final path = f['path'] as String? ?? f['name'] as String;
      return selectedFiles.contains(path);
    }).toList();

    final selectedFolderDetails = prov.folders.where((fol) {
      final path = fol['path'] as String? ?? fol['name'] as String;
      return selectedFolders.contains(path);
    }).toList();

    final hasSelection = selectedFiles.isNotEmpty || selectedFolders.isNotEmpty;

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
                langProv.tr('upload_file'),
                style: TextStyle(
                  fontSize: isMobile ? 16 : 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: AppConstants.paddingMedium),
              _buildUploadButton(
                icon: Icons.create_new_folder,
                label: langProv.tr('create_playlist'),
                onPressed: prov.transcribing ? null : onShowCreateFolder,
              ),
              const SizedBox(height: 12),
              _buildUploadButton(
                icon: Icons.audio_file,
                label: langProv.tr('upload_audio'),
                onPressed: prov.transcribing ? null : () => onUploadFile(false),
              ),
              const SizedBox(height: 12),
              _buildUploadButton(
                icon: Icons.video_file,
                label: isMobile ? langProv.tr('upload_video') : '${langProv.tr('upload_video')} (MP3)',
                onPressed: prov.transcribing ? null : () => onUploadFile(true),
              ),

              if (hasSelection) ...[
                const SizedBox(height: AppConstants.paddingLarge),
                const Divider(color: AppTheme.dividerColor),
                const SizedBox(height: 12),
                _buildSelectedFilesHeader(langProv),
                const SizedBox(height: 8),
                _buildSelectedFilesList(selectedDetails, selectedFolderDetails),
              ],

              const Divider(height: 48, color: AppTheme.dividerColor),
              Text(
                langProv.tr('settings'),
                style: TextStyle(
                  fontSize: isMobile ? 16 : 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: AppConstants.paddingMedium),
              _buildSettings(prov, langProv),
              const SizedBox(height: AppConstants.paddingExtraLarge),
              _buildStartButton(prov, langProv),
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

  Widget _buildSelectedFilesHeader(LanguageProvider langProv) {
    String summaryText = '';
    if (selectedFiles.isNotEmpty && selectedFolders.isNotEmpty) {
      summaryText = '${selectedFiles.length} File & ${selectedFolders.length} Folder';
    } else if (selectedFolders.isNotEmpty) {
      summaryText = '${selectedFolders.length} Folder';
    } else {
      summaryText = '${selectedFiles.length} File';
    }

    return Row(
      children: [
        const Icon(Icons.playlist_add_check_rounded, color: AppTheme.accentCyan, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            summaryText,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (selectedFiles.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.drive_file_move, color: AppTheme.accentBlue),
            tooltip: langProv.tr('move_to_playlist'),
            onPressed: onShowMoveDialog,
          ),
        TextButton(
          onPressed: onClearSelection,
          child: Text(langProv.tr('clear'), style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildSelectedFilesList(
    List<Map<String, dynamic>> selectedDetails,
    List<Map<String, dynamic>> selectedFolderDetails,
  ) {
    final totalItems = selectedFolderDetails.length + selectedDetails.length;

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      child: AppScrollbar(
        controller: listController,
        child: ListView.separated(
          controller: listController,
          shrinkWrap: true,
          physics: const BouncingScrollPhysics(),
          itemCount: totalItems,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index < selectedFolderDetails.length) {
              final fld = selectedFolderDetails[index];
              final name = fld['name'] ?? 'Folder';
              final count = fld['file_count'] ?? 0;
              final path = fld['path'] as String? ?? fld['name'] as String;

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.browserColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.browserColor.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_rounded, size: 16, color: AppTheme.browserColor),
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
                            '$count file (beserta subfolder)',
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => onRemoveFolder?.call(path),
                      icon: const Icon(Icons.close_rounded, size: 16, color: AppTheme.error),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Hapus dari daftar',
                    ),
                  ],
                ),
              );
            }

            final fileIndex = index - selectedFolderDetails.length;
            final f = selectedDetails[fileIndex];
            final name = f['name'] ?? 'Unknown File';
            final size = f['size'] != null ? UiUtils.formatSize(f['size']) : '';
            final path = f['path'] as String? ?? f['name'] as String;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.accentBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.accentBlue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.audio_file, size: 16, color: AppTheme.accentCyan),
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

  String _getTargetLangName(String code) {
    switch (code) {
      case 'en':
        return 'English (Inggris)';
      case 'ja':
        return 'Japanese (Jepang)';
      case 'ko':
        return 'Korean (Korea)';
      case 'id':
      default:
        return 'Bahasa Indonesia';
    }
  }

  Widget _buildSettings(TranscribeProvider prov, LanguageProvider langProv) {
    return Column(
      children: [
        _buildDropdown(
          label: langProv.tr('language_detection'),
          value: language,
          items: [
            DropdownMenuItem(value: 'auto', child: Text(langProv.tr('auto_detect'))),
            const DropdownMenuItem(value: 'id', child: Text('Indonesia')),
            const DropdownMenuItem(value: 'en', child: Text('English (Inggris)')),
            const DropdownMenuItem(value: 'ja', child: Text('Japanese (Jepang)')),
            const DropdownMenuItem(value: 'ko', child: Text('Korean (Korea)')),
          ],
          onChanged: prov.transcribing ? null : (v) => onLanguageChanged(v!),
        ),
        const SizedBox(height: 12),
        _buildDropdown(
          label: 'Mode Kecepatan (Beam Size)',
          value: beamSize.toString(),
          items: const [
            DropdownMenuItem(
              value: '1',
              child: Text('⚡ Beam 1 (Super Cepat)', style: TextStyle(fontSize: 13)),
            ),
            DropdownMenuItem(
              value: '2',
              child: Text('🚀 Beam 2 (Cepat & Seimbang - Rekomendasi)', style: TextStyle(fontSize: 13)),
            ),
            DropdownMenuItem(
              value: '3',
              child: Text('⚖️ Beam 3 (Seimbang)', style: TextStyle(fontSize: 13)),
            ),
            DropdownMenuItem(
              value: '4',
              child: Text('🔍 Beam 4 (Teliti)', style: TextStyle(fontSize: 13)),
            ),
            DropdownMenuItem(
              value: '5',
              child: Text('🎯 Beam 5 (Sangat Teliti)', style: TextStyle(fontSize: 13)),
            ),
          ],
          onChanged: prov.transcribing ? null : (v) => onBeamSizeChanged(int.tryParse(v ?? '2') ?? 2),
        ),
        const SizedBox(height: 4),
        CheckboxListTile(
          title: Text(
            doTranslate ? 'Terjemahkan ke ${_getTargetLangName(targetLang)}' : 'Terjemahkan Hasil Transkripsi',
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          subtitle: doTranslate
              ? null
              : const Text('Centang untuk mengaktifkan terjemahan otomatis', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          value: doTranslate,
          onChanged: prov.transcribing ? null : (v) => onTranslateChanged(v ?? false),
          activeColor: AppTheme.accentBlue,
          checkColor: Colors.white,
          contentPadding: EdgeInsets.zero,
        ),
        if (doTranslate) ...[
          const SizedBox(height: 6),
          _buildDropdown(
            label: langProv.tr('target_language'),
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

  Widget _buildStartButton(TranscribeProvider prov, LanguageProvider langProv) {
    return ElevatedButton.icon(
      icon: prov.transcribing
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.play_arrow),
      label: Text(prov.transcribing ? langProv.tr('transcribing') : langProv.tr('start_transcribe')),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (prov.totalBatchFiles > 1)
                  Text(
                    'File ${prov.currentFileIndex} dari ${prov.totalBatchFiles}',
                    style: const TextStyle(color: AppTheme.accentCyan, fontSize: 12, fontWeight: FontWeight.w600),
                  )
                else
                  const SizedBox.shrink(),
                Text(
                  '${displayProgress.toStringAsFixed(1)}%',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (prov.batchEta.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundDark.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.dividerColor.withOpacity(0.6)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.timer_outlined, color: AppTheme.accentCyan, size: 13),
                            SizedBox(width: 4),
                            Text('Sisa Batch:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                          ],
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            prov.batchEta,
                            style: const TextStyle(color: AppTheme.accentCyan, fontSize: 11, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.hourglass_top_rounded, color: AppTheme.textMuted, size: 13),
                            SizedBox(width: 4),
                            Text('Berjalan:', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                          ],
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            prov.elapsedTime,
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => context.read<TranscribeProvider>().cancelTranscription(),
              icon: const Icon(Icons.cancel, color: AppTheme.error, size: 16),
              label: const Text('Batalkan', style: TextStyle(color: AppTheme.error, fontSize: 12)),
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
      isExpanded: true,
      value: value,
      dropdownColor: AppTheme.cardDark,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}
