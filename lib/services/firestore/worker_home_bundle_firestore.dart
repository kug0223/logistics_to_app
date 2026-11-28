part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// [PERF-L9 · 판정289 §7 L9 · impl_15] 근로자 홈 1라운드 묶음 — callableGetWorkerHomeBundle 앱 쪽
// ═══════════════════════════════════════════════════════════
//
//   홈 1라운드가 따로 부르던 순수 읽기 callable(지원 · 월 근태 · 공개 공고 · 신분증 요청 · 계약 · 약관 준비)을
//   **한 번의 호출**로 받는다(콜드 노출·탈퇴 펜스 N→1 목표 · 실측 전이라 개선 수치는 말하지 않는다).
//
//   · 섹션별 의미 = 기존 개별 호출과 같다. 성공 섹션은 같은 해석 함수로 같은 모델이 되고, 실패 섹션은 그 섹션만
//     실패다(빈 목록/0/READY 합성 0). 지원·근태는 개별 호출처럼 **이전 캐시가 있으면 그것을 돌려준다**(stale ≠ 0).
//   · 기존 캐시·진행 중 공유와 하나다: TTL 안 캐시가 있는 섹션은 묶음에서 빼고 캐시를 쓴다. 묶음이 읽는 지원·월 근태는
//     진행 중 future 로 등록해 같은 순간의 일자리·일정 탭 호출이 합류한다. 결과는 같은 세대 규칙으로 캐시에 넣는다.
//   · uid · generation echo 가 요청과 다르면 응답 전체를 버린다(다른 계정/옛 세대의 늦은 응답).
//   · 구서버 호환: 묶음 함수 자체가 not-found/unimplemented 면 이 프로세스에서는 묶음을 끄고(로그 1회)
//     같은 호출 안에서 기존 개별 호출로 폴백한다. 그 밖의 묶음 전체 실패는 요청한 모든 섹션의 실패로 본다
//     (개별 호출이 모두 실패한 것과 같은 의미 · 같은 오류를 두 번 기다리지 않는다).
//   · 서버는 섹션 timeout 없이 allSettled 로 모두 기다린다 — 가장 느린 섹션이 응답 시각을 정한다. 홈 1라운드는
//     원래도 이 섹션들을 Future.wait 로 모두 기다렸으므로 화면 경계(P1 첫 표시)는 같다. 그 판단은 impl_15 보고 §4.

/// 한 섹션의 결과 — [value] 또는 [error] 하나.
class HomeBundleOutcome<T> {
  const HomeBundleOutcome.ok(T this.value) : error = null;
  const HomeBundleOutcome.fail(Object this.error) : value = null;
  final T? value;
  final Object? error;
  bool get ok => error == null;
}

/// 서버가 섹션 실패로 돌려준 것(`{ok:false, code[, message]}`) — 개별 호출의 FirebaseFunctionsException 과 같은 자리.
class HomeBundleSectionError implements Exception {
  const HomeBundleSectionError(this.section, this.code, [this.message]);
  final String section;
  final String code;
  final String? message;
  @override
  String toString() => 'HomeBundleSectionError($section, $code)';
}

/// 근로자 홈 1라운드 결과(요청한 것만 채워진다 · 약관은 [includeLegal] 일 때만).
class WorkerHomeBundle {
  WorkerHomeBundle({
    required this.applications,
    required this.monthlyAttendances,
    required this.publishedTOs,
    required this.idCardRequests,
    required this.contracts,
    this.legalReadiness,
    required this.viaBundle,
  });

  final HomeBundleOutcome<List<ApplicationModel>> applications;

  /// 'YYYY-M' → 그 달 근태.
  final Map<String, HomeBundleOutcome<List<AttendanceModel>>> monthlyAttendances;
  final HomeBundleOutcome<List<TOModel>> publishedTOs;
  final HomeBundleOutcome<List<IdCardAccessRequestModel>> idCardRequests;
  final HomeBundleOutcome<List<EmploymentContractModel>> contracts;
  final HomeBundleOutcome<LegalReadiness>? legalReadiness;

