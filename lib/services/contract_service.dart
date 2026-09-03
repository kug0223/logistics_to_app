import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/core/application_model.dart';
import '../models/core/business_model.dart';
import '../models/core/to_model.dart';
import '../models/core/contract_template_model.dart';
import '../models/core/employment_contract_model.dart';
import '../models/core/notification_model.dart';
import '../models/core/user_model.dart';
import '../models/core/work_detail_data.dart';
import '../utils/format_helper.dart';
import 'firestore_service.dart';

class ContractService {
  final _db = FirebaseFirestore.instance;
  final _firestoreService = FirestoreService();

  // ── 핵심: 번들링 생성/추가 ─────────────────────────────────────

  /// 확정 시 호출. 동일 (toId + workDetailId + workerId) 계약서가 있으면
  /// 슬롯 추가, 없으면 새 계약서 생성.
  /// 장기 근무는 기존처럼 단일 계약서 생성.
  ///
  /// [C01 동시성 설계]
  /// 두 관리자가 동시에 같은 근무자에게 계약서를 생성하는 경우:
  /// - 단기: _findBundle이 둘 다 null을 반환 → _createNew가 둘 다 isNewUnsaved:true 객체 반환.
  ///   이후 saveEmployerSignature에서 각자 다른 doc ref로 트랜잭션 set을 실행하므로
  ///   중복 계약서 2개가 생성될 수 있다 (TOCTOU).
  ///   방어책: saveEmployerSignature 진입 전 applicationId 기준으로 재조회하여 이미 존재하면
  ///   기존 계약에 슬롯 추가로 전환. 이 재조회-생성 사이도 race 가능하나, 실제로
  ///   두 관리자가 밀리초 단위로 동일 지원서에 계약서를 생성하는 빈도는 매우 낮으므로
  ///   last-write-wins 허용(의도된 설계). 중복 발생 시 UI에서 경고 표시.
  ///
  /// - 장기: 계약서가 근무자당 1개여야 하는 동일 문제. 마찬가지로 빈도 낮아 허용.
  ///
  /// 완전한 방어를 위해서는 Cloud Functions에서 트랜잭션으로 처리해야 하나,
  /// 현재 클라이언트 단계에서는 위 설계 수준으로 충분하다고 판단.
  Future<EmploymentContractModel> findOrCreateContract({
    required ApplicationModel application,
    required BusinessModel business,
    required UserModel worker,
    required WorkDetailData workDetail,
    List<ContractArticle> articles = const [],
    String? templateId,
  }) async {
    final isLong = application.isLongTermApplication;
    final toId = application.toId ?? '';
    final workDetailId = application.workDetailId ?? workDetail.id;

    if (!isLong) {
      // 단기: 기존 번들 계약서 탐색 (articles는 최초 생성 시에만 적용)
      final existing = await _findBundle(
        toId: toId,
        workDetailId: workDetailId,
        workerId: worker.uid,
        businessId: business.id,
      );
      // [K-001] pendingEmployer 상태에서만 슬롯 추가 허용
      // — pendingWorker 이상(사업주 서명 완료)은 슬롯 추가 불가: 서명 무결성 보호
      if (existing != null &&
          existing.status == ContractStatus.pendingEmployer) {
        return _addSlot(existing, application, workDetail);
      }
    }

    // 신규 생성 (장기 또는 첫 번째 단기 슬롯)
    return _createNew(
      application: application,
      business: business,
      worker: worker,
      workDetail: workDetail,
      toId: toId,
      workDetailId: workDetailId,
      articles: articles,
      templateId: templateId,
    );
  }

  /// 미리보기 전용 계약서 생성 — 번들 탐색 없이 항상 isNewUnsaved:true 반환.
  /// Firestore에 저장되지 않으므로 미리보기 후 버려도 안전하다.
  Future<EmploymentContractModel> buildPreviewContract({
    required ApplicationModel application,
    required BusinessModel business,
    required UserModel worker,
    required WorkDetailData workDetail,
    List<ContractArticle> articles = const [],
  }) async {
    return _createNew(
      application: application,
      business: business,
      worker: worker,
      workDetail: workDetail,
      toId: application.toId ?? '',
      workDetailId: application.workDetailId ?? workDetail.id,
      articles: articles,
    );
  }

  // ── 서명 저장 ────────────────────────────────────────────────

