import '../models/core/attendance_model.dart';
import '../models/core/work_detail_data.dart';
import 'format_helper.dart';

/// [F293-WAGE-01 · 판정293 §C] 시급 업무의 **하루 예상 금액** — 표시 전용 계산·서식의 유일한 자리.
///
///   하루 = 선택한 업무의 **예정 근무 1회**다(달력 24시간 · 모든 업무 합이 아니다). 야간 익일 종료도 시작일에 귀속한다.
///   식: 체류분 = 종료 − 시작(종료 < 시작이면 +1,440 · **종료 = 시작은 24시간으로 만들지 않는다**) ·
///        순근무분 = 체류분 − 등록된 무급 휴게분 · 금액 = round(시급 × 순근무분 ÷ 60) — 업무·근무 1회마다 원 단위 반올림.
///   전체 예정분을 **기본 시급 1배**로 환산한다. 8시간 초과 연장 · 야간 · 휴일 가산을 넣지 않는다 — 확정 급여 엔진
///   (`wage_calculator.dart`)과 다른 목적이다. 급여 확정 · 계약 · 이체 저장값과 `wageType` 은 바꾸지 않는다.
///   시급은 그 업무의 `wage` 다(일급용 `baseHourlyWage` 로 대체하지 않는다).
///
///   만들지 않는 경우(= **예상 금액 확인 필요**, 0원 표시 금지): 시급이 양수가 아님 · 시각 불명/형식 오류 · 종료 = 시작 ·
///   휴게 불명(null) · 음수 휴게 · 체류 이상의 휴게 · 순근무 ≤ 0. 누락 시각에서 임의 09:00–18:00 금액을 만들지 않는다.
enum ExpectedWageKind {
  /// 하루 예상 금액이 있다.
  estimate,

  /// 시급 업무인데 계산 입력이 불완전하다 — 시급 원값은 보일 수 있지만 금액은 만들지 않는다.
  needsCheck,

  /// 시급 업무가 아니다(일급 · 월급 · 유형 모름) — 이 helper 는 금액을 만들지 않는다(기존 표시 그대로).
  notHourly,
}

class ExpectedDailyWage {
  const ExpectedDailyWage._(this.kind,
      {this.amount, this.rate, this.stayMinutes, this.netMinutes, this.wageType, this.typeUnknown = false});

  final ExpectedWageKind kind;

  /// 하루 예상 금액(원) — [ExpectedWageKind.estimate] 일 때만.
  final int? amount;

  /// 시급 원값 — 유효한 양수일 때만.
  final int? rate;

  /// 예정 체류분 · 순근무분 — 계산에 쓴 값(시간 보조 표시가 같은 값을 쓴다).
  final int? stayMinutes;
  final int? netMinutes;

  /// 입력 급여 유형(그대로).
  final String? wageType;

  /// [F294-WAGE-01 · C294-WAGE-A] 급여 유형을 **모른다**(공고 원문에 없거나 모르는 값 · 모델 기본 'hourly' 가 아님).
  ///   소비처는 이때 모델의 `wageTypeLabel`(기본 '시급') · 원시 금액으로 돌아가지 않는다 — '급여 확인 필요'.
  final bool typeUnknown;

  bool get isEstimate => kind == ExpectedWageKind.estimate;
  bool get isHourly => kind != ExpectedWageKind.notHourly;

