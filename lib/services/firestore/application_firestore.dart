part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// 지원서 관리 (Application Management)
// ═══════════════════════════════════════════════════════════

extension ApplicationFirestore on FirestoreService {
  // ═══════════════════════════════════════════════════════════
  // 지원서 관리 (Application Management)
  // ═══════════════════════════════════════════════════════════

  /// TO별 지원자 목록 조회
  Future<List<ApplicationModel>> getApplicationsByTOId(String toId) async {
    try {
      // 1. TO 정보 조회
      final toDoc = await _firestore.collection('tos').doc(toId).get();
      if (!toDoc.exists) {
        print('❌ TO를 찾을 수 없습니다: $toId');
        return [];
      }

      final toData = toDoc.data()!;
      final businessId = toData['businessId'];
      final toTitle = toData['title'];
      final workDate = toData['date'] as Timestamp;

      // 2. businessId, toTitle, workDate로 지원서 조회
      final snapshot = await _firestore
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
        final toDoc = await _firestore.collection('tos').doc(toId).get();
        if (!toDoc.exists) {
          return MapEntry(toId, <ApplicationModel>[]);
        }

        final toData = toDoc.data()!;
        final businessId = toData['businessId'];
        final toTitle = toData['title'];
        final workDate = toData['date'] as Timestamp;

        // 지원서 조회
        final snapshot = await _firestore
            .collection('applications')
            .where('businessId', isEqualTo: businessId)
            .where('toTitle', isEqualTo: toTitle)
            .where('workDate', isEqualTo: workDate)
            .get();

        final apps = snapshot.docs
            .map((doc) => ApplicationModel.fromFirestore(doc))
            .toList();
        
        return MapEntry(toId, apps);
      }).toList();
      
      // ✅ 병렬 실행 완료 대기
      final results = await Future.wait(futures);
      final result = Map.fromEntries(results);
      
