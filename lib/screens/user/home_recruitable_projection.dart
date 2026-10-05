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
import '../../models/core/work_detail_data.dart';
import '../../utils/format_helper.dart';
import '../../widgets/dialogs/apply/application_relation.dart';
import '../../widgets/dialogs/apply/commitment_conflict.dart';

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
  ///
  /// [commitmentsKnown] 은 **내 지원 목록을 읽었는가**다. 못 읽었으면 약속
  ///   충돌을 판정할 수 없고(`unknown`), 그때는 후보를 지우지 않는다 —
  ///   읽기 실패를 "지원 가능" 으로도 "지원 불가" 로도 바꾸지 않는다.
  ///   화면은 자신의 ERROR/PARTIAL 배너로 그 사실을 따로 말한다.
  static HomeRecruitableProjection build({
    required List<TOModel> publishedTos,
    required List<ApplicationModel> myApplications,
    required DateTime today,
    required DateTime cutoff,
    Map<String, List<SlotModel>> slotsByToId = const {},
    bool commitmentsKnown = true,
  }) {
    final byDate = <DateTime, Set<String>>{};
    final unknown = <String>{};

    // [R7-APPLICATION-LIFECYCLE.1C] 홈은 "그 날짜에 **지원할 수 있는** 공고" 를
    //   말한다. 서버 `callableApplyToTO` 가 결정적으로 거부하는 관계를 세면
    //   그 수치 자체가 거짓이다. 판정은 화면마다 만들지 않고 공용 owner 가
    //   한다 — 입력은 이미 읽은 지원 목록이고 새 쿼리는 없다.
    final commitments =
        CommitmentConflictResolver.commitmentsOf(myApplications);

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
              to: to,
              date: d,
              myApplications: myApplications,
              slots: slots,
              commitments: commitments,
              commitmentsKnown: commitmentsKnown)) {
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
          if (_longTermCandidateFreeOn(
              to: to,
              startDate: cur,
              commitments: commitments,
              commitmentsKnown: commitmentsKnown)) {
            mark(cur, to.id);
          }
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

  /// 장기·계약형: [startDate] 부터 시작하는 계약이 내 약속과 겹치지 않는가.
  ///
  ///   업무가 여러 개면 **하나라도** 겹치지 않으면 그 날짜는 모집 가능이다
  ///   (§67 — 공고 단위 수치이므로 형제 업무가 살아 있으면 1로 센다).
  ///   종료일은 공고의 canonical 계산(`computeContractEndDate`)을 쓴다 —
  ///   화면용 종료일 식을 새로 만들면 또 두 벌이 된다.
  ///   업무 시간을 모르면 남긴다 — 서버가 판정한다.
  static bool _longTermCandidateFreeOn({
    required TOModel to,
    required DateTime startDate,
    required List<ApplicationModel> commitments,
    required bool commitmentsKnown,
  }) {
    if (to.workDetails.isEmpty) return true;
    final endDate = to.computeContractEndDate(startDate);
    for (final wd in to.workDetails) {
      final decision = CommitmentConflictResolver.forLongTerm(
        commitments: commitments,
        commitmentsKnown: commitmentsKnown,
        startDate: startDate,
        endDate: endDate,
        workDays: to.workDays,
        startTime: wd.startTime,
        endTime: wd.endTime,
      );
      if (!decision.blocksNewApplication) return true;
    }
    return false;
  }

  /// flex: 그 날짜에 **신규 지원 가능한 근무가 하나라도** 남아 있는가.
  static bool _flexRecruitableOn({
    required TOModel to,
    required DateTime date,
    required List<ApplicationModel> myApplications,
    required List<SlotModel>? slots,
    required List<ApplicationModel> commitments,
    required bool commitmentsKnown,
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

    // 그 날짜의 슬롯 — 있으면 업무·정원·시간의 canonical 출처다.
    SlotModel? slot;
    for (final s in slots ?? const <SlotModel>[]) {
      if (FormatHelper.toKstDate(s.date) == date) {
        slot = s;
        break;
      }
    }

    // 슬롯을 읽지 못했는데 그 날짜에 관계가 있다 — 어느 업무에 걸린
    //   관계인지 모른다. 모르는 것을 "없다"로 바꾸지 않는다.
    if (slot == null && relatedOnDate.isNotEmpty) return true;
    if (slot != null && slot.isClosed) return false;

    // [R7-APPLICATION-LIFECYCLE.1C] 약속 충돌은 **슬롯 유무와 무관하게** 본다.
    //   슬롯을 못 읽었어도 업무 시간은 공고 템플릿(`to.workDetails`)에 있다 —
    //   그래서 추가 읽기 없이 판정할 수 있다. 템플릿이 비어 있으면 시간을
    //   모르는 것이므로 남긴다.
    final works = slot?.workDetails ?? to.workDetails;
    if (works.isEmpty) return true;

    for (final wd in works) {
      if (slot != null) {
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
        if (relation.blocksNewApplication) continue;
      }
      if (_commitmentConflictOn(
          date: date,
          work: wd,
          commitments: commitments,
          commitmentsKnown: commitmentsKnown)) {
        continue;
      }
      return true;
    }
    return false;
  }

  /// 이 날짜·이 업무가 내 약속과 겹치는가. `unknown` 은 막지 않는다.
  static bool _commitmentConflictOn({
    required DateTime date,
    required WorkDetailData work,
    required List<ApplicationModel> commitments,
    required bool commitmentsKnown,
  }) =>
      CommitmentConflictResolver.forShortTerm(
        commitments: commitments,
        commitmentsKnown: commitmentsKnown,
        workDate: date,
        startTime: work.startTime,
        endTime: work.endTime,
      ).blocksNewApplication;
}
