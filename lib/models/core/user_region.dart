// ── 지역 정보 모델 ─────────────────────────────────────────────────
// V1: province / city / district 텍스트 매칭 기반 추천
// V2: lat / lng 추가 예정 (Geocoding → 거리/이동시간 기반 추천)
// ─────────────────────────────────────────────────────────────────

/// 한국 행정구역 3레벨 표현
///   province : 경기도, 서울특별시, 부산광역시 …
///   city     : 오산시, 강남구, 수원시 … (시/군/구)
///   district : 가수동, 역삼동 … (동/읍/면)
class UserRegion {
  final String? province;
  final String city;
  final String? district;

  const UserRegion({
    this.province,
    required this.city,
    this.district,
  });

  // ── 역직렬화 ─────────────────────────────────────────────────────
  static UserRegion? tryFromMap(Object? raw) {
    if (raw is! Map) return null;
    final city = raw['city'] as String?;
    if (city == null || city.isEmpty) return null;
    return UserRegion(
      province: raw['province'] as String?,
      city: city,
      district: raw['district'] as String?,
    );
  }

  // ── 직렬화 ───────────────────────────────────────────────────────
  Map<String, dynamic> toMap() => {
    if (province != null) 'province': province,
    'city': city,
    if (district != null) 'district': district,
  };

  // ── 비교 헬퍼 ────────────────────────────────────────────────────
  /// 같은 시/군/구
  bool isSameCity(UserRegion other) => city == other.city;

  /// 같은 동/읍/면 (city 포함)
  bool isSameDistrict(UserRegion other) =>
      city == other.city &&
      district != null &&
      district == other.district;

  /// 주소 문자열로 요약 표시 (null 파트 제외)
  @override
  String toString() =>
      [province, city, district].whereType<String>().join(' ');

  @override
  bool operator ==(Object other) =>
      other is UserRegion &&
      province == other.province &&
      city == other.city &&
      district == other.district;

  @override
  int get hashCode => Object.hash(province, city, district);
}

// ── 한국 주소 문자열 파서 ──────────────────────────────────────────
// 지원 형식 (→ province / city / district):
//   "경기도 오산시 가수동 123-4"  → 경기도 / 오산시 / 가수동
//   "서울특별시 강남구 역삼동"    → 서울특별시 / 강남구 / 역삼동
//   "경기도 수원시 장안구 정자동" → 경기도 / 수원시 / 장안구 (district = 구)
//   "경기 오산시 가수동"          → null / 오산시 / 가수동 (province fallback)
//
// 파싱 실패 → null 반환 (추천 fallback 동작)

UserRegion? parseKoreanAddress(String address) {
  if (address.trim().isEmpty) return null;
  final parts = address.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return null;

  String? province, city, district;

  for (final part in parts) {
    if (province == null && _isProvince(part)) {
      province = part;
    } else if (city == null && _isCity(part)) {
      city = part;
    } else if (city != null && district == null && _isDistrict(part)) {
      district = part;
      break; // province / city / district 확보 완료
    }
  }

  // city 파싱 실패 시 두 번째 토큰으로 폴백
  if (city == null && parts.length >= 2) {
    city = parts[1];
  }

  if (city == null) return null;
  return UserRegion(province: province, city: city, district: district);
}

bool _isProvince(String s) =>
    s.endsWith('도') ||
    s.endsWith('특별시') ||
    s.endsWith('광역시') ||
    s.endsWith('자치시') ||
    s.endsWith('특별자치도') ||
    s.endsWith('자치도');

bool _isCity(String s) =>
    s.endsWith('시') || s.endsWith('군') || s.endsWith('구');

bool _isDistrict(String s) =>
    s.endsWith('동') ||
    s.endsWith('읍') ||
    s.endsWith('면') ||
    s.endsWith('리');
