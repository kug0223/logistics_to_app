// [WORKTYPE-IDENTITY 2026-10-17] 업무유형 정체성 · 최신 안내 · 기존 공고 경계 — 소스 계약
//
// 실행 검증: scripts/worktype-identity-runtime.js(서버 BEFORE/AFTER + Rules 4세트),
//   test/worktype_mutation_job_posting_render_test.dart · test/schedule_detail_guidance_fallback_test.dart(렌더),
//   test/work_detail_edit_identity_lock_test.dart(D7 렌더).
// 이 파일은 그 경계가 코드에 남아 있는지 고정한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

/// [L57 r7] `prefix` 로 시작하는 호출이 그대로(`);`) 또는 꼬리 인자 하나(`tail` · 기본 `, 식별자`)를 더 붙여 끝나는가.
bool _callWithOptionalTail(String src, String prefix, {String tail = r', \w+'}) =>
    RegExp('${RegExp.escape(prefix)}(?:$tail)?\\);').hasMatch(src);

void main() {
  final cf = _read('functions/src/index.ts');
  String fnBody(String sig) {
    final i = cf.indexOf(sig);
    expect(i, greaterThanOrEqualTo(0), reason: sig);
    return cf.substring(i, cf.indexOf('\n}\n', i));
  }

  group('WI-1 서버 — 근무에 업무유형 id', () {
    test('WI-11 다섯 writer 가 모두 같은 helper 로 id 를 남긴다', () {
      expect('await srvBindWorkTypeIds('.allMatches(cf).length, 5);
      // [L57 r7] 같은 요청의 업무유형 목록(catalog)을 마지막 인자로 넘길 수 있다 — 지키려던 것은
      //   "생성 writer 두 곳이 같은 helper 로 id 를 남긴다" 이므로 인자 유무 둘 다 받는다(그 밖의 모양은 실패).
      expect(_callWithOptionalTail(cf,
          'await srvBindWorkTypeIds(businessId, toWorkDetailsCreate as Record<string, unknown>[], [], role === "SUPER_ADMIN"'), isTrue);
      expect(_callWithOptionalTail(cf,
          'await srvBindWorkTypeIds(businessId, normalizedFlexWDs, [], role === "SUPER_ADMIN"'), isTrue);
    });
    test('WI-12 기존 근무의 id 는 저장본 그대로 · 새 근무만 검증(이름 일치·활성) · 모호하면 찍지 않는다', () {
      final b = fnBody('async function srvBindWorkTypeIds(');
      expect(b, contains('if (typeof old["workTypeId"] === "string" && old["workTypeId"]) wd["workTypeId"] = old["workTypeId"];'));
      expect(b, contains('if (!d || d["name"] !== wd["workType"] || (!isSuperAdmin && d["isActive"] !== true)) {'));
      expect(b, contains('if (same.length === 1) wd["workTypeId"] = same[0][0];'));
    });
  });

  group('WI-2 D4 — 기존 공고 공개는 업무유형 목록으로 막지 않는다', () {
    test('WI-21 생성만 활성 업무유형을 본다', () {
      // [L57 r7] 생성은 준비 판정에 같은 요청의 업무유형 목록을 넘길 수 있다(`{workTypeCatalog: …}`) — 활성 업무유형을
      //   보는 것은 그대로(existingPosting 없음). 인자 유무 둘 다 받는다.
      expect(_callWithOptionalTail(cf, 'await assertBusinessPostingReady(businessId, bizAuthSnap.data()',
          tail: r', \{workTypeCatalog: \w+\}'), isTrue);
      expect(cf, contains('await assertBusinessPostingReady(businessId, authBizDataPub, {existingPosting: true});'));
      expect(cf, contains('await assertBusinessPostingReady(businessId, authBizDataUpdate, {existingPosting: true});'));
      expect(cf, contains('bizId, freshBizSnaps[bi].data(), txReadinessReader(tx), {existingPosting: true}'));
      final e = fnBody('async function evaluatePostingReadinessFirestore(');
      expect(e, contains('if (opts.existingPosting !== true) {'));
      expect(e.indexOf('return srvAttendancePolicyBlock(bizData);'), greaterThan(e.indexOf('if (opts.existingPosting !== true) {')),
          reason: '다른 공개 조건은 기존 공고에도 그대로');
    });
  });

  group('WI-3 사진 — 업무유형이 참조 중인 사진은 지우지 않는다', () {
    test('WI-31 삭제 CF 가 Storage 삭제 전에 참조를 본다', () {
      final i = cf.indexOf('export const callableDeleteBusinessImage = onCall(');
      final b = cf.substring(i, cf.indexOf('\n);\n', i));
      final guard = b.indexOf('return {success: true, skipped: "REFERENCED_BY_WORK_TYPE"};');
      expect(guard, greaterThan(0));
      expect(b.indexOf('await admin.storage().bucket().file(filePath).delete();'), greaterThan(guard));
    });
    test('WI-32 앱의 비활성화는 사진 삭제를 부르지 않는다', () {
      final s = _read('lib/services/firestore/business_firestore.dart');
      final i = s.indexOf('Future<bool> deleteBusinessWorkType(');
      final b = s.substring(i, s.indexOf('\n  }\n', i));
      // 주석은 이 CF 를 언급한다(왜 부르지 않는지) — 코드 줄만 본다.
      final code = b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
      expect(code.contains('callableDeleteBusinessImage'), isFalse);
      expect(b, contains(".update({'isActive': false});"));
    });
    test('WI-33 사진 교체 뒤 정리 대상 = 저장 전 참조 − 저장 후 참조', () {
      final s = _read('lib/screens/business_admin/work_type_detail_screen.dart');
      expect(s, contains('}.difference(stillReferenced);'));
      expect(s.indexOf('}.difference(stillReferenced);'), greaterThan(s.indexOf('.update(updateData);')),
          reason: '문서 갱신이 성공한 뒤에만 옛 사진을 지운다');
    });
  });

  group('WI-4 Rules — 이름·아이콘 고정, 단건 삭제 금지', () {
    for (final p in [
      'firestore.rules',
      'rules_candidates/firestore.worktype-identity.rules',
      'rules_candidates/firestore.worktype-identity-containment.rules',
    ]) {
      test('WI-41 [$p]', () {
        final r = _read(p);
        final i = r.indexOf('match /workTypes/{workTypeId} {');
        final b = r.substring(i, r.indexOf('\n      }\n', i));
        // [판정281 갱신] 서버 fence: 쓰기 규칙 바깥에 `callerNotDeleting() && (` 감싸기만 붙었다 — 안쪽 조건 단언은 그대로.
        // 본 rules 는 바깥 fence 의 닫는 괄호 하나만 더 붙는다. 후보 rules 파일(rules_candidates)은 fence 이전 원문 그대로.
        expect(b, contains(p == 'firestore.rules'
            ? ".affectedKeys().hasAny(['businessId', 'name', 'icon', 'color', 'backgroundColor']));"
            : ".affectedKeys().hasAny(['businessId', 'name', 'icon', 'color', 'backgroundColor']);"));
        expect(b, contains('allow delete: if false;'));
      });
    }
  });

  group('WI-5 앱 — 이름·아이콘 수정 입구 없음, 안내는 id 로', () {
    test('WI-51 업무 유형 관리에 이름·아이콘 수정 메뉴가 없다', () {
      final s = _read('lib/screens/business_admin/work_type_management_screen.dart');
      expect(s.contains("label: '아이콘수정'"), isFalse);
      expect(s.contains('_showEditDialog('), isFalse);
    });
    test('WI-52 두 reader 가 이름이 아니라 resolver 로 안내를 고른다', () {
      expect(_read('lib/screens/common/job_posting_screen.dart'), contains('WorkTypeGuideResolver.resolve('));
      expect(_read('lib/widgets/dialogs/schedule_detail_dialog.dart'), contains('WorkTypeGuideResolver.resolve('));
      expect(_read('lib/screens/common/job_posting_screen.dart').contains('_workTypeMap['), isFalse);
    });
    test('WI-53 [LOCAL-CLOSURE] 레거시 판정은 저장된 createdAt 만 · 사업장 대조 · 끝까지 읽은 목록만', () {
      for (final p in ['lib/screens/common/job_posting_screen.dart', 'lib/widgets/dialogs/schedule_detail_dialog.dart']) {
        final s = _read(p);
        expect(s, contains('storedCreatedAt,'), reason: p);
        expect(s.contains('postedAt: _to?.createdAt') || s.contains('postedAt: to?.createdAt'), isFalse, reason: p);
        expect(s, contains('businessId:'), reason: p);
      }
      final r = _read('lib/services/work_type_guide_resolver.dart');
      expect(r, contains('if (businessId.isEmpty || catalog.businessId != businessId) return null;'));
      expect(r, contains('if (!catalog.complete || postedAt == null) return null;'));
      expect(_read('lib/models/core/to_model.dart'), contains("storedCreatedAt: parseTimestampNullable(data['createdAt']),"));
    });
  });
}
