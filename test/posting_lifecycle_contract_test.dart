// [POSTING-MANAGEMENT.1] 공고를 만들고 · 보여주고 · 고치고 · 닫고 · 지우는 동안
// 약속이 흔들리지 않는다.
//
// 이번에 고친 것:
//
//   1. 하루짜리 공고를 등록할 수 없었다. FLEX는 rangeStart=min(선택날짜),
//      rangeEnd=max(선택날짜)를 보내는데 날짜를 하나 고르면 두 값이 같아진다.
//      서버의 역전 검증이 `>=`여서 그 공고를 전부 거절했다 — 가장 흔한 하루짜리
//      단기 공고가 "공고 등록에 실패했습니다"로 끝났다.
//      (DEV 실측: 수정 전 400 · 수정 후 200)
//   2. 삭제된 공고에 대한 지원은 isPublished=false로만 걸렸고, 메시지는
//      "아직 공개되지 않은 공고"였다. 없어진 공고를 기다리게 하는 문구다.
//   3. 공고를 못 읽은 것이 "삭제된 공고"로 보였다. 근로자에게는 자기 약속이
//      사라진 것처럼 읽힌다.
//   4. 등록 직후 방금 만든 공고를 목록에서 찾을 수 없었다(필터에 가리기도 했다).
//
// DEV runtime 요약:
//   생성 parity     writer=manager=applicant 14개 field 불일치 0
//   임금 11000→13000  기존 PENDING 11000 유지 · 신규 지원 13000 (클라이언트 값 무시)
//   휴게 60→30        기존 지원 60 유지
//   시간 identity 변경 활성 지원자 있으면 400
//   필요인원 2→4 허용 · 확정 2명에서 2→1 거절 · 2→0 거절 · 확정자 CONTRACT_PENDING 유지
//   확정 후 13000→15000  확정자 약속 11000/60분 불변
//   FLEX: A날짜 full → A 지원 403, B 지원 200 (날짜별 진실 유지)
//   마감: PENDING→REJECTED, 신규 403, 확정자 생존 / 재개: 지원 200, 슬롯 3→3
//   삭제: 지원 8건 있으면 400 · 0건이면 소프트 삭제(문서 보존·목록에서 사라짐)
//        삭제 공고 직접 지원 404 "삭제된 공고입니다"
//   권한: canManageTo=false → 생성·수정·마감·재개·삭제 전부 403
//   경계: B관리자가 A공고에 대해 4경로 모두 403 · 상태 변화 없음
//   오류: 권한 없는 목록 조회는 403 (빈 목록 아님)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fnsPath = 'functions/src/index.ts';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _callableOf(String source, String name) {
  final start = source.indexOf('export const $name = onCall(');
  if (start < 0) throw StateError('$name 을 찾지 못함');
  final next = source.indexOf('\nexport ', start + 10);
  return source.substring(start, next == -1 ? source.length : next);
}

