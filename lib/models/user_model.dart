// 사용자 권한 enum
enum UserRole {
  SUPER_ADMIN,    // 슈퍼관리자 (플랫폼 운영자)
  BUSINESS_ADMIN, // 사업장 관리자 (사장님)
  USER            // 일반 사용자 (지원자)
}

class UserModel {
  final String uid;
  final String name;
  final String email;
  final String? phone;
  final UserRole role;
  final String? businessId;  // 사업장 관리자의 경우 사업장 ID
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    this.phone,
    required this.role,
    this.businessId,
    this.createdAt,
    this.lastLoginAt,
  });

  // 편의 메서드: 슈퍼관리자인지 확인
  bool get isSuperAdmin => role == UserRole.SUPER_ADMIN;
  
  // 편의 메서드: 사업장 관리자인지 확인
  bool get isBusinessAdmin => role == UserRole.BUSINESS_ADMIN;
  
  // 편의 메서드: 일반 사용자인지 확인
  bool get isUser => role == UserRole.USER;
  
  // 편의 메서드: 관리자 권한이 있는지 (슈퍼 또는 사업장 관리자)
  bool get isAdmin => role == UserRole.SUPER_ADMIN || role == UserRole.BUSINESS_ADMIN;

  // Firestore에서 데이터 가져올 때
  factory UserModel.fromMap(Map<String, dynamic> map, String uid) {
    // 기존 isAdmin 필드가 있는 경우 호환성 유지
    UserRole role;
    if (map.containsKey('role')) {
      role = _roleFromString(map['role']);
    } else if (map['isAdmin'] == true) {
      role = UserRole.SUPER_ADMIN;
    } else {
      role = UserRole.USER;
    }

    return UserModel(
      uid: uid,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'],  // ✅ 추가!
      role: role,
      businessId: map['businessId'],
      createdAt: map['createdAt']?.toDate(),
      lastLoginAt: map['lastLoginAt']?.toDate(),
    );
  }

  // Firestore에 저장할 때
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'role': _roleToString(role),
      'businessId': businessId,
      'createdAt': createdAt,
      'lastLoginAt': lastLoginAt,
    };
  }

  // UserRole을 String으로 변환
  static String _roleToString(UserRole role) {
    switch (role) {
      case UserRole.SUPER_ADMIN:
        return 'SUPER_ADMIN';
      case UserRole.BUSINESS_ADMIN:
        return 'BUSINESS_ADMIN';
      case UserRole.USER:
        return 'USER';
    }
  }

  // String을 UserRole로 변환
  static UserRole _roleFromString(String roleString) {
    switch (roleString) {
      case 'SUPER_ADMIN':
        return UserRole.SUPER_ADMIN;
      case 'BUSINESS_ADMIN':
        return UserRole.BUSINESS_ADMIN;
      case 'USER':
        return UserRole.USER;
      default:
        return UserRole.USER;
    }
  }

  // copyWith 메서드 추가 (사용자 정보 업데이트 시 편리)
  UserModel copyWith({
    String? uid,
    String? name,
    String? email,
    String? phone,
    UserRole? role,
    String? businessId,
    DateTime? createdAt,
    DateTime? lastLoginAt,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      businessId: businessId ?? this.businessId,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }
}