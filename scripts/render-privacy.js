'use strict';
// [PRIVACY-REWRITE.1] 공개 개인정보처리방침을 **앱 원문에서** 생성한다.
//
//   공개 페이지와 앱 내부 정책이 각각 손으로 관리되던 동안 둘이 갈라졌다.
//   공개 페이지는 2026-08-01 에 멈춰 있었고 앱은 2026.09 였다. 읽는 사람은
//   어느 쪽이 진짜인지 알 수 없다.
//
//   그래서 원문을 한 곳에만 둔다 — lib/models/core/legal_terms_model.dart 의
//   _defaultPrivacyPolicy. 이 스크립트가 그것을 읽어 public/privacy.html 을
//   만든다. 내용을 바꾸려면 Dart 원문을 고쳐야 하고, 고친 뒤 이 스크립트를
//   다시 돌리지 않으면 계약 테스트가 실패한다.
//
//   사용법:  node scripts/render-privacy.js          (생성)
//            node scripts/render-privacy.js --check  (드리프트만 확인)

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const SRC = path.join(ROOT, 'lib', 'models', 'core', 'legal_terms_model.dart');
const OUT = path.join(ROOT, 'public', 'privacy.html');

function extract(dart, name) {
  const marker = `const ${name} = '''`;
  const i = dart.indexOf(marker);
  if (i < 0) throw new Error(`${name} 원문을 찾지 못했습니다.`);
  const start = i + marker.length;
  const end = dart.indexOf("''';", start);
  if (end < 0) throw new Error(`${name} 원문의 끝을 찾지 못했습니다.`);
  return dart.slice(start, end);
}

function revision(dart) {
  const m = dart.match(/const kPrivacyPolicyRevision = '([^']+)';/);
  if (!m) throw new Error('kPrivacyPolicyRevision 을 찾지 못했습니다.');
  return m[1];
}

/** 시행일 줄에서 사람이 읽는 날짜를 뽑는다. 없으면 빈 문자열. */
function effectiveDate(body) {
  const m = body.match(/본 처리방침은\s*([0-9]{4}년\s*[0-9]{1,2}월\s*[0-9]{1,2}일)/);
  return m ? m[1] : '';
}

const esc = (s) => s
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

function render(body, rev, eff) {
  return `<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>AlFit 개인정보 처리방침</title>
  <meta name="description" content="AlFit 개인정보 처리방침">
  <meta name="alfit-privacy-revision" content="${esc(rev)}">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans KR', sans-serif;
      font-size: 15px; line-height: 1.75; color: #1a1a1a; background: #f8f9fa;
    }
    .header { background: #1565C0; color: #fff; padding: 28px 24px 24px; }
    .header h1 { font-size: 22px; font-weight: 700; margin-bottom: 6px; }
    .header p { font-size: 13px; opacity: .85; }
    .container { max-width: 760px; margin: 0 auto; padding: 24px 16px 60px; }
    .card {
      background: #fff; border-radius: 10px; padding: 24px 20px;
      margin-bottom: 16px; box-shadow: 0 1px 3px rgba(0,0,0,.08);
    }
    .content-text {
      white-space: pre-wrap; font-family: inherit;
      font-size: 14px; line-height: 1.85; word-break: keep-all;
    }
    .nav { margin-top: 18px; font-size: 14px; }
    .nav a { color: #1565C0; text-decoration: none; font-weight: 600; }
    .nav a:hover { text-decoration: underline; }
    .foot { margin-top: 20px; font-size: 12px; color: #666; text-align: center; }
    @media (max-width: 420px) { .card { padding: 18px 14px; } }
  </style>
</head>
<body>
  <div class="header">
    <h1>AlFit 개인정보 처리방침</h1>
    <p>개정 ${esc(rev)}${eff ? ` · 시행일 ${esc(eff)}` : ''}</p>
  </div>
  <div class="container">
    <div class="card">
      <div class="content-text">${esc(body)}</div>
    </div>
    <div class="card nav">
      <p>계정을 삭제하시려면 <a href="/account-deletion">계정 삭제 요청</a> 페이지를 이용해 주세요.</p>
    </div>
    <p class="foot">이 페이지는 앱에 표시되는 개인정보 처리방침과 같은 원문에서 생성됩니다.</p>
  </div>
</body>
</html>
`;
}

function main() {
  const dart = fs.readFileSync(SRC, 'utf8');
  const body = extract(dart, '_defaultPrivacyPolicy');
  const rev = revision(dart);
  const html = render(body, rev, effectiveDate(body));

  if (process.argv.includes('--check')) {
    const cur = fs.existsSync(OUT) ? fs.readFileSync(OUT, 'utf8') : '';
    if (cur === html) {
      console.log(`공개 페이지가 원문과 일치합니다. (개정 ${rev})`);
      process.exit(0);
    }
    console.error('공개 페이지가 앱 원문과 다릅니다. ' +
      '`node scripts/render-privacy.js` 를 실행하세요.');
    process.exit(1);
  }

  fs.writeFileSync(OUT, html, 'utf8');
  console.log(`public/privacy.html 생성 완료 (개정 ${rev}, ${body.length}자)`);
}

main();
