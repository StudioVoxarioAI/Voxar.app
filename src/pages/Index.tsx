import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import {
  ArrowRight, Download, Sparkles, Globe, ShieldCheck, Swords, MessageCircle, Radio, ShoppingBag, Bot,
  Target, Server, Trophy, Lock, FileCheck2, Database, History, Scale, LifeBuoy, Users, Activity, Newspaper,
  type LucideIcon,
} from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { usePresence } from "@/contexts/PresenceContext";
import { useSiteSettings } from "@/contexts/SiteSettingsContext";
import { useFeaturedDiscord } from "@/hooks/useFeaturedDiscord";
import { useInlineEditor } from "@/contexts/InlineEditorContext";
import { fetchPageBySlug } from "@/hooks/usePages";
import type { Block } from "@/lib/pageBuilder/types";
import { Navbar } from "@/components/Navbar";
import { SEO } from "@/components/SEO";
import { AnnouncementBar } from "@/components/AnnouncementBar";
import { TopPlayersPreview } from "@/components/TopPlayersPreview";
import { EditPageButton } from "@/components/pageBuilder/EditPageButton";
import { EditableBlocks } from "@/components/pageBuilder/EditableBlocks";
import { InlineEditorFrame } from "@/components/pageBuilder/InlineEditorChrome";
import { UserAvatar } from "@/components/UserAvatar";

type PlatformStats = {
  members: number;
  active_7d: number;
  forum_threads: number;
  forum_posts: number;
  servers: number;
  servers_online: number;
  bot_servers: number;
  communities: number;
  live_streams: number;
  generated_at: string;
};

type TeamMember = { display_name: string | null; avatar_url: string | null; role: string };
type Release = { tag: string; publishedAt: string };

const products: { to: string; name: string; tag: string; desc: string; image: string; icon: LucideIcon; status?: string }[] = [
  {
    to: "/app",
    name: "Voxar.app",
    tag: "Komunita",
    desc: "Kanály, hlasové místnosti, události a obchod s kosmetikou. Celá komunita v jednom okně – na webu i v aplikaci pro Windows.",
    image: "/web/shot-community.webp",
    icon: Sparkles,
  },
  {
    to: "/browser",
    name: "VoxarioBrowser",
    tag: "Prohlížeč",
    desc: "Herní prohlížeč s pracovními prostory, ochranou soukromí, blokací reklam a vlastními aktualizacemi.",
    image: "/web/shot-browser.webp",
    icon: Globe,
  },
  {
    to: "/ashes",
    name: "Ashes of Eryon",
    tag: "Hra",
    desc: "Temné fantasy RPG s vlastním launcherem. Každé rozhodnutí zanechává stopu.",
    image: "/web/shot-ashes.webp",
    icon: Swords,
    status: "První test 24. 10.",
  },
];

const services: { to: string; name: string; desc: string; icon: LucideIcon }[] = [
  { to: "/desktop", name: "VoxarioProtect", desc: "Posílí Windows Defender, hlídá autostart a vrátí změny jedním klikem.", icon: ShieldCheck },
  { to: "/forum", name: "Fórum", desc: "Diskuze, návody a nápady komunity.", icon: MessageCircle },
  { to: "/live", name: "Live", desc: "Kdo z komunity právě streamuje.", icon: Radio },
  { to: "/obchod", name: "Obchod", desc: "Kosmetika, odznaky a výhody pro podporovatele.", icon: ShoppingBag },
  { to: "/dashboard/bot", name: "Discord bot", desc: "Moderace, tickety, body a oznámení pro tvůj server.", icon: Bot },
  { to: "/kontrakty", name: "Bounty Board", desc: "Kontrakty a odměny za pomoc ostatním.", icon: Target },
  { to: "/servery", name: "Servery", desc: "Herní servery komunity a jejich stav.", icon: Server },
  { to: "/leaderboard", name: "Žebříček", desc: "Nejaktivnější hráči a jejich body.", icon: Trophy },
];

