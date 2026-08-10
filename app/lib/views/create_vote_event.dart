part of 'track_vote.dart';

class CreateVoteEventScreen extends StatefulWidget {
  static const routeName = '/track-vote/create';

  const CreateVoteEventScreen({super.key});

  @override
  State<CreateVoteEventScreen> createState() => _CreateVoteEventScreenState();
}

class _CreateVoteEventScreenState extends State<CreateVoteEventScreen> {
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  bool _isPublic = true;
  String _policy = 'EVERYONE';
  DateTime? _startsAt;
  DateTime? _endsAt;
  bool _isSubmitting = false;
  double _radiusMeters = 1000;

  static const double _minRadiusMeters = 100;
  static const double _maxRadiusMeters = 10000;

  bool get _isLocationTime => _policy == 'LOCATION_TIME';

  String _formatRadius(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial ?? now),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickStartsAt() async {
    final picked = await _pickDateTime(_startsAt);
    if (picked != null) setState(() => _startsAt = picked);
  }

  Future<void> _pickEndsAt() async {
    final picked = await _pickDateTime(_endsAt);
    if (picked != null) setState(() => _endsAt = picked);
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return 'Select';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _message('Event name is required');
      return;
    }
    if (_isLocationTime) {
      if (_locationController.text.trim().isEmpty) {
        _message('Location is required');
        return;
      }
      if (_startsAt == null || _endsAt == null) {
        _message('Start and end time are required');
        return;
      }
      if (!_endsAt!.isAfter(_startsAt!)) {
        _message('End time must be after start time');
        return;
      }
    }

    setState(() => _isSubmitting = true);
    final result = await GraphQLConnection().client!.value.mutate(
      MutationOptions(
        document: gql(_fields(_createMutation)),
        variables: {
          'name': name,
          'isPublic': _isPublic,
          'votePolicy': _policy,
          'location': _isLocationTime ? _locationController.text.trim() : null,
          'radiusMeters': _isLocationTime ? _radiusMeters.round() : null,
          'startsAt': _isLocationTime
              ? _startsAt!.toUtc().toIso8601String()
              : null,
          'endsAt': _isLocationTime ? _endsAt!.toUtc().toIso8601String() : null,
        },
      ),
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (result.hasException) {
      _message(result.exception.toString());
      return;
    }
    final event = VoteEvent.fromJson(result.data?['createVoteEvent']);
    Navigator.of(context).pop(event);
  }

  void _message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));

  @override
  Widget build(BuildContext context) {
    return MusicRoomScaffold(
      appBar: AppBar(title: const Text('New voting event')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            key: const Key('track_vote_create_name_field'),
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Event name'),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            key: const Key('track_vote_create_public_switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Public event'),
            value: _isPublic,
            onChanged: (value) => setState(() {
              _isPublic = value;
              // A private event with an unmanaged "Everyone" policy has no
              // invite mechanism for other users to even view it, so fall
              // back to an invite-managed policy instead.
              if (!_isPublic && _policy == 'EVERYONE') {
                _policy = 'INVITED';
              }
            }),
          ),
          DropdownButtonFormField<String>(
            key: const Key('track_vote_create_policy_dropdown'),
            initialValue: _policy,
            decoration: const InputDecoration(labelText: 'Voting license'),
            items: [
              DropdownMenuItem(
                value: 'EVERYONE',
                enabled: _isPublic,
                child: Text(
                  'Everyone',
                  style: _isPublic
                      ? null
                      : TextStyle(color: Theme.of(context).disabledColor),
                ),
              ),
              const DropdownMenuItem(
                value: 'INVITED',
                child: Text('Invited users only'),
              ),
              const DropdownMenuItem(
                value: 'LOCATION_TIME',
                child: Text('Nearby during time window'),
              ),
            ],
            onChanged: (value) => setState(() => _policy = value ?? 'EVERYONE'),
          ),
          if (_isLocationTime) ...[
            const SizedBox(height: 12),
            TextField(
              key: const Key('track_vote_create_location_field'),
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'Location',
                hintText: 'e.g. Eiffel Tower, Paris',
              ),
            ),
            const SizedBox(height: 12),
            Text('Radius: ${_formatRadius(_radiusMeters)}'),
            Slider(
              key: const Key('track_vote_create_radius_slider'),
              value: _radiusMeters,
              min: _minRadiusMeters,
              max: _maxRadiusMeters,
              divisions: ((_maxRadiusMeters - _minRadiusMeters) / 100).round(),
              label: _formatRadius(_radiusMeters),
              onChanged: (value) => setState(() => _radiusMeters = value),
            ),
            const SizedBox(height: 12),
            ListTile(
              key: const Key('track_vote_create_starts_at_tile'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Start time'),
              subtitle: Text(_formatDateTime(_startsAt)),
              trailing: const Icon(Icons.edit_calendar),
              onTap: _pickStartsAt,
            ),
            ListTile(
              key: const Key('track_vote_create_ends_at_tile'),
              contentPadding: EdgeInsets.zero,
              title: const Text('End time'),
              subtitle: Text(_formatDateTime(_endsAt)),
              trailing: const Icon(Icons.edit_calendar),
              onTap: _pickEndsAt,
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('track_vote_create_submit_button'),
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create'),
          ),
        ],
      ),
    );
  }
}
