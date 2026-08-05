// End-to-end tests: a real server over a throwaway sqlite db (INKWELL_DB).
import { afterAll, beforeAll, expect, test } from "bun:test";
import { rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const DB_PATH = join(tmpdir(), `inkwell-test-${Date.now()}-${process.pid}.db`);
process.env.INKWELL_DB = DB_PATH; // read lazily on first query, so this lands in time

// Imported after the env assignment is what matters at call time, not import time.
const { handleRequest, closeDb } = await import("./server.ts");

let server: ReturnType<typeof Bun.serve>;
let base: string;

beforeAll(() => {
  server = Bun.serve({ port: 0, fetch: handleRequest });
  base = `http://localhost:${server.port}`;
});

afterAll(() => {
  server.stop(true);
  closeDb();
  for (const suffix of ["", "-shm", "-wal"]) {
    rmSync(DB_PATH + suffix, { force: true });
  }
});

const api = (path: string, init?: RequestInit) => fetch(`${base}/api${path}`, init);

const post = (path: string, body?: unknown) =>
  api(path, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

test("starts with an empty list", async () => {
  const res = await api("/posts");
  expect(res.status).toBe(200);
  expect(res.headers.get("content-type")).toContain("application/json");
  expect(await res.json()).toEqual([]);
});

test("creates a post with defaults", async () => {
  const res = await post("/posts", {});
  const created = await res.json();
  expect(created.title).toBe("Untitled");
  expect(created.content).toBe("");
  expect(created.status).toBe("draft");
  expect(created.id).toBeGreaterThan(0);
  expect(created.created_at).toBeTruthy();
  expect(created.updated_at).toBeTruthy();
});

test("full lifecycle: create → list → update → publish toggle → delete", async () => {
  const created = await (await post("/posts", { title: "Ink", content: "one two three" })).json();
  const id = created.id;
  expect(created.title).toBe("Ink");
  expect(created.status).toBe("draft");

  // list carries the summary shape, newest-updated first
  const list = await (await api("/posts")).json();
  const summary = list.find((p: { id: number }) => p.id === id);
  expect(Object.keys(summary).sort()).toEqual(
    ["id", "status", "title", "updated_at", "word_count", "target_word_count"].sort(),
  );
  expect(summary.word_count).toBe(3);
  expect(list[0].id).toBe(id); // most recently updated

  // fetch one
  const fetched = await (await api(`/posts/${id}`)).json();
  expect(fetched.content).toBe("one two three");

  // partial update touches only the given field, and bumps updated_at
  await Bun.sleep(5);
  const updated = await (
    await api(`/posts/${id}`, {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ content: "four five" }),
    })
  ).json();
  expect(updated.title).toBe("Ink");
  expect(updated.content).toBe("four five");
  expect(updated.updated_at > created.updated_at).toBe(true);
  expect(updated.created_at).toBe(created.created_at);

  const afterUpdate = await (await api("/posts")).json();
  expect(afterUpdate.find((p: { id: number }) => p.id === id).word_count).toBe(2);

  // publish toggles both ways
  const published = await (await post(`/posts/${id}/publish`)).json();
  expect(published.status).toBe("published");
  const unpublished = await (await post(`/posts/${id}/publish`)).json();
  expect(unpublished.status).toBe("draft");

  // delete
  const del = await api(`/posts/${id}`, { method: "DELETE" });
  expect(del.status).toBe(200);
  expect(await del.json()).toEqual({ ok: true });

  const remaining = await (await api("/posts")).json();
  expect(remaining.some((p: { id: number }) => p.id === id)).toBe(false);
});

test("list is ordered by updated_at DESC", async () => {
  const a = await (await post("/posts", { title: "A" })).json();
  await Bun.sleep(5);
  const b = await (await post("/posts", { title: "B" })).json();
  await Bun.sleep(5);
  await api(`/posts/${a.id}`, {
    method: "PUT",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ title: "A again" }),
  });

  const list = await (await api("/posts")).json();
  const ids = list.map((p: { id: number }) => p.id);
  expect(ids.indexOf(a.id)).toBeLessThan(ids.indexOf(b.id));
});

