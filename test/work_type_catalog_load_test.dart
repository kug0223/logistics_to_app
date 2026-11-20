// [WORKTYPE-LOCAL-CLOSURE 2026-10-17] 업무유형 목록을 끝까지 읽지 못하면 이름으로 연결하지 않는다
//
// 레거시 공고(근무에 workTypeId 없음)는 "그 이름 문서가 사업장 전체에 하나"일 때만 안내를 붙인다.
// 그 판정은 **전체**를 읽었을 때만 성립한다 — 같은 이름이 다음 페이지에 있거나, 상한에서 끊기거나,
// 한 페이지가 실패하면 유일성을 모른다.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/services/work_type_guide_resolver.dart';

Map<String, dynamic> _doc(String name, {DateTime? created}) => {
      'businessId': 'biz1',
      'name': name,
      'icon': 'box',
      'displayOrder': 0,
      'isActive': true,
      'createdAt': Timestamp.fromDate(created ?? DateTime(2025)),
    };

/// id 오름차순 문서들을 [pageSize] 단위로 잘라 주는 가짜 페이지 함수.
Future<List<(String, Map<String, dynamic>)>> Function(String?, int) _pages(
    List<(String, Map<String, dynamic>)> all, {int? failAtPage}) {
  var page = 0;
  return (after, size) async {
    if (failAtPage != null && page == failAtPage) throw Exception('page $page failed');
    page++;
    final start = after == null ? 0 : all.indexWhere((e) => e.$1 == after) + 1;
    return all.skip(start).take(size).toList();
  };
}

Object? _resolve(WorkTypeCatalog c) => WorkTypeGuideResolver.resolve(
    workTypeId: null, workTypeName: '상하차', catalog: c, businessId: 'biz1', postedAt: DateTime(2026, 9, 1));

void main() {
  test('WCL-01 한 페이지에 다 있음 · 유일 — 연결', () async {
    final c = await WorkTypeCatalog.load(
        businessId: 'biz1', pageSize: 3, fetchPage: _pages([('a', _doc('상하차')), ('b', _doc('피킹'))]));
    expect(c.complete, isTrue);
    expect(_resolve(c), isNotNull);
  });

  test('WCL-02 같은 이름이 **다음 페이지**에 있음 — 끝까지 읽어 2개로 세고 연결하지 않는다', () async {
    final all = [('a', _doc('상하차')), ('b', _doc('피킹')), ('c', _doc('분류')), ('d', _doc('상하차'))];
    final c = await WorkTypeCatalog.load(businessId: 'biz1', pageSize: 2, fetchPage: _pages(all));
    expect(c.complete, isTrue);
    expect(c.nameCounts['상하차'], 2);
    expect(_resolve(c), isNull);
  });

  test('WCL-03 상한에 닿음 — 불완전 목록, 연결하지 않는다', () async {
    final all = [for (var i = 0; i < 12; i++) ('w$i', _doc(i == 0 ? '상하차' : 'N$i'))];
    final c = await WorkTypeCatalog.load(businessId: 'biz1', pageSize: 5, maxDocs: 10, fetchPage: _pages(all));
    expect(c.complete, isFalse);
    expect(_resolve(c), isNull, reason: '상한 밖에 같은 이름이 있을 수 있다');
  });

  test('WCL-04 둘째 페이지 실패 — 일부만 읽은 목록을 돌려주지 않고 던진다', () async {
    final all = [('a', _doc('상하차')), ('b', _doc('피킹')), ('c', _doc('분류'))];
    expect(
        () => WorkTypeCatalog.load(businessId: 'biz1', pageSize: 2, fetchPage: _pages(all, failAtPage: 1)),
        throwsException);
  });

  test('WCL-05 공고 뒤에 만든 같은 이름 문서 — 연결하지 않는다', () async {
    final c = await WorkTypeCatalog.load(
        businessId: 'biz1', pageSize: 5, fetchPage: _pages([('a', _doc('상하차', created: DateTime(2026, 10, 1)))]));
    expect(_resolve(c), isNull);
  });

  test('WCL-06 정확히 pageSize 개 — 다음 빈 페이지까지 읽고 완전', () async {
    final all = [('a', _doc('상하차')), ('b', _doc('피킹'))];
    final c = await WorkTypeCatalog.load(businessId: 'biz1', pageSize: 2, fetchPage: _pages(all));
    expect(c.complete, isTrue);
    expect(_resolve(c), isNotNull);
  });
}
