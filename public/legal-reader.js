/**
 * [R7-LEGAL.1C] 공개 법적 문서 페이지가 **현재 발행본**을 읽는 한 벌.
 *
 *   예전에는 두 페이지가 서로 달랐다.
 *     · /terms   — Firestore 를 읽되 버전·시행일 라벨이 `v2025.01` /
 *                  `2025년 1월 1일` 로 박혀 있었다. 성공해도 **틀린 시행일**
 *                  을 보여 줬다.
 *     · /privacy — 253줄 정적 전문. 슈퍼관리자가 발행해도 바뀌지 않았다.
 *                  고치려면 개발자가 HTML 을 다시 써야 했다(수동 복사 단계).
 *
 *   이제 둘 다 같은 경로를 쓴다.
 *
 *     app_settings/legal_terms   ← 지금 무엇이 공개 중인가 (current pointer)
 *               ↓ revisionId
 *     legal_revisions/{id}       ← 그 글이 무엇인가 (immutable evidence)
 *
 *   본문은 **발행본에서** 가져온다. projection 의 content 는 포인터가
 *   가리키는 글의 사본일 뿐이고, 증거는 고쳐 쓸 수 없는 쪽에 있다.
 *   아직 새 발행 경로를 거치지 않은 항목(revisionId 없음)은 projection 을
 *   쓰되 **검증되지 않았음**을 표시한다.
 *
 *   ── 절대 하지 않는 것 ────────────────────────────────────────
 *   조회에 실패했을 때 옛 전문을 현재 정책인 것처럼 보여 주지 않는다.
 *   그건 ERROR 를 SUCCESS 로 위장하는 일이고, 법적 문서에서는 그 위장이
 *   곧 "동의하지 않은 내용을 고지했다" 가 된다. 못 읽었으면 못 읽었다고
 *   말한다.
 */
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.AlfitLegal = api;
}(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  /** Firestore REST 값 → 평범한 JS 값. */
  function parseValue(v) {
    if (!v) return null;
    if (v.stringValue !== undefined) return v.stringValue;
    if (v.booleanValue !== undefined) return v.booleanValue;
    if (v.integerValue !== undefined) return parseInt(v.integerValue, 10);
    if (v.doubleValue !== undefined) return parseFloat(v.doubleValue);
    if (v.timestampValue !== undefined) return v.timestampValue;
    if (v.nullValue !== undefined) return null;
    if (v.arrayValue) return (v.arrayValue.values || []).map(parseValue);
    if (v.mapValue) {
      const obj = {};
      const f = v.mapValue.fields || {};
      for (const k of Object.keys(f)) obj[k] = parseValue(f[k]);
      return obj;
    }
    return null;
  }

  function parseDoc(doc) {
    if (!doc || !doc.fields) return null;
    const out = {};
    for (const k of Object.keys(doc.fields)) out[k] = parseValue(doc.fields[k]);
    return out;
  }

  /** 현재 공개 중인 항목 하나. 비활성·부재는 null 이다. */
  function pickItem(termsDoc, itemId) {
    const data = parseDoc(termsDoc);
    const items = (data && data.items) || [];
    if (!Array.isArray(items)) return null;
    const item = items.find(function (i) {
      return i && i.id === itemId;
    });
    if (!item) return null;
    if (item.isActive === false) return null;
    return item;
  }

  /**
   * 화면이 그릴 상태 하나.
   *
   *   SUCCESS_CURRENT    현재 발행본을 읽었다
   *   MISSING            이 항목이 공개 중이 아니다
   *   REVISION_MISMATCH  포인터가 가리키는 발행본을 찾을 수 없거나 어긋난다
   *   ERROR              읽지 못했다 — **미동의도, 옛 정책도 아니다**
   */
  function buildLegalView(input) {
    const o = input || {};
    if (o.fetchError) {
      return {
        state: 'ERROR',
        message: '현재 정책을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.',
      };
    }
    const item = pickItem(o.termsDoc, o.itemId);
    if (!item) {
      return {
        state: 'MISSING',
        message: '현재 공개 중인 문서를 찾을 수 없습니다.',
      };
    }

    const revisionId = item.revisionId || null;

    // 아직 새 발행 경로를 거치지 않은 항목. 지금 공개 중인 글은 이것이
    // 맞지만, 그 글이 고쳐지지 않았다는 증거는 없다.
    if (!revisionId) {
      return {
        state: 'SUCCESS_CURRENT',
        verified: false,
        itemId: item.id,
        title: item.title || '',
        version: item.version || '',
        revisionId: null,
        content: item.content || '',
      };
    }

    const rev = parseDoc(o.revisionDoc);
    if (!rev) {
      return {
        state: 'REVISION_MISMATCH',
        revisionId: revisionId,
        message: '현재 정책의 발행본을 확인하지 못했습니다.',
      };
    }
    if (rev.itemId !== item.id || rev.version !== item.version) {
      return {
        state: 'REVISION_MISMATCH',
        revisionId: revisionId,
        message: '현재 정책의 발행본 정보가 일치하지 않습니다.',
      };
    }

    return {
      state: 'SUCCESS_CURRENT',
      verified: true,
      itemId: item.id,
      // 제목·본문은 **발행본**에서 — 고쳐 쓸 수 없는 쪽이 증거다.
      title: rev.title || item.title || '',
      version: rev.version || '',
      revisionId: revisionId,
      content: rev.content || '',
      publishedAt: rev.publishedAt || null,
    };
  }

  /** 머리말에 쓸 한 줄. 시행일을 코드에 박지 않는다. */
  function versionLabel(view) {
    if (!view || view.state !== 'SUCCESS_CURRENT') return '';
    let s = '버전 ' + (view.version || '(미지정)');
    if (view.publishedAt) {
      s += ' · 발행 ' + String(view.publishedAt).slice(0, 10);
    }
    if (!view.verified) s += ' · 발행본 미등록';
    return s;
  }

  function esc(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  // ── 브라우저 전용 ──────────────────────────────────────────────
  async function fetchJson(url) {
    const r = await fetch(url);
    if (!r.ok) throw new Error('HTTP ' + r.status);
    return r.json();
  }

  async function loadAndRender(opts) {
    const itemId = opts.itemId;
    const card = document.getElementById(opts.cardId || 'content-card');
    const verEl = document.getElementById(opts.versionId || 'version-info');

    let view;
    try {
      const cfg = await fetchJson('/__/firebase/init.json');
      const base = 'https://firestore.googleapis.com/v1/projects/' +
        cfg.projectId + '/databases/(default)/documents';
      const termsDoc = await fetchJson(
        base + '/app_settings/legal_terms?key=' + cfg.apiKey);

      // 포인터를 먼저 보고, 가리키는 발행본이 있을 때만 한 번 더 읽는다.
      const item = pickItem(termsDoc, itemId);
      let revisionDoc = null;
      if (item && item.revisionId) {
        try {
          revisionDoc = await fetchJson(base + '/legal_revisions/' +
            encodeURIComponent(item.revisionId) + '?key=' + cfg.apiKey);
        } catch (e) {
          revisionDoc = null;   // mismatch 로 떨어진다 — 본문을 지어내지 않는다
        }
      }
      view = buildLegalView({termsDoc: termsDoc, revisionDoc: revisionDoc,
        itemId: itemId});
    } catch (e) {
      view = buildLegalView({fetchError: e, itemId: itemId});
    }

    if (view.state === 'SUCCESS_CURRENT') {
      if (verEl) verEl.textContent = versionLabel(view);
      card.innerHTML = '<pre class="content-text">' + esc(view.content) +
        '</pre>';
    } else {
      // 옛 전문을 현재 정책처럼 보여 주지 않는다.
      if (verEl) verEl.textContent = '';
      card.innerHTML = '<p class="error">' + esc(view.message) + '</p>';
    }
    return view;
  }

  return {
    parseValue: parseValue,
    parseDoc: parseDoc,
    pickItem: pickItem,
    buildLegalView: buildLegalView,
    versionLabel: versionLabel,
    loadAndRender: loadAndRender,
  };
}));
