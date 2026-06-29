import 'package:cloud_firestore/cloud_firestore.dart';

/// 하위 관리자 권한 항목
class MemberPermissions {
  final bool canManageTo;       // 공고 등록/수정/삭제
  final bool canManageWorkers;  // 근무자 승인/출퇴근/확정 관리
  final bool canManageWage;     // 급여 확인/정산
  final bool canManageContract; // 계약서 작성/템플릿 관리

  const MemberPermissions({
    this.canManageTo = false,
    this.canManageWorkers = false,
    this.canManageWage = false,
    this.canManageContract = false,
  });

  factory MemberPermissions.none() => const MemberPermissions();

  factory MemberPermissions.all() => const MemberPermissions(
        canManageTo: true,
        canManageWorkers: true,
        canManageWage: true,
        canManageContract: true,
      );

  factory MemberPermissions.fromMap(Map<String, dynamic> m) => MemberPermissions(
        canManageTo: m['canManageTo'] ?? false,
        canManageWorkers: m['canManageWorkers'] ?? false,
        canManageWage: m['canManageWage'] ?? false,
        canManageContract: m['canManageContract'] ?? false,
      );

  Map<String, dynamic> toMap() => {
        'canManageTo': canManageTo,
        'canManageWorkers': canManageWorkers,
        'canManageWage': canManageWage,
        'canManageContract': canManageContract,
      };

  MemberPermissions copyWith({
    bool? canManageTo,
    bool? canManageWorkers,
    bool? canManageWage,
    bool? canManageContract,
  }) =>
      MemberPermissions(
        canManageTo: canManageTo ?? this.canManageTo,
        canManageWorkers: canManageWorkers ?? this.canManageWorkers,
        canManageWage: canManageWage ?? this.canManageWage,
        canManageContract: canManageContract ?? this.canManageContract,
      );

  bool get hasAnyPermission =>
      canManageTo || canManageWorkers || canManageWage || canManageContract;

  String get summaryText {
    final parts = <String>[];
    if (canManageTo) parts.add('공고');
    if (canManageWorkers) parts.add('근무자');
    if (canManageWage) parts.add('급여');
    if (canManageContract) parts.add('계약서');
    if (parts.isEmpty) return '권한 없음';
    return parts.join(' · ');
  }
}

/// businesses/{businessId}/members/{uid}
class BusinessMemberModel {
  final String uid;
  final String name;
  final String? phone;
  final MemberPermissions permissions;
  final DateTime addedAt;
  final String addedBy;
  // 초대 수락 시 검증용 — Firestore 규칙에서 pending 초대 존재 여부 확인에 사용
  // null: 관리자가 직접 추가한 경우 (isAdminOf 경로로 생성)
  final String? invitationId;

  const BusinessMemberModel({
    required this.uid,
    required this.name,
    this.phone,
    required this.permissions,
    required this.addedAt,
    required this.addedBy,
    this.invitationId,
  });

  factory BusinessMemberModel.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data();
    if (raw == null) {
      throw ArgumentError('BusinessMemberModel.fromFirestore: 문서 데이터 없음 (id: ${doc.id})');
    }
    final d = raw as Map<String, dynamic>;
    return BusinessMemberModel(
      uid: doc.id,
      name: d['name'] ?? '',
      phone: d['phone'],
      permissions: MemberPermissions.fromMap(
          (d['permissions'] as Map<String, dynamic>?) ?? {}),
      addedAt: d['addedAt'] != null
          ? (d['addedAt'] as Timestamp).toDate().toLocal()
          : (throw ArgumentError('BusinessMemberModel: addedAt 필드 누락 (id: ${doc.id})')),
      addedBy: d['addedBy'] ?? '',
      invitationId: d['invitationId'],
    );
  }

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'name': name,
      'phone': phone,
      'permissions': permissions.toMap(),
      'addedAt': Timestamp.fromDate(addedAt),
      'addedBy': addedBy,
    };
    if (invitationId != null) m['invitationId'] = invitationId;
    return m;
  }

  BusinessMemberModel copyWith({
    String? name,
    String? phone,
    MemberPermissions? permissions,
    DateTime? addedAt,
    String? addedBy,
    String? invitationId,
  }) =>
      BusinessMemberModel(
        uid: uid,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        permissions: permissions ?? this.permissions,
        addedAt: addedAt ?? this.addedAt,
        addedBy: addedBy ?? this.addedBy,
        invitationId: invitationId ?? this.invitationId,
      );
}
