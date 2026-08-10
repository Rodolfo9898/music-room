// E2E test suite covering the Track Vote feature (subject V.2.1):
// signup -> mail validation -> signin -> create a public EVERYONE-policy
// voting event -> suggest tracks -> vote for multiple tracks and toggle a
// vote off (ranking reorder) -> create a private INVITED-policy event -> a
// second real account (a dedicated second mailbox, see
// `TestEnv.secondTestEmail`) verifies that the public event is discoverable
// while the private one is hidden until invited -> cross-user vote
// aggregation -> owner invites the second user via the Members screen -> the
// second user gains access and votes -> the owner removes the second user
// from the Members screen and their vote is cleared -> a LOCATION_TIME
// dropdown smoke check (no real geolocation is exercised) -> both accounts
// are deleted as cleanup.
//
// This drives the real app UI (via integration_test) against a real backend
// (see `make project-up`) and a real mailbox (see `integration_test/README.md`
// for the required `--dart-define` values). No mocks. It also assumes the
// seeded music catalog from `server/src/database/migrations/002-seed-catalog.sql`
// is present, specifically "Hey Brother" (id 2), "Gangnam Style" (id 5), and
// "Palladio" (id 6).
//
// Run with e.g.:
//   flutter test integration_test/track_vote_lifecycle_test.dart \
//     -d <device-id> \
//     --dart-define=MUSIC_ROOM_SERVER=10.0.2.2:8080 \
//     --dart-define=E2E_TEST_EMAIL=music-room@vanderlynden.eu \
//     --dart-define=E2E_IMAP_PASSWORD=*** \
//     --dart-define=E2E_TEST_PASSWORD=SomeStrongPass!1 \
//     --dart-define=E2E_SECOND_TEST_PASSWORD=*** \
//     --dart-define=E2E_SECOND_IMAP_PASSWORD=***
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:pmr_music_room/config/constants.dart';
import 'package:pmr_music_room/main.dart';
import 'package:pmr_music_room/views/login.dart';
import 'package:pmr_music_room/views/home.dart';
import 'package:pmr_music_room/views/track_vote.dart';

import 'helpers/mail_client.dart';
import 'helpers/test_env.dart';

