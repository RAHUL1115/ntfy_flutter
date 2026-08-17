import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'messages.dart';
import 'publish.dart';
import 'subscriptions.dart';

enum FeedStatus { loading, connecting, connected, reconnecting, offline, error }

class FeedState {
  FeedState({
    required this.status,
    List<StoredMessage> messages = const [],
    this.cursor,
    this.error,
  }) : messages = List.unmodifiable(messages);

  final FeedStatus status;
  final List<StoredMessage> messages;
  final String? cursor;
  final Object? error;

  String? get errorMessage => error?.toString();
}

class FeedConnection {
  FeedConnection({required this.lines, this._onClose});

  final Stream<String> lines;
  final FutureOr<void> Function()? _onClose;
  var _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _onClose?.call();
  }
}

abstract interface class NtfyStreamClient {
  Future<FeedConnection> connect({required String topicUrl, String? cursor});
}

abstract interface class AbortableNtfyStreamClient {
  Future<void> abort();
}

class FeedHttpException implements Exception {
  const FeedHttpException(this.statusCode, this.uri);

  final int statusCode;
  final Uri uri;

  @override
  String toString() => 'ntfy returned HTTP $statusCode for $uri.';
}

class HttpNtfyStreamClient
    implements NtfyStreamClient, AbortableNtfyStreamClient {
  final _clients = <HttpClient>{};

  @override
  Future<FeedConnection> connect({
    required String topicUrl,
    String? cursor,
  }) async {
    final uri = buildFeedUri(topicUrl, cursor);
    final client = HttpClient();
    _clients.add(client);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        client.close(force: true);
        _clients.remove(client);
        throw FeedHttpException(response.statusCode, uri);
      }

      var closed = false;
      Future<void> closeClient() async {
        if (closed) return;
        closed = true;
        client.close(force: true);
        _clients.remove(client);
      }

      return FeedConnection(
        lines: response
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter()),
        onClose: closeClient,
      );
    } catch (_) {
      client.close(force: true);
      _clients.remove(client);
      rethrow;
    }
  }

  @override
  Future<void> abort() async {
    for (final client in List<HttpClient>.of(_clients)) {
      client.close(force: true);
    }
    _clients.clear();
  }
}

Uri buildFeedUri(String topicUrl, String? cursor) {
  final topicUri = Uri.parse(topicUrl);
  final path = topicUri.path.endsWith('/')
      ? '${topicUri.path}json'
      : '${topicUri.path}/json';
  return topicUri.replace(
    path: path,
    queryParameters: {'since': cursor ?? 'all'},
    fragment: null,
  );
}

IncomingMessage? parseNtfyLine(String line, String expectedTopic) {
  try {
    final decoded = jsonDecode(line);
    if (decoded is! Map<String, dynamic> || decoded['event'] != 'message') {
      return null;
    }

    final topic = decoded['topic'];
    if (topic is! String || topic != _topicName(expectedTopic)) return null;

    final eventId = decoded['id'];
    final time = decoded['time'];
    final message = decoded['message'];
    if (eventId is! String ||
        eventId.isEmpty ||
        time is! int ||
        time < 0 ||
        message is! String) {
      return null;
    }

    final titleValue = decoded['title'];
    if (titleValue != null && titleValue is! String) return null;

    final priorityValue = decoded['priority'];
    final priority = priorityValue ?? 3;
    if (priority is! int || priority < 1 || priority > 5) return null;

    final tagsValue = decoded['tags'];
    final tags = tagsValue == null
        ? const <String>[]
        : tagsValue is List && tagsValue.every((tag) => tag is String)
        ? List<String>.from(tagsValue)
        : null;
    if (tags == null) return null;

    return IncomingMessage(
      eventId: eventId,
      time: DateTime.fromMillisecondsSinceEpoch(time * 1000, isUtc: true),
      message: message,
      title: titleValue is String && titleValue.isNotEmpty ? titleValue : null,
      priority: priority,
      tags: List.unmodifiable(tags),
    );
  } catch (_) {
    return null;
  }
}

String _topicName(String value) {
  final uri = Uri.tryParse(value);
  if (uri != null && uri.hasScheme) {
    final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
    if (segments.isNotEmpty) return Uri.decodeComponent(segments.last);
  }
  final path = value.split('?').first.split('#').first;
  final segment = path.split('/').where((part) => part.isNotEmpty).lastOrNull;
  return segment == null ? value : Uri.decodeComponent(segment);
}

const _defaultRetryDelays = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
  Duration(seconds: 16),
  Duration(seconds: 30),
];

typedef TopicFeedFactory = TopicFeedSession Function(Subscription subscription);

class TopicFeedSession {
  TopicFeedSession({required this.controller, NtfyPublisher? publisher})
    : publisher = publisher ?? HttpNtfyPublisher();

  final TopicFeedController controller;
  final NtfyPublisher publisher;

  FeedState get state => controller.state;
  Stream<FeedState> get states => controller.states;

  Future<void> start() => controller.start();
  Future<void> publish(PublishMessage message) =>
      publisher.publish(controller.subscription.url, message);
  Future<void> close() => controller.close();
}

