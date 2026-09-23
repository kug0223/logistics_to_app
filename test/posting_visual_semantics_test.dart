// [POSTING-V2-03S.1] 공고 카드 visual semantics 정렬
//
// 03S READ에서 확인된 것:
//   · `모집 완료`(인원 충족 = 성공)가 `공고 만료`와 픽셀 단위로 같았다 —
//     grey600/grey100 + lock 배지, grey400 좌측 바. 구분은 13px 라벨 한 줄뿐.
//   · `미공개` 배지의 grey500/grey100이 AppColors.canceled/canceledBg와
//     값이 같았다. 준비 상태가 취소 상태와 같은 옷을 입었다.
//   · AppColors.scheduled가 warning의 alias여서, 정상적인 예약 공개가
//     `마감 임박`과 같은 주황이었다.
//   · 좌측 4px 바가 타입(단기=info/고정=teal)과 lifecycle(마감=grey)을 겸해
//     상태 전이 중에 말하는 축이 바뀌었다.
//   · shell이 border+shadow+bar 세 겹이라 Home(flat)보다 무거웠다.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/utils/slot_status_util.dart';
import 'package:ALfit/widgets/common/slot_status_badge.dart';

// ═══════════════════════════════════════════════════════════════
// 소스 helper
// ═══════════════════════════════════════════════════════════════

const _cardPath = 'lib/widgets/admin/cards/admin_to_group_card.dart';
const _itemCardPath = 'lib/widgets/admin/cards/admin_to_item_card.dart';
const _badgePath = 'lib/widgets/common/slot_status_badge.dart';
const _colorsPath = 'lib/theme/app_colors.dart';
const _dialogPath =
    'lib/screens/business_admin/dialogs/slot_batch_select_dialog.dart';
const _listPath =
    'lib/screens/business_admin/workforce_management/workforce_list_view.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _bodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  if (start == -1) throw StateError('$signature 를 찾지 못함');
  var paren = 0;
  var afterParams = start;
  for (var i = source.indexOf('(', start); i < source.length; i++) {
    if (source[i] == '(') paren++;
    if (source[i] == ')') {
      paren--;
      if (paren == 0) {
        afterParams = i;
        break;
      }
    }
  }
  final open = source.indexOf('{', afterParams);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  throw StateError('$signature 본문의 끝을 찾지 못함');
}

// ═══════════════════════════════════════════════════════════════
// 렌더 프로브 — 실제 위젯을 띄워 색/아이콘을 읽는다
// ═══════════════════════════════════════════════════════════════

class BadgeLook {
  final IconData icon;
  final Color iconColor;
  final Color textColor;
  final Color? bgColor;
  final Color? borderColor;
  final String label;

  const BadgeLook({
    required this.icon,
    required this.iconColor,
    required this.textColor,
    required this.bgColor,
    required this.borderColor,
    required this.label,
  });

  bool get isOutline =>
      borderColor != null && (bgColor == null || bgColor == Colors.transparent);
  bool get isFilled => !isOutline;
}

