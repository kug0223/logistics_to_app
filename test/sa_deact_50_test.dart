import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/utils/close_state_utils.dart';

TOModel _to({String status = TOStatus.closed, String? closedReason}) => TOModel(
      id: 'to1', businessId: 'biz1', businessName: '합성', type: 'flex', title: '합성 공고', creatorUID: 'uid1',
      status: status, closedReasonCode: closedReason, deadlineType: 'NONE', workDetails: const [],
      totalRequired: 0, totalConfirmed: 0, totalPending: 0, isPublished: true, publishMode: 'immediate',
      createdAt: DateTime(2025), statusUpdatedAt: DateTime(2025));

/// [SA-DEACT.50] SA 사업장 비활성 — 화면이 서버의 실제 계약만 말하는가.
///   근거(LOCAL, DEV 배포 원본 직접 실행): perf-20261028/c50/dc50.json · dc50b.json
///     - 비활성 요청 저장과 정리(트리거)는 따로 일어나고, DEV 트리거는 끝났다는 기록을 남기지 않는다.
///     - 정리는 출근 기록이 없는 확정 근무를 **지난 날짜여도** 취소한다(시작 전만이 아니다).
///       출근했거나 정산이 시작된 근무는 남긴다. 서명 전 계약서는 무효가 된다.
///     - 서버 후보(c50/cand/MANAGE)는 반복 요청에 alreadyDeactivated / alreadyActive 를 돌려준다.
String _src(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final biz = _src('lib/screens/super_admin/all_businesses_screen.dart');

  test('SA50-1 비활성 성공 안내가 정리 완료를 단정하지 않는다', () {
    expect(biz.contains("ToastHelper.showSuccess('사업장이 비활성화되었습니다');"), isFalse);
    expect(biz.contains('공고·근무 정리는 서버에서 이어서 진행됩니다'), isTrue);
  });

  test('SA50-2 확인 창이 취소 대상을 실제 기준(출근 기록·정산)으로 말한다', () {
    expect(biz.contains('시작 전인 확정 근무가 취소될 수 있습니다'), isFalse, reason: '지난 날짜도 근태가 없으면 취소된다');
    expect(biz.contains('출근 기록이 없는 확정 근무(지난 날짜 포함)'), isTrue);
    expect(biz.contains('출근했거나 급여 정산이 시작된 근무는 그대로 둡니다'), isTrue);
    expect(biz.contains('서명 전 계약서'), isTrue);
  });

  // 기기(c50/shots/c50-jobs-after-cascade): DEV 비활성 트리거는 공고 status 만 CLOSED(BUSINESS_DEACTIVATED)로 바꾸고
  //   슬롯은 그대로 둔다. 슬롯 기준 판정이 공고 상태를 보지 않아 관리자 공고 탭이 정리된 공고를 '진행중·모집중'으로 보였다
  //   (근로자 지원은 '마감된 공고입니다'로 거절, 서버 한도 0).
  group('SA50-4 사업장 정리로 닫힌 공고는 슬롯이 열려 있어도 마감', () {
    final now = DateTime(2026, 11, 1, 10);
    final slot = SlotModel(id: 's1', toId: 'to1', date: DateTime(2026, 11, 5), status: SlotStatus.open, createdAt: DateTime(2025));
    TOItem item(TOModel to) => TOItem(to: to, slot: slot, confirmedCount: 0, pendingCount: 0, totalRequired: 2, isWorkDetailLoaded: false);

    test('closedReason BUSINESS_DEACTIVATED → 마감', () {
      final to = _to(closedReason: 'BUSINESS_DEACTIVATED');
      expect(CloseStateUtils.isToItemClosed(item(to), to, now), isTrue);
    });
    test('다른 이유로 CLOSED(기존 설계: 슬롯·업무 기준) → 기존대로 열림', () {
      final to = _to(closedReason: 'ALL_WORKDETAILS_CLOSED');
      expect(CloseStateUtils.isToItemClosed(item(to), to, now), isFalse);
    });
  });

  test('SA50-3 반복 요청 응답(이미 비활성·이미 활성)을 새 처리처럼 말하지 않는다', () {
    expect(biz.contains("['alreadyDeactivated'] == true"), isTrue);
    expect(biz.contains("['alreadyActive'] == true"), isTrue);
    expect(biz.contains('이미 비활성화된 사업장입니다'), isTrue);
    expect(biz.contains('이미 활성 상태인 사업장입니다'), isTrue);
  });
}