  /// 사업주 서명 → 근무자 서명 대기로 전환
  /// [SEC-EMPLOYER-SIG] callableFinalizeEmployerSignature CF 경유:
  ///   Storage Admin SDK 업로드 + 소속 검증 서버 강제.
  ///   storage.rules signature_employer.png → if false (클라이언트 직접 업로드 차단).
  Future<EmploymentContractModel> saveEmployerSignature({
    required EmploymentContractModel contract,
    required Uint8List signatureBytes,
  }) async {
    // 클라이언트 사전 가드 (UX용) — CF에서 재검증
    if (contract.status == ContractStatus.voided) {
      throw Exception('무효 처리된 계약서에는 서명할 수 없습니다');
    }
    if (contract.status == ContractStatus.completed) {
      throw Exception('이미 완료된 계약서입니다');
    }
    if (contract.employerSignatureUrl != null && contract.employerSignatureUrl!.isNotEmpty) {
      throw Exception('이미 사업주 서명이 완료된 계약서입니다');
    }

    final signatureBase64 = base64Encode(signatureBytes);
    final Map<String, dynamic> cfData = {
      'contractId': contract.id,
      'signatureBase64': signatureBase64,
    };

    if (contract.isNewUnsaved) {
      // 신규 계약서: 계약서 데이터를 CF에 전달 (타임스탬프·서명 필드는 CF가 서버 강제)
      final contractMap = contract.toMap();
      for (final key in ['employerSignatureUrl', 'employerSignatureHash',
          'employerSignedAt', 'createdAt', 'updatedAt']) {
        contractMap.remove(key);
      }
      cfData['isNewUnsaved'] = true;
      cfData['contractData'] = contractMap;
    }

    final result = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableFinalizeEmployerSignature',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)))
        .call(cfData);

    final cfMap = result.data as Map<dynamic, dynamic>?;
    final url = cfMap?['employerSignatureUrl'] as String? ?? '';
    if (url.isEmpty) throw Exception('CF 응답에 employerSignatureUrl 없음');
    final now = DateTime.now();
    final updated = contract.copyWith(
      status: ContractStatus.pendingWorker,
      employerSignatureUrl: url,
      employerSignedAt: now,
      updatedAt: now,
    );

    // [FCM-FIX 2026-08-10] 클라이언트 알림 발송 제거 — callableFinalizeEmployerSignature CF 내부로 이전
    // CF가 계약서 저장 직후 notifications 문서를 직접 write하므로 원자성 보장됨
    // (이전 클라이언트 createNotification 호출은 CF 반환 후 크래시 시 영구 누락 위험이 있었음)

    return updated;
  }

  /// 근무자 서명 → 완료 상태로 전환
  Future<EmploymentContractModel> saveWorkerSignature({
    required EmploymentContractModel contract,
    required Uint8List signatureBytes,
    required Uint8List pdfBytes,
  }) async {
    if (contract.status == ContractStatus.voided) {
      throw Exception('무효 처리된 계약서에는 서명할 수 없습니다');
    }
    if (contract.status == ContractStatus.completed) {
      throw Exception('이미 완료된 계약서입니다');
    }
    // H-5: 사업주가 아직 서명하지 않은 상태에서는 근무자가 서명할 수 없음
    if (contract.status == ContractStatus.pendingEmployer) {
      throw Exception('사업주 서명이 완료되기 전에는 근무자가 서명할 수 없습니다.');
    }
    if (contract.workerSignatureUrl != null && contract.workerSignatureUrl!.isNotEmpty) {
      throw Exception('이미 근무자 서명이 완료된 계약서입니다');
    }

    // [SEC-WORKER-SIG] CF Admin SDK로 Storage 업로드 전환 (storage.rules: if false)
    // 클라이언트가 직접 업로드하지 않고 base64로 CF에 전달 → CF가 Admin SDK로 업로드
    final sigBase64 = base64Encode(signatureBytes);
    final pdfBase64 = base64Encode(pdfBytes);
    final HttpsCallableResult cfResult;
    try {
      cfResult = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableFinalizeWorkerSignature',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 60)))
          .call({
            'contractId': contract.id,
            'signatureBase64': sigBase64,
            'pdfBase64': pdfBase64,
          });
    } catch (e) {
      // CF 실패 → CF 내부에서 Storage 정리 완료.
      rethrow;
    }

    // CF 응답에서 URL 추출 (CF가 Admin SDK로 업로드 후 반환한 실제 Storage URL)
    final cfData = cfResult.data as Map<Object?, Object?>?;
    final cfPdfUrl = cfData?['pdfUrl'] as String? ?? '';
    final cfSigUrl = cfData?['sigUrl'] as String? ?? '';
    // saveEmployerSignature와 동일한 가드: 빈 URL은 CF 응답 이상 — completed 설정 금지
    if (cfSigUrl.isEmpty) throw Exception('CF 응답에 sigUrl 없음');
    if (cfPdfUrl.isEmpty) throw Exception('CF 응답에 pdfUrl 없음');

    final workerNow = DateTime.now(); // 로컬 변수 분리 — nullable ! 방지
    final updated = contract.copyWith(
      status: ContractStatus.completed,
      workerSignatureUrl: cfSigUrl,
      workerSignedAt: workerNow,
      pdfUrl: cfPdfUrl,
      updatedAt: workerNow,
    );

    // [알림 흐름]
    // 1차) 근무자 지원 → 관리자에게 newApplication 알림 (application_firestore.dart)
    // 2차) 관리자 확정 + 계약서 발송 → 근무자에게 contractSignRequested 알림 (saveEmployerSignature)
    // 3차) 근무자 서명 완료 → 모든 관리자(adminIds)에게 contractSigned 알림 (여기)
    try {
      final bizSnap = await _db.collection('businesses').doc(contract.businessId).get();
      final data = bizSnap.data();
      final adminIds = List<String>.from(data?['adminIds'] as List? ?? []);
      if (adminIds.isEmpty) {
        final fallback = data?['ownerId'] as String?;
        if (fallback != null && fallback.isNotEmpty) adminIds.add(fallback);
      }
      if (adminIds.isEmpty) {
        debugPrint('⚠️ contractSigned: adminIds 없음 — businessId: ${contract.businessId}');
      } else {
        // [PERF] 알림 N+1 → 병렬 발송
        await Future.wait(adminIds.map((adminUid) =>
          _firestoreService.createNotification(
            NotificationModel.createContractSigned(
              userId: adminUid,
              workerName: contract.snapshot.workerName,
              businessId: contract.businessId,
              contractId: contract.id,
              applicationId: contract.applicationId,
            ),
          ),
        ));
      }
    } catch (e) {
      debugPrint('⚠️ contractSigned 알림 발송 실패 (비치명적): $e');
    }

    return updated;
  }

