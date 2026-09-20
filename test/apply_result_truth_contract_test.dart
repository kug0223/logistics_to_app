// [R8-P3A.1] 대답을 못 들은 것을 "지원 실패"라고 말하고 있었다.
//
//   지원 서비스는 결과를 bool 하나로 돌려줬다. 그래서 "정원이 찼다"와
//   "타임아웃이라 결과를 모른다"가 같은 false 로 합쳐졌고, 화면은 둘 다
//   '지원에 실패했습니다'라고 말했다.
//
//   그런데 타임아웃은 지원이 **기록된 뒤** 응답만 유실된 것일 수 있다.
//   DEV 실측: 지원 성공 직후 canonical 재조회가 그 지원을 바로 찾아낸다
//   (Firestore 쿼리는 strong consistency — polling 불필요).
//
//   그래서 결과를 넷으로 나눈다 — 새로 기록됨 / 이미 지원중 / 서버가 거절 /
//   모름. 모름은 canonical 상태를 되물어 정정하고, 그래도 모르면 모른다고 한다.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _svc() =>
    File('lib/services/firestore/application_firestore.dart').readAsStringSync();
String _wrap() => File('lib/services/firestore_service.dart').readAsStringSync();
String _multi() => File('lib/widgets/dialogs/apply/multi_apply_confirm_sheet.dart')
    .readAsStringSync();
String _single() =>
    File('lib/widgets/dialogs/apply/apply_work_dialog.dart').readAsStringSync();
String _long() => File('lib/widgets/dialogs/apply/longterm_apply_sheet.dart')
    .readAsStringSync();
String _fn() => File('functions/src/index.ts').readAsStringSync();

