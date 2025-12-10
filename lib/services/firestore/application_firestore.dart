part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// 지원서 관리 (Application Management)
// ═══════════════════════════════════════════════════════════

extension ApplicationFirestore on FirestoreService {

  // ═══════════════════════════════════════════════════════════
  // 지원서 조회
  // ═══════════════════════════════════════════════════════════

  /// TO별 지원자 목록 조회
  Future<List<ApplicationModel>> getApplicationsByTOId(String toId) async {
    try {
      // 1. TO 정보 조회
      final toDoc = await db.collection('tos').doc(toId).get();
      if (!toDoc.exists) {
        print('❌ TO를 찾을 수 없습니다: $toId');
        return [];
      }

      final toData = toDoc.data()!;
      final businessId = toData['businessId'];
      final toTitle = toData['title'];
      final workDate = toData['date'] as Timestamp;

      // 2. businessId, toTitle, workDate로 지원서 조회
      final snapshot = await db
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('toTitle', isEqualTo: toTitle)
          .where('workDate', isEqualTo: workDate)
          .get();

      return snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ 지원자 목록 조회 실패: $e');
      return [];
    }
  }

  /// 여러 TO의 지원자를 한 번에 조회 (병렬 최적화!)
  Future<Map<String, List<ApplicationModel>>> getApplicationsByTOIds(List<String> toIds) async {
    try {
      if (toIds.isEmpty) return {};
      
      print('🔍 배치 지원자 조회 시작: ${toIds.length}개 TO (병렬 처리)');
      
      // ✅ 병렬로 각 TO의 지원서 조회
      final futures = toIds.map((toId) async {
        // TO 정보 조회
        final toDoc = await db.collection('tos').doc(toId).get();
        if (!toDoc.exists) {
          return MapEntry(toId, <ApplicationModel>[]);
        }

        final toData = toDoc.data()!;
        final businessId = toData['businessId'];
        final toTitle = toData['title'];
        final workDate = toData['date'] as Timestamp;

        // 지원서 조회
        final snapshot = await db
            .collection('applications')
            .where('businessId', isEqualTo: businessId)
            .where('toTitle', isEqualTo: toTitle)
            .where('workDate', isEqualTo: workDate)
            .get();

        final applications = snapshot.docs
            .map((doc) => ApplicationModel.fromFirestore(doc))
            .toList();

        return MapEntry(toId, applications);
      }).toList();

      final results = await Future.wait(futures);
      
      print('✅ 배치 지원자 조회 완료');
      return Map.fromEntries(results);
    } catch (e) {
      print('❌ 배치 지원자 조회 실패: $e');
      return {};
    }
  }

