// [CROSS-DOMAIN-R5.3A] 파트변경 direct mutation 동결
//
// `[BLOCKER-WORK-PART-DIRECT-MUTATION]`
//
// R5.3 READ에서 확인한 것 — `callableChangeApplicationWorkType`은 확정된 약속을
// 관리자 혼자 덮어썼다:
//
//   · 서명 완료(completed) 계약의 workType·wage를 소급 수정했다.
//     서명본 PDF는 그대로라 문서와 레코드가 갈린다.
//   · 출근 기록이 있어도 Application을 바꿨다 — 지난 사실을 다시 썼다.
//   · wdId를 갱신하지 않아 화면은 B, 집계는 A로 갈렸다
//     (workDetailCounts·syncTOStats는 전부 wdId 기준).
//   · target의 FULL/CLOSED를 읽지 않아 마감된 업무로도 옮길 수 있었다.
//   · 시간이 다른 업무로 옮겨도 겹침을 다시 보지 않았다.
//   · PENDING 지원자의 지원 조건을 동의 없이 바꾸고 사후 통보했다.
//
// 업무를 옮기는 일 자체는 필요하다. 다만 그건 **제안이고 근로자가 수락**해야
// 성립한다 — 초대(INVITED)가 이미 그 모양이다. 그 구조로 옮기기 전까지
// 이 경로는 아무것도 쓰지 않고 거절한다.
//
// DEV 실측(PASS 15/0):
//   legacy 호출 → 400 "파트변경은 더 이상 지원되지 않습니다…"
//   Application·counter·Contract·Attendance diff 0, workTypeChanged 알림 0
//   그리고 A PENDING이 있어도 같은 TO의 다른 WD로 초대가 만들어진다
//   (B = {toId}_{slotId}_{wdId}_{uid}, INVITED, A는 PENDING 유지)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _load(String p) => _flat(_codeOf(_src(p)));

String _callableBody(String raw, String name) {
  final start = raw.indexOf('export const $name = onCall(');
  if (start < 0) throw StateError('$name 을 찾지 못함');
  final end = raw.indexOf('\n);', start);
  if (end < 0) throw StateError('$name 본문 끝을 찾지 못함');
  return raw.substring(start, end);
}

const _cf = 'functions/src/index.ts';
const _workDlg = 'lib/screens/business_admin/dialogs/work_applicants_dialog.dart';
const _dayDlg = 'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';
const _appSvc = 'lib/services/firestore/application_firestore.dart';

