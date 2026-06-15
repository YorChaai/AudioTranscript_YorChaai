class FileItem {
  final String name;
  final String path;
  final String label;
  final int size;

  FileItem({
    required this.name,
    required this.path,
    required this.label,
    required this.size,
  });

  factory FileItem.fromJson(Map<String, dynamic> json) {
    return FileItem(
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      label: json['label'] ?? '',
      size: json['size'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'label': label,
      'size': size,
    };
  }
}
