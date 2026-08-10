import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'dart:async';

import '../network/music.dart';
import '../network/web_socket.dart';
import '../objects/music_track.dart';

const String _meQuery = r'''
  query Me { me }
''';

const String _createRoomMutation = r'''
  mutation CreateRoom($name: String!) {
    createRoom(name: $name) {
      id
      name
    }
  }
''';

const String _playMutation = r'''
  mutation PlayerPlay($roomId: Int!) {
    play(roomId: $roomId) {
      success
      message
      room {
        currentMusicId
        status
      }
    }
  }
''';

const String _playTrackMutation = r'''
  mutation PlayerPlayTrack($roomId: Int!, $index: Int!) {
    playTrack(roomId: $roomId, index: $index) {
      success
      message
      room {
        currentMusicId
        status
      }
    }
  }
''';

const String _addToQueueMutation = r'''
  mutation PlayerAddToQueue($roomId: Int!, $musicId: Int!) {
    addToQueue(roomId: $roomId, musicId: $musicId) {
      success
      message
      room {
        currentMusicId
        status
      }
    }
  }
''';

const String _pauseMutation = r'''
  mutation PlayerPause($roomId: Int!) {
    pause(roomId: $roomId) {
      success
      message
      room {
        currentMusicId
        status
      }
    }
  }
''';

const String _nextMutation = r'''
  mutation PlayerNext($roomId: Int!) {
    next(roomId: $roomId) {
      success
      message
      room {
        currentMusicId
        status
      }
    }
  }
''';

const String _previousMutation = r'''
  mutation PlayerPrevious($roomId: Int!) {
    previous(roomId: $roomId) {
      success
      message
      room {
        currentMusicId
        status
      }
    }
  }
''';

const String _seekMutation = r'''
  mutation PlayerSeek($roomId: Int!, $positionMs: Int!) {
    seek(roomId: $roomId, positionMs: $positionMs) {
      success
      message
      room {
        currentMusicId
        status
      }
    }
  }
''';

const String _setQueueMutation = r'''
  mutation PlayerSetQueue($roomId: Int!, $musicIds: [Int!]!) {
    setQueue(roomId: $roomId, musicIds: $musicIds) {
      success
      message
      room {
        currentMusicId
        status
      }
    }
  }
''';

const String _linkVoteEventMutation = r'''
  mutation PlayerLinkVoteEvent($roomId: Int!, $eventId: Int!) {
    linkVoteEvent(roomId: $roomId, eventId: $eventId) {
      success
      message
      room {
        currentMusicId
        status
        linkedVoteEventId
      }
    }
  }
''';

const String _unlinkVoteEventMutation = r'''
  mutation PlayerUnlinkVoteEvent($roomId: Int!) {
    unlinkVoteEvent(roomId: $roomId) {
      success
      message
    }
  }
''';

const String _leaveRoomMutation = r'''
  mutation LeaveRoom($roomId: Int!) {
    leaveRoom(roomId: $roomId)
  }
''';

const String _deleteRoomMutation = r'''
  mutation DeleteRoom($roomId: Int!) {
    deleteRoom(roomId: $roomId) {
      success
      message
    }
  }
''';

const String _transferHostMutation = r'''
  mutation TransferHost($roomId: Int!, $targetUserId: Int!) {
    transferHost(roomId: $roomId, targetUserId: $targetUserId) {
      success
      message
    }
  }
''';

const String _roomStateSubscription = r'''
  subscription PlayerRoomState($roomId: Int!) {
    roomState(roomId: $roomId) {
      id name hostId memberIds status currentMusicId currentIndex playbackTimeMs playbackUpdatedAtMs
      linkedVoteEventId
      playlist { musicId addedByUserId addedAt }
    }
  }
''';

class MusicPlayerController extends ChangeNotifier {
  static const int _roomSyncToleranceMs = 400;
  final AudioPlayer _player;

  List<MusicTrack> _tracks = [];
  List<MusicTrack> _queue = [];
  MusicTrack? _currentTrack;
  int? _activeRoomId;
  String? _activeRoomName;
  int? _hostId;
  List<int> _memberIds = [];
  int? _currentUserId;
  int? _linkedVoteEventId;
  int _currentIndex = 0;
  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int? _loadedTrackId;
  bool _isLoading = false;
  bool _hasLoadedTracks = false;
  bool _isMuted = false;
  String? _statusMessage;
  StreamSubscription<QueryResult<Object?>>? _roomStateSubscriptionHandle;
  bool _disposed = false;

