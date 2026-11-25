// [CONSENT-R4c · r4b 판 74ff382c 대체] 후보 DocumentAccessConsent(v4 · invite-v2) — 문안·판본·'자세히' 계약.
// [CONSENT-R5] C-G3 기준 지문만 지금 A(styled_dialog c1df0602 · DU561 뒤)로 다시 묶음 — 이 트랙은 공용 카드를 바꾸지 않는다(기대 같음).
//   작성만 했다 — 이번 배정 실행 0. 통과 결과가 아니다. 판본 동결이 아니다(Codex 판정 요청).
//
//   LOCAL 위치(제안): A_copy/test/consent_r4b_copy_test.dart
//   입력: 후보 lib/widgets/dialogs/apply/document_access_consent.dart ·
//         test/fixtures/consent_r4/consent_legacy_registry.json(은퇴 판본 원문 · 불변 지문)
//   네트워크·Firebase 0(위젯 하나만 그린다). 성공 = 'All tests passed!' · rc 0.
//
//   r4 판 consent_r4_copy_test.dart(7fb12e23)를 대체한다. 바뀐 기대(대응표 = r4b_test_change_map.tsv):
//     · 문단 1 = 6면 공통 행동 문장(r4 감사 §4 — 중복 '동의하면 … 동의합니다' · S7 불일치 해소)
//     · 기간 줄 = 근무 중 + 마지막 지급 30일 + 예외(L30)의 존재 · 상세에 A1–A4/T30/T_ONLY 문장
//     · 전문 지문은 **밖에서 고정한 값**과 같아야 한다(tools/copy_stats_r4b.py 가 원문을 풀어 계산)
//     · 은퇴 판본 registry 도 밖에서 고정한 지문과 같아야 한다(자기 일치만 보지 않는다)
//
//   고정하는 것
//     C-A  판본 토큰 = 서버 후보 상수 · 검토 목적 집합
//     C-B  카드 2문단 · 일반/초대 차이는 검토 기간 한 줄뿐
//     C-C  대표 결정: '관리자'만 · 거부 줄 0 · 기간 원칙과 예외 · 동일 고용관계 갱신
//     C-D  상세 = 같은 판본 · A1–A4·일반 미결·선지급 문장 · 전문 = 카드 + 상세 · 외부 고정 지문
//     C-E  여닫기 = 화면 상태만 · 닫힘 기본 · 48dp
//     C-G  색 방향 D-CB-CONSENT · 공용 카드는 승인된 현행 후보 전체 지문으로 고정(DU629c .notice 갈래 · F629c 경고 카드 아이콘 한정 교정 — C-G3)
//     C-F  은퇴 판본 registry — 외부 고정 지문 · 새 토큰이 옛 문장을 가리키지 않음
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/widgets/dialogs/apply/document_access_consent.dart';

import 'support/visible_text.dart';

