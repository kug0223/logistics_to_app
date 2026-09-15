// [SYSTEM-INTEGRATION-R2.2.1] 관리자 초대 운영 종결 계약
//
// R2.2에서 관리자에게 초대 현황이 생겼지만 두 운영 의미가 열려 있었다.
//
// 1) FULL 이후 남은 INVITED가 관리자에게 계속 `초대 중`이었다.
//
//      Application = INVITED
//      work instance = FULL
//      근로자 화면   = 모집이 완료된 초대예요 / 수락 CTA 없음
//      서버         = 수락 거부 (정원이 초과되었습니다)
//      관리자 화면   = 초대 중            ← 같은 사실을 다르게 말했다
//
//    관리자는 오지 않을 응답을 기다리게 된다. 그동안 그 자리는 이미 찼으므로
//    기다릴 것이 없다.
//
//    고치는 방법은 status를 바꾸는 것이 아니다. 자리가 다시 열리면 같은 초대가
//    다시 수락 가능해지는 현재 정책을 보존해야 하므로, 저장된 INVITED는 그대로
//    두고 **조회 시점 capacity**로 의미만 가른다 — 근로자 화면의
//    workInstanceFull과 같은 방식이다.
//
// 2) 초대를 수락한 사람이 관리자 쪽에서 그냥 `확정자`였다.
//
//      A  PENDING → 관리자 승인 → 확정
//      B  INVITED → 근로자 수락 → 확정
//
//    둘 다 자리를 가져갔지만 발생 경로가 다르다. B가 확정 명단에만 남으면
//    관리자는 자기가 보낸 초대가 어떻게 끝났는지 추적할 수 없다.
//    새 enum 없이 invitedAt으로 구분한다 — callableInviteWorker만 쓰고
//    callableAcceptTOInvitation은 지우지 않는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/ui/invite_capacity_state.dart';

/// `_GroupData.activeInvites`와 같은 규칙 — capacity가 available일 때만 센다.
int _activeCount({required InviteCapacityState capacity, required int invited}) =>
    capacity == InviteCapacityState.available ? invited : 0;

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

const _dayPath = 'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';
const _rowPath = 'lib/models/ui/day_staffing_row.dart';
const _invSvcPath = 'lib/services/firestore/application_firestore.dart';
const _myAppsPath = 'lib/screens/user/my_applications_screen.dart';
const _appModelPath = 'lib/models/core/application_model.dart';

const _guardFull =
    'if (app.workInstanceCapacityState == InviteCapacityState.full) {';
const _guardUnknown =
    'if (app.workInstanceCapacityState == InviteCapacityState.unknown) {';

/// INVITED 분기는 full → unknown → available(폴백) 순서다. 각 분기의 경계를
/// 다음 분기의 시작으로 잡는다. `return Column(`으로 자르면 분기 자신의
/// return에서 끊긴다.
String _fullBranch(String code) {
  final a = code.indexOf(_guardFull);
  final b = code.indexOf(_guardUnknown);
  expect(a, greaterThan(0), reason: 'full 분기를 찾지 못함');
  expect(b, greaterThan(a), reason: 'unknown 분기가 full 뒤에 없다');
  return code.substring(a, b);
}

String _unknownBranch(String code) {
  final a = code.indexOf(_guardUnknown);
  final b = code.indexOf('근무 초대가 도착했어요'); // available 분기의 첫 문구
  expect(a, greaterThan(0), reason: 'unknown 분기를 찾지 못함');
  expect(b, greaterThan(a), reason: 'available 분기가 unknown 뒤에 없다');
  return code.substring(a, b);
}
const _cfPath = 'functions/src/index.ts';

