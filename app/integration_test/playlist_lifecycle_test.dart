// E2E test suite covering Playlist functionality:
// signup -> mail validation -> signin -> create a playlist -> add a track
// via the in-playlist search sheet -> add another track via the Search
// screen's "Add to playlist" sheet (to an existing playlist) -> create a
// brand-new playlist directly from that same sheet -> reorder tracks ->
// toggle visibility/edit-policy -> invite a collaborator -> remove tracks
// -> delete the account (cleanup, cascades both playlists).
//
// This drives the real app UI (via integration_test) against a real backend
// (see `make project-up`) and a real mailbox (see `integration_test/README.md`
// for the required `--dart-define` values). No mocks. It also assumes the
// seeded music catalog from `server/src/database/migrations/002-seed-catalog.sql`
// is present, specifically the tracks "Gangnam Style" (id 5), "Hey Brother"
// (id 2), and "Palladio" (id 6) — their ids are used to target specific
// widgets via `ValueKey`.
//
// Run with e.g.:
//   flutter test integration_test/playlist_lifecycle_test.dart \
//     -d <device-id> \
//     --dart-define=MUSIC_ROOM_SERVER=10.0.2.2:8080 \
//     --dart-define=E2E_TEST_EMAIL=music-room@vanderlynden.eu \
//     --dart-define=E2E_IMAP_PASSWORD=*** \
//     --dart-define=E2E_TEST_PASSWORD=SomeStrongPass!1
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:pmr_music_room/config/constants.dart';
import 'package:pmr_music_room/main.dart';
import 'package:pmr_music_room/views/login.dart';
import 'package:pmr_music_room/views/home.dart';
import 'package:pmr_music_room/views/my_playlists.dart';
import 'package:pmr_music_room/views/playlist.dart';
import 'package:pmr_music_room/views/profile.dart';
import 'package:pmr_music_room/views/search.dart';

import 'helpers/mail_client.dart';
import 'helpers/test_env.dart';

