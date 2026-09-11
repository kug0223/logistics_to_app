// 지원자 처리 용어 정렬 (AHF-02 / AHF-03)
//
// 첫 지원자를 확정하는 30초 동안 관리자는 같은 한 사람, 같은 한 행동을
// 여러 이름으로 만났다.
//   PENDING : '지원'(상단 요약) / '대기'(그룹 배지) / '대기 중'(섹션 헤더)
//   확정    : 버튼 '승인' → 확인 제목 '확정' → 토스트 '승인되었습니다'
//   그리고 WorkApplicantsDialog는 전부 '승인'이었다.
//
// canonical:
//   PENDING = '지원'  — 아직 처리하지 않은 지원. 관리자가 보류한 상태가 아니다.
//                      제품에 그런 lifecycle(WAITING/보류)이 없으므로
//                      '대기'는 없는 상태를 암시한다.
//   확정 행동 = '확정' — 지원 = 관심, 확정 = 약속.
//
// INVITED는 두 dialog 어디에도 표시되지 않으므로(아래 AHV-2x)
// pendingApps를 '지원'으로 부르는 것이 정확하다.
//
// 두 dialog는 Firebase 서비스를 필드로 즉시 보유해 widget test가 불가능하다.
// 사용자 문구 계약은 소스(주석·debugPrint 제외)로 검증한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';

const _day = 'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';
const _work = 'lib/screens/business_admin/dialogs/work_applicants_dialog.dart';

String _source(String p) {
  final f = File(p);
  expect(f.existsSync(), true, reason: '$p 를 찾지 못함');
  return f.readAsStringSync();
}

/// 사용자에게 보이는 문구만 본다.
///
/// 제외 대상:
///   · 주석 — 설명에 옛 용어가 등장한다
///   · debugPrint — 로그
///   · Exception(...) — 내부 예외 메시지. catch 쪽이 일반 문구를 보여주므로
///     사용자에게 이 문자열이 그대로 노출되지 않는다(§9 내부는 변경 대상 아님).
String _copyOf(String p) {
  final lines = _source(p)
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .where((l) => !l.contains('debugPrint('))
      .where((l) => !l.contains('Exception('))
      .join('\n');
  return RegExp(r"'(?:[^'\\\n]|\\.)*'")
      .allMatches(lines)
      .map((m) => m.group(0)!)
      .join('\n');
}