  /// 엄격한 'HH:mm'(00–23 · 00–59) → 분. 아니면 null.
  static int? parseHm(String? s) {
    if (s == null) return null;
    final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(s.trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final mi = int.parse(m.group(2)!);
    if (h > 23 || mi > 59) return null;
    return h * 60 + mi;
  }

  /// 예정 체류분. 종료 < 시작이면 다음날(+1,440). 종료 = 시작 · 형식 오류는 null(24시간으로 만들지 않는다).
  static int? stayMinutesOf(String? start, String? end) {
    final s = parseHm(start);
    final e = parseHm(end);
    if (s == null || e == null || s == e) return null;
    return e > s ? e - s : e + 1440 - s;
  }

  /// 순근무분 — 휴게 null(모름) · 음수 · 체류 이상이면 null.
  static int? netMinutesOf(String? start, String? end, int? breakMinutes) {
    final stay = stayMinutesOf(start, end);
    if (stay == null || breakMinutes == null || breakMinutes < 0) return null;
    final net = stay - breakMinutes;
    return net > 0 ? net : null;
  }

  /// 계산 본체. [wageType] null = 유형 모름(시급이라 부르지 않는다) · [breakMinutes] null = 휴게 모름.
  static ExpectedDailyWage compute({
    required String? wageType,
    required int? rate,
    required String? startTime,
    required String? endTime,
    required int? breakMinutes,
  }) {
    if (wageType != 'hourly') {
      const known = {'daily', 'monthly'};
      return ExpectedDailyWage._(ExpectedWageKind.notHourly,
          wageType: wageType, typeUnknown: !known.contains(wageType),
          // 유효한 원시 단가만 남긴다(누락 0 은 남기지 않는다 · C294-WAGE-C).
          rate: (rate != null && rate > 0) ? rate : null);
    }
    final validRate = (rate != null && rate > 0) ? rate : null;
    final stay = stayMinutesOf(startTime, endTime);
    final net = netMinutesOf(startTime, endTime, breakMinutes);
    if (validRate == null || net == null) {
      return ExpectedDailyWage._(ExpectedWageKind.needsCheck,
          rate: validRate, stayMinutes: stay, wageType: wageType);
    }
    return ExpectedDailyWage._(ExpectedWageKind.estimate,
        amount: (validRate * net / 60).round(),
        rate: validRate,
        stayMinutes: stay,
        netMinutes: net,
        wageType: wageType);
  }

  /// 공고 업무 정의(posting map) — 휴게 필드 부재는 정본 writer 가 0 을 생략한 것이라 정상 0 이다
  ///   (`WorkDetailData.toMap`). 단 시각·유형이 원문에 없어 `fromMap` 이 기본값을 넣은 자료는 계산하지 않는다.
  static ExpectedDailyWage forWorkDetail(WorkDetailData wd) => compute(
        wageType: wd.wageTypeFromSource ? wd.wageType : null,
        rate: wd.wage,
        startTime: wd.scheduleFromSource ? wd.startTime : null,
        endTime: wd.scheduleFromSource ? wd.endTime : null,
        breakMinutes: wd.breakMinutes,
      );

  /// [F293-WAGE-01 · C294-WAGE-D] 예상 단계 — 근태가 없거나, 급여 산정 전이고 노쇼/결근이 아니다.
  ///   산정·확정 단계(HB3 미공개 금액 포함)에서는 예상액을 보이지 않는다. 일정 카드와 그 카드가 여는 상세가 같은 판정을 쓴다.
  static bool isExpectedStage(AttendanceModel? att) =>
      att == null ||
      (att.isWagePending &&
          att.status != AttendanceModel.statusNoShow &&
          att.status != AttendanceModel.statusAbsent);

  /// 지원·초대 약속 조건 — 휴게는 nullable 그대로(null = 모름 → 확인 필요 · 임의 0 금지).
  ///   시각은 **그 화면이 실제로 보여 주는 원천**을 호출자가 넘긴다(표시 시각 = 계산 입력).
  ///   지원서의 유형 결측(null · 레거시)은 모델이 시급으로 채우지 않는 값이다 — 예전 표시(단위 없는 금액)를 지킨다
  ///   (`typeUnknown` 은 공고 정의의 '기본값으로 채운 유형' 에만 쓴다).
  static ExpectedDailyWage forPromise({
    required String? wageType,
    required int? rate,
    required String? startTime,
    required String? endTime,
    required int? breakMinutes,
  }) {
    if (wageType == null) {
      return ExpectedDailyWage._(ExpectedWageKind.notHourly,
          rate: (rate != null && rate > 0) ? rate : null);
    }
    return compute(
        wageType: wageType,
        rate: rate,
        startTime: startTime,
        endTime: endTime,
        breakMinutes: breakMinutes);
  }
}

/// 여러 업무(화면이 실제로 대표하는 집합)를 **업무별로 환산한 뒤** 모은 것.
class ExpectedWageRange {
  const ExpectedWageRange._({
    required this.total,
    required this.estimated,
    required this.needsCheck,
    required this.notHourly,
    required this.unknownType,
    required this.knownTypes,
    this.minAmount,
    this.maxAmount,
    this.minRate,
    this.maxRate,
  });

  final int total;
  final int estimated;
  final int needsCheck;
  final int notHourly;

  /// [C294-WAGE-A] 유형을 모르는 업무 수 · [C294-WAGE-B] 알려진 유형의 가짓수(hourly/daily/monthly).
  final int unknownType;
  final int knownTypes;
  final int? minAmount;
  final int? maxAmount;

