class GenreOption {
  final int id;
  final String name;
  final String description;

  const GenreOption({
    required this.id,
    required this.name,
    required this.description,
  });

  factory GenreOption.fromJson(Map<String, dynamic> json) {
    return GenreOption(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Genre ${json['id']}',
      description: json['description'] as String? ?? '',
    );
  }
}
