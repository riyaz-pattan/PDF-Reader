class PdfDocument {
  final String path;
  final String name;
  final int size;
  final DateTime lastRead;
  final int lastPage;
  final int totalPages;
  final bool isFavorite;

  PdfDocument({
    required this.path,
    required this.name,
    required this.size,
    required this.lastRead,
    this.lastPage = 0,
    this.totalPages = 0,
    this.isFavorite = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'path': path,
      'name': name,
      'size': size,
      'lastRead': lastRead.millisecondsSinceEpoch,
      'lastPage': lastPage,
      'totalPages': totalPages,
      'isFavorite': isFavorite ? 1 : 0,
    };
  }

  factory PdfDocument.fromMap(Map<String, dynamic> map) {
    return PdfDocument(
      path: map['path'],
      name: map['name'],
      size: map['size'],
      lastRead: DateTime.fromMillisecondsSinceEpoch(map['lastRead']),
      lastPage: map['lastPage'],
      totalPages: map['totalPages'],
      isFavorite: map['isFavorite'] == 1,
    );
  }

  PdfDocument copyWith({
    String? path,
    String? name,
    int? size,
    DateTime? lastRead,
    int? lastPage,
    int? totalPages,
    bool? isFavorite,
  }) {
    return PdfDocument(
      path: path ?? this.path,
      name: name ?? this.name,
      size: size ?? this.size,
      lastRead: lastRead ?? this.lastRead,
      lastPage: lastPage ?? this.lastPage,
      totalPages: totalPages ?? this.totalPages,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}
