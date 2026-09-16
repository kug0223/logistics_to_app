// [PREDEVICE-CONTRACT-GATE.1] 계약 안내는 한 곳에서 만들고, 근무를 가리지 않는다
//
// READ에서 확인된 것:
//   · 미서명 계약 배너가 UserRootScreen과 GradientScaffold에 각각 구현돼 있어
//     문구와 이동 경로가 따로 놀 수 있었다. 근로자가 가장 자주 보는 문장이다.
//   · 문구는 '미서명 계약서 N건'뿐이라 어느 근무의 계약인지 알 수 없었고,
//     탭하면 항상 목록으로 보내 한 건뿐일 때도 다시 찾게 했다.
//   · 일정 탭에는 계약 상태가 전혀 없었다 — 근무 전에 발견할 자리가
//     배너와 알림밖에 없었다.
//   · 미서명 목록은 로그인과 FCM 수신 때만 갱신됐다. push를 놓치면 앱을
//     다시 켤 때까지 배너가 나타나지 않았다.
//
// 계약:
//   배너는 하나의 위젯이 만든다. 대표 한 건의 날짜·사업장을 함께 말하고,
//   한 건이면 그 계약서로 바로 보낸다. 일정 카드는 근무를 숨기지 않고
//   서명이 필요할 때만 행동 줄을 덧붙인다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _barPath = 'lib/widgets/user/pending_contract_bar.dart';
const _rootPath = 'lib/screens/user/user_root_screen.dart';
const _scaffoldPath = 'lib/widgets/common/gradient_scaffold.dart';
const _schedCardPath = 'lib/widgets/calendar/schedule_card.dart';
const _providerPath = 'lib/providers/user_provider.dart';
const _modelPath = 'lib/models/core/employment_contract_model.dart';
const _homePath = 'lib/screens/user/user_home_screen.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  group('배너는 한 곳에서만 만든다', () {
    test('공용 위젯이 존재하고 두 호출부가 그것을 쓴다', () {
      expect(_codeOf(_src(_barPath)).contains('class PendingContractBar'), true);
      expect(_codeOf(_src(_rootPath)).contains('const PendingContractBar()'), true);
      expect(
        _codeOf(_src(_scaffoldPath)).contains('PendingContractBar(useSafeArea: true)'),
        true,
      );
    });

    test('복제된 구현이 남아 있지 않다', () {
      for (final p in [_rootPath, _scaffoldPath]) {
        final code = _codeOf(_src(p));
        expect(code.contains('미서명 계약서'), false,
            reason: '$p 에 배너 문구 사본이 남으면 두 화면이 다른 말을 하게 된다');
        expect(code.contains('hasPendingContract'), false,
            reason: '$p 가 자체 표시 판단을 들고 있으면 안 된다');
      }
    });
  });

  group('배너가 어떤 근무인지 말한다', () {
    final bar = _codeOf(_src(_barPath));
    final flat = _flat(bar);

    test('한 건과 여러 건의 문구가 다르다', () {
      expect(bar.contains("'계약서 서명이 필요해요'"), true);
      expect(bar.contains("서명할 계약서 \${data.count}건이 있어요"), true);
      expect(bar.contains("'가장 가까운 근무 \$contextLabel'"), true,
          reason: '여러 건일 때 목록을 펼치지 않고 대표 한 건만 말한다');
      expect(bar.contains('미서명 계약서'), false,
          reason: '건수만 말하던 옛 문구가 남으면 안 된다');
    });

    test('날짜·사업장은 계약서에서 가져온다', () {
      final model = _codeOf(_src(_modelPath));
      expect(model.contains('String? get contextLabel'), true);
      expect(model.contains('String? get earliestWorkDate'), true);
      expect(model.contains('snapshot.businessName'), true);
      expect(flat.contains('data.nearest?.contextLabel'), true);
    });

    test('대표 한 건 선택은 provider의 canonical이다', () {
      final prov = _codeOf(_src(_providerPath));
      expect(prov.contains('get nearestPendingContract'), true);
      expect(flat.contains('p.nearestPendingContract'), true,
          reason: '배너가 자체 정렬 규칙을 들고 있으면 화면마다 다른 대표가 나온다');
    });

    test('한 건이면 목록을 거치지 않고 그 계약서로 간다', () {
      expect(flat.contains('final only = isSingle ? data.nearest : null;'), true);
      expect(flat.contains('only == null ? const UserContractsScreen()'), true);
      expect(flat.contains('ContractSignScreen(contract: only, role: '), true);
    });

    test('복귀 시 목록을 다시 받는다 — 다른 기기 서명 반영', () {
      expect(flat.contains('provider.refreshPendingContracts()'), true);
    });
  });

  group('일정은 근무를 숨기지 않고 남은 행동만 덧붙인다', () {
    final card = _codeOf(_src(_schedCardPath));

    test('서명 대기일 때만 행동 줄이 붙는다', () {
      expect(card.contains('_buildContractActionRow(context)'), true);
      expect(card.contains('p.pendingContractForTo(toId)'), true,
          reason: '서명 대기 계약만 근로자가 할 수 있는 일이다');
      expect(
        _flat(card).contains('if (pending == null) return const SizedBox.shrink();'),
        true,
        reason: '계약이 없거나 사업주 처리 중이면 아무 말도 하지 않는다',
      );
    });

    test('근무 자체를 가리는 분기가 없다', () {
      // 카드 렌더가 계약 때문에 통째로 비어서는 안 된다.
      expect(card.contains("'계약서 서명이 필요해요'"), true);
      expect(card.contains("'계약서 확인'"), true, reason: 'CTA가 있어야 한다');
      for (final internal in ['pending_worker', 'CONTRACT_PENDING']) {
        expect(card.contains("'$internal'"), false,
            reason: '내부 상태명을 일정 카드 문구로 쓰지 않는다');
      }
    });
  });

  group('계약 상태는 push에만 의존하지 않는다', () {
    test('홈 로드가 미서명 계약 목록도 함께 갱신한다', () {
      final home = _flat(_codeOf(_src(_homePath)));
      expect(home.contains('refreshPendingContracts()'), true,
          reason: 'push를 놓치면 앱 재시작까지 배너가 나타나지 않는다');
      expect(home.contains('unawaited('), true,
          reason: '실패해도 홈 로드를 깨뜨리지 않아야 한다');
    });
  });
}
