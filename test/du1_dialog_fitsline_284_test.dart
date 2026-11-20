// ignore_for_file: depend_on_referenced_packages
// [DU284 공용 확인창 한 줄 판정 baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU284_RUN=1 이고 DU284_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   앱 lib/ 의 공용 확인창 호출 중 글자 그대로인 것(제목·본문·행동 글, 생성: work/du284-dialog-fitsline/src/extract284.py)을
//   실제 메서드(DialogHelper.showConfirm 등)로 열고 재고 닫는다(Navigator.pop). 누르는 것은 없다.
//   조건 W360/1.0·M360/1.5·B320/2.0. 요소마다 실제 문단 폭(wDraw)·지금 판정 폭(wShell)·고친 판정 폭(wFix)·가용 폭을 잰다.
//   [v1 TB 뒤 보정(반영 전)] 고정 PNG 표본 7·확인창 폭(dlgW) 단언·예측 longToken 부분집합 단언을 더했다(측정 코드는 v0 와 같다).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/dialog_helper.dart';
import 'package:ALfit/utils/responsive_helper.dart';
import 'package:ALfit/utils/text_layout.dart';

import 'support/du1_vq_capture.dart';

typedef _It = ({String id, String m, String title, String msg, String ok, String? no, String src});

// 생성 구역 — extract284.py 결과(plan/strings284.json) 46개. 손으로 고치지 않는다.
const List<_It> _items = [
  (id: 'contract_import_paste_screen_57', m: 'showConfirm', title: '나가시겠어요?', msg: '입력한 내용이 사라집니다.', ok: '나가기', no: '계속 편집', src: 'lib/screens/business_admin/contract_import_paste_screen.dart:57'),
  (id: 'contract_import_result_screen_93', m: 'showConfirm', title: '가져온 내용 확인을 그만둘까요?', msg: '선택한 조항 상태가 사라집니다.\n붙여넣은 내용은 그대로 남아 있습니다.', ok: '나가기', no: '계속 확인', src: 'lib/screens/business_admin/contract_import_result_screen.dart:93'),
  (id: 'attendance_status_dialog_2571', m: 'showConfirm', title: '대체 인력 충원', msg: '이 근로자의 자리를 반납하고 대체 인력을 모집합니다.\n계속하시겠습니까?', ok: '충원하기', no: '취소', src: 'lib/screens/business_admin/dialogs/attendance_status_dialog.dart:2571'),
  (id: 'fixed_worker_management_dialog_2809', m: 'showConfirm', title: '해지 요청 취소', msg: '계약해지 요청을 취소하시겠습니까?', ok: '취소하기', no: '취소', src: 'lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart:2809'),
  (id: 'work_detail_management_dialog_64', m: 'showAlert', title: '인원 현황을 불러오지 못했어요', msg: '지금 인원 수를 확인할 수 없어 업무를 마감하거나 재개할 수 없어요.\n새로고침 후 다시 시도해 주세요.', ok: '확인', no: null, src: 'lib/screens/business_admin/dialogs/work_detail_management_dialog.dart:64'),
  (id: 'work_detail_management_dialog_421', m: 'showInfo', title: '알림', msg: '시간이 지난 업무는 수정할 수 없습니다.', ok: '확인', no: null, src: 'lib/screens/business_admin/dialogs/work_detail_management_dialog.dart:421'),
  (id: 'work_detail_management_dialog_434', m: 'showInfo', title: '알림', msg: '인원이 충족된 업무입니다.\n추가 인원이 필요하면 모집인원을 늘려주세요.', ok: '확인', no: null, src: 'lib/screens/business_admin/dialogs/work_detail_management_dialog.dart:434'),
  (id: 'work_detail_management_dialog_452', m: 'showInfo', title: '정원 정보를 불러오지 못했습니다', msg: '이 업무의 확정 인원을 확인할 수 없어 마감·재오픈을 진행하지 않습니다.\n\n목록을 새로고침한 뒤 다시 시도해주세요. 정원을 확인할 수 있는 다른 업무는 그대로 관리할 수 있습니다.', ok: '확인', no: null, src: 'lib/screens/business_admin/dialogs/work_detail_management_dialog.dart:452'),
  (id: 'create_to_screen_1028', m: 'showConfirm', title: '근무 유형 변경', msg: '유형을 변경하면 입력한 날짜/기간 정보가 초기화됩니다.\n계속하시겠습니까?', ok: '변경', no: '취소', src: 'lib/screens/business_admin/to_management/create_to_screen.dart:1028'),
  (id: 'create_to_screen_1263', m: 'showConfirm', title: '사업주 날인 미등록', msg: '근로계약서 서명을 위해 사업주 날인이 필요합니다.\n설정 > 사업주 날인에서 도장 이미지 또는 서명을 먼저 등록해주세요.', ok: '설정으로 이동', no: '취소', src: 'lib/screens/business_admin/to_management/create_to_screen.dart:1263'),
  (id: 'create_to_screen_1283', m: 'showConfirm', title: '지원 마감 경과', msg: '선택한 모든 날짜의 지원 마감이 이미 지났습니다.\n등록 즉시 마감 상태가 됩니다.\n그래도 등록하시겠습니까?', ok: '등록', no: '취소', src: 'lib/screens/business_admin/to_management/create_to_screen.dart:1283'),
  (id: 'create_to_screen_1470', m: 'showConfirm', title: '입력 중인 내용이 있습니다', msg: '공고 등록을 취소하시겠습니까?\n입력한 내용이 모두 사라집니다.', ok: '나가기', no: '계속 작성', src: 'lib/screens/business_admin/to_management/create_to_screen.dart:1470'),
  (id: 'edit_to_screen_1339', m: 'showConfirm', title: '변경사항 취소', msg: '저장하지 않은 변경사항이 있습니다.\n나가시겠습니까?', ok: '나가기', no: '계속 수정', src: 'lib/screens/business_admin/to_management/edit_to_screen.dart:1339'),
  (id: 'document_management_screen_635', m: 'showDangerConfirm', title: '사업자등록증 삭제', msg: '등록된 사업자등록증을 삭제하시겠습니까?', ok: '삭제', no: '취소', src: 'lib/screens/common/document_management_screen.dart:635'),
  (id: 'document_management_screen_1052', m: 'showDangerConfirm', title: '신분증 삭제', msg: '삭제하면 다시 등록해야 합니다.\n등록된 신분증을 삭제하시겠습니까?', ok: '삭제', no: '취소', src: 'lib/screens/common/document_management_screen.dart:1052'),
  (id: 'document_management_screen_1090', m: 'showDangerConfirm', title: '급여 계좌 삭제', msg: '삭제하면 다시 등록해야 합니다.\n등록된 급여 계좌 정보를 삭제하시겠습니까?', ok: '삭제', no: '취소', src: 'lib/screens/common/document_management_screen.dart:1090'),
  (id: 'job_posting_screen_3849', m: 'showCancelConfirm', title: '지원 취소', msg: '지원을 취소하시겠습니까?', ok: '취소하기', no: '취소', src: 'lib/screens/common/job_posting_screen.dart:3849'),
  (id: 'profile_edit_screen_322', m: 'showDangerConfirm', title: '변경 취소', msg: '저장하지 않은 변경사항이 있어요.\n나가면 입력한 내용이 사라져요.', ok: '나가기', no: '계속 편집', src: 'lib/screens/common/profile_edit_screen.dart:322'),
  (id: 'settings_screen_1928', m: 'showConfirm', title: 'Application 마이그레이션', msg: '기존 지원서에 누락된 workDetailId, toId, groupId를 채웁니다.\n\n⚠️ 데이터가 많으면 시간이 걸릴 수 있습니다.\n계속하시겠습니까?', ok: '실행', no: '취소', src: 'lib/screens/common/settings_screen.dart:1928'),
  (id: 'settings_screen_1981', m: 'showConfirm', title: '총 근무시간 마이그레이션', msg: '확정된 근태 기록을 기반으로 모든 사용자의\n총 근무시간(totalWorkHours)을 재계산합니다.\n\n⚠️ 기존 값을 덮어씁니다.\n계속하시겠습니까?', ok: '실행', no: '취소', src: 'lib/screens/common/settings_screen.dart:1981'),
  (id: 'settings_screen_2196', m: 'showConfirm', title: '서명 삭제', msg: '등록된 서명을 삭제하시겠습니까?', ok: '삭제', no: '취소', src: 'lib/screens/common/settings_screen.dart:2196'),
  (id: 'settings_screen_2711', m: 'showConfirm', title: '날인 삭제', msg: '등록된 날인을 삭제하시겠습니까?', ok: '삭제', no: '취소', src: 'lib/screens/common/settings_screen.dart:2711'),
  (id: 'settings_screen_2771', m: 'showDangerConfirm', title: '정말 탈퇴하시겠습니까?', msg: '탈퇴 후 계정 및 모든 데이터가 삭제되며 복구할 수 없습니다.', ok: '탈퇴하기', no: '취소', src: 'lib/screens/common/settings_screen.dart:2771'),
  (id: 'contract_sign_screen_308', m: 'showConfirm', title: '사업주 날인 미등록', msg: '계약서 발송을 위해 사업주 날인이 필요합니다.\n설정 > 사업주 날인에서 도장 또는 서명을 먼저 등록해주세요.', ok: '설정으로 이동', no: '취소', src: 'lib/screens/contract/contract_sign_screen.dart:308'),
  (id: 'contract_sign_screen_471', m: 'showConfirm', title: '서명 저장', msg: '이 서명을 저장해두면 다음 계약서 서명 시 바로 사용할 수 있습니다.', ok: '저장', no: '저장 안 함', src: 'lib/screens/contract/contract_sign_screen.dart:471'),
  (id: 'help_faq_management_screen_84', m: 'showConfirm', title: '기본값으로 초기화', msg: '현재 FAQ 전체가 기본값으로 교체됩니다.\n이 작업은 되돌릴 수 없습니다.', ok: '초기화', no: '취소', src: 'lib/screens/super_admin/help_faq_management_screen.dart:84'),
  (id: 'attendance_check_screen_326', m: 'showError', title: '오류', msg: '기기 시간이 실제 시간과 크게 다릅니다.\n설정에서 "자동 날짜/시간"을 켠 후 다시 시도해주세요.', ok: '확인', no: null, src: 'lib/screens/user/attendance_check_screen.dart:326'),
  (id: 'attendance_check_screen_338', m: 'showError', title: '오류', msg: '사업장 정보를 찾을 수 없습니다.', ok: '확인', no: null, src: 'lib/screens/user/attendance_check_screen.dart:338'),
  (id: 'attendance_check_screen_346', m: 'showError', title: '오류', msg: '사업장이 운영을 종료해 오늘은 출근할 수 없어요.\n지난 근무의 급여는 그대로 처리됩니다.', ok: '확인', no: null, src: 'lib/screens/user/attendance_check_screen.dart:346'),
  (id: 'attendance_check_screen_364', m: 'showError', title: '수동 출근 방식', msg: '이 사업장은 관리자가 직접 출퇴근을 처리합니다.\n관리자에게 문의해주세요.', ok: '확인', no: null, src: 'lib/screens/user/attendance_check_screen.dart:364'),
  (id: 'attendance_check_screen_561', m: 'showError', title: '오류', msg: 'GPS 위치를 가져올 수 없습니다.\n가짜 GPS 앱을 사용 중이거나 위치 서비스에 문제가 있습니다.', ok: '확인', no: null, src: 'lib/screens/user/attendance_check_screen.dart:561'),
  (id: 'attendance_check_screen_580', m: 'showError', title: '사업장 위치 미설정', msg: '사업장의 GPS 위치가 등록되어 있지 않습니다.\n관리자에게 사업장 위치 등록을 요청하세요.', ok: '확인', no: null, src: 'lib/screens/user/attendance_check_screen.dart:580'),
  (id: 'attendance_check_screen_624', m: 'showError', title: '비콘 설정 오류', msg: '사업장에 비콘 UUID가 등록되어 있지 않습니다.\n관리자에게 문의하세요.', ok: '확인', no: null, src: 'lib/screens/user/attendance_check_screen.dart:624'),
  (id: 'attendance_check_screen_656', m: 'showError', title: '블루투스 오류', msg: '블루투스 권한이 없거나 비콘 스캔에 실패했습니다.\n블루투스가 켜져 있는지 확인해주세요.', ok: '확인', no: null, src: 'lib/screens/user/attendance_check_screen.dart:656'),
  (id: 'attendance_check_screen_668', m: 'showError', title: '비콘 미감지', msg: '사업장 비콘을 감지하지 못했습니다.\n사업장 내부에서 다시 시도해주세요.', ok: '확인', no: null, src: 'lib/screens/user/attendance_check_screen.dart:668'),
  (id: 'attendance_check_screen_690', m: 'showError', title: 'GPS 필요', msg: '비콘 출근 시 GPS 위치도 확인이 필요합니다.\nGPS를 활성화하고 다시 시도해주세요.', ok: '확인', no: null, src: 'lib/screens/user/attendance_check_screen.dart:690'),
  (id: 'attendance_check_screen_709', m: 'showConfirm', title: '퇴근 확인', msg: '퇴근 처리하시겠습니까?', ok: '퇴근', no: '취소', src: 'lib/screens/user/attendance_check_screen.dart:709'),
  (id: 'attendance_check_screen_802', m: 'showAlert', title: '퇴근 시각은 기록됐어요', msg: '퇴근하신 시각은 그대로 저장됐습니다.\n\n다만 이 사업장의 근태 계산 기준으로는 인정 근무시간이 0분으로 계산돼, 관리자 확인이 필요합니다.\n관리자가 근태를 확인하면 급여가 계산됩니다.', ok: '확인', no: null, src: 'lib/screens/user/attendance_check_screen.dart:802'),
  (id: 'renewal_proposal_screen_130', m: 'showConfirm', title: '연장 거절', msg: '이번 계약 연장 제안을 거절합니다.\n현재 계약은 기존 종료일까지 유지됩니다.', ok: '거절', no: '취소', src: 'lib/screens/user/renewal_proposal_screen.dart:130'),
  (id: 'signature_screen_373', m: 'showDangerConfirm', title: '서명 삭제', msg: '삭제하면 계약서 서명 시 자동으로 사용할 수 없습니다.\n등록된 서명을 삭제하시겠습니까?', ok: '삭제', no: '취소', src: 'lib/screens/user/signature_screen.dart:373'),
  (id: 'logout', m: 'showConfirm', title: '로그아웃', msg: '로그아웃 하시겠습니까?', ok: '로그아웃', no: '취소', src: 'lib/utils/dialog_helper.dart:415'),
  (id: 'decline', m: 'showConfirm', title: '초대 거절', msg: '초대를 거절하시겠습니까?', ok: '초대 거절', no: '닫기', src: 'lib/utils/dialog_helper.dart:464'),
  (id: 'admin_to_group_card_3277', m: 'showDangerConfirm', title: '초대 취소', msg: '이 근로자의 초대를 취소하시겠습니까?', ok: '취소하기', no: '취소', src: 'lib/widgets/admin/cards/admin_to_group_card.dart:3277'),
  (id: 'confirmed_reassignment_sheet_54', m: 'showConfirm', title: '변경 제안 철회', msg: '보낸 근무 변경 제안을 철회합니다.\n근로자의 기존 근무는 그대로 유지됩니다.', ok: '철회', no: '닫기', src: 'lib/widgets/dialogs/confirmed_reassignment_sheet.dart:54'),
  (id: 'long_term_work_management_dialog_401', m: 'showConfirm', title: '퇴사 요청 취소', msg: '퇴사 요청을 취소하시겠습니까?', ok: '취소하기', no: '취소', src: 'lib/widgets/dialogs/long_term_work_management_dialog.dart:401'),
  (id: 'create_edit_work_detail_dialog_2140', m: 'showConfirm', title: '작성 중인 내용을 취소할까요?', msg: '입력한 내용은 저장되지 않습니다.', ok: '취소', no: '계속 작성', src: 'lib/widgets/pickers/create_edit_work_detail_dialog.dart:2140'),
];

