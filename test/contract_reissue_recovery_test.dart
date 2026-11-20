// [REISSUE-RECOVERY] 계약 발행에 실패해도 **확정은 사라지지 않는다** —
//   그리고 관리자는 그 근무를 찾아 다시 보낼 수 있어야 한다.
//
//   이 파일이 고정하는 세 문장.
//
//     계약 미작성 ≠ 계약 조회 실패   (ERROR ≠ ZERO)
//     보낼 수 있는 관계 ≠ 좌석을 쥔 모든 관계   (반납·해지는 대상이 아니다)
//     발견 ≠ 처리 가능   (권한이 없으면 action 을 내보내지 않는다)
//
//   실제로 있던 두 결함.
//     · `getContractStatusBatch` 가 **청크 조회 실패를 null 로 채웠다.**
//       소비자는 null 을 "계약서 없음"으로 읽는다 → 조회 실패가
//       `계약서 미작성 N명` 이라는 가짜 업무가 됐고, 이미 완료된 계약에도
//       `계약서 작성` 버튼이 떴다.
//     · 좌석을 반납한 노쇼 건(`대체 충원 진행 중` 배지가 붙은 바로 그 행)에
//       `계약서 작성` 버튼이 떴다. 서버 미발송 목록
//       (`srvNeedsContractIssue`)은 그 건을 **제외**하는데, 다이얼로그는
//       계약 상태만 보고 내보냈다 — 같은 사실을 두 화면이 다르게 말했다.
//
//   판정식을 테스트에서 복제하지 않는다. 실제 `ContractStatusBatch` 와
//   실제 `ApplicationModel.isContractIssuable` 을 그대로 쓴다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/services/contract_service.dart';

String _read(String p) => File(p).readAsStringSync();

/// 주석을 지운다 — 왜 바꿨는지 적은 문장에 옛 표현이 남아 있다.
String _codeOf(String dart) => dart
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

String _slice(String src, String start, String end) {
  final i = src.indexOf(start);
  if (i < 0) throw StateError('구간 시작을 찾지 못했다: $start');
  final j = src.indexOf(end, i + start.length);
  if (j < 0) throw StateError('구간 끝을 찾지 못했다: $end');
  return src.substring(i, j);
}

ApplicationModel _app({
  String id = 'a1',
  String status = 'CONTRACT_PENDING',
  DateTime? released,
  String? termination,
  String? resign,
}) =>
    ApplicationModel(
      id: id,
      uid: 'u1',
      toId: 'to1',
      slotId: 'slot1',
      businessId: 'biz1',
      businessName: 'QA 사업장',
      toTitle: 'QA 공고',
      selectedWorkType: '홀서빙',
      wdId: 'wd1',
      startTime: '09:00',
      endTime: '18:00',
      wage: 12000,
      wageType: 'hourly',
      status: status,
      workDate: DateTime(2026, 10, 20),
      appliedAt: DateTime(2026, 10, 10),
      staffingReleasedAt: released,
      terminationStatus: termination,
      resignStatus: resign,
    );