const _v4 = '2026-11-18-v4';
const _inv2 = '2026-11-18-invite-v2';
const _registry = 'test/fixtures/consent_r4/consent_legacy_registry.json';
/// 공용 카드 파일(lib/widgets/dialogs/styled_dialog.dart) 전체 바이트 지문 — 승인된 현행 후보와 같은지 본다(전역 색 치환 0 · 전체파일 SHA 비교).
///   [DU629c · 판정235 D-c2] 옛 설명('이 후보가 공용 위젯을 바꾸지 않았음')은 동의 r4d 후보 당시 범위였다 — DU629c 는 공용 InfoCard 에 .notice 갈래를 더한다.
/// [DU629b · 판정207 §6 H1] 제목 · 취소 색 토큰(코드 3 줄 · 주석 3 줄)만 바꾼 styled_dialog 후보의 전체 지문 — StyledDialogInfoCard 본문 · 색 변경 0.
/// [DU629c · 판정216 D1 (a) · D7] H1 후보 위에 StyledDialogInfoCard 중립 팩토리 `.notice`(새 갈래 `_neutral`)만 더한 후보의 전체 지문 —
///   의미색 팩토리 5 · 생성자 기본값 · 공용 `.info` 정의는 그대로(공용 위젯 전역 색 치환 0).
/// [F629c-WARN-ICON · 판정251 Q4] 현재 A(DU629c 수용 db060a85) 위에 경고 카드 아이콘 색만 warningDark 로 잇는(_iconColor) 경고 아이콘 한정 교정 후보의 전체 지문 — 다른 의미색 아이콘 · 면 · 선 · 글 그대로.
const _styledDialogSha = '340c35afd78550c2f0ad6420e2ba78d24a1c2de0aa6fe72d41e5f810fd97ce05';
/// [외부 고정] 후보 전문 지문 — tools/copy_stats_r4b.py 가 후보 Dart 원문을 풀어 계산한 값
///   (manifests/copy_stats_r4b.json · copy_fulltext_<판본>.txt). 문장이 바뀌면 이 값도 바뀌어야 한다.
const _fullSha = {
  _v4: '2d5d45c62d611b88cd9f561eb9e8fa46cdaa990056ebdbaf95abb2d950d900a8',
  _inv2: '94d62b04bcef59665a305cc4f3b78d3c3d6e7ea1912c594057f471f544d3567c',
};
/// [외부 고정] 은퇴 판본 원문 지문(r4 registry 482ca071 작성 시 A 원문 0f70a158 에서 잘라 계산).
const _retiredSha = {
  '2026-09-18-v3': '9e66709f31a16a408944ba5ad4d3b5f7e477fb61ffff9e1a1c386dfdd2b03658',
  '2026-10-15-invite-v1': 'cf7a71724127fdfb55c968948ca815f7a497637468ced8b20f61a9e4a0e906aa',
};
const _action = '아래 지원·동의·수락 버튼을 누르면 신분증·급여계좌·통장사본이 관리자에게 보여지는 데 동의합니다.';

String _src(String p) => File(p).readAsStringSync();

