import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../widgets/tool_card.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/server_status_bar.dart';
import '../config/constants.dart';

/// home screen — landing page yang aman untuk HP kecil, tablet, dan rotasi
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final orientation = media.orientation;
    final isWide = Responsive.isWide(context);
    final isTablet = Responsive.isTablet(context);

    final horizontalPadding = _horizontalPadding(size.width, isWide: isWide);
    final topPadding = isWide ? 40.0 : 20.0;
    final gridSpacing = isWide ? 20.0 : 12.0;
    final crossAxisCount = _getCrossAxisCount(
      width: size.width,
      orientation: orientation,
      isTablet: isTablet,
      isWide: isWide,
    );
    final childAspectRatio = _getChildAspectRatio(
      width: size.width,
      orientation: orientation,
      crossAxisCount: crossAxisCount,
      isWide: isWide,
    );

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    topPadding,
                    horizontalPadding,
                    0,
                  ),
                  child: _HomeHeader(
                    showMobileStatus: !isWide,
                    compact: size.width < 380,
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  24,
                  horizontalPadding,
                  24,
                ),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: gridSpacing,
                    mainAxisSpacing: gridSpacing,
                    childAspectRatio: childAspectRatio,
                  ),
                  delegate: SliverChildListDelegate(
                    [
                      ToolCard(
                        title: 'Transcribe',
                        description:
                            'Upload audio atau video, convert ke MP3, lalu ubah jadi teks.',
                        icon: Icons.mic_rounded,
                        color: AppTheme.transcribeColor,
                        onTap: () => context.go('/transcribe'),
                      ),
                      ToolCard(
                        title: 'Editor',
                        description:
                            'Edit, rapikan, dan review hasil transcript dengan cepat.',
                        icon: Icons.edit_note_rounded,
                        color: AppTheme.editorColor,
                        onTap: () => context.go('/editor'),
                      ),
                      ToolCard(
                        title: 'Convert PDF',
                        description:
                            'Ubah transcript menjadi PDF yang siap dibaca atau dibagikan.',
                        icon: Icons.picture_as_pdf_rounded,
                        color: AppTheme.pdfColor,
                        onTap: () => context.go('/pdf'),
                      ),
                      ToolCard(
                        title: 'History',
                        description:
                            'Lihat riwayat proses transcribe dan hasil yang sudah dibuat.',
                        icon: Icons.history_rounded,
                        color: AppTheme.historyColor,
                        onTap: () => context.go('/history'),
                      ),
                      ToolCard(
                        title: 'AI Summary',
                        description:
                            'Buat ringkasan cerdas dari transkrip dengan bantuan AI lokal.',
                        icon: Icons.auto_awesome_rounded,
                        color: AppTheme.accentCyan,
                        onTap: () => context.go('/summary'),
                      ),
                      ToolCard(
                        title: 'File Browser',
                        description:
                            'Jelajahi file audio, transcript, PDF, dan hasil lainnya.',
                        icon: Icons.folder_open_rounded,
                        color: AppTheme.browserColor,
                        onTap: () => context.go('/browser'),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }

  double _horizontalPadding(double width, {required bool isWide}) {
    if (isWide) return 40;
    if (width < AppConstants.mobileSmallBreakpoint) return 12;
    if (width < AppConstants.mobileLargeBreakpoint) return 16;
    return 20;
  }

  int _getCrossAxisCount({
    required double width,
    required Orientation orientation,
    required bool isTablet,
    required bool isWide,
  }) {
    if (isWide) {
      return width >= Responsive.desktopBreakpoint ? 3 : 2;
    }

    if (isTablet) {
      return orientation == Orientation.landscape ? 3 : 2;
    }

    if (orientation == Orientation.landscape && width >= AppConstants.tabletBreakpoint) {
      return 3;
    }

    if (width < AppConstants.mobileSmallBreakpoint) return 1;
    return 2;
  }

  double _getChildAspectRatio({
    required double width,
    required Orientation orientation,
    required int crossAxisCount,
    required bool isWide,
  }) {
    if (isWide) {
      return crossAxisCount >= 3 ? 1.12 : 1.22;
    }

    if (crossAxisCount == 1) {
      return width < 320 ? 1.85 : 2.1;
    }

    if (orientation == Orientation.landscape) {
      if (crossAxisCount >= 3) return 1.05;
      return 0.98;
    }

    if (width < AppConstants.mobileMediumBreakpoint) return 0.88;
    return 0.96;
  }
}

class _HomeHeader extends StatelessWidget {
  final bool showMobileStatus;
  final bool compact;

  const _HomeHeader({
    required this.showMobileStatus,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showMobileStatus) ...[
          compact ? _buildCompactTopBar() : _buildRegularTopBar(),
          const SizedBox(height: 20),
        ],
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(compact ? 18 : 22),
          decoration: BoxDecoration(
            color: AppTheme.cardDark,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.dividerColor),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.cardDark,
                AppTheme.surfaceDark.withOpacity(0.9),
              ],
            ),
          ),
          child: compact ? const _CompactHero() : const _RegularHero(),
        ),
      ],
    );
  }

  Widget _buildRegularTopBar() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/logoapp.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Audio Yor',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        const ServerStatusBar(),
      ],
    );
  }

  Widget _buildCompactTopBar() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _BrandBadge(),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Audio Yor',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            ServerStatusBar(),
          ],
        ),
      ],
    );
  }
}

class _RegularHero extends StatelessWidget {
  const _RegularHero();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                'Selamat Datang 👋',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        Text(
          'Pilih tool yang ingin digunakan. Layout ini sudah dibuat lebih aman untuk Android kecil dan saat layar diputar.',
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: AppTheme.textSecondary,
          ),
        ),
        SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _InfoChip(
              icon: Icons.phone_android_rounded,
              label: 'Android Friendly',
            ),
            _InfoChip(
              icon: Icons.screen_rotation_rounded,
              label: 'Aman saat rotate',
            ),
            _InfoChip(
              icon: Icons.grid_view_rounded,
              label: 'Grid adaptif',
            ),
          ],
        ),
      ],
    );
  }
}

class _CompactHero extends StatelessWidget {
  const _CompactHero();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Selamat Datang 👋',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Semua menu dibuat lebih rapi untuk HP kecil dan mode landscape.',
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: AppTheme.textSecondary,
          ),
        ),
        SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _InfoChip(icon: Icons.phone_android_rounded, label: 'Android'),
            _InfoChip(icon: Icons.screen_rotation_rounded, label: 'Rotate'),
          ],
        ),
      ],
    );
  }
}

class _BrandBadge extends StatelessWidget {
  const _BrandBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Image.asset(
          'assets/logoapp.png',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark.withOpacity(0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.accentBlue),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
