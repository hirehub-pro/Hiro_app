import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/services/chat_write_service.dart';

void main() {
  test('messageIdFor matches the server chat message ID', () {
    expect(
      ChatWriteService.messageIdFor(
        senderId: 'sender-123',
        idempotencyKey: 'client-message-456',
      ),
      '0be6970e465df5f206b5ef15e23f0f5c3c13601979b8eae8102ec587b72dd9e0',
    );
  });

  test('createIdempotencyKey creates bounded non-empty keys', () {
    final first = ChatWriteService.createIdempotencyKey();
    final second = ChatWriteService.createIdempotencyKey();

    expect(first, isNotEmpty);
    expect(first.length, lessThanOrEqualTo(240));
    expect(second, isNot(first));
  });
}