  /// 특정 TO에 대한 사용자의 지원 목록 조회
  Future<List<ApplicationModel>> getApplicationsForTO({
    required String toId,
    required String uid,
  }) async {
    try {
      // TO 정보 먼저 조회
      final toDoc = await db.collection('tos').doc(toId).get();
      if (!toDoc.exists) return [];

      final toData = toDoc.data()!;
      final businessId = toData['businessId'];
      final toTitle = toData['title'];
      final workDate = toData['date'] as Timestamp;

      // 지원서 조회
      final snapshot = await db
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('businessId', isEqualTo: businessId)
          .where('toTitle', isEqualTo: toTitle)
          .where('workDate', isEqualTo: workDate)
          .get();

      return snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ TO 지원 목록 조회 실패: $e');
      return [];
    }
  }
  /// 내 지원 내역 조회
  Future<List<ApplicationModel>> getMyApplications(String uid) async {
    try {
      final snapshot = await db
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .orderBy('appliedAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('내 지원 내역 조회 실패: $e');
      return [];
    }
  }

  /// 사업장별 지원자 목록 조회
  Future<List<ApplicationModel>> getApplicationsByBusinessId(String businessId) async {
    try {
      print('📋 사업장별 지원서 조회 시작: $businessId');
      
      final snapshot = await db
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .get();

      final applications = snapshot.docs
          .map((doc) => ApplicationModel.fromMap(doc.data(), doc.id))
          .toList();

      print('✅ 사업장별 지원서 조회 완료: ${applications.length}개');
      return applications;
    } catch (e) {
      print('❌ 사업장별 지원서 조회 실패: $e');
      return [];
    }
  }

  /// 여러 TO의 지원자를 한 번에 조회 (TO 정보 전달 - 중복 조회 제거)
  Future<Map<String, List<ApplicationModel>>> getApplicationsByTOs(List<TOModel> tos) async {
    try {
      if (tos.isEmpty) return {};
      
      print('🔍 배치 지원자 조회 시작: ${tos.length}개 TO (TO 정보 재사용)');
      
      final futures = tos.map((to) async {
        // ✅ TO 정보는 이미 있음 - 재조회 안 함!
        final snapshot = await db
            .collection('applications')
            .where('businessId', isEqualTo: to.businessId)
            .where('toTitle', isEqualTo: to.title)
            .where('workDate', isEqualTo: Timestamp.fromDate(to.date))
            .get();

        final apps = snapshot.docs
            .map((doc) => ApplicationModel.fromFirestore(doc))
            .toList();
        
        return MapEntry(to.id, apps);
      }).toList();
      
      final results = await Future.wait(futures);
      final result = Map.fromEntries(results);
      
      print('✅ 배치 지원자 조회 완료: ${tos.length}개 TO, ${result.values.fold(0, (sum, list) => sum + list.length)}명');
      return result;
    } catch (e) {
      print('❌ 배치 지원자 조회 실패: $e');
      return {};
    }
  }

  /// 특정 TO의 특정 업무 유형에 대한 지원서 조회
  Future<List<ApplicationModel>> getApplicationsByWorkDetail(
    String toId,
    String workType,
  ) async {
    try {
      // ✅ TO 정보 먼저 조회
      final toDoc = await db.collection('tos').doc(toId).get();
      if (!toDoc.exists) {
        print('❌ TO를 찾을 수 없습니다: $toId');
        return [];
      }

      final toData = toDoc.data()!;
      final businessId = toData['businessId'];
      final toTitle = toData['title'];
      final workDate = toData['date'] as Timestamp;

      // ✅ businessId, toTitle, workDate, workType으로 조회
      final snapshot = await db
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('toTitle', isEqualTo: toTitle)
          .where('workDate', isEqualTo: workDate)
          .where('selectedWorkType', isEqualTo: workType)
          .get();

      return snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ 업무별 지원서 조회 실패: $e');
      return [];
    }
  }

  /// TO별 지원자 목록 + 사용자 정보 조회 (관리자용)
  Future<List<Map<String, dynamic>>> getApplicantsWithUserInfo(String toId) async {
    try {
      // ✅ TO 정보 먼저 조회
      final toDoc = await db.collection('tos').doc(toId).get();
      if (!toDoc.exists) {
        print('❌ TO를 찾을 수 없습니다: $toId');
        return [];
      }

      final toData = toDoc.data()!;
      final businessId = toData['businessId'];
      final toTitle = toData['title'];
      final workDate = toData['date'] as Timestamp;

      print('🔍 지원자 조회: businessId=$businessId, toTitle=$toTitle');

      // ✅ businessId, toTitle, workDate로 조회
      QuerySnapshot appSnapshot = await db
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('toTitle', isEqualTo: toTitle)
          .where('workDate', isEqualTo: workDate)
          .get();

      print('✅ 조회된 지원서: ${appSnapshot.docs.length}개');

      // 메모리에서 정렬
      final sortedDocs = appSnapshot.docs.toList()
        ..sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTime = aData['appliedAt'] as Timestamp?;
          final bTime = bData['appliedAt'] as Timestamp?;
          
          if (aTime == null || bTime == null) return 0;
          return aTime.compareTo(bTime);
        });

      List<Map<String, dynamic>> result = [];

      for (var appDoc in sortedDocs) {
        final appData = appDoc.data() as Map<String, dynamic>;
        final uid = appData['uid'];

        final userDoc = await db.collection('users').doc(uid).get();
        
        if (userDoc.exists) {
          final userData = userDoc.data() as Map<String, dynamic>;
          
          result.add({
            'applicationId': appDoc.id,
            'application': ApplicationModel.fromMap(appData, appDoc.id),
            'userName': userData['name'] ?? '(알 수 없음)',
            'userEmail': userData['email'] ?? '',
            'userPhone': userData['phone'] ?? '',
            'userGender': userData['gender'] ?? '',
            'userBirthDate': userData['birthDate'],
          });
        }
      }

      return result;
    } catch (e) {
      print('❌ 지원자 + 사용자 정보 조회 실패: $e');
      return [];
    }
  }
  // ═══════════════════════════════════════════════════════════
  // 지원 생성
  // ═══════════════════════════════════════════════════════════

  /// TO에 지원하기 (간편 버전)
  Future<bool> applyForTO({
    required String toId,
    required String workDetailId,
    required String workType,
    required String uid,
    DateTime? desiredStartDate,
  }) async {
    try {
      // 1. TO 정보 조회
      final toDoc = await db.collection('tos').doc(toId).get();
      if (!toDoc.exists) {
        ToastHelper.showError('TO를 찾을 수 없습니다');
        return false;
      }

      final toData = toDoc.data()!;
      final to = TOModel.fromMap(toData, toId);

      // 2. WorkDetail 정보 조회
      final workDetailDoc = await db
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .doc(workDetailId)
          .get();

      if (!workDetailDoc.exists) {
        ToastHelper.showError('업무 정보를 찾을 수 없습니다');
        return false;
      }

      final workDetail = WorkDetailModel.fromMap(workDetailDoc.data()!, workDetailId);

      // 3. 기존 applyToTOWithWorkType 호출
      return await applyToTOWithWorkType(
        uid: uid,
        businessId: to.businessId,
        businessName: to.businessName,
        toTitle: to.title,
        workDate: to.date,
        selectedWorkType: workType,
        workDetailId: workDetailId,
        wage: workDetail.wage,
        startTime: workDetail.startTime,
        endTime: workDetail.endTime,
        workEndDate: to.endDate,
        workDays: to.workDays,
        type: to.isLongTerm ? 'long_term' : 'short',
        desiredStartDate: desiredStartDate,
      );
    } catch (e) {
      print('❌ TO 지원 실패: $e');
      ToastHelper.showError('지원에 실패했습니다');
      return false;
    }
  }

  /// 업무유형 선택 지원 (상세 버전)
  Future<bool> applyToTOWithWorkType({
    required String uid,
    required String businessId,
    required String businessName,
    required String toTitle,
    required DateTime workDate,
    required String selectedWorkType,
    required String workDetailId,
    required int wage,
    required String startTime,
    required String endTime,
    DateTime? workEndDate,
    List<String>? workDays,
    String type = 'short',
    DateTime? desiredStartDate,
  }) async {
    try {
      // 1. TO 문서 찾기
      final toSnapshot = await db
          .collection('tos')
          .where('businessId', isEqualTo: businessId)
          .where('title', isEqualTo: toTitle)
          .where('date', isEqualTo: Timestamp.fromDate(workDate))
          .limit(1)
          .get();

      if (toSnapshot.docs.isEmpty) {
        ToastHelper.showError('TO를 찾을 수 없습니다.');
        return false;
      }

      final toId = toSnapshot.docs.first.id;

      // 2. 중복 지원 체크
      final existingSnapshot = await db
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('businessId', isEqualTo: businessId)
          .where('toTitle', isEqualTo: toTitle)
          .where('workDate', isEqualTo: Timestamp.fromDate(workDate))
          .where('selectedWorkType', isEqualTo: selectedWorkType)
          .limit(1)
          .get();

      if (existingSnapshot.docs.isNotEmpty) {
        final existingDoc = existingSnapshot.docs.first;
        final existingData = existingDoc.data();
        final existingStatus = existingData['status'];
        
        if (existingStatus == 'PENDING' || existingStatus == 'CONFIRMED') {
          ToastHelper.showError('이미 지원한 업무입니다.');
          return false;
        }
        
        // 취소/거절 상태면 재지원
        print('✅ 기존 지원서 재활성화: ${existingDoc.id}');
        
        final batch = db.batch();
        
        batch.update(existingDoc.reference, {
          'status': 'PENDING',
          'appliedAt': FieldValue.serverTimestamp(),
          'canceledAt': null,
          'cancelReason': null,
          if (desiredStartDate != null) 
            'desiredStartDate': Timestamp.fromDate(desiredStartDate),
        });
        
        batch.update(db.collection('tos').doc(toId), {
          'totalPending': FieldValue.increment(1),
        });
        
        batch.update(
          db
              .collection('tos')
              .doc(toId)
              .collection('workDetails')
              .doc(workDetailId),
          {
            'pendingCount': FieldValue.increment(1),
          },
        );
        
        await batch.commit();
        clearCache(toId: toId);
        
        print('✅ 재지원 완료 (기존 문서 업데이트)');
        return true;
      }

      // 3. 확정된 근무와 충돌 체크
      final confirmedSchedules = await getConfirmedSchedules(
        uid: uid,
        workDate: workDate,
      );
      
      for (var schedule in confirmedSchedules) {
        if (_hasTimeOverlap(
          startTime,
          endTime,
          schedule.startTime,
          schedule.endTime,
        )) {
          ToastHelper.showError(
            '이미 ${schedule.startTime}~${schedule.endTime}에\n'
            '${schedule.businessName}에서 확정된 근무가 있습니다.\n\n'
            '해당 시간대에는 추가 지원이 불가능합니다.'
          );
          return false;
        }
      }

      // 4. Batch로 한번에 처리
      final batch = db.batch();

      // 4-1. 지원서 생성
      final appRef = db.collection('applications').doc();
      batch.set(appRef, {
        'uid': uid,
        'businessId': businessId,
        'businessName': businessName,
        'toTitle': toTitle,
        'selectedWorkType': selectedWorkType,
        'workDetailId': workDetailId,
        'wage': wage,
        'workDate': Timestamp.fromDate(workDate),
        'startTime': startTime,
        'endTime': endTime,
        'status': 'PENDING',
        'appliedAt': FieldValue.serverTimestamp(),
        'type': type,
        'workEndDate': workEndDate != null 
            ? Timestamp.fromDate(workEndDate) 
            : null,
        'workDays': workDays,
        'desiredStartDate': desiredStartDate != null 
            ? Timestamp.fromDate(desiredStartDate) 
            : null,
      });

      // 4-2. TO 통계 업데이트
      batch.update(db.collection('tos').doc(toId), {
        'totalApplications': FieldValue.increment(1),
        'totalPending': FieldValue.increment(1),
      });

      // 4-3. WorkDetail pendingCount 증가
      batch.update(
        db
            .collection('tos')
            .doc(toId)
            .collection('workDetails')
            .doc(workDetailId),
        {
          'pendingCount': FieldValue.increment(1),
        },
      );

      // 4-4. 그룹 마스터 통계 Increment
      final toDoc = await db.collection('tos').doc(toId).get();
      final groupId = toDoc.data()?['groupId'] as String?;
      
      if (groupId != null) {
        final masterSnapshot = await db
            .collection('tos')
            .where('groupId', isEqualTo: groupId)
            .where('isGroupMaster', isEqualTo: true)
            .limit(1)
            .get();
        
        if (masterSnapshot.docs.isNotEmpty) {
          batch.update(masterSnapshot.docs.first.reference, {
            'groupTotalPending': FieldValue.increment(1),
          });
        }
      }

      await batch.commit();
      print('✅ Batch commit 완료 (Increment 방식)');
      
      clearCache(toId: toId);

      print('✅ 지원 완료: businessId=$businessId, toTitle=$toTitle, WorkType=$selectedWorkType');
      return true;
    } catch (e) {
      print('❌ 지원 실패: $e');
      ToastHelper.showError('지원 중 오류가 발생했습니다.');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 지원 취소
  // ═══════════════════════════════════════════════════════════

  /// 지원 취소 (사용자용)
  Future<bool> cancelApplication(String applicationId, String uid) async {
    try {
      DocumentSnapshot appDoc = await db
          .collection('applications')
          .doc(applicationId)
          .get();

      if (!appDoc.exists) {
        ToastHelper.showError('지원서를 찾을 수 없습니다.');
        return false;
      }

      final appData = appDoc.data() as Map<String, dynamic>;

      if (appData['uid'] != uid) {
        ToastHelper.showError('본인의 지원서만 취소할 수 있습니다.');
        return false;
      }

      if (appData['status'] == 'CONFIRMED') {
        ToastHelper.showError('확정된 TO는 취소할 수 없습니다.\n관리자에게 문의해주세요.');
        return false;
      }

      final businessId = appData['businessId'];
      final toTitle = appData['toTitle'];
      final workDate = appData['workDate'] as Timestamp;

      final toSnapshot = await db
          .collection('tos')
          .where('businessId', isEqualTo: businessId)
          .where('title', isEqualTo: toTitle)
          .where('date', isEqualTo: workDate)
          .limit(1)
          .get();

      if (toSnapshot.docs.isEmpty) {
        await db.collection('applications').doc(applicationId).update({
          'status': 'CANCELED',
        });
        ToastHelper.showSuccess('지원이 취소되었습니다.');
        return true;
      }

      final toDoc = toSnapshot.docs.first;
      final toId = toDoc.id;
      final toData = toDoc.data();
      final groupId = toData['groupId'] as String?;
      final workDetailId = appData['workDetailId'] as String?;

      final batch = db.batch();

      // 1. 지원서 취소
      batch.update(db.collection('applications').doc(applicationId), {
        'status': 'CANCELED',
        'canceledAt': FieldValue.serverTimestamp(),
      });

      // 2. TO 통계 Increment
      batch.update(toDoc.reference, {
        'totalPending': FieldValue.increment(-1),
      });

      // 3. WorkDetail 통계 Increment
      if (workDetailId != null && workDetailId.isNotEmpty) {
        batch.update(
          db
              .collection('tos')
              .doc(toId)
              .collection('workDetails')
              .doc(workDetailId),
          {
            'pendingCount': FieldValue.increment(-1),
          },
        );
      }

      // 4. 그룹 마스터 통계 Increment
      if (groupId != null) {
        final masterSnapshot = await db
            .collection('tos')
            .where('groupId', isEqualTo: groupId)
            .where('isGroupMaster', isEqualTo: true)
            .limit(1)
            .get();

        if (masterSnapshot.docs.isNotEmpty) {
          batch.update(masterSnapshot.docs.first.reference, {
            'groupTotalPending': FieldValue.increment(-1),
          });
        }
      }

      await batch.commit();
      clearCache(toId: toId);
      
      // 연관 데이터 정리
      await _cleanupApplicationRelatedData(
        applicationId: applicationId,
        uid: uid,
      );

      ToastHelper.showSuccess('지원이 취소되었습니다.');
      return true;
    } catch (e) {
      print('❌ 지원 취소 실패: $e');
      ToastHelper.showError('지원 취소에 실패했습니다.');
      return false;
    }
  }

  /// 확정된 지원 취소 (노쇼 패널티 포함)
  Future<bool> cancelConfirmedApplication(
    String applicationId, {
    bool applyNoShowPenalty = false,
  }) async {
    try {
      final appDoc = await db
          .collection('applications')
          .doc(applicationId)
          .get();

      if (!appDoc.exists) {
        ToastHelper.showError('지원서를 찾을 수 없습니다');
        return false;
      }

      final appData = appDoc.data()!;
      final uid = appData['uid'] as String;

      if (appData['status'] != 'CONFIRMED') {
        ToastHelper.showError('확정된 지원만 취소할 수 있습니다');
        return false;
      }

      final batch = db.batch();

      // 1. 지원서 상태 변경
      batch.update(
        db.collection('applications').doc(applicationId),
        {
          'status': 'CANCELED',
          'canceledAt': FieldValue.serverTimestamp(),
          'cancelReason': applyNoShowPenalty ? 'SAME_DAY_CANCEL' : 'USER_CANCELED',
        },
      );

      // 2. 노쇼 패널티 적용
      if (applyNoShowPenalty) {
        batch.update(
          db.collection('users').doc(uid),
          {
            'noShowCount': FieldValue.increment(1),
          },
        );

        final userDoc = await db.collection('users').doc(uid).get();
        final currentNoShow = (userDoc.data()?['noShowCount'] ?? 0) as int;
        
        if (currentNoShow >= 2) {
          final restrictedUntil = DateTime.now().add(const Duration(days: 3));
          batch.update(
            db.collection('users').doc(uid),
            {
              'restrictedUntil': Timestamp.fromDate(restrictedUntil),
              'noShowCount': 0,
            },
          );
        }
      }

      // 3. TO 찾기 및 통계 Increment
      final businessId = appData['businessId'];
      final toTitle = appData['toTitle'];
      final workDate = appData['workDate'] as Timestamp;
      final workDetailId = appData['workDetailId'] as String?;

      final toSnapshot = await db
          .collection('tos')
          .where('businessId', isEqualTo: businessId)
          .where('title', isEqualTo: toTitle)
          .where('date', isEqualTo: workDate)
          .limit(1)
          .get();

      if (toSnapshot.docs.isNotEmpty) {
        final toDoc = toSnapshot.docs.first;
        final toId = toDoc.id;
        final toData = toDoc.data();
        final groupId = toData['groupId'] as String?;

        batch.update(toDoc.reference, {
          'totalConfirmed': FieldValue.increment(-1),
        });

        if (workDetailId != null && workDetailId.isNotEmpty) {
          batch.update(
            db
                .collection('tos')
                .doc(toId)
                .collection('workDetails')
                .doc(workDetailId),
            {
              'currentCount': FieldValue.increment(-1),
            },
          );
        }

        if (groupId != null) {
          final masterSnapshot = await db
              .collection('tos')
              .where('groupId', isEqualTo: groupId)
              .where('isGroupMaster', isEqualTo: true)
              .limit(1)
              .get();

          if (masterSnapshot.docs.isNotEmpty) {
            batch.update(masterSnapshot.docs.first.reference, {
              'groupTotalConfirmed': FieldValue.increment(-1),
            });
          }
        }

        await batch.commit();
        clearCache(toId: toId);
      } else {
        await batch.commit();
      }
      
      await _cleanupApplicationRelatedData(
        applicationId: applicationId,
        uid: uid,
      );

      print('✅ 확정 취소 완료 (패널티: $applyNoShowPenalty)');
      return true;
    } catch (e) {
      print('❌ 확정 취소 실패: $e');
      ToastHelper.showError('확정 취소에 실패했습니다');
      return false;
    }
  }

  /// 지원자 업무유형 변경 (관리자용)
  Future<bool> changeApplicationWorkType({
    required String applicationId,
    required String newWorkType,
    required int newWage,
    required String adminUID,
  }) async {
    try {
      final appDoc = await db
          .collection('applications')
          .doc(applicationId)
          .get();

      if (!appDoc.exists) {
        ToastHelper.showError('지원서를 찾을 수 없습니다.');
        return false;
      }

      final appData = appDoc.data()!;
      final currentWorkType = appData['selectedWorkType'];
      final currentWage = appData['wage'];

      await db.collection('applications').doc(applicationId).update({
        'selectedWorkType': newWorkType,
        'wage': newWage,
        'originalWorkType': appData['originalWorkType'] ?? currentWorkType,
        'originalWage': appData['originalWage'] ?? currentWage,
        'changedAt': FieldValue.serverTimestamp(),
        'changedBy': adminUID,
      });

      print('✅ 업무유형 변경 완료: $currentWorkType → $newWorkType');
      ToastHelper.showSuccess('업무유형이 변경되었습니다.');
      return true;
    } catch (e) {
      print('❌ 업무유형 변경 실패: $e');
      ToastHelper.showError('업무유형 변경에 실패했습니다.');
      return false;
    }
  }
  // ═══════════════════════════════════════════════════════════
  // 충돌 체크 헬퍼 메서드
  // ═══════════════════════════════════════════════════════════

  /// 확정된 근무 일정 조회 (장기 공고 날짜 확장 포함)
  Future<List<ApplicationModel>> getConfirmedSchedules({
    required String uid,
    required DateTime workDate,
  }) async {
    try {
      // 모든 확정된 지원서 조회
      final snapshot = await db
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('status', isEqualTo: 'CONFIRMED')
          .get();
      
      final allConfirmed = snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
      
      // 해당 날짜와 겹치는 근무만 필터링
      final relevantSchedules = <ApplicationModel>[];
      
      for (var app in allConfirmed) {
        if (_isWorkingOnDate(app, workDate)) {
          relevantSchedules.add(app);
        }
      }
      
      print('✅ ${workDate.month}/${workDate.day}에 확정된 근무: ${relevantSchedules.length}개');
      return relevantSchedules;
    } catch (e) {
      print('❌ 확정 일정 조회 실패: $e');
      return [];
    }
  }

  /// 충돌하는 지원서 찾기 (장기 공고 날짜 확장 포함)
  Future<List<ApplicationModel>> findConflictingApplications({
    required String uid,
    required DateTime workDate,
    required String startTime,
    required String endTime,
    required String excludeId,
    String status = 'PENDING',
  }) async {
    try {
      final snapshot = await db
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('status', isEqualTo: status)
          .get();
      
      final conflicts = <ApplicationModel>[];
      
      for (var doc in snapshot.docs) {
        if (doc.id == excludeId) continue;
        
        final app = ApplicationModel.fromFirestore(doc);
        
        if (!_isWorkingOnDate(app, workDate)) continue;
        
        if (_hasTimeOverlap(startTime, endTime, app.startTime, app.endTime)) {
          conflicts.add(app);
        }
      }
      
      print('✅ 충돌하는 지원서 ${conflicts.length}개 발견');
      return conflicts;
    } catch (e) {
      print('❌ 충돌 지원서 조회 실패: $e');
      return [];
    }
  }

  /// 시간이 겹치는지 체크
  bool _hasTimeOverlap(String s1, String e1, String s2, String e2) {
    final start1 = _timeToMinutes(s1);
    final end1 = _timeToMinutes(e1);
    final start2 = _timeToMinutes(s2);
    final end2 = _timeToMinutes(e2);
    
    return !(end1 <= start2 || end2 <= start1);
  }
  
  /// 시간을 분 단위로 변환 (예: "09:30" → 570)
  int _timeToMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  /// 특정 날짜에 근무하는지 확인 (장기 공고 고려)
  bool _isWorkingOnDate(ApplicationModel app, DateTime targetDate) {
    final isLongTerm = app.workDays != null && app.workDays!.isNotEmpty;
    
    if (!isLongTerm) {
      return _isSameDate(app.workDate, targetDate);
    }
    
    if (app.workEndDate == null) return false;
    
    DateTime effectiveStartDate = app.workDate;
    if (app.confirmedAt != null) {
      final confirmedDate = DateTime(
        app.confirmedAt!.year,
        app.confirmedAt!.month,
        app.confirmedAt!.day,
      );
      if (confirmedDate.isAfter(app.workDate)) {
        effectiveStartDate = confirmedDate;
      }
    }
    
    final isInRange = !targetDate.isBefore(effectiveStartDate) && 
                      !targetDate.isAfter(app.workEndDate!);
    
    if (!isInRange) return false;
    
    if (app.workDays == null || app.workDays!.isEmpty) {
      return true;
    }
    
    final targetDayKorean = _getKoreanDayOfWeek(targetDate);
    return app.workDays!.contains(targetDayKorean);
  }
  
  /// 두 날짜가 같은지 비교 (시간 제외)
  bool _isSameDate(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
           date1.month == date2.month &&
           date1.day == date2.day;
  }
  
  /// 요일을 한글로 변환
  String _getKoreanDayOfWeek(DateTime date) {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return days[date.weekday - 1];
  }

  // ═══════════════════════════════════════════════════════════
  // 연관 데이터 정리
  // ═══════════════════════════════════════════════════════════

  /// 지원서 취소/거절 시 연관 데이터 정리
  Future<void> _cleanupApplicationRelatedData({
    required String applicationId,
    required String uid,
    WriteBatch? batch,
  }) async {
    print('🧹 [Cleanup] 연관 데이터 정리 시작: $applicationId');
    
    final useBatch = batch != null;
    final localBatch = batch ?? db.batch();
    
    try {
      // 1. 신분증 요청 무효화 (pending → canceled)
      final idCardRequests = await db
          .collection('idCardAccessRequests')
          .where('applicationId', isEqualTo: applicationId)
          .where('status', isEqualTo: 'pending')
          .get();
      
      for (var doc in idCardRequests.docs) {
        localBatch.update(doc.reference, {
          'status': 'canceled',
          'canceledAt': FieldValue.serverTimestamp(),
          'cancelReason': 'APPLICATION_CANCELED',
        });
      }
      print('   📋 신분증 요청 ${idCardRequests.docs.length}건 무효화');
      
      // 2. 출근 데이터는 유지 (근무 이력 보존)
      
      // 3. 스케줄 변경 요청 취소 (PENDING → CANCELED)
      final scheduleRequests = await db
          .collection('scheduleChangeRequests')
          .where('applicationId', isEqualTo: applicationId)
          .where('status', isEqualTo: 'PENDING')
          .get();
      
      for (var doc in scheduleRequests.docs) {
        localBatch.update(doc.reference, {
          'status': 'CANCELED',
          'canceledAt': FieldValue.serverTimestamp(),
          'cancelReason': 'APPLICATION_CANCELED',
        });
      }
      print('   📋 스케줄 요청 ${scheduleRequests.docs.length}건 취소');
      
      if (!useBatch) {
        await localBatch.commit();
      }
      
      print('✅ [Cleanup] 연관 데이터 정리 완료');
    } catch (e) {
      print('❌ [Cleanup] 연관 데이터 정리 실패: $e');
    }
  }

}