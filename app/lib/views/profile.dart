import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import '../network/account.dart';
import '../network/music.dart';
import '../network/web_socket.dart';
import '../objects/device_record.dart';
import '../objects/friend_record.dart';
import '../objects/genre_option.dart';
import '../objects/user_profile.dart';
import '../services/google_auth_service.dart';
import '../state/music_player_controller.dart';
import 'login.dart';

class ProfileScreen extends StatefulWidget {
  static const routeName = '/profile';

  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static final RegExp _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  String? _email;
  String? _displayName;
  int? _accountId;
  UserProfile? _profile;
  List<GenreOption> _genres = [];
  Set<int> _selectedGenreIds = {};
  List<FriendRecord> _friends = [];
  List<DeviceRecord> _devices = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final results = await Future.wait([
      AccountService.fetchProfile(),
      MusicService.fetchGenres(),
      AccountService.fetchFriends(),
      AccountService.fetchDevices(),
    ]);
    final profile = results[0] as UserProfile?;
    final genres = results[1] as List<GenreOption>;
    final friends = results[2] as List<FriendRecord>;
    final devices = results[3] as List<DeviceRecord>;
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _genres = genres;
      _selectedGenreIds = profile?.musicPreferenceGenreIds.toSet() ?? {};
      _friends = friends;
      _devices = devices;
      _email =
          profile?.email ?? prefs.getString(SharedPreferencesKeys.accountEmail);
      _displayName =
          profile?.displayName ??
          prefs.getString(SharedPreferencesKeys.displayName);
      _accountId =
          profile?.accountId ?? prefs.getInt(SharedPreferencesKeys.accountId);
      _isLoading = false;
    });
  }

  Future<void> _requestFriend() async {
    final controller = TextEditingController();
    final dialogFormKey = GlobalKey<FormState>();
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a friend'),
        content: Form(
          key: dialogFormKey,
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Account email'),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: _validateEmail,
            onFieldSubmitted: (_) {
              final isValid = dialogFormKey.currentState?.validate() ?? false;
              if (!isValid) return;
              Navigator.pop(ctx, controller.text.trim());
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final isValid = dialogFormKey.currentState?.validate() ?? false;
              if (!isValid) return;
              Navigator.pop(ctx, controller.text.trim());
            },
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    if (email == null || email.isEmpty) return;
    final friends = await AccountService.requestFriend(email);
    if (mounted) setState(() => _friends = friends);
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Email is required';
    if (!_emailRegex.hasMatch(email)) return 'Enter a valid email address';
    return null;
  }

  Future<void> _acceptFriend(int id) async {
    final friends = await AccountService.acceptFriend(id);
    if (mounted) setState(() => _friends = friends);
  }

  Future<void> _manageDelegates(DeviceRecord device) async {
    final accepted = _friends
        .where((friend) => friend.status == 'ACCEPTED')
        .toList();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Control ${device.name}'),
          content: SizedBox(
            width: 420,
            child: accepted.isEmpty
                ? const Text('Accept a friend before delegating control.')
                : ListView(
                    shrinkWrap: true,
                    children: accepted.map((friend) {
                      final selected = device.delegateIds.contains(friend.id);
                      return CheckboxListTile(
                        value: selected,
                        title: Text(
                          friend.displayName.isEmpty
                              ? friend.email
                              : friend.displayName,
                        ),
                        subtitle: const Text(
                          'May control rooms played by this device',
                        ),
                        onChanged: device.canControl
                            ? (value) async {
                                final devices =
                                    await AccountService.setDeviceDelegate(
                                      device.id,
                                      friend.id,
                                      value == true,
                                    );
                                if (!mounted) return;
                                setState(() => _devices = devices);
                                final refreshed = devices
                                    .where((item) => item.id == device.id)
                                    .firstOrNull;
                                if (refreshed != null) {
                                  device.delegateIds
                                    ..clear()
                                    ..addAll(refreshed.delegateIds);
                                }
                                setDialogState(() {});
                              }
                            : null,
                      );
                    }).toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeFriend(int id) async {
    final friends = await AccountService.removeFriend(id);
    if (mounted) setState(() => _friends = friends);
  }

  Future<void> _toggleDevice(DeviceRecord device) async {
    final devices = await AccountService.setDeviceControl(
      device.id,
      !device.canControl,
    );
    if (mounted) setState(() => _devices = devices);
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await AccountService.logout();
    await prefs.clear();
    await GraphQLConnection().dispose();
    if (!mounted) return;
    context.read<MusicPlayerController>().onLogout();
    context.go(LoginScreen.routeName);
  }

  Future<void> _showEditProfileDialog() async {
    final dialogFormKey = GlobalKey<FormState>();
    final profile = _profile;
    final displayController = TextEditingController(text: _displayName ?? '');
    final publicController = TextEditingController(
      text: profile?.publicInfo ?? '',
    );
    final friendsController = TextEditingController(
      text: profile?.friendsInfo ?? '',
    );
    final privateController = TextEditingController(
      text: profile?.privateInfo ?? '',
    );
    bool hasPublicPreference = profile?.hasPublicPreference ?? true;
    bool isSubmitting = false;

    await showDialog<_ProfileEditResult>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> submit() async {
            final isValid = dialogFormKey.currentState?.validate() ?? false;
            if (!isValid || isSubmitting) {
              return;
            }

            setDialogState(() {
              isSubmitting = true;
            });

            if (displayController.text.trim().isEmpty) return;

            setState(() => _isSaving = true);
            final outcome = await AccountService.updateProfile(
              displayName: displayController.text.trim(),
              publicInfo: publicController.text.trim(),
              friendsInfo: friendsController.text.trim(),
              privateInfo: privateController.text.trim(),
              hasPublicPreference: hasPublicPreference,
            );

            if (!dialogContext.mounted) {
              return;
            }

            Navigator.of(dialogContext).pop();

            if (!mounted) {
              return;
            }

            if (outcome.success) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(
                SharedPreferencesKeys.displayName,
                outcome.message,
              );
              await _loadProfile();
            } else {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(outcome.message)));
            }
            if (!mounted) return;
            setState(() => _isSaving = false);
          }

          return AlertDialog(
            title: const Text('Edit profile'),
            actions: [
              TextButton(
                onPressed: isSubmitting
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('profile_edit_save_button'),
                onPressed: isSubmitting ? null : submit,
                child: isSubmitting
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
            content: SingleChildScrollView(
              child: Form(
                key: dialogFormKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      key: const Key('profile_edit_display_name_field'),
                      controller: displayController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Display name cannot be empty';
                        }
                        return null;
                      },
                    ),
                    TextFormField(
                      controller: publicController,
                      decoration: const InputDecoration(
                        labelText: 'Public info',
                      ),
                      minLines: 1,
                      maxLines: 3,
                    ),
                    TextFormField(
                      controller: friendsController,
                      decoration: const InputDecoration(
                        labelText: 'Friends info',
                      ),
                      minLines: 1,
                      maxLines: 3,
                    ),
                    TextFormField(
                      controller: privateController,
                      decoration: const InputDecoration(
                        labelText: 'Private info',
                      ),
                      minLines: 1,
                      maxLines: 3,
                    ),
                    SwitchListTile(
                      title: const Text('Share preferences publicly'),
                      value: hasPublicPreference,
                      onChanged: (value) =>
                          setDialogState(() => hasPublicPreference = value),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _toggleGenre(int genreId) async {
    final next = {..._selectedGenreIds};
    if (!next.add(genreId)) {
      next.remove(genreId);
    }
    setState(() {
      _selectedGenreIds = next;
      _isSaving = true;
    });
    final profile = await AccountService.updateMusicPreferences(next.toList());
    if (!mounted) return;
    if (profile == null) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to update music preferences.')),
      );
      return;
    }
    setState(() {
      _profile = profile;
      _selectedGenreIds = profile.musicPreferenceGenreIds.toSet();
      _isSaving = false;
    });
  }

  Future<void> _linkGoogle() async {
    setState(() => _isSaving = true);
    String? idToken;
    try {
      idToken = await GoogleService().signIn();
    } catch (_) {
      idToken = null;
    }
    if (idToken == null) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Google Sign-In failed.')));
      return;
    }
    final outcome = await AccountService.linkGoogleAccount(idToken);
    if (!mounted) return;
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(outcome.message)));
    if (outcome.success) {
      await _loadProfile();
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account'),
        content: const Text(
          'This will permanently delete your account. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('profile_delete_confirm_button'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final outcome = await AccountService.deleteAccount();
    if (!mounted) return;
    if (outcome.success) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await AccountService.logout();
      if (!mounted) return;
      context.go(LoginScreen.routeName);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(outcome.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final headline = _displayName?.isNotEmpty == true
        ? _displayName!
        : (_email?.split('@').first ?? 'Music Room listener');

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_isSaving) ...[
                    const LinearProgressIndicator(minHeight: 2),
                    const SizedBox(height: 16),
                  ],
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF11141D),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 68,
                          height: 68,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Color(0xFFFF5F6D), Color(0xFFFFC371)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              headline.isNotEmpty
                                  ? headline[0].toUpperCase()
                                  : 'M',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                headline,
                                style: const TextStyle(
                                  color: Color(0xFFF4F7FB),
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _email ?? 'No active account email',
                                style: const TextStyle(
                                  color: Color(0xFF98A2B3),
                                  fontSize: 14,
                                ),
                              ),
                              if (_accountId != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Account #$_accountId',
                                  style: const TextStyle(
                                    color: Color(0xFFD0D5DD),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _ActionTile(
                    key: const Key('profile_edit_button'),
                    icon: Icons.edit_outlined,
                    label: 'Edit profile information',
                    onTap: _showEditProfileDialog,
                  ),
                  const SizedBox(height: 12),
                  _ActionTile(
                    icon: _profile!.googleLinked
                        ? Icons.check_circle_outline
                        : Icons.link,
                    label: _profile!.googleLinked
                        ? 'Google account linked'
                        : 'Link Google account',
                    onTap: _profile!.googleLinked ? null : _linkGoogle,
                  ),
                  const SizedBox(height: 24),
                  _ProfileSection(
                    title: 'Profile visibility',
                    children: [
                      _InfoLine(
                        label: 'Public',
                        value: _profile?.publicInfo ?? '',
                      ),
                      _InfoLine(
                        label: 'Friends',
                        value: _profile?.friendsInfo ?? '',
                      ),
                      _InfoLine(
                        label: 'Private',
                        value: _profile?.privateInfo ?? '',
                      ),
                      _InfoLine(
                        label: 'Preferences',
                        value: _profile?.hasPublicPreference == true
                            ? 'Visible publicly'
                            : 'Private',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _ProfileSection(
                    title: 'Music preferences',
                    children: [
                      if (_genres.isEmpty)
                        const Text(
                          'No genres available from the backend.',
                          style: TextStyle(color: Color(0xFF98A2B3)),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _genres.map((genre) {
                            final selected = _selectedGenreIds.contains(
                              genre.id,
                            );
                            return FilterChip(
                              key: Key('profile_genre_chip_${genre.id}'),
                              label: Text(genre.name),
                              selected: selected,
                              onSelected: (_) => _toggleGenre(genre.id),
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _ProfileSection(
                    title: 'Friends and requests',
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _requestFriend,
                          icon: const Icon(Icons.person_add),
                          label: const Text('Add friend'),
                        ),
                      ),
                      if (_friends.isEmpty)
                        const Text(
                          'No friends or pending requests.',
                          style: TextStyle(color: Color(0xFF98A2B3)),
                        ),
                      ..._friends.map(
                        (friend) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            friend.displayName.isEmpty
                                ? friend.email
                                : friend.displayName,
                          ),
                          subtitle: Text(
                            friend.status == 'ACCEPTED'
                                ? 'Friend'
                                : '${friend.direction.toLowerCase()} request',
                          ),
                          trailing:
                              friend.status == 'PENDING' &&
                                  friend.direction == 'INCOMING'
                              ? FilledButton(
                                  onPressed: () => _acceptFriend(friend.id),
                                  child: const Text('Accept'),
                                )
                              : IconButton(
                                  onPressed: () => _removeFriend(friend.id),
                                  icon: const Icon(Icons.close),
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _ProfileSection(
                    title: 'Devices and permissions',
                    children: [
                      if (_devices.isEmpty)
                        const Text(
                          'This device will be registered after the next login.',
                          style: TextStyle(color: Color(0xFF98A2B3)),
                        ),
                      ..._devices.map(
                        (device) => Column(
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(device.name),
                              subtitle: Text(
                                '${device.platform} · app ${device.appVersion} · ${device.delegateIds.length} delegate(s)',
                              ),
                              value: device.canControl,
                              onChanged: (_) => _toggleDevice(device),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () => _manageDelegates(device),
                                icon: const Icon(
                                  Icons.admin_panel_settings_outlined,
                                ),
                                label: const Text('Delegate to friends'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('profile_logout_button'),
                    onPressed: _logout,
                    child: const Text('Logout'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const Key('profile_delete_account_button'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    onPressed: _confirmDeleteAccount,
                    child: const Text('Delete account'),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ProfileEditResult {
  final String displayName;
  final String publicInfo;
  final String friendsInfo;
  final String privateInfo;
  final bool hasPublicPreference;

  const _ProfileEditResult({
    required this.displayName,
    required this.publicInfo,
    required this.friendsInfo,
    required this.privateInfo,
    required this.hasPublicPreference,
  });
}

class _ProfileSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _ProfileSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF11141D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFFF4F7FB),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _InfoLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF98A2B3),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? 'Not set' : value,
              style: const TextStyle(color: Color(0xFFF4F7FB)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionTile({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF11141D),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFFF7A45), size: 22),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFF4F7FB),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onTap != null) const Spacer(),
            if (onTap != null)
              const Icon(
                Icons.chevron_right,
                color: Color(0xFF98A2B3),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
