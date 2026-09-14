import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// POSTING-V2-01A INVITE-BUSINESS-RESULT-CONSISTENCY
//
// 같은 "인력 초대"가 진입 경로에 따라 다른 application을 만들면 안 된다.
//
//   Home / DayApplicantsDialog → selectedWorkType + start + end  (정밀)
//   공고 탭 카드 메뉴          → workDate + slotId 만            (비정밀)  ← 수정 대상
//
// 비정밀 경로는 서버 callableInviteWorker의 exact workDetail resolve 블록을
// 통째로 건너뛰어 wdId / wage / wageType 없는 Application을 만들고,
// 수락 시 업무별 capacity 재검증까지 skip시킨다.
// ═══════════════════════════════════════════════════════════════

const _dialogPath =
    'lib/screens/business_admin/dialogs/invite_worker_dialog.dart';
const _cardPath = 'lib/widgets/admin/cards/admin_to_group_card.dart';
const _availSheetPath =
    'lib/screens/business_admin/dialogs/available_workers_bottom_sheet.dart';
const _availSvcPath = 'lib/services/available_workers_service.dart';
const _dayDialogPath =
    'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';
const _wdDataPath = 'lib/models/core/work_detail_data.dart';
const _fsServicePath = 'lib/services/firestore_service.dart';
const _fnPath = 'functions/src/index.ts';

String _src(String p) => File(p).readAsStringSync();

/// `//` 주석 줄 제거 — 주석 안의 문자열이 코드로 오탐되는 것을 막는다.
String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

/// 공백을 1칸으로 평탄화 — 줄바꿈/들여쓰기에 의존하지 않는 비교용.
String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _bodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  if (start == -1) throw StateError('$signature 를 찾지 못함');
  var paren = 0;
  var afterParams = start;
  for (var i = source.indexOf('(', start); i < source.length; i++) {
    if (source[i] == '(') paren++;
    if (source[i] == ')') {
      paren--;
      if (paren == 0) {
        afterParams = i;
        break;
      }
    }
  }
  final open = source.indexOf('{', afterParams);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  throw StateError('$signature 본문의 끝을 찾지 못함');
}

/// getter 전용 — 시그니처에 괄호가 없으므로 첫 `{` 부터 brace matching만 한다.
/// [_bodyOf]는 첫 `(` 를 파라미터 목록으로 가정하므로 getter에 쓸 수 없다.
String _getterBodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  if (start == -1) throw StateError('$signature 를 찾지 못함');
  final open = source.indexOf('{', start);
  if (open == -1) throw StateError('$signature 본문 시작을 찾지 못함');
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  throw StateError('$signature 본문의 끝을 찾지 못함');
}

// ── 서버 계약 재현 ────────────────────────────────────────────
//
// index.ts callableInviteWorker 5.5 블록을 그대로 옮긴 판정기.
// 클라이언트 payload가 서버에서 어떤 결과를 만드는지 테스트에서 직접 확인한다.

class _Wd {
  final String? wdId;
  final String workType;
  final String startTime;
  final String endTime;
  final int wage;
  final String wageType;
  const _Wd(this.wdId, this.workType, this.startTime, this.endTime, this.wage,
      this.wageType);

  /// WorkDetailData.id 와 동일한 composite key
  String get id => '${workType}_${startTime}_$endTime';
}

/// 서버가 payload로부터 파생하는 값들.
class _Derived {
  final String? wdId;
  final int? wage;
  final String? wageType;
  final String? selectedWorkType;
  final String startTime;
  final String endTime;
  final bool capacityValidated;
  final String? error;
  const _Derived({
    this.wdId,
    this.wage,
    this.wageType,
    this.selectedWorkType,
    required this.startTime,
    required this.endTime,
    required this.capacityValidated,
    this.error,
  });
}