void main() {
  final work =
      _codeOf(_read('lib/screens/business_admin/dialogs/work_applicants_dialog.dart'));
  final day =
      _codeOf(_read('lib/screens/business_admin/dialogs/day_applicants_dialog.dart'));
  final att = _codeOf(
      _read('lib/screens/business_admin/dialogs/attendance_status_dialog.dart'));
  final svc = _codeOf(_read('lib/services/contract_service.dart'));
  final fn = _read('functions/src/index.ts');
  final mgmt = _codeOf(
      _read('lib/screens/business_admin/admin_contract_management_screen.dart'));

  group('RR-1 — 계약 미작성 ≠ 계약 조회 실패 (실제 클래스)', () {
    test('RR-01 조회된 "계약 없음"만 미작성이다', () {
      const b = ContractStatusBatch(statuses: {'a1': null});
      expect(b.isMissingContract('a1'), isTrue);
      expect(b.isUnresolved('a1'), isFalse);
    });

    test('RR-02 voided·빈 문자열도 미작성이다 (기존 정책 유지)', () {
      const b = ContractStatusBatch(statuses: {'a1': 'voided', 'a2': ''});
      expect(b.isMissingContract('a1'), isTrue);
      expect(b.isMissingContract('a2'), isTrue);
    });

    test('RR-03 발송된 계약은 미작성이 아니다', () {
      const b = ContractStatusBatch(
          statuses: {'a1': 'pending_worker', 'a2': 'completed'});
      expect(b.isMissingContract('a1'), isFalse);
      expect(b.isMissingContract('a2'), isFalse);
    });

    test('RR-04 **조회 실패는 미작성이 아니다**', () {
      const b = ContractStatusBatch(unresolved: {'a1'});
      expect(b.isUnresolved('a1'), isTrue);
      expect(b.isMissingContract('a1'), isFalse,
          reason: 'ERROR 를 ZERO 로 바꾸면 가짜 업무가 생긴다');
    });

    test('RR-05 부분 성공 — 성공한 정보는 그대로 쓴다', () {
      const b = ContractStatusBatch(
          statuses: {'a1': 'completed', 'a2': null}, unresolved: {'a3'});
      expect(b.isMissingContract('a1'), isFalse);
      expect(b.isMissingContract('a2'), isTrue);
      expect(b.isUnresolved('a3'), isTrue);
      expect(b.isMissingContract('a3'), isFalse);
    });

    test('RR-06 발송 직후 낙관적 반영은 unresolved 를 지운다', () {
      const b = ContractStatusBatch(unresolved: {'a1'});
      final after = b.withStatus('a1', 'pending_worker');
      expect(after.isUnresolved('a1'), isFalse);
      expect(after.isMissingContract('a1'), isFalse);
      expect(after.statuses['a1'], 'pending_worker');
    });

    test('RR-07 서비스가 실패한 청크를 unresolved 로 모은다 (배선)', () {
      final batch = _slice(svc, 'Future<ContractStatusBatch> getContractStatusBatch',
          'static final _fn');
      expect(_flat(batch), contains('unresolved.addAll(chunk);'));
      expect(_flat(batch), contains('if (raw is! List)'),
          reason: '응답 모양 이상도 "0건"이 아니다');
      // 성공한 청크에서만 없음으로 단정한다.
      expect(_flat(batch),
          contains('if (unresolved.contains(id)) continue;'));
      expect(batch.contains('result.putIfAbsent(id, () => null);'), isTrue);
    });
  });

  group('RR-2 — 보낼 수 있는 관계만 대상이다 (실제 getter)', () {
    test('RR-10 좌석을 쥔 확정은 대상이다', () {
      expect(_app(status: 'CONTRACT_PENDING').isContractIssuable, isTrue);
      expect(_app(status: 'CONFIRMED').isContractIssuable, isTrue);
    });

    test('RR-11 대기·취소·거절은 대상이 아니다', () {
      for (final s in ['PENDING', 'CANCELED', 'AUTO_CANCELED', 'REJECTED',
        'EXPIRED', 'INVITED']) {
        expect(_app(status: s).isContractIssuable, isFalse, reason: s);
      }
    });

    test('RR-12 **좌석을 반납한 노쇼 건은 대상이 아니다**', () {
      final released = _app(released: DateTime(2026, 10, 20, 9));
      expect(released.isStaffingReleased, isTrue);
      expect(released.isContractIssuable, isFalse,
          reason: '대체 인력이 그 자리를 받는다 — 계약서를 보내면 안 된다');
    });

    test('RR-13 해지·퇴사가 승인된 관계는 대상이 아니다', () {
      for (final s in ['APPROVED', 'AUTO_APPROVED']) {
        expect(_app(termination: s).isContractIssuable, isFalse, reason: s);
        expect(_app(resign: s).isContractIssuable, isFalse, reason: s);
      }
      // 요청만 올라온 상태는 아직 끝난 관계가 아니다.
      expect(_app(termination: 'PENDING').isContractIssuable, isTrue);
      expect(_app(resign: 'REJECTED').isContractIssuable, isTrue);
    });

    test('RR-14 서버 제외 조건과 **같은 한 벌**이다', () {
      // 서버: 자격 판정은 [SERVER-INTEGRITY] 에서 순수 helper 로 분리됐다 —
      //   목록(srvNeedsContractIssue)과 **발행 callable** 이 함께 쓴다.
      final srv = _slice(fn, 'function srvAppEligibleForContractIssue', '\n}\n');
      expect(srv, contains('CONTRACT_SEAT_STATUSES.includes(st)'));
      expect(srv, contains('appData["staffingReleasedAt"] != null'));
      expect(srv, contains('CONTRACT_ENDED_STATUSES.includes(term)'));
      expect(srv, contains('CONTRACT_ENDED_STATUSES.includes(resign)'));
      expect(_flat(_slice(fn, 'async function srvNeedsContractIssue', '\n}\n')),
          contains('srvAppEligibleForContractIssue(appData)'),
          reason: '미발송 목록이 자격 판정을 다시 적으면 두 벌이 된다');
      expect(fn, contains('const CONTRACT_SEAT_STATUSES = ["CONTRACT_PENDING", "CONFIRMED"];'));
      expect(fn, contains('const CONTRACT_ENDED_STATUSES = ["APPROVED", "AUTO_APPROVED"];'));
      // 클라이언트: 같은 네 조건.
      final model = _codeOf(_read('lib/models/core/application_model.dart'));
      final getter = _slice(model, 'bool get isContractIssuable', '\n  }');
      expect(_flat(getter),
          contains('AppStatus.confirmedStatuses.contains(status)'));
      expect(_flat(getter), contains('isStaffingReleased'));
      expect(_flat(getter), contains("ended.contains(terminationStatus)"));
      expect(_flat(getter), contains("ended.contains(resignStatus)"));
      expect(_flat(getter), contains("{'APPROVED', 'AUTO_APPROVED'}"));
    });
  });

  group('RR-3 — 다섯 소비자가 한 술어를 쓴다 (배선)', () {
    test('RR-20 두 다이얼로그가 _needsContractIssue 를 정의한다', () {
      for (final src in [work, day]) {
        // [NOSHOW-CONTRACT-GUARD] 세 번째 사실(근무일 근태)이 같은 술어 안에 들어갔다.
        expect(_flat(src),
            contains('bool _needsContractIssue(ApplicationModel app) => '
                '_contractStatusMap.isMissingContract(app.id) && '
                'app.isContractIssuable && '
                'ContractAttendanceGate.clearForIssue(app, _contractBlockedAppIds);'));
      }
    });

    test('RR-21 행 action·일괄 대상·개수가 모두 그 술어를 쓴다', () {
      // work: 행 action + 일괄 수집
      expect(_flat(work), contains('_canManageContract() && !_isEndedRelation(app) && '
          '_needsContractIssue(app)'));
      expect(_flat(work), contains(
          "_needsContractIssue(item['application'] as ApplicationModel)"));
      // day: 행 action + 일괄 수집 + 개수
      expect(_flat(day), contains('_needsContractIssue(app) && canManageContract'));
      expect(_flat(day), contains('return _needsContractIssue(app);'));
      // [NOSHOW-CONTRACT-GUARD] 개수도 행과 같은 술어 하나 — 사본 조건이 없다.
      expect(_flat(day), contains('.where(_needsContractIssue) .length'));
    });

    test('RR-22 원시 조건(null·empty·voided)이 소비자에 남아 있지 않다', () {
      // 판정은 한 곳에만 있어야 한다 — 복붙된 조건이 다시 갈라지는 경로다.
      for (final src in [work, day]) {
        expect(src.contains("_contractStatusMap[app.id] == 'voided'"), isFalse);
        expect(src.contains("_contractStatusMap[app.id] == null"), isFalse);
      }
    });

    test('RR-23 조회 실패는 화면에서 **모른다고** 말한다', () {
      expect(_flat(work), contains("label = '계약 상태 확인 불가';"));
      expect(_flat(day), contains("label: '계약 상태 확인 불가',"));
      expect(_flat(att), contains("label = '계약확인불가';"));
      // 근태 화면은 완료 시 배지를 생략한다 — 모르는 것을 생략하면 완료로 읽힌다.
      final badge = _slice(att, 'Widget _buildContractBadge(String appId)',
          'Container(');
      expect(_flat(badge), contains('isUnresolved(appId)'));
      expect(badge.contains('isUnresolved(appId)) return const SizedBox.shrink()'),
          isFalse);
    });
  });

  group('RR-4 — 권한·발견 경로 (기존 구조 유지)', () {
    test('RR-30 재발송 action 은 canManageContract 로만 열린다', () {
      expect(_flat(work), contains('_canManageContract() && !_isEndedRelation(app)'));
      expect(_flat(day), contains('_needsContractIssue(app) && canManageContract'));
      // 다른 권한으로 대체하지 않았다.
      expect(_flat(day).contains('_needsContractIssue(app) && canManageTo'), isFalse);
      expect(_flat(day).contains('_needsContractIssue(app) && canManageWorkers'),
          isFalse);
    });

    test('RR-31 미발송 탭은 서버 판정을 쓰고 **실패를 없음으로 말하지 않는다**', () {
      final reader = _codeOf(_read('lib/services/firestore/application_firestore.dart'));
      // `_codeOf` 는 `///` 주석까지 지운다 — 표지도 코드여야 한다.
      final unsent = _slice(reader,
          'Future<List<ApplicationModel>> getUnsentApplicationsByBusiness',
          'Future<List<ApplicationModel>> getApplicationsByBusinessId');
      expect(_flat(unsent), contains("httpsCallable('callableGetUnsentApplicationsByBiz'"));
      expect(_flat(unsent), contains('rethrow;'),
          reason: '빈 목록으로 삼키면 보내야 할 계약이 화면에서 사라진다');
      // 화면은 그 실패를 ERROR 로 표현한다.
      expect(_flat(mgmt), contains('_unsentLoadFailed = true'));
      expect(_flat(mgmt), contains("'미발송 계약서를 확인하지 못했습니다'"));
    });

    test('RR-32 서버가 권한을 재검증한다 (canManageContract)', () {
      final cf = _slice(fn, 'export const callableGetUnsentApplicationsByBiz',
          '// Step 1');
      expect(cf, contains('await assertBizAdmin(callerUid, businessId);'));
      expect(cf, contains('memberPerms["canManageContract"] !== true'));
    });

    test('RR-33 발행 성공 후 목록에서 빠진다 (기존 refresh 유지)', () {
      expect(_flat(mgmt), contains('_loadUnsentContracts()'));
      // 두 다이얼로그는 발송 성공 건을 pending_worker 로 즉시 반영한다.
      for (final src in [work, day]) {
        expect(_flat(src), contains("withStatus(app.id, 'pending_worker')"));
      }
    });
  });

  group('RR-5 — 이번 Phase 가 건드리지 않은 것', () {
    test('RR-40 자동 확정 취소·좌석 반환 복구를 만들지 않았다', () {
      for (final src in [work, day]) {
        expect(src.contains('status: AppStatus.pending'), isFalse,
            reason: '확정을 되돌리는 쓰기는 ROLLBACK-ATOMICITY 에서 제거됐다');
      }
    });

    test('RR-41 모델에 새 필드를 넣지 않았다 — 기존 사실만 조합한다', () {
      final model = _codeOf(_read('lib/models/core/application_model.dart'));
      final getter = _slice(model, 'bool get isContractIssuable', '\n  }');
      // 판정은 이미 있는 세 사실 + 상태 집합으로만 한다.
      for (final f in ['isStaffingReleased', 'terminationStatus',
        'resignStatus', 'AppStatus.confirmedStatuses']) {
        expect(getter, contains(f), reason: '$f 를 보지 않는다');
      }
      // 이 판정을 위해 새 필드를 선언하지 않았다.
      expect(model.contains('contractIssuableAt'), isFalse);
      expect(RegExp(r'final .*\bcontractIssu').hasMatch(model), isFalse);
    });

    test('RR-42 ContractSlot 다중 날짜를 열지 않았다', () {
      final cm = _codeOf(_read('lib/models/core/employment_contract_model.dart'));
      final cls = _slice(cm, 'class ContractSlot {', 'String get wageTypeLabel');
      expect(cls.contains('breakMinutes'), isFalse);
    });
  });
}
