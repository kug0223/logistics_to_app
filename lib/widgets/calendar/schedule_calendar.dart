import 'package:flutter/material.dart';
import '../../models/core/application_model.dart';
import '../../utils/calendar_helper.dart';
import '../../utils/format_helper.dart';
import '../../theme/app_colors.dart';
import 'app_calendar.dart';

/// 사용자 근무 스케줄 캘린더
/// AppCalendar 위에 ApplicationModel 기반 마커를 올린 래퍼.
///
/// Phase 8.1A: 근무 가능일 표시(availabilityDates) + 에디트 모드(isEditMode) 지원.
class ScheduleCalendar extends StatelessWidget {
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final List<ApplicationModel> applications;
  final String selectedFilter;
  final Function(DateTime selectedDay, DateTime focusedDay) onDaySelected;
  final Function(DateTime focusedDay) onPageChanged;
  /// 미리 빌드된 날짜 인덱스 (null이면 O(n) fallback)
  final Map<String, List<ApplicationModel>>? dateIndex;

  // ── Phase 8.1A: 근무 가능일 ──────────────────────────────────
  /// 저장된 근무 가능일 날짜 키 Set ("YYYY-MM-DD").
  /// 평상시에 달력 날짜 아래 파란 dot으로 표시.
  final Set<String>? availabilityDates;

  /// 에디트 모드에서 현재 선택(토글) 중인 날짜 키 Set.
  /// selectedDayPredicateOverride로 파란 원 표시.
  final Set<String>? editingDates;

  /// 에디트 모드 활성화 여부.
  ///   · true: today~+90 이내만 tap 가능, editingDates 원형 표시
  ///   · false: 기존 동작 유지
  final bool isEditMode;

  const ScheduleCalendar({
    super.key,
    required this.focusedDay,
    required this.selectedDay,
    required this.applications,
    required this.selectedFilter,
    required this.onDaySelected,
    required this.onPageChanged,
    this.dateIndex,
    this.availabilityDates,
    this.editingDates,
    this.isEditMode = false,
  });