/// 주석으로 시작하는 줄(`//`·`///`)을 지운다 — 표지는 코드에서만 찾는다.
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
  final svc = _codeOf(_svc());
  final sf = _flat(svc);
  final multi = _codeOf(_multi());
  final mf = _flat(multi);
  final single = _codeOf(_single());
  final long = _codeOf(_long());

  group('AR-1 — 성공 계약이 그대로다', () {
    test('AR-10 서버 success 는 success 로 남는다', () {
      expect(sf, contains('return ApplyResult.success( applicationId: data[\'applicationId\'] as String?, isReactivation: isReactivation, )'));
    });

    test('AR-11 재지원도 성공이다', () {
      expect(sf, contains('isReactivation: isReactivation'));
      expect(sf, contains('bool get isNewlyApplied => outcome == ApplyOutcome.success;'));
    });
  });

  group('AR-2 — 서버가 말한 이유는 보존된다', () {
    test('AR-20 도메인 코드는 불확실 목록에 없다', () {
      final set = _sliceOf(svc, 'const Set<String> _kApplyUncertainCodes = {', '};');
      for (final domain in [
        'already-exists', 'failed-precondition', 'permission-denied',
        'invalid-argument', 'resource-exhausted', 'not-found', 'unauthenticated',
      ]) {
        expect(set.contains("'$domain'"), false, reason: domain);
      }
    });

    test('AR-21 도메인 실패는 서버 문장을 그대로 들고 간다', () {
      expect(sf, contains('return ApplyResult.failed(msg, code: e.code);'));
      expect(sf, contains("final msg = e.message ?? '지원 중 오류가 발생했습니다.';"));
    });

    test('AR-22 already-exists 는 실패가 아니라 "이미 지원중"이다', () {
      expect(sf, contains("if (e.code == 'already-exists') { return ApplyResult.alreadyApplied(msg); }"));
      expect(sf, contains('bool get isApplied => outcome == ApplyOutcome.success || outcome == ApplyOutcome.alreadyApplied;'));
    });

    test('AR-23 보내지도 못한 경우는 UNKNOWN 이 아니다', () {
      expect(sf, contains("return ApplyResult.failed(e.message, code: 'offline');"));
      expect(_flat(_codeOf(_wrap())),
          contains("return ApplyResult.failed('공고 정보를 찾을 수 없어 지원할 수 없습니다', code: 'no-to-id');"));
    });
  });

  group('AR-3 — 전송 불확실은 따로 센다', () {
    test('AR-30 불확실 코드는 전송 계층 것뿐이다', () {
      final set = _sliceOf(svc, 'const Set<String> _kApplyUncertainCodes = {', '};');
      for (final c in ['deadline-exceeded', 'unavailable', 'cancelled', 'internal', 'unknown']) {
        expect(set, contains("'$c'"), reason: c);
      }
    });

    test('AR-31 타임아웃·정체불명 예외는 UNKNOWN 이다', () {
      expect(sf, contains("on TimeoutException catch (e)"));
      expect(sf, contains("return ApplyResult.unknown('지원 결과를 확인하지 못했어요.', code: 'timeout');"));
      expect(sf, contains("return ApplyResult.unknown('지원 결과를 확인하지 못했어요.', code: 'unknown');"));
    });

    test('AR-32 서버는 알림 실패를 지원 실패로 만들지 않는다', () {
      final body = _codeOf(_cf(_fn(), 'callableApplyToTO'));
      expect(_flat(body), contains('} catch (notifErr) { console.error("⚠️ [applyToTO] newApplication 알림 실패 (지원은 완료됨):", notifErr); }'));
      expect(_flat(body), contains('return {success: true, applicationId: complexId, isReactivation};'));
    });
  });

  group('AR-4 — 모를 때는 canonical 상태를 되묻는다', () {
    test('AR-40 문서 id 를 계산해 맞추지 않는다 — 관계로 찾는다', () {
      expect(sf, contains('bool hasLandedApplication( List<ApplicationModel> mine, { required String toId, String? slotId, required String workType, })'));
      expect(svc.contains(r"'${toId}_"), false);
      expect(multi.contains(r"'${widget.to.id}_"), false);
    });

    test('AR-41 되물을 때 캐시를 쓰지 않는다', () {
      final reader = _sliceOf(svc,
          'Future<List<ApplicationModel>> getMyApplicationsForTOFresh(String toId) async {',
          'Future<ApplyResult> applyToTO({');
      expect(_flat(reader), contains("httpsCallable('callableGetMyApplications'"));
      expect(_flat(reader), contains("'toId': toId,"));
      expect(reader.contains('_myApplicationsCache'), false);
    });

    test('AR-42 찾으면 SUCCESS 로 정정한다', () {
      expect(mf, contains('meta.outcome = ApplyOutcome.success;'));
      expect(_flat(single), contains('applied = applied.reconciledAsApplied();'));
    });

    test('AR-43 살아있는 상태만 인정한다', () {
      final m = _sliceOf(svc, 'bool hasLandedApplication(', 'Future<ApplyResult> applyToTO({');
      expect(_flat(m), contains('const live = [ AppStatus.pending, AppStatus.contractPending, AppStatus.confirmed, ];'));
      expect(_flat(m), contains('live.contains(app.status)'));
    });
  });

  group('AR-5 — 못 찾으면 실패라고 하지 않는다', () {
    test('AR-50 못 찾은 항목은 UNKNOWN 으로 남긴다', () {
      final rec = _sliceOf(multi, 'final unknowns = targets.where((m) => m.applyUnknown).toList();',
          'if (!mounted) return;');
      expect(_flat(rec), contains('if (!landed) continue;'));
      expect(rec.contains('ApplyOutcome.failed'), false);
    });

    test('AR-51 재확인 자체가 실패해도 UNKNOWN 그대로다', () {
      final rec = _sliceOf(multi, 'final unknowns = targets.where((m) => m.applyUnknown).toList();',
          'if (!mounted) return;');
      final catchAt = rec.indexOf('} catch (e) {');
      expect(catchAt, greaterThan(-1));
      // catch 블록 안에서는 어떤 항목의 결과도 바꾸지 않는다
      final catchBody = rec.substring(catchAt);
      expect(catchBody.contains('meta.'), false);
      expect(catchBody.contains('ApplyOutcome.'), false);
    });

    test('AR-52 화면이 UNKNOWN 을 실패로 그리지 않는다', () {
      expect(mf, contains("badgeText = '확인 필요';"));
      expect(mf, contains('지원 결과를 확인하지 못했어요'));
      expect(mf, contains('지원이 접수됐을 수 있으니 내 지원 목록에서 확인해주세요.'));
    });

    test('AR-53 UNKNOWN 이 있으면 시트를 닫지 않는다', () {
      expect(mf, contains('if (targets.every((m) => m.applyOk)) {'));
    });
  });

  group('AR-6 — 다건 결과는 서로 독립이다', () {
    test('AR-60 항목별 결과를 따로 담는다', () {
      expect(mf, contains('meta.outcome = result.outcome;'));
      expect(mf, contains('meta.applyError = result.isApplied ? null : result.message;'));
    });

    test('AR-61 성공/이미지원/실패/미확인을 각각 센다', () {
      expect(mf, contains('final okCount = targets.where((m) => m.applyOk).length;'));
      expect(mf, contains('final unknownCount = targets.where((m) => m.applyUnknown).length;'));
      expect(mf, contains('final failCount = targets.length - okCount - unknownCount;'));
    });

    test('AR-62 실패 목록에 미확인 건을 섞지 않는다', () {
      expect(mf, contains('.where((m) => !m.applyOk && !m.applyUnknown)'));
    });

    test('AR-63 새로 기록된 건만 지원 건수로 센다', () {
      expect(mf, contains('if (result.isNewlyApplied) successCount++;'));
      expect(mf, contains('targets.where((m) => m.outcome == ApplyOutcome.success).length'));
    });
  });

  group('AR-7 — 단건과 다건이 같은 계약을 쓴다', () {
    test('AR-70 서비스가 ApplyResult 를 돌려준다', () {
      expect(sf, contains('Future<ApplyResult> applyToTO({'));
      expect(_flat(_codeOf(_wrap())), contains('Future<ApplyResult> applyToTOWithWorkType({'));
    });

    test('AR-71 bool 로 받는 호출자가 없다', () {
      for (final src in [single, long, multi]) {
        expect(RegExp(r'final\s+success\s*=\s*await\s+\S*applyToTO').hasMatch(src), false);
      }
    });

    test('AR-72 단건도 UNKNOWN 을 되묻는다', () {
      expect(_flat(single), contains('if (applied.isUnknown)'));
      expect(_flat(single), contains('getMyApplicationsForTOFresh(to.id)'));
    });

    test('AR-73 장기 시트도 UNKNOWN 을 실패로 말하지 않는다', () {
      expect(_flat(long), contains('if (result.isUnknown) anyUnknown = true;'));
      expect(_flat(long), contains('일부 지원 결과를 확인하지 못했어요.'));
    });
  });

  group('AR-8 — Toast 책임이 UI 로 모였다', () {
    test('AR-80 서비스는 더 이상 Toast 를 띄우지 않는다', () {
      final apply = _sliceOf(svc, 'Future<ApplyResult> applyToTO({',
          'Future<void> rejectApplication(String applicationId,');
      expect(apply.contains('ToastHelper'), false);
    });

    test('AR-81 다건 시트는 항목별 인라인으로 말한다 — Toast 폭주 없음', () {
      final submit = _sliceOf(multi, 'Future<void> _submit() async {', 'String _friendlyError(');
      // 성공 요약 Toast 하나만 남는다
      expect('ToastHelper.'.allMatches(submit).length, 1);
      expect(_flat(submit), contains('ToastHelper.showSuccess(msg);'));
    });
  });

  group('AR-9 — P3A 구조가 유지된다', () {
    test('AR-90 동시성 상한 4 가 그대로다', () {
      expect(mf, contains('static const int _applyConcurrency = 4;'));
      expect(mf, contains('targets.length < _applyConcurrency ? targets.length : _applyConcurrency'));
    });

    test('AR-91 시트를 닫아도 남은 항목을 계속 보낸다', () {
      expect(mf, contains('if (!mounted) { meta.outcome = result.outcome; continue; }'));
    });

    test('AR-92 정상 성공 경로에는 읽기를 더하지 않는다', () {
      final submit = _sliceOf(multi, 'Future<void> _submit() async {', 'String _friendlyError(');
      final recAt = submit.indexOf('getMyApplicationsForTOFresh');
      final guardAt = submit.indexOf('if (unknowns.isNotEmpty) {');
      expect(guardAt, greaterThan(-1));
      expect(guardAt, lessThan(recAt), reason: 'UNKNOWN 이 있을 때만 읽는다');
    });
  });

  group('AR-10 — 선반영 없음', () {
    test('AR-100 결과는 서버 응답 뒤에만 기록한다', () {
      final submit = _sliceOf(multi, 'Future<void> _submit() async {', 'String _friendlyError(');
      expect(submit.indexOf('await _applyOne('), lessThan(submit.indexOf('meta.outcome = result.outcome;')));
    });

    test('AR-101 클라이언트가 성공을 지어내지 않는다', () {
      // 재확인이 찾았을 때만 success 로 바꾼다
      final rec = _sliceOf(multi, 'final unknowns = targets.where((m) => m.applyUnknown).toList();',
          'if (!mounted) return;');
      final landedAt = rec.indexOf('if (!landed) continue;');
      final successAt = rec.indexOf('meta.outcome = ApplyOutcome.success;');
      expect(landedAt, lessThan(successAt));
    });
  });
}
