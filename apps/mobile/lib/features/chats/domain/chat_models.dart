enum ConversationType { direct, group }

enum ConversationRole { owner, admin, member }

enum ChatMessageType {
  text,
  image,
  video,
  voice,
  file,
  location,
  system,
  signal,
  call,
  poll,
  storyReply,
}

enum MessageDeleteMode { none, self, everyone }

enum MessageDeliveryStatus { pending, sent, delivered, read, failed }

class ConversationMember {
  const ConversationMember({
    required this.userId,
    required this.role,
    required this.displayName,
    this.emoji,
    this.avatarMediaId,
  });

  factory ConversationMember.fromJson(Map<String, dynamic> json) =>
      ConversationMember(
        userId: json['userId'] as String,
        role: _enumFromWire(
          ConversationRole.values,
          json['role'],
          ConversationRole.member,
        ),
        displayName: json['displayName']?.toString() ?? 'Друг',
        emoji: json['emoji'] as String?,
        avatarMediaId: json['avatarMediaId'] as String?,
      );

  final String userId;
  final ConversationRole role;
  final String displayName;
  final String? emoji;
  final String? avatarMediaId;

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'role': role.name.toUpperCase(),
    'displayName': displayName,
    'emoji': emoji,
    'avatarMediaId': avatarMediaId,
  };
}

class MessageReadReceipt {
  const MessageReadReceipt({required this.userId, required this.readAt});

  factory MessageReadReceipt.fromJson(Map<String, dynamic> json) =>
      MessageReadReceipt(
        userId: json['userId'] as String,
        readAt: _date(json['readAt']),
      );

