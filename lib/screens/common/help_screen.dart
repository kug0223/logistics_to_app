// lib/screens/common/help_screen.dart
//
// 도움말 & Q&A 화면 (역할별 FAQ)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../models/core/user_model.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/common/gradient_scaffold.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final role = context.read<UserProvider>().currentUser?.role;
    final isAdmin = role == UserRole.BUSINESS_ADMIN || role == UserRole.SUPER_ADMIN;
    final theme = Theme.of(context);

    return GradientScaffold(
      title: '도움말',
      body: _buildFaqList(context, theme, isAdmin ? _adminFaqs : _userFaqs),
    );
  }

  Widget _buildFaqList(
      BuildContext context, ThemeData theme, List<_FaqItem> items) {
    return ListView.builder(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        if (item.isHeader) {
          return Padding(
            padding: EdgeInsets.only(
              top: i == 0 ? 0 : ResponsiveHelper.spacing(context, 8),
              bottom: ResponsiveHelper.spacing(context, 4),
            ),
            child: Text(
              item.question,
              style: ResponsiveHelper.smallStyle(context,
                  color: theme.primaryColor, fontWeight: FontWeight.w700),
            ),
          );
        }
        return _FaqTile(item: item, theme: theme);
      },
    );
  }

  static final _userFaqs = [
    _FaqItem.header('📋 공고 & 지원'),
    _FaqItem(
      question: '공고에 어떻게 지원하나요?',
      answer: '홈 화면에서 "공고 찾기"를 누르면 날짜·업종별로 공고를 볼 수 있습니다. '
          '원하는 공고를 선택한 뒤 "지원하기" 버튼을 누르면 됩니다. '
          '지원 후 관리자가 확정하면 알림이 옵니다.',
    ),
    _FaqItem(
      question: '지원 취소는 어떻게 하나요?',
      answer: '"내 스케줄" → 해당 일정 카드 → "지원 취소" 버튼을 누르세요. '
          '단, 관리자가 이미 확정한 경우 취소 요청을 보내야 하며 관리자 승인 후 취소됩니다.',
    ),
    _FaqItem(
      question: '근무 확정 알림이 오지 않아요.',
      answer: '설정 → 알림 설정에서 푸시 알림이 켜져 있는지 확인하세요. '
          '켜져 있다면 기기 설정에서 ALfit 앱 알림 권한도 확인해 주세요.',
    ),
    _FaqItem.header('⏰ 출퇴근 체크'),
    _FaqItem(
      question: '출근 체크가 안 돼요.',
      answer: '① 근무지 근처(GPS 반경 내)에 있는지 확인하세요.\n'
          '② 위치 권한이 "항상 허용"으로 설정됐는지 확인하세요.\n'
          '③ 출근 예정 시간 10분 전부터 체크 가능합니다.\n'
          '문제가 지속되면 관리자에게 시간 조정을 요청하세요.',
    ),
    _FaqItem(
      question: '실수로 출근 체크를 잘못 했어요.',
      answer: '"내 스케줄" → 해당 날짜 → "수정 요청" 버튼을 눌러 관리자에게 '
          '수정 요청을 보내세요. 관리자 승인 후 시간이 변경됩니다.',
    ),
    _FaqItem(
      question: '퇴근 체크 시간은 언제부터 가능한가요?',
      answer: '예정 퇴근 시간 이후부터 퇴근 체크가 가능합니다. '
          '연장 근무 시에는 실제 퇴근 시간을 기록하면 자동으로 반영됩니다.',
    ),
    _FaqItem.header('💰 급여'),
    _FaqItem(
      question: '임금명세서는 어디서 확인하나요?',
      answer: '"내 스케줄" → 확정된 근무 카드 → "임금명세서" 버튼을 누르면 '
          'PDF 형태로 확인하고 저장·공유할 수 있습니다.',
    ),
    _FaqItem(
      question: '급여가 예상과 다르게 계산됐어요.',
      answer: '임금명세서에서 공제 내역(4대보험, 식대공제 등)을 확인하세요. '
          '석식/야식 공제가 적용됐을 수 있습니다. 이상이 있으면 관리자에게 문의하세요.',
    ),
    _FaqItem.header('⭐ 신뢰도'),
    _FaqItem(
      question: '신뢰도 점수는 어떻게 올리나요?',
      answer: '• 정상 출근 +1점\n• 퇴근 완료 +0.5점\n'
          '• 지각 -1점, 노쇼 -3점이 차감됩니다.\n'
          '꾸준히 성실하게 근무하면 점수가 올라가고 채용 우선순위가 높아집니다.',
    ),
    _FaqItem(
      question: '신뢰도가 너무 낮아져서 지원이 안 돼요.',
      answer: '신뢰도가 일정 수준 이하로 떨어지면 재시작 프로그램을 통해 '
          '회복할 수 있습니다. 설정 → 신뢰도 → 재시작 신청을 확인하세요.',
    ),
  ];

  static final _adminFaqs = [
    _FaqItem.header('📢 TO 등록 & 관리'),
    _FaqItem(
      question: 'TO는 어떻게 등록하나요?',
      answer: '홈 → "공고 등록"을 누르고 업종·날짜·시간·필요 인원을 입력한 뒤 '
          '"공개"를 누르면 즉시 지원자를 받을 수 있습니다. '
          '미리 저장 후 나중에 공개하는 것도 가능합니다.',
    ),
    _FaqItem(
      question: '등록 후 공고 내용을 수정할 수 있나요?',
      answer: '"공고 관리" → 해당 공고 선택 → "수정"을 누르면 됩니다. '
          '단, 이미 확정된 지원자가 있는 경우 일부 항목(날짜·시간)은 수정이 제한될 수 있습니다.',
    ),
    _FaqItem(
      question: '지원자를 어떻게 확정하나요?',
      answer: '"공고 관리" → 해당 TO → 지원자 목록에서 원하는 지원자의 '
          '"확정" 버튼을 누르세요. 확정 후 자동으로 근로계약서 서명 요청이 발송됩니다.',
    ),
    _FaqItem.header('📋 계약서'),
    _FaqItem(
      question: '계약서는 자동으로 발송되나요?',
      answer: '지원자 확정 후 앱에서 "인감 날인 → 근무자에게 발송"을 누르면 '
          '근무자 앱에 계약서 서명 요청이 전송됩니다. '
          '계약서 템플릿은 "계약서 관리"에서 미리 설정할 수 있습니다.',
    ),
    _FaqItem(
      question: '계약서 서명을 근무자가 아직 안 했어요.',
      answer: '"계약서 관리" 화면에서 서명 대기 상태를 확인할 수 있습니다. '
          '근무자에게 직접 안내하거나 앱 알림을 통해 서명을 독려하세요.',
    ),
    _FaqItem.header('📅 당일 출퇴근 관리'),
    _FaqItem(
      question: '당일명단은 어디서 보나요?',
      answer: '"공고 관리" → 해당 날짜 TO → "당일명단" 버튼을 누르세요. '
          '실시간 출퇴근 현황, 지각·조퇴·노쇼 현황을 한눈에 볼 수 있습니다.',
    ),
    _FaqItem(
      question: '근무자가 출근 체크를 못 했을 때 어떻게 하나요?',
      answer: '당일명단 → 해당 근무자 → "시간 조정" 버튼으로 관리자가 직접 '
          '출근 시간을 입력할 수 있습니다. 수정된 경우 원본 기록(근무자가 찍은 시간)은 '
          '별도 보관되어 분쟁 시 증빙 자료로 활용됩니다.',
    ),
    _FaqItem.header('💳 급여 관리'),
    _FaqItem(
      question: '급여 확정은 어떻게 하나요?',
      answer: '"급여 관리" → 해당 월 선택 → 근무자별 "급여 확인"에서 공제 항목을 '
          '검토한 뒤 "급여 확정"을 누르세요. 확정 후 근무자에게 임금명세서가 공개됩니다.',
    ),
    _FaqItem(
      question: '석식/야식 공제는 어떻게 적용하나요?',
      answer: '급여 확인 화면의 그룹 헤더에서 "+30분 / +60분 / +90분"을 선택하면 '
          '선택한 근무자에게 일괄 적용됩니다. 개별 근무자별로 다르게 설정할 수도 있습니다.',
    ),
    _FaqItem(
      question: '급여 이체 내역을 엑셀로 내보낼 수 있나요?',
      answer: '"급여 지급 현황" → "엑셀" 버튼을 누르면 은행 일괄이체용 엑셀 파일이 '
          '생성됩니다. 이름·은행명·계좌번호·이체금액이 포함됩니다.',
    ),
    _FaqItem.header('👥 인력 관리'),
    _FaqItem(
      question: '하위 관리자를 추가하려면?',
      answer: '설정 → 사업장 설정 → "멤버 관리"에서 이메일로 하위 관리자를 초대하고 '
          '권한(공고 관리/근무자 관리/급여 관리/계약서 관리)을 설정할 수 있습니다.',
    ),
  ];
}

class _FaqTile extends StatefulWidget {
  final _FaqItem item;
  final ThemeData theme;
  const _FaqTile({required this.item, required this.theme});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _expanded
              ? widget.theme.primaryColor.withValues(alpha: 0.3)
              : AppColors.grey200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.help_outline_rounded,
                      size: ResponsiveHelper.iconSize(context, 16),
                      color: widget.theme.primaryColor,
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Expanded(
                      child: Text(
                        widget.item.question,
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: ResponsiveHelper.iconSize(context, 20),
                      color: AppColors.grey400,
                    ),
                  ],
                ),
                if (_expanded) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 10)),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                    decoration: BoxDecoration(
                      color: widget.theme.primaryColor.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.item.answer,
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey700),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FaqItem {
  final String question;
  final String answer;
  final bool isHeader;

  const _FaqItem({required this.question, required this.answer})
      : isHeader = false;

  const _FaqItem.header(this.question)
      : answer = '',
        isHeader = true;
}
