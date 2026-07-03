#!/usr/bin/env node
/* =====================================================================
   build.mjs — Markdown → HTML 静的ビルド
   ネットワークラボ設計書（MDがソース）を、印刷にも耐える閲覧HTMLへ変換する。
   紙系デザイントークン・追従TOC・Mermaid同梱描画・外部CDN依存ゼロ。

   CLI:
     node build.mjs              全 .md をビルド + ポータル index.html
     node build.mjs --file <p>   単一ファイル
     node build.mjs --watch      chokidar 監視
     node build.mjs --check      検証のみ（違反あれば終了コード非0）

   ルートは「このスクリプト位置の2つ上」で解決する。絶対パスをハードコードしない。
   ===================================================================== */

import { fileURLToPath } from "node:url";
import path from "node:path";
import fs from "node:fs";
import fsp from "node:fs/promises";
import matter from "gray-matter";
import MarkdownIt from "markdown-it";
import anchor from "markdown-it-anchor";
import attrs from "markdown-it-attrs";
import hljs from "highlight.js";

/* --------------------------------------------------------------------
   パス解決（ハードコード禁止）
   -------------------------------------------------------------------- */
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename); // 規約/ビルド
const ROOT = path.resolve(__dirname, "../.."); // Mac仮想環境構築
const DOCS = path.join(ROOT, "docs");
const ASSETS = path.join(DOCS, "assets");
const NODE_MODULES = path.join(__dirname, "node_modules");
const TEMPLATE_PATH = path.join(__dirname, "template.html");

/* --------------------------------------------------------------------
   除外ディレクトリ / strict 対象
   -------------------------------------------------------------------- */
const EXCLUDE_DIRS = new Set([
  "node_modules", "docs", ".git", "log", "rfc",
  "切り分け", "インターロップ",
]);
// 規約/ 配下だが 雛形/ は除外
const EXCLUDE_PATH_SEGMENTS = ["規約/雛形", "規約\\雛形"];
// clab-* パターン
const EXCLUDE_PREFIXES = ["clab-"];

// frontmatter 必須（strict）: 規約/ と ZERO_zero_trust/ 配下
const STRICT_ROOTS = ["規約", "ZERO_zero_trust"];
const REQUIRED_FM = ["type", "theme", "status", "date", "tags", "title"];

/* --------------------------------------------------------------------
   markdown-it セットアップ
   -------------------------------------------------------------------- */
const HLJS_LANGS = new Set(["bash", "yaml", "text", "python", "sh", "shell", "yml", "json"]);

const md = new MarkdownIt({
  html: true,
  linkify: true,
  typographer: false,
  highlight(code, lang) {
    // mermaid はハイライトせず、後段でクラス付与する
    if (lang === "mermaid") return null;
    const norm = { sh: "bash", shell: "bash", yml: "yaml" }[lang] || lang;
    if (norm && HLJS_LANGS.has(lang) && hljs.getLanguage(norm)) {
      try {
        return hljs.highlight(code, { language: norm, ignoreIllegals: true }).value;
      } catch {
        /* fallthrough */
      }
    }
    return md.utils.escapeHtml(code);
  },
});

md.use(attrs);
md.use(anchor, {
  level: [2, 3],
  slugify: (s) => slugify(s),
  permalink: anchor.permalink.linkInsideHeader({
    symbol: "#",
    placement: "after",
    ariaHidden: true,
  }),
});

/* slugify: 日本語見出しでも安定・衝突回避のため index を付す（呼び出し側で管理不能なので id 収集は別途 TOC 用に自前で行う） */
function slugify(s) {
  const base = String(s)
    .trim()
    .toLowerCase()
    .replace(/<[^>]*>/g, "")
    .replace(/[\s]+/g, "-")
    .replace(/[^\p{L}\p{N}\-_]/gu, "");
  return base || "section";
}

/* --------------------------------------------------------------------
   TOC・table ラッパ・mermaid・code は render 前後で処理する。
   markdown-it-anchor の slug と一致させるため、TOC は同じ slugify + 重複連番規則を再現する。
   -------------------------------------------------------------------- */

