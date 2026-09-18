// [CROSS-DOMAIN-R5.3C.1] 급여 약속의 서버 권위 / 통상시급 provenance
//
// 이 파일이 고정하는 것:
//
//   1. 통상시급을 **누가 정했는지**(MANUAL/AUTO)가 저장된다.
//      값의 부재도 하나의 약속이다 — 적어두지 않으면 나중에 공고에 추가된
//      수동값이 그 빈자리로 들어와 이미 확정된 사람의 연장·야간 단가를 바꾼다.
//
//   2. 급여 계산은 클라이언트 payload가 아니라 **Application의 약속**을 쓴다.
//      이전에는 금액만 서버 권위였고 급여유형·소정휴게·통상시급·야간 규칙·
//      공제 방식은 클라이언트가 보낸 값을 그대로 썼다.
//
//   3. MATCH_SOURCE_WAGE는 **금액 하나만** 옮긴다. 근로조건은 언제나 대상 업무 B다.
//      단위(시급/일급)가 다르면 승계하지 않는다 — 환산은 새로운 임금 약속이다.
//
//   4. 법정 최저임금은 제안 **전에** 본다. 수락·계약·출근까지 끝난 뒤
//      처음 거부되는 흐름을 만들지 않는다.
//
//   5. 같은 이름의 업무가 여럿일 때 첫 번째를 고르지 않는다(fail-closed).

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

String _load(String p) => _flat(_codeOf(_src(p)));

String _callableBody(String raw, String name) {
  final start = raw.indexOf('export const $name = onCall(');
  if (start < 0) throw StateError('$name 을 찾지 못함');
  final end = raw.indexOf('\n);', start);
  if (end < 0) throw StateError('$name 본문 끝을 찾지 못함');
  return raw.substring(start, end);
}

const _cf = 'functions/src/index.ts';
const _wdData = 'lib/models/core/work_detail_data.dart';
const _appModel = 'lib/models/core/application_model.dart';
const _wdHelper = 'lib/utils/work_detail_helper.dart';
const _contract = 'lib/services/contract_service.dart';
const _sheet = 'lib/widgets/dialogs/alternative_work_offer_sheet.dart';
const _editor = 'lib/widgets/pickers/create_edit_work_detail_dialog.dart';

