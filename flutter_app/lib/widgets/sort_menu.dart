import 'package:flutter/material.dart';
import '../config/theme.dart';

class SortMenu extends StatelessWidget {
  final String sortBy;
  final bool sortAscending;
  final Function(String) onSortByChanged;
  final Function(bool) onSortOrderChanged;

  const SortMenu({
    super.key,
    required this.sortBy,
    required this.sortAscending,
    required this.onSortByChanged,
    required this.onSortOrderChanged,
  });

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      alignmentOffset: const Offset(0, 8),
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(AppTheme.cardDark),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        elevation: const WidgetStatePropertyAll(8),
      ),
      builder: (context, controller, child) {
        return IconButton(
          icon: const Icon(Icons.sort, color: AppTheme.textSecondary),
          tooltip: 'Urutkan File',
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
        );
      },
      menuChildren: [
        _buildSortMenuItem('name', 'Name'),
        _buildSortMenuItem('date', 'Date modified'),
        _buildSortMenuItem('type', 'Type'),
        _buildSortMenuItem('size', 'Size'),
        const Divider(color: AppTheme.dividerColor, height: 16),
        MenuItemButton(
          closeOnActivate: false,
          leadingIcon: Icon(
            sortAscending ? Icons.circle : null,
            size: 8,
            color: sortAscending ? AppTheme.accentBlue : Colors.transparent,
          ),
          onPressed: () => onSortOrderChanged(true),
          child: const Text('Ascending', style: TextStyle(color: Colors.white)),
        ),
        MenuItemButton(
          closeOnActivate: false,
          leadingIcon: Icon(
            !sortAscending ? Icons.circle : null,
            size: 8,
            color: !sortAscending ? AppTheme.accentBlue : Colors.transparent,
          ),
          onPressed: () => onSortOrderChanged(false),
          child: const Text('Descending', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildSortMenuItem(String value, String label) {
    final isSelected = sortBy == value;
    return MenuItemButton(
      closeOnActivate: false,
      leadingIcon: Icon(
        isSelected ? Icons.circle : null,
        size: 8,
        color: isSelected ? AppTheme.accentBlue : Colors.transparent,
      ),
      onPressed: () => onSortByChanged(value),
      child: Text(label, style: const TextStyle(color: Colors.white)),
    );
  }
}
