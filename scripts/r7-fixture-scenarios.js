/**
 * [R7-PRE0] 시나리오 빌더.
 *
 * 각 빌더는 canonical writer 만 불러 상태를 만들고, manifest 에 남길
 * entity id 와 "기대 사실"을 돌려준다. R7 에서 스크린샷·버그 보고가
 * 이 id 를 그대로 참조한다.
 *
 * 규칙
 *   · 불가능한 조합을 만들지 않는다 — CF 를 지나면 애초에 만들어지지 않는다.
 *   · 랜덤 대량 생성하지 않는다. 각 fixture 는 확인 목적이 하나씩 있다.
 *   · 실패하면 던진다. 반쯤 만들어진 상태로 넘어가지 않는다.
 */
'use strict';

const zlib = require('zlib');
const {callAs, kstMidnightMs, kstDateKey, kstWeekday} = require('./r7-fixture-lib');

const TITLE_PREFIX = '[R7FIX]';

// ── 서명·PDF 산출물 ──────────────────────────────────────────────────
//
//   계약 fixture 는 서명 이미지와 PDF 를 실제로 올려야 한다(CF 가 요구한다).
//   실제 사람의 서명을 쓰지 않는다 — 여기서 그려 만든다. 1×1 투명 PNG 로
//   때우면 R7 에서 서명란이 비어 보이고, 그걸 제품 버그로 오인하게 된다.

const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    t[n] = c;
  }
  return t;
})();

function crc32(buf) {
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xFF] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}

function pngChunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}

/**
 * 서명처럼 보이는 획 하나를 그린 흑백 PNG. 고정 입력 → 고정 출력이므로
 * 같은 fixture 를 다시 만들어도 같은 해시가 나온다.
 */
function signaturePng(w = 240, h = 90) {
  const raw = Buffer.alloc((w * 4 + 1) * h, 0);
  const px = (x, y, a) => {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    const o = y * (w * 4 + 1) + 1 + x * 4;
    raw[o] = 0x1F; raw[o + 1] = 0x2A; raw[o + 2] = 0x3C; raw[o + 3] = a;
  };
  // 사인 곡선 한 획 — 굵기 3px.
  for (let x = 12; x < w - 12; x++) {
    const t = (x - 12) / (w - 24);
    const y = Math.round(h / 2 + Math.sin(t * Math.PI * 2.4) * (h / 3) * (1 - t * 0.35));
    for (let d = -1; d <= 1; d++) px(x, y + d, 255);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8;    // bit depth
  ihdr[9] = 6;    // RGBA
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
    pngChunk('IHDR', ihdr),
    pngChunk('IDAT', zlib.deflateSync(raw)),
    pngChunk('IEND', Buffer.alloc(0)),
  ]);
}

/** 한 장짜리 유효 PDF. xref offset 을 실제로 계산한다 — 뷰어가 열 수 있어야 한다. */
function onePagePdf(lines) {
  const text = lines
      .map((s, i) => `BT /F1 12 Tf 60 ${740 - i * 20} Td (${
        String(s).replace(/([\\()])/g, '\\$1')}) Tj ET`)
      .join('\n');
  const objs = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] ' +
      '/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
    `<< /Length ${Buffer.byteLength(text)} >>\nstream\n${text}\nendstream`,
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  let out = '%PDF-1.4\n';
  const offsets = [];
  objs.forEach((o, i) => {
    offsets.push(Buffer.byteLength(out));
    out += `${i + 1} 0 obj\n${o}\nendobj\n`;
  });
  const xref = Buffer.byteLength(out);
  out += `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n` +
      offsets.map((o) => String(o).padStart(10, '0') + ' 00000 n \n').join('');
  out += `trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\n` +
      `startxref\n${xref}\n%%EOF\n`;
  return Buffer.from(out, 'latin1');
}

/**
 * 업무 상세 한 벌. wdId 는 CF(createFlexSlots)가 부여한다.
 *
 * payScheduleType 은 서버 필수값이다 — 없으면 공고 생성이 거절된다.
 * (근태 레코드의 payScheduleType 이 null 인 상태는 이것과 다른 축이다.
 *  그건 정산 전이라 wageDetail 자체가 없는 경우다 — PAY-01 참조.)
 */
