part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// 사업장 및 업무 유형 관리 (Business & Work Type Management)
// ═══════════════════════════════════════════════════════════

extension BusinessFirestore on FirestoreService {
  // ═══════════════════════════════════════════════════════════
  // 사업장 관리 (Business Management)
  // ═══════════════════════════════════════════════════════════
  
  /// 사업장 ID로 조회
  Future<BusinessModel?> getBusinessById(String businessId) async {
    try {
      final doc = await _firestore.collection('businesses').doc(businessId).get(const GetOptions(source: Source.server));

      if (!doc.exists) {
        debugPrint('⚠️ 사업장을 찾을 수 없습니다: $businessId');
        return null;
      }
      
      return BusinessModel.fromFirestore(doc);
    } catch (e) {
      debugPrint('❌ 사업장 조회 실패: $e');
      return null;
    }
  }

  /// 여러 사업장의 이름을 한 번에 조회 (병렬 get — list 권한 불필요)
  Future<Map<String, String>> getBusinessNames(List<String> businessIds) async {
    if (businessIds.isEmpty) return {};
    try {
      final ids = businessIds.toSet().toList();
      final docs = await Future.wait(
        ids.map((id) => _firestore.collection('businesses').doc(id)
            .get(const GetOptions(source: Source.server))),
      );
      final Map<String, String> result = {};
      for (final doc in docs) {
        if (doc.exists) {
          result[doc.id] = (doc.data()?['name'] as String?) ?? 'Unknown';
        }
      }
      return result;
    } catch (e) {
      debugPrint('❌ 사업장명 일괄 조회 실패: $e');
      return {};
    }
  }

