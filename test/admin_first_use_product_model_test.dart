// [R7-ONBOARDING.1] 관리자 첫 사용이 제품 흐름을 말하는가.
//
// 예전 첫 화면은 기능 5페이지 광고였다 — 공고·계약서·출퇴근·급여·리뷰.
// 처음 들어온 사람이 아직 쓸 수도 없는 기능을 먼저 봤고, 정작 **이 제품이
// 무엇이고 지금 무엇을 해야 하는지**는 한 줄도 없었다. 같은 자산이 투어로
// 한 번 더 있었고(제목이 글자까지 같았다), 가이드 재진입은 역할마다 다른
// 화면을 열면서 다른 역할의 투어 기록까지 지웠다.
//
// 여기서 고정하는 것
//   O  온보딩 내용 — 제품 모델 · 약속 모델 · 첫 준비 이유
//   D  중복 제거 — 자동 투어 없음, 준비 상태를 온보딩이 세지 않음
//   G  가이드 재진입 — 같은 surface, 플래그 오염 없음
//   S  하위관리자 — 막다른 길 없음, 소유자 전용 작업 요구 없음
//   R  반응형 — 320/360/411 × 배율 1.0/1.3/2.0 넘침 0
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/screens/common/onboarding_screen.dart';
import 'package:ALfit/screens/common/tour_screen.dart';

String _code(String p) => File(p)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _raw(String p) => File(p).readAsStringSync();

const _onboarding = 'lib/screens/common/onboarding_screen.dart';
const _adminHome = 'lib/screens/business_admin/business_admin_home_screen.dart';
const _jobsRoot = 'lib/screens/business_admin/jobs_root_screen.dart';
const _sharedSettings = 'lib/screens/common/settings_screen.dart';
const _userSettings = 'lib/screens/user/user_settings_screen.dart';

/// 관리자 페이지 정의 블록만 떼어 낸다.
String _adminPagesBlock() {
  final s = _raw(_onboarding);
  final a = s.indexOf('static const _adminPages = [');
  final b = s.indexOf('];', a);
  expect(a, greaterThan(-1));
  return s.substring(a, b);
}