class TopicFeedController {
  TopicFeedController({
    required this.repository,
    required this.subscription,
    required this.client,
    List<Duration>? retryDelays,
  }) : _retryDelays = List.unmodifiable(retryDelays ?? _defaultRetryDelays);

  final MessageRepository repository;
  final Subscription subscription;
  final NtfyStreamClient client;
  final List<Duration> _retryDelays;
  final _states = StreamController<FeedState>.broadcast();

  FeedState _state = FeedState(status: FeedStatus.loading);
  List<StoredMessage> _messages = const [];
  String? _cursor;
  FeedConnection? _connection;
  Future<void>? _runFuture;
  Timer? _retryTimer;
  Completer<void>? _retryCompleter;
  var _closed = false;
  var _retryIndex = 0;

  FeedState get state => _state;
  Stream<FeedState> get states => _states.stream;

  Future<void> start() {
    if (_runFuture != null) return _runFuture!;
    if (_closed) return Future<void>.value();
    final future = _run();
    _runFuture = future;
    return future;
  }

  Future<void> _run() async {
    try {
      final snapshot = await repository.loadFeed(subscription.id);
      if (_closed) return;
      _messages = List.unmodifiable(snapshot.messages);
      _cursor = snapshot.cursor;
      _emit(FeedStatus.connecting);

      while (!_closed) {
        FeedConnection? connection;
        try {
          connection = await client.connect(
            topicUrl: subscription.url,
            cursor: _cursor,
          );
          if (_closed) return;

          _connection = connection;
          _retryIndex = 0;
          _emit(FeedStatus.connected);
          final result = await _readConnection(connection);
          if (_closed || result == _ConnectionResult.closed) return;
          if (result == _ConnectionResult.socket) {
            _emit(FeedStatus.offline);
          } else {
            _emit(FeedStatus.reconnecting);
          }
        } catch (error) {
          if (_closed) return;
          if (!_isSocketError(error)) {
            _emit(FeedStatus.error, error: error);
            return;
          }
          _emit(FeedStatus.offline, error: error);
        } finally {
          if (identical(_connection, connection)) _connection = null;
          try {
            await connection?.close();
          } catch (_) {
            // Closing a failed socket is best effort.
          }
        }

        if (_closed) return;
        await _waitForRetry();
        if (!_closed) _emit(FeedStatus.reconnecting);
      }
    } catch (error) {
      if (!_closed) _emit(FeedStatus.error, error: error);
    }
  }

  Future<_ConnectionResult> _readConnection(FeedConnection connection) async {
    try {
      await for (final line in connection.lines) {
        if (_closed) return _ConnectionResult.closed;
        final incoming = parseNtfyLine(line, subscription.url);
        if (incoming == null) continue;

        final stored = await repository.ingest(subscription.id, incoming);
        if (stored == null) continue;
        _cursor = stored.eventId;
        _retryIndex = 0;
        final nextMessages = [..._messages, stored]
          ..sort(_compareStoredMessages);
        _messages = List.unmodifiable(nextMessages);
        _emit(FeedStatus.connected);
      }
      return _closed ? _ConnectionResult.closed : _ConnectionResult.eof;
    } catch (error) {
      if (_closed) return _ConnectionResult.closed;
      if (_isSocketError(error)) return _ConnectionResult.socket;
      rethrow;
    }
  }

  Future<void> _waitForRetry() async {
    final delay = _retryDelays.isEmpty
        ? Duration.zero
        : _retryDelays[_retryIndex.clamp(0, _retryDelays.length - 1)];
    if (_retryIndex < _retryDelays.length - 1) _retryIndex++;
    if (delay == Duration.zero || _closed) return;

    final completer = Completer<void>();
    _retryCompleter = completer;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
    if (identical(_retryCompleter, completer)) _retryCompleter = null;
  }

  void _emit(FeedStatus status, {Object? error}) {
    if (_closed || _states.isClosed) return;
    _state = FeedState(
      status: status,
      messages: _messages,
      cursor: _cursor,
      error: error,
    );
    _states.add(_state);
  }

  Future<void> close() async {
    if (_closed) {
      final run = _runFuture;
      if (run != null) await run;
      return;
    }
    _closed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    final completer = _retryCompleter;
    if (completer != null && !completer.isCompleted) completer.complete();
    _retryCompleter = null;

    final connection = _connection;
    if (connection != null) {
      try {
        await connection.close();
      } catch (_) {
        // Closing is best effort during cancellation.
      }
    }
    if (client case final AbortableNtfyStreamClient abortable) {
      await abortable.abort();
    }

    final run = _runFuture;
    if (run != null) await run;
    await _states.close();
  }

  static int _compareStoredMessages(StoredMessage left, StoredMessage right) {
    final byTime = left.time.compareTo(right.time);
    if (byTime != 0) return byTime;
    return left.localId.compareTo(right.localId);
  }
}

enum _ConnectionResult { eof, socket, closed }

bool _isSocketError(Object error) =>
    error is SocketException ||
    error is HttpException ||
    error is HandshakeException ||
    error is TimeoutException;
