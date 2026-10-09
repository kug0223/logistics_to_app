/**
 * [R7-P1] 관리자 화면 디자인 감사 — SOURCE READ ONLY.
 *
 *   프로젝트가 이미 갖고 있는 D0 계약(공용 컴포넌트 + 디자인 상수)으로
 *   관리자 접근 가능 화면을 측정한다. 새 디자인 체계를 만들지 않는다.
 *
 *   D0 상수: 카드 radius 12 · 배지 20 · 버튼 10 · 검색바 10
 *            빈 상태 아이콘 56 · 요약헤더 primary@0.06
 *            그림자 alpha .04 blur 6 · 좌측 인디케이터 4
 *   D0 필수 공용: GradientScaffold · AppEmptyState · AppSearchBar
 *                AppSummaryHeader · AppStatusCard · AppBatchActionBar
 *                StyledDialog · DialogHelper · ResponsiveHelper · AppColors
 *
 *   쓰기 0. 파일을 읽고 셀 뿐이다.
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const LIB = path.join(ROOT, 'lib');

// 관리자가 도달하는 트리 (지원자 전용은 P2 소유 → 제외, 공유는 표시)
const ADMIN_DIRS = [
  'screens/business_admin',
  'screens/super_admin',
];
const SHARED_DIRS = [
  'screens/common',
  'screens/contract',
  'widgets/admin',
];

function walk(dir) {
  const out = [];
  const abs = path.join(LIB, dir);
  if (!fs.existsSync(abs)) return out;
  for (const e of fs.readdirSync(abs, {withFileTypes: true})) {
    const rel = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(rel));
    else if (e.name.endsWith('.dart')) out.push(rel);
  }
  return out;
}

/** 주석을 걷어낸 코드만 본다. */
function codeOf(src) {
  return src.split(/\r?\n/)
      .filter((l) => !l.trimStart().startsWith('//'))
      .join('\n');
}

const count = (s, re) => (s.match(re) || []).length;

