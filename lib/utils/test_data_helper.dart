import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';
import '../services/firestore_service.dart';

class TestDataHelper {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirestoreService _firestoreService = FirestoreService();
  static final Random _random = Random();

  // 더미 이름 풀
  static final List<String> _firstNames = [
    '김', '이', '박', '최', '정', '강', '조', '윤', '장', '임',
    '한', '오', '서', '신', '권', '황', '안', '송', '류', '전'
  ];

  static final List<String> _lastNames = [
    '민준', '서준', '예준', '도윤', '시우', '주원', '하준', '지호', '지후', '준서',
    '서연', '서윤', '지우', '서현', '민서', '하은', '윤서', '지민', '지유', '채원'
  ];

  /// 더미 지원자 생성
  static Future<List<String>> createDummyApplicants(int count) async {
    print('👥 더미 지원자 $count명 생성 시작...');
    
    List<String> uids = [];

    for (int i = 0; i < count; i++) {
      final firstName = _firstNames[_random.nextInt(_firstNames.length)];
      final lastName = _lastNames[_random.nextInt(_lastNames.length)];
      final name = '$firstName$lastName';
      
      final uid = 'dummy_user_${DateTime.now().millisecondsSinceEpoch}_$i';
      final phone = '010-${_random.nextInt(9000) + 1000}-${_random.nextInt(9000) + 1000}';
      final email = 'dummy$i@test.com';

      await _firestore.collection('users').doc(uid).set({
        'uid': uid,
        'name': name,
        'email': email,
        'phone': phone,
        'role': 'user',
        'createdAt': FieldValue.serverTimestamp(),
        'isDummy': true,  // ✅ 더미 데이터 표시
      });

      uids.add(uid);
      print('✅ 지원자 생성: $name ($phone)');
    }

    print('🎉 더미 지원자 $count명 생성 완료!');
    return uids;
  }

  /// 특정 TO에 더미 지원서 생성
  static Future<void> createDummyApplications({
    required String toId,
    required List<String> workTypes,
    required int pendingCount,
    required int confirmedCount,
  }) async {
    print('📝 TO $toId에 지원서 생성 중...');
    print('   - 대기: $pendingCount명');
    print('   - 확정: $confirmedCount명');

    // 1. 더미 지원자 생성
    final totalCount = pendingCount + confirmedCount;
    final uids = await createDummyApplicants(totalCount);

    // 2. TO 정보 조회
    final toDoc = await _firestore.collection('tos').doc(toId).get();
    if (!toDoc.exists) {
      print('❌ TO를 찾을 수 없습니다: $toId');
      return;
    }

    final toData = toDoc.data()!;
    final businessId = toData['businessId'];
    final businessName = toData['businessName'];
    final toTitle = toData['title'];
    final date = (toData['date'] as Timestamp).toDate();

    // 3. WorkDetails 조회
    final workDetailsSnapshot = await _firestore
        .collection('tos')
        .doc(toId)
        .collection('workDetails')
        .get();

    if (workDetailsSnapshot.docs.isEmpty) {
      print('❌ WorkDetails가 없습니다');
      return;
    }

    final workDetails = workDetailsSnapshot.docs;
    final now = Timestamp.now(); // ✅ 현재 시각 미리 생성

    // 4. 지원서 생성
    int uidIndex = 0;
    List<String> createdAppIds = []; // ✅ 생성된 ID 추적

    // 대기 중인 지원서
    for (int i = 0; i < pendingCount && uidIndex < uids.length; i++) {
      final workDetail = workDetails[_random.nextInt(workDetails.length)];
      final workData = workDetail.data();

      final appRef = await _firestore.collection('applications').add({
        'uid': uids[uidIndex],
        'businessId': businessId,
        'businessName': businessName,
        'toTitle': toTitle,
        'selectedWorkType': workData['workType'],
        'wage': workData['wage'],
        'workDate': Timestamp.fromDate(date),
        'startTime': workData['startTime'],
        'endTime': workData['endTime'],
        'status': 'PENDING',
        'appliedAt': now,
        'isDummy': true,
      });

      createdAppIds.add(appRef.id);
      print('✅ 대기 지원서 생성: ${uids[uidIndex]} → ${workData['workType']}');
      uidIndex++;
    }

    // 확정된 지원서
    for (int i = 0; i < confirmedCount && uidIndex < uids.length; i++) {
      final workDetail = workDetails[_random.nextInt(workDetails.length)];
      final workData = workDetail.data();
      final workDetailId = workDetail.id;

      final appRef = await _firestore.collection('applications').add({
        'uid': uids[uidIndex],
        'businessId': businessId,
        'businessName': businessName,
        'toTitle': toTitle,
        'selectedWorkType': workData['workType'],
        'wage': workData['wage'],
        'workDate': Timestamp.fromDate(date),
        'startTime': workData['startTime'],
        'endTime': workData['endTime'],
        'status': 'CONFIRMED',
        'appliedAt': now,
        'confirmedAt': now,
        'confirmedBy': 'admin_test',
        'isDummy': true,
      });

      createdAppIds.add(appRef.id);

      // ✅ confirmed_applications 서브컬렉션에도 추가
      await _firestore
          .collection('tos')
          .doc(toId)
          .collection('confirmed_applications')
          .doc(appRef.id)
          .set({
        'uid': uids[uidIndex],
        'workDetailId': workDetailId,
        'confirmedAt': now,
        'confirmedBy': 'admin_test',
      });

      print('✅ 확정 지원서 생성: ${uids[uidIndex]} → ${workData['workType']}');
      uidIndex++;
    }
    print('');
    print('🎉 지원서 생성 완료!');
    print('   총 ${createdAppIds.length}개 생성됨');
    print('');

    // ✅ TO 통계 재계산
    print('📊 TO 통계 재계산 중...');
    final success = await _firestoreService.recalculateTOStats(toId);
    _firestoreService.clearCache(toId: toId);
    
    if (success) {
      print('✅ TO 통계 재계산 완료!');
    } else {
      print('⚠️  TO 통계 재계산 실패');
    }
    print('');

    
  }

