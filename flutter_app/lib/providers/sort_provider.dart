import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class SortProvider extends ChangeNotifier {
  String _sortBy = 'date';
  Map<String, bool> _sortAscending = {
    'name': true,
    'date': false,
    'type': true,
    'size': false,
  };

  String get sortBy => _sortBy;
  bool get sortAscending => _sortAscending[_sortBy] ?? true;

  SortProvider() {
    _loadPrefs();
  }

  void setSortBy(String value) {
    if (_sortBy == value) return;
    _sortBy = value;
    notifyListeners();
    _savePrefs();
  }

  void setSortOrder(bool ascending) {
    if (_sortAscending[_sortBy] == ascending) return;
    _sortAscending[_sortBy] = ascending;
    notifyListeners();
    _savePrefs();
  }

  Future<void> _loadPrefs() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/app_sort_prefs.json');
      if (file.existsSync()) {
        final content = await file.readAsString();
        final data = jsonDecode(content);
        if (data['sortBy'] != null) _sortBy = data['sortBy'];
        if (data['sortAscending'] != null) {
          _sortAscending = Map<String, bool>.from(data['sortAscending']);
        }
        notifyListeners();
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> _savePrefs() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/app_sort_prefs.json');
      final data = {
        'sortBy': _sortBy,
        'sortAscending': _sortAscending,
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      // ignore
    }
  }
}
