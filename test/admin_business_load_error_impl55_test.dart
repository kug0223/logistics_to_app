import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [impl_55 · AUD-4 H4] 사업장 조회 실패를 '사업장 없음'(급여 관리 시작 전 · 승인 필요 · 등록된 사업장이 없습니다)으로 말하지 않는다.
///   세 경로가 OrThrow 변형을 쓰고, 실패는 각 화면의 실패 안내로 간다(원문 핀 — 서비스 OrThrow 의 던짐은 기존 시험 몫).
String _code(String p) => File(p)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  test('B1 급여 개요 읽기 — OrThrow · 화면 catch 가 _loadError', () {
    final r = _code('lib/screens/business_admin/payroll/payroll_overview_reads.dart');
    final b = r.substring(r.indexOf('businesses: ({'), r.indexOf('payrollSummaries:'));
    expect(b.contains('svc.getBusinessByIdOrThrow(effectiveBusinessId)'), isTrue);
    expect(b.contains('svc.getBusinessesByIdsOrThrow(managedIds)'), isTrue);
    expect(RegExp(r'svc\.getBusinessById\(|svc\.getBusinessesByIds\(').hasMatch(b), isFalse);
    final s = _code('lib/screens/business_admin/payroll/payroll_overview_screen.dart');
    expect(s.contains('_loadError = e.toString();'), isTrue);
  });

  test('B2 공고 등록 — OrThrow 2곳 · 실패 = 실패 화면 + 다시 시도(사전조건 화면 아님)', () {
    final c = _code('lib/screens/business_admin/to_management/create_to_screen.dart');
    final load = c.substring(c.indexOf('Future<void> _loadMyBusinesses('), c.indexOf('Future<void> _onRecheckPressed('));
    expect('getBusinessesByIdsOrThrow('.allMatches(load).length, 2);
    expect(RegExp(r'getBusinessesByIds\(').hasMatch(load), isFalse);
    expect(load.contains('_isLoading = false; _businessLoadFailed = true;'), isTrue);
    final pre = c.substring(c.indexOf('Widget _buildPrerequisiteScreen() {'));
    final head = pre.substring(0, pre.indexOf('final theme = Theme.of(context);'));
    expect(head.contains('if (_businessLoadFailed) {'), isTrue);
    expect(head.contains("title: '사업장 정보를 불러오지 못했어요',"), isTrue);
    expect(head.contains('_loadMyBusinesses();'), isTrue);
  });

  test('B3 알림 → 날짜별 지원자 — OrThrow 2곳 · 실패는 catch(불러오는데 실패)', () {
    final n = _code('lib/screens/common/notification_screen.dart');
    expect(n.contains('fsService.getBusinessByIdOrThrow(up.effectiveBusinessId!)'), isTrue);
    expect(n.contains('fsService.getMyBusinessOrThrow(uid)'), isTrue);
    expect(n.contains('fsService.getBusinessById(up.effectiveBusinessId!)'), isFalse);
  });
}
