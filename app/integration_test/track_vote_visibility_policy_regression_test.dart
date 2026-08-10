// E2E regression suite covering the Track Vote **visibility × policy**
// dimension (subject V.2.1): PUBLIC/PRIVATE crossed with EVERYONE/INVITED,
// plus the two most important non-owner behaviors (a non-invited stranger
// can't discover a private event; a non-invited stranger on a public
// INVITED event is denied until invited).
//
// This complements `track_vote_lifecycle_test.dart` (which already deep
// dives into ranking/aggregation for these two policies) with a fast,
// focused pass over every visibility/policy combination, asserting only
// the vote eligibility outcome (allowed/denied + exact reason), per event.
//
// LOCATION_TIME is covered separately in
// `track_vote_location_time_regression_test.dart`, and the
// invite→vote→remove-member regression in
// `track_vote_member_removal_regression_test.dart`.
//
// Two accounts (owner + stranger) are provisioned once via real
// signup/mail-confirmation and reused across every flow to keep the whole
// suite fast — see `integration_test/README.md`.
//
// Run with e.g.:
//   flutter test integration_test/track_vote_visibility_policy_regression_test.dart \
//     -d <device-id> \
//     --dart-define=MUSIC_ROOM_SERVER=10.0.2.2:8080 \
//     --dart-define=E2E_TEST_EMAIL=music-room@vanderlynden.eu \
//     --dart-define=E2E_IMAP_PASSWORD=*** \
//     --dart-define=E2E_TEST_PASSWORD=SomeStrongPass!1 \
//     --dart-define=E2E_SECOND_TEST_PASSWORD=*** \
//     --dart-define=E2E_SECOND_IMAP_PASSWORD=***
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pmr_music_room/main.dart';
import 'package:pmr_music_room/views/login.dart';

import 'helpers/mail_client.dart';
import 'helpers/test_env.dart';
import 'helpers/track_vote_flow_helpers.dart';

