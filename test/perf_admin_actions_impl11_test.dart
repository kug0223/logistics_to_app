// ignore_for_file: depend_on_referenced_packages
// [PERF/정합성 impl_11] 판정291 — F291-C11 이체 일괄 stale 가드 · P12 대시보드 처리 중 표시/첫 await 전 잠금 ·
//   L53 공고 수정 슬롯 읽기 1회 · 공고 생성 사전 읽기 병렬 · L52 초대 알림 비대기 · 해당 사업장만 재조회 ·
//   L54 엑셀 이름 캐시 재사용 · 인코딩 isolate · (공유 직후 임시파일 삭제 타이밍은 **그대로**).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/utils/payroll_excel_helper.dart';
import 'package:ALfit/widgets/common/app_batch_action_bar.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options =>
      const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

String _code(String p) => File(p)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

String _bodyOf(String src, String sig) {
  final at = src.indexOf(sig);
  expect(at, isNot(-1), reason: '$sig 가 없다');
  final m = RegExp(r'\)\s*(async\s*)?\{').firstMatch(src.substring(at));
  final open = at + m!.end - 1;
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(at, i + 1);
    }
  }
  return src.substring(at);
}

/// LATE-LOCK 판정: `if (_flag) return;` 로 재진입을 막는 async 함수가 그 플래그를 **첫 await 뒤에야** 켜는 곳.
List<String> _lateLocks(String path) {
  final src = _code(path);
  final hits = <String>[];
  for (final m in RegExp(r'Future<\w*>\s+(_\w+)\([^)]*\)\s*async\s*\{').allMatches(src)) {
    final body = _bodyOf(src, src.substring(m.start, m.end - 1));
    final g = RegExp(r'if\s*\(\s*(_\w+)\s*(?:\|\|[^)]*)?\)\s*return\s*;').firstMatch(body);
    if (g == null) continue;
    final flag = g.group(1)!;
    final set = RegExp('${RegExp.escape(flag)}\\s*=\\s*true').firstMatch(body);
    final aw = body.indexOf('await ');
    if (set != null && aw >= 0 && aw < set.start) hits.add('${m.group(1)} flag=$flag');
  }
  return hits;
}

