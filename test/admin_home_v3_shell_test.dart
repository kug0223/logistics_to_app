// [HOME-V2-08D.1] Home V3 shell + header
//
// 08C spec에서 확정된 것 중 **가장 바깥 visual foundation만** 구현한다.
//   · Header hierarchy 축소 — Hero(17px)가 화면 최대 텍스트가 되려면
//     22px bold 이름이 먼저 내려와야 한다.
//   · grouped surface를 admin card 언어(surface · radius 16 · grey200 1px ·
//     shadow 없음)로 정렬. 공고 카드(03S.1)와 같은 값이다.
//
// 아직 구현하지 않는다: Adaptive Hero · section gate · Today 재구성 ·
//   당일 명단 · 다가오는 7일 변경 · task visual · section rename.
//   Hero와 section gate는 08D.2에서 **동시에** 들어간다 — Hero 없이 gate만
//   넣으면 기존 empty 설명이 사라지고 대체가 없다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _homePath = 'lib/screens/business_admin/business_admin_home_screen.dart';

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

void main() {
  final home = _src(_homePath);
  final code = _codeOf(home);
  final header = _codeOf(_bodyOf(home, 'Widget _buildHeader('));

  // ══════════════════════════════════════════════════════════════
  // §4 §5 §7 — Header
  // ══════════════════════════════════════════════════════════════
  group('01. Header 축소', () {
    test('01-a 인사말이 제거됐다 (§4)', () {
      // 주석에는 변경 이유로 남아 있으므로 코드만 본다
      expect(code.contains('안녕하세요,'), false);
      expect(header.contains("Text('안녕하세요,'"), false);
    });

    test('01-b 이름이 22 bold → 15 w700 (§5)', () {
      expect(_flat(header).contains('fontSize: 15, fontWeight: FontWeight.w700'),
          true);
      expect(header.contains('fontSize: 22'), false);
    });

    test('01-c 새 typography scale을 만들지 않았다 (§5)', () {
      // 15는 ResponsiveHelper.bodyStyle과 같은 단계다 — 앱 공통 scale 안이다.
      final rh = _src('lib/utils/responsive_helper.dart');
      expect(
        _flat(_codeOf(_bodyOf(rh, 'static TextStyle bodyStyle(')))
            .contains('fontSize: 15'),
        true,
        reason: 'header 이름 크기가 앱 공통 body 단계와 같아야 한다',
      );
      // scale 밖 값을 새로 넣지 않았다
      for (final off in ['fontSize: 11', 'fontSize: 14', 'fontSize: 19',
        'fontSize: 20', 'fontSize: 21', 'fontSize: 22']) {
        if (off == 'fontSize: 14') continue; // 이 파일에 원래 있던 값
        expect(code.contains(off), false, reason: off);
      }
    });

    test('01-d 인사말용 spacer도 함께 제거됐다 (§7)', () {
      // `안녕하세요,` 아래 2px spacer가 남아 높이만 유지되면 안 된다
      expect(header.contains('SizedBox(height: 2 * s)'), false);
    });

    test('01-e 이름 ellipsis 방어 유지', () {
      final flat = _flat(header);
      expect(flat.contains('maxLines: 1, overflow: TextOverflow.ellipsis'), true);
      expect(flat.contains('Flexible( child: Text('), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §3 §6 — Header 보존
  // ══════════════════════════════════════════════════════════════
  group('02. Header interaction / content 보존', () {
    test('02-a 이름 · 역할 배지 유지', () {
      expect(header.contains(r"Text('$name님'"), true);
      expect(_flat(header).contains('isSub ? _subAdminBadge(context, s, up, theme) : _adminBadge(s, theme)'),
          true);
    });

    test('02-b 사업장 context 유지 (§6)', () {
      expect(header.contains('_businesses.first.name'), true);
      expect(header.contains(r"'${_businesses.length}개 사업장 관리'"), true);
    });

    test('02-c 알림 · 설정 action 유지', () {
      expect(header.contains('NotificationBadge('), true);
      expect(header.contains('Icons.notifications_outlined'), true);
      expect(header.contains('NotificationScreen()'), true);
      expect(header.contains('SettingsScreen()'), true);
      expect(header.contains('_reloadReadiness()'), true,
          reason: '설정 복귀 시 readiness 재계산 [P2-01]');
    });

    test('02-d SubAdmin 전용 요소 무회귀', () {
      expect(header.contains('_buildPermissionSummaryLine(s, up)'), true);
      expect(header.contains('_buildSubAdminModeToggle(context, s, up, theme)'),
          true);
      expect(header.contains('up.permissionsLoaded'), true);
    });

    test('02-e 로고 행 유지', () {
      expect(header.contains("assets/icons/app_icon.png"), true);
      expect(header.contains("Text('ALfit'"), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §8 §10 §11 §12 §13 — surface contract
  // ══════════════════════════════════════════════════════════════
  group('03. grouped surface', () {
    final deco = _codeOf(
        _bodyOf(home, 'static final BoxDecoration _groupSurface'));

    test('03-a 단일 데코레이션 토큰이 존재한다', () {
      expect(
        home.contains('static final BoxDecoration _groupSurface = BoxDecoration('),
        true,
      );
    });

    test('03-b surface · radius 16 · grey200 1px · shadow 없음', () {
      final flat = _flat(deco);
      expect(flat.contains('color: AppColors.surface'), true);
      expect(flat.contains('borderRadius: BorderRadius.circular(16)'), true);
      expect(flat.contains('border: Border.all(color: AppColors.grey200, width: 1)'),
          true);
      expect(deco.contains('boxShadow'), false);
    });

    test('03-c 새 border color / radius를 만들지 않았다 (§12, §13)', () {
      // 기존 semantic token만 사용
      expect(deco.contains('Color(0x'), false);
      expect(deco.contains('withValues'), false);
    });

    test('03-d 실제 grouped surface가 이것을 쓴다 (§9)', () {
      // [HOME-V2-08D.2] Hero shell + skeleton이 같은 토큰을 재사용해 11곳.
      expect('decoration: _groupSurface,'.allMatches(code).length, 11);
      expect(_codeOf(_bodyOf(home, 'Widget _heroShell(')).contains('_groupSurface'),
          true);
      expect(_codeOf(_bodyOf(home, 'Widget _heroSkeleton(')).contains('_groupSurface'),
          true);
    });

    test('03-e 섹션별로 흩어져 있던 값이 사라졌다', () {
      expect(code.contains('color: Colors.white,'), false);
      expect(code.contains('BorderRadius.circular(12 * s)'), false);
      expect(code.contains('AppColors.border, width: 0.8'), false);
    });

    test('03-f Home 전체에 decorative shadow가 없다 (§11)', () {
      expect(code.contains('boxShadow'), false);
      expect(code.contains('BoxShadow'), false);
      expect(code.contains('elevation:'), false);
    });

    test('03-g 카드가 아닌 것을 카드로 바꾸지 않았다 (§9)', () {
      // 상태 배너는 자체 tint surface 유지
      final banner = _codeOf(_bodyOf(home, 'Widget _stateABanner('));
      expect(banner.contains('_groupSurface'), false);
      expect(banner.contains('theme.primaryColor.withValues(alpha: 0.06)'), true);
      // header bar도 grouped surface가 아니다
      expect(header.contains('_groupSurface'), false);
      expect(header.contains('color: AppColors.surface'), true);
    });

    test('03-h 전경 white는 건드리지 않았다 (§10)', () {
      expect('foregroundColor: Colors.white'.allMatches(code).length, 1);
      expect(code.contains('selected ? Colors.white : AppColors.grey500'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §14 §15 §16 — 배경 / spacing / 문구
  // ══════════════════════════════════════════════════════════════
  group('04. page background · spacing · 문구', () {
    test('04-a page background 무변경 (§14)', () {
      expect(code.contains('backgroundColor: AppColors.grey50'), true);
    });

    test('04-b spacing — Hero 아래 20, 섹션 사이 16 (§27)', () {
      // [HOME-V2-08D.2] 섹션 조립이 _buildSections로 옮겨졌다.
      final sec = _codeOf(_bodyOf(home, 'List<Widget> _buildSections('));
      expect(sec.contains('SizedBox(height: 20 * s)'), true);
      expect(sec.contains('SizedBox(height: 16 * s)'), true);
      // Hero 밑에 아무 섹션도 없으면 여백을 만들지 않는다
      expect(sec.contains('if (sections.isEmpty) return const [];'), true);
    });

    test('04-c section 순서 무변경', () {
      final sec = _codeOf(_bodyOf(home, 'List<Widget> _buildSections('));
      final today = sec.indexOf('_buildTodayOps(');
      final task = sec.indexOf('_buildActionDashboard(');
      final future = sec.indexOf('_buildFutureStaffing(');
      expect(today, greaterThan(-1));
      expect(today, lessThan(task));
      expect(task, lessThan(future));
      // Hero는 섹션들보다 앞에 있다
      final build = _codeOf(_bodyOf(home, 'Widget build(BuildContext context)'));
      expect(build.indexOf('_buildStateBanner('),
          lessThan(build.indexOf('_buildAdaptiveHero(')));
      expect(build.indexOf('_buildAdaptiveHero('),
          lessThan(build.indexOf('_buildSections(')));
    });

    test('04-d section 이름 무변경 (§16)', () {
      for (final t in ["'오늘 운영'", "'처리할 일'", "'다가오는 인력 부족'"]) {
        expect(home.contains(t), true, reason: t);
      }
    });

    test('04-e _sectionHeader 구조 무변경 (§16)', () {
      expect(
        _flat(code).contains(
            'Widget _sectionHeader(BuildContext context, double s, String title, {String? action, VoidCallback? onAction})'),
        true,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §17 §19 — 이번 Phase에서 구현하지 않은 것
  // ══════════════════════════════════════════════════════════════
  group('05. 08D.2 이후 상태', () {
    // [HOME-V2-08D.2] 이 group은 08D.1에서 "아직 안 했다"를 고정하던 자리다.
    //   Hero와 gate가 들어왔으므로 같은 항목을 반대 방향으로 고정한다.
    //   08D.3/08D.4 범위(Today 재구성 · rename · 당일 명단)는 여전히 미구현이다.

    test('05-a Adaptive Hero가 들어왔다', () {
      expect(code.contains('Widget _buildAdaptiveHero('), true);
      expect(code.contains('Widget _heroSkeleton('), true);
      expect(code.contains('_HeroState _heroStateOf('), true);
    });

    test('05-b section gate가 적용됐다', () {
      final sec = _codeOf(_bodyOf(home, 'List<Widget> _buildSections('));
      expect(sec.contains('if (_showTodaySection)'), true);
      expect(sec.contains('if (_showTaskSection(hero, hasRows))'), true);
      expect(sec.contains('if (_showUpcomingSection)'), true);
    });

    test('05-c 대체된 empty 문구가 제거됐다 (§18, §19)', () {
      // 주석에는 제거 이유로 남아 있으므로 코드만 본다
      expect(code.contains("'오늘 예정된 인력 운영이 없어요'"), false);
      expect(code.contains("'향후 7일 예정된 인력 운영이 없어요'"), false);
      // 남는 것: task 0 한 줄 + 미래 전부 충원
      expect(code.contains("'처리할 업무가 없어요'"), true);
      expect(code.contains("'향후 7일 인원이 모두 충원됐어요'"), true);
    });

    test('05-d 당일 명단 CTA는 아직 없다 (08D.3)', () {
      expect(home.contains('당일 명단'), false);
    });

    test('05-e Today KPI 구조 무변경', () {
      final ops = _codeOf(_bodyOf(home, 'Widget _buildStaffingMetrics('));
      for (final t in ["label: '필요'", "label: '확정'", "label: '부족'"]) {
        expect(ops.contains(t), true, reason: t);
      }
      final att = _codeOf(_bodyOf(home, 'Widget _buildAttendanceMetrics('));
      expect(att.contains("label: '현재 출근'"), true);
      expect(att.contains("label: '근태 확인'"), true);
      expect(code.contains('Widget _opsMetric('), true);
    });

    test('05-f upcoming interaction 무변경', () {
      final f = _codeOf(_bodyOf(home, 'Widget _buildFutureShortageRow('));
      expect(f.contains('_navigateToDayApplicantsForDate(context, day)'), true);
      expect(f.contains('충원하기'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §21 §22 §23 — correctness 무회귀
  // ══════════════════════════════════════════════════════════════
  group('06. 무회귀', () {
    test('06-a task truth가 posting lifecycle과 분리돼 있다 (§21)', () {
      final dash = _codeOf(_bodyOf(home, 'Widget _buildActionDashboard('));
      expect(dash.contains('publishedPostingCount'), false);
      expect(dash.contains('hasDraftPosting'), false);
      expect(dash.contains('_makeActionRows(context, s, up, cs)'), true);
      // 9종 row 전부 살아 있다
      for (final label in [
        "label: '퇴사 요청'", "label: '지원 검토'", "label: '스케줄 변경 요청'",
        "label: '계약 미발송'", "label: '마감 필요'", "label: '중간정산 요청'",
        "label: '급여 변경 요청'", "label: '이체 대기'", "label: '계약 종료 예정'",
      ]) {
        expect(home.contains(label), true, reason: label);
      }
    });

    test('06-b navigation / destination 무변경 (§22)', () {
      expect(home.contains('_navigateToDayApplicantsForDate(context, onShortageDay)'),
          true);
      expect(home.contains('_openTodayAttendanceDialog(context)'), true);
      expect('_safeNavigate('.allMatches(code).length >= 8, true);
      expect(code.contains('_requireApprovedBusiness('), true);
    });

    test('06-c mutation freshness 무변경 (§22)', () {
      final att = _flat(
          _codeOf(_bodyOf(home, 'Future<void> _openTodayAttendanceDialog(')));
      expect(att.contains('unawaited(_loadTodayAttendance());'), true);
      expect(att.contains('unawaited(_loadStaffingReadiness());'), true);
      // [HOME-V2-08D.2] +1 — Hero의 `공고 등록` 성공도 staffing을 바꾼다.
      expect('notifyDataChanged'.allMatches(code).length, 4);
      final create = _flat(_codeOf(_bodyOf(home, 'void _openCreatePosting(')));
      expect(create.contains('WorkforceController.notifyDataChanged( origin: AdminMutationOrigin.home, )'),
          true);
    });

    test('06-d self-origin skip 무변경 (§22)', () {
      final onMut = _flat(_codeOf(_bodyOf(home, 'void _onAdminMutation(')));
      expect(
        onMut.contains(
            'if (WorkforceController.lastMutationOrigin == AdminMutationOrigin.home) { return; }'),
        true,
      );
    });

    test('06-e ERROR ≠ ZERO · partial 무변경 (§22)', () {
      expect(code.contains('_todayOpsErrorRow('), true);
      expect(code.contains('_partialStaffingNotice('), true);
      expect(code.contains('hasUsableData'), true);
      expect(code.contains('hasTodayTarget'), true);
    });

    test('06-f loader 수 · API 호출 불변 (§23)', () {
      expect(
        RegExp(r'Future<void> _load\w+\(').allMatches(code).length,
        5,
        reason: 'canonicalSummary · staffingReadiness · todayAttendance · '
            'readiness · approvedBusinessStatus',
      );
      final refresh = _codeOf(_bodyOf(home, 'Future<void> _refresh('));
      for (final l in [
        '_loadCanonicalSummary()',
        '_loadStaffingReadiness()',
        '_loadTodayAttendance()',
      ]) {
        expect(refresh.contains(l), true, reason: l);
      }
    });

    test('06-g listener 무변경 (§23)', () {
      expect(code.contains('WorkforceController.dataRevision.addListener(_onAdminMutation)'),
          true);
      expect(code.contains('WorkforceController.dataRevision.removeListener(_onAdminMutation)'),
          true);
    });

    test('06-h 새 카드 컴포넌트를 만들지 않았다', () {
      for (final t in ['class HomeCard', 'class AdminSurface', 'class HeroCard']) {
        expect(home.contains(t), false, reason: t);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §18 — 08D.2 준비 상태 READ (state 추가 없음)
  // ══════════════════════════════════════════════════════════════
  group('07. 로스터 파생 state — 추가 read 0', () {
    final loader = _codeOf(_bodyOf(home, 'Future<void> _loadTodayAttendance('));

    test('07-a 이미 읽은 로스터에서만 파생한다', () {
      expect(loader.contains('getConfirmedWorkersByDateAndBusinessOrThrow'), true);
      // 조회는 기존 두 개뿐 — 새 쿼리를 넣지 않았다
      expect('await _firestoreService.'.allMatches(loader).length, 0);
      expect('_firestoreService.getAttendanceByDate'.allMatches(loader).length, 1);
      expect(
        '_firestoreService.getConfirmedWorkersByDateAndBusinessOrThrow'
            .allMatches(loader)
            .length,
        1,
      );
    });

    test('07-b 세 파생값을 보존한다', () {
      expect(loader.contains('_hasTodayRoster      = allConfirmed.isNotEmpty;'),
          true);
      expect(loader.contains('_todayFirstStart     = firstStart;'), true);
      expect(loader.contains('_todayWorkSummary    = _summarizeWork('), true);
    });

    test('07-c 실패 시 파생값도 null — ERROR ≠ ZERO', () {
      final catchAt = loader.lastIndexOf('} catch (e) {');
      final body = loader.substring(catchAt);
      expect(body.contains('_hasTodayRoster      = null;'), true);
      expect(body.contains('_todayFirstStart     = null;'), true);
      expect(body.contains('_todayWorkSummary    = null;'), true);
    });

    test('07-d 요약은 대표값을 지어내지 않는다', () {
      final sum = _codeOf(_bodyOf(home, 'static String? _summarizeWork('));
      expect(sum.contains("'업무 \${workTypes.length}개'"), true);
      expect(sum.contains("'시간대 \${ranges.length}개'"), true);
      expect(sum.contains("외 \${bizNames.length - 1}곳"), true);
      expect(sum.contains('return parts.isEmpty ? null : parts.join'), true);
    });
  });
}
