import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/core/to_filter_state.dart';

/// Algolia 키워드 검색 서비스 (REST API 직접 호출)
///
/// 사용 전 필수 설정:
///   flutter run --dart-define=ALGOLIA_APP_ID=xxx --dart-define=ALGOLIA_SEARCH_KEY=yyy
///
/// Firebase Extension "Search with Algolia" 설치 후 tos 컬렉션 인덱싱 설정 필요.
class AlgoliaService {
  // dart-define으로 빌드 타임에 주입
  static const String _appId = String.fromEnvironment('ALGOLIA_APP_ID', defaultValue: '');
  static const String _searchKey = String.fromEnvironment('ALGOLIA_SEARCH_KEY', defaultValue: '');
  static const String _indexName = 'tos';

  static bool get isConfigured => _appId.isNotEmpty && _searchKey.isNotEmpty;

  /// 키워드로 TO ID 목록 반환
  ///
  /// [filter] 있으면 지역/유형 필터도 Algolia 쿼리에 포함.
  static Future<List<String>> searchTOIds(
    String keyword, {
    TOFilterState? filter,
    int hitsPerPage = 50,
  }) async {
    if (!isConfigured) {
      debugPrint('⚠️ Algolia 키 미설정 (ALGOLIA_APP_ID / ALGOLIA_SEARCH_KEY)');
      return [];
    }
    if (keyword.trim().isEmpty) return [];

    // Algolia facet 필터 구성
    final facets = <String>[];
    if (filter?.city != null) {
      facets.add('businessCity:${filter!.city}');
      if (filter.district != null) {
        facets.add('businessDistrict:${filter.district}');
      }
    }
    if (filter?.type != null) {
      facets.add('type:${filter!.type}');
    }
    // 발행된 활성 공고만
    facets.add('isPublished:true');

    final body = {
      'query': keyword.trim(),
      'hitsPerPage': hitsPerPage,
      if (facets.isNotEmpty) 'filters': facets.join(' AND '),
    };

    try {
      final response = await http.post(
        Uri.parse('https://$_appId-dsn.algolia.net/1/indexes/$_indexName/query'),
        headers: {
          'X-Algolia-Application-Id': _appId,
          'X-Algolia-API-Key': _searchKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        debugPrint('❌ Algolia 검색 실패 (${response.statusCode}): ${response.body}');
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final hits = data['hits'] as List<dynamic>? ?? [];
      return hits.map((h) => h['objectID'] as String).toList();
    } catch (e) {
      debugPrint('❌ Algolia 검색 오류: $e');
      return [];
    }
  }
}
