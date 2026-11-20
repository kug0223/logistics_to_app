import 'package:flutter/material.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../../theme/app_colors.dart';

/// ⚡ 출퇴근 빠른 시간 선택 바텀시트
///
/// 출근/퇴근 처리 전용.
/// - 예정 시간 칩 (TO startTime/endTime 기반, 선택적)
/// - 현재 시각 칩 (10분 단위 반올림, 기본 선택)
/// - ±10분 버튼으로 미세 조정
/// - 확인 버튼에 선택 시간 실시간 표시
///
/// 시간 수정(기록 수정)은 기존 [TimePickerBottomSheet] 사용.
class AttendanceQuickTimeSheet extends StatefulWidget {
  final String title;

  /// 예정 시간 목록 (HH:mm 형식).
  /// 개별 처리: 1개 (해당 업무의 startTime/endTime)
  /// 일괄 처리: 선택된 직원들의 고유 시간 목록 (여러 업무 섞인 경우 복수 칩)
  final List<String>? scheduledTimes;

  final bool isCheckIn; // true: 출근, false: 퇴근 (색상·아이콘 결정)

  const AttendanceQuickTimeSheet({
    super.key,
    required this.title,
    this.scheduledTimes,
    this.isCheckIn = true,
  });

  static Future<String?> show({
    required BuildContext context,
    required String title,
    List<String>? scheduledTimes,
    bool isCheckIn = true,
  }) {
    return DialogHelper.showSheet<String>(
      context,
      isScrollControlled: true,
      builder: (context) => AttendanceQuickTimeSheet(
        title: title,
        scheduledTimes: scheduledTimes,
        isCheckIn: isCheckIn,
      ),
    );
  }

  /// '현재' 기본 시각 — **KST 벽시계**를 10분 단위로 반올림한다.
  ///
  /// [UI-4] 여기서 고른 'HH:mm' 은 호출자가 KST 근무일의 시각으로 저장한다
  ///   (`_hmToKstEpochMs` 등). 예전에는 기기 시간대의 시·분을 써서, GMT 기기에서
  ///   KST 02:17 에 `현재 17:20` 이 기본값이 되고 그대로 저장됐다(15시간 뒤 퇴근).
  ///   시각을 9시간 더하지 않고 기존 변환([FormatHelper.formatTime] = instant → KST HH:mm)을 쓴다.
  static ({int hour, int minute}) roundedKstNow([DateTime? instant]) {
    final hm = FormatHelper.formatTime(instant ?? DateTime.now()).split(':');
    final hour = int.parse(hm[0]);
    final minute = int.parse(hm[1]);
    final roundedStep = (minute / 10).round();
    if (roundedStep >= 6) {
      return (hour: (hour + 1) % 24, minute: 0);
    }
    return (hour: hour, minute: roundedStep * 10);
  }

  @override
  State<AttendanceQuickTimeSheet> createState() => _AttendanceQuickTimeSheetState();
}

class _AttendanceQuickTimeSheetState extends State<AttendanceQuickTimeSheet> {
  late int _hour;
  late int _minute;

  static ({int hour, int minute}) _roundedNow() =>
      AttendanceQuickTimeSheet.roundedKstNow();

  // 예정 시간 목록 파싱 (HH:mm → (hour, minute)) — 중복 제거, 정렬
  List<({int hour, int minute})> get _scheduledList {
    final times = widget.scheduledTimes;
    if (times == null || times.isEmpty) return [];
    final seen = <String>{};
    final result = <({int hour, int minute})>[];
    for (final t in times) {
      if (!seen.add(t)) continue;
      try {
        final parts = t.split(':');
        result.add((hour: int.parse(parts[0]), minute: int.parse(parts[1])));
      // 잘못된 형식의 시간 문자열은 조용히 건너뜀 — 파싱 불가 항목 제외
      } catch (_) {}
    }
    result.sort((a, b) => a.hour != b.hour ? a.hour.compareTo(b.hour) : a.minute.compareTo(b.minute));
    return result;
  }

  @override
  void initState() {
    super.initState();
    final now = _roundedNow();
    _hour = now.hour;
    _minute = now.minute;
  }

  String get _timeString => FormatHelper.formatHourMinute(_hour, _minute);

