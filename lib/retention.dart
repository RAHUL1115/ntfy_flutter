import 'dart:async';

enum RetentionPeriod {
  never(Duration.zero, 'Never'),
  oneHour(Duration(hours: 1), 'After 1 hour'),
  threeHours(Duration(hours: 3), 'After 3 hours'),
  sixHours(Duration(hours: 6), 'After 6 hours'),
  twelveHours(Duration(hours: 12), 'After 12 hours'),
  oneDay(Duration(days: 1), 'After 1 day'),
  threeDays(Duration(days: 3), 'After 3 days'),
  tenDays(Duration(days: 10), 'After 10 days'),
  thirtyDays(Duration(days: 30), 'After 30 days');

  const RetentionPeriod(this.duration, this.label);

  final Duration duration;
  final String label;

  int get seconds => duration.inSeconds;

  String get summary => this == never
      ? 'Never auto-delete notifications'
      : 'Auto-delete notifications ${label.toLowerCase()}';

  static RetentionPeriod fromSeconds(int seconds) => values.firstWhere(
    (period) => period.seconds == seconds,
    orElse: () => throw StateError('Unsupported retention value: $seconds'),
  );
}

class RetentionSettings {
  const RetentionSettings({required this.global, this.override});

  final RetentionPeriod global;
  final RetentionPeriod? override;

  RetentionPeriod get effective => override ?? global;
  bool get inheritsGlobal => override == null;

  String get summary =>
      '${effective.summary}${inheritsGlobal ? ' (using global setting)' : ''}';
}

sealed class RetentionCommand {
  const RetentionCommand({required this.now});

  final DateTime now;
}

final class SetGlobalRetention extends RetentionCommand {
  const SetGlobalRetention(this.period, {required super.now});

  final RetentionPeriod period;
}

final class SetTopicRetention extends RetentionCommand {
  const SetTopicRetention(
    this.subscriptionId,
    this.period, {
    required super.now,
  });

  final int subscriptionId;
  final RetentionPeriod? period;
}

final class RunRetentionCleanup extends RetentionCommand {
  const RunRetentionCleanup(DateTime now) : super(now: now);
}

abstract interface class RetentionRepository {
  Future<RetentionSettings> loadRetention({int? subscriptionId});

  Future<void> executeRetention(RetentionCommand command);
}

class RetentionSession {
  RetentionSession(
    this._repository, {
    this.cleanupInterval = const Duration(minutes: 1),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final RetentionRepository _repository;
  final Duration cleanupInterval;
  final DateTime Function() _now;
  final _changes = StreamController<void>.broadcast();
  Future<void> _commandTail = Future<void>.value();
  Timer? _timer;
  bool _closed = false;

  Stream<void> get changes => _changes.stream;

  Future<RetentionSettings> load({int? subscriptionId}) =>
      _repository.loadRetention(subscriptionId: subscriptionId);

  void start() {
    if (_closed || _timer != null) return;
    _runAutomaticCleanup();
    _timer = Timer.periodic(cleanupInterval, (_) => _runAutomaticCleanup());
  }

  Future<void> execute(RetentionCommand command) {
    final result = _commandTail.then(
      (_) => _repository.executeRetention(command),
    );
    _commandTail = result.then<void>((_) {}, onError: (_, _) {});
    return result.then((_) {
      if (!_closed) _changes.add(null);
    });
  }

  void _runAutomaticCleanup() {
    unawaited(
      execute(RunRetentionCleanup(_now().toUtc())).catchError((_) {
        // Retention is best effort; cleanup must never prevent app startup.
      }),
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    await _commandTail;
    await _changes.close();
  }
}