  /// 시급 원값 범위 — 유효한 시급 업무들의 실제 범위(금액 범위와 따로).
  final int? minRate;
  final int? maxRate;

  /// 모든 업무가 시급이고 모두 금액이 있다 — 이때만 완전한 범위를 말한다.
  bool get complete => total > 0 && estimated == total;

  /// 한 단위로 말할 수 없다 — 유형이 둘 이상 섞였거나(시급+일급 · **일급+월급**) 유형을 모르는 업무가 있다.
  ///   이때 화면은 첫 업무 유형 · 원시 min/max 로 합치지 않고 '업무별 급여 확인'(하나뿐이면 '급여 확인 필요').
  bool get mixed => unknownType > 0 || knownTypes > 1;

  bool get anyHourly => notHourly < total;

  static ExpectedWageRange of(Iterable<ExpectedDailyWage> items) {
    var total = 0, est = 0, chk = 0, nh = 0, unk = 0;
    final types = <String>{};
    int? minA, maxA, minR, maxR;
    for (final e in items) {
      total++;
      if (e.typeUnknown) {
        unk++;
      } else if (e.wageType != null) {
        types.add(e.wageType!);
      }
      switch (e.kind) {
        case ExpectedWageKind.estimate:
          est++;
          minA = minA == null || e.amount! < minA ? e.amount : minA;
          maxA = maxA == null || e.amount! > maxA ? e.amount : maxA;
        case ExpectedWageKind.needsCheck:
          chk++;
        case ExpectedWageKind.notHourly:
          nh++;
      }
      final r = e.rate;
      if (e.kind != ExpectedWageKind.notHourly && r != null) {
        minR = minR == null || r < minR ? r : minR;
        maxR = maxR == null || r > maxR ? r : maxR;
      }
    }
    return ExpectedWageRange._(
        total: total, estimated: est, needsCheck: chk, notHourly: nh,
        unknownType: unk, knownTypes: types.length,
        minAmount: minA, maxAmount: maxA, minRate: minR, maxRate: maxR);
  }

  static ExpectedWageRange ofWorkDetails(Iterable<WorkDetailData> wds) =>
      of(wds.map(ExpectedDailyWage.forWorkDetail));
}

/// 표시 문구 — 화면은 이 문장만 쓴다(복제식 금지).
class ExpectedWageText {
  ExpectedWageText._();

  /// 카드의 짧은 말.
  static const String shortNote = '예상·세전';

  /// 상세·지원 확인의 고지 정본(판정293 §C — 문구 그대로).
  static const String disclosure =
      '등록된 시급과 근무시간에서 무급 휴게를 뺀 세전 예상 금액이에요. '
      '별도 수당을 추가 계산하거나 공제를 차감하지 않았어요. '
      '최종 급여는 실제 근무와 급여 확정 내역에 따라 달라져요.';

  static const String needsCheck = '예상 금액 확인 필요';
  static const String perWorkCheck = '업무별 예상 금액 확인';
  static const String perWorkWage = '업무별 급여 확인';

  /// [F294-WAGE-01] 업무 하나의 유형·단가를 알 수 없을 때(모델 기본 '시급' · 누락 0원으로 말하지 않는다).
  static const String wageUnknown = '급여 확인 필요';

  /// 원시 단가 표시 — 유효한 양수만 금액으로, 누락(0 이하)은 [wageUnknown](큰 '0원' 금지 · C294-WAGE-C).
  static String rawWage(int wage) => wage > 0 ? _won(wage) : wageUnknown;

  /// [AUD-3 M3 · 판정296] 월 예정 수입처럼 **합계의 일부를 계산할 수 없을 때**(unknownShifts > 0) — 부분합이나 0원을
  ///   전체 금액처럼 말하지 않는다. 모두 계산 가능 → '22,000원' · 일부만 → '22,000원 + 확인 필요' · 하나도 없음 → '확인 필요'.
  static String partialTotal(int total, int unknownShifts) => unknownShifts <= 0
      ? _won(total)
      : (total == 0 ? '확인 필요' : '${_won(total)} + 확인 필요');

  static String _won(int v) => FormatHelper.formatWage(v);
  static String _span(int a, int b) =>
      a == b ? _won(a) : '${FormatHelper.formatNumber(a)}~${_won(b)}';