test("unknown id returns 404 {error: 'not found'} on every route", async () => {
  const missing = 999999;
  const routes = [
    api(`/posts/${missing}`),
    api(`/posts/${missing}`, {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ title: "nope" }),
    }),
    post(`/posts/${missing}/publish`),
    api(`/posts/${missing}/stats`),
  ];
  for (const res of await Promise.all(routes)) {
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ error: "not found" });
  }
});

test("malformed JSON body returns 400 with an error", async () => {
  const res = await api("/posts", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: "{not json",
  });
  expect(res.status).toBe(400);
  expect((await res.json()).error).toBeTruthy();
});

test("word_count counts whitespace-split words", async () => {
  const created = await (
    await post("/posts", { content: "  spaced \n out\twords here  " })
  ).json();
  const list = await (await api("/posts")).json();
  const summary = list.find((p: { id: number }) => p.id === created.id);
  expect(summary.word_count).toBe(4);
});

test("app.js cycles view mode on Cmd+Enter", async () => {
  const res = await fetch(`${base}/app.js`);
  expect(res.status).toBe(200);
  const text = await res.text();
  expect(text).toContain("e.key === 'Enter'");
  expect(text).toContain("cycleViewMode()");
});

// Pulls one `// --- <name> ---` section out of app.js so pure logic can be exercised directly.
function section(src: string, name: string): string {
  const start = src.indexOf(`// --- ${name}`);
  if (start === -1) throw new Error(`section "${name}" not found in app.js`);
  const rest = src.slice(start);
  const end = rest.indexOf("\n// --- ", 1);
  return end === -1 ? rest : rest.slice(0, end);
}

function loadSection<T>(src: string, name: string, exports: string[]): T {
  return new Function(`${section(src, name)}\nreturn { ${exports.join(", ")} };`)() as T;
}

test("index.html exposes the panes and the three mode buttons", async () => {
  const res = await fetch(`${base}/index.html`);
  expect(res.status).toBe(200);
  const html = await res.text();

  expect(html).toContain('id="panes"');
  expect(html).toContain('class="pane editor-pane"');
  expect(html).toContain('class="pane preview-pane"');
  expect(html).toContain('class="mode-switch"');

  expect(html).toContain('id="mode-edit"');
  expect(html).toContain('id="mode-split"');
  expect(html).toContain('id="mode-preview"');
  expect(html).toContain('data-mode="edit"');
  expect(html).toContain('data-mode="split"');
  expect(html).toContain('data-mode="preview"');

  expect(html).toContain('id="content"');
  expect(html).toContain('id="preview"');

  // #preview no longer ships `hidden`; visibility is CSS-driven off body[data-view-mode]
  expect(html).toContain('<div id="preview" class="preview"');
  const previewTag = html.slice(html.indexOf('id="preview"'), html.indexOf(">", html.indexOf('id="preview"')));
  expect(previewTag).not.toContain("hidden");

  // content before preview, both inside the #panes block
  expect(html.indexOf('id="panes"')).toBeLessThan(html.indexOf('id="content"'));
  expect(html.indexOf('id="content"')).toBeLessThan(html.indexOf('id="preview"'));

  // shortcuts modal advertises the cycle
  expect(html).toContain("Cycle view mode");
});

