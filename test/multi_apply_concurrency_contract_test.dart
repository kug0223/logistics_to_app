// [R8-P3A] 7개를 고르면 7번을 줄 세워 기다렸다.
//
//   지원 한 건은 DEV 실측 700ms 안팎이다. 다건 지원은 그걸 for/await 로
//   하나씩 보냈으니 7건이면 7.5초였다. 그런데 각 지원은 서로 독립이다 —
//   다음 호출이 앞 호출의 결과를 쓰지 않고, 정원·마감·중복은 서버
//   트랜잭션이 그 순간 다시 본다.
//
//   그래서 동시에 보내되 수를 묶었다. 실측 7건: 1→7544ms, 2→2888,
//   3→2147, 4→1553, 실패 0. 같은 TO 2건(1054ms)과 다른 TO 2건(1025ms)이
//   거의 같아 공고 문서 경합도 병목이 아니었다.
//
//   빨라진 것은 대기 시간이지 읽기·쓰기 총량이 아니다.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _src() => File(
    'lib/widgets/dialogs/apply/multi_apply_confirm_sheet.dart')
    .readAsStringSync();
String _svc() => File('lib/services/firestore/application_firestore.dart')
    .readAsStringSync();
String _fn() => File('functions/src/index.ts').readAsStringSync();

/// 주석으로 시작하는 줄만 제거한다 (문서 주석은 남는다).
String _codeOf(String raw) => raw
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// 그룹 수집 시점에도 불리므로 expect 대신 예외로 실패시킨다.
String _sliceOf(String raw, String from, String to) {
  final i = raw.indexOf(from);
  if (i < 0) throw StateError('시작 표지를 찾지 못함: $from');
  final j = raw.indexOf(to, i + from.length);
  if (j < 0) throw StateError('끝 표지를 찾지 못함: $to');
  return raw.substring(i, j);
}

String _cf(String fn, String name) {
  final i = fn.indexOf('export const $name =');
  if (i < 0) throw StateError('CF 를 찾지 못함: $name');
  final j = fn.indexOf('\nexport const ', i + 20);
  return fn.substring(i, j < 0 ? fn.length : j);
}

