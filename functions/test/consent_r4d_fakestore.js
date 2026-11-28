/**
 * [CONSENT-R4b] 메모리 가짜 Firestore + admin 네임스페이스 — consent_r4b_callables.test.js 전용 보조.
 *
 *   정적 작성물이다(작성 시점 실행 0). LOCAL 에서 A_copy/functions/test/ 에 시험 파일과 함께 둔다.
 *   외부 의존 0(Node 내장만). 네트워크·실제 Firestore·admin SDK 를 쓰지 않는다.
 *
 *   흉내 내는 것(두 callable 과 그 의존 폐포가 실제로 부르는 범위 — 작성자가 후보 index.ts 에서 확인):
 *     · collection()/doc()/doc() 자동 id/collection(하위)/add()/get()/set()/update()/create()/delete()
 *     · 쿼리 where(== != < <= > >= in not-in array-contains array-contains-any)·orderBy·limit·
 *       limitToLast·offset·startAfter(문서 스냅샷)·select·get()·count().get()
 *     · db.getAll · db.batch() · db.collectionGroup · db.doc
 *     · runTransaction(cb): tx.get(문서|쿼리)·tx.getAll·tx.set/update/create/delete 를 **버퍼**에 쌓고
 *       cb 가 끝나야 한꺼번에 반영한다(재시도 없음). 쓰기 뒤 tx.get 은 실제 SDK 처럼 던진다.
 *       update 대상 없음(NOT_FOUND 5)·create 대상 있음(ALREADY_EXISTS 6)은 커밋 시 전체 취소.
 *     · FieldValue.increment/arrayUnion/arrayRemove/delete/serverTimestamp — update 의 점 경로
 *       (`workDetailCounts.wd-1.confirmedCount`)를 경로로, set 의 키는 글자 그대로 다룬다.
 *     · Timestamp(now/fromMillis/fromDate · toMillis/toDate/seconds/nanoseconds/isEqual)
 *
 *   계측(W): reads(모든 읽기) · attempts(트랜잭션 쓰기 **시도**, 호출 시점 기록) ·
 *            commits(커밋된 트랜잭션별 쓰기 목록) · aborts(던져진 트랜잭션) ·
 *            direct(트랜잭션 밖 쓰기: ref.set/update/create/delete·add·batch).
 *   알림은 후보 코드에서 `srvPersistNotificationWithId` 가 **별도 트랜잭션의 tx.create** 로,
 *   좌석 겹침 알림은 `srvPersistNotificationInTx` 가 **호출자 트랜잭션의 tx.set** 으로 남긴다
 *   (candidate index.ts:52343-52346 · 52461-52464). 그래서 알림 집계는 경로
 *   `users/{uid}/notifications/*` 로 한다(커밋된 것만).
 */
'use strict';

const RealDate = Date;

/**
 * 가짜 저장소 하나를 만든다.
 *
 * @param {{now: function(): number}} opts 주입 시계(epoch ms)
 * @return {object} db·admin·Ts·FieldValue·W·도우미
 */
