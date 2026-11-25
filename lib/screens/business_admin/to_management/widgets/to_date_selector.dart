import 'package:flutter/material.dart';
import '../../../../utils/responsive_helper.dart';
import '../../../../utils/format_helper.dart';
import '../../../../utils/text_layout.dart';
import '../../../../theme/app_colors.dart';
import '../../../../widgets/pickers/date_picker_bottom_sheet.dart';
import 'to_section_container.dart';
import '../../../../utils/toast_helper.dart';


/// TO 날짜 선택 공통 위젯 (당근 스타일)
class TODateSelector extends StatefulWidget {
  final bool isLongTerm;
  final bool isReadOnly;

  // 단기 알바용
  final List<DateTime> selectedDates;
  final Function(DateTime)? onDateToggle;
  final Function(List<DateTime>)? onDatesChanged;
  final Function()? onClearAll;
  final int maxSelectableDays;

  // 장기 근무용
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final List<String> selectedWeekdays;
  final Function(DateTime)? onRangeStartChanged;
  final Function(DateTime)? onRangeEndChanged;
  final Function(String)? onWeekdayToggle;
  /// 계약 기간 유형: '15days' | '1month' | '3months' | '6months' | '1year' | 'custom'
  final String? contractPeriodType;
  final Function(String)? onContractPeriodTypeChanged;
  /// 근무 시작 가능기간 (preset 전용): 지원자가 희망 시작일로 고를 수 있는 범위
  final DateTime? workStartAvailableFrom;
  final DateTime? workStartAvailableUntil;
  final Function(DateTime?)? onWorkStartAvailableFromChanged;
  final Function(DateTime?)? onWorkStartAvailableUntilChanged;

  // 읽기 전용
  final DateTime? displayDate;
  final List<String>? displayWorkDays;

  const TODateSelector({
    super.key,
    required this.isLongTerm,
    this.isReadOnly = false,
    this.selectedDates = const [],
    this.onDateToggle,
    this.onDatesChanged,
    this.onClearAll,
    this.maxSelectableDays = 14,
    this.rangeStart,
    this.rangeEnd,
    this.selectedWeekdays = const [],
    this.onRangeStartChanged,
    this.onRangeEndChanged,
    this.onWeekdayToggle,
    this.contractPeriodType,
    this.onContractPeriodTypeChanged,
    this.workStartAvailableFrom,
    this.workStartAvailableUntil,
    this.onWorkStartAvailableFromChanged,
    this.onWorkStartAvailableUntilChanged,
    this.displayDate,
    this.displayWorkDays,
  });

  @override
  State<TODateSelector> createState() => _TODateSelectorState();
}

class _TODateSelectorState extends State<TODateSelector> {
  static const int _maxFutureDays = 60;

  DateTime _focusedDay = DateTime.now();
  bool _isCalendarExpanded = true;

  // 범위 선택: 첫 번째 탭으로 시작점을 기억하고 그 날짜도 선택에 추가한다(onDateToggle).
  //   두 번째 탭에서 시작점~끝 날짜 사이를 채운다. [DU1 구현51] 이전 주석의 '추가하지 않음' 은 실제 동작과 달랐다.
  DateTime? _rangeStart;

  String? _activeQuickSelect;

  @override
  Widget build(BuildContext context) {
    if (widget.isReadOnly) return _buildReadOnlySection(context);
    if (widget.isLongTerm) return _buildLongTermSelector(context);
    return _buildShortTermSelector(context);
  }