  /// 내 사업장 목록 조회 — CF callableGetMyBusiness (adminIds 노출 없이 서버 검증)
  Future<List<BusinessModel>> getMyBusiness(String uid) async {
    try {
      debugPrint('🔍 [FirestoreService] 내 사업장 조회 시작...');
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetMyBusiness',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));
      final response = await callable.call<Map<String, dynamic>>({});
      final list = (response.data['businesses'] as List?) ?? [];
      final businesses = list.map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        final id = map['id'] as String? ?? '';
        return BusinessModel.fromMap(map, id);
      }).toList();
      debugPrint('✅ [FirestoreService] 조회 완료: ${businesses.length}개');
      return businesses;
    } catch (e) {
      debugPrint('❌ [FirestoreService] 내 사업장 조회 실패: $e');
      return [];
    }
  }

  /// 사업장 생성 — businesses/{id}와 users/{ownerId}.managedBusinessIds를 원자적으로 처리
  Future<String?> createBusiness(BusinessModel business) async {
    NetworkChecker.instance.assertOnline('사업장 등록을 하려면 인터넷 연결이 필요합니다.');
    try {
      final batch = _firestore.batch();
      final bizRef = _firestore.collection('businesses').doc();
      batch.set(bizRef, business.toMap());
      batch.update(
        _firestore.collection('users').doc(business.ownerId),
        {'managedBusinessIds': FieldValue.arrayUnion([bizRef.id])},
      );
      await batch.commit();
      return bizRef.id;
    } catch (e) {
      debugPrint('사업장 생성 실패: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 업무 유형 관리 (Work Type Management)
  // ═══════════════════════════════════════════════════════════

  /// 모든 업무 유형 조회
  Future<List<WorkTypeModel>> getWorkTypes({bool activeOnly = false}) async {
    try {
      Query query = _firestore.collection('work_types');
      
      if (activeOnly) {
        query = query.where('isActive', isEqualTo: true);
      }
      
      query = query.orderBy('displayOrder', descending: false).limit(200);

      QuerySnapshot snapshot = await query.get();
      
      return snapshot.docs
          .map(WorkTypeModel.tryFromFirestore)
          .whereType<WorkTypeModel>()
          .toList();
    } catch (e) {
      debugPrint('❌ 업무 유형 목록 조회 실패: $e');
      return [];
    }
  }

  /// 특정 업무 유형 조회
  Future<WorkTypeModel?> getWorkType(String workTypeId) async {
    try {
      DocumentSnapshot doc = await _firestore
          .collection('work_types')
          .doc(workTypeId)
          .get();
      
      if (doc.exists) {
        return WorkTypeModel.tryFromFirestore(doc);
      }
      return null;
    } catch (e) {
      debugPrint('❌ 업무 유형 조회 실패: $e');
      return null;
    }
  }

  /// 업무 유형 생성
  Future<String?> createWorkType(WorkTypeModel workType) async {
    NetworkChecker.instance.assertOnline('업무 유형 등록을 하려면 인터넷 연결이 필요합니다.');
    try {
      final docRef = await _firestore.collection('work_types').add(workType.toMap());
      
      ToastHelper.showSuccess('업무 유형이 등록되었습니다.');
      return docRef.id;
    } catch (e) {
      debugPrint('❌ 업무 유형 생성 실패: $e');
      ToastHelper.showError('업무 등록에 실패했습니다.');
      return null;
    }
  }

  /// 업무 유형 수정
  Future<bool> updateWorkType(String workTypeId, WorkTypeModel workType) async {
    NetworkChecker.instance.assertOnline('업무 유형 수정을 하려면 인터넷 연결이 필요합니다.');
    try {
      await _firestore.collection('work_types').doc(workTypeId).update(
        workType.copyWith(updatedAt: DateTime.now()).toMap(),
      );
      
      ToastHelper.showSuccess('업무 정보가 수정되었습니다.');
      return true;
    } catch (e) {
      debugPrint('❌ 업무 유형 수정 실패: $e');
      ToastHelper.showError('업무 수정에 실패했습니다.');
      return false;
    }
  }

  /// 업무 유형 삭제 (소프트 삭제)
  Future<bool> deleteWorkType(String workTypeId) async {
    NetworkChecker.instance.assertOnline('업무 유형 삭제를 하려면 인터넷 연결이 필요합니다.');
    try {
      await _firestore.collection('work_types').doc(workTypeId).update({
        'isActive': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      ToastHelper.showSuccess('업무 유형이 비활성화되었습니다.');
      return true;
    } catch (e) {
      debugPrint('❌ 업무 유형 삭제 실패: $e');
      ToastHelper.showError('업무 삭제에 실패했습니다.');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 사업장별 업무 유형 관리 (Business Work Type Management)
  // ═══════════════════════════════════════════════════════════

  /// 특정 사업장의 업무 유형 목록 조회
  Future<List<BusinessWorkTypeModel>> getBusinessWorkTypes(String businessId) async {
    try {
      final snapshot = await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('workTypes')
          .where('isActive', isEqualTo: true)
          .orderBy('displayOrder')
          .limit(100)
          .get();

      final workTypes = snapshot.docs
          .map((doc) => BusinessWorkTypeModel.tryFromMap(doc.data(), doc.id))
          .whereType<BusinessWorkTypeModel>()
          .toList();

      debugPrint('🔍 Firestore 조회: ${workTypes.length}개');
      return workTypes;
    } catch (e) {
      debugPrint('❌ getBusinessWorkTypes 오류: $e');
      return [];
    }
  }

  /// 업무 유형 추가
  Future<String?> addBusinessWorkType({
    required String businessId,
    required String name,
    required String icon,
    String? color,
    String? backgroundColor,
    String wageType = 'hourly',
    int? displayOrder,
  }) async {
    NetworkChecker.instance.assertOnline('업무 유형 추가를 하려면 인터넷 연결이 필요합니다.');
    try {
      debugPrint('🔍 [FirestoreService] 업무 유형 추가...');

      // displayOrder 자동 설정 (기존 개수 + 1)
      final existingTypes = await getBusinessWorkTypes(businessId);
      final order = displayOrder ?? existingTypes.length;

      final workType = BusinessWorkTypeModel(
        id: '',
        businessId: businessId,
        name: name,
        icon: icon,
        color: color,
        backgroundColor: backgroundColor, 
        displayOrder: order,
        isActive: true,
        createdAt: DateTime.now(),
      );

      final docRef = await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('workTypes')
          .add(workType.toMap());

      debugPrint('✅ [FirestoreService] 업무 유형 추가 완료: ${docRef.id}');
      ToastHelper.showSuccess('업무 유형이 추가되었습니다');
      return docRef.id;
    } catch (e) {
      debugPrint('❌ [FirestoreService] 업무 유형 추가 실패: $e');
      ToastHelper.showError('업무 유형 추가에 실패했습니다');
      return null;
    }
  }

  /// 업무 유형 수정
  Future<bool> updateBusinessWorkType({
    required String businessId,
    required String workTypeId,
    String? name,
    String? icon,
    String? color,
    String? backgroundColor,
    String? wageType,
    int? displayOrder,
    bool showToast = true,
  }) async {
    NetworkChecker.instance.assertOnline('업무 유형 수정을 하려면 인터넷 연결이 필요합니다.');
    try {
      debugPrint('🔍 [FirestoreService] 업무 유형 수정...');

      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (icon != null) updates['icon'] = icon;
      if (color != null) updates['color'] = color;
      if (backgroundColor != null) updates['backgroundColor'] = backgroundColor;
      if (displayOrder != null) updates['displayOrder'] = displayOrder;
      if (wageType != null) updates['wageType'] = wageType;

      if (updates.isEmpty) {
        debugPrint('⚠️ 수정할 내용이 없습니다');
        return false;
      }

      await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('workTypes')
          .doc(workTypeId)
          .update(updates);

      debugPrint('✅ [FirestoreService] 업무 유형 수정 완료');
      
      if (showToast) {
        ToastHelper.showSuccess('업무 유형이 수정되었습니다');
      }
      
      return true;
    } catch (e) {
      debugPrint('❌ [FirestoreService] 업무 유형 수정 실패: $e');
      
      if (showToast) {
        ToastHelper.showError('업무 유형 수정에 실패했습니다');
      }
      
      return false;
    }
  }

  /// 업무 유형 삭제 (소프트 삭제 + Storage 이미지 삭제)
  Future<bool> deleteBusinessWorkType({
    required String businessId,
    required String workTypeId,
  }) async {
    NetworkChecker.instance.assertOnline('업무 유형 삭제를 하려면 인터넷 연결이 필요합니다.');
    try {
      debugPrint('🔍 [FirestoreService] 업무 유형 삭제...');

      // ✅ 1. 업무유형 문서 조회 (이미지 URL 확인)
      final doc = await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('workTypes')
          .doc(workTypeId)
          .get();
      
      if (doc.exists) {
        final data = doc.data()!;

        // ✅ 2. Firestore 소프트 삭제 먼저 (실패 시 Storage는 건드리지 않음)
        await _firestore
            .collection('businesses')
            .doc(businessId)
            .collection('workTypes')
            .doc(workTypeId)
            .update({'isActive': false});

        // ✅ 3. Firestore 성공 후 Storage 정리 (실패해도 문서는 이미 비활성화됨)
        final storage = FirebaseStorage.instance;
        if (data['thumbnailUrl'] != null) {
          try {
            await storage.refFromURL(data['thumbnailUrl']).delete();
            debugPrint('✅ 썸네일 삭제: ${data['thumbnailUrl']}');
          } catch (e) {
            debugPrint('⚠️ 썸네일 삭제 실패: $e');
          }
        }
        if (data['images'] != null) {
          for (var url in List<String>.from(data['images'])) {
            try {
              await storage.refFromURL(url).delete();
              debugPrint('✅ 이미지 삭제: $url');
            } catch (e) {
              debugPrint('⚠️ 이미지 삭제 실패: $e');
            }
          }
        }
        ToastHelper.showSuccess('업무 유형이 삭제되었습니다');
        return true;
      }

      // 문서가 없으면 이미 삭제된 것으로 간주 — 성공 처리
      debugPrint('⚠️ [deleteBusinessWorkType] 문서 없음 — 이미 삭제된 것으로 간주');
      ToastHelper.showSuccess('업무 유형이 삭제되었습니다');
      return true;
    } catch (e) {
      debugPrint('❌ [FirestoreService] 업무 유형 삭제 실패: $e');
      ToastHelper.showError('업무 유형 삭제에 실패했습니다');
      return false;
    }
  }

  /// 업무 유형 순서 변경 (여러 개 일괄 업데이트)
  Future<bool> reorderBusinessWorkTypes({
    required String businessId,
    required List<String> workTypeIds,
  }) async {
    NetworkChecker.instance.assertOnline('순서 변경을 하려면 인터넷 연결이 필요합니다.');
    try {
      debugPrint('🔍 [FirestoreService] 업무 유형 순서 변경...');

      var batch = _firestore.batch();
      int batchCount = 0;

      for (int i = 0; i < workTypeIds.length; i++) {
        final docRef = _firestore
            .collection('businesses')
            .doc(businessId)
            .collection('workTypes')
            .doc(workTypeIds[i]);

        batch.update(docRef, {'displayOrder': i});
        batchCount++;
        if (batchCount >= 499) {
          await batch.commit();
          batch = _firestore.batch();
          batchCount = 0;
        }
      }

      if (batchCount > 0) await batch.commit();

      debugPrint('✅ [FirestoreService] 순서 변경 완료');
      ToastHelper.showSuccess('순서가 변경되었습니다');
      return true;
    } catch (e) {
      debugPrint('❌ [FirestoreService] 순서 변경 실패: $e');
      ToastHelper.showError('순서 변경에 실패했습니다');
      return false;
    }
  }
  /// 활성 TO 조회 (사업장별) — [CF 이전 2026-07-13] callableGetTOsByBiz
  Future<List<TOModel>> getActiveTOsByBusinessId(String businessId) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetTOsByBiz',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final result = await callable.call<Map<String, dynamic>>({
        'businessId': businessId,
        'limit': 200,
      });
      return (result.data['tos'] as List? ?? [])
          .whereType<Map>()
          .map((m) {
            final raw = _cfHydrate(Map<String, dynamic>.from(m));
            final id = raw.remove('id') as String? ?? '';
            return TOModel.tryFromMap(raw, id);
          })
          .whereType<TOModel>()
          .where((t) => TOStatus.openStates.contains(t.status))
          .toList();
    } catch (e) {
      debugPrint('❌ 활성 TO 조회 실패: $e');
      return [];
    }
  }

  /// 마감된 TO 조회 (사업장별) — [CF 이전 2026-07-13] callableGetTOsByBiz
  Future<List<TOModel>> getClosedTOsByBusinessId(String businessId) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetTOsByBiz',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final result = await callable.call<Map<String, dynamic>>({
        'businessId': businessId,
        'limit': 200,
      });
      return (result.data['tos'] as List? ?? [])
          .whereType<Map>()
          .map((m) {
            final raw = _cfHydrate(Map<String, dynamic>.from(m));
            final id = raw.remove('id') as String? ?? '';
            return TOModel.tryFromMap(raw, id);
          })
          .whereType<TOModel>()
          .where((t) => TOStatus.closedStates.contains(t.status))
          .toList();
    } catch (e) {
      debugPrint('❌ 마감 TO 조회 실패: $e');
      return [];
    }
  }
}