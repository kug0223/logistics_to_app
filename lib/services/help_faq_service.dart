// lib/services/help_faq_service.dart
//
// help_faqs 컬렉션 CRUD 서비스 (슈퍼관리자 전용 write)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/core/help_faq_model.dart';

class HelpFaqService {
  final _col = FirebaseFirestore.instance.collection('help_faqs');

  Future<List<HelpFaqModel>> getItems(String role) async {
    try {
      final snap = await _col
          .where('role', isEqualTo: role)
          .where('isActive', isEqualTo: true)
          .orderBy('order')
          .get();
      return snap.docs
          .map((d) => HelpFaqModel.tryFromMap(d.data(), d.id))
          .whereType<HelpFaqModel>()
          .toList();
    } catch (e) {
      debugPrint('[HelpFaqService] getItems 실패: $e');
      return [];
    }
  }

  // 슈퍼관리자용 — 비활성 항목 포함 전체 목록
  Future<List<HelpFaqModel>> getAllItems(String role) async {
    final snap = await _col
        .where('role', isEqualTo: role)
        .orderBy('order')
        .get();
    return snap.docs
        .map((d) => HelpFaqModel.tryFromMap(d.data(), d.id))
        .whereType<HelpFaqModel>()
        .toList();
  }

  Future<String> addItem(HelpFaqModel item) async {
    final ref = await _col.add(item.toMap());
    return ref.id;
  }

  Future<void> updateItem(HelpFaqModel item) async {
    await _col.doc(item.id).update(item.toMap());
  }

  Future<void> deleteItem(String id) async {
    await _col.doc(id).delete();
  }

  // order 필드 일괄 갱신 (드래그 리오더 후 호출)
  Future<void> reorderItems(List<HelpFaqModel> items) async {
    final batch = FirebaseFirestore.instance.batch();
    for (int i = 0; i < items.length; i++) {
      batch.update(_col.doc(items[i].id), {'order': i});
    }
    await batch.commit();
  }

  // 기본 FAQ 시드 — 기존 데이터 전체 삭제 후 재등록
  Future<void> seedDefaults() async {
    final batch = FirebaseFirestore.instance.batch();

    // 기존 삭제
    final existing = await _col.get();
    for (final d in existing.docs) {
      batch.delete(d.reference);
    }

    // 기본값 등록
    final defaults = [..._defaultUserFaqs, ..._defaultAdminFaqs];
    for (int i = 0; i < defaults.length; i++) {
      batch.set(_col.doc(), defaults[i].toMap());
    }

    await batch.commit();
  }

  // ──────────────────────────────────────────────
  // 기본 FAQ 데이터 (help_screen.dart 하드코딩과 동기화)
  // ──────────────────────────────────────────────