void main() {
  final code = _codeOf(_src());
  final f = _flat(code);
  final submit = _sliceOf(code, 'Future<void> _submit() async {', 'String _friendlyError(');
  final sf = _flat(submit);

  group('MA-1 — 직렬 대기가 사라졌다', () {
    test('MA-10 제출 루프가 항목마다 await 로 줄 세우지 않는다', () {
      // 예전: for (final meta in targets) { ... await apply ... }
      expect(sf.contains('for (final meta in targets)'), false);
      expect(sf, contains('await Future.wait(List.generate('));
    });

    test('MA-11 동시 실행 수에 상한이 있다', () {
      expect(f, contains('static const int _applyConcurrency = 4;'));
      expect(sf, contains('targets.length < _applyConcurrency ? targets.length : _applyConcurrency'));
    });

    test('MA-12 상한을 넘겨 worker 를 만들지 않는다', () {
      // 항목 수가 상한보다 적으면 그만큼만 만든다
      expect(sf, contains('List.generate( targets.length < _applyConcurrency ? targets.length : _applyConcurrency, (_) => worker(), )'));
      // 항목 배열 전체를 한꺼번에 Future.wait 하지 않는다
      expect(sf.contains('targets.map('), false);
    });

    test('MA-13 작업 분배는 공용 인덱스로만 한다 — 중복 실행 없음', () {
      expect(sf, contains('final i = nextIndex++;'));
      expect(sf, contains('if (i >= targets.length) return;'));
    });
  });

  group('MA-2 — 각 지원은 서로 독립이다 (병렬화 근거)', () {
    test('MA-20 다음 호출이 앞 호출 결과를 쓰지 않는다', () {
      final one = _sliceOf(code, 'Future<bool> _applyOne(String uid, _ItemMeta meta) {',
          'Future<void> _submit() async {');
      // payload 는 meta.item 과 widget.to 만으로 만들어진다
      expect(_flat(one), contains('final work = meta.item.work;'));
      expect(_flat(one), contains('final slot = meta.item.slot;'));
      expect(one.contains('successCount'), false);
      expect(one.contains('targets['), false);
    });

    test('MA-21 서버가 같은 순간에 다시 본다 — 트랜잭션 안 재확인', () {
      final b = _flat(_codeOf(_cf(_fn(), 'callableApplyToTO')));
      expect(b, contains('await db.runTransaction(async (tx) => {'));
      expect(b, contains('const existingInTx = await tx.get(appRef);'));
      expect(b, contains('const latestSlot = await tx.get(slotRef);'));
      expect(b, contains('const latestTO = await tx.get(toRef);'));
    });

    test('MA-22 문서 id 가 결정적이라 중복 문서가 생기지 않는다', () {
      final b = _flat(_codeOf(_cf(_fn(), 'callableApplyToTO')));
      expect(b, contains(r'${toId}_${slotId}_${resolvedWdId}_${uid}'));
      expect(b, contains('"already-exists"'));
    });
  });

  group('MA-3 — 부분 실패가 나머지를 취소하지 않는다', () {
    test('MA-30 각 항목이 자기 오류를 자기 안에서 끝낸다', () {
      expect(sf, contains('String? error;'));
      expect(sf, contains('} catch (e) { error = _friendlyError(e); }'));
    });

    test('MA-31 실패해도 루프가 다음 항목으로 넘어간다', () {
      // throw 로 worker 를 끝내지 않는다 — catch 후 계속 돈다
      final worker = _sliceOf(submit, 'Future<void> worker() async {',
          'await Future.wait(List.generate(');
      expect(worker.contains('rethrow'), false);
      expect(worker.contains('break'), false);
    });

    test('MA-32 결과는 선택 순서 그대로 남는다', () {
      // 결과를 targets[i] 의 meta 에 직접 기록한다 — 정렬이 뒤섞이지 않는다
      expect(sf, contains('final meta = targets[i];'));
      expect(sf, contains('meta.submitted = true; meta.applyError = error;'));
    });

    test('MA-33 성공 건수는 서버 응답으로만 센다', () {
      expect(sf, contains('final success = await _applyOne(user.uid, meta);'));
      expect(sf, contains("if (!success) error = '지원에 실패했습니다';"));
      expect(sf, contains('if (error == null) successCount++;'));
    });

    test('MA-34 부분 결과 화면이 유지된다', () {
      expect(f, contains('_submitDone = true;'));
      expect(f, contains("'\${targets.length}개 업무에 지원했어요.'"));
    });
  });

  group('MA-4 — 시트를 닫아도 보낸 지원은 취소되지 않는다', () {
    test('MA-40 dispose 가 남은 항목 전송을 중단시키지 않는다', () {
      // 예전에는 루프 안에서 `if (!mounted) return;` 으로 통째로 빠져나갔다
      expect(sf, contains('if (!mounted) continue;'));
      final worker = _sliceOf(submit, 'Future<void> worker() async {',
          'await Future.wait(List.generate(');
      expect(worker.contains('if (!mounted) return;'), false);
    });

    test('MA-41 화면 갱신은 mounted 일 때만 한다', () {
      final worker = _sliceOf(submit, 'Future<void> worker() async {',
          'await Future.wait(List.generate(');
      final at = worker.indexOf('setState(');
      expect(at, greaterThan(worker.indexOf('if (!mounted) continue;')));
    });

    test('MA-42 중복 제출 가드가 그대로다', () {
      expect(sf, contains('if (_isSubmitting) return;'));
      expect(sf, contains('setState(() => _isSubmitting = true);'));
    });
  });

  group('MA-5 — 갱신은 끝난 뒤 한 번뿐이다', () {
    test('MA-50 항목마다 목록을 다시 읽지 않는다', () {
      expect(sf.contains('_loadData'), false);
      expect(sf.contains('reload'), false);
      // 캐시 무효화는 서비스 안에서 메모리 조작만 한다 (네트워크 재조회 아님)
      final svc = _flat(_codeOf(_svc()));
      expect(svc, contains('clearCache(toId: toId); invalidateMyApplicationsCache(uid);'));
    });

    test('MA-51 결과는 pop 한 번으로 호출자에게 넘긴다', () {
      expect(sf, contains('MultiApplyResult(hasChanges: true, appliedCount: successCount)'));
      expect("Navigator.pop(".allMatches(submit).length, 1);
    });
  });

  group('MA-6 — 서버 권위·알림 계약 불변', () {
    test('MA-60 클라이언트가 지원을 직접 쓰지 않는다', () {
      final svc = _flat(_codeOf(_svc()));
      expect(svc, contains("httpsCallable('callableApplyToTO'"));
      expect(f.contains("collection('applications')"), false);
    });

    test('MA-61 알림 정책을 이번에 바꾸지 않았다', () {
      // newApplication 알림은 여전히 CF 안에서 지원 1건당 발송된다
      final b = _flat(_codeOf(_cf(_fn(), 'callableApplyToTO')));
      expect(b, contains('type: "newApplication"'));
      expect(b, contains('await Promise.all(allRecipients.map((adminId) =>'));
    });

    test('MA-62 성공 표시는 서버 응답 뒤에만 한다 — 선반영 없음', () {
      final worker = _sliceOf(submit, 'Future<void> worker() async {',
          'await Future.wait(List.generate(');
      final applyAt = worker.indexOf('await _applyOne(');
      final markAt = worker.indexOf('meta.submitted = true');
      expect(applyAt, greaterThan(-1));
      expect(applyAt, lessThan(markAt));
    });
  });
}
