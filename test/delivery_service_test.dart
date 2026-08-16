import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/delivery_service.dart';
import 'package:ntfy_flutter/notification_service.dart';

void main() {
  test('reconnect delay grows exponentially and is bounded', () {
    expect(reconnectDelay(-1), const Duration(seconds: 1));
    expect(reconnectDelay(0), const Duration(seconds: 1));
    expect(reconnectDelay(3), const Duration(seconds: 8));
    expect(reconnectDelay(20), const Duration(seconds: 64));
  });

  test('delivery and notification payloads reject malformed values', () {
    expect(isDeliveryReloadPayload('reload'), isTrue);
    expect(isDeliveryReloadPayload('other'), isFalse);
    expect(isDeliveryReloadPayload({'type': 'reload'}), isFalse);
    expect(parseSubscriptionPayload('42'), 42);
    expect(parseSubscriptionPayload('topic'), isNull);
    expect(parseSubscriptionPayload(null), isNull);
  });
}
