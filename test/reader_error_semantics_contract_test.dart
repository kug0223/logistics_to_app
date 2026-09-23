// [R8-P7.3] 조회 실패가 정상 상태로 붕괴하지 않는다.
//
//   P7.2 에서 실제 사례를 봤다 — 인덱스가 없어 쿼리가 계속 실패했는데
//   서비스가 빈 목록으로 삼켜서 화면은 "없음"이라고 말했다. 세 층이 겹쳐야
//   보이지 않는다. 그중 삼키는 층을 없애 두면 다음번엔 첫날 드러난다.
//
//   이 파일은 그 층이 되돌아오지 않게 고정한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/ui/invite_capacity_state.dart';

String _read(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('파일을 찾지 못했다: $p');
  return f.readAsStringSync();
}

/// 주석을 지운 코드만 남긴다 — 표지를 주석에 두지 않기 위해.
String _codeOf(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// 함수의 catch 블록만 잘라 낸다.
///   조기 반환(`if (ids.isEmpty) return [];`)은 정당한 빈 결과이므로 건드리지 않는다.
String _catchBodyOf(String file, String fnStart) {
  final code = _codeOf(_read(file));
  final s = code.indexOf(fnStart);
  if (s < 0) throw StateError('함수를 찾지 못했다: $fnStart');
  final c = code.indexOf('} catch (', s);
  if (c < 0) throw StateError('catch 블록을 찾지 못했다: $fnStart');
  final open = code.indexOf('{', c + 2);
  var depth = 0;
  var end = open;
  for (var k = open; k < code.length; k++) {
    if (code[k] == '{') depth++;
    if (code[k] == '}') { depth--; if (depth == 0) { end = k; break; } }
  }
  return _flat(code.substring(open, end + 1));
}

void _propagates(String file, String fnStart, String reason) {
  final body = _catchBodyOf(file, fnStart);
  expect(body.contains('rethrow'), isTrue, reason: reason);
  expect(RegExp(r'return\s*(const\s*)?(<[^>]*>)?\s*\[\s*\]\s*;').hasMatch(body), isFalse,
      reason: '$reason — catch 안에서 빈 목록을 돌려준다');
  expect(RegExp(r'return\s*(const\s*)?(<[^>]*>)?\s*\{\s*\}\s*;').hasMatch(body), isFalse,
      reason: '$reason — catch 안에서 빈 맵을 돌려준다');
  expect(RegExp(r'return\s+0\s*;').hasMatch(body), isFalse,
      reason: '$reason — catch 안에서 0 을 돌려준다');
}

void main() {
  const appSvc = 'lib/services/firestore/application_firestore.dart';
  const attSvc = 'lib/services/firestore/attendance_firestore.dart';
  const idSvc = 'lib/services/firestore/id_card_firestore.dart';
  const fsSvc = 'lib/services/firestore_service.dart';
  const ctrSvc = 'lib/services/contract_service.dart';
  const toSvc = 'lib/services/firestore/to_firestore.dart';
  const dayDlg = 'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';
  const myApps = 'lib/screens/user/my_applications_screen.dart';

  group('[R8P7.3] 계약 — 약속을 못 읽은 것을 "계약 없음"으로 말하지 않는다', () {
    test('RS-1 근무자 계약서 조회', () {
      _propagates(ctrSvc, 'Future<List<EmploymentContractModel>> getByWorker(',
          '서명을 기다리는 계약이 있어도 근로자가 서명할 수 없게 된다');
    });

    test('RS-2 계약 확인 필요 조회', () {
      _propagates(appSvc, 'Future<List<ApplicationModel>> getExpiringLongTermApplications(',
          '종료가 다가온 계약이 화면에서 사라진다');
    });

    test('RS-3 계약 해지 요청 조회', () {
      _propagates(idSvc, 'Future<List<ApplicationModel>> getMyTerminationRequests(',
          '해지 요청이 사라진다');
    });

    test('RS-4 계약 조회 실패는 "준비 중"이 아니라 "불러오지 못했다"로 말한다', () {
      final code = _flat(_codeOf(_read(myApps)));
      expect(code.contains('_contractsFailed'), isTrue);
      expect(code.contains('계약 정보를 불러오지 못했어요'), isTrue,
          reason: '실패를 "관리자가 계약서를 준비 중"으로 단정하면 안 된다');
      // 두 분기가 함께 있어야 한다 — 실패와 "아직 없음"은 다른 문장이다.
      expect(code.contains('관리자가 계약서를 준비 중이에요'), isTrue,
          reason: '정상 "아직 없음" 문구까지 지우면 안 된다');
    });
  });

  group('[R8P7.3] 지원서 — 못 읽은 것을 "지원자 없음"으로 말하지 않는다', () {
    test('RS-5 슬롯 지원자 목록', () {
      _propagates(appSvc, 'Future<List<ApplicationModel>> getApplicationsBySlotId(', '지원자 명단');
    });
    test('RS-6 미발송 계약서 지원서', () {
      _propagates(appSvc, 'Future<List<ApplicationModel>> getUnsentApplicationsByBusiness(', '발송 대상');
    });
    test('RS-7 날짜별 대기 지원자', () {
      _propagates(appSvc, 'Future<List<ApplicationModel>> getPendingApplicationsByDateAndBusiness(', '대기 지원자');
    });
    test('RS-8 충돌 확인용 내 확정 근무', () {
      _propagates(fsSvc, 'Future<List<ApplicationModel>> getMyConfirmedApplicationsForConflictCheck(',
          '충돌을 못 읽은 것을 "충돌 없음"으로 말하면 이중 근무가 통과한다');
    });
  });

  group('[R8P7.3] 근태·일정', () {
    test('RS-9 날짜별 노쇼 판별', () {
      _propagates(attSvc, 'Future<Set<String>> getNoShowApplicationIdsByDate(', '노쇼 여부');
    });
    test('RS-10 내 스케줄 변경 요청', () {
      _propagates(attSvc, 'Future<List<ScheduleChangeRequestModel>> getMyScheduleChangeRequests(', '내 요청');
    });
  });

  group('[R8P7.3] 정원 — 못 읽은 것은 0 이 아니라 UNKNOWN 이다', () {
    test('CAP-1 정상: 정원을 알면 available/full 을 판정한다', () {
      expect(inviteCapacityStateOf(canonicalConfirmed: 1, requiredCount: 3),
          InviteCapacityState.available);
      expect(inviteCapacityStateOf(canonicalConfirmed: 3, requiredCount: 3),
          InviteCapacityState.full);
    });

    test('CAP-2 서비스가 정원 조회 실패를 빈 맵으로 바꾸지 않는다', () {
      _propagates(toSvc, 'Future<Map<String, int>> getSlotWorkDetailCapacities(',
          '소비부가 `?? 0` 으로 읽어 "정원 0"이 된다');
    });

    test('CAP-3 실패는 UNKNOWN 으로 내려간다', () {
      final code = _flat(_codeOf(_read(dayDlg)));
      expect(code.contains('bool requiredCountKnown'), isTrue);
      expect(code.contains('requiredCountKnown ?'), isTrue,
          reason: 'capacityState 가 requiredCountKnown 을 보지 않으면 0 이 available 로 샌다');
      expect(code.contains(': InviteCapacityState.unknown;'), isTrue);
      expect(code.contains('_capacityUnknown = true'), isTrue);
      expect(code.contains('requiredCountKnown: !_capacityUnknown'), isTrue);
    });

    test('CAP-4 실패를 0명으로 표시하지 않는다', () {
      final code = _flat(_codeOf(_read(dayDlg)));
      // 정원이 0 이면 분모를 아예 쓰지 않는다 — "N/0명" 을 만들지 않는다.
      expect(code.contains("required > 0 ? '\$confirmed/\$required명' : '\$confirmed명'"), isTrue,
          reason: '정원 0 을 분모로 찍으면 "확정 N / 0" 이 된다');
    });

    test('CAP-5 실패를 FULL 로 표시하지 않는다', () {
      final code = _flat(_codeOf(_read(dayDlg)));
      expect(code.contains('final isFull = required > 0 && confirmed >= required;'), isTrue,
          reason: 'required 가 0 일 때 FULL 로 판정되면 안 된다');
      expect(inviteCapacityStateOf(canonicalConfirmed: 0, requiredCount: 0),
          isNot(InviteCapacityState.full));
    });

    test('CAP-6 정원을 몰라도 지원자 명단은 살아 있다', () {
      final code = _flat(_codeOf(_read(dayDlg)));
      // 정원 조회 실패는 다이얼로그 전체를 오류로 만들지 않는다.
      expect(code.contains('_loadWorkDetailCapacitiesOrThrow(allApps)'), isTrue);
      expect(code.contains('_capacityUnknown = true; return {};'), isTrue,
          reason: '실패를 삼키되 UNKNOWN 을 세운다 — 명단은 유지된다');
    });

    test('CAP-7 slot canonical 값을 받으면 다시 "안다"가 된다', () {
      final code = _flat(_codeOf(_read(dayDlg)));
      expect(code.contains('existing.requiredCountKnown = true;'), isTrue,
          reason: 'staffing row 가 정원을 주면 UNKNOWN 을 유지할 이유가 없다');
    });
  });

  group('[R8P7.3] ERROR vs EMPTY 쌍 (§28)', () {
    test('READ-ERR-1 실제 빈 결과는 여전히 빈 목록이다', () {
      // 조기 반환은 손대지 않았다 — 입력이 비면 결과도 비는 것이 맞다.
      final code = _flat(_codeOf(_read(attSvc)));
      expect(code.contains('if (businessIds.isEmpty) return [];'), isTrue,
          reason: '정상 빈 입력까지 오류로 바꾸면 안 된다');
    });

    test('READ-ERR-2 쿼리 오류는 전파된다', () {
      _propagates(attSvc, 'Future<List<ScheduleChangeRequestModel>> getScheduleChangeRequestsForDate(',
          '오류와 빈 결과가 같은 화면이 되면 안 된다');
    });
  });
}
