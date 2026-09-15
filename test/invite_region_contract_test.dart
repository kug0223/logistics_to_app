// [SYSTEM-INTEGRATION-R2.3] 초대 받을 지역 계약
//
// 폐기된 정책:
//
//     userCity == businessCity   →   후보
//
//   거주지가 곧 초대 동의라고 본 것이다. 실제 근로자는 본업 근처, 이동 중,
//   생활권 인접지역에서 일한다. 그리고 city 문자열 비교는 서울 중구와
//   부산 중구를 같은 지역으로 봤다 — korean_regions.dart 상단이 이미
//   경고하고 있던 문제다(중구 6곳, 동구 6곳, 서구 6곳).
//
// 새 정책:
//
//     그 근무지역의 초대를 받아도 된다고 지원자가 **직접 설정**한 사람
//
//   · 먼저 오는 초대(proactive invitation)에만 적용된다. 직접 검색·지원은 무관.
//   · 후보 reader만이 아니라 invite writer가 발송 직전에 다시 검증한다.
//   · homeRegion을 자동으로 초대 지역으로 저장하지 않는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/data/korean_regions.dart';
import 'package:ALfit/models/core/invite_region_preference.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/utils/region_key.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _tsSliceOf(String source, String from, String to) {
  final a = source.indexOf(from);
  if (a == -1) throw StateError('$from 를 찾지 못함');
  final b = source.indexOf(to, a + from.length);
  if (b == -1) throw StateError('$to 를 찾지 못함');
  return source.substring(a, b);
}

String _after(String source, String signature, [int chars = 2000]) {
  final a = source.indexOf(signature);
  if (a == -1) throw StateError('$signature 를 찾지 못함');
  final end = a + chars;
  return source.substring(a, end > source.length ? source.length : end);
}

const _cfPath = 'functions/src/index.ts';
const _rulesPath = 'firestore.rules';
const _candSheetPath =
    'lib/screens/business_admin/dialogs/available_workers_bottom_sheet.dart';
const _candModelPath = 'lib/models/core/available_worker_model.dart';
const _settingsPath = 'lib/screens/user/invite_region_settings_screen.dart';
const _availSvcPath = 'lib/services/availability_service.dart';

