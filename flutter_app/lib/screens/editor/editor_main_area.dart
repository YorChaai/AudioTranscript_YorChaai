import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../widgets/app_scrollbar.dart';
import '../../widgets/responsive_layout.dart';

class EditorMainArea extends StatelessWidget {
  final String? selectedFile;
  final bool loadingContent;
  final bool hasChanges;
  final bool isLocked;
  final bool saving;
  final bool isLoading;
  
  final TextEditingController editorController;
  final ScrollController scrollController;

  final VoidCallback onBack;
  final VoidCallback onToggleLock;
  final VoidCallback onSave;
  final VoidCallback onConvertToPdf;
  final VoidCallback onDownload;
  final ValueChanged<String> onChanged;

  const EditorMainArea({
    super.key,
    required this.selectedFile,
    required this.loadingContent,
    required this.hasChanges,
    required this.isLocked,
    required this.saving,
    required this.isLoading,
    required this.editorController,
    required this.scrollController,
    required this.onBack,
    required this.onToggleLock,
    required this.onSave,
    required this.onConvertToPdf,
    required this.onDownload,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              !Responsive.isWide(context) ? 12 : 20, 12, 12, 8
            ),
            child: Row(
              children: [
                if (selectedFile != null) ...[
                  if (!Responsive.isWide(context))
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back_rounded),
                    )
                  else
                    const Icon(Icons.description_rounded, size: 18, color: AppTheme.editorColor),
                  const SizedBox(width: AppConstants.paddingSmall),
                  Expanded(
                    child: Text(
                      selectedFile!.split('/').last,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasChanges)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Unsaved',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.warning,
                              fontWeight: FontWeight.w600)),
                    ),
                  const SizedBox(width: AppConstants.paddingSmall),
                  _buildActionButtons(),
                ] else
                  const Expanded(
                    child: Text('Pilih file untuk diedit',
                        style: TextStyle(color: AppTheme.textSecondary)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildEditorArea(context)),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onToggleLock,
          icon: Icon(
            isLocked ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
            size: 20,
          ),
          tooltip: isLocked ? 'Buka Kunci' : 'Kunci Teks',
          color: isLocked ? AppTheme.textMuted : AppTheme.warning,
        ),
        IconButton(
          onPressed: hasChanges && !saving ? onSave : null,
          icon: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_rounded, size: 20),
          tooltip: 'Simpan',
          color: AppTheme.accentBlue,
        ),
        IconButton(
          onPressed: selectedFile != null && !isLoading ? onConvertToPdf : null,
          icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
          tooltip: 'Convert ke PDF',
          color: AppTheme.pdfColor,
        ),
        IconButton(
          onPressed: selectedFile != null ? onDownload : null,
          icon: const Icon(Icons.download_rounded, size: 20),
          tooltip: 'Download TXT',
          color: AppTheme.accentCyan,
        ),
      ],
    );
  }

  Widget _buildEditorArea(BuildContext context) {
    if (selectedFile == null) {
      return const Center(child: Text('Pilih file dari daftar'));
    }

    if (loadingContent) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(AppConstants.paddingMedium),
      child: Theme(
        data: Theme.of(context).copyWith(
          scrollbarTheme: ScrollbarThemeData(
            thumbVisibility: WidgetStateProperty.all(false),
            trackVisibility: WidgetStateProperty.all(false),
            thickness: WidgetStateProperty.all(0),
          ),
        ),
        child: AppScrollbar(
          controller: scrollController,
          child: TextField(
            controller: editorController,
            scrollController: scrollController,
            readOnly: isLocked,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(
                fontSize: 14,
                height: 1.6,
                fontFamily: 'Consolas',
                color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              fillColor: Colors.transparent,
              filled: true,
              hintText: 'Mulai edit teks di sini...',
              hintStyle: TextStyle(color: AppTheme.textMuted),
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}