/* markdown-it-anchor は重複 slug に -1, -2 ... を付与する。同じ規則を再現するカウンタ生成器。 */
function makeSlugger() {
  const seen = new Map();
  return (raw) => {
    let slug = slugify(raw);
    if (seen.has(slug)) {
      const n = seen.get(slug) + 1;
      seen.set(slug, n);
      slug = `${slug}-${n}`;
    } else {
      seen.set(slug, 0);
    }
    return slug;
  };
}

/* 見出しテキスト抽出（インライントークンから素のテキストを得る） */
function headingText(tokens, i) {
  const inline = tokens[i + 1];
  if (!inline || inline.type !== "inline") return "";
  return inline.children
    .filter((t) => t.type === "text" || t.type === "code_inline")
    .map((t) => t.content)
    .join("")
    .trim();
}

/* TOC を H2/H3 から生成（anchor と同一 slug を再現） */
function buildToc(tokens) {
  const slug = makeSlugger();
  const items = [];
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];
    if (t.type !== "heading_open") continue;
    if (t.tag !== "h2" && t.tag !== "h3") continue;
    const text = headingText(tokens, i);
    if (!text) continue;
    items.push({ level: t.tag === "h2" ? 2 : 3, text, id: slug(text) });
  }
  if (!items.length) return '<p class="toc-empty">（見出しなし）</p>';
  const lis = items
    .map(
      (it) =>
        `<li class="lvl-${it.level}"><a href="#${it.id}">${escapeHtml(it.text)}</a></li>`
    )
    .join("\n");
  return `<ul>\n${lis}\n</ul>`;
}

/* --------------------------------------------------------------------
   HTML後処理: table を .table-wrap で囲む / mermaid フェンスを <pre class="mermaid">
   -------------------------------------------------------------------- */
function postProcessHtml(html) {
  // <table>...</table> を横スクロール用ラッパで包む
  html = html.replace(/<table>/g, '<div class="table-wrap"><table>');
  html = html.replace(/<\/table>/g, "</table></div>");
  return html;
}

/* mermaid: markdown-it の fence を上書きし ```mermaid → <pre class="mermaid"> に */
const defaultFence =
  md.renderer.rules.fence ||
  ((tokens, idx, opts, env, self) => self.renderToken(tokens, idx, opts));
md.renderer.rules.fence = function (tokens, idx, opts, env, self) {
  const token = tokens[idx];
  const info = (token.info || "").trim().split(/\s+/)[0];
  if (info === "mermaid") {
    return `<pre class="mermaid">${escapeHtml(token.content)}</pre>\n`;
  }
  return defaultFence(tokens, idx, opts, env, self);
};

/* --------------------------------------------------------------------
   内部リンク書き換え: 相対 .md → .html（アンカー・クエリ保持）
   -------------------------------------------------------------------- */
const defaultLinkOpen =
  md.renderer.rules.link_open ||
  ((tokens, idx, opts, env, self) => self.renderToken(tokens, idx, opts));
