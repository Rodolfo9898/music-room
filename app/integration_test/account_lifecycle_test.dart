// E2E test suite covering the full account lifecycle:
// signup -> mail validation -> signin -> change profile settings -> delete
// profile.
//
// This drives the real app UI (via integration_test) against a real backend
// (see `make project-up`) and a real mailbox (see `integration_test/README.md`
// for the required `--dart-define` values). No mocks: the confirmation email
// is genuinely sent by the backend and genuinely fetched over IMAP.
//
// Run with e.g.:
//   flutter test integration_test/account_lifecycle_test.dart \
//     -d <device-id> \
//     --dart-define=MUSIC_ROOM_SERVER=10.0.2.2:8080 \
//     --dart-define=E2E_TEST_EMAIL=music-room@vanderlynden.eu \
//     --dart-define=E2E_IMAP_PASSWORD=*** \
//     --dart-define=E2E_TEST_PASSWORD=SomeStrongPass!1
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:pmr_music_room/config/constants.dart';
import 'package:pmr_music_room/main.dart';
import 'package:pmr_music_room/views/login.dart';
import 'package:pmr_music_room/views/home.dart';
import 'package:pmr_music_room/views/profile.dart';

import 'helpers/mail_client.dart';
import 'helpers/test_env.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'signup, validate email, sign in, change settings, delete profile',
    (tester) async {
      TestEnv.ensureConfigured();

      // A per-run marker keeps the display name unique across repeated runs
      // against the same shared test inbox.
      final runMarker = DateTime.now().millisecondsSinceEpoch.toString();
      final displayName = 'E2E$runMarker';
      final updatedDisplayName = 'E2E${runMarker}Updated';

      final mail = MailClientHelper(
        email: TestEnv.testEmail,
        password: TestEnv.imapPassword,
        imapHost: TestEnv.imapHost,
        imapPort: TestEnv.imapPort,
      );

      // Discard any leftover confirmation email from a previous/failed run
      // before we trigger a fresh signup, so we don't consume a stale link.
      await mail.purgeExistingConfirmationEmails();

      await tester.pumpWidget(const MainApp());
      // The splash screen checks connectivity/session before redirecting to
      // the login screen.
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.byType(LoginScreen), findsOneWidget);

      // --- Step 1: Signup ---
      await tester.tap(find.text('Sign up'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('login_email_field')),
        TestEnv.testEmail,
      );
      await tester.enterText(
        find.byKey(const Key('login_display_name_field')),
        displayName,
      );
      await tester.enterText(
        find.byKey(const Key('login_password_field')),
        TestEnv.testPassword,
      );
      await tester.enterText(
        find.byKey(const Key('login_confirm_password_field')),
        TestEnv.testPassword,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(
        find.textContaining('confirmation email has been sent'),
        findsOneWidget,
        reason: 'Signup should confirm that a confirmation email was sent.',
      );

      // The app switches back to login mode automatically after a
      // successful signup.
      expect(find.byKey(const Key('login_password_field')), findsOneWidget);

      // --- Step 2: Mail validation ---
      final confirmationLink = await mail.waitForConfirmationLink();
      // The link's host is the backend's public-facing URL (e.g.
      // `localhost:8080`), which isn't reachable as-is from an emulator/
      // device. Re-target the same path+query at the backend host the app
      // itself is configured to talk to.
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

      // --- Step 3: Signin ---
      await tester.enterText(
        find.byKey(const Key('login_email_field')),
        TestEnv.testEmail,
      );
      await tester.enterText(
        find.byKey(const Key('login_password_field')),
        TestEnv.testPassword,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.byType(HomeScreen), findsOneWidget);

      // --- Step 4: Change profile settings ---
      await tester.tap(find.byKey(const Key('home_profile_button')));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.byType(ProfileScreen), findsOneWidget);

      // Display name.
      await tester.tap(find.byKey(const Key('profile_edit_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('profile_edit_display_name_field')),
        updatedDisplayName,
      );
      await tester.tap(find.byKey(const Key('profile_edit_save_button')));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.text(updatedDisplayName), findsWidgets);

      // Music genre preferences: toggle the first available genre chip on.
      final genreChipFinder = find.byWidgetPredicate(
        (widget) =>
            widget is FilterChip &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'profile_genre_chip_',
            ),
      );
      expect(
        genreChipFinder,
        findsWidgets,
        reason: 'Backend should expose at least one music genre to toggle.',
      );
      final firstGenreChip = tester.widget<FilterChip>(genreChipFinder.first);
      final wasSelected = firstGenreChip.selected;
      await tester.tap(genreChipFinder.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final updatedGenreChip = tester.widget<FilterChip>(genreChipFinder.first);
      expect(
        updatedGenreChip.selected,
        !wasSelected,
        reason: 'Toggling a genre chip should flip its selection state.',
      );

      // --- Step 5: Delete profile ---
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
    },
  );
}
