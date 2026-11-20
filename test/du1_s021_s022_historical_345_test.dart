// ignore_for_file: depend_on_referenced_packages
// [DU345] S022 보관된 계약서 목록 · S021 상세 렌더 관측 — 최소 표시 seam(service 주입, 호출 글자 그대로).
//   목록: 완료(PDF) · 무효(사업장 삭제) · 근무자 서명 대기 · 이름 없음, 긴 이름/사업장. 상태: 목록 · 초기 조회 실패.
//   상세: 완료(스냅샷 · 근무 내역 · 자유 조항 · PDF) · 무효(PDF 없음) · 조회 실패.
//   W 392x844 1.0 / B 320x640 2.0. 가장 가까운 바탕 대비(아이콘 글리프 제외) · 공용 판정기(DU338) · 넘침.
//   단언(기본): 예외 0 · 넘침 0 · 끊김 0 · 대비 미달 0. DU_BEFORE_OBSERVE=345 이면 끊김 · 대비는 KNOWN 으로 기록만 한다.
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/historical_contract_detail.dart';
import 'package:ALfit/models/core/historical_contract_summary.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/screens/business_admin/historical_contract_detail_screen.dart';
import 'package:ALfit/screens/business_admin/historical_contracts_screen.dart';
import 'package:ALfit/services/historical_contract_service.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';
import 'support/du_word_break.dart';
import 'support/visible_text.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '345';
const _bizLong = '[QA] 아주 긴 이름의 강남 물류센터 평택 2공장';

ContractSnapshot _snap() => ContractSnapshot(
    businessName: _bizLong, businessNumber: '000-00-00000', businessAddress: '경기도 평택시 포승읍 평택항만길 123 물류단지 B동 2층',
    ownerName: '사업주', workerName: '아주긴이름의지원자홍길동', workType: '냉장 피킹·검수 보조',
    workPlace: '경기도 평택시 포승읍 평택항만길 123 물류단지 B동 2층', isLongTerm: false,
    contractStart: '2026-10-20', contractEnd: '2026-10-20', workDays: const [], startTime: '10:00', endTime: '19:00',
    breakMinutes: 60, wage: 12000, wageType: 'hourly', paymentMethod: '계좌이체', wagePaymentDay: 10, taxDeductionType: 'none');

class _FakeHist extends HistoricalContractService {
  _FakeHist({this.fail = false});
  final bool fail;
  @override
  Future<({List<HistoricalContractSummary> contracts, String? lastDocId, bool hasMore})> getHistoricalContracts(
      {int pageSize = 20, String? lastDocId}) async {
    if (fail) throw StateError('historical cf down');
    return (
      contracts: [
        HistoricalContractSummary(contractId: 'h1', businessName: _bizLong, workerName: '아주긴이름의지원자홍길동', status: 'completed',
            createdAt: DateTime(2026, 10, 17), workerSignedAt: DateTime(2026, 10, 18), pdfAvailable: true),
        HistoricalContractSummary(contractId: 'h2', businessName: '강남 물류센터', workerName: '김민수', status: 'voided',
            createdAt: DateTime(2026, 10, 1), contractVoidedAt: DateTime(2026, 10, 5), voidReason: 'BUSINESS_DELETED', pdfAvailable: false),
        HistoricalContractSummary(contractId: 'h3', businessName: '강남 물류센터', workerName: '박지영', status: 'pending_worker',
            createdAt: DateTime(2026, 9, 20), pdfAvailable: false),
        HistoricalContractSummary(contractId: 'h4', status: 'completed', createdAt: DateTime(2026, 9, 1), pdfAvailable: true),
      ],
      lastDocId: null,
      hasMore: false,
    );
  }

  @override
  Future<HistoricalContractDetail?> getHistoricalContractById(String contractId) async {
    if (fail) throw StateError('detail cf down');
    final voided = contractId == 'h2';
    return HistoricalContractDetail(
      contractId: contractId, businessName: _bizLong, workerName: '아주긴이름의지원자홍길동',
      status: voided ? 'voided' : 'completed', isLongTerm: false, createdAt: DateTime(2026, 10, 17),
      workerSignedAt: voided ? null : DateTime(2026, 10, 18), contractVoidedAt: voided ? DateTime(2026, 10, 19) : null,
      voidReason: voided ? 'BUSINESS_DELETED' : null, pdfUrl: voided ? null : 'https://example.invalid/c.pdf',
      snapshot: _snap(),
      articles: const [
        ContractArticle(title: '[QA] 특약 사항',
            content: '[QA] 근무 중 안전화 착용을 원칙으로 하며, 냉장 구역 작업 시 지급된 방한 장비를 반드시 착용한다. '
                '작업 구역 이동은 관리자 안내에 따르고, 지게차 통로에서는 지정된 보행로만 이용한다.'),
      ],
      slots: const [
        HistoricalContractSlot(workDate: '2026-10-20', startTime: '10:00', endTime: '19:00', wage: 12000, wageType: 'hourly'),
      ],
    );
  }
}

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

Color _overWhite(Color c) => Color.alphaBlend(c, Colors.white);

