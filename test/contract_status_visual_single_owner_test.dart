// [R8-INTEGRATED §3·§7] 같은 사건은 모든 화면에서 같은 색으로 말한다.
//
// ── 무엇이 틀려 있었나 ──────────────────────────────────────────────
//   계약 상태 배지 색이 화면별 private switch 로 흩어져 있었고, 값이 갈려
//   있었다. 실측:
//
//     pending_worker  →  계약 관리 화면 `info`(파랑) / 지난 계약 화면군 `warning`(주황)
//
//   `근무자 서명 대기` 가 화면을 옮기면 다른 색이 됐다. 관리자가 목록에서
//   가장 먼저 읽는 것이 "누가 움직여야 하는가" 인데, 그 신호가 화면마다
//   달랐다. 라벨(`ContractStatusX.label`)은 이미 한 곳에 있었고 색만 아니었다.
//
// ── 이 테스트가 고정하는 것 ─────────────────────────────────────────
//   ① enum 입구와 문자열 입구가 **같은 색**을 돌려준다
//      (지난 계약 화면군은 요약 문서의 문자열을 들고 있다)
//   ② 두 대기 상태는 **서로 다른 색**이다 — 행동 주체가 다르다
//   ③ 네 상태가 모두 구별된다
//   ④ 모르는 값은 색으로 추측하지 않는다(중립)
//   ⑤ 전경/배경은 `*Dark`/`*Bg` 짝으로만 쓴다
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/utils/contract_status_visual.dart';

void main() {
  group('§3 같은 사건 = 같은 색', () {
    test('enum 입구와 문자열 입구가 일치한다', () {
      for (final s in ContractStatus.values) {
        final viaEnum = s.badgeColors;
        final viaString = contractStatusColorsOf(s.value);
        expect(viaString.fg, viaEnum.fg, reason: '${s.value} 전경색');
        expect(viaString.bg, viaEnum.bg, reason: '${s.value} 배경색');
      }
    });

    test('두 대기 상태는 서로 다른 색이다 (행동 주체가 다르다)', () {
      final employer = ContractStatus.pendingEmployer.badgeColors;
      final worker = ContractStatus.pendingWorker.badgeColors;
      expect(employer.fg, isNot(worker.fg));
      expect(employer.bg, isNot(worker.bg));
    });

    test('네 상태가 모두 구별된다', () {
      final seen = <int>{};
      for (final s in ContractStatus.values) {
        // ignore: deprecated_member_use
        seen.add(s.badgeColors.fg.value);
      }
      expect(seen.length, ContractStatus.values.length,
          reason: '색이 겹치면 상태를 구별할 수 없다');
    });
  });

  group('§7 토큰 사용 규칙', () {
    test('사업주 차례는 경고 톤, 근무자 차례는 정보 톤', () {
      expect(ContractStatus.pendingEmployer.badgeColors.fg,
          AppColors.warningDark);
      expect(ContractStatus.pendingEmployer.badgeColors.bg, AppColors.warningBg);
      expect(ContractStatus.pendingWorker.badgeColors.fg, AppColors.infoDark);
      expect(ContractStatus.pendingWorker.badgeColors.bg, AppColors.infoBg);
    });

    test('완료는 성공 톤, 무효는 중립 톤', () {
      expect(ContractStatus.completed.badgeColors.fg, AppColors.successDark);
      expect(ContractStatus.completed.badgeColors.bg, AppColors.successBg);
      expect(ContractStatus.voided.badgeColors.fg, AppColors.grey600);
      expect(ContractStatus.voided.badgeColors.bg, AppColors.grey100);
    });

    test('모르는 상태는 색으로 추측하지 않는다 — 중립색', () {
      final unknown = contractStatusColorsOf('무엇인지 모르는 값');
      expect(unknown.fg, ContractStatus.voided.badgeColors.fg);
      expect(contractStatusColorsOf(null).fg,
          ContractStatus.voided.badgeColors.fg);
    });
  });

  group('§7 흩어진 사본이 남아 있지 않다', () {
    test('세 화면 모두 private switch 를 버리고 공용 표를 쓴다', () {
      const files = [
        'lib/screens/business_admin/admin_contract_management_screen.dart',
        'lib/screens/business_admin/historical_contracts_screen.dart',
        'lib/screens/business_admin/historical_contract_detail_screen.dart',
      ];
      for (final f in files) {
        final src = _read(f);
        expect(src.contains('contract_status_visual'), isTrue,
            reason: '$f 가 공용 표를 import 하지 않는다');
        // 상태값을 직접 색에 매핑하는 case 가 남아 있으면 사본이다.
        expect(
          src.contains("case 'pending_worker':\n        return (bg:"),
          isFalse,
          reason: '$f 에 색 매핑 사본이 남아 있다',
        );
      }
    });
  });
}

String _read(String path) {
  // 테스트는 프로젝트 루트에서 실행된다.
  return File(path).readAsStringSync();
}
