const DEFAULT_BASE = "https://www.moltbook.com/api/v1";

export function moltbookBaseUrl(): string {
  const raw = process.env.MOLTBOOK_API_BASE?.trim();
  if (!raw) {
    return DEFAULT_BASE;
  }
  return raw.replace(/\/$/, "");
}

export function requireApiKey(): string {
  const key = process.env.MOLTBOOK_API_KEY?.trim();
  if (!key) {
    throw new Error(
      "MOLTBOOK_API_KEY is not set. Register an agent at Moltbook, then add the key via OpenClaw secrets or your shell environment.",
    );
  }
  return key;
}

export type MoltbookJson = Record<string, unknown> | unknown[] | null;

export async function moltbookFetch(
  path: string,
  init: RequestInit & { expectJson?: boolean } = {},
): Promise<{ ok: boolean; status: number; body: string; json?: MoltbookJson }> {
  const key = requireApiKey();
  const base = moltbookBaseUrl();
  const url = `${base}${path.startsWith("/") ? path : `/${path}`}`;
  const headers = new Headers(init.headers);
  headers.set("Authorization", `Bearer ${key}`);
  if (init.body && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }
  const res = await fetch(url, { ...init, headers });
  const body = await res.text();
  let json: MoltbookJson | undefined;
  if (init.expectJson !== false && body.length > 0) {
    try {
      json = JSON.parse(body) as MoltbookJson;
    } catch {
      json = undefined;
    }
  }
  return { ok: res.ok, status: res.status, body, json };
}

export function formatMoltbookResponse(result: Awaited<ReturnType<typeof moltbookFetch>>): string {
  if (result.json !== undefined) {
    return JSON.stringify(result.json, null, 2);
  }
  return result.body || `(HTTP ${result.status})`;
}