md.renderer.rules.link_open = function (tokens, idx, opts, env, self) {
  const token = tokens[idx];
  const hrefIdx = token.attrIndex("href");
  if (hrefIdx >= 0) {
    const href = token.attrs[hrefIdx][1];
    if (isInternalMdLink(href)) {
      token.attrs[hrefIdx][1] = href.replace(
        /\.md(#[^?]*)?(\?[^#]*)?$/i,
        (_m, hash = "", query = "") => `.html${query}${hash}`
      );
    }
  }
  return defaultLinkOpen(tokens, idx, opts, env, self);
};

function isInternalMdLink(href) {
  if (!href) return false;
  if (/^[a-z][a-z0-9+.-]*:/i.test(href)) return false; // http:, mailto: 等
  if (href.startsWith("//")) return false;
  if (href.startsWith("#")) return false;
  return /\.md(#|\?|$)/i.test(href);
}

/* --------------------------------------------------------------------
   小物
   -------------------------------------------------------------------- */
function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

const STATUS_LABEL = {
  draft: "下書き",
  review: "レビュー中",
  done: "確定",
  superseded: "旧版",
};

/* YAML が date を JS Date に変換した場合も ISO(YYYY-MM-DD) で表示する */
function formatDate(v) {
  if (v instanceof Date && !isNaN(v)) {
    const y = v.getFullYear();
    const m = String(v.getMonth() + 1).padStart(2, "0");
    const d = String(v.getDate()).padStart(2, "0");
    return `${y}-${m}-${d}`;
  }
  const s = String(v).trim();
  const iso = s.match(/^\d{4}-\d{2}-\d{2}/);
  return iso ? iso[0] : s;
}

function isStrict(relPath) {
  const norm = relPath.split(path.sep).join("/");
  return STRICT_ROOTS.some(
    (r) => norm === r || norm.startsWith(r + "/")
  );
}

/* --------------------------------------------------------------------
   ファイル走査
   -------------------------------------------------------------------- */
function shouldSkipDir(name, relFromRoot) {
  if (EXCLUDE_DIRS.has(name)) return true;
  if (EXCLUDE_PREFIXES.some((p) => name.startsWith(p))) return true;
  const norm = relFromRoot.split(path.sep).join("/");
  if (EXCLUDE_PATH_SEGMENTS.some((seg) => norm === seg.replace("\\", "/"))) return true;
  return false;
}

async function collectMarkdownFiles() {
  const out = [];
  async function walk(absDir) {
    const entries = await fsp.readdir(absDir, { withFileTypes: true });
    for (const ent of entries) {
      const abs = path.join(absDir, ent.name);
      const rel = path.relative(ROOT, abs);
      if (ent.isDirectory()) {
        if (shouldSkipDir(ent.name, rel)) continue;
        await walk(abs);
      } else if (ent.isFile() && ent.name.toLowerCase().endsWith(".md")) {
        out.push(abs);
      }
    }
  }
  await walk(ROOT);
  out.sort();
  return out;
}

/* --------------------------------------------------------------------
   frontmatter / H1 抽出
   -------------------------------------------------------------------- */
/* 本文先頭の H1 を1つだけ除去する。マストヘッドが .doc-title として表示するため、
   本文に残すとページ内 H1 が二重になる（アクセシビリティ・視覚の両面で不可）。
   コードフェンス内の # は触らない。 */
function stripLeadingH1(markdownBody) {
  const lines = markdownBody.split(/\r?\n/);
  let inFence = false;
  for (let i = 0; i < lines.length; i++) {
    const t = lines[i].trim();
    if (/^```/.test(t)) { inFence = !inFence; continue; }
    if (inFence) continue;
    if (/^#\s+\S/.test(lines[i])) {
      lines.splice(i, 1);
      // 直後の空行も1つ畳んで余白の重複を防ぐ
      if (lines[i] !== undefined && lines[i].trim() === "") lines.splice(i, 1);
      break;
    }
    // H1 より前に実コンテンツがあれば除去しない（安全側）
    if (t !== "") break;
  }
  return lines.join("\n");
}

function extractFirstH1(markdownBody) {
  const lines = markdownBody.split(/\r?\n/);
  let inFence = false;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (/^```/.test(line.trim())) { inFence = !inFence; continue; }
    if (inFence) continue;
    const m = line.match(/^#\s+(.+?)\s*$/);
    if (m) return m[1].trim();
  }
  return null;
}

function countH1(markdownBody) {
  const lines = markdownBody.split(/\r?\n/);
  let inFence = false;
  let n = 0;
  for (const line of lines) {
    if (/^```/.test(line.trim())) { inFence = !inFence; continue; }
    if (inFence) continue;
    if (/^#\s+\S/.test(line)) n++;
  }
  return n;
}

/* --------------------------------------------------------------------
   パンくず生成: docs 相対の各セグメントを親 index / フォルダ名で辿る
   -------------------------------------------------------------------- */
function buildBreadcrumb(relHtmlPath) {
  const parts = relHtmlPath.split(path.sep);
  const depth = parts.length - 1; // ルートまでの階層
  const rootHref = depth > 0 ? "../".repeat(depth) + "index.html" : "index.html";
  const crumbs = [`<a href="${rootHref}">Home</a>`];
  // 中間ディレクトリ（最後のファイル名を除く）
  const dirParts = parts.slice(0, -1);
  dirParts.forEach((seg) => {
    crumbs.push(`<span>${escapeHtml(seg)}</span>`);
  });
  return crumbs.join('\n<span class="sep">/</span>\n');
}

/* --------------------------------------------------------------------
   1ファイルを HTML 文字列にレンダリング
   -------------------------------------------------------------------- */
function renderDocument({ relPath, frontmatter, body, title }) {
  const tokens = md.parse(body, {});
  const toc = buildToc(tokens);
  let content = md.render(body, {});
  content = postProcessHtml(content);

  const relHtml = relPath.replace(/\.md$/i, ".html");
  const depth = relHtml.split(path.sep).length - 1;
  const assetsPrefix = (depth > 0 ? "../".repeat(depth) : "./") + "assets";

  const status = frontmatter.status;
  let statusHtml = "";
  let noticeHtml = "";
  if (status === "draft" || status === "review") {
    statusHtml = `<span class="badge badge--${status}">${STATUS_LABEL[status]}</span>`;
  }
  if (status === "superseded") {
    statusHtml = `<span class="badge badge--review" style="background:var(--warn-soft);color:var(--warn)">旧版</span>`;
    noticeHtml =
      `<div class="notice" role="alert"><span class="icon">⚠️</span>` +
      `<span><strong>この文書は新版に置き換えられています（superseded）。</strong>` +
      `最新の情報は後継文書を参照してください。</span></div>`;
  }

  const tags = Array.isArray(frontmatter.tags) ? frontmatter.tags : [];
  const tagsHtml = tags.length
    ? `<span class="tags">${tags
        .map((t) => `<span class="tag">${escapeHtml(String(t))}</span>`)
        .join("")}</span>`
    : "";

  const dateHtml = frontmatter.date
    ? `<span class="dot"></span><span class="date">${escapeHtml(formatDate(frontmatter.date))}</span>`
    : "";

  const template = fs.readFileSync(TEMPLATE_PATH, "utf8");
  // 置換値は関数で渡す。文字列置換だと値中の `$&` 等が特殊解釈され、
  // 本文中の `$'`（bash正規表現など）が `{{content}}` 等に化ける。
  const fill = {
    "{{assets}}": assetsPrefix,
    "{{title}}": escapeHtml(title),
    "{{breadcrumb}}": buildBreadcrumb(relHtml),
    "{{status}}": statusHtml,
    "{{date}}": dateHtml,
    "{{tags}}": tagsHtml,
    "{{notice}}": noticeHtml,
    "{{toc}}": toc,
    "{{content}}": content,
  };
  return template.replace(
    /\{\{(assets|title|breadcrumb|status|date|tags|notice|toc|content)\}\}/g,
    (m) => fill[m]
  );
}

/* --------------------------------------------------------------------
   1ファイルをビルドして書き出す
   -------------------------------------------------------------------- */
async function buildFile(absMd) {
  const raw = await fsp.readFile(absMd, "utf8");
  const relPath = path.relative(ROOT, absMd);
  const parsed = matter(raw);
  const fm = parsed.data || {};
  const body = parsed.content;

  // title 解決: frontmatter.title 優先、無ければ H1（レガシー互換）、無ければファイル名
  let title = fm.title;
  if (!title) title = extractFirstH1(body);
  if (!title) title = path.basename(absMd, path.extname(absMd));

  // 本文先頭 H1 はマストヘッドと重複するため除去
  const bodyForRender = stripLeadingH1(body);

  const html = renderDocument({ relPath, frontmatter: fm, body: bodyForRender, title });

  const relHtml = relPath.replace(/\.md$/i, ".html");
  const outPath = path.join(DOCS, relHtml);
  await fsp.mkdir(path.dirname(outPath), { recursive: true });
  await fsp.writeFile(outPath, html, "utf8");
  return { relPath, relHtml, title, theme: fm.theme || null, status: fm.status || null };
}

/* --------------------------------------------------------------------
   アセット配置（doc.css / mermaid.min.js / highlight テーマ）
   -------------------------------------------------------------------- */
async function copyAssets() {
  await fsp.mkdir(ASSETS, { recursive: true });
  // doc.css（規約/ビルド/doc.css をコピー）
  await fsp.copyFile(path.join(__dirname, "doc.css"), path.join(ASSETS, "doc.css"));
  // mermaid（同梱・外部CDN禁止）
  await fsp.copyFile(
    path.join(NODE_MODULES, "mermaid", "dist", "mermaid.min.js"),
    path.join(ASSETS, "mermaid.min.js")
  );
  // highlight.js 淡色テーマ（github light）
  await fsp.copyFile(
    path.join(NODE_MODULES, "highlight.js", "styles", "github.min.css"),
    path.join(ASSETS, "highlight.css")
  );
}

/* --------------------------------------------------------------------
   ポータル index.html
   -------------------------------------------------------------------- */
function themeKey(dir) {
  if (dir === "ZERO_zero_trust") return " "; // 先頭
  const m = dir.match(/^(\d+)/);
  return m ? m[1].padStart(4, "0") : "zzzz" + dir;
}

// 進捗管理.md から「フォルダ→状態絵文字」を抽出（読めなくても壊れない）
async function loadThemeStates() {
  const states = {};
  try {
    const p = path.join(ROOT, "ロードマップ", "進捗管理.md");
    const txt = await fsp.readFile(p, "utf8");
    const rowRe = /\|[^|]*\|[^|]*\|\s*([^|]*?)\s*\|\s*`?\.\.\/([^`/|]+)\/?`?[^|]*\|/g;
    let m;
    while ((m = rowRe.exec(txt))) {
      const emoji = (m[1].match(/[✅◐⏹⚠⬜]/) || [])[0];
      const folder = m[2].trim();
      if (emoji && folder) states[folder] = emoji;
    }
  } catch {
    /* 進捗管理が読めなくても無視 */
  }
  return states;
}

async function buildPortal(built) {
  // テーマ（トップレベルディレクトリ）ごとに文書をまとめる
  const groups = new Map();
  for (const b of built) {
    const top = b.relHtml.split(path.sep)[0];
    const key = top.endsWith(".html") ? "__root__" : top;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(b);
  }

  const states = await loadThemeStates();

  // ソート: ZERO 先頭 → 番号順 → その他
  const dirs = [...groups.keys()].filter((k) => k !== "__root__");
  dirs.sort((a, b) => themeKey(a).localeCompare(themeKey(b)));

  const totalDocs = built.length;
  const totalThemes = dirs.length;

  const cards = dirs
    .map((dir) => {
      const docs = groups.get(dir).slice().sort((a, b) => a.relHtml.localeCompare(b.relHtml));
      const m = dir.match(/^(\d+|ZERO)/);
      const num = m ? (m[1] === "ZERO" ? "ZERO" : m[1]) : "";
      const name = dir.replace(/^(\d+|ZERO)[_-]?/, "");
      const emoji = states[dir] || "";
      const items = docs
        .map((d) => {
          const label = d.title || path.basename(d.relHtml, ".html");
          return `<li><a href="${d.relHtml.split(path.sep).join("/")}">${escapeHtml(label)}</a></li>`;
        })
        .join("\n");
      return `
      <article class="card">
        <div class="card-head">
          ${num ? `<span class="card-num">${escapeHtml(num)}</span>` : ""}
          <h2 class="card-name">${escapeHtml(name || dir)}</h2>
          ${emoji ? `<span class="card-state" title="進捗">${emoji}</span>` : ""}
        </div>
        <p class="card-count">${docs.length} 文書</p>
        <ul class="card-list">
${items}
        </ul>
      </article>`;
    })
    .join("\n");

  const html = `<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="light">
  <title>ネットワークラボ設計書ポータル</title>
  <link rel="stylesheet" href="assets/doc.css">
</head>
<body>
  <main class="portal">
    <header class="portal-head">
      <p class="portal-kicker">Network Lab Docs</p>
      <h1 class="portal-title">ネットワークラボ設計書ポータル</h1>
      <p class="portal-lead">Mac 仮想環境で構築する containerlab ネットワークラボの設計書群。Markdown をソースとし、印刷にも耐える閲覧ビューへ自動生成している。</p>
      <div class="portal-stats">
        <div class="stat"><div class="num">${totalThemes}</div><div class="lbl">テーマ</div></div>
        <div class="stat"><div class="num">${totalDocs}</div><div class="lbl">文書</div></div>
      </div>
    </header>
    <div class="card-grid">
${cards}
    </div>
    <footer class="portal-foot">
      生成: <span class="date">${new Date().toISOString().slice(0, 10)}</span> ／ ソースは Markdown（手編集禁止）。<code>node 規約/ビルド/build.mjs</code> で再生成。
    </footer>
  </main>
</body>
</html>
`;
  await fsp.writeFile(path.join(DOCS, "index.html"), html, "utf8");
}

/* --------------------------------------------------------------------
   --check 検証
   -------------------------------------------------------------------- */
async function runCheck() {
  const files = await collectMarkdownFiles();
  const errors = [];
  const warnings = [];

  // 有効な .md 相対パス集合（リンク切れ判定用）
  const mdSet = new Set(files.map((f) => path.relative(ROOT, f).split(path.sep).join("/")));

  for (const abs of files) {
    const rel = path.relative(ROOT, abs);
    const relNorm = rel.split(path.sep).join("/");
    const strict = isStrict(rel);
    const record = (line, kind, detail, forceError = false) => {
      const msg = `${relNorm}:${line} ${kind} ${detail}`;
      if (strict || forceError) errors.push(msg);
      else warnings.push(msg);
    };

    // 1) NFD ファイル名（全域エラー）
    const base = path.basename(abs);
    if (base !== base.normalize("NFC")) {
      errors.push(`${relNorm}:0 NFD-FILENAME ファイル名がNFC正規化されていない`);
    }

    const raw = await fsp.readFile(abs, "utf8");
    const parsed = matter(raw);
    const fm = parsed.data || {};
    const hasFm = Object.keys(fm).length > 0 || /^---\s*\n/.test(raw);
    const body = parsed.content;
    const bodyOffset = raw.split(/\r?\n/).length - body.split(/\r?\n/).length; // 本文開始の行オフセット

    // 2) frontmatter 欠落・必須欠落（strict のみエラー）
    if (strict) {
      if (!hasFm || Object.keys(fm).length === 0) {
        record(1, "FM-MISSING", "frontmatter が無い");
      } else {
        for (const key of REQUIRED_FM) {
          const v = fm[key];
          const empty =
            v === undefined ||
            v === null ||
            (typeof v === "string" && v.trim() === "") ||
            (Array.isArray(v) && v.length === 0);
          if (empty) record(1, "FM-FIELD", `必須フィールド欠落: ${key}`);
        }
      }
    }

    // 3) H1 が 0 or 複数（strict のみエラー）
    const h1n = countH1(body);
    if (strict && h1n !== 1) {
      record(bodyOffset + 1, "H1-COUNT", `H1 は 1 つ必須（現在 ${h1n} 個）`);
    }

    // 4) リンク検証（strict のみ）: 相対 .md 切れ + 絶対パス埋め込み
    if (strict) {
      const bodyLines = body.split(/\r?\n/);
      const linkRe = /\[[^\]]*\]\(([^)]+)\)/g;
      let inFence = false;
      for (let i = 0; i < bodyLines.length; i++) {
        const line = bodyLines[i];
        if (/^```/.test(line.trim())) { inFence = !inFence; continue; }
        if (inFence) continue;
        let m;
        while ((m = linkRe.exec(line))) {
          let href = m[1].trim().split(/\s+/)[0]; // タイトル部分除去
          const lineNo = bodyOffset + i + 1;
          if (/^\/Users\//.test(href) || /^\/[A-Za-z]/.test(href) && !href.startsWith("//")) {
            if (/^\/Users\//.test(href)) {
              record(lineNo, "ABS-PATH", `絶対パスリンク: ${href}`);
              continue;
            }
          }
          if (isInternalMdLink(href)) {
            const targetRel = href.replace(/[#?].*$/, "");
            const resolved = path
              .normalize(path.join(path.dirname(relNorm), targetRel))
              .split(path.sep)
              .join("/");
            if (!mdSet.has(resolved)) {
              record(lineNo, "LINK-BROKEN", `相対リンク切れ: ${href}`);
            }
          }
        }
      }
    }
  }

  // 出力
  if (warnings.length) {
    console.log("\n⚠️  警告（レガシー文書 / 非strict）:");
    warnings.forEach((w) => console.log("  " + w));
  }
  if (errors.length) {
    console.log("\n❌ エラー（strict対象）:");
    errors.forEach((e) => console.log("  " + e));
    console.log(`\n検証失敗: エラー ${errors.length} 件 / 警告 ${warnings.length} 件`);
    process.exitCode = 1;
    return false;
  }
  console.log(`\n✅ 検証OK（strict エラー 0 件 / 警告 ${warnings.length} 件 / 対象 ${files.length} ファイル）`);
  return true;
}

/* --------------------------------------------------------------------
   フルビルド
   -------------------------------------------------------------------- */
async function runBuild() {
  const files = await collectMarkdownFiles();
  await copyAssets();
  const built = [];
  for (const abs of files) {
    try {
      built.push(await buildFile(abs));
    } catch (err) {
      console.error(`ビルド失敗: ${path.relative(ROOT, abs)} — ${err.message}`);
    }
  }
  await buildPortal(built);
  console.log(`✅ ビルド完了: ${built.length} HTML → ${path.relative(ROOT, DOCS)}/ ＋ index.html`);
  return built;
}

/* --------------------------------------------------------------------
   watch
   -------------------------------------------------------------------- */
async function runWatch() {
  const { default: chokidar } = await import("chokidar");
  await runBuild();
  console.log("👀 監視中（Ctrl+C で終了）…");
  const watcher = chokidar.watch(ROOT, {
    ignored: (p) => {
      const rel = path.relative(ROOT, p);
      if (!rel) return false;
      const seg = rel.split(path.sep);
      return seg.some(
        (s) =>
          EXCLUDE_DIRS.has(s) ||
          EXCLUDE_PREFIXES.some((pre) => s.startsWith(pre))
      ) || rel.split(path.sep).join("/").startsWith("規約/雛形");
    },
    ignoreInitial: true,
    persistent: true,
  });
  const rebuild = async (p) => {
    if (!p.toLowerCase().endsWith(".md")) return;
    try {
      await buildFile(p);
      // ポータルはタイトル変化を反映するため全走査で再生成
      const files = await collectMarkdownFiles();
      const built = [];
      for (const abs of files) {
        const raw = await fsp.readFile(abs, "utf8");
        const parsed = matter(raw);
        const fm = parsed.data || {};
        const relPath = path.relative(ROOT, abs);
        let title = fm.title || extractFirstH1(parsed.content) || path.basename(abs, ".md");
        built.push({
          relPath,
          relHtml: relPath.replace(/\.md$/i, ".html"),
          title,
          theme: fm.theme || null,
          status: fm.status || null,
        });
      }
      await buildPortal(built);
      console.log(`♻️  再ビルド: ${path.relative(ROOT, p)}`);
    } catch (err) {
      console.error(`再ビルド失敗: ${err.message}`);
    }
  };
  watcher.on("change", rebuild).on("add", rebuild);
}

/* --------------------------------------------------------------------
   単一ファイル
   -------------------------------------------------------------------- */
async function runSingle(fileArg) {
  const abs = path.isAbsolute(fileArg) ? fileArg : path.resolve(process.cwd(), fileArg);
  if (!fs.existsSync(abs)) {
    console.error(`ファイルが見つかりません: ${fileArg}`);
    process.exitCode = 1;
    return;
  }
  // ROOT 外のファイルは拒否（docs/ 外へ書き出してしまうのを防ぐ）
  const rel = path.relative(ROOT, abs);
  if (rel.startsWith("..") || path.isAbsolute(rel)) {
    console.error(`対象外: ${fileArg} は ${path.basename(ROOT)}/ 配下ではありません`);
    process.exitCode = 1;
    return;
  }
  await copyAssets();
  const r = await buildFile(abs);
  console.log(`✅ 生成: ${r.relHtml}`);
}

/* --------------------------------------------------------------------
   エントリポイント
   -------------------------------------------------------------------- */
async function main() {
  const args = process.argv.slice(2);
  if (args.includes("--check")) {
    await runCheck();
    return;
  }
  if (args.includes("--watch")) {
    await runWatch();
    return;
  }
  const fileFlag = args.indexOf("--file");
  if (fileFlag >= 0) {
    await runSingle(args[fileFlag + 1]);
    return;
  }
  await runBuild();
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