  // ── 사용자 서명 저장/삭제 ─────────────────────────────────────

  /// users/{uid}.signatureBase64 저장 (CF callableSaveUserSignature 경유)
  Future<void> saveUserSignature({
    required String uid,
    required String base64,
  }) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid != uid) {
      throw StateError('saveUserSignature: 본인 서명만 저장 가능합니다.');
    }
    await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableSaveUserSignature')
        .call({'signatureBase64': base64});
  }

  /// 저장된 서명 삭제 (CF callableSaveUserSignature 경유)
  Future<void> clearUserSignature(String uid) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid != uid) {
      throw StateError('clearUserSignature: 본인 서명만 삭제 가능합니다.');
    }
    await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableSaveUserSignature')
        .call({'signatureBase64': null});
  }

  /// 기존 계약서에 템플릿 조항 적용 (articles가 비어있던 구 계약서용)
  ///
  /// [BUG-수정] completed/voided 상태의 계약서는 수정 불가 — StateError 발생.
  Future<void> updateArticles({
    required String contractId,
    required List<ContractArticle> articles,
    String? templateId,
  }) async {
    // SEC-28: TOCTOU 방지 — 상태 체크와 쓰기를 트랜잭션으로 원자 처리
    final contractRef = _db.collection('employment_contracts').doc(contractId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(contractRef);
      if (!snap.exists) throw StateError('계약서를 찾을 수 없습니다.');
      final contract = EmploymentContractModel.tryFromFirestore(snap);
      if (contract == null) throw StateError('계약서 데이터를 파싱할 수 없습니다.');
      if (contract.status == ContractStatus.pendingWorker) {
        throw StateError('근무자 서명 대기 중인 계약서는 조항을 수정할 수 없습니다. 수정이 필요하면 계약서를 재발송하세요.');
      }
      if (contract.status == ContractStatus.completed ||
          contract.status == ContractStatus.voided) {
        throw StateError('서명 완료 또는 무효화된 계약서는 수정할 수 없습니다.');
      }
      tx.update(contractRef, {
        'articles': articles.map((a) => a.toMap()).toList(),
        if (templateId != null) 'templateId': templateId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // ── 조회 ─────────────────────────────────────────────────────

  /// contractId로 계약서 단건 조회 (get — list 보안 규칙 우회 불필요)
  ///
  /// 알림 등 contractId를 직접 갖고 있는 경우 사용.
  /// allow get 규칙: workerId/businessId 확인은 문서 fetch 후 판단하므로 복합 쿼리 문제 없음.
  Future<EmploymentContractModel?> getById(String contractId) async {
    try {
      final snap = await _db.collection('employment_contracts').doc(contractId).get();
      if (!snap.exists) return null;
      return EmploymentContractModel.tryFromFirestore(snap);
    } on FirebaseException catch (e) {
      debugPrint('❌ [contract] getById 실패 (Firebase): ${e.code} $e');
      return null;
    } catch (e) {
      debugPrint('❌ [contract] getById 실패: $e');
      return null;
    }
  }

  /// applicationId로 계약서 조회 (하위 호환 + 슬롯 포함 검색)
  ///
  /// 보안 규칙상 아래 중 하나를 반드시 전달해야 함:
  ///   [workerId] USER 컨텍스트 — 본인 uid (근무자가 자신의 계약서 조회)
  ///   [businessId] 관리자 컨텍스트 — 소속 사업장 id (관리자가 계약서 조회)
  ///
  /// [보안 주의] workerId 경로는 Firestore LIST 복합 쿼리를 실행한다.
  /// Firestore 보안 규칙은 USER role의 employment_contracts 직접 list를 거부한다
  /// (규칙 주석: "USER: CF getMyContracts 프록시로 이전 — 직접 list 불허").
  /// contractId를 이미 알고 있다면 반드시 [getById]를 사용해 단건 GET으로 조회할 것.
  /// 이 메서드를 USER 컨텍스트에서 호출하는 곳은 contractId가 없을 때만 폴백으로 사용해야 한다.
  Future<EmploymentContractModel?> getByApplication(
    String applicationId, {
    String? workerId,
    String? businessId,
  }) async {
    // assert 대신 throw — assert는 릴리스 빌드에서 무시되어 Firestore 보안 규칙 오류로 이어질 수 있음 (E-043)
    if (workerId == null && businessId == null) {
      throw ArgumentError('getByApplication: workerId 또는 businessId 중 하나는 필수입니다');
    }
    try {
      if (businessId != null) {
        // CF 호출: 복합 equality 쿼리 보안 규칙 버그 우회
        // (businessId + applicationId 복합 필터에서 request.query.filters.businessId → null 문제)
        final res = await _fn
            .httpsCallable('callableGetContractsByBiz')
            .call({'businessId': businessId, 'applicationId': applicationId, 'limit': 10});
        final raw = (res.data['contracts'] as List? ?? []).whereType<Map>().toList();
        if (raw.isNotEmpty) {
          final m = Map<String, dynamic>.from(raw.first);
          final id = m['id'] as String? ?? '';
          return EmploymentContractModel.tryFromMap(m, id);
        }
        return null;
      }
      // [CF-MIGRATED 2026-07-15] employment_contracts USER list 차단
      //   workerId 단독 경로는 PERMISSION_DENIED 발생 — 호출자 없음 (데드코드)
      //   contractId를 알고 있으면 getById(), 없으면 businessId 경로 필수
      debugPrint('⚠️ [contract] getByApplication(workerId:) — USER list 차단됨, null 반환');
      return null;
    } on FirebaseException catch (e) {
      // FAILED_PRECONDITION: 복합 인덱스 미생성 → 개발자가 인지해야 하므로 rethrow
      if (e.code == 'failed-precondition') {
        debugPrint('🚨 [contract] 복합 인덱스 누락: ${e.message}');
        rethrow;
      }
      debugPrint('❌ 계약서 조회 실패 (Firebase): $e');
      return null;
    } catch (e) {
      debugPrint('❌ 계약서 조회 실패: $e');
      return null;
    }
  }

  /// applicationId 목록으로 계약서 상태 일괄 조회 (지원명단 배지용)
  /// 반환: applicationId → contractStatus 문자열 (계약서 없으면 null)
  ///
  /// [CF 전환] 복합 equality 쿼리 보안 규칙 버그 우회:
  ///   applicationIds를 30개씩 청크로 나눠 callableGetContractsByBiz 병렬 호출.
  ///   CF는 applicationId 필드 직접 매핑만 수행하므로 번들 슬롯 2차 applicationId는
  ///   탐색 불가(null 처리). 배지 표시 전용 기능이므로 허용된 설계.
  Future<Map<String, String?>> getContractStatusBatch(
    List<String> applicationIds, {
    required String businessId,
  }) async {
    if (applicationIds.isEmpty) return {};
    final result = <String, String?>{};

    // CF 병렬 호출: applicationIds 30개 단위 청크
    const chunkSize = 30;
    final futures = <Future<void>>[];
    for (var i = 0; i < applicationIds.length; i += chunkSize) {
      final chunk = applicationIds.sublist(
          i, (i + chunkSize).clamp(0, applicationIds.length));
      futures.add(() async {
        try {
          final res = await _fn
              .httpsCallable('callableGetContractsByBiz')
              .call({'businessId': businessId, 'applicationIds': chunk, 'limit': 200});
          final raw = (res.data['contracts'] as List? ?? []).whereType<Map>().toList();
          for (final c in raw) {
            final appId = c['applicationId'] as String?;
            final status = c['status'] as String?;
            if (appId != null && !result.containsKey(appId)) {
              result[appId] = status;
            }
          }
        } catch (e) { debugPrint('⚠️ 계약 상태 조회 오류 (청크): $e'); }
      }());
    }
    await Future.wait(futures);

    // 미매칭 항목 null 처리 (번들 슬롯 2차 applicationId 포함)
    for (final id in applicationIds) {
      result.putIfAbsent(id, () => null);
    }

    return result;
  }

  static final _fn = FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  /// 근무자 uid로 계약서 목록 조회 (페이지네이션 + 상태 필터) — CF 프록시
  /// employment_contracts list 규칙에서 isUser() 제거 → CF로 auth.uid 기반 서버 검증
  Future<({List<EmploymentContractModel> items, String? lastDocId, bool hasMore})>
      getByWorkerPaged(
    String workerId, {
    ContractStatus? statusFilter,
    String? startAfter,
    int pageSize = 20,
  }) async {
    try {
      final callable = _fn.httpsCallable('getMyContracts',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 20)));
      final result = await callable.call({
        if (statusFilter != null) 'statusFilter': statusFilter.value,
        if (startAfter != null) 'lastDocId': startAfter,
        'pageSize': pageSize,
      });
      final data = (result.data as Map<dynamic, dynamic>?);
      if (data == null) throw Exception('CF 응답이 null입니다 (getPagedContracts)');
      final rawItems = (data['items'] as List<dynamic>? ?? []);
      final items = rawItems
          .whereType<Map>()
          .map((e) {
            final m = Map<String, dynamic>.from(e);
            final id = m.remove('id') as String? ?? '';
            return EmploymentContractModel.tryFromMap(m, id);
          })
          .whereType<EmploymentContractModel>()
          .toList();
      return (
        items: items,
        lastDocId: data['lastDocId'] as String?,
        hasMore: data['hasMore'] as bool? ?? false,
      );
    } catch (e) {
      debugPrint('❌ 근무자 계약서 조회 실패: $e');
      rethrow;
    }
  }

  /// 근무자 uid로 계약서 목록 조회 (하위 호환 - 내부 캐시용) — CF 프록시
  Future<List<EmploymentContractModel>> getByWorker(String workerId) async {
    try {
      final callable = _fn.httpsCallable('getMyContracts',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 20)));
      final result = await callable.call({'pageSize': 200});
      final data = (result.data as Map<dynamic, dynamic>?);
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
    } catch (e) {
      debugPrint('❌ 근무자 계약서 조회 실패: $e');
      return [];
    }
  }

  /// 사업장 계약서 목록 조회 (페이지네이션 + 상태 필터)
  ///
  /// [CF 전환] 복합 equality 쿼리 보안 규칙 버그 우회.
  /// startAfterId: DocumentSnapshot 대신 문서 ID 문자열 사용 (CF 커서 방식).
  Future<({List<EmploymentContractModel> items, String? lastDocId, bool hasMore})>
      getByBusinessPaged(
    String businessId, {
    ContractStatus? statusFilter,
    String? startAfterId,
    int pageSize = 20,
  }) async {
    try {
      // pageSize+1로 호출해 hasMore 정확도 보장 — 마지막 페이지에서 빈 호출 없앰 (E-047)
      final res = await _fn
          .httpsCallable('callableGetContractsByBiz')
          .call({
            'businessId': businessId,
            if (statusFilter != null) 'status': statusFilter.value,
            'limit': pageSize + 1,
            if (startAfterId != null) 'startAfterId': startAfterId,
          });
      final raw = (res.data['contracts'] as List? ?? []).whereType<Map>().toList();
      final hasMore = raw.length > pageSize;
      final page = hasMore ? raw.sublist(0, pageSize) : raw;
      final items = page
          .map((e) {
            final m = Map<String, dynamic>.from(e);
            final id = m['id'] as String? ?? '';
            return EmploymentContractModel.tryFromMap(m, id);
          })
          .whereType<EmploymentContractModel>()
          .toList();
      final lastDocId = page.isNotEmpty ? page.last['id'] as String? : null;
      return (items: items, lastDocId: lastDocId, hasMore: hasMore);
    } catch (e) {
      debugPrint('❌ 사업장 계약서 조회 실패: $e');
      rethrow;
    }
  }


  /// 계약서 무효화 (관리자 전용)
  ///
  /// [V-001] 실행 순서: 계약서 voided 먼저 → 알림 발송 → application 취소
  /// [CF-MIGRATED 2026-07-17] Trust Boundary Charter "계약 효력 상태 = CF 필수" 준수.
  ///   callableVoidContract CF(Admin SDK)가 voidedBy=callerUid 강제 + serverTimestamp 적용.
  Future<void> voidContract(String contractId) async {
    final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableVoidContract',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
    final result = await callable.call({'contractId': contractId});
    // Firebase SDK 런타임 반환형은 Map<dynamic,dynamic> — 다른 CF 호출과 동일하게 방어 캐스팅
    final data = result.data as Map<dynamic, dynamic>?;

    final workerId = data?['workerId'] as String? ?? '';
    final bizName = data?['businessName'] as String? ?? '';
    final bizId = data?['businessId'] as String? ?? '';
    final appIds = (data?['applicationIds'] as List?)?.whereType<String>().toList() ?? [];

    if (workerId.isEmpty) return; // 이미 voided — 멱등 처리

    // 2단계: 근무자에게 무효화 알림 즉시 발송 (계약서 voided 직후 — 앱 취소 전)
    // [H-34] 앱 취소 실패와 무관하게 근무자가 즉시 인지하도록 순서 보장
    try {
      await _firestoreService.createNotification(
        NotificationModel.createContractVoided(
          userId: workerId,
          businessName: bizName,
          businessId: bizId,
          contractId: contractId,
        ),
      );
    } catch (e) {
      debugPrint('⚠️ [H-34] 계약서 무효화 알림 발송 실패 (비치명적): $e');
    }

    // 3단계: 연결된 application 취소 처리
    // [B-003] false 반환도 실패로 간주 — cancelConfirmedApplication은 내부 오류를
    // exception 대신 false로 반환하므로 반환값을 명시적으로 체크해야 함
    // [W-2] canceledBy: 'system' — voidContract는 시스템/관리자 취소이므로 ADMIN_CANCELED로 기록
    // null 전달 시 USER_CANCELED로 기록되어 감사 로그에서 혼동 발생
    // [PERF] 취소 N+1 → 병렬 처리 (각 appId 독립 실행)
    final cancelResults = await Future.wait(
      appIds.map((appId) async {
        try {
          final ok = await _firestoreService.cancelConfirmedApplication(
            appId,
            canceledBy: 'system',
            cancelReason: '계약서가 무효화되었습니다',
          );
          if (!ok) {
            debugPrint('⚠️ voidContract: application 취소 실패 ($appId): false 반환');
            return appId;
          }
          return null;
        } catch (e) {
          debugPrint('⚠️ voidContract: application 취소 실패 ($appId): $e');
          return appId;
        }
      }),
    );
    final failedIds = cancelResults.whereType<String>().toList();

    // 4단계: 실패한 appId 기록 — 관리자 화면 경고 배너로 노출, 재처리 버튼 제공
    // M-5: voidFailedAppIds 저장 실패 시 재시도(retryVoidFailedApps) 메커니즘이
    // 동작하지 않아 미취소 application이 CONFIRMED 상태로 잔존할 수 있음.
    // 완전한 해결책은 Cloud Functions의 트랜잭션 기반 처리이나, 현 규모에서는
    // exception 메시지에 failedIds를 포함해 관리자가 수동 처리할 수 있도록 한다.
    if (failedIds.isNotEmpty) {
      try {
        await _db.collection('employment_contracts').doc(contractId).update({
          'voidFailedAppIds': failedIds,
        });
      } catch (e) {
        // voidFailedAppIds 저장 실패 — retryVoidFailedApps 경로 불가.
        // failedIds를 exception 메시지에 포함해 관리자가 직접 확인할 수 있게 한다.
        debugPrint('⚠️ voidFailedAppIds 기록 실패: $e\n  미취소 IDs: $failedIds');
        throw Exception(
          '계약서가 무효화되었으나 ${failedIds.length}개 지원서 취소에 실패했습니다.\n'
          '직접 확인이 필요한 지원서 IDs: ${failedIds.join(', ')}');
      }
      throw Exception(
        '계약서가 무효화되었으나 ${failedIds.length}개 지원서 취소에 실패했습니다.\n'
        '계약서 카드에서 재처리하거나 직접 확인해주세요.');
    }
  }

  /// voidFailedAppIds에 기록된 application들을 재시도로 취소 처리.
  /// 성공한 항목은 voidFailedAppIds에서 제거하고, 전부 성공 시 필드를 삭제.
  Future<void> retryVoidFailedApps(EmploymentContractModel contract) async {
    if (contract.voidFailedAppIds.isEmpty) return;

    // [PERF] 재처리 N+1 → 병렬 처리 (voidContract와 동일 패턴)
    final retryResults = await Future.wait(
      contract.voidFailedAppIds.map((appId) async {
        try {
          final ok = await _firestoreService.cancelConfirmedApplication(
            appId,
            canceledBy: 'system', // [W-2] 재처리도 시스템 취소 — ADMIN_CANCELED 기록 유지
            cancelReason: '계약서가 무효화되었습니다',
          );
          if (!ok) {
            debugPrint('⚠️ retryVoidFailedApps: application 취소 실패 ($appId): false 반환');
            return appId;
          }
          return null;
        } catch (e) {
          debugPrint('⚠️ retryVoidFailedApps: application 취소 실패 ($appId): $e');
          return appId;
        }
      }),
    );
    final stillFailedIds = retryResults.whereType<String>().toList();

    // 성공한 항목 반영: 전부 성공 시 voidFailedAppIds 필드 삭제, 일부 실패 시 갱신
    await _db.collection('employment_contracts').doc(contract.id).update({
      'voidFailedAppIds': stillFailedIds.isEmpty
          ? FieldValue.delete()
          : stillFailedIds,
    });

    if (stillFailedIds.isNotEmpty) {
      throw Exception('${stillFailedIds.length}개 지원서 재처리 실패. 잠시 후 다시 시도해주세요.');
    }
  }

  // ── 내부: 번들 탐색 ──────────────────────────────────────────

  /// 단기 번들 계약서 탐색 (toId + workDetailId + workerId 조합으로 기존 번들 찾기)
  ///
  /// [CF 전환] 5중 equality 필터가 보안 규칙 버그를 확실히 유발하므로 CF 사용.
  /// Admin SDK는 보안 규칙을 우회하여 복합 필터를 안전하게 실행한다.
  Future<EmploymentContractModel?> _findBundle({
    required String toId,
    required String workDetailId,
    required String workerId,
    required String businessId,
  }) async {
    try {
      final res = await _fn
          .httpsCallable('callableGetContractsByBiz')
          .call({
            'businessId': businessId,
            'toId': toId,
            'workDetailId': workDetailId,
            'workerId': workerId,
            'isLongTerm': false,
            'limit': 1,
          });
      final raw = (res.data['contracts'] as List? ?? []).whereType<Map>().toList();
      if (raw.isEmpty) return null;
      final m = Map<String, dynamic>.from(raw.first);
      final id = m['id'] as String? ?? '';
      return EmploymentContractModel.tryFromMap(m, id);
    } catch (e) {
      debugPrint('❌ 번들 계약서 조회 실패: $e');
      rethrow; // null 반환 시 _createNew가 중복 계약서를 생성하므로 에러 전파
    }
  }

  // ── 내부: 슬롯 추가 ──────────────────────────────────────────

  Future<EmploymentContractModel> _addSlot(
    EmploymentContractModel contract,
    ApplicationModel application,
    WorkDetailData workDetail,
  ) async {
    final newSlot = ContractSlot(
      applicationId: application.id,
      workDate: _fmtDate(application.workDate),
      startTime: workDetail.startTime,
      endTime: workDetail.endTime,
      wage: workDetail.wage,
      wageType: workDetail.wageType,
    );

    final contractRef = _db.collection('employment_contracts').doc(contract.id);

    // 트랜잭션으로 동시 확정 시 슬롯 유실 방지 (last-write-wins 방지)
    final updatedContract = await _db.runTransaction((tx) async {
      final snap = await tx.get(contractRef);
      if (!snap.exists) throw Exception('계약서를 찾을 수 없습니다: ${contract.id}');
      final current = EmploymentContractModel.tryFromFirestore(snap);
      if (current == null) throw StateError('계약서 데이터를 파싱할 수 없습니다: ${contract.id}');

      // 멱등성 보호 — 동일 applicationId가 이미 등록된 경우 슬롯 중복 추가 방지
      // (이중 확정 또는 동시 호출 시 발생 가능)
      if (current.applicationIds.contains(application.id)) {
        return current;
      }

      // [SEC-FIX] 트랜잭션 내 status 재검증 — K-001 외부 검증(L57)과 트랜잭션 진입 사이
      // 사업주 서명이 완료된 경우 slotの추가를 차단해 서명 무결성 보호
      if (current.status != ContractStatus.pendingEmployer) {
        throw StateError('계약서가 이미 서명 단계에 있어 슬롯을 추가할 수 없습니다: ${current.status.value}');
      }

      final updatedSlots = [...current.slots, newSlot];
      final updatedIds = [...current.applicationIds, application.id];
      final now = DateTime.now(); // copyWith 용 로컬 변수 (Firestore는 serverTimestamp 사용)
      tx.update(contractRef, {
        'slots': updatedSlots.map((s) => s.toMap()).toList(),
        'applicationIds': updatedIds,
        'updatedAt': FieldValue.serverTimestamp(), // [M3-FIX] serverTimestamp 강제
      });
      return current.copyWith(
        slots: updatedSlots,
        applicationIds: updatedIds,
        updatedAt: now,
      );
    });

    return updatedContract;
  }

  // ── 내부: 신규 생성 ──────────────────────────────────────────

  Future<EmploymentContractModel> _createNew({
    required ApplicationModel application,
    required BusinessModel business,
    required UserModel worker,
    required WorkDetailData workDetail,
    required String toId,
    required String workDetailId,
    List<ContractArticle> articles = const [],
    String? templateId,
  }) async {
    // ownerName이 없으면 ownerId로 users 컬렉션에서 조회
    BusinessModel effectiveBusiness = business;
    if (business.ownerName == null || business.ownerName!.trim().isEmpty) {
      try {
        final ownerDoc = await _db.collection('users').doc(business.ownerId).get();
        final data = ownerDoc.data();
        // 사업자등록증 대표자명(ceoName) 우선, 없으면 계정 이름
        final ceoName = data?['ceoName'] as String?;
        final accountName = data?['name'] as String?;
        final name = (ceoName?.trim().isNotEmpty == true) ? ceoName : accountName;
        if (name != null && name.trim().isNotEmpty) {
          effectiveBusiness = business.copyWith(ownerName: name);
        }
      } catch (e) {
        debugPrint('대표자 이름 조회 실패: $e');
      }
    }

    bool isLong = application.isLongTermApplication;
    // 기존 데이터(type 필드 미기록)를 위해 TO 타입으로 fallback
    if (!isLong && toId.isNotEmpty) {
      try {
        final toDoc = await _db.collection('tos').doc(toId).get();
        if (toDoc.exists && toDoc.data()?['type'] == TOType.contract) {
          isLong = true;
        }
      } catch (e) {
        debugPrint('TO 타입 조회 실패 (fallback): $e');
      }
    }
    final snapshot = _buildSnapshot(
      application: application,
      business: effectiveBusiness,
      worker: worker,
      workDetail: workDetail,
      isLongTermOverride: isLong,
    );

    // 단기: 첫 슬롯 생성
    final slots = isLong
        ? <ContractSlot>[]
        : [
            ContractSlot(
              applicationId: application.id,
              workDate: _fmtDate(application.workDate),
              startTime: workDetail.startTime,
              endTime: workDetail.endTime,
              wage: workDetail.wage,
              wageType: workDetail.wageType,
            ),
          ];

    final ref = _db.collection('employment_contracts').doc();
    final contract = EmploymentContractModel(
      id: ref.id,
      applicationId: application.id,
      businessId: business.id,
      workerId: worker.uid,
      isLongTerm: isLong,
      toId: toId,
      workDetailId: workDetailId,
      slots: slots,
      applicationIds: [application.id],
      status: ContractStatus.pendingEmployer,
      snapshot: snapshot,
      articles: articles,
      templateId: templateId,
      createdAt: DateTime.now(),
      isNewUnsaved: true,  // 서명 완료 시 최초 저장
    );

    // Firestore에 저장하지 않음 — 사업주 서명 시 최초 저장
    return contract;
  }

  // ── 스냅샷 생성 ──────────────────────────────────────────────

  ContractSnapshot _buildSnapshot({
    required ApplicationModel application,
    required BusinessModel business,
    required UserModel worker,
    required WorkDetailData workDetail,
    bool? isLongTermOverride,
  }) {
    final isLong = isLongTermOverride ?? application.isLongTermApplication;
    return ContractSnapshot(
      businessName: business.name,
      businessNumber: business.formattedBusinessNumber,
      businessAddress: [business.address, business.detailAddress]
          .whereType<String>()
          .join(' '),
      businessPhone: business.phone,
      ownerName: business.ownerName ?? '',
      // [V3 FOREIGN-DOCUMENT-FIRST] officialName = 외국인은 legalName 우선, 내국인은 name
      workerName: worker.officialName,
      workerBirthDate:
          worker.birthDate != null ? _fmtDate(worker.birthDate) : null,
      workerPhone: worker.effectivePhone,
      workerAddress: [worker.address, worker.detailAddress]
              .whereType<String>()
              .join(' ')
              .trim()
              .isEmpty
          ? null
          : [worker.address, worker.detailAddress]
              .whereType<String>()
              .join(' ')
              .trim(),
      workType: workDetail.workType,
      workPlace: business.address,
      isLongTerm: isLong,
      // 희망 시작일 우선, 없으면 workDate(TO 시작일 or 지원일) 사용
      contractStart: isLong
          ? _fmtDate(application.desiredStartDate ?? application.workDate)
          : null,
      // workEndDate가 null(개방형 계약)이면 '' 대신 null을 전달 — '' 전달 시 workPeriodText != null 체크 통과
      contractEnd: isLong && application.workEndDate != null
          ? _fmtDate(application.workEndDate)
          : null,
      workDays: application.workDays,
      startTime: workDetail.startTime,
      endTime: workDetail.endTime,
      breakMinutes: workDetail.breakMinutes,
      wage: workDetail.wage,
      wageType: workDetail.wageType,
      wagePaymentDay: business.wagePaymentDay,
      baseHourlyWage: workDetail.baseHourlyWage,
      payScheduleType: workDetail.payScheduleType,
      payScheduleDay: workDetail.payScheduleDay,
      payScheduleTime: workDetail.payScheduleTime,
      taxDeductionType: workDetail.taxDeductionType,
    );
  }

  // ── 유틸 ─────────────────────────────────────────────────────

  String _fmtDate(DateTime? d) =>
      d == null ? '' : FormatHelper.formatDateISO(d);
}