Future<void> _pumpOnboarding(
  WidgetTester t, {
  required Size size,
  required double scale,
  String role = 'BUSINESS_ADMIN',
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    builder: (ctx, child) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: OnboardingScreen(role: role, onComplete: () {}),
  ));
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  // ── O. 온보딩 내용 ─────────────────────────────────────────────────

  test('O1 기능 광고 5페이지가 아니라 3페이지 이하다', () {
    final block = _adminPagesBlock();
    final count = '_OnboardingPage('.allMatches(block).length;
    expect(count, lessThanOrEqualTo(3),
        reason: '첫 화면이 기능 목록으로 돌아갔다 ($count 페이지)');
    expect(count, greaterThanOrEqualTo(2));
  });

  test('O2 제품 모델을 말한다 — 날과 사람을 맞춘다', () {
    final block = _adminPagesBlock();
    expect(block.contains('필요한 사람을 맞춥니다'), isTrue);
    expect(block.contains('일하고 싶은 날'), isTrue);
    // 확정된 근무가 어디로 이어지는지도 말한다.
    for (final k in ['계약', '일정', '근태', '급여']) {
      expect(block.contains(k), isTrue, reason: k);
    }
  });

  test('O3 약속 모델을 말한다 — 지원은 관심, 확정은 약속', () {
    final block = _adminPagesBlock();
    expect(block.contains('지원은 관심'), isTrue);
    expect(block.contains('확정은 약속'), isTrue);
    expect(block.contains('계약서가 만들어집니다'), isTrue,
        reason: '확정이 왜 다른지 설명이 없다');
  });

  test('O4 첫 공고 전 준비가 왜 필요한지 말한다', () {
    final block = _adminPagesBlock();
    expect(block.contains('첫 공고 전에'), isTrue);
    for (final k in ['사업장', '업무', '계약서 양식', '사업주 인감']) {
      expect(block.contains(k), isTrue, reason: k);
    }
  });

  test('O5 아직 쓸 수 없는 기능을 먼저 광고하지 않는다', () {
    final block = _adminPagesBlock();
    for (final banned in [
      '송금 관리', '엑셀로 일괄 이체', '은행 이체용 엑셀',
      '당일명단 PDF', '월간 리뷰로 인재 평가', '공고 등록 3단계',
    ]) {
      expect(block.contains(banned), isFalse, reason: '"$banned" 가 남아 있다');
    }
  });

  // ── D. 중복·역할 분리 ──────────────────────────────────────────────

  test('D1 관리자 홈이 자동으로 기능 투어를 열지 않는다', () {
    final c = _code(_adminHome);
    expect(c.contains('pushTourScreen'), isFalse);
    expect(c.contains('tourCompleted'), isFalse);
    expect(c.contains('TourHelper'), isFalse);
  });

  test('D2 온보딩이 준비 상태를 따로 계산하지 않는다', () {
    final c = _code(_onboarding);
    // 준비 판정은 홈의 canonical readiness 가 한다.
    for (final banned in [
      'FirstPostingReadiness', 'BusinessPostingReadiness',
      'contractTemplate', 'hasEmployerSeal', 'isApproved',
    ]) {
      expect(c.contains(banned), isFalse,
          reason: '온보딩이 "$banned" 로 준비를 세고 있다');
    }
  });

  test('D3 온보딩 완료는 "봤다" 이지 "준비됐다" 가 아니다', () {
    final m = _code('lib/main.dart');
    expect(m.contains('onboarding_completed_'), isTrue);
    // 준비 상태를 온보딩 완료로 바꿔치기하지 않는다.
    expect(m.contains('FirstPostingReadiness'), isFalse);
  });

  // ── G. 가이드 재진입 ───────────────────────────────────────────────

  test('G1 두 설정 경로가 같은 help surface 를 연다', () {
    for (final p in [_sharedSettings, _userSettings]) {
      final c = _code(p);
      expect(c.contains('pushTourScreen(context, role: role)'), isTrue,
          reason: '$p 가 다른 화면을 연다');
    }
    // 제품 소개는 다시 보기의 대상이 아니다.
    expect(_code(_userSettings).contains('OnboardingScreen('), isFalse);
  });

  test('G2 재진입이 다른 역할의 투어 기록을 지우지 않는다', () {
    for (final p in [_sharedSettings, _userSettings]) {
      expect(_code(p).contains('TourHelper.resetAll'), isFalse,
          reason: '$p 가 모든 역할의 기록을 지운다');
    }
    // resetAll 자체를 부르는 곳이 lib 에 없어야 한다.
    final hits = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (_code(f.path).contains('TourHelper.resetAll')) hits.add(f.path);
    }
    expect(hits, isEmpty, reason: '기록을 지우는 경로가 남아 있다: $hits');
  });

  test('G3 재진입이 온보딩 완료 플래그를 되돌리지 않는다', () {
    for (final p in [_sharedSettings, _userSettings]) {
      final c = _code(p);
      expect(c.contains('onboarding_completed_'), isFalse,
          reason: '$p 가 온보딩 플래그를 건드린다');
    }
  });

  // ── S. 하위관리자 ──────────────────────────────────────────────────

  test('S1 하위관리자를 준비 체크리스트가 없는 홈으로 보내지 않는다', () {
    final c = _code(_jobsRoot);
    expect(c.contains('if (!isSubAdmin) ...['), isTrue,
        reason: '막다른 길 분기가 없다');
    expect(c.contains('사업장 관리자에게 확인해 주세요'), isTrue);
    // 홈은 여전히 하위관리자에게 소유자 설정 카드를 숨긴다(기존 정책).
    expect(_code(_adminHome).contains('isSubAdmin == true'), isTrue);
  });

  test('S2 하위관리자에게 남은 개수를 압박으로 말하지 않는다', () {
    final s = _raw(_jobsRoot);
    final i = s.indexOf('isSubAdmin');
    expect(i, greaterThan(-1));
    // 개수 문장은 관리자 분기에만 있다.
    final sub = s.substring(s.indexOf('가지 준비가 남아 있습니다') - 400,
        s.indexOf('가지 준비가 남아 있습니다'));
    expect(sub.contains('isSubAdmin'), isTrue,
        reason: '개수 문장이 역할 분기 밖에 있다');
  });

  // ── R. 반응형 ──────────────────────────────────────────────────────

  testWidgets('R1 좁은 폭 × 큰 배율에서 넘치지 않는다', (t) async {
    for (final w in [320.0, 360.0, 411.0]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        await _pumpOnboarding(t, size: Size(w, 740), scale: scale);
        expect(t.takeException(), isNull,
            reason: '관리자 온보딩 ${w.toInt()}dp × $scale');
      }
    }
  });

  testWidgets('R2 지원자 온보딩도 같은 폭·배율에서 넘치지 않는다', (t) async {
    for (final w in [320.0, 411.0]) {
      for (final scale in [1.0, 2.0]) {
        await _pumpOnboarding(t, size: Size(w, 740), scale: scale, role: 'USER');
        expect(t.takeException(), isNull,
            reason: '지원자 온보딩 ${w.toInt()}dp × $scale');
      }
    }
  });

  testWidgets('R3 큰 배율에서도 CTA 가 화면 안에 있고 본문은 스크롤된다', (t) async {
    await _pumpOnboarding(t, size: const Size(320, 740), scale: 2.0);
    final cta = find.textContaining('다음');
    expect(cta, findsWidgets);
    final r = t.getRect(cta.first);
    expect(r.bottom, lessThanOrEqualTo(740.0),
        reason: 'CTA 가 화면 밖으로 밀렸다');
    // 본문이 스크롤 가능해야 글을 줄이지 않고 담을 수 있다.
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(t.takeException(), isNull);
  });

  // [GUIDE-TOUR-ROW-OVERFLOW-AT-NARROW-WIDTH-TEXTSCALE] 미해결로 남아 있던
  //   항목. 이번에 help surface 를 손댔으므로 함께 닫는다.
  testWidgets('R5 가이드(투어) 화면도 좁은 폭 × 큰 배율에서 넘치지 않는다', (t) async {
    for (final role in ['BUSINESS_ADMIN', 'USER']) {
      for (final w in [320.0, 360.0, 411.0]) {
        for (final scale in [1.0, 1.3, 2.0]) {
          t.view.physicalSize = Size(w, 740);
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.reset);
          // 반복마다 트리를 갈아끼운다 — key 가 같으면 앞 반복에서 push 된
          // 투어 route 가 그대로 남아 버튼을 가린다.
          await t.pumpWidget(MaterialApp(
            key: ValueKey('$role-$w-$scale'),
            builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(ctx)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => pushTourScreen(ctx, role: role),
                child: const Text('열기'),
              ),
            ),
          ));
          await t.pump();
          await t.tap(find.text('열기'));
          for (var i = 0; i < 10; i++) {
            await t.pump(const Duration(milliseconds: 80));
          }
          expect(t.takeException(), isNull,
              reason: '가이드 $role ${w.toInt()}dp × $scale');
        }
      }
    }
  });

  testWidgets('R4 첫 화면에 제품 메시지가 실제로 보인다', (t) async {
    await _pumpOnboarding(t, size: const Size(360, 740), scale: 1.0);
    expect(find.textContaining('필요한 사람을 맞춥니다'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
