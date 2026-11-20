// [WORKTYPE-IDENTITY · D7 2026-10-17] 공고 수정창 — 기존 업무 A 가 현재 선택 목록에 없을 때
//
// 무엇이 잘못됐었나
//   수정 모드는 업무 유형 선택을 숨기고 "업무 유형은 바꿀 수 없다" 카드만 보여준다. 그런데 초기화가
//   현재 활성 목록에서 A 를 이름으로 찾고, 없으면 `orElse: () => businessWorkTypes.first` 로 **첫
//   활성 업무 B** 를 골라 두었다. 저장 결과에는 그 B 의 이름·아이콘·색이 실려 나가고, 공고 수정
//   화면은 그것을 그대로 copyWith 한다 — 관리자가 임금만 고쳐도 근무가 A→B 로 바뀌었다
//   (A 가 비활성화됐거나 이름이 바뀐 경우).
//
// 지금 규칙: 수정 모드는 업무 정체성(이름·아이콘·색·업무유형 id)을 결과에 싣지 않는다.
//   바꾸려면 근무를 지우고 새로 추가한다(추가 경로 · 서버의 지원자 보호 관문이 그대로 적용된다).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:ALfit/models/core/business_work_type_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/widgets/pickers/create_edit_work_detail_dialog.dart';

BusinessWorkTypeModel _wt(String id, String name, String icon) => BusinessWorkTypeModel(
      id: id,
      businessId: 'biz1',
      name: name,
      icon: icon,
      color: '#112233',
      backgroundColor: '#445566',
      displayOrder: 0,
      createdAt: DateTime(2025),
    );

WorkDetailData _workA() => WorkDetailData(
      wdId: 'wdA',
      workTypeId: 'wtA',
      workType: '상하차',
      workTypeIcon: 'box',
      workTypeColor: '#000000',
      workTypeBackgroundColor: '#FFFFFF',
      wage: 12000,
      wageType: 'hourly',
      requiredCount: 2,
      startTime: '09:00',
      endTime: '18:00',
      payScheduleType: 'next_day',
    );

/// 수정창을 열고 임금만 13,000 으로 고친 뒤 저장한 결과.
Future<Map<String, dynamic>?> _editWageOnly(
    WidgetTester t, List<BusinessWorkTypeModel> active) async {
  t.view.physicalSize = const Size(400, 2000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  Map<String, dynamic>? result;
  var done = false;
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(fontFamily: 'NKR'),
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              result = await WorkDetailDialog.showEditDialog(
                  context: ctx, work: _workA(), businessWorkTypes: active);
              done = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  final wage = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '12,000');
  expect(wage, findsOneWidget);
  await t.enterText(wage, '13000');
  await t.pump();
  await t.tap(find.text('저장'));
  await t.pumpAndSettle();
  expect(done, isTrue, reason: '저장이 닫히지 않았다');
  return result;
}

/// 공고 수정 화면(edit_to_screen)이 결과를 반영하는 방식 그대로.
WorkDetailData _applyLikeEditScreen(WorkDetailData w, Map<String, dynamic> r) => w.copyWith(
      workType: r['workType'],
      workTypeIcon: r['workTypeIcon'],
      workTypeColor: r['workTypeColor'],
      workTypeBackgroundColor: r['workTypeBackgroundColor'],
      wage: r['wage'],
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ko_KR', null);
    for (final e in {
      'NKR': 'assets/fonts/NotoSansKR-Regular.ttf',
      'NKB': 'assets/fonts/NotoSansKR-Bold.ttf',
    }.entries) {
      final loader = FontLoader(e.key);
      final b = File(e.value).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(b.buffer, b.offsetInBytes, b.length)));
      await loader.load();
    }
  });

  testWidgets('WEL-01 A 가 목록에 없음(비활성·이름 변경) — 임금만 고쳐도 A 그대로', (t) async {
    final r = await _editWageOnly(t, [_wt('wtB', '피킹', 'cart')]);
    expect(r, isNotNull);
    expect(r!['wage'], 13000);
    final applied = _applyLikeEditScreen(_workA(), r);
    expect(applied.workType, '상하차', reason: '첫 활성 업무 B 로 바뀌면 안 된다');
    expect(applied.workTypeIcon, 'box');
    expect(applied.workTypeId, 'wtA');
    expect(applied.wage, 13000);
    expect(t.takeException(), isNull);
  });

  testWidgets('WEL-02 A 가 목록에 있음 — 결과는 같고 A 그대로', (t) async {
    final r = await _editWageOnly(t, [_wt('wtB', '피킹', 'cart'), _wt('wtA', '상하차', 'box')]);
    final applied = _applyLikeEditScreen(_workA(), r!);
    expect(applied.workType, '상하차');
    expect(applied.workTypeId, 'wtA');
    expect(applied.wage, 13000);
  });

  testWidgets('WEL-03 활성 목록이 비어 있음 — A 그대로', (t) async {
    final r = await _editWageOnly(t, const []);
    final applied = _applyLikeEditScreen(_workA(), r!);
    expect(applied.workType, '상하차');
    expect(applied.wage, 13000);
  });

  testWidgets('WEL-04 수정창에는 업무 유형 선택이 없다(정체성 잠금 안내만)', (t) async {
    t.view.physicalSize = const Size(400, 2000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: 'NKR'),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: ElevatedButton(
            onPressed: () => WorkDetailDialog.showEditDialog(
                context: ctx, work: _workA(), businessWorkTypes: [_wt('wtB', '피킹', 'cart')]),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('피킹'), findsNothing, reason: '수정창에서 다른 업무를 고를 수 없다');
  });
}
