import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/core/contract_template_model.dart';

class ContractTemplateService {
  final _db = FirebaseFirestore.instance;

  CollectionReference _col(String businessId) => _db
      .collection('businesses')
      .doc(businessId)
      .collection('contract_templates');

  Future<List<ContractTemplateModel>> getTemplates(String businessId,
      {int limit = 100}) async {
    try {
      debugPrint('🔍 [getTemplates] businessId=$businessId');
      // [UX-P2-02] 최신순 — 방금 만든 템플릿이 목록 최상단에 오도록 한다.
      //   계약 발송 도중 템플릿을 새로 만들고 Selector로 돌아왔을 때
      //   스크롤 없이 바로 찾을 수 있어야 한다. (자동 선택은 하지 않음)
      final snap = await _col(businessId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      debugPrint('✅ [getTemplates] ${snap.docs.length}개 조회됨');
      return snap.docs
          .map(ContractTemplateModel.tryFromFirestore)
          .whereType<ContractTemplateModel>()
          .toList();
    } catch (e) {
      debugPrint('❌ [getTemplates] businessId=$businessId 조회 실패: $e');
      rethrow;
    }
  }

  Future<ContractTemplateModel> createTemplate({
    required String businessId,
    required String name,
    required String templateType,
    required List<ContractArticle> articles,
  }) async {
    debugPrint('💾 [createTemplate] businessId=$businessId name=$name');
    final ref = _col(businessId).doc();
    final template = ContractTemplateModel(
      id: ref.id,
      businessId: businessId,
      name: name,
      templateType: templateType,
      articles: articles,
      createdAt: DateTime.now(),
    );
    await ref.set(template.toMap()..['createdAt'] = FieldValue.serverTimestamp());
    return template;
  }

  Future<void> updateTemplate(ContractTemplateModel template) async {
    await _col(template.businessId).doc(template.id).update({
      'name': template.name,
      'templateType': template.templateType,
      'articles': template.articles.map((a) => a.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<ContractTemplateModel> duplicateTemplate(
      ContractTemplateModel source) async {
    final ref = _col(source.businessId).doc();
    final copy = ContractTemplateModel(
      id: ref.id,
      businessId: source.businessId,
      name: '${source.name} (복사)',
      templateType: source.templateType,
      articles: source.articles
          .map((a) => ContractArticle(title: a.title, content: a.content))
          .toList(),
      createdAt: DateTime.now(),
    );
    await ref.set(copy.toMap()..['createdAt'] = FieldValue.serverTimestamp());
    return copy;
  }

  Future<void> deleteTemplate({
    required String businessId,
    required String templateId,
  }) async {
    await _col(businessId).doc(templateId).delete();
  }

  /// 다른 사업장 템플릿 → [targetBusinessId] 사업장으로 독립 복사
  ///
  /// Firestore rule: create 시 request.resource.data.businessId == URL businessId 강제.
  /// targetBusinessId 를 문서 businessId 에 그대로 넣으므로 규칙 통과.
  Future<ContractTemplateModel> duplicateTemplateTo(
    ContractTemplateModel source,
    String targetBusinessId,
  ) async {
    debugPrint(
        '📋 [duplicateTemplateTo] from=${source.businessId} to=$targetBusinessId');
    final ref = _col(targetBusinessId).doc();
    final copy = ContractTemplateModel(
      id: ref.id,
      businessId: targetBusinessId,
      name: '${source.name} (복사)',
      templateType: source.templateType,
      articles: source.articles
          .map((a) => ContractArticle(title: a.title, content: a.content))
          .toList(),
      createdAt: DateTime.now(),
      // updatedAt: 복사 금지 (source 날짜 미전달)
    );
    await ref.set(copy.toMap()..['createdAt'] = FieldValue.serverTimestamp());
    return copy;
  }
}