  // ============================================================
  // 📅 읽기 전용 섹션
  // ============================================================
  Widget _buildReadOnlySection(BuildContext context) {
    final now = DateTime.now();

    String dateText;
    if (widget.isLongTerm && widget.contractPeriodType != null && widget.contractPeriodType != 'custom') {
      // preset 기간 유형: 계약기간 레이블 + 근무 시작 가능기간
      final Map<String, String> labels = {
        '15days': '15일', '1month': '1개월', '3months': '3개월',
        '6months': '6개월', '1year': '1년',
      };
      dateText = labels[widget.contractPeriodType] ?? widget.contractPeriodType!;
      if (widget.workStartAvailableFrom != null && widget.workStartAvailableUntil != null) {
        final fromFmt = FormatHelper.formatDateKorean(widget.workStartAvailableFrom!);
        final untilFmt = FormatHelper.formatDateKorean(widget.workStartAvailableUntil!);
        dateText += ' · 시작 가능 $fromFmt ~ $untilFmt';
      } else if (widget.rangeStart != null) {
        // legacy: rangeStart 기준 표시
        final isSameYear = widget.rangeStart!.year == now.year;
        final fmt = isSameYear ? FormatHelper.formatDateKorean : FormatHelper.formatDateLong;
        dateText += ' · ${fmt(widget.rangeStart!)} 이후 시작 가능';
      }
    } else if (widget.isLongTerm && widget.rangeStart != null && widget.rangeEnd != null) {
      final isSameYear = widget.rangeStart!.year == now.year;
      final fmt = isSameYear ? FormatHelper.formatDateKorean : FormatHelper.formatDateLong;
      dateText = '${fmt(widget.rangeStart!)} ~ ${fmt(widget.rangeEnd!)}';
    } else if (widget.displayDate != null) {
      final isSameYear = widget.displayDate!.year == now.year;
      dateText = isSameYear
          ? FormatHelper.formatDateKorean(widget.displayDate!)
          : FormatHelper.formatDateLong(widget.displayDate!);
    } else {
      dateText = '날짜 정보 없음';
    }
    // [DU542b · 감사138 4-5] 수정 불가 안내 = 분기별 완전한 문장 1개(조사 보간 없음) — 수정 화면의 같은 뜻 줄은 지우고 이 한 곳만 남긴다.
    final lockNotice = widget.isLongTerm ? '공고 생성 후 계약 기간과 근무 요일은 변경할 수 없어요.' : '공고 생성 후 근무 날짜는 변경할 수 없어요.';

    return TOSectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                // [DU542] 장식 아이콘 칸 — 중립 면 · 회색 아이콘(그림자는 색만 투명 · 크기 그대로)
                decoration: BoxDecoration(
                  color: AppColors.grey100,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.transparent,
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.calendar_today,
                  color: AppColors.grey600,
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 16)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.isLongTerm ? '계약 기간' : '근무 날짜',
                      style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                    Text(
                      dateText,
                      style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (widget.isLongTerm && widget.displayWorkDays != null && widget.displayWorkDays!.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Row(
              children: [
                Icon(Icons.event_repeat, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.grey600),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                // [DU1 구현48 C1 S031] 320·2.0 에서 요일 글이 줄지 않아 오른쪽으로 92px 넘쳤다 — 남은 폭 안에서 단어 단위 줄바꿈(문구 그대로)
                Expanded(
                  child: Text(
                    TextLayout.keepWords('근무 요일: ${widget.displayWorkDays!.join(', ')}'),
                    style: ResponsiveHelper.bodyStyle(context, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ],

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            // [DU542 · DU542b] 수정 불가 안내 띠 = 읽기 전용 고정 제약 — 중립 면 · 선 · 회색 잠금 아이콘(감사138 4-4 · 크기 그대로) · 보조 글
            decoration: BoxDecoration(
              color: AppColors.grey100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border, width: 1),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline, color: AppColors.grey600, size: ResponsiveHelper.iconSize(context, 18)),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: Text(
                    TextLayout.keepWords(lockNotice),
                    semanticsLabel: lockNotice,
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 📅 단기 알바 - 당근 스타일 캘린더
  // ============================================================
  Widget _buildShortTermSelector(BuildContext context) {
    return TOSectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          _buildQuickSelectButtons(context),

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          _buildCalendarToggle(context),

          if (_isCalendarExpanded) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _buildCarrotStyleCalendar(context),
          ],
        ],
      ),
    );
  }

  /// 헤더 (범위 선택 중일 때 힌트로 교체). 기본 배율은 두 상태가 같은 최소 높이라 전환 때 흔들리지 않고,
  /// 확대 글자에서는 글 높이만큼 늘어난다(잘림 방지 — 고정 높이 아님).
  Widget _buildHeader(BuildContext context) {

    // [DU1 구현50 C1 S030] 고정 높이(40 상당)였다 — 320·2.0 에서 범위 안내 글이 2줄(76px)을 필요로 하는데 32px 안에
    //   갇혀 '11월 9일 (월) · 종' 까지만 보였다(종료 날짜를 탭하라는 안내 자체가 잘림). 최소 높이로 바꿔 글이 커지면 늘어난다.
    //   기본 배율은 두 상태 모두 최소 높이 안이라 전환 때 레이아웃이 흔들리지 않는다
    //   (50 = 안내 상자: 닫기 터치 48 + 테두리 1×2).
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: ResponsiveHelper.spacing(context, 40) < 50 ? 50 : ResponsiveHelper.spacing(context, 40)),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.15),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: _rangeStart != null
            // 범위 선택 중: 시작일 안내
            ? Container(
                key: const ValueKey('hint'),
                padding: EdgeInsets.only(left: ResponsiveHelper.spacing(context, 12)),
                decoration: BoxDecoration(
                  color: AppColors.grey100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.touch_app, color: AppColors.grey600, size: ResponsiveHelper.iconSize(context, 16)),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Expanded(
                      child: RichText(
                        textScaler: MediaQuery.textScalerOf(context), // [SCALE-BALANCE.34] RichText 는 배율을 스스로 받지 않는다
                        text: TextSpan(
                          style: ResponsiveHelper.smallStyle(context, color: AppColors.textPrimary),
                          // [DU1 구현50] '종/료' 음절 끊김 — 단어 단위로 묶는다(문구 그대로)
                          // [DU1 구현51 · 후속51 F51-1] keepWords 는 표시 전용 U+2060 을 넣는다 — 접근성 이름에는
                          //   제어문자 없는 원문을 semanticsLabel 로 따로 준다(표시·접근성 분리).
                          children: [
                            TextSpan(
                              text: TextLayout.keepWords(FormatHelper.formatDateKorean(_rangeStart!)),
                              semanticsLabel: FormatHelper.formatDateKorean(_rangeStart!),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            TextSpan(
                              text: TextLayout.keepWords(' · 종료 날짜를 탭하세요'),
                              semanticsLabel: ' · 종료 날짜를 탭하세요',
                            ),
                          ],
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        final start = _rangeStart!;
                        setState(() => _rangeStart = null);
                        widget.onDateToggle?.call(start);
                      },
                      // [DU1 구현50] 실측 13.6×13.6(320·2.0)·14.4(360·1.0) — 아이콘 크기는 그대로, 누르는 영역만 48×48
                      behavior: HitTestBehavior.opaque,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: Icon(Icons.close, color: AppColors.textSecondary, size: ResponsiveHelper.iconSize(context, 16)),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            // 기본 헤더
            : Row(
                key: const ValueKey('header'),
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // [R7-P4.4E.6B] 제목과 선택 일수를 고정 폭 자식으로만 늘어놓아
                  //   오른쪽 '전체 해제' 와 함께 줄을 넘쳤다(360dp 13px,
                  //   320dp 48px, 배율 2.0 288px). 몇 일을 골랐는지는 핵심
                  //   사실이므로 감추지 않고 Wrap 으로 줄을 바꾼다.
                  Expanded(
                    child: Wrap(
                      spacing: ResponsiveHelper.spacing(context, 8),
                      runSpacing: ResponsiveHelper.spacing(context, 4),
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '근무 날짜 선택',
                          style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (widget.selectedDates.isNotEmpty)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: ResponsiveHelper.spacing(context, 10),
                              vertical: ResponsiveHelper.spacing(context, 4),
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).primaryColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${widget.selectedDates.length}일',
                              style: ResponsiveHelper.smallStyle(context).copyWith(
                                color: AppColors.surface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Opacity(
                    opacity: widget.selectedDates.isNotEmpty ? 1.0 : 0.0,
                    child: IgnorePointer(
                      ignoring: widget.selectedDates.isEmpty,
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _activeQuickSelect = null;
                              _rangeStart = null;
                            });
                            widget.onClearAll?.call();
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: ResponsiveHelper.spacing(context, 12),
                              vertical: ResponsiveHelper.spacing(context, 8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.clear_all, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.textSecondary),
                                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                                Text(
                                  '전체 해제',
                                  style: ResponsiveHelper.smallStyle(context).copyWith(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// 빠른 선택 버튼
  Widget _buildQuickSelectButtons(BuildContext context) {
    return Row(
      children: [
        _buildQuickButton(context, id: 'today', icon: Icons.today, label: '오늘'),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        _buildQuickButton(context, id: 'thisWeek', icon: Icons.view_week, label: '이번 주'),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        _buildQuickButton(context, id: 'nextWeek', icon: Icons.next_week, label: '다음 주'),
      ],
    );
  }

  Widget _buildQuickButton(
    BuildContext context, {
    required String id,
    required IconData icon,
    required String label,
  }) {
    final isActive = _activeQuickSelect == id;

    return Expanded(
      child: Material(
        // [DU542] 고른 빠른 선택만 brand 채움 — 고르지 않은 것은 아래 캘린더 접기 줄과 같은 grey100 · grey700
        color: isActive ? Theme.of(context).primaryColor : AppColors.grey100,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _handleQuickSelect(id),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 10)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: isActive ? AppColors.surface : AppColors.grey700,
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  label,
                  style: ResponsiveHelper.tinyStyle(context).copyWith(
                    color: isActive ? AppColors.surface : AppColors.grey700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 캘린더 토글
  Widget _buildCalendarToggle(BuildContext context) {
    return Material(
      color: AppColors.grey100,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => setState(() => _isCalendarExpanded = !_isCalendarExpanded),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 16),
            vertical: ResponsiveHelper.spacing(context, 12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isCalendarExpanded ? Icons.expand_less : Icons.expand_more,
                color: AppColors.grey700,
                size: ResponsiveHelper.iconSize(context, 20),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                _isCalendarExpanded ? '캘린더 접기' : '캘린더 펼치기',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: AppColors.grey700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 당근 스타일 캘린더
  Widget _buildCarrotStyleCalendar(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.grey200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      // [DU1 구현52 F50-1] 7열 칸에 두 자리 날짜가 안 들어가면(확대 글자 — 320·2.0 에서 칸 36.7 에 '10111213' 처럼 붙었다)
      //   글자를 줄이지 않고 **날짜 목록**으로 배치를 바꾼다(한 줄 = 한 날짜, 전체 폭·최소 52). 기본 배율은 기존 7열 그대로.
      child: LayoutBuilder(builder: (c, cons) {
        final listMode = _needsDateList(c, cons.maxWidth);
        return Column(
          children: [
            _buildCalendarHeader(c),
            // [DU1 구현53 F53-1] 월말을 시작으로 고른 뒤 다음 달로 넘기면 시작일이 이 달에 없어 탭 자리 안내가 사라졌다
            //   (머리 안내는 화면 위 밖). 시작일이 다른 달이면 월 제목 바로 아래에 시작일과 함께 안내한다.
            if (_rangeStart != null &&
                (_rangeStart!.year != _focusedDay.year || _rangeStart!.month != _focusedDay.month))
              _buildInlineRangeHint(c, startLabel: FormatHelper.formatDateKorean(_rangeStart!)),
            if (!listMode) _buildWeekdayHeader(c),
            listMode ? _buildDateList(c, today) : _buildDateGrid(c, today),
            SizedBox(height: ResponsiveHelper.spacing(c, 8)),
          ],
        );
      }),
    );
  }

  /// [DU1 구현52 F50-1] 날짜 칸(7열) 폭에 가장 넓은 두 자리 날짜가 좌우 여백과 함께 들어가는가 — 실제 글꼴·배율로 잰다.
  bool _needsDateList(BuildContext context, double calendarWidth) {
    final cellW = (calendarWidth - ResponsiveHelper.spacing(context, 4) * 2) / 7;
    final tp = TextPainter(
      text: TextSpan(text: '28', style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final need = tp.width + 12; // 숫자 사이가 이어 보이지 않을 최소 좌우 여백(6+6)
    tp.dispose();
    return need > cellW;
  }

  /// [DU1 구현52 F50-1] 확대 글자용 날짜 목록 — 고를 수 있는 날짜(오늘~60일)만, 한 줄 한 날짜.
  ///   선택·범위(첫 탭 시작 → 두 번째 탭 끝) 규칙은 달력과 같은 `_handleDateTap` 을 쓴다.
  Widget _buildDateList(BuildContext context, DateTime today) {
    final lastDay = DateTime(_focusedDay.year, _focusedDay.month + 1, 0).day;
    final rows = <Widget>[];
    for (var day = 1; day <= lastDay; day++) {
      final date = DateTime(_focusedDay.year, _focusedDay.month, day);
      final isPast = date.isBefore(today);
      final isTooFar = date.isAfter(today.add(const Duration(days: _maxFutureDays)));
      if (isPast || isTooFar) continue;
      rows.add(_buildDateListRow(context, date, today));
      if (_rangeStart != null && _isSameDay(date, _rangeStart!)) rows.add(_buildInlineRangeHint(context));
    }
    if (rows.isEmpty) {
      rows.add(Padding(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
        child: Text(
          TextLayout.keepWords('이 달에는 고를 수 있는 날짜가 없습니다'),
          semanticsLabel: '이 달에는 고를 수 있는 날짜가 없습니다',
          style: ResponsiveHelper.bodyStyle(context, color: AppColors.textSecondary),
        ),
      ));
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
    );
  }

  Widget _buildDateListRow(BuildContext context, DateTime date, DateTime today) {
    final isSelected = widget.selectedDates.any((d) => _isSameDay(d, date));
    final isToday = _isSameDay(date, today);
    final label = FormatHelper.formatDateKorean(date);
    final primary = Theme.of(context).primaryColor;
    // [DU542b · 감사138 4-1] 주말은 요일 조건일 뿐 오류 · 휴무 상태가 아니다 — 고르지 않은 날짜 글은 평일과 같은 textPrimary(선택 brand/흰 그대로)
    final fg = isSelected ? AppColors.surface : AppColors.textPrimary;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 2)),
      child: Semantics(
        selected: isSelected,
        button: true,
        child: Material(
          color: isSelected ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => _handleDateTap(date, today),
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 12),
                  vertical: ResponsiveHelper.spacing(context, 8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        TextLayout.keepWords(label),
                        semanticsLabel: isToday ? '$label 오늘' : label,
                        style: ResponsiveHelper.bodyStyle(context, color: fg).copyWith(
                          fontWeight: (isSelected || isToday) ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (isToday)
                      ExcludeSemantics(
                        child: Text('오늘', style: ResponsiveHelper.smallStyle(context, color: isSelected ? AppColors.surface : primary)),
                      ),
                    if (isSelected) ...[
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Icon(Icons.check, color: AppColors.surface, size: ResponsiveHelper.iconSize(context, 18)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// [DU1 구현52 F50-2] 첫 탭 바로 아래에 끝 날짜 안내 — 머리의 안내가 탭 위치에서 화면 밖(위)에 떠 보이지 않았다.
  ///   접근성 이름은 머리 안내 하나로 충분하므로 이 시각 단서는 Semantics 에서 뺀다(중복 방지).
  Widget _buildInlineRangeHint(BuildContext context, {String? startLabel}) {
    return ExcludeSemantics(
      child: Container(
        key: const ValueKey('inline-range-hint'),
        margin: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 4),
          vertical: ResponsiveHelper.spacing(context, 4),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 10),
          vertical: ResponsiveHelper.spacing(context, 6),
        ),
        decoration: BoxDecoration(
          color: AppColors.grey100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.touch_app, color: AppColors.grey600, size: ResponsiveHelper.iconSize(context, 16)),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Expanded(
              child: Text(
                TextLayout.keepWords(startLabel == null ? '종료 날짜를 탭하세요' : '$startLabel 시작 · 종료 날짜를 탭하세요'),
                style: ResponsiveHelper.smallStyle(context, color: AppColors.textPrimary).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 캘린더 헤더
  Widget _buildCalendarHeader(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () {
              setState(() {
                _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1, 1);
              });
            },
            icon: Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.chevron_left, color: Theme.of(context).primaryColor),
            ),
          ),
          // [R7-P4.4E.6B] 좌우 이동 버튼 사이에서 연월이 줄어들 수 없었다.
          //   어느 달을 보고 있는지는 핵심 사실이므로 자르지 않고 줄을 바꾼다.
          Expanded(
            child: Text(
              FormatHelper.formatYearMonth(_focusedDay),
              textAlign: TextAlign.center,
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1, 1);
              });
            },
            icon: Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.chevron_right, color: Theme.of(context).primaryColor),
            ),
          ),
        ],
      ),
    );
  }

  /// 요일 헤더
  Widget _buildWeekdayHeader(BuildContext context) {
    const weekdays = ['일', '월', '화', '수', '목', '금', '토'];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 8)),
      child: Row(
        children: weekdays.asMap().entries.map((entry) {
          return Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 8)),
                child: Text(
                  entry.value,
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.grey600, // [DU542b · 감사138 4-1] 요일 머리 7칸 같은 중립(주말 빨강 없음 · app_calendar 요일 머리와 같은 토큰)
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 날짜 그리드
  Widget _buildDateGrid(BuildContext context, DateTime today) {
    final firstDayOfMonth = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final lastDayOfMonth = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);
    final firstWeekday = firstDayOfMonth.weekday % 7;

    final daysInMonth = lastDayOfMonth.day;
    final totalCells = ((firstWeekday + daysInMonth) / 7).ceil() * 7;

    List<Widget> rows = [];
    List<Widget> currentRow = [];

    for (int i = 0; i < totalCells; i++) {
      final dayOffset = i - firstWeekday;

      if (dayOffset < 0 || dayOffset >= daysInMonth) {
        currentRow.add(Expanded(child: SizedBox(height: ResponsiveHelper.spacing(context, 44))));
      } else {
        final date = DateTime(_focusedDay.year, _focusedDay.month, dayOffset + 1);
        currentRow.add(Expanded(child: _buildDateCell(context, date, today)));
      }

      if (currentRow.length == 7) {
        rows.add(
          Padding(
            padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 4)),
            child: Row(children: currentRow),
          ),
        );
        currentRow = [];
        // [DU1 구현52 F50-2] 범위 시작일이 든 주 바로 아래에 끝 날짜 안내(탭한 자리에서 보이게)
        final weekStartOffset = i - 6 - firstWeekday;
        if (_rangeStart != null &&
            _rangeStart!.year == _focusedDay.year &&
            _rangeStart!.month == _focusedDay.month &&
            _rangeStart!.day - 1 >= weekStartOffset &&
            _rangeStart!.day - 1 <= weekStartOffset + 6) {
          rows.add(_buildInlineRangeHint(context));
        }
      }
    }

    return Column(children: rows);
  }

  /// 날짜 셀 (당근 스타일 - 연속 날짜 연결 배경)
  Widget _buildDateCell(BuildContext context, DateTime date, DateTime today) {
    final isPast = date.isBefore(today);
    final isTooFar = date.isAfter(today.add(const Duration(days: _maxFutureDays)));
    final isToday = _isSameDay(date, today);
    final isSelected = widget.selectedDates.any((d) => _isSameDay(d, date));
    final isRangeStart = _rangeStart != null && _isSameDay(date, _rangeStart!);

    // 연속 날짜 체크
    final prevDay = date.subtract(const Duration(days: 1));
    final nextDay = date.add(const Duration(days: 1));
    final hasPrev = widget.selectedDates.any((d) => _isSameDay(d, prevDay));
    final hasNext = widget.selectedDates.any((d) => _isSameDay(d, nextDay));

    // 주 행 경계 보정: 일요일(행 시작)은 왼쪽 연결 없음, 토요일(행 끝)은 오른쪽 연결 없음
    final weekdayIndex = date.weekday % 7; // Sun=0, Sat=6
    final effectiveHasPrev = hasPrev && weekdayIndex != 0;
    final effectiveHasNext = hasNext && weekdayIndex != 6;

    // 연결 배경 모서리
    BorderRadius borderRadius;
    if (isSelected) {
      if (effectiveHasPrev && effectiveHasNext) {
        borderRadius = BorderRadius.zero;
      } else if (effectiveHasPrev && !effectiveHasNext) {
        borderRadius = BorderRadius.horizontal(right: Radius.circular(ResponsiveHelper.spacing(context, 22)));
      } else if (!effectiveHasPrev && effectiveHasNext) {
        borderRadius = BorderRadius.horizontal(left: Radius.circular(ResponsiveHelper.spacing(context, 22)));
      } else {
        borderRadius = BorderRadius.circular(ResponsiveHelper.spacing(context, 22));
      }
    } else {
      borderRadius = BorderRadius.circular(ResponsiveHelper.spacing(context, 22));
    }

    // 색상
    Color backgroundColor;
    Color textColor;

    if (isPast || isTooFar) {
      backgroundColor = Colors.transparent;
      textColor = AppColors.grey300;
    } else if (isSelected) {
      backgroundColor = Theme.of(context).primaryColor;
      textColor = AppColors.surface;
    } else {
      backgroundColor = Colors.transparent;
      // [DU542b · 감사138 4-1] 고를 수 있고 고르지 않은 날 — 주말도 평일과 같은 글(지난/불가 grey300 · 선택 brand 분기가 먼저)
      textColor = AppColors.textPrimary;
    }

    return GestureDetector(
      onTap: (isPast || isTooFar) ? null : () => _handleDateTap(date, today),
      child: Container(
        height: ResponsiveHelper.spacing(context, 38),
        margin: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 2)),
        decoration: BoxDecoration(
          color: isSelected ? backgroundColor : Colors.transparent,
          borderRadius: borderRadius,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 오늘 테두리
            if (isToday && !isSelected)
              Container(
                width: ResponsiveHelper.spacing(context, 36),
                height: ResponsiveHelper.spacing(context, 36),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).primaryColor, width: 2),
                ),
              ),

            // 범위 시작점 - 점선 외곽 링 (시각적 구분)
            if (isRangeStart && isSelected)
              Container(
                width: ResponsiveHelper.spacing(context, 36),
                height: ResponsiveHelper.spacing(context, 36),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.7),
                    width: 2,
                  ),
                ),
              ),

            // 날짜 텍스트
            Text(
              '${date.day}',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: textColor,
                fontWeight: (isSelected || isToday) ? FontWeight.bold : FontWeight.normal,
                decoration: isPast ? TextDecoration.lineThrough : null,
                decorationColor: AppColors.grey300,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 📅 장기 근무 - 계약 기간 유형 + 요일 선택
  // ============================================================

  static const _periodOptions = [
    ('15days', '15일'),
    ('1month', '1개월'),
    ('3months', '3개월'),
    ('6months', '6개월'),
    ('1year', '1년'),
    ('custom', '직접 입력'),
  ];

  Widget _buildLongTermSelector(BuildContext context) {
    final isCustom = widget.contractPeriodType == 'custom';
    final hasPreset = widget.contractPeriodType != null && !isCustom;

    return TOSectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '계약 기간',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text(
            isCustom
                ? '근무 시작·종료일을 직접 지정합니다'
                : '지원자의 희망 시작일 기준으로 종료일이 자동 계산됩니다',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          // 기간 유형 칩
          _buildPeriodTypeChips(context),

          // 날짜 직접 지정(custom): 고정 시작일·종료일 피커
          if (isCustom) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Row(
              children: [
                Expanded(
                  child: _buildDateField(
                    context: context,
                    label: '시작일',
                    date: widget.rangeStart,
                    onTap: () => _selectLongTermDate(context, isStart: true),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 12)),
                  child: Icon(Icons.arrow_forward, color: AppColors.grey600),
                ),
                Expanded(
                  child: _buildDateField(
                    context: context,
                    label: '종료일',
                    date: widget.rangeEnd,
                    onTap: () => _selectLongTermDate(context, isStart: false),
                  ),
                ),
              ],
            ),
          ],

          // preset: 근무 시작 가능기간 [시작일] ~ [종료일] 필수 입력
          if (hasPreset) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            _buildWorkStartAvailableRangeFields(context),
          ],

          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
          const Divider(color: AppColors.grey300),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          Text(
            '근무 요일 선택',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            '※ 매주 반복되는 근무 요일을 선택하세요',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          _buildWeekdayButtons(context),

          if (widget.selectedWeekdays.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            _buildWeekdaySummary(context),
          ],
        ],
      ),
    );
  }

  Widget _buildPeriodTypeChips(BuildContext context) {
    return Wrap(
      spacing: ResponsiveHelper.spacing(context, 8),
      runSpacing: ResponsiveHelper.spacing(context, 8),
      children: _periodOptions.map(((String, String) opt) {
        final (value, label) = opt;
        final isSelected = widget.contractPeriodType == value;
        return GestureDetector(
          onTap: () => widget.onContractPeriodTypeChanged?.call(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: ResponsiveHelper.spacing(context, 10),
            ),
            decoration: BoxDecoration(
              color: isSelected ? Theme.of(context).primaryColor : AppColors.grey100,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? Theme.of(context).primaryColor : AppColors.grey300,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [BoxShadow(color: Theme.of(context).primaryColor.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 3))]
                  : null,
            ),
            child: Text(
              label,
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: isSelected ? Colors.white : AppColors.grey700,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// preset 장기공고 — 근무 시작 가능기간 [시작일] ~ [종료일] 필수 입력
  Widget _buildWorkStartAvailableRangeFields(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // [DU549 · 감사138 F138-DATESELECTOR-B-LAYOUT] 제목과 필수 표지가 한 줄에 다 안 들어가면(좁은 화면 · 큰 글자) 표지를 다음 줄로 내린다.
        //   이전 Row 는 오른쪽으로 39px 넘쳐 표지가 화면 밖으로 나갔다. 글 · 글자 크기 · 색 · 간격 6 그대로 — 넉넉하면 이전과 같은 한 줄.
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: ResponsiveHelper.spacing(context, 6),
          runSpacing: ResponsiveHelper.spacing(context, 4),
          children: [
            Text(
              '근무 시작 가능기간',
              style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w600),
            ),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 6),
                vertical: ResponsiveHelper.spacing(context, 2),
              ),
              decoration: BoxDecoration(
                color: AppColors.errorBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '필수',
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.errorDark, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
        Text(
          '지원자가 희망 시작일로 선택할 수 있는 기간입니다.',
          style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        Row(
          children: [
            Expanded(
              child: _buildDateField(
                context: context,
                label: '시작일',
                date: widget.workStartAvailableFrom,
                onTap: () => _selectWorkStartDate(context, isFrom: true),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 12)),
              child: Icon(Icons.arrow_forward, color: AppColors.grey600),
            ),
            Expanded(
              child: _buildDateField(
                context: context,
                label: '종료일',
                date: widget.workStartAvailableUntil,
                onTap: () => _selectWorkStartDate(context, isFrom: false),
              ),
            ),
          ],
        ),
        if (widget.workStartAvailableFrom != null && widget.workStartAvailableUntil != null) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            decoration: BoxDecoration(
              color: AppColors.grey100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.grey600, size: 16),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: Text(
                    '지원자는 이 기간 안에서 희망 근무 시작일을 선택할 수 있습니다.',
                    style: ResponsiveHelper.tinyStyle(context, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _selectWorkStartDate(BuildContext context, {required bool isFrom}) async {
    final now = DateTime.now();
    final minDate = isFrom ? now : (widget.workStartAvailableFrom ?? now);
    final picked = await DatePickerBottomSheet.show(
      context: context,
      initialDate: isFrom
          ? (widget.workStartAvailableFrom ?? now)
          : (widget.workStartAvailableUntil ?? widget.workStartAvailableFrom ?? now),
      title: isFrom ? '시작 가능 첫날' : '시작 가능 마지막날',
      subtitle: isFrom
          ? '지원자가 선택 가능한 가장 이른 시작일입니다'
          : '지원자가 선택 가능한 가장 늦은 시작일입니다',
      minDate: minDate,
      maxDate: now.add(const Duration(days: 365)),
    );

    if (picked != null) {
      if (isFrom) {
        widget.onWorkStartAvailableFromChanged?.call(picked);
        // 시작일이 종료일보다 늦어지면 종료일도 같이 초기화
        if (widget.workStartAvailableUntil != null &&
            picked.isAfter(widget.workStartAvailableUntil!)) {
          widget.onWorkStartAvailableUntilChanged?.call(null);
        }
      } else {
        widget.onWorkStartAvailableUntilChanged?.call(picked);
      }
    }
  }

  Widget _buildDateField({
    required BuildContext context,
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 12),
            vertical: ResponsiveHelper.spacing(context, 10),
          ),
          decoration: BoxDecoration(
            // [DU542b · 감사138 4-2] 값이 있는 칸 = 흰 면 · border 선(두께 2 그대로) · textPrimary 값 — brand 강조는 날짜 시트에서 지금 고르는 칸에만
            color: date != null ? AppColors.surface : AppColors.grey50,
            border: Border.all(
              color: AppColors.border,
              width: date != null ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary)),
              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
              Text(
                date != null ? FormatHelper.formatDate(date) : '선택하세요',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: date != null ? AppColors.textPrimary : AppColors.textTertiary,
                  fontWeight: date != null ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectLongTermDate(BuildContext context, {required bool isStart}) async {
    final picked = await DatePickerBottomSheet.show(
      context: context,
      initialDate: isStart
          ? (widget.rangeStart ?? DateTime.now())
          : (widget.rangeEnd ?? widget.rangeStart ?? DateTime.now()),
      title: isStart ? '계약 시작일' : '계약 종료일',
      subtitle: isStart ? '근무 시작 날짜를 선택하세요' : '근무 종료 날짜를 선택하세요',
      minDate: isStart ? DateTime.now() : (widget.rangeStart ?? DateTime.now()),
      maxDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      if (isStart) {
        widget.onRangeStartChanged?.call(picked);
      } else {
        widget.onRangeEndChanged?.call(picked);
      }
    }
  }

  Widget _buildWeekdayButtons(BuildContext context) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];

    return LayoutBuilder(
      builder: (context, constraints) {
        final buttonWidth = (constraints.maxWidth - 48) / 7;

        // [DU601b · 판정145 F138-DATESELECTOR-B-LAYOUT] 큰 글자(B 320 · 2.0)에서 요일 글자 줄(약 49)이 칸(약 30)보다 커서 잘리고 겹쳐 보였다('월' → '워').
        //   렌더와 같은 글 · 스타일 · 배율로 요일 글자 상자를 재서 칸에 들어가면 예전과 같은 한 줄 7칸(같은 Row 를 그대로 돌려준다),
        //   안 들어가면 글자 상자에 맞춘 같은 모양 칸을 여러 줄로 놓는다(칸 사이 · 줄 사이 8 = 예전 칸 사이 · 숨김 · 글자 축소 · 말줄임 0).
        final labelStyle = DefaultTextStyle.of(context).style.merge(ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold));
        var labelBox = 0.0;
        for (final day in weekdays) {
          final painter = TextPainter(
            text: TextSpan(text: day, style: labelStyle),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          if (painter.width > labelBox) labelBox = painter.width;
          if (painter.height > labelBox) labelBox = painter.height;
          painter.dispose();
        }
        final fitsRow = labelBox <= buttonWidth;
        final side = fitsRow ? buttonWidth : labelBox;

        final row = Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: weekdays.map((day) {
            final isSelected = widget.selectedWeekdays.contains(day);

            return GestureDetector(
              onTap: () => widget.onWeekdayToggle?.call(day),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: side,
                height: side,
                decoration: BoxDecoration(
                  // [DU542b · 감사138 4-1] 고르지 않은 요일 7칸 = grey100 · textPrimary(주말 errorBg/error 없음 · 고른 요일 brand/흰 그대로)
                  color: isSelected ? Theme.of(context).primaryColor : AppColors.grey100,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected
                      ? [BoxShadow(color: Theme.of(context).primaryColor.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))]
                      : null,
                ),
                child: Center(
                  child: Text(
                    day,
                    style: ResponsiveHelper.subtitleStyle(context).copyWith(
                      color: isSelected ? AppColors.surface : AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
        if (fitsRow) return row;
        return Wrap(spacing: 8, runSpacing: 8, children: row.children);
      },
    );
  }

  Widget _buildWeekdaySummary(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.grey600, size: ResponsiveHelper.iconSize(context, 18)),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                '주 ${widget.selectedWeekdays.length}일 근무',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            '선택된 요일: ${widget.selectedWeekdays.join(', ')}',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 🛠️ 이벤트 핸들러
  // ============================================================

  /// 날짜 탭 처리 (당근 스타일 범위 선택)
  void _handleDateTap(DateTime date, DateTime today) {
    setState(() => _activeQuickSelect = null);

    final isAlreadySelected = widget.selectedDates.any((d) => _isSameDay(d, date));

    if (isAlreadySelected) {
      // 범위 시작점을 다시 탭 → 범위 모드 취소
      if (_rangeStart != null && _isSameDay(date, _rangeStart!)) {
        setState(() => _rangeStart = null);
        widget.onDateToggle?.call(date);
        return;
      }
      // 일반 해제
      setState(() => _rangeStart = null);
      widget.onDateToggle?.call(date);
      return;
    }

    // 최대 개수 초과 & 범위 시작 전
    if (widget.selectedDates.length >= widget.maxSelectableDays && _rangeStart == null) {
      ToastHelper.showWarning('최대 ${widget.maxSelectableDays}일까지 선택 가능합니다');
      return;
    }

    if (_rangeStart == null) {
      // 첫 번째 탭: 시작점 설정 + 날짜 선택
      setState(() => _rangeStart = date);
      widget.onDateToggle?.call(date);
    } else {
      // 두 번째 탭: 범위 채우기
      _selectRange(_rangeStart!, date, today);
      setState(() => _rangeStart = null);
    }
  }

  /// 범위 선택 (14일 제한 통합 적용)
  void _selectRange(DateTime start, DateTime end, DateTime today) {
    DateTime rangeStart = start.isBefore(end) ? start : end;
    DateTime rangeEnd = start.isBefore(end) ? end : start;

    // 이미 시작점이 selectedDates에 있으므로 현재 개수 기준으로 체크
    int count = widget.selectedDates.length;
    bool reachedLimit = false;

    final newDates = List<DateTime>.from(widget.selectedDates);

    for (var d = rangeStart; !d.isAfter(rangeEnd); d = d.add(const Duration(days: 1))) {
      if (!d.isBefore(today) && !newDates.any((existing) => _isSameDay(existing, d))) {
        if (count < widget.maxSelectableDays) {
          newDates.add(d);
          count++;
        } else {
          reachedLimit = true;
        }
      }
    }

    if (reachedLimit) {
      ToastHelper.showWarning('최대 ${widget.maxSelectableDays}일까지 선택 가능합니다');
    }

    newDates.sort();

    if (widget.onDatesChanged != null) {
      widget.onDatesChanged!(newDates);
    } else {
      // onDatesChanged 없는 경우: 시작점은 이미 추가됐으므로 나머지만 추가
      for (final d in newDates) {
        if (!widget.selectedDates.any((existing) => _isSameDay(existing, d))) {
          widget.onDateToggle?.call(d);
        }
      }
    }
  }

  /// 빠른 선택 처리 (토글 방식)
  void _handleQuickSelect(String id) {
    final today = DateTime.now();
    final todayNormalized = DateTime(today.year, today.month, today.day);

    setState(() => _rangeStart = null);

    if (_activeQuickSelect == id) {
      setState(() => _activeQuickSelect = null);
      widget.onClearAll?.call();
      return;
    }

    List<DateTime> dates = [];

    switch (id) {
      case 'today':
        dates = [todayNormalized];
        break;
      case 'thisWeek':
        dates = _getWeekDates(todayNormalized, isNextWeek: false);
        break;
      case 'nextWeek':
        dates = _getWeekDates(todayNormalized, isNextWeek: true);
        break;
    }

    dates = dates.where((d) => !d.isBefore(todayNormalized)).toList();

    // 14일 제한 적용
    if (dates.length > widget.maxSelectableDays) {
      dates = dates.take(widget.maxSelectableDays).toList();
      ToastHelper.showWarning('최대 ${widget.maxSelectableDays}일까지 선택 가능합니다');
    }

    setState(() => _activeQuickSelect = id);

    if (widget.onDatesChanged != null) {
      widget.onDatesChanged!(dates);
    } else {
      widget.onClearAll?.call();
      for (var date in dates) {
        widget.onDateToggle?.call(date);
      }
    }
  }

  /// 주간 날짜 가져오기 (월~일)
  List<DateTime> _getWeekDates(DateTime today, {required bool isNextWeek}) {
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final targetMonday = isNextWeek ? monday.add(const Duration(days: 7)) : monday;
    return List.generate(7, (i) => targetMonday.add(Duration(days: i)));
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
