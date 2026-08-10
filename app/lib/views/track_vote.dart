import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:pmr_music_room/views/utils/scaffold.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import '../network/music.dart';
import '../network/web_socket.dart';
import '../objects/music_track.dart';
import '../objects/vote_event.dart';
import '../objects/vote_member.dart';
import '../state/music_player_controller.dart';

part 'track_vote_list.dart';
part 'track_vote_detail.dart';
part 'create_vote_event.dart';

const _eventFields = r'''
  id name owner_id is_public vote_policy latitude longitude radius_meters
  starts_at ends_at version can_vote can_vote_reason invited_user_ids user_vote_music_ids
  members { id email display_name }
  tracks { music_id title artist_name duration vote_count suggested_by }
''';

const _eventsQuery =
    'query VoteEvents(\$latitude: Float, \$longitude: Float) { voteEvents(latitude: \$latitude, longitude: \$longitude) { $_eventFields } }';
const _searchEventsQuery =
    'query SearchVoteEvents(\$query: String!) { searchVoteEvents(query: \$query) { $_eventFields } }';
const _eventSubscription = r'''
  subscription VoteEventLive($eventId: Int!, $latitude: Float, $longitude: Float) {
    voteEventUpdated(eventId: $eventId, latitude: $latitude, longitude: $longitude) { EVENT_FIELDS }
  }
''';
const _createMutation = r'''
  mutation CreateVoteEvent($name: String!, $isPublic: Boolean!, $votePolicy: VotePolicy!, $location: String, $radiusMeters: Int, $startsAt: String, $endsAt: String) {
    createVoteEvent(name: $name, isPublic: $isPublic, votePolicy: $votePolicy, location: $location, radiusMeters: $radiusMeters, startsAt: $startsAt, endsAt: $endsAt) { EVENT_FIELDS }
  }
''';
const _suggestMutation = r'''
  mutation SuggestVoteTrack($eventId: Int!, $musicId: Int!, $latitude: Float, $longitude: Float) {
    suggestVoteTrack(eventId: $eventId, musicId: $musicId, latitude: $latitude, longitude: $longitude) { EVENT_FIELDS }
  }
''';
const _voteMutation = r'''
  mutation VoteForTrack($eventId: Int!, $musicId: Int!, $latitude: Float, $longitude: Float) {
    voteForTrack(eventId: $eventId, musicId: $musicId, latitude: $latitude, longitude: $longitude) { EVENT_FIELDS }
  }
''';
const _inviteMutation = r'''
  mutation InviteVoteUser($eventId: Int!, $email: String!) {
    inviteVoteEventUser(eventId: $eventId, email: $email) { EVENT_FIELDS }
  }
''';
const _removeMemberMutation = r'''
  mutation RemoveVoteMember($eventId: Int!, $userId: Int!) {
    removeVoteEventUser(eventId: $eventId, userId: $userId) { EVENT_FIELDS }
  }
''';
const _deleteEventMutation = r'''
  mutation DeleteVoteEvent($eventId: Int!) {
    deleteVoteEvent(eventId: $eventId)
  }
''';

String _fields(String document) =>
    document.replaceAll('EVENT_FIELDS', _eventFields);

