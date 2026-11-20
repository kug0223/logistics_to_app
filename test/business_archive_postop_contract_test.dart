// [BUSINESS-ARCHIVE · CREATE-ROLLBACK 2026-10-16] 운영 종료 뒤 지나간 근무 · 슬롯 미완성 공고
//
// 무엇이 잘못됐었나
//
//   1. 운영 종료 연쇄(onBusinessDeactivated → srvLifecycleCancelBulk)는 "미래" 확정만이
//      아니라 근태 기록이 없는 **지난** 확정도 취소했다. 출근 기록 누락·노쇼 판정 전인
//      건의 확정이 사라지면 급여를 줄 근거도 사라진다. 그 건의 미서명 계약도 무효화됐다.
//   2. 앱은 isApproved:false 를 모두 '승인대기'로 말했고, 계약·통계·리뷰·미지급·정산
//      진입 피커가 종료 사업장을 숨겨 지난 기록에 닿지 못했다.
//   3. 확인창은 무엇이 몇 건 정리되는지 말하지 않았다.
//   4. 슬롯 생성이 끝나지 않은 슬롯 공고(totalSlots 0)를 예약 공개·즉시 공개가 그대로
//      공개했다(DEV 배포본 에뮬레이터 재현 — scripts/archive-postop-runtime.js).
//
// 이 파일이 고정하는 것
//
//   PO-0x  확인 문구는 실제 사전 조회 건수로 만들고, 모르면 null(실행 차단)
//   PO-1x  상태 이름: 운영 종료 / 운영 중지 / 승인대기 / 승인됨
//   PO-2x  기록 화면 피커는 종료 사업장을 포함, 운영 설정 화면은 제외
//   PO-3x  서버: futureOnly 취소 경계, 보존 건 계약 유지, 대기 지원 알림, 공개 가드
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/screens/business_admin/business_list_screen.dart';

String _read(String p) => File(p).readAsStringSync();

