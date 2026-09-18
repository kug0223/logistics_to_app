// [BULK-OPERATIONS.1] 일괄 확정은 단건 확정을 N번 하는 것이어야 한다
//
// READ에서 확인된 것:
//   · 서버에 지원자 bulk writer는 없다. batch callable은 근태·급여 쪽에만 있고
//     (BatchSetNoShow / BatchCheckIn / BatchCheckOut / BatchAdjustAttendanceTime /
//      BatchAdminConfirm / BatchResetAttendance / MarkTransferredBatch /
//      ConfirmFinalWage), 좌석을 만드는 확정·승인·거절·초대는 전부 단건이다.
//   · 그래서 화면의 "일괄 확정"은 canonical 단건 CF를 **순차로** 반복한다.
//     병렬로 바꾸면 같은 슬롯에 중복 확정이 생긴다(코드 주석이 그 이유를 적어 둠).
//   · 좌석·겹침·정원 판정은 전부 서버 트랜잭션 안에 있고, 세 seat-commit writer가
//     같은 overlap 계약(srvCollectSeatCommitOverlap / srvApplySeatCommitOverlap)을
//     공유한다.
//
// DEV runtime:
//   정원 4 · 선택 5   → 4 성공 / 1 거절("정원이 초과되었습니다") · 카운터 정확히 4
//   겹침             → 같은 시간 PENDING·INVITED 둘 다 AUTO_CANCELED,
//                      다른 시간 PENDING 유지, 신뢰도 Δ0, 겹친 쪽 좌석 불변
//   stale 선택       → 취소된 건·정원 소진 건 모두 서버가 fresh read로 거절
//   같은 건 두 번    → 좌석 중복 증가 없음
//   10 / 30 / 60명   → 2.7s / 7.9s / 15.6s (건당 ~0.26초, 선형)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fnsPath = 'functions/src/index.ts';
const _dialogPath =
    'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _memberOf(String source, String decl) {
  final start = source.indexOf(decl);
  if (start < 0) throw StateError('$decl 을 찾지 못함');
  final next = source.indexOf('\n  Future<', start + decl.length);
  final next2 = source.indexOf('\n  Widget ', start + decl.length);
  final end = [next, next2].where((i) => i > 0).fold<int>(source.length,
      (a, b) => b < a ? b : a);
  return source.substring(start, end);
}

