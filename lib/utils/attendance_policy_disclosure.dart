// [R7-PAYROLL-POLICY.4B] 근태·급여 처리 기준을 **한 벌의 문장**으로 만든다
//
// ── 왜 필요한가 ─────────────────────────────────────────────────────
//   `.4`/`.4A` 는 화면마다 따로 라벨을 적었다. 근로자 수락 화면은 4항목,
//   계약서는 5항목, 관리자 확인 시트는 5항목이었다. 그런데 급여에 영향하는
//   숫자는 **7개 전부**다(아래 각 항목 주석의 실제 계산 효과 참조).
//   화면마다 다른 부분집합을 보여주면
//     · 근로자가 지급액에 영향하는 조건을 다 알 수 없고,
//     · 같은 약속을 두고 화면마다 다른 말을 한다.
//
//   그래서 표시 항목·문구·그룹을 여기 한 곳에 둔다. 소비자는 받은 snapshot 만
//   읽어 렌더한다 — Flutter 위젯이 아니라 **데이터**로 돌려주는 이유는
//   계약서 PDF(`pw.*`)와 화면(`Text`)이 같은 목록을 써야 하기 때문이다.
//
// ── 표시 원칙 ───────────────────────────────────────────────────────
//   · 내부 필드 이름을 직역하지 않는다. `earlyWindow` 를 "조기 창" 이라고
//     쓰면 근로자는 그것이 급여를 바꾸는 줄 모른다.
//   · 각 줄은 **효과**를 말한다. 숫자만 나열하면 이해할 수 없다.
//   · 법적 보증·면책 문구를 쓰지 않는다. 이건 조건 고지다.
import '../models/core/business_model.dart';
// [R7-PREDEVICE-STABILIZATION.1A] 고지의 사례 숫자는 계산 모듈에서 온다.
//   순환 없음 — rounding_helper 는 이 파일을 모른다.
import 'attendance_rounding_helper.dart';

/// 근태·급여 기준 한 줄 — 라벨과 값.
class AttendancePolicyLine {
  const AttendancePolicyLine(this.label, this.value);

  final String label;
  final String value;
}

/// 출근/퇴근으로 묶은 한 묶음.
class AttendancePolicyGroup {
  const AttendancePolicyGroup(this.title, this.lines);

  final String title;
  final List<AttendancePolicyLine> lines;
}

/// 모든 화면이 쓰는 같은 이름. 관리자 설정도 같은 도메인 이름을 쓴다
/// (`근태 및 급여 처리 기준`) — 화면마다 다른 이름이면 같은 것을 말하는지
/// 알 수 없다.
const String kAttendancePolicyTitle = '근태·급여 처리 기준';

/// 약속에 고정됐다는 사실. 근로자 결정 화면에서 쓴다.
const String kAttendancePolicyFrozenNote =
    '이 기준은 이 근무에 고정됩니다. 사업장이 이후에 기준을 바꿔도 적용되지 않습니다.';

/// 기록이 없는 근무. **사업장 현재 기준으로 대신 채우지 않는다** —
/// 모름과 현재값은 다르다.
const String kAttendancePolicyUnknownNote =
    '이 근무의 근태·급여 처리 기준이 기록되어 있지 않습니다.\n'
    '사업장에 확인해 주세요.';

/// [R7-PAYROLL-POLICY.4D] 사업장에 적용할 기준 **자체가 없다** — 새 지원을
/// 만들 수 없다.
///
///   근로자가 할 수 있는 일이 없는 상태다. "근태 기준을 입력해 주세요" 처럼
///   근로자 잘못으로 읽히는 문구를 쓰지 않는다 — 입력 권한이 없다.
///
///   영구 거부도 아니다. 사업장이 기준을 저장하면 그때부터 지원할 수 있으므로
///   "지원할 수 없습니다" 가 아니라 **준비 중**으로 말한다.
const String kAttendancePolicyUnavailableNote =
    '사업장의 근태·급여 기준이 아직 준비되지 않았어요.\n'
    '기준이 준비되면 지원할 수 있습니다.';

/// 기준을 **읽지 못한** 상태 — 없는 것과 다르다(ERROR ≠ ABSENT).
const String kAttendancePolicyLoadFailedNote =
    '근태·급여 처리 기준을 확인하지 못했어요.\n잠시 후 다시 시도해 주세요.';

