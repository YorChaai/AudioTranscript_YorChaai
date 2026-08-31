import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/theme_provider.dart';
import '../providers/language_provider.dart';
import '../theme/app_theme_modes.dart';

class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const SettingsDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProv = context.watch<ThemeProvider>();
    final langProv = context.watch<LanguageProvider>();
    final activeThemeKey = themeProv.currentThemeKey;
    final activeLang = langProv.languageCode;

    return Dialog(
      backgroundColor: AppTheme.cardDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Dialog Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accentBlue.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.tune_rounded, color: AppTheme.accentCyan, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      langProv.tr('settings'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(height: 1, color: AppTheme.dividerColor),
              const SizedBox(height: 16),

              Expanded(
                child: ListView(
                  children: [
                    // Section 1: Language Selection
                    _buildSectionHeader(
                      icon: Icons.language_rounded,
                      title: langProv.tr('language'),
                      subtitle: 'Pilih bahasa antarmuka aplikasi / Select interface language',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildLanguageCard(
                            title: 'Bahasa Indonesia',
                            subtitle: 'Bahasa Indonesia',
                            code: 'id',
                            isActive: activeLang == 'id',
                            onTap: () => langProv.setLanguage('id'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildLanguageCard(
                            title: 'English',
                            subtitle: 'Full English Mode',
                            code: 'en',
                            isActive: activeLang == 'en',
                            onTap: () => langProv.setLanguage('en'),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // Section 2: Theme Selection (Mathall Reference Architecture)
                    _buildSectionHeader(
                      icon: Icons.palette_rounded,
                      title: langProv.tr('theme'),
                      subtitle: 'Pilih skema warna & gaya visual aplikasi',
                    ),
                    const SizedBox(height: 12),

                    ...AppThemePresets.all.map((preset) {
                      final isSelected = activeThemeKey == preset.key;
                      return _buildThemeItem(
                        preset: preset,
                        isSelected: isSelected,
                        onTap: () => themeProv.setTheme(preset.key),
                      );
                    }),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: Text(langProv.tr('close')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({required IconData icon, required String title, required String subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppTheme.accentCyan, size: 18),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildLanguageCard({
    required String title,
    required String subtitle,
    required String code,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.accentBlue.withOpacity(0.15) : AppTheme.backgroundDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? AppTheme.accentBlue : AppTheme.dividerColor,
            width: isActive ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isActive ? AppTheme.accentBlue : AppTheme.cardDark,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  code.toUpperCase(),
                  style: TextStyle(
                    color: isActive ? Colors.white : AppTheme.textSecondary,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                  ),
                ],
              ),
            ),
            if (isActive)
              const Icon(Icons.check_circle_rounded, color: AppTheme.accentCyan, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeItem({
    required ThemePreset preset,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.accentBlue.withOpacity(0.12) : AppTheme.backgroundDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppTheme.accentBlue : AppTheme.dividerColor,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // Swatches (from Mathall theme design)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: preset.previewSwatches.map((color) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 1),
                    ),
                  ),
                )).toList(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.displayName,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      preset.description,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_circle_rounded, color: AppTheme.accentCyan, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