const _dash = 'lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart';
const _members = 'lib/screens/business_admin/member_management_screen.dart';
const _memberSvc = 'lib/services/member_service.dart';
const _edit = 'lib/screens/business_admin/to_management/edit_to_screen.dart';
const _toFs = 'lib/services/firestore/to_firestore.dart';
const _create = 'lib/screens/business_admin/to_management/create_to_screen.dart';
const _excel = 'lib/utils/payroll_excel_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  // ── F291-C11 ────────────────────────────────────────────────────────
  group('[F291-C11] 일괄 이체 stale 가드 — 단건과 같은 기준', () {
    test('C11-1 입구 + 두 확인 창 뒤 쓰기 직전에 _blockStaleWrite · 현재 목록 세대 · 선택 대상 그대로', () {
      final b = _flat(_bodyOf(_code(_dash), 'Future<void> _markBatch('));
      final entry = b.indexOf('if (_blockStaleWrite()) return;');
      final firstAwait = b.indexOf('await ');
      expect(entry, allOf(greaterThan(-1), lessThan(firstAwait)), reason: '입구');
      final note = b.indexOf('await _showTransferNoteDialog()');
      final write = b.indexOf('await _payService.markTransferredBatch(');
      final second = b.indexOf('if (_blockStaleWrite()) return;', note);
      expect(second, allOf(greaterThan(note), lessThan(write)), reason: '쓰기 직전');
      final gen = b.indexOf('if (gen0 != _recordsGen || !setEquals(_selectedIds, idSet))');
      expect(gen, allOf(greaterThan(note), lessThan(write)), reason: '창을 보는 사이 목록·선택이 바뀌면 쓰지 않는다');
      expect(b.contains('attendanceIds: ids,'), isTrue, reason: '확인 창에 보인 대상 = 보내는 대상');
      expect(b.contains('final ids = _selectedIds.toList(growable: false);'), isTrue, reason: '입구에서 한 번만 잡는다');
      expect(RegExp(r'attendanceIds:\s*_selectedIds').hasMatch(b), isFalse);
    });

    test('C11-2 목록 교체가 세대를 올린다', () {
      final load = _flat(_bodyOf(_code(_dash), 'Future<void> _load({'));
      expect(load.contains('_allRecords = allRecs; _recordsGen++;'), isTrue);
    });
  });

  // ── P12 ─────────────────────────────────────────────────────────────
  group('[P12] 첫 await 전 잠금 · 처리 중 표시', () {
    test('P12-1 재발 방지 — 대시보드·멤버 관리의 행동 함수에 늦은 잠금 0', () {
      expect(_lateLocks(_dash), isEmpty);
      expect(_lateLocks(_members), isEmpty);
      final cancel = _flat(_bodyOf(_code(_dash), 'Future<void> _cancelTransfer('));
      final guard = cancel.indexOf('if (_isCancelling) return;');
      final lock = cancel.indexOf('setState(() => _isCancelling = true);');
      expect(guard, greaterThan(-1), reason: '이체 취소는 재진입 검사 자체가 없었다');
      expect(lock, allOf(greaterThan(guard), lessThan(cancel.indexOf('await '))),
          reason: '첫 await(사유 창) 전에 잠근다');
    });

    test('P12-2 처리 중에는 행동 버튼이 잠기고 진행 표시가 보인다', () {
      final d = _flat(_code(_dash));
      for (final s in [
        "onAction: _selectedIds.isNotEmpty && _selectedNet > 0 && !_isTransferring ? _markBatch : null,",
        'busy: _isTransferring,',
        'onMarkTransferred: _outstandingWritable && !_isTransferring',
        'onMarkTransferred: !_batchMode && !_isTransferring ?',
        'onApprove: _isTransferring ? null : () => _approveChangeRequest(req),',
        'onReject: _isTransferring ? null : () => _rejectChangeRequest(req),',
        'req.isPending && !_isTransferring ? () => _approveSettlement(req)',
        'req.isPending && !_isTransferring ? () => _rejectSettlement(req)',
        'req.isApproved && !_isTransferring ? () => _processSettlement(req)',
        'req.isApproved && !_isTransferring ? () => _cancelApprovedSettlement(req)',
        'if (_isTransferring) const LinearProgressIndicator(minHeight: 2),',
      ]) {
        expect(d.contains(s), isTrue, reason: s);
      }
    });

    testWidgets('P12-3 일괄 바 busy — 실행 버튼 비활성 · 아이콘 자리 진행 표시 · 선택 조작 잠금', (t) async {
      var acted = 0;
      Future<void> pump(bool busy) => t.pumpWidget(MaterialApp(
            home: Scaffold(
              body: AppBatchActionBar(
                selectedCount: 2,
                selectedAmount: 1000,
                onSelectAll: () {},
                onDeselectAll: () {},
                onAction: () => acted++,
                busy: busy,
              ),
            ),
          ));
      await pump(true);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.tap(find.byWidgetPredicate((w) => w is ElevatedButton));
      expect(acted, 0);
      final choices = t.widgetList<TextButton>(find.byType(TextButton)).toList();
      expect(choices.every((b) => b.onPressed == null), isTrue);
      await pump(false);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await t.tap(find.byWidgetPredicate((w) => w is ElevatedButton));
      expect(acted, 1, reason: '기본(busy:false)은 예전과 같다');
    });
  });

  // ── L53 ─────────────────────────────────────────────────────────────
  group('[L53] 공고 수정·생성 사전 읽기', () {
    test('L53-1 저장 흐름의 슬롯 완전 읽기 1회 → 두 갱신에 같은 목록 · 두 writer 는 받은 목록이 있으면 다시 읽지 않는다', () {
      final e = _code(_edit);
      expect('getSlotsForWrite(widget.to.id)'.allMatches(e).length, 1);
      expect('preloadedSlots: slots,'.allMatches(e).length, 2);
      final t = _code(_toFs);
      for (final sig in ['Future<void> updateSlotsDeadlines(', 'Future<void> updateSlotsPublishSettings(']) {
        final b = _bodyOf(t, sig);
        expect(b.contains('final slots = preloadedSlots ?? await getSlots(toId, requireComplete: true);'), isTrue,
            reason: sig);
      }
      // 저장 흐름이 넘기는 목록도 writer 와 같은 완전 읽기여야 한다(부분 파싱 목록을 넘기면 PARTIAL WRITE).
      expect(t.contains('Future<List<SlotModel>> getSlotsForWrite(String toId) => getSlots(toId, requireComplete: true);'),
          isTrue);
    });

    test('L53-2 공고 생성 사전 점검 — 등록증·날인·업무·템플릿 한 번에 · 날인 규칙 하나', () {
      final c = _flat(_code(_create));
      expect('_employerSealOf('.allMatches(c).length, 3, reason: '정의 1 + 두 경로 호출');
      expect(c.contains("collection('users') .doc(biz.ownerId)"), isFalse, reason: '인라인 날인 읽기가 남았다');
      final re = _flat(_bodyOf(_code(_create), 'Future<void> _reCheckPrerequisites('));
      expect(re.contains('final results = await Future.wait(['), isTrue);
      expect(re.indexOf('BusinessPostingReadiness.hasLicenseForBusiness'),
          lessThan(re.indexOf('if (!mounted) return;')), reason: '등록증을 업무·템플릿 뒤에 따로 기다리지 않는다');
    });

    test('L53-3 [ROOT-FUTURE] 공고 수정 로드 — 먼저 출발한 슬롯 조회의 실패가 새지 않는다', () {
      expect(_code(_edit).contains('slotsFuture?.ignore();'), isTrue);
    });
  });

  // ── L52 ─────────────────────────────────────────────────────────────
  group('[L52] 멤버 초대', () {
    test('L52-1 초대 알림 callable 을 기다리지 않고 실패는 로그만', () {
      final b = _flat(_bodyOf(_code(_memberSvc), 'Future<void> sendInvitation('));
      expect(b.contains('await _firestoreService.createNotification('), isFalse);
      expect(b.contains('unawaited(_firestoreService .createNotification('), isTrue);
      expect(b.contains('onError: (Object e) {'), isTrue);
      expect(b.indexOf('await ref.set(invMap);'), lessThan(b.indexOf('createNotification')),
          reason: '초대 문서 저장은 그대로 기다린다');
    });

    test('L52-2 초대·초대 취소 뒤 그 사업장만 다시 읽는다 · 권한 변경 경로(C02)는 그대로', () {
      final s = _code(_members);
      expect(_flat(_bodyOf(s, 'Future<void> _invite(')).contains('unawaited(_reloadSection(businessId))'), isTrue);
      expect(_flat(_bodyOf(s, 'Future<void> _cancelInvitation(')).contains('unawaited(_reloadSection(invitation.businessId))'),
          isTrue);
      final r = _flat(_bodyOf(s, 'Future<void> _reloadSection('));
      expect(r.contains('getMembers)(businessId)'), isTrue);
      expect(r.contains('getSentPendingInvitations)(businessId)'), isTrue);
      expect(r.contains('businessesByIds'), isFalse, reason: '사업장 이름 전체를 다시 읽지 않는다');
      // 권한 변경(C02 · 별도 CORRECTION 셀)은 손대지 않았다 — 여전히 전체 _load().
      expect(_flat(_bodyOf(s, 'Future<void> _editPermissions(')).contains('_load();'), isTrue);
    });
  });

  // ── L54 ─────────────────────────────────────────────────────────────
  group('[L54] 엑셀 내보내기', () {
    test('L54-1 (동작) 화면이 준 이름·번호가 있으면 사용자 문서를 다시 읽지 않는다', () async {
      // 받은 이름이 있으면 서버 조회(getUsersBatch)를 부르지 않는다 — 시험 환경에서 부르면 플러그인 오류로 실패한다.
      final rec = AttendanceModel(
        id: 'a1', applicationId: 'app1', userId: 'u1', businessId: 'b1', businessName: 'b',
        workDate: DateTime.utc(2026, 11, 20), workType: 'x', status: 'present',
        wageStatus: AttendanceModel.wageConfirmed, adminConfirmed: true, createdAt: DateTime.utc(2026, 11, 20),
      );
      final plan = await PayrollExcelHelper.prepareTransferPlan(
        records: [rec],
        businessId: 'b1',
        profiles: (names: {'u1': '김근로'}, personNos: {'u1': 'P-001'}),
      );
      // 화면이 준 이름이 계획에 그대로 실린다(다시 읽었다면 시험 환경 조회 결과로 이름이 비었다).
      final names = [
        ...plan.rows.map((r) => r.workerName),
        ...plan.blocked.map((r) => r.workerName),
        ...plan.notApplicable.map((r) => r.workerName),
      ];
      expect(names, contains('김근로'));
    });

    test('L54-2 대시보드 캐시는 모든 근로자 이름이 있을 때만 쓴다 · 두 내보내기에 연결', () {
      final d = _code(_dash);
      final f = _flat(_bodyOf(d, 'WorkerProfiles? _cachedProfilesFor('));
      expect(f.contains('if (c == null || name == null) return null;'), isTrue, reason: '빠진 이름을 빈 칸으로 내보내지 않는다');
      expect(_flat(d).contains('knownProfiles: _cachedProfilesFor(allFilteredRecs),'), isTrue);
      expect(_flat(d).contains('profiles: _cachedProfilesFor(pendingRecs),'), isTrue);
    });

    test('L54-3 인코딩은 isolate 우선 · 실패 시 메인 · 공유 직후 삭제 타이밍은 그대로(판정291 §6)', () {
      final x = _flat(_bodyOf(_code(_excel), 'static Future<void> _shareExcel('));
      // [impl_19] 같은 규칙이 공용 부품 `OffMain.encodeExcel` 로 옮겨졌다(isolate 우선 · 실패/초과 시 이 isolate) —
      //   그 부품의 실패 경로는 test/perf_offmain_export_impl19_test.dart F1–F3 이 고정한다.
      expect(x.contains("final List<int>? bytes = await OffMain.encodeExcel(excel, tag: 'payrollXlsx');"), isTrue);
      expect(_code('lib/utils/off_main.dart').contains("debugLastPath = 'main-fallback';"), isTrue, reason: 'fallback');
      final share = x.indexOf('await Share.shareXFiles(');
      final del = x.indexOf('await file.delete();');
      expect(share, greaterThan(-1));
      expect(del, greaterThan(share), reason: '공유 뒤 finally 삭제(기존) — 이번에 바꾸지 않는다');
      expect(x.contains('} finally { await file.delete(); }'), isTrue);
    });
  });
}