  final String userId;
  final DateTime readAt;

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'readAt': readAt.toUtc().toIso8601String(),
  };
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.type,
    required this.createdAt,
    this.senderId,
    this.clientMessageId,
    this.text,
    this.metadata = const {},
    this.replyToMessageId,
    this.forwardedFromMessageId,
    this.editedAt,
    this.deletedAt,
    this.deleteMode = MessageDeleteMode.none,
    this.readReceipts = const [],
    this.deliveryStatus = MessageDeliveryStatus.sent,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final receipts = (json['readReceipts'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (value) =>
              MessageReadReceipt.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList();
    final localStatus = json['_localStatus'] == null
        ? null
        : _enumFromWire(
            MessageDeliveryStatus.values,
            json['_localStatus'],
            MessageDeliveryStatus.sent,
          );
    final serverStatus = json['deliveryStatus'] == null
        ? null
        : _enumFromWire(
            MessageDeliveryStatus.values,
            json['deliveryStatus'],
            MessageDeliveryStatus.sent,
          );
    final status =
        localStatus == MessageDeliveryStatus.pending ||
            localStatus == MessageDeliveryStatus.failed
        ? localStatus!
        : serverStatus ?? localStatus ?? MessageDeliveryStatus.sent;
    return ChatMessage(
      id: json['id'] as String,
      conversationId: json['conversationId'] as String,
      senderId: json['senderId'] as String?,
      clientMessageId: json['clientMessageId'] as String?,
      type: _enumFromWire(
        ChatMessageType.values,
        json['type'],
        ChatMessageType.text,
      ),
      text: json['text'] as String?,
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : const {},
      replyToMessageId: json['replyToMessageId'] as String?,
      forwardedFromMessageId: json['forwardedFromMessageId'] as String?,
      createdAt: _date(json['createdAt']),
      editedAt: _nullableDate(json['editedAt']),
      deletedAt: _nullableDate(json['deletedAt']),
      deleteMode: _enumFromWire(
        MessageDeleteMode.values,
        json['deleteMode'],
        MessageDeleteMode.none,
      ),
      readReceipts: receipts,
      deliveryStatus: status,
    );
  }

  final String id;
  final String conversationId;
  final String? senderId;
  final String? clientMessageId;
  final ChatMessageType type;
  final String? text;
  final Map<String, dynamic> metadata;
  final String? replyToMessageId;
  final String? forwardedFromMessageId;
  final DateTime createdAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final MessageDeleteMode deleteMode;
  final List<MessageReadReceipt> readReceipts;
  final MessageDeliveryStatus deliveryStatus;

  ChatMessage normalizeDeliveryForViewer(String viewerId) {
    if (senderId != viewerId) return this;
    final readByAnotherMember = readReceipts.any(
      (receipt) => receipt.userId != viewerId,
    );
    if (readByAnotherMember) {
      return copyWith(deliveryStatus: MessageDeliveryStatus.read);
    }
    // Old cache rows may have inferred READ from the sender's own receipt.
    if (deliveryStatus == MessageDeliveryStatus.read) {
      return copyWith(deliveryStatus: MessageDeliveryStatus.sent);
    }
    return this;
  }

  ChatMessage markDelivered() => deliveryStatus == MessageDeliveryStatus.read
      ? this
      : copyWith(deliveryStatus: MessageDeliveryStatus.delivered);

  ChatMessage copyWith({
    String? id,
    String? text,
    DateTime? editedAt,
    DateTime? deletedAt,
    MessageDeleteMode? deleteMode,
    List<MessageReadReceipt>? readReceipts,
    MessageDeliveryStatus? deliveryStatus,
  }) => ChatMessage(
    id: id ?? this.id,
    conversationId: conversationId,
    senderId: senderId,
    clientMessageId: clientMessageId,
    type: type,
    text: text ?? this.text,
    metadata: metadata,
    replyToMessageId: replyToMessageId,
    forwardedFromMessageId: forwardedFromMessageId,
    createdAt: createdAt,
    editedAt: editedAt ?? this.editedAt,
    deletedAt: deletedAt ?? this.deletedAt,
    deleteMode: deleteMode ?? this.deleteMode,
    readReceipts: readReceipts ?? this.readReceipts,
    deliveryStatus: deliveryStatus ?? this.deliveryStatus,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'conversationId': conversationId,
    'senderId': senderId,
    'clientMessageId': clientMessageId,
    'type': _messageTypeWire(type),
    'text': text,
    'metadata': metadata,
    'replyToMessageId': replyToMessageId,
    'forwardedFromMessageId': forwardedFromMessageId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'editedAt': editedAt?.toUtc().toIso8601String(),
    'deletedAt': deletedAt?.toUtc().toIso8601String(),
    'deleteMode': deleteMode.name.toUpperCase(),
    'readReceipts': readReceipts.map((value) => value.toJson()).toList(),
    'deliveryStatus': deliveryStatus.name.toUpperCase(),
    if (deliveryStatus == MessageDeliveryStatus.pending ||
        deliveryStatus == MessageDeliveryStatus.failed)
      '_localStatus': deliveryStatus.name.toUpperCase(),
  };
}

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
    this.title,
    this.avatarMediaId,
    this.ownerId,
    this.lastMessageAt,
    this.role = ConversationRole.member,
    this.mutedUntil,
    this.members = const [],
    this.lastMessage,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isArchived = false,
    this.isTyping = false,
    this.hasActiveCall = false,
    this.hasActiveSignal = false,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    final membership = json['membership'] is Map
        ? Map<String, dynamic>.from(json['membership'] as Map)
        : const <String, dynamic>{};
    return ConversationSummary(
      id: json['id'] as String,
      type: _enumFromWire(
        ConversationType.values,
        json['type'],
        ConversationType.direct,
      ),
      title: json['title'] as String?,
      avatarMediaId: json['avatarMediaId'] as String?,
      ownerId: json['ownerId'] as String?,
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
      lastMessageAt: _nullableDate(json['lastMessageAt']),
      role: _enumFromWire(
        ConversationRole.values,
        membership['role'],
        ConversationRole.member,
      ),
      mutedUntil: _nullableDate(membership['mutedUntil']),
      members: (json['members'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (value) =>
                ConversationMember.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList(),
      lastMessage: json['lastMessage'] is Map
          ? ChatMessage.fromJson(
              Map<String, dynamic>.from(json['lastMessage'] as Map),
            )
          : null,
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      isPinned: json['isPinned'] == true,
      isArchived: json['isArchived'] == true,
      isTyping: json['isTyping'] == true,
      hasActiveCall: json['hasActiveCall'] == true,
      hasActiveSignal: json['hasActiveSignal'] == true,
    );
  }

  final String id;
  final ConversationType type;
  final String? title;
  final String? avatarMediaId;
  final String? ownerId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastMessageAt;
  final ConversationRole role;
  final DateTime? mutedUntil;
  final List<ConversationMember> members;
  final ChatMessage? lastMessage;
  final int unreadCount;
  final bool isPinned;
  final bool isArchived;
  final bool isTyping;
  final bool hasActiveCall;
  final bool hasActiveSignal;

  String displayTitle(String currentUserId) {
    final explicit = title?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final others = members.where((member) => member.userId != currentUserId);
    return others.isEmpty
        ? 'Сохранённые сообщения'
        : others.map((member) => member.displayName).join(', ');
  }

  String displayEmoji(String currentUserId) {
    if (type == ConversationType.group) return '◌';
    return members
            .where((member) => member.userId != currentUserId)
            .firstOrNull
            ?.emoji ??
        '🙂';
  }

  ConversationSummary copyWith({
    DateTime? updatedAt,
    DateTime? lastMessageAt,
    ChatMessage? lastMessage,
    int? unreadCount,
    bool? isTyping,
  }) => ConversationSummary(
    id: id,
    type: type,
    title: title,
    avatarMediaId: avatarMediaId,
    ownerId: ownerId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    role: role,
    mutedUntil: mutedUntil,
    members: members,
    lastMessage: lastMessage ?? this.lastMessage,
    unreadCount: unreadCount ?? this.unreadCount,
    isPinned: isPinned,
    isArchived: isArchived,
    isTyping: isTyping ?? this.isTyping,
    hasActiveCall: hasActiveCall,
    hasActiveSignal: hasActiveSignal,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name.toUpperCase(),
    'title': title,
    'avatarMediaId': avatarMediaId,
    'ownerId': ownerId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'lastMessageAt': lastMessageAt?.toUtc().toIso8601String(),
    'membership': {
      'role': role.name.toUpperCase(),
      'mutedUntil': mutedUntil?.toUtc().toIso8601String(),
    },
    'members': members.map((value) => value.toJson()).toList(),
    'lastMessage': lastMessage?.toJson(),
    'unreadCount': unreadCount,
    'isPinned': isPinned,
    'isArchived': isArchived,
    'isTyping': isTyping,
    'hasActiveCall': hasActiveCall,
    'hasActiveSignal': hasActiveSignal,
  };
}

class ConversationPage {
  const ConversationPage({required this.items, this.nextCursor});
  final List<ConversationSummary> items;
  final String? nextCursor;
}

class MessagePage {
  const MessagePage({required this.items, this.nextCursor});
  final List<ChatMessage> items;
  final String? nextCursor;
}

T _enumFromWire<T extends Enum>(List<T> values, dynamic raw, T fallback) {
  final normalized = raw?.toString().replaceAll('_', '').toLowerCase();
  return values.cast<T>().firstWhere(
    (value) => value.name.replaceAll('_', '').toLowerCase() == normalized,
    orElse: () => fallback,
  );
}

DateTime _date(dynamic value) =>
    DateTime.tryParse(value?.toString() ?? '')?.toLocal() ?? DateTime.now();

DateTime? _nullableDate(dynamic value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

String _messageTypeWire(ChatMessageType type) => switch (type) {
  ChatMessageType.storyReply => 'STORY_REPLY',
  _ => type.name.toUpperCase(),
};

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