void main() {
  final rawCf = _codeOf(_src(_cf));
  final cf = _flat(rawCf);
  final offer = _flat(_callableBody(rawCf, 'callableOfferAlternativeWork'));
  final wage = _flat(_callableBody(rawCf, 'callableCalculateAndConfirmWage'));
  final apply = _flat(_callableBody(rawCf, 'callableApplyToTO'));

  // ══════════════════════════════════════════════════════════════════
  // PART B — baseHourlyWage provenance
  // ══════════════════════════════════════════════════════════════════

  group('통상시급 mode가 저장된다', () {
    final wd = _load(_wdData);

    test('WorkDetail이 mode를 갖는다', () {
      expect(wd.contains('final String? baseHourlyWageMode;'), true);
      expect(wd.contains("static const String baseHourlyManual = 'MANUAL';"), true);
      expect(wd.contains("static const String baseHourlyAuto = 'AUTO';"), true);
    });

    test('값이 없어도 mode는 저장된다', () {
      // AUTO도 명시적 약속이다 — 빈자리로 두면 나중 값이 들어온다.
      expect(
          wd.contains("'baseHourlyWageMode': baseHourlyWageMode ?? "
              "(baseHourlyWage != null ? baseHourlyManual : baseHourlyAuto),"),
          true);
    });

    test('레거시 해석은 한 곳에서만 한다', () {
      expect(
          wd.contains('static String resolveBaseHourlyWageMode('
              'Map<String, dynamic> map) {'),
          true);
      expect(
          wd.contains("return map['baseHourlyWage'] != null ? "
              'baseHourlyManual : baseHourlyAuto;'),
          true,
          reason: '값이 얼마인지가 아니라 존재 여부로 해석한다');
    });

    test('편집기가 두 저장 경로 모두에서 mode를 쓴다', () {
      final e = _load(_editor);
      expect(
          e.contains("'baseHourlyWageMode': editBaseHourly != null "
              '? WorkDetailData.baseHourlyManual '
              ': WorkDetailData.baseHourlyAuto,'),
          true);
      expect(
          e.contains('baseHourlyWageMode: addBaseHourly != null '
              '? WorkDetailData.baseHourlyManual '
              ': WorkDetailData.baseHourlyAuto,'),
          true);
    });

    test('파생값을 저장 필드에 자동으로 채우지 않는다', () {
      // 이 invariant가 깨지면 non-null ⟺ MANUAL 해석이 소급해서 무효가 된다.
      final e = _codeOf(_src(_editor));
      final assigns = RegExp(r'_baseHourlyWageController\.text\s*=\s*([^;]+);')
          .allMatches(e)
          .map((m) => m.group(1)!.trim())
          .toSet();
      expect(assigns, {"''"},
          reason: '컨트롤러에 계산값을 넣으면 MANUAL/AUTO를 구분할 수 없게 된다: $assigns');
    });

    test('서버도 같은 규칙으로 읽는다', () {
      expect(cf.contains('function srvResolveBaseHourlyWageMode('), true);
      expect(
          cf.contains('return (typeof bhw === "number" && bhw > 0) ? '
              'BASE_HOURLY_MANUAL : BASE_HOURLY_AUTO;'),
          true);
    });

    test('약속 스냅샷에 mode가 들어간다', () {
      expect(
          cf.contains('out.baseHourlyWageMode = srvResolveBaseHourlyWageMode(wd);'),
          true);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // BLOCKER-AUTO-BASE-HOURLY-LIVE-LEAKAGE
  // ══════════════════════════════════════════════════════════════════

  group('AUTO 약속에 공고 현재값이 스며들지 않는다', () {
    final a = _load(_appModel);
    final h = _load(_wdHelper);

    test('Application이 mode를 읽고 쓴다', () {
      expect(a.contains('final String? baseHourlyWageMode;'), true);
      expect(
          a.contains("baseHourlyWageMode: data['baseHourlyWageMode'] as String?,"),
          true);
      expect(
          a.contains("if (baseHourlyWageMode != null) "
              "'baseHourlyWageMode': baseHourlyWageMode,"),
          true);
    });

    test('resolver가 AUTO에서 live 값을 지운다', () {
      expect(
          h.contains('if (baseHourlyWageModeOf(app) == '
              'WorkDetailData.baseHourlyAuto) { '
              "merged.remove('baseHourlyWage'); }"),
          true,
          reason: '{...live, ...promised}는 키가 없으면 live가 살아남는다');
    });

    test('mode 판정은 한 곳에서만 한다', () {
      expect(h.contains('static String? baseHourlyWageModeOf(ApplicationModel app)'),
          true);
    });

    test('스냅샷 없는 레거시는 판정하지 않는다', () {
      expect(
          h.contains('if (!app.hasCompensationSnapshot) return null;'), true,
          reason: 'UNKNOWN을 공고 현재값으로 추정하지 않는다');
    });

    test('계약서도 mode를 옮긴다', () {
      expect(
          _load(_contract).contains(
              'baseHourlyWageMode: WorkDetailHelper.baseHourlyWageModeOf(application),'),
          true);
    });

    test('값을 지우는 것은 AUTO 선언이다', () {
      expect(
          _load(_wdData).contains('baseHourlyWageMode: clearBaseHourlyWage '
              '? baseHourlyAuto '
              ': (baseHourlyWageMode ?? this.baseHourlyWageMode),'),
          true);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // BLOCKER-WAGE-SERVER-COMPENSATION-AUTHORITY
  // ══════════════════════════════════════════════════════════════════

  group('급여 계산은 약속을 쓰고 payload를 쓰지 않는다', () {
    test('서버 resolver가 있다', () {
      expect(cf.contains('function srvResolvePromisedCompensation('), true);
    });

    test('Application을 읽지 못하면 payload로 넘어가지 않는다', () {
      expect(
          wage.contains('"이 근태의 지원서를 찾을 수 없어 급여를 확정할 수 없습니다."'),
          true,
          reason: '읽기 실패를 "약속 없음"으로 바꾸면 payload가 이긴다');
    });

    test('계산 입력이 전부 promised다', () {
      expect(wage.contains('wageType: promised.wageType, baseWage: effectiveBaseWage,'),
          true);
      expect(wage.contains('nightAllowanceApplied: promised.nightAllowanceApplied,'),
          true);
      expect(wage.contains('nightIncluded: promised.nightIncluded,'), true);
      expect(wage.contains('baseHourlyWage: promised.baseHourlyWage,'), true);
      expect(wage.contains('const schedBreakMins = promised.scheduledBreakMinutes ?? breakMins;'),
          true);
    });

    test('공제도 약속 기준이다', () {
      expect(
          wage.contains('let wageResult2: SrvWageResult = '
              'promised.taxDeductionType !== "daily_auto_8" ? '
              'srvApplyDeduction(base2, promised.taxDeductionType, rates2)'),
          true);
      expect(wage.contains('if (promised.taxDeductionType === "daily_auto_8") {'),
          true);
    });

    test('최저임금 판정도 약속 기준이다', () {
      expect(wage.contains('if (promised.wageType === "hourly" && minimumWage2 > 0'),
          true);
      expect(wage.contains('if (promised.wageType === "daily" && minimumWage2 > 0) {'),
          true);
      expect(wage.contains('const schedBreakMins2 = promised.scheduledBreakMinutes ?? 0;'),
          true);
    });

    test('실제 휴게는 관리자 관측 사실이라 그대로 둔다', () {
      expect(
          wage.contains('const breakMins = typeof d.breakMinutes === "number" '
              '? d.breakMinutes : 0;'),
          true,
          reason: '소정휴게는 약속, 실제휴게는 사실 — 둘을 섞지 않는다');
    });

    test('약속과 payload가 다르면 기록은 남긴다', () {
      expect(wage.contains('클라이언트 급여 조건이 약속과 다름'), true);
    });

    test('스냅샷 없는 레거시는 강제하지 않는다', () {
      expect(cf.contains('if (!appData || !hasSnapshot) {'), true);
      expect(cf.contains('hasSnapshot: false,'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // PART A / J — MATCH_SOURCE_WAGE
  // ══════════════════════════════════════════════════════════════════

  group('옵션은 서버 allowlist다', () {
    test('두 값만 받는다', () {
      expect(
          offer.contains('const OFFER_COMPENSATION_OPTIONS = '
              '["TARGET_BASE", "MATCH_SOURCE_WAGE"];'),
          true);
      expect(
          offer.contains('!OFFER_COMPENSATION_OPTIONS.includes(compensationOption)'),
          true);
    });

    test('legacy SOURCE_WAGE는 받지 않는다', () {
      expect(offer.contains('"SOURCE_WAGE"'), false);
    });

    test('금액 입력 경로가 없다', () {
      expect(RegExp(r'request\.data[^;]*\bwage\b').hasMatch(offer), false);
      expect(_load(_sheet).contains("'wage':"), false);
    });
  });

  group('MATCH는 금액 하나만 옮긴다', () {
    test('단위가 다르면 승계하지 않는다', () {
      expect(
          offer.contains('if (!srcWageType || !offeredWageType || '
              'srcWageType !== offeredWageType) {'),
          true);
      expect(offer.contains('"기존 지원과 제안 업무의 급여 기준(시급/일급)이 달라 " + '
          '"기존 급여를 그대로 승계할 수 없습니다."'), true);
    });

    test('근로조건은 언제나 B다', () {
      // A의 휴게·야간·공제를 옮기면 A 8시간 휴게 60분이 B 5시간에 붙는다.
      expect(offer.contains('const offeredSnapshot = buildCompensationSnapshot(targetWD);'),
          true);
      expect(offer.contains('srcData.breakMinutes'), false);
      expect(offer.contains('srcData.nightAllowanceApplied'), false);
      expect(offer.contains('srcData.taxDeductionType'), false);
    });

    test('금액만 source에서 온다', () {
      expect(offer.contains('offeredWage = srcWage;'), true);
    });

    test('MANUAL 통상시급은 유지한다', () {
      // 관리자가 직접 정한 정책값이다 — 금액이 달라져도 재계산하지 않는다.
      expect(
          offer.contains('if (srvResolveBaseHourlyWageMode(targetWD) === '
              'BASE_HOURLY_AUTO) { delete offeredSnapshot.baseHourlyWage;'),
          true,
          reason: 'AUTO일 때만 지운다 — MANUAL은 건드리지 않는다');
    });

    test('AUTO는 숫자를 얼리지 않는다', () {
      expect(
          offer.contains('offeredSnapshot.baseHourlyWageMode = BASE_HOURLY_AUTO;'),
          true,
          reason: '약속 금액과 그때의 근무시간으로 파생한다 — 시간 정합 유지');
    });

    test('cross-type 업무 변경 자체는 막지 않는다', () {
      // TARGET_BASE는 wageType이 달라도 정상이다 — 막는 것은 자동 환산뿐이다.
      final matchGuard = offer.substring(offer.indexOf('if (offerIsMatch) {'));
      expect(matchGuard.contains('srcWageType !== offeredWageType'), true);
      expect(
          offer.indexOf('if (offerIsMatch) {') >
              offer.indexOf('const targetBaseWage = targetWD["wage"]'),
          true,
          reason: '단위 검사는 MATCH 분기 안에만 있어야 한다');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // BLOCKER-MINIMUM-WAGE-PRECOMMIT-GUARD
  // ══════════════════════════════════════════════════════════════════

  group('최저임금은 제안 전에 본다', () {
    test('공용 판정 함수가 있다', () {
      expect(cf.contains('function srvValidateMinimumWagePromise('), true);
      expect(cf.contains('async function srvLoadMinimumWage('), true);
    });

    test('급여 확정과 같은 판정식이다', () {
      expect(cf.contains('const minDaily = Math.ceil(p.minimumWage * work / 60);'),
          true);
    });

    test('제안 writer가 커밋 전에 호출한다', () {
      final at = offer.indexOf('srvValidateMinimumWagePromise({');
      expect(at, greaterThan(-1));
      final tx = offer.indexOf('await db.runTransaction(async (offerTx)');
      expect(at < tx, true, reason: '트랜잭션보다 먼저여야 상태가 남지 않는다');
    });

    test('위반이면 throw한다', () {
      expect(
          offer.contains('if (violation) { throw new HttpsError('
              '"failed-precondition", violation); }'),
          true);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // PART K — 권한
  // ══════════════════════════════════════════════════════════════════

  group('개별 급여 제안은 canManageWage가 따로 필요하다', () {
    test('서버가 강제한다', () {
      expect(
          offer.contains('if (offerIsMatch && offerPerms.canManageWage !== true) { '
              'throw new HttpsError( "permission-denied", '
              '"개별 급여 제안 권한이 필요합니다.");'),
          true);
    });

    test('TARGET_BASE는 canManageTo만 본다', () {
      expect(offer.contains('if (offerPerms.canManageTo !== true) {'), true);
      // canManageWage 검사가 canManageTo 검사와 별개 조건이어야 한다.
      expect(offer.contains('offerIsMatch && offerPerms.canManageWage'), true);
    });

    test('UI도 같은 권한을 본다', () {
      final s = _load(_sheet);
      expect(s.contains('required bool canManageWage,'), true);
      expect(
          s.contains('final matchEnabled = sameType && canManageWage && sourceWage > 0;'),
          true);
    });

    test('권한이 없어도 옵션을 숨기지 않는다', () {
      final s = _load(_sheet);
      expect(s.contains("? '개별 급여 제안 권한이 필요합니다.'"), true);
      expect(s.contains('if (!enabled && disabledReason != null)'), true,
          reason: '부재를 "그런 기능 없음"으로 보이게 하지 않는다');
    });

    test('MATCH가 막혀도 업무 제안 자체는 계속된다', () {
      final s = _load(_sheet);
      // TARGET_BASE 옵션은 언제나 enabled: true 다.
      expect(
          s.contains("label: '공고 기본 급여', amount: sel.formattedWage, "
              'value: optionTargetBase, groupValue: option, enabled: true,'),
          true);
    });

    test('다른 권한을 섞지 않는다', () {
      expect(offer.contains('canManageContract'), false);
      expect(offer.contains('canManageWorkers'), false);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // PART L — 감사
  // ══════════════════════════════════════════════════════════════════

  group('감사 chain이 닫힌다', () {
    test('제안 당시 공고 기본급이 숫자로 남는다', () {
      expect(
          offer.contains('baseCompensationSnapshotAtOffer: { ...targetBaseSnapshot, '
              'wage: targetBaseWage ?? null, wageType: offeredWageType ?? null, },'),
          true);
    });

    test('약정 급여도 숫자로 남는다', () {
      expect(
          offer.contains('offeredCompensationSnapshot: { ...offeredSnapshot, '
              'wage: offeredWage ?? null, wageType: offeredWageType ?? null, },'),
          true);
    });

    test('어느 옵션이었는지 남는다', () {
      expect(offer.contains('compensationOption,'), true);
      expect(
          offer.contains('compensationSource: offerIsMatch ? '
              '"ALTERNATIVE_WORK_OFFER_MATCH_SOURCE" : "ALTERNATIVE_WORK_OFFER",'),
          true);
    });

    test('누가 언제 제안했는지 남는다', () {
      expect(offer.contains('offeredBy: callerUid,'), true);
      expect(offer.contains('offeredAt: offerTime,'), true);
      expect(offer.contains('offerId,'), true);
      expect(offer.contains('sourceApplicationId,'), true);
    });

    test('조건이 다른 재전송을 조용히 삼키지 않는다', () {
      expect(
          offer.contains('if (tOption !== compensationOption) { '
              'throw new HttpsError( "already-exists", '
              '"이미 다른 급여 조건으로 제안했습니다. "'),
          true,
          reason: '관리자가 보냈다고 믿는 금액과 실제가 갈리면 안 된다');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // 자연키 — 같은 이름 업무 fail-closed
  // ══════════════════════════════════════════════════════════════════

  group('어느 업무인지 모르면 고르지 않는다', () {
    test('공용 matcher가 있다', () {
      expect(cf.contains('function srvMatchWorkDetail('), true);
      expect(apply.contains('srvMatchWorkDetail(rawWD, workDetailId ?? undefined'),
          true);
      expect(apply.contains('srvMatchWorkDetail(rawWDList, workDetailId ?? undefined'),
          true);
    });

    test('wdId가 composite보다 먼저다', () {
      expect(
          cf.contains('const byWdId = list.find((d) => d["wdId"] === workDetailId);'),
          true);
    });

    test('workType 폴백은 후보가 하나일 때만', () {
      expect(cf.contains('if (byType.length === 1) return byType[0];'), true);
      expect(
          cf.contains('"같은 이름의 업무가 여러 개 있어 어느 업무인지 특정할 수 없습니다. "'),
          true,
          reason: '첫 번째를 고르면 지원자가 고르지 않은 조건이 약속이 된다');
    });

    test('제안은 문서 id가 아니라 관계로 중복을 본다', () {
      // 직접 지원은 composite, 초대·제안은 wdId를 discriminator로 쓴다.
      expect(
          offer.contains('const offerAltKeyed = offerRelSnap.docs.find( '
              '(d) => d.id !== targetAppId && d.get("wdId") === targetWdId);'),
          true);
      expect(offer.contains('const freshAlt = await offerTx.get(offerAltKeyed.ref);'),
          true, reason: '트랜잭션 읽기 집합에 넣어야 경합에 안전하다');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // PART N — 근로자 화면
  // ══════════════════════════════════════════════════════════════════

  group('근로자에게는 실제 수락할 조건이 primary다', () {
    final m = _load('lib/screens/user/my_applications_screen.dart');

    test('개별 급여 여부를 모델이 말한다', () {
      expect(
          _load(_appModel).contains('bool get hasIndividualCompensation => '
              "compensationOption == 'MATCH_SOURCE_WAGE';"),
          true);
    });

    test('제안 급여를 앞에 세운다', () {
      expect(m.contains("'\${app.formattedWage} · 회원님께 제안된 급여입니다',"), true);
    });

    test('공고 기본급을 경쟁 truth로 띄우지 않는다', () {
      expect(m.contains('공고 기본 급여'), false);
    });
  });
}