void main() {
  final rawCf = _codeOf(_src(_cf));
  final cf = _flat(rawCf);
  final frozen = _flat(_callableBody(rawCf, 'callableChangeApplicationWorkType'));

  // ── PART A. 서버 freeze ────────────────────────────────────────────

  group('서버가 아무것도 쓰지 않고 거절한다', () {
    test('deterministic reject', () {
      expect(
          frozen.contains('throw new HttpsError( "failed-precondition", '
              '"파트변경은 더 이상 지원되지 않습니다.'),
          true);
    });

    test('거절이 어떤 읽기·쓰기보다 먼저다', () {
      final throwAt = frozen.indexOf('파트변경은 더 이상 지원되지 않습니다');
      expect(throwAt, greaterThan(-1));
      final head = frozen.substring(0, throwAt);
      for (final forbidden in [
        'db.collection(', 'runTransaction', 'assertBizAdmin', 'bulkWriter',
      ]) {
        expect(head.contains(forbidden), false, reason: '거절 전에 $forbidden');
      }
    });

    test('옛 구현이 남아 있지 않다', () {
      // mutation 코드가 파일 어디에도 되살아나지 않게 고정한다.
      expect(cf.contains('const TERMINAL_APP_STATUSES = new Set(["REJECTED", '
          '"CANCELED", "AUTO_CANCELED", "COMPLETED", "NO_SHOW"]);'), false);
      expect(cf.contains('attendanceResetCount'), false);
      expect(cf.contains('_deprecatedChangeApplicationWorkTypeImpl'), false);
    });

    test('신규 workTypeChanged emitter가 없다', () {
      expect(cf.contains('type: "workTypeChanged"'), false,
          reason: '사후 통보 알림을 더 만들지 않는다');
    });

    test('권한 정책 자체는 남아 있다', () {
      // canManageTo 계약은 다른 경로에서 그대로 쓰인다 — 기능만 내렸다.
      expect(cf.contains('"TO 관리 권한이 없습니다."'), true);
    });
  });

  // ── PART A. 클라이언트 freeze ──────────────────────────────────────

  group('클라이언트에 호출 경로가 없다', () {
    test('업무별 지원자 다이얼로그에 CTA가 없다', () {
      final s = _load(_workDlg);
      expect(s.contains("label: '파트변경',"), false);
      expect(s.contains('_showChangeWorkPartDialog('), false);
    });

    test('날짜별 지원자 다이얼로그에 CTA가 없다', () {
      final s = _load(_dayDlg);
      expect(s.contains("label: '파트변경',"), false);
      expect(s.contains('_showChangeWorkPartDialog('), false);
    });

    test('서비스 래퍼가 제거됐다', () {
      final s = _load(_appSvc);
      expect(s.contains('changeApplicationWorkType'), false);
      expect(s.contains("httpsCallable('callableChangeApplicationWorkType'"), false);
    });

    test('lib 어디에도 호출이 남아 있지 않다', () {
      final hits = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final code = _codeOf(f.readAsStringSync());
        if (code.contains('callableChangeApplicationWorkType') ||
            code.contains('changeApplicationWorkType(')) {
          hits.add(f.path);
        }
      }
      expect(hits, isEmpty, reason: hits.join(', '));
    });
  });

  // ── legacy 알림 호환 유지 ──────────────────────────────────────────

  group('legacy workTypeChanged는 읽기 호환을 유지한다', () {
    test('enum과 parser가 남아 있다', () {
      final m = _load('lib/models/core/notification_model.dart');
      expect(m.contains('workTypeChanged,'), true);
      expect(m.contains("case 'workTypeChanged': return NotificationType.workTypeChanged;"),
          true, reason: '과거 알림을 읽지 못하게 되면 안 된다');
    });

    test('deep-link reader도 남아 있다', () {
      expect(_load('lib/screens/common/notification_screen.dart')
          .contains('case NotificationType.workTypeChanged:'), true);
      expect(_load('lib/services/fcm_service.dart')
          .contains("case 'workTypeChanged':"), true);
    });
  });

  // ── PART B/C. natural key 계약 ─────────────────────────────────────

  group('Application natural key는 wdId 기반이다', () {
    test('지원 경로가 wdId를 discriminator로 쓴다', () {
      final apply = _flat(_callableBody(rawCf, 'callableApplyToTO'));
      expect(
          apply.contains('const complexId = slotId ? '
              '`\${toId}_\${slotId}_\${discriminator}_\${uid}` : '
              '`\${toId}_\${discriminator}_\${uid}`;'),
          true);
    });

    test('초대 경로도 같은 모양이다', () {
      final invite = _flat(_callableBody(rawCf, 'callableInviteWorker'));
      expect(
          invite.contains('const inviteComplexId = slotId ? '
              '`\${toId}_\${slotId}_\${inviteDiscriminator}_\${targetUid}` : '
              '`\${toId}_\${inviteDiscriminator}_\${targetUid}`;'),
          true);
      expect(
          invite.contains('const inviteDiscriminator = '
              '(inviteResolvedWdId && inviteResolvedWdId.length > 0) ? '
              'inviteResolvedWdId : (selectedWorkType ?? "unknown");'),
          true,
          reason: 'wdId 우선, 없을 때만 workType 폴백');
    });

    test('docId는 만들 때 정해지고 바뀌지 않는다', () {
      // rename 경로가 없다는 것을 고정 — A의 wdId를 B로 rewrite하는 설계 금지.
      expect(cf.contains('.rename('), false);
    });
  });

  group('A PENDING은 같은 TO의 다른 업무 초대를 막지 않는다', () {
    test('중복 가드 목록에 PENDING이 없다', () {
      final invite = _flat(_callableBody(rawCf, 'callableInviteWorker'));
      expect(
          invite.contains('.where("status", "in", ["INVITED", "CONFIRMED", '
              '"CONTRACT_PENDING", "REJECTED", "EXPIRED"])'),
          true,
          reason: 'PENDING이 들어가면 다른 업무 제안 자체가 불가능해진다');
    });

    test('재초대 허용 상태가 명시돼 있다', () {
      final invite = _flat(_callableBody(rawCf, 'callableInviteWorker'));
      expect(invite.contains('const REINVITABLE = ["REJECTED", "CANCELED", "AUTO_CANCELED"];'),
          true);
    });
  });

  // ── PART F. counter 의미 ───────────────────────────────────────────

  group('pending 카운터는 PENDING과 INVITED를 함께 센다', () {
    test('재계산 기준이 두 상태다', () {
      expect(cf.contains('const PENDING_STATUSES = ["PENDING", "INVITED"];'), true);
      expect(cf.contains('.where("status", "in", PENDING_STATUSES).count().get()'), true,
          reason: '증분 writer와 재계산이 같은 정의를 써야 한다');
    });
  });
}
