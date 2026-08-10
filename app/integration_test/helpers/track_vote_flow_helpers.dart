// Shared step helpers for the Track Vote E2E suites (extracted from
// `track_vote_lifecycle_test.dart` so the regression suites in
// `track_vote_visibility_policy_regression_test.dart`,
// `track_vote_location_time_regression_test.dart` and
// `track_vote_member_removal_regression_test.dart` don't have to
// copy/paste the same ~150 lines of boilerplate).
//
// These helpers drive the real app UI (via integration_test) exactly like
// the original lifecycle test does — no mocks, real backend, real mailbox.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pmr_music_room/config/constants.dart';
import 'package:pmr_music_room/views/login.dart';
import 'package:pmr_music_room/views/home.dart';
import 'package:pmr_music_room/views/track_vote.dart';

import 'mail_client.dart';

/// Wraps a [WidgetTester] with the common Track Vote flow steps (signup,
/// mail confirmation, signin, event creation, suggesting/voting, etc.).
class TrackVoteFlow {
  TrackVoteFlow(this.tester);

  final WidgetTester tester;

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
    // Idempotent: if we're already on the TrackVoteScreen (e.g. the
    // previous flow's `back()` popped the event detail screen but stayed
    // on the events list), there's no Home button to tap, and there's
    // nothing to do.
    if (find.byType(TrackVoteScreen).evaluate().isNotEmpty) {
      return;
    }
    await tester.tap(find.byKey(const Key('home_track_vote_button')));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.byType(TrackVoteScreen), findsOneWidget);
  }

  /// Opens the create-event form, fills the common fields, and (when
  /// [policy] is `LOCATION_TIME`) the location/radius/start/end fields too.
  /// [startsAt]/[endsAt] let callers drive the time-window dimension via
  /// the real date/time pickers, computed relative to `DateTime.now()` by
  /// the caller.
  Future<void> createEvent({
    required String name,
    required bool isPublic,
    required String policy,
    String location = 'Eiffel Tower, Paris',
    double radiusMeters = 300,
    DateTime? startsAt,
    DateTime? endsAt,
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

    if (policy == 'LOCATION_TIME') {
      await tester.enterText(
        find.byKey(const Key('track_vote_create_location_field')),
        location,
      );
      await tester.pumpAndSettle();

      await _pickDateTimeTile('track_vote_create_starts_at_tile', startsAt!);
      await _pickDateTimeTile('track_vote_create_ends_at_tile', endsAt!);
    }

    await tester.tap(
      find.byKey(const Key('track_vote_create_submit_button')),
    );
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text(name), findsOneWidget);
  }

  Future<void> _pickDateTimeTile(String key, DateTime value) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();

    // Scope all lookups to the open Dialog: the route underneath (the
    // create-event form) stays mounted while a dialog is shown, and its own
    // TextField widgets (name, location) would otherwise be picked up by an
    // unscoped `find.byType(TextField)`, silently overwriting form data
    // instead of the picker's own fields.
    final dialog = find.byType(Dialog);

    // Date picker: navigate to the requested day within the currently
    // displayed month grid using the "Switch to input" affordance so we can
    // type the date directly instead of driving the calendar UI, which is
    // resilient across month/locale rendering differences.
    final entryModeButton = find.descendant(
      of: dialog,
      matching: find.byIcon(Icons.edit_outlined),
    );
    if (entryModeButton.evaluate().isNotEmpty) {
      await tester.tap(entryModeButton.first);
      await tester.pumpAndSettle();
    }
    final dateField = find.descendant(
      of: dialog,
      matching: find.byType(TextFormField),
    ).first;
    await tester.enterText(
      dateField,
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.year}',
    );
    // Explicitly submit the field (equivalent to pressing "done" on the
    // keyboard) so the FormField's value is committed even if a bare
    // `enterText` doesn't trigger it reliably on a real device.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Time picker: same input-mode trick, still scoped to the (new) dialog.
    final timeDialog = find.byType(Dialog);
    final timeEntryModeButton = find.descendant(
      of: timeDialog,
      matching: find.byIcon(Icons.keyboard_outlined),
    );
    if (timeEntryModeButton.evaluate().isNotEmpty) {
      await tester.tap(timeEntryModeButton.first);
      await tester.pumpAndSettle();
    }
    final timeFields = find.descendant(
      of: timeDialog,
      matching: find.byType(TextField),
    );
    final hourField = timeFields.at(0);
    final minuteField = timeFields.at(1);
    // The time picker respects the device's 24-hour/12-hour OS setting
    // (`MediaQuery.alwaysUse24HourFormatOf`), which varies across
    // emulators. Detect which mode is active (an AM/PM period control is
    // only rendered in 12-hour mode) and enter the hour accordingly,
    // otherwise both start/end times can silently fall back to the
    // picker's initial value (e.g. an invalid "13" hour in 12-hour mode).
    final isTwelveHour =
        find.descendant(of: timeDialog, matching: find.text('AM')).evaluate().isNotEmpty ||
        find.descendant(of: timeDialog, matching: find.text('PM')).evaluate().isNotEmpty;
    // Enter hour then minute, and only *then* select AM/PM (matching the
    // Flutter framework's own time picker tests): tapping the period
    // control after typing commits both the hour/minute text and the
    // period together via the same rebuild, avoiding order-dependent
    // clobbering of uncommitted state.
    if (isTwelveHour) {
      var hour12 = value.hour % 12;
      if (hour12 == 0) hour12 = 12;
      await tester.enterText(hourField, hour12.toString().padLeft(2, '0'));
    } else {
      await tester.enterText(hourField, value.hour.toString().padLeft(2, '0'));
    }
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(
      minuteField,
      value.minute.toString().padLeft(2, '0'),
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 50));
    if (isTwelveHour) {
      final isPm = value.hour >= 12;
      await tester.tap(
        find.descendant(
          of: timeDialog,
          matching: find.text(isPm ? 'PM' : 'AM'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.descendant(of: timeDialog, matching: find.text('OK')));
    await tester.pumpAndSettle();
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
  }

  Future<void> voteFor(int musicId) async {
    await tester.tap(
      find.byKey(ValueKey('track_vote_vote_button_$musicId')),
    );
    await tester.pumpAndSettle(const Duration(seconds: 3));
  }

  Future<void> openEvent(String name) async {
    await tester.tap(find.text(name));
    await tester.pumpAndSettle(const Duration(seconds: 3));
  }

  Future<void> back() async {
    await tester.pageBack();
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }
}
