// [WORKTYPE-SCHEDULE-GUIDANCE 2026-10-17] 근로자 일정 상세 — 저장된 업무명과 맞는 업무유형이 없을 때
//
// 무엇이 잘못됐었나
//   일정 상세는 업무 안내(사진·한 줄 소개·설명·주요 업무·환경·자격·주의사항)를 저장본이 아니라
//   현재 활성 업무유형 목록에서 **이름으로** 찾는다. 이름이 맞는 문서가 없으면
//   `orElse: () => wts.first` 로 **목록의 첫 업무**를 골랐다. 관리자가 업무 A 의 이름을 바꾸거나
//   비활성화하면, A 로 확정된 근로자의 일정 상세에 업무 B 의 안내가 A 의 것처럼 떴다.
//
// 이 파일이 고정하는 것(WORKTYPE-IDENTITY 이후)
//   · 안내는 공고 근무의 workTypeId 문서 최신본 — 비활성이어도 그 업무 것, 같은 이름의 새 문서는 아니다(D5).
//   · 레거시(id 없음)는 이름이 사업장에서 유일하고 공고보다 먼저 만든 문서일 때만 연결.
//   · 못 고르면 다른 업무의 안내를 그리지 않는다(D1) — 목록 비어 있음 · 조회 실패 · 공고 못 읽음 포함.
//   · 저장된 업무명·임금·시간·확정 상태는 업무유형과 무관하게 그대로.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/visible_text.dart'; // [DU256] 업무명·안내 문장은 낱말 결합 문자를 품는다
import 'package:intl/date_symbol_data_local.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/business_work_type_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/services/work_type_guide_resolver.dart';
import 'package:ALfit/widgets/dialogs/schedule_detail_dialog.dart';
import 'package:ALfit/widgets/dialogs/schedule_detail_reads.dart';

ApplicationModel _app() => ApplicationModel(
      id: 'app1',
      businessId: 'biz1',
      businessName: '평택 물류센터',
      toTitle: '단기 모집',
      workDate: DateTime(2026, 11, 3),
      startTime: '09:00',
      endTime: '18:00',
      uid: 'u1',
      selectedWorkType: '상하차',
      workDetailId: '상하차_09:00_18:00',
      wage: 12000,
      wageType: 'hourly',
      status: AppStatus.confirmed,
      appliedAt: DateTime(2026, 10, 1),
      workTypeIcon: 'box',
    );

BusinessModel _business() => BusinessModel(
      id: 'biz1',
      name: '평택 물류센터',
      ownerId: 'admin1',
      businessNumber: '000-00-00000',
      address: '경기도 평택시 진위면 마산8로 10',
      category: '물류',
      subCategory: '창고',
      isApproved: true,
      createdAt: DateTime(2025),
    );

/// 업무마다 서로 다른 안내 — 어느 업무의 안내가 그려졌는지 문장으로 구별한다.
BusinessWorkTypeModel _wt(String id, String name, String tag,
        {bool isActive = true, DateTime? createdAt}) =>
    BusinessWorkTypeModel(
      id: id,
      businessId: 'biz1',
      name: name,
      icon: 'box',
      displayOrder: 0,
      isActive: isActive,
      createdAt: createdAt ?? DateTime(2025),
      oneLineIntro: '$tag 한 줄 소개',
      description: '$tag 업무 설명',
      duties: '$tag 주요 업무',
      workEnvironment: '$tag 근무 환경',
      requirements: '$tag 자격 요건',
      precautions: '$tag 주의사항',
    );

final _a = _wt('wtA', '상하차', 'A');
final _b = _wt('wtB', '피킹', 'B');

WorkTypeCatalog _catalog(List<BusinessWorkTypeModel> docs, {bool complete = true}) {
  final counts = <String, int>{};
  for (final d in docs) {
    counts[d.name] = (counts[d.name] ?? 0) + 1;
  }
  return WorkTypeCatalog(
      businessId: 'biz1', byId: {for (final d in docs) d.id: d}, nameCounts: counts, complete: complete);
}

