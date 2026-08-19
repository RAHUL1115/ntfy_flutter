import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_settings.dart';
import 'attachments.dart';
import 'messages.dart';
import 'notifications.dart';
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
  HttpNtfyStreamClient({this.profiles});

  final AppSettingsRepository? profiles;
  final _clients = <HttpClient>{};
  final _sockets = <WebSocket>{};

  @override
  Future<FeedConnection> connect({
    required String topicUrl,
    String? cursor,
  }) async {
    final topicUri = Uri.parse(topicUrl);
    final profile = await profiles?.profileFor(topicUri);
    await profiles?.addLogSafely(
      'Connecting ${profile?.protocol.name ?? 'http'} stream to ${topicUri.origin}',
    );
    if (profile?.protocol == ConnectionProtocol.websocket) {
      return _connectWebSocket(topicUri, cursor, profile!);
    }
    final uri = buildFeedUri(topicUrl, cursor);
    final client = HttpClient(context: profile?.securityContext);
    _clients.add(client);
    try {
      final request = await client.getUrl(uri);
      profile?.apply(request);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        client.close(force: true);
        _clients.remove(client);
        throw FeedHttpException(response.statusCode, uri);
      }
      await profiles?.addLogSafely('Connected stream to ${topicUri.origin}');

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
    } catch (error) {
      client.close(force: true);
      _clients.remove(client);
      await profiles?.addLogSafely(
        'Stream connection to ${topicUri.origin} failed: ${error.runtimeType}',
      );
      rethrow;
    }
  }

  Future<FeedConnection> _connectWebSocket(
    Uri topicUri,
    String? cursor,
    ConnectionProfile profile,
  ) async {
    final path = topicUri.path.endsWith('/')
        ? '${topicUri.path}ws'
        : '${topicUri.path}/ws';
    final uri = topicUri.replace(
      scheme: topicUri.scheme == 'https' ? 'wss' : 'ws',
      path: path,
      queryParameters: {'since': cursor ?? 'all'},
      fragment: null,
    );
    final headers = <String, dynamic>{};
    final account = profile.account;
    if (account != null) {
      headers[HttpHeaders.authorizationHeader] =
          'Basic ${base64Encode(utf8.encode('${account.username}:${account.password}'))}';
    }
    for (final header in profile.headers) {
      headers[header.name] = header.value;
    }
    final client = HttpClient(context: profile.securityContext);
    final socket = await WebSocket.connect(
      uri.toString(),
      headers: headers,
      customClient: client,
    );
    _clients.add(client);
    _sockets.add(socket);
    await profiles?.addLogSafely(
      'Connected WebSocket stream to ${topicUri.origin}',
    );
    return FeedConnection(
      lines: socket.where((event) => event is String).cast<String>(),
      onClose: () async {
        _sockets.remove(socket);
        await socket.close();
        _clients.remove(client);
        client.close(force: true);
      },
    );
  }

  @override
  Future<void> abort() async {
    for (final socket in List<WebSocket>.of(_sockets)) {
      await socket.close();
    }
    _sockets.clear();
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

class NtfyMessageEvent {
  const NtfyMessageEvent({required this.topic, required this.message});

  final String topic;
  final IncomingMessage message;
}

bool isNtfyProtocolLine(String line) {
  try {
    final decoded = jsonDecode(line);
    return decoded is Map<String, dynamic> &&
        (decoded['event'] == 'keepalive' ||
            decoded['event'] == 'message' ||
            decoded['event'] == 'message_clear' ||
            decoded['event'] == 'message_delete');
  } catch (_) {
    return false;
  }
}

NtfyMessageEvent? parseNtfyMessageEvent(String line) {
  try {
    final decoded = jsonDecode(line);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final event = switch (decoded['event']) {
      'message' => MessageEventType.message,
      'message_clear' => MessageEventType.clear,
      'message_delete' => MessageEventType.delete,
      _ => null,
    };
    if (event == null) return null;

    final topic = decoded['topic'];
    if (topic is! String || topic.isEmpty) return null;

    final eventId = decoded['id'];
    final time = decoded['time'];
    final message = decoded['message'] ?? '';
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
    final sequenceValue = decoded['sequence_id'];
    if (sequenceValue != null && sequenceValue is! String) return null;
    final clickValue = decoded['click'];
    if (clickValue != null && clickValue is! String) return null;
    final iconValue = decoded['icon'];
    if (iconValue != null && iconValue is! String) return null;
    final contentTypeValue = decoded['content_type'];
    if (contentTypeValue != null && contentTypeValue is! String) return null;
    final encodingValue = decoded['encoding'];
    if (encodingValue != null && encodingValue is! String) return null;
    final actionsValue = decoded['actions'];
    final actions = <MessageAction>[];
    if (actionsValue != null) {
      if (actionsValue is! List) return null;
      for (final value in actionsValue) {
        final action = MessageAction.fromJson(value);
        if (action == null) return null;
        actions.add(action);
      }
    }
    final attachmentValue = decoded['attachment'];
    MessageAttachment? attachment;
    if (attachmentValue != null) {
      if (attachmentValue is! Map) return null;
      final name = attachmentValue['name'];
      final url = attachmentValue['url'];
      if (name is! String || url is! String) return null;
      final size = attachmentValue['size'];
      final expires = attachmentValue['expires'];
      attachment = MessageAttachment(
        name: name,
        url: url,
        type: attachmentValue['type'] as String?,
        size: size is int ? size : null,
        expires: expires is int
            ? DateTime.fromMillisecondsSinceEpoch(expires * 1000, isUtc: true)
            : null,
      );
    }

    return NtfyMessageEvent(
      topic: topic,
      message: IncomingMessage(
        eventId: eventId,
        sequenceId: sequenceValue is String && sequenceValue.isNotEmpty
            ? sequenceValue
            : eventId,
        event: event,
        time: DateTime.fromMillisecondsSinceEpoch(time * 1000, isUtc: true),
        message: message,
        title: titleValue is String && titleValue.isNotEmpty
            ? titleValue
            : null,
        priority: priority,
        tags: List.unmodifiable(tags),
        click: clickValue is String && clickValue.isNotEmpty
            ? clickValue
            : null,
        icon: iconValue is String && iconValue.isNotEmpty ? iconValue : null,
        actions: List.unmodifiable(actions),
        contentType: contentTypeValue is String && contentTypeValue.isNotEmpty
            ? contentTypeValue
            : null,
        encoding: encodingValue is String && encodingValue.isNotEmpty
            ? encodingValue
            : null,
        attachment: attachment,
      ),
    );
  } catch (_) {
    return null;
  }
}

IncomingMessage? parseNtfyLine(String line, String expectedTopic) {
  final event = parseNtfyMessageEvent(line);
  return event?.topic == _topicName(expectedTopic) ? event?.message : null;
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

sealed class TopicFeedCommand {
  const TopicFeedCommand();
}

final class PublishTopicMessage extends TopicFeedCommand {
  const PublishTopicMessage(this.message);

  final PublishMessage message;
}

final class DeleteLocalMessage extends TopicFeedCommand {
  const DeleteLocalMessage(this.localId);

  final int localId;
}

final class RestoreLocalMessage extends TopicFeedCommand {
  const RestoreLocalMessage(this.message);

  final StoredMessage message;
}

final class ClearLocalMessages extends TopicFeedCommand {
  const ClearLocalMessages();
}

final class RefreshLocalMessages extends TopicFeedCommand {
  const RefreshLocalMessages();
}

final class ReconnectTopicFeed extends TopicFeedCommand {
  const ReconnectTopicFeed();
}

class TopicFeedSession {
  TopicFeedSession({required this.controller, NtfyPublisher? publisher})
    : publisher = publisher ?? HttpNtfyPublisher();

  final TopicFeedController controller;
  final NtfyPublisher publisher;

  FeedState get state => controller.state;
  Stream<FeedState> get states => controller.states;

  Future<void> start() => controller.start();

  Future<void> pause() => controller.pause();

  void resume() => controller.resume();

  Future<void> execute(TopicFeedCommand command) async {
    switch (command) {
      case PublishTopicMessage(:final message):
        await publisher.publish(controller.subscription.url, message);
      case DeleteLocalMessage(:final localId):
        await controller.deleteMessage(localId);
      case RestoreLocalMessage(:final message):
        await controller.restoreMessage(message);
      case ClearLocalMessages():
        await controller.clearMessages();
      case RefreshLocalMessages():
        await controller.refreshLocalMessages();
      case ReconnectTopicFeed():
        await controller.reconnect();
    }
  }

  Future<void> close() => controller.close();
}

class TopicFeedController {
  TopicFeedController({
    required this.repository,
    required this.subscription,
    required this.client,
    this.notifications,
    this.attachments,
    List<Duration>? retryDelays,
  }) : _retryDelays = List.unmodifiable(retryDelays ?? _defaultRetryDelays);

  final MessageRepository repository;
  final Subscription subscription;
  final NtfyStreamClient client;
  final MessageNotificationSession? notifications;
  final AttachmentAutoDownloader? attachments;
  final List<Duration> _retryDelays;
  final _states = StreamController<FeedState>.broadcast();

  FeedState _state = FeedState(status: FeedStatus.loading);
  List<StoredMessage> _messages = const [];
  String? _cursor;
  FeedConnection? _connection;
  Future<void>? _runFuture;
  Future<void> _operationTail = Future<void>.value();
  Timer? _retryTimer;
  Completer<void>? _retryCompleter;
  Completer<void>? _resumeCompleter;
  var _closed = false;
  var _paused = false;
  var _retryIndex = 0;
  var _retryImmediately = false;

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
      await _serialize(() async {
        final snapshot = await repository.loadFeed(subscription.id);
        if (_closed) return;
        _messages = List.unmodifiable(snapshot.messages);
        _cursor = snapshot.cursor;
        _emit(FeedStatus.connecting);
      });

      while (!_closed) {
        await _waitUntilResumed();
        if (_closed) return;
        FeedConnection? connection;
        try {
          connection = await client.connect(
            topicUrl: subscription.url,
            cursor: _cursor,
          );
          if (_closed) return;
          if (_paused) continue;

          _connection = connection;
          _emit(FeedStatus.connected);
          final result = await _readConnection(connection);
          if (_closed || result == _ConnectionResult.closed) return;
          if (_paused) continue;
          if (result == _ConnectionResult.socket) {
            _emit(FeedStatus.offline);
          } else {
            _emit(FeedStatus.reconnecting);
          }
        } catch (error) {
          if (_closed) return;
          if (_paused) continue;
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
        if (_paused) continue;
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
        if (isNtfyProtocolLine(line)) _retryIndex = 0;
        final incoming = parseNtfyLine(line, subscription.url);
        if (incoming == null) continue;

        await _serialize(() async {
          var stored = await repository.ingest(subscription.id, incoming);
          _cursor = incoming.eventId;
          if (incoming.event != MessageEventType.message) {
            await notifications?.handleControl(subscription, incoming);
          }
          if (stored == null) {
            await _refreshLocalMessages();
            return;
          }
          await notifications?.show(subscription, stored);
          _retryIndex = 0;
          final nextMessages = [..._messages, stored]
            ..sort(_compareStoredMessages);
          _messages = List.unmodifiable(nextMessages);
          _emit(FeedStatus.connected);
          _downloadAttachment(stored);
        });
      }
      return _closed ? _ConnectionResult.closed : _ConnectionResult.eof;
    } catch (error) {
      if (_closed) return _ConnectionResult.closed;
      if (_isSocketError(error)) return _ConnectionResult.socket;
      rethrow;
    }
  }

  void _downloadAttachment(StoredMessage stored) {
    final downloader = attachments;
    if (downloader == null || stored.attachment == null) return;
    unawaited(() async {
      try {
        final downloaded = await downloader.process(subscription, stored);
        if (downloaded.attachment?.localPath == stored.attachment?.localPath) {
          return;
        }
        await _serialize(() async {
          if (_closed) return;
          final index = _messages.indexWhere(
            (message) => message.localId == downloaded.localId,
          );
          if (index < 0) return;
          final nextMessages = [..._messages]..[index] = downloaded;
          _messages = List.unmodifiable(nextMessages);
          _emit(_state.status);
        });
      } catch (_) {
        // Attachment failures are represented by the still-remote attachment.
      }
    }());
  }

  Future<void> _waitForRetry() async {
    if (_retryImmediately) {
      _retryImmediately = false;
      return;
    }
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

  Future<void> _waitUntilResumed() async {
    if (!_paused || _closed) return;
    final completer = Completer<void>();
    _resumeCompleter = completer;
    await completer.future;
    if (identical(_resumeCompleter, completer)) _resumeCompleter = null;
  }

  Future<void> pause() async {
    if (_closed || _paused) return;
    _paused = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    final retry = _retryCompleter;
    if (retry != null && !retry.isCompleted) retry.complete();
    await _connection?.close();
  }

  void resume() {
    if (_closed || !_paused) return;
    _paused = false;
    _retryIndex = 0;
    final completer = _resumeCompleter;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  Future<StoredMessage?> deleteMessage(int localId) => _serialize(() async {
    final deleted = _messages
        .where((message) => message.localId == localId)
        .firstOrNull;
    if (deleted == null) return null;
    _messages = List.unmodifiable(
      _messages.where((message) => message.localId != localId),
    );
    _emit(_state.status, error: _state.error);
    try {
      await repository.deleteMessage(subscription.id, localId);
      return deleted;
    } catch (_) {
      _messages = List.unmodifiable(
        <StoredMessage>[..._messages, deleted]..sort(_compareStoredMessages),
      );
      _emit(_state.status, error: _state.error);
      rethrow;
    }
  });

  Future<void> restoreMessage(StoredMessage message) => _serialize(() async {
    if (message.subscriptionId != subscription.id) {
      throw ArgumentError.value(
        message.subscriptionId,
        'message.subscriptionId',
        'Must match the active subscription.',
      );
    }
    if (_messages.any((stored) => stored.eventId == message.eventId)) return;
    _messages = List.unmodifiable(
      <StoredMessage>[..._messages, message]..sort(_compareStoredMessages),
    );
    _emit(_state.status, error: _state.error);
    try {
      await repository.restoreMessage(subscription.id, message);
    } catch (_) {
      _messages = List.unmodifiable(
        _messages.where((stored) => stored.localId != message.localId),
      );
      _emit(_state.status, error: _state.error);
      rethrow;
    }
  });

  Future<void> clearMessages() => _serialize(() async {
    await repository.clearMessages(subscription.id);
    await _refreshLocalMessages();
  });

  Future<void> refreshLocalMessages() => _serialize(_refreshLocalMessages);

  Future<void> reconnect() async {
    if (_closed) return;
    _retryIndex = 0;
    _retryImmediately = true;
    final completer = _retryCompleter;
    if (completer != null && !completer.isCompleted) completer.complete();
    await _connection?.close();
  }

  Future<void> _refreshLocalMessages() async {
    final snapshot = await repository.loadFeed(subscription.id);
    _messages = List.unmodifiable(snapshot.messages);
    _cursor = snapshot.cursor;
    _emit(_state.status, error: _state.error);
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _operationTail.then((_) => operation());
    _operationTail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
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
    final resume = _resumeCompleter;
    if (resume != null && !resume.isCompleted) resume.complete();
    _resumeCompleter = null;

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
    await _operationTail;
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