  MusicPlayerController({AudioPlayer? audioPlayer})
    : _player = audioPlayer ?? AudioPlayer() {
    _player.onPlayerStateChanged.listen((state) {
      if (_disposed) return;
      _playerState = state;
      notifyListeners();
    });

    _player.onPositionChanged.listen((position) {
      if (_disposed) return;
      _position = position;
      notifyListeners();
    });

    _player.onDurationChanged.listen((duration) {
      if (_disposed) return;
      _duration = duration;
      notifyListeners();
    });

    _player.onPlayerComplete.listen((_) => skipNext());
  }

  List<MusicTrack> get tracks => List.unmodifiable(_tracks);
  List<MusicTrack> get queue => List.unmodifiable(_queue);
  MusicTrack? get currentTrack => _currentTrack;
  int? get activeRoomId => _activeRoomId;
  String? get activeRoomName => _activeRoomName;
  bool get hasActiveRoom => _activeRoomId != null;
  List<int> get roomMemberIds => List.unmodifiable(_memberIds);
  int? get currentUserId => _currentUserId;
  int? get linkedVoteEventId => _linkedVoteEventId;
  bool get isRoomHost =>
      hasActiveRoom && _currentUserId != null && _hostId == _currentUserId;

  /// Members of the active room excluding the current user, suitable for
  /// host-transfer target selection.
  List<int> get otherRoomMemberIds =>
      _memberIds.where((id) => id != _currentUserId).toList();
  int get currentIndex => _currentIndex;
  PlayerState get playerState => _playerState;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isLoading => _isLoading;
  bool get isPlaying => _playerState == PlayerState.playing;
  bool get isMuted => _isMuted;
  String? get statusMessage => _statusMessage;
  bool get showPlayer => hasActiveRoom;
  bool get canSkipPrevious => _playbackIndex > 0;
  bool get canSkipNext =>
      _playbackIndex >= 0 && _playbackIndex < _playbackLength - 1;

  int get _playbackLength => _queue.isNotEmpty ? _queue.length : _tracks.length;

  int get _playbackIndex {
    final track = _currentTrack;
    if (track == null || _playbackLength == 0) {
      return -1;
    }
    if (_queue.isNotEmpty) {
      return queueIndex;
    }
    return _currentIndex.clamp(0, _tracks.length - 1);
  }

  Duration get displayDuration {
    if (_duration.inSeconds > 0) {
      return _duration;
    }
    final track = currentTrack;
    if (track == null) return Duration.zero;
    return Duration(seconds: track.duration);
  }

  Future<void> loadTracks() async {
    if (_isLoading || _hasLoadedTracks) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    final result = await MusicService.fetchTracks();
    _tracks = result.tracks;
    _currentIndex = _currentIndex.clamp(0, _tracks.length - 1);
    _statusMessage = result.message;
    _hasLoadedTracks = true;
    _isLoading = false;
    notifyListeners();
  }

  void setActiveRoom({required int roomId, required String roomName}) {
    _activeRoomId = roomId;
    _activeRoomName = roomName;
    _statusMessage = 'Connected to $roomName over socket.';
    _subscribeToRoom(roomId);
    unawaited(_ensureCurrentUserId());
    notifyListeners();
  }

  Future<void> _ensureCurrentUserId() async {
    if (_currentUserId != null) return;
    final client = GraphQLConnection().client?.value;
    if (client == null) return;
    try {
      final result = await client.query(
        QueryOptions(document: gql(_meQuery), fetchPolicy: FetchPolicy.noCache),
      );
      final userId = result.data?['me'];
      if (userId is int) {
        _currentUserId = userId;
        notifyListeners();
      }
    } catch (_) {}
  }

