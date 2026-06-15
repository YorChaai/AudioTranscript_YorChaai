import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/app_scrollbar.dart';

/// file browser screen - jelajahi folder di server
class FileBrowserScreen extends StatefulWidget {
  const FileBrowserScreen({super.key});

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _currentPath = '';
  final List<String> _pathHistory = [];
  final ScrollController _gridScrollController = ScrollController();
  final ScrollController _mobileScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadFolder('');
  }

  @override
  void dispose() {
    _gridScrollController.dispose();
    _mobileScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFolder(String folder) async {
    setState(() => _loading = true);
    try {
      final result = await ApiService.browseFiles(folder: folder);
      setState(() {
        _items = List<Map<String, dynamic>>.from(result['items'] ?? []);
        _currentPath = result['current'] ?? '';
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  void _navigateTo(String path) {
    _pathHistory.add(_currentPath);
    _loadFolder(path);
  }

  void _goBack() {
    if (_pathHistory.isNotEmpty) {
      final prev = _pathHistory.removeLast();
      _loadFolder(prev);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _getFileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'txt':
        return Icons.description_rounded;
      case 'mp3':
      case 'wav':
      case 'm4a':
      case 'flac':
      case 'ogg':
      case 'aac':
      case 'mp4':
        return Icons.audio_file_rounded;
      case 'json':
        return Icons.code_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _getFileColor(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return AppTheme.pdfColor;
      case 'txt':
        return AppTheme.editorColor;
      case 'mp3':
      case 'wav':
      case 'm4a':
      case 'flac':
      case 'ogg':
      case 'aac':
      case 'mp4':
        return AppTheme.transcribeColor;
      default:
        return AppTheme.textMuted;
    }
  }

  Future<void> _downloadFile(String path) async {
    try {
      final bytes = await ApiService.downloadFile(path);
      final filename = path.split('/').last;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '📥 Downloaded: $filename (${_formatSize(bytes.length)})',
            ),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Download gagal: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = Responsive.isWide(context);

    return SafeArea(
      child: isWide ? _buildDesktopLayout() : _buildMobileLayout(),
    );
  }

  Widget _buildDesktopLayout() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          _buildBreadcrumb(),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? _buildEmptyState()
                    : _buildGridView(),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return RefreshIndicator(
      onRefresh: () => _loadFolder(_currentPath),
      child: AppScrollbar(
        controller: _mobileScrollController,
        child: CustomScrollView(
          controller: _mobileScrollController,
          physics: const BouncingScrollPhysics(),
          slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _buildHeader(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildBreadcrumb(),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_items.isEmpty)
            SliverFillRemaining(
              child: _buildEmptyState(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildMobileItem(_items[index]),
                  ),
                  childCount: _items.length,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
      ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.browserColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.folder_open_rounded,
            color: AppTheme.browserColor,
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'File Browser',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Jelajahi file di server',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => _loadFolder(_currentPath),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }

  Widget _buildBreadcrumb() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(
        children: [
          if (_currentPath.isNotEmpty)
            InkWell(
              onTap: _goBack,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_back_rounded,
                    size: 18,
                    color: AppTheme.accentBlue,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Kembali',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.accentBlue,
                    ),
                  ),
                  SizedBox(width: 12),
                ],
              ),
            ),
          InkWell(
            onTap: _currentPath.isNotEmpty ? () => _loadFolder('') : null,
            child: Text(
              '📁 root',
              style: TextStyle(
                fontSize: 13,
                color: _currentPath.isNotEmpty
                    ? AppTheme.accentBlue
                    : AppTheme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (_currentPath.isNotEmpty) ...[
            const Text(
              ' / ',
              style: TextStyle(color: AppTheme.textMuted),
            ),
            Expanded(
              child: Text(
                _currentPath,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_off_rounded,
            size: 48,
            color: AppTheme.textMuted,
          ),
          SizedBox(height: 12),
          Text(
            'Folder kosong',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildGridView() {
    return AppScrollbar(
      controller: _gridScrollController,
      child: GridView.builder(
        controller: _gridScrollController,
        physics: const BouncingScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.3,
        ),
        itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        final isDir = item['is_dir'] == true;

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: isDir ? () => _navigateTo(item['path']) : null,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.dividerColor),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isDir ? Icons.folder_rounded : _getFileIcon(item['name']),
                  size: 36,
                  color: isDir
                      ? AppTheme.browserColor
                      : _getFileColor(item['name']),
                ),
                const SizedBox(height: 8),
                Text(
                  item['name'],
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  isDir
                      ? '${item["file_count"] ?? 0} files'
                      : _formatSize(item['size'] ?? 0),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        );
      },
      ),
    );
  }

  Widget _buildMobileItem(Map<String, dynamic> item) {
    final isDir = item['is_dir'] == true;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 4,
        ),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: (isDir ? AppTheme.browserColor : _getFileColor(item['name']))
                .withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isDir ? Icons.folder_rounded : _getFileIcon(item['name']),
            color: isDir ? AppTheme.browserColor : _getFileColor(item['name']),
            size: 20,
          ),
        ),
        title: Text(
          item['name'],
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          isDir
              ? '${item["file_count"] ?? 0} files'
              : _formatSize(item['size'] ?? 0),
          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
        trailing: isDir
            ? const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.textMuted,
              )
            : IconButton(
                onPressed: () => _downloadFile(item['path']),
                icon: const Icon(
                  Icons.download_rounded,
                  size: 20,
                  color: AppTheme.accentCyan,
                ),
                tooltip: 'Download',
              ),
        onTap: isDir ? () => _navigateTo(item['path']) : null,
      ),
    );
  }
}
