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
List<AttendancePolicyGroup> attendancePolicyGroups(AttendanceRules r) => [
      AttendancePolicyGroup('출근', [
        AttendancePolicyLine(
            '일찍 도착', '시작 ${r.earlyWindow}분 전까지는 정시 처리'),
        AttendancePolicyLine(
            '조출 인정', '${r.earlyWindow}분을 넘겨 도착하면 ${r.earlyArrivalUnit}분 단위'),
        AttendancePolicyLine('지각 유예', '${r.lateGrace}분까지는 정시 처리'),
        AttendancePolicyLine('지각 처리', '${r.lateUnit}분 단위'),
      ]),
      AttendancePolicyGroup('퇴근', [
        AttendancePolicyLine(
            '늦게 퇴근', '종료 후 ${r.lateWindow}분까지는 정시 처리'),
        AttendancePolicyLine(
            '연장 인정', '${r.lateWindow}분을 넘기면 ${r.overtimeUnit}분 단위'),
        AttendancePolicyLine('조퇴 처리', '${r.earlyLeaveUnit}분 단위'),
      ]),
    ];

/// 그룹을 펼친 평면 목록 — 묶음 제목을 쓸 수 없는 좁은 화면·PDF 용.
List<AttendancePolicyLine> attendancePolicyLines(AttendanceRules r) =>
    attendancePolicyGroups(r).expand((g) => g.lines).toList();