Color _bgOf(Element e) {
  Color? found;
  e.visitAncestorElements((a) {
    final w = a.widget;
    Color? c;
    if (w is ButtonStyleButton) {
      c = w.style?.backgroundColor?.resolve(w.enabled ? <WidgetState>{} : {WidgetState.disabled});
      if (c == null && w is ElevatedButton) c = Theme.of(a).colorScheme.primary;
      if (c == null) return true;
    } else if (w is Container && w.decoration is BoxDecoration) {
      c = (w.decoration! as BoxDecoration).color;
    } else if (w is Container && w.color != null) {
      c = w.color;
    } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
      c = (w.decoration as BoxDecoration).color;
    } else if (w is Material && w.type != MaterialType.transparency) {
      c = w.color ?? Theme.of(a).colorScheme.surface;
    } else if (w is ColoredBox) {
      c = w.color;
    }
    if (c == null || c.a == 0) return true;
    found = _overWhite(c);
    return false;
  });
  return found ?? Colors.white;
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
  });

  const cases = [
    (k: 'list', detail: false, fail: false, id: ''),
    (k: 'listfail', detail: false, fail: true, id: ''),
    (k: 'done', detail: true, fail: false, id: 'h1'),
    (k: 'void', detail: true, fail: false, id: 'h2'),
    (k: 'detailfail', detail: true, fail: true, id: 'h1'),
  ];
  for (final c in const [(id: 'S02X-W', w: 392.0, h: 844.0, s: 1.0), (id: 'S02X-B', w: 320.0, h: 640.0, s: 2.0)]) {
    for (final st in cases) {
      testWidgets('${c.id} 보관 계약 ${st.k} ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
        await t.runAsync(vqLoadFonts);
        final overflows = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final m = d.exceptionAsString();
          if (m.contains('overflowed')) {
            overflows.add(m.split('\n').first);
          } else {
            prev?.call(d);
          }
        };
        addTearDown(() => FlutterError.onError = prev);
        try {
          t.view.physicalSize = Size(c.w, c.h);
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.reset);
          final key = GlobalKey();
          void out(String l) {
            // ignore: avoid_print
            print(l);
          }

          final svc = _FakeHist(fail: st.fail);
          await t.pumpWidget(RepaintBoundary(
            key: key,
            child: ChangeNotifierProvider<NotificationProvider>(
              create: (_) => NotificationProvider(),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: RoleTheme.businessAdminTheme,
                builder: (ctx, child) =>
                    MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
                home: st.detail
                    ? HistoricalContractDetailScreen(contractId: st.id, service: svc)
                    : HistoricalContractsScreen(service: svc),
              ),
            ),
          ));
          for (var i = 0; i < 10; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          expect(t.takeException(), isNull);
          var avoid = 0, low = 0;
          final forced = <WordBreak>[];
          final seen = <String>{};
          void dump(String tag) {
            for (final e in find.byType(RichText).evaluate()) {
              final rp = e.renderObject! as RenderParagraph;
              final s = visibleText(rp.text.toPlainText());
              if (s.isEmpty) continue;
              final self = find.byElementPredicate((x) => identical(x, e));
              final r = t.getRect(self);
              if (r.bottom < 0 || r.top > c.h || r.width == 0) continue;
              if (find.ancestor(of: self, matching: find.byType(Icon)).evaluate().isNotEmpty) continue;
              final col = rp.text.style?.color;
              final bg = _bgOf(e);
              final k = '$s@${bg.toARGB32()}@${col?.toARGB32()}';
              if (seen.contains(k)) continue;
              seen.add(k);
              for (final b in wordBreaks(rp)) {
                if (b.forced) {
                  forced.add(b);
                } else {
                  avoid++;
                  out('$tag avoidable $b');
                }
              }
              final cst = col == null ? 99.0 : _contrast(_overWhite(col), bg);
              if (cst < 4.5) {
                low++;
                out('$tag low "${s.length > 30 ? '${s.substring(0, 30)}…' : s}" color=0x${col?.toARGB32().toRadixString(16)} bg=0x${bg.toARGB32().toRadixString(16)} contrast=${cst.toStringAsFixed(2)}');
              }
            }
          }

          final tag = '${c.id}_${st.k}';
          dump(tag);
          await vqCapture(t, key, '${tag}_1_top', conditions: {'state': st.k, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
          if (!st.fail) {
            final pos = t.state<ScrollableState>(find.byType(Scrollable).first).position;
            var guard = 0;
            while (pos.pixels < pos.maxScrollExtent - 0.5 && guard++ < 30) {
              pos.jumpTo(math.min(pos.pixels + c.h * 0.5, pos.maxScrollExtent));
              await t.pump(const Duration(milliseconds: 50));
              dump('${tag}_walk');
            }
            if (guard > 0) {
              await vqCapture(t, key, '${tag}_2_end', conditions: {'state': '${st.k} 끝', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
            }
          }
          expect(t.takeException(), isNull);
          out('$tag summary overflows=${overflows.length} $overflows avoidable=$avoid forced=${forced.length} $forced low=$low beforeObs=$_beforeObs');
          out('KNOWN ${avoid == 0 ? 'ok' : 'NG'} $tag 피할 수 있는 끊김 0(실측 $avoid)');
          out('KNOWN ${low == 0 ? 'ok' : 'NG'} $tag 대비 미달 0(실측 $low)');
          expect(overflows, isEmpty, reason: '$tag 넘침');
          if (!_beforeObs) {
            expect(avoid, 0, reason: '$tag 피할 수 있는 끊김');
            expect(low, 0, reason: '$tag 대비 미달');
          }
          await t.pumpWidget(const SizedBox.shrink());
        } finally {
          FlutterError.onError = prev;
        }
      });
    }
  }
}