/// [R7-PAYROLL-POLICY.4D] 이 기준으로 **새 지원을 만들 수 있는가.**
///
///   `null` 은 적용할 조건이 없다는 뜻이므로 새 약속의 씨앗을 만들 수 없다.
///   `'absent'` 토큰은 진단·표시용이고 **지원 성공 토큰이 아니다**.
///
///   최종 판정은 서버다(`srvHasCanonicalAttendancePolicy`). 이 함수는 화면이
///   보낼 수 없는 요청을 보내지 않게 하는 사전 판단일 뿐 — 클라이언트 차단만
///   으로 무결성을 삼지 않는다.
bool canApplyWithAttendancePolicy(AttendanceRules? r) => r != null;

/// 인정 시간이 급여 기준이 된다는 사실.
const String kAttendancePolicyEffectNote = '인정된 시간이 급여 계산의 기준이 됩니다.';

/// 급여에 영향하는 **7개 전부**를 출근/퇴근으로 묶어 돌려준다.
///
/// 각 줄이 실제 계산에서 무엇을 바꾸는가 — `processCheckin`/`processCheckout`
/// (서버 `_processCheckin`/`_processCheckout` 와 같은 식) 기준:
///
///   earlyWindow      시작 전 이 범위 **이내** 도착은 시작 시각으로 정규화된다.
///                    즉 그만큼 일찍 와도 **근무로 인정되지 않는다.**
///                    이 범위를 넘겨 도착하면 조출로 인정된다 → 금액이 달라진다.
///   earlyArrivalUnit 조출로 인정될 때 그 시간을 이 단위로 끊는다(시작 쪽으로).
///   lateGrace        시작 후 이 범위 이내 도착은 지각으로 보지 않고 정시 처리.
///   lateUnit         지각일 때 이 단위로 올려 인정 시작 시각을 늦춘다.
///   lateWindow       종료 후 이 범위 **이내** 퇴근은 종료 시각으로 정규화된다.
///                    즉 그만큼 더 있어도 **연장으로 인정되지 않는다.**
///   overtimeUnit     연장으로 인정될 때 그 시간을 이 단위로 내려 끊는다.
///   earlyLeaveUnit   조퇴일 때 이 단위로 올려 인정 종료 시각을 앞당긴다.
/// [R7-PREDEVICE-STABILIZATION.1] "N분 단위" 는 **방향을 말하지 않았다.**
///
///   네 개의 단위 항목은 모두 근로자에게 **불리한 쪽**으로 끊는다
///   (위 `processCheckin`/`processCheckout` 실측 · 기본값 유예 5분·단위 30분):
///     · 조출   남는 시간을 버린다        47분 일찍 → 30분만 인정
///     · 지각   올려서 차감한다            6분 늦음  → 30분 차감
///     · 연장   남는 시간을 버린다        59분 연장 → 30분만 인정
///     · 조퇴   올려서 차감한다            1분 일찍  → 30분 차감
///
///   그런데 근로자가 보던 문장은 "30분 단위" 뿐이었다. 이것은 **반올림**
///   으로 읽힌다 — 어떤 때는 유리하고 어떤 때는 불리한 중립 연산. 실제로는
///   네 항목 전부가 한 방향이고, 그 방향이 지급액을 줄인다. 방향을 적지
///   않으면 근로자는 자기 임금이 어떻게 계산되는지 알 수 없다.
///
///   그래서 각 줄에 **방향과 구체적 경계 사례**를 같이 적는다. "올림"
///   같은 용어만으로는 효과가 전달되지 않으므로 "6분 늦으면 30분" 처럼
///   실제로 일어나는 일을 쓴다.
///
///   [R7-PREDEVICE-STABILIZATION.1A] 사례의 **두 숫자는 설정에 따라 다르다.**
///   지각은 유예를 넘겨야 시작되고(유예 5분이면 1분 지각은 정시), 유예+1 이
///   단위보다 크면 차감도 단위와 다르다(유예 5·단위 5 → 6분 지각은 10분).
///   그래서 숫자를 문장에 적지 않고 계산 모듈에서 받는다.
List<AttendancePolicyGroup> attendancePolicyGroups(AttendanceRules r) => [
      AttendancePolicyGroup('출근', [
        AttendancePolicyLine(
            '일찍 도착', '시작 ${r.earlyWindow}분 전까지는 정시 처리'),
        AttendancePolicyLine('조출 인정',
            '${r.earlyWindow}분을 넘겨 도착하면 ${r.earlyArrivalUnit}분 단위로 인정'
            ' (남는 시간은 인정되지 않아요)'),
        AttendancePolicyLine('지각 유예', '${r.lateGrace}분까지는 정시 처리'),
        // [R7-PREDEVICE-STABILIZATION.1A] 사례 숫자를 짐작하지 않는다.
        //   `.1` 은 "1분 늦어도 N분" 이라고 적었는데 유예가 있는 사업장에서
        //   거짓이다(유예 5분이면 1분 지각은 정시). 또 유예+1 이 단위보다
        //   크면 차감도 단위와 다르다. 둘 다 실제 계산에서 가져온다.
        AttendancePolicyLine('지각 처리',
            '${r.lateUnit}분 단위로 올려서 차감'
            ' (${firstLateOffsetMinutes(r)}분 늦으면'
            ' ${firstLateDeductionMinutes(r)}분)'),
      ]),
      AttendancePolicyGroup('퇴근', [
        AttendancePolicyLine(
            '늦게 퇴근', '종료 후 ${r.lateWindow}분까지는 정시 처리'),
        AttendancePolicyLine('연장 인정',
            '${r.lateWindow}분을 넘기면 ${r.overtimeUnit}분 단위로 인정'
            ' (남는 시간은 인정되지 않아요)'),
        // 조퇴에는 유예가 없다 — 1분이 그대로 첫 사례다. 그래도 차감 분은
        //   단위와 같다고 **짐작하지 않고** 계산에서 가져온다.
        AttendancePolicyLine('조퇴 처리',
            '${r.earlyLeaveUnit}분 단위로 올려서 차감'
            ' (1분 일찍 가도 ${firstEarlyLeaveDeductionMinutes(r)}분)'),
      ]),
    ];

