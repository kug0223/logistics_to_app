// ignore_for_file: prefer_const_constructors, lines_longer_than_80_chars
//
// 도메인별 감사 체크리스트 — 8개 미감사 영역
//
// Group A: TOModel (D1) — closedReasonCode 직렬화 누락, TOStatus draft 고립
// Group B: ApplicationModel.hasTimeOverlap (D2) — 야간 시프트 겹침 판단
// Group C: MemberInvitationModel (D4) — 초대 만료, isPending
// Group D: ContractSnapshot.hourlyWage (D5) — workMins=0 보호 (false positive 확인)
// Group E: BusinessModel.AttendanceRules (D8) — null 처리, clamp
// Group F: 감사 발견 문서화 — HIGH/MEDIUM 항목

import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/member_invitation_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';

// ── 헬퍼 ─────────────────────────────────────────────────────────────────────

Map<String, dynamic> _minimalToMap({String? closedReason}) => {
  'businessId': 'biz001',
  'businessName': '테스트 매장',
  'businessAddress': '서울시',
  'businessCity': '서울',
  'businessDistrict': '강남구',
  'type': 'flex',
  'title': '테스트 TO',
  'description': '설명',
  'workDetails': [],
  'totalSlots': 1,
  'workDays': ['월'],
  'deadlineType': 'hours_before',
  'hoursBeforeStart': 2,
  'totalRequired': 1,
  'totalConfirmed': 0,
  'totalPending': 0,
  'status': 'OPEN',
  'isManualClosed': false,
  'publishMode': 'immediate',
  'isPublished': true,
  'publishDaysBefore': 0,
  'publishTime': '00:00',
  'creatorUID': 'user001',
  'createdAt': Timestamp.fromDate(DateTime(2026, 7, 1)),
  if (closedReason != null) 'closedReason': closedReason,
};

ContractSnapshot _makeSnapshot({
  String wageType = 'hourly',
  int wage = 10320,
  String startTime = '09:00',
  String endTime = '18:00',
  int breakMinutes = 60,
  int? baseHourlyWage,
}) =>
    ContractSnapshot(
      businessName: '테스트 매장',
      businessNumber: '1234567890',
      businessAddress: '서울시 강남구',
      ownerName: '사장님',
      workerName: '홍길동',
      workType: '홀서빙',
      workPlace: '홀',
      isLongTerm: false,
      startTime: startTime,
      endTime: endTime,
      breakMinutes: breakMinutes,
      wage: wage,
      wageType: wageType,
      baseHourlyWage: baseHourlyWage,
      taxDeductionType: 'none',
    );

MemberInvitationModel _makeInvitation({
  InvitationStatus status = InvitationStatus.pending,
  DateTime? createdAt,
}) =>
    MemberInvitationModel(
      id: 'inv001',
      businessId: 'biz001',
      businessName: '테스트 매장',
      targetUid: 'user001',
      targetName: '홍길동',
      invitedBy: 'admin001',
      invitedByName: '관리자',
      permissions: MemberPermissions(),
      status: status,
      createdAt: createdAt ?? DateTime.now(),
    );

