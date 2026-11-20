import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/core/insurance_rate_model.dart';

/// [.59] 저장 직전 서버값이 화면을 연 뒤 바뀌었다.
class InsuranceRatesChangedException implements Exception {
  const InsuranceRatesChangedException(this.year);
  final int year;
  @override
  String toString() => '$year년 보험료율이 다른 곳에서 바뀌었습니다';
}

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
  ///
  /// [.60] 결과를 돌려준다 — true = 서버 값을 확인함(저장값 없음 포함), false = 읽지 못함(캐시·내장값 그대로).
  ///   급여관리 창이 '확인 중/확인 실패' 를 구분해, 확인 전 금액을 확정 금액처럼 보이지 않는다.
  static Future<bool> loadRates() async {
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
          return true;
        }
      }
      debugPrint('⚠️ 보험료율 Firestore 데이터 없음, 로컬 백업 사용');
      return true;
    } catch (e) {
      debugPrint('⚠️ 보험료율 로드 실패, 로컬 백업 사용: $e');
      return false;
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
  ///
  /// [.59] [expected] = 화면을 열 때 읽은 그 연도의 저장값(없었으면 null). 저장 직전 서버값과 다르면
  ///   [InsuranceRatesChangedException] — 다른 SA 화면이 그 사이 바꾼 값을 조용히 덮지 않는다.
  ///   같은 문서의 다른 필드(최저시급·다른 연도)는 merge 로 그대로 둔다.
  static Future<void> saveRates(InsuranceRateModel rates, {required InsuranceRateModel? expected}) async {
    final ref = FirebaseFirestore.instance.collection(_collection).doc(_doc);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final raw = snap.data()?[_field];
      final cur = raw is Map && raw['${rates.year}'] is Map
          ? InsuranceRateModel.fromMap(Map<String, dynamic>.from(raw['${rates.year}'] as Map))
          : null;
      if (!mapEquals(cur?.toMap(), expected?.toMap())) {
        throw InsuranceRatesChangedException(rates.year);
      }
      tx.set(ref, {
        _field: {
          '${rates.year}': rates.toMap(),
        },
      }, SetOptions(merge: true));
    });

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

  /// [.59] 슈퍼관리자 설정 화면용 — **서버에 저장된 연도만** 돌려준다. 읽기 실패는 던진다.
  ///   [fetchAll] 은 실패하면 내장값을 돌려줘서, 화면이 내장값을 저장값처럼 보이고 그대로 저장할 수 있었다.
  static Future<Map<int, InsuranceRateModel>> fetchStored() async {
    final doc = await FirebaseFirestore.instance.collection(_collection).doc(_doc).get();
    final result = <int, InsuranceRateModel>{};
    final raw = doc.data()?[_field];
    if (raw is Map) {
      raw.forEach((key, value) {
        final year = int.tryParse(key.toString());
        if (year != null && value is Map) {
          result[year] = InsuranceRateModel.fromMap(Map<String, dynamic>.from(value));
        }
      });
    }
    return result;
  }

  /// 앱 내장 기본값(연도별). 설정 화면이 '저장값 없음' 을 알리며 보여 준다.
  static Map<int, InsuranceRateModel> get builtinDefaults => Map.unmodifiable(_localDefaults);

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
