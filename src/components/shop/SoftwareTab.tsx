import { useCallback, useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Progress } from "@/components/ui/progress";
import { Switch } from "@/components/ui/switch";
import { Check, Download, HardDrive, KeyRound, Loader2, MonitorPlay, RefreshCw, Sparkles } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import type { ShopItem } from "@/hooks/useShop";
import { downloadShopFile, formatBytes, formatRemaining } from "@/lib/shopFiles";

export type Period = "month" | "year";
/** Jednorázová licence nebo Upgrade pass (prodloužení aktualizací). */
export type LicensePlan = "license" | "pass_month" | "pass_year";

/** Zvolený tarif při nákupu předplatného / licence (nebo zaplacení připravené platby za obnovení). */
export type BuyPlan = { period: Period | LicensePlan; autoRenew: boolean; renewalId?: string | null; amount?: number | null };

type MyLicense = { item_id: string; purchased_at: string; updates_until: string; updates_active: boolean; can_download: boolean };

export const isLicensePlan = (p: string | null | undefined): p is LicensePlan =>
  p === "license" || p === "pass_month" || p === "pass_year";

export const licensePrice = (item: ShopItem, plan: LicensePlan) =>
  plan === "license" ? item.price_czk : plan === "pass_year" ? item.pass_year_czk ?? 0 : item.pass_month_czk ?? 0;

const fmtDate = (d: string | Date) => new Date(d).toLocaleDateString("cs-CZ", { day: "numeric", month: "numeric", year: "numeric" });

type MyDownload = {
  item_id: string;
  expires_at: string;
  active: boolean;
  period: Period | null;
  auto_renew: boolean;
  pending_purchase: string | null;
  pending_amount: number | null;
  pending_period: Period | null;
  activated_at: string | null;
  refundable_until: string | null;
};

export const planPrice = (item: ShopItem, period: Period) =>
  period === "year" && item.price_year_czk ? item.price_year_czk : item.price_czk;

/** Data pro platební dialog u předplatného nebo licence. */
/** Software, který se instaluje přes StudioVoxario Connect (katalog Connectu) – web nenabízí jeho instalátor. */
const CONNECT_PRODUCTS = new Set(["voxario-studio-engine"]);
const viaConnect = (item: ShopItem) => !!item.product_key && CONNECT_PRODUCTS.has(item.product_key);

function ConnectInstall({ item }: { item: ShopItem }) {
  return (
    <div className="space-y-2">
      <Button className="w-full" asChild>
        <a href={`studiovoxario://library/${item.product_key}`}>
          <Download className="h-4 w-4 mr-2" /> Instalovat ve StudioVoxario Connect
        </a>
      </Button>
      <p className="text-xs text-muted-foreground text-center">
        Instalace a aktualizace probíhají v aplikaci StudioVoxario Connect (licence se ověří u účtu).{" "}
        <a href="/desktop" className="text-primary hover:underline">Stáhnout Connect</a>
      </p>
    </div>
  );
}

export function subscriptionCheckout(item: ShopItem, plan: BuyPlan) {
  if (isLicensePlan(plan.period)) {
    const p = plan.period;
    const label = p === "license" ? "licence" : p === "pass_year" ? "Upgrade pass (rok)" : "Upgrade pass (měsíc)";
    return {
      title: `${item.title} – ${label}`,
      amount: licensePrice(item, p),
      note: `${item.title} ${label}`,
      kind: "software" as const,
      itemId: item.id,
      cosmeticId: null,
      period: p,
      autoRenew: false,
      renewalId: null,
    };
  }
  const label = plan.period === "year" ? "roční" : "měsíční";
  return {
    title: plan.renewalId ? `${item.title} – obnovení (${label})` : `${item.title} – ${label} předplatné`,
    amount: plan.amount ?? planPrice(item, plan.period),
    note: `${item.title} ${label}`,
    kind: "software" as const,
    itemId: item.id,
    cosmeticId: null,
    period: plan.period,
    autoRenew: plan.autoRenew,
    renewalId: plan.renewalId ?? null,
  };
}

