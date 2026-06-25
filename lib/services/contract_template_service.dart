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
      final snap = await _col(businessId)
          .orderBy('createdAt', descending: false)
          .limit(limit)
          .get();
      debugPrint('✅ [getTemplates] ${snap.docs.length}개 조회됨');
      return snap.docs
          .map((d) => ContractTemplateModel.fromFirestore(d))
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
    final now = DateTime.now();
    final template = ContractTemplateModel(
      id: ref.id,
      businessId: businessId,
      name: name,
      templateType: templateType,
      articles: articles,
      createdAt: now,
    );
    await ref.set(template.toMap());
    return template;
  }

  Future<void> updateTemplate(ContractTemplateModel template) async {
    await _col(template.businessId).doc(template.id).update({
      'name': template.name,
      'templateType': template.templateType,
      'articles': template.articles.map((a) => a.toMap()).toList(),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<ContractTemplateModel> duplicateTemplate(
      ContractTemplateModel source) async {
    final ref = _col(source.businessId).doc();
    final now = DateTime.now();
    final copy = ContractTemplateModel(
      id: ref.id,
      businessId: source.businessId,
      name: '${source.name} (복사)',
      templateType: source.templateType,
      articles: source.articles
          .map((a) => ContractArticle(title: a.title, content: a.content))
          .toList(),
      createdAt: now,
    );
    await ref.set(copy.toMap());
    return copy;
  }

  Future<void> deleteTemplate({
    required String businessId,
    required String templateId,
  }) async {
    await _col(businessId).doc(templateId).delete();
  }
}
