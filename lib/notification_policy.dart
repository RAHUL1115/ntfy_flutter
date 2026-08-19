class NotificationPolicy {
  const NotificationPolicy({
    this.mutedUntilEpochSeconds = 0,
    this.minimumPriority = 1,
    this.insistentMaxPriority = false,
    this.attachmentDownloadMaxBytes = 1024 * 1024,
    this.subscriptionIconPath,
    this.dedicatedChannel = false,
  });

  static const untilResumed = -1;

  final int mutedUntilEpochSeconds;
  final int minimumPriority;
  final bool insistentMaxPriority;
  final int attachmentDownloadMaxBytes;
  final String? subscriptionIconPath;
  final bool dedicatedChannel;

  NotificationPolicy copyWith({
    int? mutedUntilEpochSeconds,
    int? minimumPriority,
    bool? insistentMaxPriority,
    int? attachmentDownloadMaxBytes,
    Object? subscriptionIconPath = _unsetPolicyValue,
    bool? dedicatedChannel,
  }) => NotificationPolicy(
    mutedUntilEpochSeconds:
        mutedUntilEpochSeconds ?? this.mutedUntilEpochSeconds,
    minimumPriority: minimumPriority ?? this.minimumPriority,
    insistentMaxPriority: insistentMaxPriority ?? this.insistentMaxPriority,
    attachmentDownloadMaxBytes:
        attachmentDownloadMaxBytes ?? this.attachmentDownloadMaxBytes,
    subscriptionIconPath: identical(subscriptionIconPath, _unsetPolicyValue)
        ? this.subscriptionIconPath
        : subscriptionIconPath as String?,
    dedicatedChannel: dedicatedChannel ?? this.dedicatedChannel,
  );

  bool allows(int priority, DateTime now) {
    if (priority < minimumPriority) return false;
    if (mutedUntilEpochSeconds == untilResumed) return false;
    return mutedUntilEpochSeconds <= now.toUtc().millisecondsSinceEpoch ~/ 1000;
  }
}

const _unsetPolicyValue = Object();

abstract interface class NotificationPolicyRepository {
  Future<NotificationPolicy> loadNotificationPolicy({int? subscriptionId});

  Future<void> setGlobalNotificationPolicy(NotificationPolicy policy);

  Future<void> setTopicNotificationPolicy(
    int subscriptionId,
    NotificationPolicy? policy,
  );
}

class TopicNotificationPolicyOverrides {
  const TopicNotificationPolicyOverrides({
    this.mutedUntilEpochSeconds,
    this.minimumPriority,
    this.insistentMaxPriority,
    this.attachmentDownloadMaxBytes,
    this.subscriptionIconPath,
    this.dedicatedChannel,
  });

  final int? mutedUntilEpochSeconds;
  final int? minimumPriority;
  final bool? insistentMaxPriority;
  final int? attachmentDownloadMaxBytes;
  final String? subscriptionIconPath;
  final bool? dedicatedChannel;

  TopicNotificationPolicyOverrides copyWith({
    Object? mutedUntilEpochSeconds = _unsetPolicyValue,
    Object? minimumPriority = _unsetPolicyValue,
    Object? insistentMaxPriority = _unsetPolicyValue,
    Object? attachmentDownloadMaxBytes = _unsetPolicyValue,
    Object? subscriptionIconPath = _unsetPolicyValue,
    Object? dedicatedChannel = _unsetPolicyValue,
  }) => TopicNotificationPolicyOverrides(
    mutedUntilEpochSeconds: identical(mutedUntilEpochSeconds, _unsetPolicyValue)
        ? this.mutedUntilEpochSeconds
        : mutedUntilEpochSeconds as int?,
    minimumPriority: identical(minimumPriority, _unsetPolicyValue)
        ? this.minimumPriority
        : minimumPriority as int?,
    insistentMaxPriority: identical(insistentMaxPriority, _unsetPolicyValue)
        ? this.insistentMaxPriority
        : insistentMaxPriority as bool?,
    attachmentDownloadMaxBytes:
        identical(attachmentDownloadMaxBytes, _unsetPolicyValue)
        ? this.attachmentDownloadMaxBytes
        : attachmentDownloadMaxBytes as int?,
    subscriptionIconPath: identical(subscriptionIconPath, _unsetPolicyValue)
        ? this.subscriptionIconPath
        : subscriptionIconPath as String?,
    dedicatedChannel: identical(dedicatedChannel, _unsetPolicyValue)
        ? this.dedicatedChannel
        : dedicatedChannel as bool?,
  );
}

abstract interface class TopicNotificationPolicyRepository {
  Future<TopicNotificationPolicyOverrides> loadTopicNotificationPolicyOverrides(
    int subscriptionId,
  );

  Future<void> setTopicNotificationPolicyOverrides(
    int subscriptionId,
    TopicNotificationPolicyOverrides overrides,
  );
}