BusinessModel _biz(Map<String, dynamic> m) =>
    BusinessModel.fromMap(
        {'name': '사업장', 'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)), ...m}, 'b1');

void main() {
  group('PO-0x 운영 종료 사전 처리 게이트 · 확인 문구', () {
    // [BUSINESS-ARCHIVE 4단계] 세 갈래: 사전 해결 필수 / 종료하며 처리 / 종료 후 보존·처리
    const full = <String, dynamic>{
      'inProgressShifts': 0,
      'ongoingLongTerm': 0,
      // [ARCHIVE-CLOSED-TO-PREFLIGHT] 실근무가 있는 계약 대기 — 사전 해결 필수 항목
      'contractPendingWorked': 0,
      'openPostings': 2,
      'pendingApplications': 3,
      'invites': 1,
      'futureConfirmed': 4,
      'contractsVoided': 2,
      'keptStarted': 5,
      'contractsKept': 1,
      'unpaidWages': 6,
      'workedUncalculated': 7,
      'interimPending': 1,
      'interimApproved': 2,
      'truncated': false,
    };
    test('PO-01 실제 건수를 세 갈래로 말한다', () {
      final m = BusinessListScreen.archiveConfirmMessage('가게', full)!;
      expect(m, contains('종료하면서 정리되는 것'));
      expect(m, contains('모집 중·예약 공고 2건 마감'));
      expect(m, contains('대기 중인 지원 3건 마감 (마감된 공고 포함)'));
      expect(m, contains('초대 1건 철회'));
      expect(m, contains('시작 전 확정·계약 대기 근무 4건 취소'));
      expect(m, contains('취소되는 근무의 미서명 계약 2건 무효'));
      expect(m, contains('종료 후에도 남아 계속 처리하는 것'));
      expect(m, contains('지난 확정 근무 5건 · 그 미서명 계약 1건'));
      expect(m, contains('미지급 급여 6건 · 계산 전 근무 7건'));
      expect(m, contains('중간정산 대기 1건 · 승인 후 미이체 2건'));
      expect(m, contains('일시 정지가 아니라'));
      expect(BusinessListScreen.archiveBlockedMessage(full), isNull);
    });
    test('PO-02 조회 실패·누락·음수·문자열은 확인창 없음 + 종료 불가 — 0건으로 말하지 않는다', () {
      expect(BusinessListScreen.archiveConfirmMessage('가게', null), isNull);
      expect(BusinessListScreen.archiveBlockedMessage(null), isNotNull);
      for (final k in full.keys.where((k) => k != 'truncated')) {
        for (final bad in [null, -1, '0']) {
          final m = Map<String, dynamic>.from(full);
          if (bad == null) {
            m.remove(k);
          } else {
            m[k] = bad;
          }
          expect(BusinessListScreen.archiveConfirmMessage('가게', m), isNull, reason: '$k=$bad');
          expect(BusinessListScreen.archiveBlockedMessage(m), isNotNull, reason: '$k=$bad');
        }
      }
    });
    test('PO-03 진행 중 출근·진행 중 장기 근무·상한 초과는 확인창 대신 사전 해결 안내', () {
      final a = BusinessListScreen.archiveBlockedMessage({...full, 'inProgressShifts': 1})!;
      expect(a, contains('퇴근하지 않은 근무 1건'));
      final b = BusinessListScreen.archiveBlockedMessage({...full, 'ongoingLongTerm': 2})!;
      expect(b, contains('진행 중인 장기 근무 2건'));
      // [정정] 실행할 수 없는 해결 경로(기존 해지로 앞당겨 끝내기)를 안내하지 않는다.
      expect(b, contains('앞당겨 끝내는 기능이 없어요'));
      expect(b.contains('계약 해지·퇴사 처리로 먼저'), isFalse);
      // [ARCHIVE-CLOSED-TO-PREFLIGHT] 실근무 계약 대기는 지금 실행할 수 있는 길(계약 서명)을 안내한다.
      final w = BusinessListScreen.archiveBlockedMessage({...full, 'contractPendingWorked': 3})!;
      expect(w, contains('계약서 서명 전에 이미 일한 근무 3건'));
      expect(w, contains('근로자 서명을 받은 뒤 운영을 종료할 수 있어요'));
      expect(BusinessListScreen.archiveConfirmMessage('가게', {...full, 'contractPendingWorked': 1}), isNull);
      final t = BusinessListScreen.archiveBlockedMessage({...full, 'truncated': true})!;
      expect(t, contains('따로 처리하실 일은 없어요'), reason: '상한 초과는 사용자 업무가 아니라 판정 불가');
      expect(BusinessListScreen.archiveBlockedMessage({...full, 'truncated': true}), isNotNull);
      expect(BusinessListScreen.archiveConfirmMessage('가게', {...full, 'ongoingLongTerm': 1}), isNull);
    });
    test('PO-04 화면: 사전 조회 실패면 실행하지 않고, 서버가 새 결과를 주면 그것으로 다시 묻는다', () {
      final s = _read('lib/screens/business_admin/business_list_screen.dart');
      expect(s, contains("'preview': true"));
      expect(s, contains("{'businessId': id, 'expected': expected}"));
      expect(s, contains("code == 'ARCHIVE_PREVIEW_CHANGED' || code == 'ARCHIVE_BLOCKED'"));
      expect(s, contains('preview = fresh; // 새 결과로 다시 보여 준다'));
      final i = s.indexOf('final message = BusinessListScreen.archiveConfirmMessage(');
      final j = s.indexOf('showDangerConfirm', i);
      expect(s.substring(i, j), contains('if (message == null)'));
    });
    test('PO-05 서버: 실행 직전 원장을 다시 세고, 다르거나 사전 해결 항목이 있으면 종료하지 않는다', () {
      final cf = _read('functions/src/index.ts').replaceAll('\r\n', '\n');
      final i = cf.indexOf('export const callableArchiveOwnBusiness');
      final seg = cf.substring(i, cf.indexOf('\nexport const ', i + 10));
      final recount = seg.indexOf('const fresh = await srvArchivePreview(businessId);');
      final write = seg.indexOf('tx.update(bizRef, {');
      expect(recount, greaterThan(0));
      expect(recount, lessThan(write));
      expect(seg, contains('{code: "ARCHIVE_BLOCKED", preview: fresh}'));
      expect(seg, contains('{code: "ARCHIVE_PREVIEW_CHANGED", preview: fresh}'));
      expect(seg, contains('if (!srvArchivePreviewSame(expected, fresh)) {'));
    });
  });

  group('PO-1x 상태 이름', () {
    final at = DateTime(2026, 10, 16);
    final ts = Timestamp.fromDate(at);
    test('PO-11 소유자 운영 종료 → 운영 종료', () {
      final b = _biz({'isApproved': false, 'deactivatedAt': ts, 'archivedAt': ts});
      expect(b.isClosedByOwner, isTrue);
      expect(b.operationStatusLabel, '운영 종료');
    });
    test('PO-12 슈퍼관리자 비활성화 → 운영 중지(승인대기 아님)', () {
      final b = _biz({'isApproved': false, 'deactivatedAt': ts});
      expect(b.operationStatusLabel, '운영 중지');
    });
    test('PO-13 재활성화 뒤 archivedAt 이 남아도 종료로 보지 않는다', () {
      final b = _biz({'isApproved': true, 'archivedAt': ts});
      expect(b.isClosedByOwner, isFalse);
      expect(b.operationStatusLabel, '승인됨');
    });
    test('PO-14 승인 전 → 승인대기', () {
      expect(_biz({'isApproved': false}).operationStatusLabel, '승인대기');
    });
    test('PO-15 archivedAt 은 쓰기(toMap)에 실리지 않는다', () {
      final b = _biz({'isApproved': false, 'deactivatedAt': ts, 'archivedAt': ts});
      expect(b.toMap().containsKey('archivedAt'), isFalse);
      expect(b.copyWith().archivedAt, at);
    });
    test('PO-16 목록 배지와 관리자 홈은 종료를 승인 대기로 말하지 않는다', () {
      final list = _read('lib/screens/business_admin/business_list_screen.dart');
      expect(list, contains('business.operationStatusLabel'));
      expect(list.contains("business.isApproved ? '승인됨' : '승인대기'"), isFalse);
      final home = _read('lib/screens/business_admin/business_admin_home_screen.dart');
      final d = home.indexOf('STATE D');
      final b = home.indexOf("'사업장이 승인 완료되면 이용하실 수 있어요.'");
      expect(d, greaterThan(0));
      expect(d, lessThan(b), reason: '종료 판정이 승인 대기 판정보다 먼저여야 한다');
      expect(home, contains('_allBusinessesClosed'));
    });
  });

  group('PO-2x 피커', () {
    final settings = _read('lib/screens/common/settings_screen.dart');
    final review = _read('lib/screens/business_admin/admin_review_list_screen.dart');
    test('PO-21 기록 화면 6곳은 종료 사업장을 포함한다', () {
      expect('includeClosed: true'.allMatches(settings).length, 6,
          reason: '계약 관리 2 · 통계 · 리뷰 · 미지급 · 중간정산');
      expect(review, contains('includeClosed: true'));
    });
    test('PO-22 운영 설정(업무·템플릿)은 종료 사업장을 제외한다(기본값)', () {
      final helper = _read('lib/utils/business_picker_helper.dart');
      expect(helper, contains('bool includeClosed = false'));
      expect(helper, contains('b.isApproved || (includeClosed && b.isDeactivated)'));
    });
  });

  group('PO-3x 서버', () {
    final cf = _read('functions/src/index.ts');
    String body(String head) {
      final i = cf.indexOf(head);
      expect(i, greaterThanOrEqualTo(0), reason: head);
      return cf.substring(i, cf.indexOf('\n}\n', i));
    }
    test('PO-31 운영 종료 연쇄의 확정 취소는 시작 전 건만 넘긴다(공용 helper 불변)', () {
      // [ARCHIVE-CASCADE-PAGINATION] 세 호출(공고별·잔여 계약 대기·잔여 확정)이 사업장 전체 id 페이지
      //   루프 하나로 합쳐졌다. 트리거는 그 본문을 부르기만 한다.
      final i = cf.indexOf('export const onBusinessDeactivated');
      final trig = cf.substring(i, cf.indexOf('\nexport const ', i + 10));
      expect(trig, contains('const cascade = await srvRunBusinessArchiveCascade(businessId);'));
      final j = cf.indexOf('async function srvRunBusinessArchiveCascade(');
      final run = cf.substring(j, cf.indexOf('\n}\n', j)).replaceAll('\r\n', '\n');
      expect('srvLifecycleCancelBulk(srvNotStartedOnly(docs), {'.allMatches(run).length, 1);
      expect(run, contains('for (const st of ["CONTRACT_PENDING", "CONFIRMED"]) {'));
      // 다른 lifecycle writer(사업장 삭제·공고 삭제·탈퇴)가 쓰는 helper 시그니처는 그대로다.
      expect(cf, contains('  allowedStatuses: string[] = CONFIRMED_STATUSES\n): Promise<SrvLifecycleCancelReport>'
          .replaceAll('\n', cf.contains('\r\n') ? '\r\n' : '\n')));
    });
    test('PO-32 시작 판정은 KST 날짜 정규화 + 근무일 모르면 보존', () {
      final b = body('function srvScheduleNotStarted(');
      expect(b, contains('srvKstDayStartMs(wd.toMillis())'));
      expect(b, contains('return false;'));
    });
    test('PO-33 보존 건의 미서명 계약은 무효화하지 않고, 확인 실패도 무효화하지 않는다', () {
      // [ARCHIVE-CASCADE-PAGINATION] 판정은 contractLive 하나 — 살아 있는 연결 지원서가 있으면 유지,
      //   읽지 못하면 throw → catch 에서 실패로 센다(무효화하지 않고 재실행 대상).
      final i = cf.indexOf('const contractLive = async (cd: FirebaseFirestore.QueryDocumentSnapshot): Promise<boolean> => {');
      expect(i, greaterThan(0));
      final seg = cf.substring(i, i + 1800);
      expect(seg, contains('CONFIRMED_STATUSES.includes'));
      expect(seg, contains('if (await contractLive(cd)) return;'));
      expect(seg, contains('fail(`계약 \${cd.id}`, e);'));
    });
    test('PO-34 대기 지원 마감 알림은 반영된 건만, 앱이 아는 type', () {
      final b = body('async function srvNotifyPendingEndedByBusiness(');
      expect(b, contains('now.get("status") !== "REJECTED"'));
      expect(b, contains('type: "applicationRejected"'));
      expect(b, contains('biz_end_'));
    });
    test('PO-35 슬롯 미완성 공고는 예약 공개·즉시 공개 모두 막는다', () {
      // [3단계] 동기 판정(srvFlexSlotsIncomplete)은 관계 자료로 증명하는 srvFlexSlotCompleteness 로
      //   바뀌었다 — 필드 없음은 완성 증거가 아니다(세부는 archive_fence_contract_test FX-3x).
      expect(cf.contains('srvFlexSlotsIncomplete('), isFalse);
      expect('srvFlexSlotCompleteness('.allMatches(cf).length, 3,
          reason: '정의 1 + 예약 공개 tx 1 + 즉시 공개 1');
    });
    test('PO-36 생성 롤백 쓰기는 트랜잭션 안에서 조건을 다시 본다', () {
      final b = body('async function srvRollbackFailedFlexCreate(');
      expect(b, contains('db.runTransaction'));
      expect(b, contains('f["isPublished"] === true'));
      expect(b, contains('assertNoPostingRelations'));
    });
    test('PO-37 사전 조회는 소유자만, 쓰기 없음', () {
      final i = cf.indexOf('if (preview === true) {');
      final seg = cf.substring(i, cf.indexOf('const result = await db.runTransaction', i));
      expect(seg, contains('permission-denied'));
      expect(seg.contains('.update('), isFalse);
      expect(seg.contains('.set('), isFalse);
    });
  });
}
