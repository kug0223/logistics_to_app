// [R8-INTEGRATED §7] 계약 상태의 **시각 표현 소유자**.
//
// ── 왜 한 곳으로 모으는가 ───────────────────────────────────────────
//   같은 사건이 화면마다 다른 색으로 말해지고 있었다. 실측:
//
//     상태                계약 관리 화면        지난 계약 화면군
//     pending_employer    warning (주황)        warning  (주황)
//     pending_worker      **info (파랑)**       **warning (주황)**
//     completed           success               successDark
//     voided              grey500               grey600
//
//   `근무자 서명 대기` 가 한 화면에서는 파랑이고 다른 화면에서는 주황이었다.
//   근로자와 사업주 중 **누가 움직여야 하는가** 는 관리자가 목록을 훑으며
//   가장 먼저 판단하는 것이다. 같은 상태가 화면마다 다른 색이면 그 판단이
//   화면을 옮길 때마다 흔들린다.
//
//   라벨은 이미 한 곳에 있다(`ContractStatusX.label`). 색만 화면별 private
//   함수로 흩어져 있었다. 그래서 색도 라벨과 같은 축으로 모은다.
//
// ── 왜 두 대기 상태를 다른 색으로 두는가 ────────────────────────────
//   둘을 같은 주황으로 묶으면 "내가 서명해야 한다" 와 "상대를 기다린다" 가
//   구별되지 않는다. 행동 주체가 다르므로 색도 다르다 —
//   사업주 차례는 주황(내 할 일), 근무자 차례는 파랑(기다림)이다.
//
//   전경색은 `*Dark`, 배경은 `*Bg` 로 짝지어 쓴다. 연한 배경 위의 중간 톤은
//   작은 라벨에서 대비가 부족했다(기존 배지 수정에서 확인된 짝).
import 'package:flutter/material.dart';

import '../models/core/employment_contract_model.dart';
import '../theme/app_colors.dart';

/// 계약 상태 배지의 전경·배경 한 벌.
typedef ContractStatusColors = ({Color fg, Color bg});

extension ContractStatusVisual on ContractStatus {
  /// 이 상태를 표현하는 색. **모든 화면이 이 값을 쓴다.**
  ContractStatusColors get badgeColors {
    switch (this) {
      case ContractStatus.pendingEmployer:
        // 사업주가 서명할 차례 — 관리자의 할 일이다.
        return (fg: AppColors.warningDark, bg: AppColors.warningBg);
      case ContractStatus.pendingWorker:
        // 근무자를 기다리는 중 — 관리자가 할 일은 없다.
        return (fg: AppColors.infoDark, bg: AppColors.infoBg);
      case ContractStatus.completed:
        return (fg: AppColors.successDark, bg: AppColors.successBg);
      case ContractStatus.voided:
        return (fg: AppColors.grey600, bg: AppColors.grey100);
    }
  }
}

/// 문자열 상태값(`'pending_worker'` 등)에서 같은 색을 얻는다.
///
///   지난 계약 화면군은 enum 이 아니라 요약 문서의 문자열을 들고 있다.
///   그 경로도 **같은 표**를 쓰게 하려고 문자열 입구를 함께 둔다.
///   모르는 값은 `voided` 와 같은 중립색으로 둔다 — 색으로 추측하지 않는다.
ContractStatusColors contractStatusColorsOf(String? rawStatus) {
  switch (rawStatus) {
    case 'pending_employer':
      return ContractStatus.pendingEmployer.badgeColors;
    case 'pending_worker':
      return ContractStatus.pendingWorker.badgeColors;
    case 'completed':
      return ContractStatus.completed.badgeColors;
    case 'voided':
      return ContractStatus.voided.badgeColors;
    default:
      return ContractStatus.voided.badgeColors;
  }
}
