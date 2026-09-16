// [SYSTEM-INTEGRATION-R2.3] 초대 받을 지역 설정.
//
// 제품 원칙:
//
//     거주지역 ≠ 초대 받을 지역
//
//   관리자가 보는 후보는 "그 지역에 사는 사람"이 아니라 "그 근무지역의 초대를
//   받아도 된다고 지원자가 직접 설정한 사람"이다. 실제 근로자는 본업 근처,
//   이동 중, 생활권 인접지역에서 일한다.
//
// 이 설정은 **먼저 오는 초대(proactive invitation)에만** 적용된다.
// 지원자가 직접 검색해서 지원하는 것은 이 설정과 무관하다.

import '../../data/korean_regions.dart';
import '../../utils/region_key.dart';
import 'user_region.dart';

/// [§8] 네 상태를 각각 구분한다.
///
///   UNSET != OFF   — 아직 안 정한 것과 끄기로 정한 것은 다르다.
///                    UNSET에만 설정 안내를 띄우고, OFF는 조르지 않는다(§28).
///   ERROR != OFF   — 못 읽은 것을 "초대 안 받음"으로 저장하면 안 된다.
enum InvitePreferenceState {
  /// 한 번도 설정한 적 없음 — 안내 대상.
  unset,

  /// 명시적으로 끔. 새 초대를 받지 않는다. 선택했던 지역은 보존된다.
  off,

  /// 켬 + 유효한 지역 1곳 이상.
  on,

  /// 읽지 못했다. OFF로도 ON으로도 단정하지 않는다.
  unknown,
}

class InviteRegionPreference {
  /// null = 문서에 값이 없음(UNSET).
  final bool? enabled;

  /// 지원자가 고른 지역. OFF여도 보존된다 — 다시 켤 때 처음부터 고르지 않도록.
  final List<UserRegion> regions;

  /// 읽기 실패. true면 다른 값은 의미 없다.
  final bool loadFailed;

  const InviteRegionPreference({
    this.enabled,
    this.regions = const [],
    this.loadFailed = false,
  });

  /// 읽지 못한 상태 — 빈 설정과 구분한다.
  const InviteRegionPreference.unknown()
      : enabled = null,
        regions = const [],
        loadFailed = true;

  static InviteRegionPreference fromAvailabilityMap(Map<String, dynamic>? m) {
    if (m == null) return const InviteRegionPreference();
    final raw = m['inviteRegions'];
    final regions = raw is List
        ? raw.map(UserRegion.tryFromMap).whereType<UserRegion>().toList()
        : <UserRegion>[];
    final e = m['inviteEnabled'];
    return InviteRegionPreference(
      enabled: e is bool ? e : null,
      regions: regions,
    );
  }

  InvitePreferenceState get state {
    if (loadFailed) return InvitePreferenceState.unknown;
    final e = enabled;
    if (e == null) return InvitePreferenceState.unset;
    if (!e) return InvitePreferenceState.off;
    // [§8] ON인데 지역 0개는 모순이다. 서버가 저장을 막지만, 과거 데이터나
    //   부분 실패로 그런 문서를 만나면 ON이라고 말하지 않는다.
    return regions.isEmpty
        ? InvitePreferenceState.unknown
        : InvitePreferenceState.on;
  }

  /// 지금 이 근무지역의 초대를 받을 수 있는가.
  /// 판단할 수 없으면 false — 모르는 것을 허용으로 읽지 않는다.
  bool allows(String? workRegionKey) {
    if (workRegionKey == null) return false;
    if (state != InvitePreferenceState.on) return false;
    return regions.any((r) => regionKeyOfRegion(r) == workRegionKey);
  }

  List<String> get regionKeys =>
      regions.map(regionKeyOfRegion).whereType<String>().toList();

  InviteRegionPreference copyWith({
    bool? enabled,
    List<UserRegion>? regions,
  }) =>
      InviteRegionPreference(
        enabled: enabled ?? this.enabled,
        regions: regions ?? this.regions,
      );

  /// [R2.3 FINAL §7/§8] 선택 상한 — **technical hard ceiling**이다.
  ///
  ///   20곳을 고르라는 권장이 아니다. 인덱스 비용(20 × 60일 = 1,200 entries)에서
  ///   나온 안전 한계이고, 서버가 같은 값으로 최종 방어한다.
  ///   전국/전체 선택 같은 일괄 기능은 만들지 않는다.
  static const int maxRegions = 20;

  /// 저장 전 검증 — 서버와 같은 규칙.
  /// 통과하지 못하는 이유를 돌려준다(null이면 유효).
  String? validationError() {
    if (enabled == true && regions.isEmpty) {
      return '초대 받을 지역을 한 곳 이상 선택해 주세요.';
    }
    if (regions.length > maxRegions) {
      return '초대 받을 지역은 최대 $maxRegions곳까지 선택할 수 있어요.';
    }
    for (final r in regions) {
      final p = r.province;
      if (p == null || p.isEmpty) {
        if (KoreanRegions.provinceOfCity(r.city) == null) {
          return '${r.city}는 시/도를 함께 선택해 주세요.';
        }
        continue;
      }
      if (!KoreanRegions.isValidPair(p, r.city)) {
        return '알 수 없는 지역입니다: $p ${r.city}';
      }
    }
    return null;
  }
}
