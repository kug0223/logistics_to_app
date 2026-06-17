// lib/services/legal_terms_service.dart
//
// 약관 Firestore 서비스
// - app_settings/legal_terms 문서 읽기/쓰기
// - 슈퍼관리자 약관 수정, 회원가입 시 로드

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/core/legal_terms_model.dart';

class LegalTermsService {
  static const _collection = 'app_settings';
  static const _docId = 'legal_terms';

  final _ref = FirebaseFirestore.instance
      .collection(_collection)
      .doc(_docId);

  /// 약관 로드 (없으면 기본값 반환 + Firestore에 자동 초기화)
  Future<LegalTerms> getTerms() async {
    try {
      final snap = await _ref.get();
      if (!snap.exists || snap.data() == null) {
        // 최초 실행: 기본값을 Firestore에 저장
        final defaults = LegalTerms.defaultTerms();
        await _initializeDefaults(defaults);
        return defaults;
      }
      return LegalTerms.fromFirestore(snap);
    } catch (e) {
      debugPrint('⚠️ 약관 로드 실패, 기본값 사용: $e');
      return LegalTerms.defaultTerms();
    }
  }

  /// 약관 전체 저장 (슈퍼관리자)
  Future<void> saveTerms(LegalTerms terms, {required String updatedBy}) async {
    await _ref.set({
      'items': terms.items.map((t) => t.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
    });
  }

  /// 단일 항목 수정
  Future<void> updateItem(LegalTermsItem item, {required String updatedBy}) async {
    // snap을 한 번만 읽어 재사용 (이중 읽기 방지)
    final snap = await _ref.get();
    if (!snap.exists || snap.data() == null) {
      final defaults = LegalTerms.defaultTerms();
      await _initializeDefaults(defaults);
      return;
    }

    final current = LegalTerms.fromFirestore(snap);
    final updated = current.items.map((t) => t.id == item.id ? item : t).toList();
    await _ref.update({
      'items': updated.map((t) => t.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
    });
  }

  /// 항목 활성/비활성 토글
  ///
  /// getTerms() + update() 분리 시 동시 호출에서 덮어쓰기가 발생할 수 있으므로
  /// runTransaction으로 read → write를 원자화한다.
  Future<void> toggleActive(String itemId, bool isActive, {required String updatedBy}) async {
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(_ref);
      if (!snap.exists || snap.data() == null) return;
      final current = LegalTerms.fromFirestore(snap);
      final updated = current.items.map((t) =>
          t.id == itemId ? t.copyWith(isActive: isActive) : t).toList();
      tx.update(_ref, {
        'items': updated.map((t) => t.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': updatedBy,
      });
    });
  }

  /// Firestore 초기화 (최초 1회)
  Future<void> _initializeDefaults(LegalTerms defaults) async {
    try {
      await _ref.set({
        'items': defaults.items.map((t) => t.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': 'system_init',
      });
      debugPrint('✅ 기본 약관 초기화 완료');
    } catch (e) {
      debugPrint('⚠️ 약관 초기화 실패: $e');
    }
  }
}