  void _adjustMinutes(int delta) {
    setState(() {
      // 24시간 순환 — 23:50 + 10분 = 00:00, 00:00 - 10분 = 23:50
      final total = ((_hour * 60 + _minute + delta) % (24 * 60) + 24 * 60) % (24 * 60);
      _hour = total ~/ 60;
      _minute = (total % 60) ~/ 10 * 10; // 10분 단위 유지
    });
  }

  void _select(int hour, int minute) => setState(() {
        _hour = hour;
        _minute = minute;
      });

  bool _isSelected(int hour, int minute) => _hour == hour && _minute == minute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = _roundedNow();
    final scheduledList = _scheduledList;
    final isCheckIn = widget.isCheckIn;
    final actionLabel = isCheckIn ? '출근' : '퇴근';
    final actionIcon = isCheckIn ? Icons.login : Icons.logout;
    final actionColor = isCheckIn ? AppColors.success : AppColors.purple;
    // [DU301 Q2] 출근/퇴근 의미는 머리 아이콘에만 둔다. 출근 success 전경(10% 면 위 2.53) → successDark,
    //   퇴근 purple 은 그대로. 10% 면은 기존 의미색(감사300 §3).
    final actionIconColor = isCheckIn ? AppColors.successDark : AppColors.purple;
    final confirmLabel = '$_timeString 로 $actionLabel 처리';

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          ResponsiveHelper.spacing(context, 16),
          0,
          ResponsiveHelper.spacing(context, 16),
          ResponsiveHelper.spacing(context, 20),
        ),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 핸들바
              Center(
                child: Container(
                  margin: EdgeInsets.symmetric(
                    vertical: ResponsiveHelper.spacing(context, 12),
                  ),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.grey300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // 헤더
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                    decoration: BoxDecoration(
                      color: actionColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      actionIcon,
                      color: actionIconColor,
                      size: ResponsiveHelper.iconSize(context, 22),
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    // [DU301 Q5] 큰 글자에서 낱말 단위로 줄을 바꾼다(읽기 이름 원문)
                    child: Text(
                      TextLayout.keepWords(widget.title),
                      semanticsLabel: widget.title,
                      style: ResponsiveHelper.subtitleStyle(context)
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  // [DU301 Q3] 닫기 누름 48×48(축소 배율 없이)
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: Icon(Icons.close, color: AppColors.textSecondary),
                  ),
                ],
              ),

              SizedBox(height: ResponsiveHelper.spacing(context, 16)),

              // [DU301 Q4] 내용만 스크롤하고 취소/확정은 아래에 둔다(큰 글자·작은 화면에서 세로로 넘쳤다)
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 선택 시간 표시 카드
                      // [DU301 Q2] 의미색 gradient·선 → 중립 단색 면 + 본문색 숫자(감사300 §3). 크기·반경 그대로
                      Container(
                        padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 14),
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.grey100,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Center(
                          child: Text(
                            _timeString,
                            style: ResponsiveHelper.titleStyle(context).copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: ResponsiveHelper.getFontSize(context, 34),
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ),

                      SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                      // 빠른 선택 칩
                      Text(
                        '빠른 선택',
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.textSecondary),
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                      Wrap(
                        spacing: ResponsiveHelper.spacing(context, 8),
                        runSpacing: ResponsiveHelper.spacing(context, 8),
                        children: [
                          // 예정 시간 칩 (업무별 고유 시간 목록)
                          ...scheduledList.map((s) => _buildChip(
                            context: context,
                            label: '예정  ${FormatHelper.formatHourMinute(s.hour, s.minute)}',
                            hour: s.hour,
                            minute: s.minute,
                          )),
                          // 현재 시각 칩
                          _buildChip(
                            context: context,
                            label: '현재  ${FormatHelper.formatHourMinute(now.hour, now.minute)}',
                            hour: now.hour,
                            minute: now.minute,
                          ),
                        ],
                      ),

                      SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                      // ±10분 조정 바
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.grey100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: IntrinsicHeight(
                          child: Row(
                            children: [
                              // -10분 버튼
                              Expanded(
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => _adjustMinutes(-10),
                                    borderRadius: const BorderRadius.horizontal(
                                        left: Radius.circular(12)),
                                    // [DU301 Q3] 누름 높이 최소 48
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(minHeight: 48),
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(
                                            vertical: ResponsiveHelper.spacing(context, 14)),
                                        // [DU302] 아이콘 위·'10분' 아래 — B320 2.0 에서 가로 배치(13.6+3.4+55.35)가 칸 72.2 보다 0.15px 넓었다(진단 D)
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.remove,
                                                size: ResponsiveHelper.iconSize(context, 16),
                                                color: AppColors.grey700),
                                            SizedBox(
                                                height: ResponsiveHelper.spacing(context, 4)),
                                            Text(
                                              '10분',
                                              style: ResponsiveHelper.smallStyle(context,
                                                      color: AppColors.grey700)
                                                  .copyWith(fontWeight: FontWeight.w600),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // 구분선
                              VerticalDivider(
                                  width: 1, thickness: 1, color: AppColors.border),

                              // 현재 선택 시간
                              Expanded(
                                flex: 2,
                                child: Center(
                                  child: Text(
                                    _timeString,
                                    style: ResponsiveHelper.subtitleStyle(context).copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: theme.primaryColor,
                                    ),
                                  ),
                                ),
                              ),

                              // 구분선
                              VerticalDivider(
                                  width: 1, thickness: 1, color: AppColors.border),

                              // +10분 버튼
                              Expanded(
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => _adjustMinutes(10),
                                    borderRadius: const BorderRadius.horizontal(
                                        right: Radius.circular(12)),
                                    // [DU301 Q3] 누름 높이 최소 48
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(minHeight: 48),
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(
                                            vertical: ResponsiveHelper.spacing(context, 14)),
                                        // [DU302] 아이콘 위·'10분' 아래 — B320 2.0 에서 가로 배치(13.6+3.4+55.35)가 칸 72.2 보다 0.15px 넓었다(진단 D)
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.add,
                                                size: ResponsiveHelper.iconSize(context, 16),
                                                color: AppColors.grey700),
                                            SizedBox(
                                                height: ResponsiveHelper.spacing(context, 4)),
                                            Text(
                                              '10분',
                                              style: ResponsiveHelper.smallStyle(context,
                                                      color: AppColors.grey700)
                                                  .copyWith(fontWeight: FontWeight.w600),
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
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: ResponsiveHelper.spacing(context, 20)),

              // 취소 / 처리 버튼
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        // [DU301 Q3] 누름 최소 48(확정과 같은 줄 높이 52)
                        minimumSize: const Size(48, 52),
                        padding: EdgeInsets.symmetric(
                            vertical: ResponsiveHelper.spacing(context, 14)),
                        side: BorderSide(color: AppColors.grey300),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        '취소',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: AppColors.grey700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, _timeString),
                      style: ElevatedButton.styleFrom(
                        // [DU301 Q1] 확정은 일반 진행 — brand(Standards §9.1). 이전 출근 success 흰 글 2.78
                        backgroundColor: AppColors.brand,
                        foregroundColor: AppColors.surface,
                        // [DU301 Q3] 주 행동 최소 52
                        minimumSize: const Size(48, 52),
                        padding: EdgeInsets.symmetric(
                            vertical: ResponsiveHelper.spacing(context, 14)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      // [DU301 Q5] 큰 글자에서 낱말 단위로 줄을 바꾼다(읽기 이름 원문)
                      child: Text(
                        TextLayout.keepWords(confirmLabel),
                        semanticsLabel: confirmLabel,
                        textAlign: TextAlign.center,
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: AppColors.surface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
    );
  }

  Widget _buildChip({
    required BuildContext context,
    required String label,
    required int hour,
    required int minute,
  }) {
    final selected = _isSelected(hour, minute);
    return Material(
      // [DU301 Q1] 선택 칩 채움 → brand(이전 출근 success 흰 글 2.78)
      color: selected ? AppColors.brand : AppColors.grey100,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => _select(hour, minute),
        borderRadius: BorderRadius.circular(20),
        // [DU301 Q3] 누름 최소 48×48 — 글은 가운데
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Align(
            widthFactor: 1.0,
            heightFactor: 1.0,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 16),
                vertical: ResponsiveHelper.spacing(context, 9),
              ),
              child: Text(
                label,
                style: ResponsiveHelper.smallStyle(context).copyWith(
                  color: selected ? AppColors.surface : AppColors.textPrimary,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
