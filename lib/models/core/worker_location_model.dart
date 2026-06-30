import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// 근로자 실시간 위치 모델
/// Firestore 컬렉션: worker_locations/{applicationId}
class WorkerLocationModel {
  final String applicationId;
  final String userId;
  final String businessId;

  final double lat;
  final double lng;
  final double accuracy;

  /// 사업장까지 거리 (미터) — 저장 시 클라이언트가 계산
  final double? distanceMeters;

  /// 추적 윈도우 내 위치 공유 활성 여부
  final bool isActive;

  final DateTime workDate;

  /// 예정 출근 시간 "HH:mm"
  final String scheduledStart;

  /// 위치 공유 동의 여부 (사용자가 동의 배너에서 허용한 경우 true)
  final bool consentGiven;

  final DateTime updatedAt;
  final DateTime createdAt;

  const WorkerLocationModel({
    required this.applicationId,
    required this.userId,
    required this.businessId,
    required this.lat,
    required this.lng,
    required this.accuracy,
    this.distanceMeters,
    required this.isActive,
    required this.workDate,
    required this.scheduledStart,
    required this.consentGiven,
    required this.updatedAt,
    required this.createdAt,
  });

  factory WorkerLocationModel.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data();
    if (raw == null) throw ArgumentError('WorkerLocationModel.fromFirestore: doc.data() is null (id: ${doc.id})');
    return WorkerLocationModel.fromMap(raw as Map<String, dynamic>, doc.id);
  }

  // [SCHEMA-09] 역직렬화 실패 격리 — 손상 문서 1건이 목록 전체 크래시 방지
  static WorkerLocationModel? tryFromFirestore(DocumentSnapshot doc) {
    try {
      return WorkerLocationModel.fromFirestore(doc);
    } catch (e, st) {
      debugPrint('[WorkerLocationModel] 역직렬화 실패 id=${doc.id}: $e\n$st');
      return null;
    }
  }

  factory WorkerLocationModel.fromMap(Map<String, dynamic> map, String id) {
    return WorkerLocationModel(
      applicationId: id,
      userId: map['userId'] ?? '',
      businessId: map['businessId'] ?? '',
      lat: (map['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0.0,
      accuracy: (map['accuracy'] as num?)?.toDouble() ?? 0.0,
      distanceMeters: (map['distanceMeters'] as num?)?.toDouble(),
      isActive: map['isActive'] ?? false,
      workDate: (map['workDate'] as Timestamp?)?.toDate().toLocal() ??
          (throw ArgumentError('WorkerLocationModel: workDate is required')),
      scheduledStart: map['scheduledStart'] ?? '',
      consentGiven: map['consentGiven'] ?? false,
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate().toLocal() ??
          (throw ArgumentError('WorkerLocationModel: updatedAt is required')),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate().toLocal() ??
          (throw ArgumentError('WorkerLocationModel: createdAt is required')),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'businessId': businessId,
      'lat': lat,
      'lng': lng,
      'accuracy': accuracy,
      'distanceMeters': distanceMeters,
      'isActive': isActive,
      'workDate': Timestamp.fromDate(workDate),
      'scheduledStart': scheduledStart,
      'consentGiven': consentGiven,
      'updatedAt': Timestamp.fromDate(updatedAt),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  WorkerLocationModel copyWith({
    double? lat,
    double? lng,
    double? accuracy,
    double? distanceMeters,
    bool? isActive,
    bool? consentGiven,
    DateTime? updatedAt,
  }) {
    return WorkerLocationModel(
      applicationId: applicationId,
      userId: userId,
      businessId: businessId,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      accuracy: accuracy ?? this.accuracy,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      isActive: isActive ?? this.isActive,
      workDate: workDate,
      scheduledStart: scheduledStart,
      consentGiven: consentGiven ?? this.consentGiven,
      updatedAt: updatedAt ?? this.updatedAt,
      createdAt: createdAt,
    );
  }

  /// 거리 포맷팅 (표시용)
  String get formattedDistance {
    if (distanceMeters == null) return '위치 미확인';
    if (distanceMeters! < 1000) {
      return '${distanceMeters!.toStringAsFixed(0)}m';
    }
    return '${(distanceMeters! / 1000).toStringAsFixed(1)}km';
  }

  /// 사업장 근처 여부
  /// gpsRadius와 비교가 이상적이나 위치 모델에서 접근 불가 → 200m 기준 (배지와 동일)
  bool get isNearBusiness => (distanceMeters ?? double.infinity) <= 200;
}
