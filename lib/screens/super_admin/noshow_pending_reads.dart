/// [NS-PENDING-DEST] 노쇼 원장 보류 처리 화면이 서버와 주고받는 단 하나의 경계.
///
/// 보류 문서(`noshow_ledger_pending`)는 규칙상 클라이언트가 읽을 수 없다 —
/// 조회·해소 모두 기존 `callableMigrateNoShowLedger`(슈퍼관리자 전용)를 쓴다.
///   조회: `{uids:[uid], dryRun:true, includePending:true}`
///   해소: `{uids:[uid], dryRun:false, includePending:true, resolution, reason,
///          requestId, expectedPending:{id, occurrence}}`
/// 벌점 원장은 서버만 쓴다. production 은 `reads: null` 이라 실제 호출을 쓴다.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class NoShowPendingReads {
  const NoShowPendingReads({required this.migrate, this.targetLabel});

  /// callableMigrateNoShowLedger 원본 응답(Map). 실패는 FirebaseFunctionsException 그대로.
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data) migrate;

  /// [.56] 대상 근로자를 사람이 알아볼 수 있게 — 이름(@아이디). SA 는 users 문서를 읽을 수 있다(규칙).
  ///   보류·알림에는 uid 만 있어서, 화면이 누구에 대한 결정인지 말하지 못했다. 실패하면 null(화면이 '확인하지 못함').
  final Future<String?> Function(String uid)? targetLabel;

  factory NoShowPendingReads.of() => NoShowPendingReads(
        targetLabel: (uid) async {
          final d = (await FirebaseFirestore.instance.collection('users').doc(uid).get()).data();
          if (d == null) return null;
          final name = (d['name'] as String?)?.trim();
          final username = (d['username'] as String?)?.trim();
          if ((name ?? '').isEmpty && (username ?? '').isEmpty) return null;
          return [if ((name ?? '').isNotEmpty) name, if ((username ?? '').isNotEmpty) '(@$username)'].join(' ');
        },
        migrate: (data) async {
          final callable =
              FirebaseFunctions.instanceFor(region: 'asia-northeast3')
                  .httpsCallable('callableMigrateNoShowLedger',
                      options: HttpsCallableOptions(
                          timeout: const Duration(seconds: 60)));
          final result = await callable.call<dynamic>(data);
          // 안쪽 map 은 Map<Object?, Object?> 로 온다 — 캐스트하지 않고 복사한다.
          final top = result.data;
          return top is Map ? _deepMap(top) : <String, dynamic>{};
        },
      );
}

Map<String, dynamic> _deepMap(Map m) =>
    m.map((k, v) => MapEntry(k.toString(), _deep(v)));

Object? _deep(Object? v) {
  if (v is Map) return _deepMap(v);
  if (v is List) return v.map(_deep).toList();
  return v;
}