const trust: { title: string; desc: string; icon: LucideIcon; to?: string }[] = [
  { title: "Bezpečné přihlášení", desc: "Přihlášení e-mailem nebo účtem Google. Hesla se nikdy neukládají v čitelné podobě.", icon: Lock },
  { title: "Práva hlídá databáze", desc: "Každý vidí jen to, co smí. Pravidla přístupu platí přímo v databázi, ne jen v aplikaci.", icon: Database },
  { title: "Ověřené instalátory", desc: "Ke každé verzi zveřejňujeme kontrolní součet SHA-256. Aktualizace se ověřují před instalací.", icon: FileCheck2, to: "/desktop" },
  { title: "Ochrana počítače", desc: "VoxarioProtect spolupracuje s Windows Defenderem – nic nemění bez tvého potvrzení.", icon: ShieldCheck, to: "/desktop" },
  { title: "Otevřený vývoj", desc: "Každá změna aplikací je zapsaná ve veřejné historii verzí.", icon: History, to: "/verze" },
  { title: "Jasná pravidla", desc: "Srozumitelné obchodní podmínky, ochrana soukromí a moderace, kterou dělají lidé i AI.", icon: Scale, to: "/obchodni-podminky" },
];

const roleLabel: Record<string, string> = { admin: "Zakladatel a správce", editor: "Tým platformy" };

function formatNumber(value: number | undefined) {
  return typeof value === "number" ? value.toLocaleString("cs-CZ") : "—";
}