function workDetail({
  workType, start, end, required, wage = 12000,
  payScheduleType = 'same_day', payScheduleDay,
}) {
  return {
    workType,
    workTypeIcon: '📋',
    startTime: start,
    endTime: end,
    requiredCount: required,
    wage,
    wageType: 'hourly',
    breakMinutes: 0,
    nightAllowanceApplied: true,
    nightIncluded: false,
    weeklyHolidayIncluded: false,
    payScheduleType,
    ...(payScheduleDay != null ? {payScheduleDay} : {}),
  };
}

/** flex 공고 생성 + 슬롯 + 공개. createTO 의 클라이언트 오케스트레이션과 같은 순서. */
async function createFlexPosting(ctx, {scenarioId, title, dayOffsets, wds}) {
  const dates = dayOffsets.map((o) => kstDateKey(o));
  const toData = {
    businessId: ctx.businessId,
    businessName: ctx.businessName,
    type: 'flex',
    title: `${TITLE_PREFIX} ${title}`,
    description: `R7 fixture — ${scenarioId}`,
    workDetails: wds,
    totalSlots: dates.length,
    totalRequired: wds.reduce((s, w) => s + w.requiredCount, 0) * dates.length,
    totalConfirmed: 0,
    totalPending: 0,
    rangeStart: kstMidnightMs(Math.min(...dayOffsets)),
    rangeEnd: kstMidnightMs(Math.max(...dayOffsets)),
    workDays: [],
    deadlineType: 'HOURS_BEFORE',
    hoursBeforeStart: 2,
    postingDurationDays: 30,
    creatorUID: ctx.adminUid,
    // 슬롯이 생기기 전에 공개되지 않게 — 클라이언트와 같은 deferred 경로.
    publishMode: 'deferred',
    isPublished: false,
    status: 'SCHEDULED',
    isManualClosed: false,
  };

  const created = await callAs(ctx.adminUid, 'callableCreateTO', {toData});
  const toId = created.toId;

  await callAs(ctx.adminUid, 'callableCreateFlexSlots', {
    toId,
    businessId: ctx.businessId,
    dates,
    workDetails: wds,
    deadlineType: 'HOURS_BEFORE',
    hoursBeforeStart: 2,
    publishMode: 'immediate',
  });

  await callAs(ctx.adminUid, 'callablePublishTO', {toId});
  return {toId, dates};
}

/** contract(장기) 공고 생성 + 공개. 슬롯이 없다. */
async function createContractPosting(ctx, {scenarioId, title, fromOffset, toOffset, workDays, wds}) {
  const toData = {
    businessId: ctx.businessId,
    businessName: ctx.businessName,
    type: 'contract',
    title: `${TITLE_PREFIX} ${title}`,
    description: `R7 fixture — ${scenarioId}`,
    workDetails: wds,
    totalSlots: 0,
    totalRequired: wds.reduce((s, w) => s + w.requiredCount, 0),
    totalConfirmed: 0,
    totalPending: 0,
    rangeStart: kstMidnightMs(fromOffset),
    rangeEnd: kstMidnightMs(toOffset),
    workDays,
    deadlineType: 'HOURS_BEFORE',
    hoursBeforeStart: 2,
    contractPeriodType: 'custom',
    postingDurationDays: 30,
    creatorUID: ctx.adminUid,
    publishMode: 'immediate',
    isPublished: true,
    status: 'ACTIVE',
    isManualClosed: false,
  };
  const created = await callAs(ctx.adminUid, 'callableCreateTO', {toData});
  return {toId: created.toId};
}

/** 슬롯 목록 조회 — 지원에 필요한 slotId/wdId 를 얻는다. */
async function readSlots(ctx, toId) {
  const snap = await ctx.db.collection('tos').doc(toId)
      .collection('slots').orderBy('date').get();
  return snap.docs.map((d) => ({
    slotId: d.id,
    date: d.data().date,
    workDetails: d.data().workDetails || [],
  }));
}

module.exports = {
  TITLE_PREFIX,
  signaturePng,
  onePagePdf,
  workDetail,
  createFlexPosting,
  createContractPosting,
  readSlots,
  kstDateKey,
  kstWeekday,
  kstMidnightMs,
};
