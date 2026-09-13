import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// POSTING-V2-01C.2 CLIENT DELETE LIFECYCLE ALIGNMENT
//
// 서버는 이미 relation-zero only로 활성화됐다(01C.1 + DEV deploy).
// 클라이언트는 아직 옛 UX였다:
//   · 모든 status에서 삭제 / 일괄삭제 메뉴 노출
//   · '확정 근무자 N명 포함, 총 M명의 지원서가 자동 취소됩니다' 문구
//   · 서버 failed-precondition 메시지를 generic 토스트로 덮음
//
// 새 계약:
//   CLIENT UX  = DRAFT-only delete   (서버보다 의도적으로 더 좁다)
//   SERVER     = relation-zero only  (구버전 클라이언트·직접 호출의 최종 권위)
// ═══════════════════════════════════════════════════════════════

const _cardPath = 'lib/widgets/admin/cards/admin_to_group_card.dart';
const _dialogsPath = 'lib/screens/business_admin/dialogs/to_list_dialogs.dart';
const _toFsPath = 'lib/services/firestore/to_firestore.dart';
const _fnPath = 'functions/src/index.ts';
const _inviteDialogPath =
    'lib/screens/business_admin/dialogs/invite_worker_dialog.dart';
const _ctrlPath = 'lib/controllers/workforce_controller.dart';

String _src(String p) => File(p).readAsStringSync();

/// `//` 주석 줄 제거 — 주석 안의 문자열이 코드로 오탐되는 것을 막는다.
String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

/// 공백 1칸 평탄화.
String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _bodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  if (start == -1) throw StateError('$signature 를 찾지 못함');
  var paren = 0;
  var afterParams = start;
  for (var i = source.indexOf('(', start); i < source.length; i++) {
    if (source[i] == '(') paren++;
    if (source[i] == ')') {
      paren--;
      if (paren == 0) {
        afterParams = i;
        break;
      }
    }
  }
  final open = source.indexOf('{', afterParams);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  throw StateError('$signature 본문의 끝을 찾지 못함');
}

/// `case 'x':` 부터 다음 `break;` 까지.
String _caseOf(String source, String label) {
  final start = source.indexOf("case '$label':");
  if (start == -1) throw StateError("case '$label' 을 찾지 못함");
  final end = source.indexOf('break;', start);
  if (end == -1) throw StateError("case '$label' 의 break를 찾지 못함");
  return source.substring(start, end);
}

// ── UI 노출 계약 재현 ─────────────────────────────────────────
//
// admin_to_group_card._showSingleTOMenuSheet 의 판정을 옮긴다.
// status + permission 만으로 결정된다 — 관계 질의가 개입하지 않는다.

const _draft = 'DRAFT';
const _allStatuses = [
  'DRAFT',
  'SCHEDULED',
  'ACTIVE',
  'FULL',
  'CLOSED',
  'EXPIRED',
];

bool deleteMenuVisible({
  required String status,
  required bool isBusinessAdmin,
  required bool isSuperAdmin,
  required bool canManageTo,
}) {
  final canDelete = isBusinessAdmin || isSuperAdmin || canManageTo;
  final isDraft = status == _draft;
  return canDelete && isDraft;
}

String deleteMenuLabel({required bool isContract}) =>
    isContract ? '미공개 공고 삭제' : '날짜 일괄삭제';

/// 삭제 시도 결과 — 서버가 최종 판정한다.
class _DeleteOutcome {
  final bool listChanged;
  final String toast;
  const _DeleteOutcome(this.listChanged, this.toast);
}

/// to_list_dialogs.showDeleteTODialog + to_firestore.deleteTO 의 결과 처리 재현.
_DeleteOutcome attemptDelete({
  required bool serverAllows,
  String serverMessage = '',
}) {
  if (serverAllows) {
    return const _DeleteOutcome(true, '공고가 삭제되었습니다.');
  }
  // 실패: 서버 메시지를 그대로 노출하고 목록은 건드리지 않는다
  final msg = serverMessage.isNotEmpty ? serverMessage : '공고 삭제에 실패했습니다.';
  return _DeleteOutcome(false, msg);
}