// Seeded catalog track ids (see 002-seed-catalog.sql).
const _gangnamStyleId = 5;
const _heyBrotherId = 2;
const _palladioId = 6;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'signup, create playlists, add/reorder/remove tracks, invite, delete profile',
    (tester) async {
      TestEnv.ensureConfigured();

      // A per-run marker keeps the display name and playlist names unique
      // across repeated runs against the same shared test inbox.
      final runMarker = DateTime.now().millisecondsSinceEpoch.toString();
      final displayName = 'E2EPlaylist$runMarker';
      final playlistName = 'E2E Playlist $runMarker';
      final createdPlaylistName = 'E2E Created $runMarker';

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
      expect(find.byKey(const Key('login_password_field')), findsOneWidget);

      // --- Step 2: Mail validation ---
      final confirmationLink = await mail.waitForConfirmationLink();
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

      // --- Step 4: Create playlist #1 ---
      await tester.tap(find.byKey(const Key('home_playlists_button')));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.byType(MyPlaylistsScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('my_playlists_fab')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('playlist_dialog_name_field')),
        playlistName,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('playlist_dialog_create_button')));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.text(playlistName), findsOneWidget);

      // --- Step 5: Open playlist #1, add track #1 via the in-playlist
      // search sheet ---
      await tester.tap(find.text(playlistName));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.byType(PlaylistScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('playlist_add_track_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('playlist_track_search_field')),
        'Gangnam Style',
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.tap(
        find.byKey(const ValueKey('playlist_track_result_$_gangnamStyleId')),
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(
        find.byKey(const ValueKey(_gangnamStyleId)),
        findsOneWidget,
        reason: 'Gangnam Style should now appear in the playlist track list.',
      );

      // --- Step 6: Add track #2 via the Search screen's "Add to playlist"
      // sheet, targeting the existing playlist #1 ---
      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.byType(MyPlaylistsScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.byType(HomeScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('search_field')),
        'Hey Brother',
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.tap(
        find.byKey(const ValueKey('search_result_menu_$_heyBrotherId')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to playlist'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(playlistName));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // --- Step 7: Create a brand-new playlist directly from the Search
      // screen's "Add to playlist" sheet, for track #3 ---
      await tester.enterText(
        find.byKey(const Key('search_field')),
        'Palladio',
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.tap(
        find.byKey(const ValueKey('search_result_menu_$_palladioId')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to playlist'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add_to_playlist_create_toggle')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('add_to_playlist_name_field')),
        createdPlaylistName,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add_to_playlist_create_button')));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(
        find.textContaining('Created "$createdPlaylistName"'),
        findsOneWidget,
        reason:
            'Creating a new playlist from the Search "Add to playlist" '
            'sheet should confirm success.',
      );

      // --- Step 8: Verify the new playlist exists and contains track #3 ---
      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.byType(HomeScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('home_playlists_button')));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.text(createdPlaylistName), findsOneWidget);

      await tester.tap(find.text(createdPlaylistName));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(
        find.byKey(const ValueKey(_palladioId)),
        findsOneWidget,
        reason:
            'The playlist created via the Search sheet should contain '
            'Palladio.',
      );

      // --- Step 9: Return to playlist #1, verify both tracks are present,
      // then reorder them ---
      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await tester.tap(find.text(playlistName));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.byKey(const ValueKey(_gangnamStyleId)), findsOneWidget);
      expect(find.byKey(const ValueKey(_heyBrotherId)), findsOneWidget);

      final gangnamPositionBefore = tester
          .getTopLeft(find.byKey(const ValueKey(_gangnamStyleId)))
          .dy;
      final heyBrotherPositionBefore = tester
          .getTopLeft(find.byKey(const ValueKey(_heyBrotherId)))
          .dy;
      expect(
        gangnamPositionBefore,
        lessThan(heyBrotherPositionBefore),
        reason: 'Gangnam Style was added first, so it should be on top.',
      );

      final dragHandle = find.byKey(
        const ValueKey('playlist_track_drag_handle_$_heyBrotherId'),
      );
      final gesture = await tester.startGesture(tester.getCenter(dragHandle));
      await tester.pump(kLongPressTimeout + kPressTimeout);
      // Drag in small incremental steps (with a pump between each) rather
      // than one large jump: SliverReorderableList recomputes the swap
      // threshold against the currently rendered item extents on each
      // frame, and a single big `moveBy` can land past the point where the
      // list has already re-laid-out, causing the reorder to be missed.
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, -30));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await gesture.up();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final gangnamPositionAfter = tester
          .getTopLeft(find.byKey(const ValueKey(_gangnamStyleId)))
          .dy;
      final heyBrotherPositionAfter = tester
          .getTopLeft(find.byKey(const ValueKey(_heyBrotherId)))
          .dy;
      expect(
        heyBrotherPositionAfter,
        lessThan(gangnamPositionAfter),
        reason: 'Dragging Hey Brother above Gangnam Style should reorder it.',
      );

      // --- Step 10: Toggle visibility ---
      expect(find.byTooltip('Make private'), findsOneWidget);
      await tester.tap(find.byKey(const Key('playlist_toggle_visibility_button')));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.byTooltip('Make public'), findsOneWidget);

      // --- Step 11: Toggle edit policy ---
      expect(
        find.byTooltip('Restrict editing to collaborators'),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('playlist_toggle_edit_policy_button')),
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.byTooltip('Allow everyone to edit'), findsOneWidget);

      // --- Step 12: Invite a collaborator (self-invite, since only one
      // confirmed test account exists in this environment) ---
      await tester.tap(find.byKey(const Key('playlist_invite_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('playlist_invite_email_field')),
        TestEnv.testEmail,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('playlist_invite_submit_button')));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(
        find.textContaining('Successfully added'),
        findsOneWidget,
        reason: 'Inviting a collaborator should show a success snackbar.',
      );

      // --- Step 13: Remove both tracks ---
      await tester.tap(
        find.byKey(
          const ValueKey('playlist_remove_track_button_$_heyBrotherId'),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.byKey(const ValueKey(_heyBrotherId)), findsNothing);

      await tester.tap(
        find.byKey(
          const ValueKey('playlist_remove_track_button_$_gangnamStyleId'),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.byKey(const ValueKey(_gangnamStyleId)), findsNothing);

      // --- Step 14: Delete profile (cleanup, cascades both playlists) ---
      // Navigate back to Home: the stack here is Home -> MyPlaylists ->
      // PlaylistScreen, so a single pageBack() only reaches MyPlaylists.
      var popAttempts = 0;
      while (find.byType(HomeScreen).evaluate().isEmpty && popAttempts < 5) {
        await tester.pageBack();
        await tester.pumpAndSettle(const Duration(seconds: 2));
        popAttempts++;
      }
      expect(find.byType(HomeScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('home_profile_button')));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.byType(ProfileScreen), findsOneWidget);

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
