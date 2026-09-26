// [CORRECTION-R7-RECRUITING-GREEN] 모집 상태의 색 의미 계약.
//
//   `모집중`과 `모집 완료`가 같은 green family였다. 상위 의미가 같다는
//   이유였는데, 그 둘은 관리자가 **지금 할 일이 다른** 상태다. 목록을 훑을 때
//   "더 받아야 한다"와 "다 찼다"가 한 덩어리로 보였다.
//
//   Frozen D0:
//     RECRUITING → 정보색 파랑 (진행 중)
//     FULL       → green       (달성)
//     CLOSED     → grey        (종료)
//
//   그리고 색 하나에 의미를 걸지 않는다 — 라벨과 아이콘이 함께 말한다.
//   (색각 이상·흑백 캡처·저조도에서 색만으로 읽히는 상태는 읽히지 않는 상태다)

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

/// 주석을 걷어낸다 — 아래 검사는 **코드**에만 걸린다.
/// (이 패치의 설명 주석 자체가 `successBg` 같은 단어를 담고 있다)
String _codeOf(String dart) => dart
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _slice(String src, String start, String end) {
  final i = src.indexOf(start);
  expect(i, greaterThan(-1), reason: '구간 시작을 찾지 못했다: $start');
  final j = src.indexOf(end, i + start.length);
  expect(j, greaterThan(i), reason: '구간 끝을 찾지 못했다: $end');
  return src.substring(i, j);
}

/// `모집중` 배지를 그리는 곳 전부. 하나라도 빠지면 앱이 스스로와 모순된다.
const _recruitingSurfaces = [
  'lib/widgets/common/slot_status_badge.dart',
  'lib/widgets/admin/cards/admin_work_detail.dart',
  'lib/widgets/user/cards/user_to_card.dart',
  'lib/widgets/dialogs/apply/work_selection_card.dart',
  'lib/screens/user/user_home_screen.dart',
  'lib/screens/common/job_posting_screen.dart',
];

/// green 계열 토큰 — 모집중 배지가 다시 집어 들면 안 되는 것들.
const _greenTokens = [
  'AppColors.success',
  'AppColors.successBg',
  'AppColors.successDark',
  'AppColors.successDeep',
  'AppColors.successLight',
];