  static final _defaultUserFaqs = [
    _faq('user', 0, '📋 공고 & 지원', '', isHeader: true),
    _faq('user', 1, '📋 공고 & 지원', '공고에 어떻게 지원하나요?',
        answer: '홈 화면 → "공고 찾기"를 눌러 날짜·업종별로 공고를 탐색할 수 있습니다. '
            '원하는 공고를 선택한 뒤 "지원하기" 버튼을 누르면 됩니다. '
            '관리자가 확정하면 알림과 함께 근로계약서 서명 요청이 전송됩니다.'),
    _faq('user', 2, '📋 공고 & 지원', '지원 취소는 어떻게 하나요?',
        answer: '"내 스케줄" → 해당 일정 카드 → "지원 취소" 버튼을 누르세요.\n'
            '• 대기 중(미확정): 즉시 취소됩니다.\n'
            '• 확정 후: 취소 요청을 보내야 하며, 관리자 승인 후 취소됩니다.\n'
            '당일 취소 또는 무단 노쇼는 신뢰도 점수에 영향을 줍니다.'),
    _faq('user', 3, '📋 공고 & 지원', '근무 확정·취소 알림이 오지 않아요.',
        answer: '① 설정 → 알림 → 푸시 알림이 켜져 있는지 확인하세요.\n'
            '② 기기 설정에서 ALfit 알림 권한이 "허용"인지 확인하세요.\n'
            '③ 설정 → 알림 → "지원 결과 알림"이 활성화되어 있는지 확인하세요.'),
    _faq('user', 4, '⏰ 출퇴근 체크', '', isHeader: true),
    _faq('user', 5, '⏰ 출퇴근 체크', '출근 체크가 안 돼요.',
        answer: '① 근무지 근처(GPS 반경 내)에 있는지 확인하세요.\n'
            '② 위치 권한이 "항상 허용"으로 설정됐는지 확인하세요.\n'
            '③ 블루투스가 켜져 있는지 확인하세요 (비콘 방식 사업장).\n'
            '④ 출근 예정 시간 10분 전부터 체크 가능합니다.\n'
            '그래도 안 되면 관리자에게 수동 시간 조정을 요청하세요.'),
    _faq('user', 6, '⏰ 출퇴근 체크', '실수로 출근 체크 시간이 잘못됐어요.',
        answer: '"내 스케줄" → 해당 날짜 → "수정 요청" 버튼을 눌러 '
            '관리자에게 수정 요청을 보내세요. 관리자 승인 후 시간이 변경됩니다. '
            '원본 기록(최초 체크 시간)은 별도 보관됩니다.'),
    _faq('user', 7, '⏰ 출퇴근 체크', '퇴근 체크는 언제부터 가능한가요?',
        answer: '예정 퇴근 시간 이후부터 퇴근 체크가 가능합니다. '
            '연장 근무 시 실제 퇴근 시간을 기록하면 추가 근무가 반영됩니다.'),
    _faq('user', 8, '✍️ 근로계약서', '', isHeader: true),
    _faq('user', 9, '✍️ 근로계약서', '계약서 서명 요청이 왔어요. 어떻게 하나요?',
        answer: '① 설정 → "내 서명"에서 서명을 먼저 등록해주세요.\n'
            '② 홈 하단 "미서명 계약서 N건" 배너를 탭하거나, '
            '"내 스케줄" → 해당 카드 → 계약서를 열어 내용을 확인한 뒤 서명하세요.\n'
            '서명 후 관리자와 본인 모두 서명된 계약서를 PDF로 확인할 수 있습니다.'),
    _faq('user', 10, '✍️ 근로계약서', '내 서명은 어디서 등록하나요?',
        answer: '설정 → "내 서명" 항목에서 서명 패드에 직접 서명을 그릴 수 있습니다. '
            '등록된 서명은 계약서 서명 시 자동으로 적용됩니다. '
            '"변경"으로 언제든지 업데이트할 수 있습니다.'),
    _faq('user', 11, '💰 급여 & 임금명세서', '', isHeader: true),
    _faq('user', 12, '💰 급여 & 임금명세서', '임금명세서는 어디서 확인하나요?',
        answer: '"내 스케줄" → 확정된 근무 카드 → "임금명세서" 버튼을 누르면 '
            'PDF 형태로 확인하고 저장·공유할 수 있습니다. '
            '관리자가 급여를 확정한 이후부터 열람 가능합니다.'),
    _faq('user', 13, '💰 급여 & 임금명세서', '급여가 예상과 다르게 계산됐어요.',
        answer: '임금명세서에서 공제 내역(4대보험, 식대공제 등)을 확인하세요. '
            '야간 식대나 특정 공제가 적용됐을 수 있습니다. '
            '이상이 있으면 관리자에게 직접 문의하세요.'),
    _faq('user', 14, '⭐ 신뢰도', '', isHeader: true),
    _faq('user', 15, '⭐ 신뢰도', '신뢰도 점수는 어떻게 올리나요?',
        answer: '• 정상 출근: +1점\n'
            '• 퇴근 완료: +0.5점\n'
            '• 지각: -1점\n'
            '• 노쇼(무단 결근): -3점\n\n'
            '꾸준히 성실하게 근무하면 점수가 올라가고, '
            '채용 시 관리자에게 더 좋은 인상을 줄 수 있습니다.'),
    _faq('user', 16, '⭐ 신뢰도', '신뢰도가 낮아져서 지원이 막혔어요.',
        answer: '신뢰도가 일정 수준 이하로 떨어지면 지원이 제한될 수 있습니다. '
            '설정 → 신뢰도 → "재시작 프로그램"을 통해 점수를 회복할 수 있습니다. '
            '관리자 평점도 신뢰도에 영향을 줍니다.'),
    _faq('user', 17, '👤 계정 & 서류', '', isHeader: true),
    _faq('user', 18, '👤 계정 & 서류', 'PASS 본인인증은 어디서 하나요?',
        answer: '설정 → "본인인증 (PASS)"을 눌러 인증을 진행할 수 있습니다. '
            '본인인증 완료 후 공고 지원 시 신뢰도가 높아집니다.'),
    _faq('user', 19, '👤 계정 & 서류', '서류(신분증, 통장사본 등)는 어디서 등록하나요?',
        answer: '설정 → "내 서류 관리"에서 신분증, 계좌정보, 통장사본을 등록할 수 있습니다. '
            '서류 미등록 시 일부 사업장에서 지원이 제한될 수 있습니다.'),
  ];

