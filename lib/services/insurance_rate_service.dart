import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/core/insurance_rate_model.dart';

/// 보험료율 서비스
///
/// WageCalculator.loadMinimumWages()와 동일한 패턴.
/// - 앱 시작 시 1회 loadRates() 호출
/// - Firestore: settings/wage_config.insuranceRates (연도별 Map)
/// - 로컬 백업으로 네트워크 오류 대비
class InsuranceRateService {
  static const _collection = 'settings';
  static const _doc = 'wage_config';
  static const _field = 'insuranceRates';

  /// 로컬 백업
  static final Map<int, InsuranceRateModel> _localDefaults = {
    2026: InsuranceRateModel.defaults2026(),
  };

  /// Firestore 캐시
  static Map<int, InsuranceRateModel>? _cached;

  /// 앱 시작 시 1회 호출 — Firestore에서 보험료율 로드
  static Future<void> loadRates() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc(_doc)
          .get();

      if (doc.exists) {
        final raw = doc.data()?[_field];
        if (raw is Map) {
          _cached = {};
          raw.forEach((key, value) {
            final year = int.tryParse(key.toString());
            if (year != null && value is Map) {
              _cached![year] = InsuranceRateModel.fromMap(
                Map<String, dynamic>.from(value),
              );
            }
          });
          debugPrint('✅ 보험료율 로드 완료: ${_cached!.keys}');
          return;
        }
      }
      debugPrint('⚠️ 보험료율 Firestore 데이터 없음, 로컬 백업 사용');
    } catch (e) {
      debugPrint('⚠️ 보험료율 로드 실패, 로컬 백업 사용: $e');
    }
  }

  /// 특정 연도의 보험료율 반환 (없으면 가장 최근 연도 백업)
  ///
  /// 우선순위:
  ///   1. Firestore 캐시 (슈퍼관리자가 연도별로 등록한 값)
  ///   2. 로컬 백업 (현재 2026년만 내장)
  ///   3. 가장 최근 로컬 백업 (3순위 폴백)
  ///
  /// ⚠️ B04 설계 방침: 과거 연도(예: 2024)가 Firestore에 없으면 2026년 요율을 반환한다.
  /// 이는 과거 데이터 소급 처리 시 연도 불일치를 유발할 수 있다.
  /// 정확한 과거 요율이 필요한 사업장은 슈퍼관리자 화면에서 해당 연도 데이터를 등록해야 한다.
  /// 미래 연도(예: 2027)도 동일하게 최근 연도로 폴백 — 신년 요율 확정 전 임시 적용.
  static InsuranceRateModel getRates(int year) {
    // 1순위: Firestore 캐시
    if (_cached != null && _cached!.containsKey(year)) {
      return _cached![year]!;
    }
    // 2순위: 로컬 백업
    if (_localDefaults.containsKey(year)) {
      return _localDefaults[year]!;
    }
    // 3순위: 가장 최근 로컬 백업
    final latestYear = _localDefaults.keys.reduce((a, b) => a > b ? a : b);
    return _localDefaults[latestYear]!;
  }

  /// 현재 연도 보험료율
  static InsuranceRateModel get current => getRates(DateTime.now().year);

  /// 슈퍼관리자: 연도별 보험료율 저장
  static Future<void> saveRates(InsuranceRateModel rates) async {
    final ref = FirebaseFirestore.instance.collection(_collection).doc(_doc);
    await ref.set({
      _field: {
        '${rates.year}': rates.toMap(),
      },
    }, SetOptions(merge: true));

    // 캐시 갱신
    _cached ??= {};
    _cached![rates.year] = rates;
    debugPrint('✅ ${rates.year}년 보험료율 저장 완료');
  }

  /// 슈퍼관리자: 저장된 모든 연도 목록 (캐시 기준)
  static List<int> get cachedYears {
    final years = <int>{
      ..._localDefaults.keys,
      ...?_cached?.keys,
    }.toList()
      ..sort((a, b) => b.compareTo(a));
    return years;
  }

  /// 슈퍼관리자: Firestore에서 전체 연도 데이터 조회 (설정 화면용)
  static Future<Map<int, InsuranceRateModel>> fetchAll() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc(_doc)
          .get();

      final result = Map<int, InsuranceRateModel>.from(_localDefaults);

      if (doc.exists) {
        final raw = doc.data()?[_field];
        if (raw is Map) {
          raw.forEach((key, value) {
            final year = int.tryParse(key.toString());
            if (year != null && value is Map) {
              result[year] = InsuranceRateModel.fromMap(
                Map<String, dynamic>.from(value),
              );
            }
          });
        }
      }
      return result;
    } catch (e) {
      debugPrint('⚠️ 보험료율 전체 조회 실패: $e');
      return Map<int, InsuranceRateModel>.from(_localDefaults);
    }
  }
}
