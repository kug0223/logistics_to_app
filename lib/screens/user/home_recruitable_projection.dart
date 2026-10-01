// lib/screens/user/home_recruitable_projection.dart
//
// [R7-P4.4E.8A] 홈이 "그 날짜에 지원할 수 있는 공고" 를 판단하는 **단일 계산**.
//
// 왜 필요했나
//   홈은 두 곳에서 각각 판단하고 있었고, 두 곳 모두 지원서가 있으면
//   **공고 전체를 버렸다**(`appliedToIds.contains(to.id)`).
//     · 날짜칩 카운트  `_toDateCounts`
//     · 추천 목록      `_getRecommendedTos`
//   그래서 flex 공고의 10/05 에 지원하면 10/06~10/11 의 **다른 날짜 모집까지**
//   홈에서 사라졌다. DEV 실측: 6일 × 2업무 = **12개의 실제 지원 가능한 근무**가
//   사라졌고, 공고가 1건뿐인 DEV 에서는 모든 날짜 칩이 0 이 됐다.
//   Jobs 목록·공고 상세·서버는 같은 사실을 다르게 말하고 있었다.
//
// 무엇을 바꿨나
//   지원 = 관심이고, flex 의 모집 단위는 **날짜 × 근무(wdId)** 다.
//   그래서 공고를 버리지 않고 **그 날짜에 신규 지원 가능한 근무가 하나라도
//   남아 있는가**로 판단한다. 관계가 있는 wdId 만 빠지고 형제 wdId 는 산다.
//
// 모르는 것을 "없다"로 바꾸지 않는다
//   슬롯 날짜를 모르거나(불완전) 슬롯을 읽지 못한 경우는 **남긴다** —
//   서버가 최종 판정한다. 기존 홈이 이미 그렇게 적어 둔 원칙이다.
import '../../models/core/application_model.dart';
import '../../models/core/slot_model.dart';
import '../../models/core/to_model.dart';
import '../../utils/format_helper.dart';
import '../../widgets/dialogs/apply/application_relation.dart';

/// 날짜(KST 정규화) → 그 날짜에 신규 지원 가능한 공고 id 집합.
class HomeRecruitableProjection {
  const HomeRecruitableProjection({
    required this.byDate,
    required this.unknownDateToIds,
  });

  /// 날짜별 모집 가능한 공고 id.
  final Map<DateTime, Set<String>> byDate;

  /// 근무 날짜를 **확실히 알 수 없는** 공고 — 어느 날짜에서도 지우지 않는다.
  /// (flex 인데 `dates` 가 비었거나 불완전한 경우. 서버가 판정한다.)
  final Set<String> unknownDateToIds;

  /// 그 날짜에 이 공고를 보여줘도 되는가.
  bool isRecruitable(String toId, DateTime dateKey) =>
      unknownDateToIds.contains(toId) ||
      (byDate[dateKey]?.contains(toId) ?? false);

  /// 날짜와 무관하게 — 어느 하루라도 모집 가능한가.
  bool hasAnyDate(String toId) =>
      unknownDateToIds.contains(toId) ||
      byDate.values.any((s) => s.contains(toId));

  /// 그 날짜의 공고 수. 홈의 `일자리 N개` 는 **공고 수**다(업무 수가 아니다).
  int countOn(DateTime dateKey) =>
      (byDate[dateKey]?.length ?? 0) + unknownDateToIds.length;

  static const _dowLabels = ['월', '화', '수', '목', '금', '토', '일'];

  /// [slotsByToId] 는 **관계가 있는 공고에만** 채워 넣는다.
  ///   비어 있으면 그 공고의 그 날짜는 "관계 없음" 으로 판단되어 남는다 —
  ///   읽지 못한 것을 못 뽑은 것으로 바꾸지 않는다.
  static HomeRecruitableProjection build({
    required List<TOModel> publishedTos,
    required List<ApplicationModel> myApplications,
    required DateTime today,
    required DateTime cutoff,
    Map<String, List<SlotModel>> slotsByToId = const {},
  }) {
    final byDate = <DateTime, Set<String>>{};
    final unknown = <String>{};

    void mark(DateTime d, String toId) =>
        (byDate[d] ??= <String>{}).add(toId);

    for (final to in publishedTos) {
      if (!_isCandidate(to)) continue;

      if (to.isFlexType) {
        // 근무 날짜를 모르면 지우지 않는다.
        if (to.slotDateKeys.isEmpty || !to.slotDatesLookComplete) {
          unknown.add(to.id);
          continue;
        }
        final slots = slotsByToId[to.id];
        for (final key in to.slotDateKeys) {
          final d = FormatHelper.parseKstDateKey(key);
          if (d == null) continue;
          if (d.isBefore(today) || d.isAfter(cutoff)) continue;
          if (_flexRecruitableOn(
              to: to, date: d, myApplications: myApplications, slots: slots)) {
            mark(d, to.id);
          }
        }
        continue;
      }

      // ── 장기·계약형 ─────────────────────────────────────────
      //   이쪽은 지원서 하나가 **기간 전체**에 대한 관계다 — 날짜별 근무가
      //   따로 모집되지 않는다. 그래서 관계가 있으면 공고 단위로 빠지는 것이
      //   맞다. 다만 **상태를 본다** — 거절·취소·만료는 서버가 재지원을
      //   허용하므로 여기서도 자격이 돌아와야 한다.
      if (_hasActiveRelationForTo(to, myApplications)) continue;

      final rawS = to.hasWorkStartAvailableRange
          ? to.workStartAvailableFrom
          : to.rangeStart;
      final rawE = to.hasWorkStartAvailableRange
          ? to.workStartAvailableUntil
          : to.rangeEnd;
      if (rawS == null) continue;
      final rangeS = FormatHelper.toKstDate(rawS);
      final rangeE = rawE != null ? FormatHelper.toKstDate(rawE) : null;
      final start = rangeS.isBefore(today) ? today : rangeS;
      final end = rangeE == null
          ? cutoff
          : (rangeE.isAfter(cutoff) ? cutoff : rangeE);
      if (start.isAfter(end)) continue;
      var cur = start;
      while (!cur.isAfter(end)) {
        final label = _dowLabels[cur.weekday - 1];
        if (to.type != 'contract' ||
            to.workDays.isEmpty ||
            to.workDays.contains(label)) {
          mark(cur, to.id);
        }
        cur = cur.add(const Duration(days: 1));
      }
    }

    return HomeRecruitableProjection(
        byDate: byDate, unknownDateToIds: unknown);
  }