/// 확정 근무의 공고(2026-09-01 생성). 근무 칸은 업무유형 id 를 들고 있다(레거시면 null).
TOModel _to({String? workTypeId = 'wtA', bool storedCreatedAt = true, String businessId = 'biz1'}) => TOModel(
      id: 'to1',
      businessId: businessId,
      businessName: '평택 물류센터',
      type: 'flex',
      title: '단기 모집',
      creatorUID: 'admin1',
      status: TOStatus.active,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: [
        WorkDetailData(
          wdId: 'wd1',
          workTypeId: workTypeId,
          workType: '상하차',
          workTypeIcon: 'box',
          wage: 12000,
          requiredCount: 2,
          startTime: '09:00',
          endTime: '18:00',
        ),
      ],
      totalRequired: 2,
      totalConfirmed: 1,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: DateTime(2026, 9, 1),
      storedCreatedAt: storedCreatedAt ? DateTime(2026, 9, 1) : null,
      statusUpdatedAt: DateTime(2026, 9, 1),
    );

Future<void> _pump(WidgetTester t, Future<WorkTypeCatalog> Function() catalog,
    {TOModel? to, bool noTo = false}) async {
  t.view.physicalSize = const Size(360, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    // 앱은 fontFamily 를 지정하지 않는다 — 기기 한글 폰트에 가까운 번들 NotoSansKR 로 잰다(테스트 기본 폰트는 더 넓다).
    theme: ThemeData(fontFamily: 'NKR'),
    home: Scaffold(
      body: ScheduleDetailDialog(
        application: _app(),
        reads: ScheduleDetailReads(
          businessById: (_) async => _business(),
          toByApplication: (_) async => noTo ? null : (to ?? _to()),
          workTypeCatalog: (_) => catalog(),
        ),
      ),
    ),
  ));
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

const _fields = ['한 줄 소개', '업무 설명', '주요 업무', '근무 환경', '자격 요건', '주의사항'];

/// tag 업무의 안내 문장이 하나라도 보이는가.
int _guideOf(String tag) =>
    // [DU256] 보이는 글자 기준 — 원문 finder 면 keepWords 문장을 못 찾아 '0개' 단언이 늘 통과한다.
    _fields.where((f) => findVisibleText('$tag $f').evaluate().isNotEmpty).length;

