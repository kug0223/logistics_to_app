// [impl_21 · 2026-11-26] 판정 #292 준비 묶음의 결함 2건과 같은 뿌리.
//   Q18  관리자 홈 준비 상태 계산 실패 → Hero 가 로딩에 갇힘 (위젯 시험은 admin_home_content_render_test AHR-Q18-*).
//   Q25  슬롯 업무 배열을 편집 사본으로 덮어 다른 관리자의 마감/재오픈/긴급 종료를 지움.
//        · updateSlotFull(호출자 0) — 거래 안 최신 배열과 wdId 짝짓기 · 수정 토큰 증가.
//        · 실제 슬롯 수정 경로(callableUpdateSlotWorkDetails · STALE-EDIT)는 editRevision 으로만 겹침을 알아챈다 →
//          클라이언트의 슬롯 업무 배열 쓰기(마감·재오픈·긴급 종료 · 마감시간 동기화)가 토큰을 올린다.
//        · 일괄 날짜 수정은 첫 날짜의 상태를 모든 날짜에 보냈다 → 날짜마다 그 날짜의 상태로.
//        · 마감/긴급 업무가 있는 날짜는 수정 전송 자체가 실패했다(closedAt Timestamp → callable 코덱 Invalid argument).
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/work_detail_data.dart';

