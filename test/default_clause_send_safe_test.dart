// ALfit 기본 조항 send-safe 불변식 (C-P1-01)
//
// canonical rule:
//   DEFAULT ARTICLE = READY TO SEND
//
// renderer(ContractTemplateWidget)가 article.content를 그대로 PDF에 출력하므로,
// 관리자가 수정하지 않고 발송해도 문서가 완결되어 있어야 한다.
// 기본 조항에 다음이 있으면 근로자가 서명하는 문서에 그대로 인쇄된다:
//   · 관리자 편집 지시문   · 빈칸 placeholder
//   · 미체크 체크박스      · 대체 문구 후보
//   · 관리자 교육용 경고   · 시점 의존 전환 안내
//
// 특정 문자열 하나가 아니라 위 semantic invariant를 검증한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/contract_template_model.dart';

/// 신규 생성에서 선택 가능한 분류만 검사한다.
/// outsource는 4.1에서 신규 생성 대상에서 제외됐고 legacy read 호환으로만 남아 있다.
const _activeTypes = <String>[
  ContractTemplateType.daily,
  ContractTemplateType.period,
];

Iterable<ContractArticle> _allActiveDefaults() sync* {
  for (final t in _activeTypes) {
    yield* ContractTemplateModel.defaultArticlesFor(t);
  }
}

/// 조항을 "type/title" 로 식별해 실패 메시지에서 바로 찾을 수 있게 한다.
Iterable<MapEntry<String, ContractArticle>> _labeled() sync* {
  for (final t in _activeTypes) {
    for (final a in ContractTemplateModel.defaultArticlesFor(t)) {
      yield MapEntry('$t/${a.title}', a);
    }
  }
}

