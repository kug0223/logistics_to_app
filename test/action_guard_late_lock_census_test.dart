// [I9 · impl_16] LATE-LOCK 재발 방지 — lib 전수.
//
//   잡는 꼴: async 행동 함수가 잠금 플래그(`_isXxx` · `_busy`)를 **첫 await(확인·선택 창 등) 뒤에야** 켠다.
//     (a) `if (_flag) return;` 재진입 검사가 있는데 그 플래그를 켜기 전에 await 가 있다.
//     (b) 재진입 검사 유무와 무관하게, 확인·선택 창을 await 한 뒤에 잠금 플래그를 처음 켠다.
//   창이 뜨기 전(다음 프레임) 연타의 두 번째 진입이 창·mutation 을 한 번 더 낸다(ActionGuard 설명).
//
//     (c) [impl_20] Set 기반: `if (_xIds.contains(k)) return;` 재진입 검사가 있는데 `_xIds.add(` 전에 await 가 있다.
//   통과하는 꼴: 첫 await 전에 잠금 · 또는 그 함수가 `ActionGuard.run/runVoid(key, () => 이름(...))` 안에서만
//     불린다(바깥 잠금 · `…Locked`/`…Inner` 본문).
//
//   허용 목록 = (1) 다른 담당이 수정 중이라 이번에 넘긴 위치(사라지면 목록에서 지운다) (2) 위치별로 확인한 오탐.
//   새 위치가 생기면 실패한다 — 고치거나, 오탐이면 이유와 함께 여기에 적는다.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/action_guard.dart';

const _handedOff = <String>{
  // 공고 상세 취소·거절 · 탈퇴 실행 · 서명 삭제 — impl_18 이 바깥 잠금으로 교정해 목록에서 지웠다.
  // 서류 관리 4곳 — impl_17(L41·L42 담당)이 바깥 잠금(`…Tap` → ActionGuard.runVoid)으로 교정해 목록에서 지웠다.
};

const _falsePositive = <String>{
  // 사업장 미선택 분기에서 자기 잠금을 가진 `_loadMyBusinesses` 로 넘기고 return — 잠금 전 await 는 그 위임뿐
  'lib/screens/business_admin/to_management/create_to_screen.dart:_reCheckPrerequisites',
  // 잠금 전 await 는 "휴게 확인 필요" 안내 뒤 바로 return 하는 분기뿐 — mutation 경로는 첫 await 전에 잠근다
  'lib/screens/business_admin/dialogs/wage_confirm_dialog.dart:_processIndividualConfirm',
};

final _dialogAwait = RegExp(
    r'await\s+(?:DialogHelper\.\w+|showDialog|showModalBottomSheet|Navigator\.(?:of\([^)]*\)\.)?push\w*|'
    r'NavigationHelper\.push\w*|[A-Z]\w*\.(?:show|pick)\w*|_?show\w*(?:Dialog|Sheet|Confirm|Picker)\w*)\s*[<(]');
// 잠금 플래그 — 상태 표시 플래그(`_isDirty` 등 편집됨·펼침·선택)는 잠금이 아니다.
final _lockFlag = RegExp(r'^_(?:is(?!(?:Dirty|Changed|Edited|Expanded|Selected)$)[A-Z]\w*|busy)$');

String _stripComments(String s) => s.replaceAll(RegExp(r'//[^\n]*'), '');

