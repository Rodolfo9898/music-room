import '../config/constants.dart';

const String _musicUrl = '${Constants.httpServer}/musics';

class MusicTrack {
  final int id;
  final String title;
  final int artistId;
  final int genreId;
  final int duration;
  final String streamUrl;
  final String? artistName;

  const MusicTrack({
    required this.id,
    required this.title,
    required this.artistId,
    required this.genreId,
    required this.duration,
    required this.streamUrl,
    this.artistName,
  });

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as int;
    final streamUrl = json['streamUrl'] as String?;
    return MusicTrack(
      id: id,
      title: json['title'] as String? ?? 'Untitled track',
      artistId: json['artist_id'] as int? ?? 0,
      genreId: json['genre_id'] as int? ?? 0,
      duration: json['duration'] as int? ?? 0,
      streamUrl: _absoluteStreamUrl(streamUrl, id),
      artistName: json['artist_name'] as String?,
    );
  }
}

String _absoluteStreamUrl(String? value, int id) {
  if (value == null || value.isEmpty) {
    return '$_musicUrl/$id/stream';
  }
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return value;
  }
  if (value.startsWith('/')) {
    return '${Constants.httpServer}$value';
  }
  return '${Constants.httpServer}/$value';
}
