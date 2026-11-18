import { useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import { Link } from "react-router-dom";
import { Navbar } from "@/components/Navbar";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { CalendarDays, Search, Sparkles, Wrench, ShieldCheck, Rocket, Newspaper } from "lucide-react";
import { PageHero } from "@/components/PageHero";
import { SEO } from "@/components/SEO";
import { CHANGELOG, type ChangelogEntry, type ChangelogType } from "@/data/changelog";
import { useConnectChangelog } from "@/hooks/useConnectChangelog";

const TYPE_META: Record<ChangelogType, { icon: typeof Sparkles; cs: string; en: string; className: string }> = {
  feature: { icon: Rocket, cs: "Novinka", en: "Feature", className: "bg-primary/15 text-primary border-primary/40" },
  improvement: { icon: Sparkles, cs: "Vylepšení", en: "Improvement", className: "bg-accent/15 text-accent border-accent/40" },
  fix: { icon: Wrench, cs: "Oprava", en: "Fix", className: "bg-muted text-muted-foreground border-border" },
  security: { icon: ShieldCheck, cs: "Bezpečnost", en: "Security", className: "bg-destructive/15 text-destructive border-destructive/40" },
};

const Novinky = () => {
  const { i18n } = useTranslation();
  const cs = i18n.language === "cs";
  const [search, setSearch] = useState("");
  const [type, setType] = useState<"all" | ChangelogType>("all");

  const fmtDate = (iso: string) =>
    new Date(iso).toLocaleDateString(cs ? "cs-CZ" : "en-US", {
      day: "numeric", month: "long", year: "numeric",
    });

  // platforma (StudioVoxario Connect, živě z vydání) + dosavadní historie Voxar.app, od nejnovějšího
  const { data: connect = [] } = useConnectChangelog();
  const all = useMemo(() => [
    ...connect.map((e) => ({ ...e, product: "StudioVoxario Connect" })),
    ...CHANGELOG.map((e: ChangelogEntry) => ({ ...e, product: "Voxar.app" })),
  ].sort((a, b) => b.date.localeCompare(a.date)), [connect]);

  const entries = useMemo(() => {
    const q = search.trim().toLowerCase();
    return all.map((e) => {
      const changes = e.changes.filter((c) => {
        if (type !== "all" && c.type !== type) return false;
        if (!q) return true;
        const hay = `${e.product} ${e.version} ${e.title} ${e.titleEn ?? ""} ${c.text} ${c.textEn ?? ""}`.toLowerCase();
        return hay.includes(q);
      });
      return { ...e, changes };
    }).filter((e) => e.changes.length > 0);
  }, [search, type, all]);

  const totalChanges = all.reduce((n, e) => n + e.changes.length, 0);

  const title = cs ? "Novinky a changelog" : "News and changelog";
  const desc = cs
    ? "Skutečné poznámky ke každé verzi platformy StudioVoxario Connect a historie Voxar.app."
    : "Real release notes for every StudioVoxario Connect version and the Voxar.app history.";

  return (
    <div className="min-h-screen relative">
      <SEO
        title={title}
        description={desc}
        jsonLd={{
          "@context": "https://schema.org",
          "@type": "CollectionPage",
          name: title,
          description: desc,
          url: "https://studiovoxario.com/novinky",
        }}
      />
      <div className="fixed inset-0 -z-10 gradient-hero" />
      <div className="fixed inset-0 -z-10 neon-grid opacity-30" />
      <Navbar />
      <main className="container py-10 animate-fade-in max-w-4xl">
        <PageHero
          eyebrow={cs ? "Novinky" : "Changelog"}
          title={title}
          icon={Newspaper}
          description={
            <>
              {cs
                ? "Co se změnilo v aplikaci — každá úprava, oprava i bezpečnostní zásah."
                : "What changed in the app — every update, fix and security hardening."}
              <br />
              <span className="text-foreground/70">
                {cs
                  ? `${all.length} verzí · ${totalChanges} záznamů`
                  : `${all.length} versions · ${totalChanges} entries`}
              </span>
            </>
          }
        />

        <Link
          to="/verze"
          className="inline-flex items-center gap-2 mb-6 text-sm text-primary hover:text-primary/80 border border-primary/40 rounded-md px-3 py-2"
        >
          <CalendarDays className="h-4 w-4" />
          {cs ? "Historie verzí — co je nainstalované a kdy vyšlo" : "Version history — what is installed and when it shipped"}
        </Link>


        <Card className="glass border-border p-4 mb-6">
          <div className="grid md:grid-cols-2 gap-3">
            <div className="relative">
              <Search className="h-4 w-4 absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
              <Input
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder={cs ? "Hledat v changelogu…" : "Search the changelog…"}
                className="pl-9"
              />
            </div>
            <Select value={type} onValueChange={(v) => setType(v as typeof type)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">{cs ? "Všechny typy" : "All types"}</SelectItem>
                {(Object.keys(TYPE_META) as ChangelogType[]).map((k) => (
                  <SelectItem key={k} value={k}>{cs ? TYPE_META[k].cs : TYPE_META[k].en}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </Card>

        {entries.length === 0 ? (
          <Card className="glass border-border p-10 text-center">
            <p className="text-muted-foreground">
              {cs ? "Žádný záznam neodpovídá filtru." : "No entry matches the filter."}
            </p>
          </Card>
        ) : (
          <div className="space-y-6">
            {entries.map((e) => (
              <Card key={`${e.product}-${e.version}`} className="glass border-border p-5">
                <div className="flex flex-wrap items-baseline gap-3 mb-4">
                  <span className={`text-[11px] uppercase tracking-[0.18em] ${e.product === "Voxar.app" ? "text-muted-foreground" : "text-primary"}`}>{e.product}</span>
                  <h2 className="font-display font-black text-2xl text-glow">{e.version}</h2>
                  <span className="inline-flex items-center gap-1 text-xs text-muted-foreground">
                    <CalendarDays className="h-3 w-3" />
                    {fmtDate(e.date)}
                  </span>
                  <span className="text-sm text-foreground/80">
                    {cs ? e.title : e.titleEn ?? e.title}
                  </span>
                </div>
                <ul className="space-y-3">
                  {e.changes.map((c, i) => {
                    const meta = TYPE_META[c.type];
                    const Icon = meta.icon;
                    return (
                      <li key={i} className="flex items-start gap-3">
                        <Badge variant="outline" className={`shrink-0 gap-1 ${meta.className}`}>
                          <Icon className="h-3 w-3" />
                          {cs ? meta.cs : meta.en}
                        </Badge>
                        <span className="text-sm leading-relaxed">
                          {cs ? c.text : c.textEn ?? c.text}
                        </span>
                      </li>
                    );
                  })}
                </ul>
              </Card>
            ))}
          </div>
        )}
      </main>
    </div>
  );
};

export default Novinky;