test("style.css defines all three layouts", async () => {
  const res = await fetch(`${base}/style.css`);
  expect(res.status).toBe(200);
  const css = await res.text();

  expect(css).toContain(".panes");
  expect(css).toContain(".editor-pane");
  expect(css).toContain(".preview-pane");
  expect(css).toContain(".pane-label");
  expect(css).toContain(".mode-switch");

  expect(css).toContain('body[data-view-mode="edit"]');
  expect(css).toContain('body[data-view-mode="split"]');
  expect(css).toContain('body[data-view-mode="preview"]');

  // split adds a divider between the panes
  const splitRule = css.slice(
    css.indexOf('body[data-view-mode="split"] .preview-pane'),
    css.indexOf("}", css.indexOf('body[data-view-mode="split"] .preview-pane')),
  );
  expect(splitRule).toContain("border-left");

  // token discipline: no hex/rgba literals in the new view-modes block
  const viewModesBlock = css.slice(css.indexOf("/* --- view modes"));
  expect(viewModesBlock).not.toMatch(/#[0-9a-fA-F]{3,8}\b/);
  expect(viewModesBlock).not.toContain("rgba(");
});

test("app.js wires mode state, buttons, and live preview", async () => {
  const res = await fetch(`${base}/app.js`);
  expect(res.status).toBe(200);
  const js = await res.text();

  expect(js).toContain("VIEW_MODES");
  expect(js).toContain("nextViewMode");
  expect(js).toContain("setViewMode");
  expect(js).toContain("refreshPreview");
  expect(js).toContain("document.body.dataset.viewMode");
  expect(js).toContain(".mode-btn");

  expect(js).not.toContain("showPreview");
  expect(js).not.toContain("previewing");

  // the content input handler re-renders the live preview on every keystroke
  const handler = js.slice(
    js.indexOf("ui.content.addEventListener('input'"),
    js.indexOf("});", js.indexOf("ui.content.addEventListener('input'")),
  );
  expect(handler).toContain("refreshPreview()");
});

test("view-mode cycling: edit → split → preview → edit (behavioral, pure section)", async () => {
  const res = await fetch(`${base}/app.js`);
  expect(res.status).toBe(200);
  const js = await res.text();

  const { VIEW_MODES, nextViewMode, normalizeViewMode, viewModeShowsPreview } =
    loadSection<any>(js, "view mode (pure)", ["VIEW_MODES", "nextViewMode", "normalizeViewMode", "viewModeShowsPreview"]);

  expect(VIEW_MODES).toEqual(["edit", "split", "preview"]);
  expect(nextViewMode("edit")).toBe("split");
  expect(nextViewMode("split")).toBe("preview");
  expect(nextViewMode("preview")).toBe("edit"); // wraps
  expect(nextViewMode("bogus")).toBe("split"); // unknown normalizes to edit, then advances
  expect(normalizeViewMode(undefined)).toBe("edit");
  expect(viewModeShowsPreview("edit")).toBe(false);
  expect(viewModeShowsPreview("split")).toBe(true);
  expect(viewModeShowsPreview("preview")).toBe(true);

  // three cycles from edit return to edit — every mode is reachable by the hot key
  let mode = "edit";
  const seen = [mode];
  for (let i = 0; i < 3; i++) {
    mode = nextViewMode(mode);
    seen.push(mode);
  }
  expect(seen).toEqual(["edit", "split", "preview", "edit"]);
});

test("preview rendering: markdown section renders headings, inline marks, lists, code (behavioral)", async () => {
  const res = await fetch(`${base}/app.js`);
  expect(res.status).toBe(200);
  const js = await res.text();

  const { renderMarkdown } = loadSection<any>(js, "markdown", ["renderMarkdown"]);

  const html = renderMarkdown("# Title\n\nsome **bold** and `code`\n\n- one\n- two");
  expect(html).toContain("<h1>Title</h1>");
  expect(html).toContain("<strong>bold</strong>");
  expect(html).toContain("<code>code</code>");
  expect(html).toContain("<li>one</li>");
  expect(html).toContain("<ul>");
  expect(renderMarkdown("```\nlet x = 1;\n```")).toContain("<pre><code>let x = 1;</code></pre>");
  expect(renderMarkdown("<script>alert(1)</script>")).toContain("&lt;script&gt;");
  // live-updating: successive keystroke states render different output
  expect(renderMarkdown("# a")).not.toBe(renderMarkdown("# ab"));
});

test("index.html contains shortcuts modal elements and visual key hints", async () => {
  const res = await fetch(`${base}/index.html`);
  expect(res.status).toBe(200);
  const text = await res.text();
  expect(text).toContain('id="shortcuts-modal"');
  expect(text).toContain('id="shortcuts-toggle"');
  expect(text).toContain('id="modal-close"');
  expect(text).toContain('class="key-hint"');
});

test("app.js contains keydown handlers for Cmd+N, ?, and Escape", async () => {
  const res = await fetch(`${base}/app.js`);
  expect(res.status).toBe(200);
  const text = await res.text();
  expect(text).toContain("e.key.toLowerCase() === 'n'");
  expect(text).toContain("e.key === '?'");
  expect(text).toContain("e.key === 'Escape'");
  expect(text).toContain("toggleShortcutsModal");
});

test("index.html contains focus mode and font size control elements", async () => {
  const res = await fetch(`${base}/index.html`);
  expect(res.status).toBe(200);
  const text = await res.text();
  expect(text).toContain('id="focus-toggle"');
  expect(text).toContain('id="font-increase"');
  expect(text).toContain('id="font-decrease"');
  expect(text).toContain("Toggle focus mode");
  expect(text).toContain("Increase font size");
  expect(text).toContain("Decrease font size");
});

test("style.css contains focus-mode styles", async () => {
  const res = await fetch(`${base}/style.css`);
  expect(res.status).toBe(200);
  const text = await res.text();
  expect(text).toContain("body.focus-mode .sidebar");
  expect(text).toContain("body.focus-mode .footer");
});

test("app.js contains focus mode and font size handlers and shortcut listeners", async () => {
  const res = await fetch(`${base}/app.js`);
  expect(res.status).toBe(200);
  const text = await res.text();
  expect(text).toContain("toggleFocusMode");
  expect(text).toContain("setFontSize");
  expect(text).toContain("ui.title.style.fontSize");
  expect(text).toContain("e.shiftKey && e.key.toLowerCase() === 'f'");
  expect(text).toContain("e.key === '=' || e.key === '+'");
  expect(text).toContain("e.key === '-' || e.key === '_'");
});

test("creates post with target_word_count and updates it via PUT", async () => {
  const created = await (
    await post("/posts", { title: "Goal Test", content: "hello world", target_word_count: 500 })
  ).json();
  expect(created.target_word_count).toBe(500);

  const updated = await (
    await api(`/posts/${created.id}`, {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ target_word_count: 1000 }),
    })
  ).json();
  expect(updated.target_word_count).toBe(1000);

  const fetched = await (await api(`/posts/${created.id}`)).json();
  expect(fetched.target_word_count).toBe(1000);

  const list = await (await api("/posts")).json();
  const item = list.find((p: { id: number }) => p.id === created.id);
  expect(item.target_word_count).toBe(1000);
});