  /// 묶음 호출이 실제로 쓰였는가(false = 구서버 폴백 또는 전부 캐시).
  final bool viaBundle;

  static String monthKey(int year, int month) => '$year-$month';
}

// ── 해석 — 개별 호출과 **같은 함수**(개별 fetch 도 이 함수를 쓴다) ──────────────────────
List<ApplicationModel> _parseMyApplications(Map data) => (data['applications'] as List? ?? [])
    .whereType<Map>()
    .map((m) {
      final raw = _cfHydrate(Map<String, dynamic>.from(m));
      final id = raw.remove('id') as String? ?? '';
      return ApplicationModel.tryFromMap(raw, id);
    })
    .whereType<ApplicationModel>()
    .toList()
  ..sort((a, b) => b.appliedAt.compareTo(a.appliedAt));

List<AttendanceModel> _parseMyAttendanceItems(List? items) => (items ?? const [])
    .whereType<Map>()
    .map((e) {
      final m = Map<String, dynamic>.from(e);
      final id = m.remove('id') as String? ?? '';
      return AttendanceModel.tryFromMap(m, id);
    })
    .whereType<AttendanceModel>()
    .toList();

List<TOModel> _parsePublishedTOs(Map data) => (data['tos'] as List? ?? [])
    .whereType<Map>()
    .map((m) {
      final raw = _cfHydrate(Map<String, dynamic>.from(m));
      final id = raw.remove('id') as String? ?? '';
      return TOModel.tryFromMap(raw, id);
    })
    .whereType<TOModel>()
    .toList();

List<IdCardAccessRequestModel> _parseMyIdCardRequests(Map data) => ((data['requests'] as List? ?? [])
    .whereType<Map>()
    .map((m) {
      final raw = _cfHydrate(Map<String, dynamic>.from(m));
      final id = raw.remove('id') as String? ?? '';
      return IdCardAccessRequestModel.tryFromMap(raw, id);
    })
    .whereType<IdCardAccessRequestModel>()
    .toList()
  ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt)));

/// `ContractService.getByWorker` 의 해석과 같은 규칙(그 파일은 계약 담당 소유라 손대지 않고 같은 줄을 둔다 —
///   시험 WHB-APP-PARSE 가 두 해석의 일치를 본다).
List<EmploymentContractModel> _parseMyContracts(Map? data) {
  if (data == null) return [];
  final rawItems = (data['items'] as List<dynamic>? ?? []);
  return rawItems
      .whereType<Map>()
      .map((e) {
        final m = Map<String, dynamic>.from(e);
        final id = m.remove('id') as String? ?? '';
        return EmploymentContractModel.tryFromMap(m, id);
      })
      .whereType<EmploymentContractModel>()
      .toList();
}

/// [impl_15] 시험용 — 해석 함수를 밖에서 같은 입력으로 비교한다.
@visibleForTesting
List<EmploymentContractModel> debugParseMyContracts(Map? data) => _parseMyContracts(data);

extension WorkerHomeBundleFirestore on FirestoreService {
  /// 이 프로세스에서 묶음 함수가 없다고 확인됐는가(구서버). 다시 켜지 않는다(재시작 때 다시 시도).
  static bool _bundleUnsupported = false;

  /// 시험·진단용.
  static bool get debugBundleUnsupported => _bundleUnsupported;
  @visibleForTesting
  static void debugResetBundleSupport() => _bundleUnsupported = false;

