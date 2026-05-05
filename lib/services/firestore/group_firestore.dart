part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// Groups 컬렉션 관리 (Group Collection Management)
// ═══════════════════════════════════════════════════════════

extension GroupFirestore on FirestoreService {
  
  // ═══════════════════════════════════════════════════════════
  // 그룹 CRUD
  // ═══════════════════════════════════════════════════════════

  /// 그룹 ID 생성
  String generateGroupId() {
    return 'group_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// 그룹 생성
  Future<String?> createGroup({
    required String groupName,
    required String businessId,
    required String businessName,
    String? businessAddress,
    String? businessCity,
    String? businessDistrict,
    required String title,
    String? description,
    required DateTime startDate,
    required DateTime endDate,
    required int totalRequired,
    int? minWage,
    int? maxWage,
    String? wageType,
    int workDetailCount = 1,
    String publishMode = 'immediate',
    DateTime? publishAt,
    bool isPublished = true,
    int? publishDaysBefore,
    String? publishTime,
    required String creatorUID,
  }) async {
    try {
      final groupId = generateGroupId();
      debugPrint('🔨 [Groups] 그룹 생성: $groupId');
      
      final groupData = {
        'groupName': groupName,
        'businessId': businessId,
        'businessName': businessName,
        'businessAddress': businessAddress,
        'businessCity': businessCity,
        'businessDistrict': businessDistrict,
        'title': title,
        'description': description,
        'startDate': Timestamp.fromDate(startDate),
        'endDate': Timestamp.fromDate(endDate),
        'status': 'ACTIVE',
        'statusUpdatedAt': FieldValue.serverTimestamp(),
        'totalRequired': totalRequired,
        'totalConfirmed': 0,
        'totalPending': 0,
        'actualDaysCount': 0,
        'minWage': minWage,
        'maxWage': maxWage,
        'wageType': wageType,
        'workDetailCount': workDetailCount,
        'publishMode': publishMode,
        'publishAt': publishAt != null ? Timestamp.fromDate(publishAt) : null,
        'isPublished': isPublished,
        'publishDaysBefore': publishDaysBefore,
        'publishTime': publishTime,
        'isManualClosed': false,
        'creatorUID': creatorUID,
        'createdAt': FieldValue.serverTimestamp(),
      };
      
      await _firestore.collection('groups').doc(groupId).set(groupData);
      
      debugPrint('✅ [Groups] 그룹 생성 완료: $groupId');
      return groupId;
    } catch (e) {
      debugPrint('❌ [Groups] 그룹 생성 실패: $e');
      return null;
    }
  }

  /// 그룹 조회 (단일)
  Future<GroupModel?> getGroup(String groupId) async {
    try {
      final doc = await _firestore.collection('groups').doc(groupId).get();
      if (!doc.exists) return null;
      return GroupModel.fromMap(doc.data()!, doc.id);
    } catch (e) {
      debugPrint('❌ [Groups] 그룹 조회 실패: $e');
      return null;
    }
  }

  /// 사업장별 활성 그룹 목록 조회
  Future<List<GroupModel>> getActiveGroups({String? businessId}) async {
    try {
      Query query = _firestore
          .collection('groups')
          .where('status', isEqualTo: 'ACTIVE');
      
      if (businessId != null) {
        query = query.where('businessId', isEqualTo: businessId);
      }
      
      final snapshot = await query
          .orderBy('startDate', descending: false)
          .get();
      
      return snapshot.docs
          .map((doc) => GroupModel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    } catch (e) {
      debugPrint('❌ [Groups] 활성 그룹 조회 실패: $e');
      return [];
    }
  }

  /// 마감된 그룹 목록 조회
  Future<List<GroupModel>> getClosedGroups({String? businessId, int limit = 10}) async {
    try {
      Query query = _firestore
          .collection('groups')
          .where('status', whereIn: ['CLOSED', 'EXPIRED', 'FULL']);
      
      if (businessId != null) {
        query = query.where('businessId', isEqualTo: businessId);
      }
      
      final snapshot = await query
          .orderBy('endDate', descending: true)
          .limit(limit)
          .get();
      
      return snapshot.docs
          .map((doc) => GroupModel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    } catch (e) {
      debugPrint('❌ [Groups] 마감 그룹 조회 실패: $e');
      return [];
    }
  }

  /// 그룹 내 TO 목록 조회
  Future<List<TOModel>> getGroupTOs(String groupId) async {
    try {
      final snapshot = await _firestore
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .orderBy('date', descending: false)
          .get();
      
      return snapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      debugPrint('❌ [Groups] 그룹 TO 조회 실패: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 그룹 통계 동기화
  // ═══════════════════════════════════════════════════════════

  /// 그룹 통계 업데이트 (TO 통계 합산)
  Future<bool> syncGroupStats(String groupId) async {
    try {
      debugPrint('📊 [Groups] 통계 동기화: $groupId');
      
      // 1. 그룹 내 모든 TO 조회
      final tos = await getGroupTOs(groupId);
      if (tos.isEmpty) {
        debugPrint('   ⚠️ 그룹에 TO가 없습니다');
        return false;
      }
      
      // 2. 통계 합산
      int totalRequired = 0;
      int totalConfirmed = 0;
      int totalPending = 0;
      int? minWage;
      int? maxWage;
      
      for (var to in tos) {
        totalRequired += to.totalRequired;
        totalConfirmed += to.totalConfirmed;
        totalPending += to.totalPending;
        
        if (to.minWage != null) {
          if (minWage == null || to.minWage! < minWage) {
            minWage = to.minWage;
          }
        }
        if (to.maxWage != null) {
          if (maxWage == null || to.maxWage! > maxWage) {
            maxWage = to.maxWage;
          }
        }
      }
      
      // 3. 그룹 문서 업데이트
      await _firestore.collection('groups').doc(groupId).update({
        'totalRequired': totalRequired,
        'totalConfirmed': totalConfirmed,
        'totalPending': totalPending,
        'actualDaysCount': tos.length,
        'minWage': minWage,
        'maxWage': maxWage,
        'statsUpdatedAt': FieldValue.serverTimestamp(),
      });
      
      debugPrint('   ✅ 통계 업데이트: $totalConfirmed/$totalRequired (+$totalPending)');
      return true;
    } catch (e) {
      debugPrint('❌ [Groups] 통계 동기화 실패: $e');
      return false;
    }
  }

  /// 그룹 상태 동기화 (하위 TO 상태 기반)
  Future<bool> syncGroupStatus(String groupId) async {
    try {
      debugPrint('📊 [Groups] 상태 동기화: $groupId');
      
      // 1. 그룹 문서 조회
      final groupDoc = await _firestore.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) return false;
      
      final groupData = groupDoc.data()!;
      
      // 수동 마감된 그룹은 상태 변경 안 함
      if (groupData['isManualClosed'] == true) {
        debugPrint('   ℹ️ 수동 마감된 그룹 - 스킵');
        return true;
      }
      
      // 2. 그룹 내 TO 상태 조회
      final tosSnapshot = await _firestore
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .get();
      
      if (tosSnapshot.docs.isEmpty) return false;
      
      // 3. 상태 판단
      bool hasActiveTO = false;
      bool allScheduled = true;
      
      for (var doc in tosSnapshot.docs) {
        final status = doc.data()['status'] ?? 'ACTIVE';
        final isPublished = doc.data()['isPublished'] ?? true;
        
        if (status == 'ACTIVE') {
          hasActiveTO = true;
        }
        if (isPublished) {
          allScheduled = false;
        }
      }
      
      // 4. 새 상태 결정
      String newStatus;
      if (hasActiveTO) {
        newStatus = 'ACTIVE';
      } else if (allScheduled) {
        newStatus = 'SCHEDULED';
      } else {
        newStatus = 'CLOSED';
      }
      
      // 5. 상태 변경 시에만 업데이트
      final currentStatus = groupData['status'];
      if (currentStatus != newStatus) {
        final updates = <String, dynamic>{
          'status': newStatus,
          'statusUpdatedAt': FieldValue.serverTimestamp(),
        };
        
        if (newStatus == 'CLOSED') {
          updates['closedAt'] = FieldValue.serverTimestamp();
          updates['closedReason'] = 'ALL_TOS_CLOSED';
        }
        
        await _firestore.collection('groups').doc(groupId).update(updates);
        debugPrint('   ✅ 상태 변경: $currentStatus → $newStatus');
      } else {
        debugPrint('   ℹ️ 상태 유지: $currentStatus');
      }
      
      return true;
    } catch (e) {
      debugPrint('❌ [Groups] 상태 동기화 실패: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 그룹 마감 관리
  // ═══════════════════════════════════════════════════════════

  /// 그룹 수동 마감
  Future<bool> closeGroup(String groupId, String adminUID) async {
    try {
      debugPrint('🔒 [Groups] 그룹 마감: $groupId');
      
      // 1. 그룹 문서 업데이트
      await _firestore.collection('groups').doc(groupId).update({
        'status': 'CLOSED',
        'isManualClosed': true,
        'closedAt': FieldValue.serverTimestamp(),
        'closedBy': adminUID,
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });
      
      // 2. 그룹 내 모든 TO도 마감
      final tosSnapshot = await _firestore
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .get();
      
      final batch = _firestore.batch();
      for (var doc in tosSnapshot.docs) {
        batch.update(doc.reference, {
          'status': 'CLOSED',
          'isManualClosed': true,
          'closedAt': FieldValue.serverTimestamp(),
          'closedBy': adminUID,
          'statusUpdatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      
      invalidateListCache();
      debugPrint('✅ [Groups] 그룹 마감 완료: ${tosSnapshot.docs.length}개 TO 포함');
      return true;
    } catch (e) {
      debugPrint('❌ [Groups] 그룹 마감 실패: $e');
      return false;
    }
  }

  /// 그룹 재오픈
  Future<bool> reopenGroup(String groupId, String adminUID) async {
    try {
      debugPrint('🔓 [Groups] 그룹 재오픈: $groupId');
      
      // 1. 그룹 문서 업데이트
      await _firestore.collection('groups').doc(groupId).update({
        'status': 'ACTIVE',
        'isManualClosed': false,
        'closedAt': FieldValue.delete(),
        'closedBy': FieldValue.delete(),
        'reopenedAt': FieldValue.serverTimestamp(),
        'reopenedBy': adminUID,
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });
      
      // 2. 그룹 내 미래 날짜 TO들 재오픈
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      final tosSnapshot = await _firestore
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .get();
      
      final batch = _firestore.batch();
      int reopenedCount = 0;
      
      for (var doc in tosSnapshot.docs) {
        final toDate = (doc.data()['date'] as Timestamp).toDate();
        final toDateOnly = DateTime(toDate.year, toDate.month, toDate.day);
        
        // 오늘 이후 날짜만 재오픈
        if (!toDateOnly.isBefore(today)) {
          batch.update(doc.reference, {
            'status': 'ACTIVE',
            'isManualClosed': false,
            'closedAt': FieldValue.delete(),
            'closedBy': FieldValue.delete(),
            'reopenedAt': FieldValue.serverTimestamp(),
            'reopenedBy': adminUID,
            'statusUpdatedAt': FieldValue.serverTimestamp(),
          });
          reopenedCount++;
        }
      }
      await batch.commit();
      
      // 3. 그룹 날짜 범위 업데이트
      await _updateGroupDateRange(groupId);
      
      invalidateListCache();
      debugPrint('✅ [Groups] 그룹 재오픈 완료: $reopenedCount개 TO 재오픈');
      return true;
    } catch (e) {
      debugPrint('❌ [Groups] 그룹 재오픈 실패: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 그룹 정보 수정
  // ═══════════════════════════════════════════════════════════

  /// 그룹명 수정
  Future<bool> updateGroupName(String groupId, String newName) async {
    try {
      await _firestore.collection('groups').doc(groupId).update({
        'groupName': newName,
      });
      
      // 하위 TO들의 groupName도 업데이트
      final tosSnapshot = await _firestore
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .get();
      
      final batch = _firestore.batch();
      for (var doc in tosSnapshot.docs) {
        batch.update(doc.reference, {'groupName': newName});
      }
      await batch.commit();
      
      debugPrint('✅ [Groups] 그룹명 수정: $newName');
      return true;
    } catch (e) {
      debugPrint('❌ [Groups] 그룹명 수정 실패: $e');
      return false;
    }
  }

  /// 그룹 날짜 범위 재계산
  Future<void> _updateGroupDateRange(String groupId) async {
    try {
      final tos = await getGroupTOs(groupId);
      if (tos.isEmpty) return;
      
      DateTime? minDate;
      DateTime? maxDate;
      
      for (var to in tos) {
        if (minDate == null || to.date.isBefore(minDate)) {
          minDate = to.date;
        }
        if (maxDate == null || to.date.isAfter(maxDate)) {
          maxDate = to.date;
        }
      }
      
      if (minDate != null && maxDate != null) {
        await _firestore.collection('groups').doc(groupId).update({
          'startDate': Timestamp.fromDate(minDate),
          'endDate': Timestamp.fromDate(maxDate),
          'actualDaysCount': tos.length,
        });
      }
    } catch (e) {
      debugPrint('⚠️ [Groups] 날짜 범위 업데이트 실패: $e');
    }
  }

  /// 그룹 삭제 (하위 TO 포함)
  Future<bool> deleteGroup(String groupId) async {
    try {
      debugPrint('🗑️ [Groups] 그룹 삭제: $groupId');
      
      // 1. 하위 TO들의 WorkDetails 삭제
      final tosSnapshot = await _firestore
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .get();
      
      for (var toDoc in tosSnapshot.docs) {
        final workDetailsSnapshot = await toDoc.reference
            .collection('workDetails')
            .get();
        
        for (var wdDoc in workDetailsSnapshot.docs) {
          await wdDoc.reference.delete();
        }
        
        await toDoc.reference.delete();
      }
      
      // 2. 그룹 문서 삭제
      await _firestore.collection('groups').doc(groupId).delete();
      
      invalidateListCache();
      debugPrint('✅ [Groups] 그룹 삭제 완료: ${tosSnapshot.docs.length}개 TO 포함');
      return true;
    } catch (e) {
      debugPrint('❌ [Groups] 그룹 삭제 실패: $e');
      return false;
    }
  }
}