// Seeded catalog track ids (see 002-seed-catalog.sql).
const _heyBrotherId = 2;
const _gangnamStyleId = 5;
const _palladioId = 6;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'signup, public/private voting events, ranking, cross-user voting, invite, delete',
    (tester) async {
      TestEnv.ensureSecondAccountConfigured();

      final runMarker = DateTime.now().millisecondsSinceEpoch.toString();
      final ownerDisplayName = 'E2EVoteOwner$runMarker';
      final voterDisplayName = 'E2EVoteVoter$runMarker';
      final publicEventName = 'Public event $runMarker';
      final privateEventName = 'Private event $runMarker';
      final voterEmail = TestEnv.secondTestEmail;

      final mail = MailClientHelper(
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

      Future<void> signup(
        String email,
        String displayName,
        String password,
      ) async {
        await tester.tap(find.text('Sign up'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('login_email_field')),
          email,
        );
        await tester.enterText(
          find.byKey(const Key('login_display_name_field')),
          displayName,
        );
        await tester.enterText(
          find.byKey(const Key('login_password_field')),
          password,
        );
        await tester.enterText(
          find.byKey(const Key('login_confirm_password_field')),
          password,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('login_submit_button')));
        await tester.pumpAndSettle(const Duration(seconds: 5));

        expect(
          find.textContaining('confirmation email has been sent'),
          findsOneWidget,
          reason: 'Signup should confirm that a confirmation email was sent.',
        );
        expect(find.byKey(const Key('login_password_field')), findsOneWidget);
      }

      Future<void> confirmEmail(MailClientHelper mailHelper) async {
        final confirmationLink = await mailHelper.waitForConfirmationLink();
        final confirmationUri = Uri.parse(confirmationLink);
        final confirmRequestUri = Uri.parse(
          Constants.httpServer,
        ).replace(path: confirmationUri.path, query: confirmationUri.query);
        final confirmResponse = await http.get(confirmRequestUri);
        expect(
          confirmResponse.statusCode,
          200,
          reason:
              'Clicking the confirmation link should succeed: '
              '${confirmResponse.body}',
        );
      }

      Future<void> signin(String email, String password) async {
        await tester.enterText(
          find.byKey(const Key('login_email_field')),
          email,
        );
        await tester.enterText(
          find.byKey(const Key('login_password_field')),
          password,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('login_submit_button')));
        await tester.pumpAndSettle(const Duration(seconds: 5));

        expect(find.byType(HomeScreen), findsOneWidget);
      }

      Future<void> popToHome() async {
        var attempts = 0;
        while (find.byType(HomeScreen).evaluate().isEmpty && attempts < 5) {
          await tester.pageBack();
          await tester.pumpAndSettle(const Duration(seconds: 2));
          attempts++;
        }
        expect(find.byType(HomeScreen), findsOneWidget);
      }

      Future<void> logout() async {
        await popToHome();
        await tester.tap(find.byKey(const Key('home_profile_button')));
        await tester.pumpAndSettle(const Duration(seconds: 3));
        await tester.scrollUntilVisible(
          find.byKey(const Key('profile_logout_button')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('profile_logout_button')));
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byType(LoginScreen), findsOneWidget);
      }

      Future<void> deleteAccount() async {
        await popToHome();
        await tester.tap(find.byKey(const Key('home_profile_button')));
        await tester.pumpAndSettle(const Duration(seconds: 3));
        await tester.scrollUntilVisible(
          find.byKey(const Key('profile_delete_account_button')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('profile_delete_account_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('profile_delete_confirm_button')));
        await tester.pumpAndSettle(const Duration(seconds: 5));
        expect(find.byType(LoginScreen), findsOneWidget);
      }

      Future<void> openTrackVote() async {
        await tester.tap(find.byKey(const Key('home_track_vote_button')));
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byType(TrackVoteScreen), findsOneWidget);
      }

      Future<void> createEvent({
        required String name,
        required bool isPublic,
        required String policy,
      }) async {
        await tester.tap(find.byKey(const Key('track_vote_new_event_button')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('track_vote_create_name_field')),
          name,
        );
        if (!isPublic) {
          await tester.tap(
            find.byKey(const Key('track_vote_create_public_switch')),
          );
          await tester.pumpAndSettle();
        }
        if (policy != 'EVERYONE') {
          await tester.tap(
            find.byKey(const Key('track_vote_create_policy_dropdown')),
          );
          await tester.pumpAndSettle();
          final label = switch (policy) {
            'INVITED' => 'Invited users only',
            'LOCATION_TIME' => 'Nearby during time window',
            _ => 'Everyone',
          };
          await tester.tap(find.text(label).last);
          await tester.pumpAndSettle();
        }

        await tester.tap(
          find.byKey(const Key('track_vote_create_submit_button')),
        );
        await tester.pumpAndSettle(const Duration(seconds: 3));

        expect(find.text(name), findsOneWidget);
      }

      Future<void> suggestTrack(String query, int musicId) async {
        await tester.tap(find.byKey(const Key('track_vote_suggest_button')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('track_vote_suggest_search_field')),
          query,
        );
        await tester.pumpAndSettle(const Duration(seconds: 2));

        await tester.tap(
          find.byKey(ValueKey('track_vote_suggest_result_$musicId')),
        );
        await tester.pumpAndSettle(const Duration(seconds: 3));

        expect(
          find.byKey(ValueKey('track_vote_track_$musicId')),
          findsOneWidget,
          reason: 'The suggested track should now appear in the ranking.',
        );
      }

      Future<void> voteFor(int musicId) async {
        await tester.tap(
          find.byKey(ValueKey('track_vote_vote_button_$musicId')),
        );
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }

      double trackTop(int musicId) => tester
          .getTopLeft(find.byKey(ValueKey('track_vote_track_$musicId')))
          .dy;

      // ------------------------------------------------------------------
      // Step 1: owner signup, mail validation, signin.
      // ------------------------------------------------------------------
      await mail.purgeExistingConfirmationEmails();

      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.byType(LoginScreen), findsOneWidget);

      await signup(TestEnv.testEmail, ownerDisplayName, TestEnv.testPassword);
      await confirmEmail(mail);
      await signin(TestEnv.testEmail, TestEnv.testPassword);

      // ------------------------------------------------------------------
      // Step 2: public EVERYONE event — suggest, vote for multiple tracks,
      // ranking reorder, and toggling a vote off.
      // ------------------------------------------------------------------
      await openTrackVote();
      await createEvent(
        name: publicEventName,
        isPublic: true,
        policy: 'EVERYONE',
      );
      await tester.tap(find.text(publicEventName));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await suggestTrack('Hey Brother', _heyBrotherId);
      await suggestTrack('Gangnam Style', _gangnamStyleId);

      // Tied at 0 votes each: insertion order (Hey Brother suggested first).
      expect(trackTop(_heyBrotherId), lessThan(trackTop(_gangnamStyleId)));

      await voteFor(_gangnamStyleId);
      expect(
        trackTop(_gangnamStyleId),
        lessThan(trackTop(_heyBrotherId)),
        reason: 'A track that gains a vote should rank above a tied track.',
      );

      // Voting for a second track adds another vote without removing the
      // first: a user can back multiple tracks at once.
      await voteFor(_heyBrotherId);
      expect(
        find.textContaining('1 votes'),
        findsNWidgets(2),
        reason: 'Voting for a second track keeps the first vote in place.',
      );

      // Voting again for a track the user already backed toggles it off.
      await voteFor(_heyBrotherId);
      expect(
        trackTop(_gangnamStyleId),
        lessThan(trackTop(_heyBrotherId)),
        reason:
            'Toggling a vote off should drop that track back to the '
            'unvoted tally.',
      );
      expect(find.textContaining('0 votes'), findsOneWidget);
      expect(find.textContaining('1 votes'), findsOneWidget);


      // ------------------------------------------------------------------
      // Step 3: private INVITED event — owner suggests, does not vote.
      // ------------------------------------------------------------------
      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.byType(TrackVoteScreen), findsOneWidget);

      await createEvent(
        name: privateEventName,
        isPublic: false,
        policy: 'INVITED',
      );
      await tester.tap(find.text(privateEventName));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await suggestTrack('Palladio', _palladioId);

      // ------------------------------------------------------------------
      // Step 4: LOCATION_TIME dropdown smoke check — verify the option is
      // selectable without ever calling geolocation (dialog is cancelled).
      // ------------------------------------------------------------------
      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.byType(TrackVoteScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('track_vote_new_event_button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('track_vote_create_policy_dropdown')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nearby during time window'), findsWidgets);
      await tester.tap(find.text('Nearby during time window').last);
      await tester.pumpAndSettle();
      // No dedicated Cancel button exists on this form — use the standard
      // AppBar back navigation to dismiss the dialog without submitting.
      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.byType(TrackVoteScreen), findsOneWidget);

      await logout();

      // ------------------------------------------------------------------
      // Step 5: second account (voter) — pre-invite visibility checks.
      // ------------------------------------------------------------------
      await voterMail.purgeExistingConfirmationEmails();
      await signup(voterEmail, voterDisplayName, TestEnv.secondImapPassword);
      await confirmEmail(voterMail);
      await signin(voterEmail, TestEnv.secondImapPassword);

      await openTrackVote();
      expect(
        find.text(publicEventName),
        findsOneWidget,
        reason: 'A public event must be discoverable by any user.',
      );
      expect(
        find.text(privateEventName),
        findsNothing,
        reason:
            'A private event must not be discoverable by a non-invited user.',
      );

      // ------------------------------------------------------------------
      // Step 6: cross-user vote aggregation on the public event.
      // ------------------------------------------------------------------
      await tester.tap(find.text(publicEventName));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(
        find.textContaining(
          'Your current invitation, location, or time does not satisfy',
        ),
        findsNothing,
        reason: 'EVERYONE policy should let the second user vote too.',
      );

      await voteFor(_heyBrotherId);
      // Owner's vote (Gangnam Style, from step 2) + voter's vote (Hey
      // Brother): 1 each, tie broken by suggestion order (Hey Brother
      // suggested first).
      expect(trackTop(_heyBrotherId), lessThan(trackTop(_gangnamStyleId)));
      expect(find.textContaining('1 votes'), findsNWidgets(2));

      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await logout();

      // ------------------------------------------------------------------
      // Step 7: owner invites the voter to the private event.
      // ------------------------------------------------------------------
      await signin(TestEnv.testEmail, TestEnv.testPassword);
      await openTrackVote();
      await tester.tap(find.text(privateEventName));
      await tester.pumpAndSettle(const Duration(seconds: 3));

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

      await logout();

      // ------------------------------------------------------------------
      // Step 8: voter regains access after being invited, and votes.
      // ------------------------------------------------------------------
      await signin(voterEmail, TestEnv.secondImapPassword);
      await openTrackVote();
      expect(
        find.text(privateEventName),
        findsOneWidget,
        reason: 'An invited user should now be able to discover the event.',
      );

      await tester.tap(find.text(privateEventName));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(
        find.textContaining(
          'Your current invitation, location, or time does not satisfy',
        ),
        findsNothing,
        reason: 'An invited user must be allowed to vote.',
      );

      await voteFor(_palladioId);
      expect(find.textContaining('1 votes'), findsOneWidget);

      // ------------------------------------------------------------------
      // Step 9: owner removes the voter from the private event — their
      // vote must be cleared immediately (subject: removing a member
      // removes their votes).
      // ------------------------------------------------------------------
      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await logout();

      await signin(TestEnv.testEmail, TestEnv.testPassword);
      await openTrackVote();
      await tester.tap(find.text(privateEventName));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(
        find.textContaining('1 votes'),
        findsOneWidget,
        reason: 'The voter\'s vote for Palladio should still be present.',
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

      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(
        find.textContaining('1 votes'),
        findsNothing,
        reason: 'Removing a member must clear their vote from the ranking.',
      );

      // ------------------------------------------------------------------
      // Step 10: cleanup — delete both accounts.
      // ------------------------------------------------------------------
      await logout();
      await signin(voterEmail, TestEnv.secondImapPassword);
      await deleteAccount();

      await signin(TestEnv.testEmail, TestEnv.testPassword);
      await deleteAccount();
    },
  );
}