// Seeded catalog track ids (see 002-seed-catalog.sql).
const _heyBrotherId = 2;
const _gangnamStyleId = 5;
const _palladioId = 6;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'visibility x policy regression matrix: public/private x everyone/invited',
    (tester) async {
      TestEnv.ensureSecondAccountConfigured();

      final flow = TrackVoteFlow(tester);
      final runMarker = DateTime.now().millisecondsSinceEpoch.toString();
      final ownerDisplayName = 'E2EVisPolOwner$runMarker';
      final strangerDisplayName = 'E2EVisPolStranger$runMarker';
      final strangerEmail = TestEnv.secondTestEmail;

      final ownerMail = MailClientHelper(
        email: TestEnv.testEmail,
        password: TestEnv.imapPassword,
        imapHost: TestEnv.imapHost,
        imapPort: TestEnv.imapPort,
      );
      final strangerMail = MailClientHelper(
        email: TestEnv.secondTestEmail,
        password: TestEnv.secondImapPassword,
        imapHost: TestEnv.imapHost,
        imapPort: TestEnv.imapPort,
      );

      final publicEveryoneName = 'VisPol PublicEveryone $runMarker';
      final privateEveryoneName = 'VisPol PrivateEveryone $runMarker';
      final publicInvitedName = 'VisPol PublicInvited $runMarker';
      final privateInvitedName = 'VisPol PrivateInvited $runMarker';

      // ------------------------------------------------------------------
      // Setup: provision both accounts once (real signup + mail
      // confirmation), owner ends up signed in.
      // ------------------------------------------------------------------
      await ownerMail.purgeExistingConfirmationEmails();
      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.byType(LoginScreen), findsOneWidget);

      await flow.signup(TestEnv.testEmail, ownerDisplayName, TestEnv.testPassword);
      await flow.confirmEmail(ownerMail);
      await flow.signin(TestEnv.testEmail, TestEnv.testPassword);
      await flow.logout();

      await strangerMail.purgeExistingConfirmationEmails();
      await flow.signup(
        strangerEmail,
        strangerDisplayName,
        TestEnv.secondImapPassword,
      );
      await flow.confirmEmail(strangerMail);
      await flow.signin(strangerEmail, TestEnv.secondImapPassword);
      await flow.logout();

      await flow.signin(TestEnv.testEmail, TestEnv.testPassword);

      // ------------------------------------------------------------------
      // Flow 1: PUBLIC + EVERYONE -> owner can vote.
      // ------------------------------------------------------------------
      await flow.openTrackVote();
      await flow.createEvent(
        name: publicEveryoneName,
        isPublic: true,
        policy: 'EVERYONE',
      );
      await flow.openEvent(publicEveryoneName);
      await flow.suggestTrack('Hey Brother', _heyBrotherId);
      expect(
        find.byKey(const Key('track_vote_suggest_button')),
        findsOneWidget,
        reason: 'PUBLIC/EVERYONE: owner must be able to vote/suggest.',
      );
      await flow.voteFor(_heyBrotherId);
      expect(find.textContaining('1 votes'), findsOneWidget);
      await flow.back();

      // ------------------------------------------------------------------
      // Flow 2: PRIVATE + EVERYONE -> owner can vote.
      // ------------------------------------------------------------------
      await flow.createEvent(
        name: privateEveryoneName,
        isPublic: false,
        policy: 'EVERYONE',
      );
      await flow.openEvent(privateEveryoneName);
      await flow.suggestTrack('Gangnam Style', _gangnamStyleId);
      expect(
        find.byKey(const Key('track_vote_suggest_button')),
        findsOneWidget,
        reason: 'PRIVATE/EVERYONE: owner must still be able to vote/suggest.',
      );
      await flow.voteFor(_gangnamStyleId);
      expect(find.textContaining('1 votes'), findsOneWidget);
      await flow.back();

      // ------------------------------------------------------------------
      // Flow 3: PUBLIC + INVITED -> owner can vote.
      // ------------------------------------------------------------------
      await flow.createEvent(
        name: publicInvitedName,
        isPublic: true,
        policy: 'INVITED',
      );
      await flow.openEvent(publicInvitedName);
      await flow.suggestTrack('Palladio', _palladioId);
      expect(
        find.byKey(const Key('track_vote_suggest_button')),
        findsOneWidget,
        reason: 'PUBLIC/INVITED: owner must still be able to vote/suggest.',
      );
      await flow.voteFor(_palladioId);
      expect(find.textContaining('1 votes'), findsOneWidget);
      await flow.back();

      // ------------------------------------------------------------------
      // Flow 4: PRIVATE + INVITED -> owner can vote (no invite needed for
      // the owner themselves).
      // ------------------------------------------------------------------
      await flow.createEvent(
        name: privateInvitedName,
        isPublic: false,
        policy: 'INVITED',
      );
      await flow.openEvent(privateInvitedName);
      await flow.suggestTrack('Hey Brother', _heyBrotherId);
      expect(
        find.byKey(const Key('track_vote_suggest_button')),
        findsOneWidget,
        reason: 'PRIVATE/INVITED: owner must still be able to vote/suggest.',
      );
      await flow.voteFor(_heyBrotherId);
      expect(find.textContaining('1 votes'), findsOneWidget);
      await flow.back();
      await flow.logout();

      // ------------------------------------------------------------------
      // Flow 13: non-invited stranger can't discover ANY private event,
      // regardless of policy (NOT_VIEWABLE).
      // ------------------------------------------------------------------
      await flow.signin(strangerEmail, TestEnv.secondImapPassword);
      await flow.openTrackVote();
      expect(
        find.text(publicEveryoneName),
        findsOneWidget,
        reason: 'A public event must be discoverable by any user.',
      );
      expect(
        find.text(privateEveryoneName),
        findsNothing,
        reason:
            'A private EVERYONE-policy event must not be discoverable by a '
            'non-invited user.',
      );
      expect(
        find.text(privateInvitedName),
        findsNothing,
        reason:
            'A private INVITED-policy event must not be discoverable by a '
            'non-invited user.',
      );

      // ------------------------------------------------------------------
      // Flow 14: stranger sees the public INVITED event (public events are
      // always discoverable) but is denied voting (NOT_INVITED) until
      // invited by the owner.
      // ------------------------------------------------------------------
      expect(
        find.text(publicInvitedName),
        findsOneWidget,
        reason:
            'A public event must be discoverable even under the INVITED '
            'policy.',
      );
      await flow.openEvent(publicInvitedName);
      expect(
        find.textContaining("haven't been invited to vote"),
        findsOneWidget,
        reason:
            'A non-invited user on a public INVITED event must be denied '
            'with the NOT_INVITED reason.',
      );
      expect(
        find.byKey(const Key('track_vote_suggest_button')),
        findsNothing,
        reason: 'A non-invited user must not see the suggest action.',
      );
      await flow.back();
      await flow.logout();

      await flow.signin(TestEnv.testEmail, TestEnv.testPassword);
      await flow.openTrackVote();
      await flow.openEvent(publicInvitedName);
      await tester.tap(find.byKey(const Key('track_vote_members_button')));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await tester.tap(find.byKey(const Key('track_vote_members_add_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('track_vote_invite_email_field')),
        strangerEmail,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('track_vote_invite_submit_button')),
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.textContaining('Invitation added.'), findsOneWidget);
      await flow.back();
      await flow.back();
      await flow.logout();

      await flow.signin(strangerEmail, TestEnv.secondImapPassword);
      await flow.openTrackVote();
      await flow.openEvent(publicInvitedName);
      expect(
        find.textContaining("haven't been invited to vote"),
        findsNothing,
        reason: 'An invited user must no longer be denied for NOT_INVITED.',
      );
      expect(
        find.byKey(const Key('track_vote_suggest_button')),
        findsOneWidget,
        reason: 'An invited user must be allowed to vote/suggest.',
      );
      await flow.back();

      // ------------------------------------------------------------------
      // Cleanup: delete both accounts.
      // ------------------------------------------------------------------
      await flow.deleteAccount();
      await flow.signin(TestEnv.testEmail, TestEnv.testPassword);
      await flow.deleteAccount();
    },
  );
}
