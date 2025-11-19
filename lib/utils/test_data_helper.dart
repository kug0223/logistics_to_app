// lib/utils/test_data_helper.dart (UserModel 개선 버전)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';
import '../services/firestore_service.dart';

class TestDataHelper {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirestoreService _firestoreService = FirestoreService();
  static final Random _random = Random();

  // ━━━ 더미 이름 풀 ━━━
  static final List<String> _firstNames = [
    '김', '이', '박', '최', '정', '강', '조', '윤', '장', '임',
    '한', '오', '서', '신', '권', '황', '안', '송', '류', '전',
    '홍', '고', '문', '양', '손', '배', '조', '백', '허', '유'
  ];

  static final List<String> _lastNames = [
    '민준', '서준', '예준', '도윤', '시우', '주원', '하준', '지호', '지후', '준서',
    '서연', '서윤', '지우', '서현', '민서', '하은', '윤서', '지민', '지유', '채원',
    '수빈', '지안', '유진', '지원', '다은', '예은', '채은', '서아', '민지', '은서'
  ];

  // ━━━ 은행 목록 ━━━
  static final List<String> _banks = [
    '국민은행', '신한은행', '우리은행', '하나은행', '농협은행', 
    'IBK기업은행', '카카오뱅크', '토스뱅크', 'SC제일은행', '씨티은행'
  ];

  // ━━━ 주소 풀 ━━━
  static final List<String> _addresses = [
    '서울시 강남구 역삼동',
    '서울시 송파구 잠실동',
    '경기도 성남시 분당구 정자동',
    '서울시 마포구 상암동',
    '경기도 고양시 일산동구',
    '인천시 남동구 구월동',
    '서울시 영등포구 여의도동',
    '경기도 용인시 수지구',
    '서울시 강서구 화곡동',
    '경기도 수원시 팔달구',
    '서울시 관악구 신림동',
    '부천시 원미구 중동',
    '서울시 동작구 사당동',
    '경기도 안양시 동안구',
    '서울시 서초구 반포동',
  ];

  // ━━━ 자기소개 템플릿 ━━━
  static final List<String> _bioTemplates = [
    '성실하게 일하겠습니다!',
    '책임감 있게 근무하는 것을 목표로 합니다.',
    '물류 경력 {}년차입니다.',
    '항상 웃으면서 일합니다 :)',
    '빠르고 정확한 작업을 지향합니다.',
    '팀워크를 중시하는 근무자입니다.',
    '꼼꼼하고 정확한 업무 처리가 장점입니다.',
    '새로운 환경에 빠르게 적응합니다.',
    '성실함만큼은 자신있습니다!',
    '근무 태도가 좋다는 말을 많이 듣습니다.',
  ];

  // ━━━ 업무 유형 풀 ━━━
  static final List<String> _allWorkTypes = [
    '피킹', '패킹', '분류', '하역', '검수', '배송', '포장', '검품'
  ];

  /// ⭐ 주민등록번호 생성 (더미용)
  static String _generateResidentNumber(DateTime birthDate, String gender) {
    final year = birthDate.year.toString().substring(2);
    final month = birthDate.month.toString().padLeft(2, '0');
    final day = birthDate.day.toString().padLeft(2, '0');
    
    // 성별 코드 (남자: 1/3, 여자: 2/4)
    int genderCode;
    if (birthDate.year >= 2000) {
      genderCode = gender == '남성' ? 3 : 4;
    } else {
      genderCode = gender == '남성' ? 1 : 2;
    }
    
    final random6digits = _random.nextInt(900000) + 100000;
    
    return '$year$month$day-$genderCode$random6digits';
  }

