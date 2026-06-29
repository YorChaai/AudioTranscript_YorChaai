import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../widgets/responsive_layout.dart';
import '../providers/editor_provider.dart';
import '../services/api_service.dart';
import '../utils/ui_utils.dart';

import 'editor/editor_sidebar.dart';
import 'editor/editor_main_area.dart';

class EditorScreen extends StatefulWidget {
  final String? initialFilePath;

  const EditorScreen({super.key, this.initialFilePath});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  String? _selectedFile;
  bool _loadingContent = false;
  bool _saving = false;
  bool _hasChanges = false;
  bool _isLocked = true;
  final TextEditingController _editorController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _listScrollController = ScrollController();
  final ScrollController _mobileScrollController = ScrollController();

  EditorProvider get _prov => context.read<EditorProvider>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFiles();
    });
  }

  @override
  void dispose() {
    _editorController.dispose();
    _scrollController.dispose();
    _listScrollController.dispose();
    _mobileScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    // If we have a target file from navigation (e.g. from "Buka Editor" button),
    // load it directly without scanning the current directory first.
    if (widget.initialFilePath != null && _selectedFile == null) {
      setState(() {
        _selectedFile = widget.initialFilePath;
      });
      await _loadFileContent(widget.initialFilePath!);
      // Also load the directory listing in the background so the sidebar shows files
      await _prov.loadFiles();
      return;
    }

    await _prov.loadFiles();
    final files = _prov.files;
    if (files.isNotEmpty && _selectedFile == null) {
      if (mounted && Responsive.isWide(context)) {
        setState(() {
          _selectedFile = files.first['path'] as String;
        });
        _loadFileContent(files.first['path'] as String);
      }
    }
  }

  Future<void> _loadFileContent(String filepath) async {
    setState(() => _loadingContent = true);
    final content = await _prov.loadTranscriptContent(filepath);
    if (!mounted) return;

    if (content != null) {
      setState(() {
        _editorController.text = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
        _hasChanges = false;
        _loadingContent = false;
      });
    } else {
      setState(() => _loadingContent = false);
      UiUtils.showSnackBar(context, _prov.errorMessage ?? 'Gagal memuat file', isError: true);
    }
  }

  Future<void> _saveContent() async {
    if (_selectedFile == null) return;
    setState(() => _saving = true);
    final normalizedContent = _editorController.text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final success = await _prov.saveTranscript(_selectedFile!, normalizedContent);
    if (!mounted) return;
    setState(() => _saving = false);
    
    if (success) {
      setState(() => _hasChanges = false);
      UiUtils.showSnackBar(context, 'Perubahan berhasil disimpan di server!');
    } else {
      UiUtils.showSnackBar(context, _prov.errorMessage ?? 'Gagal menyimpan', isError: true);
    }
  }

  Future<void> _convertToPdf() async {
    if (_selectedFile == null) return;
    UiUtils.showSnackBar(context, 'Converting to PDF...');
    final pdfPath = await _prov.convertToPdf(_selectedFile!);
    
    if (!mounted) return;
    if (pdfPath != null) {
      UiUtils.showSnackBar(context, 'Berhasil convert PDF! File: $pdfPath');
    } else {
      UiUtils.showSnackBar(context, _prov.errorMessage ?? 'Gagal convert PDF', isError: true);
    }
  }

  Future<void> _downloadFile(String filepath) async {
    try {
      UiUtils.showSnackBar(context, 'Mendownload...');
      final bytes = await ApiService.downloadFile(filepath);
      final filename = filepath.split('/').last;

      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/$filename');
      await file.writeAsBytes(bytes);

      if (!mounted) return;
      UiUtils.showSnackBar(context, 'File berhasil didownload ke ${file.path}');
    } catch (e) {
      if (!mounted) return;
      UiUtils.showSnackBar(context, 'Gagal download: $e', isError: true);
    }
  }

  void _onFileSelected(String filepath) {
    setState(() {
      _selectedFile = filepath;
      _isLocked = true;
    });
    _loadFileContent(filepath);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = Responsive.isWide(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (_selectedFile != null && _hasChanges && !_saving) _saveContent();
        },
      },
      child: Focus(
        autofocus: false,
        child: SafeArea(
          child: isWide ? _buildDesktopLayout() : _buildMobileLayout(),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 300,
          child: EditorSidebar(
            isMobile: false,
            selectedFile: _selectedFile,
            onFileSelected: _onFileSelected,
            onRefresh: _loadFiles,
            listScrollController: _listScrollController,
            mobileScrollController: _mobileScrollController,
          ),
        ),
        const SizedBox(width: 24),
        Expanded(child: _buildMainArea()),
      ],
    );
  }

  Widget _buildMobileLayout() {
    if (_selectedFile == null) {
      return EditorSidebar(
        isMobile: true,
        selectedFile: _selectedFile,
        onFileSelected: _onFileSelected,
        onRefresh: _loadFiles,
        listScrollController: _listScrollController,
        mobileScrollController: _mobileScrollController,
      );
    }
    return _buildMainArea();
  }

  Widget _buildMainArea() {
    return EditorMainArea(
      selectedFile: _selectedFile,
      loadingContent: _loadingContent,
      hasChanges: _hasChanges,
      isLocked: _isLocked,
      saving: _saving,
      isLoading: _prov.isLoading,
      editorController: _editorController,
      scrollController: _scrollController,
      onBack: () => setState(() => _selectedFile = null),
      onToggleLock: () => setState(() => _isLocked = !_isLocked),
      onSave: _saveContent,
      onConvertToPdf: _convertToPdf,
      onDownload: () => _downloadFile(_selectedFile!),
      onChanged: (val) {
        if (!_hasChanges) setState(() => _hasChanges = true);
      },
    );
  }
}