function audit(rel) {
  const s = codeOf(fs.readFileSync(path.join(LIB, rel), 'utf8'));
  const radii = [...new Set((s.match(/circular\((\d+(?:\.\d+)?)\)/g) || [])
      .map((m) => m.replace(/\D/g, '')))].sort((a, b) => a - b);
  return {
    file: rel.replace(/\\/g, '/'),
    lines: s.split('\n').length,
    // shell / 진입
    isScreen: /class \w+ extends (StatefulWidget|StatelessWidget)/.test(s) &&
        /Scaffold\(|GradientScaffold\(|AppModalShell\(|Dialog\(/.test(s),
    gradientScaffold: count(s, /GradientScaffold\(/g),
    rawScaffold: count(s, /\bScaffold\(/g),
    appBar: count(s, /AppBar\(/g),
    modalShell: count(s, /AppModalShell\(/g),
    rawDialog: count(s, /(?<!Styled|Modal|Alert)\bDialog\(/g),
    alertDialog: count(s, /AlertDialog\(/g),
    styledDialog: count(s, /StyledDialog|DialogHelper\./g),
    rawBottomSheet: count(s, /showModalBottomSheet\(/g),
    // D0 공용 컴포넌트
    emptyState: count(s, /AppEmptyState\(/g),
    searchBar: count(s, /AppSearchBar\(/g),
    summaryHeader: count(s, /AppSummaryHeader\(/g),
    statusCard: count(s, /AppStatusCard\(/g),
    batchBar: count(s, /AppBatchActionBar\(/g),
    commonWidgets: count(s, /CommonWidgets\./g),
    // 반응형 / 타이포
    responsive: count(s, /ResponsiveHelper\./g),
    hardFontSize: count(s, /fontSize:\s*\d/g),
    // 색
    appColors: count(s, /AppColors\./g),
    rawColor: count(s, /Color\(0x/g),
    colorsDot: count(s, /\bColors\.(?!transparent|white\b|black\b)/g),
    // 날짜
    dateFormat: count(s, /DateFormat\(/g),
    formatHelper: count(s, /FormatHelper\./g),
    radii,
  };
}

const files = [
  ...ADMIN_DIRS.flatMap(walk).map((f) => ({rel: f, scope: 'ADMIN'})),
  ...SHARED_DIRS.flatMap(walk).map((f) => ({rel: f, scope: 'SHARED'})),
];

const rows = files.map(({rel, scope}) => ({...audit(rel), scope}));
const screens = rows.filter((r) => r.isScreen);

console.log('═══ [R7-P1] 관리자 디자인 감사 (SOURCE READ ONLY) ═══');
console.log(`파일 ${rows.length}개 · 화면/다이얼로그 성격 ${screens.length}개`);
console.log('(정규화된 surface 단위이며 독립 화면 수가 아니다)');

// ── 1. D0 위반: 직접 Dialog / AlertDialog / showModalBottomSheet ──
console.log('\n── [V1] StyledDialog·DialogHelper 계약 위반 ──');
const v1 = rows.filter((r) => r.alertDialog > 0 || r.rawBottomSheet > 0);
v1.forEach((r) => console.log(
    `  ${r.scope} ${r.file}  AlertDialog=${r.alertDialog} showModalBottomSheet=${r.rawBottomSheet}`));
if (v1.length === 0) console.log('  없음');

// ── 2. ResponsiveHelper 미사용 + 하드코딩 타이포 ──
console.log('\n── [V2] ResponsiveHelper 0 + 하드코딩 fontSize (상위 15) ──');
rows.filter((r) => r.isScreen && r.responsive === 0 && r.hardFontSize > 0)
    .sort((a, b) => b.hardFontSize - a.hardFontSize)
    .slice(0, 15)
    .forEach((r) => console.log(
        `  ${r.scope} ${r.file}  fontSize=${r.hardFontSize} lines=${r.lines}`));

// ── 3. 구디자인(지원자 파란 그라디언트) 유입 ──
//
//   [정정 2026-09-27] 처음에는 `GradientScaffold` **미적용**을 위반으로 셌다.
//   그것이 거꾸로였다. `gradient_scaffold.dart` 는 스스로 이렇게 적는다:
//     "지원자 화면 공통 레이아웃 / 파란 그라디언트 헤더 + 32px 곡선"
//   현재 admin 언어는 `HOME-V2-08D.1` 이 규정한
//     grey50 배경 · surface 카드 · radius 16 · grey200 1px · shadow 없음
//   이고, 모달은 `flat white + grey200 divider + 3px brand accent` 다.
//   그래서 관리자 화면의 `GradientScaffold` 는 **구디자인 유입**이다.
console.log('\n── [V3] 구디자인 유입: 관리자 화면의 파란 GradientScaffold ──');
rows.filter((r) => r.gradientScaffold > 0)
    .sort((a, b) => b.lines - a.lines)
    .forEach((r) => console.log(`  ${r.scope} ${r.file}  lines=${r.lines}`));

// ── 4. radius 계약 이탈 ──
//   [정정] admin 카드는 radius **16** 이다(HOME-V2-08D.1 / 공고카드 03S.1).
//   12 는 아이콘 버튼·작은 요소. 메모리의 2026-06 기록(카드 12 · 그림자 .04/6)은
//   R7 리디자인 **이전** 값이므로 기준으로 쓰지 않는다.
console.log('\n── [V4] radius 계약 이탈 (admin: 카드16 / 버튼·칩 12·20 / 8·4 보조) ──');
const allowed = new Set(['4', '8', '10', '12', '16', '20']);
rows.filter((r) => r.radii.some((x) => !allowed.has(x)))
    .slice(0, 12)
    .forEach((r) => console.log(`  ${r.scope} ${r.file}  radii=[${r.radii.join(',')}]`));

// ── 5. 색 하드코딩 ──
console.log('\n── [V5] AppColors 밖 색 사용 (상위 12) ──');
rows.filter((r) => r.rawColor + r.colorsDot > 0)
    .sort((a, b) => (b.rawColor + b.colorsDot) - (a.rawColor + a.colorsDot))
    .slice(0, 12)
    .forEach((r) => console.log(
        `  ${r.scope} ${r.file}  Color(0x..)=${r.rawColor} Colors.*=${r.colorsDot} AppColors=${r.appColors}`));

// ── 6. 업무 날짜에 DateFormat ──
console.log('\n── [V6] DateFormat 사용 (KST 계약 확인 대상) ──');
rows.filter((r) => r.dateFormat > 0)
    .forEach((r) => console.log(
        `  ${r.scope} ${r.file}  DateFormat=${r.dateFormat} FormatHelper=${r.formatHelper}`));

// ── 7. 공용 컴포넌트 채택률 ──
console.log('\n── [V7] D0 공용 컴포넌트 채택 (화면 성격 파일 기준) ──');
for (const [k, label] of [
  ['emptyState', 'AppEmptyState'], ['searchBar', 'AppSearchBar'],
  ['summaryHeader', 'AppSummaryHeader'], ['statusCard', 'AppStatusCard'],
  ['batchBar', 'AppBatchActionBar'], ['gradientScaffold', 'GradientScaffold'],
  ['modalShell', 'AppModalShell'], ['styledDialog', 'StyledDialog/DialogHelper'],
]) {
  const n = screens.filter((r) => r[k] > 0).length;
  console.log(`  ${label.padEnd(26)} ${n}/${screens.length}`);
}

console.log('\n═══ 쓰기 0건 ═══');