void main() {
  group('C-A 판본', () {
    test('C-A1 클라이언트 토큰 = 서버 후보 상수', () {
      expect(DocumentAccessConsent.version, _v4);
      expect(DocumentAccessConsent.inviteVersion, _inv2);
      final cf = _src('functions/src/index.ts');
      expect(cf.contains('const DOCUMENT_ACCESS_CONSENT_V4 = "$_v4";'), isTrue);
      expect(cf.contains('const DOCUMENT_ACCESS_CONSENT_INVITE_V2 = "$_inv2";'), isTrue);
    });
    test('C-A2 검토 목적 집합 = 새 세대 두 판본', () {
      expect(DocumentAccessConsent.reviewPurposeVersions, {_v4, _inv2});
    });
  });

  group('C-B 카드 2문단', () {
    test('C-B1 두 문단 · join 등식', () {
      for (final p in [DocumentAccessConsent.partsFor('X'), DocumentAccessConsent.invitePartsFor('X')]) {
        expect(p.length, 2);
      }
      expect(DocumentAccessConsent.partsFor('X').join('\n'), DocumentAccessConsent.copyFor('X'));
      expect(DocumentAccessConsent.invitePartsFor('X').join('\n'), DocumentAccessConsent.inviteCopyFor('X'));
    });
    test('C-B2 문단 1 = 공통 행동 문장(한 번만 "동의") · 문단 2 = 목적→기간 두 줄', () {
      final g = DocumentAccessConsent.partsFor('X');
      expect(g[0], _action);
      expect('동의합니다'.allMatches(g[0]).length, 1, reason: "r4 '동의하면 … 동의합니다' 중복 해소");
      final lines = g[1].split('\n');
      expect(lines.length, 2);
      expect(lines[0], '· 채용 검토: 지원이 끝날 때까지');
      expect(lines[1].startsWith('· 근무 확정 후(소득신고·급여처리): '), isTrue);
    });
    test('C-B3 일반/초대 차이는 검토 기간 한 줄뿐(문단 1·확정 후 줄은 같다)', () {
      final g = DocumentAccessConsent.partsFor('X');
      final i = DocumentAccessConsent.invitePartsFor('X');
      expect(i[0], g[0]);
      expect(i[1].split('\n')[0], '· 채용 검토: 수락 기한까지');
      expect(i[1].split('\n')[1], g[1].split('\n')[1]);
      expect(i.join('\n').contains('지원하기'), isFalse);
    });
  });

  group('C-C 대표 결정 반영', () {
    final all = [
      ...DocumentAccessConsent.partsFor('강남 물류센터'),
      ...DocumentAccessConsent.detailsFor('강남 물류센터'),
      ...DocumentAccessConsent.invitePartsFor('강남 물류센터'),
      ...DocumentAccessConsent.inviteDetailsFor('강남 물류센터'),
    ].join('\n');
    test('C-C1 받는 쪽은 "관리자"뿐 — 사업장 이름·"지원한 사업장의"·"권한 있는" 0', () {
      expect(all.contains('강남 물류센터'), isFalse);
      expect(all.contains('['), isFalse);
      expect(all.contains('사업장의'), isFalse);
      expect(DocumentAccessConsent.copyFor('X').contains('관리자에게'), isTrue);
    });
    test('C-C2 거부 안내 줄 0(대표 결정 ① · 법무 HOLD)', () {
      expect(all.contains('거부'), isFalse);
    });
    test('C-C3 기간 줄 — 신분증 7일 · 계좌 = 근무 중 + 마지막 지급 30일 + 예외(L30) 존재', () {
      final line = DocumentAccessConsent.partsFor('X')[1];
      expect(line.contains('신분증은 마지막 근무일부터 7일 동안'), isTrue);
      expect(line.contains('급여계좌·통장사본은 근무하는 동안과 마지막 급여 지급부터 30일 동안'), isTrue);
      expect(line.contains('(지급 이력이 없는 경우 등은 마지막 근무일부터 30일 동안)'), isTrue);
      expect(all.contains('급여처리 관계가 유효한 동안'), isFalse, reason: '옛 계좌 기간 문구');
    });
    test('C-C4 갱신 승계 = 동일 고용관계 한정(‘같은 사업장’ 0)', () {
      final d = DocumentAccessConsent.detailsFor('X').join('\n');
      expect(d.contains('같은 고용관계에서 근로계약이 갱신된 근무'), isTrue);
      expect(d.contains('같은 사업장'), isFalse);
    });
  });

  group('C-D 상세(자세히) — 같은 판본 · 기간 문장 대조', () {
    for (final invite in [false, true]) {
      test('C-D1 ${invite ? '초대' : '일반'} 상세 — T 정의 · 일반 미결 · A2/A3/A4 L30 · A1 결손 예외 · 선지급 · 끝 · 현재 서류', () {
        final d = (invite ? DocumentAccessConsent.inviteDetailsFor('X') : DocumentAccessConsent.detailsFor('X'))
            .join('\n');
        for (final s in [
          '은행 입금 시각이 아닙니다',                                         // T = 서버 이체 완료 처리 시각
          '지급할 급여가 남아 있는 동안에는 30일을 아직 세지 않으며(바로 아래 경우는 예외)', // 일반 미결(T 규칙)
          '이체 완료가 취소되면 다시 지급한 시각부터 셉니다',                    // 취소 → 새 지급 문맥
          '다음 경우에는 마지막 근무일(한국 시간) 0시부터 30일 동안 볼 수 있습니다.', // L30 · 경계 DRAFT 식
          '지급할 급여 없이 근무가 끝난 경우',                                   // A2
          '지급 기록 가운데 확인이 필요한 것이 있는 경우(지급할 급여가 남아 있어도 같습니다)', // A3
          '급여 지급을 마친 뒤 지금 등록된 계좌서류에 대한 다시 등록 요청만 남았거나', // A4(현재 판본 결속)
          '그런 요청이 있는지 확인이 필요한 경우입니다',                           // PP-R4B-UNKNOWN(종결 뒤 보완 불명 = A3)
          '종료일이 기록되지 않은 근무는 근무 시작 뒤 서명한 근로계약 기간 동안',     // A1 결손 예외
          '근무가 끝나기 전에 급여를 모두 받았다면',                              // 선지급 T_ONLY
          '급여계좌·통장사본은 위 기간이 지나면 이 근무관계를 근거로 새로 열람할 수 없습니다',
          '이체를 마친 급여 지급 기록(지급한 계좌 포함)은 급여 기록으로 남습니다',
          '지금 등록해 둔 신분증·급여계좌·통장사본',
        ]) {
          expect(d.contains(s), isTrue, reason: s);
        }
        // 옛 기대(교체됨): 'A3·A4 미정' 시절의 넓은 문장 · 종료일 없는 근무 일반 허용 문장.
        expect(d.contains('종료일 없이 계속 근무 중인 경우 포함'), isFalse);
        expect(d.contains('근무하는 동안(종료일 없이'), isFalse);
        expect(d.contains('정산·정정 처리가 끝난 뒤부터'), isFalse);
        expect(d.contains('모집 기간'), isFalse);
      });
    }
    test('C-D2 초대 상세 — 수락 기한·거절·취소·만료', () {
      final d = DocumentAccessConsent.inviteDetailsFor('X').join('\n');
      expect(d.contains('수락 기한이 지나거나, 초대·제안을 거절하거나, 초대·제안이 취소·만료되거나'), isTrue);
      expect(d.contains('이 초대·제안을 수락해 확정된 근무'), isTrue);
    });
    test('C-D3 판본 전문 = 카드 + 상세', () {
      expect(DocumentAccessConsent.fullTextFor(_v4),
          [...DocumentAccessConsent.partsFor('X'), ...DocumentAccessConsent.detailsFor('X')].join('\n'));
      expect(DocumentAccessConsent.fullTextFor(_inv2),
          [...DocumentAccessConsent.invitePartsFor('X'), ...DocumentAccessConsent.inviteDetailsFor('X')].join('\n'));
    });
    test('C-D4 전문 지문 = 밖에서 고정한 값(manifests/copy_stats_r4b.json)', () {
      for (final v in [_v4, _inv2]) {
        final h = sha256.convert(utf8.encode(DocumentAccessConsent.fullTextFor(v))).toString();
        // ignore: avoid_print
        print('CONSENT-FULLTEXT $v sha256=$h chars=${DocumentAccessConsent.fullTextFor(v).length}');
        expect(h, _fullSha[v], reason: '$v 전문이 고정 지문과 다르다 — 문장·판본을 함께 다시 판정');
      }
    });
  });

  group('C-E 자세히 여닫기', () {
    for (final invite in [false, true]) {
      testWidgets('C-E1 ${invite ? '초대' : '일반'} — 기본 닫힘 · 열면 상세 · 닫으면 숨김 · Navigator 변화 0', (t) async {
        final nav = GlobalKey<NavigatorState>();
        await t.pumpWidget(MaterialApp(
          navigatorKey: nav,
          home: Scaffold(body: SingleChildScrollView(child: invite
              ? DocumentAccessConsent.inviteCard('X')
              : DocumentAccessConsent.card('X'))),
        ));
        final details = invite
            ? DocumentAccessConsent.inviteDetailsFor('X')
            : DocumentAccessConsent.detailsFor('X');
        expect(findVisibleTextContaining(details.first), findsNothing, reason: '기본은 닫힘');
        final toggle = find.byKey(const ValueKey('documentAccessConsentDetailsToggle'));
        expect(toggle, findsOneWidget);
        expect(t.getSize(toggle).height, greaterThanOrEqualTo(48 - 0.01), reason: '터치 영역');
        expect(t.getSize(toggle).width, greaterThanOrEqualTo(48 - 0.01), reason: '터치 영역');
        final canPopBefore = nav.currentState!.canPop();
        await t.tap(toggle);
        await t.pump();
        for (final d in details) {
          expect(findVisibleTextContaining(d), findsOneWidget, reason: d);
        }
        expect(find.text('자세히 닫기'), findsOneWidget);
        expect(nav.currentState!.canPop(), canPopBefore, reason: '라우트·제출 0 — 화면 상태만');
        await t.tap(toggle);
        await t.pump();
        expect(findVisibleTextContaining(details.first), findsNothing);
        expect(find.text('자세히'), findsOneWidget);
      });
    }
    test('C-E2 여닫기 콜백은 setState 하나 — 서버·동의 쓰기 호출 0(원문 고정)', () {
      final s = _src('lib/widgets/dialogs/apply/document_access_consent.dart');
      final i = s.indexOf("key: const ValueKey('documentAccessConsentDetailsToggle')");
      final body = s.substring(i, s.indexOf('child: Text(', i));
      expect(body.contains('onPressed: () => setState(() => _open = !_open),'), isTrue);
      for (final w in ['httpsCallable', 'FirebaseFunctions', 'Navigator', 'Firestore']) {
        expect(s.contains(w), isFalse, reason: w);
      }
    });
  });

  group('C-G 색 방향 — D-CB-CONSENT(후속121 §3 · 색 예산 C1·C2·C4)', () {
    for (final invite in [false, true]) {
      testWidgets('C-G1 ${invite ? '초대' : '일반'} — 중립 면·중립 본문·정보 아이콘(중립)·brand 자세히', (t) async {
        await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
            child: invite ? DocumentAccessConsent.inviteCard('X') : DocumentAccessConsent.card('X')))));
        final body = find.byKey(const ValueKey('documentAccessConsentBody'));
        final box = t.widget<Container>(find.descendant(of: body, matching: find.byType(Container)).first);
        final deco = box.decoration! as BoxDecoration;
        expect(deco.color, AppColors.background, reason: '중립 면(경고 alpha 면 0)');
        expect((deco.border! as Border).top.color, AppColors.borderLight, reason: '중립 선');
        final parts = invite ? DocumentAccessConsent.invitePartsFor('X') : DocumentAccessConsent.partsFor('X');
        for (final p in parts) {
          expect(t.widget<Text>(findVisibleText(p)).style?.color, AppColors.textPrimary, reason: '중립 본문');
        }
        final icon = t.widget<Icon>(find.descendant(of: body, matching: find.byType(Icon)));
        expect(icon.icon, Icons.info_outline);
        expect(icon.color, AppColors.textSecondary, reason: 'C4 기본 중립 아이콘');
        expect(t.widget<Text>(find.text('자세히')).style?.color, AppColors.brand, reason: 'C2 링크 = brand');
        await t.tap(find.byKey(const ValueKey('documentAccessConsentDetailsToggle')));
        await t.pump();
        final dbox = t.widget<Container>(find.descendant(
            of: find.byKey(const ValueKey('documentAccessConsentDetails')), matching: find.byType(Container)).first);
        expect((dbox.decoration! as BoxDecoration).color, AppColors.surface, reason: '상세 = 흰 중립 면');
      });
    }
    test('C-G2 이 파일에 경고 토큰·경고 아이콘·공용 경고 카드 호출 0', () {
      final code = _src('lib/widgets/dialogs/apply/document_access_consent.dart')
          .split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
      for (final w in ['AppColors.warning', 'warningSegments', 'Icons.warning', 'StyledDialogInfoCard',
        'AppColors.info,', 'AppColors.infoBg']) {
        expect(code.contains(w), isFalse, reason: w);
      }
    });
    test('C-G3 공용 StyledDialogInfoCard는 승인된 현행 후보 지문과 같다(경고 카드 아이콘 한정 교정 · 그 밖 색 치환 0)', () {
      final h = sha256.convert(File('lib/widgets/dialogs/styled_dialog.dart').readAsBytesSync()).toString();
      expect(h, _styledDialogSha);
    });
  });

  group('C-F 은퇴 판본 registry', () {
    test('C-F1 registry 원문 지문 = 밖에서 고정한 값(자기 일치만 보지 않는다)', () {
      final reg = jsonDecode(File(_registry).readAsStringSync()) as Map<String, dynamic>;
      final entries = (reg['entries'] as List).cast<Map<String, dynamic>>();
      expect(entries.map((e) => e['version']).toSet(), _retiredSha.keys.toSet());
      for (final e in entries) {
        final v = e['version'] as String;
        final text = e['text'] as String;
        final h = sha256.convert(utf8.encode(text)).toString();
        expect(h, e['textSha256'], reason: '$v 기록 지문');
        expect(h, _retiredSha[v], reason: '$v 외부 고정 지문');
      }
    });
    test('C-F2 새 토큰은 옛 문장을 가리키지 않는다 · 옛 토큰은 현재 상수가 아니다', () {
      final reg = jsonDecode(File(_registry).readAsStringSync()) as Map<String, dynamic>;
      for (final e in (reg['entries'] as List).cast<Map<String, dynamic>>()) {
        final v = e['version'] as String;
        expect(v == DocumentAccessConsent.version || v == DocumentAccessConsent.inviteVersion, isFalse, reason: v);
        final old = (e['text'] as String).replaceAll(r'[$businessName]', '[X]');
        expect(old == DocumentAccessConsent.copyFor('X') || old == DocumentAccessConsent.inviteCopyFor('X'), isFalse);
      }
    });
  });
}
