part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// TO 그룹 관리 (TO Group Management)
// ═══════════════════════════════════════════════════════════

extension TOGroupFirestore on FirestoreService {
  // ═══════════════════════════════════════════════════════════
  // TO 그룹 관리 (TO Group Management)
  // ═══════════════════════════════════════════════════════════

  /// 그룹 ID 생성
  String generateGroupId() {
    return 'group_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// 그룹별 TO 조회
  Future<List<TOModel>> getTOsByGroup(String groupId) async {
    try {
      print('🔍 [FirestoreService] 그룹 TO 조회 시작...');
      print('   그룹 ID: $groupId');

      final snapshot = await _firestore
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .orderBy('date', descending: false)
          .get();

      final toList = snapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();

      print('✅ [FirestoreService] 그룹 TO 조회 완료: ${toList.length}개');
      return toList;
    } catch (e) {
      print('❌ [FirestoreService] 그룹 TO 조회 실패: $e');
      return [];
    }
  }

  /// 그룹 TO 일괄 생성 (날짜 범위)
  Future<bool> createTOGroup({
    required String businessId,
    required String businessName,
    required String groupName,
    required String title,
    required DateTime startDate,
    required DateTime endDate,
    required List<Map<String, dynamic>> workDetails,
    required DateTime applicationDeadline,
    String? description,
    required String creatorUID,
  }) async {
    try {
      print('🔨 [FirestoreService] 그룹 TO 생성 시작...');
      print('   기간: ${startDate.toString().split(' ')[0]} ~ ${endDate.toString().split(' ')[0]}');
      
      final groupId = generateGroupId();
      print('   생성된 그룹 ID: $groupId');
      
      // 시작일~종료일 사이의 모든 날짜 계산
      List<DateTime> dates = [];
      DateTime currentDate = startDate;
      
      while (currentDate.isBefore(endDate.add(Duration(days: 1)))) {
        dates.add(DateTime(currentDate.year, currentDate.month, currentDate.day));
        currentDate = currentDate.add(Duration(days: 1));
      }
      
      print('   생성할 TO 개수: ${dates.length}개');
      
      // 총 필요 인원 계산
      int totalRequired = 0;
      for (var work in workDetails) {
        totalRequired += (work['requiredCount'] as int?) ?? 0;
      }
      // ✅ 사업장 주소 정보 조회
      String? businessAddress;
      String? businessCity;
      String? businessDistrict;
      try {
        final business = await getBusinessById(businessId);
        if (business != null) {
          businessAddress = business.address;
          businessCity = business.city;
          businessDistrict = business.district;
        }
      } catch (e) {
        print('⚠️ 사업장 주소 조회 실패: $e');
      }
      // ✅ 급여 정보 계산
      final wages = workDetails.map((d) => d['wage'] as int).toList();
      final minWage = wages.isNotEmpty ? wages.reduce((a, b) => a < b ? a : b) : 0;
      final maxWage = wages.isNotEmpty ? wages.reduce((a, b) => a > b ? a : b) : 0;
      final wageType = workDetails.isNotEmpty ? (workDetails.first['wageType'] ?? 'hourly') : 'hourly';
      final workDetailCount = workDetails.length;

      // 각 날짜별 TO 생성
      for (int i = 0; i < dates.length; i++) {
        final toData = {
          'businessId': businessId,
          'businessName': businessName,
          'businessAddress': businessAddress,
          'businessCity': businessCity,
          'businessDistrict': businessDistrict,
          'groupId': groupId,
          'groupName': groupName,
          'startDate': Timestamp.fromDate(startDate),
          'endDate': Timestamp.fromDate(endDate),
          'isGroupMaster': i == 0,
          'title': title,
          'date': Timestamp.fromDate(dates[i]),
          'startTime': workDetails.isNotEmpty ? workDetails[0]['startTime'] ?? '' : '',
          'endTime': workDetails.isNotEmpty ? workDetails[0]['endTime'] ?? '' : '',
          'applicationDeadline': Timestamp.fromDate(applicationDeadline),
          'totalRequired': totalRequired,
          'totalConfirmed': 0,
          // ✅ 급여 정보
          'minWage': minWage,
          'maxWage': maxWage,
          'wageType': wageType,
          'workDetailCount': workDetailCount,
          'description': description,
          'creatorUID': creatorUID,
          'createdAt': FieldValue.serverTimestamp(),
          // ✅ Phase 4: 상태 필드
          'status': 'ACTIVE',
          'statusUpdatedAt': FieldValue.serverTimestamp(),
        };
        
        // TO 문서 생성
        final toDoc = await _firestore.collection('tos').add(toData);
        print('   ✅ ${dates[i].toString().split(' ')[0]} TO 생성 완료 (ID: ${toDoc.id})');
        
        // WorkDetails 하위 컬렉션 생성
        for (int j = 0; j < workDetails.length; j++) {
          await _firestore
              .collection('tos')
              .doc(toDoc.id)
              .collection('workDetails')
              .add({
            'workType': workDetails[j]['workType'],
            'workTypeIcon': workDetails[j]['workTypeIcon'],
            'workTypeColor': workDetails[j]['workTypeColor'],
            'wage': workDetails[j]['wage'],
            'wageType': workDetails[j]['wageType'] ?? 'hourly',
            'requiredCount': workDetails[j]['requiredCount'],
            'currentCount': 0,
            'pendingCount': 0, 
            'startTime': workDetails[j]['startTime'],
            'endTime': workDetails[j]['endTime'],
            'order': j,
          });
        }
      }
      
      print('✅ [FirestoreService] 그룹 TO 생성 완료: ${dates.length}개');
      //ToastHelper.showSuccess('${dates.length}개의 TO가 생성되었습니다!');
      return true;
      
    } catch (e) {
      print('❌ [FirestoreService] 그룹 TO 생성 실패: $e');
      ToastHelper.showError('TO 생성 중 오류가 발생했습니다.');
      return false;
    }
  }
  /// TO를 다른 그룹에 재연결
  Future<bool> reconnectToGroup({
    required String toId,
    required String targetGroupId,
  }) async {
    try {
      // 대상 그룹의 정보 가져오기
      final targetGroupTOs = await getTOsByGroup(targetGroupId);
      if (targetGroupTOs.isEmpty) {
        ToastHelper.showError('대상 그룹을 찾을 수 없습니다.');
        return false;
      }
      
      final targetMasterTO = targetGroupTOs.firstWhere((to) => to.isGroupMaster);
      
      // TO를 새 그룹에 연결
      await _firestore.collection('tos').doc(toId).update({
        'groupId': targetGroupId,
        'groupName': targetMasterTO.groupName,
        'isGroupMaster': false,
        'startDate': targetMasterTO.startDate,
        'endDate': targetMasterTO.endDate,
      });
      
      // 대상 그룹의 날짜 범위 재계산
      await _updateGroupDateRange(targetGroupId);
      
      // ✅ 대상 그룹 마스터 통계 동기화
      await _updateGroupMasterStats(targetGroupId);
      
      print('✅ TO 그룹 재연결 완료: $toId → $targetGroupId');
      ToastHelper.showSuccess('그룹에 연결되었습니다.');
      return true;
    } catch (e) {
      print('❌ TO 그룹 재연결 실패: $e');
      ToastHelper.showError('그룹 연결에 실패했습니다.');
      return false;
    }
  }
  /// 단일 TO로 새 그룹 생성
  Future<bool> createNewGroupFromTO({
    required String toId,
    required String groupName,
  }) async {
    try {
      final to = await getTO(toId);
      if (to == null) {
        ToastHelper.showError('TO를 찾을 수 없습니다.');
        return false;
      }
      
      // 새 그룹 ID 생성
      final groupId = 'group_${DateTime.now().millisecondsSinceEpoch}';
      
      // TO를 그룹으로 변경
      await _firestore.collection('tos').doc(toId).update({
        'groupId': groupId,
        'groupName': groupName,
        'isGroupMaster': true,  // 대표 TO로 지정
        'startDate': Timestamp.fromDate(to.date),
        'endDate': Timestamp.fromDate(to.date),
      });
      
      // ✅ 그룹 마스터 통계 초기화
      await _updateGroupMasterStats(groupId);
      
      print('✅ 새 그룹 생성 완료');
      print('   그룹 ID: $groupId');
      print('   그룹명: $groupName');
      print('   대표 TO: $toId');
      
      ToastHelper.showSuccess('새 그룹이 생성되었습니다.');
      return true;
    } catch (e) {
      print('❌ 새 그룹 생성 실패: $e');
      ToastHelper.showError('그룹 생성에 실패했습니다.');
      return false;
    }
  }

  /// 기존 그룹에 TO 추가
  Future<bool> createTOGroupWithExistingGroup({
    required String businessId,
    required String businessName,
    required String groupId,
    required String groupName,
    required String title,
    required DateTime startDate,
    required DateTime endDate,
    required List<Map<String, dynamic>> workDetails,
    required DateTime applicationDeadline,
    String? description,
    required String creatorUID,
  }) async {
    try {
      print('🔧 [FirestoreService] 기존 그룹에 TO 추가 시작...');
      print('   그룹 ID: $groupId');
      print('   그룹명: $groupName');
      print('   기간: ${startDate.month}/${startDate.day} ~ ${endDate.month}/${endDate.day}');

      final batch = _firestore.batch();
      
      // 날짜 범위 내 모든 날짜 생성
      List<DateTime> dates = [];
      DateTime currentDate = startDate;
      
      while (currentDate.isBefore(endDate) || currentDate.isAtSameMomentAs(endDate)) {
        dates.add(currentDate);
        currentDate = currentDate.add(const Duration(days: 1));
      }

      print('   생성할 TO 개수: ${dates.length}일');

      // 전체 필요 인원 계산
      int totalRequired = 0;
      for (var detail in workDetails) {
        totalRequired += (detail['requiredCount'] as int);
      }
      // ✅ 급여 정보 계산
      final wages = workDetails.map((d) => d['wage'] as int).toList();
      final minWage = wages.isNotEmpty ? wages.reduce((a, b) => a < b ? a : b) : 0;
      final maxWage = wages.isNotEmpty ? wages.reduce((a, b) => a > b ? a : b) : 0;
      final wageType = workDetails.isNotEmpty ? (workDetails.first['wageType'] ?? 'hourly') : 'hourly';
      final workDetailCount = workDetails.length;

      // 각 날짜별 TO 생성
      for (int i = 0; i < dates.length; i++) {
        final date = dates[i];

        // TO 기본 정보
        final toData = {
          'businessId': businessId,
          'businessName': businessName,
          'groupId': groupId,
          'groupName': groupName,
          'startDate': Timestamp.fromDate(startDate),
          'endDate': Timestamp.fromDate(endDate),
          'isGroupMaster': false,
          'title': title,
          'date': Timestamp.fromDate(date),
          'applicationDeadline': Timestamp.fromDate(applicationDeadline),
          'totalRequired': totalRequired,
          'totalConfirmed': 0,
          // ✅ 급여 정보
          'minWage': minWage,
          'maxWage': maxWage,
          'wageType': wageType,
          'workDetailCount': workDetailCount,
          'description': description ?? '',
          'creatorUID': creatorUID,
          'createdAt': FieldValue.serverTimestamp(),
          // ✅ Phase 4: 상태 필드
          'status': 'ACTIVE',
          'statusUpdatedAt': FieldValue.serverTimestamp(),
        };

        final toDoc = _firestore.collection('tos').doc();
        batch.set(toDoc, toData);

        // WorkDetails 추가
        for (int j = 0; j < workDetails.length; j++) {
          final detail = workDetails[j];
          final workDetailDoc = toDoc.collection('workDetails').doc();
          
          batch.set(workDetailDoc, {
            'workType': detail['workType'],
            'workTypeIcon': detail['workTypeIcon'],
            'workTypeColor': detail['workTypeColor'],
            'wage': detail['wage'],
            'wageType': detail['wageType'] ?? 'hourly',
            'requiredCount': detail['requiredCount'],
            'currentCount': 0,
            'pendingCount': 0, 
            'startTime': detail['startTime'],
            'endTime': detail['endTime'],
            'order': j,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        print('  ✅ ${date.month}/${date.day} TO 준비 완료');
      }
      // 대표 TO의 날짜 범위 업데이트
      final masterTOSnapshot = await _firestore
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .where('isGroupMaster', isEqualTo: true)
          .limit(1)
          .get();

      if (masterTOSnapshot.docs.isNotEmpty) {
        final masterTODoc = masterTOSnapshot.docs.first;
        final currentStartDate = (masterTODoc.data()['startDate'] as Timestamp).toDate();
        final currentEndDate = (masterTODoc.data()['endDate'] as Timestamp).toDate();
        
        // 새로운 날짜 범위 계산
        final newStartDate = startDate.isBefore(currentStartDate) ? startDate : currentStartDate;
        final newEndDate = endDate.isAfter(currentEndDate) ? endDate : currentEndDate;
        
        // 대표 TO 업데이트
        batch.update(masterTODoc.reference, {
          'startDate': Timestamp.fromDate(newStartDate),
          'endDate': Timestamp.fromDate(newEndDate),
        });
        
        print('✅ 대표 TO 날짜 범위 업데이트: ${newStartDate.month}/${newStartDate.day} ~ ${newEndDate.month}/${newEndDate.day}');
      }

      await batch.commit();
      
      print('✅ [FirestoreService] 기존 그룹에 TO 추가 완료!');
      print('   추가된 TO: ${dates.length}개');
      print('   그룹 ID: $groupId');
      
      // ✅ 그룹 마스터 통계 동기화
      await _updateGroupMasterStats(groupId);
      
      ToastHelper.showSuccess('${dates.length}개 TO가 그룹에 추가되었습니다!');
      return true;
      
    } catch (e) {
      print('❌ [FirestoreService] 기존 그룹 TO 추가 실패: $e');
      ToastHelper.showError('TO 추가 중 오류가 발생했습니다.');
      return false;
    }
  }

  /// TO의 그룹 정보 업데이트
  Future<bool> updateTOGroup({
    required String toId,
    required String groupId,
    required String groupName,
  }) async {
    try {
      await _firestore.collection('tos').doc(toId).update({
        'groupId': groupId,
        'groupName': groupName,
      });
      
      print('✅ [FirestoreService] TO 그룹 정보 업데이트 완료');
      print('   TO ID: $toId');
      print('   Group ID: $groupId');
      print('   Group Name: $groupName');
      
      return true;
    } catch (e) {
      print('❌ [FirestoreService] TO 그룹 정보 업데이트 실패: $e');
      return false;
    }
  }

  /// 그룹명 일괄 수정
  Future<bool> updateGroupName(String groupId, String newGroupName) async {
    try {
      print('🔧 [FirestoreService] 그룹명 수정 시작...');
      print('   그룹 ID: $groupId');
      print('   새 그룹명: $newGroupName');

      // 같은 groupId를 가진 모든 TO 조회
      final snapshot = await _firestore
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .get();

      if (snapshot.docs.isEmpty) {
        ToastHelper.showError('그룹을 찾을 수 없습니다.');
        return false;
      }

      // Batch 업데이트
      final batch = _firestore.batch();
      
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {'groupName': newGroupName});
      }

      await batch.commit();

      print('✅ [FirestoreService] 그룹명 수정 완료: ${snapshot.docs.length}개 TO 업데이트');
      ToastHelper.showSuccess('그룹명이 수정되었습니다.');
      return true;
    } catch (e) {
      print('❌ [FirestoreService] 그룹명 수정 실패: $e');
      ToastHelper.showError('그룹명 수정에 실패했습니다.');
      return false;
    }
  }

  /// 그룹 전체 삭제
  Future<bool> deleteGroupTOs(String groupId) async {
    try {
      final groupTOs = await getTOsByGroup(groupId);
      
      if (groupTOs.isEmpty) {
        ToastHelper.showError('그룹을 찾을 수 없습니다.');
        return false;
      }
      
      // 모든 TO 삭제
      for (var to in groupTOs) {
        await deleteTO(to.id);
      }
      
      print('✅ 그룹 전체 삭제 완료: $groupId');
      ToastHelper.showSuccess('그룹이 삭제되었습니다.');
      return true;
    } catch (e) {
      print('❌ 그룹 삭제 실패: $e');
      ToastHelper.showError('그룹 삭제에 실패했습니다.');
      return false;
    }
  }

  /// 특정 날짜 TO만 삭제 (그룹 내 단일 삭제)
  Future<bool> deleteSingleTOFromGroup(String toId, String? groupId) async {
    try {
      print('🗑️ [FirestoreService] 단일 TO 삭제 시작...');
      print('   TO ID: $toId');

      // 1. 삭제할 TO 조회
      final toDoc = await _firestore.collection('tos').doc(toId).get();
      if (!toDoc.exists) {
        ToastHelper.showError('TO를 찾을 수 없습니다.');
        return false;
      }

      final to = TOModel.fromMap(toDoc.data()!, toDoc.id);
      
      // 2. WorkDetails 삭제
      final workDetailsSnapshot = await _firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .get();
      
      final batch = _firestore.batch();
      for (var doc in workDetailsSnapshot.docs) {
        batch.delete(doc.reference);
      }
      
      // 3. 지원서 삭제
      final applicationsSnapshot = await _firestore
          .collection('applications')
          .where('toId', isEqualTo: toId)
          .get();
      
      for (var doc in applicationsSnapshot.docs) {
        batch.delete(doc.reference);
      }
      
      // 4. TO 문서 삭제
      batch.delete(_firestore.collection('tos').doc(toId));
      
      await batch.commit();
      
      // 5. 대표 TO였다면 다음 TO를 대표로 변경
      if (to.isGroupMaster && groupId != null) {
        final groupTOs = await getTOsByGroup(groupId);
        if (groupTOs.isNotEmpty) {
          // 남은 TO 중 첫 번째를 대표로
          await _firestore.collection('tos').doc(groupTOs[0].id).update({
            'isGroupMaster': true,
          });
          print('   ✅ 새 대표 TO 지정: ${groupTOs[0].id}');
        }
      }
      
      // ✅ 그룹 마스터 통계 동기화 (그룹이 남아있는 경우만)
      if (groupId != null) {
        final remainingTOs = await getTOsByGroup(groupId);
        if (remainingTOs.isNotEmpty) {
          await _updateGroupMasterStats(groupId);
        }
      }
      
      print('✅ [FirestoreService] TO 삭제 완료');
      ToastHelper.showSuccess('TO가 삭제되었습니다.');
      return true;
      
    } catch (e) {
      print('❌ [FirestoreService] TO 삭제 실패: $e');
      ToastHelper.showError('삭제 중 오류가 발생했습니다.');
      return false;
    }
  }

  /// TO를 그룹에서 해제하여 독립 TO로 변경
  Future<bool> removeFromGroup(String toId) async {
    try {
      final to = await getTO(toId);
      if (to == null || to.groupId == null) {
        ToastHelper.showError('그룹 TO가 아닙니다.');
        return false;
      }
      
      final groupId = to.groupId!;
      
      // 1. TO를 독립 TO로 변경
      await _firestore.collection('tos').doc(toId).update({
        'groupId': FieldValue.delete(),
        'groupName': FieldValue.delete(),
        'isGroupMaster': false,
        'startDate': FieldValue.delete(),
        'endDate': FieldValue.delete(),
      });
      
      // 1. TO를 독립 TO로 변경
      await _firestore.collection('tos').doc(toId).update({
        'groupId': FieldValue.delete(),
        'groupName': FieldValue.delete(),
        'isGroupMaster': false,
        'startDate': FieldValue.delete(),
        'endDate': FieldValue.delete(),
      });

      // 2. 남은 그룹 TO 확인 (최신 데이터 다시 조회)
      final remainingSnapshot = await _firestore
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .get();

      final remainingTOs = remainingSnapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();
      if (remainingTOs.length == 1) {
        // 마지막 TO도 독립 TO로 변경
        final lastTO = remainingTOs.first;
        await _firestore.collection('tos').doc(lastTO.id).update({
          'groupId': FieldValue.delete(),
          'groupName': FieldValue.delete(),
          'isGroupMaster': false,
          'startDate': FieldValue.delete(),
          'endDate': FieldValue.delete(),
        });
        print('✅ 마지막 TO도 독립 TO로 변경');
        clearCache(toId: lastTO.id);
      } else if (remainingTOs.isNotEmpty) {
        // 해제된 TO가 대표였다면 다음 TO를 대표로 지정
        if (to.isGroupMaster) {
          final newMasterTO = remainingTOs.first;
          await _firestore.collection('tos').doc(newMasterTO.id).update({
            'isGroupMaster': true,
          });
          print('✅ 새 대표 TO 지정: ${newMasterTO.id}');
        }
        
        // 그룹 날짜 범위 재계산
        await _updateGroupDateRange(groupId);
      }
      
      clearCache(toId: toId);
      
      // ✅ 그룹 마스터 통계 동기화 (그룹이 남아있는 경우만)
      if (remainingTOs.length > 1) {
        await _updateGroupMasterStats(groupId);
      }
      
      print('✅ TO 그룹 해제 완료: $toId');
      ToastHelper.showSuccess('그룹에서 해제되었습니다.');
      return true;
    } catch (e) {
      print('❌ TO 그룹 해제 실패: $e');
      ToastHelper.showError('그룹 해제에 실패했습니다.');
      return false;
    }
  }

  /// 그룹 날짜 범위 재계산 (내부 헬퍼 함수)
  Future<void> _updateGroupDateRange(String groupId) async {
    try {
      final groupTOs = await getTOsByGroup(groupId);
      if (groupTOs.isEmpty) return;
      
      // 최소/최대 날짜 계산
      DateTime minDate = groupTOs.first.date;
      DateTime maxDate = groupTOs.first.date;
      
      for (var to in groupTOs) {
        if (to.date.isBefore(minDate)) minDate = to.date;
        if (to.date.isAfter(maxDate)) maxDate = to.date;
      }
      
      // 대표 TO 업데이트
      final masterTO = groupTOs.firstWhere((to) => to.isGroupMaster);
      await _firestore.collection('tos').doc(masterTO.id).update({
        'startDate': Timestamp.fromDate(minDate),
        'endDate': Timestamp.fromDate(maxDate),
      });
      
      print('✅ 그룹 날짜 범위 업데이트: $minDate ~ $maxDate');
    } catch (e) {
      print('❌ 그룹 날짜 범위 업데이트 실패: $e');
    }
  }

  /// 그룹 TO의 전체 시간 범위 계산 (최적화 - 병렬 처리)
  Future<Map<String, String>> calculateGroupTimeRange(String groupId, {bool forceRefresh = false}) async {
    try {
      print('🕐 [FirestoreService] 그룹 시간 범위 계산 시작...');
      print('   그룹 ID: $groupId');

      // 1. 그룹의 모든 TO 조회
      final snapshot = await _firestore
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .get();

      if (snapshot.docs.isEmpty) {
        return {'minStart': '~', 'maxEnd': '~'};
      }

      final toIds = snapshot.docs.map((doc) => doc.id).toList();

      // 2. ✅ 병렬로 모든 WorkDetails 조회
      final workDetailsFutures = toIds.map((toId) => getWorkDetails(toId, forceRefresh: forceRefresh)).toList();
      final allWorkDetailsLists = await Future.wait(workDetailsFutures);

      String? minStart;
      String? maxEnd;

      // 3. 시간 범위 계산
      for (var workDetailsList in allWorkDetailsLists) {
        for (var work in workDetailsList) {
          // 최소 시작 시간
          if (minStart == null || work.startTime.compareTo(minStart) < 0) {
            minStart = work.startTime;
          }
          
          // 최대 종료 시간
          if (maxEnd == null || work.endTime.compareTo(maxEnd) > 0) {
            maxEnd = work.endTime;
          }
        }
      }

      print('✅ [FirestoreService] 시간 범위 계산 완료');
      print('   최소 시작: $minStart, 최대 종료: $maxEnd');

      return {
        'minStart': minStart ?? '~',
        'maxEnd': maxEnd ?? '~',
      };
    } catch (e) {
      print('❌ [FirestoreService] 시간 범위 계산 실패: $e');
      return {'minStart': '~', 'maxEnd': '~'};
    }
  }
  // ═══════════════════════════════════════════════════════════
  // ✨ 그룹 마스터 통계 동기화 (Group Master Stats Sync)
  // ═══════════════════════════════════════════════════════════

  /// 그룹 마스터 TO의 통계 업데이트
  /// - 그룹 내 모든 TO의 통계를 합산하여 마스터에 저장
  /// - 지원 확정/거절/취소, TO 생성/삭제 시 호출
  Future<bool> _updateGroupMasterStats(String groupId) async {
    try {
      print('📊 [Sync] 그룹 마스터 통계 업데이트: $groupId');
      
      // 1. 그룹의 모든 TO 조회
      final groupTOs = await getTOsByGroup(groupId);
      if (groupTOs.isEmpty) {
        print('   ⚠️ 그룹 TO가 없습니다');
        return false;
      }
      
      // 2. 마스터 TO 찾기
      final masterTO = groupTOs.firstWhere(
        (to) => to.isGroupMaster,
        orElse: () => groupTOs.first,
      );
      
      // 3. 그룹 전체 통계 합산
      int groupTotalRequired = 0;
      int groupTotalConfirmed = 0;
      int groupTotalPending = 0;
      
      // ✅ 그룹 전체 급여 정보 (최대/최소)
      int? groupMinWage;
      int? groupMaxWage;
      
      for (var to in groupTOs) {
        groupTotalRequired += to.totalRequired;
        groupTotalConfirmed += to.totalConfirmed;
        groupTotalPending += to.totalPending;
        
        // 급여 정보 비교
        if (to.minWage != null) {
          if (groupMinWage == null || to.minWage! < groupMinWage) {
            groupMinWage = to.minWage;
          }
        }
        if (to.maxWage != null) {
          if (groupMaxWage == null || to.maxWage! > groupMaxWage) {
            groupMaxWage = to.maxWage;
          }
        }
      }
      
      // 4. 마스터 TO 업데이트
      await _firestore.collection('tos').doc(masterTO.id).update({
        'groupTotalRequired': groupTotalRequired,
        'groupTotalConfirmed': groupTotalConfirmed,
        'groupTotalPending': groupTotalPending,
        // ✅ 그룹 전체 급여 정보
        'minWage': groupMinWage,
        'maxWage': groupMaxWage,
        // ✅ 그룹 실제 날짜 개수
        'groupActualDaysCount': groupTOs.length,
        'groupStatsUpdatedAt': FieldValue.serverTimestamp(),
      });
      
      print('   ✅ 마스터 통계 업데이트 완료: 필요 $groupTotalRequired, 확정 $groupTotalConfirmed, 대기 $groupTotalPending');
      return true;
    } catch (e) {
      print('❌ [Sync] 그룹 마스터 통계 업데이트 실패: $e');
      return false;
    }
  }
  /// 그룹 마스터 TO의 status 재계산
  /// - 그룹 내 활성 TO가 1개라도 있으면 → ACTIVE
  /// - 그룹 내 모든 TO가 마감이면 → CLOSED
  Future<bool> _updateGroupMasterStatus(String groupId) async {
    try {
      print('📊 [Sync] 그룹 마스터 status 재계산: $groupId');
      
      // 1. 그룹의 모든 TO 조회
      final snapshot = await _firestore
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .get();
      
      if (snapshot.docs.isEmpty) return false;
      
      // 2. 마스터 TO 찾기
      DocumentSnapshot? masterDoc;
      bool hasActiveTO = false;
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        
        if (data['isGroupMaster'] == true) {
          masterDoc = doc;
        }
        
        // 마스터가 아닌 TO 중 활성 상태 체크
        if (data['isGroupMaster'] != true) {
          final status = data['status'] ?? 'ACTIVE';
          if (status == 'ACTIVE') {
            hasActiveTO = true;
          }
        }
      }
      
      if (masterDoc == null) {
        print('   ⚠️ 마스터 TO를 찾을 수 없음');
        return false;
      }
      
      // 3. 마스터 status 결정
      final masterData = masterDoc.data() as Map<String, dynamic>;
      final isManualClosed = masterData['isManualClosed'] ?? false;
      
      String newStatus;
      if (isManualClosed) {
        // 마스터가 수동 마감이면 CLOSED 유지
        newStatus = 'CLOSED';
      } else if (hasActiveTO) {
        // 활성 TO가 있으면 ACTIVE
        newStatus = 'ACTIVE';
      } else {
        // 모든 TO가 마감이면 CLOSED
        newStatus = 'CLOSED';
      }
      
      // 4. 마스터 status 업데이트
      await masterDoc.reference.update({
        'status': newStatus,
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });
      
      print('   ✅ 마스터 status 업데이트: $newStatus (활성 TO: $hasActiveTO)');
      return true;
    } catch (e) {
      print('❌ [Sync] 그룹 마스터 status 업데이트 실패: $e');
      return false;
    }
  }

  /// 공개 메서드: TO의 그룹 마스터 통계 동기화
  /// - toId로 해당 TO의 groupId를 찾아서 마스터 통계 업데이트
  Future<bool> syncGroupMasterStats(String toId) async {
    try {
      final to = await getTO(toId);
      if (to == null) return false;
      
      // 그룹 TO가 아니면 스킵
      if (to.groupId == null) {
        print('   ℹ️ 단일 TO - 그룹 동기화 스킵');
        return true;
      }
      
      return await _updateGroupMasterStats(to.groupId!);
    } catch (e) {
      print('❌ syncGroupMasterStats 실패: $e');
      return false;
    }
  }

  /// 그룹 마스터 통계 전체 재계산 (마이그레이션/수동 보정용)
  Future<int> migrateAllGroupMasterStats() async {
    try {
      print('🔄 [Migration] 전체 그룹 마스터 통계 마이그레이션 시작...');
      
      // 모든 그룹 마스터 TO 조회
      final snapshot = await _firestore
          .collection('tos')
          .where('isGroupMaster', isEqualTo: true)
          .get();
      
      int successCount = 0;
      final groupIds = <String>{};
      
      for (var doc in snapshot.docs) {
        final groupId = doc.data()['groupId'] as String?;
        if (groupId != null && !groupIds.contains(groupId)) {
          groupIds.add(groupId);
          final success = await _updateGroupMasterStats(groupId);
          if (success) successCount++;
        }
      }
      
      print('✅ [Migration] 완료: $successCount/${groupIds.length}개 그룹');
      return successCount;
    } catch (e) {
      print('❌ [Migration] 실패: $e');
      return 0;
    }
  }
  
}