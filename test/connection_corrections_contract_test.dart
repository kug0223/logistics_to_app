// [SYSTEM-INTEGRATION-R2.2] FULL apply 계약 + 연결 Journey CORRECTION
//
// 1) posting-wide FULL이 shortage 날짜의 지원까지 막았다.
//
//    syncTOStats는 공고 전체 합계로 TO.status를 FULL로 올린다. FLEX는 날짜마다
//    자리를 따로 세는데 callableApplyToTO가 그 공고 전체 값을 관문으로 썼다.
//
//      9/21 필요3 확정3 → 마감
//      9/22 필요3 확정1 → 2명 필요   ← 여기까지 `마감된 공고입니다`
//
//    공고 목록에는 계속 보이므로(callableGetPublishedTOs는 FULL도 노출)
//    들어가서 지원하면 이유 없이 거부되는 상태였다.
//    R2 보고의 "FULL이 shortage 날짜를 숨기지 않는다"는 **목록 노출**에 한한
//    말이었고, mutation은 막혀 있었다.
//
//    DEV 실측(수정 후):
//      CASE A 9/21 → `해당 업무의 모집 인원이 마감되었습니다` (prerequisite 아님)
//      CASE B 9/22 → PENDING 생성, 그 wdId pendingCount +1, 9/21 불변
//
// 2) FULL이 된 모집 단위의 초대가 근로자에게 여전히 `수락하기`로 보였다.
//    서버는 정확히 막지만 눌러야 실패를 아는 action이었다.
//
// 3) REJECTED 하나에 관리자 거절과 근로자의 초대 거절이 같이 들어 있었다.
//
// 4) 초대 후보 목록이 membership만으로 열렸고(초대 자체는 canManageTo 필요),
//    판단 정보가 가려진 이름·지역·주간 횟수뿐이었다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _after(String source, String signature, [int chars = 2000]) {
  final a = source.indexOf(signature);
  if (a == -1) throw StateError('$signature 를 찾지 못함');
  final end = a + chars;
  return source.substring(a, end > source.length ? source.length : end);
}

String _tsSliceOf(String source, String from, String to) {
  final a = source.indexOf(from);
  if (a == -1) throw StateError('$from 를 찾지 못함');
  final b = source.indexOf(to, a + from.length);
  if (b == -1) throw StateError('$to 를 찾지 못함');
  return source.substring(a, b);
}

const _cfPath = 'functions/src/index.ts';
const _myAppsPath = 'lib/screens/user/my_applications_screen.dart';
const _candSheetPath =
    'lib/screens/business_admin/dialogs/available_workers_bottom_sheet.dart';
const _candModelPath = 'lib/models/core/available_worker_model.dart';
const _appModelPath = 'lib/models/core/application_model.dart';

