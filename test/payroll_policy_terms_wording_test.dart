// [R7-PAYROLL-POLICY.5] 약관이 제품을 사실대로 말하는가.
//
// `.4`~`.4D` 에서 근태·급여 처리 기준을 근로자에게 고지하고 계약서에 넣고
// 서버에서 고정했다. 그런데 **약관**은 그 기준이 무엇이고 누가 정하며 누가
// 책임지는지 한 줄도 말하지 않았고, 서비스의 내용을 "중개자로서의 역할만"
// 이라고 적어 실제로 하는 일(근무시간 인정·임금 계산)을 빼놓았다.
//
// 이 파일이 고정하는 것:
//
//   TW-1  제6조가 실제로 제공하는 기능을 말한다 (과소기술 금지)
//   TW-2  제7조가 법률상 무효인 면책을 주장하지 않는다 (약관규제법 제7조)
//   TW-3  제8조가 근태·급여 처리 기준의 주인과 한계를 말한다
//   TW-4  제9조가 법정 의무의 주체를 사업장으로 적는다
//   TW-5  조 번호가 연속하고 중복되지 않는다
//   TW-6  보존기간이 세 문서에서 같은 근거를 가리킨다 (5년 금지)
//   TW-7  제3자 제공 고지가 실제 제공 항목·열람 조건과 맞는다
//   TW-8  문구에 내부 기술어·과도한 절대어가 없다
//   TW-9  사업자 정보 placeholder 와 RELEASE BLOCKER 기록이 함께 산다
//   TW-10 약관 제8조가 화면 고지의 범주를 빠뜨리지 않는다
//
// 왜 소스 텍스트를 읽는가: 발행본은 Firestore 에 있고 immutable 이다. 저장소가
// 가진 것은 **다음에 발행할 원문**이고, 발행이 잘못되는 것을 막는 유일한
// 지점이 여기다.

import 'dart:io';

import 'package:ALfit/models/core/legal_terms_model.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _item(String id) =>
    LegalTerms.defaultTerms().items.firstWhere((i) => i.id == id).content;

/// 조문 하나를 잘라낸다 — 다음 조 머리글까지.
String _article(String terms, int no) {
  final head = '제$no조 (';
  final a = terms.indexOf(head);
  expect(a, greaterThan(-1), reason: '제$no조 를 찾지 못했다');
  final b = terms.indexOf('제${no + 1}조 (', a);
  return b < 0 ? terms.substring(a) : terms.substring(a, b);
}

