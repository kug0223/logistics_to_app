import 'package:cloud_functions/cloud_functions.dart';

/// [서버296 보안 묶음 · impl_42] 변경 요청(일정 SCR · 지급방식 PCR) 승인·거절이 **요청 정보와 지원서가 맞지 않아**
///   서버가 처리하지 않은 거절인가. 서버는 이때 요청을 PENDING 으로 남기고 details.code 를 싣는다.
///   - `SCR_RELATION_MISMATCH`(지원서 id·사업장·신청자 불일치) · `PCR_RELATION_MISMATCH`(사업장·근로자 불일치)
///   - `SCR_TYPE_INVALID`(처리할 수 없는 요청 종류)
///   일반 실패('처리에 실패했습니다')로 뭉개면 관리자가 무엇이 남았는지 모른다 — code 로만 판정한다(문구 판별 0).
const String requestRelationHeldMessage = '요청 정보가 지원서와 맞지 않아 처리하지 않았어요. 요청은 대기 상태로 남아 있어요.';
const String requestTypeInvalidMessage = '처리할 수 없는 요청 종류라 처리하지 않았어요. 요청은 대기 상태로 남아 있어요.';

String? requestHeldMessageOf(Object error) {
  if (error is! FirebaseFunctionsException) return null;
  final d = error.details;
  final code = (d is Map && d['code'] is String) ? d['code'] as String : null;
  if (code == 'SCR_RELATION_MISMATCH' || code == 'PCR_RELATION_MISMATCH') return requestRelationHeldMessage;
  if (code == 'SCR_TYPE_INVALID') return requestTypeInvalidMessage;
  return null;
}

/// 그 밖의 실패 안내 — 서버 문구가 있으면 그것, 없으면 [fallback](예외 문자열 0).
String requestFailureMessageOf(Object error, {required String fallback}) {
  if (error is FirebaseFunctionsException && (error.message?.isNotEmpty ?? false)) return error.message!;
  return fallback;
}