  void _subscribeToRoom(int roomId) {
    _roomStateSubscriptionHandle?.cancel();
    final client = GraphQLConnection().client?.value;
    if (client == null) return;
    _roomStateSubscriptionHandle = client
        .subscribe(
          SubscriptionOptions(
            document: gql(_roomStateSubscription),
            variables: {'roomId': roomId},
            fetchPolicy: FetchPolicy.noCache,
          ),
        )
        .listen(
          (result) async {
            if (result.hasException) {
              _statusMessage = 'Live room synchronization disconnected.';
              notifyListeners();
              return;
            }
            final room = result.data?['roomState'];
            if (room is! Map<String, dynamic>) return;
            _activeRoomName = room['name'] as String? ?? _activeRoomName;
            _hostId = room['hostId'] as int? ?? _hostId;
            _linkedVoteEventId = room['linkedVoteEventId'] as int?;
            final rawMemberIds = room['memberIds'];
            if (rawMemberIds is List) {
              _memberIds = rawMemberIds.whereType<int>().toList();
            }
            if (_currentUserId != null &&
                !_memberIds.contains(_currentUserId)) {
              await _clearActiveRoomState('You are no longer in this room.');
              return;
            }
            final rawQueue = room['playlist'];
            if (rawQueue is List) {
              final ids = rawQueue
                  .whereType<Map<String, dynamic>>()
                  .map((item) => item['musicId'])
                  .whereType<int>()
                  .toList();
              _queue = ids
                  .map(
                    (id) =>
                        _tracks.where((track) => track.id == id).firstOrNull,
                  )
                  .whereType<MusicTrack>()
                  .toList();
            }
            _syncRoomTrack(room);
            final status = room['status'] as String? ?? 'IDLE';
            await _synchronizePlaybackWithRoom(room, status);
            _statusMessage = null;
            notifyListeners();
          },
          onDone: () {
            if (_activeRoomId == roomId) {
              unawaited(_clearActiveRoomState('The room was closed.'));
            }
          },
        );
  }

  /// Clears local room/queue/playback state and cancels the room subscription.
  /// Shared by explicit leave/delete actions and by detection of being
  /// removed from a room (grace-period expiry, host deletion, etc.) or the
  /// room closing while the subscription is still active.
  Future<void> _clearActiveRoomState(String message) async {
    await _roomStateSubscriptionHandle?.cancel();
    _roomStateSubscriptionHandle = null;
    if (_playerState != PlayerState.stopped) {
      await _player.stop();
    }

    _activeRoomId = null;
    _activeRoomName = null;
    _hostId = null;
    _memberIds = [];
    _queue = [];
    _currentTrack = null;
    _loadedTrackId = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _statusMessage = message;
    notifyListeners();
  }

  /// Leaves the currently active room. This is best-effort on the client:
  /// even if the server mutation fails, local room/queue/playback state is
  /// still cleared so the UI doesn't get stuck thinking a room is active.
  Future<bool> leaveRoom() async {
    final roomId = _activeRoomId;
    if (roomId == null) return true;

    var success = true;
    final client = GraphQLConnection().client?.value;
    if (client != null) {
      final result = await client.mutate(
        MutationOptions(
          document: gql(_leaveRoomMutation),
          variables: {'roomId': roomId},
          fetchPolicy: FetchPolicy.noCache,
        ),
      );
      success = !result.hasException && result.data?['leaveRoom'] == true;
    } else {
      success = false;
    }

    await _clearActiveRoomState(
      success
          ? 'You left the room.'
          : 'Left the room locally, but the server could not be notified.',
    );
    return success;
  }

  /// Deletes the currently active room. Only the host may call this
  /// successfully. Local room/queue/playback state is cleared on success
  /// since the room no longer exists for anyone.
  Future<bool> deleteRoom() async {
    final roomId = _activeRoomId;
    if (roomId == null) return true;

    final client = GraphQLConnection().client?.value;
    if (client == null) {
      _statusMessage = 'Realtime connection is not ready.';
      notifyListeners();
      return false;
    }

    final result = await client.mutate(
      MutationOptions(
        document: gql(_deleteRoomMutation),
        variables: {'roomId': roomId},
        fetchPolicy: FetchPolicy.noCache,
      ),
    );

    final data = result.data?['deleteRoom'];
    final success =
        !result.hasException &&
        data is Map<String, dynamic> &&
        data['success'] == true;

    if (!success) {
      final message = data is Map<String, dynamic>
          ? data['message'] as String?
          : null;
      _statusMessage = message ?? 'Could not delete the room.';
      notifyListeners();
      return false;
    }

    await _clearActiveRoomState('Room deleted.');
    return true;
  }

