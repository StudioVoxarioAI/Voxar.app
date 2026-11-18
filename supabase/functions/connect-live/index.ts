// Živá vysílání YouTube pro StudioVoxario Connect (a web): stav kanálů featured streamerů -> public.live_youtube.
//
// Postup (jen oficiální rozhraní YouTube):
//   1. featured streameři: rpc get_featured_streamers + profiles.youtube_handle
//   2. ID kanálu: YouTube Data API channels.list?forHandle (uloží se, příště se nehledá)
//   3. kandidátní videa: veřejný RSS kanálu (feeds/videos.xml – posledních 15 videí včetně živých a naplánovaných)
//      + video, které bylo živě minule (dokud neskončí)
//   4. videos.list?part=snippet,liveStreamingDetails,statistics – po 50 ID najednou (1 jednotka kvóty za volání):
//      živě = actualStartTime bez actualEndTime, naplánováno = nejbližší scheduledStartTime v budoucnu
//   5. miniatura = ta, kterou si streamer nastavil (snippet.thumbnails maxres -> standard -> high)
// Výsledek jde také do live_streams_cache (stávající sekce webu dostane stejné údaje).
//
// Spouští pg_cron každou minutu; častější volání (Connect při otevření sekce) vrátí jen uložený stav.
// Secrets: YOUTUBE_API_KEY (Google Cloud – YouTube Data API v3), SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const MIN_INTERVAL_MS = 45_000;
const API = "https://www.googleapis.com/youtube/v3";