void main() {
  final dayRaw = _src(_dayPath);
  final day = _codeOf(dayRaw);
  final cf = _codeOf(_src(_cfPath));

  // ═════════════════════════════════════════════════════════════
  // 1. 관리자와 근로자가 같은 canonical capacity를 본다
  // ═════════════════════════════════════════════════════════════
  group('R2.2.1-01 canonical capacity 공유', () {
    test('01-a 관리자 FULL 판정은 slot이 준 confirmedCount를 쓴다', () {
      // 지원서를 세지 않는다. 지원서에서 유도하면 근로자 화면(slot 기준)과
      // 갈라져 한쪽은 `수락 불가`, 다른 쪽은 `초대 중`이 된다.
      expect(day.contains('int? canonicalConfirmed;'), isTrue);
      expect(day.contains('existing.canonicalConfirmed = row.confirmedCount;'),
          isTrue);
      expect(day.contains('..canonicalConfirmed = row.confirmedCount;'), isTrue);
    });

    test('01-b DayStaffingRow.confirmedCount는 workDetailCounts에서 온다', () {
      final detail = _tsSliceOf(
          cf, 'export const callableGetDayStaffingDetail', 'return {rows};');
      expect(detail.contains('sd["workDetailCounts"]'), isTrue);
      expect(
          detail.contains('confirmedCount: Math.max(0, wdc[wdId]?.confirmedCount ?? 0)'),
          isTrue);
      expect(_src(_rowPath).contains('final int confirmedCount;'), isTrue);
    });

    test('01-c 근로자 capacity 판정도 같은 join을 쓴다', () {
      final mine = _tsSliceOf(cf, 'const invitedDocs = docs.filter', 'return {');
      expect(mine.contains('getWorkDetailCount(sd, wd)'), isTrue);
      expect(
          mine.contains(
              'capStateMap[d.id] = (req > 0 && conf >= req) ? "full" : "available";'),
          isTrue);
    });

    test('01-d 관리자 판정식이 서버 판정식과 같다 (req > 0 && conf >= req)', () {
      // 순수 함수라 직접 검증한다.
      expect(
          inviteCapacityStateOf(canonicalConfirmed: 2, requiredCount: 3),
          InviteCapacityState.available);
      expect(
          inviteCapacityStateOf(canonicalConfirmed: 3, requiredCount: 3),
          InviteCapacityState.full);
      expect(
          inviteCapacityStateOf(canonicalConfirmed: 4, requiredCount: 3),
          InviteCapacityState.full);
      // req == 0 → 서버도 full로 보지 않는다 (`req > 0 &&`).
      expect(
          inviteCapacityStateOf(canonicalConfirmed: 0, requiredCount: 0),
          InviteCapacityState.available);
    });

    test('01-e canonical row가 없으면 FULL로도 여유로도 단정하지 않는다', () {
      // UNKNOWN != FULL, UNKNOWN != AVAILABLE.
      for (final req in const [0, 1, 3]) {
        final s = inviteCapacityStateOf(
            canonicalConfirmed: null, requiredCount: req);
        expect(s, InviteCapacityState.unknown, reason: 'req=$req');
        expect(s == InviteCapacityState.available, isFalse);
        expect(s == InviteCapacityState.full, isFalse);
      }
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 1b. [CORRECTION] UNKNOWN이 available로 새지 않는다
  //
  //   `bool?` + `!= true`가 원인이었다. Dart에서 `null != true`는 true라
  //   인력 현황을 읽지 못한 상태가 `자리 있음`으로 흘러들었다.
  // ═════════════════════════════════════════════════════════════
  group('R2.2.1-01b UNKNOWN != AVAILABLE', () {
    test('01b-a 판정 타입이 nullable bool이 아니다', () {
      // nullable bool이면 `!= true` 한 줄로 두 상태가 다시 뭉쳐질 수 있다.
      expect(day.contains('bool? get isWorkInstanceFull'), isFalse,
          reason: 'nullable bool 판정이 되살아났다');
      expect(day.contains('InviteCapacityState get capacityState'), isTrue);
    });

    test('01b-b capacity를 읽는 predicate에 `!= true` / `!= false`가 없다', () {
      // 세 갈래는 각각 `== available` / `== full` / `== unknown`으로만 쓴다.
      final hits = day
          .split('\n')
          .where((l) =>
              l.contains('capacityState') || l.contains('isWorkInstanceFull'))
          .where((l) => l.contains('!=') || l.contains('!g.') || l.contains('!_'))
          .toList();
      expect(hits, isEmpty, reason: 'UNKNOWN을 뭉뚱그리는 부정 비교가 남았다: $hits');
    });

    test('01b-c 세 갈래가 서로 배타적이고 빠짐없다', () {
      for (final f in const [
        [null, 3],
        [0, 3],
        [3, 3],
        [1, 0],
        [null, 0],
      ]) {
        final s = inviteCapacityStateOf(
            canonicalConfirmed: f[0], requiredCount: f[1]!);
        final flags = [
          s == InviteCapacityState.available,
          s == InviteCapacityState.full,
          s == InviteCapacityState.unknown,
        ];
        expect(flags.where((x) => x).length, 1, reason: '$f → $s');
      }
    });

    test('01b-d 세 fixture — active invite 집계', () {
      // capacity false → 1 / true → 0 / null → 0 (세지 않는다)
      expect(_activeCount(capacity: InviteCapacityState.available, invited: 1), 1);
      expect(_activeCount(capacity: InviteCapacityState.full, invited: 1), 0);
      expect(_activeCount(capacity: InviteCapacityState.unknown, invited: 1), 0);
    });

    test('01b-e UNKNOWN은 초대를 세지 않되 지우지도 않는다', () {
      // `초대 ?` — 초대가 떠 있다는 사실은 사실이다. 숫자만 주장하지 않는다.
      expect(day.contains('if (g.unknownInvites.isNotEmpty)'), isTrue);
      expect(day.contains(r"'초대 ?'"), isTrue);
      expect(day.contains(r"'상태 확인 불가 (${unknown.length}명)'"), isTrue);
    });

    test('01b-f UNKNOWN에서는 충원 CTA가 서지 않고 이유를 말한다', () {
      expect(day.contains('g.capacityState == InviteCapacityState.available &&'),
          isTrue, reason: 'CTA가 available일 때만 서야 한다');
      expect(day.contains('_buildCapacityUnknownNotice'), isTrue);
      expect(day.contains('인력 현황을 확인하지 못해 충원이 필요한지 알 수 없어요'), isTrue);
    });

    test('01b-g UNKNOWN 초대 행은 `초대 중`도 `모집 완료`도 아니다', () {
      final label = _after(dayRaw, '(String, Color) _inviteStateLabel', 900);
      expect(label.contains('case InviteCapacityState.available:'), isTrue);
      expect(label.contains('case InviteCapacityState.full:'), isTrue);
      expect(label.contains('case InviteCapacityState.unknown:'), isTrue);
      expect(label.contains("return ('상태 확인 불가'"), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 2. FULL stale invitation — 저장 status는 건드리지 않는다
  // ═════════════════════════════════════════════════════════════
  group('R2.2.1-02 stale invitation', () {
    test('02-a 표시를 위해 INVITED를 다른 status로 쓰지 않는다', () {
      // 자리가 다시 열리면 이 초대는 다시 수락 가능해야 한다.
      // 화면 때문에 CANCELED로 바꾸면 그 정책이 사라진다.
      for (final banned in const [
        "status: 'CANCELED'",
        "'INVITE_STALE'",
        "'UNACCEPTABLE'",
        'AppStatus.inviteStale',
      ]) {
        expect(day.contains(banned), isFalse, reason: '$banned 가 추가됐다');
      }
    });

    test('02-b FULL이면 activeInvites가 비고 staleInvites로 간다', () {
      final active = _after(dayRaw, 'List<ApplicationModel> get activeInvites', 200);
      expect(
          active.contains(
              'capacityState == InviteCapacityState.available ? invitedApps : const []'),
          isTrue);
      final stale = _after(dayRaw, 'List<ApplicationModel> get staleInvites', 200);
      expect(
          stale.contains(
              'capacityState == InviteCapacityState.full ? invitedApps : const []'),
          isTrue);
      final unknown =
          _after(dayRaw, 'List<ApplicationModel> get unknownInvites', 200);
      expect(
          unknown.contains(
              'capacityState == InviteCapacityState.unknown ? invitedApps : const []'),
          isTrue);
    });

    test('02-c FULL 초대의 라벨이 `초대 중`이 아니다', () {
      final label = _after(dayRaw, '(String, Color) _inviteStateLabel', 900);
      expect(label.contains('case InviteCapacityState.full:'), isTrue);
      expect(label.contains("return ('모집 완료 · 수락 불가'"), isTrue);
    });

    test('02-d FULL 초대는 별도 섹션에 선다', () {
      expect(day.contains(r"'모집 완료 · 수락 불가 (${stale.length}명)'"), isTrue);
      expect(day.contains(r"'초대 중 (${outstanding.length}명)'"), isTrue);
    });

    test('02-e 근로자 화면이 말하는 것과 같은 의미다', () {
      final mine = _codeOf(_src(_myAppsPath));
      expect(mine.contains('모집이 완료된 초대예요'), isTrue);
      expect(mine.contains('app.workInstanceCapacityState'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 2b. [FINAL CORRECTION] 근로자 reader도 같은 3-state를 쓴다
  //
  //   관리자 쪽만 고치면 같은 초대가 두 화면에서 다른 말을 한다.
  //   서버가 판단하지 못한 경우(slot 없음·읽기 실패·wdId 계약 손상)에
  //   필드를 비워 두면 클라이언트 non-nullable bool이 false로 읽어
  //   `수락하기`를 띄운다 — UNKNOWN이 AVAILABLE로 새는 같은 결함이다.
  // ═════════════════════════════════════════════════════════════
  group('R2.2.1-02b worker 3-state', () {
    final mine = _codeOf(_src(_myAppsPath));
    final model = _codeOf(_src(_appModelPath));
    final getMine = _tsSliceOf(cf, 'export const callableGetMyApplications',
        'export const callableGetMyInvitations');

    test('02b-a 서버가 세 상태를 명시적으로 내려보낸다', () {
      expect(getMine.contains('type WiCapState = "available" | "full" | "unknown"'),
          isTrue);
      expect(getMine.contains('workInstanceCapacityState: cap'), isTrue);
      expect(
          getMine.contains(
              'capStateMap[d.id] = (req > 0 && conf >= req) ? "full" : "available";'),
          isTrue,
          reason: '판정식이 관리자·서버와 같아야 한다');
    });

    test('02b-b 판단하지 못한 모든 경우가 unknown이다', () {
      // §3 — slot 없음 / wdId 없음 / capacity row 없음 / slot read 실패
      final unknowns = RegExp(r'capStateMap\[d\.id\] = "unknown";')
          .allMatches(getMine)
          .length;
      expect(unknowns, greaterThanOrEqualTo(3),
          reason: 'UNKNOWN 분기가 빠졌다 (slotId/wdId 없음, slot 없음·실패, wd 없음)');
      // slot read 실패도 목록 전체를 죽이지 않고 그 초대만 unknown으로
      expect(getMine.contains('Promise.allSettled'), isTrue);
      expect(getMine.contains('byKey.set(k, null); // 읽기 실패 → UNKNOWN'), isTrue);
      // wdId 계약 손상을 빈 자리로 취급하지 않는다
      expect(getMine.contains('WORKDETAIL_CONTRACT_BROKEN'), isTrue);
    });

    test('02b-c 필드 없음이 available이 되지 않는다', () {
      // 구버전 서버·초대 아닌 문서·알 수 없는 문자열 → 전부 unknown
      expect(
          model.contains('InviteCapacityState _parseCapacityState(Object? raw)'),
          isTrue);
      final p = _after(_src(_appModelPath),
          'InviteCapacityState _parseCapacityState(Object? raw)', 400);
      expect(p.contains('default:'), isTrue);
      expect(p.contains('return InviteCapacityState.unknown;'), isTrue);
      // 기본값도 unknown
      expect(
          model.contains(
              'this.workInstanceCapacityState = InviteCapacityState.unknown,'),
          isTrue);
    });

    test('02b-d workInstanceFull은 확인된 full일 때만 true다', () {
      // `!workInstanceFull`을 `수락 가능`으로 읽는 경로가 생기지 않게
      // canAcceptInvite를 따로 둔다.
      final g = _after(_src(_appModelPath), 'bool get workInstanceFull', 200);
      expect(g.contains('workInstanceCapacityState == InviteCapacityState.full'),
          isTrue);
      final a = _after(_src(_appModelPath), 'bool get canAcceptInvite', 200);
      expect(
          a.contains('workInstanceCapacityState == InviteCapacityState.available'),
          isTrue);
    });

    test('02b-e UNKNOWN에서 수락 CTA가 없다', () {
      final branch = _unknownBranch(mine);
      expect(branch.contains("label: '수락하기'"), isFalse,
          reason: 'UNKNOWN에서 수락 CTA가 남았다');
      expect(branch.contains('_acceptInvite'), isFalse);
      // 거절은 유지 — capacity와 무관한 본인 결정이다
      expect(branch.contains('_declineInvite(app.id)'), isTrue);
    });

    test('02b-f UNKNOWN을 FULL로 표현하지 않는다', () {
      final branch = _unknownBranch(mine);
      expect(branch.contains('모집이 완료된 초대예요'), isFalse);
      expect(branch.contains('인원이 모두 찼어요'), isFalse);
      expect(branch.contains('근무 가능 여부를 확인하지 못했어요'), isTrue);
      expect(branch.contains('새로고침 후 다시 확인해 주세요'), isTrue);
      // 내부 오류 메시지를 그대로 노출하지 않는다 (§3)
      for (final leak in const [
        'WORKDETAIL_CONTRACT_BROKEN',
        'wdId',
        'slotId',
        'Exception',
      ]) {
        expect(branch.contains(leak), isFalse, reason: '내부 오류 노출: $leak');
      }
    });

    test('02b-g 서버 accept guard를 약화하지 않았다 (§4)', () {
      final accept = _tsSliceOf(cf, 'export const callableAcceptTOInvitation',
          'export const callableDeclineTOInvitation');
      expect(accept.contains('db.runTransaction'), isTrue);
      expect(accept.contains('getWorkDetailCount(freshSlotData'), isTrue);
      expect(accept.contains('업무 정원이 초과되었습니다.'), isTrue);
      // 클라이언트가 보낸 capacity 상태를 신뢰하지 않는다
      expect(accept.contains('workInstanceCapacityState'), isFalse);
      expect(accept.contains('workInstanceFull'), isFalse);
    });

    test('02b-h manager/worker symmetry — 같은 어휘, 같은 판정식', () {
      // 같은 enum을 양쪽이 쓴다
      expect(mine.contains("import '../../models/ui/invite_capacity_state.dart'"),
          isTrue);
      expect(day.contains("import '../../../models/ui/invite_capacity_state.dart'"),
          isTrue);
      // 서버 판정식 == 클라이언트 판정식
      expect(
          getMine.contains('(req > 0 && conf >= req) ? "full" : "available"'),
          isTrue);
      final f = _codeOf(_src('lib/models/ui/invite_capacity_state.dart'));
      expect(
          f.contains('if (requiredCount > 0 && canonicalConfirmed >= requiredCount)'),
          isTrue);
    });

    test('02b-i 세 상태가 각각 다른 화면을 낳는다', () {
      // available: 수락하기 / full: 모집 완료 / unknown: 확인 못 함
      expect(mine.contains("label: '수락하기'"), isTrue);
      expect(mine.contains('모집이 완료된 초대예요'), isTrue);
      expect(mine.contains('근무 가능 여부를 확인하지 못했어요'), isTrue);
      // 세 문구가 서로 다른 분기에 있다
      final a = mine.indexOf('모집이 완료된 초대예요');
      final b = mine.indexOf('근무 가능 여부를 확인하지 못했어요');
      final c = mine.indexOf("label: '수락하기'");
      expect(a, greaterThan(0));
      expect(b, greaterThan(a));
      expect(c, greaterThan(b), reason: 'available 분기가 마지막 폴백이어야 한다');
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 3. active invite count (§9)
  // ═════════════════════════════════════════════════════════════
  group('R2.2.1-03 count contract', () {
    test('03-a `초대 N` = 지금 수락될 수 있는 초대만', () {
      expect(day.contains(r"'초대 ${g.activeInvites.length}'"), isTrue);
      expect(day.contains(r"'초대 ${g.invitedApps.length}'"), isFalse,
          reason: 'stale 초대가 active count에 남았다');
      expect(day.contains(r'if (g.activeInvites.isNotEmpty)'), isTrue);
    });

    test('03-b 지원과 초대를 한 숫자로 합치지 않는다', () {
      expect(day.contains(r"'지원 $pending'"), isTrue);
    });

    test('03-c 별도 mutable inviteCount 필드를 만들지 않는다', () {
      for (final banned in const [
        'inviteCount',
        'activeInviteCount',
        'invitedCount',
      ]) {
        expect(day.contains(banned), isFalse, reason: '$banned 가 추가됐다');
      }
      // Application + 현재 capacity로 센다.
      expect(day.contains('List<ApplicationModel> get activeInvites'), isTrue);
    });

    test('03-d FULL이면 추가 초대 CTA를 내린다', () {
      expect(day.contains('g.capacityState == InviteCapacityState.available &&'),
          isTrue);
      // 기존 CTA 문구·부족 계산은 그대로다.
      expect(dayRaw.contains(r"'인력 초대 ($shortage명 부족)'"), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 4. 초대 수락 provenance (§5, §6)
  // ═════════════════════════════════════════════════════════════
  group('R2.2.1-04 accepted-invite provenance', () {
    test('04-a 확정 중 invitedAt이 있는 것만 초대 결과로 수집한다', () {
      expect(day.contains('final List<ApplicationModel> acceptedInvites = [];'),
          isTrue);
      expect(
          day.contains(
              'if (app.invitedAt != null) groups[key]!.acceptedInvites.add(app);'),
          isTrue);
    });

    test('04-b 초대 수락은 `초대 수락 · 확정`으로 보인다', () {
      final label = _after(dayRaw, '(String, Color) _inviteStateLabel', 1200);
      expect(label.contains('case AppStatus.confirmed:'), isTrue);
      expect(label.contains('case AppStatus.contractPending:'), isTrue);
      expect(label.contains("return ('초대 수락 · 확정'"), isTrue);
    });

    test('04-c 최근 초대 응답에 수락이 함께 선다', () {
      expect(day.contains('[...g.closedInvites, ...g.acceptedInvites]'), isTrue);
      expect(day.contains(r"'최근 초대 응답'"), isTrue);
    });

    test('04-d 직접 지원 확정(A)은 초대 집계에 들어가지 않는다', () {
      // invitedAt은 callableInviteWorker만 쓴다 — 지원 경로는 쓰지 않는다.
      final apply = _tsSliceOf(cf, 'export const callableApplyToTO',
          'export const callableGetMyApplications');
      expect(apply.contains('invitedAt:'), isFalse,
          reason: '지원 경로가 invitedAt을 쓰면 A와 B를 구분할 수 없다');
      final invite = _tsSliceOf(cf, 'export const callableInviteWorker',
          'export const callableAcceptTOInvitation');
      expect(invite.contains('invitedAt:'), isTrue);
    });

    test('04-e 수락이 invitedAt을 지우지 않는다', () {
      final accept = _tsSliceOf(
          cf, 'srvApplySeatCommitOverlap(tx, acceptOverlapPlan', 'if (toId) {');
      expect(accept.contains('status:      "CONFIRMED"'), isTrue);
      expect(accept.contains('invitedAt'), isFalse,
          reason: '수락이 invitedAt을 건드리면 provenance가 사라진다');
      expect(accept.contains('action: "INVITE_ACCEPTED"'), isTrue);
    });

    test('04-f 추가 조회를 만들지 않았다 — 확정 명단이 이미 싣고 온다', () {
      // 초대 조회는 여전히 미응답/종료만 가져온다. 수락은 확정 명단에서 온다.
      final svc = _codeOf(_src(_invSvcPath));
      final q = _after(svc, 'Future<List<ApplicationModel>> getDayInvitationsByDateAndBusiness',
          1600);
      expect(q.contains('a.status == AppStatus.invited'), isTrue);
      expect(q.contains('a.status == AppStatus.confirmed'), isFalse);
      expect(q.contains('a.invitedAt != null'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 5. 범위 불변식
  // ═════════════════════════════════════════════════════════════
  group('R2.2.1-05 범위', () {
    test('05-a 초대 현황은 notification을 읽지 않는다', () {
      expect(day.contains('notifications'), isFalse);
      final svc = _src(_invSvcPath);
      final q = _after(_codeOf(svc),
          'Future<List<ApplicationModel>> getDayInvitationsByDateAndBusiness', 1600);
      expect(q.contains('notification'), isFalse);
    });

    test('05-b 초대 전용 별도 메뉴를 만들지 않았다', () {
      final dir = Directory('lib/screens');
      final invitationScreens = dir
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path.replaceAll('\\', '/'))
          .where((p) => p.contains('invitation_management') ||
              p.contains('invite_management'))
          .toList();
      expect(invitationScreens, isEmpty);
    });

    test('05-c 조회 실패를 `초대 중 0명`으로 바꾸지 않는다 (ERROR != ZERO)', () {
      expect(day.contains('if (_dayInvitations == null)'), isTrue);
      expect(day.contains('초대 현황을 확인하지 못했어요'), isTrue);
    });

    test('05-d 초대 현황은 canManageTo가 있을 때만 조회한다', () {
      expect(day.contains('_canForSelectedBiz((p) => p.canManageTo)'), isTrue);
      expect(day.contains('if (canSeeInvites) {'), isTrue);
    });

    test('05-e 사람이 아니라 모집 단위로 묶는다', () {
      // 같은 사람이 9/21과 9/22에 각각 초대받을 수 있다.
      final addInvite = _after(dayRaw, 'void addInvite(ApplicationModel app)', 900);
      expect(addInvite.contains(r"final key = '${app.toId ?? app.toTitle}_$wKey';"),
          isTrue);
    });
  });
}
