// E2E regression test covering the Track Vote **member removal** behavior
// (subject V.2.1): inviting a stranger to a private INVITED event, having
// them vote, then removing them as a member — their vote must be cleared
// immediately and they must lose view access to the event again
// (NOT_VIEWABLE), as an isolated, fast flow (extracted as flow #15 of the
// full regression matrix; also exercised end-to-end alongside other steps
// in `track_vote_lifecycle_test.dart`).
//
// Two accounts (owner + stranger) are provisioned once via real
// signup/mail-confirmation.
//
// Run with e.g.:
//   flutter test integration_test/track_vote_member_removal_regression_test.dart \
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

// Seeded catalog track id (see 002-seed-catalog.sql).
const _palladioId = 6;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'flow 15: invite, vote, then remove member -> vote cleared and access revoked',
    (tester) async {
      TestEnv.ensureSecondAccountConfigured();

      final flow = TrackVoteFlow(tester);
      final runMarker = DateTime.now().millisecondsSinceEpoch.toString();
      final ownerDisplayName = 'E2EMemberRemOwner$runMarker';
      final voterDisplayName = 'E2EMemberRemVoter$runMarker';
      final voterEmail = TestEnv.secondTestEmail;
      final eventName = 'MemberRemoval event $runMarker';

      final ownerMail = MailClientHelper(
        email: TestEnv.testEmail,
        password: TestEnv.imapPassword,
        imapHost: TestEnv.imapHost,
        imapPort: TestEnv.imapPort,
      );
      final voterMail = MailClientHelper(
        email: TestEnv.secondTestEmail,
        password: TestEnv.secondImapPassword,
        imapHost: TestEnv.imapHost,
        imapPort: TestEnv.imapPort,
      );

      // ------------------------------------------------------------------
      // Setup: provision both accounts (the voter must already have an
      // account before the owner can invite them by email — the invite
      // mutation resolves the invitee to an existing user id server-side
      // and cannot invite an email with no registered account), owner
      // creates a private INVITED event and suggests a track.
      // ------------------------------------------------------------------
      await ownerMail.purgeExistingConfirmationEmails();
      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.byType(LoginScreen), findsOneWidget);

      await voterMail.purgeExistingConfirmationEmails();
      await flow.signup(voterEmail, voterDisplayName, TestEnv.secondImapPassword);
      await flow.confirmEmail(voterMail);

      // Reset the app to a fresh sign-in screen before signing up the
      // owner (the login screen is still in "sign up" mode after the
      // voter's signup).
      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.byType(LoginScreen), findsOneWidget);

      await flow.signup(TestEnv.testEmail, ownerDisplayName, TestEnv.testPassword);
      await flow.confirmEmail(ownerMail);
      await flow.signin(TestEnv.testEmail, TestEnv.testPassword);

      await flow.openTrackVote();
      await flow.createEvent(
        name: eventName,
        isPublic: false,
        policy: 'INVITED',
      );
      await flow.openEvent(eventName);
      await flow.suggestTrack('Palladio', _palladioId);

      // ------------------------------------------------------------------
      // Owner invites the voter.
      // ------------------------------------------------------------------
      await tester.tap(find.byKey(const Key('track_vote_members_button')));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await tester.tap(find.byKey(const Key('track_vote_members_add_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('track_vote_invite_email_field')),
        voterEmail,
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

      // ------------------------------------------------------------------
      // Voter signs in, sees the now-invited private event, and votes.
      // ------------------------------------------------------------------
      await flow.signin(voterEmail, TestEnv.secondImapPassword);

      await flow.openTrackVote();
      expect(
        find.text(eventName),
        findsOneWidget,
        reason: 'An invited user should be able to discover the event.',
      );
      await flow.openEvent(eventName);
      expect(
        find.byKey(const Key('track_vote_suggest_button')),
        findsOneWidget,
        reason: 'An invited user must be allowed to vote.',
      );
      await flow.voteFor(_palladioId);
      expect(find.textContaining('1 votes'), findsOneWidget);
      await flow.back();
      await flow.logout();

      // ------------------------------------------------------------------
      // Owner removes the voter from the members list -> vote is cleared.
      // ------------------------------------------------------------------
      await flow.signin(TestEnv.testEmail, TestEnv.testPassword);
      await flow.openTrackVote();
      await flow.openEvent(eventName);
      expect(
        find.textContaining('1 votes'),
        findsOneWidget,
        reason: "The voter's vote for Palladio should still be present.",
      );

      await tester.tap(find.byKey(const Key('track_vote_members_button')));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await tester.tap(find.byIcon(Icons.person_remove));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('track_vote_members_remove_confirm_button')),
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.textContaining('removed.'), findsOneWidget);

      await flow.back();
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(
        find.textContaining('1 votes'),
        findsNothing,
        reason: "Removing a member must clear their vote from the ranking.",
      );
      await flow.back();
      await flow.logout();

      // ------------------------------------------------------------------
      // The removed voter must lose view access to the event again.
      // ------------------------------------------------------------------
      await flow.signin(voterEmail, TestEnv.secondImapPassword);
      await flow.openTrackVote();
      expect(
        find.text(eventName),
        findsNothing,
        reason:
            'A removed member must no longer be able to discover the '
            'private event (NOT_VIEWABLE).',
      );

      // ------------------------------------------------------------------
      // Cleanup: delete both accounts.
      // ------------------------------------------------------------------
      await flow.deleteAccount();
      await flow.signin(TestEnv.testEmail, TestEnv.testPassword);
      await flow.deleteAccount();
    },
  );
}