void main() {
  final card = _src(_cardPath);
  final cardCode = _codeOf(card);
  final menuBody = _codeOf(_bodyOf(card, 'void _showSingleTOMenuSheet('));
  final dialogs = _src(_dialogsPath);

  // ═════════════════════════════════════════════════════════════
  // CLIENT-DELETE-01 — status별 노출
  // ═════════════════════════════════════════════════════════════
  group('CLIENT-DELETE-01 status별 삭제 메뉴 노출', () {
    test('DRAFT만 보이고 나머지는 숨는다', () {
      for (final s in _allStatuses) {
        final visible = deleteMenuVisible(
          status: s,
          isBusinessAdmin: true,
          isSuperAdmin: false,
          canManageTo: true,
        );
        expect(visible, s == _draft, reason: '$s 의 노출 여부가 잘못됐다');
      }
    });

    test('권한이 있어도 공개된 공고에서는 안 보인다', () {
      for (final s in _allStatuses.where((s) => s != _draft)) {
        expect(
          deleteMenuVisible(
            status: s,
            isBusinessAdmin: true,
            isSuperAdmin: true,
            canManageTo: true,
          ),
          isFalse,
          reason: '$s 에서 삭제가 노출된다',
        );
      }
    });

    test('DRAFT여도 권한이 없으면 안 보인다', () {
      expect(
        deleteMenuVisible(
          status: _draft,
          isBusinessAdmin: false,
          isSuperAdmin: false,
          canManageTo: false,
        ),
        isFalse,
      );
    });

    test('canManageTo만 가진 SubAdmin은 DRAFT에서만 보인다', () {
      expect(
        deleteMenuVisible(
          status: _draft,
          isBusinessAdmin: false,
          isSuperAdmin: false,
          canManageTo: true,
        ),
        isTrue,
      );
      expect(
        deleteMenuVisible(
          status: 'ACTIVE',
          isBusinessAdmin: false,
          isSuperAdmin: false,
          canManageTo: true,
        ),
        isFalse,
      );
    });

    test('메뉴 gate가 canDelete && isDraft 다', () {
      expect(menuBody.contains('if (canDelete && isDraft)'), isTrue,
          reason: '삭제 메뉴가 여전히 canDelete만으로 노출된다');
      expect(
        _flat(menuBody).contains(
            'final isDraft = widget.groupItem.masterTO.status == TOStatus.draft;'),
        isTrue,
        reason: 'DRAFT 판정이 masterTO.status 기반이 아니다',
      );
      // 권한 계약 자체는 그대로
      expect(
        _flat(menuBody).contains('final canDelete = user?.isBusinessAdmin == true '
            '|| user?.isSuperAdmin == true || up.can((p) => p.canManageTo);'),
        isTrue,
        reason: 'permission 계약이 바뀌었다',
      );
    });

    test('라벨이 lifecycle 의미를 드러낸다', () {
      expect(
        menuBody.contains("label: isContract ? '미공개 공고 삭제' : '날짜 일괄삭제',"),
        isTrue,
      );
      expect(deleteMenuLabel(isContract: true), '미공개 공고 삭제');
      expect(deleteMenuLabel(isContract: false), '날짜 일괄삭제');
      // 옛 라벨 제거
      expect(menuBody.contains("? '삭제' : '일괄삭제'"), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // CLIENT-DELETE-02 — 노출 계산에 관계 질의 없음
  // ═════════════════════════════════════════════════════════════
  group('CLIENT-DELETE-02 relation 질의 없음', () {
    test('메뉴 시트 빌드가 동기다 (await 없음)', () {
      expect(menuBody.contains('await '), isFalse,
          reason: '메뉴 노출 계산이 비동기 조회를 한다');
      expect(menuBody.contains('async'), isFalse);
    });

    test('메뉴 시트가 관계 데이터를 읽지 않는다', () {
      for (final forbidden in [
        'applications',
        'employment_contracts',
        'attendance',
        'checkTOBeforeDelete',
        'FirebaseFirestore',
        'httpsCallable',
        'getApplicationsByTOId',
      ]) {
        expect(menuBody.contains(forbidden), isFalse,
            reason: '메뉴 노출 계산이 "$forbidden" 로 관계를 판정한다');
      }
    });

    test('클라이언트가 relation-zero를 재구현하지 않는다', () {
      // 서버 판정을 흉내 내는 조합 판정이 없어야 한다
      for (final forbidden in [
        'relationZero',
        'hasRelations',
        'contractCount ==',
        'attendanceCount ==',
      ]) {
        expect(cardCode.contains(forbidden), isFalse,
            reason: '"$forbidden" 로 서버 정책을 복제한다');
      }
    });

    test('삭제 다이얼로그가 사전 관계 조회를 하지 않는다', () {
      final body = _codeOf(_bodyOf(dialogs, 'Future<void> showDeleteTODialog('));
      expect(body.contains('checkTOBeforeDelete'), isFalse,
          reason: '활성 지원서만 보는 precheck를 canonical처럼 쓴다');
      expect(body.contains('confirmedCount'), isFalse);
      expect(body.contains('totalCount'), isFalse);
      expect(body.contains('hasApplicants'), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // CLIENT-DELETE-03 — 서버 차단을 성공으로 처리하지 않음
  // ═════════════════════════════════════════════════════════════
  group('CLIENT-DELETE-03 서버 거절 처리', () {
    test('차단되면 목록이 바뀌지 않는다', () {
      final r = attemptDelete(
        serverAllows: false,
        serverMessage: '이 공고에는 지원·초대·근무 기록이 있어 삭제할 수 없습니다. '
            '모집을 중단하려면 공고 종료를 이용해주세요.',
      );
      expect(r.listChanged, isFalse);
      expect(r.toast.contains('공고 종료를 이용해주세요'), isTrue);
    });

    test('성공했을 때만 목록이 갱신된다', () {
      expect(attemptDelete(serverAllows: true).listChanged, isTrue);
    });

    test('onChanged가 success 분기 안에만 있다 (optimistic delete 없음)', () {
      final body =
          _flat(_codeOf(_bodyOf(dialogs, 'Future<void> showDeleteTODialog(')));
      expect(
        body.contains('final success = await firestoreService.deleteTO(to.id); '
            'if (success) { if (!context.mounted) return; onChanged(); }'),
        isTrue,
        reason: '실패해도 목록이 갱신되거나 낙관적으로 제거된다',
      );
      // onChanged 호출은 success 블록 안의 1회뿐이다
      expect('onChanged()'.allMatches(body).length, 1,
          reason: 'success 블록 밖에서도 onChanged가 호출된다');
    });

    test('flex 날짜 삭제도 실패 시 onChanged를 부르지 않는다', () {
      final body = _flat(_codeOf(_caseOf(card, 'batchDelete')));
      final catchIdx = body.indexOf('} catch (e) {');
      expect(catchIdx, isNot(-1));
      expect(body.substring(catchIdx).contains('widget.onChanged()'), isFalse,
          reason: '삭제 실패 후에도 목록을 갱신한다');
    });
  });

  // ═════════════════════════════════════════════════════════════
  // CLIENT-DELETE-04 — confirmation copy
  // ═════════════════════════════════════════════════════════════
  group('CLIENT-DELETE-04 confirmation copy', () {
    test('TO 삭제 문구가 서버 계약과 같은 말을 한다', () {
      final body = _codeOf(_bodyOf(dialogs, 'Future<void> showDeleteTODialog('));
      expect(body.contains("title: '미공개 공고 삭제',"), isTrue);
      expect(body.contains("'삭제한 공고는 복구할 수 없습니다.\\n'"), isTrue);
      expect(body.contains("'지원·초대·근무 기록이 있는 공고는 삭제할 수 없습니다.',"), isTrue);
    });

    test('날짜 삭제 문구도 동일 계약을 말한다', () {
      final body = _flat(_codeOf(_caseOf(card, 'batchDelete')));
      expect(body.contains("title: '날짜 삭제',"), isTrue);
      expect(
        body.contains("'삭제한 날짜는 복구할 수 없습니다.\\n' "
            "'지원·초대·근무 기록이 있는 날짜는 삭제할 수 없습니다.'"),
        isTrue,
      );
    });

    test('전부 선택 시 공고까지 삭제된다는 사실을 알린다', () {
      final body = _flat(_codeOf(_caseOf(card, 'batchDelete')));
      expect(
        body.contains("\${deletesAll ? '\\n\\n모든 날짜를 삭제하면 미공개 공고도 함께 삭제됩니다.' : ''}"),
        isTrue,
      );
    });

    test('옛 자동취소 semantics 문구가 삭제 확인에서 사라졌다', () {
      final del = _codeOf(_bodyOf(dialogs, 'Future<void> showDeleteTODialog('));
      final batch = _codeOf(_caseOf(card, 'batchDelete'));
      for (final old in [
        '자동 취소',
        '확정 근무자',
        '무효화',
        '지원서',
      ]) {
        expect(del.contains(old), isFalse, reason: 'TO 삭제 문구에 "$old" 잔존');
        expect(batch.contains(old), isFalse, reason: '날짜 삭제 문구에 "$old" 잔존');
      }
    });

    test('다른 기능의 정상 취소 문구는 건드리지 않았다', () {
      // 일괄 종료는 여전히 PENDING 거절을 명시해야 한다 — 실제 동작이 그렇다
      final close = _codeOf(_caseOf(card, 'batchClose'));
      expect(close.contains('대기 중인 지원자는 거절 처리됩니다'), isTrue);
      expect(close.contains('확정된 근무 기록은 유지됩니다'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 서버 에러 표면
  // ═════════════════════════════════════════════════════════════
  group('서버 에러 표면', () {
    test('deleteTO가 서버 메시지를 generic 토스트로 덮지 않는다', () {
      final body = _flat(_codeOf(_bodyOf(_src(_toFsPath), 'Future<bool> deleteTO(')));
      expect(
        body.contains('final msg = (e is FirebaseFunctionsException && '
            '(e.message?.isNotEmpty ?? false)) ? e.message! : '
            "'공고 삭제에 실패했습니다.'; ToastHelper.showError(msg);"),
        isTrue,
        reason: '서버 안내가 사용자에게 전달되지 않는다',
      );
    });

    test('다이얼로그가 중복 토스트로 서버 메시지를 덮지 않는다', () {
      final body = _codeOf(_bodyOf(dialogs, 'Future<void> showDeleteTODialog('));
      expect(body.contains("ToastHelper.showError('공고 삭제에 실패했습니다.')"), isFalse,
          reason: 'deleteTO의 서버 메시지 위에 generic 토스트가 덮인다');
    });

    test('날짜 삭제도 서버 메시지를 그대로 쓴다 (기존 유지)', () {
      final body = _flat(_codeOf(_caseOf(card, 'batchDelete')));
      expect(
        body.contains("final msg = _cfErrorMessage(e, fallback: '삭제 처리에 실패했습니다');"),
        isTrue,
      );
    });

    test('서버가 실제로 다음 행동을 안내한다 (01C.1 계약 확인)', () {
      final fn = _codeOf(_src(_fnPath));
      expect(fn.contains('"모집을 중단하려면 공고 종료를 이용해주세요."'), isTrue);
      expect(fn.contains('"해당 날짜의 모집을 중단하려면 날짜 종료를 이용해주세요."'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // CLIENT-DELETE-05 / 06 — 나머지 lifecycle 무변경
  // ═════════════════════════════════════════════════════════════
  group('CLIENT-DELETE-05·06 close / reopen / repost 무변경', () {
    test('ACTIVE: 종료 메뉴 조건 그대로', () {
      expect(menuBody.contains("label: '공고 종료',"), isTrue);
      expect(menuBody.contains("label: '일괄 종료',"), isTrue);
      expect(_flat(menuBody).contains('if (!isClosed) [ AppMenuSheetItem( '
          'icon: Icons.lock_outline, label: \'공고 종료\','), isTrue);
    });

    test('재오픈 조건 그대로', () {
      expect(_flat(menuBody).contains("if (isClosed && isManualClosed) ["), isTrue);
      expect(menuBody.contains("label: '공고 재오픈',"), isTrue);
      expect(
        _flat(menuBody).contains('if (isClosed && !isManualClosed && !isFull && '
            'widget.groupItem.hasReopenableManualSlots) ['),
        isTrue,
      );
      expect(menuBody.contains("label: '종료한 날짜 재오픈',"), isTrue);
    });

    test('다시 모집 whitelist 그대로', () {
      expect(
        _flat(menuBody).contains('final canRepost = canManageTo && isClosed && '
            "(isManualClosed || isFull || repostReasonCode == 'POSTING_EXPIRED' || "
            "repostReasonCode == 'TIME_EXPIRED' || "
            "repostReasonCode == 'ALL_SLOTS_EXPIRED' || "
            "repostReasonCode == 'ALL_WORKDETAILS_CLOSED' || "
            "repostReasonCode == 'ALL_CHILDREN_CLOSED');"),
        isTrue,
      );
    });

    test('수정 메뉴 조건 그대로', () {
      expect(_flat(menuBody).contains('if (canManageTo && !isClosed) ['), isTrue);
      expect(menuBody.contains("label: isContract ? '수정' : '일괄수정',"), isTrue);
    });

    test('close / reopen callable 경로 무변경', () {
      expect(cardCode.contains('batchCloseSlots('), isTrue);
      expect(cardCode.contains('batchReopenSlots('), isTrue);
      expect(_codeOf(dialogs).contains('showCloseTODialog('), isTrue);
      expect(_codeOf(dialogs).contains('showReopenTODialog('), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // live entry point 전수
  // ═════════════════════════════════════════════════════════════
  group('live delete entry point', () {
    test('TOGroupCard 생성 지점이 하나뿐이고 list mode다', () {
      final all = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.readAsStringSync())
          .join('\n');
      expect(RegExp(r'\bTOGroupCard\(').allMatches(_codeOf(all)).length, 2,
          reason: '선언 1 + 생성 1 이 아니다 — 새 진입점이 생겼다');
      expect(_codeOf(all).contains('displayMode:'), isFalse,
          reason: 'calendar mode 생성자가 생겼다 — dead 경로가 살아난다');
    });

    test('reachable 삭제 액션은 DRAFT gate 안의 2개뿐이다', () {
      // list mode 메뉴에서 삭제를 트리거하는 지점
      expect(
        _flat(menuBody).contains("onTap: () => _handleSingleTOMenuAction("
            "context, isContract ? 'delete' : 'batchDelete'),"),
        isTrue,
      );
      expect(
        "_handleSingleTOMenuAction(context, isContract ? 'delete' : 'batchDelete')"
            .allMatches(_flat(menuBody))
            .length,
        1,
        reason: '삭제 트리거가 여러 개다',
      );
    });

    test('새 delete entry point를 만들지 않았다', () {
      // 카드 밖 어디에도 TO/슬롯 삭제 호출이 없어야 한다
      final all = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') &&
              !f.path.endsWith('to_firestore.dart') &&
              !f.path.endsWith('firestore_service.dart'))
          .map((f) => _codeOf(f.readAsStringSync()))
          .join('\n');
      expect('batchDeleteSlots('.allMatches(all).length, 1,
          reason: '슬롯 삭제 호출 지점이 늘었다');
      expect('.deleteTO('.allMatches(all).length, 2,
          reason: 'TO 삭제 호출 지점이 늘었다 (카드 chain 1 + 다이얼로그 1)');
    });

    test('dead delete 코드는 그대로 둔다 (backlog)', () {
      // [BACKLOG-POSTING-DEAD-DELETE-UI] / [BACKLOG-POSTING-DEAD-TOITEMCARD]
      expect(cardCode.contains('void _showCalendarMenuSheet('), isTrue,
          reason: 'dead cleanup으로 diff를 확대했다');
      expect(
        File('lib/widgets/admin/cards/admin_to_item_card.dart').existsSync(),
        isTrue,
      );
    });
  });

  // ═════════════════════════════════════════════════════════════
  // server / client capability 차이는 의도된 상태
  // ═════════════════════════════════════════════════════════════
  group('server vs client capability', () {
    test('서버는 relation-zero면 status 무관 허용 (더 넓다)', () {
      final fn = _codeOf(_src(_fnPath));
      final guard = _bodyOf(fn, 'async function assertNoPostingRelations(');
      for (final s in _allStatuses) {
        expect(guard.contains('"$s"'), isFalse,
            reason: '서버 guard가 $s 를 특별 취급한다 — 클라이언트와 정책이 얽힌다');
      }
    });

    test('클라이언트는 DRAFT에서만 노출 (더 좁다) — 의도된 비대칭', () {
      // relation 0인 ACTIVE도 서버는 허용하지만 UI는 제공하지 않는다
      expect(
        deleteMenuVisible(
          status: 'ACTIVE',
          isBusinessAdmin: true,
          isSuperAdmin: false,
          canManageTo: true,
        ),
        isFalse,
      );
      expect(menuBody.contains('if (canDelete && isDraft)'), isTrue);
    });

    test('DRAFT도 클라이언트가 relation 0이라 단정하지 않는다', () {
      // callableInviteWorker가 DRAFT를 막지 않으므로 초대가 붙어 있을 수 있다
      final fn = _codeOf(_src(_fnPath));
      final inv = _bodyOf(fn, 'export const callableInviteWorker = onCall(');
      expect(inv.contains('"DRAFT"'), isFalse,
          reason: 'DRAFT invite 정책을 이번에 수정했다 — 범위 밖');
      // 클라이언트는 사전 판정 없이 서버에 맡긴다
      final body = _codeOf(_bodyOf(dialogs, 'Future<void> showDeleteTODialog('));
      expect(body.contains('checkTOBeforeDelete'), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // scope guard
  // ═════════════════════════════════════════════════════════════
  group('scope guard', () {
    test('FUNCTIONS 무변경 — 01C.1 계약 그대로', () {
      final fn = _codeOf(_src(_fnPath));
      expect(fn.contains('async function assertNoPostingRelations('), isTrue);
      expect(fn.contains('async function assertNoSlotRelations('), isTrue);
      expect(
        fn.contains('const toRelation = await assertNoPostingRelations('),
        isTrue,
      );
      expect(fn.contains('const slotRelation = await assertNoSlotRelations('),
          isTrue);
    });

    test('근무 취소 / 공개 취소 기능을 추가하지 않았다', () {
      for (final forbidden in [
        '근무 취소',
        '모집 취소',
        '예약 공개 취소',
        '공개 취소',
      ]) {
        expect(cardCode.contains(forbidden), isFalse,
            reason: '"$forbidden" 기능을 새로 만들었다');
      }
    });

    test('permission 계약 무변경', () {
      expect(
        _flat(cardCode).contains('final canManageTo = up.can((p) => p.canManageTo);'),
        isTrue,
      );
    });

    test('POSTING-V2-01A 회귀 없음', () {
      final d = _flat(_codeOf(_src(_inviteDialogPath)));
      expect(
        d.contains("'selectedWorkType': generalWd!.workType, "
            "'workDetailStartTime': generalWd.startTime, "
            "'workDetailEndTime': generalWd.endTime,"),
        isTrue,
      );
    });

    test('POSTING-V2-01B 회귀 없음', () {
      final c = _codeOf(_src(_ctrlPath));
      expect(c.contains('_loadError = e;'), isTrue);
      expect(c.contains('Object? get loadError => _loadError;'), isTrue);
    });

    // [POSTING-V2-02A.1] activeToCount는 02A.1에서 제거됐다(quota 분자 계약 폐기).
    // [POSTING-V2-02B.2] notifyDataChanged는 origin 인자를 받는 mutation 전용 API가 됐다.
    // delete lifecycle이 quota/freshness 계약에 영향을 주지 않는다는 점만 고정한다.
    test('freshness API 유지 · quota는 controller에서 제거된 상태 유지', () {
      final c = _codeOf(_src(_ctrlPath));
      expect(
        c.contains(
            'static void notifyDataChanged({required AdminMutationOrigin origin})'),
        isTrue,
        reason: 'freshness API가 사라졌다',
      );
      expect(c.contains('activeToCount'), isFalse,
          reason: '거부된 quota 분자가 되살아났다');
    });

    // DRAFT 삭제는 Home truth에 영향이 없다 — 02B.2가 정한 경계를 여기서도 고정한다.
    test('DRAFT 삭제가 Home invalidation을 유발하지 않는다', () {
      final card = _codeOf(_src(_cardPath));
      final delIdx = card.indexOf("case 'batchDelete':");
      expect(delIdx, isNot(-1));
      final block = card.substring(delIdx, card.indexOf('break;', delIdx));
      expect(block.contains('notifyDataChanged'), isFalse);
    });
  });
}
