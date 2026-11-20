// ignore_for_file: depend_on_referenced_packages
// [DU331] S030/S031 업무 카드 행동(수정 · 삭제) — 소급 4 채택 '수정 action brand/brandSurface' + _ActionButton 48 · 비겹침 · 확장부 hit.
//   TOWorkDetailCard 를 직접 띄운다(to_work_detail_card_responsive_test 와 같은 자료). W 360x780 1.0 / B 320x640 2.0.
//   단언(기본 실행): 두 receiver(InkWell) ≥ 48×48 · 서로 겹침 0 · 중심과 늘어난 가장자리(안쪽 2px)에서 그 InkWell 이 hit 대상 ·
//   탭하면 해당 콜백만 1회 · '수정' 타일 색 brand 계열(위험/주의색 아님). DU_BEFORE_OBSERVE=331 이면 48 · 색을 KNOWN 기록.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/screens/business_admin/to_management/widgets/to_work_detail_card.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';

final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '331';

void main() {
  for (final c in const [(id: 'S031-W', w: 360.0, h: 780.0, s: 1.0), (id: 'S031-B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${c.id} 업무 카드 행동 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
      await t.runAsync(vqLoadFonts);
      t.view.physicalSize = Size(c.w, c.h);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      var edits = 0, deletes = 0;
      void out(String l) {
        // ignore: avoid_print
        print(l);
      }

      void known(bool ok, String what) {
        out('KNOWN ${ok ? 'ok' : 'NG'} $what beforeObs=$_beforeObs');
        if (!_beforeObs) expect(ok, isTrue, reason: what);
      }

      await t.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: RoleTheme.businessAdminTheme,
          builder: (ctx, child) =>
              MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
          home: Scaffold(
            backgroundColor: AppColors.background,
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TOWorkDetailCard(
                  workType: '포장',
                  workTypeIcon: 'local_shipping',
                  workTypeColor: '#2E7D32',
                  wage: 12000,
                  requiredCount: 2,
                  startTime: '09:00',
                  endTime: '18:00',
                  breakMinutes: 60,
                  onEdit: () => edits++,
                  onDelete: () => deletes++,
                ),
              ),
            ),
          ),
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(t.takeException(), isNull, reason: '${c.id} 넘침 · 예외');

      Finder receiver(IconData icon) =>
          find.ancestor(of: find.byIcon(icon), matching: find.byType(InkWell)).first;
      bool hitsTarget(Finder f, Offset p) {
        final hit = HitTestResult();
        WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
        final ro = t.renderObject(f);
        return hit.path.any((e) => identical(e.target, ro));
      }

      final rects = <String, Rect>{};
      for (final (name, icon) in const [('수정', Icons.edit_outlined), ('삭제', Icons.delete_outline)]) {
        final f = receiver(icon);
        final r = t.getRect(f);
        rects[name] = r;
        final center = hitsTarget(f, r.center);
        final edge = hitsTarget(f, Offset(r.left + 2, r.center.dy)) && hitsTarget(f, Offset(r.right - 2, r.center.dy)); // 둥근 모서리 밖이 아닌 좌/우 변 가운데
        out('${c.id} $name receiver=$r ${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)} centerHit=$center edgeHit=$edge');
        expect(center, isTrue, reason: '${c.id} $name 중심 hit 대상');
        expect(edge, isTrue, reason: '${c.id} $name 좌/우 변(안쪽 2px) hit 대상');
        known(r.width >= 48 - 1e-6 && r.height >= 48 - 1e-6, '${c.id} $name receiver ≥ 48×48(실측 ${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)})');
      }
      final ov = rects['수정']!.intersect(rects['삭제']!);
      expect(ov.width > 0.5 && ov.height > 0.5, isFalse, reason: '${c.id} 수정 ↔ 삭제 겹침');
      // '수정' 타일 색 — 아이콘 색이 brand 계열(주의/위험 아님)
      final editIcon = t.widget<Icon>(find.byIcon(Icons.edit_outlined));
      out('${c.id} editIconColor=${editIcon.color} deleteIconColor=${t.widget<Icon>(find.byIcon(Icons.delete_outline)).color}');
      known(editIcon.color == AppColors.brand, '${c.id} 수정 아이콘 brand(실측 ${editIcon.color})');
      await vqCapture(t, key, '${c.id}_card', conditions: {'state': '업무 카드 · 수정/삭제', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s, 'beforeObserve': _beforeObs});
      // 탭 — 각 콜백 1회, 서로 섞이지 않음(가장자리 탭 포함)
      final er = rects['수정']!;
      await t.tapAt(Offset(er.left + 3, er.center.dy));
      await t.pump(const Duration(milliseconds: 300));
      final dr = rects['삭제']!;
      await t.tapAt(Offset(dr.right - 3, dr.center.dy));
      await t.pump(const Duration(milliseconds: 300));
      out('${c.id} taps edits=$edits deletes=$deletes');
      expect(edits, 1, reason: '수정 1회');
      expect(deletes, 1, reason: '삭제 1회');
      await t.pumpWidget(const SizedBox.shrink());
    });
  }
}
