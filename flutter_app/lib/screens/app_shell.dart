import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../config/theme.dart';
import '../widgets/server_status_bar.dart';

class _NavItem {
  final IconData icon;
  final String label;
  final String subtitle;
  const _NavItem(
      {required this.icon, required this.label, required this.subtitle});
}

class AppShell extends StatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _sidebarExpanded = true;

  final List<_NavItem> _navItems = const [
    _NavItem(
        icon: Icons.home_rounded, label: 'Home', subtitle: 'Ringkasan fitur'),
    _NavItem(
        icon: Icons.mic_rounded,
        label: 'Transcribe',
        subtitle: 'Audio & video ke teks'),
    _NavItem(
        icon: Icons.edit_note_rounded,
        label: 'Editor',
        subtitle: 'Edit hasil transcript'),
    _NavItem(
        icon: Icons.picture_as_pdf_rounded,
        label: 'PDF',
        subtitle: 'Convert & merge PDF'),
    _NavItem(
        icon: Icons.auto_awesome_rounded,
        label: 'Summary',
        subtitle: 'Ringkas hasil AI'),
    _NavItem(
        icon: Icons.history_rounded,
        label: 'History',
        subtitle: 'Riwayat proses'),
    _NavItem(
        icon: Icons.folder_rounded, label: 'Browse', subtitle: 'File server'),
  ];

  int get _currentIndex {
    final location = GoRouterState.of(context).uri.path;
    if (location == '/') return 0;
    if (location.startsWith('/transcribe')) return 1;
    if (location.startsWith('/editor')) return 2;
    if (location.startsWith('/pdf')) return 3;
    if (location.startsWith('/summary')) return 4;
    if (location.startsWith('/history')) return 5;
    if (location.startsWith('/browser')) return 6;
    return 0;
  }

  void _onNavigate(int index) {
    if (_currentIndex == index) return;
    switch (index) {
      case 0:
        context.go('/');
        break;
      case 1:
        context.go('/transcribe');
        break;
      case 2:
        context.go('/editor');
        break;
      case 3:
        context.go('/pdf');
        break;
      case 4:
        context.go('/summary');
        break;
      case 5:
        context.go('/history');
        break;
      case 6:
        context.go('/browser');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width >= 900;
    final isTablet = size.width >= 600 && size.width < 900;

    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: Row(
        children: [
          if (isDesktop || isTablet) _buildSidebar(isTablet),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: (isDesktop || isTablet)
                        ? const BorderRadius.only(
                            topLeft: Radius.circular(24),
                            bottomLeft: Radius.circular(24),
                          )
                        : BorderRadius.zero,
                    child: Container(
                      color: AppTheme.surfaceDark,
                      child: widget.child,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: (!isDesktop && !isTablet) ? _buildBottomNav() : null,
    );
  }

  Widget _buildSidebar(bool isTablet) {
    final width = isTablet ? 80.0 : (_sidebarExpanded ? 280.0 : 80.0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: width,
      child: ClipRect(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: SizedBox(
            width: width,
            child: Column(
              children: [
                const SizedBox(height: 16),
                if (!isTablet)
                  Align(
                    alignment: _sidebarExpanded ? Alignment.centerRight : Alignment.center,
                    child: Padding(
                      padding: EdgeInsets.only(right: _sidebarExpanded ? 16 : 0, bottom: 8),
                      child: IconButton(
                        icon: Icon(
                          _sidebarExpanded ? Icons.menu_open_rounded : Icons.menu_rounded,
                          color: AppTheme.textSecondary,
                        ),
                        tooltip: _sidebarExpanded ? 'Sembunyikan Sidebar' : 'Tampilkan Sidebar',
                        onPressed: () => setState(() => _sidebarExpanded = !_sidebarExpanded),
                      ),
                    ),
                  ),
                _buildLogo(isTablet),
                const SizedBox(height: 24),
                Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _navItems.length,
              itemBuilder: (context, index) {
                return _buildNavItem(index, isTablet);
              },
            ),
          ),
          if (!isTablet && _sidebarExpanded)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: ServerStatusBar(),
            ),
        ],
      ),
     ),
    ),
   ),
  );
 }

 Widget _buildLogo(bool isTablet) {
    final isCompact = isTablet || !_sidebarExpanded;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 0 : 24),
      child: Row(
        mainAxisAlignment:
            isCompact ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
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
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
            ),
          ),
          if (!isCompact) ...[
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Audio Yor',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Audio to Text',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, bool isTablet) {
    final item = _navItems[index];
    final isSelected = _currentIndex == index;
    final isCompact = isTablet || !_sidebarExpanded;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _onNavigate(index),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 0 : 16,
            vertical: isCompact ? 16 : 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isSelected
                ? AppTheme.accentBlue.withOpacity(0.15)
                : Colors.transparent,
            border: Border.all(
              color: isSelected
                  ? AppTheme.accentBlue.withOpacity(0.3)
                  : Colors.transparent,
            ),
          ),
          child: isCompact
              ? Center(
                  child: Icon(item.icon,
                      color: isSelected ? AppTheme.accentBlue : Colors.white60,
                      size: 26),
                )
              : Row(
                  children: [
                    Icon(item.icon,
                        color:
                            isSelected ? AppTheme.accentBlue : Colors.white60,
                        size: 24),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.label,
                            style: TextStyle(
                              color: isSelected
                                  ? AppTheme.accentBlue
                                  : Colors.white,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.subtitle,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: _navItems.asMap().entries.map((e) {
              final isSelected = _currentIndex == e.key;
              return Expanded(
                child: InkWell(
                  onTap: () => _onNavigate(e.key),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          e.value.icon,
                          color:
                              isSelected ? AppTheme.accentBlue : Colors.white54,
                          size: 20,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          e.value.label,
                          style: TextStyle(
                            color: isSelected
                                ? AppTheme.accentBlue
                                : Colors.white54,
                            fontSize: 9,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