  /// 모든 더미 데이터 삭제 (강화 버전)
  static Future<void> clearAllDummyData() async {
    print('');
    print('🗑️ ═══════════════════════════════════════');
    print('🗑️ 더미 데이터 삭제 시작...');
    print('🗑️ ═══════════════════════════════════════');
    print('');

    try {
      int totalDeleted = 0;
      Set<String> affectedTOIds = {}; // ✅ 전역으로 선언

      // ========================================
      // 1단계: 더미 지원자 삭제
      // ========================================
      print('📋 1단계: 더미 지원자(users) 삭제 중...');
      
      // 모든 users 조회 후 필터링 (가장 확실한 방법)
      final allUsersSnapshot = await _firestore.collection('users').get();
      print('   전체 users: ${allUsersSnapshot.docs.length}개');
      
      final dummyUsers = allUsersSnapshot.docs.where((doc) {
        final uid = doc.id;
        final data = doc.data();
        // uid 패턴 또는 isDummy 필드로 확인
        return uid.startsWith('dummy_user_') || (data['isDummy'] == true);
      }).toList();
      
      print('   더미 users: ${dummyUsers.length}개');

      if (dummyUsers.isNotEmpty) {
        // 배치로 삭제 (500개씩)
        for (int i = 0; i < dummyUsers.length; i += 500) {
          final batch = _firestore.batch();
          final chunk = dummyUsers.skip(i).take(500);
          
          for (var doc in chunk) {
            batch.delete(doc.reference);
            print('     삭제: ${doc.id} (${doc.data()['name'] ?? 'N/A'})');
          }
          
          await batch.commit();
        }
        print('✅ 더미 지원자 ${dummyUsers.length}명 삭제 완료');
        totalDeleted += dummyUsers.length;
      } else {
        print('   ℹ️  삭제할 더미 users 없음');
      }

      print('');

      // ========================================
      // 2단계: 더미 지원서 삭제
      // ========================================
      print('📋 2단계: 더미 지원서(applications) 삭제 중...');
      
      // 모든 applications 조회 후 필터링
      final allAppsSnapshot = await _firestore.collection('applications').get();
      print('   전체 applications: ${allAppsSnapshot.docs.length}개');
      
      final dummyApps = allAppsSnapshot.docs.where((doc) {
        final data = doc.data();
        final uid = data['uid'];
        // uid 패턴 또는 isDummy 필드로 확인
        return (uid != null && uid.toString().startsWith('dummy_user_')) || 
               (data['isDummy'] == true);
      }).toList();
      
      print('   더미 applications: ${dummyApps.length}개');

      if (dummyApps.isNotEmpty) {
        // ✅ 삭제 전에 TO 정보 수집
        print('   영향받은 TO 추적 중...');
        for (var doc in dummyApps) {
          final data = doc.data();
          final businessId = data['businessId'];
          final toTitle = data['toTitle'];
          final workDate = data['workDate'] as Timestamp?;
          
          if (businessId != null && toTitle != null && workDate != null) {
            // TO ID 찾기
            final toSnapshot = await _firestore
                .collection('tos')
                .where('businessId', isEqualTo: businessId)
                .where('title', isEqualTo: toTitle)
                .where('date', isEqualTo: workDate)
                .limit(1)
                .get();
            
            if (toSnapshot.docs.isNotEmpty) {
              final toId = toSnapshot.docs.first.id;
              affectedTOIds.add(toId);
              print('     → TO 추적: $toId');
            }
          }
        }
        
        print('   영향받은 TO: ${affectedTOIds.length}개');
        print('');
        
        // 배치로 삭제 (500개씩)
        for (int i = 0; i < dummyApps.length; i += 500) {
          final batch = _firestore.batch();
          final chunk = dummyApps.skip(i).take(500);
          
          for (var doc in chunk) {
            batch.delete(doc.reference);
            final data = doc.data();
            print('     삭제: ${doc.id} (${data['selectedWorkType'] ?? 'N/A'})');
          }
          
          await batch.commit();
        }
        print('✅ 더미 지원서 ${dummyApps.length}개 삭제 완료');
        totalDeleted += dummyApps.length;
      } else {
        print('   ℹ️  삭제할 더미 applications 없음');
      }

      print('');

      // ========================================
      // 3단계: confirmed_applications 서브컬렉션 정리
      // ========================================
      print('📋 3단계: confirmed_applications 서브컬렉션 정리 중...');
      final tosSnapshot = await _firestore.collection('tos').get();
      print('   전체 TO: ${tosSnapshot.docs.length}개');
      
      int confirmedDeleted = 0;

      for (var toDoc in tosSnapshot.docs) {
        final confirmedAppsSnapshot = await _firestore
            .collection('tos')
            .doc(toDoc.id)
            .collection('confirmed_applications')
            .get();

        if (confirmedAppsSnapshot.docs.isNotEmpty) {
          final confirmedBatch = _firestore.batch();
          int deletedCount = 0;

          for (var confirmedDoc in confirmedAppsSnapshot.docs) {
            final confirmedData = confirmedDoc.data();
            final uid = confirmedData['uid'];

            // uid가 'dummy_user_'로 시작하면 더미 데이터
            if (uid != null && uid.toString().startsWith('dummy_user_')) {
              confirmedBatch.delete(confirmedDoc.reference);
              deletedCount++;
              affectedTOIds.add(toDoc.id);
              print('     삭제: TO ${toDoc.id} / ${confirmedDoc.id}');
            }
          }

          if (deletedCount > 0) {
            await confirmedBatch.commit();
            print('  ✅ TO ${toDoc.id}의 더미 확정 지원서 $deletedCount개 삭제');
            confirmedDeleted += deletedCount;
          }
        }
      }

      if (confirmedDeleted > 0) {
        print('✅ 총 confirmed_applications $confirmedDeleted개 삭제');
        totalDeleted += confirmedDeleted;
      } else {
        print('   ℹ️  삭제할 confirmed_applications 없음');
      }

      print('');

      // ========================================
      // 4단계: 영향받은 TO들의 통계 재계산
      // ========================================
      if (affectedTOIds.isNotEmpty) {
        print('📊 4단계: TO 통계 재계산 중... (${affectedTOIds.length}개 TO)');
        print('');
        
        int recalculatedCount = 0;
        for (var toId in affectedTOIds) {
          final success = await _firestoreService.recalculateTOStats(toId);
          _firestoreService.clearCache(toId: toId);
          if (success) recalculatedCount++;
        }
        
        print('');
        print('✅ TO 통계 재계산 완료: $recalculatedCount/${affectedTOIds.length}개');
      } else {
        print('📊 4단계: 영향받은 TO 없음 (통계 재계산 생략)');
      }

      print('');
      print('🎉 ═══════════════════════════════════════');
      print('🎉 더미 데이터 삭제 완료!');
      print('🎉 ═══════════════════════════════════════');
      print('   📊 총 $totalDeleted개 항목 삭제됨');
      print('   🎯 영향받은 TO: ${affectedTOIds.length}개');
      print('');
      
      if (totalDeleted == 0) {
        print('⚠️  경고: 삭제된 항목이 없습니다!');
        print('   Firebase Console에서 다음을 확인하세요:');
        print('   1. users 컬렉션에 dummy_user_로 시작하는 문서가 있는지');
        print('   2. applications 컬렉션에 해당 uid의 문서가 있는지');
        print('');
      }
    } catch (e, stackTrace) {
      print('');
      print('❌ ═══════════════════════════════════════');
      print('❌ 더미 데이터 삭제 실패!');
      print('❌ ═══════════════════════════════════════');
      print('에러: $e');
      print('스택 트레이스: $stackTrace');
      print('');
      rethrow;
    }
  }
  /// ⭐ 더미 출근 데이터 생성
  static Future<void> createDummyAttendance({
    required String businessId,
    required DateTime date,
  }) async {
    print('');
    print('🕐 ═══════════════════════════════════════');
    print('🕐 더미 출근 데이터 생성 시작...');
    print('🕐 ═══════════════════════════════════════');
    print('   날짜: ${date.year}-${date.month}-${date.day}');
    print('   사업장: $businessId');
    print('');

    try {
      // 1. 해당 날짜의 확정 지원서 조회
      final dateStart = DateTime(date.year, date.month, date.day);
      
      final confirmedSnapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'CONFIRMED')
          .get();

      print('📋 확정 지원서: ${confirmedSnapshot.docs.length}개');

      // 2. 해당 날짜에 근무하는 사람 필터링
      final todayWorkers = confirmedSnapshot.docs.where((doc) {
        final data = doc.data();
        final workDate = (data['workDate'] as Timestamp).toDate();
        final isLongTerm = data['type'] == 'long_term';

        // 단기
        if (!isLongTerm) {
          return dateStart.year == workDate.year &&
                 dateStart.month == workDate.month &&
                 dateStart.day == workDate.day;
        }

        // 장기
        final workEndDate = data['workEndDate'] as Timestamp?;
        if (workEndDate == null) return false;

        final endDate = workEndDate.toDate();
        if (dateStart.isBefore(workDate) || dateStart.isAfter(endDate)) {
          return false;
        }

        // 요일 체크
        final workDays = data['workDays'] as List?;
        if (workDays == null || workDays.isEmpty) return true;

        final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
        final dayOfWeek = weekdays[date.weekday - 1];

        return workDays.contains(dayOfWeek);
      }).toList();

      print('📅 오늘 근무 대상: ${todayWorkers.length}명');
      print('');

      if (todayWorkers.isEmpty) {
        print('⚠️  해당 날짜에 근무하는 확정 인원이 없습니다.');
        return;
      }

      // 3. 70%는 출근, 30%는 미출근 (랜덤)
      int checkedInCount = 0;
      int checkedOutCount = 0;

      for (var doc in todayWorkers) {
        final appId = doc.id;
        final data = doc.data();
        final uid = data['uid'];
        final workType = data['selectedWorkType'];
        final startTime = data['startTime'];
        final endTime = data['endTime'];

        // 70% 확률로 출근
        final shouldCheckIn = _random.nextInt(100) < 70;

        if (!shouldCheckIn) {
          print('   ⏰ $uid - 미출근');
          continue;
        }

        // 출근 시간 (시작 시간 ± 30분)
        final startParts = startTime.split(':');
        final startHour = int.parse(startParts[0]);
        final startMinute = int.parse(startParts[1]);
        final randomMinutes = _random.nextInt(61) - 30; // -30 ~ +30
        
        final checkInHour = startHour;
        final checkInMinute = (startMinute + randomMinutes).clamp(0, 59);
        final checkInTime = '${checkInHour.toString().padLeft(2, '0')}:${checkInMinute.toString().padLeft(2, '0')}:00';

        // 50% 확률로 퇴근도 찍음
        final shouldCheckOut = _random.nextInt(100) < 50;
        String? checkOutTime;
        double? workHours;

        if (shouldCheckOut) {
          final endParts = endTime.split(':');
          final endHour = int.parse(endParts[0]);
          final endMinute = int.parse(endParts[1]);
          final randomEndMinutes = _random.nextInt(61) - 30;
          
          final checkOutHour = endHour;
          final checkOutMinute = (endMinute + randomEndMinutes).clamp(0, 59);
          checkOutTime = '${checkOutHour.toString().padLeft(2, '0')}:${checkOutMinute.toString().padLeft(2, '0')}:00';

          // 근무 시간 계산
          final inMinutes = checkInHour * 60 + checkInMinute;
          final outMinutes = checkOutHour * 60 + checkOutMinute;
          workHours = (outMinutes - inMinutes) / 60.0;
        }

        // 출근 기록 생성
        await _firestore.collection('attendance').add({
          'applicationId': appId,
          'userId': uid,
          'businessId': businessId,
          'businessName': data['businessName'],
          'workDate': Timestamp.fromDate(dateStart),
          'workType': workType,
          'checkIn': checkInTime,
          'checkInLat': 37.5665 + _random.nextDouble() * 0.01,
          'checkInLng': 126.9780 + _random.nextDouble() * 0.01,
          'checkInMethod': 'gps',
          'checkInTime': Timestamp.now(),
          'checkOut': checkOutTime,
          'checkOutLat': checkOutTime != null ? 37.5665 + _random.nextDouble() * 0.01 : null,
          'checkOutLng': checkOutTime != null ? 126.9780 + _random.nextDouble() * 0.01 : null,
          'checkOutMethod': checkOutTime != null ? 'gps' : null,
          'checkOutTime': checkOutTime != null ? Timestamp.now() : null,
          'status': 'present',
          'workHours': workHours,
          'isModified': false,
          'modifyRequested': false,
          'createdAt': Timestamp.now(),
          'isDummy': true,  // ⭐ 더미 데이터 표시
        });

        if (shouldCheckOut) {
          print('   🏠 $uid - 출근 $checkInTime, 퇴근 $checkOutTime');
          checkedOutCount++;
        } else {
          print('   ✅ $uid - 출근 $checkInTime');
        }
        checkedInCount++;
      }

      print('');
      print('🎉 ═══════════════════════════════════════');
      print('🎉 더미 출근 데이터 생성 완료!');
      print('🎉 ═══════════════════════════════════════');
      print('   출근 완료: $checkedInCount명');
      print('   퇴근 완료: $checkedOutCount명');
      print('   미출근: ${todayWorkers.length - checkedInCount}명');
      print('');
    } catch (e, stackTrace) {
      print('');
      print('❌ ═══════════════════════════════════════');
      print('❌ 더미 출근 데이터 생성 실패!');
      print('❌ ═══════════════════════════════════════');
      print('에러: $e');
      print('스택 트레이스: $stackTrace');
      print('');
      rethrow;
    }
  }

  /// ⭐ 더미 출근 데이터 삭제
  static Future<void> clearDummyAttendance() async {
    print('');
    print('🗑️ ═══════════════════════════════════════');
    print('🗑️ 더미 출근 데이터 삭제 시작...');
    print('🗑️ ═══════════════════════════════════════');
    print('');

    try {
      final allAttendanceSnapshot = await _firestore.collection('attendance').get();
      print('   전체 attendance: ${allAttendanceSnapshot.docs.length}개');

      final dummyAttendance = allAttendanceSnapshot.docs.where((doc) {
        final data = doc.data();
        return data['isDummy'] == true;
      }).toList();

      print('   더미 attendance: ${dummyAttendance.length}개');

      if (dummyAttendance.isNotEmpty) {
        for (int i = 0; i < dummyAttendance.length; i += 500) {
          final batch = _firestore.batch();
          final chunk = dummyAttendance.skip(i).take(500);

          for (var doc in chunk) {
            batch.delete(doc.reference);
            print('     삭제: ${doc.id}');
          }

          await batch.commit();
        }
        print('✅ 더미 출근 데이터 ${dummyAttendance.length}개 삭제 완료');
      } else {
        print('   ℹ️  삭제할 더미 attendance 없음');
      }

      print('');
      print('🎉 더미 출근 데이터 삭제 완료!');
      print('');
    } catch (e) {
      print('❌ 더미 출근 데이터 삭제 실패: $e');
      rethrow;
    }
  }
}