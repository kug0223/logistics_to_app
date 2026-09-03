import 'package:cloud_firestore/cloud_firestore.dart';



/// Firestore Timestamp → 기기 로컬 DateTime 변환.
/// ⚠️ 반환값은 기기 타임존 기준 DateTime이다 (KST 고정 아님).
/// 화면 표시 시에는 FormatHelper.formatDate* 또는 FormatHelper._toKst()를 통해 KST로 변환할 것.
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