void main() {
  late String service;
  late String privacy;
  late String thirdParty;
  late String location;
  late String marketing;
  late String gateDoc;
  late String disclosure;

  setUpAll(() {
    service = _item('service_terms');
    privacy = _item('privacy_policy');
    thirdParty = _item('privacy_third_party');
    location = _item('location_terms');
    marketing = _item('marketing_consent');
    gateDoc = _read('docs/release-privacy-gate.md');
    disclosure = _read('lib/utils/attendance_policy_disclosure.dart');
  });

  // ───────────────────────────────────────────────────────────
  group('TW-1 제6조 — 하는 일을 말한다', () {
    test('01 실제 제공 기능이 빠짐없이 적혀 있다', () {
      final a = _article(service, 6);
      for (final f in <String>[
        '지원서 접수',
        '전자 근로계약서',
        '출퇴근 기록',
        '근태·급여 처리 기준을 적용한 근무시간 인정',
        '임금액 계산',
        '임금 지급 상태',
        '상호 평가',
      ]) {
        expect(a, contains(f), reason: '제6조에 "$f" 가 없다');
      }
    });

    test('02 "중개자로서의 역할만" 류의 과소기술이 없다', () {
      // 근태 기준을 적용해 근무시간을 인정하고 임금을 계산하는 쪽이
      // "역할만" 이라고 적으면 거짓이 된다.
      for (final under in <String>[
        '중개자로서의 역할만',
        '중개 플랫폼으로서',
        '연결만',
      ]) {
        expect(service, isNot(contains(under)), reason: under);
      }
    });

    test('03 계약 당사자와 임금 지급 주체를 뒤집지 않는다', () {
      final a = _article(service, 6);
      expect(a, contains('근로계약의 당사자는 사업장과 지원자이며'));
      expect(a, contains('회사는 임금을 직접 지급하지 않으며'));
      expect(_article(service, 2),
          contains('임금 지급은 서비스에 포함되지 않습니다'));
    });
  });

  // ───────────────────────────────────────────────────────────
  group('TW-2 제7조 — 무효인 면책을 주장하지 않는다', () {
    test('04 고의·중대한 과실 책임을 배제하지 않는다고 적혀 있다', () {
      // 약관규제법 제7조 제1호 — 그 배제는 무효다. 무효 조항을 싣고
      // 있는 것 자체가 리스크이므로 명시적으로 유보한다.
      expect(_article(service, 7),
          contains('고의 또는 중대한 과실로 인한 법률상의 책임은 본 약관으로 배제되지 않습니다'));
    });

    test('05 회사가 제공하는 기능의 오류 책임을 떠넘기지 않는다', () {
      final a = _article(service, 7);
      expect(a, contains('그 기능이 잘못 동작하여 회원에게 손해가 생긴 경우'));
      expect(a, contains('그 범위에서 책임을 집니다'));
      // 전면 배제로 읽히는 옛 문구가 돌아오지 않는다.
      expect(service, isNot(contains('직접적인 책임을 지지 않습니다')));
    });

    test('06 기준을 정하는 쪽과 적용하는 쪽을 구별한다', () {
      expect(_article(service, 7),
          contains('근태·급여 처리 기준을 정하는 것은 사업장이며'));
    });
  });

  // ───────────────────────────────────────────────────────────
  group('TW-3 제8조 — 근태·급여 처리 기준', () {
    test('07 기준이 무엇인지 정의한다', () {
      expect(_article(service, 8), contains('"근태·급여 처리 기준"이란'));
    });

    test('08 기준의 주인은 사업장이다', () {
      final a = _article(service, 8);
      expect(a, contains('사업장이 정하고 확인합니다'));
      expect(a, contains('회사는 기준값을 사업장을 대신해 정하지 않습니다'));
    });

    test('09 지원 시점 고정과 소급 불적용을 적는다 — 서버 동작과 같다', () {
      final a = _article(service, 8);
      expect(a, contains('지원하기 전에 그 근무에 적용될 기준을 확인'));
      expect(a, contains('확인한 기준은 해당 근무에 고정됩니다'));
      expect(a, contains('이미 확정된 근무에는 적용되지 않습니다'));
    });

    test('10 약관이 반올림 결과를 정당화하지 않는다', () {
      // 이 문장이 `.5` 의 핵심이다. 약관은 계산 방법을 설명할 수 있어도
      // 법정 임금 지급 의무를 줄이는 근거가 될 수 없다.
      // (근로기준법 제43조 제1항 — 전액 지급)
      final a = _article(service, 8);
      expect(a, contains('「근로기준법」이 정한 임금 지급 의무를 줄이거나 대신하지 않습니다'));
      expect(a, contains('법정 기준에 미치지 못하는 경우에는 법정 기준이 적용됩니다'));
    });

    test('11 기준을 "합의된 임금 조건" 으로 승격하지 않는다', () {
      for (final bad in <String>[
        '이 기준에 따라 산정된 금액을 최종 임금으로',
        '이 기준에 동의한 것으로 보아',
        '이의를 제기할 수 없습니다',
      ]) {
        expect(service, isNot(contains(bad)), reason: bad);
      }
    });
  });

  // ───────────────────────────────────────────────────────────
  group('TW-4 제9조 — 법정 의무의 주체', () {
    test('12 네 가지 의무와 조문이 함께 적혀 있다', () {
      final a = _article(service, 9);
      for (final e in <String>[
        '근로조건의 명시와 서면 교부 (「근로기준법」 제17조)',
        '임금의 전액 지급 (「근로기준법」 제43조)',
        '임금대장 작성과 임금명세서 교부 (「근로기준법」 제48조)',
        '근로계약에 관한 서류의 보존 (「근로기준법」 제42조)',
      ]) {
        expect(a, contains(e), reason: e);
      }
    });

    test('13 의무 주체는 사업장이고, 회사는 수단을 제공한다', () {
      final a = _article(service, 9);
      expect(a, contains('의무의 주체는 사용자인 사업장입니다'));
      expect(a, contains('의무를 대신 지지 않습니다'));
      // 반대로 회사가 의무를 이행한다고 약속하지도 않는다.
      expect(service, isNot(contains('회사가 임금명세서를 교부')));
    });
  });

  // ───────────────────────────────────────────────────────────
  group('TW-5 조 번호', () {
    test('14 제1조부터 제11조까지 하나씩, 중복 없이', () {
      final nos = RegExp(r'^제(\d+)조 \(', multiLine: true)
          .allMatches(service)
          .map((m) => int.parse(m.group(1)!))
          .toList();
      expect(nos, List<int>.generate(11, (i) => i + 1),
          reason: '조 번호가 어긋났다: $nos');
    });

    test('15 시행일과 이전 시행일이 함께 있다', () {
      expect(service, contains('■ 시행일: 2026년 10월 8일'));
      expect(service, contains('■ 이전 시행일: 2026년 8월 1일'));
    });
  });

  // ───────────────────────────────────────────────────────────
  group('TW-6 보존기간 — 세 문서가 같은 근거를 가리킨다', () {
    test('16 어느 문서도 5년을 말하지 않는다', () {
      // 근로기준법 제42조의 기간은 3년이다. 옛 문구는 근로기준법을 근거로
      // 들면서 5년을 적었다 — 법령명 오인용이었다.
      for (final e in {
        'service_terms': service,
        'privacy_policy': privacy,
        'privacy_third_party': thirdParty,
        'location_terms': location,
      }.entries) {
        expect(e.value, isNot(contains('5년')), reason: e.key);
      }
    });

    test('17 3년을 적은 곳은 근로기준법 제42조를 함께 적는다', () {
      for (final e in {
        'privacy_policy': privacy,
        'privacy_third_party': thirdParty,
        'location_terms': location,
      }.entries) {
        for (final line in e.value.split('\n')) {
          if (!line.contains('3년')) continue;
          expect(line.contains('근로기준법 제42조'), isTrue,
              reason: '근거 없는 3년 (${e.key}): $line');
        }
      }
    });

    test('18 출퇴근 기록을 독립 법정 class 로 단정하지 않는다', () {
      // privacy_policy 가 이미 정한 방식을 나머지도 따른다.
      for (final e in {
        'privacy_policy': privacy,
        'privacy_third_party': thirdParty,
        'location_terms': location,
      }.entries) {
        expect(e.value, contains('임금 계산의 근거가 되는 기록'), reason: e.key);
        expect(e.value, isNot(contains('출퇴근 기록: 3년')), reason: e.key);
      }
    });

    test('19 세무 자료에 없는 조문·연수를 지어내지 않는다', () {
      for (final e in {
        'privacy_third_party': thirdParty,
        'location_terms': location,
      }.entries) {
        for (final invented in <String>[
          '국세기본법', '법인세법', '부가가치세법', '상법 제33조',
        ]) {
          expect(e.value, isNot(contains(invented)), reason: '${e.key}/$invented');
        }
      }
      expect(thirdParty, contains('관계 세법이 정한 기간'));
    });
  });

  // ───────────────────────────────────────────────────────────
  group('TW-7 제3자 제공 — 실제 제공과 맞는다', () {
    test('20 통장 사본이 제공 항목 목록 안에 있다', () {
      // worker_detail_dialog 가 callableGetBankbookSignedUrl 로 관리자에게
      // 통장 사본 이미지를 보여준다. 고지에 없으면 거짓이다.
      //
      // [M6] 문서 어딘가에 "통장 사본" 이 있는지만 보면 안 된다 — 아래
      //   열람 범위 설명에도 그 말이 나오므로, 제공 항목에서 지워도
      //   통과해버린다. **목록 안에서** 본다.
      final s = thirdParty.indexOf('[제공하는 개인정보 항목]');
      final e = thirdParty.indexOf('[신분증·통장 사본의 열람 범위와 종료]');
      expect(s, greaterThan(-1));
      expect(e, greaterThan(s));
      final items = thirdParty.substring(s, e);
      for (final it in <String>[
        '이름, 휴대폰 번호',
        '계좌번호, 은행명, 예금주',
        '통장 사본',
        '신분증 사본',
        '출퇴근 기록',
        '지원 이력 및 근무 기록',
      ]) {
        expect(items, contains(it), reason: '제공 항목에 "$it" 이 없다');
      }
      final client = _read('lib/widgets/dialogs/worker_detail_dialog.dart');
      expect(client, contains('callableGetBankbookSignedUrl'),
          reason: '관리자 열람 경로가 사라졌다면 이 고지도 다시 봐야 한다');
    });

    test('21 신분증 열람을 "요청하면 공개" 로 적지 않는다', () {
      // 실제 조건은 동의 + 유효한 지원·근무관계 + 권한 + 자동 종료다.
      expect(thirdParty, isNot(contains('별도 요청 시 공개')));
      expect(thirdParty, contains('[신분증·통장 사본의 열람 범위와 종료]'));
      expect(thirdParty, contains('마지막 근무일부터 7일'));
      expect(thirdParty, contains('거절·취소·만료되면'));
    });

    test('22 확정 전 열람을 숨기지 않는다', () {
      // DocumentAccessConsent 2026-09-18-v3 가 채용 검토 목적 열람을 담는다.
      expect(thirdParty, contains('지원한 사업장의 권한 있는 관리자'));
      expect(thirdParty, contains('지원자 확인 및 채용 검토'));
      expect(thirdParty, isNot(contains('근무 확정된 사업장의 관리자')));
    });

    test('23 처리방침이 근무시간 인정·임금 계산 목적을 말한다', () {
      expect(privacy,
          contains('사업장이 정한 근태·급여 처리 기준에 따른 근무시간 인정 및 임금 계산'));
    });
  });

  // ───────────────────────────────────────────────────────────
  group('TW-8 문구 위생', () {
    test('24 내부 기술어가 근로자 문구에 새지 않는다', () {
      for (final e in {
        'service_terms': service,
        'privacy_third_party': thirdParty,
        'location_terms': location,
      }.entries) {
        for (final jargon in <String>[
          'snapshot', 'fingerprint', 'canonical', 'projection',
          'acknowledgement', '스냅샷',
        ]) {
          expect(e.value.toLowerCase(), isNot(contains(jargon.toLowerCase())),
              reason: '${e.key}: $jargon');
        }
      }
    });

    test('25 과도한 절대어를 쓰지 않는다', () {
      for (final e in {
        'service_terms': service,
        'privacy_third_party': thirdParty,
        'location_terms': location,
      }.entries) {
        for (final abs in <String>['전적으로', '일체의 책임', '어떠한 경우에도']) {
          expect(e.value, isNot(contains(abs)), reason: '${e.key}: $abs');
        }
      }
    });

    test('26 마케팅 동의는 이번 개정에서 손대지 않았다', () {
      expect(marketing, contains('■ 마케팅 정보 수신 동의 (선택)'));
      expect(marketing, isNot(contains('근태')));
      expect(marketing, isNot(contains('2026년 10월')));
    });
  });

  // ───────────────────────────────────────────────────────────
  group('TW-9 사업자 정보 placeholder', () {
    test('27 남아 있는 placeholder 와 blocker 기록이 정확히 일치한다', () {
      // [M8] "하나라도 남았는가" 로 묶으면 넷 중 셋을 채워도 통과한다.
      //   placeholder **하나하나**를 문서 표와 맞춘다 — 양방향이다.
      //     · 약관에서 채웠는데 문서에 남아 있으면  → 깨진다
      //     · 문서에서 지웠는데 약관에 남아 있으면  → 깨진다
      const holders = <String, String>{
        '[대표자명 기재 필요]': 'service_terms 제1조 대표자',
        '[사업장 주소 기재 필요]': 'service_terms 제1조 소재지',
        '[사업자등록번호 기재 필요]': 'service_terms 제1조 사업자등록번호',
        '[회사명 기재 필요]': 'location_terms 위치기반서비스사업자',
      };
      final present = <String>{
        for (final h in holders.keys)
          if (service.contains(h) || location.contains(h)) h,
      };
      for (final h in holders.keys) {
        expect(gateDoc.contains(h), present.contains(h),
            reason: '${holders[h]} — 약관과 blocker 문서가 어긋났다: $h');
      }
      const token = '[LEGAL-BLOCKER-BUSINESS-IDENTITY-PLACEHOLDER]';
      expect(gateDoc.contains(token), present.isNotEmpty,
          reason: present.isNotEmpty ?
              '약관에 placeholder 가 남아 있는데 blocker 기록이 없다' :
              'placeholder 를 모두 채웠는데 blocker 기록이 남아 있다');
    });

    test('28 실제 사업자 정보를 지어내지 않았다', () {
      // 확인되지 않은 상호·번호를 넣는 것이 placeholder 보다 나쁘다.
      // placeholder 가 아닌 값이 들어왔다면 그 값은 **사용자가 준 것**이어야
      // 하고, 그때는 위 27 이 문서와의 일치를 요구한다.
      expect(RegExp(r'사업자등록번호: \d').hasMatch(service), isFalse,
          reason: '확인되지 않은 사업자등록번호가 들어갔다');
      for (final invented in <String>['가상', '예시', '샘플', 'TODO', 'XXX']) {
        expect(_article(service, 1), isNot(contains(invented)),
            reason: '사업자 정보에 임시 값이 들어갔다: $invented');
      }
    });
  });

  // ───────────────────────────────────────────────────────────
  group('TW-10 약관과 화면 고지가 같은 것을 말한다', () {
    test('29 제8조가 화면 고지의 네 범주를 모두 담는다', () {
      final a = _article(service, 8);
      for (final cat in <String>['일찍 도착', '지각', '연장', '조퇴']) {
        expect(a, contains(cat), reason: '제8조에 "$cat" 범주가 없다');
        expect(disclosure, contains(cat),
            reason: '화면 고지에 "$cat" 이 없다 — 한쪽만 바뀌었다');
      }
    });

    test('30 고지 항목 수(7)와 임금 영향 필드 수가 같다', () {
      // `.4B` 가 화면·PDF 를 같은 formatter 로 묶었다. 약관 제8조는 그 일곱
      // 숫자를 나열하지 않는다 — 근무마다 값이 다르기 때문이다. 대신 범주를
      // 말한다. 그래서 여기서는 **개수가 늘었는지**만 본다.
      // 생성자 호출이 줄바꿈될 수 있으므로 함수 본문을 잘라 세어야 한다 —
      // `AttendancePolicyLine('` 로 세면 포매팅에 따라 수가 달라진다.
      final s = disclosure.indexOf('attendancePolicyGroups(AttendanceRules r)');
      final e = disclosure.indexOf('attendancePolicyLines(AttendanceRules r)');
      expect(s, greaterThan(-1));
      expect(e, greaterThan(s));
      final lines = 'AttendancePolicyLine('
          .allMatches(disclosure.substring(s, e))
          .length;
      expect(lines, 7,
          reason: '임금에 영향하는 항목 수가 바뀌었다 — 약관 제8조 범주도 다시 봐야 한다');
    });
  });
}