  /// Transfers host ownership of the active room to [targetUserId], who must
  /// currently be a member of the room. Only the current host may succeed.
  Future<bool> transferHost(int targetUserId) async {
    final roomId = _activeRoomId;
    if (roomId == null) return false;

    final client = GraphQLConnection().client?.value;
    if (client == null) {
      _statusMessage = 'Realtime connection is not ready.';
      notifyListeners();
      return false;
    }

    final result = await client.mutate(
      MutationOptions(
        document: gql(_transferHostMutation),
        variables: {'roomId': roomId, 'targetUserId': targetUserId},
        fetchPolicy: FetchPolicy.noCache,
      ),
    );

    final data = result.data?['transferHost'];
    final success =
        !result.hasException &&
        data is Map<String, dynamic> &&
        data['success'] == true;

    if (!success) {
      final message = data is Map<String, dynamic>
          ? data['message'] as String?
          : null;
      _statusMessage = message ?? 'Could not transfer host.';
      notifyListeners();
      return false;
    }

    _statusMessage = 'Host transferred.';
    notifyListeners();
    return true;
  }

  Future<bool> addToQueue(MusicTrack track) async {
    if (_activeRoomId == null) {
      final created = await _createRoom();
      if (!created) return false;
    }
    final success = await _sendRoomAction(
      _addToQueueMutation,
      'addToQueue',
      variables: {'musicId': track.id},
    );
    if (success) {
      // _queue.add(track);
      notifyListeners();
    }
    return success;
  }

  int get queueIndex {
    final track = _currentTrack;
    if (track == null) return -1;
    return _queue.indexWhere((t) => t.id == track.id);
  }

  Future<bool> _setQueue(List<MusicTrack> tracks) async {
    if (_activeRoomId == null) return false;
    final musicIds = tracks.map((t) => t.id).toList();
    final success = await _sendRoomAction(
      _setQueueMutation,
      'setQueue',
      variables: {'musicIds': musicIds},
    );
    if (success) {
      _queue = List.of(tracks);
      notifyListeners();
    }
    return success;
  }

  /// Links the active room to the given Track Vote event and seeds its queue
  /// with the current ranking. The server keeps the queue in sync with future
  /// votes (reordering the upcoming tracks) for as long as the room stays
  /// linked, so every room member observes the live ranking through the
  /// room-state subscription without needing to press this again.
  Future<bool> playVoteRanking(int eventId, List<int> musicIds) async {
    if (musicIds.isEmpty) return false;
    if (!_hasLoadedTracks) await loadTracks();
    if (_activeRoomId == null && !await _createRoom()) return false;
    final success = await _sendRoomAction(
      _linkVoteEventMutation,
      'linkVoteEvent',
      variables: {'eventId': eventId},
    );
    if (success) {
      _linkedVoteEventId = eventId;
      notifyListeners();
    }
    return success;
  }

  /// Detaches the active room from any linked Track Vote event; the queue
  /// stops following future vote changes.
  Future<bool> unlinkVoteEvent() async {
    if (_activeRoomId == null) return false;
    final success = await _sendRoomAction(
      _unlinkVoteEventMutation,
      'unlinkVoteEvent',
    );
    if (success) {
      _linkedVoteEventId = null;
      notifyListeners();
    }
    return success;
  }

  Future<bool> _createRoom() async {
    final client = GraphQLConnection().client?.value;
    if (client == null) {
      _statusMessage = 'Realtime connection is not ready.';
      notifyListeners();
      return false;
    }

    // Get user ID for room name.
    String roomName = 'Room';
    try {
      final meResult = await client.query(
        QueryOptions(document: gql(_meQuery), fetchPolicy: FetchPolicy.noCache),
      );
      final userId = meResult.data?['me'];
      if (userId is int) {
        roomName = 'Room $userId';
      }
    } catch (_) {}

    // Create the room.
    final result = await client.mutate(
      MutationOptions(
        document: gql(_createRoomMutation),
        variables: {'name': roomName},
        fetchPolicy: FetchPolicy.noCache,
      ),
    );

    if (result.hasException) {
      _statusMessage = 'Could not create a room.';
      notifyListeners();
      return false;
    }

    final room = result.data?['createRoom'];
    if (room is! Map<String, dynamic>) {
      _statusMessage = 'Invalid room response.';
      notifyListeners();
      return false;
    }

    final roomId = room['id'] as int?;
    final name = room['name'] as String? ?? roomName;
    if (roomId == null) {
      _statusMessage = 'Room creation failed.';
      notifyListeners();
      return false;
    }

    setActiveRoom(roomId: roomId, roomName: name);
    return true;
  }

  Future<bool> setQueue(List<MusicTrack> tracks) async {
    if (_activeRoomId == null || isRoomHost) {
      final created = await _createRoom();
      if (!created) return false;
    }
    return _setQueue(tracks);
  }

