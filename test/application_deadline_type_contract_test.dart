// [R6.5] 마감 시각은 저장되는 순간에 타입이 정해진다.
//
//   writer 들이 하나같이 "숫자면 바꾸고 아니면 그대로 둔다" 였다.
//   그래서 map·문자열이 그대로 저장됐고, 잘못됐다는 사실은 한참 뒤
//   지원 시점에 wdDeadlineTs.toDate is not a function → INTERNAL 로 터졌다.
//   쓰는 사람이 고칠 수 있는 입력 오류를 내부 오류로 만들지 않는다.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _src() => File('functions/src/index.ts').readAsStringSync();

/// 주석으로 시작하는 줄만 제거한다 (JSDoc 은 남는다).
String _codeOf(String raw) => raw
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// 그룹 수집 시점에도 불리므로 expect 대신 예외로 실패시킨다.
String _sliceOf(String raw, String from, String to) {
  final i = raw.indexOf(from);
  if (i < 0) throw StateError('시작 표지를 찾지 못함: $from');
  final j = raw.indexOf(to, i + from.length);
  if (j < 0) throw StateError('끝 표지를 찾지 못함: $to');
  return raw.substring(i, j);
}

void main() {
  final raw = _src();
  final norm = _sliceOf(raw, 'function srvNormalizeTimestampField(',
      'function srvNormalizeWorkDetailTimestamps(');
  final nf = _flat(_codeOf(norm));

  group('AD-1 — canonical 타입은 Timestamp 다', () {
    test('AD-10 숫자(ms)는 Timestamp 로 변환한다', () {
      expect(nf, contains('typeof v === "number" && Number.isFinite(v)'));
      expect(nf, contains('admin.firestore.Timestamp.fromMillis(v)'));
    });

    test('AD-11 이미 Timestamp 면 그대로 둔다', () {
      expect(nf, contains('v instanceof admin.firestore.Timestamp'));
    });

    test('AD-12 그 밖의 타입은 거절한다', () {
      expect(nf, contains('throw new HttpsError('));
      expect(nf, contains('"invalid-argument"'));
      expect(nf, contains('형식이 올바르지 않습니다'));
    });

    test('AD-13 INTERNAL 로 만들지 않는다', () {
      expect(nf, isNot(contains('"internal"')));
      expect(nf, isNot(contains('"unknown"')));
    });
  });

  group('AD-2 — 없음과 잘못된 타입은 다르다', () {
    test('AD-20 undefined / null 은 그대로 둔다', () {
      expect(nf, contains('if (v === undefined) return undefined'));
      expect(nf, contains('if (v === null) return null'));
    });

    test('AD-21 없는 값을 지어내지 않는다', () {
      expect(nf, isNot(contains('Timestamp.now()')));
      expect(nf, isNot(contains('?? admin.firestore.Timestamp')));
    });
  });

  group('AD-3 — workDetail 배열도 같은 기준', () {
    final wdn = _sliceOf(raw, 'function srvNormalizeWorkDetailTimestamps(',
        'function srvReadTimestampOrThrow(');
    final f = _flat(_codeOf(wdn));

    test('AD-30 세 날짜 필드를 모두 본다', () {
      expect(_flat(raw), contains(
          'const WD_TIMESTAMP_FIELDS = [ "applicationDeadline", "closedAt", "emergencyOpenedAt", ]'));
      expect(f, contains('for (const f of WD_TIMESTAMP_FIELDS)'));
    });

    test('AD-31 원본을 바꾸지 않는다', () {
      expect(f, contains('const out: Record<string, unknown> = {...wd}'));
    });

    test('AD-32 하나라도 틀리면 전체를 거절한다 — 부분 저장 없음', () {
      // 필드별 try/catch 로 개별 통과시키지 않는다
      expect(_codeOf(wdn), isNot(contains('catch')));
    });
  });

  group('AD-4 — 네 writer 가 모두 같은 계약을 쓴다', () {
    test('AD-40 공고 생성 — TO 레벨 + workDetails', () {
      final c = _sliceOf(raw, 'export const callableCreateTO = onCall(',
          'interface _ToMatchSlot');
      final f = _flat(_codeOf(c));
      expect(f, contains('srvNormalizeTimestampField(finalData[field], field)'));
      expect(f, contains('srvNormalizeWorkDetailTimestamps(finalData.workDetails)'));
      // 옛 "숫자면 바꾸고 아니면 통과" 패턴이 남아 있지 않다
      expect(f, isNot(contains('if (typeof v === "number") { finalData[field] =')));
    });

    test('AD-41 슬롯 생성', () {
      final c = _sliceOf(raw, 'export const callableCreateFlexSlots = onCall(',
          'export const callableGetAdminAttendances');
      final f = _flat(_codeOf(c));
      expect(f, contains('const normalizedFlexWDs = srvNormalizeWorkDetailTimestamps(workDetails)'));
      expect(f, contains('normalizedFlexWDs.map((wd)'));
    });

    test('AD-42 공고 수정 — 날짜 필드 + workDetails', () {
      final c = _sliceOf(raw, 'export const callableUpdateTO = onCall(',
          'export const callableUpdateSlotWorkDetails = onCall(');
      final f = _flat(_codeOf(c));
      expect(f, contains('const norm = srvNormalizeTimestampField(value, key)'));
      expect(f, contains('finalUpdates[key] = srvNormalizeWorkDetailTimestamps(value)'));
    });

    test('AD-43 슬롯 수정 — Ms 필드와 Timestamp 필드 양쪽', () {
      final c = _sliceOf(raw, 'export const callableUpdateSlotWorkDetails = onCall(',
          'const checkDuplicateIds =');
      final f = _flat(_codeOf(c));
      expect(f, contains('srvNormalizeTimestampField(v, "applicationDeadlineMs")'));
      expect(f, contains('srvNormalizeWorkDetailTimestamps(wds.map((d)'));
    });
  });

  group('AD-5 — reader 는 fail-closed 다', () {
    final rd = _sliceOf(raw, 'function srvReadTimestampOrThrow(',
        'function srvAssertUniqueWorkDetailIds(');
    final f = _flat(_codeOf(rd));

    test('AD-50 손상된 값을 "마감 없음" 으로 넘기지 않는다', () {
      expect(f, contains('throw new HttpsError('));
      expect(f, contains('정보가 손상되어 처리할 수 없습니다'));
      expect(f, contains('"failed-precondition"'));
    });

    test('AD-51 없음은 그대로 없음이다', () {
      expect(f, contains('if (v === undefined || v === null) return null'));
    });

    test('AD-52 지원 경로의 네 곳이 모두 이 guard 를 쓴다', () {
      final apply = _sliceOf(raw, 'export const callableApplyToTO = onCall(',
          'export const callableAcceptTOInvitation');
      final af = _codeOf(apply);
      expect('srvReadTimestampOrThrow('.allMatches(af).length, 4);
      // 직접 캐스팅 후 .toDate() 하는 경로가 남아 있지 않다
      expect(_flat(af), isNot(contains(
          'as admin.firestore.Timestamp | undefined; if (wdDeadlineTs && wdDeadlineTs.toDate()')));
    });
  });

  group('AD-6 — 기존 정책은 건드리지 않았다', () {
    test('AD-60 슬롯 생성의 마감 계산 규칙 그대로', () {
      final c = _sliceOf(raw, 'export const callableCreateFlexSlots = onCall(',
          'export const callableGetAdminAttendances');
      final f = _flat(_codeOf(c));
      expect(f, contains('deadlineType === "HOURS_BEFORE" && typeof wd.startTime === "string"'));
      expect(f, contains('deadlineType === "FIXED_TIME" && fixedDeadline'));
      expect(f, contains('fixedDeadline이 슬롯 시작 시간'));
    });

    test('AD-61 마감 없는 공고가 여전히 가능하다', () {
      // slotDeadline 이 없으면 필드를 쓰지 않는다
      final c = _sliceOf(raw, 'export const callableCreateFlexSlots = onCall(',
          'export const callableGetAdminAttendances');
      expect(_flat(_codeOf(c)), contains('if (slotDeadline) slotData.applicationDeadline = slotDeadline'));
    });

    test('AD-62 슬롯 수정의 마감 삭제 경로 유지', () {
      final c = _sliceOf(raw, 'export const callableUpdateSlotWorkDetails = onCall(',
          'export const callableExtendTOPosting');
      final f = _flat(_codeOf(c));
      expect(f, contains('slotUpdate["applicationDeadline"] = admin.firestore.FieldValue.delete()'));
    });
  });
}