  /// ⭐ 나이 계산
  static int _calculateAge(DateTime birthDate) {
    final now = DateTime.now();
    int age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  /// ⭐ 개선된 더미 지원자 생성 - 새로운 UserModel 필드 포함
  static Future<List<String>> createDummyApplicants(int count) async {
    print('');
    print('👥 ═══════════════════════════════════════');
    print('👥 더미 지원자 $count명 생성 시작...');
    print('👥 ═══════════════════════════════════════');
    print('');
    
    final List<String> uids = [];

    for (int i = 0; i < count; i++) {
      // ━━━ 기본 정보 생성 ━━━
      final firstName = _firstNames[_random.nextInt(_firstNames.length)];
      final lastName = _lastNames[_random.nextInt(_lastNames.length)];
      final name = '$firstName$lastName';
      
      final uid = 'dummy_user_${DateTime.now().millisecondsSinceEpoch}_$i';
      final phone = '010-${_random.nextInt(9000) + 1000}-${_random.nextInt(9000) + 1000}';
      final email = 'dummy$i@ALfit.test';
      
      // ━━━ 성별 & 생년월일 ━━━
      final gender = _random.nextBool() ? '남성' : '여성';
      
      // 나이: 20~55세
      final age = _random.nextInt(35) + 20;
      final birthYear = DateTime.now().year - age;
      final birthMonth = _random.nextInt(12) + 1;
      final birthDay = _random.nextInt(28) + 1; // 안전하게 1~28일
      final birthDate = DateTime(birthYear, birthMonth, birthDay);
      
      // ⭐ 주민번호 생성
      final residentNumber = _generateResidentNumber(birthDate, gender);
      
      // ━━━ 주소 ━━━
      final address = _addresses[_random.nextInt(_addresses.length)];
      final detailAddress = '${_random.nextInt(999) + 1}호';
      
      // ━━━ 급여 계좌 ━━━
      final bankName = _banks[_random.nextInt(_banks.length)];
      final accountNumber = '${_random.nextInt(900) + 100}-${_random.nextInt(9000) + 1000}-${_random.nextInt(9000) + 1000}';
      final accountHolder = name;
      
      // ━━━ 프로필 ━━━
      final bioTemplate = _bioTemplates[_random.nextInt(_bioTemplates.length)];
      final bio = bioTemplate.contains('{}') 
          ? bioTemplate.replaceFirst('{}', '${_random.nextInt(5) + 1}')
          : bioTemplate;
      
      // 선호 업무 (1~3개)
      final preferredCount = _random.nextInt(3) + 1;
      final shuffled = List.from(_allWorkTypes)..shuffle(_random);
      final preferredWorkTypes = shuffled.take(preferredCount).toList();
      
      // ━━━ 근무 이력 ━━━
      final totalWorkDays = _random.nextInt(100);
      final totalWorkHours = totalWorkDays * (_random.nextInt(4) + 6); // 6~9시간
      final averageRating = totalWorkDays > 0 
          ? (_random.nextDouble() * 2 + 3).clamp(3.0, 5.0) 
          : 0.0;
      final reviewCount = totalWorkDays > 0 
          ? (totalWorkDays * 0.3).round() 
          : 0;
      final noShowCount = _random.nextInt(3);
      final lateCount = _random.nextInt(5);
      
      // ━━━ Firestore에 저장 ━━━
      await _firestore.collection('users').doc(uid).set({
        // 기본 정보
        'name': name,
        'email': email,
        'phone': phone,
        'role': 'USER',
        'createdAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
        
        // ⭐ 주민번호 기반 정보
        'gender': gender,
        'birthDate': Timestamp.fromDate(birthDate),
        'residentNumber': residentNumber, // ⚠️ 실제론 암호화 필요!
        
        // 주소
        'address': address,
        'detailAddress': detailAddress,
        
        // 신분증 정보 (더미는 null)
        'idCardImageUrl': null,
        'idCardVerifiedAt': null,
        'isIdVerified': false,
        
        // 급여 정보
        'bankName': bankName,
        'accountNumber': accountNumber, // ⚠️ 실제론 암호화 필요
        'accountHolder': accountHolder,
        
        // 프로필
        'profileImageUrl': null,
        'bio': bio,
        'skills': null,
        'preferredWorkTypes': preferredWorkTypes,
        
        // 통계
        'totalWorkDays': totalWorkDays,
        'totalWorkHours': totalWorkHours,
        'averageRating': averageRating,
        'reviewCount': reviewCount,
        'noShowCount': noShowCount,
        'lateCount': lateCount,
        
        // 상태
        'isAvailable': true,
        'unavailableReason': null,
        'availableFrom': null,
        'isBlacklisted': false,
        'blacklistReason': null,
        
        'isDummy': true,  // ⭐ 더미 데이터 표시
      });

      uids.add(uid);
      
      // ━━━ 로그 출력 ━━━
      final calculatedAge = _calculateAge(birthDate);
      final trustScore = _calculateTrustScore(
        totalWorkDays, averageRating, noShowCount, lateCount
      );
      
      print('  ✅ $name ($gender, ${calculatedAge}세)');
      print('     🆔 $residentNumber');
      print('     📞 $phone');
      print('     🏠 $address $detailAddress');
      print('     💳 $bankName $accountNumber ($accountHolder)');
      print('     ⭐ 평점: ${averageRating.toStringAsFixed(1)} (${reviewCount}개) | 신뢰도: $trustScore점');
      print('     💼 선호: ${preferredWorkTypes.join(", ")}');
      print('     📊 근무: ${totalWorkDays}일 (${totalWorkHours}시간)');
      print('');
    }

    print('🎉 ═══════════════════════════════════════');
    print('🎉 더미 지원자 $count명 생성 완료!');
    print('🎉 ═══════════════════════════════════════');
    print('');
    
    return uids;
  }

  /// 신뢰도 점수 계산
  static int _calculateTrustScore(
    int totalWorkDays, 
    double averageRating, 
    int noShowCount, 
    int lateCount
  ) {
    if (totalWorkDays == 0) return 0;
    
    int score = 60;
    
    if (averageRating > 0) {
      score += (averageRating * 4).toInt();
    }
    
    score += (totalWorkDays / 10).clamp(0, 15).toInt();
    score -= noShowCount * 5;
    score -= lateCount * 2;
    
    return score.clamp(0, 100);
  }

  /// ⭐ 특정 TO에 더미 지원서 생성
  static Future<void> createDummyApplications({
    required String toId,
    required List<String> workTypes,
    required int pendingCount,
    required int confirmedCount,
  }) async {
    print('');
    print('📝 ═══════════════════════════════════════');
    print('📝 TO $toId에 지원서 생성 중...');
    print('📝 ═══════════════════════════════════════');
    print('   대기: $pendingCount명');
    print('   확정: $confirmedCount명');
    print('');

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
    final startTime = toData['startTime'];
    final endTime = toData['endTime'];

    // 장기 TO 정보
    final jobType = toData['jobType'] ?? 'short';
    final isLongTerm = jobType == 'long_term';
    final workEndDate = toData['endDate'] as Timestamp?;
    final workDays = toData['workDays'] as List?;

    if (isLongTerm) {
      print('📌 장기 TO 감지!');
      if (workEndDate != null) {
        final endDate = workEndDate.toDate();
        print('   근무 기간: ${date.year}-${date.month}-${date.day} ~ ${endDate.year}-${endDate.month}-${endDate.day}');
      }
      if (workDays != null && workDays.isNotEmpty) {
        print('   근무 요일: ${workDays.join(", ")}');
      }
    }

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
    final now = Timestamp.now();

    // 4. 지원서 생성
    final List<String> createdAppIds = [];
    
    for (int i = 0; i < uids.length; i++) {
      final uid = uids[i];
      final isConfirmed = i < confirmedCount;
      
      // 랜덤 WorkDetail 선택
      final workDetail = workDetails[_random.nextInt(workDetails.length)];
      final workData = workDetail.data();
      
      // 지원서 데이터 생성
      final applicationData = <String, dynamic>{
        'businessId': businessId,
        'businessName': businessName,
        'toTitle': toTitle,
        'workDate': Timestamp.fromDate(date),
        'startTime': startTime,
        'endTime': endTime,
        'uid': uid,
        'selectedWorkType': workData['workType'],
        'wage': workData['wage'],
        'status': isConfirmed ? 'CONFIRMED' : 'PENDING',
        'appliedAt': now,
        'confirmedAt': isConfirmed ? now : null,
        'isDummy': true,
        
        // 장기 TO 필드
        'type': jobType,
      };
      
      // 장기 TO인 경우 추가 필드
      if (isLongTerm && workEndDate != null) {
        applicationData['isLongTermApplication'] = true;
        applicationData['workEndDate'] = workEndDate;
        
        if (workDays != null && workDays.isNotEmpty) {
          applicationData['workDays'] = workDays;
        }
      }
      
      final appDoc = await _firestore.collection('applications').add(applicationData);
      createdAppIds.add(appDoc.id);
      
      print('  ${isConfirmed ? "✅" : "⏳"} $uid → ${workData['workType']} (${workData['wage']}원)');
    }

    print('');
    print('🎉 지원서 ${createdAppIds.length}개 생성 완료!');
    
    // 5. TO 통계 재계산
    print('📊 TO 통계 재계산 중...');
    final success = await _firestoreService.recalculateTOStats(toId);
    if (success) {
      print('✅ TO 통계 재계산 완료');
    } else {
      print('⚠️  TO 통계 재계산 실패');
    }
    print('');
  }

  /// 더미 출근 데이터 생성
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
      final dateStart = DateTime(date.year, date.month, date.day);
      
      // 해당 사업장의 확정 지원서 조회
      final confirmedSnapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'CONFIRMED')
          .get();