  /// 주금액 한 줄 — 업무 하나.
  ///   estimate → '하루 예상 22,000원' · needsCheck → '예상 금액 확인 필요' · notHourly → null(기존 표시 유지).
  static String? daily(ExpectedDailyWage e) => switch (e.kind) {
        ExpectedWageKind.estimate => '하루 예상 ${_won(e.amount!)}',
        ExpectedWageKind.needsCheck => needsCheck,
        // [C294-WAGE-A] 유형을 모르면 기존 표시(모델 기본 '시급')로 돌려보내지 않는다.
        ExpectedWageKind.notHourly => e.typeUnknown ? wageUnknown : null,
      };

  /// 보조 시급 — '시급 11,000원'(유효한 시급일 때만).
  static String? rate(ExpectedDailyWage e) =>
      e.isHourly && e.rate != null ? '시급 ${_won(e.rate!)}' : null;

  /// 한 줄 요약(약속 카드 · 일정 · 내 지원처럼 금액 줄이 하나인 자리) — 주금액 먼저, 시급 보조.
  ///   estimate → '하루 예상 22,000원 · 시급 11,000원' · needsCheck → '시급 11,000원 · 예상 금액 확인 필요'(시급 모르면 문구만) ·
  ///   notHourly → null(기존 표시 유지).
  static String? combined(ExpectedDailyWage e) {
    switch (e.kind) {
      case ExpectedWageKind.estimate:
        return '하루 예상 ${_won(e.amount!)} · 시급 ${_won(e.rate!)}';
      case ExpectedWageKind.needsCheck:
        return e.rate != null ? '시급 ${_won(e.rate!)} · $needsCheck' : needsCheck;
      case ExpectedWageKind.notHourly:
        // [C294-WAGE-A] 유형을 모르면 '급여 확인 필요'(기존 표시 = 모델 기본 '시급' 으로 돌아가지 않는다).
        return e.typeUnknown ? wageUnknown : null;
    }
  }

  /// 주금액 한 줄 — 여러 업무.
  ///   모두 시급 · 모두 금액 → '하루 예상 22,000원' 또는 '하루 예상 22,000~44,000원'.
  ///   시급만인데 일부 계산 불가 → 하나뿐이면 '예상 금액 확인 필요', 여럿이면 '업무별 예상 금액 확인'(부분 범위를 완전한 범위처럼 말하지 않는다).
  ///   시급과 다른 유형이 섞임 → '업무별 급여 확인'(첫 업무 유형으로 전체를 시급이라 부르지 않는다).
  ///   시급 업무가 없음 → null(기존 표시 유지).
  static String? dailyRange(ExpectedWageRange r) {
    if (r.total == 0) return null;
    // [C294-WAGE-A·B] 유형을 모르거나 유형이 둘 이상이면(일급+월급 포함) 한 단위 범위로 합치지 않는다.
    if (r.mixed) return r.total == 1 ? wageUnknown : perWorkWage;
    if (!r.anyHourly) return null;
    if (r.complete) return '하루 예상 ${_span(r.minAmount!, r.maxAmount!)}';
    return r.total == 1 ? needsCheck : perWorkCheck;
  }

  /// 보조 시급 범위 — 시급 업무만 있을 때 그 실제 범위. 섞였으면 null(유형은 업무별로 보인다).
  static String? rateRange(ExpectedWageRange r) {
    if (!r.anyHourly || r.mixed || r.minRate == null) return null;
    return '시급 ${_span(r.minRate!, r.maxRate!)}';
  }

  /// 지원 확인의 선택 합계 — 같은 확정 선택 집합의 근무별 반올림 금액을 더한다. 하나라도 금액이 없으면 null.
  ///   '하루' 라고 부르지 않는다.
  static String? selectedTotal(Iterable<ExpectedDailyWage> items) {
    var sum = 0;
    var n = 0;
    for (final e in items) {
      if (!e.isEstimate) return null;
      sum += e.amount!;
      n++;
    }
    if (n < 2) return null;
    return '선택한 근무 예상 합계 ${_won(sum)}';
  }

  /// 시간 보조 — 같은 분 계산(종료 = 시작 · 형식 오류는 null). 예: '실근무 8시간' · '실근무 7시간 30분'.
  static String? netTime(int? netMinutes) {
    if (netMinutes == null || netMinutes <= 0) return null;
    final h = netMinutes ~/ 60;
    final m = netMinutes % 60;
    if (h == 0) return '실근무 $m분';
    return m == 0 ? '실근무 $h시간' : '실근무 $h시간 $m분';
  }
}