  @override
  Widget build(BuildContext context) {
    // [E1-KSTDAY] 선택 가능 범위의 기준도 **KST 오늘**이다.
    //   서버(`callableSetAvailability`)와 `filterValidDates` 가 KST day key 로
    //   `today ~ +90일` 을 자르는데, 여기만 기기 날짜를 쓰면 기기 시간대에
    //   따라 **저장되지 않을 날짜를 열어 주게** 된다.
    final kstToday = FormatHelper.toKstDate(DateTime.now());
    final todayOnly = DateTime(kstToday.year, kstToday.month, kstToday.day);
    final maxDate = todayOnly.add(const Duration(days: 90));

    // 에디트 모드 enabledDayPredicate: today~+90 이내만 활성화
    bool editModePredicate(DateTime day) {
      final dayOnly = DateTime(day.year, day.month, day.day);
      return !dayOnly.isBefore(todayOnly) && !dayOnly.isAfter(maxDate);
    }

    // 일반 모드 enabledDayPredicate: 과거는 이벤트 있을 때만, 미래 항상
    bool normalModePredicate(DateTime day) {
      final dayOnly = DateTime(day.year, day.month, day.day);
      if (!dayOnly.isBefore(todayOnly)) return true;
      final events = dateIndex != null
          ? CalendarHelper.getEventsForDayFromIndex(day, dateIndex!)
          : CalendarHelper.getEventsForDay(day, applications, selectedFilter);
      return events.isNotEmpty;
    }

    return AppCalendar(
      focusedDay: focusedDay,
      selectedDay: selectedDay,
      onDaySelected: onDaySelected,
      onPageChanged: onPageChanged,
      rowHeight: 36,
      headerVerticalPadding: 4,
      enabledDayPredicate: isEditMode ? editModePredicate : normalModePredicate,
      // 에디트 모드: 복수 선택 원형 표시 (editingDates Set으로 판단)
      selectedDayPredicateOverride: isEditMode && editingDates != null
          ? (day) => editingDates!.contains(_civilDateKey(day))
          : null,
      eventLoader: (day) => dateIndex != null
          ? CalendarHelper.getEventsForDayFromIndex(day, dateIndex!)
          : CalendarHelper.getEventsForDay(day, applications, selectedFilter),
      markerBuilder: (context, date, events) {
        final apps = events.whereType<ApplicationModel>().toList();
        final dateKey = _civilDateKey(date);

        // 에디트 모드에서는 application 마커 숨기고, 선택 원만 표시
        if (isEditMode) {
          // 에디트 모드에서는 마커 없음 (selectedDayPredicateOverride가 원 표시)
          return null;
        }

        final shortTermApps = apps.where((a) => !a.isLongTermApplication).toList();
        final longTermApps = apps.where((a) => a.isLongTermApplication).toList();

        final hasConfirmed = apps.any((a) => AppStatus.confirmedStatuses.contains(a.status));
        final hasPending = apps.any((a) => a.status == AppStatus.pending);
        // 가능일 파란 dot
        final hasAvailability = availabilityDates?.contains(dateKey) ?? false;

        final markers = <Widget>[];

        // [DU1 후속101 C101-2] 선택(brand 채움)·오늘(brand 30% 채움) 날은 표식 아래 일부가 채운 원 위에 놓인다.
        //   어두운 표식(확정 #166534 · 대기 #E65100(단기 점·장기 별) · 휴무 #757575 · 장기 #946200)은 그 채움과 1.1~2.4:1 이라 흐려지므로,
        //   그날만 표식 둘레에 흰 테두리(halo)를 그려 표식이 흰색과 맞닿게 한다(흰색 대비 3.8~7.1).
        //   그림자(paint)만 더해 표식 크기·위치·개수 규칙과 날짜 탭 영역은 그대로다. 별은 위쪽을 뺀다(_starHalo).
        final onFilled = _isSameCell(selectedDay, date) || _isSameCell(todayOnly, date);

        if (hasConfirmed) {
          final hasShortConfirmed = shortTermApps.any(
              (a) => AppStatus.confirmedStatuses.contains(a.status));
          final hasLongConfirmed = longTermApps.any(
              (a) => AppStatus.confirmedStatuses.contains(a.status));
          final hasLeaveDay = longTermApps.any(
              (a) => AppStatus.confirmedStatuses.contains(a.status) &&
                     a.isLeaveDateOn(date));

          if (hasShortConfirmed) {
            // [DU1 구현100 셀B] 단기 확정 = 홈과 같은 successDark(#166534). 예전 primaryColor(brand 파랑)는
            //   같은 달력의 선택 채움·오늘·가능일 윤곽(모두 파랑 계열)과 같은 색이라 '약속'과 '선택/의향'이 색으로 갈리지 않았고,
            //   같은 화면 근무 카드의 `확정` 배지(초록)와도 달랐다. 형태(채운 점)·위치·개수 규칙은 그대로다.
            markers.add(_dot(AppColors.successDark, isLongTerm: false, halo: onFilled));
          }
          if (hasLongConfirmed) {
            // [DU1 후속101 C101-3] 휴무 별 grey400(#BDBDBD, 흰 바탕 1.88) → grey600(#757575, 4.61).
            // [DU1 후속102 C102-1] 장기 근무 별 amberDark(#FFA000, 흰 2.04 · 선택 채움 2.73) → warningDark(#946200, 흰 5.24).
            //   같은 황색 계열의 진한 값이라 '장기 = 금색 별' 뜻은 그대로고, 대기 점(#E65100 적주황)과는 형태·색상,
            //   휴무 별(회색)과는 채도로 갈린다. 이제 둘 다 어두운 별이라 채움 날에는 같은 흰 테두리를 그린다.
            markers.add(_dot(
              hasLeaveDay ? AppColors.grey600 : AppColors.warningDark,
              isLongTerm: true,
              halo: onFilled,
            ));
          }
        }

        if (hasPending) {
          if (shortTermApps.any((a) => a.status == AppStatus.pending)) {
            // [DU1 후속101 C101-3] 단기 대기 점 warningMedium(#FB8C00, 흰 바탕 2.37) → warningDarkest(#E65100, 3.79).
            //   같은 주황 계열이라 '대기 = 주황 점' 의미와 홈 이번 주 대기 점(같은 색)이 그대로 이어진다.
            markers.add(_dot(AppColors.warningDarkest, isLongTerm: false, halo: onFilled));
          }
          if (longTermApps.any((a) => a.status == AppStatus.pending)) {
            // [DU1 후속103 C103-1] 장기 대기 별 warningFaded(#FFA726, 흰 1.94) → warningDarkest(#E65100, 3.79).
            //   예전 색은 범례 어느 항목(★ 장기 황갈 · ● 대기 적주황)과도 맞지 않는 연한 호박색이었다.
            //   이제 '별 = 장기, 적주황 = 대기' 로 범례 두 항목을 합쳐 읽힌다(범례 항목은 늘리지 않는다).
            markers.add(_dot(AppColors.warningDarkest, isLongTerm: true, halo: onFilled));
          }
        }

        // ── [E1-AVAIL] 가능일은 **마커가 아니다** ────────────────────
        //
        //   예전에는 확정 근무와 똑같은 7px 원이었고(#1565C0 vs #2196F3),
        //   색만 달랐다. 다른 마커 쌍은 전부 형태(별) 또는 색상환(주황·회색)
        //   으로 갈리는데 이 둘만 어느 축으로도 갈리지 않아, 실제 약속과
        //   사용자의 의향이 같은 점으로 보였다.
        //
        //   게다가 가능일은 **마지막에** 추가돼 마커가 3개면 조용히 빠졌다.
        //
        //   이제 가능일은 날짜 셀의 **윤곽선**이다. 마커 배열을 쓰지 않으므로
        //   3개 제한에서 탈락하지 않고, "채워짐 = 약속 / 윤곽 = 의향" 이라는
        //   위계가 선다. 색이 아니라 **형태**가 구별의 축이다.
        final overlay = <Widget>[];

        if (hasAvailability) {
          // 선택된 날은 배경이 primaryColor 로 꽉 차므로 같은 계열 윤곽선은
          //   묻힌다 — 그 때만 흰색으로 뒤집는다.
          final onFilledBackground = _isSameCell(selectedDay, date);
          overlay.add(Positioned.fill(
            child: Container(
              margin: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: onFilledBackground ? Colors.white : AppColors.info,
                  width: 1.5,
                ),
              ),
            ),
          ));
        }

        if (markers.isNotEmpty) {
          overlay.add(Positioned(
            bottom: 3,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: markers.take(3).toList(),
            ),
          ));
        }