void main() {
  final cf = _codeOf(_src(_cfPath));

  // ═════════════════════════════════════════════════════════════
  // 1. FULL은 모집 단위의 상태다
  // ═════════════════════════════════════════════════════════════
  group('R2.2-01 apply gate unit', () {
    final apply = _tsSliceOf(cf, 'export const callableApplyToTO',
        'export const callableGetMyApplications');

    test('01-a 슬롯 지원에는 공고 전체 FULL을 관문으로 쓰지 않는다', () {
      expect(apply.contains('const applyIsSlotBased ='), isTrue);
      expect(
        apply.contains('(toData["status"] === "FULL" && !applyIsSlotBased)'),
        isTrue,
      );
    });

    test('01-b 공고 전체를 닫는 사건은 그대로 막는다', () {
      // isManualClosed / CLOSED / SCHEDULED는 날짜와 무관하다.
      for (final g in [
        'toData["isManualClosed"] === true',
        'toData["status"] === "CLOSED"',
        'toData["status"] === "SCHEDULED"',
      ]) {
        expect(apply.contains(g), isTrue, reason: g);
      }
    });

    test('01-c 날짜 단위 관문이 살아 있다', () {
      // 공고 전체 FULL을 뺀 자리를 이 둘이 대신한다.
      expect(apply.contains('해당 날짜는 마감되었습니다'), isTrue);
      expect(apply.contains('해당 업무의 모집 인원이 마감되었습니다'), isTrue);
    });

    test('01-d 슬롯 없는 공고(CONTRACT)는 기존대로', () {
      // applyIsSlotBased가 false면 FULL이 그대로 관문이 된다.
      final at = apply.indexOf('const applyIsSlotBased =');
      final decl = apply.substring(at, at + 120);
      expect(decl.contains('typeof slotId === "string" && slotId.length > 0'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 2. stale invitation
  // ═════════════════════════════════════════════════════════════
  group('R2.2-02 stale invitation', () {
    test('02-a 서버가 INVITED에 모집 완료 여부를 실어 준다', () {
      final fn = _tsSliceOf(cf, 'export const callableGetMyApplications',
          'export const callableGetMyInvitations');
      expect(fn.contains('workInstanceFull'), isTrue);
      expect(fn.contains('getWorkDetailCount'), isTrue);
      // INVITED 문서에만 계산 — 일반 조회에 추가 read를 만들지 않는다
      expect(fn.contains('d.data()["status"] === "INVITED"'), isTrue);
    });

    test('02-b 새 status enum을 만들지 않았다', () {
      final model = _codeOf(_src(_appModelPath));
      for (final s in ['INVITE_FULL', 'FULL_INVITE', 'invitedFull']) {
        expect(model.contains(s), isFalse);
      }
      // 상태는 INVITED 그대로, 사실만 덧붙인다.
      // [R2.2.1] bool → 3-state. status enum은 여전히 만들지 않는다.
      expect(
          model.contains(
              'final InviteCapacityState workInstanceCapacityState;'),
          isTrue);
    });

    test('02-c Firestore 필드가 아니라 조회 시점 계산값이다', () {
      final model = _codeOf(_src(_appModelPath));
      expect(
          model.contains(
              "_parseCapacityState(data['workInstanceCapacityState'])"),
          isTrue);
      // toMap에 실어 저장하면 stale 값이 문서에 굳는다
      final toMapAt = model.indexOf("'inviteExpiresAt': inviteExpiresAt");
      final toMap = model.substring(toMapAt, toMapAt + 400);
      expect(toMap.contains('workInstanceFull'), isFalse);
      expect(toMap.contains('workInstanceCapacityState'), isFalse);
    });

    test('02-d 모집이 찬 초대에는 수락 CTA가 없다', () {
      final code = _codeOf(_src(_myAppsPath));
      const guard =
          'if (app.workInstanceCapacityState == InviteCapacityState.full) {';
      // [R2.2.1] full 다음에 unknown 분기가 생겼다 — 경계는 그 시작이다.
      //   `return Column(`으로 자르면 분기 자신의 return에서 끊긴다.
      const nextGuard =
          'if (app.workInstanceCapacityState == InviteCapacityState.unknown) {';
      expect(code.contains(guard), isTrue);
      expect(code.contains("'모집이 완료된 초대예요'"), isTrue);
      final at = code.indexOf(guard);
      final end = code.indexOf(nextGuard, at);
      expect(end, greaterThan(at), reason: 'UNKNOWN 분기가 full 뒤에 없다');
      final branch = code.substring(at, end);
      expect(branch.contains("label: '수락하기'"), isFalse);
      // 거절(정리)은 계속 가능해야 한다
      expect(branch.contains('_declineInvite(app.id)'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 3. decline vs admin rejection
  // ═════════════════════════════════════════════════════════════
  group('R2.2-03 decline vs rejection', () {
    final code = _codeOf(_src(_myAppsPath));

    test('03-a 이미 있는 canonical 신호로 구분한다', () {
      // invitedAt은 callableInviteWorker만 기록한다 — 후보 자격 검사도 같은 신호를 쓴다.
      expect(code.contains('if (app.invitedAt != null)'), isTrue);
    });

    test('03-b 내가 거절한 초대를 거절당한 것처럼 쓰지 않는다', () {
      expect(code.contains("'초대를 거절했어요'"), isTrue);
      expect(code.contains("label: '초대 거절'"), isTrue);
    });

    test('03-c 관리자 거절 문구는 그대로 남는다', () {
      expect(code.contains("'이번 지원은 확정되지 않았어요'"), isTrue);
      expect(code.contains("label: '거절'"), isTrue);
    });

    test('03-d 새 status enum을 만들지 않았다', () {
      final model = _codeOf(_src(_appModelPath));
      expect(model.contains('inviteDeclined'), isFalse);
      expect(model.contains('INVITE_REJECTED'), isFalse);
    });

    test('03-e 상태 칩이 application을 함께 본다', () {
      expect(code.contains('_StatusInfo _statusInfo(String status, {ApplicationModel? app})'),
          isTrue);
      expect(code.contains('_statusInfo(app.status, app: app)'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 4. candidate decision context
  // ═════════════════════════════════════════════════════════════
  group('R2.2-04 candidate detail', () {
    final cand = _tsSliceOf(cf, 'export const callableGetAvailableWorkers',
        'export const callableGetMyScheduleChanges');

    test('04-a 후보 조회 권한 = canManageTo (초대 action과 같은 capability)', () {
      expect(cand.contains('awPerms?.canManageTo !== true'), isTrue);
      expect(cand.contains('"TO 관리 권한이 없습니다."'), isTrue);
    });

    test('04-b 지원 검토와 같은 allowlist 한 벌을 쓴다', () {
      expect(cf.contains('const APPLICANT_REVIEW_ALLOWED = new Set(['), isTrue);
      // 모듈 레벨로 올라가 두 곳이 같은 상수를 참조한다
      final n = RegExp(r'APPLICANT_REVIEW_ALLOWED\.has\(').allMatches(cf).length;
      expect(n, 2, reason: '지원 검토 projection과 후보 projection 두 곳');
    });

    test('04-c 이름은 마스킹 값으로 덮고 연락처는 뺀다', () {
      expect(cand.contains('profile["name"] = maskedName'), isTrue);
      for (final f in ['"phone"', '"contactPhone"', '"authPhone"', '"koreanName"']) {
        expect(cand.contains('delete profile[$f]'), isTrue, reason: f);
      }
    });

    test('04-d Timestamp를 그대로 내보내지 않는다', () {
      expect(cand.contains('profile: serializeFirestoreData(profile)'), isTrue);
    });

    test('04-e 새 프로필 화면을 만들지 않고 기존 상세를 연다', () {
      final sheet = _codeOf(_src(_candSheetPath));
      expect(sheet.contains('WorkerDetailDialog.show('), isTrue);
      expect(sheet.contains('isConfirmed: false'), isTrue);
      expect(sheet.contains('showApprovalButtons: false'), isTrue);
    });

    test('04-f 상세 tap과 초대 action이 분리돼 있다', () {
      final sheet = _codeOf(_src(_candSheetPath));
      final body = _after(sheet, 'Widget _buildCandidateRow(AvailableWorkerModel worker)', 1600);
      expect(body.contains('onTap: worker.profile == null'), isTrue);
      expect(body.contains('_openCandidateDetail(worker)'), isTrue);
    });

    test('04-g 구버전 서버 응답이면 상세를 열지 않는다', () {
      final model = _codeOf(_src(_candModelPath));
      expect(model.contains('final Map<String, dynamic>? profile;'), isTrue);
      expect(model.contains("m['profile'] is Map"), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 5. 관리자 초대 현황 (addendum)
  // ═════════════════════════════════════════════════════════════
  group('R2.2-05 manager invitation tracking', () {
    final svc = _codeOf(_src('lib/services/firestore/application_firestore.dart'));
    final dlg = _codeOf(_src('lib/screens/business_admin/dialogs/day_applicants_dialog.dart'));

    test('05-a 초대를 지원과 별도로 읽는다', () {
      expect(svc.contains('getDayInvitationsByDateAndBusiness'), isTrue);
      final b = _after(svc, 'getDayInvitationsByDateAndBusiness({', 1600);
      // 초대로 시작한 문서만 — 관리자 거절·사용자 취소는 초대 기록이 아니다
      expect(b.contains('a.invitedAt != null'), isTrue);
      expect(b.contains('AppStatus.invited'), isTrue);
    });

    test('05-b 조회 실패를 초대 0건으로 바꾸지 않는다', () {
      final b = _after(svc, 'getDayInvitationsByDateAndBusiness({', 1600);
      expect(b.contains('return [];'), isFalse);
      expect(dlg.contains("'초대 현황을 확인하지 못했어요'"), isTrue);
      expect(dlg.contains('if (_dayInvitations == null)'), isTrue);
    });

    test('05-c 지원 대기와 초대 중을 합치지 않는다', () {
      final b = _after(dlg, 'Widget _buildGroupStats(BuildContext context, _GroupData g)', 2200);
      expect(b.contains(r"'지원 $pending'"), isTrue);
      // [R2.2.1] 세는 대상이 좁아졌다 — 자리가 차서 지금은 수락될 수 없는 초대는
      //   active count에서 빠진다. 지원/초대를 분리한다는 계약은 그대로다.
      expect(b.contains(r"'초대 ${g.activeInvites.length}'"), isTrue);
      // 합쳐진 표기가 남아 있으면 안 된다
      expect(b.contains(r"'+$pending'"), isFalse);
    });

    test('05-d 초대는 work instance 단위로 묶는다 (사람 단위 아님)', () {
      final b = _after(dlg, 'void addInvite(ApplicationModel app)', 1400);
      expect(b.contains(r"'${app.toId ?? app.toTitle}_$wKey'"), isTrue);
      expect(b.contains('app.wdId'), isTrue);
      // 사람(uid) 단위로 묶으면 한 날짜 거절이 다른 날짜까지 물들인다
      expect(b.contains('groups[app.uid]'), isFalse);
    });

    test('05-e 상태는 canonical status에서 읽는다 — 새 enum 없음', () {
      // [R2.2.1] capacity를 함께 본다 — 시그니처에 isFull이 붙었다.
      final b = _after(dlg, '(String, Color) _inviteStateLabel(', 1400);
      for (final s in ['초대 중', '초대 거절', '초대 철회', '응답 만료']) {
        expect(b.contains(s), isTrue, reason: s);
      }
      expect(b.contains('SCHEDULE_CONFLICT'), isTrue);
    });

    test('05-f 응답 대기 → 최근 응답 순서, 전체 기록을 펼치지 않는다', () {
      // [R2.2.1 / R2 FINAL] 섹션이 늘었다 (모집 완료 · 모집 종료 · 상태 확인 불가).
      final b = _after(dlg,
          'Widget _buildInviteSection(BuildContext context, _GroupData g)', 3400);
      final out = b.indexOf('초대 중 (');
      // [R2.2.1] `최근 응답` → `최근 초대 응답`. 수락도 함께 서기 때문에
      //   무엇에 대한 응답인지 이름에 남긴다.
      final recent = b.indexOf('최근 초대 응답');
      expect(out, greaterThan(0));
      expect(recent, greaterThan(out));
      expect(b.contains('closed.take(3)'), isTrue);
    });

    test('05-g 누구에게 언제 보냈는지 보인다', () {
      final b = _after(dlg, 'Widget _buildInviteRow(', 2000);
      expect(b.contains('app.invitedAt'), isTrue);
      expect(b.contains('발송'), isTrue);
    });

    test('05-h 권한 없으면 ERROR가 아니라 조회하지 않는다', () {
      expect(dlg.contains('final canSeeInvites = _canForSelectedBiz((p) => p.canManageTo)'), isTrue);
    });

    test('05-i 초대만 있는 날도 목록을 그린다', () {
      final b = _after(dlg, 'Widget _buildBody(BuildContext context)', 1600);
      expect(b.contains('_dayInvitations?.isNotEmpty ?? false'), isTrue);
    });
  });
}