      print('📋 확정 지원서: ${confirmedSnapshot.docs.length}개');

      // 오늘 근무 대상 필터링
      final todayWorkers = confirmedSnapshot.docs.where((doc) {
        final data = doc.data();
        final workDate = (data['workDate'] as Timestamp).toDate();
        final isLongTerm = data['type'] == 'long_term' || data['isLongTermApplication'] == true;

        if (!isLongTerm) {
          // 단기: 날짜 일치
          return dateStart.year == workDate.year &&
                 dateStart.month == workDate.month &&
                 dateStart.day == workDate.day;
        }

        // 장기: 기간 + 요일 체크
        final workEndDate = data['workEndDate'] as Timestamp?;
        if (workEndDate == null) return false;

        final endDate = workEndDate.toDate();
        if (dateStart.isBefore(workDate) || dateStart.isAfter(endDate)) {
          return false;
        }

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

      int checkedInCount = 0;
      int checkedOutCount = 0;

      for (var appDoc in todayWorkers) {
        final appData = appDoc.data();
        final appId = appDoc.id;
        final uid = appData['uid'];
        final startTime = appData['startTime'];
        final endTime = appData['endTime'];

        // 70% 확률로 출근
        if (_random.nextDouble() > 0.7) continue;

        // 출근 시간 생성
        final startParts = startTime.split(':');
        final startHour = int.parse(startParts[0]);
        final startMinute = int.parse(startParts[1]);

        final checkInTime = DateTime(
          date.year,
          date.month,
          date.day,
          startHour,
          startMinute + _random.nextInt(30) - 15, // ±15분
        );

        // 50% 확률로 퇴근
        DateTime? checkOutTime;
        if (_random.nextBool()) {
          final endParts = endTime.split(':');
          final endHour = int.parse(endParts[0]);
          final endMinute = int.parse(endParts[1]);

          checkOutTime = DateTime(
            date.year,
            date.month,
            date.day,
            endHour,
            endMinute + _random.nextInt(30) - 15,
          );
          checkedOutCount++;
        }

        // GPS 좌표 (랜덤)
        final latitude = 37.5 + _random.nextDouble() * 0.1;
        final longitude = 127.0 + _random.nextDouble() * 0.1;

        // Firestore 저장
        await _firestore.collection('attendance').add({
          'applicationId': appId,
          'uid': uid,
          'businessId': businessId,
          'date': Timestamp.fromDate(dateStart),
          'checkInTime': Timestamp.fromDate(checkInTime),
          'checkOutTime': checkOutTime != null 
              ? Timestamp.fromDate(checkOutTime) 
              : null,
          'checkInLatitude': latitude,
          'checkInLongitude': longitude,
          'checkOutLatitude': checkOutTime != null ? latitude : null,
          'checkOutLongitude': checkOutTime != null ? longitude : null,
          'isDummy': true,
        });

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

  /// 모든 더미 데이터 삭제
  static Future<void> clearAllDummyData() async {
    print('');
    print('🗑️ ═══════════════════════════════════════');
    print('🗑️ 더미 데이터 삭제 시작...');
    print('🗑️ ═══════════════════════════════════════');
    print('');

    try {
      int totalDeleted = 0;
      Set<String> affectedTOIds = {};

      // 1. 더미 지원자 삭제
      print('📋 1단계: 더미 지원자(users) 삭제 중...');
      
      final allUsersSnapshot = await _firestore.collection('users').get();
      print('   전체 users: ${allUsersSnapshot.docs.length}개');
      
      final dummyUsers = allUsersSnapshot.docs.where((doc) {
        final uid = doc.id;
        final data = doc.data();
        return uid.startsWith('dummy_user_') || (data['isDummy'] == true);
      }).toList();
      
      print('   더미 users: ${dummyUsers.length}개');

      if (dummyUsers.isNotEmpty) {
        for (int i = 0; i < dummyUsers.length; i += 500) {
          final batch = _firestore.batch();
          final chunk = dummyUsers.skip(i).take(500);
          
          for (var doc in chunk) {
            batch.delete(doc.reference);
          }
          
          await batch.commit();
        }
        print('✅ 더미 지원자 ${dummyUsers.length}명 삭제 완료');
        totalDeleted += dummyUsers.length;
      } else {
        print('   ℹ️  삭제할 더미 users 없음');
      }

      print('');

      // 2. 더미 지원서 삭제
      print('📋 2단계: 더미 지원서(applications) 삭제 중...');
      
      final allAppsSnapshot = await _firestore.collection('applications').get();
      print('   전체 applications: ${allAppsSnapshot.docs.length}개');
      
      final dummyApps = allAppsSnapshot.docs.where((doc) {
        final data = doc.data();
        final uid = data['uid'];
        return (uid != null && uid.toString().startsWith('dummy_user_')) || 
               (data['isDummy'] == true);
      }).toList();
      
      print('   더미 applications: ${dummyApps.length}개');

      if (dummyApps.isNotEmpty) {
        for (int i = 0; i < dummyApps.length; i += 500) {
          final batch = _firestore.batch();
          final chunk = dummyApps.skip(i).take(500);
          
          for (var doc in chunk) {
            final data = doc.data();
            final businessId = data['businessId'];
            if (businessId != null) {
              // TO ID 추적 (나중에 통계 재계산)
              affectedTOIds.add(businessId);
            }
            
            batch.delete(doc.reference);
          }
          
          await batch.commit();
        }
        print('✅ 더미 지원서 ${dummyApps.length}개 삭제 완료');
        totalDeleted += dummyApps.length;
      } else {
        print('   ℹ️  삭제할 더미 applications 없음');
      }

      print('');

      // 3. 더미 출근 데이터 삭제
      await clearDummyAttendance();

      print('');
      print('🎉 ═══════════════════════════════════════');
      print('🎉 모든 더미 데이터 삭제 완료!');
      print('🎉 ═══════════════════════════════════════');
      print('   📊 총 $totalDeleted개 항목 삭제됨');
      print('   🎯 영향받은 TO: ${affectedTOIds.length}개');
      print('');
      
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

  /// 더미 출근 데이터 삭제
  static Future<void> clearDummyAttendance() async {
    print('📋 3단계: 더미 출근 데이터(attendance) 삭제 중...');

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
          }

          await batch.commit();
        }
        print('✅ 더미 출근 데이터 ${dummyAttendance.length}개 삭제 완료');
      } else {
        print('   ℹ️  삭제할 더미 attendance 없음');
      }
    } catch (e) {
      print('❌ 더미 출근 데이터 삭제 실패: $e');
      rethrow;
    }
  }
}