import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/screens/common/job_posting_reads.dart';
import 'package:ALfit/services/work_type_guide_resolver.dart';

// [L33 · impl_7] 공고 상세 업무 안내(catalog) TTL 캐시 — 성공만 · TTL · in-flight 1 · 사업장별.
WorkTypeCatalog _cat(String biz) =>
    WorkTypeCatalog(businessId: biz, byId: const {}, nameCounts: const {}, complete: true);

void main() {
  test('CT-1 TTL 안 재진입은 다시 읽지 않고, TTL 이 지나면 다시 읽는다', () async {
    var now = DateTime(2026, 11, 26, 12);
    var loads = 0;
    final c = WorkTypeCatalogTtlCache(now: () => now);
    final get = c.wrap((b) async { loads++; return _cat(b); });
    await get('b1');
    now = now.add(const Duration(minutes: 4, seconds: 59));
    await get('b1');
    expect(loads, 1);
    now = now.add(const Duration(seconds: 2));
    await get('b1');
    expect(loads, 2);
    await get('b2');
    expect(loads, 3, reason: '사업장별로 따로');
  });

  test('CT-2 실패는 담지 않는다 — 다음 진입에서 다시 읽는다', () async {
    var loads = 0;
    final c = WorkTypeCatalogTtlCache();
    final get = c.wrap((b) async {
      loads++;
      if (loads == 1) throw StateError('offline');
      return _cat(b);
    });
    await expectLater(get('b1'), throwsStateError);
    expect((await get('b1')).businessId, 'b1');
    expect(loads, 2);
  });

  test('CT-3 동시에 열면 조회 1회를 함께 받는다', () async {
    var loads = 0;
    final gate = Completer<WorkTypeCatalog>();
    final c = WorkTypeCatalogTtlCache();
    final get = c.wrap((b) { loads++; return gate.future; });
    final a = get('b1');
    final b = get('b1');
    gate.complete(_cat('b1'));
    expect(identical(await a, await b), isTrue);
    expect(loads, 1);
  });

}