  Future<void> playTrack(int index, {bool syncRoomQueue = true}) async {
    if (index < 0 || index >= _tracks.length) {
      return;
    }
    final track = _tracks[index];

    if (_activeRoomId != null && syncRoomQueue) {
      final queued = await _sendRoomAction(
        _addToQueueMutation,
        'addToQueue',
        variables: {'musicId': track.id},
      );
      if (!queued) {
        return;
      }
      _queue.add(track);
    }

    _currentIndex = index;
    await _startPlayback(track);
  }

  Future<void> playQueueTrack(int index) async {
    if (index < 0 || index >= _queue.length) {
      return;
    }

    if (_activeRoomId != null) {
      // In a room, changing the current track is a host-only action that must
      // go through the server so every member stays in sync; playing locally
      // would let any member desync their playback from the room.
      await _sendRoomAction(
        _playTrackMutation,
        'playTrack',
        variables: {'index': index},
      );
      return;
    }

    final track = _queue[index];
    final catalogIndex = _tracks.indexWhere((t) => t.id == track.id);
    if (catalogIndex >= 0) {
      _currentIndex = catalogIndex;
    }
    await _startPlayback(track);
  }

  Future<void> _startPlayback(MusicTrack track) async {
    _currentTrack = track;
    _position = Duration.zero;
    _duration = Duration.zero;
    _statusMessage = null;
    notifyListeners();

    try {
      await _player.stop();
      await _player.play(UrlSource(track.streamUrl));
      await _player.setVolume(_isMuted ? 0 : 1);
      _loadedTrackId = track.id;
    } catch (_) {
      _loadedTrackId = null;
      _statusMessage =
          'This track could not be played. Check that the server has the MP3 file.';
      notifyListeners();
    }
  }

