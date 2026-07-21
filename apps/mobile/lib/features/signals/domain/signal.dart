class SignalModel {
  const SignalModel({
    required this.id,
    required this.authorId,
    required this.category,
    required this.startsAt,
    required this.expiresAt,
    required this.state,
    required this.participantCount,
    this.text,
    this.emoji,
    this.authorName = 'Друг',
    this.locationLabel,
  });
  final String id;
  final String authorId;
  final String category;
  final String? text;
  final String? emoji;
  final DateTime startsAt;
  final DateTime expiresAt;
  final String state;
  final int participantCount;
  final String authorName;
  final String? locationLabel;

  factory SignalModel.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>?;
    final profile = author?['profile'] as Map<String, dynamic>?;
    final count = json['_count'] as Map<String, dynamic>?;
    return SignalModel(
      id: json['id'] as String,
      authorId: json['authorId'] as String,
      category: json['category'] as String,
      text: json['text'] as String?,
      emoji: json['emoji'] as String?,
      startsAt: DateTime.parse(json['startsAt'] as String).toLocal(),
      expiresAt: DateTime.parse(json['expiresAt'] as String).toLocal(),
      state: json['state'] as String,
      participantCount: count?['participants'] as int? ?? 1,
      authorName: profile?['displayName'] as String? ?? 'Друг',
      locationLabel:
          json['districtLabel'] as String? ?? json['cityLabel'] as String?,
    );
  }
}

const signalCategoryLabels = {
  'walk': ('Погулять', '🌿'),
  'game': ('Поиграть', '🎮'),
  'talk': ('Поговорить', '💬'),
  'movie': ('Посмотреть фильм', '🍿'),
  'study': ('Поучиться', '📚'),
  'food': ('Поесть', '🍜'),
  'trip': ('Куда-нибудь', '🛣️'),
  'music': ('Музыка', '🎧'),
  'company': ('Не хочу быть один', '🫶'),
  'other': ('Другое', '✨'),
};