test("index.html contains target word count, reading time, and goal elements", async () => {
  const res = await fetch(`${base}/index.html`);
  expect(res.status).toBe(200);
  const text = await res.text();
  expect(text).toContain('id="target-words"');
  expect(text).toContain('id="reading-time"');
  expect(text).toContain('id="goal-progress"');
  expect(text).toContain('id="goal-container"');
});

test("app.js contains reading time calculation and writing goal logic", async () => {
  const res = await fetch(`${base}/app.js`);
  expect(res.status).toBe(200);
  const text = await res.text();
  expect(text).toContain("calcReadingTime");
  expect(text).toContain("target_word_count");
  expect(text).toContain("goalProgress");
  expect(text).toContain("goal-met");
});

test("GET /api/posts?q= filters posts by title or content (case-insensitive)", async () => {
  const p1 = await (await post("/posts", { title: "Alpha Quantum", content: "first post body" })).json();
  const p2 = await (await post("/posts", { title: "Beta Note", content: "quantum leap inside body" })).json();
  const p3 = await (await post("/posts", { title: "Gamma Draft", content: "unrelated content" })).json();

  // Filter by title match ("alpha")
  const searchTitle = await (await api("/posts?q=alpha")).json();
  expect(searchTitle.length).toBe(1);
  expect(searchTitle[0].id).toBe(p1.id);

  // Filter by content match ("quantum") -> matches p1 title and p2 content
  const searchContent = await (await api("/posts?q=QUANTUM")).json();
  const contentIds = searchContent.map((p: { id: number }) => p.id);
  expect(contentIds).toContain(p1.id);
  expect(contentIds).toContain(p2.id);
  expect(contentIds).not.toContain(p3.id);

  // Filter with no matches
  const searchNone = await (await api("/posts?q=nonexistentxyz")).json();
  expect(searchNone).toEqual([]);

  // Alias search= parameter works identically
  const searchAlias = await (await api("/posts?search=Beta")).json();
  expect(searchAlias.length).toBe(1);
  expect(searchAlias[0].id).toBe(p2.id);
});