/// index.ts:25862~26004 + 26388 의 판정을 재현한다.
_Derived _serverResolve(
  Map<String, dynamic> payload,
  List<_Wd> workDetails, {
  required String slotStartTime,
  required String slotEndTime,
}) {
  final selectedWorkType = payload['selectedWorkType'] as String?;
  final st = payload['workDetailStartTime'] as String?;
  final en = payload['workDetailEndTime'] as String?;
  final hasStart = st != null && st.isNotEmpty;
  final hasEnd = en != null && en.isNotEmpty;

  // fail-closed validation (index.ts:25864)
  if (hasStart != hasEnd) {
    return _Derived(
      startTime: slotStartTime,
      endTime: slotEndTime,
      capacityValidated: false,
      error: 'invalid-argument',
    );
  }
  if ((hasStart || hasEnd) && (selectedWorkType == null)) {
    return _Derived(
      startTime: slotStartTime,
      endTime: slotEndTime,
      capacityValidated: false,
      error: 'invalid-argument',
    );
  }

  // selectedWorkType이 없으면 5.5 블록 전체 skip → 아무것도 파생되지 않는다
  if (selectedWorkType == null) {
    return _Derived(
      startTime: slotStartTime,
      endTime: slotEndTime,
      // index.ts:26388 freshSelectedWorkType 없음 → 업무별 capacity 재검증 skip
      capacityValidated: false,
    );
  }

  // ambiguity guard (index.ts:25971)
  if (!hasStart && !hasEnd) {
    final sameType =
        workDetails.where((w) => w.workType == selectedWorkType).toList();
    if (sameType.length > 1) {
      return _Derived(
        selectedWorkType: selectedWorkType,
        startTime: slotStartTime,
        endTime: slotEndTime,
        capacityValidated: false,
        error: 'failed-precondition',
      );
    }
  }

  // 3중 매칭 (index.ts:25980)
  _Wd? matched;
  for (final w in workDetails) {
    if (w.workType != selectedWorkType) continue;
    if (hasStart && hasEnd) {
      if (w.startTime != st || w.endTime != en) continue;
    }
    matched = w;
    break;
  }

  if (matched == null) {
    if (hasStart && hasEnd) {
      // exact context 제공 + 매칭 실패 → fail-closed (index.ts:25996)
      return _Derived(
        selectedWorkType: selectedWorkType,
        startTime: slotStartTime,
        endTime: slotEndTime,
        capacityValidated: false,
        error: 'failed-precondition',
      );
    }
    return _Derived(
      selectedWorkType: selectedWorkType,
      startTime: slotStartTime,
      endTime: slotEndTime,
      capacityValidated: true,
    );
  }

  return _Derived(
    wdId: matched.wdId,
    wage: matched.wage,
    wageType: matched.wageType,
    selectedWorkType: selectedWorkType,
    // matchedWD의 시간으로 보정 (index.ts:25994)
    startTime: matched.startTime,
    endTime: matched.endTime,
    capacityValidated: true,
  );
}

/// ApplicationModel:262 — wage 누락 시 0으로 떨어진다.
int _modelWage(_Derived d) => d.wage ?? 0;

/// wage_confirm_dialog.dart:416 — wageType 누락 시 hourly로 떨어진다.
String _modelWageType(_Derived d) => d.wageType ?? 'hourly';

/// firestore_service.dart:405 loadTOWorkDetails 의 집계 key.
String _aggregationKey(_Derived d) {
  final wdId = d.wdId;
  if (wdId != null && wdId.isNotEmpty && wdId != d.selectedWorkType) {
    return wdId;
  }
  return '${d.selectedWorkType}_${d.startTime}_${d.endTime}';
}

// ── 픽스처 ────────────────────────────────────────────────────
//
// 같은 슬롯에 동일 workType이 시간대만 다르게 2개 + 다른 workType 1개.
const _picking0918 = _Wd('wd_a1', '피킹', '09:00', '18:00', 12000, 'hourly');
const _picking1822 = _Wd('wd_a2', '피킹', '18:00', '22:00', 15000, 'hourly');
const _packing0918 = _Wd('wd_b1', '포장', '09:00', '18:00', 110000, 'daily');
const _slotWds = [_picking0918, _picking1822, _packing0918];

