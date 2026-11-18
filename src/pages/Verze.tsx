import { useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import { Link } from "react-router-dom";
import { Navbar } from "@/components/Navbar";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { PageHero } from "@/components/PageHero";
import { SEO } from "@/components/SEO";
import { CHANGELOG, type ChangelogType } from "@/data/changelog";
import { useConnectChangelog } from "@/hooks/useConnectChangelog";
import { History, Rocket, Sparkles, Wrench, ShieldCheck, Monitor, Globe, CheckCircle2 } from "lucide-react";

const TYPE_META: Record<ChangelogType, { icon: typeof Sparkles; cs: string; en: string; className: string }> = {
  feature: { icon: Rocket, cs: "Novinka", en: "Feature", className: "bg-primary/15 text-primary border-primary/40" },
  improvement: { icon: Sparkles, cs: "Vylepšení", en: "Improvement", className: "bg-accent/15 text-accent border-accent/40" },
  fix: { icon: Wrench, cs: "Oprava", en: "Fix", className: "bg-muted text-muted-foreground border-border" },
  security: { icon: ShieldCheck, cs: "Bezpečnost", en: "Security", className: "bg-destructive/15 text-destructive border-destructive/40" },
};

type HistoryRow = { version: string; installedAt: string; channel?: string };
type Desktop = {
  getVersionHistory?: () => Promise<{ current: string; history: HistoryRow[] }>;
};

const norm = (v: string) => v.replace(/^v/i, "").split("-")[0];

const Verze = () => {
  const { i18n } = useTranslation();
  const cs = i18n.language === "cs";
  const [module, setModule] = useState<"connect" | "app" | "browser">("connect");
  const { data: connectLog = [], isLoading: connectLoading } = useConnectChangelog();
  const [installed, setInstalled] = useState<HistoryRow[]>([]);
  const [current, setCurrent] = useState<string | null>(null);

  useEffect(() => {
    const desktop: Desktop | undefined = (window as unknown as { studioVoxarioDesktop?: Desktop }).studioVoxarioDesktop;
    desktop?.getVersionHistory?.()
      .then((r) => {
        setInstalled(Array.isArray(r?.history) ? r.history : []);
        setCurrent(r?.current ?? null);
      })
      .catch(() => {});
  }, []);

  const installedMap = useMemo(() => {
    const map = new Map<string, HistoryRow>();
    installed.forEach((row) => map.set(norm(row.version), row));
    return map;
  }, [installed]);

  const fmt = (iso: string) =>
    new Date(iso).toLocaleDateString(cs ? "cs-CZ" : "en-US", { day: "numeric", month: "long", year: "numeric" });

  const title = cs ? "Historie verzí" : "Version history";
  const desc = cs
    ? "Přehled verzí Voxar.app a VoxarioBrowseru — kdy byly nainstalované a co každá aktualizace přináší."
    : "Voxar.app and VoxarioBrowser releases — when they were installed and what each update brings.";

  return (
    <div className="min-h-screen relative">
      <SEO title={title} description={desc} />
      <div className="fixed inset-0 -z-10 gradient-hero" />
      <div className="fixed inset-0 -z-10 neon-grid opacity-30" />
      <Navbar />
      <main className="container py-10 animate-fade-in max-w-4xl">
        <PageHero
          eyebrow={cs ? "Verze" : "Releases"}
          title={title}
          icon={History}
          description={
            <>
              {desc}
              {current && (
                <>
                  <br />
                  <span className="text-foreground/70">
                    {cs ? "Nainstalovaná verze" : "Installed version"}: <strong>v{current}</strong>
                  </span>
                </>
              )}
            </>
          }
        />

        <Link
          to="/novinky"
          className="inline-flex items-center gap-2 mt-6 text-sm text-primary hover:text-primary/80 border border-primary/40 rounded-md px-3 py-2"
        >
          <History className="h-4 w-4" />
          {cs ? "Zobrazit celý changelog" : "View the full changelog"}
        </Link>

        <div className="flex flex-wrap gap-2 my-6">
          <Button
            variant={module === "connect" ? "default" : "outline"}
            onClick={() => setModule("connect")}
            className="gap-2"
          >
            <Rocket className="w-4 h-4" /> StudioVoxario Connect
          </Button>
          <Button
            variant={module === "app" ? "default" : "outline"}
            onClick={() => setModule("app")}
            className="gap-2"
          >
            <Monitor className="w-4 h-4" /> Voxar.app
          </Button>
          <Button
            variant={module === "browser" ? "default" : "outline"}
            onClick={() => setModule("browser")}
            className="gap-2"
          >
            <Globe className="w-4 h-4" /> VoxarioBrowser
          </Button>
        </div>

        <p className="text-sm text-muted-foreground mb-4">
          {module === "connect"
            ? cs
              ? "Platforma StudioVoxario Connect – poznámky ke každé vydané verzi. Connect se aktualizuje sám."
              : "StudioVoxario Connect platform – notes for every released version. Connect updates itself."
            : module === "app"
            ? cs
              ? "Voxar.app se aktualizuje automaticky při spuštění i za běhu."
              : "Voxar.app updates automatically on launch and while running."
            : cs
              ? "VoxarioBrowser se distribuuje ve stejném balíčku a aktualizuje se spolu s aplikací."
              : "VoxarioBrowser ships in the same package and updates together with the app."}
        </p>

        <div className="space-y-5">
          {module === "connect" && connectLoading && <p className="text-sm text-muted-foreground">{cs ? "Načítám vydání…" : "Loading releases…"}</p>}
          {(module === "connect" ? connectLog : CHANGELOG).map((entry) => {
            const inst = module === "connect" ? undefined : installedMap.get(norm(entry.version));
            return (
              <Card key={entry.version} className="p-5 holo-panel">
                <div className="flex flex-wrap items-center gap-3 mb-3">
                  <Badge variant="outline" className="font-mono">v{entry.version}</Badge>
                  <span className="text-sm text-muted-foreground">{fmt(entry.date)}</span>
                  {inst && (
                    <Badge className="gap-1 bg-primary/15 text-primary border-primary/40">
                      <CheckCircle2 className="w-3 h-3" />
                      {cs ? "Nainstalováno" : "Installed"} {fmt(inst.installedAt)}
                    </Badge>
                  )}
                  {module !== "connect" && current && norm(current) === norm(entry.version) && (
                    <Badge variant="secondary">{cs ? "Aktuální" : "Current"}</Badge>
                  )}
                </div>
                <h2 className="text-lg font-display mb-3">{cs ? entry.title : entry.titleEn ?? entry.title}</h2>
                <ul className="space-y-2">
                  {entry.changes.map((c, i) => {
                    const meta = TYPE_META[c.type];
                    const Icon = meta.icon;
                    return (
                      <li key={i} className="flex gap-3 text-sm">
                        <Badge variant="outline" className={`${meta.className} gap-1 shrink-0 h-6`}>
                          <Icon className="w-3 h-3" />
                          {cs ? meta.cs : meta.en}
                        </Badge>
                        <span className="text-muted-foreground">{cs ? c.text : c.textEn ?? c.text}</span>
                      </li>
                    );
                  })}
                </ul>
              </Card>
            );
          })}
        </div>
      </main>
    </div>
  );
};

export default Verze;