test("GET /api/posts/:id/stats returns post stats and 404 for unknown id", async () => {
  // Post with 0 words
  const emptyPost = await (await post("/posts", { content: "" })).json();
  const emptyStatsRes = await api(`/posts/${emptyPost.id}/stats`);
  expect(emptyStatsRes.status).toBe(200);
  expect(emptyStatsRes.headers.get("content-type")).toContain("application/json");
  expect(await emptyStatsRes.json()).toEqual({
    word_count: 0,
    reading_minutes: 0,
    status: "draft",
  });

  // Post with 150 words (<= 200 words => 1 min read)
  const words150 = Array(150).fill("word").join(" ");
  const p150 = await (await post("/posts", { content: words150 })).json();
  const stats150 = await (await api(`/posts/${p150.id}/stats`)).json();
  expect(stats150).toEqual({
    word_count: 150,
    reading_minutes: 1,
    status: "draft",
  });

  // Post with 250 words (> 200 words => 2 min read)
  const words250 = Array(250).fill("word").join(" ");
  const p250 = await (await post("/posts", { content: words250 })).json();
  const stats250 = await (await api(`/posts/${p250.id}/stats`)).json();
  expect(stats250).toEqual({
    word_count: 250,
    reading_minutes: 2,
    status: "draft",
  });

  // Toggle publish status and verify status update in stats
  await post(`/posts/${p250.id}/publish`);
  const publishedStats = await (await api(`/posts/${p250.id}/stats`)).json();
  expect(publishedStats.status).toBe("published");

  // Non-existent ID returns 404
  const missingRes = await api("/posts/9999999/stats");
  expect(missingRes.status).toBe(404);
  expect(await missingRes.json()).toEqual({ error: "not found" });

  // Non-GET method returns 405
  const postRes = await post(`/posts/${p250.id}/stats`);
  expect(postRes.status).toBe(405);
  expect(await postRes.json()).toEqual({ error: "method not allowed" });
});

test("GET /api/stats returns counts of total, published, and draft posts, and total_words", async () => {
  // Get initial stats
  const initialRes = await api("/stats");
  expect(initialRes.status).toBe(200);
  expect(initialRes.headers.get("content-type")).toContain("application/json");
  const initialStats = await initialRes.json();
  expect(typeof initialStats.total).toBe("number");
  expect(typeof initialStats.published).toBe("number");
  expect(typeof initialStats.drafts).toBe("number");
  expect(typeof initialStats.total_words).toBe("number");

  // Create a draft post with content
  const p1 = await (await post("/posts", { title: "Draft 1", content: "hello world" })).json();

  // Create another post with content and publish it
  const p2 = await (await post("/posts", { title: "Pub 1", content: "one two three" })).json();
  await post(`/posts/${p2.id}/publish`);

  const updatedStats = await (await api("/stats")).json();
  expect(updatedStats.total).toBe(initialStats.total + 2);
  expect(updatedStats.published).toBe(initialStats.published + 1);
  expect(updatedStats.drafts).toBe(initialStats.drafts + 1);
  expect(updatedStats.total_words).toBe(initialStats.total_words + 5);

  // Method not allowed for POST /api/stats
  const postRes = await post("/stats");
  expect(postRes.status).toBe(405);
});

test("index.html, app.js, and style.css contain search filter UI elements and logic", async () => {
  const htmlRes = await fetch(`${base}/index.html`);
  const html = await htmlRes.text();
  expect(html).toContain('id="search-input"');
  expect(html).toContain('id="search-clear"');
  expect(html).toContain('id="search-count"');
  expect(html).toContain('class="search-box"');

  const jsRes = await fetch(`${base}/app.js`);
  const js = await jsRes.text();
  expect(js).toContain("searchInput");
  expect(js).toContain("searchClear");
  expect(js).toContain("searchCount");
  expect(js).toContain("performSearch");
  expect(js).toContain("/api/posts?q=");

  const cssRes = await fetch(`${base}/style.css`);
  const css = await cssRes.text();
  expect(css).toContain(".search-box");
  expect(css).toContain(".search-input");
  expect(css).toContain(".search-clear");
  expect(css).toContain(".search-count");
});