void main() {
  final cfRaw = _src(_cfPath);
  final cf = _codeOf(cfRaw);
  // 주석에는 "이전 코드: userCity !== businessCity" 같은 설명이 남아 있으므로
  // 실제 동작을 보는 검사는 주석을 제거한 버전으로 한다.
  final getWorkers = _codeOf(_tsSliceOf(cfRaw,
      'export const callableGetAvailableWorkers',
      '// ─── callableGetMyScheduleChanges'));
  final inviteFn = _tsSliceOf(cfRaw, 'export const callableInviteWorker',
      'export const callableAcceptTOInvitation');

  // ═════════════════════════════════════════════════════════════
  // 1. 지역 identity — city 문자열만으로 특정하지 않는다 (§5)
  // ═════════════════════════════════════════════════════════════
  group('R2.3-01 region key', () {
    test('01-a 동명 시/군/구는 province 없이 특정되지 않는다', () {
      // 이것이 기존 `city == city` 비교가 틀렸던 이유다.
      expect(KoreanRegions.provinceOfCity('중구'), isNull);
      expect(KoreanRegions.provinceOfCity('동구'), isNull);
      expect(KoreanRegions.provinceOfCity('서구'), isNull);
      expect(regionKeyOf(city: '중구'), isNull, reason: '추측해서 고르면 안 된다');
    });

    test('01-b 유일한 시/군/구는 province를 유추한다', () {
      expect(KoreanRegions.provinceOfCity('수원시'), '경기도');
      expect(regionKeyOf(city: '수원시'), '경기도|수원시');
      expect(regionKeyOf(city: '오산시'), '경기도|오산시');
    });

    test('01-c 표기 drift가 eligibility를 깨지 않는다', () {
      // 수원 / 수원시 / 경기도 수원시 / 경기 수원시
      const want = '경기도|수원시';
      expect(regionKeyOf(province: '경기도', city: '수원시'), want);
      expect(regionKeyOf(province: '경기', city: '수원시'), want);
      expect(regionKeyOf(province: ' 경기도 ', city: ' 수원시 '), want);
      expect(regionKeyOf(city: '수원시'), want);
    });

    test('01-d 서울 중구와 부산 중구는 다른 지역이다', () {
      final seoul = regionKeyOf(province: '서울특별시', city: '중구');
      final busan = regionKeyOf(province: '부산광역시', city: '중구');
      expect(seoul, '서울특별시|중구');
      expect(busan, '부산광역시|중구');
      expect(seoul == busan, isFalse, reason: '기존 city 비교는 이 둘을 같게 봤다');
    });

    test('01-e 존재하지 않는 조합은 저장 전에 걸러진다', () {
      expect(KoreanRegions.isValidPair('경기도', '수원시'), isTrue);
      expect(KoreanRegions.isValidPair('경기도', '강남구'), isFalse);
      expect(KoreanRegions.isValidPair('서울특별시', '강남구'), isTrue);
      expect(KoreanRegions.isValidPair('세종특별자치시', '세종특별자치시'), isTrue);
    });

    test('01-f 서버 구현이 같은 규칙을 쓴다', () {
      expect(cf.contains('const REGION_KEY_SEP = "|";'), isTrue);
      expect(cf.contains('function srvRegionKeyOf('), isTrue);
      expect(cf.contains('function srvProvinceOfCity('), isTrue);
      // 동명이면 null — 추측 금지
      final f = _after(cfRaw, 'function srvProvinceOfCity(', 500);
      expect(f.contains('if (found !== null) return null;'), isTrue);
    });

    test('01-g 서버/클라이언트 지역 데이터가 같다', () {
      // 두 목록이 갈라지면 한쪽에서만 유효한 지역이 생긴다.
      final tsBlock = _tsSliceOf(
          cfRaw, 'const KOREAN_CITIES_BY_PROVINCE', '\n};');
      for (final e in KoreanRegions.citiesByProvince.entries) {
        expect(tsBlock.contains('"${e.key}"'), isTrue,
            reason: '서버에 ${e.key} 없음');
        for (final city in e.value) {
          expect(tsBlock.contains('"$city"'), isTrue,
              reason: '서버에 ${e.key} $city 없음');
        }
      }
      // 총량도 맞춘다 — 서버에만 있는 지역이 생기지 않도록
      final tsCities = RegExp('"[^"]+"')
          .allMatches(tsBlock)
          .map((m) => m.group(0)!)
          .length;
      final dartCities = KoreanRegions.citiesByProvince.values
              .fold<int>(0, (a, b) => a + b.length) +
          KoreanRegions.citiesByProvince.length;
      expect(tsCities, dartCities);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 2. preference state — UNSET != OFF, ERROR != OFF (§8)
  // ═════════════════════════════════════════════════════════════
  group('R2.3-02 preference state', () {
    test('02-a 네 상태가 각각 구분된다', () {
      expect(const InviteRegionPreference().state, InvitePreferenceState.unset);
      expect(const InviteRegionPreference(enabled: false).state,
          InvitePreferenceState.off);
      expect(
          const InviteRegionPreference(
              enabled: true, regions: [UserRegion(province: '경기도', city: '수원시')])
              .state,
          InvitePreferenceState.on);
      expect(const InviteRegionPreference.unknown().state,
          InvitePreferenceState.unknown);
    });

    test('02-b UNSET을 OFF로 읽지 않는다', () {
      const unset = InviteRegionPreference();
      expect(unset.state == InvitePreferenceState.off, isFalse);
      expect(unset.enabled, isNull, reason: '없음과 false는 다르다');
    });

    test('02-c ERROR를 OFF로 읽지 않는다', () {
      const err = InviteRegionPreference.unknown();
      expect(err.state == InvitePreferenceState.off, isFalse);
      expect(err.allows('경기도|수원시'), isFalse, reason: '모르는 것을 허용으로 읽지 않는다');
    });

    test('02-d ON인데 지역 0개는 ON이 아니다', () {
      const broken = InviteRegionPreference(enabled: true, regions: []);
      expect(broken.state, InvitePreferenceState.unknown);
      expect(broken.validationError(), isNotNull);
    });

    test('02-e 서버도 같은 모순을 막는다', () {
      final fn = _tsSliceOf(cfRaw, 'export const callableSetInviteRegions',
          'export const callableSyncInviteKeys');
      expect(fn.contains('if (enabled && cleaned.length === 0)'), isTrue);
      expect(fn.contains('초대 받을 지역을 한 곳 이상 선택해 주세요.'), isTrue);
    });

    test('02-f allows는 정확히 그 지역만 허용한다', () {
      const pref = InviteRegionPreference(enabled: true, regions: [
        UserRegion(province: '경기도', city: '수원시'),
        UserRegion(province: '경기도', city: '오산시'),
      ]);
      expect(pref.allows('경기도|수원시'), isTrue);
      expect(pref.allows('경기도|오산시'), isTrue);
      expect(pref.allows('경기도|용인시'), isFalse);
      expect(pref.allows(null), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 3. 거주지역 hard gate 제거 (§1, §13, §31)
  // ═════════════════════════════════════════════════════════════
  group('R2.3-03 거주지역 gate 제거', () {
    test('03-a userCity == businessCity 가 사라졌다', () {
      expect(getWorkers.contains('if (userCity !== businessCity) continue;'),
          isFalse, reason: '거주지역 hard gate가 남아 있다');
      expect(getWorkers.contains('const userCity ='), isFalse);
    });

    test('03-b 자격은 지원자가 설정한 초대 동의다', () {
      expect(getWorkers.contains('avData["inviteEnabled"] !== true'), isTrue);
      expect(getWorkers.contains('avRegionKeys.includes(workRegionKey)'), isTrue);
    });

    test('03-c pool 쿼리가 거주 city로 좁히지 않는다', () {
      // 기존: city == businessCity AND dates array-contains
      expect(getWorkers.contains('.where("city", "==", businessCity)'), isFalse);
      expect(getWorkers.contains('.where("inviteKeys", "array-contains", inviteKey)'),
          isTrue);
    });

    test('03-d homeRegion은 자격이 아니라 제외 대상이다 (§18/§19)', () {
      // 거주 동/읍/면을 관리자에게 보내지 않는다
      expect(getWorkers.contains('const userDistrict: string | undefined = undefined;'),
          isTrue);
      // 지원자가 설정한 초대 지역 **목록 전체**도 보내지 않는다
      expect(getWorkers.contains('inviteRegions:'), isFalse);
      expect(getWorkers.contains('inviteRegionKeys:'), isFalse,
          reason: '후보 DTO에 preference 목록이 실렸다');
    });

    test('03-e 후보 행이 거주지로 오해되지 않는다 (§19)', () {
      final m = _codeOf(_src(_candModelPath));
      expect(m.contains("'\$city 근무 가능'"), isTrue);
      expect(m.contains("'\$city \$district'"), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 4. canonical work location (§4, §16)
  // ═════════════════════════════════════════════════════════════
  group('R2.3-04 근무 장소', () {
    test('04-a TO/slot/workDetail에 근무 장소 필드가 없다 — 확인 결과 고정', () {
      // 이 사실이 바뀌면(공고별 근무주소 도입) 이 계약이 깨져서 알려 준다.
      final to = _src('lib/models/core/to_model.dart');
      final slot = _src('lib/models/core/slot_model.dart');
      for (final f in const [
        'workAddress',
        'workLocation',
        'workPlaceAddress',
        'workRegion',
      ]) {
        expect(to.contains(f), isFalse, reason: 'TOModel에 $f 가 생겼다');
        expect(slot.contains(f), isFalse, reason: 'SlotModel에 $f 가 생겼다');
      }
    });

    test('04-b 근무 지역은 businesses에서 한 곳으로 읽는다', () {
      expect(cf.contains('function srvWorkRegionKeyOfBusiness('), isTrue);
      // 후보 조회와 초대 발송이 같은 함수를 쓴다 — 두 판정이 갈리지 않는다
      expect(getWorkers.contains('srvWorkRegionKeyOfBusiness(bizData)'), isTrue);
      expect(inviteFn.contains('srvWorkRegionKeyOfBusiness('), isTrue);
    });

    test('04-c 지역을 특정 못 하면 UNKNOWN이다 — 후보 0명이 아니다 (§20)', () {
      expect(getWorkers.contains('WORK_REGION_UNRESOLVED'), isTrue);
      final sheet = _codeOf(_src(_candSheetPath));
      expect(sheet.contains('work_region_unresolved'), isTrue);
      expect(sheet.contains('근무 지역을 확인하지 못했어요'), isTrue);
    });

    test('04-d SUCCESS_ZERO 문구가 새 자격을 말한다', () {
      final sheet = _codeOf(_src(_candSheetPath));
      expect(sheet.contains('이 지역의 근무 초대를 받도록'), isTrue);
      expect(sheet.contains('현재 초대 가능한 인력이 없습니다.'), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 5. mutation-time revalidation — BLOCKER (§15, §16, §26)
  // ═════════════════════════════════════════════════════════════
  group('R2.3-05 invite writer 재검증', () {
    test('05-a writer가 발송 직전에 preference를 fresh read한다', () {
      expect(inviteFn.contains('db.collection("worker_availability")\n      .doc(targetUid).get()'),
          isTrue);
      expect(inviteFn.contains('inviteAvData?.["inviteEnabled"] !== true'), isTrue);
      expect(inviteFn.contains('이 근로자는 현재 근무 초대를 받지 않습니다.'), isTrue);
    });

    test('05-b writer가 지역 일치를 다시 확인한다', () {
      expect(inviteFn.contains('inviteAllowedKeys.includes(inviteWorkRegionKey)'),
          isTrue);
      expect(inviteFn.contains('초대 받을 지역으로 선택하지 않은 근무입니다.'), isTrue);
    });

    test('05-c 클라이언트가 보낸 지역 값을 쓰지 않는다 (§16)', () {
      // 근무 지역은 지금 businesses에서 다시 읽는다. 입력으로 받지 않는다.
      final args = _after(cfRaw, 'export const callableInviteWorker', 1400);
      expect(args.contains('regionKey'), isFalse);
      expect(args.contains('workRegion'), isFalse);
      expect(inviteFn.contains('const inviteBizSnap ='), isTrue);
    });

    test('05-d 검증 실패는 Application/카운터/알림 이전에 일어난다 (§26)', () {
      final at = inviteFn.indexOf('inviteAllowedKeys.includes(inviteWorkRegionKey)');
      final tx = inviteFn.indexOf('await db.runTransaction');
      final notif = inviteFn.indexOf('to_invite_');
      expect(at, greaterThan(0));
      expect(tx, greaterThan(at), reason: '재검증이 트랜잭션 뒤에 있다');
      expect(notif, greaterThan(at), reason: '재검증이 알림 뒤에 있다');
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 6. 쓰기 권한 (§21) + 쿼리 구조 (§17)
  // ═════════════════════════════════════════════════════════════
  group('R2.3-06 권한·쿼리', () {
    test('06-a preference writer는 본인 uid만 쓴다', () {
      final fn = _tsSliceOf(cfRaw, 'export const callableSetInviteRegions',
          'export const callableSyncInviteKeys');
      expect(fn.contains('const uid = request.auth.uid;'), isTrue);
      // 대상 uid를 입력으로 받지 않는다 — 관리자가 남의 설정을 바꿀 수 없다
      expect(fn.contains('targetUid'), isFalse);
      expect(fn.contains('db.collection("worker_availability").doc(uid)'), isTrue);
    });

    test('06-b 초대 필드는 클라이언트가 쓸 수 없다', () {
      final rules = _src(_rulesPath);
      expect(rules.contains('function isInviteFieldsUnchanged()'), isTrue);
      for (final f in const [
        'inviteEnabled',
        'inviteRegions',
        'inviteRegionKeys',
        'inviteKeys',
      ]) {
        expect(
            rules.contains("d.get('$f', null) == p.get('$f', null)"), isTrue,
            reason: '$f 변경이 막히지 않았다');
      }
      expect(rules.contains('isInviteFieldsUnchanged()'), isTrue);
    });

    test('06-c 후보 조회는 canManageTo를 요구한다 (§22)', () {
      expect(getWorkers.contains('awPerms?.canManageTo !== true'), isTrue);
      expect(getWorkers.contains('TO 관리 권한이 없습니다.'), isTrue);
    });

    test('06-d 전국 스캔이 아니다 — 지역과 날짜를 한 쿼리로 좁힌다 (§17/§33)', () {
      // Firestore는 array-contains를 쿼리당 하나만 허용한다.
      // 지역만 좁히면 페이지가 엉뚱하게 비고, 날짜만 좁히면 전국 스캔이 된다.
      expect(cf.contains('function srvInviteKey('), isTrue);
      expect(getWorkers.contains('const inviteKey = srvInviteKey(workRegionKey, dateKey);'),
          isTrue);
      // pool 쿼리 3곳 모두 복합 키를 쓴다 (count / full_pool / legacy_paged)
      final n = RegExp(r'\.where\("inviteKeys", "array-contains", inviteKey\)')
          .allMatches(getWorkers)
          .length;
      expect(n, 3, reason: 'pool 쿼리 중 좁혀지지 않은 경로가 있다');
    });

    test('06-e 복합 키는 서버가 만든다', () {
      final set = _tsSliceOf(cfRaw, 'export const callableSetInviteRegions',
          'export const callableSyncInviteKeys');
      expect(set.contains('srvInviteKey(k, d)'), isTrue);
      expect(cf.contains('export const callableSyncInviteKeys'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 7. 기존 동작 무회귀 (§2, §24, §25, §10, §11)
  // ═════════════════════════════════════════════════════════════
  group('R2.3-07 무회귀', () {
    test('07-a 직접 지원은 초대 설정과 무관하다 (§2/§24)', () {
      final apply = _tsSliceOf(cfRaw, 'export const callableApplyToTO',
          'export const callableGetMyApplications');
      for (final f in const [
        'inviteEnabled',
        'inviteRegionKeys',
        'inviteKeys',
        'worker_availability',
      ]) {
        expect(apply.contains(f), isFalse,
            reason: '지원 경로가 초대 설정을 보고 있다: $f');
      }
    });

    test('07-b preference 변경이 기존 초대를 소급 취소하지 않는다 (§12/§25)', () {
      final set = _tsSliceOf(cfRaw, 'export const callableSetInviteRegions',
          'export const callableSyncInviteKeys');
      for (final f in const [
        'applications',
        'AUTO_CANCELED',
        'CANCELED',
        'status:',
      ]) {
        expect(set.contains(f), isFalse,
            reason: '설정 변경이 Application을 건드린다: $f');
      }
    });

    test('07-c OFF여도 선택한 지역은 보존된다 (§11)', () {
      final set = _tsSliceOf(cfRaw, 'export const callableSetInviteRegions',
          'export const callableSyncInviteKeys');
      // inviteRegions는 항상 저장, 매칭용 키만 비운다
      expect(set.contains('inviteRegions: cleaned.map('), isTrue);
      expect(set.contains('inviteRegionKeys: enabled ? regionKeys : []'), isTrue);
    });

    test('07-d homeRegion을 자동으로 초대 지역에 넣지 않는다 (§10)', () {
      final set = _tsSliceOf(cfRaw, 'export const callableSetInviteRegions',
          'export const callableSyncInviteKeys');
      // 문서를 처음 만들 때 city(기존 스키마)만 채운다 — inviteRegions에는 넣지 않는다
      final at = set.indexOf('if (!avSnap.exists)');
      final block = set.substring(at, at + 420);
      expect(block.contains('payload["inviteRegions"]'), isFalse);
      expect(block.contains('payload["inviteRegionKeys"]'), isFalse);
      // UI에서도 추천일 뿐 — 누르면 목록에 담기고, 저장은 별도다
      final ui = _codeOf(_src(_settingsPath));
      expect(ui.contains('_regions.add(home)'), isTrue);
      expect(ui.contains('onPressed: (_saving || !_dirty) ? null : _save'), isTrue);
    });

    test('07-e 근무 가능일 저장이 초대 설정을 지우지 않는다', () {
      final svc = _codeOf(_src(_availSvcPath));
      expect(svc.contains('SetOptions(merge: true)'), isTrue);
      expect(svc.contains('callableSyncInviteKeys'), isTrue);
      // 문서 삭제는 초대 설정까지 지운다 — 날짜만 비운다
      expect(svc.contains('.delete()'), isFalse);
    });

    test('07-f 가입 필수 단계를 추가하지 않았다 (§9)', () {
      for (final p in const [
        'lib/screens/auth/register_screen.dart',
        'lib/screens/auth/foreign_register_screen.dart',
      ]) {
        final s = _src(p);
        expect(s.contains('InviteRegionSettingsScreen'), isFalse,
            reason: '$p 가 초대 지역 설정을 가입 단계로 만들었다');
        expect(s.contains('inviteRegion'), isFalse);
      }
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 8. V2로 미룬 것 (§6, §35)
  // ═════════════════════════════════════════════════════════════
  group('R2.3-08 이번 범위 밖', () {
    test('08-a GPS·반경·통근시간·요일/시간 availability를 만들지 않았다', () {
      final ui = _src(_settingsPath);
      final svcSrc = _src('lib/services/invite_region_service.dart');
      for (final banned in const [
        'radius',
        'latitude',
        'longitude',
        'commute',
        'Geolocator',
        'weekday',
        'timeRange',
      ]) {
        expect(ui.contains(banned), isFalse, reason: '설정 화면에 $banned');
        expect(svcSrc.contains(banned), isFalse, reason: '서비스에 $banned');
      }
    });

    test('08-b 새 scoring algorithm을 만들지 않았다 (§14)', () {
      // 지역은 eligibility다. 정렬은 기존 _rankCandidates 그대로.
      expect(cf.contains('function _rankCandidates('), isTrue);
      final rank = _after(cfRaw, 'function _rankCandidates(', 2000);
      expect(rank.contains('inviteRegion'), isFalse);
      expect(rank.contains('regionKey'), isFalse);
    });

    test('08-c 미사용 preferredJobRegions에 초대 의미를 덧씌우지 않았다 (§3)', () {
      // 이름이 비슷하다는 이유로 재사용하면 기존 소비자(추천 점수)가 흔들린다.
      final set = _tsSliceOf(cfRaw, 'export const callableSetInviteRegions',
          'export const callableSyncInviteKeys');
      expect(set.contains('preferredJobRegions'), isFalse);
      expect(getWorkers.contains('preferredJobRegions'), isFalse);
    });
  });
}
