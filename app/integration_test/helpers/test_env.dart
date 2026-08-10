/// Reads E2E test configuration passed in via `--dart-define` at test-run
/// time. None of these values are hardcoded or committed — see
/// `integration_test/README.md` for how to supply them.
class TestEnv {
  /// Mailbox used both to sign up and to verify the confirmation email via
  /// IMAP (e.g. `music-room@vanderlynden.eu`).
  static const String testEmail = String.fromEnvironment('E2E_TEST_EMAIL');

  /// Password for the account used to sign up (must satisfy the app's
  /// signup password rules).
  static const String testPassword = String.fromEnvironment(
    'E2E_TEST_PASSWORD',
    defaultValue: 'E2eTestPassword!1',
  );

  /// IMAP password for [testEmail]'s mailbox.
  static const String imapPassword = String.fromEnvironment(
    'E2E_IMAP_PASSWORD',
  );

  /// A second, fully distinct mailbox/account dedicated to this project,
  /// used by suites that need two real accounts (e.g. owner vs. an
  /// outside/invited user) instead of a plus-addressed alias.
  static const String secondTestEmail = String.fromEnvironment(
    'E2E_SECOND_TEST_EMAIL',
    defaultValue: 'test-pierre@choraledelouvain.org',
  );

  /// IMAP password for [secondTestEmail]'s mailbox (same mail server as
  /// [testEmail] unless overridden).
  static const String secondImapPassword = String.fromEnvironment(
    'E2E_SECOND_IMAP_PASSWORD',
  );

  /// IMAP host, defaults to the OVH mail host already used by the backend's
  /// outbound SMTP config.
  static const String imapHost = String.fromEnvironment(
    'E2E_IMAP_HOST',
    defaultValue: 'ssl0.ovh.net',
  );

  /// Implicit TLS IMAP port.
  static const int imapPort = int.fromEnvironment(
    'E2E_IMAP_PORT',
    defaultValue: 993,
  );

  static void ensureConfigured() {
    final missing = <String>[
      if (testEmail.isEmpty) 'E2E_TEST_EMAIL',
      if (imapPassword.isEmpty) 'E2E_IMAP_PASSWORD',
    ];
    if (missing.isNotEmpty) {
      throw StateError(
        'Missing required --dart-define value(s) for the E2E suite: '
        '${missing.join(', ')}. See integration_test/README.md.',
      );
    }
  }

  /// Like [ensureConfigured] but additionally requires the second-mailbox
  /// credentials (used by suites needing two distinct real accounts).
  static void ensureSecondAccountConfigured() {
    ensureConfigured();
    final missing = <String>[
      if (secondImapPassword.isEmpty) 'E2E_SECOND_IMAP_PASSWORD',
    ];
    if (missing.isNotEmpty) {
      throw StateError(
        'Missing required --dart-define value(s) for the E2E suite: '
        '${missing.join(', ')}. See integration_test/README.md.',
      );
    }
  }
}
