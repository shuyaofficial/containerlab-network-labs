#!/usr/bin/env node
/*
 * NW-ZT Console ライブ更新 — data.js 再生成本体（refresh.sh から呼ばれる）。
 *
 * 入力: 環境変数 NAC_JSON / ZTNA_JSON / NDR_JSON / MICROSEG_JSON に各 export の
 *       stdout（JSON 文字列）を渡す（未設定 or 空 or status:"stopped" なら既存値を保持）。
 * 出力: src/data.js を "window.NWZT_DATA = {...};" 形式で上書き。
 *
 * 設計: 既存 data.js を require して window.NWZT_DATA を取得し、
 *       採取できたセクションだけ差し替える。壊れない・空にならないことを最優先。
 */
'use strict';

const fs = require('fs');
const path = require('path');

const DATA_PATH = path.join(__dirname, '..', 'src', 'data.js');

function loadExistingData() {
  const sandbox = { window: {} };
  const code = fs.readFileSync(DATA_PATH, 'utf8');
  // eslint-disable-next-line no-new-func
  const fn = new Function('window', code + '\nreturn window;');
  const result = fn(sandbox.window);
  return result.NWZT_DATA;
}

function parseSectionEnv(name) {
  const raw = process.env[name];
  if (!raw || raw.trim() === '') {
    return null;
  }
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (err) {
    process.stderr.write(`[refresh] ${name} の JSON パースに失敗、既存値を保持: ${err.message}\n`);
    return null;
  }
  if (!parsed || parsed.status === 'stopped') {
    return null;
  }
  return parsed;
}

function stripStatus(section) {
  if (!section || typeof section !== 'object') {
    return section;
  }
  const { status, ...rest } = section;
  return rest;
}

function mergeSection(existing, captured, sectionName) {
  if (captured === null) {
    process.stderr.write(`[refresh] ${sectionName}: 停止中 or 採取失敗 → 既存値を保持\n`);
    return existing;
  }
  process.stderr.write(`[refresh] ${sectionName}: 採取値で更新\n`);
  return stripStatus(captured);
}

// microseg は nftables 版 / cilium 版が独立に稼働・停止するため、
// 通常の mergeSection（セクション丸ごと差し替え）だと片方だけ稼働中の場合に
// もう片方の approach が消えてしまう。approaches 配列を id 単位でマージし、
// 採取できた approach だけ差し替え、稼働していない approach は既存値を残す。
function mergeMicroseg(existing, captured) {
  if (captured === null) {
    process.stderr.write('[refresh] microseg: 両系統とも停止中 or 採取失敗 → 既存値を保持\n');
    return existing;
  }

  const capturedSection = stripStatus(captured);
  const existingApproaches = Array.isArray(existing.approaches) ? existing.approaches : [];
  const capturedApproaches = Array.isArray(capturedSection.approaches) ? capturedSection.approaches : [];

  const mergedApproaches = existingApproaches.map((existingApproach) => {
    const updated = capturedApproaches.find((a) => a.id === existingApproach.id);
    if (updated) {
      process.stderr.write(`[refresh] microseg.${existingApproach.id}: 採取値で更新\n`);
      return updated;
    }
    process.stderr.write(`[refresh] microseg.${existingApproach.id}: 停止中 → 既存値を保持\n`);
    return existingApproach;
  });

  // 既存に無かった新規 approach id が採取された場合は追加する
  for (const approach of capturedApproaches) {
    if (!existingApproaches.some((a) => a.id === approach.id)) {
      mergedApproaches.push(approach);
    }
  }

  return {
    ...existing,
    ...capturedSection,
    approaches: mergedApproaches
  };
}

function today() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function buildOutput(data) {
  const header = `/* NW-ZT Console 実データ
 * 出所: 各ラボの実機検証で採取した本物の値（試験結果 doc / 実行ログ）。
 * 稼働中ラボから再生成する場合は capture/ の export で per-lab JSON を作り、
 * refresh でこのファイルを再構築する（外部依存ゼロ・file:// でも開ける）。 */
`;
  const body = `window.NWZT_DATA = ${JSON.stringify(data, null, 2)};\n`;
  return header + body;
}

function main() {
  const existing = loadExistingData();
  if (!existing || !existing.meta) {
    throw new Error('既存 data.js から NWZT_DATA を読み込めませんでした（壊れている可能性）');
  }

  const nac = parseSectionEnv('NAC_JSON');
  const ztna = parseSectionEnv('ZTNA_JSON');
  const ndr = parseSectionEnv('NDR_JSON');
  const microseg = parseSectionEnv('MICROSEG_JSON');

  const nextData = {
    meta: {
      ...existing.meta,
      capturedAt: today()
    },
    nac: mergeSection(existing.nac, nac, 'nac'),
    ztna: mergeSection(existing.ztna, ztna, 'ztna'),
    ndr: mergeSection(existing.ndr, ndr, 'ndr'),
    microseg: mergeMicroseg(existing.microseg, microseg)
  };

  // 安全弁: 必須キーが空/未定義にならないことを確認（壊れた再生成を防ぐ）
  const requiredKeys = ['meta', 'nac', 'ztna', 'ndr', 'microseg'];
  for (const key of requiredKeys) {
    if (!nextData[key] || typeof nextData[key] !== 'object') {
      throw new Error(`再生成後の ${key} が空/不正のため中断（data.js は書き換えない）`);
    }
  }

  fs.writeFileSync(DATA_PATH, buildOutput(nextData));
  process.stderr.write(`[refresh] data.js 再生成完了 (capturedAt=${nextData.meta.capturedAt})\n`);
}

main();
