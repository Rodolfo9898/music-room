import 'music_track.dart';

class MusicServiceResult {
  final bool success;
  final String? message;
  final List<MusicTrack> tracks;

  const MusicServiceResult({
    required this.success,
    required this.tracks,
    this.message,
  });
}