      print('✅ 배치 지원자 조회 완료 (병렬): ${toIds.length}개 TO, ${result.values.fold(0, (sum, list) => sum + list.length)}명');
      return result;
    } catch (e) {
      print('❌ 배치 지원자 조회 실패: $e');
      return {};
    }
  }
  /// 사업장별 지원자 목록 조회
  Future<List<ApplicationModel>> getApplicationsByBusinessId(String businessId) async {
    try {
      print('📋 사업장별 지원서 조회 시작: $businessId');
      
      final snapshot = await _firestore
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
        final snapshot = await _firestore
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
      final toDoc = await _firestore.collection('tos').doc(toId).get();
      if (!toDoc.exists) {
        print('❌ TO를 찾을 수 없습니다: $toId');
        return [];
      }

      final toData = toDoc.data()!;
      final businessId = toData['businessId'];
      final toTitle = toData['title'];
      final workDate = toData['date'] as Timestamp;

      // ✅ businessId, toTitle, workDate, workType으로 조회
      final snapshot = await _firestore
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
  /// TO의 모든 지원서 조회 (businessId, title, date 기준)
  /// [isLongTerm] - 장기 TO인 경우 날짜 필터 제외
  Future<List<ApplicationModel>> getApplicationsByTO(
    String businessId,
    String title,
    DateTime date, {
    bool isLongTerm = false,
  }) async {
    try {
      QuerySnapshot snapshot;
      
      if (isLongTerm) {
        // ✅ 장기 TO: businessId + toTitle로만 조회 (날짜 필터 제외)
        snapshot = await _firestore
            .collection('applications')
            .where('businessId', isEqualTo: businessId)
            .where('toTitle', isEqualTo: title)
            .get();
        
        print('✅ 장기 TO 지원서 조회: ${snapshot.docs.length}개 (businessId=$businessId, title=$title)');
      } else {
        // ✅ 단기 TO: 날짜 범위로 조회
        final dateStart = DateTime(date.year, date.month, date.day);
        final dateEnd = dateStart.add(const Duration(days: 1));
        
        snapshot = await _firestore
            .collection('applications')
            .where('businessId', isEqualTo: businessId)
            .where('toTitle', isEqualTo: title)
            .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(dateStart))
            .where('workDate', isLessThan: Timestamp.fromDate(dateEnd))
            .get();
        
        print('✅ 단기 TO 지원서 조회: ${snapshot.docs.length}개 (businessId=$businessId, title=$title, date=$dateStart~$dateEnd)');
      }

      final apps = snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();

      return apps;
    } catch (e) {
      print('❌ TO 지원서 조회 실패: $e');
      return [];
    }
  }
  

  /// 내 지원 내역 조회
  Future<List<ApplicationModel>> getMyApplications(String uid) async {
    try {
      final snapshot = await _firestore
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

  /// TO별 지원자 목록 + 사용자 정보 조회 (관리자용)
  Future<List<Map<String, dynamic>>> getApplicantsWithUserInfo(String toId) async {
    try {
      // ✅ TO 정보 먼저 조회
      final toDoc = await _firestore.collection('tos').doc(toId).get();
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
      QuerySnapshot appSnapshot = await _firestore
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

        final userDoc = await _firestore.collection('users').doc(uid).get();
        
        if (userDoc.exists) {
          final userData = userDoc.data() as Map<String, dynamic>;
          
          result.add({
            'applicationId': appDoc.id,
            'application': ApplicationModel.fromMap(appData, appDoc.id),
            'userName': userData['name'] ?? '(알 수 없음)',
            'userEmail': userData['email'] ?? '',
            'userPhone': userData['phone'] ?? '',
          });
        }
      }

      print('✅ 사용자 정보 포함 지원자: ${result.length}명');
      return result;
    } catch (e) {
      print('❌ 지원자 조회 실패: $e');
      return [];
    }
  }

  /// 지원하기 (업무유형 선택)
  Future<bool> applyToTOWithWorkType({
    required String businessId,
    required String businessName,
    required String toTitle,
    required DateTime workDate,
    required String uid,
    required String selectedWorkType,
    required String workDetailId,  // ✅ 추가
    required int wage,
    required String startTime,
    required String endTime,
    // ⭐ Phase 1: 장기 공고 정보 추가
    DateTime? workEndDate,
    List<String>? workDays,
    String type = 'short',
    // ✅ 장기공고 희망 시작일
    DateTime? desiredStartDate,
  }) async {
    try {
      // ✅ 서버 레벨 서류 체크
      final userDoc = await _firestore.collection('users').doc(uid).get();
      
      if (!userDoc.exists) {
        ToastHelper.showError('사용자 정보를 찾을 수 없습니다.');
        return false;
      }
      
      final userData = userDoc.data()!;
      
      // 필수 서류 체크
      if (userData['idCardImageUrl'] == null) {
        ToastHelper.showError('신분증 등록이 필요합니다.');
        return false;
      }
      
      if (userData['bankName'] == null || userData['accountNumber'] == null) {
        ToastHelper.showError('통장 정보 등록이 필요합니다.');
        return false;
      }
      
      if (userData['bankbookImageUrl'] == null) {
        ToastHelper.showError('통장사본 등록이 필요합니다.');
        return false;
      }
      // 1. 중복 지원 확인 - ✅ workDetailId 기준으로 체크 (시간대 다르면 다른 업무)
      // 먼저 workDetailId 찾기
      final toSnapshot = await _firestore
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

      // 1. 기존 지원서 확인 (상태 무관)
      final existingApp = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('toTitle', isEqualTo: toTitle)
          .where('workDate', isEqualTo: Timestamp.fromDate(workDate))
          .where('uid', isEqualTo: uid)
          .where('selectedWorkType', isEqualTo: selectedWorkType)
          .where('startTime', isEqualTo: startTime)
          .where('endTime', isEqualTo: endTime)
          .limit(1)
          .get();
      
      // 기존 지원서가 있는 경우
      if (existingApp.docs.isNotEmpty) {
        final existingDoc = existingApp.docs.first;
        final existingStatus = existingDoc.data()['status'];
        
        // 이미 활성 상태면 차단
        if (existingStatus == 'PENDING' || existingStatus == 'CONFIRMED') {
          print('🔍 활성 지원서 발견: 이미 지원한 업무');
          ToastHelper.showWarning('이미 지원한 업무입니다.');
          return false;
        }
        
        // 취소/거절 상태면 → 재지원 (status만 업데이트)
        print('✅ 기존 지원서 재활성화: ${existingDoc.id}');
        
        final batch = _firestore.batch();
        
        // 지원서 상태 업데이트
        batch.update(existingDoc.reference, {
          'status': 'PENDING',
          'appliedAt': FieldValue.serverTimestamp(),
          'canceledAt': null,
          'cancelReason': null,
          // ✅ 장기공고 희망 시작일도 업데이트
          if (desiredStartDate != null) 
            'desiredStartDate': Timestamp.fromDate(desiredStartDate),
        });
        
        // TO 통계 업데이트
        batch.update(_firestore.collection('tos').doc(toId), {
          'totalPending': FieldValue.increment(1),
        });
        
        // WorkDetail pendingCount 증가
        batch.update(
          _firestore
              .collection('tos')
              .doc(toId)
              .collection('workDetails')
              .doc(workDetailId),
          {
            'pendingCount': FieldValue.increment(1),
          },
        );
        
        // ✅ 그룹 마스터 통계 Increment (그룹 TO인 경우) - 재지원에도 추가!
        final toDoc = await _firestore.collection('tos').doc(toId).get();
        final groupId = toDoc.data()?['groupId'] as String?;
        
        if (groupId != null) {
          final masterSnapshot = await _firestore
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
        clearCache(toId: toId);
        
        print('✅ 재지원 완료 (기존 문서 업데이트)');
        return true;
      }
      // ⭐ Phase 2-C: 확정된 근무와 충돌 체크
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
          // ⚠️ 충돌 발견!
          ToastHelper.showError(
            '이미 ${schedule.startTime}~${schedule.endTime}에\n'
            '${schedule.businessName}에서 확정된 근무가 있습니다.\n\n'
            '해당 시간대에는 추가 지원이 불가능합니다.'
          );
          return false;
        }
      }

      // 4. Batch로 한번에 처리
      final batch = _firestore.batch();

      // ✅ 장기공고 여부 판단: workDays가 있어야 진짜 장기
      final isReallyLongTerm = type == 'long_term' && workDays != null && workDays.isNotEmpty;
      
      // 4-1. 지원서 생성
      final appRef = _firestore.collection('applications').doc();
      
      // ✅ groupId 조회 (이미 toDoc을 아래에서 조회하므로 여기서 미리 조회)
      final toDocForGroup = await _firestore.collection('tos').doc(toId).get();
      final groupIdForSave = toDocForGroup.data()?['groupId'] as String?;
      
      batch.set(appRef, {
        'uid': uid,
        'businessId': businessId,
        'businessName': businessName,
        'toId': toId,              // ✅ TO 고유 ID 저장
        'groupId': groupIdForSave, // ✅ 그룹 ID 저장
        'toTitle': toTitle,
        'selectedWorkType': selectedWorkType,
        'workDetailId': workDetailId,
        'wage': wage,
        'workDate': Timestamp.fromDate(workDate),
        'startTime': startTime,
        'endTime': endTime,
        'status': 'PENDING',
        'appliedAt': FieldValue.serverTimestamp(),
        // ✅ 장기 공고일 때만 추가 필드 저장 (단기는 null)
        'type': isReallyLongTerm ? 'long_term' : 'short',
        'workEndDate': isReallyLongTerm && workEndDate != null 
            ? Timestamp.fromDate(workEndDate) 
            : null,
        'workDays': isReallyLongTerm ? workDays : null,
        // ✅ 장기공고 희망 시작일 (장기일 때만)
        'desiredStartDate': isReallyLongTerm && desiredStartDate != null 
            ? Timestamp.fromDate(desiredStartDate) 
            : null,
      });

      // 4-2. TO 통계 업데이트
      batch.update(_firestore.collection('tos').doc(toId), {
        'totalApplications': FieldValue.increment(1),
        'totalPending': FieldValue.increment(1),
      });

      // 4-3. WorkDetail pendingCount 증가
      batch.update(
        _firestore
            .collection('tos')
            .doc(toId)
            .collection('workDetails')
            .doc(workDetailId),
        {
          'pendingCount': FieldValue.increment(1),
        },
      );

      // 4-4. 그룹 마스터 통계 Increment (그룹 TO인 경우)
      final toDoc = await _firestore.collection('tos').doc(toId).get();
      final groupId = toDoc.data()?['groupId'] as String?;
      
      if (groupId != null) {
        final masterSnapshot = await _firestore
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
      
      // ✅ 캐시만 클리어 (재계산 없음!)
      clearCache(toId: toId);

      print('✅ 지원 완료: businessId=$businessId, toTitle=$toTitle, WorkType=$selectedWorkType');
      return true;
    } catch (e) {
      print('❌ 지원 실패: $e');
      ToastHelper.showError('지원 중 오류가 발생했습니다.');
      return false;
    }
  }
  /// TO에 지원하기 (간편 버전)
  /// 
  /// apply_work_dialog에서 사용
  Future<bool> applyForTO({
    required String toId,
    required String workDetailId,
    required String workType,
    required String uid,
    DateTime? desiredStartDate,  // ✅ 장기공고 희망 시작일
  }) async {
    try {
      // 1. TO 정보 조회
      final toDoc = await _firestore.collection('tos').doc(toId).get();
      if (!toDoc.exists) {
        ToastHelper.showError('TO를 찾을 수 없습니다');
        return false;
      }

      final toData = toDoc.data()!;
      final to = TOModel.fromMap(toData, toId);

      // 2. WorkDetail 정보 조회
      final workDetailDoc = await _firestore
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
        workDetailId: workDetailId,  // ✅ 추가
        wage: workDetail.wage,
        startTime: workDetail.startTime,
        endTime: workDetail.endTime,
        workEndDate: to.endDate,
        workDays: to.workDays,
        type: to.isLongTerm ? 'long_term' : 'short',
        desiredStartDate: desiredStartDate,  // ✅ 희망 시작일 전달
      );
    } catch (e) {
      print('❌ TO 지원 실패: $e');
      ToastHelper.showError('지원에 실패했습니다');
      return false;
    }
  }
  /// 지원자 승인 (관리자용)
  Future<bool> confirmApplicant(String applicationId, String adminUID) async {
    try {
      DocumentSnapshot appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();

      if (!appDoc.exists) {
        ToastHelper.showError('지원서를 찾을 수 없습니다.');
        return false;
      }

      final appData = appDoc.data() as Map<String, dynamic>;

      if (appData['status'] == 'CONFIRMED') {
        ToastHelper.showError('이미 확정된 지원자입니다.');
        return false;
      }

      if (appData['status'] == 'CANCELED') {
        ToastHelper.showError('취소된 지원자는 확정할 수 없습니다.');
        return false;
      }

      await _firestore.collection('applications').doc(applicationId).update({
        'status': 'CONFIRMED',
        'confirmedAt': FieldValue.serverTimestamp(),
        'confirmedBy': adminUID,
      });

      ToastHelper.showSuccess('지원자가 확정되었습니다.');
      return true;
    } catch (e) {
      print('지원자 승인 실패: $e');
      ToastHelper.showError('승인 중 오류가 발생했습니다.');
      return false;
    }
  }

  /// 지원자 확정 (WorkDetail count + TO 통계 업데이트 포함)
  Future<bool> confirmApplicantWithWorkDetail({
    required String applicationId,
    required String adminUID,
  }) async {
    try {
      // 1. 지원서 조회
      final appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();

      if (!appDoc.exists) {
        ToastHelper.showError('지원서를 찾을 수 없습니다.');
        return false;
      }

      final appData = appDoc.data()!;
      
      // 이미 확정된 경우
      if (appData['status'] == 'CONFIRMED') {
        ToastHelper.showError('이미 확정된 지원자입니다.');
        return false;
      }

      // 취소된 경우
      if (appData['status'] == 'CANCELED') {
        ToastHelper.showError('취소된 지원자는 확정할 수 없습니다.');
        return false;
      }

      // ✅ TO 식별 정보 추출
      final businessId = appData['businessId'];
      final toTitle = appData['toTitle'];
      final workDate = appData['workDate'] as Timestamp;
      final selectedWorkType = appData['selectedWorkType'];
      final uid = appData['uid'];

      // 2. TO 문서 찾기
      final toSnapshot = await _firestore
          .collection('tos')
          .where('businessId', isEqualTo: businessId)
          .where('title', isEqualTo: toTitle)
          .where('date', isEqualTo: workDate)
          .limit(1)
          .get();

      if (toSnapshot.docs.isEmpty) {
        ToastHelper.showError('TO를 찾을 수 없습니다.');
        return false;
      }

      final toId = toSnapshot.docs.first.id;

      // 3. WorkDetail ID 찾기
      final workDetailId = await findWorkDetailIdByType(toId, selectedWorkType);
      if (workDetailId == null) {
        ToastHelper.showError('업무유형 정보를 찾을 수 없습니다.');
        return false;
      }

      // 4. 정원 체크
      final workDetailDoc = await _firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .doc(workDetailId)
          .get();
      
      if (!workDetailDoc.exists) {
        ToastHelper.showError('업무 정보를 찾을 수 없습니다.');
        return false;
      }
      
      final workDetailData = workDetailDoc.data()!;
      final currentCount = workDetailData['currentCount'] ?? 0;
      final requiredCount = workDetailData['requiredCount'] ?? 0;
      
      // 정원 초과 체크
      if (currentCount >= requiredCount) {
        ToastHelper.showError('이미 정원이 충족되었습니다. ($currentCount/$requiredCount명)');
        return false;
      }

      // 5. Batch 업데이트
      final batch = _firestore.batch();
      final now = Timestamp.now();

      // 5-1. 지원서 확정
      batch.update(_firestore.collection('applications').doc(applicationId), {
        'status': 'CONFIRMED',
        'confirmedAt': now,
        'confirmedBy': adminUID,
      });

      // 5-2. confirmed_applications 서브컬렉션에 추가
      final confirmedRef = _firestore
          .collection('tos')
          .doc(toId)
          .collection('confirmed_applications')
          .doc(applicationId);
      
      batch.set(confirmedRef, {
        'uid': uid,
        'workDetailId': workDetailId,
        'confirmedAt': now,
        'confirmedBy': adminUID,
      });

      await batch.commit();

      // ✅ 통계 재계산 (통합 함수 사용)
      print('📊 지원자 확정 후 통계 재계산...');
      await recalculateTOStats(toId);
      clearCache(toId: toId);
      
      // ✅ 그룹 마스터 통계 동기화
      await syncGroupMasterStats(toId);

      print('✅ 지원자 확정 완료');
      ToastHelper.showSuccess('지원자가 확정되었습니다.');
      return true;
    } catch (e) {
      print('❌ 지원자 확정 실패: $e');
      ToastHelper.showError('확정 중 오류가 발생했습니다.');
      return false;
    }
  }

  /// 지원자 거절 (관리자용)
  Future<bool> rejectApplicant(
    String applicationId, 
    String adminUID, {
    String? rejectMessage,
  }) async {
    try {
      DocumentSnapshot appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();

      if (!appDoc.exists) {
        ToastHelper.showError('지원서를 찾을 수 없습니다.');
        return false;
      }

      final appData = appDoc.data() as Map<String, dynamic>;

      if (appData['status'] == 'CANCELED') {
        ToastHelper.showError('이미 취소된 지원자입니다.');
        return false;
      }

      // ✅ TO 식별 정보 추출
      final businessId = appData['businessId'];
      final toTitle = appData['toTitle'];
      final workDate = appData['workDate'] as Timestamp;

      // 지원서 거절 처리
      final updateData = <String, dynamic>{
        'status': 'REJECTED',
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectedBy': adminUID,
      };
      
      if (rejectMessage != null && rejectMessage.isNotEmpty) {
        updateData['rejectMessage'] = rejectMessage;
      }
      
      // ✅ TO 찾기 (장기공고 고려)
      final isLongTerm = appData['isLongTermApplication'] == true;
      
      QuerySnapshot toSnapshot;
      if (isLongTerm) {
        // 🔥 장기공고: date 대신 isLongTerm + title로 검색
        toSnapshot = await _firestore
            .collection('tos')
            .where('businessId', isEqualTo: businessId)
            .where('title', isEqualTo: toTitle)
            .where('isLongTerm', isEqualTo: true)
            .limit(1)
            .get();
        print('🔍 [확정취소] 장기공고 TO 검색: ${toSnapshot.docs.length}건');
      } else {
        // 단기공고: 기존 방식
        toSnapshot = await _firestore
            .collection('tos')
            .where('businessId', isEqualTo: businessId)
            .where('title', isEqualTo: toTitle)
            .where('date', isEqualTo: workDate)
            .limit(1)
            .get();
        print('🔍 [확정취소] 단기공고 TO 검색: ${toSnapshot.docs.length}건');
      }

      if (toSnapshot.docs.isEmpty) {
        await _firestore.collection('applications').doc(applicationId).update(updateData);
        print('✅ 지원자 거절 완료 (TO 없음)');
        return true;
      }

      final toDoc = toSnapshot.docs.first;
      final toId = toDoc.id;
      final toData = toDoc.data() as Map<String, dynamic>;
      final groupId = toData['groupId'] as String?;
      final workDetailId = appData['workDetailId'] as String?; 

      // ✅ Batch로 한 번에 처리
      final batch = _firestore.batch();

      // 1. 지원서 거절
      batch.update(_firestore.collection('applications').doc(applicationId), updateData);

      // 2. TO 통계 Increment (PENDING인 경우만)
      if (appData['status'] == 'PENDING') {
        batch.update(toDoc.reference, {
          'totalPending': FieldValue.increment(-1),
        });

        // 3. WorkDetail 통계 Increment
        if (workDetailId != null && workDetailId.isNotEmpty) {
          batch.update(
            _firestore
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
          final masterSnapshot = await _firestore
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
      }

      await batch.commit();
      clearCache(toId: toId);

      print('✅ 지원자 거절 완료');
      ToastHelper.showSuccess('지원자가 거절되었습니다.');
      return true;
    } catch (e) {
      print('❌ 지원자 거절 실패: $e');
      ToastHelper.showError('거절 중 오류가 발생했습니다.');
      return false;
    }
  }

  

  /// 지원 취소 (사용자용)
  Future<bool> cancelApplication(String applicationId, String uid) async {
    try {
      DocumentSnapshot appDoc = await _firestore
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

      // ✅ TO 식별 정보 추출
      final businessId = appData['businessId'];
      final toTitle = appData['toTitle'];
      final workDate = appData['workDate'] as Timestamp;

      // 🔥 장기공고 여부 확인
      final isLongTerm = appData['isLongTermApplication'] == true || 
                         appData['type'] == 'long_term';
      
      // ✅ TO 찾기 (장기공고 고려)
      QuerySnapshot toSnapshot;
      if (isLongTerm) {
        toSnapshot = await _firestore
            .collection('tos')
            .where('businessId', isEqualTo: businessId)
            .where('title', isEqualTo: toTitle)
            .where('isLongTerm', isEqualTo: true)
            .limit(1)
            .get();
        print('🔍 [지원취소] 장기공고 TO 검색: ${toSnapshot.docs.length}건');
      } else {
        toSnapshot = await _firestore
            .collection('tos')
            .where('businessId', isEqualTo: businessId)
            .where('title', isEqualTo: toTitle)
            .where('date', isEqualTo: workDate)
            .limit(1)
            .get();
        print('🔍 [지원취소] 단기공고 TO 검색: ${toSnapshot.docs.length}건');
      }

      if (toSnapshot.docs.isEmpty) {
        await _firestore.collection('applications').doc(applicationId).update({
          'status': 'CANCELED',
        });
        ToastHelper.showSuccess('지원이 취소되었습니다.');
        print('⚠️ [지원취소] TO 없음 - 지원서만 취소');
        return true;
      }

      final toDoc = toSnapshot.docs.first;
      final toId = toDoc.id;
      final toData = toDoc.data() as Map<String, dynamic>;
      final groupId = toData['groupId'] as String?;
      final workDetailId = appData['workDetailId'] as String?;  // ✅ 추가

      // ✅ Batch로 한 번에 처리
      final batch = _firestore.batch();

      // 1. 지원서 취소
      batch.update(_firestore.collection('applications').doc(applicationId), {
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
          _firestore
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
        final masterSnapshot = await _firestore
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
      
      // ✅ 연관 데이터 정리 (신분증 요청 등)
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
  /// 
  /// [applicationId] - 지원서 ID
  /// [applyNoShowPenalty] - true면 노쇼 카운트 증가
  Future<bool> cancelConfirmedApplication(
    String applicationId, {
    bool applyNoShowPenalty = false,
  }) async {
    try {
      // 1. 지원서 조회
      final appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();

      if (!appDoc.exists) {
        ToastHelper.showError('지원서를 찾을 수 없습니다');
        return false;
      }

      final appData = appDoc.data()!;
      final uid = appData['uid'] as String;

      // 2. 상태 확인
      if (appData['status'] != 'CONFIRMED') {
        ToastHelper.showError('확정된 지원만 취소할 수 있습니다');
        return false;
      }

      // 3. Batch로 처리
      final batch = _firestore.batch();

      // 3-1. 지원서 상태 변경
      batch.update(
        _firestore.collection('applications').doc(applicationId),
        {
          'status': 'CANCELED',
          'canceledAt': FieldValue.serverTimestamp(),
          'cancelReason': applyNoShowPenalty ? 'SAME_DAY_CANCEL' : 'USER_CANCELED',
        },
      );

      // 3-2. 노쇼 패널티 적용
      if (applyNoShowPenalty) {
        batch.update(
          _firestore.collection('users').doc(uid),
          {
            'noShowCount': FieldValue.increment(1),
          },
        );

        // 노쇼 3회 체크 → 3일 이용 제한
        final userDoc = await _firestore.collection('users').doc(uid).get();
        final currentNoShow = (userDoc.data()?['noShowCount'] ?? 0) as int;
        
        if (currentNoShow >= 2) { // 이번 취소 포함해서 3회
          final restrictedUntil = DateTime.now().add(const Duration(days: 3));
          batch.update(
            _firestore.collection('users').doc(uid),
            {
              'restrictedUntil': Timestamp.fromDate(restrictedUntil),
              'noShowCount': 0, // 리셋
            },
          );
        }
      }

      // 4. TO 찾기 및 통계 Increment
      final businessId = appData['businessId'];
      final toTitle = appData['toTitle'];
      final workDate = appData['workDate'] as Timestamp;
      final workDetailId = appData['workDetailId'] as String?;

      // 🔥 장기공고 여부 확인
      final isLongTerm = appData['isLongTermApplication'] == true;
      
      QuerySnapshot toSnapshot;
      if (isLongTerm) {
        // 장기공고: date 대신 isLongTerm + title로 검색
        toSnapshot = await _firestore
            .collection('tos')
            .where('businessId', isEqualTo: businessId)
            .where('title', isEqualTo: toTitle)
            .where('isLongTerm', isEqualTo: true)
            .limit(1)
            .get();
        print('🔍 [확정취소] 장기공고 TO 검색: ${toSnapshot.docs.length}건');
      } else {
        // 단기공고: 기존 방식
        toSnapshot = await _firestore
            .collection('tos')
            .where('businessId', isEqualTo: businessId)
            .where('title', isEqualTo: toTitle)
            .where('date', isEqualTo: workDate)
            .limit(1)
            .get();
        print('🔍 [확정취소] 단기공고 TO 검색: ${toSnapshot.docs.length}건');
      }

      if (toSnapshot.docs.isNotEmpty) {
        final toDoc = toSnapshot.docs.first;
        final toId = toDoc.id;
        final toData = toDoc.data() as Map<String, dynamic>;  // 🔥 캐스팅 추가
        final groupId = toData['groupId'] as String?;

        // TO 통계 Increment (CONFIRMED → CANCELED)
        batch.update(toDoc.reference, {
          'totalConfirmed': FieldValue.increment(-1),
        });

        // WorkDetail 통계 Increment
        if (workDetailId != null && workDetailId.isNotEmpty) {
          batch.update(
            _firestore
                .collection('tos')
                .doc(toId)
                .collection('workDetails')
                .doc(workDetailId),
            {
              'currentCount': FieldValue.increment(-1),
            },
          );
        }

        // 그룹 마스터 통계 Increment
        if (groupId != null) {
          final masterSnapshot = await _firestore
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
      
      // ✅ 연관 데이터 정리 (신분증 요청, 출근 기록, 스케줄 요청)
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
      // 1. 기존 지원서 조회
      final appDoc = await _firestore
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

      // 2. 업무유형 변경
      await _firestore.collection('applications').doc(applicationId).update({
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
  /// 지원서 상태 업데이트 (승인/거절) - Phase 2: 자동 취소 추가
  /// 반환: 충돌로 취소된 TO ID 목록 (확정 시에만, 그 외는 빈 목록)
  Future<List<String>> updateApplicationStatus({
    required String applicationId,
    required String status,
    String? confirmedBy,
    String? rejectedBy,
    String? message,  // ⭐ Phase 2: 메시지 추가
  }) async {
    try {
      // ✅ 먼저 현재 상태 조회 (통계 처리용)
      final currentAppDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();
      String? previousStatus;
      if (currentAppDoc.exists) {
        previousStatus = currentAppDoc.data()?['status'] as String?;
      }
      print('🔍 [updateApplicationStatus] 이전상태: $previousStatus → 새상태: $status');
      
      // ⭐ Phase 2: 확정 시 충돌 처리
      if (status == 'CONFIRMED') {
        final affectedTOIds = await _confirmWithConflictCheck(
          applicationId: applicationId,
          confirmedBy: confirmedBy,
          message: message,
        );
        return affectedTOIds;
      }
      
      // 기존 로직 (거절 등)
      final updates = <String, dynamic>{
        'status': status,
      };

      if (status == 'REJECTED') {
        updates['rejectedAt'] = FieldValue.serverTimestamp();
        if (rejectedBy != null) {
          updates['rejectedBy'] = rejectedBy;
        }
        if (message != null) {
          updates['rejectMessage'] = message;  // ⭐ Phase 2
        }
      }

      await _firestore
          .collection('applications')
          .doc(applicationId)
          .update(updates);

      print('✅ 지원서 상태 업데이트: $status');
      
      // ✅ REJECTED/CANCELED: Increment 방식으로 처리
      if (status == 'REJECTED' || status == 'CANCELED') {
        print('🔍 [updateApplicationStatus] REJECTED/CANCELED 처리 시작, previousStatus=$previousStatus');
        if (currentAppDoc.exists) {
          final appData = currentAppDoc.data()!;
          // ✅ previousStatus는 위에서 이미 저장됨 - 중복 선언 제거
          final workDetailId = appData['workDetailId'] as String?;
          
          // ✅ TO 찾기 (단기 우선, 실패 시 장기 시도)
          QuerySnapshot toSnapshot;
          
          // 1차: 단기공고로 검색 (날짜 포함)
          toSnapshot = await _firestore
              .collection('tos')
              .where('businessId', isEqualTo: appData['businessId'])
              .where('title', isEqualTo: appData['toTitle'])
              .where('date', isEqualTo: appData['workDate'])
              .limit(1)
              .get();
          print('🔍 [확정취소] 단기공고 TO 검색: ${toSnapshot.docs.length}건');
          
          // 2차: 단기 검색 실패 시 장기공고로 재시도
          if (toSnapshot.docs.isEmpty) {
            toSnapshot = await _firestore
                .collection('tos')
                .where('businessId', isEqualTo: appData['businessId'])
                .where('title', isEqualTo: appData['toTitle'])
                .where('isLongTerm', isEqualTo: true)
                .limit(1)
                .get();
            print('🔍 [확정취소] 장기공고 TO 재검색: ${toSnapshot.docs.length}건');
          }
          
          if (toSnapshot.docs.isNotEmpty) {
            final toDoc = toSnapshot.docs.first;
            final toId = toDoc.id;
            final toData = toDoc.data() as Map<String, dynamic>;
            final groupId = toData['groupId'] as String?;
            
            final batch = _firestore.batch();
            
            // ✅ 이전 상태에 따라 다른 통계 감소
            if (previousStatus == 'CONFIRMED') {
              // CONFIRMED → REJECTED/CANCELED: totalConfirmed 감소
              batch.update(toDoc.reference, {
                'totalConfirmed': FieldValue.increment(-1),
              });
              
              // WorkDetail currentCount 감소
              if (workDetailId != null && workDetailId.isNotEmpty) {
                batch.update(
                  _firestore
                      .collection('tos')
                      .doc(toId)
                      .collection('workDetails')
                      .doc(workDetailId),
                  {
                    'currentCount': FieldValue.increment(-1),
                  },
                );
              }
              
              // 그룹 마스터 통계 감소
              if (groupId != null) {
                final masterSnapshot = await _firestore
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
            } else if (previousStatus == 'PENDING') {
              // PENDING → REJECTED/CANCELED: totalPending 감소
              batch.update(toDoc.reference, {
                'totalPending': FieldValue.increment(-1),
              });
            
            // WorkDetail pendingCount 감소
              if (workDetailId != null && workDetailId.isNotEmpty) {
                batch.update(
                  _firestore
                      .collection('tos')
                      .doc(toId)
                      .collection('workDetails')
                      .doc(workDetailId),
                  {
                    'pendingCount': FieldValue.increment(-1),
                  },
                );
              }
              
              // 그룹 마스터 통계 감소
              if (groupId != null) {
                final masterSnapshot = await _firestore
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
            }
            
            await batch.commit();
            clearCache(toId: toId);
            print('📊 TO 통계 Increment 완료: $toId (이전상태: $previousStatus)');
          }
        }
      }
    // 🔥 확정이 아닌 경우 빈 목록 반환
      return [];
      
    } catch (e) {
      print('❌ 지원서 상태 업데이트 실패: $e');
      rethrow;
    }
  }
  
  /// 확정 처리 (Increment 방식 - 재계산 없음!)
  /// 반환: 충돌로 취소된 TO ID 목록
  Future<List<String>> _confirmWithConflictCheck({
    required String applicationId,
    String? confirmedBy,
    String? message,
  }) async {
    try {
      // 1. 지원서 조회
      final appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();
      
      if (!appDoc.exists) {
        throw Exception('지원서를 찾을 수 없습니다');
      }
      
      final appData = appDoc.data()!;
      final currentStatus = appData['status'];
      
      // 이미 확정/취소된 경우
      if (currentStatus == 'CONFIRMED') return [];
      if (currentStatus == 'CANCELED') {
        throw Exception('취소된 지원서는 확정할 수 없습니다');
      }
      
      final app = ApplicationModel.fromMap(appData, appDoc.id);
      final workDetailId = appData['workDetailId'] as String?;
      
      // 2. TO 찾기
      final toSnapshot = await _firestore
          .collection('tos')
          .where('businessId', isEqualTo: app.businessId)
          .where('title', isEqualTo: app.toTitle)
          .where('date', isEqualTo: Timestamp.fromDate(app.workDate))
          .limit(1)
          .get();
      
      if (toSnapshot.docs.isEmpty) {
        throw Exception('TO를 찾을 수 없습니다');
      }
      
      final toDoc = toSnapshot.docs.first;
      final toId = toDoc.id;
      final toData = toDoc.data();
      final groupId = toData['groupId'] as String?;
      
      // 3. 충돌하는 대기중 지원서 찾기
      // ✅ 장기공고인 경우 모든 근무일에 대해 충돌 체크
      final isConfirmingLongTerm = app.workDays != null && app.workDays!.isNotEmpty;
      
      List<ApplicationModel> conflictingApps;
      
      if (isConfirmingLongTerm && app.workEndDate != null) {
        // 장기공고: 모든 근무일에 대해 충돌 체크
        conflictingApps = await _findConflictingForLongTerm(
          uid: app.uid,
          startDate: app.workDate,
          endDate: app.workEndDate!,
          workDays: app.workDays!,
          startTime: app.startTime,
          endTime: app.endTime,
          excludeId: applicationId,
        );
      } else {
        // 단기공고: 해당 날짜만 체크
        conflictingApps = await findConflictingApplications(
          uid: app.uid,
          workDate: app.workDate,
          startTime: app.startTime,
          endTime: app.endTime,
          excludeId: applicationId,
          status: 'PENDING',
        );
      }
      
      print('✅ 충돌하는 지원서 ${conflictingApps.length}개 발견');
      
      // 4. Batch 처리 (모든 업데이트를 한 번에!)
      final batch = _firestore.batch();
      final now = FieldValue.serverTimestamp();
      
      // 4-1. 지원서 확정
      final confirmUpdates = <String, dynamic>{
        'status': 'CONFIRMED',
        'confirmedAt': now,
      };
      if (confirmedBy != null) confirmUpdates['confirmedBy'] = confirmedBy;
      if (message != null) confirmUpdates['confirmMessage'] = message;
      
      batch.update(appDoc.reference, confirmUpdates);
      
      // 4-2. TO 통계 Increment (PENDING → CONFIRMED)
      batch.update(toDoc.reference, {
        'totalConfirmed': FieldValue.increment(1),
        'totalPending': FieldValue.increment(-1),
      });
      
      // 4-3. WorkDetail 통계 Increment
      if (workDetailId != null && workDetailId.isNotEmpty) {
        batch.update(
          _firestore
              .collection('tos')
              .doc(toId)
              .collection('workDetails')
              .doc(workDetailId),
          {
            'currentCount': FieldValue.increment(1),
            'pendingCount': FieldValue.increment(-1),
          },
        );
      }
      
      // 4-4. 그룹 마스터 통계 Increment
      if (groupId != null) {
        final masterSnapshot = await _firestore
            .collection('tos')
            .where('groupId', isEqualTo: groupId)
            .where('isGroupMaster', isEqualTo: true)
            .limit(1)
            .get();
        
        if (masterSnapshot.docs.isNotEmpty) {
          batch.update(masterSnapshot.docs.first.reference, {
            'groupTotalConfirmed': FieldValue.increment(1),
            'groupTotalPending': FieldValue.increment(-1),
          });
        }
      }
      
      // 4-5. 충돌 지원 자동 취소 + TO 통계 감소
      for (var conflictApp in conflictingApps) {
        batch.update(
          _firestore.collection('applications').doc(conflictApp.id),
          {
            'status': 'AUTO_CANCELED',
            'canceledAt': now,
            'cancelReason': 'SCHEDULE_CONFLICT',
            'conflictingAppId': applicationId,
            'conflictingBusiness': app.businessName,
            'conflictingTime': '${app.startTime}~${app.endTime}',
          },
        );
      }
      
      // 5. 한 번에 커밋!
      await batch.commit();
      
      // 5-1. ✅ AUTO_CANCELED 된 지원서들의 TO 통계 업데이트 (별도 batch)
      final Set<String> affectedTOIds = {};  // 🔥 충돌 취소된 TO ID 수집
      
      if (conflictingApps.isNotEmpty) {
        final statsBatch = _firestore.batch();
        
        for (var conflictApp in conflictingApps) {
          // 🔥 충돌 지원서의 TO 찾기 (단기 우선, 실패 시 장기 시도)
          QuerySnapshot conflictTOSnapshot;
          
          // 1차: 단기공고로 검색 (날짜 포함)
          conflictTOSnapshot = await _firestore
              .collection('tos')
              .where('businessId', isEqualTo: conflictApp.businessId)
              .where('title', isEqualTo: conflictApp.toTitle)
              .where('date', isEqualTo: Timestamp.fromDate(conflictApp.workDate))
              .limit(1)
              .get();
          print('🔍 [충돌취소] 단기공고 TO 검색: ${conflictTOSnapshot.docs.length}건');
          
          // 2차: 단기 검색 실패 시 장기공고로 재시도
          if (conflictTOSnapshot.docs.isEmpty) {
            conflictTOSnapshot = await _firestore
                .collection('tos')
                .where('businessId', isEqualTo: conflictApp.businessId)
                .where('title', isEqualTo: conflictApp.toTitle)
                .where('isLongTerm', isEqualTo: true)
                .limit(1)
                .get();
            print('🔍 [충돌취소] 장기공고 TO 재검색: ${conflictTOSnapshot.docs.length}건');
          } else {
            conflictTOSnapshot = await _firestore
                .collection('tos')
                .where('businessId', isEqualTo: conflictApp.businessId)
                .where('title', isEqualTo: conflictApp.toTitle)
                .where('date', isEqualTo: Timestamp.fromDate(conflictApp.workDate))
                .limit(1)
                .get();
            print('🔍 [충돌취소] 단기공고 TO 검색: ${conflictTOSnapshot.docs.length}건');
          }
          
          if (conflictTOSnapshot.docs.isNotEmpty) {
            final conflictTODoc = conflictTOSnapshot.docs.first;
            final conflictTOData = conflictTODoc.data() as Map<String, dynamic>;  // 🔥 캐스팅 추가
            final conflictGroupId = conflictTOData['groupId'] as String?;
            
            // 🔥 영향받은 TO ID 저장
            affectedTOIds.add(conflictTODoc.id);
            
            // TO pendingCount 감소
            
            // TO pendingCount 감소
            statsBatch.update(conflictTODoc.reference, {
              'totalPending': FieldValue.increment(-1),
            });
            
            // WorkDetail pendingCount 감소
            final conflictWorkDetailId = conflictApp.workDetailId;
            if (conflictWorkDetailId != null && conflictWorkDetailId.isNotEmpty) {
              statsBatch.update(
                _firestore
                    .collection('tos')
                    .doc(conflictTODoc.id)
                    .collection('workDetails')
                    .doc(conflictWorkDetailId),
                {
                  'pendingCount': FieldValue.increment(-1),
                },
              );
            }
            
            // 그룹 마스터 통계 감소
            if (conflictGroupId != null) {
              final conflictMasterSnapshot = await _firestore
                  .collection('tos')
                  .where('groupId', isEqualTo: conflictGroupId)
                  .where('isGroupMaster', isEqualTo: true)
                  .limit(1)
                  .get();
              
              if (conflictMasterSnapshot.docs.isNotEmpty) {
                statsBatch.update(conflictMasterSnapshot.docs.first.reference, {
                  'groupTotalPending': FieldValue.increment(-1),
                });
              }
            }
            
            // 캐시 클리어
            clearCache(toId: conflictTODoc.id);
          }
        }
        
        await statsBatch.commit();
        print('✅ AUTO_CANCELED ${conflictingApps.length}건의 TO 통계 업데이트 완료');
      }
      
      // 6. 캐시만 클리어 (재계산 없음!)
      clearCache(toId: toId);
      
      print('✅ 확정 완료 + ${conflictingApps.length}개 자동 취소 (Increment 방식)');
      
      // 🔥 충돌 취소된 TO ID 목록 반환
      return affectedTOIds.toList();
      
    } catch (e) {
      print('❌ 확정 처리 실패: $e');
      rethrow;
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
      // 1. 해당 상태의 모든 지원서 조회
      final snapshot = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('status', isEqualTo: status)
          .get();
      
      // 2. 날짜와 시간대 겹침 필터링
      final conflicts = <ApplicationModel>[];
      
      for (var doc in snapshot.docs) {
        if (doc.id == excludeId) continue;
        
        final app = ApplicationModel.fromFirestore(doc);
        
        // 해당 날짜에 근무하는지 확인
        if (!_isWorkingOnDate(app, workDate)) continue;
        
        // 시간대 겹침 확인
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
  /// 장기공고 확정 시 모든 근무일에 대해 충돌하는 지원서 찾기
  Future<List<ApplicationModel>> _findConflictingForLongTerm({
    required String uid,
    required DateTime startDate,
    required DateTime endDate,
    required List<String> workDays,
    required String startTime,
    required String endTime,
    required String excludeId,
  }) async {
    try {
      print('📅 [LongTerm] 장기공고 충돌 체크 시작');
      print('   기간: ${startDate.month}/${startDate.day} ~ ${endDate.month}/${endDate.day}');
      print('   요일: $workDays');
      
      // 1. 해당 사용자의 모든 PENDING 지원서 조회
      final snapshot = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('status', isEqualTo: 'PENDING')
          .get();
      
      final conflicts = <ApplicationModel>{};  // Set으로 중복 방지
      
      // 2. 장기공고의 모든 근무일 생성
      final workingDates = <DateTime>[];
      var currentDate = startDate;
      
      while (!currentDate.isAfter(endDate)) {
        final dayOfWeek = _getKoreanDayOfWeek(currentDate);
        if (workDays.contains(dayOfWeek)) {
          workingDates.add(currentDate);
        }
        currentDate = currentDate.add(const Duration(days: 1));
      }
      
      print('   근무일 수: ${workingDates.length}일');
      
      // 3. 각 근무일에 대해 충돌 체크
      for (var doc in snapshot.docs) {
        if (doc.id == excludeId) continue;
        
        final app = ApplicationModel.fromFirestore(doc);
        
        // 각 근무일과 비교
        for (var workDate in workingDates) {
          // 해당 날짜에 근무하는 지원서인지 확인
          if (!_isWorkingOnDate(app, workDate)) continue;
          
          // 시간대 겹침 확인
          if (_hasTimeOverlap(startTime, endTime, app.startTime, app.endTime)) {
            conflicts.add(app);
            break;  // 이미 충돌 확인됐으면 다음 지원서로
          }
        }
      }
      
      print('✅ [LongTerm] 충돌 지원서 ${conflicts.length}개 발견');
      return conflicts.toList();
    } catch (e) {
      print('❌ [LongTerm] 충돌 조회 실패: $e');
      return [];
    }
  }
  /// 확정된 근무 일정 조회 (장기 공고 날짜 확장 포함)
  Future<List<ApplicationModel>> getConfirmedSchedules({
    required String uid,
    required DateTime workDate,
  }) async {
    try {
      // 1. 모든 확정된 지원서 조회
      final snapshot = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('status', isEqualTo: 'CONFIRMED')
          .get();
      
      final allConfirmed = snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
      
      // 2. 해당 날짜와 겹치는 근무만 필터링
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
  // ============================================================
  // 🧹 지원서 연관 데이터 정리 (공통)
  // ============================================================

  /// 지원서 취소/거절 시 연관 데이터 정리
  /// - 신분증 요청 무효화
  /// - 출근 데이터 삭제
  /// - 스케줄 변경 요청 취소
  Future<void> _cleanupApplicationRelatedData({
    required String applicationId,
    required String uid,
    WriteBatch? batch,
  }) async {
    print('🧹 [Cleanup] 연관 데이터 정리 시작: $applicationId');
    
    final useBatch = batch != null;
    final localBatch = batch ?? _firestore.batch();
    
    try {
      // 1. 신분증 요청 무효화 (pending → canceled)
      final idCardRequests = await _firestore
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
      // 확정 취소되어도 이미 출근한 기록은 남겨둠
      
      // 3. 스케줄 변경 요청 취소 (PENDING → CANCELED)
      final scheduleRequests = await _firestore
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
      
      // batch가 외부에서 제공되지 않은 경우에만 commit
      if (!useBatch) {
        await localBatch.commit();
      }
      
      print('✅ [Cleanup] 연관 데이터 정리 완료');
    } catch (e) {
      print('❌ [Cleanup] 연관 데이터 정리 실패: $e');
      // 실패해도 메인 로직은 계속 진행
    }
  }
  // ═══════════════════════════════════════════════════════════
  // 일괄 처리 메서드 (Batch Operations)
  // ═══════════════════════════════════════════════════════════

  /// 지원서 일괄 확정 (Increment 방식)
  Future<BatchResult> batchConfirmApplications({
    required List<String> applicationIds,
    required String adminUID,
  }) async {
    if (applicationIds.isEmpty) {
      return BatchResult(success: 0, failed: 0);
    }
    
    try {
      print('📦 [Batch] 일괄 확정 시작: ${applicationIds.length}건');
      
      // 1. 모든 지원서 조회 (병렬)
      final appFutures = applicationIds.map((id) => 
        _firestore.collection('applications').doc(id).get()
      );
      final appDocs = await Future.wait(appFutures);
      
      // 2. TO 정보 한 번만 조회
      String? toId;
      String? groupId;
      DocumentReference? toRef;
      DocumentReference? masterRef;
      
      for (var appDoc in appDocs) {
        if (!appDoc.exists) continue;
        final appData = appDoc.data()!;
        
        if (toId == null) {
          final toSnapshot = await _firestore
              .collection('tos')
              .where('businessId', isEqualTo: appData['businessId'])
              .where('title', isEqualTo: appData['toTitle'])
              .where('date', isEqualTo: appData['workDate'])
              .limit(1)
              .get();
          
          if (toSnapshot.docs.isNotEmpty) {
            toRef = toSnapshot.docs.first.reference;
            toId = toSnapshot.docs.first.id;
            groupId = toSnapshot.docs.first.data()['groupId'] as String?;
            
            // 마스터 TO 찾기
            if (groupId != null) {
              final masterSnapshot = await _firestore
                  .collection('tos')
                  .where('groupId', isEqualTo: groupId)
                  .where('isGroupMaster', isEqualTo: true)
                  .limit(1)
                  .get();
              
              if (masterSnapshot.docs.isNotEmpty) {
                masterRef = masterSnapshot.docs.first.reference;
              }
            }
          }
        }
        break;
      }
      
      // 3. Batch 처리
      final batch = _firestore.batch();
      final now = Timestamp.now();
      int successCount = 0;
      int failedCount = 0;
      
      // WorkDetail별 카운트 집계
      Map<String, int> workDetailCounts = {};
      
      for (var appDoc in appDocs) {
        if (!appDoc.exists) {
          failedCount++;
          continue;
        }
        
        final appData = appDoc.data()!;
        
        if (appData['status'] == 'CONFIRMED' || appData['status'] == 'CANCELED') {
          failedCount++;
          continue;
        }
        
        // 지원서 확정
        batch.update(appDoc.reference, {
          'status': 'CONFIRMED',
          'confirmedAt': now,
          'confirmedBy': adminUID,
        });
        
        // WorkDetail 카운트 집계
        final workDetailId = appData['workDetailId'] as String?;
        if (workDetailId != null && workDetailId.isNotEmpty) {
          workDetailCounts[workDetailId] = (workDetailCounts[workDetailId] ?? 0) + 1;
        }
        
        successCount++;
      }
      
      // TO 통계 한 번에 업데이트
      if (toRef != null && successCount > 0) {
        batch.update(toRef, {
          'totalConfirmed': FieldValue.increment(successCount),
          'totalPending': FieldValue.increment(-successCount),
        });
      }
      
      // WorkDetail 통계 한 번에 업데이트
      for (var entry in workDetailCounts.entries) {
        batch.update(
          _firestore
              .collection('tos')
              .doc(toId)
              .collection('workDetails')
              .doc(entry.key),
          {
            'currentCount': FieldValue.increment(entry.value),
            'pendingCount': FieldValue.increment(-entry.value),
          },
        );
      }
      
      // 그룹 마스터 통계 한 번에 업데이트
      if (masterRef != null && successCount > 0) {
        batch.update(masterRef, {
          'groupTotalConfirmed': FieldValue.increment(successCount),
          'groupTotalPending': FieldValue.increment(-successCount),
        });
      }
      
      await batch.commit();
      
      if (toId != null) clearCache(toId: toId);
      
      print('✅ [Batch] 확정 완료: $successCount건 성공, $failedCount건 실패');
      return BatchResult(success: successCount, failed: failedCount);
    } catch (e) {
      print('❌ [Batch] 일괄 확정 실패: $e');
      rethrow;
    }
  }

  /// 지원서 일괄 거절 (Increment 방식)
  Future<BatchResult> batchRejectApplications({
    required List<String> applicationIds,
    required String adminUID,
    String? message,
  }) async {
    if (applicationIds.isEmpty) {
      return BatchResult(success: 0, failed: 0);
    }
    
    try {
      print('📦 [Batch] 일괄 거절 시작: ${applicationIds.length}건');
      
      final appFutures = applicationIds.map((id) => 
        _firestore.collection('applications').doc(id).get()
      );
      final appDocs = await Future.wait(appFutures);
      
      String? toId;
      String? groupId;
      DocumentReference? toRef;
      DocumentReference? masterRef;
      
      for (var appDoc in appDocs) {
        if (!appDoc.exists) continue;
        final appData = appDoc.data()!;
        
        if (toId == null) {
          final toSnapshot = await _firestore
              .collection('tos')
              .where('businessId', isEqualTo: appData['businessId'])
              .where('title', isEqualTo: appData['toTitle'])
              .where('date', isEqualTo: appData['workDate'])
              .limit(1)
              .get();
          
          if (toSnapshot.docs.isNotEmpty) {
            toRef = toSnapshot.docs.first.reference;
            toId = toSnapshot.docs.first.id;
            groupId = toSnapshot.docs.first.data()['groupId'] as String?;
            
            if (groupId != null) {
              final masterSnapshot = await _firestore
                  .collection('tos')
                  .where('groupId', isEqualTo: groupId)
                  .where('isGroupMaster', isEqualTo: true)
                  .limit(1)
                  .get();
              
              if (masterSnapshot.docs.isNotEmpty) {
                masterRef = masterSnapshot.docs.first.reference;
              }
            }
          }
        }
        break;
      }
      
      final batch = _firestore.batch();
      final now = Timestamp.now();
      int successCount = 0;
      int failedCount = 0;
      
      Map<String, int> workDetailCounts = {};
      
      for (var appDoc in appDocs) {
        if (!appDoc.exists) {
          failedCount++;
          continue;
        }
        
        final appData = appDoc.data()!;
        
        if (appData['status'] == 'CANCELED') {
          failedCount++;
          continue;
        }
        
        final updates = <String, dynamic>{
          'status': 'REJECTED',
          'rejectedAt': now,
          'rejectedBy': adminUID,
        };
        if (message != null) updates['rejectMessage'] = message;
        
        batch.update(appDoc.reference, updates);
        
        // PENDING인 경우만 카운트
        if (appData['status'] == 'PENDING') {
          final workDetailId = appData['workDetailId'] as String?;
          if (workDetailId != null && workDetailId.isNotEmpty) {
            workDetailCounts[workDetailId] = (workDetailCounts[workDetailId] ?? 0) + 1;
          }
        }
        
        successCount++;
      }
      
      // PENDING 거절 수만큼 통계 감소
      final pendingRejectCount = workDetailCounts.values.fold(0, (sum, v) => sum + v);
      
      if (toRef != null && pendingRejectCount > 0) {
        batch.update(toRef, {
          'totalPending': FieldValue.increment(-pendingRejectCount),
        });
      }
      
      for (var entry in workDetailCounts.entries) {
        batch.update(
          _firestore
              .collection('tos')
              .doc(toId)
              .collection('workDetails')
              .doc(entry.key),
          {
            'pendingCount': FieldValue.increment(-entry.value),
          },
        );
      }
      
      if (masterRef != null && pendingRejectCount > 0) {
        batch.update(masterRef, {
          'groupTotalPending': FieldValue.increment(-pendingRejectCount),
        });
      }
      
      await batch.commit();
      
      if (toId != null) clearCache(toId: toId);
      
      print('✅ [Batch] 거절 완료: $successCount건');
      return BatchResult(success: successCount, failed: failedCount);
    } catch (e) {
      print('❌ [Batch] 일괄 거절 실패: $e');
      rethrow;
    }
  }
  /// 해당 application에 출퇴근 기록이 있는지 확인
  Future<bool> hasAttendanceRecord(String applicationId) async {
    try {
      final snapshot = await _firestore
          .collection('attendance')
          .where('applicationId', isEqualTo: applicationId)
          .limit(1)
          .get();
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      print('❌ 출퇴근 기록 확인 실패: $e');
      return false;
    }
  }
  // ═══════════════════════════════════════════════════════════
  // 지원 다이얼로그용 메서드
  // ═══════════════════════════════════════════════════════════

  /// 특정 TO에 대한 사용자의 지원 목록 조회
  /// 
  /// [toId] - TO 문서 ID
  /// [uid] - 사용자 UID
  /// 
  /// 반환: 해당 사용자가 이 TO에 지원한 모든 지원서
  Future<List<ApplicationModel>> getApplicationsForTO({
    required String toId,
    required String uid,
  }) async {
    try {
      // TO 정보 먼저 조회
      final toDoc = await _firestore.collection('tos').doc(toId).get();
      if (!toDoc.exists) return [];

      final toData = toDoc.data()!;
      final businessId = toData['businessId'];
      final toTitle = toData['title'];
      final workDate = toData['date'] as Timestamp;

      // 지원서 조회
      final snapshot = await _firestore
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
  /// 지원서 업데이트
  Future<bool> updateApplication(String applicationId, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update(data);
      print('✅ 지원서 업데이트 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 지원서 업데이트 실패: $e');
      return false;
    }
  }
  /// ApplicationModel에서 TO 찾기
  Future<TOModel?> getTOByApplication(ApplicationModel app) async {
    try {
      final snapshot = await _firestore
          .collection('tos')
          .where('businessId', isEqualTo: app.businessId)
          .where('title', isEqualTo: app.toTitle)
          .where('date', isEqualTo: Timestamp.fromDate(
            DateTime(app.workDate.year, app.workDate.month, app.workDate.day)
          ))
          .limit(1)
          .get();
      
      if (snapshot.docs.isEmpty) {
        print('⚠️ TO를 찾을 수 없음: ${app.businessId} / ${app.toTitle} / ${app.workDate}');
        return null;
      }
      
      final doc = snapshot.docs.first;
      return TOModel.fromMap(doc.data(), doc.id);
    } catch (e) {
      print('❌ TO 조회 실패: $e');
      return null;
    }
  }
  // ═══════════════════════════════════════════════════════════
  // 🔥 Phase A: 퇴사 관리 시스템
  // ═══════════════════════════════════════════════════════════

  /// 퇴사 요청 (지원자용)
  Future<bool> requestResignation({
    required String applicationId,
    required DateTime resignDate,
  }) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'resignRequestedAt': Timestamp.fromDate(DateTime.now()),
        'resignRequestDate': Timestamp.fromDate(resignDate),
        'resignStatus': 'PENDING',
      });

      print('✅ 퇴사 요청 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 퇴사 요청 실패: $e');
      return false;
    }
  }

  /// 퇴사 요청 취소 (지원자용)
  Future<bool> cancelResignRequest(String applicationId) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'resignRequestedAt': FieldValue.delete(),
        'resignRequestDate': FieldValue.delete(),
        'resignStatus': FieldValue.delete(),
      });

      print('✅ 퇴사 요청 취소 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 퇴사 요청 취소 실패: $e');
      return false;
    }
  }

  /// 퇴사 승인 (관리자용)
  Future<bool> approveResignation({
    required String applicationId,
    required String adminUID,
  }) async {
    try {
      final appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();

      if (!appDoc.exists) {
        ToastHelper.showError('지원서를 찾을 수 없습니다.');
        return false;
      }

      final appData = appDoc.data() as Map<String, dynamic>;
      final resignDate = (appData['resignRequestDate'] as Timestamp).toDate();

      await _firestore.collection('applications').doc(applicationId).update({
        'resignStatus': 'APPROVED',
        'resignApprovedAt': Timestamp.fromDate(DateTime.now()),
        'resignApprovedBy': adminUID,
        'actualResignDate': Timestamp.fromDate(resignDate),
        'workEndDate': Timestamp.fromDate(resignDate), // 실제 종료일 업데이트
      });

      print('✅ 퇴사 승인 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 퇴사 승인 실패: $e');
      return false;
    }
  }

  /// 퇴사 거절 (관리자용)
  Future<bool> rejectResignation({
    required String applicationId,
    required String adminUID,
    required String rejectReason,
  }) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'resignStatus': 'REJECTED',
        'resignApprovedAt': Timestamp.fromDate(DateTime.now()),
        'resignApprovedBy': adminUID,
        'resignRejectReason': rejectReason,
      });

      print('✅ 퇴사 거절 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 퇴사 거절 실패: $e');
      return false;
    }
  }
  // ============================================================
  // 🔥 계약해지 관리 (관리자 → 근무자)
  // ============================================================

  /// 계약해지 요청 (관리자용)
  Future<bool> requestTermination({
    required String applicationId,
    required String reason,
    required String requestedByUid,
  }) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'terminationRequestedAt': Timestamp.fromDate(DateTime.now()),
        'terminationReason': reason,
        'terminationRequestedByUid': requestedByUid,
        'terminationStatus': 'PENDING',
      });

      print('✅ 계약해지 요청 완료: $applicationId');
      
      // TODO: 근무자에게 알림 발송
      // await _sendTerminationNotification(applicationId);
      
      return true;
    } catch (e) {
      print('❌ 계약해지 요청 실패: $e');
      return false;
    }
  }

  /// 계약해지 요청 취소 (관리자용)
  Future<bool> cancelTerminationRequest(String applicationId) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'terminationRequestedAt': FieldValue.delete(),
        'terminationReason': FieldValue.delete(),
        'terminationRequestedByUid': FieldValue.delete(),
        'terminationStatus': FieldValue.delete(),
        'terminationRespondedAt': FieldValue.delete(),
        'terminationRejectReason': FieldValue.delete(),
      });

      print('✅ 계약해지 요청 취소 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 계약해지 요청 취소 실패: $e');
      return false;
    }
  }

  /// 계약해지 승인 (근무자용)
  Future<bool> approveTermination(String applicationId) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'terminationStatus': 'APPROVED',
        'terminationRespondedAt': Timestamp.fromDate(DateTime.now()),
        'resignStatus': 'APPROVED',  // 퇴사 상태도 함께 업데이트
        'actualResignDate': Timestamp.fromDate(DateTime.now()),
      });

      print('✅ 계약해지 승인 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 계약해지 승인 실패: $e');
      return false;
    }
  }

  /// 계약해지 거절 (근무자용)
  Future<bool> rejectTermination({
    required String applicationId,
    String? rejectReason,
  }) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'terminationStatus': 'REJECTED',
        'terminationRespondedAt': Timestamp.fromDate(DateTime.now()),
        'terminationRejectReason': rejectReason,
      });

      print('✅ 계약해지 거절 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 계약해지 거절 실패: $e');
      return false;
    }
  }

  /// 계약해지 자동 승인 처리 (3일 경과 시)
  Future<bool> autoApproveTermination(String applicationId) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'terminationStatus': 'AUTO_APPROVED',
        'terminationRespondedAt': Timestamp.fromDate(DateTime.now()),
        'resignStatus': 'AUTO_APPROVED',
        'actualResignDate': Timestamp.fromDate(DateTime.now()),
      });

      print('✅ 계약해지 자동 승인 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 계약해지 자동 승인 실패: $e');
      return false;
    }
  }

  /// 계약해지 대기 중인 지원서 조회 (3일 경과 체크용)
  Future<List<ApplicationModel>> getPendingTerminations() async {
    try {
      final snapshot = await _firestore
          .collection('applications')
          .where('terminationStatus', isEqualTo: 'PENDING')
          .get();

      return snapshot.docs
          .map((doc) => ApplicationModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('❌ 계약해지 대기 목록 조회 실패: $e');
      return [];
    }
  }

  /// 퇴사 자동 승인 처리 (Cloud Function에서 호출)
  Future<bool> autoApproveResignation(String applicationId) async {
    try {
      final appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();

      if (!appDoc.exists) return false;

      final appData = appDoc.data() as Map<String, dynamic>;
      
      // 이미 처리된 경우 스킵
      if (appData['resignStatus'] != 'PENDING') return false;

      final resignDate = (appData['resignRequestDate'] as Timestamp).toDate();

      await _firestore.collection('applications').doc(applicationId).update({
        'resignStatus': 'AUTO_APPROVED',
        'resignApprovedAt': Timestamp.fromDate(DateTime.now()),
        'resignApprovedBy': 'SYSTEM',
        'actualResignDate': Timestamp.fromDate(resignDate),
        'workEndDate': Timestamp.fromDate(resignDate),
      });

      print('✅ 퇴사 자동 승인 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 퇴사 자동 승인 실패: $e');
      return false;
    }
  }
  /// 퇴사 요청 목록 조회 (관리자용)
  Future<List<ApplicationModel>> getResignRequests(String businessId) async {
    try {
      final snapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'CONFIRMED')
          .where('resignStatus', isEqualTo: 'PENDING')
          .get();

      final applications = snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .where((app) => app.isLongTermApplication) // 장기 근무만
          .toList();

      print('✅ 퇴사 요청 ${applications.length}건 조회');
      return applications;
    } catch (e) {
      print('❌ 퇴사 요청 조회 실패: $e');
      return [];
    }
  }
  /// 장기 근무 지원자 조회 (사업장별)
  Future<List<ApplicationModel>> getLongTermApplicationsByBusiness(
    String businessId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'CONFIRMED')
          .get();

      final applications = snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .where((app) => app.isLongTermApplication)
          .toList();

      print('✅ 장기 근무 지원자 조회: ${applications.length}명');
      return applications;
    } catch (e) {
      print('❌ 장기 근무 지원자 조회 실패: $e');
      return [];
    }
  }
}