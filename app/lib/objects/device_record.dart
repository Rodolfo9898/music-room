class DeviceRecord {
  final int id;
  final String name, platform, appVersion;
  final bool canControl;
  final Set<int> delegateIds;
  const DeviceRecord({
    required this.id,
    required this.name,
    required this.platform,
    required this.appVersion,
    required this.canControl,
    required this.delegateIds,
  });
  factory DeviceRecord.fromJson(Map<String, dynamic> json) => DeviceRecord(
    id: (json['id'] as num).toInt(),
    name: json['name'] as String? ?? 'Unknown device',
    platform: json['platform'] as String? ?? 'unknown',
    appVersion: json['app_version'] as String? ?? 'unknown',
    canControl: json['can_control'] == true || json['can_control'] == 1,
    delegateIds: '${json['delegate_ids'] ?? ''}'
        .split(',')
        .map(int.tryParse)
        .whereType<int>()
        .toSet(),
  );
}
