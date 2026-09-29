// lib/utils/business_location_status.dart
//
// [R7-P4.3A] 사업장 주소 → 위치 확인 상태를 **사용자에게 뭐라고 말할지**.
//
// ── 왜 화면 밖으로 뺐나 ────────────────────────────────────────────
//   예전에는 등록 폼이 좌표가 `null` 이냐 아니냐만 보고 한 문장을 썼다:
//     'GPS 위치 미확인 — 탭하여 주소 재검색'
//   그 한 문장에 여섯 가지가 섞여 있었다.
//     · 아직 주소를 고르지 않았다
//     · 지금 조회 중이다
//     · 그 주소로 등록된 좌표가 없다        → 주소를 바꿔야 한다
//     · 네트워크가 안 됐다                   → 다시 누르면 될 수 있다
//     · 빌드에 API 키가 없다                 → 기기에서 뭘 해도 안 된다
//     · 키가 거부됐다                        → 〃
//   다음 행동이 전부 다른데 문장과 버튼이 같으니, 관리자는 되지도 않을
//   주소 재검색만 반복하게 된다.
//
//   'GPS' 라는 말 자체도 틀렸다. 이 값은 **주소로 찾은 사업장 위치**이지
//   관리자 기기의 현재 위치가 아니다. 등록 폼은 기기 위치를 한 번도 읽지
//   않는다 — 본사에서 다른 지점을 등록할 수 있어야 하기 때문이다.

import '../services/geocoding_service.dart';

/// 상태 칩을 눌렀을 때 할 일.
enum LocationAction {
  /// 누를 것이 없다 — 확인됐거나, 아직 주소가 없거나, 조회 중이다.
  none,

  /// 같은 주소로 다시 조회한다. **일시적** 실패에만 권한다.
  retry,

  /// 좌표를 직접 입력한다. 다시 눌러도 결과가 같을 때의 탈출구다.
  manual,
}

/// 사용자에게 보여 줄 한 줄과 그때 할 수 있는 행동.
class BusinessLocationCopy {
  const BusinessLocationCopy(this.text, this.action);

  final String text;
  final LocationAction action;
}

/// 현재 상태 → 문구·행동.
///
/// - [resolving] : 조회가 진행 중
/// - [resolved]  : **지금 주소의** 좌표를 갖고 있다
/// - [failure]   : 마지막 조회의 실패 원인 (없으면 null)
BusinessLocationCopy businessLocationCopy({
  required bool resolving,
  required bool resolved,
  GeocodeStatus? failure,
}) {
  // 순서가 중요하다. 조회 중이면 직전 실패 문구가 남아 있어도 그것을 말하지
  // 않는다 — 지금 벌어지는 일이 우선이다.
  if (resolving) {
    return const BusinessLocationCopy(
      '주소의 위치를 확인하고 있어요',
      LocationAction.none,
    );
  }
  if (resolved) {
    return const BusinessLocationCopy(
      '사업장 위치 확인됨',
      LocationAction.none,
    );
  }
  return switch (failure) {
    // 같은 주소로 다시 조회해도 결과는 같다 — 재시도를 권하지 않는다.
    GeocodeStatus.notFound => const BusinessLocationCopy(
        '이 주소의 위치를 찾지 못했어요 — 탭하여 직접 입력',
        LocationAction.manual,
      ),
    // 네트워크·타임아웃. 이것만 재시도가 의미 있다.
    GeocodeStatus.unavailable => const BusinessLocationCopy(
        '위치를 확인하지 못했어요 — 탭하여 다시 시도',
        LocationAction.retry,
      ),
    // 기기에서 무엇을 해도 안 된다. 주소를 바꿔 보라고 하지 않는다.
    // 그렇다고 등록을 막아 세우지도 않는다 — 직접 입력을 남겨 둔다.
    GeocodeStatus.unauthorized || GeocodeStatus.notConfigured =>
      const BusinessLocationCopy(
        '앱 설정 문제로 위치를 확인할 수 없어요 — 탭하여 직접 입력',
        LocationAction.manual,
      ),
    // 아직 아무것도 하지 않았다.
    null || GeocodeStatus.resolved => const BusinessLocationCopy(
        '주소를 검색하면 사업장 위치가 확인돼요',
        LocationAction.none,
      ),
  };
}
