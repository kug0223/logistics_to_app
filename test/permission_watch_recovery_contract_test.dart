// [CROSS-DOMAIN-R5.1F.4] 죽은 권한 구독의 회복
//
// R5.1F.3에서 나는 "에러 뒤 정상 snapshot이 오면 상태가 되돌아온다"고 적었다.
// 그건 틀렸다. Firestore의 listen 에러는 **terminal**이다 — 그 구독은 다시
// snapshot을 주지 않는다. 그래서 실제로는 이렇게 됐다:
//
//   · 대상 사업장 구독: 죽은 구독이 registry에 그대로 남아, 다음 watch가
//     "이미 구독 중"으로 오인하고 다시 붙이지 않았다. 그 사업장은 열린 화면이
//     전부 닫힐 때까지 영영 미검증(error)으로 남는다.
//   · 선택 사업장 구독: _memberPermsSub가 non-null로 남아, access refresh의
//     _normalizeSelectedContext도 "이미 그 사업장을 보고 있다"고 판단해
//     다시 붙이지 않았다. 같은 고착이다.
//
// 이번에 고친 것:
//   1. onError를 terminal로 취급한다 — 구독을 끊고 자리를 비운다.
//      refcount는 보존한다(보고 있는 화면 수는 변하지 않았다).
//   2. 빈 자리는 "다시 붙일 수 있음"을 뜻한다. watch/retry가 그때 새로 붙인다.
//   3. 재시도는 두 경로뿐이다 — 화면의 명시 재시도, 그리고 기존 access refresh.
//      타이머도, 자동 반복도, 전체 사업장 재시작도 없다.
//
// 바뀌지 않은 것: ERROR ≠ DENIED. 에러는 권한 값을 지우지 않는다.
//
// 테스트 가능 범위:
//   UserProvider는 필드 초기화에서 Firebase를 잡아 테스트에서 생성되지 않는다
//   (permission_provider_seam_probe_test 실측). 실제 listener 전이는 R7
//   실기기 확인이고, 여기서는 제어흐름의 성질을 소스에서 고정한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _load(String p) => _flat(_codeOf(_src(p)));

const _provider = 'lib/providers/user_provider.dart';
const _payDash = 'lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart';
const _queue = 'lib/screens/business_admin/support_review_queue_screen.dart';

/// 소스에서 함수 본문을 중괄호 균형으로 잘라낸다.
String _bodyOf(String raw, String signature) {
  final i = raw.indexOf(signature);
  if (i < 0) throw StateError('$signature 를 찾지 못함');
  final open = raw.indexOf('{', i);
  var depth = 0;
  for (var j = open; j < raw.length; j++) {
    if (raw[j] == '{') depth++;
    if (raw[j] == '}') {
      depth--;
      if (depth == 0) return raw.substring(i, j + 1);
    }
  }
  throw StateError('$signature 본문이 닫히지 않음');
}

