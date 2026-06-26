// lib/utils/test_data_helper.dart (UserModel 개선 버전)

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';
import '../services/firestore_service.dart';
import '../models/core/application_model.dart';
import '../models/core/to_model.dart';
import '../models/core/work_detail_data.dart';
import 'format_helper.dart';
import 'toast_helper.dart';
import 'encryption_helper.dart';

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
    debugPrint('');
    debugPrint('👥 ═══════════════════════════════════════');
    debugPrint('👥 더미 지원자 $count명 생성 시작...');
    debugPrint('👥 ═══════════════════════════════════════');
    debugPrint('');
    
    final List<String> uids = [];
    // 루프 밖에서 기준 타임스탬프 고정 → 내부에서 호출해도 중복 없음
    final baseTs = DateTime.now().millisecondsSinceEpoch;

    for (int i = 0; i < count; i++) {
      // ━━━ 기본 정보 생성 ━━━
      final firstName = _firstNames[_random.nextInt(_firstNames.length)];
      final lastName = _lastNames[_random.nextInt(_lastNames.length)];
      final name = '$firstName$lastName';

      final uid = 'dummy_user_${baseTs}_$i';
      final phone = '010-${_random.nextInt(9000) + 1000}-${_random.nextInt(9000) + 1000}';
      // 타임스탬프 포함 → 반복 호출 시 이메일 중복 방지
      final email = 'dummy_${baseTs}_$i@alfit.test';
      
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
      // 신뢰도 점수 — Firestore에 저장해야 배지에 표시됨
      final trustScore = _calculateTrustScore(totalWorkDays, averageRating, noShowCount, lateCount);

      // ━━━ Firestore에 저장 ━━━
      final username = 'dummy_${baseTs}_$i'; // 아이디 (로그인·검색 기준)
      await _firestore.collection('users').doc(uid).set({
        // 기본 정보
        'name': name,
        'username': username,
        'userEmail': email,
        'email': email,
        'phone': phone,
        'role': 'USER',
        'isEmailVerified': true, // 기존 호환성 유지 (PASS 미전환 사용자)
        'createdAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
        
        // ⭐ 주민번호 기반 정보
        'gender': gender,
        'birthDate': Timestamp.fromDate(birthDate),
        'residentNumber': EncryptionHelper.encrypt(residentNumber) ?? residentNumber,
        
        // 주소
        'address': address,
        'detailAddress': detailAddress,
        
        // 신분증·통장 — 더미값 설정 (지원 조건 충족용)
        'idCardImageUrl': 'https://placehold.co/300x200?text=dummy_id',
        'bankbookImageUrl': 'https://placehold.co/300x200?text=dummy_bank',
        'idCardVerifiedAt': FieldValue.serverTimestamp(),
        'isIdVerified': true,
        
        // 급여 정보
        'bankName': bankName,
        'accountNumber': EncryptionHelper.encrypt(accountNumber) ?? accountNumber,
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
        'trustScore': trustScore, // 신뢰도 배지 표시용 (UserModel.storedTrustScore)

        // 상태
        'isAvailable': true,
        'unavailableReason': null,
        'availableFrom': null,
        'isBlacklisted': false,
        'blacklistReason': null,

        'isDummy': true, // ⭐ 더미 데이터 표시
      });

      uids.add(uid);

      // ━━━ 로그 출력 ━━━
      final calculatedAge = _calculateAge(birthDate);
      // 릴리즈 빌드에서도 debugPrint는 출력됨 — 주민번호·계좌번호는 kDebugMode 가드 안에서만 로그.
      debugPrint('  ✅ $name ($gender, $calculatedAge세) | 평점: ${averageRating.toStringAsFixed(1)} | 신뢰도: $trustScore점');
      if (kDebugMode) {
        debugPrint('     🆔 $residentNumber');
        debugPrint('     📞 $phone');
        debugPrint('     🏠 $address $detailAddress');
        debugPrint('     💳 $bankName $accountNumber ($accountHolder)');
      }
      debugPrint('     💼 선호: ${preferredWorkTypes.join(", ")}');
      debugPrint('     📊 근무: $totalWorkDays일 ($totalWorkHours시간)');
      debugPrint('');
    }

    debugPrint('🎉 ═══════════════════════════════════════');
    debugPrint('🎉 더미 지원자 $count명 생성 완료!');
    debugPrint('🎉 ═══════════════════════════════════════');
    debugPrint('');
    
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
    required int pendingCount,
    required int confirmedCount,
    DateTime? slotDate, // flex TO 슬롯 선택 시 workDate 오버라이드
    String? slotId,     // flex TO 슬롯 ID (지원자 조회·슬롯 통계에 필수)
  }) async {
    debugPrint('');
    debugPrint('📝 ═══════════════════════════════════════');
    debugPrint('📝 TO $toId에 지원서 생성 중...');
    debugPrint('📝 ═══════════════════════════════════════');
    debugPrint('   대기: $pendingCount명');
    debugPrint('   확정: $confirmedCount명');
    debugPrint('');

    // 1. 더미 지원자 생성
    final totalCount = pendingCount + confirmedCount;
    final uids = await createDummyApplicants(totalCount);

    // 2. TO 정보 조회
    final toDoc = await _firestore.collection('tos').doc(toId).get();
    if (!toDoc.exists) {
      debugPrint('❌ TO를 찾을 수 없습니다: $toId');
      return;
    }

    final toData = toDoc.data()!;
    final businessId = toData['businessId'] as String?;
    if (businessId == null || businessId.isEmpty) {
      debugPrint('❌ TO에 businessId가 없습니다: $toId');
      return;
    }
    final businessName = toData['businessName'] as String? ?? '';
    final toTitle = toData['title'] as String? ?? '';
    final toType = toData['type'] as String? ?? TOType.flex;
    final isContract = toType == TOType.contract;

    // TOModel 생성 → computeContractEndDate 사용
    final toModel = TOModel.fromMap(toData, toId);

    final rangeStart = toModel.rangeStart ?? DateTime.now();
    final toWorkDays = List<String>.from(toData['workDays'] as List? ?? []);

    // flex TO: slotDate 지정 시 그 날짜, 없으면 오늘 → 출근 데이터 생성 즉시 테스트 가능
    // contract TO: rangeStart(근무 시작일) 사용
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final workDate = isContract
        ? rangeStart
        : (slotDate != null
            ? DateTime(slotDate.year, slotDate.month, slotDate.day)
            : todayStart);

    if (isContract) {
      debugPrint('📌 장기(long_term) TO 감지!');
      debugPrint('   contractPeriodType: ${toModel.contractPeriodType ?? "custom"}');
      final sampleEnd = toModel.computeContractEndDate(todayStart);
      debugPrint('   근무 시작: ${rangeStart.month}/${rangeStart.day}');
      debugPrint('   계약 종료 예시(오늘 기준): ${sampleEnd.month}/${sampleEnd.day}');
      if (toWorkDays.isNotEmpty) {
        debugPrint('   근무 요일: ${toWorkDays.join(", ")}');
      }
    }

    // 3. WorkDetails — slotId 있으면 슬롯 문서 우선, 없으면 TO 문서
    List<WorkDetailData> workDetailsList = [];

    if (slotId != null) {
      final slotDoc = await _firestore
          .collection('tos')
          .doc(toId)
          .collection('slots')
          .doc(slotId)
          .get();
      if (slotDoc.exists) {
        final slotWorkDetailsRaw = slotDoc.data()?['workDetails'] as List?;
        if (slotWorkDetailsRaw != null && slotWorkDetailsRaw.isNotEmpty) {
          workDetailsList = slotWorkDetailsRaw
              .map((e) => WorkDetailData.fromMap(e as Map<String, dynamic>))
              .toList();
          debugPrint('   업무 상세: 슬롯 문서에서 읽음 (${workDetailsList.length}개)');
        }
      }
    }

    // 슬롯에 없으면 TO 문서에서 폴백
    if (workDetailsList.isEmpty) {
      final workDetailsRaw = toData['workDetails'] as List?;
      if (workDetailsRaw != null && workDetailsRaw.isNotEmpty) {
        workDetailsList = workDetailsRaw
            .map((e) => WorkDetailData.fromMap(e as Map<String, dynamic>))
            .toList();
        debugPrint('   업무 상세: TO 문서에서 읽음 (${workDetailsList.length}개)');
      }
    }

    if (workDetailsList.isEmpty) {
      debugPrint('❌ WorkDetails가 없습니다 (슬롯 또는 TO 문서에 workDetails 배열이 필요합니다)');
      ToastHelper.showError('업무 상세 정보가 없습니다. 먼저 업무 유형을 등록해주세요.');
      return;
    }

    debugPrint('   업무 상세: ${workDetailsList.map((w) => w.workType).join(", ")}');

    final now = Timestamp.now();
    final List<String> createdAppIds = [];

    // 4. 지원서 생성
    for (int i = 0; i < uids.length; i++) {
      final uid = uids[i];
      final isConfirmed = i < confirmedCount;

      // 업무상세 골고루 분배 (라운드 로빈)
      final workDetail = workDetailsList[i % workDetailsList.length];

      // contract TO: 희망 시작일 = 오늘 ~ 3일 후 중 랜덤 (당일 테스트 가능하도록)
      DateTime? desiredStartDate;
      DateTime? workEndDate;
      if (isContract) {
        final daysToAdd = _random.nextInt(4); // 0~3일
        final ds = DateTime.now().add(Duration(days: daysToAdd));
        desiredStartDate = DateTime(ds.year, ds.month, ds.day);
        workEndDate = toModel.computeContractEndDate(desiredStartDate);
        debugPrint('     📅 희망시작일: ${desiredStartDate.month}/${desiredStartDate.day} → 종료: ${workEndDate.month}/${workEndDate.day}');
      }

      final applicationData = <String, dynamic>{
        'businessId': businessId,
        'businessName': businessName,
        'toId': toId,
        'toTitle': toTitle,
        if (slotId != null) 'slotId': slotId,
        'workDate': Timestamp.fromDate(workDate),
        'startTime': workDetail.startTime,
        'endTime': workDetail.endTime,
        'uid': uid,
        'selectedWorkType': workDetail.workType,
        'workDetailId': workDetail.id,
        'wage': workDetail.wage,
        'wageType': workDetail.wageType,
        'status': isConfirmed ? 'CONFIRMED' : 'PENDING',
        'appliedAt': now,
        'confirmedAt': isConfirmed ? now : null,
        if (isConfirmed) 'confirmedBy': 'SYSTEM',
        'isDummy': true,
        // 실제 로직과 동일: contract → 'long_term', flex → 'short'
        'type': isContract ? 'long_term' : 'short',
        'statusHistory': [{
          'status': isConfirmed ? 'CONFIRMED' : 'PENDING',
          'at': Timestamp.now(),
          'by': isConfirmed ? 'SYSTEM' : null,
          'action': isConfirmed ? 'CONFIRM' : 'APPLY',
        }],
        // contract TO 전용 필드
        if (isContract) ...{
          'workDays': toWorkDays,
          'desiredStartDate': Timestamp.fromDate(desiredStartDate!),
          'workEndDate': Timestamp.fromDate(workEndDate!),
        },
      };

      final appDoc = await _firestore.collection('applications').add(applicationData);
      createdAppIds.add(appDoc.id);

      debugPrint('  ${isConfirmed ? "✅" : "⏳"} $uid → ${workDetail.workType} (${workDetail.wage}원)');
    }

    debugPrint('');
    debugPrint('🎉 지원서 ${createdAppIds.length}개 생성 완료!');

    // 5. 슬롯 통계 직접 업데이트 (flex TO 슬롯 선택 시)
    if (slotId != null) {
      debugPrint('📊 슬롯 통계 업데이트 중...');
      try {
        await _firestore
            .collection('tos')
            .doc(toId)
            .collection('slots')
            .doc(slotId)
            .update({
          'pendingCount': FieldValue.increment(pendingCount),
          'confirmedCount': FieldValue.increment(confirmedCount),
        });
        debugPrint('✅ 슬롯 통계 업데이트 완료 (대기+$pendingCount, 확정+$confirmedCount)');
      } catch (e) {
        debugPrint('⚠️ 슬롯 통계 업데이트 실패: $e');
      }
    }

    // 6. TO 통계 재계산 (한 번만)
    debugPrint('📊 TO 통계 재계산 중...');
    final success = await _firestoreService.recalculateTOStats(toId);
    debugPrint(success ? '✅ TO 통계 재계산 완료' : '⚠️  TO 통계 재계산 실패');

    // ✅ 캐시 클리어
    _firestoreService.clearCache();
    debugPrint('');
  }

  /// 더미 출근 데이터 생성
  static Future<void> createDummyAttendance({
    required String businessId,
    required DateTime date,
  }) async {
    debugPrint('');
    debugPrint('🕐 ═══════════════════════════════════════');
    debugPrint('🕐 더미 출근 데이터 생성 시작...');
    debugPrint('🕐 ═══════════════════════════════════════');
    debugPrint('   날짜: ${date.year}-${date.month}-${date.day}');
    debugPrint('   사업장: $businessId');
    debugPrint('');

    try {
      final dateStart = DateTime(date.year, date.month, date.day);
      
      // 해당 사업장의 더미 확정 지원서 조회 (isDummy 필터 — 실 데이터 오염 방지)
      final confirmedSnapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'CONFIRMED')
          .where('isDummy', isEqualTo: true)
          .get();

      debugPrint('📋 확정 지원서: ${confirmedSnapshot.docs.length}개');

      // 오늘 근무 대상 필터링
      final todayWorkers = confirmedSnapshot.docs.where((doc) {
        final data = doc.data();
        // [B11 수정] toLocal() 필수: Firestore Timestamp.toDate()는 UTC 기준 반환.
        // toLocal() 없이 year/month/day 비교 시 KST(+9) 경계일(자정 전후)에서 1일 오차 발생.
        final workDate = (data['workDate'] as Timestamp).toDate().toLocal();
        final isLongTerm = data['type'] == AppType.longTerm;

        if (!isLongTerm) {
          // 단기: 날짜 일치
          return dateStart.year == workDate.year &&
                 dateStart.month == workDate.month &&
                 dateStart.day == workDate.day;
        }

        // 장기: 기간 + 요일 체크
        final workEndDate = data['workEndDate'] as Timestamp?;
        if (workEndDate == null) return false;

        // [B11 수정] toLocal() 필수 — KST 경계일 안전
        final endDate = workEndDate.toDate().toLocal();
        final desiredStartTs = data['desiredStartDate'] as Timestamp?;
        final effectiveStart = desiredStartTs != null
            ? DateTime(desiredStartTs.toDate().toLocal().year, desiredStartTs.toDate().toLocal().month, desiredStartTs.toDate().toLocal().day)
            : DateTime(workDate.year, workDate.month, workDate.day);

        if (dateStart.isBefore(effectiveStart) || dateStart.isAfter(endDate)) {
          return false;
        }

        final workDays = data['workDays'] as List?;
        if (workDays == null || workDays.isEmpty) return true;

        return workDays.contains(FormatHelper.weekday(date));
      }).toList();

      debugPrint('📅 오늘 근무 대상: ${todayWorkers.length}명');
      debugPrint('');

      if (todayWorkers.isEmpty) {
        debugPrint('⚠️  해당 날짜에 근무하는 확정 인원이 없습니다.');
        return;
      }

      int checkedInCount = 0;
      int checkedOutCount = 0;

      for (var appDoc in todayWorkers) {
        final appData = appDoc.data();
        final appId = appDoc.id;
        final uid = appData['uid'] as String?;
        final startTime = appData['startTime'] as String?;
        final endTime = appData['endTime'] as String?;

        // 필수 필드 누락 시 스킵
        if (uid == null || startTime == null || endTime == null ||
            !startTime.contains(':') || !endTime.contains(':')) {
          debugPrint('  ⚠️ $appId - startTime/endTime 누락, 스킵');
          continue;
        }

        // 70% 확률로 출근 (30% 스킵)
        if (_random.nextDouble() < 0.3) continue;

        // 출근 시간 생성 (±10분 오프셋, 0~59분 범위 클램프)
        final startParts = startTime.split(':');
        final startHour = int.parse(startParts[0]);
        final startMinute = int.parse(startParts[1]);

        final checkInTime = DateTime(
          date.year,
          date.month,
          date.day,
          startHour,
          (startMinute + _random.nextInt(21) - 10).clamp(0, 59),
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
            (endMinute + _random.nextInt(21) - 10).clamp(0, 59),
          );
          checkedOutCount++;
        }

        // GPS 좌표 (랜덤)
        final latitude = 37.5 + _random.nextDouble() * 0.1;
        final longitude = 127.0 + _random.nextDouble() * 0.1;

        // Firestore 저장
        // 출근 시간 문자열 포맷
        final checkInStr = '${checkInTime.hour.toString().padLeft(2, '0')}:${checkInTime.minute.toString().padLeft(2, '0')}:00';
        final checkOutStr = checkOutTime != null 
            ? '${checkOutTime.hour.toString().padLeft(2, '0')}:${checkOutTime.minute.toString().padLeft(2, '0')}:00'
            : null;
        
        await _firestore.collection('attendance').add({
          'applicationId': appId,
          'userId': uid,                                    // ✅ uid → userId
          'businessId': businessId,
          'businessName': appData['businessName'] ?? '',    // ✅ 추가
          'workDate': Timestamp.fromDate(dateStart),        // ✅ date → workDate
          'workType': appData['selectedWorkType'] ?? '',    // ✅ 추가
          'checkIn': checkInStr,                            // ✅ 문자열 형식
          'checkInTime': Timestamp.fromDate(checkInTime),
          'checkInLat': latitude,                           // ✅ checkInLatitude → checkInLat
          'checkInLng': longitude,                          // ✅ checkInLongitude → checkInLng
          'checkInMethod': 'manual',                        // ✅ 추가
          'checkOut': checkOutStr,                          // ✅ 문자열 형식
          'checkOutTime': checkOutTime != null 
              ? Timestamp.fromDate(checkOutTime) 
              : null,
          'checkOutLat': checkOutTime != null ? latitude : null,   // ✅ 수정
          'checkOutLng': checkOutTime != null ? longitude : null,  // ✅ 수정
          'checkOutMethod': checkOutTime != null ? 'manual' : null, // ✅ 추가
          'status': 'present',                              // ✅ 추가
          'isModified': false,                              // ✅ 추가
          'modifyRequested': false,                         // ✅ 추가
          'wageStatus': 'pending',                          // ✅ 추가
          'createdAt': FieldValue.serverTimestamp(),        // ✅ 추가
          'isDummy': true,
        });

        checkedInCount++;
      }

      debugPrint('');
      debugPrint('🎉 ═══════════════════════════════════════');
      debugPrint('🎉 더미 출근 데이터 생성 완료!');
      debugPrint('🎉 ═══════════════════════════════════════');
      debugPrint('   출근 완료: $checkedInCount명');
      debugPrint('   퇴근 완료: $checkedOutCount명');
      debugPrint('   미출근: ${todayWorkers.length - checkedInCount}명');
      debugPrint('');
      // ✅ 캐시 클리어
      _firestoreService.clearCache();
      debugPrint('🗑️ 캐시 클리어 완료');
    } catch (e, stackTrace) {
      debugPrint('');
      debugPrint('❌ ═══════════════════════════════════════');
      debugPrint('❌ 더미 출근 데이터 생성 실패!');
      debugPrint('❌ ═══════════════════════════════════════');
      debugPrint('에러: $e');
      debugPrint('스택 트레이스: $stackTrace');
      debugPrint('');
      rethrow;
    }
  }

  /// 모든 더미 데이터 삭제
  static Future<void> clearAllDummyData() async {
    debugPrint('');
    debugPrint('🗑️ ═══════════════════════════════════════');
    debugPrint('🗑️ 더미 데이터 삭제 시작...');
    debugPrint('🗑️ ═══════════════════════════════════════');
    debugPrint('');

    try {
      int totalDeleted = 0;
      Set<String> affectedTOIds = {};
      final Map<String, Set<String>> affectedSlots = {}; // toId → Set<slotId>

      // 1. 더미 지원자 삭제
      debugPrint('📋 1단계: 더미 지원자(users) 삭제 중...');

      // users list 규칙: BUSINESS_ADMIN은 limit <= 30 필수
      final dummyUsersSnapshot = await _firestore
          .collection('users')
          .where('isDummy', isEqualTo: true)
          .limit(30)
          .get();
      final dummyUsers = dummyUsersSnapshot.docs;

      debugPrint('   더미 users: ${dummyUsers.length}개');

      if (dummyUsers.isNotEmpty) {
        for (int i = 0; i < dummyUsers.length; i += 500) {
          final batch = _firestore.batch();
          final chunk = dummyUsers.skip(i).take(500);
          
          for (var doc in chunk) {
            batch.delete(doc.reference);
          }
          
          await batch.commit();
        }
        debugPrint('✅ 더미 지원자 ${dummyUsers.length}명 삭제 완료');
        totalDeleted += dummyUsers.length;
      } else {
        debugPrint('   ℹ️  삭제할 더미 users 없음');
      }

      debugPrint('');

      // 2. 더미 지원서 삭제
      debugPrint('📋 2단계: 더미 지원서(applications) 삭제 중...');

      final dummyAppsSnapshot = await _firestore
          .collection('applications')
          .where('isDummy', isEqualTo: true)
          .get();
      final dummyApps = dummyAppsSnapshot.docs;

      debugPrint('   더미 applications: ${dummyApps.length}개');

      if (dummyApps.isNotEmpty) {
        for (int i = 0; i < dummyApps.length; i += 500) {
          final batch = _firestore.batch();
          final chunk = dummyApps.skip(i).take(500);
          
          for (var doc in chunk) {
            final data = doc.data();
            final toId = data['toId'] as String?;
            final slotId = data['slotId'] as String?;
            if (toId != null) {
              affectedTOIds.add(toId);
              if (slotId != null) {
                affectedSlots.putIfAbsent(toId, () => {}).add(slotId);
              }
            }
            batch.delete(doc.reference);
          }
          
          await batch.commit();
        }
        debugPrint('✅ 더미 지원서 ${dummyApps.length}개 삭제 완료');
        totalDeleted += dummyApps.length;
      } else {
        debugPrint('   ℹ️  삭제할 더미 applications 없음');
      }

      debugPrint('');

      // 3. 더미 출근 데이터 삭제
      await clearDummyAttendance();

      // 4. 더미 위치 추적 데이터 삭제 (worker_locations)
      debugPrint('📋 4단계: 더미 위치 데이터(worker_locations) 삭제 중...');
      try {
        // worker_locations는 applicationId를 문서 ID로 사용
        // isDummy 마커가 없으므로 더미 applicationId 기반으로 삭제
        final dummyAppIds = dummyApps.map((d) => d.id).toList();
        for (int i = 0; i < dummyAppIds.length; i += 500) {
          final batch = _firestore.batch();
          final chunk = dummyAppIds.skip(i).take(500);
          for (final appId in chunk) {
            batch.delete(_firestore.collection('worker_locations').doc(appId));
          }
          await batch.commit();
        }
        debugPrint('✅ 더미 위치 데이터 삭제 완료');
      } catch (e) {
        debugPrint('⚠️ 위치 데이터 삭제 실패 (무시): $e');
      }

      // 5. 더미 리뷰 삭제
      await clearDummyReviews();

      // 6. ✅ 모든 TO 통계 재계산
      debugPrint('');
      debugPrint('📊 5단계: TO 통계 재계산 중...');
      
      final allTOsSnapshot = await _firestore.collection('tos').limit(500).get();

      // 병렬로 TO 통계 재계산 + 영향받은 groupId 수집
      final groupIdResults = await Future.wait(
        allTOsSnapshot.docs.map((toDoc) async {
          final toId = toDoc.id;
          await _firestoreService.recalculateTOStats(toId);
          final groupId = toDoc.data()['groupId'] as String?;
          if (groupId != null) {
            await _firestoreService.syncGroupMasterStats(toId);
          }
          return groupId;
        }),
      );
      final recalculatedCount = allTOsSnapshot.docs.length;
      final affectedGroupIds = groupIdResults.whereType<String>().toSet();

      debugPrint('✅ $recalculatedCount개 TO 통계 재계산 완료');

      // 병렬로 groups 컬렉션 통계 재계산
      debugPrint('📊 6단계: groups 컬렉션 통계 재계산 중...');
      await Future.wait(
        affectedGroupIds.map((groupId) => _firestoreService.syncGroupStats(groupId)),
      );
      debugPrint('✅ ${affectedGroupIds.length}개 그룹 통계 재계산 완료');

      // 7. 슬롯 통계 재계산 (확정 인원 초과로 status='full'인 슬롯 복구)
      if (affectedSlots.isNotEmpty) {
        debugPrint('');
        debugPrint('📊 7단계: 슬롯 통계 재계산 중...');
        int slotCount = 0;
        for (final entry in affectedSlots.entries) {
          for (final slotId in entry.value) {
            await _recalculateSlotStats(entry.key, slotId);
            slotCount++;
          }
        }
        debugPrint('✅ $slotCount개 슬롯 통계 재계산 완료');
      }

      debugPrint('');
      debugPrint('🎉 ═══════════════════════════════════════');
      debugPrint('🎉 모든 더미 데이터 삭제 완료!');
      debugPrint('🎉 ═══════════════════════════════════════');
      debugPrint('   📊 총 $totalDeleted개 항목 삭제됨');
      debugPrint('   📊 $recalculatedCount개 TO 통계 재계산됨');
      debugPrint('   📊 ${affectedGroupIds.length}개 그룹 통계 재계산됨');
      debugPrint('');
      // ✅ 캐시 클리어
      _firestoreService.clearCache();
      debugPrint('🗑️ 캐시 클리어 완료');
      
    } catch (e, stackTrace) {
      debugPrint('');
      debugPrint('❌ ═══════════════════════════════════════');
      debugPrint('❌ 더미 데이터 삭제 실패!');
      debugPrint('❌ ═══════════════════════════════════════');
      debugPrint('에러: $e');
      debugPrint('스택 트레이스: $stackTrace');
      debugPrint('');
      rethrow;
    }
  }

  /// 더미 출근 데이터 삭제
  static Future<void> clearDummyAttendance() async {
    debugPrint('📋 3단계: 더미 출근 데이터(attendance) 삭제 중...');

    try {
      final dummyAttendanceSnapshot = await _firestore
          .collection('attendance')
          .where('isDummy', isEqualTo: true)
          .get();
      final dummyAttendance = dummyAttendanceSnapshot.docs;

      debugPrint('   더미 attendance: ${dummyAttendance.length}개');

      if (dummyAttendance.isNotEmpty) {
        for (int i = 0; i < dummyAttendance.length; i += 500) {
          final batch = _firestore.batch();
          final chunk = dummyAttendance.skip(i).take(500);

          for (var doc in chunk) {
            batch.delete(doc.reference);
          }

          await batch.commit();
        }
        debugPrint('✅ 더미 출근 데이터 ${dummyAttendance.length}개 삭제 완료');
      } else {
        debugPrint('   ℹ️  삭제할 더미 attendance 없음');
      }
      // ✅ 캐시 클리어
      _firestoreService.clearCache();
    } catch (e) {
      debugPrint('❌ 더미 출근 데이터 삭제 실패: $e');
      rethrow;
    }
  }
  // ━━━ 리뷰 코멘트 템플릿 ━━━
  static final List<String> _reviewComments = [
    '성실하게 일해주셨습니다.',
    '시간 약속을 잘 지켜요.',
    '업무 이해도가 높아요.',
    '다음에도 같이 일하고 싶어요.',
    '꼼꼼하게 작업해주셨습니다.',
    '적극적으로 일해주셨어요.',
    '다른 분들과 협력을 잘 해요.',
    '빠르고 정확하게 처리해요.',
    '친절하고 예의 바릅니다.',
    '책임감이 강해요.',
    '조금 늦게 오셨지만 열심히 일해주셨어요.',
    '업무 속도가 조금 느린 편이에요.',
    '기본적인 업무는 잘 수행해요.',
  ];

  /// ⭐ 더미 리뷰 생성 (더미 사용자 대상 - 전체)
  static Future<void> createDummyReviews({
    required String businessId,
    required String businessName,
    required String reviewerId,
    required String reviewerName,
  }) async {
    debugPrint('');
    debugPrint('⭐ ═══════════════════════════════════════');
    debugPrint('⭐ 더미 리뷰 생성 시작 (모든 더미 사용자 대상)...');
    debugPrint('⭐ ═══════════════════════════════════════');
    debugPrint('');

    try {
      // 1. 더미 사용자 조회 — isDummy 필터로 직접 쿼리 (orderBy 인덱스 불필요)
      final usersSnapshot = await _firestore
          .collection('users')
          .where('isDummy', isEqualTo: true)
          .get();

      final dummyUsers = usersSnapshot.docs.toList();

      if (dummyUsers.isEmpty) {
        debugPrint('⚠️ 더미 사용자가 없습니다. 먼저 더미 지원자를 생성해주세요.');
        return;
      }

      debugPrint('📋 더미 사용자 ${dummyUsers.length}명 발견 (전체 대상)');

      int createdCount = 0;
      final now = DateTime.now();

      // 이미 리뷰가 있는 더미 사용자 ID를 한 번에 조회 (N+1 쿼리 방지)
      final existingReviewsSnap = await _firestore
          .collection('reviews')
          .where('businessId', isEqualTo: businessId)
          .where('isDummy', isEqualTo: true)
          .get();
      final alreadyReviewedUids = existingReviewsSnap.docs
          .map((d) => d.data()['targetUserId'] as String?)
          .whereType<String>()
          .toSet();

      for (var userDoc in dummyUsers) {
        final uid = userDoc.id;
        final userData = userDoc.data();

        if (alreadyReviewedUids.contains(uid)) {
          debugPrint('  ⏭️ $uid - 이미 리뷰 존재, 스킵');
          continue;
        }

        // 랜덤 업무 유형
        final workType = _allWorkTypes[_random.nextInt(_allWorkTypes.length)];
        
        // 랜덤 근무일 (최근 30일 내)
        final daysAgo = _random.nextInt(30);
        final workDate = now.subtract(Duration(days: daysAgo));

        // 랜덤 평점 (3~5점 70%, 3점 20%, 1~2점 10%)
        int rating;
        final ratingRandom = _random.nextDouble();
        if (ratingRandom < 0.1) {
          rating = _random.nextInt(2) + 1;  // 1~2점 (10%)
        } else if (ratingRandom < 0.3) {
          rating = 3;  // 3점 (20%)
        } else {
          rating = _random.nextInt(2) + 4;  // 4~5점 (70%)
        }

        // 랜덤 코멘트 (80% 확률)
        String? comment;
        if (_random.nextDouble() < 0.8) {
          comment = _reviewComments[_random.nextInt(_reviewComments.length)];
        }

        // 재고용 의사 (평점에 따라)
        final wouldRehire = rating >= 3;

        // 리뷰 직접 생성 (Firestore에 직접 추가)
        await _firestore.collection('reviews').add({
          'applicationId': 'dummy_app_${uid}_${now.millisecondsSinceEpoch}',
          'reviewerId': reviewerId,
          'reviewerName': reviewerName,
          'targetUserId': uid,
          'businessId': businessId,
          'businessName': businessName,
          'workType': workType,
          'workDate': Timestamp.fromDate(workDate),
          'rating': rating,
          'comment': comment,
          'wouldRehire': wouldRehire,
          'createdAt': FieldValue.serverTimestamp(),
          'isDummy': true,  // ⭐ 더미 표시 추가
        });

        // 사용자 평점 통계 업데이트
        await _updateUserReviewStats(uid);

        createdCount++;
        final userName = userData['name'] ?? uid;
        debugPrint('  ⭐ $userName → $rating점 ${comment != null ? '(코멘트 있음)' : ''}');
      }

      debugPrint('');
      debugPrint('🎉 ═══════════════════════════════════════');
      debugPrint('🎉 더미 리뷰 $createdCount개 생성 완료!');
      debugPrint('🎉 ═══════════════════════════════════════');
      debugPrint('');
      // ✅ 캐시 클리어
      _firestoreService.clearCache();
      debugPrint('🗑️ 캐시 클리어 완료');
    } catch (e) {
      debugPrint('❌ 더미 리뷰 생성 실패: $e');
    }
  }

  /// 사용자 리뷰 통계 업데이트 (내부용)
  static Future<void> _updateUserReviewStats(String userId) async {
    try {
      final reviews = await _firestore
          .collection('reviews')
          .where('targetUserId', isEqualTo: userId)
          .get();
      
      if (reviews.docs.isEmpty) return;
      
      double totalRating = 0;
      for (var doc in reviews.docs) {
        totalRating += ((doc.data()['rating'] ?? 0) as num).toDouble();
      }
      
      final avgRating = totalRating / reviews.docs.length;
      
      await _firestore.collection('users').doc(userId).update({
        'averageRating': avgRating,
        'reviewCount': reviews.docs.length,
      });
    } catch (e) {
      debugPrint('⚠️ 사용자 리뷰 통계 업데이트 실패: $e');
    }
  }
  /// 더미 리뷰 삭제
  static Future<void> clearDummyReviews() async {
    debugPrint('📋 더미 리뷰(reviews) 삭제 중...');

    try {
      final reviewsSnapshot = await _firestore
          .collection('reviews')
          .where('isDummy', isEqualTo: true)
          .get();

      final toDelete = reviewsSnapshot.docs.where((doc) {
        final data = doc.data();
        final targetUserId = data['targetUserId'] as String?;
        return data['isDummy'] == true ||
            (targetUserId != null && targetUserId.startsWith('dummy_user_'));
      }).toList();

      debugPrint('   더미 reviews: ${toDelete.length}개');

      for (int i = 0; i < toDelete.length; i += 500) {
        final batch = _firestore.batch();
        for (var doc in toDelete.skip(i).take(500)) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }

      debugPrint('✅ 더미 리뷰 ${toDelete.length}개 삭제 완료');
    } catch (e) {
      debugPrint('⚠️ 더미 리뷰 삭제 실패: $e');
    }
  }

  /// 슬롯 통계 재계산 — 남은 실제 applications 기반으로 pendingCount/confirmedCount/status 초기화
  static Future<void> _recalculateSlotStats(String toId, String slotId) async {
    try {
      // 남은 applications 집계 (더미 삭제 후 실 데이터만 남음)
      final appsSnap = await _firestore
          .collection('applications')
          .where('toId', isEqualTo: toId)
          .where('slotId', isEqualTo: slotId)
          .get(const GetOptions(source: Source.server));

      int pendingCount = 0;
      int confirmedCount = 0;
      final Map<String, int> wtPending = {};
      final Map<String, int> wtConfirmed = {};

      for (final doc in appsSnap.docs) {
        final d = doc.data();
        final status = d['status'] as String? ?? '';
        final wt = d['selectedWorkType'] as String? ?? '';
        if (status == 'PENDING') {
          pendingCount++;
          wtPending[wt] = (wtPending[wt] ?? 0) + 1;
        } else if (status == 'CONFIRMED' || status == 'CONTRACT_PENDING') {
          confirmedCount++;
          wtConfirmed[wt] = (wtConfirmed[wt] ?? 0) + 1;
        }
      }

      // 슬롯 현재 데이터 (requiredCount, isManualClosed)
      final slotDoc = await _firestore
          .collection('tos').doc(toId)
          .collection('slots').doc(slotId)
          .get();
      if (!slotDoc.exists) return;

      final slotData = slotDoc.data()!;
      final isManualClosed = slotData['isManualClosed'] as bool? ?? false;
      final workDetails = slotData['workDetails'] as List? ?? [];
      final slotRequired = workDetails.fold<int>(
        0,
        (acc, wd) => acc + (((wd as Map<String, dynamic>)['requiredCount'] as num?)?.toInt() ?? 0),
      );

      final update = <String, dynamic>{
        'pendingCount': pendingCount,
        'confirmedCount': confirmedCount,
      };
      if (!isManualClosed) {
        update['status'] = (slotRequired > 0 && confirmedCount >= slotRequired) ? 'full' : 'open';
      }
      // workTypeCounts 재계산
      final allWts = {...wtPending.keys, ...wtConfirmed.keys};
      for (final wt in allWts) {
        update['workTypeCounts.$wt.pendingCount'] = wtPending[wt] ?? 0;
        update['workTypeCounts.$wt.confirmedCount'] = wtConfirmed[wt] ?? 0;
      }

      await _firestore
          .collection('tos').doc(toId)
          .collection('slots').doc(slotId)
          .update(update);

      debugPrint('   ✅ 슬롯 재계산: $slotId → 대기$pendingCount 확정$confirmedCount ${update['status']}');
    } catch (e) {
      debugPrint('   ⚠️ 슬롯 재계산 실패 ($slotId): $e');
    }
  }
}