// [ARCHIVE-WRITER-FENCE · ARCHIVE-RULES-COMPAT 2026-10-17] 운영 종료 뒤·종료와 겹치는 새 운영 행위
//
// 무엇이 잘못됐었나 (에뮬레이터 반례 — scripts/archive-writer-fence-runtime.js ·
//   scripts/archive-rules-compat-runtime.js)
//
//   1. 공고 생성(슈퍼관리자는 사전 확인 면제)·공개·슬롯 생성·공고 편집·연장·추가 근무 승인·출근이
//      사업장 종료를 트랜잭션 밖에서만 보거나 아예 보지 않았다 — 종료 뒤 순차 호출이나, 사전 확인과
//      쓰기 사이에 종료가 커밋되면 새 공고·슬롯·근무일·출근이 생겼다.
//   2. Rules 는 단독 관리자가 deactivatedAt 을 지우거나(null) 바꾸고, 관리자·슈퍼관리자가 archive*·
//      archiveCascade 를 위조하고, 종료 사업장의 슬롯을 직접 다시 열 수 있게 했다.
//
// 이 파일은 그 경계가 코드에 남아 있는지 고정한다(실행 검증은 위 스크립트).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final cf = _read('functions/src/index.ts');
  final rules = _read('firestore.rules');
  final cand = _read('rules_candidates/firestore.archive-compat.rules');
  String callable(String name) {
    final i = cf.indexOf('export const $name = onCall(');
    expect(i, greaterThanOrEqualTo(0), reason: name);
    return cf.substring(i, cf.indexOf('\n);\n', i));
  }

  group('AW-1 남은 writer 는 트랜잭션 안에서 사업장을 본다', () {
    test('AW-11 공고 생성: 즉시·초안 모두, 역할 무관', () {
      final b = callable('callableCreateTO');
      expect('await srvAssertBizOpenInTx(tx, businessId, ARCHIVE_NEW_POSTING_MESSAGE);'.allMatches(b).length, 2);
      expect(b.contains('await db.collection("tos").add(finalData);'), isFalse,
          reason: 'add() 는 사업장을 읽지 않는다');
    });
    test('AW-12 공개·슬롯 생성(청크 트랜잭션)', () {
      expect(callable('callablePublishTO'), contains('await srvAssertBizOpenInTx(tx, businessId, ARCHIVE_NEW_POSTING_MESSAGE);'));
      final f = cf.substring(cf.indexOf('async function srvCreateFlexSlotsBody('));
      final body = f.substring(0, f.indexOf('\n}\n'));
      expect(body, contains('await srvAssertBizOpenInTx(tx, businessId, ARCHIVE_REOPEN_MESSAGE);'));
      expect(body.contains('let batch = db.batch();'), isFalse);
    });
    test('AW-13 공고 편집·업무 단위 수정·재배치·대체 업무·연장', () {
      expect(callable('callableUpdateTO'), contains(
          'await srvAssertBizOpenInTx(txEdit, freshData.businessId as string, ARCHIVE_REOPEN_MESSAGE);'));
      expect('await srvAssertBizOpenInTx(tx, businessId, ARCHIVE_REOPEN_MESSAGE);'
          .allMatches(callable('callableUpdateSlotWorkDetails')).length, 2);
      expect(callable('callableProposeConfirmedReassignment'), contains('await srvAssertBizOpenInTx(crTx, crBizId, ARCHIVE_NEW_WORK_MESSAGE);'));
      expect(callable('callableAcceptConfirmedReassignment'), contains('await srvAssertBizOpenInTx(tx, acBizId, ARCHIVE_NEW_WORK_MESSAGE);'));
      expect(callable('callableOfferAlternativeWork'), contains('await srvAssertBizOpenInTx(offerTx, offerBizId ?? "",'));
      expect(callable('callableCreateRenewalProposal'), contains('await srvAssertBizOpenInTx(tx, businessId, ARCHIVE_NEW_WORK_MESSAGE);'));
      expect(callable('callableAcceptRenewalProposal'), contains('await srvAssertBizOpenInTx(tx, businessId, ARCHIVE_NEW_WORK_MESSAGE);'));
    });
    test('AW-14 추가 근무 승인만 막고 휴무·취소는 처리한다', () {
      final b = callable('callableApproveScheduleChangeRequest');
      expect(b, contains('if (scrData.requestType === "EXTRA_WORK") {\n        await srvAssertBizOpenInTx(tx, scrBusinessId, ARCHIVE_NEW_WORK_MESSAGE);'));
    });
    test('AW-15 출근: 본인·일괄 모두 트랜잭션 안 재판정(종료 전 시각 기록 규칙은 그대로)', () {
      final ci = callable('callableCheckIn');
      expect(ci, contains('const txCiBiz = await tx.get(db.collection("businesses").doc(businessId));'));
      expect('await srvArchivedNewWorkBlockedInTx(tx, businessId, appVerifySnap.data()!, workDateMs, checkInMs)'
          .allMatches(callable('callableBatchCheckIn')).length, 2);
      final rule = cf.substring(cf.indexOf('function srvArchivedNewWorkBlocked('));
      expect(rule.substring(0, rule.indexOf('\n}\n')),
          contains('return !(typeof checkInMs === "number" && checkInMs < closedAt.toMillis());'));
    });
    test('AW-16 재실행 callable: App Check·인증·소유자/슈퍼관리자·종료 사업장만', () {
      final b = callable('callableRetryBusinessArchiveCascade');
      expect(b, contains('{region: "asia-northeast3", enforceAppCheck: true, timeoutSeconds: 540},'));
      expect(b, contains('if (!request.auth) throw new HttpsError("unauthenticated"'));
    });
  });

  group('AF-1 슬롯 청크 저장 — 부분 저장·재시도·동시 실행 (ARCHIVE-FLEX-PARTIAL)', () {
    final f = cf.substring(cf.indexOf('async function srvCreateFlexSlotsBody('));
    final body = f.substring(0, f.indexOf('\n}\n'));
    test('AF-11 슬롯 id 는 날짜에서 — 같은 날짜에 문서가 둘 생기지 않는다', () {
      expect(body, contains(r'const slotRef = toRef.collection("slots").doc(`d${dateStr.replace(/-/g, "")}`);'));
      expect(body, contains('const fresh = chunk.filter((_, k) => !existing[k].exists);'));
    });
    test('AF-12 마지막 청크가 원장을 다시 세어 절대값·완료 표식을 쓴다', () {
      expect(body, contains('const allSlots = isLast ? await tx.get(toRef.collection("slots").select("date", "workDetails")) : null;'));
      expect(body, contains('totalRequired: committedReq + freshReq,'));
      expect(body, contains('slotWrite: {state: "COMPLETE", requested: uniqueDates.length,'));
      expect(body, contains('slotWrite: {state: "IN_PROGRESS", requested: uniqueDates.length,'));
      expect(body.contains('totalSlots: admin.firestore.FieldValue.increment(totalNewSlots)'), isFalse);
    });
    test('AF-13 진행 중인 공고는 완성으로 보지 않는다(공개 판정)', () {
      final c = cf.substring(cf.indexOf('async function srvFlexSlotCompleteness('));
      final b = c.substring(0, c.indexOf('\n}\n'));
      final ip = b.indexOf('?.state === "IN_PROGRESS") return "INCOMPLETE";');
      expect(ip, greaterThan(0));
      expect(b.indexOf('if (typeof d.totalSlots === "number")'), greaterThan(ip));
    });
  });

  group('AF-2 최초 생성 전용 관문 (FLEX-INITIAL-ONLY)', () {
    final g = cf.substring(cf.indexOf('async function srvFlexInitialGateInTx('));
    final gate = g.substring(0, g.indexOf('\n}\n'));
    test('AF-21 묶음 트랜잭션마다 공고를 다시 읽고 판정한다', () {
      expect(cf, contains('if (await srvFlexInitialGateInTx(tx, toRef, flexRequestFp, isFirst) === "ALREADY_COMPLETE") {'));
      expect(gate, contains('const snap = await tx.get(toRef);'));
    });
    test('AF-22 최초: 미공개 SCHEDULED/DRAFT · totalSlots 0 · 슬롯 0 / 이어 쓰기: IN_PROGRESS + 같은 지문', () {
      expect(gate, contains('if (d["isPublished"] === true) no("PUBLISHED");'));
      expect(gate, contains('if (!["SCHEDULED", "DRAFT"].includes(d["status"] as string)) no("STATUS_" + String(d["status"]));'));
      expect(gate, contains('if (w.requestFp !== fp) no("IN_PROGRESS_OTHER_REQUEST");'));
      expect(gate, contains('if (!any.empty) no("LEGACY_SLOTS_EXIST");'));
    });
    test('AF-23 완료 뒤 같은 지문만 완료 결과 — 다른 요청은 거절(슬롯 존재만으로 같은 요청이라 보지 않는다)', () {
      expect(gate, contains('if (isFirst && w.requestFp === fp) return "ALREADY_COMPLETE";'));
      expect(gate, contains('no("COMPLETE_OTHER_REQUEST");'));
      expect(cf, contains('dates: [...uniqueDates].sort(), workDetails, deadlineType, hoursBeforeStart, fixedDeadlineMs,'));
    });
    test('AF-24 관문 거절은 생성 실패 롤백(soft delete)으로 가지 않는다', () {
      final w = cf.substring(cf.indexOf('export const callableCreateFlexSlots = onCall('));
      final wrap = w.substring(0, w.indexOf('\n);\n'));
      final skip = wrap.indexOf('=== FLEX_NOT_INITIAL_CODE) throw e;');
      expect(skip, greaterThan(0));
      expect(wrap.indexOf('await srvRollbackFailedFlexCreate(request)'), greaterThan(skip));
    });
  });

  group('AR-1 Rules 후보 = DEV 활성 원문 + 종료 경계 세 곳', () {
    for (final entry in {'후보': cand, '작업 트리': rules}.entries) {
      test('AR-11 [${entry.key}] 종료 표식·연쇄 상태는 슈퍼관리자 포함 클라이언트 금지', () {
        final r = entry.value;
        expect(r, contains("'deactivatedAt', 'archivedAt', 'archivedBy', 'archiveReason',\n"
            "                               'archiveCascade', 'archiveCascadeRuns']) &&"));
        expect(r.contains(".hasOnly(['deactivatedAt']) &&\n                        resource.data.get('adminIds', []).size() <= 1"), isFalse,
            reason: 'SEC-95 단독 관리자 예외 제거');
      });
      test('AR-12 [${entry.key}] 슬롯: 종료 사업장 생성·closed→open·workDetails 금지, 마감·카운터 허용', () {
        final r = entry.value;
        expect(r, contains('function slotBizOpen() {'));
        expect(r, contains("!(resource.data.get('status', '') == 'closed' &&\n"
            "                    request.resource.data.get('status', '') != 'closed'));"));
        expect(r, contains('                        slotBizOpen() &&\n'));
        expect(r, contains('                        slotNoReopenWhenClosed() &&\n'));
      });
      test('AR-13 [${entry.key}] 공고 workDetails 단독 수정은 운영 중 사업장에서만', () {
        if (entry.key == '작업 트리') {
          // [impl_29 · J1 · 판정292 C292-02 · 의도된 기대 변경] 작업 트리의 공고 업무 직접 쓰기는 '상태 전용 문'이 됐다
          //   (workDetails + editRevision+1 · 업무별 상태 키만). 운영 종료 사업장 거절(이 시험의 뜻)은 같은 문 끝에 그대로 있다.
          final r = entry.value;
          final at = r.indexOf("affectedKeys().hasOnly(['workDetails', 'editRevision']) &&");
          expect(at, greaterThan(0));
          final stmtEnd = r.indexOf('== null);', at);
          expect(stmtEnd, greaterThan(at));
          expect(r.substring(at, stmtEnd), contains("get(/databases/\$(database)/documents/businesses/\$(resource.data.businessId))\n"
              "                      .data.get('deactivatedAt', null)"));
          expect(r.contains("affectedKeys().hasOnly(['workDetails']) &&"), isFalse, reason: 'workDetails 단독 갈래가 남았다');
          return;
        }
        expect(entry.value, contains("request.resource.data.diff(resource.data).affectedKeys().hasOnly(['workDetails']) &&\n"
            "                        get(/databases/\$(database)/documents/businesses/\$(resource.data.businessId))"));
      });
    }
  });

  // [BUSINESS-DELETE-CONTAINMENT 2026-10-17] 구 앱 사업장 삭제는 업무유형·멤버를 한 batch 로 먼저 지운다 —
  //   사업장 delete 만 막으면 그 batch 가 이미 커밋돼 있다(scripts/business-delete-containment-runtime.js).
  group('BD-1 사업장 삭제 봉쇄 후보 = 원문 + delete 세 줄', () {
    final pairs = {
      'firestore.business-delete-containment.rules': _read('rules_candidates/firestore.applications-only.rules'),
      'firestore.archive-compat-containment.rules': cand,
    };
    for (final e in pairs.entries) {
      final c = _read('rules_candidates/${e.key}');
      test('BD-11 [${e.key}] 사업장·업무유형·멤버 delete 가 모두 if false', () {
        expect('[BUSINESS-DELETE-CONTAINMENT]'.allMatches(c).length, 3);
        expect('allow delete: if false;'.allMatches(c).length - 'allow delete: if false;'.allMatches(e.value).length, 3);
        expect(c.contains('allow delete: if (isAdminOf(businessId) && resource.data.ownerId == request.auth.uid) || isSuperAdmin();'), isFalse);
      });
      test('BD-12 [${e.key}] 업무유형 소프트 삭제(update) 규칙은 원문 그대로', () {
        final u = RegExp(r'match /workTypes/\{[^}]+\} \{[\s\S]*?allow update:[^\n]*').firstMatch(e.value)!.group(0)!;
        expect(c, contains(u.substring(u.indexOf('allow update:'))));
      });
    }
  });
}
