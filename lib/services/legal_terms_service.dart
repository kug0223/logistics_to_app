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

  /// 약관 로드.
  ///
  /// 문서가 없으면 Dart 기본값을 **메모리로만** 돌려준다. 예전에는 여기서
  /// Firestore 에 기본값을 써 넣었는데, 그것은 발행이다 — 발행은 CF 를
  /// 거쳐야 하고 발행본을 함께 남겨야 한다. 클라이언트가 조용히 약관을
  /// 만들어 두면 그 글은 아무 발행 이력도 갖지 못한다.
  Future<LegalTerms> getTerms() async {
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

  /// 항목 발행 — 생성·수정 공용.
  ///
  /// 서버가 같은 `(id, version)` 에 다른 본문을 받으면 거절한다.
  /// 본문을 바꾸려면 버전을 올려야 한다.
  Future<void> updateItem(LegalTermsItem item, {required String updatedBy}) =>
      _publish(item);

  /// 노출 토글. 본문은 그대로 다시 발행한다 — 같은 본문이므로 서버는
  /// 발행본을 새로 만들지 않고 공개 목록만 바꾼다.
  Future<void> toggleActive(String itemId, bool isActive,
      {required String updatedBy}) async {
    final terms = await getTerms();
    final item = terms.items.firstWhere(
      (t) => t.id == itemId,
      orElse: () => throw StateError('약관 항목을 찾을 수 없습니다: $itemId'),
    );
    await _publish(item.copyWith(isActive: isActive));
  }

  Future<void> _publish(LegalTermsItem item) async {
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
    });
  }
}