void main() {
  group('기본 조항 send-safe 불변식', () {
    test('DSS-01 미완성 placeholder 없음 (빈칸)', () {
      // '__개월', '____' 등 관리자가 채워야 하는 빈칸
      final placeholder = RegExp(r'_{2,}');
      for (final e in _labeled()) {
        expect(placeholder.hasMatch(e.value.content), false,
            reason: '${e.key} 에 빈칸 placeholder가 남아 있음');
        expect(placeholder.hasMatch(e.value.title), false,
            reason: '${e.key} 제목에 빈칸 placeholder가 남아 있음');
      }
    });

    test('DSS-02 미체크 체크박스 없음', () {
      // □ / ☐ / [ ] 형태
      final box = RegExp(r'[□☐]|\[\s\]');
      for (final e in _labeled()) {
        expect(box.hasMatch(e.value.content), false,
            reason: '${e.key} 에 미체크 체크박스가 남아 있음');
      }
    });

    test('DSS-03 관리자 편집 지시문 없음', () {
      // 관리자에게 행동을 요구하는 명령형 어미 + 편집 동사
      final instruction = RegExp(
        r'(삭제하거나|삭제하세요|수정하세요|확인하세요|사용하세요|체크|기입하세요|입력하세요)',
      );
      for (final e in _labeled()) {
        expect(instruction.hasMatch(e.value.content), false,
            reason: '${e.key} 에 관리자 편집 지시문이 남아 있음');
      }
    });

    test('DSS-04 대체 문구 후보 / 관리자 주석 블록 없음', () {
      // 【 】 로 감싼 블록은 이 코드베이스에서 관리자 주석 관례였다.
      for (final e in _labeled()) {
        expect(e.value.content.contains('【'), false,
            reason: '${e.key} 에 관리자 주석 블록【】이 남아 있음');
        expect(e.value.content.contains('】'), false,
            reason: '${e.key} 에 관리자 주석 블록【】이 남아 있음');
      }
    });

    test('DSS-05 사업주 대상 과태료/제재 안내 없음', () {
      // 근로조건이 아니라 관리자 교육용 경고
      for (final e in _labeled()) {
        expect(e.value.content.contains('과태료'), false,
            reason: '${e.key} 에 사업주 과태료 안내가 남아 있음');
      }
    });

    test('DSS-06 시점 의존 전환 안내 없음', () {
      // '2027년부터 단계 적용 예정' 같은 관리자용 transitional note.
      // 근로조건에 필요한 날짜값 전반을 금지하지는 않는다 —
      // 미래 연도 + 적용/시행/예정 조합만 검출한다.
      final futureNote = RegExp(r'20(2[7-9]|[3-9]\d)년[^\n]{0,20}(적용|시행|예정)');
      for (final e in _labeled()) {
        expect(futureNote.hasMatch(e.value.content), false,
            reason: '${e.key} 에 시점 의존 전환 안내가 남아 있음');
      }
    });
  });

  group('기본 조항 구조', () {
    test('DSS-10 daily / period 조항 수', () {
      // [5.9] 해지/해고예고 조항 제거로 각각 4 → 3.
      //   조항 수 대칭은 목표가 아니다 — 제거 결과가 우연히 같을 뿐이다.
      expect(
          ContractTemplateModel.defaultArticlesFor(ContractTemplateType.daily)
              .length,
          3);
      // [RB-01·RB-05] 4대보험 가입·근태 및 복무가 reference default에서 제외됨
      expect(
          ContractTemplateModel.defaultArticlesFor(ContractTemplateType.period)
              .length,
          3);
    });

    test('DSS-11 제목 조 번호가 제4조부터 끊김 없이 이어진다', () {
      // 고정 제1~3조 뒤에 붙으므로 default는 제4조에서 시작해야 한다.
      final numRe = RegExp(r'^제(\d+)조');
      for (final t in _activeTypes) {
        final nums = ContractTemplateModel.defaultArticlesFor(t)
            .map((a) => numRe.firstMatch(a.title))
            .map((m) => m == null ? -1 : int.parse(m.group(1)!))
            .toList();
        expect(nums.contains(-1), false, reason: '$t: 제N조 형식이 아닌 제목이 있음');
        for (var i = 0; i < nums.length; i++) {
          expect(nums[i], 4 + i,
              reason: '$t: ${i + 1}번째 조항 번호가 제${4 + i}조가 아님 (제${nums[i]}조)');
        }
      }
    });

    test('DSS-12 제목·본문이 비어 있지 않다', () {
      for (final e in _labeled()) {
        expect(e.value.title.trim().isNotEmpty, true, reason: '${e.key} 제목 비어 있음');
        expect(e.value.content.trim().isNotEmpty, true, reason: '${e.key} 본문 비어 있음');
      }
    });
  });

  group('reference core 경계 — ALfit이 대신 판단하지 않는다', () {
    // ALfit은 사업장 정책이나 법적 적용 여부를 대신 확정하지 않는다.
    // 아래 주제들은 적용 조건을 ALfit이 추적·판정하지 않거나 사업장 정책이라
    // reference default에서 제외됐다. 제거는 "법적으로 불필요하다"가 아니라
    // "ALfit이 기본 템플릿에서 적용 여부를 대신 제시하지 않는다"는 뜻이다.
    const removedTopics = <String>[
      '4대보험',      // 가입 요건·부담률 — ALfit이 집계·판정하지 않음
      '주휴',         // ALfit이 자격 판정·수당 가산을 하지 않음
      '공휴일',       // 사업장 규모 조건 의존
      '연차',         // 발생 요건 미추적
      '퇴직급여',     // 발생 요건 미추적
      '차별금지',     // 사업주 대상 법정 금지의 낭독
      '근태',         // 사업장 취업규칙 영역
      '복무',
      '임금명세서',   // 실제 payroll/payslip 기능과 중복
      '수습',         // 관리자 입력 없이는 불완전
    ];

    test('DSS-30 제거된 주제가 어떤 default 제목에도 없다', () {
      for (final t in _activeTypes) {
        final titles = ContractTemplateModel.defaultArticlesFor(t)
            .map((a) => a.title)
            .toList();
        for (final topic in removedTopics) {
          expect(titles.any((x) => x.contains(topic)), false,
              reason: '$t default에 "$topic" 조항이 남아 있음');
        }
      }
    });

    test('DSS-31 ALfit이 대신 확정하던 문구가 본문에 없다', () {
      final all = _allActiveDefaults().map((a) => a.content).join('\n');
      expect(all.contains('징계'), false);
      expect(all.contains('급여에서 공제'), false);
      expect(all.contains('유급휴일'), false, reason: '주휴 부여 확정 문구');
      expect(all.contains('유급 공휴일'), false);
      expect(all.contains('유급휴가'), false, reason: '연차 발생 확정 문구');
    });

    test('DSS-32 daily reference core (제거만, 새 문장 창작 없음)', () {
      final titles =
          ContractTemplateModel.defaultArticlesFor(ContractTemplateType.daily)
              .map((a) => a.title)
              .toList();
      expect(titles, [
        '제4조 (안전·보건 및 산업재해)',
        '제5조 (개인정보 보호)',
        '제6조 (기타)',
      ]);
    });

    test('DSS-33 period reference core (제거만, 새 문장 창작 없음)', () {
      final titles =
          ContractTemplateModel.defaultArticlesFor(ContractTemplateType.period)
              .map((a) => a.title)
              .toList();
      expect(titles, [
        '제4조 (직장 내 괴롭힘 금지)',
        '제5조 (개인정보 보호)',
        '제6조 (기타)',
      ]);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // [5.9] mixed content finalization
  //
  // ALfit 기본값은 사업장 정책(징계·해지 사유, 영업비밀 범위, 책임 범위)이나
  // 조건부 법률 적용을 대신 확정하지 않는다. 아래는 제거된 세 영역이
  // 되살아나지 않는지 지키는 불변식이다. 관리자는 필요하면 편집 화면에서
  // 직접 작성할 수 있으므로 자유도는 줄지 않는다.
  // ─────────────────────────────────────────────────────────────────
  group('reference default에 해지/해고 상세 설명이 없다', () {
    test('DSS-40 해지·해고예고 조항이 어떤 default에도 없다', () {
      for (final t in _activeTypes) {
        final titles = ContractTemplateModel.defaultArticlesFor(t)
            .map((a) => a.title)
            .toList();
        expect(titles.any((x) => x.contains('해고')), false,
            reason: '$t default에 해고 관련 조항 제목이 남아 있음');
        expect(titles.any((x) => x.contains('계약 해지')), false,
            reason: '$t default에 계약 해지 조항 제목이 남아 있음');
      }
    });

    test('DSS-41 해지 상세 fragment가 본문에 남지 않았다', () {
      final all = _allActiveDefaults().map((a) => a.content).join('\n');
      // 5.6 외부 검증에서 부정확·조건부·정책으로 판정된 구체 표현만 검사한다.
      for (final fragment in const [
        '해고예고수당',
        '즉시 해고',
        '부당해고',
        '30일 이전에 서면',
        '30일 전에 예고',
        '해고예고',
      ]) {
        expect(all.contains(fragment), false,
            reason: 'default 본문에 "$fragment" 가 남아 있음');
      }
    });
  });

  group('사업장 정책 fragment가 기본값에 없다', () {
    test('DSS-42 안전 조항에 해지 정책이 없다', () {
      // 일반 안전·보건 내용은 유지하되, 어떤 위반이 계약 해지 사유인지는
      // 사업장 징계 정책이므로 ALfit이 기본값으로 정하지 않는다.
      final daily =
          ContractTemplateModel.defaultArticlesFor(ContractTemplateType.daily);
      final safety =
          daily.firstWhere((a) => a.title.contains('안전·보건'));
      expect(safety.content.contains('계약 해지 사유'), false);
      expect(safety.content.contains('안전 수칙 위반'), false);

      // 남아야 하는 일반 내용 — 제거가 과도하지 않았는지 확인
      expect(safety.content.contains('산업안전보건법'), true);
      expect(safety.content.contains('산업재해보상보험법'), true);
      expect(safety.content.contains('안전·보건 지시'), true);
    });

    test('DSS-43 비밀유지·책임 범위를 기본값이 확정하지 않는다', () {
      final all = _allActiveDefaults();
      for (final a in all) {
        expect(a.title.contains('비밀유지'), false,
            reason: '"${a.title}" 에 비밀유지가 남아 있음');
      }
      final body = all.map((a) => a.content).join('\n');
      for (final fragment in const [
        '영업비밀',
        '고객정보',
        '내부 운영 정보',
        '민·형사상 책임',
        '누설',
      ]) {
        expect(body.contains(fragment), false,
            reason: 'default 본문에 "$fragment" 가 남아 있음');
      }
    });

    test('DSS-44 개인정보 core는 양쪽 모두 남아 있다', () {
      // 제거가 개인정보 보호 자체를 지운 것이 아님을 확인한다.
      for (final t in _activeTypes) {
        final arts = ContractTemplateModel.defaultArticlesFor(t);
        final privacy =
            arts.where((a) => a.title.contains('개인정보 보호')).toList();
        expect(privacy.length, 1, reason: '$t 에 개인정보 보호 조항이 정확히 1개가 아님');
        expect(privacy.single.content.contains('개인정보보호법'), true);
        expect(privacy.single.content.trim().endsWith('.'), true,
            reason: '$t 개인정보 조항이 문장으로 완결되지 않음');
      }
    });
  });

  group('남은 core는 훼손되지 않았다', () {
    test('DSS-20 core 주제가 그대로 유지된다', () {
      final all = _allActiveDefaults().map((a) => a.content).join('\n');
      expect(all.contains('개인정보'), true);
      expect(all.contains('산업안전보건법'), true);
      // [5.9] '해고예고수당'은 해지 조항과 함께 제거됐다 — DSS-41이 부재를 지킨다.
      //   남은 core 주제로 직장 내 괴롭힘 금지를 확인한다.
      expect(all.contains('직장 내 괴롭힘'), true);
      expect(all.contains('관계 법령'), true);
    });

    test('DSS-21 남은 조항 본문은 이번 축소에서 재작성되지 않았다', () {
      // 제거만 했으므로 남은 조항의 첫 문장이 원문 그대로여야 한다.
      final daily =
          ContractTemplateModel.defaultArticlesFor(ContractTemplateType.daily);
      expect(
          daily.first.content
              .startsWith('① 사업주는 산업안전보건법에 따라 근로자가 안전한 환경에서 근무하도록'),
          true);
      final period =
          ContractTemplateModel.defaultArticlesFor(ContractTemplateType.period);
      expect(period.first.content.startsWith('사업주 및 근로자는 직장에서의'), true);
    });
  });
}
