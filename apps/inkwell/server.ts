// inkwell — minimalist blog writing app. Bun + bun:sqlite, zero dependencies.
// Run: bun run server.ts   (PORT and INKWELL_DB env overrides supported)

import { Database } from "bun:sqlite";

const APP_DIR = import.meta.dir;
const PUBLIC_DIR = `${APP_DIR}/public`;
const PORT = Number(process.env.PORT ?? 4501);

type Post = {
  id: number;
  title: string;
  content: string;
  status: string;
  target_word_count: number;
  created_at: string;
  updated_at: string;
};

// ─── db ────────────────────────────────────────────────────────────────────
// Opened lazily so INKWELL_DB can be set by a test before the first request.
let _db: Database | null = null;

function db(): Database {
  if (_db) return _db;
  const path = process.env.INKWELL_DB || `${APP_DIR}/inkwell.db`;
  _db = new Database(path, { create: true });
  _db.run(`
    CREATE TABLE IF NOT EXISTS posts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT,
      content TEXT,
      status TEXT DEFAULT 'draft',
      target_word_count INTEGER DEFAULT 0,
      created_at TEXT,
      updated_at TEXT
    )
  `);
  try {
    _db.run("ALTER TABLE posts ADD COLUMN target_word_count INTEGER DEFAULT 0");
  } catch {
    // Column already exists
  }
  return _db;
}

export function closeDb(): void {
  _db?.close();
  _db = null;
}

const now = () => new Date().toISOString();

const wordCount = (content: string) =>
  content.trim() === "" ? 0 : content.trim().split(/\s+/).length;

const getPost = (id: number) =>
  db().query("SELECT * FROM posts WHERE id = ?").get(id) as Post | null;

// ─── responses ─────────────────────────────────────────────────────────────
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

const notFound = () => json({ error: "not found" }, 404);

/** Reads a JSON body, tolerating an empty one. Throws on malformed JSON. */
async function readBody(req: Request): Promise<Record<string, unknown>> {
  const text = await req.text();
  if (text.trim() === "") return {};
  const parsed = JSON.parse(text);
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new SyntaxError("body must be a JSON object");
  }
  return parsed as Record<string, unknown>;
}

// ─── static ────────────────────────────────────────────────────────────────
const CONTENT_TYPES: Record<string, string> = {
  html: "text/html; charset=utf-8",
  js: "text/javascript; charset=utf-8",
  mjs: "text/javascript; charset=utf-8",
  css: "text/css; charset=utf-8",
  json: "application/json",
  svg: "image/svg+xml",
  png: "image/png",
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  gif: "image/gif",
  webp: "image/webp",
  ico: "image/x-icon",
  woff2: "font/woff2",
  txt: "text/plain; charset=utf-8",
};

async function serveStatic(pathname: string): Promise<Response> {
  const rel = pathname === "/" ? "index.html" : decodeURIComponent(pathname).slice(1);
  if (rel.includes("..")) return new Response("forbidden", { status: 403 });

  const file = Bun.file(`${PUBLIC_DIR}/${rel}`);
  if (!(await file.exists())) return new Response("not found", { status: 404 });

  const ext = rel.split(".").pop()?.toLowerCase() ?? "";
  return new Response(file, {
    headers: { "content-type": CONTENT_TYPES[ext] ?? "application/octet-stream" },
  });
}

