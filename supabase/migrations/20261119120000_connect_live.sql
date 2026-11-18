-- Živá vysílání pro StudioVoxario Connect (sekce „Živě“): stav YouTube kanálů featured streamerů.
--
-- Funkce connect-live (každou minutu přes pg_cron) projde featured streamery (get_featured_streamers + profiles.youtube_handle),
-- z veřejného RSS kanálu vezme poslední videa a jedním voláním YouTube Data API (videos.list, 1 jednotka kvóty pro
-- všechny kanály dohromady) zjistí, co je živě, co je naplánované, počet diváků a miniaturu, kterou si streamer nastavil.
-- Tabulka je veřejně čitelná (Connect i web), zapisuje jen funkce (service role). Změny chodí přes Realtime.

create table if not exists public.live_youtube (
  user_id uuid primary key,
  handle text not null,
  channel_id text,
  channel_title text,
  channel_avatar text,
  status text not null default 'offline' check (status in ('live', 'upcoming', 'offline')),
  video_id text,
  title text,
  description text,
  thumbnail_url text,
  viewer_count integer not null default 0,
  like_count integer,
  started_at timestamptz,
  scheduled_start_at timestamptz,
  chat_enabled boolean not null default false,
  last_live_at timestamptz,
  checked_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.live_youtube enable row level security;

drop policy if exists live_youtube_public_read on public.live_youtube;
create policy live_youtube_public_read on public.live_youtube for select using (true);

create index if not exists live_youtube_status_idx on public.live_youtube (status, viewer_count desc);

do $$
begin
  alter publication supabase_realtime add table public.live_youtube;
exception when others then null;
end $$;

-- plánovač: každou minutu (funkce sama nepouští kontrolu častěji než jednou za 45 s)
do $$
begin
  perform cron.unschedule('connect-live-job');
exception when others then null;
end $$;

do $$
begin
  perform cron.schedule(
    'connect-live-job',
    '* * * * *',
    $c$
    select net.http_post(
      url := 'https://rioexuvgvmdwvidfakxy.supabase.co/functions/v1/connect-live',
      headers := '{"Content-Type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJpb2V4dXZndm1kd3ZpZGZha3h5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0MzM5NTUsImV4cCI6MjA5MjAwOTk1NX0.LdZvFJw_W-0wD1XUFPFjGpu9Mp1BT_j_HJOOMr3VbLE"}'::jsonb,
      body := '{}'::jsonb
    );
    $c$
  );
exception when others then null;
end $$;