Future<BadgeLook> look(
  WidgetTester tester, {
  required SlotDisplayStatus status,
  String? closedLabel,
  bool recruitmentComplete = false,
  DateTime? scheduledAt,
  bool compact = false,
  double width = 320,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: Row(
            children: [
              Flexible(
                child: SlotStatusBadge(
                  status: status,
                  closedLabel: closedLabel,
                  recruitmentComplete: recruitmentComplete,
                  scheduledAt: scheduledAt,
                  compact: compact,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ));

  final iconW = tester.widget<Icon>(
      find.descendant(of: find.byType(SlotStatusBadge), matching: find.byType(Icon)));
  final textW = tester.widget<Text>(
      find.descendant(of: find.byType(SlotStatusBadge), matching: find.byType(Text)));
  final container = tester.widget<Container>(find
      .descendant(
          of: find.byType(SlotStatusBadge), matching: find.byType(Container))
      .first);
  final deco = container.decoration as BoxDecoration;

  return BadgeLook(
    icon: iconW.icon!,
    iconColor: iconW.color!,
    textColor: textW.style!.color!,
    bgColor: deco.color,
    borderColor: (deco.border as Border?)?.top.color,
    label: textW.data!,
  );
}

void main() {
  // ══════════════════════════════════════════════════════════════
  // §1 §2 §32 — scheduled 토큰 분리
  // ══════════════════════════════════════════════════════════════
  group('01. scheduled semantic token', () {
    test('01-a warning alias가 아니다', () {
      expect(AppColors.scheduled, isNot(AppColors.warning));
      expect(AppColors.scheduledBg, isNot(AppColors.warningBg));
      expect(AppColors.scheduledDark, isNot(AppColors.warningDark));
    });

    test('01-b 전용 indigo 값을 갖는다', () {
      expect(AppColors.scheduled, const Color(0xFF5C6BC0));
      expect(AppColors.scheduledLight, const Color(0xFFC5CAE9));
      expect(AppColors.scheduledDark, const Color(0xFF3949AB));
      expect(AppColors.scheduledBg, const Color(0xFFE8EAF6));
    });

    test('01-c 소스에서 alias 선언이 사라졌다', () {
      final src = _codeOf(_src(_colorsPath));
      expect(src.contains('scheduled = warning;'), false);
      expect(src.contains('scheduledBg = warningBg;'), false);
      expect(src.contains('scheduledDark = warningDark;'), false);
    });

    test('01-d API 이름은 그대로다 — call-site 토큰 난립 없음', () {
      final src = _src(_colorsPath);
      for (final name in [
        'Color scheduled =',
        'Color scheduledLight =',
        'Color scheduledDark =',
        'Color scheduledBg =',
      ]) {
        expect(src.contains(name), true, reason: name);
      }
    });

    test('01-e warning 토큰 자체는 무변경', () {
      expect(AppColors.warning, const Color(0xFFFF9800));
      expect(AppColors.warningBg, const Color(0xFFFFF3E0));
      expect(AppColors.warningDark, const Color(0xFFF57C00));
    });

    test('01-f scheduled 사용처는 전부 예약/준비 의미다', () {
      // blast radius: SlotStatusBadge(예약 공개/공개 대기)
      //             + WorkDetailRow의 예약 배지
      final badge = _codeOf(_src(_badgePath));
      expect(badge.contains('AppColors.scheduledDark'), true);
      final row = _codeOf(_src('lib/widgets/admin/cards/admin_work_detail.dart'));
      expect(row.contains('AppColors.scheduledBg'), true);
      expect(row.contains("'공개 대기'"), true);
      expect(row.contains("'예약 공개'"), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §7 §13 §29 — DRAFT
  // ══════════════════════════════════════════════════════════════
  group('02. 미공개 (DRAFT)', () {
    testWidgets('02-a edit_note 아이콘 · visibility_off 미사용', (tester) async {
      final l = await look(tester, status: SlotDisplayStatus.draft);
      expect(l.icon, Icons.edit_note);
      expect(l.icon, isNot(Icons.visibility_off_outlined));
      expect(l.label, '미공개');
    });

    testWidgets('02-b outline이다 — filled closed와 surface가 다르다',
        (tester) async {
      final draft = await look(tester, status: SlotDisplayStatus.draft);
      final closed = await look(tester, status: SlotDisplayStatus.closed);
      expect(draft.isOutline, true);
      expect(closed.isFilled, true);
      expect(draft.borderColor, AppColors.grey300);
    });

    testWidgets('02-c canceled 토큰과 같은 조합이 아니다', (tester) async {
      final l = await look(tester, status: SlotDisplayStatus.draft);
      expect(l.textColor, isNot(AppColors.canceled));
      expect(l.bgColor, isNot(AppColors.canceledBg));
      expect(l.textColor, AppColors.grey700);
    });

    testWidgets('02-d 대비가 이전(grey500 on grey100)보다 나빠지지 않았다',
        (tester) async {
      final l = await look(tester, status: SlotDisplayStatus.draft);
      // grey700(#616161)이 grey500(#9E9E9E)보다 어둡다 = 흰 배경에서 더 읽힌다
      expect(l.textColor.r, lessThan(AppColors.grey500.r));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §8 §14 — SCHEDULED
  // ══════════════════════════════════════════════════════════════
  group('03. 예약 공개 / 공개 대기', () {
    testWidgets('03-a scheduled family를 쓴다 — warning 아님', (tester) async {
      final l = await look(tester,
          status: SlotDisplayStatus.scheduled,
          scheduledAt: DateTime.now().add(const Duration(days: 3)));
      expect(l.textColor, AppColors.scheduledDark);
      expect(l.bgColor, AppColors.scheduledBg);
      expect(l.textColor, isNot(AppColors.warningDark));
      expect(l.bgColor, isNot(AppColors.warningBg));
    });

    testWidgets('03-b 아이콘 구분이 유지된다', (tester) async {
      final future = await look(tester,
          status: SlotDisplayStatus.scheduled,
          scheduledAt: DateTime.now().add(const Duration(days: 3)));
      expect(future.icon, Icons.schedule);
      final overdue = await look(tester,
          status: SlotDisplayStatus.scheduled,
          scheduledAt: DateTime.now().subtract(const Duration(days: 1)));
      expect(overdue.icon, Icons.hourglass_empty);
      expect(overdue.label, '공개 대기');
    });

    testWidgets('03-c 마감임박 warning과 다른 family다 (§14)', (tester) async {
      final scheduled = await look(tester,
          status: SlotDisplayStatus.scheduled,
          scheduledAt: DateTime.now().add(const Duration(days: 3)));
      // 카드의 '마감임박' 배지는 warningBg/warningDark를 쓴다
      expect(scheduled.bgColor, isNot(AppColors.warningBg));
      expect(scheduled.textColor, isNot(AppColors.warningDark));
    });

    test('03-d 카드의 마감임박 배지는 여전히 warning이다', () {
      final body =
          _codeOf(_bodyOf(_src(_cardPath), 'Widget _buildUrgentBadge('));
      expect(body.contains('AppColors.warningBg'), true);
      expect(body.contains('AppColors.warningDark'), true);
      expect(body.contains("'마감임박'"), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §9 — RECRUITING
  // ══════════════════════════════════════════════════════════════
  group('04. 모집중', () {
    testWidgets('04-a label · icon · green family 유지', (tester) async {
      final l = await look(tester, status: SlotDisplayStatus.recruiting);
      expect(l.label, '모집중');
      expect(l.icon, Icons.campaign);
      expect(l.bgColor, AppColors.successBg);
    });

    testWidgets('04-b 13px 라벨이 읽히도록 successDeep을 쓴다', (tester) async {
      final l = await look(tester, status: SlotDisplayStatus.recruiting);
      expect(l.textColor, AppColors.successDeep);
      expect(l.iconColor, AppColors.successDeep);
      expect(l.textColor, isNot(AppColors.successDark));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §10 §12 — FULL
  // ══════════════════════════════════════════════════════════════
  group('05. 모집 완료 (FULL)', () {
    testWidgets('05-a check_circle + success family', (tester) async {
      final l = await look(tester,
          status: SlotDisplayStatus.closed,
          recruitmentComplete: true,
          closedLabel: '모집 완료');
      expect(l.icon, Icons.check_circle);
      expect(l.textColor, AppColors.successDeep);
      expect(l.iconColor, AppColors.successDeep);
      expect(l.bgColor, AppColors.successBg);
      expect(l.label, '모집 완료');
    });

    testWidgets('05-b lock을 쓰지 않는다', (tester) async {
      final l = await look(tester,
          status: SlotDisplayStatus.closed, recruitmentComplete: true);
      expect(l.icon, isNot(Icons.lock));
    });

    testWidgets('05-c closedLabel 없이도 모집 완료로 읽힌다', (tester) async {
      final l = await look(tester,
          status: SlotDisplayStatus.closed, recruitmentComplete: true);
      expect(l.label, SlotStatusBadge.recruitmentCompleteLabel);
    });

    testWidgets('05-d §12 invariant — 만료와 색·아이콘이 모두 다르다',
        (tester) async {
      final full = await look(tester,
          status: SlotDisplayStatus.closed,
          recruitmentComplete: true,
          closedLabel: '모집 완료');
      final expired = await look(tester,
          status: SlotDisplayStatus.closed, closedLabel: '공고 만료');
      expect(full.icon, isNot(expired.icon));
      expect(full.textColor, isNot(expired.textColor));
      expect(full.bgColor, isNot(expired.bgColor));
    });

    testWidgets('05-e 종료 · 지원 마감과도 구별된다', (tester) async {
      final full = await look(tester,
          status: SlotDisplayStatus.closed, recruitmentComplete: true);
      for (final label in ['종료', '지원 마감', '마감']) {
        final other = await look(tester,
            status: SlotDisplayStatus.closed, closedLabel: label);
        expect(other.icon, Icons.lock, reason: label);
        expect(full.bgColor, isNot(other.bgColor), reason: label);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §11 — CLOSED / EXPIRED
  // ══════════════════════════════════════════════════════════════
  group('06. 종료 / 만료', () {
    testWidgets('06-a neutral filled + lock', (tester) async {
      final l = await look(tester,
          status: SlotDisplayStatus.closed, closedLabel: '공고 만료');
      expect(l.icon, Icons.lock);
      expect(l.bgColor, AppColors.grey100);
      expect(l.isFilled, true);
    });

    testWidgets('06-b grey600 → grey700으로 대비가 올라갔다', (tester) async {
      final l = await look(tester, status: SlotDisplayStatus.closed);
      expect(l.textColor, AppColors.grey700);
      expect(l.textColor.r, lessThan(AppColors.grey600.r));
    });

    testWidgets('06-c reason별 label이 그대로 전달된다', (tester) async {
      for (final label in ['종료', '지원 마감', '공고 만료']) {
        final l = await look(tester,
            status: SlotDisplayStatus.closed, closedLabel: label);
        expect(l.label, label);
      }
      final legacy = await look(tester, status: SlotDisplayStatus.closed);
      expect(legacy.label, '마감');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §24 — 최종 매트릭스
  // ══════════════════════════════════════════════════════════════
  group('07. status matrix', () {
    testWidgets('07-a 여섯 상태가 (icon, bg) 조합으로 서로 다르다', (tester) async {
      final looks = <String, BadgeLook>{
        '미공개': await look(tester, status: SlotDisplayStatus.draft),
        '예약 공개': await look(tester,
            status: SlotDisplayStatus.scheduled,
            scheduledAt: DateTime.now().add(const Duration(days: 3))),
        '공개 대기': await look(tester,
            status: SlotDisplayStatus.scheduled,
            scheduledAt: DateTime.now().subtract(const Duration(days: 1))),
        '모집중': await look(tester, status: SlotDisplayStatus.recruiting),
        '모집 완료': await look(tester,
            status: SlotDisplayStatus.closed, recruitmentComplete: true),
        '만료': await look(tester,
            status: SlotDisplayStatus.closed, closedLabel: '공고 만료'),
      };
      final keys = looks.keys.toList();
      for (var i = 0; i < keys.length; i++) {
        for (var j = i + 1; j < keys.length; j++) {
          final a = looks[keys[i]]!;
          final b = looks[keys[j]]!;
          final same = a.icon == b.icon &&
              a.bgColor == b.bgColor &&
              a.borderColor == b.borderColor;
          expect(same, false, reason: '${keys[i]} 와 ${keys[j]} 가 같은 visual');
        }
      }
    });

    testWidgets('07-c success 상태만 successDeep을 쓴다', (tester) async {
      for (final l in [
        await look(tester, status: SlotDisplayStatus.recruiting),
        await look(tester,
            status: SlotDisplayStatus.closed, recruitmentComplete: true),
      ]) {
        expect(l.textColor, AppColors.successDeep);
      }
      for (final l in [
        await look(tester, status: SlotDisplayStatus.draft),
        await look(tester, status: SlotDisplayStatus.closed),
        await look(tester,
            status: SlotDisplayStatus.scheduled,
            scheduledAt: DateTime.now().add(const Duration(days: 3))),
      ]) {
        expect(l.textColor, isNot(AppColors.successDeep));
      }
    });

    testWidgets('07-b compact 모드도 같은 semantics를 쓴다', (tester) async {
      final full = await look(tester,
          status: SlotDisplayStatus.closed,
          recruitmentComplete: true,
          compact: true);
      expect(full.icon, Icons.check_circle);
      expect(full.textColor, AppColors.successDeep);
      expect(full.bgColor, AppColors.successBg);
      final draft =
          await look(tester, status: SlotDisplayStatus.draft, compact: true);
      expect(draft.icon, Icons.edit_note);
      expect(draft.isOutline, true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §23 — 세 호출부 동일 적용
  // ══════════════════════════════════════════════════════════════
  group('08. shared caller parity', () {
    test('08-a 세 호출부 모두 recruitmentComplete를 넘긴다', () {
      for (final entry in {
        _cardPath: 'recruitmentComplete: isRecruitmentComplete',
        _itemCardPath: 'recruitmentComplete: isRecruitmentComplete',
        _dialogPath: 'recruitmentComplete: slot.isFull || widget.to.isFull',
      }.entries) {
        expect(_flat(_codeOf(_src(entry.key))).contains(entry.value), true,
            reason: entry.key);
      }
    });

    test('08-b 호출부별 임시 색상 override가 없다', () {
      for (final p in [_cardPath, _itemCardPath, _dialogPath]) {
        final code = _codeOf(_src(p));
        expect(code.contains('SlotStatusBadge(\n        color:'), false,
            reason: p);
      }
      // 배지의 색 결정은 컴포넌트 내부에만 있다
      final badge = _codeOf(_src(_badgePath));
      expect(badge.contains('AppColors.successBg'), true);
      expect(badge.contains('AppColors.grey100'), true);
    });

    test('08-c 라벨 상수를 공유한다', () {
      final badge = _src(_badgePath);
      expect(
          badge.contains(
              "static const String recruitmentCompleteLabel = '모집 완료';"),
          true);
      for (final p in [_cardPath, _itemCardPath]) {
        expect(
            _codeOf(_src(p))
                .contains('SlotStatusBadge.recruitmentCompleteLabel'),
            true,
            reason: p);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §3 §4 §5 §30 — shell
  // ══════════════════════════════════════════════════════════════
  group('09. card shell', () {
    final src = _src(_cardPath);
    final build = _codeOf(_bodyOf(src, 'Widget build(BuildContext context)'));

    test('09-a 좌측 컬러바가 사라졌다', () {
      expect(build.contains('statusBarColor'), false);
      expect(build.contains('Positioned('), false);
      expect(build.contains('Stack('), false);
      expect(_codeOf(src).contains('AppColors.longTerm,'), false);
    });

    test('09-b shadow가 없다', () {
      expect(build.contains('boxShadow'), false);
      expect(build.contains('BoxShadow'), false);
      expect(build.contains('blurRadius'), false);
    });

    test('09-c border와 radius는 유지', () {
      final flat = _flat(build);
      expect(flat.contains('border: Border.all( color: AppColors.grey200, width: 1, )'),
          true);
      expect(flat.contains('borderRadius: BorderRadius.circular(16)'), true);
    });

    test('09-d raw Colors.white 대신 AppColors.surface', () {
      final flat = _flat(build);
      expect(flat.contains('color: AppColors.surface, borderRadius'), true);
      expect(build.contains('color: Colors.white,'), false);
    });

    test('09-e compactCardDecoration을 채택하지 않았다 (§33)', () {
      expect(build.contains('compactCardDecoration'), false);
    });

    test('09-f 카드가 배치 여백을 소유하지 않는다 (§21)', () {
      expect(_flat(build).contains('margin: EdgeInsets.only( bottom:'), false);
      expect(build.contains("margin: const EdgeInsets.only(left: 4)"), false);
      // 간격은 목록이 소유한다
      final list = _codeOf(_src(_listPath));
      expect(
        _flat(list).contains(
            'padding: EdgeInsets.only( bottom: ResponsiveHelper.spacing(context, 10), ), child: TOGroupCard('),
        true,
      );
    });

    test('09-g expanded 구조 무변경 (§22, §26)', () {
      expect(build.contains('AnimatedSize('), true);
      expect(build.contains('Divider(height: 1, color: AppColors.grey200)'), true);
      expect(build.contains('color: AppColors.grey50'), true);
      expect(build.contains('_buildMultiSlotLayout('), true);
      expect(build.contains('_buildExpandedBodyContent('), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §15 §18 §19 §20 — 텍스트 / CTA / separator
  // ══════════════════════════════════════════════════════════════
  group('10. typography · CTA · separator', () {
    final src = _src(_cardPath);

    // [R7-P1-2] 관리용 제목을 회색 보조행으로 낮추던 구조가 사라졌다.
    //   제목은 카드의 1순위 textPrimary가 됐고, 대신 사업장명이 그 자리의
    //   tertiary로 내려왔다. 이 테스트는 그 자리의 색 계약을 이어받는다.
    test('10-a 제목은 textPrimary, 사업장명은 grey600 tertiary (§15)', () {
      final title = _codeOf(_bodyOf(src, 'Widget _buildTitleLine('));
      expect(title.contains('color: known ? AppColors.textPrimary'), true);
      expect(title.contains('FontWeight.w700'), true);

      final when = _codeOf(_bodyOf(src, 'Widget _buildWhenLine('));
      expect(when.contains('color: AppColors.grey600'), true,
          reason: '사업장명은 날짜보다 약하다');
    });

    test('10-b CTA는 filled button이 아니다 (§18)', () {
      final body = _codeOf(_bodyOf(src, 'Widget _buildActionBar('));
      expect(body.contains('ElevatedButton'), false);
      expect(body.contains('FilledButton'), false);
      expect(body.contains("'인력 현황'"), true); // [R7-P1-7 §15]
      expect(body.contains('Theme.of(context).primaryColor'), true);
    });

    test('10-c chevron은 CTA보다 약한 무채색 (§19)', () {
      final body = _codeOf(_bodyOf(src, 'Widget _buildActionBar('));
      expect(body.contains('color: AppColors.grey400'), true);
      // tap 영역 유지 — padding이 남아 있다
      expect(
        _flat(body).contains(
            'padding: ResponsiveHelper.symmetricPadding(context, horizontal: 14, vertical: 9)'),
        true,
      );
    });

    test('10-d 카드 안 separator가 한 tone이다 (§20)', () {
      final body = _codeOf(_bodyOf(src, 'Widget _buildActionBar('));
      expect(body.contains('BorderSide(color: AppColors.grey200)'), true);
      expect(body.contains('AppColors.grey100'), false);
      // expanded divider와 같은 값
      final build = _codeOf(_bodyOf(src, 'Widget build(BuildContext context)'));
      expect(build.contains('Divider(height: 1, color: AppColors.grey200)'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §16 §31 — 대비 / 레이아웃 무회귀
  // ══════════════════════════════════════════════════════════════
  group('11. 대비 · 레이아웃', () {
    /// 상대 휘도 (WCAG 정의)
    double luminance(Color c) {
      double ch(double v) => v <= 0.03928
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
    }

    double ratio(Color fg, Color bg) {
      final a = luminance(fg);
      final b = luminance(bg);
      final hi = a > b ? a : b;
      final lo = a > b ? b : a;
      return (hi + 0.05) / (lo + 0.05);
    }

    test('11-a 변경한 조합이 이전보다 대비가 높다', () {
      // 미공개: grey500/grey100 → grey700/surface(outline)
      expect(ratio(AppColors.grey700, AppColors.surface),
          greaterThan(ratio(AppColors.grey500, AppColors.grey100)));
      // 종료: grey600/grey100 → grey700/grey100
      expect(ratio(AppColors.grey700, AppColors.grey100),
          greaterThan(ratio(AppColors.grey600, AppColors.grey100)));
      // 예약: warningDark/warningBg → scheduledDark/scheduledBg
      expect(ratio(AppColors.scheduledDark, AppColors.scheduledBg),
          greaterThan(ratio(AppColors.warningDark, AppColors.warningBg)));
      // 관리용 제목: grey500 → grey600 (흰 배경)
      expect(ratio(AppColors.grey600, AppColors.surface),
          greaterThan(ratio(AppColors.grey500, AppColors.surface)));
    });

    test('11-b 변경한 조합이 본문 기준(4.5)을 넘는다', () {
      expect(ratio(AppColors.grey700, AppColors.surface), greaterThan(4.5));
      expect(ratio(AppColors.grey700, AppColors.grey100), greaterThan(4.5));
      expect(
          ratio(AppColors.scheduledDark, AppColors.scheduledBg), greaterThan(4.5));
    });

    test('11-c 모집중 · 모집 완료 라벨이 본문 기준(4.5)을 넘는다', () {
      // successDark/successBg는 약 3.87로 13px 라벨에 부족했다.
      //   이미 존재하던 successDeep으로 올렸다 — 새 토큰 없음.
      expect(ratio(AppColors.successDark, AppColors.successBg), lessThan(4.5),
          reason: '이 값이 4.5를 넘게 되면 이 correction의 전제가 사라진다');
      expect(ratio(AppColors.successDeep, AppColors.successBg),
          greaterThan(4.5));
    });

    test('11-f successDark 토큰 자체는 그대로다 — 전역 blast radius 없음', () {
      expect(AppColors.successDark, const Color(0xFF388E3C));
      expect(AppColors.successDeep, const Color(0xFF1B5E20));
      expect(AppColors.success, const Color(0xFF4CAF50));
      expect(AppColors.confirmedDark, AppColors.successDark,
          reason: '확정·체크인 등 다른 화면은 successDark를 계속 쓴다');
    });

    testWidgets('11-d 좁은 폭에서 overflow 없음 (§31)', (tester) async {
      for (final width in [90.0, 120.0, 200.0]) {
        await look(tester,
            status: SlotDisplayStatus.scheduled,
            scheduledAt: DateTime(2026, 9, 20, 14, 0),
            width: width);
        expect(tester.takeException(), isNull, reason: 'width=$width');
      }
    });

    testWidgets('11-e outline 배지도 좁은 폭에서 버틴다', (tester) async {
      await look(tester, status: SlotDisplayStatus.draft, width: 80);
      expect(tester.takeException(), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §26 §27 — IA / sort 무회귀
  // ══════════════════════════════════════════════════════════════
  group('12. IA · sort 무회귀', () {
    final src = _src(_cardPath);
    final build = _codeOf(_bodyOf(src, 'Widget build(BuildContext context)'));

    // [R7-P1-2] 줄 순서가 바뀌었다 — 제목이 1순위로 올라왔다.
    //   순서의 canonical 계약은 posting_card_ia_test 06-a가 갖는다.
    //   여기서는 시각 위계가 그 순서와 어긋나지 않는지만 본다.
    test('12-a collapsed 줄 순서: 제목 → 언제 → 업무 → 인원 → 액션 (§26)', () {
      final title = build.indexOf('_buildTitleLine(');
      final when = build.indexOf('_buildWhenLine(');
      final work = build.indexOf('_buildWorkLine(');
      final staffing = build.indexOf('_buildStaffingLine(');
      final action = build.indexOf('_buildActionBar(');
      expect(title, greaterThan(-1));
      expect(title, lessThan(when));
      expect(when, lessThan(work));
      expect(work, lessThan(staffing));
      expect(staffing, lessThan(action));
    });

    test('12-b operationalDate 계약 무변경 (§27)', () {
      final body = _codeOf(_bodyOf(src, 'String? _collapsedDateText('));
      expect(body.contains('widget.groupItem.operationalDate'), true);
      expect(body.contains('groupTOs.first'), false);
      final ctrl = _codeOf(_src('lib/controllers/workforce_controller.dart'));
      expect(ctrl.contains('static DateTime? priorityDateOf('), true);
      expect(
          RegExp(r'setOperationalDate\(').allMatches(ctrl).length, 3,
          reason: 'root load + 펼침 + [R8-P4.1] 단일 공고 갱신 — 모두 controller 안이다');
    });

    test('12-c 추가 조회 없음 (§28)', () {
      final badge = _codeOf(_src(_badgePath));
      expect(badge.contains('await'), false);
      expect(badge.contains('Firestore'), false);
      expect(badge.contains('httpsCallable'), false);
    });

    test('12-d 타입 badge는 그대로 info / teal (§6)', () {
      expect(build.contains('AppColors.longTermBg'), true);
      expect(build.contains('AppColors.shortTermBg'), true);
      expect(build.contains("'고정' : '단기'"), true);
    });
  });
}