String _code(String p) => File(p)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _bodyOf(String src, String sig) {
  final at = src.indexOf(sig);
  expect(at, isNot(-1), reason: '$sig 가 없다');
  final m = RegExp(r'\)\s*(async\s*)?(=>|\{)').firstMatch(src.substring(at));
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

WorkDetailData _wd(String type, {
  String? wdId,
  String start = '09:00',
  String end = '18:00',
  int wage = 12000,
  bool closed = false,
  DateTime? closedAt,
  String? closedBy,
  bool emergency = false,
  DateTime? emergencyAt,
}) =>
    WorkDetailData(
      wdId: wdId,
      workType: type,
      wage: wage,
      wageType: 'hourly',
      requiredCount: 2,
      startTime: start,
      endTime: end,
      isManualClosed: closed,
      closedAt: closedAt,
      closedBy: closedBy,
      isEmergencyOpen: emergency,
      emergencyOpenedAt: emergencyAt,
    );

/// callable 전송과 같은 코덱(pigeon `_PigeonCodec extends StandardMessageCodec` — int 외에는 표준 코덱 그대로).
void _encodeLikeCallable(Object? payload) =>
    const StandardMessageCodec().encodeMessage(<Object?>[payload]);

void main() {
  final closedAt = DateTime.utc(2099, 1, 1, 3);
  final emergencyAt = DateTime.utc(2099, 1, 1, 4);

  group('Q25 상태 짝짓기(순수 함수)', () {
    test('I21-1 경합 재현 — 폼을 연 뒤 다른 관리자가 마감: 옛 사본 그대로는 마감을 지우고, 짝짓기는 마감 + 내 금액을 둘 다 남긴다', () {
      // 내가 폼을 열 때 읽은 사본(둘 다 열림) → 금액만 바꿔 저장하려 한다.
      final form = [_wd('상하차', wdId: 'a', wage: 13000), _wd('분류', wdId: 'b', wage: 13000)];
      // 그 사이 관리자 B 가 '분류' 를 마감했다(같은 슬롯 문서의 최신 배열).
      final fresh = [_wd('상하차', wdId: 'a'), _wd('분류', wdId: 'b', closed: true, closedAt: closedAt, closedBy: 'adminB')];

      final old = WorkDetailData.listToFirestore(form); // 예전 updateSlotFull 이 쓰던 것
      expect(old[1].containsKey('closedAt'), isFalse, reason: '옛 사본에는 마감이 없다 — 덮으면 B 의 마감이 사라진다');

      final merged = WorkDetailData.withStatusFrom(form, fresh);
      expect(merged[1].isManualClosed, isTrue);
      expect(merged[1].closedBy, 'adminB');
      expect(merged[1].closedAt, closedAt);
      expect(merged.map((d) => d.wage), [13000, 13000], reason: '폼이 소유한 정의(금액)는 폼 값');
      expect(merged[0].isManualClosed, isFalse);
    });

    test('I21-2 반대 방향 — 폼 사본엔 마감, 그 사이 재오픈·긴급 종료 → 최신(열림·긴급 없음)을 따른다', () {
      final form = [_wd('상하차', wdId: 'a', closed: true, closedAt: closedAt, closedBy: 'me', emergency: true, emergencyAt: emergencyAt)];
      final fresh = [_wd('상하차', wdId: 'a')];
      final m = WorkDetailData.withStatusFrom(form, fresh).single;
      expect([m.isManualClosed, m.closedAt, m.closedBy, m.isEmergencyOpen, m.emergencyOpenedAt],
          [false, null, null, false, null]);
    });

    // [impl_29 · J3 · 판정292 C292-04 · 의도된 기대 변경] 짝은 업무 정체(업무·시작·끝 = 서버 compositeId)만 본다.
    //   wdId 가 같아도 업무 이름·시간이 바뀌면 서버는 새 업무로 저장하므로 상태를 잇지 않는다. 짝 없는 새 정체는 상태를 비운다.
    test('I21-3 짝 = 업무 정체(업무·시작·끝)만 · wdId 만 같은 것은 새 정체 · 짝 없는 새 업무는 상태 비움', () {
      final form = [
        _wd('상하차', wdId: 'a'),                       // wdId 만 같음(이름이 다른 fresh) → 새 정체
        _wd('분류'),                                      // 업무 정체 짝
        _wd('검수', wdId: 'z', closed: true, closedBy: 'form'), // 짝 없음(새 업무) → 비움
      ];
      final fresh = [
        _wd('상하차-이름바뀜', wdId: 'a', emergency: true, emergencyAt: emergencyAt),
        _wd('분류', closed: true, closedAt: closedAt, closedBy: 'B'),
      ];
      final m = WorkDetailData.withStatusFrom(form, fresh);
      expect(m[0].isEmergencyOpen, isFalse, reason: 'wdId 만 같고 정체가 다르면 잇지 않는다');
      expect(m[0].workType, '상하차', reason: '정의는 편집본');
      expect(m[1].closedBy, 'B');
      expect([m[2].isManualClosed, m[2].closedBy], [false, null], reason: '새 정체에 옛 마감 이월 0');
    });

    test('I21-4 일괄 날짜 수정 — 첫 날짜 사본에서 시작해도 날짜마다 그 날짜의 상태(wdId 가 날짜마다 달라 업무 정체로 짝)', () {
      final firstDay = [_wd('상하차', wdId: 'd1a', closed: true, closedAt: closedAt, closedBy: 'A'), _wd('분류', wdId: 'd1b')];
      final otherDay = [_wd('상하차', wdId: 'd2a'), _wd('분류', wdId: 'd2b', emergency: true, emergencyAt: emergencyAt)];
      final forOther = WorkDetailData.withStatusFrom(firstDay, otherDay);
      expect(forOther[0].isManualClosed, isFalse, reason: '첫 날짜의 마감을 다른 날짜에 퍼뜨리지 않는다');
      expect(forOther[1].isEmergencyOpen, isTrue, reason: '다른 날짜의 긴급 모집을 지우지 않는다');
      final forFirst = WorkDetailData.withStatusFrom(firstDay, firstDay);
      expect(forFirst[0].closedBy, 'A', reason: '같은 날짜는 그대로');
    });
  });

  group('Q25 같은 뿌리 — 마감/긴급 업무가 있는 날짜의 수정 전송', () {
    test('I21-5 CF 전송본에 Timestamp 가 없다(closedAt · emergencyOpenedAt 밀리초) · callable 코덱으로 인코딩된다', () {
      final wds = [_wd('상하차', closed: true, closedAt: closedAt, closedBy: 'A', emergency: true, emergencyAt: emergencyAt)];
      // 고치기 전 꼴(Timestamp 가 남은 Firestore 직렬화)은 코덱이 거절한다 — 이것이 결함의 원인이다.
      expect(() => _encodeLikeCallable(WorkDetailData.listToFirestore(wds)), throwsArgumentError);
      final payload = WorkDetailData.listToCFPayload(wds);
      expect(payload.single['closedAt'], closedAt.millisecondsSinceEpoch);
      expect(payload.single['emergencyOpenedAt'], emergencyAt.millisecondsSinceEpoch);
      bool hasTs(Object? v) => v is Timestamp || (v is Map && v.values.any(hasTs)) || (v is List && v.any(hasTs));
      expect(hasTs(payload), isFalse);
      expect(() => _encodeLikeCallable(payload), returnsNormally);
    });
  });

  group('Q25 writer 계약(소스)', () {
    final toFs = _code('lib/services/firestore/to_firestore.dart');
    final svc = _code('lib/services/firestore_service.dart');

    test('I21-6 updateSlotFull — 거래 안 tx.get 뒤 최신 배열과 짝지어 쓰고 수정 토큰을 올린다(편집 사본 그대로 쓰기 0)', () {
      final b = _bodyOf(toFs, 'Future<void> updateSlotFull(');
      final getAt = b.indexOf('await tx.get(slotRef)');
      final mergeAt = b.indexOf('WorkDetailData.withStatusFrom(workDetails, freshDetails)');
      expect(getAt, greaterThan(-1));
      expect(mergeAt, greaterThan(getAt));
      expect(b.contains("'editRevision': currentRevision + 1"), isTrue);
      expect(RegExp(r"'workDetails':\s*WorkDetailData\.listToFirestore\(workDetails\)").hasMatch(b), isFalse,
          reason: '편집 사본으로 배열을 통째로 덮는 쓰기가 남았다');
    });

    // [impl_29 · J1 · 의도된 기대 변경] 공고(TO) 문서도 토큰을 올린다(rules 상태 전용 문과 한 셀) — 슬롯만이던 조건을 뺐다.
    test('I21-7 업무 배열 쓰기가 수정 토큰을 올린다 — 마감·재오픈·긴급 종료(슬롯·공고) · 마감시간 동기화', () {
      final atomic = _bodyOf(svc, '_updateWorkDetailsInArrayAtomic({');
      expect(RegExp(r"if \(slotId != null\)\s*'editRevision':").hasMatch(atomic), isFalse);
      expect(atomic.contains("'editRevision': (((snap.data() as Map<String, dynamic>)['editRevision'] as num?)?.toInt() ?? 0) + 1"), isTrue);
      final dl = _bodyOf(toFs, 'Future<void> updateSlotsDeadlines(');
      expect(dl.contains("'editRevision': fresh.editRevision + 1"), isTrue);
    });

    test('I21-8 일괄 날짜 수정 전송은 날짜마다 그 날짜 슬롯의 상태로 짝짓는다', () {
      final edit = _code('lib/screens/business_admin/to_management/edit_to_screen.dart');
      expect(RegExp(r'WorkDetailData\.listToCFPayload\(\s*WorkDetailData\.withStatusFrom\(updatedWorkDetails, slot\.workDetails\)\)')
          .hasMatch(edit), isTrue);
    });
  });

  group('Q18 같은 꼴 — 예외가 진행 표시를 끝내지 못함', () {
    test('I21-9 관리자 홈 준비 상태 실패 갈래가 끝난 상태로 둔다(세대 검사 뒤 · mounted 검사 뒤)', () {
      final home = _code('lib/screens/business_admin/business_admin_home_screen.dart');
      final b = _bodyOf(home, 'Future<void> _loadPostingReadiness() async {');
      final c = b.substring(b.indexOf('} catch (e) {'));
      final seqAt = c.indexOf('if (seq != _readinessSeq) return;');
      final mountedAt = c.indexOf('if (!mounted) return;');
      final loadedAt = c.indexOf('_readinessLoaded = true;');
      expect([seqAt, mountedAt, loadedAt].every((i) => i > -1) && seqAt < mountedAt && mountedAt < loadedAt, isTrue);
      expect(c.substring(0, c.indexOf('return;', loadedAt)).contains('_readinessFailed = true;'), isTrue);
      final row = _bodyOf(home, 'Widget _buildReadinessFailedRow(');
      expect(row.contains('_todayOpsErrorRow('), isTrue, reason: 'HOME-V2-08D.5 공용 데이터 상태 줄');
      expect(row.contains('unawaited(_loadPostingReadiness())'), isTrue, reason: '재시도 = 같은 loader');
    });

    test('I21-10 공고 카드 상세 이동 — 근무 정보 조회 실패가 진행 표시를 남기지 않고 반환값을 쓴다', () {
      final card = _code('lib/widgets/user/cards/user_to_card.dart');
      final b = _bodyOf(card, 'Future<void> _goToDetail() async {');
      expect(b.contains('details = await _fetch();'), isTrue);
      final tryAt = b.indexOf('try {');
      final finAt = b.indexOf('} finally {');
      expect(tryAt > -1 && tryAt < b.indexOf('details = await _fetch();') && finAt > -1, isTrue);
      expect(b.substring(finAt).contains('_isApplyLoading = false'), isTrue);
    });
  });
}