  /// 근로자 홈 1라운드. [months] = 이번 KST 달(+ 1일이면 지난달) · 최대 2.
  Future<WorkerHomeBundle> getWorkerHomeBundle({
    required String uid,
    required String generation,
    required List<({int year, int month})> months,
    bool includeLegal = false,
  }) async {
    assert(months.isNotEmpty && months.length <= 2);
    final now = DateTime.now();

    // ── 1. 캐시·진행 중 공유 — TTL 안 값이 있거나 이미 날아가는 요청이 있으면 묶음에서 뺀다 ──────
    Future<List<ApplicationModel>>? appsJoin;
    final appsCached = _myApplicationsCache[uid];
    final appsTs = _myApplicationsCacheTimestamps[uid];
    if (appsCached != null && appsTs != null && now.difference(appsTs) < FirestoreService._myApplicationsCacheTTL) {
      appsJoin = Future.value(appsCached);
    } else {
      appsJoin = _myApplicationsInFlight[uid];
    }
    final attJoin = <String, Future<List<AttendanceModel>>>{};
    final attNeed = <({int year, int month})>[];
    for (final m in months) {
      final key = '${uid}_${m.year}_${m.month}';
      final c = _myAttendanceCache[key];
      final ts = _myAttendanceCacheTimestamps[key];
      if (c != null && ts != null && now.difference(ts) < FirestoreService._myAttendanceCacheTTL) {
        attJoin[key] = Future.value(c);
      } else if (_myAttendanceInFlight[key] != null) {
        attJoin[key] = _myAttendanceInFlight[key]!;
      } else {
        attNeed.add(m);
      }
    }
    List<TOModel>? tosCached;
    if (TOFirestore._cachedPublishedTOs != null &&
        TOFirestore._cachedPublishedTOsAt != null &&
        now.difference(TOFirestore._cachedPublishedTOsAt!) < TOFirestore._publishedTOsCacheTTL) {
      tosCached = TOFirestore._cachedPublishedTOs;
    }

    final sections = <String>[
      if (appsJoin == null) 'applications',
      if (attNeed.isNotEmpty) 'monthlyAttendances',
      if (tosCached == null) 'publishedTOs',
      'idCardRequests',
      'contracts',
      if (includeLegal) 'legalReadiness',
    ];

    // ── 2. 묶음이 읽는 지원·근태를 진행 중으로 등록 — 같은 순간의 다른 탭 호출이 합류한다 ──────────
    final appsGen = _myApplicationsGeneration[uid] ?? 0;
    final attGen = _myAttendanceGeneration[uid] ?? 0;
    Completer<List<ApplicationModel>>? appsC;
    if (appsJoin == null) {
      appsC = Completer<List<ApplicationModel>>();
      final f = appsC.future;
      f.ignore(); // 소비자가 없을 때 처리 안 된 오류로 남지 않게
      _myApplicationsInFlight[uid] = f;
      unawaited(f.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        if (identical(_myApplicationsInFlight[uid], f)) _myApplicationsInFlight.remove(uid);
      }));
    }
    final attC = <String, Completer<List<AttendanceModel>>>{};
    for (final m in attNeed) {
      final key = '${uid}_${m.year}_${m.month}';
      final c = Completer<List<AttendanceModel>>();
      final f = c.future;
      f.ignore();
      _myAttendanceInFlight[key] = f;
      unawaited(f.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        if (identical(_myAttendanceInFlight[key], f)) _myAttendanceInFlight.remove(key);
      }));
      attC[key] = c;
    }

    // ── 3. 호출(구서버면 개별 폴백 · 전체 실패면 요청 섹션 전부 실패) ────────────────────────
    Map? sectionsData;
    Object? wholeError;
    var viaBundle = false;
    var fellBack = false;
    if (!_bundleUnsupported) {
      try {
        final res = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
            .httpsCallable('callableGetWorkerHomeBundle',
                options: HttpsCallableOptions(timeout: const Duration(seconds: 30)))
            .call<Map<String, dynamic>>({
          'sections': sections,
          'generation': generation,
          if (attNeed.isNotEmpty)
            'monthlyAttendances': {
              'months': [for (final m in attNeed) {'year': m.year, 'month': m.month}],
            },
        });
        final data = res.data;
        // 다른 계정·옛 세대의 늦은 응답은 버린다.
        if (data['version'] != 1 || data['uid'] != uid || '${data['generation']}' != generation) {
          wholeError = StateError('workerHomeBundle stale or foreign response');
        } else {
          sectionsData = data['sections'] as Map?;
          viaBundle = true;
        }
      } on FirebaseFunctionsException catch (e) {
        if (e.code == 'not-found' || e.code == 'unimplemented') {
          _bundleUnsupported = true;
          fellBack = true;
          debugPrint('ℹ️ [홈 묶음] 서버에 묶음 함수가 없다 — 이 실행에서는 개별 호출로 폴백(1회 기록)');
        } else {
          wholeError = e;
        }
      } catch (e) {
        wholeError = e;
      }
    } else {
      fellBack = true;
    }

    // ── 4. 섹션 결과 만들기 ────────────────────────────────────────────────────
    HomeBundleOutcome<T> section<T>(String name, T Function(Map data) parse) {
      if (wholeError != null) return HomeBundleOutcome<T>.fail(wholeError);
      final s = sectionsData?[name];
      if (s is! Map) return HomeBundleOutcome.fail(HomeBundleSectionError(name, 'missing'));
      if (s['ok'] == true) {
        try {
          return HomeBundleOutcome.ok(parse((s['data'] as Map?) ?? const {}));
        } catch (e) {
          return HomeBundleOutcome.fail(e);
        }
      }
      return HomeBundleOutcome.fail(HomeBundleSectionError(name, '${s['code'] ?? 'unknown'}', s['message'] as String?));
    }

    // [폴백] 개별 호출은 **동시에** 출발시킨다 — 섹션마다 앞 호출을 기다리면 원래 개별 경로(Future.wait)보다 느려진다.
    Future<HomeBundleOutcome<T>> wrap<T>(Future<T> f) => f.then<HomeBundleOutcome<T>>(
        (v) => HomeBundleOutcome<T>.ok(v), onError: (Object e) => HomeBundleOutcome<T>.fail(e));
    Future<List<ApplicationModel>>? fbApps;
    final fbAtt = <String, Future<List<AttendanceModel>>>{};
    Future<HomeBundleOutcome<List<TOModel>>>? fbTos;
    Future<HomeBundleOutcome<List<IdCardAccessRequestModel>>>? fbId;
    Future<HomeBundleOutcome<List<EmploymentContractModel>>>? fbCon;
    if (fellBack) {
      if (appsJoin == null) {
        fbApps = _fetchMyApplications(uid, appsCached, appsGen);
        appsC!.complete(fbApps);
      }
      for (final m in attNeed) {
        final key = '${uid}_${m.year}_${m.month}';
        final f = _fetchMyMonthlyAttendances(
            cacheKey: key, userId: uid, year: m.year, month: m.month, cached: _myAttendanceCache[key], generation: attGen);
        fbAtt[key] = f;
        attC[key]!.complete(f);
      }
      if (tosCached == null) fbTos = wrap(getPublishedTOs());
      fbId = wrap(getPendingIdCardRequestsForUser(uid));
      fbCon = wrap(ContractService().getByWorker(uid));
    }

    // 지원
    late final HomeBundleOutcome<List<ApplicationModel>> appsOut;
    if (appsJoin != null) {
      appsOut = await appsJoin.then<HomeBundleOutcome<List<ApplicationModel>>>(
            (v) => HomeBundleOutcome<List<ApplicationModel>>.ok(v), onError: (Object e) => HomeBundleOutcome<List<ApplicationModel>>.fail(e));
    } else if (fellBack) {
      appsOut = await wrap(fbApps!);
    } else {
      var o = section<List<ApplicationModel>>('applications', _parseMyApplications);
      if (o.ok) {
        if ((_myApplicationsGeneration[uid] ?? 0) == appsGen) {
          _myApplicationsCache[uid] = o.value!;
          _myApplicationsCacheTimestamps[uid] = DateTime.now();
        }
      } else {
        debugPrint('내 지원 내역 조회 실패(묶음): ${o.error}');
        if (appsCached != null) o = HomeBundleOutcome.ok(appsCached); // 개별 호출과 같다 — 이전 값이 있으면 그것
      }
      if (o.ok) {
        appsC!.complete(o.value!);
      } else {
        appsC!.completeError(o.error!);
      }
      appsOut = o;
    }

    // 월 근태
    final attOut = <String, HomeBundleOutcome<List<AttendanceModel>>>{};
    for (final m in months) {
      final key = '${uid}_${m.year}_${m.month}';
      final mk = WorkerHomeBundle.monthKey(m.year, m.month);
      final join = attJoin[key];
      if (join != null) {
        attOut[mk] = await join.then<HomeBundleOutcome<List<AttendanceModel>>>(
            (v) => HomeBundleOutcome<List<AttendanceModel>>.ok(v), onError: (Object e) => HomeBundleOutcome<List<AttendanceModel>>.fail(e));
        continue;
      }
      final cached = _myAttendanceCache[key];
      if (fellBack) {
        attOut[mk] = await wrap(fbAtt[key]!);
        continue;
      }
      var o = section<List<AttendanceModel>>('monthlyAttendances', (d) {
        for (final x in (d['months'] as List? ?? const [])) {
          if (x is Map && x['year'] == m.year && x['month'] == m.month) {
            return _parseMyAttendanceItems(x['items'] as List?);
          }
        }
        throw HomeBundleSectionError('monthlyAttendances', 'month-missing');
      });
      if (o.ok) {
        if ((_myAttendanceGeneration[uid] ?? 0) == attGen) {
          _myAttendanceCache[key] = o.value!;
          _myAttendanceCacheTimestamps[key] = DateTime.now();
        }
      } else {
        debugPrint('❌ 월별 출근 기록 조회 실패(묶음): ${o.error}');
        if (cached != null) o = HomeBundleOutcome.ok(cached); // 개별 호출과 같다
      }
      if (o.ok) {
        attC[key]!.complete(o.value!);
      } else {
        attC[key]!.completeError(o.error!);
      }
      attOut[mk] = o;
    }

    // 공개 공고
    late final HomeBundleOutcome<List<TOModel>> tosOut;
    if (tosCached != null) {
      tosOut = HomeBundleOutcome.ok(tosCached);
    } else if (fellBack) {
      tosOut = await fbTos!;
    } else {
      tosOut = section<List<TOModel>>('publishedTOs', _parsePublishedTOs);
      if (tosOut.ok) {
        TOFirestore._cachedPublishedTOs = tosOut.value;
        TOFirestore._cachedPublishedTOsAt = now;
      } else {
        debugPrint('❌ [TO] 공개 공고 목록 조회 실패(묶음): ${tosOut.error}');
      }
    }

    // 신분증 요청 · 계약 · 약관
    final idOut = fellBack
        ? await fbId!
        : section<List<IdCardAccessRequestModel>>('idCardRequests', _parseMyIdCardRequests);
    final conOut = fellBack
        ? await fbCon!
        : section<List<EmploymentContractModel>>('contracts', _parseMyContracts);
    HomeBundleOutcome<LegalReadiness>? legalOut;
    if (includeLegal) {
      legalOut = fellBack
          ? null // 폴백이면 약관 카드가 자기 호출로 읽는다(호출부가 null 을 '직접 읽기'로 처리)
          : section<LegalReadiness>('legalReadiness', (d) => LegalReadiness.fromServer(d));
    }

    return WorkerHomeBundle(
      applications: appsOut,
      monthlyAttendances: attOut,
      publishedTOs: tosOut,
      idCardRequests: idOut,
      contracts: conOut,
      legalReadiness: legalOut,
      viaBundle: viaBundle,
    );
  }
}