const Index = () => {
  const { user, isEditor } = useAuth();
  const { visitorCount, registeredCount } = usePresence();
  const { settings } = useSiteSettings();
  const { discord } = useFeaturedDiscord();
  const ed = useInlineEditor();
  const [customBlocks, setCustomBlocks] = useState<Block[]>([]);
  const [stats, setStats] = useState<PlatformStats | null>(null);
  const [team, setTeam] = useState<TeamMember[]>([]);
  const [release, setRelease] = useState<Release | null>(null);

  useEffect(() => {
    fetchPageBySlug("home", isEditor).then((page) => {
      if (!page) return;
      const blocks = isEditor && page.draft_blocks?.length ? page.draft_blocks : page.published_blocks;
      setCustomBlocks(blocks ?? []);
    });
  }, [isEditor]);

  useEffect(() => {
    let alive = true;
    const load = async () => {
      const { data } = await supabase.rpc("get_platform_stats");
      if (alive && data) setStats(data as unknown as PlatformStats);
    };
    void load();
    const timer = setInterval(load, 60_000);
    supabase.rpc("get_public_team").then(({ data }) => { if (alive && data) setTeam(data as TeamMember[]); });
    fetch("https://api.github.com/repos/Sokolcz97-rgb/Voxar.app/releases/latest", { headers: { Accept: "application/vnd.github+json" } })
      .then((response) => (response.ok ? response.json() : null))
      .then((data) => { if (alive && data?.tag_name) setRelease({ tag: data.tag_name, publishedAt: data.published_at }); })
      .catch(() => {});
    return () => { alive = false; clearInterval(timer); };
  }, []);

  const telemetry = useMemo(() => [
    { label: "Členů platformy", value: formatNumber(stats?.members), icon: Users },
    { label: "Online právě teď", value: formatNumber(registeredCount), icon: Activity, live: true },
    { label: "Aktivní za 7 dní", value: formatNumber(stats?.active_7d), icon: Sparkles },
    { label: "Komunit ve Voxar.app", value: formatNumber(stats?.communities), icon: MessageCircle },
    { label: "Discord serverů s botem", value: formatNumber(stats?.bot_servers), icon: Bot },
    { label: "Živých streamů", value: formatNumber(stats?.live_streams), icon: Radio },
  ], [stats, registeredCount]);

  const editingThis = ed.active && ed.slug === "home";
  const blocksToShow = editingThis ? ed.blocks : customBlocks;
  const siteName = settings.site_name || "StudioVoxario";
  const updatedAt = stats?.generated_at ? new Date(stats.generated_at).toLocaleTimeString("cs-CZ", { hour: "2-digit", minute: "2-digit" }) : null;

  return (
    <InlineEditorFrame>
      <SEO
        title={`${siteName} — herní platforma: komunita, aplikace, prohlížeč a hry`}
        description="Česká herní platforma na jednom účtu: komunita Voxar.app, VoxarioBrowser, ochrana VoxarioProtect, fórum, live streamy a hra Ashes of Eryon."
        jsonLd={{
          "@context": "https://schema.org",
          "@type": "WebSite",
          name: siteName,
          url: typeof window !== "undefined" ? window.location.origin : "",
          potentialAction: {
            "@type": "SearchAction",
            target: `${typeof window !== "undefined" ? window.location.origin : ""}/forum?q={search_term_string}`,
            "query-input": "required name=search_term_string",
          },
        }}
      />
      <div className="min-h-screen relative overflow-x-clip">
        <Navbar />
        <main>
          <AnnouncementBar />

          {/* HERO */}
          <section className="container relative pt-12 sm:pt-16 lg:pt-20 pb-16">
            <div className="grid items-center gap-12 lg:grid-cols-[1.02fr_1fr]">
              <div className="holo-rise">
                <span className="holo-kicker"><span className="dot" />Platforma online · živá data</span>
                <h1 className="mt-6 text-4xl font-bold leading-[1.05] sm:text-5xl xl:text-[64px]">
                  Jedna platforma.
                  <br />
                  <span className="holo-title">Celý tvůj herní svět.</span>
                </h1>
                <p className="mt-6 max-w-xl text-base leading-relaxed text-muted-foreground sm:text-lg">
                  Komunita, hlasový chat, vlastní prohlížeč, ochrana počítače a hry. Všechno propojené jedním účtem StudioVoxario –
                  česky, bezpečně a bez zbytečného hluku.
                </p>
                <div className="mt-8 flex flex-col gap-3 sm:flex-row sm:flex-wrap">
                  {user ? (
                    <Link to="/app" className="holo-btn-primary inline-flex h-12 items-center justify-center gap-2 rounded-xl px-6 text-base">
                      Otevřít Voxar.app <ArrowRight className="h-4 w-4" />
                    </Link>
                  ) : (
                    <Link to="/auth" className="holo-btn-primary inline-flex h-12 items-center justify-center gap-2 rounded-xl px-6 text-base">
                      Vytvořit účet zdarma <ArrowRight className="h-4 w-4" />
                    </Link>
                  )}
                  <Link to="/desktop" className="web-btn inline-flex h-12 items-center justify-center gap-2 px-6">
                    <Download className="h-4 w-4" /> Stáhnout StudioVoxario Connect
                  </Link>
                  {discord && (
                    <a href={discord.invite_url} target="_blank" rel="noreferrer" className="web-btn inline-flex h-12 items-center justify-center gap-2 px-6">
                      <MessageCircle className="h-4 w-4" /> {discord.name}
                    </a>
                  )}
                </div>
                <ul className="mt-8 flex flex-wrap gap-x-6 gap-y-2 text-sm text-muted-foreground">
                  <li className="flex items-center gap-2"><ShieldCheck className="h-4 w-4 text-primary" /> Jeden účet pro web, aplikace i hry</li>
                  <li className="flex items-center gap-2"><FileCheck2 className="h-4 w-4 text-primary" /> Ověřené instalátory</li>
                  <li className="flex items-center gap-2"><LifeBuoy className="h-4 w-4 text-primary" /> Česká podpora</li>
                </ul>
              </div>

              <div className="relative holo-rise" style={{ animationDelay: "120ms" }}>
                <div className="holo-orbit" aria-hidden="true" />
                <div className="holo-device holo-tilt">
                  <img src="/web/shot-community.webp" alt="Ukázka komunity ve Voxar.app" loading="eager" />
                </div>
                <div className="holo-float holo-float-a">
                  <span className="holo-float-icon"><Activity className="h-4 w-4" /></span>
                  <div><strong>{formatNumber(registeredCount)}</strong><small>online právě teď</small></div>
                </div>
                <div className="holo-float holo-float-b">
                  <span className="holo-float-icon violet"><Users className="h-4 w-4" /></span>
                  <div><strong>{formatNumber(stats?.members)}</strong><small>členů platformy</small></div>
                </div>
              </div>
            </div>
          </section>

          {/* ŽIVÁ ČÍSLA */}
          <section className="container pb-20" aria-labelledby="telemetry-title">
            <div className="holo-panel p-5 sm:p-6">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <h2 id="telemetry-title" className="text-sm font-semibold uppercase tracking-[0.22em] text-primary">Živě z platformy</h2>
                <span className="text-xs text-muted-foreground">
                  Skutečná čísla z databáze{updatedAt ? ` · aktualizováno ${updatedAt}` : ""} · návštěvníci teď: {formatNumber(visitorCount)}
                </span>
              </div>
              <div className="mt-5 grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
                {telemetry.map((item) => (
                  <div key={item.label} className="holo-metric">
                    <item.icon className="h-4 w-4 text-primary" />
                    <strong>{item.value}</strong>
                    <span>{item.label}</span>
                    {item.live && <i className="live" aria-hidden="true" />}
                  </div>
                ))}
              </div>
            </div>
          </section>

          {/* EKOSYSTÉM */}
          <section className="container pb-20" aria-labelledby="ecosystem-title">
            <div className="mx-auto max-w-3xl text-center">
              <span className="holo-kicker">Ekosystém StudioVoxario</span>
              <h2 id="ecosystem-title" className="mt-5 text-3xl font-bold sm:text-4xl">
                Víc než obchod s hrami. <span className="holo-title">Místo, kde se hraje spolu.</span>
              </h2>
              <p className="mt-4 text-muted-foreground">
                Steam ti hry prodá. My tě s lidmi propojíme – komunita, nástroje a hry v jednom ekosystému, který spolu mluví.
              </p>
            </div>

            <div className="mt-10 grid gap-5 lg:grid-cols-3">
              {products.map((product) => (
                <Link key={product.name} to={product.to} className="holo-panel is-interactive holo-sheen group overflow-hidden p-0">
                  <div className="relative aspect-[16/9] overflow-hidden rounded-t-[13px]">
                    <img src={product.image} alt={`Ukázka ${product.name}`} loading="lazy" className="h-full w-full object-cover object-top transition-transform duration-700 group-hover:scale-[1.04]" />
                    <div className="absolute inset-0 bg-gradient-to-t from-[#03101b] via-transparent to-transparent" />
                    {product.status && (
                      <span className="absolute right-3 top-3 rounded-full border border-amber-400/50 bg-black/60 px-3 py-1 text-xs font-semibold text-amber-300">
                        {product.status}
                      </span>
                    )}
                  </div>
                  <div className="p-6">
                    <div className="flex items-center gap-3">
                      <span className="holo-mega-icon"><product.icon className="h-[18px] w-[18px]" /></span>
                      <div>
                        <div className="text-[11px] font-semibold uppercase tracking-[0.2em] text-primary">{product.tag}</div>
                        <h3 className="text-xl font-bold">{product.name}</h3>
                      </div>
                    </div>
                    <p className="mt-4 text-sm leading-relaxed text-muted-foreground">{product.desc}</p>
                    <span className="mt-5 inline-flex items-center gap-1.5 text-sm font-semibold text-primary">
                      Prozkoumat <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-1" />
                    </span>
                  </div>
                </Link>
              ))}
            </div>

            <div className="mt-5 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              {services.map((service) => (
                <Link key={service.name} to={service.to} className="holo-panel is-interactive holo-sheen group flex gap-4 p-5">
                  <span className="holo-mega-icon"><service.icon className="h-[18px] w-[18px]" /></span>
                  <div>
                    <h3 className="text-base font-semibold">{service.name}</h3>
                    <p className="mt-1 text-sm leading-relaxed text-muted-foreground">{service.desc}</p>
                  </div>
                </Link>
              ))}
            </div>
          </section>

          {/* DŮVĚRA */}
          <section className="container pb-20" aria-labelledby="trust-title">
            <div className="grid gap-10 lg:grid-cols-[0.9fr_1.4fr] lg:items-start">
              <div className="lg:sticky lg:top-28">
                <span className="holo-kicker">Bezpečnost a transparentnost</span>
                <h2 id="trust-title" className="mt-5 text-3xl font-bold sm:text-4xl">
                  Postaveno na <span className="holo-title">důvěře</span>.
                </h2>
                <p className="mt-4 text-muted-foreground">
                  Nepotřebuješ věřit slibům. Ukazujeme skutečná čísla, zveřejňujeme historii změn a ke každé aplikaci přidáváme
                  kontrolní součet, abys věděl, že instaluješ přesně to, co jsme vydali.
                </p>
                <div className="holo-panel mt-6 p-5">
                  <div className="text-xs font-semibold uppercase tracking-[0.2em] text-primary">Aktuální vydání aplikací</div>
                  <div className="mt-3 flex items-end justify-between gap-4">
                    <div>
                      <div className="font-display text-3xl font-bold">{release?.tag ?? "—"}</div>
                      <div className="text-xs text-muted-foreground">
                        {release ? `vydáno ${new Date(release.publishedAt).toLocaleString("cs-CZ")}` : "Načítám…"}
                      </div>
                    </div>
                    <Link to="/verze" className="web-btn inline-flex h-10 items-center gap-2 px-4 text-sm">
                      <History className="h-4 w-4" /> Historie verzí
                    </Link>
                  </div>
                </div>
              </div>
              <div className="grid gap-4 sm:grid-cols-2">
                {trust.map((item) => {
                  const body = (
                    <>
                      <span className="holo-mega-icon"><item.icon className="h-[18px] w-[18px]" /></span>
                      <h3 className="mt-4 text-lg font-semibold">{item.title}</h3>
                      <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{item.desc}</p>
                    </>
                  );
                  return item.to ? (
                    <Link key={item.title} to={item.to} className="holo-panel is-interactive holo-sheen block p-6">{body}</Link>
                  ) : (
                    <div key={item.title} className="holo-panel p-6">{body}</div>
                  );
                })}
              </div>
            </div>
          </section>

          {/* LIDÉ ZA PROJEKTEM */}
          <section className="container pb-20" aria-labelledby="team-title">
            <div className="mx-auto max-w-3xl text-center">
              <span className="holo-kicker">Lidé za projektem</span>
              <h2 id="team-title" className="mt-5 text-3xl font-bold sm:text-4xl">Žádná anonymní korporace.</h2>
              <p className="mt-4 text-muted-foreground">
                {siteName} tvoří skuteční lidé z české herní komunity. Napiš nám kdykoli – odpovídá tým, ne robot.
              </p>
            </div>
            <div className="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              {team.map((member) => (
                <div key={`${member.display_name}-${member.role}`} className="holo-panel holo-sheen flex flex-col items-center p-6 text-center">
                  <div className="rounded-full p-[3px] bg-gradient-to-br from-cyan-300 to-violet-500 shadow-[0_0_24px_-6px_rgba(41,226,247,.8)]">
                    <UserAvatar url={member.avatar_url ?? ""} name={member.display_name ?? ""} className="h-20 w-20 border-2 border-[#03101b]" />
                  </div>
                  <h3 className="mt-4 text-lg font-semibold">{member.display_name}</h3>
                  <span className="mt-1 text-xs font-semibold uppercase tracking-[0.18em] text-primary">{roleLabel[member.role] ?? member.role}</span>
                </div>
              ))}
              <div className="holo-panel flex flex-col justify-between p-6">
                <div>
                  <span className="holo-mega-icon"><LifeBuoy className="h-[18px] w-[18px]" /></span>
                  <h3 className="mt-4 text-lg font-semibold">Potřebuješ pomoc?</h3>
                  <p className="mt-2 text-sm text-muted-foreground">
                    {settings.contact_full_name ? `Provozovatel: ${settings.contact_full_name}${settings.contact_ico ? `, IČO ${settings.contact_ico}` : ""}.` : "Podpora odpovídá přes tickety."}
                  </p>
                </div>
                <Link to="/tickets" className="web-btn mt-5 inline-flex h-10 items-center justify-center gap-2 px-4 text-sm">
                  Napsat podpoře <ArrowRight className="h-4 w-4" />
                </Link>
              </div>
            </div>
          </section>

          <TopPlayersPreview />

          {/* VÝZVA */}
          <section className="container pb-8 pt-4">
            <div className="holo-panel holo-cta relative overflow-hidden px-6 py-12 text-center sm:px-12">
              <h2 className="text-3xl font-bold sm:text-4xl">Připoj se do <span className="holo-title">{siteName}</span></h2>
              <p className="mx-auto mt-4 max-w-2xl text-muted-foreground">
                Založ si účet za pár vteřin, stáhni Voxar.app nebo VoxarioBrowser a buď u toho, až se otevře svět Ashes of Eryon.
              </p>
              <div className="mt-8 flex flex-col justify-center gap-3 sm:flex-row">
                <Link to={user ? "/app" : "/auth"} className="holo-btn-primary inline-flex h-12 items-center justify-center gap-2 rounded-xl px-7 text-base">
                  {user ? "Otevřít Voxar.app" : "Začít zdarma"} <ArrowRight className="h-4 w-4" />
                </Link>
                <Link to="/novinky" className="web-btn inline-flex h-12 items-center justify-center gap-2 px-6">
                  <Newspaper className="h-4 w-4" /> Co je nového
                </Link>
              </div>
            </div>
          </section>

          {(blocksToShow.length > 0 || editingThis) && (
            <section className="container max-w-4xl pb-16">
              <EditableBlocks blocks={blocksToShow} editable={editingThis} />
            </section>
          )}
        </main>
        <EditPageButton slug="home" />
      </div>
    </InlineEditorFrame>
  );
};

export default Index;
