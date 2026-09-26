// [R5-G] 권한 상태 표현 계약.
//
//   지키는 문장은 하나다.
//
//     모른다와 확인 실패는 권한 없음이 아니다.
//
//   메뉴가 사라지는 것은 사용자에게 "권한을 빼앗겼다"로 읽힌다. 구독이 한 번
//   끊긴 것뿐인데 그렇게 보이면 안 된다. 그래서 **감추는 것은 확인된 거부일
//   때뿐**이고, 모르는 동안에는 자리를 지킨다.
//
//   판정 규칙은 실제 코드(PermissionCheckUx)를 직접 불러 고정하고, 어느
//   화면이 그 규칙을 쓰는지는 소스 문자열로 고정한다.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/providers/user_provider.dart';

String _codeOf(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  late String shell;
  late String settings;
  late String provider;

  setUpAll(() {
    shell = _codeOf(File(
      'lib/screens/business_admin/business_admin_shell.dart',
    ).readAsStringSync());
    settings = _codeOf(
        File('lib/screens/common/settings_screen.dart').readAsStringSync());
    provider =
        _codeOf(File('lib/providers/user_provider.dart').readAsStringSync());
  });

  // ───────────────────────────────────────────────────────────
  group('G-1x 네 상태 표현 규칙 (§4)', () {
    test('A 허용 → 보인다', () {
      expect(PermissionCheck.allowed.hidesAffordance, isFalse);
      expect(PermissionCheck.allowed.isAllowed, isTrue);
    });

    test('B 확인된 거부 → 감춘다', () {
      expect(PermissionCheck.denied.hidesAffordance, isTrue);
      expect(PermissionCheck.denied.isAllowed, isFalse);
    });

    test('C 모름 → 거부로 오인하지 않는다', () {
      expect(PermissionCheck.unknown.hidesAffordance, isFalse,
          reason: '모르는 것을 확정적으로 감추면 권한을 잃은 것처럼 보인다');
      expect(PermissionCheck.unknown.isAllowed, isFalse,
          reason: '동시에 허용으로도 쓰지 않는다');
      expect(PermissionCheck.unknown.isPending, isTrue);
    });

    test('D 확인 실패 → 거부로 오인하지 않는다', () {
      expect(PermissionCheck.error.hidesAffordance, isFalse);
      expect(PermissionCheck.error.isAllowed, isFalse);
      expect(PermissionCheck.error.isPending, isTrue);
    });

    test('네 상태가 두 축에서 서로 구별된다', () {
      // (보임, 허용) 조합이 상태마다 달라야 bool 하나로 되돌아가지 않는다.
      final seen = <String>{};
      for (final c in PermissionCheck.values) {
        seen.add('${c.hidesAffordance}/${c.isAllowed}/${c.isPending}');
      }
      expect(seen.length, 3,
          reason: 'allowed · denied · (unknown=error) 세 가지 표현');
      expect(PermissionCheck.values.length, 4);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('G-2x 상태 전이 (§9 F·G·H)', () {
    // 화면이 보는 것은 "지금 판정"이다. 전이는 그 판정이 바뀌는 것이고,
    //   규칙이 상태에만 의존하므로 순서에 기억이 남지 않아야 한다.
    bool visible(PermissionCheck c) => !c.hidesAffordance;

    test('F 확인 실패는 직전 허용을 검증된 허용으로 만들지 않는다', () {
      expect(visible(PermissionCheck.allowed), isTrue);
      expect(visible(PermissionCheck.error), isTrue, reason: '자리는 지킨다');
      expect(PermissionCheck.error.isAllowed, isFalse,
          reason: '그러나 실행을 열어주지는 않는다');
    });

    test('G 실패 → 허용 회복: 재로그인 없이 되돌아온다', () {
      const path = [
        PermissionCheck.allowed,
        PermissionCheck.error,
        PermissionCheck.allowed,
      ];
      expect(path.map(visible).toList(), [true, true, true]);
      expect(path.map((c) => c.isAllowed).toList(), [true, false, true]);
    });

    test('H 실패 → 거부 확정: 그때 감춘다', () {
      const path = [
        PermissionCheck.allowed,
        PermissionCheck.error,
        PermissionCheck.denied,
      ];
      expect(path.map(visible).toList(), [true, true, false]);
    });

    test('모름 → 거부 확정도 같은 규칙이다', () {
      const path = [
        PermissionCheck.unknown,
        PermissionCheck.denied,
      ];
      expect(path.map(visible).toList(), [true, false]);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('G-3x Shell 탭 안정성 (§5·§9 J)', () {
    test('J 탭 목록이 확인된 거부에만 반응한다', () {
      expect(shell.contains('.hidesAffordance) 2'), isTrue);
      expect(shell.contains('.hidesAffordance) 3'), isTrue);
      expect(shell.contains('up.can((p) => p.canManageWorkers)'), isFalse,
          reason: 'bool 하나로 돌아가면 모름이 다시 탭을 지운다');
      expect(shell.contains('up.can((p) => p.canManageWage)'), isFalse);
    });

    test('J2 홈·MY 는 언제나 남는다 — index 매핑이 흔들리지 않는다', () {
      final i = shell.indexOf('List<int> _visibleTabIndices');
      expect(i, greaterThan(-1));
      final body = shell.substring(i, i + 900);
      expect(body.contains('0, // 홈'), isTrue);
      expect(body.contains('4, // MY'), isTrue);
    });

    test('J3 숨겨진 탭에 있으면 홈으로 보내는 로직은 그대로다', () {
      // 규칙 자체는 유지한다 — 이제 그 조건이 확정된 거부에만 걸린다.
      expect(shell.contains('if (!visibleIndices.contains(_currentIndex))'),
          isTrue);
      expect(shell.contains('setState(() => _currentIndex = 0)'), isTrue);
    });

    test('J4 IndexedStack 자식 구성은 건드리지 않았다', () {
      for (final t in <String>[
        '_lazyTab(0,', '_lazyTab(3,', '_lazyTab(4,',
      ]) {
        expect(shell.contains(t), isTrue, reason: t);
      }
    });
  });

  // ───────────────────────────────────────────────────────────
  group('G-4x Settings 메뉴 (§6)', () {
    test('권한 메뉴가 확인된 거부에만 사라진다', () {
      final n = 'hidesAffordance'.allMatches(settings).length;
      expect(n, greaterThanOrEqualTo(7),
          reason: '날인·업무관리·계약·분석 섹션과 그 안의 항목들');
      expect(settings.contains('userProvider.can((p)'), isFalse,
          reason: 'bool 하나를 쓰면 모름이 메뉴를 지운다');
    });

    test('E 소유자 경로는 그대로다', () {
      // 소유자는 member 문서와 무관하게 통과한다 — 기존 첫 절을 유지했다.
      expect(settings.contains("user?.isBusinessAdmin == true ||"), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('G-5x 앞선 권한 계약 보존 (§2·§7·§8)', () {
    test('E2 소유자·SUPER_ADMIN 은 판정 첫 줄에서 허용된다', () {
      final i = provider.indexOf('PermissionCheck checkCurrentBusiness(');
      final body = provider.substring(i, i + 700);
      expect(
        body.contains(
            'if (user.isBusinessAdmin || user.isSuperAdmin) return PermissionCheck.allowed;'),
        isTrue,
        reason: 'SubAdmin 구독 실패가 소유자 메뉴를 흔들면 안 된다',
      );
    });

    test('F2 구독이 죽으면 마지막 값으로 허용하지 않는다', () {
      final i = provider.indexOf('PermissionCheck checkCurrentBusiness(');
      final body = provider.substring(i, i + 900);
      final errIdx = body.indexOf('return PermissionCheck.error;');
      final permIdx = body.indexOf('_memberPermissions');
      expect(errIdx, greaterThan(-1));
      expect(permIdx, greaterThan(errIdx),
          reason: '캐시된 값을 보기 **전에** 실패를 판정해야 한다');
    });

    test('I 사업장별로 구독 상태를 따로 본다', () {
      expect(provider.contains('permissionWatchStateFor(businessId)'), isTrue);
      final i = provider.indexOf('PermissionCheck checkForBusiness(');
      final body = provider.substring(i, i + 900);
      expect(body.contains('_subAdminPermissionsByBusinessView[businessId]'),
          isTrue,
          reason: '다른 사업장의 검증값을 대체 진실로 쓰지 않는다');
    });

    test('bool API 를 없애지 않았다 — 다른 화면 계약은 그대로다', () {
      expect(provider.contains('bool can(bool Function(MemberPermissions p) check)'),
          isTrue);
      expect(provider.contains('bool canForBusiness('), isTrue);
    });

    test('새 capability 를 만들지 않았다', () {
      for (final bad in <String>[
        'canViewMenu', 'canSeeTab', 'canNavigate',
      ]) {
        expect(provider.contains(bad), isFalse, reason: bad);
      }
    });
  });
}
