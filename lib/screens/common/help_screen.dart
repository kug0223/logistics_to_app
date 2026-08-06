// lib/screens/common/help_screen.dart
//
// 도움말 & Q&A 화면 (역할별 FAQ)
// Firestore help_faqs 컬렉션에서 로드, 데이터 없으면 로컬 기본값 사용

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../models/core/user_model.dart';
import '../../models/core/help_faq_model.dart';
import '../../services/help_faq_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/common/gradient_scaffold.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _service = HelpFaqService();
  late bool _isAdmin;
  List<HelpFaqModel>? _items; // null = 로딩 중 (로컬 폴백 표시)

  @override
  void initState() {
    super.initState();
    final userProvider = context.read<UserProvider>();
    final role = userProvider.currentUser?.role;
    _isAdmin = role == UserRole.BUSINESS_ADMIN ||
        role == UserRole.SUPER_ADMIN ||
        (userProvider.isSubAdmin && userProvider.isAdminMode);
    _loadFaqs();
  }

  Future<void> _loadFaqs() async {
    final items = await _service.getItems(_isAdmin ? 'admin' : 'user');
    if (!mounted) return;
    // Firestore에 데이터 없으면 로컬 폴백 유지 (null 상태 → 로컬 목록 사용)
    if (items.isNotEmpty) {
      setState(() => _items = items);
    } else {
      setState(() => _items = []); // 빈 리스트 = 로컬 폴백으로 전환
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Firestore 응답 전이거나 비어있으면 로컬 폴백
    final useLocal = _items == null || _items!.isEmpty;
    return GradientScaffold(
      title: '도움말',
      body: useLocal
          ? _buildLocalList(context, theme)
          : _buildFirestoreList(context, theme, _items!),
    );
  }

  // Firestore 데이터로 렌더링
  Widget _buildFirestoreList(
      BuildContext context, ThemeData theme, List<HelpFaqModel> items) {
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
        return _FaqTile(
          question: item.question,
          answer: item.answer,
          theme: theme,
        );
      },
    );
  }

  // 로컬 하드코딩 폴백
  Widget _buildLocalList(BuildContext context, ThemeData theme) {
    final items = _isAdmin ? _adminFaqs : _userFaqs;
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
        return _FaqTile(
          question: item.question,
          answer: item.answer,
          theme: theme,
        );
      },
    );
  }

  // ────────────────────────────────────────────────────────────
  // 지원자(근로자) FAQ — 로컬 폴백
  // ────────────────────────────────────────────────────────────
  static final _userFaqs = [
    _FaqItem.header('📋 공고 & 지원'),
    _FaqItem(
      question: '공고에 어떻게 지원하나요?',
      answer: '홈 화면 → "공고 찾기"를 눌러 날짜·업종별로 공고를 탐색할 수 있습니다. '
          '원하는 공고를 선택한 뒤 "지원하기" 버튼을 누르면 됩니다. '
          '관리자가 확정하면 알림과 함께 근로계약서 서명 요청이 전송됩니다.',
    ),
    _FaqItem(
      question: '지원 취소는 어떻게 하나요?',
      answer: '"내 스케줄" → 해당 일정 카드 → "지원 취소" 버튼을 누르세요.\n'
          '• 대기 중(미확정): 즉시 취소됩니다.\n'
          '• 확정 후: 취소 요청을 보내야 하며, 관리자 승인 후 취소됩니다.\n'
          '당일 취소 또는 무단 노쇼는 신뢰도 점수에 영향을 줍니다.',
    ),
    _FaqItem(
      question: '근무 확정·취소 알림이 오지 않아요.',
      answer: '① 설정 → 알림 → 푸시 알림이 켜져 있는지 확인하세요.\n'
          '② 기기 설정에서 ALfit 알림 권한이 "허용"인지 확인하세요.\n'
          '③ 설정 → 알림 → "지원 결과 알림"이 활성화되어 있는지 확인하세요.',
    ),
    _FaqItem.header('⏰ 출퇴근 체크'),
    _FaqItem(
      question: '출근 체크가 안 돼요.',
      answer: '① 근무지 근처(GPS 반경 내)에 있는지 확인하세요.\n'
          '② 위치 권한이 "항상 허용"으로 설정됐는지 확인하세요.\n'
          '③ 블루투스가 켜져 있는지 확인하세요 (비콘 방식 사업장).\n'
          '④ 출근 예정 시간 10분 전부터 체크 가능합니다.\n'
          '그래도 안 되면 관리자에게 수동 시간 조정을 요청하세요.',
    ),
    _FaqItem(
      question: '실수로 출근 체크 시간이 잘못됐어요.',
      answer: '"내 스케줄" → 해당 날짜 → "수정 요청" 버튼을 눌러 '
          '관리자에게 수정 요청을 보내세요. 관리자 승인 후 시간이 변경됩니다. '
          '원본 기록(최초 체크 시간)은 별도 보관됩니다.',
    ),
    _FaqItem(
      question: '퇴근 체크는 언제부터 가능한가요?',
      answer: '예정 퇴근 시간 이후부터 퇴근 체크가 가능합니다. '
          '연장 근무 시 실제 퇴근 시간을 기록하면 추가 근무가 반영됩니다.',
    ),
    _FaqItem.header('✍️ 근로계약서'),
    _FaqItem(
      question: '계약서 서명 요청이 왔어요. 어떻게 하나요?',
      answer: '① 설정 → "내 서명"에서 서명을 먼저 등록해주세요.\n'
          '② 홈 하단 "미서명 계약서 N건" 배너를 탭하거나, '
          '"내 스케줄" → 해당 카드 → 계약서를 열어 내용을 확인한 뒤 서명하세요.\n'
          '서명 후 관리자와 본인 모두 서명된 계약서를 PDF로 확인할 수 있습니다.',
    ),
    _FaqItem(
      question: '내 서명은 어디서 등록하나요?',
      answer: '설정 → "내 서명" 항목에서 서명 패드에 직접 서명을 그릴 수 있습니다. '
          '등록된 서명은 계약서 서명 시 자동으로 적용됩니다. '
          '"변경"으로 언제든지 업데이트할 수 있습니다.',
    ),
    _FaqItem.header('💰 급여 & 임금명세서'),
    _FaqItem(
      question: '임금명세서는 어디서 확인하나요?',
      answer: '"내 스케줄" → 확정된 근무 카드 → "임금명세서" 버튼을 누르면 '
          'PDF 형태로 확인하고 저장·공유할 수 있습니다. '
          '관리자가 급여를 확정한 이후부터 열람 가능합니다.',
    ),
    _FaqItem(
      question: '급여가 예상과 다르게 계산됐어요.',
      answer: '임금명세서에서 공제 내역(4대보험, 식대공제 등)을 확인하세요. '
          '야간 식대나 특정 공제가 적용됐을 수 있습니다. '
          '이상이 있으면 관리자에게 직접 문의하세요.',
    ),
    _FaqItem.header('⭐ 신뢰도'),
    _FaqItem(
      question: '신뢰도 점수는 어떻게 올리나요?',
      answer: '• 정상 출근: +1점\n'
          '• 퇴근 완료: +0.5점\n'
          '• 지각: -1점\n'
          '• 노쇼(무단 결근): -3점\n\n'
          '꾸준히 성실하게 근무하면 점수가 올라가고, '
          '채용 시 관리자에게 더 좋은 인상을 줄 수 있습니다.',
    ),
    _FaqItem(
      question: '신뢰도가 낮아져서 지원이 막혔어요.',
      answer: '신뢰도가 일정 수준 이하로 떨어지면 지원이 제한될 수 있습니다. '
          '신뢰도가 50점 미만이면 설정 화면 상단 신뢰도 카드에 "재시작 프로그램 신청" 버튼이 나타납니다. '
          '신청 시 신뢰도가 50점으로 리셋되고 노쇼·지각 기록 각 1회가 감면됩니다 (2개월 1회 제한). '
          '관리자 평점도 신뢰도에 영향을 줍니다.',
    ),
    _FaqItem(
      question: '설정에서 재시작 프로그램 신청 버튼이 안 보여요.',
      answer: '재시작 프로그램 버튼은 신뢰도가 50점 미만일 때만 설정 화면 상단 신뢰도 카드에 표시됩니다. '
          '현재 신뢰도가 50점 이상이면 버튼이 나타나지 않으며, '
          '신뢰도가 50점 아래로 떨어지면 자동으로 활성화됩니다.',
    ),
    _FaqItem.header('👤 계정 & 서류'),
    _FaqItem(
      question: 'PASS 본인인증은 어디서 하나요?',
      answer: '설정 → "본인인증 (PASS)"을 눌러 인증을 진행할 수 있습니다. '
          '본인인증 완료 후 공고 지원 시 신뢰도가 높아집니다.',
    ),
    _FaqItem(
      question: '서류(신분증, 통장사본 등)는 어디서 등록하나요?',
      answer: '설정 → "내 서류 관리"에서 신분증, 계좌정보, 통장사본을 등록할 수 있습니다. '
          '서류 미등록 시 일부 사업장에서 지원이 제한될 수 있습니다.',
    ),
  ];

  // ────────────────────────────────────────────────────────────
  // 관리자(BUSINESS_ADMIN / SubAdmin 관리자 모드) FAQ — 로컬 폴백
  // ────────────────────────────────────────────────────────────
  static final _adminFaqs = [
    _FaqItem.header('📢 공고(TO) 등록 & 관리'),
    _FaqItem(
      question: '공고는 어떻게 등록하나요?',
      answer: '홈 화면 우측 상단 "+" 버튼 → 필요 정보(업종, 날짜, 시간, 인원, 시급)를 입력 → '
          '"공개"를 누르면 즉시 지원자를 받을 수 있습니다. '
          '"임시저장" 후 나중에 공개하는 것도 가능합니다.',
    ),
    _FaqItem(
      question: '지원자를 어떻게 확정하나요?',
      answer: '홈 달력 → 해당 날짜 탭 → 공고 카드 → "지원자 목록"에서 '
          '원하는 지원자의 "확정" 버튼을 누르세요. '
          '확정 후 근로계약서를 발송하려면 날인 후 "계약서 발송"을 눌러주세요.',
    ),
    _FaqItem(
      question: '등록된 공고를 수정하거나 삭제할 수 있나요?',
      answer: '홈 달력 → 해당 공고 카드 → "수정" 또는 "삭제"를 선택하세요. '
          '이미 확정된 지원자가 있으면 날짜·시간 수정이 제한되며, '
          '삭제 시 확정된 지원자에게 취소 알림이 전송됩니다.',
    ),
    _FaqItem.header('📋 근로계약서'),
    _FaqItem(
      question: '계약서는 어떻게 발송하나요?',
      answer: '지원자 확정 후, 지원자 카드에서 "계약서 발송" 버튼을 누르세요. '
          '사전에 날인(인감/서명)이 등록되어 있어야 합니다. '
          '발송된 계약서는 근무자 앱에서 서명 요청이 표시됩니다.',
    ),
    _FaqItem(
      question: '계약서 템플릿은 어디서 관리하나요?',
      answer: '설정 → "근로계약서 관리"에서 템플릿을 추가·수정·삭제할 수 있습니다. '
          '업무 유형별로 다른 템플릿을 설정하면 공고 등록 시 자동으로 적용됩니다.',
    ),
    _FaqItem(
      question: '근무자가 계약서 서명을 아직 안 했어요.',
      answer: '홈 하단 "미서명 계약서 N건" 배너를 확인하거나, '
          '해당 지원자 카드에서 서명 대기 상태를 볼 수 있습니다. '
          '근무자에게 직접 안내하거나, 알림이 자동 발송됩니다.',
    ),
    _FaqItem.header('📅 당일 출퇴근 관리'),
    _FaqItem(
      question: '당일 근무 현황은 어디서 보나요?',
      answer: '홈 달력 → 해당 날짜 → 공고 카드 → "당일명단" 버튼을 누르세요. '
          '실시간 출퇴근 현황, 지각·노쇼 여부를 한눈에 확인할 수 있습니다.',
    ),
    _FaqItem(
      question: '근무자가 출퇴근 체크를 못 했을 때 어떻게 하나요?',
      answer: '당일명단 → 해당 근무자 → "시간 조정" 버튼으로 관리자가 직접 '
          '출퇴근 시간을 입력할 수 있습니다. '
          '원본 기록(근무자가 체크한 시간)은 별도 보관됩니다.',
    ),
    _FaqItem(
      question: '노쇼 처리는 어떻게 하나요?',
      answer: '당일명단 → 해당 근무자 → "노쇼 처리" 버튼을 누르세요. '
          '노쇼 처리 시 해당 근무자의 신뢰도 점수가 차감됩니다.',
    ),
    _FaqItem.header('💳 급여 관리'),
    _FaqItem(
      question: '급여 확정은 어떻게 하나요?',
      answer: '홈 → "급여 관리" → 해당 월 선택 → 근무자별 "급여 확인"에서 '
          '공제 항목을 검토한 뒤 "급여 확정"을 누르세요. '
          '확정 후 근무자 앱에 임금명세서가 공개됩니다.',
    ),
    _FaqItem(
      question: '식대(야식) 공제는 어떻게 적용하나요?',
      answer: '급여 확인 화면의 그룹 헤더에서 공제 시간(+30분 / +60분 / +90분)을 선택하면 '
          '그룹 내 근무자에게 일괄 적용됩니다. '
          '개별 근무자별로 다르게 설정하는 것도 가능합니다.',
    ),
    _FaqItem(
      question: '급여 이체 내역을 엑셀로 내보낼 수 있나요?',
      answer: '"급여 지급 현황" 화면 → "엑셀" 버튼을 누르면 '
          '은행 일괄이체용 엑셀 파일이 생성됩니다. '
          '이름·은행명·계좌번호·이체금액이 포함됩니다.',
    ),
    _FaqItem.header('👥 인력 & 멤버 관리'),
    _FaqItem(
      question: '고정 근무자를 등록하려면?',
      answer: '홈 → "인력 관리" → "고정 근무자 추가"에서 등록할 수 있습니다. '
          '고정 근무자는 공고 없이도 스케줄을 배정할 수 있습니다.',
    ),
    _FaqItem(
      question: '서브관리자(하위 관리자)를 추가하려면?',
      answer: '설정 → 사업장 설정 → "멤버 관리"에서 초대 코드나 이메일로 '
          '서브관리자를 초대하고 권한(공고 관리/근무자 관리/급여 관리/계약서 관리)을 '
          '개별 설정할 수 있습니다.',
    ),
    _FaqItem.header('⚙️ 사업장 설정'),
    _FaqItem(
      question: '업무 유형은 어디서 추가·관리하나요?',
      answer: '설정 → "업무 유형 관리"에서 업종별 업무 유형을 추가하고 '
          '시급·일급 기준을 설정할 수 있습니다. '
          '공고 등록 시 이 업무 유형을 선택하면 임금이 자동으로 적용됩니다.',
    ),
    _FaqItem(
      question: '날인(인감/서명)은 어디서 등록하나요?',
      answer: '설정 → 사업장 설정 → "날인 관리"에서 도장 이미지 업로드 또는 '
          '직접 서명으로 날인을 등록할 수 있습니다. '
          '계약서 발송 시 자동으로 적용됩니다.',
    ),
  ];
}

class _FaqTile extends StatefulWidget {
  final String question;
  final String answer;
  final ThemeData theme;

  const _FaqTile({
    required this.question,
    required this.answer,
    required this.theme,
  });

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
                        widget.question,
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
                    padding:
                        EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                    decoration: BoxDecoration(
                      color:
                          widget.theme.primaryColor.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.answer,
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