void main() {
  final fns = _codeOf(_src(_fnsPath));
  final fnsFlat = _flat(fns);
  final dialog = _src(_dialogPath);
  final dialogCode = _codeOf(dialog);

  group('일괄 확정은 canonical 단건 writer를 반복한다', () {
    final body = _memberOf(dialogCode, 'Future<void> _batchApprove() async {');
    final flat = _flat(body);

    test('bulk 전용 서버 writer를 만들지 않았다', () {
      expect(fnsFlat.contains('callableBatchConfirmApplication'), false);
      expect(fnsFlat.contains('callableBatchApprove'), false,
          reason: 'bulk 전용 writer가 생기면 좌석 판정이 두 벌이 된다');
    });

    test('순차 루프다 — 병렬로 바꾸지 않는다', () {
      expect(flat.contains('for (final appId in ids)'), true);
      expect(flat.contains('Future.wait'), false,
          reason: '병렬이면 같은 슬롯에 중복 확정이 생긴다');
      expect(body.contains('status: AppStatus.confirmed'), true,
          reason: '단건 확정 경로(callableConfirmApplication)를 그대로 쓴다');
    });

    test('좌석 카운터를 클라이언트가 직접 더하지 않는다', () {
      expect(flat.contains('confirmedCount +'), false);
      expect(flat.contains('increment('), false,
          reason: '카운터 증감은 서버 트랜잭션의 몫이다');
    });

    test('실행 시점에 권한을 다시 본다', () {
      expect(flat.contains("_canForSelectedBiz((p) => p.canManageTo)"), true);
      expect(body.contains('일괄 확정 권한이 없습니다.'), true);
    });

    test('부분 실패를 전체 성공으로 말하지 않는다', () {
      expect(body.contains('successCount == 0'), true);
      expect(body.contains('successCount < total'), true);
      expect(body.contains('명 확정 완료. 실패한 지원자의 상태를 확인해 주세요.'), true,
          reason: '몇 명이 실패했는지 관리자가 알아야 한다');
    });

    test('오래 걸리는 동안 진행 상황을 말한다', () {
      expect(flat.contains('_batchProgress = (done: processed, total: total)'),
          true, reason: '60명이면 약 16초다 — 멈춘 것처럼 보이면 안 된다');
      expect(_flat(dialogCode).contains('_batchProgress = null'), true,
          reason: '끝나면 진행 표시를 지워야 한다');
      expect(_flat(dialogCode).contains('처리 중 '), true,
          reason: '진행 상황 문구가 있어야 한다');
    });
  });

  group('좌석·겹침 판정은 서버 트랜잭션 안에 있다', () {
    // [CROSS-DOMAIN-R5.3E.2] 호출 수 대신 writer 이름으로 확인한다.
    //   숫자는 "전부 쓴다"의 대리값이었고, writer가 정당하게 늘면
    //   계약은 그대로인데 테스트만 깨졌다.
    test('모든 seat-commit writer가 같은 overlap 계약을 쓴다', () {
      for (final w in const [
        'callableApproveApplicationForReview',
        'callableConfirmApplication',
        'callableAcceptTOInvitation',
        'callableAcceptConfirmedReassignment',
      ]) {
        final a = fnsFlat.indexOf('export const $w = onCall(');
        expect(a >= 0, true, reason: '$w 를 찾지 못함');
        final b = fnsFlat.indexOf('export const ', a + 20);
        final body = fnsFlat.substring(a, b < 0 ? fnsFlat.length : b);
        expect(body.contains('srvCollectSeatCommitOverlap(tx,'), true,
            reason: '$w 가 빠지면 그 경로에서만 겹침이 남는다');
        expect(body.contains('srvApplySeatCommitOverlap(tx,'), true, reason: w);
      }
    });

    test('정원 검증이 트랜잭션 안에서 fresh하게 이뤄진다', () {
      // 주석까지 포함한 원문에서 확인한다 — 표식 자체가 주석이다.
      expect(_src(_fnsPath).contains('[CAPACITY-GUARD] 정원 서버 검증'), true);
      expect(fns.contains('정원이 초과되었습니다.'), true);
    });

    test('확정은 건당 1씩만 올린다', () {
      expect(
        fnsFlat.contains('confirmedCount: admin.firestore.FieldValue.increment(1)'),
        true,
        reason: 'bulk 때문에 +N으로 바꾸면 정원 판정을 건너뛰게 된다',
      );
    });
  });

  group('선택 범위와 식별자', () {
    test('지원서 단위로 선택한다 — userId가 아니다', () {
      final flat = _flat(dialogCode);
      expect(flat.contains('final Set<String> _selectedIds = {};'), true);
      expect(flat.contains('_selectedIds.contains(app.id)'), true,
          reason: '한 근로자가 여러 지원서를 가질 수 있다');
      expect(flat.contains('_selectedIds.add(app.uid)'), false,
          reason: 'userId로 선택하면 같은 사람의 다른 지원서가 뭉개진다');
    });

    test('전체 선택 범위가 화면에 보이는 업무 단위다', () {
      final flat = _flat(dialogCode);
      expect(flat.contains('final pendingIds = g.pendingApps.map((a) => a.id).toList();'),
          true, reason: '숨은 페이지까지 선택되면 범위를 알 수 없다');
      expect(flat.contains('_selectedIds.addAll(pendingIds);'), true);
    });

    test('날짜·사업장이 바뀌면 선택을 비운다', () {
      expect(_flat(dialogCode).contains('_selectedIds.clear();'), true,
          reason: '다른 맥락의 행이 섞인 채 실행되면 안 된다');
    });
  });
}