        if (overlay.isEmpty) return null;

        // 날짜 탭 영역을 가리지 않는다 — 표시 전용이다.
        return Positioned.fill(
          child: IgnorePointer(child: Stack(children: overlay)),
        );
      },
    );
  }

  /// [E1-KSTDAY] 달력 셀(연·월·일 성분) → 저장 키 `'YYYY-MM-DD'`.
  ///
  ///   `WorkerAvailabilityModel.dateKeyFrom` 은 **실제 시각**을 KST 날짜로
  ///   바꾸는 함수다. 달력 셀은 이미 달력일이라 그 변환을 통과시키면
  ///   UTC+9 를 넘는 기기에서 하루가 밀린다 — `kstDayKeyOfCivil` 의 주석이
  ///   같은 함정을 적어 두었다. 성분을 그대로 키로 쓴다.
  static String _civilDateKey(DateTime civilDay) =>
      FormatHelper.toKstDateKey(FormatHelper.kstDayKeyOfCivil(civilDay));

  /// 달력 셀 비교 — 연·월·일 성분만 본다(셀 날짜는 기기 local civil 값이다).
  static bool _isSameCell(DateTime? a, DateTime b) =>
      a != null && a.year == b.year && a.month == b.month && a.day == b.day;

  /// [DU1 후속101] 별 표식 흰 테두리 — 옆·아래 5방향 1px 그림자(번짐 0). 레이아웃 크기는 그대로다.
  ///   별(10px)은 점(7px)보다 3px 높아 꼭대기가 날짜 숫자 밑선에 거의 닿는다. 위쪽까지 테두리를 그리면
  ///   선택일의 흰 숫자와 흰 테두리가 이어져 숫자가 별에 붙어 보이므로 위쪽은 그리지 않는다.
  static const List<Shadow> _starHalo = [
    Shadow(color: Colors.white, offset: Offset(1, 0)),
    Shadow(color: Colors.white, offset: Offset(-1, 0)),
    Shadow(color: Colors.white, offset: Offset(0, 1)),
    Shadow(color: Colors.white, offset: Offset(0.7, 0.7)),
    Shadow(color: Colors.white, offset: Offset(-0.7, 0.7)),
  ];

  Widget _dot(Color color, {required bool isLongTerm, bool halo = false}) {
    if (isLongTerm) {
      return Icon(Icons.star, size: 10, color: color, shadows: halo ? _starHalo : null);
    }
    return Container(
      width: 7,
      height: 7,
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        // 흰 테두리 1px — 옆 점과의 간격(margin 1.5 × 2 = 3)보다 좁아 이웃 점을 덮지 않고,
        //   점 위 숫자 밑선과의 간격(약 3px)도 남긴다(1.5px 는 DPR1 에서 숫자 7 끝과 이어져 보였다).
        boxShadow: halo ? const [BoxShadow(color: Colors.white, spreadRadius: 1)] : null,
      ),
    );
  }

}
