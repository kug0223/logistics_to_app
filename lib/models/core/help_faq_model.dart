class HelpFaqModel {
  final String id;
  final String role;     // 'user' | 'admin'
  final int order;
  final String category; // 카테고리 헤더명 (isHeader=true면 question과 동일)
  final String question;
  final String answer;
  final bool isHeader;
  final bool isActive;

  const HelpFaqModel({
    required this.id,
    required this.role,
    required this.order,
    required this.category,
    required this.question,
    required this.answer,
    required this.isHeader,
    required this.isActive,
  });

  factory HelpFaqModel.fromMap(Map<String, dynamic> map, String id) {
    return HelpFaqModel(
      id: id,
      role: map['role'] as String? ?? 'user',
      order: (map['order'] as num?)?.toInt() ?? 0,
      category: map['category'] as String? ?? '',
      question: map['question'] as String? ?? '',
      answer: map['answer'] as String? ?? '',
      isHeader: map['isHeader'] as bool? ?? false,
      isActive: map['isActive'] as bool? ?? true,
    );
  }

  static HelpFaqModel? tryFromMap(Map<String, dynamic>? map, String id) {
    if (map == null) return null;
    try {
      return HelpFaqModel.fromMap(map, id);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toMap() => {
    'role': role,
    'order': order,
    'category': category,
    'question': question,
    'answer': answer,
    'isHeader': isHeader,
    'isActive': isActive,
  };

  HelpFaqModel copyWith({
    String? role,
    int? order,
    String? category,
    String? question,
    String? answer,
    bool? isHeader,
    bool? isActive,
  }) {
    return HelpFaqModel(
      id: id,
      role: role ?? this.role,
      order: order ?? this.order,
      category: category ?? this.category,
      question: question ?? this.question,
      answer: answer ?? this.answer,
      isHeader: isHeader ?? this.isHeader,
      isActive: isActive ?? this.isActive,
    );
  }
}