/// 그룹을 펼친 평면 목록 — 묶음 제목을 쓸 수 없는 좁은 화면·PDF 용.
List<AttendancePolicyLine> attendancePolicyLines(AttendanceRules r) =>
    attendancePolicyGroups(r).expand((g) => g.lines).toList();

/// [R7-PAYROLL-POLICY.4C] 근로자가 **본 기준**을 식별하는 토큰.
///
///   직접 지원 submit 에 함께 보낸다. 서버가 commit 시점 canonical 값과
///   비교해, 보는 동안 사업장이 기준을 바꿨으면 지원을 거부한다
///   (`ATTENDANCE_POLICY_CHANGED`).
///
///   이 값은 **stale 탐지 입력일 뿐**이다. 저장되는 snapshot 은 서버가 읽은
///   사업장 문서에서 만든다 — 클라이언트가 보낸 숫자가 약속이 되지 않는다.
///
///   서버 `srvAttendancePolicyFingerprint` 와 **같은 필드·같은 순서·같은
///   형식**이어야 한다. 한쪽이 항목을 빼면 그 항목의 변경을 아무도 못 잡는다.
///   기준이 없으면 `'absent'` — 없는 것을 기본값 토큰으로 만들지 않는다.
///
///   주의: 모델은 [AttendanceRules.fromMap] 에서 값을 clamp 한다. 저장된 값이
///   허용 범위를 벗어난 사업장은 서버 원값과 토큰이 달라 계속 mismatch 가
///   된다 — 지원이 열리는 쪽이 아니라 막히는 쪽이므로 안전한 방향이다.
String attendancePolicyFingerprint(AttendanceRules? r) {
  if (r == null) return 'absent';
  return 'earlyWindow=${r.earlyWindow}'
      '|earlyArrivalUnit=${r.earlyArrivalUnit}'
      '|lateGrace=${r.lateGrace}'
      '|lateUnit=${r.lateUnit}'
      '|lateWindow=${r.lateWindow}'
      '|overtimeUnit=${r.overtimeUnit}'
      '|earlyLeaveUnit=${r.earlyLeaveUnit}';
}

/// [R7-PAYROLL-POLICY.4C] 보는 동안 기준이 바뀌어 지원이 만들어지지 않았다.
///
///   법률 경고가 아니라 **상태 변경 안내**다. 무엇을 하면 되는지 말한다.
///   서버가 자동으로 새 기준으로 다시 지원하지 않는다 — 근로자가 바뀐
///   기준을 다시 확인해야 한다.
const String kAttendancePolicyChangedNote =
    '근태·급여 처리 기준이 변경됐어요.\n변경된 기준을 확인한 뒤 다시 지원해 주세요.';
