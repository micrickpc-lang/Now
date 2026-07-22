import 'package:flutter_test/flutter_test.dart';
import 'package:seychas/features/chats/domain/chat_models.dart';

void main() {
  test('parses the backend conversation and message contracts', () {
    final conversation = ConversationSummary.fromJson({
      'id': 'conversation-1',
      'type': 'DIRECT',
      'title': null,
      'createdAt': '2026-07-22T10:00:00.000Z',
      'updatedAt': '2026-07-22T10:05:00.000Z',
      'lastMessageAt': '2026-07-22T10:05:00.000Z',
      'membership': {'role': 'MEMBER', 'mutedUntil': null},
      'members': [
        {'userId': 'me', 'role': 'MEMBER', 'displayName': 'Я', 'emoji': '✨'},
        {
          'userId': 'friend',
          'role': 'MEMBER',
          'displayName': 'Аня',
          'emoji': '🌸',
        },
      ],
      'lastMessage': {
        'id': 'message-1',
        'conversationId': 'conversation-1',
        'senderId': 'friend',
        'clientMessageId': null,
        'type': 'TEXT',
        'text': 'Привет',
        'metadata': <String, dynamic>{},
        'createdAt': '2026-07-22T10:05:00.000Z',
        'deleteMode': 'NONE',
        'readReceipts': <dynamic>[],
      },
      'unreadCount': 1,
    });

    expect(conversation.type, ConversationType.direct);
    expect(conversation.displayTitle('me'), 'Аня');
    expect(conversation.displayEmoji('me'), '🌸');
    expect(conversation.lastMessage?.text, 'Привет');
    expect(conversation.unreadCount, 1);
  });

  test('local delivery status survives cache serialization', () {
    final message = ChatMessage(
      id: 'local-1',
      conversationId: 'conversation-1',
      senderId: 'me',
      clientMessageId: 'client-1',
      type: ChatMessageType.text,
      text: 'В очереди',
      createdAt: DateTime(2026, 7, 22, 12),
      deliveryStatus: MessageDeliveryStatus.failed,
    );

    final restored = ChatMessage.fromJson(message.toJson());
    expect(restored.clientMessageId, 'client-1');
    expect(restored.deliveryStatus, MessageDeliveryStatus.failed);
  });

  test('sender receipt alone does not mark an outgoing message as read', () {
    final serverMessage = ChatMessage.fromJson({
      'id': 'message-1',
      'conversationId': 'conversation-1',
      'senderId': 'me',
      'type': 'TEXT',
      'text': 'Привет',
      'createdAt': '2026-07-22T10:05:00.000Z',
      'readReceipts': [
        {'userId': 'me', 'readAt': '2026-07-22T10:05:00.000Z'},
      ],
    });

    expect(
      serverMessage.normalizeDeliveryForViewer('me').deliveryStatus,
      MessageDeliveryStatus.sent,
    );

    final readByFriend = ChatMessage.fromJson({
      ...serverMessage.toJson()..remove('_localStatus'),
      'readReceipts': [
        {'userId': 'me', 'readAt': '2026-07-22T10:05:00.000Z'},
        {'userId': 'friend', 'readAt': '2026-07-22T10:06:00.000Z'},
      ],
    });
    expect(
      readByFriend.normalizeDeliveryForViewer('me').deliveryStatus,
      MessageDeliveryStatus.read,
    );
  });

  test('uses viewer-aware server delivery status for non-outbox messages', () {
    Map<String, dynamic> payload(String status) => {
      'id': 'message-$status',
      'conversationId': 'conversation-1',
      'senderId': 'me',
      'type': 'TEXT',
      'text': 'Привет',
      'createdAt': '2026-07-22T10:05:00.000Z',
      'deliveryStatus': status,
      'readReceipts': status == 'READ'
          ? [
              {'userId': 'friend', 'readAt': '2026-07-22T10:06:00.000Z'},
            ]
          : <dynamic>[],
    };

    expect(
      ChatMessage.fromJson(
        payload('DELIVERED'),
      ).normalizeDeliveryForViewer('me').deliveryStatus,
      MessageDeliveryStatus.delivered,
    );
    expect(
      ChatMessage.fromJson(
        payload('READ'),
      ).normalizeDeliveryForViewer('me').deliveryStatus,
      MessageDeliveryStatus.read,
    );
  });

  test('delivery event advances SENT but never downgrades READ', () {
    final sent = ChatMessage(
      id: 'sent',
      conversationId: 'conversation-1',
      senderId: 'me',
      type: ChatMessageType.text,
      text: 'Привет',
      createdAt: DateTime(2026, 7, 22),
    );
    final read = sent.copyWith(deliveryStatus: MessageDeliveryStatus.read);

    expect(
      sent.markDelivered().deliveryStatus,
      MessageDeliveryStatus.delivered,
    );
    expect(read.markDelivered().deliveryStatus, MessageDeliveryStatus.read);
  });
}