// ─── api ───────────────────────────────────────────────────────────────────
async function handleApi(req: Request, pathname: string): Promise<Response> {
  const segments = pathname.split("/").filter(Boolean); // ["api", "posts", ...]
  const method = req.method.toUpperCase();

  if (segments[1] === "stats") {
    if (segments.length === 2) {
      if (method === "GET") {
        const row = db()
          .query(
            "SELECT COUNT(*) as total, COUNT(CASE WHEN status = 'published' THEN 1 END) as published, COUNT(CASE WHEN status = 'draft' THEN 1 END) as drafts FROM posts",
          )
          .get() as { total: number; published: number; drafts: number };
        const posts = db().query("SELECT content FROM posts").all() as { content: string | null }[];
        const totalWords = posts.reduce((sum, p) => sum + wordCount(p.content ?? ""), 0);
        return json({
          total: row.total,
          published: row.published,
          drafts: row.drafts,
          total_words: totalWords,
        });
      }
      return json({ error: "method not allowed" }, 405);
    }
    return notFound();
  }

  if (segments[1] === "tags") {
    if (segments.length === 2) {
      if (method === "GET") {
        const tableInfo = db().query("PRAGMA table_info(posts)").all() as { name: string }[];
        const hasTagsColumn = tableInfo.some((col) => col.name === "tags");

        const posts = hasTagsColumn
          ? (db().query("SELECT title, tags FROM posts").all() as { title: string | null; tags?: string | null }[])
          : (db().query("SELECT title FROM posts").all() as { title: string | null });

        const tagCounts: Record<string, number> = {};

        for (const post of posts) {
          const postTags = new Set<string>();

          if (
            hasTagsColumn &&
            typeof (post as { tags?: string | null }).tags === "string" &&
            (post as { tags: string }).tags.trim() !== ""
          ) {
            const rawTags = (post as { tags: string }).tags.split(",");
            for (const rawTag of rawTags) {
              const trimmed = rawTag.trim();
              if (trimmed) {
                postTags.add(trimmed);
              }
            }
          } else {
            const title = post.title ?? "";
            const hashtagMatches = title.match(/#([^\s#]+)/g) || [];
            for (const match of hashtagMatches) {
              const tag = match.slice(1).replace(/[.,!?:;'"()\[\]{}]+$/, "").trim();
              if (tag) {
                postTags.add(tag);
              }
            }
          }

          for (const tag of postTags) {
            tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
          }
        }

        const tags = Object.entries(tagCounts)
          .map(([tag, count]) => ({ tag, count }))
          .sort((a, b) => {
            if (b.count !== a.count) {
              return b.count - a.count;
            }
            return a.tag.localeCompare(b.tag);
          });

        return json({ tags });
      }
      return json({ error: "method not allowed" }, 405);
    }
    return notFound();
  }

  if (segments[1] !== "posts") return notFound();

  // /api/posts
  if (segments.length === 2) {
    if (method === "GET") {
      const url = new URL(req.url);
      const query = url.searchParams.get("q") ?? url.searchParams.get("search") ?? "";
      const trimmed = query.trim();

      let rows: Post[];
      if (trimmed) {
        const pattern = `%${trimmed}%`;
        rows = db()
          .query("SELECT * FROM posts WHERE title LIKE ? OR content LIKE ? ORDER BY updated_at DESC, id DESC")
          .all(pattern, pattern) as Post[];
      } else {
        rows = db()
          .query("SELECT * FROM posts ORDER BY updated_at DESC, id DESC")
          .all() as Post[];
      }

      return json(
        rows.map((p) => ({
          id: p.id,
          title: p.title,
          status: p.status,
          updated_at: p.updated_at,
          word_count: wordCount(p.content ?? ""),
          target_word_count: p.target_word_count ?? 0,
        })),
      );
    }

    if (method === "POST") {
      const body = await readBody(req);
      const title = typeof body.title === "string" ? body.title : "Untitled";
      const content = typeof body.content === "string" ? body.content : "";
      const targetWordCount =
        typeof body.target_word_count === "number" && body.target_word_count >= 0
          ? Math.floor(body.target_word_count)
          : 0;
      const ts = now();
      const { lastInsertRowid } = db().run(
        "INSERT INTO posts (title, content, status, target_word_count, created_at, updated_at) VALUES (?, ?, 'draft', ?, ?, ?)",
        [title, content, targetWordCount, ts, ts],
      );
      return json(getPost(Number(lastInsertRowid)), 201);
    }

    return json({ error: "method not allowed" }, 405);
  }

  const id = Number(segments[2]);
  if (!Number.isInteger(id)) return notFound();

  // /api/posts/:id/publish
  if (segments.length === 4 && segments[3] === "publish") {
    if (method !== "POST") return json({ error: "method not allowed" }, 405);
    const post = getPost(id);
    if (!post) return notFound();
    const status = post.status === "published" ? "draft" : "published";
    db().run("UPDATE posts SET status = ?, updated_at = ? WHERE id = ?", [status, now(), id]);
    return json(getPost(id));
  }

  // /api/posts/:id/stats
  if (segments.length === 4 && segments[3] === "stats") {
    if (method !== "GET") return json({ error: "method not allowed" }, 405);
    const post = getPost(id);
    if (!post) return notFound();
    const wc = wordCount(post.content ?? "");
    const readingMinutes = wc === 0 ? 0 : Math.ceil(wc / 200);
    return json({
      word_count: wc,
      reading_minutes: readingMinutes,
      status: post.status,
    });
  }

  // /api/posts/:id
  if (segments.length === 3) {
    const post = getPost(id);
    if (!post) return notFound();

    if (method === "GET") return json(post);

    if (method === "PUT") {
      const body = await readBody(req);
      const title = typeof body.title === "string" ? body.title : post.title;
      const content = typeof body.content === "string" ? body.content : post.content;
      let targetWordCount = post.target_word_count ?? 0;
      if (typeof body.target_word_count === "number" && body.target_word_count >= 0) {
        targetWordCount = Math.floor(body.target_word_count);
      } else if (body.target_word_count === null) {
        targetWordCount = 0;
      }
      db().run(
        "UPDATE posts SET title = ?, content = ?, target_word_count = ?, updated_at = ? WHERE id = ?",
        [title, content, targetWordCount, now(), id],
      );
      return json(getPost(id));
    }

    if (method === "DELETE") {
      db().run("DELETE FROM posts WHERE id = ?", [id]);
      return json({ ok: true });
    }

    return json({ error: "method not allowed" }, 405);
  }

  return notFound();
}

// ─── entry ─────────────────────────────────────────────────────────────────
export async function handleRequest(req: Request): Promise<Response> {
  const { pathname } = new URL(req.url);

  if (pathname === "/api" || pathname.startsWith("/api/")) {
    try {
      return await handleApi(req, pathname);
    } catch (err) {
      if (err instanceof SyntaxError) return json({ error: "malformed JSON body" }, 400);
      return json({ error: String(err) }, 500);
    }
  }

  return serveStatic(pathname);
}

if (import.meta.main) {
  const server = Bun.serve({ port: PORT, fetch: handleRequest });
  console.log(`inkwell listening on http://localhost:${server.port}`);
}