function createFakeFirestore(opts) {
  const nowMs = () => opts.now();

  // ── Timestamp ──────────────────────────────────────────────────────────
  class Ts {
    constructor(ms) {
      if (typeof ms !== 'number' || !Number.isFinite(ms)) {
        throw new Error('가짜 Timestamp 에 유한 ms 가 아닌 값: ' + String(ms));
      }
      this._ms = ms;
    }
    toMillis() { return this._ms; }
    toDate() { return new RealDate(this._ms); }
    get seconds() { return Math.floor(this._ms / 1000); }
    get nanoseconds() { return (((this._ms % 1000) + 1000) % 1000) * 1e6; }
    isEqual(o) { return o instanceof Ts && o._ms === this._ms; }
    toJSON() { return {__ts: this._ms}; }
    static now() { return new Ts(nowMs()); }
    static fromMillis(ms) { return new Ts(ms); }
    static fromDate(d) { return new Ts(d.getTime()); }
  }

  // ── FieldValue ─────────────────────────────────────────────────────────
  class FV {
    constructor(kind, args) { this.kind = kind; this.args = args; }
  }
  const FieldValue = {
    increment: (n) => new FV('increment', [n]),
    arrayUnion: (...els) => new FV('arrayUnion', els),
    arrayRemove: (...els) => new FV('arrayRemove', els),
    delete: () => new FV('delete', []),
    serverTimestamp: () => new FV('serverTimestamp', []),
  };
  const isFV = (v, kind) => v instanceof FV && (kind === undefined || v.kind === kind);
  class FieldPath {
    constructor(...segs) { this.segs = segs; }
    static documentId() { return new FieldPath('__name__'); }
  }

  // ── 값 도우미 ──────────────────────────────────────────────────────────
  const isPlain = (v) => v !== null && typeof v === 'object' && !Array.isArray(v) &&
    (Object.getPrototypeOf(v) === Object.prototype || Object.getPrototypeOf(v) === null);
  function clone(v) {
    if (Array.isArray(v)) return v.map(clone);
    if (isPlain(v)) {
      const o = {};
      for (const k of Object.keys(v)) o[k] = clone(v[k]);
      return o;
    }
    return v; // 원시값 · Ts(불변) · FV · 그 밖의 객체는 그대로
  }
  function deq(a, b) {
    if (a === b) return true;
    if (a instanceof Ts || b instanceof Ts) {
      return a instanceof Ts && b instanceof Ts && a._ms === b._ms;
    }
    if (Array.isArray(a) || Array.isArray(b)) {
      if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false;
      return a.every((x, i) => deq(x, b[i]));
    }
    if (isPlain(a) && isPlain(b)) {
      const ka = Object.keys(a).sort();
      const kb = Object.keys(b).sort();
      if (ka.length !== kb.length || ka.some((k, i) => k !== kb[i])) return false;
      return ka.every((k) => deq(a[k], b[k]));
    }
    if (a instanceof FV && b instanceof FV) {
      return a.kind === b.kind && deq(a.args, b.args);
    }
    return false;
  }
  /** 비교·출력용 정규형 — Ts 는 {__ts: ms}, FV 는 {__fv, args}. */
  function canon(v) {
    if (v instanceof Ts) return {__ts: v._ms};
    if (v instanceof FV) return {__fv: v.kind, args: canon(v.args)};
    if (Array.isArray(v)) return v.map(canon);
    if (isPlain(v)) {
      const o = {};
      for (const k of Object.keys(v).sort()) o[k] = canon(v[k]);
      return o;
    }
    return v;
  }
  function cmpVal(a, b) {
    const n = (x) => (x instanceof Ts ? x._ms : x);
    const x = n(a);
    const y = n(b);
    if (x === y) return 0;
    if (x === undefined || x === null) return -1;
    if (y === undefined || y === null) return 1;
    return x < y ? -1 : 1;
  }
  function getPath(obj, field, docId) {
    if (field instanceof FieldPath) {
      if (field.segs.length === 1 && field.segs[0] === '__name__') return docId;
      field = field.segs.join('.');
    }
    if (field === '__name__') return docId;
    let cur = obj;
    for (const seg of String(field).split('.')) {
      if (cur === null || cur === undefined || typeof cur !== 'object') return undefined;
      cur = cur[seg];
    }
    return cur;
  }

  const DELETE = Symbol('DELETE');
  /** 센티널을 실제 값으로. existing 은 그 자리의 현재 값. */
  function resolve(v, existing, commitTs) {
    if (v instanceof FV) {
      switch (v.kind) {
      case 'increment':
        return (typeof existing === 'number' ? existing : 0) + v.args[0];
      case 'arrayUnion': {
        const base = Array.isArray(existing) ? clone(existing) : [];
        for (const el of v.args) if (!base.some((x) => deq(x, el))) base.push(clone(el));
        return base;
      }
      case 'arrayRemove': {
        const base = Array.isArray(existing) ? clone(existing) : [];
        return base.filter((x) => !v.args.some((el) => deq(x, el)));
      }
      case 'serverTimestamp':
        return commitTs;
      case 'delete':
        return DELETE;
      default:
        throw new Error('모르는 FieldValue: ' + v.kind);
      }
    }
    if (Array.isArray(v)) return v.map((x) => resolve(x, undefined, commitTs));
    if (isPlain(v)) {
      const o = {};
      for (const k of Object.keys(v)) {
        const r = resolve(v[k], undefined, commitTs);
        if (r !== DELETE) o[k] = r;
      }
      return o;
    }
    return clone(v);
  }
  function mergeInto(base, data, commitTs) {
    for (const k of Object.keys(data)) {
      const v = data[k];
      if (isPlain(v)) {
        if (!isPlain(base[k])) base[k] = {};
        mergeInto(base[k], v, commitTs);
      } else {
        const r = resolve(v, base[k], commitTs);
        if (r === DELETE) delete base[k];
        else base[k] = r;
      }
    }
  }
  class FsError extends Error {
    constructor(code, message) { super(message); this.code = code; }
  }
  /**
   * 실제 SDK 처럼 쓰기 **호출 시점**에 undefined 값을 거절한다. 이 프로젝트는
   * ignoreUndefinedProperties 를 켜지 않는다(후보 index.ts:510-541 주석).
   */
  function assertNoUndefined(v, where) {
    if (v === undefined) {
      throw new Error('Value for argument "data" is not a valid Firestore document. ' +
        `Cannot use "undefined" as a Firestore value (found in field "${where}").`);
    }
    if (v instanceof FV) {
      for (const a of v.args) assertNoUndefined(a, where);
      return;
    }
    if (Array.isArray(v)) {
      v.forEach((x, i) => assertNoUndefined(x, `${where}.${i}`));
      return;
    }
    if (isPlain(v)) {
      for (const k of Object.keys(v)) assertNoUndefined(v[k], where ? `${where}.${k}` : k);
    }
  }
  function validateWrite(op, data) {
    if (op === 'delete') return;
    if (!isPlain(data)) throw new Error(`${op}: 문서 데이터가 일반 객체가 아니다`);
    assertNoUndefined(data, '');
  }
  /** 쓰기 하나를 문서 값에 적용 — 결과(undefined = 삭제). */
  function applyOne(cur, w, commitTs) {
    switch (w.op) {
    case 'set': {
      if (w.opts && (w.opts.merge === true || Array.isArray(w.opts.mergeFields))) {
        const base = isPlain(cur) ? clone(cur) : {};
        mergeInto(base, w.data, commitTs);
        return base;
      }
      return resolve(w.data, undefined, commitTs);
    }
    case 'create':
      if (cur !== undefined) throw new FsError(6, `ALREADY_EXISTS: ${w.path}`);
      return resolve(w.data, undefined, commitTs);
    case 'update': {
      if (cur === undefined) throw new FsError(5, `NOT_FOUND: ${w.path}`);
      const base = clone(cur);
      for (const key of Object.keys(w.data)) {
        const segs = key.split('.');
        let node = base;
        for (let i = 0; i < segs.length - 1; i++) {
          if (!isPlain(node[segs[i]])) node[segs[i]] = {};
          node = node[segs[i]];
        }
        const leaf = segs[segs.length - 1];
        const r = resolve(w.data[key], node[leaf], commitTs);
        if (r === DELETE) delete node[leaf];
        else node[leaf] = r;
      }
      return base;
    }
    case 'delete':
      return undefined;
    default:
      throw new Error('모르는 쓰기: ' + w.op);
    }
  }

  // ── 저장소·계측 ────────────────────────────────────────────────────────
  const STORE = new Map();
  const W = {reads: [], attempts: [], commits: [], aborts: [], direct: [], txSeq: 0, batchSeq: 0};
  // [r4c] afterDirect — 트랜잭션 밖 쓰기(예: 감사 로그 add)가 끝난 직후(시계 이동 반례용).
  const hooks = {afterGet: null, beforeCommit: null, afterDirect: null, afterQuery: null};
  // [s296] 선택형 낙관적 동시성(OCC) — occ.enabled=true 일 때만. 거래가 읽은 문서 버전·쿼리 결과가 커밋 시점에 바뀌었으면
  //   그 시도를 버리고(쓰기 0) 처음부터 다시 한다(최대 5회 · Firestore 거래 재시도 모형). 기본값 false = 기존 시험 동작 불변.
  const occ = {enabled: false, retries: 0};
  const VER = new Map();
  const bump = (p) => VER.set(p, (VER.get(p) || 0) + 1);
  const TXREADS = new Map();
  let autoSeq = 0;
  const EXT_TOUCHED = [];
  const STORAGE_CALLS = [];

  function reset() {
    STORE.clear();
    W.reads.length = 0; W.attempts.length = 0; W.commits.length = 0;
    W.aborts.length = 0; W.direct.length = 0;
    hooks.afterGet = null; hooks.beforeCommit = null; hooks.afterDirect = null; hooks.afterQuery = null;
    STORAGE_CALLS.length = 0;
    occ.enabled = false; occ.retries = 0; VER.clear(); TXREADS.clear();
  }
  function clearLog() {
    W.reads.length = 0; W.attempts.length = 0; W.commits.length = 0;
    W.aborts.length = 0; W.direct.length = 0;
  }

  /** 쓰기 묶음을 원자적으로 반영한다. 검증 실패면 아무것도 반영하지 않고 던진다. */
  function commitAtomically(writes) {
    const commitTs = new Ts(nowMs());
    const work = new Map();
    for (const w of writes) {
      const cur = work.has(w.path) ? work.get(w.path) : STORE.get(w.path);
      work.set(w.path, applyOne(cur, w, commitTs));
    }
    for (const [p, v] of work) {
      if (v === undefined) STORE.delete(p);
      else STORE.set(p, v);
      bump(p);
    }
  }

  function snapOf(p, raw) {
    const d = raw === undefined ? undefined : clone(raw);
    const id = p.split('/').pop();
    return {
      id,
      ref: docRef(p),
      exists: d !== undefined,
      data: () => (d === undefined ? undefined : clone(d)),
      get: (f) => (d === undefined ? undefined : clone(getPath(d, f, id))),
      readTime: new Ts(nowMs()),
      createTime: d === undefined ? undefined : new Ts(0),
      updateTime: d === undefined ? undefined : new Ts(0),
    };
  }
  function readDoc(p, txId) {
    W.reads.push({tx: txId, kind: 'doc', path: p});
    if (txId && TXREADS.has(txId)) TXREADS.get(txId).docs.set(p, VER.get(p) || 0);
    const s = snapOf(p, STORE.get(p));
    if (hooks.afterGet) hooks.afterGet(p, txId);
    return s;
  }
  function runQuery(q, txId, silent) {
    const sp = q._spec;
    if (!silent) {
      W.reads.push({tx: txId, kind: 'query', path: sp.group ? '**/' + sp.cp : sp.cp,
        filters: sp.filters.map((f) => [String(f[0]), f[1], canon(f[2])]), limit: sp.lim});
    }
    let rows = [];
    for (const [k, v] of STORE) {
      const segs = k.split('/');
      if (sp.group) {
        if (segs.length < 2 || segs[segs.length - 2] !== sp.cp) continue;
      } else {
        const prefix = sp.cp + '/';
        if (!k.startsWith(prefix) || k.slice(prefix.length).includes('/')) continue;
      }
      const id = segs[segs.length - 1];
      const ok = sp.filters.every(([f, op, x]) => {
        const fv = getPath(v, f, id);
        switch (op) {
        case '==': return deq(fv, x);
        case '!=': return fv !== undefined && !deq(fv, x);
        case '<': return fv !== undefined && cmpVal(fv, x) < 0;
        case '<=': return fv !== undefined && cmpVal(fv, x) <= 0;
        case '>': return fv !== undefined && cmpVal(fv, x) > 0;
        case '>=': return fv !== undefined && cmpVal(fv, x) >= 0;
        case 'in': return Array.isArray(x) && x.some((y) => deq(fv, y));
        case 'not-in': return fv !== undefined && Array.isArray(x) && !x.some((y) => deq(fv, y));
        case 'array-contains': return Array.isArray(fv) && fv.some((y) => deq(y, x));
        case 'array-contains-any':
          return Array.isArray(fv) && Array.isArray(x) && fv.some((y) => x.some((z) => deq(y, z)));
        default: throw new Error('모르는 where 연산자: ' + op);
        }
      });
      if (ok) rows.push([k, v]);
    }
    rows.sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
    if (sp.orders.length) {
      rows.sort((a, b) => {
        for (const [f, dir] of sp.orders) {
          const c = cmpVal(getPath(a[1], f, a[0].split('/').pop()), getPath(b[1], f, b[0].split('/').pop()));
          if (c !== 0) return dir === 'desc' ? -c : c;
        }
        return 0;
      });
    }
    if (sp.after) {
      const i = rows.findIndex((r) => r[0] === sp.after);
      rows = i >= 0 ? rows.slice(i + 1) : rows;
    }
    if (sp.off) rows = rows.slice(sp.off);
    if (sp.lastN !== undefined) rows = rows.slice(Math.max(0, rows.length - sp.lastN));
    if (sp.lim !== undefined) rows = rows.slice(0, sp.lim);
    const docs = rows.map(([k, v]) => {
      let data = v;
      if (sp.sel) {
        data = {};
        for (const f of sp.sel) {
          const x = getPath(v, f);
          if (x !== undefined) data[f] = x;
        }
      }
      return snapOf(k, data);
    });
    if (!silent && txId && TXREADS.has(txId)) {
      TXREADS.get(txId).queries.push({q, sig: rows.map(([k]) => k + '#' + (VER.get(k) || 0)).join('|')});
    }
    if (!silent && hooks.afterQuery) hooks.afterQuery(sp.cp, txId);
    return {docs, size: docs.length, empty: docs.length === 0,
      forEach: (fn) => docs.forEach(fn), query: q, readTime: new Ts(nowMs())};
  }

  function makeQuery(cp, spec) {
    const sp = Object.assign({cp, filters: [], orders: [], lim: undefined, lastN: undefined,
      off: 0, sel: null, after: null, group: false}, spec || {});
    const q = {
      __kind: 'query',
      _spec: sp,
      where: (f, op, v) => makeQuery(cp, Object.assign({}, sp, {filters: [...sp.filters, [f, op, v]]})),
      orderBy: (f, dir) => makeQuery(cp, Object.assign({}, sp, {orders: [...sp.orders, [f, dir || 'asc']]})),
      limit: (n) => makeQuery(cp, Object.assign({}, sp, {lim: n})),
      limitToLast: (n) => makeQuery(cp, Object.assign({}, sp, {lastN: n})),
      offset: (n) => makeQuery(cp, Object.assign({}, sp, {off: n})),
      select: (...f) => makeQuery(cp, Object.assign({}, sp, {sel: f})),
      startAfter: (s) => makeQuery(cp, Object.assign({}, sp, {after: s && s.ref ? s.ref.path : null})),
      get: async () => runQuery(q, null),
      count: () => ({get: async () => {
        const r = runQuery(q, null);
        return {data: () => ({count: r.size})};
      }}),
      withConverter: () => q,
    };
    return q;
  }

  /** 트랜잭션 밖 쓰기 — 기록(ok=false) → 반영 → ok=true. 반영 실패면 ok=false 로 남고 던진다. */
  function directWrite(op, p, data, wopts) {
    validateWrite(op, data);
    const w = {op, path: p, data: data === undefined ? undefined : Object.assign({}, data), opts: wopts};
    const rec = Object.assign({batch: null, ok: false}, w);
    W.direct.push(rec);
    commitAtomically([w]);
    rec.ok = true;
    if (hooks.afterDirect) hooks.afterDirect(rec);
  }

  function colRef(cp) {
    const segs = cp.split('/');
    const q = makeQuery(cp);
    return Object.assign(q, {
      id: segs[segs.length - 1],
      path: cp,
      parent: segs.length > 1 ? docRef(segs.slice(0, -1).join('/')) : null,
      doc: (id) => {
        if (id === undefined) {
          autoSeq++;
          id = 'auto' + String(autoSeq).padStart(4, '0');
        }
        return docRef(cp + '/' + id);
      },
      add: async (data) => {
        autoSeq++;
        const ref = docRef(cp + '/auto' + String(autoSeq).padStart(4, '0'));
        directWrite('create', ref.path, data);
        return ref;
      },
    });
  }
  function docRef(p) {
    const segs = p.split('/');
    if (segs.length % 2 !== 0 || segs.some((s) => s.length === 0)) {
      throw new Error('문서 경로가 아니다: ' + p);
    }
    const ref = {
      __kind: 'doc',
      id: segs[segs.length - 1],
      path: p,
      get parent() { return colRef(segs.slice(0, -1).join('/')); },
      collection: (c) => colRef(p + '/' + c),
      get: async () => readDoc(p, null),
      set: async (d, o) => { directWrite('set', p, d, o); return {}; },
      update: async (d) => { directWrite('update', p, d); return {}; },
      create: async (d) => { directWrite('create', p, d); return {}; },
      delete: async () => { directWrite('delete', p); return {}; },
      isEqual: (o) => !!o && o.path === p,
      withConverter: () => ref,
    };
    return ref;
  }

  async function runTransaction(cb) {
    if (!occ.enabled) return runTransactionOnce(cb);
    for (let i = 0; ; i++) {
      try {
        return await runTransactionOnce(cb, true);
      } catch (e) {
        if (!(e && e.__occConflict) || i >= 4) throw e;
        occ.retries++;
      }
    }
  }
  async function runTransactionOnce(cb, track) {
    const txId = ++W.txSeq;
    if (track) TXREADS.set(txId, {docs: new Map(), queries: []});
    const buf = [];
    let wrote = false;
    const rec = (op, ref, data, wopts) => {
      if (!ref || ref.__kind !== 'doc') throw new Error('트랜잭션 쓰기 대상이 문서 ref 가 아니다');
      validateWrite(op, data);
      const w = {tx: txId, op, path: ref.path,
        data: data === undefined ? undefined : Object.assign({}, data), opts: wopts};
      W.attempts.push(w);
      buf.push(w);
      wrote = true;
    };
    const tx = {
      get: async (x) => {
        if (wrote) {
          throw new Error('Firestore transactions require all reads to be executed before all writes.');
        }
        if (x && x.__kind === 'query') return runQuery(x, txId);
        if (x && x.__kind === 'doc') return readDoc(x.path, txId);
        throw new Error('tx.get 에 ref/쿼리가 아닌 값');
      },
      getAll: async (...refs) => {
        if (wrote) {
          throw new Error('Firestore transactions require all reads to be executed before all writes.');
        }
        return refs.filter((r) => r && r.__kind === 'doc').map((r) => readDoc(r.path, txId));
      },
      set: (ref, data, wopts) => { rec('set', ref, data, wopts); return tx; },
      update: (ref, data) => { rec('update', ref, data); return tx; },
      create: (ref, data) => { rec('create', ref, data); return tx; },
      delete: (ref) => { rec('delete', ref); return tx; },
    };
    let out;
    try {
      out = await cb(tx);
    } catch (e) {
      W.aborts.push({tx: txId, attempts: buf.length, error: e});
      throw e;
    }
    try {
      if (track) {
        const rs = TXREADS.get(txId);
        TXREADS.delete(txId);
        let conflict = false;
        for (const [p, v] of rs.docs) if ((VER.get(p) || 0) !== v) conflict = true;
        for (const {q, sig} of rs.queries) {
          const r = runQuery(q, null, true);
          if (r.docs.map((d) => d.ref.path + '#' + (VER.get(d.ref.path) || 0)).join('|') !== sig) conflict = true;
        }
        if (conflict) {
          const ce = new Error('ABORTED: 거래 read-set 이 바뀌었다(OCC)');
          ce.__occConflict = true;
          throw ce;
        }
      }
      if (hooks.beforeCommit) hooks.beforeCommit(txId, buf);
      commitAtomically(buf);
    } catch (e) {
      W.aborts.push({tx: txId, attempts: buf.length, error: e, atCommit: true});
      throw e;
    }
    W.commits.push({tx: txId, writes: buf});
    return out;
  }

  const db = {
    collection: (c) => colRef(c),
    doc: (p) => docRef(p),
    collectionGroup: (name) => makeQuery(name, {group: true}),
    runTransaction,
    getAll: async (...refs) => refs.filter((r) => r && r.__kind === 'doc').map((r) => readDoc(r.path, null)),
    batch: () => {
      const id = ++W.batchSeq;
      const ops = [];
      const b = {
        set: (ref, data, wopts) => {
          validateWrite('set', data);
          ops.push({op: 'set', path: ref.path, data: Object.assign({}, data), opts: wopts});
          return b;
        },
        update: (ref, data) => {
          validateWrite('update', data);
          ops.push({op: 'update', path: ref.path, data: Object.assign({}, data)});
          return b;
        },
        create: (ref, data) => {
          validateWrite('create', data);
          ops.push({op: 'create', path: ref.path, data: Object.assign({}, data)});
          return b;
        },
        delete: (ref) => { ops.push({op: 'delete', path: ref.path}); return b; },
        commit: async () => {
          const recs = ops.map((w) => Object.assign({batch: id, ok: false}, w));
          W.direct.push(...recs);
          commitAtomically(ops);
          for (const r of recs) r.ok = true;
          return [];
        },
      };
      return b;
    },
  };

  // ── 관대한 대용품(알 수 없는 외부 기능) — 닿으면 기록한다 ─────────────
  function lenient(name) {
    const fn = function() {};
    return new Proxy(fn, {
      get: (_t, k) => {
        if (k === 'then') return undefined; // await 가 멈추지 않게
        if (k === Symbol.toPrimitive) return () => `[stub ${name}]`;
        EXT_TOUCHED.push(`${name}.${String(k)}`);
        return lenient(`${name}.${String(k)}`);
      },
      apply: () => { EXT_TOUCHED.push(`${name}()`); return lenient(`${name}()`); },
      construct: () => { EXT_TOUCHED.push(`new ${name}`); return lenient(`new ${name}`); },
    });
  }

  const storage = {
    bucket: () => ({
      name: 'fake-bucket',
      file: (p) => ({
        name: p,
        exists: async () => { STORAGE_CALLS.push(['exists', p]); return [true]; },
        getSignedUrl: async () => { STORAGE_CALLS.push(['getSignedUrl', p]); return ['https://fake/' + p]; },
        delete: async () => { STORAGE_CALLS.push(['delete', p]); return []; },
      }),
    }),
  };
  const firestoreNs = Object.assign(() => db, {Timestamp: Ts, FieldValue, FieldPath});
  const admin = {
    firestore: firestoreNs,
    storage: () => storage,
    auth: () => lenient('admin.auth()'),
    messaging: () => lenient('admin.messaging()'),
    initializeApp: () => ({}),
    apps: [],
  };

  return {
    db, admin, Ts, FV, FieldValue, FieldPath, isFV, W, hooks, STORE, EXT_TOUCHED, STORAGE_CALLS,
    lenient, canon, deq, clone, reset, clearLog,
    /** 시드 — 계측에 남기지 않는다. */
    put: (p, data) => { docRef(p); STORE.set(p, clone(data)); bump(p); },
    occ,
    /** 현재 값(사본) — 계측에 남기지 않는다. */
    get: (p) => (STORE.has(p) ? clone(STORE.get(p)) : undefined),
    del: (p) => { STORE.delete(p); bump(p); },
    has: (p) => STORE.has(p),
    /** 전체 저장소 정규형(비교용). */
    dump: () => {
      const o = {};
      for (const k of [...STORE.keys()].sort()) o[k] = canon(STORE.get(k));
      return o;
    },
  };
}

module.exports = {createFakeFirestore};