class VoteEventService {
  static Future<List<VoteEvent>> search(String query) async {
    final client = GraphQLConnection().client?.value;
    if (client == null) return [];

    try {
      final result = await client.query(
        QueryOptions(
          document: gql(_searchEventsQuery),
          variables: {'query': query},
          fetchPolicy: FetchPolicy.noCache,
        ),
      );
      final data = result.data?['searchVoteEvents'];
      if (result.hasException || data is! List) return [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(VoteEvent.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<VoteEvent>> fetchVoteEvents({
    double? latitude,
    double? longitude,
  }) async {
    final client = GraphQLConnection().client?.value;
    if (client == null) return [];

    try {
      final result = await client.query(
        QueryOptions(
          document: gql(_eventsQuery),
          variables: {'latitude': latitude, 'longitude': longitude},
          fetchPolicy: FetchPolicy.noCache,
        ),
      );
      final data = result.data?['voteEvents'];
      if (result.hasException || data is! List) return [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(VoteEvent.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<SuggestTrackResult> suggestTrack(
    VoteEvent event,
    int musicId,
  ) async {
    final client = GraphQLConnection().client?.value;
    if (client == null) {
      return const SuggestTrackResult(
        SuggestTrackOutcome.serverError,
        'Realtime connection unavailable',
      );
    }

    double? latitude;
    double? longitude;
    if (event.votePolicy == 'LOCATION_TIME') {
      final location = await requestCurrentLocation();
      if (!location.isGranted) {
        return SuggestTrackResult(
          SuggestTrackOutcome.locationUnavailable,
          locationAccessMessage(location.status),
        );
      }
      latitude = location.position?.latitude;
      longitude = location.position?.longitude;
    }

    try {
      final result = await client.mutate(
        MutationOptions(
          document: gql(_fields(_suggestMutation)),
          variables: {
            'eventId': event.id,
            'musicId': musicId,
            'latitude': latitude,
            'longitude': longitude,
          },
        ),
      );
      if (result.hasException) {
        return SuggestTrackResult(
          SuggestTrackOutcome.serverError,
          result.exception.toString(),
        );
      }
      return const SuggestTrackResult(SuggestTrackOutcome.success);
    } catch (e) {
      return SuggestTrackResult(SuggestTrackOutcome.serverError, e.toString());
    }
  }
}

enum SuggestTrackOutcome { success, locationUnavailable, serverError }

class SuggestTrackResult {
  final SuggestTrackOutcome outcome;
  final String? message;
  const SuggestTrackResult(this.outcome, [this.message]);
  bool get isSuccess => outcome == SuggestTrackOutcome.success;
}

enum LocationAccessStatus {
  granted,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
}

class LocationAccessResult {
  final LocationAccessStatus status;
  final Position? position;
  const LocationAccessResult(this.status, [this.position]);
  bool get isGranted => status == LocationAccessStatus.granted;
}

// Maps a LocationAccessStatus to a precise, user-facing message explaining
// why location access wasn't available and what to do about it.
String locationAccessMessage(LocationAccessStatus status) {
  switch (status) {
    case LocationAccessStatus.granted:
      return '';
    case LocationAccessStatus.serviceDisabled:
      return 'Location services are turned off. Enable them to vote or suggest tracks for this event.';
    case LocationAccessStatus.permissionDenied:
      return 'Location permission is required to vote or suggest tracks for this event.';
    case LocationAccessStatus.permissionDeniedForever:
      return 'Location permission was permanently denied. Enable it from system settings to vote or suggest tracks for this event.';
  }
}

// Test-only seam letting integration tests inject a fake device location
// instead of driving the real OS/Geolocator APIs (which can't be scripted
// portably across emulators/simulators/CI). Always `null` in production and
// in every non-test code path: `requestCurrentLocation()` falls through to
// the real `Geolocator` calls unless a test explicitly sets this field, so
// behavior for real users (and any other test) is provably unchanged.
class LocationTestOverride {
  LocationTestOverride._();

  /// When non-null, `requestCurrentLocation()` returns this instead of
  /// querying the OS. Set/cleared only by integration tests; must be reset
  /// to `null` in test teardown.
  static LocationAccessResult? value;
}

// Asks the OS for location access (service check + permission prompt) and
// returns a precise status so callers can show the right message instead of
// silently sending null coordinates to the server.
Future<LocationAccessResult> requestCurrentLocation() async {
  final override = LocationTestOverride.value;
  if (override != null) return override;

  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    return const LocationAccessResult(LocationAccessStatus.serviceDisabled);
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.deniedForever) {
    return const LocationAccessResult(
      LocationAccessStatus.permissionDeniedForever,
    );
  }
  if (permission == LocationPermission.denied) {
    return const LocationAccessResult(LocationAccessStatus.permissionDenied);
  }
  final position = await Geolocator.getCurrentPosition();
  return LocationAccessResult(LocationAccessStatus.granted, position);
}