test("GET /api/tags returns distinct tag counts sorted by count DESC, tag ASC", async () => {
  // Test 405 for POST /api/tags and 404 for subpath /api/tags/foo
  const postRes = await post("/tags");
  expect(postRes.status).toBe(405);
  expect(await postRes.json()).toEqual({ error: "method not allowed" });

  const subpathRes = await api("/tags/foo");
  expect(subpathRes.status).toBe(404);
  expect(await subpathRes.json()).toEqual({ error: "not found" });

  // Clear existing posts so we can test tag counts cleanly
  await api("/posts"); // ensure table initialized
  const Database = (await import("bun:sqlite")).Database;
  const db = new Database(process.env.INKWELL_DB!);
  db.run("DELETE FROM posts");

  // Initial GET /api/tags on empty posts table
  const emptyRes = await api("/tags");
  expect(emptyRes.status).toBe(200);
  expect(await emptyRes.json()).toEqual({ tags: [] });

  // Create posts with title hashtags
  await post("/posts", { title: "First Post #tech #bun" });
  await post("/posts", { title: "Second Post #tech #sqlite" });
  await post("/posts", { title: "Third Post #tech #bun #zebra!" });

  const tagsRes = await api("/tags");
  expect(tagsRes.status).toBe(200);
  const data = await tagsRes.json();
  expect(data).toEqual({
    tags: [
      { tag: "tech", count: 3 },
      { tag: "bun", count: 2 },
      { tag: "sqlite", count: 1 },
      { tag: "zebra", count: 1 },
    ],
  });

  // Now test with 'tags' column added to posts table
  db.run("ALTER TABLE posts ADD COLUMN tags TEXT");
  db.run("DELETE FROM posts");

  // Post 1 has explicit tags, Post 2 has explicit tags with spaces, Post 3 falls back to hashtag in title
  db.run("INSERT INTO posts (title, tags) VALUES (?, ?)", ["Explicit 1", "bun, tech, javascript"]);
  db.run("INSERT INTO posts (title, tags) VALUES (?, ?)", ["Explicit 2", "tech, bun"]);
  db.run("INSERT INTO posts (title, tags) VALUES (?, ?)", ["Hashtag Fallback #javascript", null]);

  const tagsColRes = await api("/tags");
  expect(tagsColRes.status).toBe(200);
  const dataCol = await tagsColRes.json();
  expect(dataCol).toEqual({
    tags: [
      { tag: "bun", count: 2 },
      { tag: "javascript", count: 2 },
      { tag: "tech", count: 2 },
    ],
  });

  db.close();
});

