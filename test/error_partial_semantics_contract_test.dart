// [R5-ERROR-PARTIAL-R0] 모르는 것을 없다고 말하지 않는다
//
// 이 파일이 고정하는 것:
//
//   INV-1  없는 필드 하나가 핵심 동작을 죽이지 않는다
//   INV-2  값을 지어내지 않는다 (추론 금지)
//   INV-3  조회 실패는 "없음"과 다른 화면이다
//   INV-4  모르는 상태에서 그 전제를 쓰는 action을 열지 않는다
//   INV-5  실패 화면에는 복구 경로가 있다 (자동 폴링 없이)
//   INV-6  권한 없음과 조회 실패는 다른 화면이다

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _sliceOf(String raw, String from, String to) {
  final a = raw.indexOf(from);
  if (a < 0) throw StateError('$from 를 찾지 못함');
  final b = raw.indexOf(to, a + from.length);
  if (b < 0) throw StateError('$to 를 찾지 못함');
  return raw.substring(a, b);
}

const _cfPath = 'functions/src/index.ts';
const _attDialog = 'lib/screens/business_admin/dialogs/attendance_status_dialog.dart';
const _payroll =
    'lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart';

void main() {
  final cfRaw = _src(_cfPath);
  final cf = _codeOf(cfRaw);
  final att = _codeOf(_src(_attDialog));
  final pay = _codeOf(_src(_payroll));

  group('INV-1 — 없는 필드가 출근을 죽이지 않는다 (§1·§5·§6)', () {
    test('01 undefined를 걸러 내는 공통 helper가 있다', () {
      final f = _flat(_codeOf(_sliceOf(cfRaw,
          'function srvOmitUndefined(', 'return out;')));
      expect(f, contains('if (v !== undefined) out[k] = v;'));
    });

    test('02 두 출근 writer 모두 그것을 지난다', () {
      expect(cf, contains('tx.set(ref, srvOmitUndefined(docData));'));
      expect(cf, contains(
          'await db.collection("attendance").doc(docId).set(srvOmitUndefined({'));
      expect('srvOmitUndefined('.allMatches(cf).length, 3,
          reason: '정의 1 + 단건 출근 1 + 일괄 출근 1');
    });

    test('03 snapshot 필드가 여전히 optional이다', () {
      // 값이 없을 수 있다는 사실 자체는 그대로 둔다 — 지어내지 않는다.
      expect(cf, contains(
          'snapshotWageType: typeof appData.wageType === "string" ? appData.wageType : undefined'));
    });

    test('04 전역 ignoreUndefinedProperties로 덮지 않았다 (§5)', () {
      // 전역으로 켜면 의도치 않은 undefined도 조용히 사라진다 —
      // 이 Phase가 없애려는 바로 그 은폐다. (주석 언급은 허용, 설정은 금지)
      expect(cf, isNot(contains('settings({ignoreUndefinedProperties')));
      expect(cf, isNot(contains('ignoreUndefinedProperties: true')));
    });
  });

  group('INV-2 — 값을 지어내지 않는다 (§3·§4)', () {
    test('05 출근 snapshot 경로가 값을 지어내지 않는다', () {
      // 이 Phase가 고친 자리는 출근 snapshot이다. 없으면 쓰지 않고,
      // 급여 계산은 기존대로 WorkDetail에서 해상도한다.
      final ci = _flat(_codeOf(_sliceOf(cfRaw,
          '// 체크인 시점 임금 스냅샷', 'tx.set(ref, srvOmitUndefined(docData));')));
      expect(ci, isNot(contains('?? "hourly"')));
      expect(ci, isNot(contains('?? "daily"')));
      expect(ci, contains(': undefined'));
    });

    test('05b [잔존] 지원 생성은 아직 wageType을 기본값으로 만든다', () {
      // [OPEN-R5R0-APPLY-WAGETYPE-DEFAULT] callableApplyToTO가
      //   `data.wageType ?? "hourly"`로 보상 모델을 지어낸다. 이 Phase의
      //   범위(출근 크래시)가 아니라 생성 semantics이므로 손대지 않았고,
      //   사라지면 이 테스트가 알려 준다.
      expect(cf, contains('const wageType = data.wageType ?? "hourly";'),
          reason: '고쳐졌다면 이 테스트를 지우고 잔존 목록에서 빼야 한다');
    });

    test('06 소비자는 부재를 "다른 출처에서 해상도"로 읽는다', () {
      final wc = _codeOf(
          _src('lib/screens/business_admin/dialogs/wage_confirm_dialog.dart'));
      // snapshot이 있을 때만 override — 없으면 WorkDetail 해상도 결과를 쓴다.
      expect(wc, contains('if (attendance.snapshotWageType != null) {'));
      expect(wc, contains('wageType = attendance.snapshotWageType!;'));
    });

    test('07 클라이언트 모델도 null이면 쓰지 않는다', () {
      final am = _src('lib/models/core/attendance_model.dart');
      expect(am, contains("if (snapshotWageType != null)'snapshotWageType'"));
    });
  });

  group('INV-3 — 실패는 "없음"과 다른 화면이다 (§16·§22)', () {
    test('08 당일명단: 실패 상태를 따로 들고 있다', () {
      expect(att, contains('String? _loadError;'));
      final c = _flat(_sliceOf(att, '} catch (e) {', 'ToastHelper.showError'));
      expect(c, contains("_loadError = '근무자 명단을 불러오지 못했습니다.'"));
    });

    test('09 당일명단: 빈 상태와 실패 상태가 갈라진다', () {
      final b = _flat(_sliceOf(att, "child: _isLoading", '_buildContent(theme),'));
      expect(b, contains('_loadError != null ? _buildErrorState()'));
      expect(b, contains('_confirmedWorkers.isEmpty ? _buildEmptyState()'));
    });

    test('10 당일명단: 실패 문구가 "없음"을 부정한다', () {
      final e = _flat(_sliceOf(att, 'Widget _buildErrorState() {', '\n  }'));
      expect(e, contains('근무자가 없다는 뜻이 아닙니다'));
      // 빈 상태 문구를 재사용하지 않는다.
      expect(e, isNot(contains('확정된 근무자가 없습니다')));
    });

    test('11 급여: 실패 상태를 따로 들고 있다', () {
      expect(pay, contains('String? _loadError;'));
      expect(pay, contains("_loadError = '급여 현황을 불러오지 못했습니다.'"));
    });

    test('12 급여: 실패 시 금액·건수를 그리지 않는다', () {
      final b = _flat(_sliceOf(pay,
          "? const LoadingWidget(message: '급여 현황 불러오는 중...')",
          ': Column(children: ['));
      expect(b, contains('_loadError != null'));
      expect(b, contains('미지급 건이 없다는 뜻이 아닙니다'));
    });

    test('13 재시도 시작 시 실패 표시를 지운다', () {
      expect(att, contains('_loadError = null;'));
      expect(pay, contains('if (_loadError != null) setState(() => _loadError = null);'));
    });
  });

  group('INV-4 — 모르는 상태에서 action을 열지 않는다 (§18)', () {
    test('14 당일명단: 하단 바가 실패 시 숨는다', () {
      expect(att, contains('if (!_isLoading && _loadError == null)\n            _buildBottomBar(theme)'));
    });

    test('15 당일명단: 선택 확인 바도 숨는다', () {
      expect(att, contains(
          'if (!_isLoading && _loadError == null && _selectedIds.isNotEmpty)'));
    });
  });

  group('INV-5 — 복구 경로 (§30)', () {
    test('16 두 화면 모두 다시 시도를 제공한다', () {
      for (final s in [att, pay]) {
        expect(_flat(s), contains("label: const Text('다시 시도')"));
      }
    });

    test('17 자동 폴링·listener를 늘리지 않았다', () {
      for (final s in [att, pay]) {
        expect(s, isNot(contains('Timer.periodic')));
      }
    });
  });

  group('INV-6 — 권한 없음 ≠ 조회 실패 (§17)', () {
    test('18 급여 화면이 둘을 다른 화면으로 말한다', () {
      expect(pay, contains("title: '접근 권한이 없습니다'"));
      expect(pay, contains("subtitle: '급여 관리 권한이 있는 관리자에게 문의하세요.'"));
      // 같은 build 분기 안에서 권한이 로딩·실패보다 앞이다.
      final branch = _sliceOf(pay,
          "title: '접근 권한이 없습니다'", ': Column(children: [');
      expect(branch, contains("_isLoading"));
      expect(branch, contains('_loadError != null'));
      expect(branch.indexOf('_isLoading'),
          lessThan(branch.indexOf('_loadError != null')));
    });
  });

  group('회귀 — 이미 하드닝된 곳을 되돌리지 않았다', () {
    test('19 근로자 Home의 도메인별 실패 보존', () {
      final uh = _codeOf(_src('lib/screens/user/user_home_screen.dart'));
      expect(uh, contains('_homeLoadFailed = true;'));
      expect(uh, contains('if (appsErr == null) {'));
    });

    test('20 관리자 Home의 수치 미표시 원칙', () {
      final ah = _src('lib/screens/business_admin/business_admin_home_screen.dart');
      expect(ah, contains('error 상태로 전환 (수치 표시 금지)'));
    });
  });
}
