// lib/services/legal_terms_service.dart
//
// 약관 Firestore 서비스
// - app_settings/legal_terms 문서 읽기 (가입·설정·공개 페이지 공용)
// - 발행은 CF 전용 (callablePublishLegalRevision)
//
// [R7-LEGAL.1B] 쓰기가 왜 CF 로 갔는가
//
//   예전에는 이 서비스가 `app_settings/legal_terms` 를 직접 고쳤다. 그래서
//   **이미 동의를 받은 version 의 본문**을 그 자리에서 바꿀 수 있었고, 그
//   순간 과거 동의 증거가 어떤 글을 가리키는지 확정할 수 없게 됐다.
//
//   이제 발행은 `legal_revisions/{itemId}__{version}` 라는 immutable 문서를
//   만드는 일과 한 묶음이다. 그 묶음은 transaction 이어야 하고, 발행본은
//   클라이언트가 만들 수 없어야 한다(rules 전면 차단). 그래서 CF 가 유일한
//   writer 다.
//
//   본문을 바꾸려면 **새 버전**을 발행해야 한다. 같은 버전에 다른 본문을
//   발행하려 하면 서버가 `LEGAL_VERSION_REUSED` 로 거절한다.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../models/core/legal_terms_model.dart';

class LegalTermsService {
  static const _collection = 'app_settings';
  static const _docId = 'legal_terms';

  final _ref = FirebaseFirestore.instance
      .collection(_collection)
      .doc(_docId);

  /// [R7-PAYROLL-POLICY.5B] **지금 시행 중인 약관.** 동의를 받는 모든
  /// 화면이 쓰는 유일한 경로다.
  ///
  /// 어느 판이 시행 중인지는 서버가 정한다 — 발행과 시행이 분리된 뒤로는
  /// `app_settings/legal_terms` 의 base 만 읽으면 안 된다. base 는 시행
  /// 시각이 지나도 정기 정합화가 올려 주기 전까지 낡아 있을 수 있고, 비로그인
  /// 가입 화면은 서버 시각을 알 수 없어 스스로 판정할 수도 없다.
  ///
  /// **실패하면 throw 한다.** 기본값으로 대체하지 않는다 — 발행되지 않은
  /// 글을 현재 약관인 것처럼 보여 주고 동의를 받으면, 사용자가 보지 않은
  /// 글에 동의한 기록이 생긴다. 모르는 것은 모르는 것이다.
  Future<EffectiveLegalTerms> fetchEffectiveTerms() async {
    final res = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableGetEffectiveLegalTerms',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)))
        .call<Map<dynamic, dynamic>>();
    return EffectiveLegalTerms.fromServer(res.data);
  }

  /// 편집용 약관 로드 — **슈퍼관리자 발행 화면 전용.**
  ///
  /// 문서가 없으면 Dart 기본값을 **메모리로만** 돌려준다. 예전에는 여기서
  /// Firestore 에 기본값을 써 넣었는데, 그것은 발행이다 — 발행은 CF 를
  /// 거쳐야 하고 발행본을 함께 남겨야 한다. 클라이언트가 조용히 약관을
  /// 만들어 두면 그 글은 아무 발행 이력도 갖지 못한다.
  ///
  /// [R7-PAYROLL-POLICY.5B] 이 기본값 대체가 **동의 화면에 쓰이면 안 되는
  /// 이유**로 이름을 바꿨다. 가입 화면이 이 경로를 쓰고 있었고, 조회가
  /// 실패하면 발행되지 않은 코드 기본값을 현재 약관으로 보여 준 뒤 동의를
  /// 받았다. 그 동의는 사용자가 본 글을 가리키지 않는다.
  /// 동의를 받는 화면은 [fetchEffectiveTerms] 를 쓴다.
  Future<LegalTerms> getTermsForEditing() async {
    try {
      final snap = await _ref.get();
      if (!snap.exists || snap.data() == null) {
        debugPrint('⚠️ 약관 문서 없음 — 기본값(메모리)으로 표시. '
            '발행은 슈퍼관리자가 약관 관리 화면에서 수행한다.');
        return LegalTerms.defaultTerms();
      }
      return LegalTerms.fromFirestore(snap);
    } catch (e) {
      debugPrint('⚠️ 약관 로드 실패, 기본값 사용: $e');
      return LegalTerms.defaultTerms();
    }
  }

  /// [R7-PAYROLL-POLICY.5B] 이 실패가 "동의하는 사이에 약관이 바뀌었다"
  /// 인가.
  ///
  /// 판별을 한 곳에 둔다. 화면마다 문자열을 다시 비교하면 한쪽이 이것을
  /// 평범한 오류로 보고 같은 payload 로 재시도하게 된다 — 그 재시도는
  /// 영원히 실패한다. 실제로 가입 화면이 그랬다.
  static bool isTermsVersionStale(Object error) {
    if (error is! FirebaseFunctionsException) return false;
    final msg = error.message ?? '';
    return msg.contains('TERMS_VERSION_STALE');
  }

  /// 항목 발행 — 생성·수정 공용.
  ///
  /// 서버가 같은 `(id, version)` 에 다른 본문을 받으면 거절한다.
  /// 본문을 바꾸려면 버전을 올려야 한다.
  ///
  /// [R7-PAYROLL-POLICY.5A] 발행은 시행이 아니다. 새 본문을 발행할 때는
  /// 변경 방향(`changeType`)과 시행일(`effectiveAt`)을 함께 보내야 하고,
  /// 서버가 `service_terms` 제3조 ② 의 사전고지 기간을 강제한다.
  Future<void> updateItem(
    LegalTermsItem item, {
    required String updatedBy,
    required LegalChangeType changeType,
    required DateTime effectiveAt,
  }) =>
      _publish(item, changeType: changeType, effectiveAtMs:
          effectiveAt.millisecondsSinceEpoch);

  /// 노출 토글. 본문은 그대로 다시 발행한다 — 같은 본문이므로 서버는
  /// 발행본을 새로 만들지 않고 공개 목록만 바꾼다.
  ///
  /// [R7-PAYROLL-POLICY.5A] 이미 발행된 판을 **그 시행일 그대로** 다시
  /// 보내는 경우이므로 고지기간을 다시 요구하지 않는다. 시행일을 모르면
  /// 보낼 수 없다 — 모르는 날짜를 지어내면 그 값이 발행본과 어긋난다.
  Future<void> toggleActive(String itemId, bool isActive,
      {required String updatedBy}) async {
    final terms = await getTermsForEditing();
    final item = terms.items.firstWhere(
      (t) => t.id == itemId,
      orElse: () => throw StateError('약관 항목을 찾을 수 없습니다: $itemId'),
    );
    final at = item.effectiveAt;
    if (at == null) {
      throw StateError(
          '이 항목은 아직 시행일 기록이 없어 노출만 바꿀 수 없습니다: $itemId');
    }
    await _publish(item.copyWith(isActive: isActive),
        changeType: LegalChangeType.neutral,
        effectiveAtMs: at.millisecondsSinceEpoch);
  }

  Future<void> _publish(
    LegalTermsItem item, {
    required LegalChangeType changeType,
    required int effectiveAtMs,
  }) async {
    await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callablePublishLegalRevision',
            options:
                HttpsCallableOptions(timeout: const Duration(seconds: 20)))
        .call({
      'itemId': item.id,
      'version': item.version,
      'title': item.title,
      'content': item.content,
      'isRequired': item.isRequired,
      'isActive': item.isActive,
      'order': item.order,
      'changeType': changeType.wire,
      'effectiveAt': effectiveAtMs,
    });
  }
}