/// 저장본이 그대로 그려지는가 — 업무명 · 임금 · 시간 · 확정 상태.
void _expectSnapshot(WidgetTester t) {
  expect(findVisibleText('상하차'), findsWidgets); // [DU256] 머리글 업무명 keepWords
  expect(find.textContaining('12,000원', skipOffstage: false), findsWidgets);
  expect(find.textContaining('09:00', skipOffstage: false), findsWidgets);
  expect(find.text('확정', skipOffstage: false), findsWidgets);
}

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

  testWidgets('WSG-01 id 로 연결된 업무 — 그 업무의 안내 그대로', (t) async {
    await _pump(t, () async => _catalog([_b, _a]));
    expect(_guideOf('A'), _fields.length);
    expect(_guideOf('B'), 0);
    _expectSnapshot(t);
    expect(t.takeException(), isNull);
  });

  testWidgets('WSG-02 [D1] 연결된 업무 문서가 없음 — 목록의 첫 업무(B) 안내로 대체하지 않는다', (t) async {
    await _pump(t, () async => _catalog([_b]));
    expect(_guideOf('B'), 0, reason: '목록의 첫 업무(B) 안내로 대체하면 안 된다');
    expect(find.text('업무 안내', skipOffstage: false), findsNothing);
    _expectSnapshot(t);
    expect(t.takeException(), isNull);
  });

  testWidgets('WSG-03 연결된 업무 비활성 — 기존 근무는 같은 업무의 최신 안내', (t) async {
    await _pump(t, () async => _catalog([_b, _wt('wtA', '상하차', 'A', isActive: false)]));
    expect(_guideOf('A'), _fields.length);
    expect(_guideOf('B'), 0);
    _expectSnapshot(t);
  });

  testWidgets('WSG-04 업무유형이 하나도 없다 — 안내 없음, 저장본은 그대로', (t) async {
    await _pump(t, () async => WorkTypeCatalog.empty);
    expect(find.text('업무 안내', skipOffstage: false), findsNothing);
    _expectSnapshot(t);
    expect(t.takeException(), isNull);
  });

  testWidgets('WSG-05 업무유형 조회 실패 — 다른 업무 안내 없음, 저장본 헤더는 그대로', (t) async {
    // 세 조회를 한 번에 기다리므로 사업장·공고 정보까지 함께 비고 토스트가 뜬다(범위 밖 — 보고만).
    await _pump(t, () async => throw Exception('network'));
    expect(_guideOf('A') + _guideOf('B'), 0);
    expect(findVisibleText('상하차'), findsWidgets); // [DU256] 머리글 업무명 keepWords
    expect(find.text('확정', skipOffstage: false), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('WSG-06 [D5] id 연결 · 옛 업무 비활성 + 같은 이름 새 문서 — 새 안내를 붙이지 않는다', (t) async {
    await _pump(t, () async => _catalog([
          _wt('wtA', '상하차', 'A', isActive: false),
          _wt('wtNew', '상하차', 'NEW', createdAt: DateTime(2026, 10, 1)),
        ]));
    expect(_guideOf('NEW'), 0);
    expect(_guideOf('A'), _fields.length);
    _expectSnapshot(t);
  });

  testWidgets('WSG-07 [D1·레거시] id 없는 공고 · 같은 이름 문서 없음 — B 로 대체하지 않는다', (t) async {
    await _pump(t, () async => _catalog([_b]), to: _to(workTypeId: null));
    expect(_guideOf('B'), 0);
    _expectSnapshot(t);
  });

  testWidgets('WSG-08 레거시 · 그 이름 문서가 하나이고 공고보다 먼저 — 연결', (t) async {
    await _pump(t, () async => _catalog([_b, _a]), to: _to(workTypeId: null));
    expect(_guideOf('A'), _fields.length);
  });

  testWidgets('WSG-09 [D5·레거시] 옛 문서 + 같은 이름 새 문서 — 어느 쪽도 붙이지 않는다', (t) async {
    await _pump(t, () async => _catalog([
          _wt('wtA', '상하차', 'A', isActive: false),
          _wt('wtNew', '상하차', 'NEW', createdAt: DateTime(2026, 10, 1)),
        ]), to: _to(workTypeId: null));
    expect(_guideOf('A') + _guideOf('NEW'), 0);
  });

  testWidgets('WSG-10 공고를 읽지 못함 — 이름이 유일해도 연결하지 않는다', (t) async {
    await _pump(t, () async => _catalog([_a]), noTo: true);
    expect(_guideOf('A'), 0);
    _expectSnapshot(t);
  });

  // ── [WORKTYPE-LOCAL-CLOSURE] 확인하지 못하면 숨긴다
  testWidgets('WSG-11 레거시 · 공고 문서에 createdAt 없음 — 연결하지 않는다', (t) async {
    await _pump(t, () async => _catalog([_a]), to: _to(workTypeId: null, storedCreatedAt: false));
    expect(_guideOf('A'), 0);
    _expectSnapshot(t);
  });

  testWidgets('WSG-12 레거시 · 목록 불완전 — 연결하지 않는다', (t) async {
    await _pump(t, () async => _catalog([_a], complete: false), to: _to(workTypeId: null));
    expect(_guideOf('A'), 0);
  });

  testWidgets('WSG-13 공고가 다른 사업장 소속(목록은 지원서 사업장) — 연결하지 않는다', (t) async {
    await _pump(t, () async => _catalog([_a]), to: _to(businessId: 'bizX'));
    expect(_guideOf('A'), 0);
    _expectSnapshot(t);
  });
}