/// 파일 하나의 위반 `path:name` 목록.
List<String> lateLocks(String path, String rawSrc) {
  final src = _stripComments(rawSrc);
  final wrapped = <String>{
    for (final m in RegExp(r'ActionGuard\.run(?:Void)?\s*(?:<[^>]*>)?\s*\(').allMatches(src))
      ...RegExp(r'\(\)\s*(?:async\s*)?(?:=>|\{\s*(?:return\s+|await\s+)?)\s*(_\w+)\(')
          .allMatches(src.substring(m.end, (m.end + 400).clamp(0, src.length)))
          .take(1)
          .map((x) => x.group(1)!),
  };
  final out = <String>[];
  for (final m in RegExp(r'Future<[\w?<>, ]*>\s+(_\w+)\([^)]*\)\s*async\s*\{').allMatches(src)) {
    final name = m.group(1)!;
    var depth = 1, i = m.end;
    while (i < src.length && depth > 0) {
      if (src[i] == '{') depth++;
      if (src[i] == '}') depth--;
      i++;
    }
    final body = src.substring(m.end, i);
    if (wrapped.contains(name)) continue;
    String? hit;
    // (a) 재진입 검사 + 그 플래그를 켜기 전 await
    final guard = RegExp(r'if\s*\(\s*(_\w+)\s*(?:\|\|[^)]*)?\)\s*return\s*;').firstMatch(body);
    if (guard != null) {
      final flag = guard.group(1)!;
      final set = RegExp('${RegExp.escape(flag)}\\s*=\\s*true').firstMatch(body);
      final aw = body.indexOf('await ');
      if (set != null && aw >= 0 && aw < set.start) hit = flag;
    }
    // (c) [impl_20] Set 기반 — `if (_xIds.contains(k)) return;` 재진입 검사가 있는데 그 Set 에 넣기(`_xIds.add(`) 전에 await.
    //   플래그(bool) 형태만 보던 (a)(b)의 사각지대였다(같은 프레임 두 번째 탭이 같은 항목으로 다시 들어온다).
    if (hit == null) {
      final sg = RegExp(r'if\s*\(\s*(_\w+)\.contains\([^)]*\)\s*(?:\|\|[^)]*)?\)\s*return\s*;').firstMatch(body);
      if (sg != null) {
        final setName = sg.group(1)!;
        final add = RegExp('${RegExp.escape(setName)}\\.add\\(').firstMatch(body);
        final aw = body.indexOf('await ');
        if (add != null && aw >= 0 && aw < add.start) hit = setName;
      }
    }
    // (b) 창 await 뒤 첫 잠금
    final dlg = _dialogAwait.firstMatch(body);
    if (hit == null && dlg != null) {
      final seen = <String>{};
      for (final s in RegExp(r'(_\w+)\s*=\s*true').allMatches(body)) {
        final flag = s.group(1)!;
        if (!seen.add(flag) || !_lockFlag.hasMatch(flag)) continue;
        if (dlg.start < s.start) {
          hit = flag;
          break;
        }
      }
    }
    if (hit != null) out.add('$path:$name');
  }
  return out;
}

