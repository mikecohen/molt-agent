import type { AgentToolResult } from "@mariozechner/pi-agent-core";
import { Type } from "@sinclair/typebox";
import { emptyPluginConfigSchema, type OpenClawPluginApi } from "openclaw/plugin-sdk";

import { formatMoltbookResponse, moltbookFetch } from "./client.js";

function textResult(message: string): AgentToolResult<Record<string, never>> {
  return {
    content: [{ type: "text", text: message }],
    details: {},
  };
}

const plugin = {
  id: "moltbook",
  name: "Moltbook",
  description: "Moltbook community tools (feed, posts, comments, search).",
  configSchema: emptyPluginConfigSchema(),
  register(api: OpenClawPluginApi) {
    api.registerTool({
      name: "moltbook_get_me",
      label: "Moltbook · profile",
      description:
        "Get the current Moltbook agent profile (authenticated as your bot). Use to confirm identity and stats.",
      parameters: Type.Object({}),
      async execute() {
        try {
          const r = await moltbookFetch("/agents/me");
          return textResult(formatMoltbookResponse(r));
        } catch (e) {
          return textResult(e instanceof Error ? e.message : String(e));
        }
      },
    });

    api.registerTool({
      name: "moltbook_feed",
      label: "Moltbook · feed",
      description: "Personalized Moltbook feed from subscribed submolts and followed agents.",
      parameters: Type.Object({
        sort: Type.Optional(
          Type.Union([
            Type.Literal("hot"),
            Type.Literal("new"),
            Type.Literal("top"),
            Type.Literal("rising"),
          ]),
        ),
        limit: Type.Optional(Type.Number({ minimum: 1, maximum: 50 })),
      }),
      async execute(_id, params) {
        try {
          const q = new URLSearchParams();
          if (params.sort) {
            q.set("sort", params.sort);
          }
          if (params.limit != null) {
            q.set("limit", String(params.limit));
          }
          const path = `/feed${q.toString() ? `?${q}` : ""}`;
          const r = await moltbookFetch(path);
          return textResult(formatMoltbookResponse(r));
        } catch (e) {
          return textResult(e instanceof Error ? e.message : String(e));
        }
      },
    });

    api.registerTool({
      name: "moltbook_list_posts",
      label: "Moltbook · posts",
      description: "List posts (global) with sort order.",
      parameters: Type.Object({
        sort: Type.Optional(
          Type.Union([
            Type.Literal("hot"),
            Type.Literal("new"),
            Type.Literal("top"),
            Type.Literal("rising"),
          ]),
        ),
        limit: Type.Optional(Type.Number({ minimum: 1, maximum: 50 })),
      }),
      async execute(_id, params) {
        try {
          const q = new URLSearchParams();
          if (params.sort) {
            q.set("sort", params.sort);
          }
          if (params.limit != null) {
            q.set("limit", String(params.limit));
          }
          const path = `/posts${q.toString() ? `?${q}` : ""}`;
          const r = await moltbookFetch(path);
          return textResult(formatMoltbookResponse(r));
        } catch (e) {
          return textResult(e instanceof Error ? e.message : String(e));
        }
      },
    });

    api.registerTool({
      name: "moltbook_get_post",
      label: "Moltbook · get post",
      description: "Fetch a single post by id.",
      parameters: Type.Object({
        post_id: Type.String({ minLength: 1 }),
      }),
      async execute(_id, params) {
        try {
          const enc = encodeURIComponent(params.post_id);
          const r = await moltbookFetch(`/posts/${enc}`);
          return textResult(formatMoltbookResponse(r));
        } catch (e) {
          return textResult(e instanceof Error ? e.message : String(e));
        }
      },
    });

    api.registerTool({
      name: "moltbook_create_post",
      label: "Moltbook · create post",
      description:
        "Create a Moltbook post. Use content for a text post, OR url for a link post (not both). Respect rate limits (posts are heavily limited).",
      parameters: Type.Object({
        submolt: Type.String({ minLength: 1 }),
        title: Type.String({ minLength: 1 }),
        content: Type.Optional(Type.String()),
        url: Type.Optional(Type.String()),
      }),
      async execute(_id, params) {
        try {
          const hasContent = params.content != null && params.content.trim() !== "";
          const hasUrl = params.url != null && params.url.trim() !== "";
          if (hasContent === hasUrl) {
            return textResult("Provide exactly one of: content (text post) or url (link post).");
          }
          const body: Record<string, string> = {
            submolt: params.submolt,
            title: params.title,
          };
          if (hasContent) {
            body.content = params.content!.trim();
          } else {
            body.url = params.url!.trim();
          }
          const r = await moltbookFetch("/posts", {
            method: "POST",
            body: JSON.stringify(body),
          });
          return textResult(formatMoltbookResponse(r));
        } catch (e) {
          return textResult(e instanceof Error ? e.message : String(e));
        }
      },
    });

    api.registerTool({
      name: "moltbook_comment",
      label: "Moltbook · comment",
      description: "Add a comment on a post. Optional parent_id for a threaded reply.",
      parameters: Type.Object({
        post_id: Type.String({ minLength: 1 }),
        content: Type.String({ minLength: 1 }),
        parent_id: Type.Optional(Type.String()),
      }),
      async execute(_id, params) {
        try {
          const enc = encodeURIComponent(params.post_id);
          const body: Record<string, string> = { content: params.content };
          if (params.parent_id) {
            body.parent_id = params.parent_id;
          }
          const r = await moltbookFetch(`/posts/${enc}/comments`, {
            method: "POST",
            body: JSON.stringify(body),
          });
          return textResult(formatMoltbookResponse(r));
        } catch (e) {
          return textResult(e instanceof Error ? e.message : String(e));
        }
      },
    });

    api.registerTool({
      name: "moltbook_search",
      label: "Moltbook · search",
      description: "Search Moltbook for posts, agents, and submolts.",
      parameters: Type.Object({
        query: Type.String({ minLength: 1 }),
        limit: Type.Optional(Type.Number({ minimum: 1, maximum: 50 })),
      }),
      async execute(_id, params) {
        try {
          const q = new URLSearchParams();
          q.set("q", params.query);
          if (params.limit != null) {
            q.set("limit", String(params.limit));
          }
          const r = await moltbookFetch(`/search?${q}`);
          return textResult(formatMoltbookResponse(r));
        } catch (e) {
          return textResult(e instanceof Error ? e.message : String(e));
        }
      },
    });

    api.registerTool({
      name: "moltbook_list_submolts",
      label: "Moltbook · submolts",
      description: "List Moltbook communities (submolts).",
      parameters: Type.Object({}),
      async execute() {
        try {
          const r = await moltbookFetch("/submolts");
          return textResult(formatMoltbookResponse(r));
        } catch (e) {
          return textResult(e instanceof Error ? e.message : String(e));
        }
      },
    });

    api.registerTool(
      {
        name: "moltbook_upvote_post",
        label: "Moltbook · upvote",
        description: "Upvote a post by id.",
        parameters: Type.Object({
          post_id: Type.String({ minLength: 1 }),
        }),
        async execute(_id, params) {
          try {
            const enc = encodeURIComponent(params.post_id);
            const r = await moltbookFetch(`/posts/${enc}/upvote`, { method: "POST", body: "{}" });
            return textResult(formatMoltbookResponse(r));
          } catch (e) {
            return textResult(e instanceof Error ? e.message : String(e));
          }
        },
      },
      { optional: true },
    );

    api.registerTool(
      {
        name: "moltbook_downvote_post",
        label: "Moltbook · downvote",
        description: "Downvote a post by id.",
        parameters: Type.Object({
          post_id: Type.String({ minLength: 1 }),
        }),
        async execute(_id, params) {
          try {
            const enc = encodeURIComponent(params.post_id);
            const r = await moltbookFetch(`/posts/${enc}/downvote`, { method: "POST", body: "{}" });
            return textResult(formatMoltbookResponse(r));
          } catch (e) {
            return textResult(e instanceof Error ? e.message : String(e));
          }
        },
      },
      { optional: true },
    );
  },
};

export default plugin;
