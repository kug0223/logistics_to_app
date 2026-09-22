import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/utils/person_label.dart';

// ═══════════════════════════════════════════════════════════════
// R7-PRE1A.1  PERSON-NO / SAME-NAME DISAMBIGUATION
//
//   system mutation identity = uid          (R7-PRE1A 에서 SAFE 확인)
//   human-readable identity  = personNo     (여기서 만든다)
//
//   동명 USER 계정은 DEV 에 없고, 제품에 이름 변경 경로가 없어서
//   (rules 가 users.name 본인 수정을 차단) 실제 계정으로는 재현할 수 없다.
//   본인인증을 우회해 계정을 만들지 않는다 — 대신 **모델만으로** 같은 이름
//   두 사람을 세워 표시 계층이 둘을 가르는지 본다.
// ═══════════════════════════════════════════════════════════════

UserModel _person({
  required String uid,
  required String name,
  int? personNo,
}) =>
    UserModel(
      uid: uid,
      username: 'u_$uid',
      name: name,
      personNo: personNo,
      email: '$uid@example.invalid',
      role: UserRole.USER,
    );

String _src(String p) => File(p).readAsStringSync();
String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
String _codeOf(String b) => b
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
    })
    .join('\n');

void main() {
  group('PNO-1x 표기', () {
    test('PNO-10 번호는 P-000 으로 0채움', () {
      expect(PersonLabel.of(14), 'P-014');
      expect(PersonLabel.of(1), 'P-001');
      expect(PersonLabel.of(999), 'P-999');
    });

    test('PNO-11 1000 을 넘으면 자릿수가 자연히 늘어난다', () {
      expect(PersonLabel.of(1000), 'P-1000');
    });

    test('PNO-12 번호가 없으면 null — 빈 문자열이 아니다', () {
      // '' 로 돌려주면 파일명이 `_김지현_...` 이 되고, 보조 줄에 점만 남는다.
      expect(PersonLabel.of(null), isNull);
      expect(PersonLabel.of(0), isNull);
      expect(PersonLabel.of(-1), isNull);
    });

    test('PNO-13 보조 문구는 `P-014 · 30대`', () {
      expect(PersonLabel.secondary(14, '30대'), 'P-014 · 30대');
      expect(PersonLabel.secondary(14, ''), 'P-014');
      expect(PersonLabel.secondary(null, '30대'), '30대');
      expect(PersonLabel.secondary(null, ''), '');
    });
  });

  group('PNO-2x 같은 이름 두 사람 — 모델 합성', () {
    final a = _person(uid: 'uidA', name: '김지현', personNo: 14);
    final b = _person(uid: 'uidB', name: '김지현', personNo: 27);

    test('PNO-20 이름은 같다 — 그래서 이름만으로는 못 가른다', () {
      expect(a.name, b.name);
      expect(a.displayName, b.displayName);
    });

    test('PNO-21 표시 라벨이 둘을 가른다', () {
      expect(a.personLabel, 'P-014');
      expect(b.personLabel, 'P-027');
      expect(a.personLabel, isNot(b.personLabel));
    });

    test('PNO-22 확인 문구가 둘을 가른다', () {
      expect(a.nameWithPersonNo, '김지현(P-014)');
      expect(b.nameWithPersonNo, '김지현(P-027)');
      expect(a.nameWithPersonNo, isNot(b.nameWithPersonNo));
    });

    test('PNO-23 사람 identity 는 여전히 uid 다', () {
      // 번호는 읽는 사람을 위한 것이지 시스템의 열쇠가 아니다.
      expect(a.uid, isNot(b.uid));
      final byUid = {a.uid: a, b.uid: b};
      expect(byUid.length, 2);
    });

    test('PNO-24 번호가 없으면 이름만 — 괄호만 남기지 않는다', () {
      final c = _person(uid: 'uidC', name: '김지현');
      expect(c.personLabel, isNull);
      expect(c.nameWithPersonNo, '김지현');
    });

    test('PNO-25 copyWith 가 번호를 떨어뜨리지 않는다', () {
      // 한 번이라도 떨어지면 그 뒤 목록에서 번호가 사라진다.
      expect(a.copyWith(phone: '01000000000').personNo, 14);
    });
  });

  group('PNO-3x business-local — 같은 사람도 사업장마다 다른 번호', () {
    test('PNO-30 같은 uid 가 사업장별로 다른 번호를 가질 수 있다', () {
      // 전역 번호를 주면 두 사업장이 같은 번호로 동일인을 대조할 수 있다.
      // 그건 지금 없는 노출이라 만들지 않는다.
      final atBizA = _person(uid: 'same', name: '김지현', personNo: 3);
      final atBizB = _person(uid: 'same', name: '김지현', personNo: 1);
      expect(atBizA.uid, atBizB.uid);
      expect(atBizA.personLabel, isNot(atBizB.personLabel));
    });
  });

  group('PNO-4x 파일명·시트명 안전화', () {
    test('PNO-40 파일명 금지문자를 바꾼다', () {
      expect(PersonLabel.safeFileName('김/지현'), '김_지현');
      expect(PersonLabel.safeFileName(r'a\b:c*d?e"f<g>h|i'), 'a_b_c_d_e_f_g_h_i');
    });

    test('PNO-41 끝의 점·공백은 Windows 가 잘라 낸다 — 미리 없앤다', () {
      expect(PersonLabel.safeFileName('사업장. '), '사업장');
    });

    test('PNO-42 빈 이름도 파일명이 된다', () {
      expect(PersonLabel.safeFileName(''), '이름없음');
      expect(PersonLabel.safeFileName('   '), '이름없음');
    });

    test('PNO-43 시트명은 31자 · 금지문자 없음', () {
      expect(PersonLabel.safeSheetName('a' * 40).length, 31);
      expect(PersonLabel.safeSheetName(r'생산/1팀[A]'), '생산_1팀_A_');
      expect(PersonLabel.safeSheetName(''), '시트');
    });

    test('PNO-44 파일명 조각은 번호가 없으면 구분자도 없다', () {
      expect(PersonLabel.filePart(14), 'P-014_');
      expect(PersonLabel.filePart(null), '');
    });
  });

  group('PNO-5x export 가 번호를 싣는다', () {
    test('PNO-50 급여 Excel 두 시트 모두 인력번호 컬럼', () {
      final s = _flat(_codeOf(_src('lib/utils/payroll_excel_helper.dart')));
      expect(s.contains("PersonLabel.fieldLabel, '근로자명(현재)'"), isTrue,
          reason: '은행 이체 시트 — 받는 쪽에는 물어볼 화면이 없다.');
      expect(s.contains("PersonLabel.fieldLabel, '근로자명', '사업장'"), isTrue,
          reason: '급여현황 시트.');
    });

    test('PNO-51 이체 시트는 이름과 예금주를 구분해 적는다', () {
      // 한쪽으로 통일하지 않는다 — 서로 다른 사실이다.
      final s = _flat(_codeOf(_src('lib/utils/payroll_excel_helper.dart')));
      expect(s.contains("'근로자명(현재)'"), isTrue);
      expect(s.contains("'예금주(급여확정시)'"), isTrue);
    });

    test('PNO-52 근태 Excel 은 인력번호를 넣고 성별·연락처를 뺐다', () {
      final s = _flat(_codeOf(
          _src('lib/screens/business_admin/admin_month_detail_screen.dart')));
      expect(s.contains("PersonLabel.fieldLabel, '사업장명', '근무일자', '파트', '근로자명',"), isTrue);
      expect(s.contains("info?.gender ?? ''"), isFalse,
          reason: '월 근태 파일에서 성별을 뺐다.');
      expect(s.contains("info?.phone ?? ''"), isFalse,
          reason: '연락처가 사실상 식별자로 쓰이고 있었다 — 번호가 그 일을 대신한다.');
    });

    test('PNO-53 당일명단은 연락처를 유지한다 — 목적이 다르다', () {
      final s = _flat(_codeOf(_src('lib/utils/attendance_list_pdf.dart')));
      expect(s.contains('worker.phone'), isTrue,
          reason: '현장에서 사람에게 전화하려고 들고 다니는 문서다. '
              '목적이 다른 export 를 같은 PII 정책으로 묶지 않는다.');
      expect(s.contains('_nameWithNo(worker)'), isTrue,
          reason: '같은 파트에 동명이인이 있으면 두 줄이 완전히 같아 보였다.');
    });

    test('PNO-54 임금명세서 파일명이 번호로 갈린다', () {
      final s = _flat(_codeOf(_src(
          'lib/screens/business_admin/payroll/payroll_worker_detail_screen.dart')));
      expect(s.contains(r'$_fileNamePrefix${widget.year}년'), isTrue);
      expect(s.contains(r'${no}_${name}_'), isTrue,
          reason: 'raw uid 가 아니라 번호를 쓴다.');
    });
  });

  group('PNO-6x 번호는 관계에서 나온다', () {
    test('PNO-60 지원·초대 시점에 발급한다 — 확정까지 미루지 않는다', () {
      final s = _flat(_codeOf(_src('functions/src/index.ts')));
      expect(s.contains('await srvIssuePersonNoBestEffort(businessId, uid);'),
          isTrue, reason: '동명이인은 지원 검토 단계에서 구분돼야 한다.');
      expect(
          s.contains('await srvIssuePersonNoBestEffort(businessId, targetUid);'),
          isTrue, reason: '초대도 첫 관계가 될 수 있다.');
    });

    test('PNO-61 조회는 읽기만 한다 — 상태를 바꾸지 않는다', () {
      final s = _flat(_codeOf(_src('functions/src/index.ts')));
      expect(s.contains('const personNos = await srvPersonNosFor('), isTrue);
      // [R7-PRE1A.2] 조회가 발급하면 번호가 "누가 먼저 화면을 열었는가"로
      //   정해진다. 발급은 관계를 만드는 writer 만 한다.
      final body = s.substring(
          s.indexOf('async function srvPersonNosFor('),
          s.indexOf('const APPLICANT_REVIEW_ALLOWED'));
      expect(body.contains('srvEnsurePersonNo'), isFalse,
          reason: 'reader 안에서 발급하면 안 된다.');
      expect(body.contains('tx.set'), isFalse,
          reason: 'reader 는 쓰지 않는다.');
    });

    test('PNO-64 발급은 관계를 만드는 writer 에만 있다', () {
      final s = _flat(_codeOf(_src('functions/src/index.ts')));
      // 호출부는 지원·초대 두 곳뿐이어야 한다. 늘어나면 그 경로가
      // 정말 "첫 관계"를 만드는지 다시 봐야 한다.
      final calls = 'srvIssuePersonNoBestEffort('.allMatches(s).length;
      expect(calls, 3,
          reason: '정의 1회 + 호출 2회(applyToTO · inviteWorker). 현재 $calls회.');
    });

    test('PNO-62 번호는 사업장 카운터를 트랜잭션으로 올려 준다', () {
      final s = _flat(_codeOf(_src('functions/src/index.ts')));
      expect(s.contains("collection(\"counters\").doc(\"personNo\")"), isTrue);
      expect(s.contains('return db.runTransaction(async (tx) => {'), isTrue);
    });

    test('PNO-65 username 은 사업장 범위 조회에 실리지 않는다', () {
      // 로그인 ID 다. 자격증명의 절반을 모든 사업장에 보낼 이유가 없고,
      // 사람을 가르는 일은 personNo 가 한다.
      final s = _flat(_codeOf(_src('functions/src/index.ts')));
      final start = s.indexOf('const APPLICANT_REVIEW_ALLOWED');
      final body = s.substring(start, s.indexOf(']);', start));
      expect(body.contains('"username"'), isFalse,
          reason: 'WORKER_DIRECTORY_ALLOWED 도 이 목록에서 파생된다.');
    });

    test('PNO-66 표기는 한 곳에서만 정해진다', () {
      // 접두사·자릿수·라벨이 화면과 파일에서 갈리면 같은 사람이 두 표기로 남는다.
      for (final p in [
        'lib/utils/payroll_excel_helper.dart',
        'lib/screens/business_admin/admin_month_detail_screen.dart',
        'lib/utils/attendance_list_pdf.dart',
      ]) {
        final s = _flat(_codeOf(_src(p)));
        expect(s.contains("'근로자번호'"), isFalse,
            reason: ': 머리글을 직접 적지 않는다 — PersonLabel.fieldLabel 을 쓴다.');
      }
    });
    test('PNO-63 클라이언트는 번호를 쓰지도 읽지도 못한다', () {
      final rules = _src('firestore.rules');
      expect(
          rules.contains('match /businesses/{businessId}/persons/{uid} {'),
          isTrue);
      expect(
          rules.contains('match /businesses/{businessId}/counters/{counterName} {'),
          isTrue);
    });
  });
}
