import 'package:cloud_functions/cloud_functions.dart';

/// [impl_64 · 판정296 P2] 근로자 탈퇴 전 서버 미리보기(callableGetWithdrawBlockers) — 차단(hard)과 경고(warnings).
///
///   예전 근로자 경로(비밀번호 · 카카오 모두)는 hardBlocks 만 읽고 warnings 는 버렸다. 그래서 서명하지 않은 계약
///   (탈퇴 때 무효 처리 · 사업주 알림)과 진행 중 장기 근무(퇴사 신청 권장)를 근로자가 모른 채 탈퇴했다.
///   서버 계약은 그대로다 — 경고는 막지 않고 알리기만 한다. 차단은 서버(PreData · Final)가 다시 막는다.
class WithdrawPreview {
  const WithdrawPreview({required this.hardBlocks, required this.warnings});

  final List<Map<String, dynamic>> hardBlocks;
  final List<Map<String, dynamic>> warnings;

  static List<Map<String, dynamic>> _list(Object? v) => (v is List)
      ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)]
      : const <Map<String, dynamic>>[];

  factory WithdrawPreview.fromData(Object? data) {
    final m = data is Map ? data : const {};
    return WithdrawPreview(hardBlocks: _list(m['hardBlocks']), warnings: _list(m['warnings']));
  }

  /// 경고 줄(근로자 문구). 비어 있으면 경고 없음.
  List<String> get warningLines => [for (final w in warnings) withdrawWarningLabel(w)];
}

/// 서버 미리보기를 읽는다. 실패는 던진다(호출부가 '확인하지 못했어요' 로 멈춘다 — 미리보기 없이 진행하지 않는다).
Future<WithdrawPreview> fetchWithdrawPreview() async {
  final r = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
      .httpsCallable('callableGetWithdrawBlockers',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 25)))
      .call<Map<String, dynamic>>({});
  return WithdrawPreview.fromData(r.data);
}

int _count(Map<String, dynamic> m) => (m['count'] as num?)?.toInt() ?? 0;

/// 경고 유형 → 근로자 문구(서버 유형 이름 그대로 · 모르는 유형도 숨기지 않는다).
String withdrawWarningLabel(Map<String, dynamic> w) {
  final n = _count(w);
  return switch (w['type'] as String? ?? '') {
    'UNSIGNED_CONTRACT' => '서명하지 않은 계약서 $n건 — 탈퇴하면 무효 처리되고 사업주에게 알려요',
    'CONFIRMED_WORK' => '진행 중인 장기 근무 $n건 — 탈퇴 전에 관리자에게 퇴사 신청을 권장해요',
    'PENDING_APPLICANTS' => '대기 중 지원자 $n명 — 탈퇴 시 자동 취소',
    'ACTIVE_TOS' => '활성 공고 $n개 — 탈퇴 시 자동 마감',
    final t => '확인이 필요한 항목($t) $n건',
  };
}

/// 차단 유형 → 근로자 문구(첫 항목만 토스트로 쓴다 — 기존 화면과 같은 방식).
String withdrawHardBlockMessage(Map<String, dynamic> b) {
  final n = _count(b);
  return switch (b['type'] as String? ?? '') {
    'SUBADMIN_MEMBERSHIP' => '서브관리자로 등록된 사업장($n곳)에서 직책 해제 후 탈퇴해주세요.',
    // 구서버는 미서명 계약을 차단으로 보낸다(판정296 이전) — 그때의 안내 그대로.
    'UNSIGNED_CONTRACT' => '미서명 계약서($n건)를 먼저 서명해주세요.',
    'PENDING_WAGES' => '받지 못한 급여($n건)가 있어요. 관리자에게 이체를 요청한 뒤 탈퇴해주세요.',
    _ => '탈퇴 전 처리해야 할 항목($n건)이 있습니다. 해결 후 다시 시도해주세요.',
  };
}