/// 수정 전 공고 탭 payload — workDetail identity 없음.
Map<String, dynamic> _payloadPostingTabBefore() => {
      'toId': 'to_1',
      'businessId': 'biz_1',
      'targetUid': 'u_1',
      'workDate': '2026-09-20T00:00:00.000',
      'slotId': 'slot_1',
    };

/// 수정 후 공고 탭 payload — 사용자가 고른 workDetail을 그대로 전달.
Map<String, dynamic> _payloadPostingTabAfter(_Wd chosen) => {
      'toId': 'to_1',
      'businessId': 'biz_1',
      'targetUid': 'u_1',
      'workDate': '2026-09-20T00:00:00.000',
      'slotId': 'slot_1',
      'selectedWorkType': chosen.workType,
      'workDetailStartTime': chosen.startTime,
      'workDetailEndTime': chosen.endTime,
    };

/// DayApplicantsDialog → InviteWorkerDialog.contextual 경로.
Map<String, dynamic> _payloadDayApplicants(_Wd chosen) => {
      'toId': 'to_1',
      'businessId': 'biz_1',
      'targetUid': 'u_1',
      'workDate': '2026-09-20T00:00:00.000',
      'slotId': 'slot_1',
      'selectedWorkType': chosen.workType,
      'workDetailStartTime': chosen.startTime,
      'workDetailEndTime': chosen.endTime,
    };

/// Home 부족 인력 → AvailableWorkersBottomSheet 경로.
Map<String, dynamic> _payloadAvailableWorkers(_Wd chosen) => {
      'toId': 'to_1',
      'businessId': 'biz_1',
      'targetUid': 'u_1',
      'workDate': '2026-09-20T00:00:00.000',
      'slotId': 'slot_1',
      'selectedWorkType': chosen.workType,
      'workDetailStartTime': chosen.startTime,
      'workDetailEndTime': chosen.endTime,
    };

