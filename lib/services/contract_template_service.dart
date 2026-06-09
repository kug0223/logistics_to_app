import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/core/contract_template_model.dart';

class ContractTemplateService {
  final _db = FirebaseFirestore.instance;

  CollectionReference _col(String businessId) => _db
      .collection('businesses')
      .doc(businessId)
      .collection('contract_templates');

  Future<List<ContractTemplateModel>> getTemplates(String businessId) async {
    try {
      final snap = await _col(businessId)
          .orderBy('createdAt', descending: false)
          .get();
      return snap.docs
          .map((d) => ContractTemplateModel.fromFirestore(d))
          .toList();
    } catch (e) {
      debugPrint('템플릿 목록 조회 실패: $e');
      return [];
    }
  }

  Future<ContractTemplateModel> createTemplate({
    required String businessId,
    required String name,
    required String templateType,
    required List<ContractArticle> articles,
  }) async {
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