test("style.css color variables meet WCAG AA contrast standards", async () => {
  const res = await fetch(`${base}/style.css`);
  expect(res.status).toBe(200);
  const css = await res.text();

  const getVar = (name: string): string => {
    const match = css.match(new RegExp(`${name}:\\s*([^;]+);`));
    if (!match) throw new Error(`Variable ${name} not found in style.css`);
    return match[1].trim();
  };

  const bg = getVar("--bg");
  const bgSidebar = getVar("--bg-sidebar");
  const border = getVar("--border");
  const textFaint = getVar("--text-faint");
  const textDim = getVar("--text-dim");

  function parseHex(hex: string): [number, number, number] {
    const h = hex.replace("#", "");
    const num = parseInt(h, 16);
    return [(num >> 16) & 255, (num >> 8) & 255, num & 255];
  }

  function relativeLuminance([r, g, b]: [number, number, number]): number {
    const rs = r / 255;
    const gs = g / 255;
    const bs = b / 255;
    const R = rs <= 0.04045 ? rs / 12.92 : Math.pow((rs + 0.055) / 1.055, 2.4);
    const G = gs <= 0.04045 ? gs / 12.92 : Math.pow((gs + 0.055) / 1.055, 2.4);
    const B = bs <= 0.04045 ? bs / 12.92 : Math.pow((bs + 0.055) / 1.055, 2.4);
    return 0.2126 * R + 0.7152 * G + 0.0722 * B;
  }

  function contrastRatio(hex1: string, hex2: string): number {
    const l1 = relativeLuminance(parseHex(hex1));
    const l2 = relativeLuminance(parseHex(hex2));
    const lighter = Math.max(l1, l2);
    const darker = Math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  // 1. --text-faint contrast ratio >= 4.5:1 against --bg and --bg-sidebar
  expect(contrastRatio(textFaint, bg)).toBeGreaterThanOrEqual(4.5);
  expect(contrastRatio(textFaint, bgSidebar)).toBeGreaterThanOrEqual(4.5);

  // 2. --text-dim contrast ratio >= 4.5:1 against input/hover dark backgrounds (#11161e and #161b22)
  expect(contrastRatio(textDim, "#11161e")).toBeGreaterThanOrEqual(4.5);
  expect(contrastRatio(textDim, "#161b22")).toBeGreaterThanOrEqual(4.5);

  // 3. --border contrast ratio against --bg is >= 1.5:1
  expect(contrastRatio(border, bg)).toBeGreaterThanOrEqual(1.5);

  // 4. Focus visible rules present
  expect(css).toContain(":focus-visible");
});

test("index.html contains brand vector icon and relocated new-post button in list-head", async () => {
  const res = await fetch(`${base}/index.html`);
  expect(res.status).toBe(200);
  const html = await res.text();

  // Brand header icon present
  expect(html).toContain('class="brand-icon"');
  expect(html).toContain('<svg class="brand-icon"');
  expect(html).toContain('viewBox="0 0 32 32"');
  expect(html).toContain('stroke-width="2.5"');
  expect(html).toContain('<rect width="32" height="32"');
  expect(html).toContain('<span>inkwell</span>');

  // Favicon uses vector SVG instead of emoji text
  expect(html).toContain('rel="icon"');
  expect(html).toContain('image/svg+xml');
  expect(html).not.toContain('&#9998;');

  // New post button is inside .list-head above post-list
  expect(html).toContain('class="list-head"');
  expect(html).toContain('id="new-post"');
  expect(html).toContain('class="new-btn"');

  // Verify structure: list-head comes before post-list, new-post is in list-head, not sidebar-head
  const listHeadIdx = html.indexOf('class="list-head"');
  const postListIdx = html.indexOf('id="post-list"');
  const newPostIdx = html.indexOf('id="new-post"');
  const searchBoxIdx = html.indexOf('class="search-box"');

  expect(listHeadIdx).toBeGreaterThan(searchBoxIdx);
  expect(postListIdx).toBeGreaterThan(listHeadIdx);
  expect(newPostIdx).toBeGreaterThan(listHeadIdx);
  expect(newPostIdx).toBeLessThan(postListIdx);
});

test("style.css contains styles for brand icon, brand alignment, and list-head controls", async () => {
  const res = await fetch(`${base}/style.css`);
  expect(res.status).toBe(200);
  const css = await res.text();

  expect(css).toContain(".brand-icon");
  expect(css).toContain(".list-head");
  expect(css).toContain(".brand");
  expect(css).toContain("display: inline-flex");
  expect(css).toContain("align-items: center");
});

test("theme tokens, light mode, and theme toggle controls are present", async () => {
  const htmlRes = await fetch(`${base}/index.html`);
  const html = await htmlRes.text();
  expect(html).toContain('id="theme-toggle"');
  expect(html).toContain("inkwell-theme");

  const cssRes = await fetch(`${base}/style.css`);
  const css = await cssRes.text();
  expect(css).toContain("--themes: dark light");
  expect(css).toContain('[data-theme="light"]');

  const jsRes = await fetch(`${base}/app.js`);
  const js = await jsRes.text();
  expect(js).toContain("inkwell-theme");
  expect(js).toContain("availableThemes");
  expect(js).toContain("applyTheme");
});
