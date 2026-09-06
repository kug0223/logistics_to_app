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
    // Firestore에 데이터 없으면 로컬 폴백 유지
    if (items.isNotEmpty) {
      setState(() => _items = items);
    } else {
      setState(() => _items = []); // 빈 리스트 = 로컬 폴백으로 전환
    }
  }

  @override
  Widget build(BuildContext context) {
    // Firestore 응답 전이거나 비어있으면 로컬 폴백
    final useLocal = _items == null || _items!.isEmpty;
    final flat = useLocal
        ? (_isAdmin ? _adminFaqs : _userFaqs)
        : _items!
            .map((m) => m.isHeader
                ? _FaqItem.header(m.question)
                : _FaqItem(question: m.question, answer: m.answer))
            .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          '도움말',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.borderLight),
        ),
      ),
      body: _buildGroupedList(context, flat),
    );
  }

  // ── 그룹 렌더링 ───────────────────────────────────────────────────

  /// 평탄 리스트 → 카테고리 그룹화 → 카드 목록 렌더링
  Widget _buildGroupedList(BuildContext context, List<_FaqItem> flat) {
    final groups = _groupItems(flat);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      itemCount: groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (ctx, i) => _buildCategorySection(ctx, groups[i]),
    );
  }

  /// 카테고리 섹션: 레이블 + 질문 그룹 카드
  Widget _buildCategorySection(BuildContext context, _FaqGroup group) {
    final theme = Theme.of(context);
    final items = group.items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 섹션 레이블 — Material 아이콘 + ALfit Blue 제목
        Padding(
          padding: EdgeInsets.only(
              left: ResponsiveHelper.spacing(context, 4)),
          child: Row(children: [
            Icon(group.icon,
                size: ResponsiveHelper.iconSize(context, 14),
                color: theme.primaryColor),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Text(
              group.title,
              style: ResponsiveHelper.smallStyle(context,
                  color: theme.primaryColor, fontWeight: FontWeight.w700),
            ),
          ]),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        // 그룹 카드 — 여러 질문을 하나의 Card 안에 묶음
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Material(
              color: Colors.transparent,
              child: Column(
                children: [
                  for (int i = 0; i < items.length; i++) ...[
                    _FaqAccordionRow(
                      key: ValueKey(items[i].question),
                      question: items[i].question,
                      answer: items[i].answer,
                    ),
                    if (i < items.length - 1)
                      const Divider(
                          height: 1, indent: 16, thickness: 0.5,
                          color: AppColors.borderLight),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 데이터 유틸 ────────────────────────────────────────────────────

  /// 평탄 리스트를 [header → 이하 items] 구조로 그룹화
  static List<_FaqGroup> _groupItems(List<_FaqItem> flat) {
    final groups = <_FaqGroup>[];
    String header = '';
    final items = <_FaqItem>[];

    for (final item in flat) {
      if (item.isHeader) {
        if (items.isNotEmpty) {
          groups.add(_FaqGroup(
            title: _stripEmoji(header),
            icon: _iconFor(header),
            items: List.of(items),
          ));
          items.clear();
        }
        header = item.question;
      } else {
        items.add(item);
      }
    }
    if (items.isNotEmpty) {
      groups.add(_FaqGroup(
        title: _stripEmoji(header),
        icon: _iconFor(header),
        items: List.of(items),
      ));
    }
    return groups;
  }

  /// 헤더 문자열 앞의 emoji 제거
  static String _stripEmoji(String s) {
    final match = RegExp(r'[가-힣a-zA-Z]').firstMatch(s);
    return match != null ? s.substring(match.start).trim() : s.trim();
  }

  /// 헤더 제목 → Material 아이콘 매핑 (emoji 없이 키워드 기반)
  static IconData _iconFor(String title) {
    final t = title;
    if (t.contains('공고') || t.contains('지원') || t.contains('TO')) {
      return Icons.work_outline;
    }
    if (t.contains('출퇴근') || t.contains('근태') || t.contains('당일')) {
      return Icons.schedule_outlined;
    }
    if (t.contains('계약서')) return Icons.description_outlined;
    if (t.contains('급여') || t.contains('임금') || t.contains('💳')) {
      return Icons.payments_outlined;
    }
    if (t.contains('노쇼 & 제재')) return Icons.warning_amber_outlined;
    if (t.contains('인력') || t.contains('멤버')) return Icons.group_outlined;
    if (t.contains('사업장') || t.contains('설정')) return Icons.settings_outlined;
    if (t.contains('계정') || t.contains('서류')) return Icons.badge_outlined;
    return Icons.help_outline;
  }

  // ────────────────────────────────────────────────────────────
  // 지원자(근로자) FAQ — 로컬 폴백
  // ────────────────────────────────────────────────────────────
  static final _userFaqs = [
    _FaqItem.header('📋 공고 & 지원'),
    _FaqItem(
      question: '공고에 어떻게 지원하나요?',
      answer: '홈 화면의 "지금 지원 가능한 일자리" 목록에서 공고를 선택하거나, '
          '하단 "일자리" 탭에서 날짜·업종별로 공고를 탐색할 수 있습니다. '
          '공고를 탭해 상세 내용을 확인한 후 "지원하기"를 눌러주세요. '
          '관리자가 확정하면 알림과 함께 근로계약서 서명 요청이 전송됩니다.',
    ),
    _FaqItem(
      question: '지원 취소는 어떻게 하나요?',
      answer: '"일정" 탭에서 해당 날짜를 선택한 후 일정 카드의 "지원 취소" 버튼을 누르세요.\n'
          '• 대기 중(미확정): 즉시 취소됩니다.\n'
          '• 확정 후: 취소 요청을 보내야 하며, 관리자 승인 후 취소됩니다.\n'
          '당일 취소 또는 무단 노쇼는 노쇼 기록에 남아 90일 이내 3회 이상 시 지원 제한이 적용됩니다.',
    ),
    _FaqItem(
      question: '근무 확정·취소 알림이 오지 않아요.',
      answer: '① MY → "설정" → 알림에서 푸시 알림이 켜져 있는지 확인하세요.\n'
          '② 기기 설정에서 ALfit 알림 권한이 "허용"인지 확인하세요.\n'
          '③ MY → "설정" → 알림 세부 설정에서 "지원 현황 알림"이 활성화되어 있는지 확인하세요.',
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
      answer: '"일정" 탭에서 해당 날짜를 선택한 후 일정 카드의 "수정 요청" 버튼을 눌러 '
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
      answer: '화면 하단에 나타나는 "미서명 계약서 N건" 배너를 탭하거나, '
          'MY → 근무 관리 → "계약서"에서 해당 계약서를 열어 내용을 확인한 뒤 서명하세요.\n'
          '계약서 화면에서 바로 서명을 그릴 수 있습니다. '
          'MY → 근무 관리 → "내 서명"에 미리 등록해두면 다음 계약서부터 편리하게 사용할 수 있습니다.\n'
          '서명 후 관리자와 본인 모두 서명된 계약서를 PDF로 확인할 수 있습니다.',
    ),
    _FaqItem(
      question: '내 서명은 어디서 등록하나요?',
      answer: 'MY → 근무 관리 → "내 서명"에서 서명 패드에 직접 서명을 그릴 수 있습니다. '
          '미리 등록해두면 계약서 서명 시 저장된 서명을 바로 사용할 수 있어 편리합니다. '
          '등록하지 않아도 계약서 화면에서 직접 서명할 수 있습니다. '
          '"변경"으로 언제든지 업데이트할 수 있습니다.',
    ),
    _FaqItem.header('💰 급여 & 임금명세서'),
    _FaqItem(
      question: '임금명세서는 어디서 확인하나요?',
      answer: '"일정" 탭 → 확정된 근무 카드 → "임금명세서" 버튼을 누르면 '
          'PDF 형태로 확인하고 저장·공유할 수 있습니다. '
          '관리자가 급여를 확정한 이후부터 열람 가능합니다.',
    ),
    _FaqItem(
      question: '급여가 예상과 다르게 계산됐어요.',
      answer: '임금명세서에서 공제 내역(4대보험, 식대공제 등)을 확인하세요. '
          '야간 식대나 특정 공제가 적용됐을 수 있습니다. '
          '이상이 있으면 관리자에게 직접 문의하세요.',
    ),
    _FaqItem.header('📊 노쇼 & 제재'),
    _FaqItem(
      question: '노쇼 기록은 어디서 확인하나요?',
      answer: '설정(MY → 설정) 화면 상단 통계 카드에서 '
          '"노쇼(90일)" 항목으로 최근 90일 내 노쇼 횟수를 확인할 수 있습니다.',
    ),
    _FaqItem(
      question: '지원이 제한됐어요. 원인이 뭔가요?',
      answer: '최근 90일 이내 노쇼 기록이 3회 이상이면 24시간 지원 제한이 적용됩니다. '
          '제한 기간이 지나면 자동으로 해제됩니다. '
          '제재 해제 시점은 설정 화면에서 확인할 수 있습니다.',
    ),
    _FaqItem.header('👤 계정 & 서류'),
    _FaqItem(
      question: '본인인증은 언제 하나요?',
      answer: '회원가입 시 휴대폰 본인인증(KG이니시스)을 완료하면 가입이 완료됩니다. '
          '별도로 인증을 다시 할 필요가 없습니다.',
    ),
    _FaqItem(
      question: '서류(신분증, 통장사본 등)는 어디서 등록하나요?',
      answer: 'MY → 근무 관리 → "내 서류 관리"에서 신분증, 계좌정보, 통장사본을 등록할 수 있습니다. '
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
          '노쇼 처리 시 해당 근무자의 노쇼 기록이 남고 90일 이내 3회 누적 시 지원 제한이 적용됩니다.',
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

// ── 아코디언 Row 위젯 ────────────────────────────────────────────────
//
// 독립 Card 방식 대신 카테고리 Card 안의 Row로 동작.
// Material 조상이 제공하는 InkWell ripple 효과 사용.
class _FaqAccordionRow extends StatefulWidget {
  final String question;
  final String answer;

  const _FaqAccordionRow({
    super.key,
    required this.question,
    required this.answer,
  });

  @override
  State<_FaqAccordionRow> createState() => _FaqAccordionRowState();
}

class _FaqAccordionRowState extends State<_FaqAccordionRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 질문 Row — 텍스트 + chevron, 파란 ? 아이콘 없음
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: ResponsiveHelper.spacing(context, 14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.question,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: ResponsiveHelper.iconSize(context, 20),
                  color: AppColors.grey400,
                ),
              ],
            ),
          ),
        ),
        // 답변 영역 — 연한 grey50 배경, 파란 강조 없음
        if (_expanded)
          Container(
            width: double.infinity,
            color: AppColors.grey50,
            padding: EdgeInsets.fromLTRB(
              ResponsiveHelper.spacing(context, 16),
              ResponsiveHelper.spacing(context, 10),
              ResponsiveHelper.spacing(context, 16),
              ResponsiveHelper.spacing(context, 14),
            ),
            child: Text(
              widget.answer,
              style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.grey700)
                  .copyWith(height: 1.6),
            ),
          ),
      ],
    );
  }
}

// ── 내부 데이터 모델 ───────────────────────────────────────────────────

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

class _FaqGroup {
  final String title;
  final IconData icon;
  final List<_FaqItem> items;

  const _FaqGroup({
    required this.title,
    required this.icon,
    required this.items,
  });
}