type Row = {
  user_id: string;
  handle: string;
  channel_id: string | null;
  channel_title: string | null;
  channel_avatar: string | null;
  status: "live" | "upcoming" | "offline";
  video_id: string | null;
  title: string | null;
  description: string | null;
  thumbnail_url: string | null;
  viewer_count: number;
  like_count: number | null;
  started_at: string | null;
  scheduled_start_at: string | null;
  chat_enabled: boolean;
  last_live_at: string | null;
  checked_at: string;
  updated_at: string;
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

function cleanHandle(h: string): string {
  let s = h.trim();
  const m = s.match(/youtube\.com\/(@[\w.\-]+|channel\/UC[\w-]{22})/i);
  if (m) s = m[1];
  if (s.startsWith("channel/")) return s;
  return s.startsWith("@") ? s : `@${s}`;
}

async function yt<T>(path: string, key: string): Promise<T> {
  const r = await fetch(`${API}/${path}${path.includes("?") ? "&" : "?"}key=${key}`);
  if (!r.ok) throw new Error(`YouTube API ${r.status}: ${(await r.text()).slice(0, 300)}`);
  return (await r.json()) as T;
}

function bestThumb(t: Record<string, { url: string }> | undefined): string | null {
  if (!t) return null;
  return (t.maxres ?? t.standard ?? t.high ?? t.medium ?? t.default)?.url ?? null;
}

async function rssVideoIds(channelId: string): Promise<string[]> {
  try {
    const r = await fetch(`https://www.youtube.com/feeds/videos.xml?channel_id=${channelId}`);
    if (!r.ok) return [];
    const xml = await r.text();
    return [...xml.matchAll(/<yt:videoId>([\w-]{11})<\/yt:videoId>/g)].map((m) => m[1]);
  } catch {
    return [];
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const key = Deno.env.get("YOUTUBE_API_KEY");

    const { data: existing } = await admin.from("live_youtube").select("*");
    const prev = new Map<string, Row>((existing ?? []).map((r: Row) => [r.user_id, r]));
    const newest = Math.max(0, ...(existing ?? []).map((r: Row) => Date.parse(r.checked_at) || 0));
    if (Date.now() - newest < MIN_INTERVAL_MS) return json({ ok: true, cached: true, streams: existing ?? [] });
    if (!key) return json({ ok: false, error: "Chybí secret YOUTUBE_API_KEY (YouTube Data API v3).", streams: existing ?? [] }, 200);

    // 1) featured streameři s YouTube kanálem
    const { data: featured, error: fErr } = await admin.rpc("get_featured_streamers");
    if (fErr) throw fErr;
    const ids = (featured ?? []).map((r: { user_id: string }) => r.user_id);
    const { data: profiles } = ids.length
      ? await admin.from("profiles").select("user_id, youtube_handle").in("user_id", ids)
      : { data: [] };
    const people = (profiles ?? [])
      .filter((p: { youtube_handle: string | null }) => p.youtube_handle?.trim())
      .map((p: { user_id: string; youtube_handle: string }) => ({ user_id: p.user_id, handle: cleanHandle(p.youtube_handle) }));

    // kdo už není featured / nemá kanál -> pryč
    const keep = new Set(people.map((p) => p.user_id));
    const gone = (existing ?? []).filter((r: Row) => !keep.has(r.user_id)).map((r: Row) => r.user_id);
    if (gone.length) await admin.from("live_youtube").delete().in("user_id", gone);

    // 2) ID a vzhled kanálu (jen když chybí nebo se změnil handle; obrázek kanálu obnovit jednou za den)
    const now = new Date().toISOString();
    const rows: Row[] = [];
    for (const p of people) {
      const old = prev.get(p.user_id);
      let channelId = old && old.handle === p.handle ? old.channel_id : null;
      let title = old?.channel_title ?? null;
      let avatar = old?.channel_avatar ?? null;
      const stale = !old || Date.now() - Date.parse(old.updated_at) > 24 * 3600_000;
      if (!channelId || stale) {
        try {
          const q = p.handle.startsWith("channel/") ? `id=${p.handle.slice(8)}` : `forHandle=${encodeURIComponent(p.handle)}`;
          const c = await yt<{ items?: Array<{ id: string; snippet: { title: string; thumbnails: Record<string, { url: string }> } }> }>(
            `channels?part=snippet&${q}`, key);
          const it = c.items?.[0];
          if (it) { channelId = it.id; title = it.snippet.title; avatar = bestThumb(it.snippet.thumbnails); }
        } catch (e) { console.error("channel", p.handle, e); }
      }
      rows.push({
        user_id: p.user_id, handle: p.handle, channel_id: channelId, channel_title: title, channel_avatar: avatar,
        status: "offline", video_id: null, title: null, description: null, thumbnail_url: null, viewer_count: 0, like_count: null,
        started_at: null, scheduled_start_at: null, chat_enabled: false, last_live_at: old?.last_live_at ?? null,
        checked_at: now, updated_at: stale ? now : old!.updated_at,
      });
    }

    // 3) kandidátní videa z RSS (+ minule živé video)
    const candidates = new Map<string, string[]>();
    await Promise.all(rows.filter((r) => r.channel_id).map(async (r) => {
      const vids = (await rssVideoIds(r.channel_id!)).slice(0, 15);
      const old = prev.get(r.user_id);
      if (old?.video_id && !vids.includes(old.video_id)) vids.unshift(old.video_id);
      candidates.set(r.user_id, vids);
    }));

    // 4) detaily videí po 50
    const all = [...new Set([...candidates.values()].flat())];
    type Video = {
      id: string;
      snippet: { channelId: string; title: string; description: string; liveBroadcastContent: string; thumbnails: Record<string, { url: string }> };
      liveStreamingDetails?: { actualStartTime?: string; actualEndTime?: string; scheduledStartTime?: string; concurrentViewers?: string; activeLiveChatId?: string };
      statistics?: { likeCount?: string };
    };
    const videos = new Map<string, Video>();
    for (let i = 0; i < all.length; i += 50) {
      const part = all.slice(i, i + 50);
      const v = await yt<{ items?: Video[] }>(`videos?part=snippet,liveStreamingDetails,statistics&id=${part.join(",")}`, key);
      for (const it of v.items ?? []) videos.set(it.id, it);
    }

    // 5) stav každého kanálu
    const nowMs = Date.now();
    for (const r of rows) {
      const vids = (candidates.get(r.user_id) ?? []).map((id) => videos.get(id)).filter(Boolean) as Video[];
      const live = vids
        .filter((v) => v.liveStreamingDetails?.actualStartTime && !v.liveStreamingDetails.actualEndTime)
        .sort((a, b) => Number(b.liveStreamingDetails?.concurrentViewers ?? 0) - Number(a.liveStreamingDetails?.concurrentViewers ?? 0))[0];
      const upcoming = vids
        .filter((v) => v.snippet.liveBroadcastContent === "upcoming" && v.liveStreamingDetails?.scheduledStartTime &&
          Date.parse(v.liveStreamingDetails.scheduledStartTime) > nowMs - 2 * 3600_000)
        .sort((a, b) => Date.parse(a.liveStreamingDetails!.scheduledStartTime!) - Date.parse(b.liveStreamingDetails!.scheduledStartTime!))[0];
      const v = live ?? upcoming;
      if (!v) continue;
      r.status = live ? "live" : "upcoming";
      r.video_id = v.id;
      r.title = v.snippet.title;
      r.description = (v.snippet.description ?? "").slice(0, 2000);
      r.thumbnail_url = bestThumb(v.snippet.thumbnails) ?? `https://i.ytimg.com/vi/${v.id}/hqdefault.jpg`;
      r.viewer_count = Number(v.liveStreamingDetails?.concurrentViewers ?? 0);
      r.like_count = v.statistics?.likeCount ? Number(v.statistics.likeCount) : null;
      r.started_at = v.liveStreamingDetails?.actualStartTime ?? null;
      r.scheduled_start_at = v.liveStreamingDetails?.scheduledStartTime ?? null;
      r.chat_enabled = !!v.liveStreamingDetails?.activeLiveChatId;
      if (live) r.last_live_at = now;
    }

    if (rows.length) {
      const { error } = await admin.from("live_youtube").upsert(rows, { onConflict: "user_id" });
      if (error) throw error;
      // stávající sekce webu (live_streams_cache) dostane stejné údaje
      const cache = rows.map((r) => ({
        user_id: r.user_id, platform: "youtube", handle: r.handle, is_live: r.status === "live", title: r.title, game_name: null,
        viewer_count: r.viewer_count, thumbnail_url: r.thumbnail_url,
        stream_url: r.video_id ? `https://www.youtube.com/watch?v=${r.video_id}` : `https://www.youtube.com/${r.handle}`,
        started_at: r.started_at, scheduled_start_at: r.status === "upcoming" ? r.scheduled_start_at : null, checked_at: now,
      }));
      const { error: cErr } = await admin.from("live_streams_cache").upsert(cache, { onConflict: "user_id,platform" });
      if (cErr) console.error("live_streams_cache", cErr);
    }
    return json({ ok: true, checked: rows.length, live: rows.filter((r) => r.status === "live").length, streams: rows });
  } catch (e) {
    console.error("connect-live", e);
    return json({ ok: false, error: String((e as Error)?.message ?? e) }, 500);
  }
});