void main() {
  final raw = _src(_fnsPath);
  final fnsFlat = _flat(_codeOf(raw));

  group('하루짜리 공고를 등록할 수 있다', () {
    test('같은 날은 역전이 아니다', () {
      expect(fnsFlat.contains('if (rsTs && reTs && rsTs.toMillis() > reTs.toMillis())'), true,
          reason: '>= 로 막으면 날짜를 하나만 고른 공고가 전부 거절된다');
      expect(fnsFlat.contains('rsTs.toMillis() >= reTs.toMillis()'), false);
    });

    test('수정 쪽도 같은 기준을 쓴다', () {
      expect(fnsFlat.contains('if (newRs && newRe && newRs.toMillis() > newRe.toMillis())'), true);
      expect(fnsFlat.contains('newRs.toMillis() >= newRe.toMillis()'), false,
          reason: '생성은 되는데 수정이 막히면 같은 공고가 열었다 닫힌다');
    });
  });

  group('없어진 공고에는 지원할 수 없다', () {
    final apply = _flat(_codeOf(_callableOf(raw, 'callableApplyToTO')));

    test('삭제를 직접 본다', () {
      expect(apply.contains('if (toData["isDeleted"] === true) { throw new HttpsError("not-found", "삭제된 공고입니다.");'),
          true, reason: 'isPublished에만 기대면 문구가 "아직 공개되지 않은 공고"가 된다');
    });

    test('삭제 검사가 다른 상태 검사보다 앞선다', () {
      final d = apply.indexOf('isDeleted"] === true');
      final p = apply.indexOf('if (!toData["isPublished"])');
      expect(d > 0 && p > d, true);
    });

    test('마감·비공개도 여전히 막힌다', () {
      expect(apply.contains('if (!toData["isPublished"])'), true);
      expect(apply.contains('toData["status"] === "CLOSED"'), true);
    });
  });

  group('공고 수정이 이미 한 약속에 닿지 않는다', () {
    test('지원 시점에 산정 조건을 고정한다', () {
      expect(fnsFlat.contains('export function buildCompensationSnapshot('), true);
      for (final f in ['baseHourlyWage', 'breakMinutes', 'nightAllowanceApplied',
        'nightIncluded', 'taxDeductionType']) {
        expect(fnsFlat.contains('out.$f') || fnsFlat.contains('out.$f ='), true,
            reason: '$f 가 빠지면 금액이 같아도 실제 지급액이 달라질 수 있다');
      }
    });

    test('임금은 서버가 공고에서 읽는다', () {
      final apply = _flat(_codeOf(_callableOf(raw, 'callableApplyToTO')));
      expect(apply.contains('const effectiveWage = serverWage;'), true,
          reason: '클라이언트가 보낸 임금을 쓰면 약속을 위조할 수 있다');
      expect(apply.contains('const compensationSnapshot = buildCompensationSnapshot(promisedWD);'),
          true);
    });

    test('업무·시간 identity는 활성 지원자가 있으면 못 바꾼다', () {
      final upd = _flat(_codeOf(_callableOf(raw, 'callableUpdateSlotWorkDetails')));
      expect(upd.contains('const ACTIVE_STATUSES_WITH_CONFIRMED = ["PENDING", "INVITED", "CONTRACT_PENDING", "CONFIRMED"];'),
          true, reason: '네 상태 중 하나라도 빠지면 그 사람의 지원 join이 끊긴다');
      expect(upd.contains('해당 업무 시간대에 활성 지원자가 있어 업무 구성을 변경할 수 없습니다'), true);
    });

    test('조건 스냅샷이 없는 옛 지원서는 조건 변경을 잠근다', () {
      final upd = _flat(_codeOf(_callableOf(raw, 'callableUpdateSlotWorkDetails')));
      expect(upd.contains('const LEGACY_PROTECTED_FIELDS = [ "baseHourlyWage", "breakMinutes", '
          '"nightAllowanceApplied", "nightIncluded", "taxDeductionType", ];'), true);
    });
  });

  group('필요 인원을 줄여서 약속을 깨지 않는다', () {
    final upd = _flat(_codeOf(_callableOf(raw, 'callableUpdateSlotWorkDetails')));

    test('확정 인원 아래로는 못 내린다', () {
      expect(upd.contains('const OCCUPANCY_STATUSES = ["CONFIRMED", "CONTRACT_PENDING"];'), true);
      expect(upd.contains('if (newRequired < occupied)'), true);
      expect(upd.contains('보다 작게 설정할 수 없습니다'), true);
    });

    test('거절만 하고 자리를 취소하지 않는다', () {
      // 확정 취소는 별도 행동이다. 인원 수정이 사람을 내보내면 안 된다.
      expect(RegExp(r'status:\s*"(AUTO_)?CANCELED"').hasMatch(upd), false,
          reason: '필요 인원 수정 경로에 취소 write가 있으면 약속이 조용히 깨진다');
    });

    test('0명은 무제한이 아니다', () {
      expect(upd.contains('if (newRequired < 1)'), true);
    });
  });

  group('FULL과 CLOSED는 다르다', () {
    final apply = _flat(_codeOf(_callableOf(raw, 'callableApplyToTO')));

    test('공고 전체 FULL이 날짜별 모집을 덮지 않는다', () {
      expect(apply.contains('(toData["status"] === "FULL" && !applyIsSlotBased)'), true,
          reason: 'FLEX는 날짜마다 자리를 따로 센다 — 합계로 막으면 빈 날짜까지 닫힌다');
    });

    test('날짜 마감은 그 날짜만 막는다', () {
      expect(apply.contains('if (sd["isManualClosed"] === true || sd["status"] === "closed")'), true);
      expect(apply.contains('해당 날짜는 마감되었습니다'), true);
    });

    test('마감은 대기만 정리하고 확정은 건드리지 않는다', () {
      final close = _flat(_codeOf(_callableOf(raw, 'callableCloseSlots')));
      expect(close.contains('.where("status", "==", "PENDING")'), true);
      expect(close.contains('status: "REJECTED", rejectedAt: now,'), true);
      expect(close.contains('"CONFIRMED"'), false,
          reason: '마감이 확정자를 정리하면 근무 약속이 사라진다');
    });

    test('재개는 전체 종료·FULL 상태를 우회하지 않는다', () {
      final re = _flat(_codeOf(_callableOf(raw, 'callableReopenSlots')));
      expect(re.contains('종료된 전체 공고는 먼저 공고를 재오픈해야 합니다'), true);
      expect(re.contains('정원이 충족된 공고는 확정 취소를 통해서만 모집 상태로 변경됩니다'), true);
    });
  });

  group('삭제가 기록을 지우지 않는다', () {
    test('관계가 하나라도 있으면 삭제하지 않는다', () {
      expect(fnsFlat.contains('if (!appSnap.empty) return {blocked: true, reason: "APPLICATION_EXISTS"};'),
          true);
      expect(fnsFlat.contains('if (!contractSnap.empty) return {blocked: true, reason: "CONTRACT_EXISTS"};'),
          true);
    });

    test('관계를 확인하지 못하면 지우지 않는다', () {
      expect(fnsFlat.contains('return {blocked: true, reason: "RELATION_CHECK_FAILED"};'), true,
          reason: '조회 실패를 "관계 없음"으로 읽으면 기록이 사라진다');
    });

    test('삭제는 문서를 지우는 것이 아니라 표시하는 것이다', () {
      final del = _flat(_codeOf(_callableOf(raw, 'callableDeleteTO')));
      expect(del.contains('isDeleted: true,'), true);
      expect(del.contains('isPublished: false,'), true);
      expect(RegExp(r'tos"\)\.doc\(toId\)\.delete\(\)').hasMatch(del), false,
          reason: '문서를 지우면 지원 이력·근무 기록의 부모가 없어진다');
    });

    test('다음에 할 일을 알려준다', () {
      expect(fnsFlat.contains('모집을 중단하려면 공고 종료를 이용해주세요'), true);
    });
  });

  group('못 읽은 것을 없어진 것이라고 말하지 않는다', () {
    test('조회가 실패와 부재를 나눠서 돌려준다', () {
      final s = _flat(_codeOf(_src('lib/services/firestore/to_firestore.dart')));
      expect(s.contains('Future<({TOModel? to, bool failed})> getTOOrFailure(String toId) async'), true);
      expect(s.contains('return (to: null, failed: true);'), true);
    });

    test('공고 상세가 두 상황을 다르게 말한다', () {
      final s = _flat(_codeOf(_src('lib/screens/common/job_posting_screen.dart')));
      expect(s.contains("Text(_loadFailed ? '공고를 불러오지 못했습니다' : '공고를 찾을 수 없습니다'"), true);
      expect(s.contains("text: '다시 시도',"), true,
          reason: '실패에는 되돌아가기가 아니라 다시 시도가 맞는 행동이다');
    });

    test('근로자 지원 목록도 구분한다', () {
      final s = _flat(_codeOf(_src('lib/screens/user/my_applications_screen.dart')));
      expect(s.contains("? '공고 정보를 불러오지 못했어요'"), true);
      expect(s.contains('final isDeleted = to == null && !loadFailed;'), true);
    });

    test('관리자 목록은 네 상태를 유지한다', () {
      final c = _src('lib/controllers/workforce_controller.dart');
      expect(c.contains('Object? _loadError;'), true);
      expect(c.contains('Object? get loadError => _loadError;'), true);
    });
  });

  group('만든 것을 바로 확인할 수 있다', () {
    test('등록 후 그 공고를 목록에서 드러낸다', () {
      final s = _flat(_codeOf(
          _src('lib/screens/business_admin/to_management/create_to_screen.dart')));
      expect(s.contains('AdminTabSwitcher.instance.switchToJobsWithTarget(toId);'), true,
          reason: '목록만 새로고침하면 방금 만든 것이 어느 것인지 알 수 없다');
    });

    test('알림 deep link가 쓰던 경로를 그대로 쓴다', () {
      // 새 reveal 경로를 만들면 두 경로가 서로 다르게 동작하게 된다.
      final t = _flat(_codeOf(_src('lib/utils/admin_tab_switcher.dart')));
      expect(t.contains('bool switchToJobsWithTarget(String toId) {'), true);
      expect(t.contains('if (!switchToTab(jobsTab)) return false;'), true,
          reason: '보여줄 수 없는 화면에 reveal 상태만 남기지 않는다');
    });

    test('지원자 화면 미리보기가 관리자에게 열려 있다', () {
      final card = _flat(_codeOf(
          _src('lib/widgets/admin/cards/admin_to_item_card.dart')));
      expect(card.contains("label: '지원자 화면 미리보기',"), true);
      expect(card.contains('mode: TODetailMode.adminPreview,'), true);
    });

    test('미리보기에 지원 행동이 없다', () {
      final s = _flat(_codeOf(_src('lib/screens/common/job_posting_screen.dart')));
      expect(s.contains('if (widget.mode == TODetailMode.adminPreview) { return const SizedBox.shrink(); }'),
          true, reason: '관리자가 근로자 권한을 얻는 화면이 되면 안 된다');
      expect(s.contains('final canSelect = widget.mode == TODetailMode.applicant && !isClosed;'), true);
      expect(s.contains("_applicantUid = widget.mode == TODetailMode.applicant"), true);
    });
  });

  group('공고 생명주기는 한 권한으로 묶인다', () {
    test('생성·수정·마감·재개·삭제가 모두 canManageTo를 본다', () {
      for (final n in ['callableCreateTO', 'callableUpdateSlotWorkDetails',
        'callableCloseSlots', 'callableReopenSlots', 'callableDeleteTO',
        'callableCreateFlexSlots', 'callablePublishTO']) {
        final f = _flat(_codeOf(_callableOf(raw, n)));
        expect(f.contains('canManageTo'), true, reason: '$n 에 권한 검사가 없다');
      }
    });

    test('슬롯 조작은 공고의 사업장과 교차검증한다', () {
      final close = _flat(_codeOf(_callableOf(raw, 'callableCloseSlots')));
      expect(close.contains('해당 TO가 요청한 사업장에 속하지 않습니다'), true,
          reason: 'businessId만 바꿔 남의 공고를 닫을 수 있으면 안 된다');
    });
  });
}
