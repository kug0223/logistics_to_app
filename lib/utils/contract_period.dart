import 'format_helper.dart';

/// [CONTRACT-PERIOD-RULE] 계약 기간 종료일 — **하나의 규칙**.
///
/// ## 왜 이 파일이 있는가
///
/// 종료일을 만드는 식이 두 벌이었다. 클라이언트(`TOModel.computeContractEndDate`)
/// 와 서버(`callableConfirmApplication`)가 서로 다른 답을 냈고, 지원자는
/// 확정 전에 본 날짜와 다른 날짜로 계약서를 받았다. 전 기간 유형에서
/// 최소 하루, 월말 기산에서는 2~4일 어긋났다.
/// (감사: `docs/r7-contract-monthend-audit.md`)
///
/// 언어가 둘이라 구현 파일은 둘일 수밖에 없다. 그래서 **규칙에 버전을 박고
/// 검증 벡터를 공유한다** — 한쪽만 바뀌면 벡터 대조가 깨진다.
///   · 이 파일 (Dart)
///   · `functions/src/contract_period.ts` (TypeScript)
///   · 공유 벡터 `test/fixtures/contract_period_vectors.json`
///
/// ## 규칙 v2 — KST 달력일 · 초일산입 · 민법 160②③
///
/// 전제(감사에서 실측):
///   · 계약서 제2조는 **날짜 두 개**만 출력한다(`'{start} ~ {end}'`).
///     기간 산식도 "N개월" 문구도 계약서 본문에 없다 → 산식은 코드가 정한다.
///   · `contractStart`/`contractEnd` 는 `formatDateISO` 를 지나 **KST 달력일**
///     문자열로 찍힌다. 시각 성분은 계약서에 없다.
///   · `workEndDate` 의 의미는 **마지막 근무 가능일(inclusive)** 이다
///     (`effectiveEndDate` · `occupiesSeatOn` · `isWorkingOnDate` 세 곳 일치).
///
/// 그래서 기간은 **시작일 0시부터 시작하는 달력 기간**으로 본다
/// (민법 제157조 단서 — 초일산입).
///
///   일 단위 (`15days`)
///     마지막 유효일 = 시작일 + (15 - 1)일        · 시작일 포함 15일
///
///   월·연 단위 (`1month`/`3months`/`6months`/`1year`) — 민법 제160조
///     ② 해당일이 있으면 → 마지막 유효일 = **해당일의 전일**
///     ③ 최종 월에 해당일이 없으면 → 마지막 유효일 = **그 월의 말일**
///
///   `custom` 은 이 규칙을 쓰지 않는다 — `rangeEnd` 가 고정값이다.
///
/// ## 무엇이 달라졌나 (v1 → v2)
///
/// v1 클라이언트는 `(시작 + N개월, 월말 clamp) - 1일` 이었다. 월중 기산에서는
/// 160② 와 같은 답이지만, **해당일이 없는 달에서 clamp 후 또 하루를 빼서**
/// 하루 짧았다(1/31 + 1개월 → 2/27). ③ 이 "그 월의 말일" 이라고 정하므로
/// 2/28 이어야 한다.
///
/// v1 서버는 `setMonth(+N)` 뿐이어서 `- 1일` 도 clamp 도 없었고, 게다가
/// **UTC 성분**으로 계산해 KST 자정 기산일이 전날로 읽혔다.
///
/// v2 는 어느 쪽 식도 그대로 승격하지 않는다. 둘 다 고쳐 한 규칙으로 모았다.
const String kContractPeriodRuleVersion = 'v2-kst-civil-160';

/// 이 규칙이 다루는 preset 기간 유형.
const Set<String> kContractPresetPeriodTypes = {
  '15days',
  '1month',
  '3months',
  '6months',
  '1year',
};

/// 유형별 개월 수 (일 단위는 null).
const Map<String, int> _monthsOf = {
  '1month': 1,
  '3months': 3,
  '6months': 6,
  '1year': 12,
};

/// 유형별 일수 (월·연 단위는 null).
const Map<String, int> _daysOf = {
  '15days': 15,
};

/// 계약 기간의 **마지막 유효일**을 KST 달력일 키로 돌려준다.
///
/// [startKstDay] 는 KST 달력일 키다 — `FormatHelper.kstDayKeyOfCivil`(달력에서
/// 고른 날) 또는 `FormatHelper.toKstDate`(저장된 instant)가 만든 값.
/// 기기·서버 시간대와 무관하게 같은 답이 나온다.
///
/// 반환값도 같은 꼴의 키(`DateTime.utc(y, m, d)`)다. 저장할 instant 가
/// 필요하면 [contractPeriodEndInstant] 를 쓴다.
///
/// 규칙 밖의 유형(`custom`, 알 수 없는 값)이면 null — 모르는 것을 날짜로
/// 지어내지 않는다.
DateTime? contractPeriodEndKstDay(DateTime startKstDay, String? periodType) {
  if (periodType == null) return null;

  final days = _daysOf[periodType];
  if (days != null) {
    // 초일산입 — 시작일이 첫날이므로 마지막 날은 +(N-1).
    return DateTime.utc(
        startKstDay.year, startKstDay.month, startKstDay.day + days - 1);
  }

  final months = _monthsOf[periodType];
  if (months == null) return null;

  // 해당일(anniversary)을 먼저 구한다 — 원 기산일의 **일자를 보존**한다.
  final rawMonth = startKstDay.month + months;
  final targetYear = startKstDay.year + (rawMonth - 1) ~/ 12;
  final targetMonth = ((rawMonth - 1) % 12) + 1;
  // 그 달의 말일. `DateTime.utc(y, m + 1, 0)` 은 m 월의 마지막 날이다.
  final lastDayOfTarget = DateTime.utc(targetYear, targetMonth + 1, 0).day;

  if (startKstDay.day > lastDayOfTarget) {
    // ③ 최종 월에 해당일이 없다 → 그 월의 말일로 만료.
    return DateTime.utc(targetYear, targetMonth, lastDayOfTarget);
  }
  // ② 해당일의 전일.
  return DateTime.utc(targetYear, targetMonth, startKstDay.day)
      .subtract(const Duration(days: 1));
}

/// [contractPeriodEndKstDay] 와 같은 판정을, 저장·전송용 **KST 자정 instant**
/// 로 돌려준다.
///
/// 저장소의 DATE_ONLY 관례가 그것이다(`slot.date`·`workDate` 와 같은 꼴,
/// `FormatHelper.kstDayRange` 주석 참조). 서버의 `srvKstDayStartMs` 와도
/// 같은 값이라, 같은 계약의 종료일이 두 쪽에서 bit 단위로 같아진다.
DateTime? contractPeriodEndInstant(DateTime startKstDay, String? periodType) {
  final end = contractPeriodEndKstDay(startKstDay, periodType);
  if (end == null) return null;
  return FormatHelper.kstMidnightOfKstDay(end);
}
