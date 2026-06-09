import 'package:flutter/material.dart';

class TOFilterState {
  final String? city;
  final String? district;
  final String? type;
  final DateTimeRange? dateRange;
  final String? keyword;
  final String sortBy;
  final bool showFavoritesOnly;

  const TOFilterState({
    this.city,
    this.district,
    this.type,
    this.dateRange,
    this.keyword,
    this.sortBy = 'createdAt',
    this.showFavoritesOnly = false,
  });

  bool get hasFilters =>
      city != null ||
      district != null ||
      type != null ||
      dateRange != null ||
      keyword != null ||
      showFavoritesOnly;

  int get activeCount =>
      [city, district, type, dateRange, keyword].where((v) => v != null).length +
      (showFavoritesOnly ? 1 : 0);

  TOFilterState copyWith({
    String? city,
    String? district,
    String? type,
    DateTimeRange? dateRange,
    String? keyword,
    String? sortBy,
    bool? showFavoritesOnly,
    bool clearCity = false,
    bool clearDistrict = false,
    bool clearType = false,
    bool clearDateRange = false,
    bool clearKeyword = false,
  }) =>
      TOFilterState(
        city: clearCity ? null : city ?? this.city,
        district: clearDistrict ? null : district ?? this.district,
        type: clearType ? null : type ?? this.type,
        dateRange: clearDateRange ? null : dateRange ?? this.dateRange,
        keyword: clearKeyword ? null : keyword ?? this.keyword,
        sortBy: sortBy ?? this.sortBy,
        showFavoritesOnly: showFavoritesOnly ?? this.showFavoritesOnly,
      );

  TOFilterState clearRegion() => copyWith(clearCity: true, clearDistrict: true);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TOFilterState &&
          city == other.city &&
          district == other.district &&
          type == other.type &&
          dateRange == other.dateRange &&
          keyword == other.keyword &&
          sortBy == other.sortBy &&
          showFavoritesOnly == other.showFavoritesOnly;

  @override
  int get hashCode =>
      Object.hash(city, district, type, dateRange, keyword, sortBy, showFavoritesOnly);
}