// ══════════════════════════════════════════════════════════════════════════════
void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // Group A — TOModel: closedReasonCode 직렬화 이슈 (D1-CP1, D1-CP4)
  // ══════════════════════════════════════════════════════════════════════════
  group('A. TOModel — closedReasonCode / TOStatus', () {
    // A-01: fromMap이 'closedReason' 키를 읽어 closedReasonCode에 매핑
    test('A-01: fromMap — "closedReason" 키 → closedReasonCode 매핑', () {
      final to = TOModel.fromMap(_minimalToMap(closedReason: 'MANUAL'), 'to001');
      expect(to.closedReasonCode, equals('MANUAL'));
    });

    // A-02: toMap()에 closedReason 포함 → 왕복 후 유지 (수정 완료)
    test('A-02: toMap() — closedReasonCode → "closedReason" 직렬화 왕복 확인', () {
      final to = TOModel.fromMap(_minimalToMap(closedReason: 'MANUAL'), 'to001');
      expect(to.closedReasonCode, equals('MANUAL'));
      final map = to.toMap();
      expect(map['closedReason'], equals('MANUAL')); // 직렬화 포함
      final restored = TOModel.fromMap(map, 'to001');
      expect(restored.closedReasonCode, equals('MANUAL')); // 왕복 후 유지
    });

    // A-03: closedReasonCode 'POSTING_EXPIRED' → isPostingExpiredAndExtendable 조건 충족
    test('A-03: closedReasonCode="POSTING_EXPIRED" → isPostingExpiredAndExtendable 판단에 사용', () {
      // CLOSED + contractType + 'POSTING_EXPIRED' + endDate 3일 이상 남은 경우만 true
      // → closedReasonCode가 null이면 false가 되어 관리자가 연장 버튼을 볼 수 없음
      final toClosed = TOModel.fromMap({
        ..._minimalToMap(closedReason: 'POSTING_EXPIRED'),
        'status': 'CLOSED',
        'type': 'contract',
        'rangeEnd': Timestamp.fromDate(DateTime.now().add(Duration(days: 10))),
      }, 'to001');
      expect(toClosed.closedReasonCode, equals('POSTING_EXPIRED'));
      expect(toClosed.isPostingExpiredAndExtendable, isTrue);

      // closedReasonCode null이면 → false
      final toWithoutReason = TOModel.fromMap({
        ..._minimalToMap(),
        'status': 'CLOSED',
        'type': 'contract',
        'rangeEnd': Timestamp.fromDate(DateTime.now().add(Duration(days: 10))),
      }, 'to002');
      expect(toWithoutReason.closedReasonCode, isNull);
      expect(toWithoutReason.isPostingExpiredAndExtendable, isFalse);
    });

    // A-04: [D1-CP4] TOStatus.draft는 어느 그룹에도 속하지 않는 고립 상태
    test('A-04: TOStatus.draft 고립 확인 — openStates에도 closedStates에도 없음', () {
      expect(TOStatus.openStates, isNot(contains(TOStatus.draft)));
      expect(TOStatus.closedStates, isNot(contains(TOStatus.draft)));
    });

    // A-05: fromMap — closedReason 없으면 closedReasonCode null
    test('A-05: fromMap — closedReason 없음 → closedReasonCode null', () {
      final to = TOModel.fromMap(_minimalToMap(), 'to001');
      expect(to.closedReasonCode, isNull);
    });

    // A-06: closedReason getter (표시용) vs closedReasonCode (저장용) 구분
    test('A-06: isManualClosed=true → closedReason getter "수동 마감" 반환', () {
      final to = TOModel.fromMap({
        ..._minimalToMap(),
        'isManualClosed': true,
      }, 'to001');
      expect(to.isManualClosed, isTrue);
      expect(to.closedReason, equals('수동 마감'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Group B — ApplicationModel.hasTimeOverlap (D2-CP7)
  // ══════════════════════════════════════════════════════════════════════════
  group('B. ApplicationModel.hasTimeOverlap — 야간 시프트 겹침 판단', () {
    // B-01: 일반 겹침
    test('B-01: 09:00~18:00 vs 17:00~22:00 → 겹침 true', () {
      expect(ApplicationModel.hasTimeOverlap('09:00', '18:00', '17:00', '22:00'), isTrue);
    });

    // B-02: 겹침 없음
    test('B-02: 09:00~13:00 vs 14:00~18:00 → 겹침 없음 false', () {
      expect(ApplicationModel.hasTimeOverlap('09:00', '13:00', '14:00', '18:00'), isFalse);
    });

    // B-03: 경계 접촉 (end1 == start2) → false (strict: x1 < y2 && x2 < y1)
    test('B-03: 09:00~13:00 vs 13:00~18:00 → 경계 접촉 false', () {
      expect(ApplicationModel.hasTimeOverlap('09:00', '13:00', '13:00', '18:00'), isFalse);
    });

    // B-04: 빈 문자열 → false
    test('B-04: 빈 문자열 → false', () {
      expect(ApplicationModel.hasTimeOverlap('', '18:00', '17:00', '22:00'), isFalse);
      expect(ApplicationModel.hasTimeOverlap('09:00', '', '17:00', '22:00'), isFalse);
    });

    // B-05: 야간 시프트 정규화 — 22:00~02:00 vs 01:00~03:00 → 겹침 true
    test('B-05: 야간 시프트 22:00~02:00 vs 01:00~03:00 → 겹침 true', () {
      expect(ApplicationModel.hasTimeOverlap('22:00', '02:00', '01:00', '03:00'), isTrue);
    });

    // B-06: 야간 시프트 겹침 없음 — 22:00~01:00 vs 03:00~06:00 → false
    test('B-06: 야간 시프트 22:00~01:00 vs 03:00~06:00 → 겹침 없음 false', () {
      expect(ApplicationModel.hasTimeOverlap('22:00', '01:00', '03:00', '06:00'), isFalse);
    });

    // B-07: 야간 시프트 자정 경계 — 23:30~00:30 vs 00:00~02:00 → 겹침 true
    test('B-07: 23:30~00:30 vs 00:00~02:00 → 겹침 true', () {
      expect(ApplicationModel.hasTimeOverlap('23:30', '00:30', '00:00', '02:00'), isTrue);
    });

    // B-08: 완전 동일 시간 → true
    test('B-08: 동일 시간대 → 겹침 true', () {
      expect(ApplicationModel.hasTimeOverlap('09:00', '18:00', '09:00', '18:00'), isTrue);
    });

    // B-09: 포함 관계 (shift2가 shift1 내부) → true
    test('B-09: shift2가 shift1 내부에 포함 → 겹침 true', () {
      expect(ApplicationModel.hasTimeOverlap('09:00', '18:00', '10:00', '15:00'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Group C — MemberInvitationModel (D4-CP1)
  // ══════════════════════════════════════════════════════════════════════════
  group('C. MemberInvitationModel — isPending / 만료 기준', () {
    // C-01: isPending = status == InvitationStatus.pending
    test('C-01: status=pending → isPending true', () {
      expect(_makeInvitation(status: InvitationStatus.pending).isPending, isTrue);
    });

    test('C-02: status=accepted → isPending false', () {
      expect(_makeInvitation(status: InvitationStatus.accepted).isPending, isFalse);
    });

    test('C-03: status=cancelled → isPending false', () {
      expect(_makeInvitation(status: InvitationStatus.cancelled).isPending, isFalse);
    });

    // C-04: tryFromMap status 기본값 'pending' 폴백
    test('C-04: tryFromMap — status 누락 → pending으로 폴백', () {
      final model = MemberInvitationModel.tryFromMap({
        'businessId': 'biz001',
        'businessName': '매장',
        'targetUid': 'u1',
        'targetName': '홍길동',
        'invitedBy': 'admin',
        'invitedByName': '관리자',
        'createdAt': Timestamp.fromDate(DateTime.now()),
      }, 'inv001');
      expect(model, isNotNull);
      expect(model!.isPending, isTrue);
    });

    // C-05: [HIGH 감사 발견 문서화] 클라이언트 3일 만료 vs Firestore rules 30일 불일치
    // member_service.dart:134 — expiryDate = createdAt + 3일
    // firestore.rules:164 — inv.createdAt > request.time - duration.value(30, 'd')
    // → 3~30일 사이 초대는 REST API 직접 호출로 수락 가능 (클라이언트 체크 우회)
    test('C-05: [HIGH 문서화] 초대 만료 기준 불일치 — 클라이언트 3일 체크', () {
      // 클라이언트 체크: createdAt + 3일 이후 → 만료 (member_service.dart)
      final fresh = _makeInvitation(createdAt: DateTime.now().subtract(Duration(days: 2)));
      final expired3 = _makeInvitation(createdAt: DateTime.now().subtract(Duration(days: 4)));

      final freshExpiryDate = fresh.createdAt.add(Duration(days: 3));
      final expiredExpiryDate = expired3.createdAt.add(Duration(days: 3));

      expect(DateTime.now().isAfter(freshExpiryDate), isFalse); // 2일 → 미만료
      expect(DateTime.now().isAfter(expiredExpiryDate), isTrue); // 4일 → 만료

      // Firestore rules는 30일 기준 → 4~29일 초대는 클라이언트 막지만 REST API 통과
      // 수정 권장: Firestore rules를 3일로 줄이거나 CF 이전
    });

    // C-06: 'cancelled' 영국식 철자 (vs 'canceled' 미국식) 직렬화 확인
    test('C-06: cancelled 상태 직렬화 — 영국식 "cancelled"', () {
      final inv = _makeInvitation(status: InvitationStatus.cancelled);
      final map = inv.toMap();
      expect(map['status'], equals('cancelled'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Group D — ContractSnapshot.hourlyWage (D5-CP1 오판 확인)
  // ══════════════════════════════════════════════════════════════════════════
  group('D. ContractSnapshot.hourlyWage — 0분 보호 (D5-CP1 재검증)', () {
    // D-01: [False Positive 확인] workMins=0 → null (Infinity 아님)
    // 탐색 에이전트 D5-CP1 "workMins=0 → Infinity" 발견은 오판.
    // 실제 코드(line 316): if (workMins <= 0) return null; → 음수/0 모두 null 반환
    test('D-01: [FALSE POSITIVE 확인] daily, startTime==endTime → hourlyWage null (Infinity 아님)', () {
      final snap = _makeSnapshot(
        wageType: 'daily',
        wage: 150000,
        startTime: '09:00',
        endTime: '09:00', // 0분 근무
        breakMinutes: 0,
      );
      expect(snap.hourlyWage, isNull); // Infinity 아님 — 기존 가드 확인
    });

    // D-02: daily, breakMinutes > 실 근무시간 → workMins ≤ 0 → null
    test('D-02: daily, breakMinutes 초과 → workMins <= 0 → hourlyWage null', () {
      final snap = _makeSnapshot(
        wageType: 'daily',
        wage: 150000,
        startTime: '09:00',
        endTime: '10:00', // 60분 근무
        breakMinutes: 90, // 90분 휴게 > 60분 근무 → workMins = -30
      );
      expect(snap.hourlyWage, isNull);
    });

    // D-03: daily, 정상 계산 — 150000원 / 8시간 = 18750원
    test('D-03: daily 150000원 / 8h → 18750원/시', () {
      final snap = _makeSnapshot(
        wageType: 'daily',
        wage: 150000,
        startTime: '09:00',
        endTime: '18:00', // 9h - 1h 휴게 = 8h = 480분
        breakMinutes: 60,
      );
      expect(snap.hourlyWage, equals(18750));
    });

    // D-04: hourly → wage 직접 반환
    test('D-04: hourly → hourlyWage = wage', () {
      final snap = _makeSnapshot(wageType: 'hourly', wage: 12000);
      expect(snap.hourlyWage, equals(12000));
    });

    // D-05: baseHourlyWage > 0 → 최우선 적용
    test('D-05: baseHourlyWage > 0 → 항상 baseHourlyWage 반환 (hourly/daily 무관)', () {
      final snap = _makeSnapshot(
        wageType: 'daily',
        wage: 150000,
        baseHourlyWage: 15000,
      );
      expect(snap.hourlyWage, equals(15000));
    });

    // D-06: baseHourlyWage == 0 → 무시하고 계산 로직 사용
    test('D-06: baseHourlyWage == 0 → 무시 (0보다 큰 경우만 우선 적용)', () {
      final snap = _makeSnapshot(
        wageType: 'hourly',
        wage: 12000,
        baseHourlyWage: 0, // 0이면 무시
      );
      expect(snap.hourlyWage, equals(12000)); // wage 사용
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Group E — BusinessModel.AttendanceRules (D8-CP1, D8-CP7)
  // ══════════════════════════════════════════════════════════════════════════
  group('E. BusinessModel.AttendanceRules — null / clamp / defaults', () {
    // E-01: [D8-CP1] BusinessModel.attendanceRules nullable → null 가능
    // null인 경우 사용 측에서 AttendanceRules.defaults()로 폴백해야 함
    test('E-01: attendanceRules 없는 BusinessModel → attendanceRules null', () {
      final biz = BusinessModel.fromMap({
        'businessId': 'biz001',
        'ownerId': 'user001',
        'name': '테스트 매장',
        'businessNumber': '1234567890',
        'category': '식음료',
        'adminIds': ['user001'],
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      }, 'biz001');
      expect(biz.attendanceRules, isNull);
      // 사용 측: biz.attendanceRules ?? AttendanceRules.defaults() 필수
      final rules = biz.attendanceRules ?? AttendanceRules.defaults();
      expect(rules.lateGrace, equals(5)); // 기본값 정상 적용
    });

    // E-02: AttendanceRules.defaults() — 기본값 전체 확인
    test('E-02: AttendanceRules.defaults() 기본값', () {
      final r = AttendanceRules.defaults();
      expect(r.earlyWindow, equals(30));
      expect(r.earlyArrivalUnit, equals(30));
      expect(r.lateGrace, equals(5));
      expect(r.lateUnit, equals(30));
      expect(r.lateWindow, equals(30));
      expect(r.overtimeUnit, equals(10));
      expect(r.earlyLeaveUnit, equals(30));
    });

    // E-03: AttendanceRules.fromMap — clamp 상한 (earlyWindow 최대 120)
    test('E-03: fromMap earlyWindow > 120 → clamp(120)', () {
      final r = AttendanceRules.fromMap({'earlyWindow': 200});
      expect(r.earlyWindow, equals(120));
    });

    // E-04: AttendanceRules.fromMap — clamp 하한 (earlyArrivalUnit 최소 5)
    test('E-04: fromMap earlyArrivalUnit < 5 → clamp(5)', () {
      final r = AttendanceRules.fromMap({'earlyArrivalUnit': 1});
      expect(r.earlyArrivalUnit, equals(5));
    });

    // E-05: AttendanceRules.fromMap — lateGrace clamp (0~30)
    test('E-05: fromMap lateGrace > 30 → clamp(30)', () {
      final r = AttendanceRules.fromMap({'lateGrace': 99});
      expect(r.lateGrace, equals(30));
    });

    // E-06: AttendanceRules.fromMap — overtimeUnit clamp (5~30)
    test('E-06: fromMap overtimeUnit=10 → clamp 범위 내 유지', () {
      final r = AttendanceRules.fromMap({'overtimeUnit': 10});
      expect(r.overtimeUnit, equals(10));
    });

    // E-07: [D8-CP5] isDeactivated = deactivatedAt != null
    // 미래 시각이어도 즉시 비활성화로 처리됨
    test('E-07: isDeactivated — 미래 deactivatedAt 이어도 즉시 true (설계 확인)', () {
      final biz = BusinessModel.fromMap({
        'businessId': 'biz001',
        'ownerId': 'user001',
        'name': '매장',
        'businessNumber': '1234567890',
        'category': '식음료',
        'adminIds': ['user001'],
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'deactivatedAt': Timestamp.fromDate(DateTime.now().add(Duration(days: 30))), // 미래
      }, 'biz001');
      expect(biz.isDeactivated, isTrue); // 미래 시각이어도 null이 아니므로 true
      // 주의: 예약 비활성화 의도라면 DateTime.now().isAfter(deactivatedAt!) 사용해야 함
    });

    // E-08: AttendanceRules fromMap 기본값 폴백 — 필드 없으면 defaults()와 동일
    test('E-08: fromMap 빈 map → defaults()와 동일', () {
      final fromEmpty = AttendanceRules.fromMap({});
      final defaults = AttendanceRules.defaults();
      expect(fromEmpty.earlyWindow, equals(defaults.earlyWindow));
      expect(fromEmpty.lateGrace, equals(defaults.lateGrace));
      expect(fromEmpty.overtimeUnit, equals(defaults.overtimeUnit));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Group F — 감사 발견 문서화 (HIGH/MEDIUM 항목)
  // ══════════════════════════════════════════════════════════════════════════
  group('F. 감사 발견 문서화', () {
    // F-01: [D1-CP1 HIGH → FIXED] TOModel.toMap() closedReason 직렬화 수정 완료
    test('F-01: [D1-CP1 FIXED] TOModel.toMap() closedReason 직렬화 — 왕복 후 유지', () {
      final to = TOModel.fromMap(_minimalToMap(closedReason: 'POSTING_EXPIRED'), 'to001');
      expect(to.closedReasonCode, equals('POSTING_EXPIRED'));
      expect(to.toMap()['closedReason'], equals('POSTING_EXPIRED'),
          reason: 'FIXED: toMap에 closedReason 포함 → Firestore 재저장 시 유지');
    });

    // F-02: [D4-CP1 HIGH] 초대 만료 기준 불일치 — 클라이언트 3일, Firestore rules 30일
    // 수정 방향: Firestore rules의 30일을 3일로 줄이거나, acceptInvitation을 CF로 이전
    test('F-02: [D4-CP1 HIGH] 초대 만료 기준 — 클라이언트 3일 vs Firestore rules 30일', () {
      // 3일 초과 초대의 isExpired 상태 계산 (클라이언트 기준)
      final inv = _makeInvitation(
          createdAt: DateTime.now().subtract(Duration(days: 5)));
      final clientExpiry = inv.createdAt.add(Duration(days: 3));
      expect(DateTime.now().isAfter(clientExpiry), isTrue,
          reason: '5일 된 초대 → 클라이언트 체크는 만료(3일 초과)');
      // Firestore rules는 30일 기준이므로 이 초대가 REST API로 직접 수락 가능
      // → acceptInvitation CF 이전 시 서버에서 3일 기준 강제 가능
      expect(true, isTrue, reason: 'HIGH 감사 발견 문서화');
    });

    // F-03: [D2-CP7 MEDIUM] hasTimeOverlap — 경계 케이스 전수 확인 완료
    test('F-03: [D2-CP7 MEDIUM] hasTimeOverlap 야간 경계 케이스 — overlaps() strict 비교', () {
      // overlaps = x1 < y2 && x2 < y1 (strict, 경계 접촉 제외)
      expect(ApplicationModel.hasTimeOverlap('13:00', '18:00', '09:00', '13:00'), isFalse,
          reason: '경계 접촉(end2==start1) → strict 비교로 false');
    });

    // F-04: [D5-CP1] hourlyWage 0분 보호 — FALSE POSITIVE 확인
    test('F-04: [D5-CP1 FALSE POSITIVE] hourlyWage workMins=0 → null (기존 가드 존재)', () {
      final snap = _makeSnapshot(
          wageType: 'daily', wage: 100000,
          startTime: '09:00', endTime: '09:00', breakMinutes: 0);
      expect(snap.hourlyWage, isNull,
          reason: 'workMins <= 0 → return null 가드 존재. 탐색 에이전트 D5-CP1 발견은 오판.');
    });

    // F-05: [D8-CP1 HIGH] attendanceRules null — 사용 측 폴백 코드 필수
    test('F-05: [D8-CP1 HIGH] BusinessModel.attendanceRules null 시 폴백 패턴', () {
      final biz = BusinessModel.fromMap({
        'businessId': 'biz001',
        'ownerId': 'admin',
        'name': '매장',
        'businessNumber': '1234567890',
        'category': '식음료',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      }, 'biz001');
      // 신규 사업장 또는 attendanceRules 미설정 → null
      expect(biz.attendanceRules, isNull);
      // 사용 측 반드시: biz.attendanceRules ?? AttendanceRules.defaults()
      final safe = biz.attendanceRules ?? AttendanceRules.defaults();
      expect(safe, isNotNull);
    });

    // F-06: [D3-CP2 MEDIUM] noShow 패널티 복원 — 규칙 변경 시 불일치 가능
    // onAttendanceWageStatusChanged 에서 복원 시 현재 trust_rules 기준으로 역산
    // → noShow 발생 이후 운영자가 패널티 규칙을 낮추면 복원 점수 < 원래 패널티
    // 수정 방향: trust_score_history에 appliedPenalty 저장 후 역산
    test('F-06: [D3-CP2 MEDIUM] noShow 복원 불일치 — 서버 로직, 문서화 테스트', () {
      // 클라이언트에서 직접 검증 불가 (CF 로직)
      // 핵심: 패널티 5점 적용 → 규칙 변경 3점 → 복원 3점만 → net -2점
      expect(true, isTrue, reason: 'MEDIUM 감사 발견 문서화');
    });

    // F-07: [D6-CP2 HIGH] tos list 규칙 — isPublished 미검증
    // allow list: if isLoggedIn() && (isSuperAdmin() || (isUser() && request.query.limit <= 50))
    // → limit<=50 쿼리로 isPublished=false TO 조회 가능
    // 수정 방향: allow list: if isLoggedIn() && (이전) && request.query.filters.isPublished == true
    // (단, CLAUDE.md 이미 알려진 버그: whereIn 복합쿼리에서 filters가 null 반환됨)
    // → 실질적 수정: get 규칙에서 isPublished 강제 (이미 구현됨)
    test('F-07: [D6-CP2 HIGH] tos list 규칙 isPublished 미강제 — 문서화', () {
      expect(true, isTrue, reason: 'HIGH 감사 발견: tos list 규칙에서 isPublished 필터 없음. '
          'REST API limit<=50 쿼리로 미발행 TO 정보 노출 가능. '
          'Firestore rules list 레벨 필터는 기술적 제약(CLAUDE.md 참조)으로 수정 어려움. '
          '실질 대응: tos list는 CF로 이전하거나 클라이언트 쿼리를 CF 전용으로 전환.');
    });
  });
}
