// E2E regression suite covering the Track Vote **LOCATION_TIME** policy's
// full time-window x location matrix (subject V.2.1), crossed with
// visibility (public/private), plus the LOCATION_UNAVAILABLE case.
//
// This complements `track_vote_lifecycle_test.dart` (which only does a
// dropdown "smoke check" of LOCATION_TIME, deliberately avoiding real
// geolocation) by actually creating LOCATION_TIME events and asserting the
// exact vote eligibility reason for every inside/outside x time/location
// combination.
//
// The event's own stored coordinates are still resolved via the real
// Nominatim geocoding API server-side (no mocking there) using a fixed,
// real landmark (see `helpers/location_override.dart`). Only the
// *simulated device position* is faked, via the app's test-only
// `LocationTestOverride` seam (`app/lib/views/track_vote.dart`) — this
// avoids needing OS-level GPS mocking (`adb emu geo fix` / simulator
// location simulation), which is platform-specific and not portable across
// CI/devices.
//
// Time windows need no such seam: they're driven through the real
// `track_vote_create_starts_at_tile` / `_ends_at_tile` date/time pickers,
// computed relative to `DateTime.now()`.
//
// Only one account (the owner) is needed for this suite — the config
// matrix below all asserts the *owner's* own vote eligibility, which is
// enough to exercise every VoteEligibilityReason branch that depends on
// time/location (visibility/invite-specific reasons are covered in
// `track_vote_visibility_policy_regression_test.dart`).
//
// Run with e.g.:
//   flutter test integration_test/track_vote_location_time_regression_test.dart \
//     -d <device-id> \
//     --dart-define=MUSIC_ROOM_SERVER=10.0.2.2:8080 \
//     --dart-define=E2E_TEST_EMAIL=music-room@vanderlynden.eu \
//     --dart-define=E2E_IMAP_PASSWORD=*** \
//     --dart-define=E2E_TEST_PASSWORD=SomeStrongPass!1
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pmr_music_room/main.dart';
import 'package:pmr_music_room/views/login.dart';

import 'helpers/location_override.dart';
import 'helpers/mail_client.dart';
import 'helpers/test_env.dart';
import 'helpers/track_vote_flow_helpers.dart';

