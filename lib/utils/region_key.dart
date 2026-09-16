// [SYSTEM-INTEGRATION-R2.3] 지역 identity — canonical region key.
//
// 왜 문자열 city 비교를 그대로 확장하지 않는가:
//
//   현재 후보 조회는 `worker_availability.city == businesses.city`다.
//   korean_regions.dart 상단이 이미 경고하고 있는 문제가 그대로 열려 있다 —
//     중구 : 서울·부산·대구·인천·대전·울산 (6개)
//     동구 : 부산·대구·인천·전남광주·대전·울산 (6개)
//   즉 서울 중구 사람이 부산 중구 근무의 후보가 된다.
//
//   표기 drift도 eligibility를 깨면 안 된다:
//     수원 / 수원시 / 경기도 수원시
//
// canonical key:
//
//     "<canonical province>|<city>"      예: "경기도|수원시"
//
//   · province는 KoreanRegions.canonicalProvince로 축약형을 펴서 쓴다.
//   · province가 없으면 city로 유추하되 **유일할 때만** 쓴다. 중구처럼
//     여러 시/도에 있는 이름은 null — UNKNOWN이지 아무거나 고르는 것이 아니다.
//   · 이 key는 저장되고 쿼리에 쓰이므로 절대 포맷을 바꾸지 않는다.
//     (functions/src/index.ts의 srvRegionKeyOf가 같은 규칙을 구현한다.
//      region_key_contract_test가 두 구현이 같은 결과를 내는지 고정한다.)

import '../data/korean_regions.dart';
import '../models/core/user_region.dart';

/// key 구분자. city/province 이름에 등장할 수 없는 문자를 쓴다.
const String kRegionKeySeparator = '|';

/// [R2.3 CLOSURE §8] 저장된 시/군/구 표기를 canonical 단위로 맞춘다.
///
///   Daum 주소검색의 `sigungu`는 구가 있는 시에서 `"수원시 팔달구"`를 주고,
///   `parseAddressCity` 폴백은 `"수원시"`를 준다. 지원자 피커는 항상 `"수원시"`다.
///   정규화하지 않으면 `경기도|수원시 팔달구` 키가 만들어져 영원히 매칭되지 않는다.
///
///   문자열을 추측해 자르지 않는다 — canonical 표에 있는 값이 나올 때까지만
///   뒤 토큰을 떼고, 끝내 없으면 null(UNKNOWN)이다.
String? normalizeCityName(String province, String rawCity) {
  final c = rawCity.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (!KoreanRegions.citiesByProvince.containsKey(province)) return null;
  final cities = KoreanRegions.citiesOf(province);
  // [R2.3 FINAL §5] 시/군/구 단계가 없는 시/도는 시/도 자체가 선택 단위다.
  //   이름이 아니라 표에서 그 시/도의 시/군/구가 **자기 자신 하나뿐**이라는
  //   사실로 판단한다 — 세종특별자치시가 그렇게 저장돼 있다.
  if (cities.length == 1 && cities.first == province) return province;
  if (c.isEmpty) return null;
  if (cities.contains(c)) return c;
  final tokens = c.split(' ');
  for (var n = tokens.length - 1; n >= 1; n--) {
    final cand = tokens.sublist(0, n).join(' ');
    if (cities.contains(cand)) return cand;
  }
  return null;
}

/// canonical region key. 지역을 특정할 수 없으면 null (UNKNOWN).
String? regionKeyOf({String? province, String? city}) {
  final raw = (city ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
  if (raw.isEmpty) return null;

  final p = KoreanRegions.canonicalProvince((province ?? '').trim());
  if (p.isNotEmpty) {
    final c = normalizeCityName(p, raw);
    if (c == null) return null;
    return '$p$kRegionKeySeparator$c';
  }
  // province가 없으면 뒤 토큰을 떼며 유추 — 단, 유일할 때만.
  final tokens = raw.split(' ');
  for (var n = tokens.length; n >= 1; n--) {
    final cand = tokens.sublist(0, n).join(' ');
    final inferred = KoreanRegions.provinceOfCity(cand);
    if (inferred != null) return '$inferred$kRegionKeySeparator$cand';
  }
  return null;
}

/// UserRegion → canonical key.
String? regionKeyOfRegion(UserRegion? r) =>
    r == null ? null : regionKeyOf(province: r.province, city: r.city);

/// key → 사람이 읽는 표기. 파싱 실패 시 key 그대로.
String regionLabelOf(String key) {
  final i = key.indexOf(kRegionKeySeparator);
  if (i <= 0 || i == key.length - 1) return key;
  return key.substring(i + 1); // 목록에서는 시/군/구만 보여준다
}

/// key → 시/도 (없으면 null)
String? regionProvinceOf(String key) {
  final i = key.indexOf(kRegionKeySeparator);
  return i <= 0 ? null : key.substring(0, i);
}
