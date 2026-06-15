import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/sort_menu.dart';
import '../providers/sort_provider.dart';
import 'package:provider/provider.dart';
import '../widgets/app_scrollbar.dart';

/// screen convert transcript ke PDF
class PdfScreen extends StatefulWidget {
  const PdfScreen({super.key});

  @override
  State<PdfScreen> createState() => _PdfScreenState();
}

class _PdfScreenState extends State<PdfScreen> {
  List<Map<String, dynamic>> _files = [];
  List<Map<String, dynamic>> _txtFolders = [];
  bool _loading = true;
  final Set<String> _selectedFiles = {};
  bool _converting = false;
  final List<Map<String, dynamic>> _results = [];

  // Results State
  List<Map<String, dynamic>> _pdfFiles = [];
  List<Map<String, dynamic>> _pdfFolders = [];
  bool _loadingPdfs = true;
  final Set<String> _downloadedPdfs = {};

  // Folder Navigation State
  String _currentPath = '';
  final List<String> _pathHistory = [];

  // Scroll Controllers
  final ScrollController _mobileConvertScrollController = ScrollController();
  final ScrollController _desktopListScrollController = ScrollController();
  final ScrollController _resultsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadFiles();
    _loadPdfs();
  }

  @override
  void dispose() {
    _mobileConvertScrollController.dispose();
    _desktopListScrollController.dispose();
    _resultsScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    setState(() => _loading = true);
    try {
      final result = await ApiService.listTranscripts(path: _currentPath);
      setState(() {
        _files = List<Map<String, dynamic>>.from(result['files'] ?? []);
        _txtFolders = List<Map<String, dynamic>>.from(result['folders'] ?? []);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _convertSelected() async {
    if (_selectedFiles.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pilih file dulu')));
      return;
    }

    setState(() {
      _converting = true;
      _results.clear();
    });

    for (final filepath in _selectedFiles) {
      try {
        final result = await ApiService.convertToPdf(filepath);
        setState(() {
          _results.add({
            'file': filepath.split('/').last,
            'success': true,
            'pdf': result['pdf_name'],
            'pdf_path': result['pdf_path'],
          });
        });
      } catch (e) {
        setState(() {
          _results.add({
            'file': filepath.split('/').last,
            'success': false,
            'error': e.toString(),
          });
        });
      }
    }

    if (!mounted) return;
    setState(() {
      _converting = false;
    });
    _loadFiles();
    _loadPdfs(); // reload pdfs
  }

  Future<void> _loadPdfs() async {
    if (!mounted) return;
    setState(() => _loadingPdfs = true);
    try {
      final result = await ApiService.listPdfs(path: _currentPath);
      final pdfs = List<Map<String, dynamic>>.from(result['files'] ?? []);
      final pFolders = List<Map<String, dynamic>>.from(result['folders'] ?? []);

      // Check local existence
      final docDir = await getApplicationDocumentsDirectory();
      final localFiles =
          docDir.listSync().map((e) => e.uri.pathSegments.last).toSet();

      if (mounted) {
        setState(() {
          _pdfFiles = pdfs;
          _pdfFolders = pFolders;
          _downloadedPdfs.clear();
          for (var pdf in pdfs) {
            if (localFiles.contains(pdf['name'])) {
              _downloadedPdfs.add(pdf['name']);
            }
          }
          _loadingPdfs = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingPdfs = false);
    }
  }

  Future<void> _downloadPdf(String path, String filename) async {
    try {
      final bytes = await ApiService.downloadFile(path);
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes);

      setState(() {
        _downloadedPdfs.add(filename);
      });

      // Auto-open file
      final openResult = await OpenFile.open(file.path);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(openResult.type == ResultType.done
                ? '✅ File dibuka: $filename'
                : '✅ File tersimpan: $filename'),
            backgroundColor: AppTheme.success,
            showCloseIcon: true,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Gagal download: $e'),
            backgroundColor: AppTheme.error,
            showCloseIcon: true,
          ),
        );
      }
    }
  }

  Future<void> _openPdf(String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$filename';
    if (File(path).existsSync()) {
      OpenFile.open(path);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('File tidak ditemukan, coba download lagi')),
      );
      setState(() {
        _downloadedPdfs.remove(filename);
      });
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  List<Map<String, dynamic>> _getSortedFiles(SortProvider sortProv) {
    final list = List<Map<String, dynamic>>.from(_files);
    list.sort((a, b) {
      int result = 0;
      switch (sortProv.sortBy) {
        case 'date':
          final dateA = a['modified']?.toString() ?? '';
          final dateB = b['modified']?.toString() ?? '';
          result = dateA.compareTo(dateB);
          break;
        case 'type':
          final typeA =
              (a['name']?.toString() ?? '').split('.').last.toLowerCase();
          final typeB =
              (b['name']?.toString() ?? '').split('.').last.toLowerCase();
          result = typeA.compareTo(typeB);
          break;
        case 'size':
          final sizeA = a['size'] as int? ?? 0;
          final sizeB = b['size'] as int? ?? 0;
          result = sizeA.compareTo(sizeB);
          break;
        case 'name':
        default:
          final nameA = (a['name']?.toString() ?? '').toLowerCase();
          final nameB = (b['name']?.toString() ?? '').toLowerCase();
          result = nameA.compareTo(nameB);
          break;
      }
      return sortProv.sortAscending ? result : -result;
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: AppTheme.surfaceDark,
            child: const TabBar(
              indicatorColor: AppTheme.pdfColor,
              labelColor: AppTheme.pdfColor,
              unselectedLabelColor: AppTheme.textSecondary,
              tabs: [
                Tab(icon: Icon(Icons.transform_rounded), text: 'Convert'),
                Tab(icon: Icon(Icons.picture_as_pdf_rounded), text: 'Results'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildConvertTab(context),
                _buildResultsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConvertTab(BuildContext context) {
    final isWide = Responsive.isWide(context);

    if (!isWide) {
      return RefreshIndicator(
        onRefresh: _loadFiles,
        child: AppScrollbar(
          controller: _mobileConvertScrollController,
          child: CustomScrollView(
            controller: _mobileConvertScrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: _buildHeaderSection(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: _buildActionBarSection(),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: _buildBreadcrumb(),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              sliver: SliverToBoxAdapter(
                child: _buildFileListSection(isMobile: true),
              ),
            ),
          ],
        ),
      ),
    );
  }

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderSection(),
          const SizedBox(height: 20),
          _buildActionBarSection(),
          const SizedBox(height: 16),

          _buildBreadcrumb(),
          const SizedBox(height: 16),
          Expanded(
            child: _buildFileListSection(isMobile: false),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.pdfColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.picture_as_pdf_rounded,
            color: AppTheme.pdfColor,
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Convert to PDF',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Pilih transcript untuk dijadikan PDF',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionBarSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(
        children: [
          Text(
            '${_selectedFiles.length} file dipilih',
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const Spacer(),
          if (_selectedFiles.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _selectedFiles.clear()),
              child: const Text(
                'Clear',
                style: TextStyle(fontSize: 13),
              ),
            ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _converting ? null : _convertSelected,
            icon: Icon(
              _converting
                  ? Icons.hourglass_top_rounded
                  : Icons.picture_as_pdf_rounded,
              size: 18,
            ),
            label: Text(
              _converting ? 'Converting...' : 'Convert ke PDF',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.pdfColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.success.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Hasil Konversi',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ..._results.map(
            (r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    r['success']
                        ? Icons.check_circle_rounded
                        : Icons.error_rounded,
                    size: 16,
                    color: r['success'] ? AppTheme.success : AppTheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      r['success'] ? r['pdf'] : '${r["file"]}: ${r["error"]}',
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (r['success'] && r['pdf_path'] != null)
                    IconButton(
                      onPressed: () async {
                        try {
                          await _downloadPdf(r['pdf_path'], r['pdf']);
                        } catch (e) {
                          // ignore
                        }
                      },
                      icon: const Icon(
                        Icons.download_rounded,
                        size: 18,
                      ),
                      tooltip: 'Download',
                      color: AppTheme.accentCyan,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileListSection({required bool isMobile}) {
    return Container(
      height: isMobile ? null : double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        mainAxisSize: isMobile ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
            child: Row(
              children: [
                const Text(
                  'File Transcript',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (_selectedFiles.length == _files.length) {
                        _selectedFiles.clear();
                      } else {
                        _selectedFiles.clear();
                        for (final f in _files) {
                          _selectedFiles.add(f['path']);
                        }
                      }
                    });
                  },
                  child: Text(
                    _selectedFiles.length == _files.length && _files.isNotEmpty
                        ? 'Deselect All'
                        : 'Select All',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                SortMenu(
                  sortBy: context.watch<SortProvider>().sortBy,
                  sortAscending: context.watch<SortProvider>().sortAscending,
                  onSortByChanged: (value) =>
                      context.read<SortProvider>().setSortBy(value),
                  onSortOrderChanged: (value) =>
                      context.read<SortProvider>().setSortOrder(value),
                ),
                IconButton(
                  onPressed: _loadFiles,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (isMobile)
            _loading
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : (_files.isEmpty && _txtFolders.isEmpty)
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                            child: Text('Belum ada transcript',
                                style:
                                    TextStyle(color: AppTheme.textSecondary))),
                      )
                    : Column(
                        children: [
                          ..._txtFolders.map((f) => _buildFolderTile(f)),
                          ..._getSortedFiles(context.read<SortProvider>())
                              .map((file) => _buildFileTile(file)),
                        ],
                      )
          else
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : (_files.isEmpty && _txtFolders.isEmpty)
                      ? const Center(
                          child: Text(
                            'Belum ada transcript',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                        )
                      : Builder(
                          builder: (context) {
                            final sorted = _getSortedFiles(context.watch<SortProvider>());
                            return AppScrollbar(
                              controller: _desktopListScrollController,
                              child: ListView.separated(
                                controller: _desktopListScrollController,
                                physics: const BouncingScrollPhysics(),
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                itemCount: _txtFolders.length + sorted.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1, indent: 56),
                                itemBuilder: (context, index) {
                                  if (index < _txtFolders.length) {
                                    return _buildFolderTile(_txtFolders[index]);
                                  }
                                  return _buildFileTile(sorted[index - _txtFolders.length]);
                                },
                              ),
                            );
                          },
                        ),
            ),
        ],
      ),
    );
  }

  Widget _buildFileTile(Map<String, dynamic> file) {
    final isSelected = _selectedFiles.contains(file['path']);
    return CheckboxListTile(
      value: isSelected,
      onChanged: (v) {
        setState(() {
          if (v == true) {
            _selectedFiles.add(file['path']);
          } else {
            _selectedFiles.remove(file['path']);
          }
        });
      },
      activeColor: AppTheme.pdfColor,
      secondary: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: (isSelected ? AppTheme.pdfColor : AppTheme.textMuted)
              .withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.description_rounded,
          size: 18,
          color: isSelected ? AppTheme.pdfColor : AppTheme.textMuted,
        ),
      ),
      title: Text(
        file['name'],
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${file["label"]} · ${_formatSize(file["size"])}',
        style: const TextStyle(
          fontSize: 11,
          color: AppTheme.textMuted,
        ),
      ),
    );
  }

  Widget _buildFolderTile(Map<String, dynamic> folder) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppTheme.browserColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.folder_rounded,
          size: 18,
          color: AppTheme.browserColor,
        ),
      ),
      title: Text(
        folder['name'] ?? 'Folder',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppTheme.textPrimary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${folder['file_count'] ?? 0} files',
        style: const TextStyle(
          fontSize: 11,
          color: AppTheme.textMuted,
        ),
      ),
      onTap: () {
        setState(() {
          _pathHistory.add(_currentPath);
          _currentPath = folder['path'];
        });
        _loadFiles();
        _loadPdfs();
      },
    );
  }

  Widget _buildBreadcrumb() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(
        children: [
          if (_currentPath.isNotEmpty)
            InkWell(
              onTap: () {
                if (_pathHistory.isNotEmpty) {
                  setState(() {
                    _currentPath = _pathHistory.removeLast();
                  });
                  _loadFiles();
                  _loadPdfs();
                }
              },
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_rounded, size: 18, color: AppTheme.pdfColor),
                  SizedBox(width: 4),
                  Text('Kembali', style: TextStyle(fontSize: 13, color: AppTheme.pdfColor)),
                  SizedBox(width: 12),
                ],
              ),
            ),
          InkWell(
            onTap: _currentPath.isNotEmpty ? () {
                setState(() {
                  _pathHistory.clear();
                  _currentPath = '';
                });
                _loadFiles();
                _loadPdfs();
            } : null,
            child: Text(
              '📁 root',
              style: TextStyle(
                fontSize: 13,
                color: _currentPath.isNotEmpty ? AppTheme.pdfColor : AppTheme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (_currentPath.isNotEmpty) ...[
            const Text(' / ', style: TextStyle(color: AppTheme.textMuted)),
            Expanded(
              child: Text(
                _currentPath,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _mergePdfs() async {
    setState(() => _loadingPdfs = true);
    try {
      final res = await ApiService.mergePdfs();
      if (!mounted) return;

      await _loadPdfs(); // reload list first

      // show results
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.menu_book_rounded, color: AppTheme.accentCyan),
              SizedBox(width: 8),
              Text('Merge PDF Berhasil!'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Semua PDF berhasil digabung menjadi satu buku.'),
              const SizedBox(height: 8),
              Text('📁 Filename: ${res["filename"]}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('📄 Jumlah file: ${res["count"]}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.download_rounded, size: 16),
              onPressed: () {
                Navigator.pop(ctx);
                _downloadPdf(res['path'], res['filename']);
              },
              label: const Text('Download Book'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingPdfs = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Gagal merge: $e'), backgroundColor: AppTheme.error),
      );
    }
  }

  Widget _buildResultsTab() {
    if (_loadingPdfs) return const Center(child: CircularProgressIndicator());

    if (_pdfFiles.isEmpty && _pdfFolders.isEmpty) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _buildBreadcrumb(),
          ),
          const Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.picture_as_pdf, size: 64, color: AppTheme.textMuted),
                  SizedBox(height: 16),
                  Text('Belum ada file PDF',
                      style: TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _buildBreadcrumb(),
        ),

        // Merge Button Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentCyan,
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _pdfFiles.length > 1 ? _mergePdfs : null,
              icon: const Icon(Icons.menu_book_rounded),
              label: const Text('Gabungkan Semua PDF Jadi Buku (Merge)'),
            ),
          ),
        ),

        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadPdfs,
            child: AppScrollbar(
              controller: _resultsScrollController,
              thumbVisibility: false,
              child: ListView.separated(
                controller: _resultsScrollController,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: _pdfFolders.length + _pdfFiles.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                if (index < _pdfFolders.length) {
                  return _buildFolderTile(_pdfFolders[index]);
                }
                final pdf = _pdfFiles[index - _pdfFolders.length];
                final isDownloaded = _downloadedPdfs.contains(pdf['name']);
                final isBook = pdf['name'].toString().startsWith('Merged_Book');

                return Container(
                  decoration: BoxDecoration(
                    color: isBook
                        ? AppTheme.accentCyan.withOpacity(0.05)
                        : AppTheme.cardDark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isBook
                            ? AppTheme.accentCyan.withOpacity(0.3)
                            : AppTheme.dividerColor),
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color:
                            (isDownloaded ? AppTheme.success : AppTheme.error)
                                .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isBook
                            ? Icons.menu_book_rounded
                            : Icons.picture_as_pdf_rounded,
                        color: isDownloaded
                            ? AppTheme.success
                            : AppTheme.error, // Hijau/Merah
                      ),
                    ),
                    title: Text(
                      pdf['name'],
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${(pdf["size"] / 1024).toStringAsFixed(1)} KB · ${isDownloaded ? "Tersimpan di HP" : "Belum diunduh"}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDownloaded ? AppTheme.success : AppTheme.error,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isDownloaded)
                          IconButton(
                            icon: const Icon(Icons.visibility_rounded,
                                color: AppTheme.textSecondary),
                            tooltip: 'Lihat',
                            onPressed: () => _openPdf(pdf['name']),
                          ),
                        IconButton(
                          icon: Icon(
                              isDownloaded
                                  ? Icons.download_done_rounded
                                  : Icons.download_rounded,
                              color: isDownloaded
                                  ? AppTheme.success
                                  : AppTheme.accentBlue),
                          tooltip: 'Download',
                          onPressed: () =>
                              _downloadPdf(pdf['path'], pdf['name']),
                        ),
                      ],
                    ),
                    onTap: () {
                      if (isDownloaded) {
                        _openPdf(pdf['name']);
                      } else {
                        _downloadPdf(pdf['path'], pdf['name']);
                      }
                    },
                  ),
                );
              },
            ),
          ),
        ),
        ),
      ],
    );
  }
}
