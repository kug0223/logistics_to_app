import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [impl_57 · AUD-4 H4 같은 꼴] 다른 사업장 템플릿 시트 — 내 사업장 목록 조회 실패를 '다른 사업장 없음'으로 말하지 않는다.
void main() {
  test('T1 OrThrow · 실패 상태 · 다시 시도', () {
    final s = File('lib/screens/business_admin/contract_template_list_screen.dart').readAsStringSync().replaceAll('\r\n', '\n');
    final b = s.substring(s.indexOf('class _OtherBusinessTemplateSheetState'));
    expect(b.contains('await firestoreService.getMyBusinessOrThrow(uid);'), isTrue);
    expect(b.contains('firestoreService.getMyBusiness(uid)'), isFalse);
    expect(b.contains('_loading = false; _loadFailed = true;'), isTrue);
    expect(b.contains("title: '사업장 목록을 불러오지 못했어요',"), isTrue);
    expect(b.contains('_loadOtherBusinessTemplates();'), isTrue);
  });
}
