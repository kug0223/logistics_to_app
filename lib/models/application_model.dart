import 'package:cloud_firestore/cloud_firestore.dart';

/// 지원서 모델
class ApplicationModel {
  final String id; // 문서 ID
  final String toId; // 지원한 TO의 ID
  final String uid; // 지원자 UID
  final String status; // PENDING, CONFIRMED, REJECTED, CANCELED
  final DateTime appliedAt; // 지원 시각
  final DateTime? confirmedAt; // 확정 시각 (null 가능)
  final String? confirmedBy; // 확정한 사람 (SYSTEM 또는 관리자 UID)

  ApplicationModel({
    required this.id,
    required this.toId,
    required this.uid,
    required this.status,
    required this.appliedAt,
    this.confirmedAt,
    this.confirmedBy,
  });

  /// Firestore 문서를 ApplicationModel로 변환
  factory ApplicationModel.fromMap(Map<String, dynamic> data, String documentId) {
    return ApplicationModel(
      id: documentId,
      toId: data['toId'] ?? '',
      uid: data['uid'] ?? '',
      status: data['status'] ?? 'PENDING',
      appliedAt: data['appliedAt'] != null
          ? (data['appliedAt'] as Timestamp).toDate()
          : DateTime.now(),
      confirmedAt: data['confirmedAt'] != null
          ? (data['confirmedAt'] as Timestamp).toDate()
          : null,
      confirmedBy: data['confirmedBy'],
    );
  }
  
  /// Firestore DocumentSnapshot에서 변환
factory ApplicationModel.fromFirestore(DocumentSnapshot doc) {
  final data = doc.data() as Map<String, dynamic>;
  return ApplicationModel.fromMap(data, doc.id);
  }
  
  /// ApplicationModel을 Firestore 문서로 변환
  Map<String, dynamic> toMap() {
    return {
      'toId': toId,
      'uid': uid,
      'status': status,
      'appliedAt': Timestamp.fromDate(appliedAt),
      'confirmedAt': confirmedAt != null ? Timestamp.fromDate(confirmedAt!) : null,
      'confirmedBy': confirmedBy,
    };
  }

  /// 상태 한글 표시
  String get statusText {
    switch (status) {
      case 'PENDING':
        return '대기 중';
      case 'CONFIRMED':
        return '확정';
      case 'REJECTED':
        return '거절';
      case 'CANCELED':
        return '취소됨';
      default:
        return '알 수 없음';
    }
  }

  /// 상태별 색상
  int get statusColor {
    switch (status) {
      case 'PENDING':
        return 0xFFF59E0B; // 주황색
      case 'CONFIRMED':
        return 0xFF10B981; // 초록색
      case 'REJECTED':
        return 0xFFEF4444; // 빨간색
      case 'CANCELED':
        return 0xFF6B7280; // 회색
      default:
        return 0xFF9CA3AF; // 기본 회색
    }
  }

  /// 복사본 생성
  ApplicationModel copyWith({
    String? id,
    String? toId,
    String? uid,
    String? status,
    DateTime? appliedAt,
    DateTime? confirmedAt,
    String? confirmedBy,
  }) {
    return ApplicationModel(
      id: id ?? this.id,
      toId: toId ?? this.toId,
      uid: uid ?? this.uid,
      status: status ?? this.status,
      appliedAt: appliedAt ?? this.appliedAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      confirmedBy: confirmedBy ?? this.confirmedBy,
    );
  }
}