void main() {
  late String badge;

  setUpAll(() {
    badge = _codeOf(_read('lib/widgets/common/slot_status_badge.dart'));
  });

  // ══════════════════════════════════════════════════════════════
  // A~C. 세 상태가 각자 색을 갖는다
  // ══════════════════════════════════════════════════════════════

  test('RS-A RECRUITING 은 정보색 파랑이다', () {
    final s = _slice(badge, 'case SlotDisplayStatus.recruiting:', 'Widget _badge(');
    expect(s, contains('AppColors.infoDeep'));
    expect(s, contains('AppColors.infoBg'));
    for (final g in _greenTokens) {
      expect(s, isNot(contains(g)), reason: '모집중이 다시 green 으로 돌아갔다: $g');
    }
  });

  test('RS-B FULL(모집 완료)은 green 이다', () {
    final s = _slice(badge, 'if (recruitmentComplete) {', 'icon: Icons.lock,');
    expect(s, contains('AppColors.successDeep'));
    expect(s, contains('AppColors.successBg'));
    expect(s, contains('recruitmentCompleteLabel'));
  });

  test('RS-C CLOSED 는 grey 다', () {
    final s = _slice(badge, 'icon: Icons.lock,', 'case SlotDisplayStatus.scheduled:');
    expect(s, contains('AppColors.grey700'));
    expect(s, contains('AppColors.grey100'));
  });

  test('RS-C2 세 상태의 색이 서로 겹치지 않는다', () {
    final recruiting =
        _slice(badge, 'case SlotDisplayStatus.recruiting:', 'Widget _badge(');
    final full = _slice(badge, 'if (recruitmentComplete) {', 'icon: Icons.lock,');
    expect(recruiting.contains('AppColors.infoDeep'), isTrue);
    expect(full.contains('AppColors.infoDeep'), isFalse);
    expect(full.contains('AppColors.successDeep'), isTrue);
    expect(recruiting.contains('AppColors.successDeep'), isFalse);
  });

  // ══════════════════════════════════════════════════════════════
  // D. 라벨·아이콘 유지
  // ══════════════════════════════════════════════════════════════

  test('RS-D 라벨과 아이콘이 그대로다', () {
    expect(badge, contains("label: '모집중'"));
    expect(badge, contains('Icons.campaign'), reason: '모집중 아이콘');
    expect(badge, contains('Icons.check_circle'), reason: '모집 완료 아이콘');
    expect(badge, contains('Icons.lock'), reason: '마감 아이콘');
    expect(badge, contains("static const String recruitmentCompleteLabel = '모집 완료'"));
  });

  // ══════════════════════════════════════════════════════════════
  // E. 색 하나가 유일한 표현이 아니다
  // ══════════════════════════════════════════════════════════════

  test('RS-E 모든 상태가 아이콘 + 라벨을 함께 갖는다', () {
    // _badge 는 icon 과 label 을 모두 required 로 받는다 — 색만 다른 배지를
    // 만들 수 없는 구조다.
    final sig = _slice(badge, 'Widget _badge(', 'final hPad');
    expect(sig, contains('required IconData icon'));
    expect(sig, contains('required String label'));
    // 그리고 라벨이 잘려 사라지지 않는다.
    expect(badge, contains('TextOverflow.ellipsis'));
    expect(badge, contains('Flexible('));
  });

  // ══════════════════════════════════════════════════════════════
  // 전수 — 다른 표면에 green 모집중이 남아 있지 않다
  // ══════════════════════════════════════════════════════════════

  test('RS-F 모집중 배지가 green 을 쓰는 곳이 없다', () {
    final offenders = <String>[];
    for (final path in _recruitingSurfaces) {
      final lines = _codeOf(_read(path)).split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('모집중')) continue;
        // 배지 한 덩어리를 본다 — 라벨 줄 기준 위아래 4줄.
        final from = (i - 4).clamp(0, lines.length);
        final to = (i + 5).clamp(0, lines.length);
        final block = lines.sublist(from, to).join('\n');
        for (final g in _greenTokens) {
          if (block.contains(g)) {
            offenders.add('$path:${i + 1} → $g');
            break;
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: '모집중이 아직 green 이다 (RECRUITING != 달성):\n${offenders.join('\n')}');
  });

  test('RS-G 모집중 표면이 파랑 계열을 쓴다', () {
    const blue = [
      'AppColors.info',
      'AppColors.infoBg',
      'AppColors.infoDark',
      'AppColors.infoDeep',
      'AppColors.infoMedium',
    ];
    final missing = <String>[];
    for (final path in _recruitingSurfaces) {
      final lines = _codeOf(_read(path)).split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('모집중')) continue;
        final from = (i - 4).clamp(0, lines.length);
        final to = (i + 5).clamp(0, lines.length);
        final block = lines.sublist(from, to).join('\n');
        if (!blue.any(block.contains)) missing.add('$path:${i + 1}');
      }
    }
    expect(missing, isEmpty,
        reason: '모집중인데 정보색이 아니다:\n${missing.join('\n')}');
  });

  test('RS-H CTA brand 색을 배지에 쓰지 않는다', () {
    // primary CTA(#1565C0)와 같은 값을 쓰면 배지가 버튼처럼 읽힌다.
    for (final path in _recruitingSurfaces) {
      final lines = _codeOf(_read(path)).split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('모집중')) continue;
        final from = (i - 4).clamp(0, lines.length);
        final to = (i + 5).clamp(0, lines.length);
        final block = lines.sublist(from, to).join('\n');
        expect(block, isNot(contains('AppColors.brand')),
            reason: '$path:${i + 1} — 배지가 CTA 색을 집었다');
      }
    }
  });

  test('RS-I 토큰 값이 의도한 그대로다', () {
    final colors = _read('lib/theme/app_colors.dart');
    expect(colors, contains('infoMedium     = Color(0xFF1E88E5)'));
    expect(colors, contains('infoDeep       = Color(0xFF0D47A1)'));
    expect(colors, contains('brand = workTypeBlue'));
    // 새 색 family 를 만들지 않았다.
    expect(colors, isNot(contains('recruitingBlue')));
    expect(colors, isNot(contains('AppColors.recruiting')));
  });
}
