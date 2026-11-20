import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [BA-53] SA 사업장 승인 화면이 서버 후보(perf-20261028/c53/cand/P2)의 계약을 따르는가.
///   이 시험은 소스 검사다 — 동작 근거는 c53/ap53.json(DEV 원본 ↔ 후보: 검토 후 서류 교체, 반복 승인, 비활성 승인, 승인 대기 재활성)과 기기 기록.
String _src(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final s = _src('lib/screens/super_admin/all_businesses_screen.dart');
  final approve = s.substring(s.indexOf('Future<void> _approveBusiness('), s.indexOf('Future<void> _reactivateBusiness('));

  test('BA53-1 승인 요청에 화면이 본 값(등록증·사업자번호·사업장명)을 싣는다', () {
    expect(approve.contains("'expected': {"), isTrue);
    expect(approve.contains("'licenseUrl': item.business.businessLicenseImageUrl"), isTrue);
    expect(approve.contains("'businessNumber': item.business.businessNumber"), isTrue);
  });

  test('BA53-2 서류가 없을 때 재량 승인을 약속하지 않는다(서버는 등록증 없이 승인하지 않는다)', () {
    expect(approve.contains("confirmText: '그래도 승인'"), isFalse);
    expect(approve.contains('없으면 승인되지 않습니다'), isTrue);
  });

  test('BA53-3 이미 승인·검토 후 변경을 구별하고, 실패 뒤 목록을 다시 읽는다(예외 원문 접두 없음)', () {
    expect(approve.contains("res.data['alreadyApproved'] == true"), isTrue);
    expect(approve.contains("'처리 실패: \${e.message}'"), isFalse);
    expect(approve.contains('unawaited(_loadAllBusinesses());'), isTrue);
    expect(approve.contains('사업자번호 \${item.business.formattedBusinessNumber}'), isTrue, reason: '확인 창의 대상이 분명해야 한다(목록과 같은 표기)');
  });

  test('BA53-4 겹친 목록 읽기에서 늦게 온 이전 결과가 최신 목록을 덮지 않고, 실패를 원문·0건으로 바꾸지 않는다', () {
    expect(s.contains('if (!mounted || seq != _loadSeq) return;'), isTrue);
    expect(s.contains("'사업장 목록을 불러오는데 실패했습니다: \$e'"), isFalse);
  });
}