/// 항상 PNG 를 찍는 고정 표본(판정과 무관한 대조용)
const _fixedShots = {
  'logout',
  'decline',
  'document_management_screen_635',
  'create_to_screen_1283',
  'settings_screen_2771',
  'job_posting_screen_3849',
  'edit_to_screen_1339',
};

/// FL4 뒤에도 낱말 하나가 가용 폭보다 넓어 끊김이 불가피하다고 쓰기 전에 예측한 곳(plan/predict_fl4.txt)
//   [r1] 같은 SA 전용 이전 도구 문구의 M360 을 더했다 — 묶인 낱말 '근무시간(totalWorkHours)을' 294.7 > 292(예측은 원문 폭 289.4 로 쟀다)
const _expectedLong = {'B320|settings_screen_1981|본문', 'B320|settings_screen_2771|제목', 'M360|settings_screen_1981|본문'};

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a);
  final y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

void _out(String l) {
  // ignore: avoid_print
  print(l);
}

/// 글자 단위 줄 나눔 — 줄마다 보이는 글자, 그리고 '낱말 안에서 끊긴' 곳 수(DU275 시험과 같은 규칙).
({List<String> lines, int sylBreaks}) _lineInfo(RenderParagraph rp) {
  final raw = rp.text.toPlainText();
  final wj = String.fromCharCode(0x2060);
  final zw = String.fromCharCode(0x200B);
  bool word(String ch) {
    final u = ch.codeUnitAt(0);
    return (u >= 0xAC00 && u <= 0xD7A3) || (u >= 0x30 && u <= 0x39) || (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A);
  }

  final lines = <String>[];
  var buf = StringBuffer();
  int? lastTop;
  var lastIdx = -1;
  var breaks = 0;
  for (var i = 0; i < raw.length; i++) {
    final ch = raw[i];
    if (ch == wj) continue;
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty || ch == ' ' || ch == zw) {
      buf.write(ch);
      continue;
    }
    final top = bx.first.top.round();
    if (lastTop != null && top != lastTop) {
      lines.add(TextLayout.plain(buf.toString()).trim());
      buf = StringBuffer();
      final gap = raw.substring(lastIdx, i + 1);
      final sep = gap.contains(' ') || gap.contains(zw) || gap.contains(String.fromCharCode(10)) ||
          RegExp('[·,./()~-]').hasMatch(gap);
      if (!sep && word(raw[lastIdx]) && word(ch)) breaks++;
    }
    buf.write(ch);
    lastTop = top;
    lastIdx = i;
  }
  lines.add(TextLayout.plain(buf.toString()).trim());
  return (lines: lines, sylBreaks: breaks);
}