// Seeded catalog track ids (see 002-seed-catalog.sql).
const _heyBrotherId = 2;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'LOCATION_TIME regression matrix: public/private x inside/outside time x inside/outside location',
    (tester) async {
      TestEnv.ensureConfigured();

      final flow = TrackVoteFlow(tester);
      final runMarker = DateTime.now().millisecondsSinceEpoch.toString();
      final ownerDisplayName = 'E2ELocTimeOwner$runMarker';

      final ownerMail = MailClientHelper(
        email: TestEnv.testEmail,
        password: TestEnv.imapPassword,
        imapHost: TestEnv.imapHost,
        imapPort: TestEnv.imapPort,
      );

      // ------------------------------------------------------------------
      // Setup: provision the owner account once.
      // ------------------------------------------------------------------
      await ownerMail.purgeExistingConfirmationEmails();
      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.byType(LoginScreen), findsOneWidget);

      await flow.signup(TestEnv.testEmail, ownerDisplayName, TestEnv.testPassword);
      await flow.confirmEmail(ownerMail);
      await flow.signin(TestEnv.testEmail, TestEnv.testPassword);

      final now = DateTime.now();
      final insideStart = now.subtract(const Duration(minutes: 30));
      final insideEnd = now.add(const Duration(minutes: 30));
      final pastStart = now.subtract(const Duration(hours: 2));
      final pastEnd = now.subtract(const Duration(hours: 1));
      final futureStart = now.add(const Duration(hours: 1));
      final futureEnd = now.add(const Duration(hours: 2));

      Future<void> runFlow({
        required String name,
        required bool isPublic,
        required DateTime startsAt,
        required DateTime endsAt,
        required bool insideLocation,
        required String expectAllowedOrReasonSubstring,
        bool expectAllowed = false,
      }) async {
        LocationOverrideHelper.setPosition(
          insideLocation ? landmarkLatitude : farAwayLatitude,
          insideLocation ? landmarkLongitude : farAwayLongitude,
        );

        await flow.openTrackVote();
        await flow.createEvent(
          name: name,
          isPublic: isPublic,
          policy: 'LOCATION_TIME',
          location: landmarkName,
          radiusMeters: 300,
          startsAt: startsAt,
          endsAt: endsAt,
        );
        await flow.openEvent(name);
        // Give the detail screen time to resolve the (overridden) device
        // location and re-subscribe with it before asserting eligibility.
        await tester.pumpAndSettle(const Duration(seconds: 2));

        if (expectAllowed) {
          expect(
            find.byKey(const Key('track_vote_suggest_button')),
            findsOneWidget,
            reason: '$name: expected voting to be allowed.',
          );
          await flow.suggestTrack('Hey Brother', _heyBrotherId);
          await flow.voteFor(_heyBrotherId);
          expect(find.textContaining('1 votes'), findsOneWidget);
        } else {
          expect(
            find.textContaining(expectAllowedOrReasonSubstring),
            findsOneWidget,
            reason: '$name: expected denial reason not shown.',
          );
          expect(
            find.byKey(const Key('track_vote_suggest_button')),
            findsNothing,
            reason: '$name: voting must be blocked.',
          );
        }
        await flow.back();
        LocationOverrideHelper.clear();
      }

      // ------------------------------------------------------------------
      // Flow 5: PUBLIC, inside time, inside location -> allowed.
      // ------------------------------------------------------------------
      await runFlow(
        name: 'LocTime Public InIn $runMarker',
        isPublic: true,
        startsAt: insideStart,
        endsAt: insideEnd,
        insideLocation: true,
        expectAllowedOrReasonSubstring: '',
        expectAllowed: true,
      );

      // ------------------------------------------------------------------
      // Flow 6: PUBLIC, inside time, outside location -> OUTSIDE_RADIUS.
      // ------------------------------------------------------------------
      await runFlow(
        name: 'LocTime Public InOut $runMarker',
        isPublic: true,
        startsAt: insideStart,
        endsAt: insideEnd,
        insideLocation: false,
        expectAllowedOrReasonSubstring: "too far from the event's location",
      );

      // ------------------------------------------------------------------
      // Flow 7: PUBLIC, outside time (past), inside location ->
      // OUTSIDE_TIME_WINDOW.
      // ------------------------------------------------------------------
      await runFlow(
        name: 'LocTime Public PastIn $runMarker',
        isPublic: true,
        startsAt: pastStart,
        endsAt: pastEnd,
        insideLocation: true,
        expectAllowedOrReasonSubstring: 'voting window for this event is not currently open',
      );

      // ------------------------------------------------------------------
      // Flow 8: PUBLIC, outside time (future), inside location ->
      // OUTSIDE_TIME_WINDOW.
      // ------------------------------------------------------------------
      await runFlow(
        name: 'LocTime Public FutureIn $runMarker',
        isPublic: true,
        startsAt: futureStart,
        endsAt: futureEnd,
        insideLocation: true,
        expectAllowedOrReasonSubstring: 'voting window for this event is not currently open',
      );

      // ------------------------------------------------------------------
      // Flow 9: PRIVATE, inside time, inside location -> allowed (owner).
      // ------------------------------------------------------------------
      await runFlow(
        name: 'LocTime Private InIn $runMarker',
        isPublic: false,
        startsAt: insideStart,
        endsAt: insideEnd,
        insideLocation: true,
        expectAllowedOrReasonSubstring: '',
        expectAllowed: true,
      );

      // ------------------------------------------------------------------
      // Flow 10: PRIVATE, inside time, outside location -> OUTSIDE_RADIUS.
      // ------------------------------------------------------------------
      await runFlow(
        name: 'LocTime Private InOut $runMarker',
        isPublic: false,
        startsAt: insideStart,
        endsAt: insideEnd,
        insideLocation: false,
        expectAllowedOrReasonSubstring: "too far from the event's location",
      );

      // ------------------------------------------------------------------
      // Flow 11: PRIVATE, outside time (past), inside location ->
      // OUTSIDE_TIME_WINDOW.
      // ------------------------------------------------------------------
      await runFlow(
        name: 'LocTime Private PastIn $runMarker',
        isPublic: false,
        startsAt: pastStart,
        endsAt: pastEnd,
        insideLocation: true,
        expectAllowedOrReasonSubstring: 'voting window for this event is not currently open',
      );

      // ------------------------------------------------------------------
      // Flow 12: PRIVATE, outside time (future), inside location ->
      // OUTSIDE_TIME_WINDOW.
      // ------------------------------------------------------------------
      await runFlow(
        name: 'LocTime Private FutureIn $runMarker',
        isPublic: false,
        startsAt: futureStart,
        endsAt: futureEnd,
        insideLocation: true,
        expectAllowedOrReasonSubstring: 'voting window for this event is not currently open',
      );

      // ------------------------------------------------------------------
      // Flow 16: device location unavailable during the time window ->
      // LOCATION_UNAVAILABLE (distinct from OUTSIDE_RADIUS).
      // ------------------------------------------------------------------
      LocationOverrideHelper.setUnavailable();
      final unavailableName = 'LocTime Unavailable $runMarker';
      await flow.openTrackVote();
      await flow.createEvent(
        name: unavailableName,
        isPublic: true,
        policy: 'LOCATION_TIME',
        location: landmarkName,
        radiusMeters: 300,
        startsAt: insideStart,
        endsAt: insideEnd,
      );
      await flow.openEvent(unavailableName);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(
        find.textContaining('location could not be determined'),
        findsOneWidget,
        reason: 'LOCATION_UNAVAILABLE reason not shown when GPS is denied/unavailable.',
      );
      expect(
        find.byKey(const Key('track_vote_suggest_button')),
        findsNothing,
      );
      await flow.back();
      LocationOverrideHelper.clear();

      // ------------------------------------------------------------------
      // Cleanup.
      // ------------------------------------------------------------------
      await flow.deleteAccount();
    },
  );
}