void main() {
  test('LL-1 lib 전수 — 확인·선택 창(첫 await) 뒤에야 잠그는 행동이 새로 생기지 않았다', () {
    final found = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final p = f.path.replaceAll('\\', '/');
      found.addAll(lateLocks(p, f.readAsStringSync()));
    }
    final unexpected = found.where((k) => !_handedOff.contains(k) && !_falsePositive.contains(k)).toList()..sort();
    expect(unexpected, isEmpty,
        reason: '첫 await 전에 잠그거나 ActionGuard.runVoid(ActionGuard.ownerKey(...), () => …Locked(...)) 로 감싼다');
  });

  test('LL-2 탐지기 자체 — 늦은 잠금 · 재진입 검사 없는 창 뒤 잠금을 잡고, 첫 await 전 잠금 · ActionGuard 감싸기는 통과', () {
    const late = '''
  Future<void> _a() async {
    if (_isBusyA) return;
    final ok = await DialogHelper.showConfirm(context);
    setState(() => _isBusyA = true);
  }
  Future<void> _b() async {
    final r = await showDialog<String>(context: context, builder: (_) => const SizedBox());
    setState(() => _isSaving = true);
  }
''';
    expect(lateLocks('x.dart', late), ['x.dart:_a', 'x.dart:_b']);
    const ok = '''
  Future<void> _a() async {
    if (_isBusyA) return;
    setState(() => _isBusyA = true);
    try { await DialogHelper.showConfirm(context); } finally { _isBusyA = false; }
  }
  Future<void> _b() =>
      ActionGuard.runVoid(ActionGuard.ownerKey('x._isSaving', this), () => _bLocked());
  Future<void> _bLocked() async {
    final r = await showDialog<String>(context: context, builder: (_) => const SizedBox());
    setState(() => _isSaving = true);
  }
  Future<void> _c() async {
    final r = await showDialog<String>(context: context, builder: (_) => const SizedBox());
    setState(() => _hasChanges = true);
  }
''';
    expect(lateLocks('y.dart', ok), isEmpty);
  });

  test('LL-4 탐지기 — Set 기반 늦은 잠금(contains → await → add)을 잡고, 첫 await 전 add · ActionGuard 감싸기는 통과', () {
    const late = r'''
  Future<void> _d(String id) async {
    if (_decliningIds.contains(id)) return;
    final ok = await DialogHelper.showConfirm(context);
    setState(() => _decliningIds.add(id));
  }
  Future<void> _f(String id) async {
    if (_busyIds.contains(id) || _isOther) return;
    await save();
    _busyIds.add(id);
  }
''';
    expect(lateLocks('s.dart', late), ['s.dart:_d', 's.dart:_f']);
    const ok = r'''
  Future<void> _d(String id) async {
    if (_decliningIds.contains(id)) return;
    setState(() => _decliningIds.add(id));
    try { await DialogHelper.showConfirm(context); } finally { _decliningIds.remove(id); }
  }
  Future<void> _e(String id) =>
      ActionGuard.runVoid(ActionGuard.ownerKey('s._decliningIds#$id', this), () => _eLocked(id));
  Future<void> _eLocked(String id) async {
    if (_decliningIds.contains(id)) return;
    final ok = await DialogHelper.showConfirm(context);
    setState(() => _decliningIds.add(id));
  }
''';
    expect(lateLocks('t.dart', ok), isEmpty);
  });

  test('LL-5 항목 단위 키 — 같은 항목 연타는 막고 다른 항목은 막지 않는다', () async {
    ActionGuard.resetForTest();
    final owner = Object();
    var a = 0, b = 0;
    final gate = Completer<void>();
    Future<void> act(String id, void Function() hit) => ActionGuard.runVoid(
        ActionGuard.ownerKey('s._decliningIds#$id', owner), () async {
          hit();
          await gate.future;
        });
    final f1 = act('A', () => a++);
    final f2 = act('A', () => a++); // 같은 항목 — 같은 프레임 두 번째
    final f3 = act('B', () => b++); // 다른 항목
    expect((a, b), (1, 1));
    gate.complete();
    await Future.wait([f1, f2, f3]);
    expect(ActionGuard.inFlightCount, 0);
  });

  _behavior();
}


/// 교정 꼴의 최소 모형 — 화면 플래그는 창 뒤에 켜고(예전과 같다), 바깥 ActionGuard 가 첫 await 전에 잠근다.
class _FakeScreen {
  bool isActing = false;
  int dialogs = 0, mutations = 0;
  final dialog = Completer<bool>();
  Future<void> approve() =>
      ActionGuard.runVoid(ActionGuard.ownerKey('fake._isActing', this), () => _approveLocked());
  Future<void> _approveLocked() async {
    if (isActing) return;
    dialogs++;
    final ok = await dialog.future; // 확인 창
    if (!ok) return;
    isActing = true;
    try {
      mutations++;
      await Future<void>.delayed(Duration.zero);
    } finally {
      isActing = false;
    }
  }
}

void _behavior() {
  setUp(ActionGuard.resetForTest);
  test('LL-3 창이 뜨기 전 연타 두 번 → 창 1 · mutation 1 · 끝나면 다시 가능 · 다른 화면 인스턴스는 서로 막지 않는다', () async {
    final a = _FakeScreen();
    final first = a.approve();
    final second = a.approve(); // 같은 프레임의 두 번째 탭
    expect(a.dialogs, 1, reason: '두 번째 진입이 창을 한 번 더 띄웠다');
    final b = _FakeScreen();
    final other = b.approve();
    expect(b.dialogs, 1, reason: '다른 화면 인스턴스까지 막으면 안 된다');
    a.dialog.complete(true);
    b.dialog.complete(false);
    await Future.wait([first, second, other]);
    expect(a.mutations, 1);
    expect(b.mutations, 0);
    expect(ActionGuard.inFlightCount, 0, reason: '잠금이 풀리지 않았다');
    expect(ActionGuard.ownerKey('g', a) == ActionGuard.ownerKey('g', b), isFalse);
    expect(ActionGuard.ownerKey('g', a) == ActionGuard.ownerKey('h', a), isFalse);
  });
}