double _tpWidth(String text, TextStyle style, TextScaler scaler, Locale? locale) {
  final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, textScaler: scaler, locale: locale)
    ..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}

void _open(BuildContext ctx, _It it) {
  switch (it.m) {
    case 'showConfirm':
      unawaited(DialogHelper.showConfirm(ctx, title: it.title, message: it.msg, confirmText: it.ok, cancelText: it.no!));
    case 'showDangerConfirm':
      unawaited(DialogHelper.showDangerConfirm(ctx, title: it.title, message: it.msg, confirmText: it.ok, cancelText: it.no!));
    case 'showAlert':
      unawaited(DialogHelper.showAlert(ctx, title: it.title, message: it.msg, buttonText: it.ok));
    case 'showError':
      unawaited(DialogHelper.showError(ctx, title: it.title, message: it.msg));
    case 'showInfo':
      unawaited(DialogHelper.showInfo(ctx, title: it.title, message: it.msg));
    case 'showCancelConfirm':
      unawaited(DialogHelper.showCancelConfirm(ctx, title: it.title, message: it.msg));
    default:
      throw StateError('알 수 없는 메서드 ${it.m}');
  }
}

void main() {
  final phase = Platform.environment['DU284_PHASE'] ?? '';
  final run = Platform.environment['DU284_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);
  final wj = String.fromCharCode(0x2060);

  testWidgets('D284 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPump = 0, nPng = 0, nOpen = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D284-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        need(nPump <= 4000 && nPng <= 160 && nOpen <= 160, '사용량 한도');
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    final overflow = <String>[];
    void safe(String at) {
      final ex = t.takeException();
      need(ex == null, '$at 예외: $ex');
      for (final e in errors) {
        if (!after && e.startsWith('A RenderFlex overflowed by')) {
          overflow.add('$at $e');
        } else {
          stop('$at 예외/overflow: $e');
        }
      }
      errors.clear();
    }

    double r1(double v) => double.parse(v.toStringAsFixed(1));
    List<double> lt(Rect r) => [r.left, r.top, r.right, r.bottom].map(r1).toList();
    bool inside(Rect r, Rect b) => r.left >= b.left - 0.5 && r.top >= b.top - 0.5 && r.right <= b.right + 0.5 && r.bottom <= b.bottom + 0.5;

    Color bgOf(Element e) {
      final layers = <Color>[];
      e.visitAncestorElements((a) {
        final w = a.widget;
        Color? c;
        if (w is ColoredBox) {
          c = w.color;
        } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
          c = (w.decoration as BoxDecoration).color;
        } else if (w is Material && w.type != MaterialType.transparency) {
          c = w.color ?? Theme.of(a).canvasColor;
        } else if (w is Scaffold) {
          c = w.backgroundColor ?? Theme.of(a).scaffoldBackgroundColor;
        }
        if (c == null || c.a == 0) return true;
        layers.add(c);
        return c.a < 1.0;
      });
      var out = layers.isEmpty ? Colors.white : layers.last;
      for (final c in layers.reversed.skip(1)) {
        out = Color.alphaBlend(c, out);
      }
      return out;
    }

    final key = GlobalKey();
    final rows = <Map<String, Object?>>[];
    try {
      for (final c in const [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'M360', w: 360.0, h: 780.0, s: 1.5),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ]) {
        cur = c.id;
        await t.pumpWidget(const SizedBox.shrink());
        await frames(1);
        safe('조건 시작');
        t.view.physicalSize = Size(c.w, c.h);
        t.view.devicePixelRatio = 1.0;
        t.platformDispatcher.textScaleFactorTestValue = c.s;
        final screen = Rect.fromLTWH(0, 0, c.w, c.h);
        final enlarged = c.s > 1.0;
        BuildContext? appCtx;
        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('ko', 'KR')],
            home: Scaffold(
              body: Builder(builder: (ctx) {
                appCtx = ctx;
                return const SizedBox.expand();
              }),
            ),
          ),
        ));
        await frames(2);
        need(appCtx != null, '앱 문맥 없음');
        for (final it in _items) {
          cur = '${c.id} ${it.id}';
          nOpen++;
          _open(appCtx!, it);
          await frames(8);
          safe('열림');
          Finder host() => find.byType(Dialog);
          need(host().evaluate().length == 1, '확인창이 열리지 않았다');
          final ctxIn = t.element(host());
          Finder fe(Element e) => find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
          // 확인창 안 글자 전부(위 → 아래)
          final texts = find
              .descendant(of: host(), matching: find.byType(RichText), skipOffstage: false)
              .evaluate()
              .toList()
            ..sort((a, b) => t.getRect(fe(a)).top.compareTo(t.getRect(fe(b)).top));
          /// 가장 가까운 조상(깊이가 가장 깊은 것)
          Element? nearest(Element e, Type type) {
            final xs = find.ancestor(of: fe(e), matching: find.byType(type)).evaluate().toList();
            if (xs.isEmpty) return null;
            xs.sort((a, b) => b.depth.compareTo(a.depth));
            return xs.first;
          }

          String plainOf(Element e) => TextLayout.plain((e.widget as RichText).text.toPlainText());
          Element? pick(String s, {bool last = false, Set<Element> not = const {}}) {
            final xs = texts.where((e) => plainOf(e) == s && !not.contains(e)).toList();
            if (xs.isEmpty) return null;
            return last ? xs.last : xs.first;
          }

          final eTitle = pick(it.title);
          need(eTitle != null, '제목 없음');
          final eMsg = pick(it.msg, not: {eTitle!});
          need(eMsg != null, '본문 없음');
          final eOk = pick(it.ok, last: true, not: {eTitle, eMsg!});
          need(eOk != null, '주 행동 없음');
          final eNo = it.no == null ? null : pick(it.no!, last: true, not: {eTitle, eMsg, eOk!});
          need(it.no == null || eNo != null, '보조 행동 없음');
          Element lbOf(Element e) {
            final lb = nearest(e, LayoutBuilder);
            need(lb != null, 'LayoutBuilder 조상 없음');
            return lb!;
          }

          final scaler = MediaQuery.textScalerOf(ctxIn);
          final hdrLb = lbOf(eTitle);
          final hdrW = t.getSize(fe(hdrLb)).width;
          final icon = find.descendant(of: fe(hdrLb), matching: find.byType(Icon)).evaluate().first;
          final iconR = t.getRect(fe(icon));
          final besideW = hdrW - 44 - ResponsiveHelper.spacing(ctxIn, 12);
          final bodyLb = lbOf(eMsg);
          final bodyW = t.getSize(fe(bodyLb)).width;
          final actLb = lbOf(eOk!);
          final actW = t.getSize(fe(actLb)).width;
          final n = eNo == null ? 1 : 2;
          final per = (actW - ResponsiveHelper.spacing(ctxIn, 8) * (n - 1)) / n;
          final okR = t.getRect(fe(eOk));
          final noR = eNo == null ? null : t.getRect(fe(eNo));
          final btnLayout = noR == null ? 'single' : (okR.top < noR.bottom && noR.top < okR.bottom ? 'row' : 'col');
          final titleR = t.getRect(fe(eTitle));
          final titleLayout = titleR.left > iconR.right - 1 ? 'beside' : (titleR.top >= iconR.bottom - 1 ? 'above' : '?');
          // 확인창 자신의 면(Dialog 가 만드는 첫 Material) 폭
          final dlgW = t.getSize(find.descendant(of: host(), matching: find.byType(Material)).first).width;

          Map<String, Object?> info(String nm, Element e, TextStyle shell, Element lb, double availNow, double availJudge) {
            final rp = t.renderObject<RenderParagraph>(fe(e));
            final raw = plainOf(e);
            final r = t.getRect(fe(e));
            final st = rp.text.style;
            final fg = st?.color;
            final bg = bgOf(e);
            final li = _lineInfo(rp);
            final joined = rp.text.toPlainText().contains(wj);
            final lbCtx = lb;
            final eff = shell.inherit ? DefaultTextStyle.of(lbCtx).style.merge(shell) : shell;
            final loc = Localizations.maybeLocaleOf(lbCtx);
            final wShell = _tpWidth(raw, shell, scaler, null);
            final wFix = _tpWidth(raw, eff, scaler, loc);
            final wDraw = rp.getMaxIntrinsicWidth(double.infinity);
            var maxTok = 0.0;
            // [r1] 낱말 묶기(WJ) 글자도 letterSpacing 을 받아 묶인 낱말은 원문보다 넓다(0.25px/자) — 그린 꼴로 잰다
            for (final tok in raw.split(RegExp('[ $nl]+'))) {
              if (tok.isEmpty) continue;
              maxTok = math.max(maxTok, _tpWidth(joined ? TextLayout.keepWords(tok) : tok, eff, scaler, loc));
            }
            final ink = nearest(e, InkWell);
            final box = ink == null ? null : t.getRect(fe(ink));
            return {
              'name': nm, 'rect': lt(r), 'visible': inside(r, screen),
              'fontSize': st?.fontSize, 'weight': st?.fontWeight?.value, 'ls': st?.letterSpacing,
              'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg),
              'contrast': fg == null ? null : double.parse(_contrast(fg, bg).toStringAsFixed(2)),
              'didExceedMaxLines': rp.didExceedMaxLines,
              'lines': li.lines, 'sylBreaks': li.sylBreaks, 'joined': joined,
              'wShell': r1(wShell), 'wFix': r1(wFix), 'wDraw': r1(wDraw),
              'availNow': r1(availNow), 'availJudge': r1(availJudge),
              'flip': enlarged && ((wShell <= availJudge) != (wFix <= availJudge)),
              'longToken': maxTok > availNow + 0.5, 'maxTok': r1(maxTok),
              if (box != null) 'boxH': r1(box.height),
            };
          }

          final xs = <Map<String, Object?>>[];
          final titleShell = ResponsiveHelper.subtitleStyle(ctxIn).copyWith(fontWeight: FontWeight.bold, color: const Color(0xFF111827));
          xs.add(info('제목', eTitle, titleShell, hdrLb, titleLayout == 'beside' ? besideW : hdrW, besideW));
          xs.add(info('본문', eMsg, ResponsiveHelper.bodyStyle(ctxIn), bodyLb, bodyW, bodyW));
          final okShell = ResponsiveHelper.bodyStyle(ctxIn).copyWith(color: Colors.white, fontWeight: FontWeight.bold);
          final noShell = ResponsiveHelper.bodyStyle(ctxIn).copyWith(color: const Color(0xFF4B5563), fontWeight: FontWeight.w600);
          final btnNow = btnLayout == 'col' ? actW - 16 : per - 16;
          xs.add(info('주 행동', eOk, okShell, actLb, btnNow, per - 16));
          if (eNo != null) xs.add(info('보조 행동', eNo, noShell, actLb, btnNow, per - 16));
          // 행동 둘의 가로/세로 판정: 한 칸에 안 들어가는 글이 하나라도 있으면 세로
          final rowFlip = enlarged && n == 2 &&
              (xs.skip(2).any((x) => (x['wShell'] as double) > (x['availJudge'] as double)) !=
                  xs.skip(2).any((x) => (x['wFix'] as double) > (x['availJudge'] as double)));
          final anyFlip = rowFlip || xs.any((x) => x['flip'] == true);

          if (after) {
            final wantW = math.min(380.0, c.w - (enlarged ? 32 : 64));
            need((dlgW - wantW).abs() <= 0.5, '확인창 폭 $dlgW ≠ $wantW');
            for (final x in xs) {
              if (x['longToken'] == true) {
                need(_expectedLong.contains('${c.id}|${it.id}|${x['name']}'), '예측 밖 longToken $x');
              }
            }
            for (final x in xs) {
              final at = '${x['name']}';
              need(x['didExceedMaxLines'] != true, '$at 말줄임 $x');
              need(x['visible'] == true || x['name'] == '본문', '$at 화면 밖 $x');
              if (x['joined'] != true) {
                need(((x['wFix'] as double) - (x['wDraw'] as double)).abs() <= 0.5, '$at 판정 폭≠그린 폭 $x');
              }
              if (enlarged && x['longToken'] != true) need(x['sylBreaks'] == 0, '$at 음절 끊김 $x');
              if (x.containsKey('boxH')) need((x['boxH'] as double) >= 48, '$at 행동 높이 $x');
            }
            if (enlarged && titleLayout == 'beside') {
              need((xs[0]['wDraw'] as double) <= besideW + 0.5, '제목 가로인데 아이콘 옆 폭보다 넓다 ${xs[0]}');
            }
            if (enlarged && btnLayout == 'row') {
              for (final x in xs.skip(2)) {
                if (x['joined'] != true) need((x['wDraw'] as double) <= per - 16 + 0.5, '행동 가로인데 한 칸보다 넓다 $x');
              }
            }
          }

          final shot = enlarged && (anyFlip || _fixedShots.contains(it.id)) || (!enlarged && _fixedShots.contains(it.id));
          if (shot) {
            nPng++;
            await vqCapture(t, key, 'D284-$phase-${c.id}_${it.id}', conditions: {
              'phase': phase, 'item': it.id, 'src': it.src, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s,
            });
          }
          rows.add({'phase': phase, 'cond': c.id, 'id': it.id, 'm': it.m, 'src': it.src, 'titleLayout': titleLayout,
            'btnLayout': btnLayout, 'rowFlip': rowFlip, 'anyFlip': anyFlip, 'shot': shot,
            'dlgW': r1(dlgW), 'hdrW': r1(hdrW), 'besideW': r1(besideW), 'bodyW': r1(bodyW), 'actW': r1(actW), 'per': r1(per), 'texts': xs});
          _out('D284 ${jsonEncode(rows.last)}');
          // 닫기
          Navigator.of(ctxIn).pop();
          await frames(8);
          safe('닫힘');
          need(find.byType(Dialog).evaluate().isEmpty, '확인창이 닫히지 않았다');
        }
      }
      if (after) {
        need(rows.length == _items.length * 3, '열린 수 ${rows.length}');
        need(overflow.isEmpty, 'overflow $overflow');
      }
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D284-END ${jsonEncode({'pump': nPump, 'png': nPng, 'open': nOpen, 'rows': rows.length, 'overflow': overflow})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 8)));
}
