import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/core/application_model.dart';
import '../../models/core/employment_contract_model.dart';
import '../../models/core/user_model.dart';
import '../../models/core/work_detail_data.dart';
import '../../services/contract_service.dart';
import '../../services/firestore_service.dart';
import '../../utils/global_loading_controller.dart';
import '../../utils/toast_helper.dart';
import '../../utils/work_detail_helper.dart';
import '../../widgets/dialogs/contract_template_selector_dialog.dart';
import '../contract/contract_sign_screen.dart';

/// [CONTRACT-DISPATCH-B3] 좌석을 확보한 확정·승인 직후 **기존** 계약서 작성 흐름을 잇는다.
///
///   근로자 상세 다이얼로그의 확정 → `_createContractAndSign` 과 같은 순서다:
///   템플릿 선택 → 그 지원서의 업무 → 서버 최신 지원서 → `findOrCreateContract` → 사업주 서명 화면.
///   지원 검토 큐의 '승인'(PENDING → CONTRACT_PENDING, 좌석 +1)은 이 연결이 없었다 —
///   근로자는 계약서를 받지 못하고, 출근은 계약 동의를 요구한다.
///
///   돌려주는 값은 **발송 여부**다. 화면을 열었다는 사실을 발송으로 보지 않는다 —
///   서명 화면이 갱신된 계약(pending_worker)을 돌려줄 때만 true.
///   관리자가 중간에 닫으면 false — 지원서는 CONTRACT_PENDING 으로 남고, 미발송 목록이 다음 일이다.
class ContractDispatchFlow {
  ContractDispatchFlow._();

  static Future<bool> start(
    BuildContext context, {
    required ApplicationModel application,
    required UserModel worker,
  }) async {
    final businessId = application.businessId;
    final articles = await ContractTemplateSelectorDialog.show(
      context,
      businessId: businessId,
    );
    if (articles == null || !context.mounted) return false;

    final fs = FirestoreService();
    // [PERF-L51 · 2026-11-26] 템플릿을 고른 뒤 서명 화면이 뜰 때까지 아무 표시가 없었다 — 그동안 진행 표시를 띄운다.
    GlobalLoadingController.show('계약서를 준비하는 중...');
    var loadingShown = true;
    void hideLoading() {
      if (!loadingShown) return;
      loadingShown = false;
      GlobalLoadingController.hide();
    }
    try {
      final toId = application.toId ?? '';
      // [PERF-L51] 서로 독립인 세 읽기(업무 · 사업장 · 서버 최신 지원서)를 **동시에** 시작한다(예전: 차례로 3번 왕복).
      //   판정·안내는 예전 순서 그대로다 — 업무 → 사업장 → 지원서. 앞 단계에서 멈추면 뒤 읽기 결과는 버린다
      //   (실패도 여기서 삼키지 않고 그 단계에 도달했을 때만 예전처럼 처리한다).
      final workDetailsFuture =
          toId.isNotEmpty ? fs.getWorkDetails(toId) : Future.value(<WorkDetailData>[]);
      final businessFuture = fs.getBusinessById(businessId);
      // 승인 직후 서버가 채운 값(근무 종료일 등)이 계약서에 들어가도록 서버에서 다시 읽는다.
      final freshDocFuture = FirebaseFirestore.instance
          .collection('applications')
          .doc(application.id)
          .get(const GetOptions(source: Source.server));
      // 앞 단계에서 멈춰 기다리지 않게 된 읽기의 오류가 처리되지 않은 채 남지 않게 한다(await 하는 곳은 그대로 오류를 받는다).
      businessFuture.ignore();
      freshDocFuture.ignore();

      final workDetails = await workDetailsFuture;
      if (!context.mounted) return false;
      if (workDetails.isEmpty) {
        ToastHelper.showError('업무 정보를 불러올 수 없어 계약서를 만들지 못했어요.');
        return false;
      }
      final workDetail =
          WorkDetailHelper.contractWorkDetailFor(application, workDetails);
      if (workDetail == null) {
        ToastHelper.showError('이 근무의 업무를 공고에서 찾지 못해 계약서를 만들지 못했어요.');
        return false;
      }
      final business = await businessFuture;
      if (!context.mounted) return false;
      if (business == null) {
        ToastHelper.showError('사업장 정보를 불러올 수 없어 계약서를 만들지 못했어요.');
        return false;
      }
      final freshDoc = await freshDocFuture;
      if (!freshDoc.exists) throw Exception('지원서를 찾을 수 없습니다');
      final freshApp = ApplicationModel.tryFromMap(freshDoc.data()!, freshDoc.id);
      if (freshApp == null) throw Exception('지원서 데이터가 손상되었습니다');

      final contract = await ContractService().findOrCreateContract(
        application: freshApp,
        business: business,
        worker: worker,
        workDetail: workDetail,
        articles: articles,
      );
      hideLoading();
      if (!context.mounted) return false;
      final result = await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => ContractSignScreen(contract: contract, role: 'employer'),
        ),
      );
      return result is EmploymentContractModel &&
          result.status == ContractStatus.pendingWorker;
    } catch (e) {
      debugPrint('❌ [ContractDispatchFlow] 계약서 준비 실패: $e');
      hideLoading();
      if (context.mounted) {
        ToastHelper.showWarning('승인은 완료됐지만 계약서를 만들지 못했습니다.\n미발송 계약에서 다시 시도해주세요.');
      }
      return false;
    } finally {
      hideLoading();
    }
  }
}