/** Předplatné: měsíční nebo roční tarif, automatické obnovení a stažení přiloženého souboru. */
export function SoftwareTab({
  items,
  onBuy,
  focus,
}: {
  items: ShopItem[];
  onBuy: (item: ShopItem, plan: BuyPlan) => void;
  /** Odkaz z aplikace: ?licence=<klíč> nebo ?pass=<klíč> – otevře rovnou nákup. */
  focus?: { key: string; mode: "licence" | "pass"; period?: "month" | "year" } | null;
}) {
  const { user } = useAuth();
  const [mine, setMine] = useState<Record<string, MyDownload>>({});
  const [licenses, setLicenses] = useState<Record<string, MyLicense>>({});
  const [licLoaded, setLicLoaded] = useState(false);
  const focusDone = useRef(false);
  const [progress, setProgress] = useState<Record<string, number>>({});
  const [choice, setChoice] = useState<Record<string, Period>>({});
  const [renew, setRenew] = useState<Record<string, boolean>>({});
  const [toggling, setToggling] = useState<string | null>(null);
  const [refundAsk, setRefundAsk] = useState<string | null>(null);
  const [refundReason, setRefundReason] = useState("");
  const [refundBusy, setRefundBusy] = useState(false);
  const [, setTick] = useState(0);

  const load = useCallback(async () => {
    if (!user) {
      setMine({});
      return;
    }
    const [{ data }, lic] = await Promise.all([supabase.rpc("shop_my_downloads"), supabase.rpc("shop_my_licenses")]);
    const map: Record<string, MyDownload> = {};
    for (const d of (data ?? []) as MyDownload[]) map[d.item_id] = d;
    setMine(map);
    const lmap: Record<string, MyLicense> = {};
    for (const l of (lic.data ?? []) as MyLicense[]) lmap[l.item_id] = l;
    setLicenses(lmap);
    setLicLoaded(true);
  }, [user]);

  // odkaz z aplikace (engine): otevřít nákup licence / Upgrade passu
  useEffect(() => {
    if (!focus || focusDone.current || !licLoaded) return;
    const item = items.find((i) => i.sale_mode === "license" && (i.product_key === focus.key || i.id === focus.key));
    if (!item) return;
    focusDone.current = true;
    document.getElementById(`sw-${item.id}`)?.scrollIntoView({ behavior: "smooth", block: "center" });
    const owned = !!licenses[item.id];
    if (!owned) {
      onBuy(item, { period: "license", autoRenew: false });
      return;
    }
    const wantYear = focus.period !== "month" && !!item.pass_year_czk;
    const plan: LicensePlan = wantYear || !item.pass_month_czk ? "pass_year" : "pass_month";
    if (licensePrice(item, plan) > 0) onBuy(item, { period: plan, autoRenew: false });
  }, [focus, items, licenses, licLoaded, onBuy]);

  useEffect(() => {
    void load();
    const t = window.setInterval(() => setTick((x) => x + 1), 15_000);
    return () => window.clearInterval(t);
  }, [load]);

  const download = async (item: ShopItem) => {
    setProgress((p) => ({ ...p, [item.id]: 0 }));
    try {
      await downloadShopFile(item, (k) => setProgress((p) => ({ ...p, [item.id]: k })));
      void supabase.rpc("shop_log_download", { p_item: item.id });
      toast.success("Stahování dokončeno.");
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Stažení se nezdařilo.");
      void load();
    } finally {
      setProgress((p) => {
        const next = { ...p };
        delete next[item.id];
        return next;
      });
    }
  };

  const setAutoRenew = async (item: ShopItem, on: boolean, period: Period) => {
    setToggling(item.id);
    const { error } = await supabase.rpc("shop_set_auto_renew", { p_item: item.id, p_on: on, p_period: period });
    setToggling(null);
    if (error) {
      toast.error("Nastavení se nepodařilo uložit.");
      return;
    }
    toast.success(on ? "Automatické obnovení zapnuto." : "Automatické obnovení vypnuto.");
    void load();
  };

  const requestRefund = async (item: ShopItem) => {
    setRefundBusy(true);
    const { error } = await supabase.rpc("shop_request_refund", { p_item: item.id, p_reason: refundReason.trim() || null });
    setRefundBusy(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    setRefundAsk(null);
    setRefundReason("");
    toast.success("Žádost přijata. Přístup byl ukončen a peníze ti vrátíme nejpozději do 14 dnů.");
    void load();
  };

  if (items.length === 0) return <p className="text-muted-foreground">Zatím tu není žádné předplatné.</p>;

  return (
    <div className="grid sm:grid-cols-2 gap-5">
      {items.map((item) => {
        if (item.sale_mode === "license") {
          return (
            <LicenseCard
              key={item.id}
              item={item}
              license={licenses[item.id]}
              signedIn={!!user}
              progress={progress[item.id]}
              busy={item.id in progress}
              onDownload={() => void download(item)}
              onBuy={(plan) => onBuy(item, { period: plan, autoRenew: false })}
            />
          );
        }
        const own = mine[item.id];
        const active = own?.active && new Date(own.expires_at).getTime() > Date.now();
        const busy = item.id in progress;
        const hasYear = !!item.price_year_czk;
        const period: Period = hasYear ? choice[item.id] ?? own?.period ?? "month" : "month";
        const autoRenew = renew[item.id] ?? own?.auto_renew ?? true;
        const yearSaving = hasYear ? Math.max(0, Math.round(100 - (item.price_year_czk! / (item.price_czk * 12)) * 100)) : 0;
        return (
          <Card key={item.id} id={`sw-${item.id}`} className="glass border-border p-6 flex flex-col">
            <div className="flex items-start justify-between gap-3">
              <div>
                <h3 className="font-display font-bold text-lg">{item.title}</h3>
                {item.file_version && <p className="text-xs text-muted-foreground">verze {item.file_version}</p>}
                {item.description && <p className="text-sm text-muted-foreground mt-1">{item.description}</p>}
              </div>
              <Badge variant="secondary">od {item.price_czk} Kč / měs.</Badge>
            </div>

            <div className={`mt-4 grid gap-2 ${hasYear ? "grid-cols-2" : "grid-cols-1"}`}>
              {(hasYear ? (["month", "year"] as Period[]) : (["month"] as Period[])).map((p) => (
                <button
                  key={p}
                  type="button"
                  onClick={() => setChoice((c) => ({ ...c, [item.id]: p }))}
                  className={`border p-3 text-left transition-colors ${
                    period === p ? "border-primary bg-primary/10" : "border-border hover:border-primary/50"
                  }`}
                >
                  <span className="block text-xs uppercase tracking-wide text-muted-foreground">
                    {p === "year" ? "Roční" : "Měsíční"}
                  </span>
                  <span className="block font-bold text-lg">
                    {planPrice(item, p)} Kč
                    <span className="text-xs font-normal text-muted-foreground"> / {p === "year" ? "rok" : "měsíc"}</span>
                  </span>
                  {p === "year" && yearSaving > 0 && (
                    <span className="block text-xs text-primary">ušetříš {yearSaving} %</span>
                  )}
                </button>
              ))}
            </div>

            <div className="mt-3 flex flex-wrap gap-x-5 gap-y-1 text-sm text-muted-foreground">
              {item.file_size ? <span className="flex items-center gap-1.5"><HardDrive className="h-4 w-4" /> {formatBytes(item.file_size)}</span> : null}
            </div>
            {item.features?.length > 0 && (
              <ul className="mt-3 space-y-1.5 text-sm">
                {item.features.map((f, i) => (
                  <li key={i} className="flex gap-2">
                    <Check className="h-4 w-4 text-primary shrink-0 mt-0.5" />
                    <span>{f}</span>
                  </li>
                ))}
              </ul>
            )}

            <div className="mt-auto pt-6 space-y-2">
              {/voxario studio/i.test(item.title) && (
                <Button asChild variant="outline" className="w-full">
                  <Link to="/studio/demo">
                    <MonitorPlay className="h-4 w-4 mr-2" /> Vyzkoušet živé demo v prohlížeči
                  </Link>
                </Button>
              )}
              {own?.pending_purchase && (
                <div className="border border-primary/40 bg-primary/5 p-3 space-y-2">
                  <p className="text-sm">
                    Připravená platba za obnovení: <b>{own.pending_amount} Kč</b> ({own.pending_period === "year" ? "rok" : "měsíc"})
                  </p>
                  <Button
                    className="w-full"
                    onClick={() =>
                      onBuy(item, {
                        period: own.pending_period ?? "month",
                        autoRenew: true,
                        renewalId: own.pending_purchase,
                        amount: own.pending_amount,
                      })
                    }
                  >
                    <RefreshCw className="h-4 w-4 mr-2" /> Zaplatit obnovení
                  </Button>
                </div>
              )}

              {active && viaConnect(item) ? (
                <ConnectInstall item={item} />
              ) : active ? (
                <>
                  <Button className="w-full" disabled={busy || !item.file_parts?.length} onClick={() => download(item)}>
                    {busy ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <Download className="h-4 w-4 mr-2" />}
                    {busy ? `Stahuji… ${Math.round((progress[item.id] ?? 0) * 100)} %` : `Stáhnout ${item.file_name ?? ""}`}
                  </Button>
                  {busy && <Progress value={(progress[item.id] ?? 0) * 100} />}
                  <p className="text-xs text-muted-foreground text-center">
                    {own.period === "year" ? "Roční" : "Měsíční"} předplatné aktivní – vyprší za {formatRemaining(own.expires_at)} (
                    {new Date(own.expires_at).toLocaleString("cs-CZ")})
                  </p>
                  <label className="flex items-center justify-between gap-3 border border-border p-3 text-sm">
                    <span>
                      Automatické obnovení
                      <span className="block text-xs text-muted-foreground">
                        {own.auto_renew
                          ? `3 dny před koncem připravíme platbu za další ${period === "year" ? "rok" : "měsíc"}.`
                          : "Vypnuto – předplatné po skončení nebude pokračovat."}
                      </span>
                    </span>
                    <Switch
                      checked={own.auto_renew}
                      disabled={toggling === item.id}
                      onCheckedChange={(v) => void setAutoRenew(item, v, period)}
                    />
                  </label>
                  {own.auto_renew && hasYear && own.period !== period && (
                    <Button variant="ghost" size="sm" className="w-full" onClick={() => void setAutoRenew(item, true, period)}>
                      Další období obnovovat jako {period === "year" ? "roční" : "měsíční"}
                    </Button>
                  )}
                  {own.refundable_until && new Date(own.refundable_until).getTime() > Date.now() && (
                    <div className="border border-border p-3 space-y-2 text-sm">
                      <p className="text-xs text-muted-foreground">
                        Záruka vrácení peněz: požádat můžeš ještě{" "}
                        <b>{Math.max(1, Math.ceil((new Date(own.refundable_until).getTime() - Date.now()) / 60000))} min</b> (do{" "}
                        {new Date(own.refundable_until).toLocaleTimeString("cs-CZ", { hour: "2-digit", minute: "2-digit" })}), pokud jsi
                        program nezačal(a) používat.{" "}
                        <Link to="/obchodni-podminky#vraceni" className="text-primary underline">Podmínky</Link>
                      </p>
                      {refundAsk === item.id ? (
                        <>
                          <textarea
                            className="w-full rounded border border-border bg-background p-2 text-sm"
                            rows={2}
                            maxLength={1000}
                            placeholder="Důvod (nepovinné) – např. program nejde spustit"
                            value={refundReason}
                            onChange={(e) => setRefundReason(e.target.value)}
                          />
                          <p className="text-xs text-muted-foreground">
                            Po potvrzení se přístup okamžitě ukončí a program musíš odinstalovat. Záruku lze u předplatného využít jen jednou.
                          </p>
                          <div className="flex gap-2">
                            <Button variant="destructive" size="sm" disabled={refundBusy} onClick={() => void requestRefund(item)}>
                              {refundBusy && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}Potvrdit žádost o vrácení
                            </Button>
                            <Button variant="ghost" size="sm" onClick={() => setRefundAsk(null)}>Zpět</Button>
                          </div>
                        </>
                      ) : (
                        <Button variant="outline" size="sm" className="w-full" onClick={() => setRefundAsk(item.id)}>
                          Požádat o vrácení peněz
                        </Button>
                      )}
                    </div>
                  )}
                  {!own.pending_purchase && (
                    <Button variant="outline" className="w-full" onClick={() => onBuy(item, { period, autoRenew: own.auto_renew })}>
                      Prodloužit hned ({planPrice(item, period)} Kč)
                    </Button>
                  )}
                </>
              ) : (
                <>
                  <label className="flex items-center justify-between gap-3 border border-border p-3 text-sm">
                    <span>
                      Automaticky obnovovat
                      <span className="block text-xs text-muted-foreground">Před koncem ti připravíme platbu a upozorníme tě.</span>
                    </span>
                    <Switch checked={autoRenew} onCheckedChange={(v) => setRenew((r) => ({ ...r, [item.id]: v }))} />
                  </label>
                  {!own?.pending_purchase && (
                    <Button className="w-full" onClick={() => onBuy(item, { period, autoRenew })}>
                      Předplatit {period === "year" ? "na rok" : "na měsíc"} – {planPrice(item, period)} Kč
                    </Button>
                  )}
                  {own && !own.active && (
                    <p className="text-xs text-muted-foreground text-center">
                      Tvoje předplatné vypršelo {new Date(own.expires_at).toLocaleString("cs-CZ")}.
                    </p>
                  )}
                  <p className="text-xs text-muted-foreground text-center">
                    Po ověření platby se předplatné aktivuje a objeví se tu tlačítko ke stažení.
                  </p>
                </>
              )}
            </div>
          </Card>
        );
      })}
    </div>
  );
}

/** Jednorázová licence: koupě, stav aktualizací, Upgrade pass a stažení. */
function LicenseCard({
  item,
  license,
  signedIn,
  busy,
  progress,
  onDownload,
  onBuy,
}: {
  item: ShopItem;
  license?: MyLicense;
  signedIn: boolean;
  busy: boolean;
  progress?: number;
  onDownload: () => void;
  onBuy: (plan: LicensePlan) => void;
}) {
  const days = item.license_updates_days ?? 365;
  const updatesLabel = days % 365 === 0 ? `${days / 365} ${days / 365 === 1 ? "rok" : "roky"}` : days % 30 === 0 ? `${days / 30} měs.` : `${days} dní`;
  const active = license ? new Date(license.updates_until).getTime() > Date.now() : false;
  const base = license ? Math.max(Date.now(), new Date(license.updates_until).getTime()) : Date.now();
  const passes = (
    [
      ["pass_month", item.pass_month_czk, 30, "měsíc"],
      ["pass_year", item.pass_year_czk, 365, "rok"],
    ] as [LicensePlan, number | null | undefined, number, string][]
  ).filter(([, price]) => !!price);
  const yearSaving =
    item.pass_month_czk && item.pass_year_czk ? Math.max(0, Math.round(100 - (item.pass_year_czk / (item.pass_month_czk * 12)) * 100)) : 0;

  return (
    <Card id={`sw-${item.id}`} className="glass border-border p-6 flex flex-col">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h3 className="font-display font-bold text-lg">{item.title}</h3>
          {item.file_version && <p className="text-xs text-muted-foreground">verze {item.file_version}</p>}
          {item.description && <p className="text-sm text-muted-foreground mt-1">{item.description}</p>}
        </div>
        <Badge variant="secondary">{item.price_czk} Kč jednorázově</Badge>
      </div>

      <div className="mt-4 border border-border p-3 text-sm space-y-1">
        <p className="flex items-center gap-2 font-medium">
          <KeyRound className="h-4 w-4 text-primary" /> Trvalá licence + aktualizace na {updatesLabel}
        </p>
        <p className="text-xs text-muted-foreground">
          Program ti zůstane napořád. Nové verze dostáváš {updatesLabel} od koupě
          {passes.length > 0 && (
            <>
              , potom si je můžeš prodloužit <b>Upgrade passem</b> (
              {passes.map(([, price, , label], i) => (
                <span key={label}>
                  {i > 0 ? " / " : ""}
                  {price} Kč za {label}
                </span>
              ))}
              {yearSaving > 0 ? `, ročně ušetříš ${yearSaving} %` : ""})
            </>
          )}
          . Bez passu program funguje dál, jen bez nových verzí.
        </p>
      </div>

      <div className="mt-3 flex flex-wrap gap-x-5 gap-y-1 text-sm text-muted-foreground">
        {item.file_size ? <span className="flex items-center gap-1.5"><HardDrive className="h-4 w-4" /> {formatBytes(item.file_size)}</span> : null}
      </div>
      {item.features?.length > 0 && (
        <ul className="mt-3 space-y-1.5 text-sm">
          {item.features.map((f, i) => (
            <li key={i} className="flex gap-2">
              <Check className="h-4 w-4 text-primary shrink-0 mt-0.5" />
              <span>{f}</span>
            </li>
          ))}
        </ul>
      )}

      <div className="mt-auto pt-6 space-y-2">
        {/voxario studio/i.test(item.title) && (
          <Button asChild variant="outline" className="w-full">
            <Link to="/studio/demo">
              <MonitorPlay className="h-4 w-4 mr-2" /> Vyzkoušet živé demo v prohlížeči
            </Link>
          </Button>
        )}
        {license ? (
          <>
            <div className={`border p-3 text-sm ${active ? "border-primary/40 bg-primary/5" : "border-border"}`}>
              <p className="font-medium flex items-center gap-2">
                <Check className="h-4 w-4 text-primary" /> Licenci vlastníš (od {fmtDate(license.purchased_at)})
              </p>
              <p className="text-xs text-muted-foreground mt-1">
                {active
                  ? `Aktualizace aktivní do ${fmtDate(license.updates_until)} (ještě ${formatRemaining(license.updates_until)}).`
                  : `Aktualizace skončily ${fmtDate(license.updates_until)} – program funguje dál, nové verze odemkne Upgrade pass.`}
              </p>
            </div>
            {license.can_download && viaConnect(item) ? (
              <ConnectInstall item={item} />
            ) : license.can_download ? (
              <>
                <Button className="w-full" disabled={busy || !item.file_parts?.length} onClick={onDownload}>
                  {busy ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <Download className="h-4 w-4 mr-2" />}
                  {busy ? `Stahuji… ${Math.round((progress ?? 0) * 100)} %` : `Stáhnout ${item.file_name ?? ""}`}
                </Button>
                {busy && <Progress value={(progress ?? 0) * 100} />}
              </>
            ) : (
              <p className="text-xs text-muted-foreground text-center">
                Nejnovější verze {item.file_version ? `(${item.file_version}) ` : ""}vyšla po konci tvých aktualizací. Stáhneš ji po
                prodloužení Upgrade passem.
              </p>
            )}
            {passes.length > 0 && (
              <div className={`grid gap-2 ${passes.length > 1 ? "grid-cols-2" : "grid-cols-1"}`}>
                {passes.map(([plan, price, addDays, label]) => (
                  <Button key={plan} variant={plan === "pass_year" ? "default" : "outline"} className="h-auto py-2 flex-col" onClick={() => onBuy(plan)}>
                    <span className="flex items-center gap-1.5">
                      <Sparkles className="h-4 w-4" /> Upgrade pass – {label}
                    </span>
                    <span className="text-xs font-normal opacity-80">
                      {price} Kč · aktualizace do {fmtDate(new Date(base + addDays * 86_400_000))}
                    </span>
                  </Button>
                ))}
              </div>
            )}
          </>
        ) : (
          <>
            <Button className="w-full" onClick={() => onBuy("license")}>
              <KeyRound className="h-4 w-4 mr-2" /> Koupit licenci – {item.price_czk} Kč
            </Button>
            <p className="text-xs text-muted-foreground text-center">
              {signedIn
                ? "Po zaplacení se licence aktivuje a objeví se tu tlačítko ke stažení."
                : "Pro nákup se přihlas – licence se váže k tvému účtu StudioVoxario."}
            </p>
          </>
        )}
      </div>
    </Card>
  );
}