  /// Toggles muting the local audio output without affecting playback state
  /// (play/pause) or other room members. This is purely a client-side volume
  /// control.
  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    await _player.setVolume(_isMuted ? 0 : 1);
    notifyListeners();
  }

  Future<void> togglePlay() async {
    if (_activeRoomId != null) {
      await _sendRoomAction(
        isPlaying ? _pauseMutation : _playMutation,
        isPlaying ? 'pause' : 'play',
      );
      return;
    }

    if (isPlaying) {
      await _player.pause();
      return;
    }

    if (_position > Duration.zero && _position < displayDuration) {
      await _player.resume();
      return;
    }

    await playTrack(_currentIndex);
  }

  Future<void> seek(double seconds) async {
    if (_activeRoomId != null) {
      await _sendRoomAction(
        _seekMutation,
        'seek',
        variables: {'positionMs': seconds.round() * 1000},
      );
      return;
    }
    await _player.seek(Duration(seconds: seconds.round()));
  }

  Future<void> skipPrevious() async {
    if (!canSkipPrevious) return;

    if (_activeRoomId != null) {
      await _sendRoomAction(_previousMutation, 'previous');
      return;
    }

    if (_queue.isNotEmpty) {
      final previousQueueIndex = queueIndex - 1;
      if (previousQueueIndex < 0) return;
      await playQueueTrack(previousQueueIndex);
      return;
    }

    await playTrack(_currentIndex - 1);
  }

  Future<void> skipNext() async {
    if (!canSkipNext) return;

    if (_activeRoomId != null) {
      await _sendRoomAction(_nextMutation, 'next');
      return;
    }

    if (_queue.isNotEmpty) {
      final nextQueueIndex = queueIndex + 1;
      if (nextQueueIndex >= _queue.length) return;
      await playQueueTrack(nextQueueIndex);
      return;
    }

    await playTrack(_currentIndex + 1);
  }

  Future<bool> _sendRoomAction(
    String mutation,
    String actionName, {
    Map<String, dynamic> variables = const {},
  }) async {
    final roomId = _activeRoomId;
    final client = GraphQLConnection().client?.value;
    if (roomId == null || client == null) {
      _statusMessage = 'Realtime room connection is not ready.';
      notifyListeners();
      return false;
    }

    final result = await client.mutate(
      MutationOptions(
        document: gql(mutation),
        variables: {'roomId': roomId, ...variables},
        fetchPolicy: FetchPolicy.noCache,
      ),
    );

    if (result.hasException) {
      _statusMessage = 'Could not $actionName in ${_activeRoomName ?? 'room'}.';
      notifyListeners();
      return false;
    }

    final data = result.data?[actionName];
    if (data is! Map<String, dynamic> || data['success'] != true) {
      final message = data is Map<String, dynamic>
          ? data['message'] as String?
          : null;
      _statusMessage = message ?? 'Room rejected $actionName.';
      notifyListeners();
      return false;
    }

    _syncRoomTrack(data['room']);
    final room = data['room'];
    if (room is Map<String, dynamic>) {
      final status = room['status'] as String? ?? 'IDLE';
      await _synchronizePlaybackWithRoom(room, status);
    }
    _statusMessage = null;
    notifyListeners();
    return true;
  }

  void _syncRoomTrack(dynamic room) {
    if (room is! Map<String, dynamic>) {
      return;
    }

    final musicId = room['currentMusicId'];
    if (musicId is! int) {
      _currentTrack = null;
      return;
    }

    final catalogIndex = _tracks.indexWhere((track) => track.id == musicId);
    if (catalogIndex >= 0) {
      _currentIndex = catalogIndex;
    }

    final queueIndex = _queue.indexWhere((track) => track.id == musicId);
    if (queueIndex >= 0) {
      _currentTrack = _queue[queueIndex];
    } else if (catalogIndex >= 0) {
      _currentTrack = _tracks[catalogIndex];
    }
  }

  Future<void> _synchronizePlaybackWithRoom(
    Map<String, dynamic> room,
    String status,
  ) async {
    final targetPosition = _resolveRoomTargetPosition(room, status);
    final track = _currentTrack;

    if (status == 'IDLE') {
      if (_playerState != PlayerState.stopped) {
        await _player.stop();
      }
      _loadedTrackId = null;
      _position = Duration.zero;
      return;
    }

    if (track == null || targetPosition == null) return;
    final trackNeedsReload = _loadedTrackId != track.id;

    if (status == 'PAUSED') {
      if (trackNeedsReload || _playerState == PlayerState.stopped) {
        await _startPlayback(track);
      }
      if (_playerState == PlayerState.playing) {
        await _player.pause();
      }
      await _seekIfOutsideTolerance(targetPosition);
      return;
    }

    if (trackNeedsReload || _playerState == PlayerState.stopped) {
      await _startPlayback(track);
    } else if (_playerState == PlayerState.paused) {
      await _player.resume();
    }

    await _seekIfOutsideTolerance(targetPosition);
  }

  Duration? _resolveRoomTargetPosition(
    Map<String, dynamic> room,
    String status,
  ) {
    final playbackTimeMs = (room['playbackTimeMs'] as num?)?.toDouble();
    if (playbackTimeMs == null) return null;

    var targetMs = playbackTimeMs;
    if (status == 'PLAYING') {
      final playbackUpdatedAtMs = (room['playbackUpdatedAtMs'] as num?)
          ?.toDouble();
      if (playbackUpdatedAtMs != null) {
        final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
        targetMs += (nowMs - playbackUpdatedAtMs).clamp(0, double.infinity);
      }
    }

    final track = _currentTrack;
    if (track != null && track.duration > 0) {
      targetMs = targetMs.clamp(0, track.duration * 1000.0);
    } else {
      targetMs = targetMs.clamp(0, double.infinity);
    }

    return Duration(milliseconds: targetMs.round());
  }

  Future<void> _seekIfOutsideTolerance(Duration target) async {
    final driftMs = (_position - target).inMilliseconds.abs();
    if (driftMs <= _roomSyncToleranceMs) return;
    await _player.seek(target);
  }

  @override
  void dispose() {
    _disposed = true;
    _roomStateSubscriptionHandle?.cancel();
    _player.dispose();
    super.dispose();
  }

  void onLogout() {
    unawaited(_roomStateSubscriptionHandle?.cancel());
    _roomStateSubscriptionHandle = null;
    if (_playerState != PlayerState.stopped) {
      unawaited(_player.stop());
    }

    _tracks = [];
    _queue = [];
    _currentTrack = null;
    _activeRoomId = null;
    _activeRoomName = null;
    _hostId = null;
    _memberIds = [];
    _currentUserId = null;
    _currentIndex = 0;
    _playerState = PlayerState.stopped;
    _position = Duration.zero;
    _duration = Duration.zero;
    _loadedTrackId = null;
    _isLoading = false;
    _hasLoadedTracks = false;
    _statusMessage = null;
    notifyListeners();
  }
}
