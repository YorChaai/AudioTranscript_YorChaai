class JobStatus {
  final String id;
  final String type;
  final String inputFile;
  final String status;
  final double progress;
  final String? error;
  final String? outputFile;
  final String createdAt;
  final String updatedAt;

  JobStatus({
    required this.id,
    required this.type,
    required this.inputFile,
    required this.status,
    required this.progress,
    this.error,
    this.outputFile,
    required this.createdAt,
    required this.updatedAt,
  });

  factory JobStatus.fromJson(Map<String, dynamic> json) {
    return JobStatus(
      id: json['id'] ?? '',
      type: json['type'] ?? '',
      inputFile: (json['input_file'] ?? json['audio_file'] ?? json['source_file'] ?? '').toString(),
      status: json['status'] ?? '',
      progress: (json['progress'] ?? 0).toDouble(),
      error: json['error'],
      outputFile: json['output_file'],
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'input_file': inputFile,
      'status': status,
      'progress': progress,
      'error': error,
      'output_file': outputFile,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  String get readableStatus {
    switch (status) {
      case 'pending':
        return 'Menunggu antrean...';
      case 'converting':
        return 'Mengonversi video ke MP3...';
      case 'processing':
        return 'Sedang memproses...';
      case 'transcribing':
        return 'Mentranskripsi audio...';
      case 'loading_model':
        return 'Memuat model AI...';
      case 'generating_summary':
        return 'Membuat ringkasan...';
      case 'waiting_ollama':
        return 'Menunggu AI (Ollama)...';
      case 'saving':
        return 'Menyimpan hasil...';
      case 'completed':
        return '✅ Selesai!';
      case 'failed':
      case 'error':
        return '❌ Gagal';
      case 'cancelled':
        return '🛑 Dibatalkan';
      default:
        return status;
    }
  }
}