void main() {
  final up = _load(_provider);
  final rawUp = _src(_provider);

  // ── PART B/C. terminal error와 죽은 구독 정리 ──────────────────────

  group('listen 에러는 terminal로 취급한다', () {
    test('registry가 빈 자리를 표현할 수 있다', () {
      expect(
          up.contains('final Map<String, ({StreamSubscription<DocumentSnapshot'
              '<Map<String, dynamic>>>? sub, int count})> _targetPermsSubs = {};'),
          true,
          reason: 'sub가 null일 수 없으면 죽은 구독과 산 구독을 구분할 수 없다');
    });

    test('onError가 구독을 끊고 자리를 비운다', () {
      final attach = _flat(_codeOf(
          _bodyOf(rawUp, 'StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>\n'
              '      _attachTargetPermsListener(')));
      expect(attach.contains('_markTargetPermsListenerDead(businessId);'), true);
    });

    test('자리를 비우되 refcount는 보존한다', () {
      final dead = _flat(_codeOf(
          _bodyOf(rawUp, 'void _markTargetPermsListenerDead(String businessId) {')));
      expect(dead.contains('cur.sub!.cancel();'), true, reason: '죽은 구독은 끊는다');
      expect(dead.contains('_targetPermsSubs[businessId] = (sub: null, count: cur.count);'),
          true, reason: '보고 있는 화면 수는 변하지 않았다');
      expect(dead.contains('_targetPermsSubs.remove('), false,
          reason: 'entry를 지우면 남아 있는 화면의 해제가 길을 잃는다');
    });

    test('에러는 권한 값을 지우지 않는다 (ERROR ≠ DENIED)', () {
      final attach = _flat(_codeOf(
          _bodyOf(rawUp, 'StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>\n'
              '      _attachTargetPermsListener(')));
      final onError = attach.substring(attach.indexOf('}, onError: (e) {'));
      expect(onError.contains('_setBusinessPermission'), false);
      expect(onError.contains('_setPermissionWatchState(businessId, PermissionWatchState.error);'),
          true);
    });

    test('에러 상태에서 예전 허용을 쓰지 않는다 (ERROR ≠ VERIFIED_ALLOW)', () {
      expect(
          up.contains('if (watch == PermissionWatchState.error) return PermissionCheck.error;'),
          true);
      final body = _flat(_codeOf(
          _bodyOf(rawUp, 'PermissionCheck checkForBusiness(')));
      expect(body.indexOf('PermissionWatchState.error') <
              body.indexOf('_subAdminPermissionsByBusinessView[businessId]'),
          true,
          reason: 'error 판정이 기존 map 값보다 먼저여야 한다');
    });
  });

  // ── PART D/E. 재부착과 중복 방지 ───────────────────────────────────

  group('죽은 자리에만 다시 붙인다', () {
    final watch =
        _flat(_codeOf(_bodyOf(rawUp, 'VoidCallback watchBusinessPermissions(String businessId) {')));
    final retry = _flat(
        _codeOf(_bodyOf(rawUp, 'void retryBusinessPermissionWatch(String businessId) {')));

    test('watch: 자리가 비어 있으면 붙이고, 살아 있으면 그대로 쓴다', () {
      expect(
          watch.contains('sub: existing.sub ?? _attachTargetPermsListener(businessId, user.uid), '
              'count: existing.count + 1,'),
          true,
          reason: '?? 가 없으면 죽은 구독이 "이미 구독 중"으로 오인된다');
    });

    test('retry: 살아 있으면 아무 일도 하지 않는다 — 중복 구독 0', () {
      expect(retry.contains('if (cur == null || cur.sub != null) return;'), true,
          reason: '이미 살아 있는데 또 붙이면 같은 사업장에 구독이 둘이 된다');
    });

    test('retry: 아무도 보고 있지 않으면 붙이지 않는다', () {
      expect(retry.contains('if (cur == null'), true,
          reason: '화면이 없는데 구독을 만들면 상시 구독이 된다');
    });

    test('retry: refcount를 건드리지 않는다', () {
      expect(retry.contains('count: cur.count,'), true);
      expect(retry.contains('cur.count + 1'), false);
    });

    test('retry 직후는 unknown이다 — 아직 답을 받지 못했다', () {
      expect(retry.contains('_setPermissionWatchState(businessId, PermissionWatchState.unknown);'),
          true, reason: 'error도 verified도 아니다');
    });

    test('SUB_ADMIN이 아니면 retry도 하지 않는다', () {
      expect(retry.contains('if (user == null || !user.isSubAdmin) return;'), true);
    });
  });

  group('여러 화면이 같은 사업장을 봐도 구독은 하나다', () {
    final watch =
        _flat(_codeOf(_bodyOf(rawUp, 'VoidCallback watchBusinessPermissions(String businessId) {')));

    test('두 번째 화면은 count만 올린다', () {
      expect(watch.contains('count: existing.count + 1,'), true);
    });

    test('한 화면이 닫혀도 나머지가 있으면 유지한다', () {
      expect(watch.contains('_targetPermsSubs[businessId] = (sub: cur.sub, count: cur.count - 1);'),
          true);
    });

    test('마지막 화면이 닫히면 정리한다', () {
      expect(
          watch.contains('if (cur.count <= 1) { cur.sub?.cancel(); '
              '_targetPermsSubs.remove(businessId); '
              '_releaseWatchStateIfUnwatched(businessId); }'),
          true,
          reason: '죽은 자리(sub==null)에서도 안전해야 하므로 ?. 다');
    });

    test('아직 누가 보고 있으면 신선도를 비우지 않는다', () {
      final rel = _flat(_codeOf(
          _bodyOf(rawUp, 'void _releaseWatchStateIfUnwatched(String businessId) {')));
      expect(rel.contains('final watchedByTarget = _targetPermsSubs[businessId]?.sub != null;'),
          true);
      expect(
          rel.contains('final watchedBySelected = _memberPermsSub != null && '
              '_memberPermsBusinessId == businessId;'),
          true,
          reason: '선택 사업장 listener가 같은 사업장을 보고 있으면 여전히 검증된 값이다');
      expect(rel.contains('if (watchedByTarget || watchedBySelected) return;'), true);
    });

    test('provider dispose는 죽은 자리를 만나도 안전하다', () {
      expect(up.contains('for (final e in _targetPermsSubs.values) { e.sub?.cancel(); } '
          '_targetPermsSubs.clear();'), true);
    });
  });

  // ── PART F. 회복 경로 ──────────────────────────────────────────────

  group('재시도 경로는 결정적이고 둘뿐이다', () {
    test('명시 재시도 — 화면이 부른다', () {
      final s = _load(_payDash);
      expect(
          s.contains('onTap: () => ctx .read<UserProvider>() '
              '.retryBusinessPermissionWatch(widget.businessId),'),
          true);
      expect(s.contains("Text('권한 정보를 확인하지 못했습니다 · 다시 확인',"), true);
    });

    test('생명주기 재시도 — 기존 access refresh에 얹힌다', () {
      expect(up.contains('retryDeadPermissionWatches();'), true);
      final run = _flat(_codeOf(
          _bodyOf(rawUp, 'Future<void> _runSubAdminAccessRefresh() async {')));
      expect(run.contains('retryDeadPermissionWatches();'), true,
          reason: '당겨서 새로고침·resume이 이미 부르는 경로다');
    });

    test('죽은 자리만 다시 붙인다 — 전체 재시작이 아니다', () {
      final all = _flat(
          _codeOf(_bodyOf(rawUp, 'void retryDeadPermissionWatches() {')));
      expect(all.contains('.where((e) => e.value.sub == null)'), true);
      expect(all.contains('subAdminBusinessIds'), false,
          reason: '배정 전체를 대상으로 삼으면 상시 구독에 가까워진다');
    });

    test('타이머도 자동 반복도 없다', () {
      for (final sig in [
        'void retryBusinessPermissionWatch(String businessId) {',
        'void retryDeadPermissionWatches() {',
        'void _markTargetPermsListenerDead(String businessId) {',
      ]) {
        final body = _codeOf(_bodyOf(rawUp, sig));
        for (final forbidden in ['Timer', 'Future.delayed', 'while (', 'for (var']) {
          expect(body.contains(forbidden), false, reason: '$sig 안의 $forbidden');
        }
      }
    });

    test('재로그인을 요구하지 않는다', () {
      final retry = _codeOf(
          _bodyOf(rawUp, 'void retryBusinessPermissionWatch(String businessId) {'));
      expect(retry.contains('signOut'), false);
      expect(retry.contains('_loadUserData'), false);
    });
  });

  group('재부착 뒤 첫 snapshot이 결론을 낸다', () {
    final attach = _flat(_codeOf(
        _bodyOf(rawUp, 'StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>\n'
            '      _attachTargetPermsListener(')));

    test('허용/거부 어느 쪽이든 verified다', () {
      expect(attach.contains('_setPermissionWatchState(businessId, PermissionWatchState.verified);'),
          true);
    });

    test('membership 삭제는 확인된 거부다', () {
      expect(attach.contains('data == null ? null : MemberPermissions.fromMap('), true);
      expect(up.contains('if (watch == PermissionWatchState.verified) return PermissionCheck.denied;'),
          true);
    });

    test('다시 에러가 나면 같은 정리를 반복한다', () {
      final onError = attach.substring(attach.indexOf('}, onError: (e) {'));
      expect(onError.contains('_markTargetPermsListenerDead(businessId);'), true,
          reason: '두 번째 에러에서도 자리를 비워야 다시 붙일 수 있다');
    });
  });

  // ── PART G. 선택 사업장 listener 정렬 ──────────────────────────────

  group('선택 사업장 listener도 같은 원칙이다', () {
    final sel = _flat(_codeOf(
        _bodyOf(rawUp, 'void _startMemberPermsListener(String businessId, String uid) {')));

    test('onError가 자리를 비운다', () {
      final onError = sel.substring(sel.indexOf('}, onError: (e) {'));
      expect(onError.contains('_memberPermsSub = null; _memberPermsBusinessId = null;'), true,
          reason: 'non-null로 남으면 _normalizeSelectedContext가 다시 붙이지 않는다');
    });

    test('onError가 권한 값을 지우지 않는다', () {
      final onError = sel.substring(sel.indexOf('}, onError: (e) {'));
      expect(onError.contains('_memberPermissions = null'), false);
      expect(onError.contains('_setBusinessPermission'), false);
      expect(onError.contains('_setPermissionWatchState(businessId, PermissionWatchState.error);'),
          true);
    });

    test('기존 refresh 경로가 다시 붙인다 — 새 재시도 경로를 만들지 않았다', () {
      final norm = _flat(
          _codeOf(_bodyOf(rawUp, 'void _normalizeSelectedContext(String uid) {')));
      expect(norm.contains('if (_memberPermsSub != null && _memberPermsBusinessId == active) return;'),
          true);
      expect(norm.contains('_startMemberPermsListener(active, uid);'), true);
    });

    test('성공 snapshot은 선택 사업장에도 신선도를 남긴다', () {
      expect(
          sel.contains('_setBusinessPermission(businessId, _memberPermissions); '
              '_setPermissionWatchState(businessId, PermissionWatchState.verified);'),
          true);
      expect(
          sel.contains('_setBusinessPermission(businessId, null); '
              '_setPermissionWatchState(businessId, PermissionWatchState.verified);'),
          true,
          reason: 'membership 상실도 확인된 사실이다');
    });

    test('membership 상실 복구는 선택 listener만의 책임으로 남는다', () {
      expect(sel.contains('_recoverFromSelectedMembershipLoss(businessId)'), true);
      final attach = _flat(_codeOf(
          _bodyOf(rawUp, 'StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>\n'
              '      _attachTargetPermsListener(')));
      expect(attach.contains('_recoverFromSelectedMembershipLoss'), false,
          reason: 'B의 membership 상실이 A의 선택 context를 흔들면 안 된다');
    });
  });

  // ── 폴링 금지 재확인 ───────────────────────────────────────────────

  group('여전히 폴링이 아니다', () {
    test('구독 지점은 둘뿐이다', () {
      expect('snapshots()'.allMatches(_codeOf(rawUp)).length, 2,
          reason: '상시 1(선택 사업장) + 화면 수명 1(대상 사업장)');
    });

    test('큐의 결정적 refresh가 재부착까지 이어진다', () {
      final s = _load(_queue);
      expect(s.contains('unawaited(up.refreshSubAdminAccessState());'), true,
          reason: '이 경로가 retryDeadPermissionWatches까지 간다');
    });
  });
}
