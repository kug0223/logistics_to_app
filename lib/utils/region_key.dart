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

/// canonical region key. 지역을 특정할 수 없으면 null (UNKNOWN).
String? regionKeyOf({String? province, String? city}) {
  final c = (city ?? '').trim();
  if (c.isEmpty) return null;

  var p = (province ?? '').trim();
  if (p.isNotEmpty) {
    p = KoreanRegions.canonicalProvince(p);
  } else {
    // province가 없으면 유추 — 단, 유일할 때만.
    final inferred = KoreanRegions.provinceOfCity(c);
    if (inferred == null) return null; // 동명 지역 — 특정 불가
    p = inferred;
  }
  if (p.isEmpty) return null;
  return '$p$kRegionKeySeparator$c';
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
