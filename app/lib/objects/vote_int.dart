int voteInt(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