  static final _defaultAdminFaqs = [
    _faq('admin', 0, '📢 공고(TO) 등록 & 관리', '', isHeader: true),
    _faq('admin', 1, '📢 공고(TO) 등록 & 관리', '공고는 어떻게 등록하나요?',
        answer: '홈 화면 우측 상단 "+" 버튼 → 필요 정보(업종, 날짜, 시간, 인원, 시급)를 입력 → '
            '"공개"를 누르면 즉시 지원자를 받을 수 있습니다. '
            '"임시저장" 후 나중에 공개하는 것도 가능합니다.'),
    _faq('admin', 2, '📢 공고(TO) 등록 & 관리', '지원자를 어떻게 확정하나요?',
        answer: '홈 달력 → 해당 날짜 탭 → 공고 카드 → "지원자 목록"에서 '
            '원하는 지원자의 "확정" 버튼을 누르세요. '
            '확정 후 근로계약서를 발송하려면 날인 후 "계약서 발송"을 눌러주세요.'),
    _faq('admin', 3, '📢 공고(TO) 등록 & 관리', '등록된 공고를 수정하거나 삭제할 수 있나요?',
        answer: '홈 달력 → 해당 공고 카드 → "수정" 또는 "삭제"를 선택하세요. '
            '이미 확정된 지원자가 있으면 날짜·시간 수정이 제한되며, '
            '삭제 시 확정된 지원자에게 취소 알림이 전송됩니다.'),
    _faq('admin', 4, '📋 근로계약서', '', isHeader: true),
    _faq('admin', 5, '📋 근로계약서', '계약서는 어떻게 발송하나요?',
        answer: '지원자 확정 후, 지원자 카드에서 "계약서 발송" 버튼을 누르세요. '
            '사전에 날인(인감/서명)이 등록되어 있어야 합니다. '
            '발송된 계약서는 근무자 앱에서 서명 요청이 표시됩니다.'),
    _faq('admin', 6, '📋 근로계약서', '계약서 템플릿은 어디서 관리하나요?',
        answer: '설정 → "근로계약서 관리"에서 템플릿을 추가·수정·삭제할 수 있습니다. '
            '업무 유형별로 다른 템플릿을 설정하면 공고 등록 시 자동으로 적용됩니다.'),
    _faq('admin', 7, '📋 근로계약서', '근무자가 계약서 서명을 아직 안 했어요.',
        answer: '홈 하단 "미서명 계약서 N건" 배너를 확인하거나, '
            '해당 지원자 카드에서 서명 대기 상태를 볼 수 있습니다. '
            '근무자에게 직접 안내하거나, 알림이 자동 발송됩니다.'),
    _faq('admin', 8, '📅 당일 출퇴근 관리', '', isHeader: true),
    _faq('admin', 9, '📅 당일 출퇴근 관리', '당일 근무 현황은 어디서 보나요?',
        answer: '홈 달력 → 해당 날짜 → 공고 카드 → "당일명단" 버튼을 누르세요. '
            '실시간 출퇴근 현황, 지각·노쇼 여부를 한눈에 확인할 수 있습니다.'),
    _faq('admin', 10, '📅 당일 출퇴근 관리', '근무자가 출퇴근 체크를 못 했을 때 어떻게 하나요?',
        answer: '당일명단 → 해당 근무자 → "시간 조정" 버튼으로 관리자가 직접 '
            '출퇴근 시간을 입력할 수 있습니다. '
            '원본 기록(근무자가 체크한 시간)은 별도 보관됩니다.'),
    _faq('admin', 11, '📅 당일 출퇴근 관리', '노쇼 처리는 어떻게 하나요?',
        answer: '당일명단 → 해당 근무자 → "노쇼 처리" 버튼을 누르세요. '
            '노쇼 처리 시 해당 근무자의 신뢰도 점수가 차감됩니다.'),
    _faq('admin', 12, '💳 급여 관리', '', isHeader: true),
    _faq('admin', 13, '💳 급여 관리', '급여 확정은 어떻게 하나요?',
        answer: '홈 → "급여 관리" → 해당 월 선택 → 근무자별 "급여 확인"에서 '
            '공제 항목을 검토한 뒤 "급여 확정"을 누르세요. '
            '확정 후 근무자 앱에 임금명세서가 공개됩니다.'),
    _faq('admin', 14, '💳 급여 관리', '식대(야식) 공제는 어떻게 적용하나요?',
        answer: '급여 확인 화면의 그룹 헤더에서 공제 시간(+30분 / +60분 / +90분)을 선택하면 '
            '그룹 내 근무자에게 일괄 적용됩니다. '
            '개별 근무자별로 다르게 설정하는 것도 가능합니다.'),
    _faq('admin', 15, '💳 급여 관리', '급여 이체 내역을 엑셀로 내보낼 수 있나요?',
        answer: '"급여 지급 현황" 화면 → "엑셀" 버튼을 누르면 '
            '은행 일괄이체용 엑셀 파일이 생성됩니다. '
            '이름·은행명·계좌번호·이체금액이 포함됩니다.'),
    _faq('admin', 16, '👥 인력 & 멤버 관리', '', isHeader: true),
    _faq('admin', 17, '👥 인력 & 멤버 관리', '고정 근무자를 등록하려면?',
        answer: '홈 → "인력 관리" → "고정 근무자 추가"에서 등록할 수 있습니다. '
            '고정 근무자는 공고 없이도 스케줄을 배정할 수 있습니다.'),
    _faq('admin', 18, '👥 인력 & 멤버 관리', '서브관리자(하위 관리자)를 추가하려면?',
        answer: '설정 → 사업장 설정 → "멤버 관리"에서 초대 코드나 이메일로 '
            '서브관리자를 초대하고 권한(공고 관리/근무자 관리/급여 관리/계약서 관리)을 '
            '개별 설정할 수 있습니다.'),
    _faq('admin', 19, '⚙️ 사업장 설정', '', isHeader: true),
    _faq('admin', 20, '⚙️ 사업장 설정', '업무 유형은 어디서 추가·관리하나요?',
        answer: '설정 → "업무 유형 관리"에서 업종별 업무 유형을 추가하고 '
            '시급·일급 기준을 설정할 수 있습니다. '
            '공고 등록 시 이 업무 유형을 선택하면 임금이 자동으로 적용됩니다.'),
    _faq('admin', 21, '⚙️ 사업장 설정', '날인(인감/서명)은 어디서 등록하나요?',
        answer: '설정 → 사업장 설정 → "날인 관리"에서 도장 이미지 업로드 또는 '
            '직접 서명으로 날인을 등록할 수 있습니다. '
            '계약서 발송 시 자동으로 적용됩니다.'),
  ];

  static HelpFaqModel _faq(
    String role,
    int order,
    String category,
    String question, {
    String answer = '',
    bool isHeader = false,
  }) {
    return HelpFaqModel(
      id: '',
      role: role,
      order: order,
      category: category,
      question: isHeader ? category : question,
      answer: answer,
      isHeader: isHeader,
      isActive: true,
    );
  }
}