void main() {
  // ── AHF-02 PENDING 용어 ─────────────────────────────────────────
  group('AHV-0x PENDING은 한 단어로 부른다', () {
    test('AHV-01 "대기"로 지원자 수를 세는 문구가 없다', () {
      // '서명대기'(계약 서명 대기)와 '계약 대기 상태'(CONTRACT_PENDING 설명)는
      // 다른 개념이므로 카운트 라벨만 검사한다.
      final countLabel = RegExp(r"'대기( 중)?[ (]");
      for (final p in const [_day, _work]) {
        final hits = _copyOf(p)
            .split('\n')
            .where((l) => countLabel.hasMatch(l))
            .toList();
        expect(hits, isEmpty, reason: '$p 에 대기 계열 카운트 라벨 잔존: $hits');
      }
    });

    test('AHV-02 두 dialog 모두 "지원"으로 센다', () {
      expect(_copyOf(_day).contains(r"'지원 $totalPending'"), true);
      expect(_copyOf(_work).contains("'지원'"), true);
    });

    test('AHV-03 별개 개념인 "서명대기"는 유지된다', () {
      // 계약 서명 대기는 PENDING이 아니다 — 함께 쓸어내면 안 된다.
      for (final p in const [_day, _work]) {
        expect(_copyOf(p).contains("'서명대기'"), true, reason: '$p 서명대기 소실');
      }
    });

    test('AHV-04 "계약 대기 상태" 설명은 유지된다', () {
      // 확정의 결과가 CONTRACT_PENDING임을 알리는 좋은 문구다(§8).
      final c = _copyOf(_day);
      expect(c.contains('계약 대기 상태로 변경하시겠습니까'), true);
      expect(c.contains('이후 계약서를 직접 작성·서명해야 합니다'), true);
    });
  });

  // ── AHF-03 확정 용어 ────────────────────────────────────────────
  group('AHV-1x 확정 행동은 한 단어로 부른다', () {
    test('AHV-10 사용자 문구에 "승인"이 남지 않았다', () {
      for (final p in const [_day, _work]) {
        final hits = _copyOf(p)
            .split('\n')
            .where((l) => l.contains('승인'))
            .toList();
        expect(hits, isEmpty, reason: '$p 에 승인 잔존: $hits');
      }
    });

    test('AHV-11 두 dialog의 확정 버튼이 같은 단어다', () {
      expect(_copyOf(_day).contains("'확정'"), true);
      expect(_copyOf(_work).contains("'확정'"), true);
    });

    test('AHV-12 성공 피드백이 확정으로 통일됐다', () {
      expect(
          _copyOf(_day).contains("'확정되었습니다. 계약서를 작성해 주세요.'"), true);
      expect(_copyOf(_work).contains('님이 확정되었습니다. 계약서를 작성해 주세요.'), true);
    });

    test('AHV-13 일괄 처리도 확정으로 통일됐다', () {
      final c = _copyOf(_day);
      expect(c.contains("'일괄 확정'"), true);
      expect(c.contains("'일괄 승인'"), false);
    });

    test('AHV-14 내부 식별자는 바꾸지 않았다', () {
      // 함수명·enum·주석은 대상이 아니다(§9).
      final s = _source(_day);
      expect(s.contains('_batchApprove'), true);
      expect(s.contains('_approveApp'), true);
      expect(_source(_work).contains('canApproveWithContract'), true);
    });
  });

  // ── §2 INVITED 분류 (display contract 고정) ─────────────────────
  group('AHV-2x INVITED는 관리자 지원자 목록에 표시되지 않는다', () {
    test('AHV-20 INVITED는 별개 status다', () {
      expect(AppStatus.invited, 'INVITED');
      expect(AppStatus.pending, 'PENDING');
      expect(AppStatus.invited == AppStatus.pending, false);
    });

    test('AHV-21 두 dialog 모두 INVITED를 참조하지 않는다', () {
      // 관리자 목록은 PENDING/CONFIRMED 두 갈래뿐이다.
      // 따라서 pendingApps를 '지원'으로 부르는 것이 정확하다.
      for (final p in const [_day, _work]) {
        expect(_source(p).contains('AppStatus.invited'), false,
            reason: '$p 가 INVITED를 다루기 시작했다 — 라벨 재검토 필요');
      }
    });

    test('AHV-22 pending 목록은 PENDING만 담는다', () {
      expect(
          _source(_work).contains('status == AppStatus.pending'), true);
      // Day는 서비스 레이어에서 필터한다
      final svc = _source('lib/services/firestore/application_firestore.dart');
      expect(svc.contains('app.status == AppStatus.pending'), true);
    });
  });

  // ── 범위 불변식 ─────────────────────────────────────────────────
  group('AHV-3x 표현만 바꿨다', () {
    test('AHV-30 거절 흐름 무변경', () {
      expect(_copyOf(_day).contains("'지원 거절'"), true);
      expect(_copyOf(_day).contains('거절 사유를 선택해주세요'), true);
      expect(_copyOf(_work).contains("'거절'"), true);
    });

    test('AHV-31 정원 초과 차단 문구 유지', () {
      expect(_copyOf(_day).contains('정원이 초과되어 확정할 수 없습니다'), true);
    });

    test('AHV-32 처리 후 전체 재조회 유지', () {
      final s = _source(_day);
      expect('await _load();'.allMatches(s).length >= 5, true,
          reason: 'reload semantics가 줄었다');
    });

    test('AHV-33 초대 CTA 문구·정원 계산 무변경', () {
      final s = _source(_day);
      expect(s.contains(r"'인력 초대 ($shortage명 부족)'"), true);
      expect(s.contains('isPendingSufficient'), true);
      // shortage 공식: Σ max(required - confirmed(active), 0)
      expect(s.contains('g.requiredCount -'), true);
      expect(s.contains('!a.isStaffingReleased'), true);
    });

    test('AHV-34 노쇼 배지 무변경 (AHF-07 제외)', () {
      expect(_copyOf(_day).contains(r'최근 90일 노쇼 $count회'), true);
    });

    test('AHV-35 정렬/필터·필요 인원을 추가하지 않았다', () {
      // AHF-04 / AHF-05 는 이번 범위 밖이다.
      final s = _source(_day);
      for (final banned in const ['_sortBy', '_filterBy', 'SortOption']) {
        expect(s.contains(banned), false, reason: '$banned 가 추가됐다');
      }
    });
  });
}
