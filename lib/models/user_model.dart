class UserModel {
  final String uid;
  final String name;
  final String email;
  final bool isAdmin;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.isAdmin,
    this.createdAt,
    this.lastLoginAt,
  });

  // Firestore에서 데이터 가져올 때
  factory UserModel.fromMap(Map<String, dynamic> map, String uid) {
    return UserModel(
      uid: uid,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      isAdmin: map['isAdmin'] ?? false,
      createdAt: map['createdAt']?.toDate(),
      lastLoginAt: map['lastLoginAt']?.toDate(),
    );
  }

  // Firestore에 저장할 때
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'isAdmin': isAdmin,
      'createdAt': createdAt,
      'lastLoginAt': lastLoginAt,
    };
  }
}