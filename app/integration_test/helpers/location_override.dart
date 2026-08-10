// Test-side wrapper for the app's `LocationTestOverride` seam
// (`app/lib/views/track_vote.dart`), letting the LOCATION_TIME regression
// suite inject a fixed device position instead of driving real OS
// geolocation (which can't be scripted portably across
// emulators/simulators/CI).
//
// Real geocoding of the event's stored coordinates still goes through the
// real Nominatim API server-side (no mocking there, consistent with this
// project's "no mocks" E2E philosophy) — only the simulated *device*
// position is faked here.
import 'package:geolocator/geolocator.dart';
import 'package:pmr_music_room/views/track_vote.dart';

/// A real, geocodable landmark used as the fixed location for every
/// LOCATION_TIME event created by the regression suite. Must match the
/// `location` string typed into `track_vote_create_location_field`.
const String landmarkName = 'Eiffel Tower, Paris';

/// The landmark's real-world coordinates (must be inside the radius
/// configured on the event to be usable as the "inside" position).
const double landmarkLatitude = 48.8584;
const double landmarkLongitude = 2.2945;

/// A coordinate far enough away (central London) to be outside any
/// reasonable event radius, used as the "outside" position.
const double farAwayLatitude = 51.5074;
const double farAwayLongitude = -0.1278;

/// Test-side helper to set/clear the app's `LocationTestOverride`.
class LocationOverrideHelper {
  LocationOverrideHelper._();

  /// Makes `requestCurrentLocation()` report a granted position at the
  /// given coordinates, without touching the real OS/Geolocator APIs.
  static void setPosition(double latitude, double longitude) {
    LocationTestOverride.value = LocationAccessResult(
      LocationAccessStatus.granted,
      Position(
        latitude: latitude,
        longitude: longitude,
        timestamp: DateTime.now(),
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      ),
    );
  }

  /// Simulates the device being unable to determine its position (denied
  /// permission), distinct from `OUTSIDE_RADIUS` — used for the
  /// `LOCATION_UNAVAILABLE` regression flow.
  static void setUnavailable() {
    LocationTestOverride.value = const LocationAccessResult(
      LocationAccessStatus.permissionDenied,
    );
  }

  /// Resets the override so any subsequent code path falls through to the
  /// real `Geolocator` calls. Must be called in test teardown.
  static void clear() {
    LocationTestOverride.value = null;
  }
}
