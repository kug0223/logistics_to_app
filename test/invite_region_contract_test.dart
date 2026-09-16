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
import 'package:ALfit/utils/format_helper.dart';
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
      expect(regionKeyOf(province: '경기도', city: '강남구'), isNull);
    });

    test('01-h [CLOSURE §8] 구가 있는 시의 표기 차이가 매칭을 깨지 않는다', () {
      // Daum sigungu는 "수원시 팔달구", parseAddressCity 폴백은 "수원시".
      // 지원자 피커는 언제나 "수원시"다. 같은 생활권이면 같은 key여야 한다.
      const want = '경기도|수원시';
      expect(regionKeyOf(province: '경기도', city: '수원시 팔달구'), want);
      expect(regionKeyOf(province: '경기도', city: '수원시'), want);
      expect(regionKeyOf(city: '수원시 팔달구'), want, reason: 'province 없이도');

      for (final c in const [
        ['경기도', '용인시 기흥구', '경기도|용인시'],
        ['경기도', '성남시 분당구', '경기도|성남시'],
        ['경기도', '고양시 일산서구', '경기도|고양시'],
        ['경기도', '안산시 단원구', '경기도|안산시'],
        ['충청북도', '청주시 흥덕구', '충청북도|청주시'],
        ['충청남도', '천안시 서북구', '충청남도|천안시'],
        ['경상남도', '창원시 성산구', '경상남도|창원시'],
        ['경상북도', '포항시 남구', '경상북도|포항시'],
        ['전북특별자치도', '전주시 완산구', '전북특별자치도|전주시'],
      ]) {
        expect(regionKeyOf(province: c[0], city: c[1]), c[2], reason: '${c[1]}');
      }
    });

    test('01-i 표에 없는 값은 추측해서 맞추지 않는다', () {
      expect(normalizeCityName('경기도', '없는시 어떤구'), isNull);
      expect(regionKeyOf(province: '경기도', city: '없는시'), isNull);
      // 포항 남구는 경상북도 포항시다 — 부산 남구로 넘어가면 안 된다.
      expect(regionKeyOf(province: '경상북도', city: '포항시 남구'), '경상북도|포항시');
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
      // [CLOSURE] 단일 writer가 merge로 쓰므로 초대 필드가 남는다.
      final setAv = _tsSliceOf(cfRaw, 'export const callableSetAvailability',
          'export const callableSyncInviteKeys');
      expect(setAv.contains('{merge: true}'), isTrue);
      final at = setAv.indexOf('const payload');
      final payload = setAv.substring(at, setAv.indexOf('tx.set(avRef'));
      for (final f in const ['inviteEnabled', 'inviteRegions', 'inviteRegionKeys']) {
        expect(payload.contains('$f:'), isFalse, reason: '$f 를 덮어쓴다');
      }
      // 문서 삭제는 초대 설정까지 지운다 — 날짜만 비운다
      final svc = _codeOf(_src(_availSvcPath));
      expect(svc.contains('.delete()'), isFalse);
      expect(svc.contains('_setDates(const [])'), isTrue);
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
  // 9. [CLOSURE] writer ownership + 부분 실패 (§1~§4)
  //
  //   `dates`(canonical)와 `inviteKeys`(파생)가 서로 다른 writer에 있으면
  //   "저장하고 나서 동기화 호출"이라는 순차 두 단계가 생긴다. 그 사이의
  //   실패는 조용한 정상 상태로 남는다 — availability != candidate projection.
  // ═════════════════════════════════════════════════════════════
  group('R2.3-09 writer ownership', () {
    final setAv = _tsSliceOf(cfRaw, 'export const callableSetAvailability',
        'export const callableSyncInviteKeys');
    final setRegions = _tsSliceOf(cfRaw,
        'export const callableSetInviteRegions',
        'export const callableSetAvailability');

    test('09-a 클라이언트는 worker_availability를 직접 쓰지 않는다', () {
      final rules = _src(_rulesPath);
      final block = _after(rules, 'match /worker_availability/{uid}', 5000);
      expect(block.contains('allow create, update, delete: if false;'), isTrue,
          reason: '클라이언트 직접 write 경로가 남아 있다');
      // 예전 허용 규칙이 되살아나지 않았는지
      expect(block.contains('allow create, update: if isLoggedIn()'), isFalse);
      final svc = _codeOf(_src(_availSvcPath));
      expect(svc.contains('_col.doc(uid).set('), isFalse);
      expect(svc.contains('callableSetAvailability'), isTrue);
    });

    test('09-b dates와 파생 inviteKeys가 한 번의 write로 저장된다', () {
      // 두 번의 set/update로 나뉘면 부분 성공이 생긴다.
      expect(setAv.contains('tx.set(avRef, payload, {merge: true});'), isTrue);
      final writes = RegExp(r'tx\.set\(avRef|await avRef\.(set|update)\(')
          .allMatches(setAv)
          .length;
      expect(writes, 1, reason: 'availability 저장이 여러 write로 쪼개졌다');
      // 같은 payload에 둘 다 들어간다
      final at = setAv.indexOf('const payload');
      final payload = setAv.substring(at, setAv.indexOf('tx.set(avRef'));
      expect(payload.contains('dates,'), isTrue);
      expect(payload.contains('inviteKeys,'), isTrue);
    });

    test('09-c 지역 저장도 같은 성질이다', () {
      expect(setRegions.contains('tx.set(avRef, payload, {merge: true});'),
          isTrue);
      final writes = RegExp(r'tx\.set\(avRef|await avRef\.(set|update)\(')
          .allMatches(setRegions)
          .length;
      expect(writes, 1);
      final at = setRegions.indexOf('const payload');
      final payload =
          setRegions.substring(at, setRegions.indexOf('tx.set(avRef'));
      expect(payload.contains('inviteRegionKeys:'), isTrue);
      expect(payload.contains('inviteKeys,'), isTrue);
    });

    test('09-d 클라이언트 순차 호출로 원자성을 주장하지 않는다', () {
      final svc = _codeOf(_src(_availSvcPath));
      // 저장 후 별도 동기화 호출이 남아 있으면 그 사이가 구멍이다.
      expect(svc.contains('callableSyncInviteKeys'), isFalse,
          reason: '정상 경로에 2단계 호출이 남아 있다');
      // 실패를 삼키지 않는다 — 저장되지 않은 것을 저장됐다고 하지 않는다
      expect(svc.contains('} catch'), isFalse);
    });

    test('09-e 서버가 날짜를 다시 검증한다', () {
      expect(setAv.contains('MAX_AVAILABILITY_DATES'), isTrue);
      expect(setAv.contains('d >= todayKey && d <= maxKey'), isTrue);
      expect(setAv.contains('new Set('), isTrue, reason: '중복 제거');
    });

    test('09-f 복구 수단은 있고, 스케줄러는 만들지 않았다 (§7)', () {
      expect(cf.contains('export const callableSyncInviteKeys'), isTrue);
      final sync = _tsSliceOf(cfRaw, 'export const callableSyncInviteKeys',
          '// ─── callableGetAvailableWorkers');
      expect(sync.contains('const uid = request.auth.uid;'), isTrue);
      // onSchedule / onDocumentWritten 트리거를 추가하지 않았다
      expect(sync.contains('onSchedule'), isFalse);
      expect(sync.contains('onDocumentWritten'), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 10. [CLOSURE] stale projection을 truth로 믿지 않는다 (§3, §5)
  // ═════════════════════════════════════════════════════════════
  group('R2.3-10 stale projection 방어', () {
    test('10-a 후보 reader가 canonical dates로 다시 판정한다', () {
      // inviteKeys는 인덱스다. 뒤처져도 없는 자격이 생기면 안 된다.
      expect(getWorkers.contains('const avDates = (avData["dates"]'), isTrue);
      expect(getWorkers.contains('if (!avDates.includes(dateKey)) continue;'),
          isTrue);
    });

    test('10-b invite writer가 그 날짜의 가능일을 fresh read로 확인한다 (§5)', () {
      expect(inviteFn.contains('const invAvDates ='), isTrue);
      expect(inviteFn.contains('if (!invAvDates.includes(invDateKey))'), isTrue);
      expect(inviteFn.contains('해당 날짜의 근무 가능일을 등록하지 않았습니다.'), isTrue);
    });

    test('10-c writer는 파생 인덱스가 아니라 canonical을 본다', () {
      // inviteKeys를 보고 판단하면 stale index를 truth로 믿는 것이다.
      final at = inviteFn.indexOf('const invAvDates =');
      final block = inviteFn.substring(at, at + 200);
      expect(block.contains('"dates"'), isTrue);
      expect(block.contains('inviteKeys'), isFalse);
    });

    test('10-d 그 검증도 Application/알림보다 앞에 있다 (§26)', () {
      final at = inviteFn.indexOf('if (!invAvDates.includes(invDateKey))');
      final tx = inviteFn.indexOf('await db.runTransaction');
      final notif = inviteFn.indexOf('to_invite_');
      expect(at, greaterThan(0));
      expect(tx, greaterThan(at));
      expect(notif, greaterThan(at));
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 11. [CLOSURE] cardinality (§9)
  // ═════════════════════════════════════════════════════════════
  group('R2.3-11 cardinality', () {
    test('11-a 상한이 근거와 함께 상수로 있다', () {
      expect(cf.contains('const MAX_INVITE_REGIONS = 20;'), isTrue);
      expect(cf.contains('const MAX_AVAILABILITY_DATES = 60;'), isTrue);
      // dates 상한은 기존 계약과 같은 값이어야 한다
      expect(_src('lib/models/core/worker_availability_model.dart')
          .contains('valid.length > 60'), isTrue);
    });

    test('11-b 최대 inviteKeys가 Firestore 한도 안이다', () {
      const maxRegions = 20, maxDates = 60;
      const maxKeys = maxRegions * maxDates; // 1,200
      expect(maxKeys, 1200);
      // 문서당 index entries 한도 40,000
      expect(maxKeys < 40000, isTrue);
      // key 길이 대략 "경기도|수원시#2026-09-22" ≈ 26 bytes → 약 31KB (1MB 한도)
      expect(maxKeys * 30 < 1024 * 1024, isTrue);
    });

    test('11-c 중복 지역은 저장 전에 제거된다', () {
      final setRegions = _tsSliceOf(cfRaw,
          'export const callableSetInviteRegions',
          'export const callableSetAvailability');
      expect(setRegions.contains('if (seen.has(key)) continue;'), isTrue);
      // [FINAL §8] 상한 초과는 자르지 않고 거부한다 — 14-a 참조
      expect(setRegions.contains('MAX_INVITE_REGIONS'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 12. [FINAL] concurrent writer — 단일 write 원자성 ≠ cross-callable 원자성
  //
  //   두 callable이 같은 문서의 서로 다른 canonical input을 바꾸면서 같은
  //   파생값(inviteKeys)을 만든다. 각자 한 번의 write를 하더라도, 상대의
  //   최신 입력을 못 본 채 계산한 값으로 덮으면 불변식이 깨진다.
  //   그 drift는 reader 재검증으로 false positive만 막을 뿐,
  //   false negative(쿼리에서 이미 빠진 후보)는 복원하지 못한다.
  // ═════════════════════════════════════════════════════════════
  group('R2.3-12 concurrent writer', () {
    final setAv = _tsSliceOf(cfRaw, 'export const callableSetAvailability',
        'export const callableSyncInviteKeys');
    final setRegions = _tsSliceOf(cfRaw,
        'export const callableSetInviteRegions',
        'export const callableSetAvailability');

    test('12-a 두 writer 모두 트랜잭션 안에서 읽고 쓴다', () {
      for (final e in {'setAvailability': setAv, 'setInviteRegions': setRegions}
          .entries) {
        expect(e.value.contains('await db.runTransaction'), isTrue,
            reason: '${e.key} 가 트랜잭션이 아니다');
        expect(e.value.contains('await tx.get(avRef)'), isTrue,
            reason: '${e.key} 가 트랜잭션 밖에서 읽는다');
        expect(e.value.contains('tx.set(avRef, payload, {merge: true})'), isTrue,
            reason: '${e.key} 가 트랜잭션 밖에서 쓴다');
      }
    });

    test('12-b counterpart를 트랜잭션 안에서 읽는다', () {
      // setAvailability는 inviteRegionKeys를, setInviteRegions는 dates를
      // 상대의 canonical 입력으로 읽는다. 그 읽기가 tx 밖이면 stale이다.
      final avTx = _after(setAv, 'await db.runTransaction', 1200);
      expect(avTx.contains('cur["inviteRegionKeys"]'), isTrue);
      expect(avTx.contains('cur["inviteEnabled"]'), isTrue);
      final rgTx = _after(setRegions, 'await db.runTransaction', 1200);
      expect(rgTx.contains('cur["dates"]'), isTrue);
    });

    test('12-c 트랜잭션 밖에 avRef read/write가 남아 있지 않다', () {
      for (final e in {'setAvailability': setAv, 'setInviteRegions': setRegions}
          .entries) {
        expect(e.value.contains('await avRef.get()'), isFalse,
            reason: '${e.key} 에 tx 밖 read가 남았다');
        expect(e.value.contains('await avRef.set('), isFalse,
            reason: '${e.key} 에 tx 밖 write가 남았다');
      }
    });

    test('12-d 불변식을 계산하는 식이 양쪽 동일하다', () {
      const formula =
          'regionKeys.flatMap((k) => dates.map((d) => srvInviteKey(k, d)))';
      expect(setAv.contains(formula), isTrue);
      expect(setRegions.contains(formula), isTrue);
    });

    test('12-e 클라이언트 재시도·후속 sync에 의존하지 않는다', () {
      final svc = _codeOf(_src(_availSvcPath));
      expect(svc.contains('retry'), isFalse);
      expect(svc.contains('callableSyncInviteKeys'), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 13. [FINAL] region coverage — 세종 포함 (§5, §6)
  // ═════════════════════════════════════════════════════════════
  group('R2.3-13 region coverage', () {
    test('13-a 광역자치단체 전수 — 코드 기준', () {
      final p = KoreanRegions.provinces;
      // 2026.7.1 전남광주통합특별시 출범 반영 → 17 → 16
      expect(p.length, 16, reason: p.join(', '));
      for (final want in const [
        '서울특별시', '부산광역시', '대구광역시', '인천광역시', '대전광역시', '울산광역시',
        '세종특별자치시', '경기도', '강원특별자치도', '충청북도', '충청남도',
        '전북특별자치도', '경상북도', '경상남도', '제주특별자치도', '전남광주통합특별시',
      ]) {
        expect(p.contains(want), isTrue, reason: '$want 누락');
      }
      final total = KoreanRegions.citiesByProvince.values
          .fold<int>(0, (a, b) => a + b.length);
      expect(total, 229);
    });

    test('13-b 세종의 시/군/구는 자기 자신 하나뿐 — 가짜를 만들지 않는다', () {
      // 이 형태가 "하위 단계 없음"의 canonical 표현이다.
      expect(KoreanRegions.citiesOf('세종특별자치시'), ['세종특별자치시']);
      expect(KoreanRegions.isSejong('세종특별자치시'), isTrue);
      // 다른 시/도는 모두 자기 자신이 아닌 하위 지역을 갖는다
      for (final e in KoreanRegions.citiesByProvince.entries) {
        if (e.key == '세종특별자치시') continue;
        expect(e.value.contains(e.key), isFalse, reason: '${e.key} 가 자기 자신을 담았다');
        expect(e.value.length, greaterThan(1), reason: e.key);
      }
    });

    test('13-c 세종의 canonical key는 시/도 자신이다', () {
      const want = '세종특별자치시|세종특별자치시';
      // picker가 만드는 값 (province == city)
      expect(regionKeyOf(province: '세종특별자치시', city: '세종특별자치시'), want);
      // province만 알아도 같은 key
      expect(regionKeyOf(city: '세종특별자치시'), want);
      // 축약형도
      expect(regionKeyOf(province: '세종', city: '세종특별자치시'), want);
    });

    test('13-d picker가 세종을 그렇게 만든다 — 규칙이 한 곳에서 나온다', () {
      final picker = _codeOf(_src('lib/widgets/inputs/home_region_picker_sheet.dart'));
      expect(picker.contains('KoreanRegions.isSejong(province)'), isTrue);
      expect(picker.contains('UserRegion(province: province, city: province)'),
          isTrue);
    });

    test('13-e 세종 사업장의 잘못 저장된 city가 매칭을 막지 않는다', () {
      // parseAddressCity('세종특별자치시 한누리대로 2130')은 시/도를 건너뛴 뒤
      // parts[1] = '한누리대로'를 city로 저장한다. 실측 확인된 동작이다.
      expect(FormatHelper.parseAddressCity('세종특별자치시 한누리대로 2130'),
          '한누리대로',
          reason: '이 동작이 바뀌면 아래 서버 보정의 전제가 달라진다');
      // 그래서 서버는 시/군/구 단계가 없는 시/도면 저장된 city를 쓰지 않는다.
      expect(cf.contains('provCities.length === 1 && provCities[0] === province'),
          isTrue);
      final f = _after(cfRaw, 'function srvWorkRegionKeyOfBusiness(', 1600);
      expect(f.contains('return srvRegionKeyOf(province, province);'), isTrue);
      // 클라이언트 정규화도 이름이 아니라 "하위 지역 없음"으로 판단한다
      expect(normalizeCityName('세종특별자치시', '한누리대로'), '세종특별자치시');
      expect(normalizeCityName('세종특별자치시', ''), '세종특별자치시');
    });

    test('13-f 세종 규칙이 다른 시/도로 새지 않는다', () {
      expect(normalizeCityName('경기도', '한누리대로'), isNull);
      expect(normalizeCityName('경기도', ''), isNull);
      expect(regionKeyOf(province: '경기도', city: ''), isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 14. [FINAL] region ceiling (§7, §8)
  // ═════════════════════════════════════════════════════════════
  group('R2.3-14 region ceiling', () {
    test('14-a 21개는 조용히 잘리지 않고 거부된다', () {
      final setRegions = _tsSliceOf(cfRaw,
          'export const callableSetInviteRegions',
          'export const callableSetAvailability');
      expect(setRegions.contains('.slice(0, MAX_INVITE_REGIONS)'), isFalse,
          reason: 'silent truncate가 남아 있다');
      expect(
          setRegions.contains(
              'if ((regions ?? []).length > MAX_INVITE_REGIONS)'),
          isTrue);
      expect(setRegions.contains('곳까지 선택할 수 있어요.'), isTrue);
    });

    test('14-b 클라이언트도 추가 시점에 막는다', () {
      final ui = _codeOf(_src(_settingsPath));
      expect(
          ui.contains('_regions.length >= InviteRegionPreference.maxRegions'),
          isTrue);
      expect(ui.contains('곳까지 선택할 수 있어요.'), isTrue);
    });

    test('14-c 모델 검증도 같은 상한을 쓴다', () {
      expect(InviteRegionPreference.maxRegions, 20);
      final over = InviteRegionPreference(
        enabled: true,
        regions: List.generate(21,
            (i) => UserRegion(province: '경기도', city: '수원시$i')),
      );
      expect(over.validationError(), isNotNull);
    });

    test('14-d 일괄 선택 기능을 만들지 않았다 (§7)', () {
      final ui = _src(_settingsPath);
      for (final banned in const ['전국', '전체 선택', 'selectAll', '모두 선택']) {
        expect(ui.contains(banned), isFalse, reason: '$banned 가 추가됐다');
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