  /// 공고 자체가 후보인가 — 기존 홈 필터와 같은 기준.
  static bool _isCandidate(TOModel to) {
    if (to.status == TOStatus.closed ||
        to.status == TOStatus.expired ||
        to.status == TOStatus.scheduled) {
      return false;
    }
    if (to.isDeleted) return false;
    // [R8-P9D] 공고 전체 정원은 flex 를 닫는 근거가 아니다 — 한 날짜가 찼다고
    //   다른 날짜 모집까지 사라지면 안 된다. 서버도 그렇게 정해 두었다.
    if (!to.isFlexType &&
        (to.status == TOStatus.full ||
            (to.totalRequired > 0 &&
                to.totalConfirmed >= to.totalRequired))) {
      return false;
    }
    return true;
  }

  /// 이 공고에 **활성 관계**가 하나라도 있는가(장기·계약형 전용).
  static bool _hasActiveRelationForTo(
      TOModel to, List<ApplicationModel> apps) {
    for (final app in apps) {
      if (app.toId != to.id) continue;
      if (app.isExitDecided) continue;
      final s = app.status;
      if (s == AppStatus.pending ||
          s == AppStatus.contractPending ||
          s == AppStatus.confirmed ||
          s == AppStatus.invited) {
        return true;
      }
    }
    return false;
  }

  /// flex: 그 날짜에 **신규 지원 가능한 근무가 하나라도** 남아 있는가.
  static bool _flexRecruitableOn({
    required TOModel to,
    required DateTime date,
    required List<ApplicationModel> myApplications,
    required List<SlotModel>? slots,
  }) {
    // 그 날짜에 내가 가진 활성 관계들.
    final relatedOnDate = myApplications.where((a) {
      if (a.toId != to.id) return false;
      if (FormatHelper.toKstDate(a.workDate) != date) return false;
      if (a.isExitDecided) return false;
      final s = a.status;
      return s == AppStatus.pending ||
          s == AppStatus.contractPending ||
          s == AppStatus.confirmed ||
          s == AppStatus.invited;
    }).toList();

    // 관계가 없으면 그 날짜는 그대로 모집 중이다 — 슬롯을 읽을 이유가 없다.
    //   (슬롯 openness 는 기존 홈과 같은 수준으로 `dates` 로 근사한다.
    //    모르면 노출하고 서버가 판정한다 — 거짓 0 을 만들지 않는 쪽이다.)
    if (relatedOnDate.isEmpty) return true;

    // 관계가 있으면 **그 날짜의 슬롯**을 정확히 본다.
    SlotModel? slot;
    for (final s in slots ?? const <SlotModel>[]) {
      if (FormatHelper.toKstDate(s.date) == date) {
        slot = s;
        break;
      }
    }

    // 슬롯을 읽지 못했다 — 모르는 것을 "없다"로 바꾸지 않는다.
    if (slot == null) return true;
    if (slot.isClosed) return false;

    for (final wd in slot.workDetails) {
      if (wd.isClosed || wd.isTimeExpired) continue;
      // 그 근무가 이미 찼는가 — 날짜별 카운터로 본다.
      final c = slot.workDetailCounts[wd.canonicalId];
      if (wd.requiredCount > 0 &&
          c != null &&
          c.confirmedCount >= wd.requiredCount) {
        continue;
      }
      // 같은 판정을 쓴다 — E7 의 resolver. slotId + wdId 가 축이다.
      final relation = ApplicationRelationResolver.resolve(
        myApplications: relatedOnDate,
        toId: to.id,
        slotId: slot.id,
        work: wd,
      );
      if (!relation.blocksNewApplication) return true;
    }
    return false;
  }
}