void main() {
  // ═════════════════════════════════════════════════════════════
  // INVITE-CONSISTENCY-01 — 공고 탭 payload에 workDetail identity
  // ═════════════════════════════════════════════════════════════
  group('INVITE-CONSISTENCY-01 공고 탭 초대 payload', () {
    final dialog = _src(_dialogPath);
    final sendBody = _codeOf(_bodyOf(dialog, 'Future<void> _send()'));

    test('일반 모드 단기 분기가 3중 매칭 필드를 전송한다', () {
      // 단기 분기: 'workDate' + slotId + 3중 매칭
      final shortBranch = _flat(sendBody);
      expect(
        shortBranch.contains(
            "if (_selectedSlotId != null) 'slotId': _selectedSlotId, "
            "'selectedWorkType': generalWd!.workType, "
            "'workDetailStartTime': generalWd.startTime, "
            "'workDetailEndTime': generalWd.endTime,"),
        isTrue,
        reason: '단기 일반 초대가 selectedWorkType/start/end를 보내지 않는다',
      );
    });

    test('일반 모드 장기 분기도 3중 매칭 필드를 전송한다', () {
      final flat = _flat(sendBody);
      expect(
        flat.contains("'workDays': widget.groupItem!.masterTO.workDays, "
            "'selectedWorkType': generalWd!.workType, "
            "'workDetailStartTime': generalWd.startTime, "
            "'workDetailEndTime': generalWd.endTime,"),
        isTrue,
        reason: '장기 일반 초대가 selectedWorkType/start/end를 보내지 않는다',
      );
    });

    test('workDetail 미확정이면 발송 자체가 막힌다 (fail-closed)', () {
      final flat = _flat(sendBody);
      expect(
        flat.contains(
            'if (!widget.isContextualMode && generalWd == null) {'),
        isTrue,
        reason: '_send가 workDetail 없이도 통과한다',
      );

      final canSend = _codeOf(_getterBodyOf(dialog, 'bool get _canSend'));
      expect(
        _flat(canSend).contains('if (_selectedWorkDetail == null) return false;'),
        isTrue,
        reason: '_canSend가 workDetail 미선택을 허용한다',
      );
    });

    test('업무 선택 UI가 일반 모드에 렌더된다', () {
      expect(dialog.contains('Widget _buildWorkDetailSection('), isTrue);
      final build = _flat(_codeOf(_bodyOf(dialog, 'Widget build(BuildContext context)')));
      expect(
        build.contains('if (_isLong || _selectedDate != null) ...['),
        isTrue,
        reason: '단기에서 날짜 확정 전에 업무 섹션이 노출되면 슬롯과 다른 후보를 보게 된다',
      );
      expect(build.contains('_buildWorkDetailSection(theme, s),'), isTrue);
    });

    test('날짜(슬롯) 변경 시 업무 선택이 재동기화된다', () {
      final slotSection =
          _codeOf(_bodyOf(dialog, 'Widget _buildShortTermSlotSection('));
      expect(
        _flat(slotSection).contains('_selectedSlotId = entry.slotId; '
            '_syncWorkDetailSelection();'),
        isTrue,
        reason: '슬롯이 바뀌어도 이전 슬롯의 업무 선택이 남는다',
      );
    });

    test('업무 후보는 서버와 같은 우선순위(slot → TO)로 고른다', () {
      final opts =
          _codeOf(_getterBodyOf(dialog, 'List<WorkDetailData> get _workDetailOptions'));
      final flat = _flat(opts);
      expect(flat.contains('matched?.slot?.workDetails'), isTrue,
          reason: 'slot.workDetails를 1순위로 쓰지 않는다');
      expect(flat.contains('return gi.masterTO.workDetails;'), isTrue,
          reason: 'TO.workDetails 폴백이 없다');
    });

    test('추가 Firestore/서버 조회 없이 이미 로드된 context만 쓴다', () {
      final opts = _codeOf(
          _getterBodyOf(dialog, 'List<WorkDetailData> get _workDetailOptions'));
      for (final forbidden in [
        'FirebaseFirestore',
        'httpsCallable',
        'await ',
        '.get(',
      ]) {
        expect(opts.contains(forbidden), isFalse,
            reason: '_workDetailOptions가 $forbidden 로 새 조회를 한다');
      }
      // 다이얼로그 전체의 callable은 초대 발송 1개뿐이어야 한다
      expect(
        'httpsCallable'.allMatches(_codeOf(dialog)).length,
        1,
        reason: '초대 다이얼로그에 새로운 callable이 추가됐다',
      );
    });
  });

  // ═════════════════════════════════════════════════════════════
  // INVITE-CONSISTENCY-02 — 동일 workType 다중 시간대
  // ═════════════════════════════════════════════════════════════
  group('INVITE-CONSISTENCY-02 동일 workType 다중 시간대', () {
    test('수정 전 payload는 서버 exact resolve에 도달조차 못 한다', () {
      final d = _serverResolve(_payloadPostingTabBefore(), _slotWds,
          slotStartTime: '09:00', slotEndTime: '22:00');
      expect(d.selectedWorkType, isNull);
      expect(d.wdId, isNull);
      expect(d.wage, isNull);
      expect(d.wageType, isNull);
    });

    test('workType만 보내면 서버 ambiguity guard가 차단한다', () {
      final d = _serverResolve(
        {
          'toId': 'to_1',
          'businessId': 'biz_1',
          'targetUid': 'u_1',
          'workDate': '2026-09-20T00:00:00.000',
          'slotId': 'slot_1',
          'selectedWorkType': '피킹',
        },
        _slotWds,
        slotStartTime: '09:00',
        slotEndTime: '22:00',
      );
      expect(d.error, 'failed-precondition',
          reason: '피킹 09~18 / 18~22 가 동시에 있으면 workType 단독 resolve는 금지');
    });

    test('09~18을 고르면 09~18 workDetail만 resolve된다', () {
      final d = _serverResolve(
          _payloadPostingTabAfter(_picking0918), _slotWds,
          slotStartTime: '09:00', slotEndTime: '22:00');
      expect(d.error, isNull);
      expect(d.wdId, 'wd_a1');
      expect(d.startTime, '09:00');
      expect(d.endTime, '18:00');
      expect(d.wage, 12000);
    });

    test('18~22를 고르면 18~22 workDetail만 resolve된다', () {
      final d = _serverResolve(
          _payloadPostingTabAfter(_picking1822), _slotWds,
          slotStartTime: '09:00', slotEndTime: '22:00');
      expect(d.error, isNull);
      expect(d.wdId, 'wd_a2');
      expect(d.startTime, '18:00');
      expect(d.endTime, '22:00');
      expect(d.wage, 15000);
    });

    test('선택 key가 시간대를 포함해 두 시간대를 구분한다', () {
      expect(_picking0918.id, isNot(_picking1822.id));
      expect(_picking0918.id, '피킹_09:00_18:00');
      // WorkDetailData.id 정의가 바뀌면 선택 key도 깨진다
      expect(
        _src(_wdDataPath)
            .contains("String get id => '\${workType}_\${startTime}_\$endTime';"),
        isTrue,
        reason: 'WorkDetailData.id composite 정의가 바뀌었다',
      );
    });
  });

  // ═════════════════════════════════════════════════════════════
  // INVITE-CONSISTENCY-03 — 세 경로 canonical identity 동일
  // ═════════════════════════════════════════════════════════════
  group('INVITE-CONSISTENCY-03 cross-entry business result', () {
    for (final chosen in [_picking0918, _picking1822, _packing0918]) {
      test('${chosen.workType} ${chosen.startTime}~${chosen.endTime} '
          '— 세 경로 결과 동일', () {
        final posting = _serverResolve(
            _payloadPostingTabAfter(chosen), _slotWds,
            slotStartTime: '09:00', slotEndTime: '22:00');
        final day = _serverResolve(_payloadDayApplicants(chosen), _slotWds,
            slotStartTime: '09:00', slotEndTime: '22:00');
        final avail = _serverResolve(
            _payloadAvailableWorkers(chosen), _slotWds,
            slotStartTime: '09:00', slotEndTime: '22:00');

        for (final other in [day, avail]) {
          expect(posting.wdId, other.wdId);
          expect(posting.wage, other.wage);
          expect(posting.wageType, other.wageType);
          expect(posting.selectedWorkType, other.selectedWorkType);
          expect(posting.startTime, other.startTime);
          expect(posting.endTime, other.endTime);
          expect(posting.capacityValidated, other.capacityValidated);
          expect(posting.error, other.error);
        }
      });
    }

    test('payload key 집합이 세 경로에서 동일하다', () {
      final a = _payloadPostingTabAfter(_picking1822).keys.toSet();
      final b = _payloadDayApplicants(_picking1822).keys.toSet();
      final c = _payloadAvailableWorkers(_picking1822).keys.toSet();
      expect(a, b);
      expect(a, c);
    });

    test('세 경로 모두 동일한 callable 하나를 쓴다', () {
      expect(_src(_dialogPath).contains("httpsCallable('callableInviteWorker')"),
          isTrue);
      expect(_src(_availSvcPath).contains("httpsCallable('callableInviteWorker')"),
          isTrue);
      // 공고 탭 전용 callable이 새로 생기지 않았다
      final clientFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      var inviteCallables = 0;
      for (final f in clientFiles) {
        inviteCallables +=
            RegExp(r"httpsCallable\('callableInvite").allMatches(f.readAsStringSync()).length;
      }
      expect(inviteCallables, 2,
          reason: 'callableInvite* 호출 지점이 2곳(dialog, service)이 아니다');
    });

    test('수정 전 공고 탭 결과는 나머지 두 경로와 달랐다 (회귀 기준)', () {
      final before = _serverResolve(_payloadPostingTabBefore(), _slotWds,
          slotStartTime: '09:00', slotEndTime: '22:00');
      final day = _serverResolve(_payloadDayApplicants(_picking0918), _slotWds,
          slotStartTime: '09:00', slotEndTime: '22:00');
      expect(before.wdId == day.wdId, isFalse);
      expect(before.wage == day.wage, isFalse);
      expect(before.capacityValidated == day.capacityValidated, isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // INVITE-CONSISTENCY-04 — wage fallback 0 제거
  // ═════════════════════════════════════════════════════════════
  group('INVITE-CONSISTENCY-04 wage / wageType canonical', () {
    test('수정 전 payload는 wage 0 · wageType hourly 로 떨어졌다', () {
      final before = _serverResolve(_payloadPostingTabBefore(), _slotWds,
          slotStartTime: '09:00', slotEndTime: '22:00');
      expect(_modelWage(before), 0);
      expect(_modelWageType(before), 'hourly');
    });

    test('수정 후에는 workDetail 원본 금액이 그대로 온다', () {
      for (final chosen in _slotWds) {
        final d = _serverResolve(_payloadPostingTabAfter(chosen), _slotWds,
            slotStartTime: '09:00', slotEndTime: '22:00');
        expect(_modelWage(d), chosen.wage);
        expect(_modelWageType(d), chosen.wageType);
      }
    });

    test('daily 업무가 hourly로 오분류되지 않는다', () {
      final d = _serverResolve(_payloadPostingTabAfter(_packing0918), _slotWds,
          slotStartTime: '09:00', slotEndTime: '22:00');
      expect(_modelWageType(d), 'daily');
      expect(_modelWage(d), 110000);
    });

    test('wage 0 fallback 지점이 그대로 살아 있다 (수정 대상 아님)', () {
      // 이 fallback 자체는 바꾸지 않는다. payload 쪽에서 도달을 막았을 뿐이다.
      expect(
        _src('lib/models/core/application_model.dart')
            .contains("wage: (data['wage'] as num?)?.toInt() ?? 0,"),
        isTrue,
      );
    });
  });

  // ═════════════════════════════════════════════════════════════
  // INVITE-CONSISTENCY-05 — 수락 시 capacity 재검증
  // ═════════════════════════════════════════════════════════════
  group('INVITE-CONSISTENCY-05 capacity validation', () {
    final fn = _src(_fnPath);

    test('서버 exact-match 계약이 그대로다 (FUNCTIONS_CHANGED = NONE)', () {
      final code = _codeOf(fn);
      expect(
        code.contains(
            'return (wd.startTime as string | undefined) === workDetailStartTime &&'),
        isTrue,
        reason: '3중 매칭 조건이 변경됐다',
      );
      expect(code.contains('inviteResolvedWdId = matchedWD.wdId as string | undefined;'),
          isTrue,
          reason: 'wdId 파생이 사라졌다');
      expect(
        code.contains('if (typeof matchedWD.wage === "number")'),
        isTrue,
        reason: 'wage 서버 파생이 사라졌다',
      );
    });

    test('수락 시 capacity 재검증이 selectedWorkType에 의존한다', () {
      final code = _codeOf(fn);
      expect(code.contains('if (freshSelectedWorkType) {'), isTrue,
          reason: '업무별 정원 재검증 gate가 바뀌었다');
      expect(
        code.contains(r'`${freshSelectedWorkType} 업무 정원이 초과되었습니다. (${wtConf}/${wtReq}명)`'),
        isTrue,
        reason: '업무별 정원 초과 차단이 사라졌다',
      );
    });

    test('workDetailCounts dual-write가 wdId에 의존한다', () {
      final code = _codeOf(fn);
      expect(
        code.contains(r'slotUpdate[`workDetailCounts.${inviteAcceptWdId}.confirmedCount`] ='),
        isTrue,
        reason: 'wdId canonical counter가 사라졌다',
      );
    });

    test('수정 후 경로는 capacity 검증이 활성화된다', () {
      for (final chosen in _slotWds) {
        final d = _serverResolve(_payloadPostingTabAfter(chosen), _slotWds,
            slotStartTime: '09:00', slotEndTime: '22:00');
        expect(d.capacityValidated, isTrue);
        expect(d.wdId, isNotNull,
            reason: 'wdId 없으면 workDetailCounts 증가 자체가 안 된다');
      }
      final before = _serverResolve(_payloadPostingTabBefore(), _slotWds,
          slotStartTime: '09:00', slotEndTime: '22:00');
      expect(before.capacityValidated, isFalse);
    });

    test('FULL / closed guard 정책은 건드리지 않았다', () {
      final code = _codeOf(fn);
      expect(code.contains('"정원이 마감된 공고에는 초대를 보낼 수 없습니다."'), isTrue);
      expect(code.contains('"마감된 공고에는 초대를 보낼 수 없습니다."'), isTrue);
      expect(code.contains('"마감된 슬롯에는 초대를 보낼 수 없습니다."'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // INVITE-CONSISTENCY-06 — WorkDetailRow 집계 귀속
  // ═════════════════════════════════════════════════════════════
  group('INVITE-CONSISTENCY-06 workDetail row 집계', () {
    test('수정 전에는 null_시작_종료 키로 빠져 어느 row에도 안 잡혔다', () {
      final before = _serverResolve(_payloadPostingTabBefore(), _slotWds,
          slotStartTime: '09:00', slotEndTime: '22:00');
      final key = _aggregationKey(before);
      expect(key, 'null_09:00_22:00');
      expect(_slotWds.any((w) => w.id == key || w.wdId == key), isFalse,
          reason: '어떤 workDetail row에도 귀속되지 않는다');
    });

    test('수정 후에는 정확히 선택한 workDetail row에 귀속된다', () {
      for (final chosen in _slotWds) {
        final d = _serverResolve(_payloadPostingTabAfter(chosen), _slotWds,
            slotStartTime: '09:00', slotEndTime: '22:00');
        expect(_aggregationKey(d), chosen.wdId,
            reason: '${chosen.workType} 집계 키가 wdId가 아니다');
      }
    });

    test('legacy(wdId 없는) workDetail도 composite로 정확히 귀속된다', () {
      const legacy = _Wd(null, '검수', '10:00', '15:00', 11000, 'hourly');
      final d = _serverResolve(_payloadPostingTabAfter(legacy), [legacy],
          slotStartTime: '10:00', slotEndTime: '15:00');
      expect(_aggregationKey(d), legacy.id);
      expect(_aggregationKey(d), '검수_10:00_15:00');
    });

    test('집계 키 규칙이 loadTOWorkDetails와 동일하다', () {
      final body =
          _codeOf(_bodyOf(_src(_fsServicePath), 'Future<Map<String, dynamic>> loadTOWorkDetails('));
      final flat = _flat(body);
      expect(
        flat.contains(
            "final key = (wdId != null && wdId.isNotEmpty && wdId != app.selectedWorkType) "
            "? wdId : '\${app.selectedWorkType}_\${app.startTime}_\${app.endTime}';"),
        isTrue,
        reason: 'loadTOWorkDetails 집계 키 규칙이 바뀌었다 — 테스트 재현식도 함께 갱신 필요',
      );
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 기존 정상 경로 회귀 — 변경 없음
  // ═════════════════════════════════════════════════════════════
  group('기존 정밀 경로 회귀', () {
    test('AvailableWorkersBottomSheet는 3중 매칭을 그대로 보낸다', () {
      final flat = _flat(_codeOf(_src(_availSheetPath)));
      expect(flat.contains('selectedWorkType: widget.workType, '
          'workDetailStartTime: widget.startTime, '
          'workDetailEndTime: widget.endTime,'), isTrue);
    });

    test('DayApplicantsDialog는 contextual 생성자를 그대로 쓴다', () {
      final flat = _flat(_codeOf(_src(_dayDialogPath)));
      expect(flat.contains('InviteWorkerDialog.contextual('), isTrue);
      expect(
        flat.contains('workType: g.workType, startTime: g.startTime, '
            'endTime: g.endTime,'),
        isTrue,
      );
    });

    test('contextual 모드 payload 분기는 그대로다', () {
      final sendBody = _flat(_codeOf(_bodyOf(_src(_dialogPath), 'Future<void> _send()')));
      expect(
        sendBody.contains("if (widget.prefilledWorkType != null && "
            "widget.prefilledWorkType!.isNotEmpty) "
            "'selectedWorkType': widget.prefilledWorkType,"),
        isTrue,
      );
    });

    test('contextual 모드는 업무 재선택 UI를 띄우지 않는다', () {
      final build =
          _flat(_codeOf(_bodyOf(_src(_dialogPath), 'Widget build(BuildContext context)')));
      // 업무 섹션은 !isContextualMode 블록 안에만 있다
      final idx = build.indexOf('_buildWorkDetailSection(theme, s)');
      expect(idx, isNot(-1));
      final guard = build.indexOf('if (!widget.isContextualMode) ...[');
      expect(guard, isNot(-1));
      expect(guard < idx, isTrue,
          reason: '업무 선택 섹션이 contextual 모드에도 노출된다');
    });

    test('AvailableWorkersService 시그니처가 유지된다', () {
      final svc = _src(_availSvcPath);
      for (final param in [
        'String? selectedWorkType,',
        'String? workDetailStartTime,',
        'String? workDetailEndTime,',
      ]) {
        expect(svc.contains(param), isTrue);
      }
    });
  });

  // ═════════════════════════════════════════════════════════════
  // Scope guard — 이번 Phase에서 건드리지 않은 것들
  // ═════════════════════════════════════════════════════════════
  group('scope guard', () {
    test('permission gate 변경 없음', () {
      final card = _codeOf(_src(_cardPath));
      expect(card.contains("label: '인력 초대',"), isTrue,
          reason: '카드 메뉴 초대 진입점이 사라졌다 — 이번 Phase 범위 아님');
      expect(
        'onTap: () => _showInviteWorkerDialog(context),'
            .allMatches(card)
            .length,
        3,
        reason: '초대 메뉴 항목 수가 바뀌었다 (list 1 + calendar contract 1 + calendar flex 1)',
      );
      final fn = _codeOf(_src(_fnPath));
      expect(
        fn.contains(
            'if (!memberPermsForInv.canManageTo) throw new HttpsError("permission-denied", "TO 관리 권한이 없습니다.");'),
        isTrue,
      );
    });

    test('notification semantics 변경 없음', () {
      final fn = _codeOf(_src(_fnPath));
      expect(fn.contains('type:      "toInvite",'), isTrue);
      expect(fn.contains('title:     "업무 초대가 도착했어요! 🎉",'), isTrue);
    });

    test('P1-2 ERROR != ZERO 는 이번에 수정하지 않았다', () {
      expect(
        _codeOf(_src('lib/controllers/workforce_controller.dart'))
            .contains('_items = [];'),
        isTrue,
        reason: 'ERROR!=ZERO는 POSTING-V2-01B 범위다',
      );
    });

    test('P1-3 슬롯 삭제 정책은 이번에 수정하지 않았다', () {
      final flat = _flat(_codeOf(_src(_cardPath)));
      expect(
        // [POSTING-V2-03M.1] 변수명만 deleteSlotIds로 바뀌었다
        flat.contains("'선택한 \${deleteSlotIds.length}개 날짜를 삭제하시겠습니까?'"),
        isTrue,
        reason: '슬롯 삭제 문구는 별도 Phase 범위다',
      );
    });

    test('legacy invitation backfill 코드가 없다', () {
      final dialog = _src(_dialogPath);
      for (final forbidden in ['backfill', 'migrate', 'Backfill', 'Migrate']) {
        expect(dialog.contains(forbidden), isFalse);
      }
    });
  });
}
