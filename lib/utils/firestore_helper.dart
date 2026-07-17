import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore Timestamp → DateTime 변환.
/// Firestore 직접 조회 시 Timestamp 객체, CF 응답 시 {_seconds, _nanoseconds} Map으로 옴.
DateTime parseTimestamp(dynamic v) {
  if (v is Timestamp) return v.toDate().toLocal();
  if (v is Map) {
    final s = (v['_seconds'] as num? ?? 0).toInt();
    final ns = (v['_nanoseconds'] as num? ?? 0).toInt();
    return Timestamp(s, ns).toDate().toLocal();
  }
  throw ArgumentError('Timestamp 변환 불가: ${v.runtimeType}');
}

/// null 허용 버전
DateTime? parseTimestampNullable(dynamic v) =>
    v == null ? null : parseTimestamp(v);
