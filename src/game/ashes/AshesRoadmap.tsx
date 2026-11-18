import { useCallback, useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import type { SupabaseClient } from "@supabase/supabase-js";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { L, setLang, useLang } from "./i18n";
import "./ashes.css";
import "./roadmap.css";

/**
 * Veřejná roadmapa Ashes of Eryon (studiovoxario.com/ashes, /hra/roadmap).
 * Obsah je v tabulce `ashes_roadmap`: správce ji upravuje přímo na stránce
 * a změny se všem otevřeným stránkám projeví hned (Supabase Realtime).
 * Pole MILESTONES níže je jen záloha, když databáze není dostupná.
 */

type Status = "now" | "next" | "planned" | "done";
type Milestone = {
  /** Přesný začátek (ISO) – u akce s odpočtem. */
  at?: string;
  when: { cs: string; en: string };
  title: { cs: string; en: string };
  act?: string;
  status: Status;
  text: { cs: string; en: string };
  items: { cs: string; en: string }[];
};

/** První testování: sobota 24. 10. 2026 v 17:00 (letní čas, UTC+2). */
const FIRST_TEST = "2026-10-24T17:00:00+02:00";

const MILESTONES: Milestone[] = [
  {
    at: FIRST_TEST,
    when: { cs: "Sobota 24. 10. 2026 · 17:00", en: "Saturday 24 Oct 2026 · 5 PM CEST" },
    title: { cs: "První testování", en: "First playtest" },
    act: "I",
    status: "now",
    text: {
      cs: "Uzavřený test 1. aktu „Poslední štít“. Otevřený svět pobřeží Kalidry, obě strany války a první příběhové úkoly.",
      en: "Closed test of Act I “The Last Shield”. The open world of Kalidra's coast, both sides of the war and the first story quests.",
    },
    items: [
      { cs: "Přihláška přes ticket na studiovoxario.com", en: "Sign up with a ticket on studiovoxario.com" },
      { cs: "Obránci Kalidry i Legie Rudého slunce", en: "Defenders of Kalidra and the Legion of the Red Sun" },
      { cs: "16 postav s rozhovory, 15 úkolů, aréna a válka o hradby", en: "16 characters to talk to, 15 quests, the arena and the war for the walls" },
      { cs: "Hra v prohlížeči i přes launcher pro Windows", en: "Play in the browser or through the Windows launcher" },
    ],
  },
  {
    when: { cs: "Listopad 2026", en: "November 2026" },
    title: { cs: "Opravy a otevřená alfa", en: "Fixes and open alpha" },
    act: "I",
    status: "next",
    text: {
      cs: "Opravíme vše, co najdete při testu, a otevřeme brány Kalidry všem přihlášeným hráčům.",
      en: "We fix everything you find during the test and open the gates of Kalidra to every signed-in player.",
    },
    items: [
      { cs: "Úpravy podle zpětné vazby testerů", en: "Changes based on tester feedback" },
      { cs: "Lepší modely postav a zvířat", en: "Better character and animal models" },
      { cs: "Hra otevřená všem s účtem StudioVoxario", en: "Open to everyone with a StudioVoxario account" },
    ],
  },
  {
    when: { cs: "Prosinec 2026", en: "December 2026" },
    title: { cs: "Oheň Kalidry", en: "Fire of Kalidra" },
    act: "II",
    status: "planned",
    text: {
      cs: "Druhý akt ságy. Ohně na horách, obležené město a nové části mapy za hradbami.",
      en: "The second act of the saga. Fires on the mountains, a besieged city and new parts of the map beyond the walls.",
    },
    items: [
      { cs: "Nové území a příběhové úkoly", en: "New territory and story quests" },
      { cs: "Píseň „Oheň Kalidry“ v celé kapitole", en: "The song “Fire of Kalidra” throughout the chapter" },
    ],
  },
  {
    when: { cs: "Začátek roku 2027", en: "Early 2027" },
    title: { cs: "Pochod bronzu", en: "March of Bronze" },
    act: "III",
    status: "planned",
    text: {
      cs: "Třetí akt. Vojska vyrážejí z Kalidry a hráči se poprvé spojí do družin.",
      en: "Act III. Armies march out of Kalidra and players band together for the first time.",
    },
    items: [
      { cs: "Družiny a společné výpravy", en: "Warbands and group expeditions" },
      { cs: "Bitvy více hráčů najednou", en: "Battles with several players at once" },
    ],
  },
  {
    when: { cs: "Jaro 2027", en: "Spring 2027" },
    title: { cs: "Moře krve", en: "Sea of Blood" },
    act: "IV",
    status: "planned",
    text: { cs: "Čtvrtý akt. Válka se přenese na moře k černým lodím Legie.", en: "Act IV. The war moves to the sea and the Legion's black ships." },
    items: [{ cs: "Bitvy u pobřeží a na lodích", en: "Battles on the coast and aboard ships" }],
  },
  {
    when: { cs: "Léto 2027", en: "Summer 2027" },
    title: { cs: "Koruna popela", en: "Crown of Ash" },
    act: "V",
    status: "planned",
    text: { cs: "Pátý akt. Kdo vládne popelu, vládne Kalidře.", en: "Act V. Whoever rules the ashes rules Kalidra." },
    items: [{ cs: "Rozhodnutí, která změní svět pro všechny hráče", en: "Decisions that change the world for every player" }],
  },
  {
    when: { cs: "Podzim 2027", en: "Autumn 2027" },
    title: { cs: "Poslední pochod", en: "The Last March" },
    act: "VI",
    status: "planned",
    text: { cs: "Finále ságy Eryona a Azkara.", en: "The finale of the saga of Eryon and Azkar." },
    items: [{ cs: "Závěrečná bitva obou stran", en: "The final battle of both sides" }],
  },
];

type Row = {
  id: string;
  sort: number;
  starts_at: string | null;
  when_cs: string;
  when_en: string;
  title_cs: string;
  title_en: string;
  act: string | null;
  status: Status;
  text_cs: string;
  text_en: string;
  items: { cs: string; en: string }[];
};

const db = supabase as unknown as SupabaseClient;

const FALLBACK: Row[] = MILESTONES.map((m, i) => ({
  id: `fallback-${i}`,
  sort: (i + 1) * 10,
  starts_at: m.at ?? null,
  when_cs: m.when.cs,
  when_en: m.when.en,
  title_cs: m.title.cs,
  title_en: m.title.en,
  act: m.act ?? null,
  status: m.status,
  text_cs: m.text.cs,
  text_en: m.text.en,
  items: m.items,
}));

function useRoadmap() {
  const [rows, setRows] = useState<Row[]>(FALLBACK);
  const load = useCallback(async () => {
    const { data, error } = await db.from("ashes_roadmap").select("*").order("sort", { ascending: true });
    if (!error && Array.isArray(data) && data.length) setRows(data as Row[]);
  }, []);
  useEffect(() => {
    void load();
    const channel = db
      .channel("ashes-roadmap")
      .on("postgres_changes", { event: "*", schema: "public", table: "ashes_roadmap" }, () => void load())
      .subscribe();
    return () => {
      void db.removeChannel(channel);
    };
  }, [load]);
  return { rows, reload: load };
}

function useCountdown(iso: string) {
  const target = new Date(iso).getTime();
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const t = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(t);
  }, []);
  const left = Math.max(0, target - now);
  return {
    done: left === 0,
    d: Math.floor(left / 86_400_000),
    h: Math.floor(left / 3_600_000) % 24,
    m: Math.floor(left / 60_000) % 60,
    s: Math.floor(left / 1000) % 60,
  };
}

/** Odpočet k nejbližšímu termínu z roadmapy (použito i na bráně /hra). */
export function RoadmapCountdown() {
  const lang = useLang();
  const { rows } = useRoadmap();
  const headline = useMemo(() => rows.find((r) => r.starts_at && r.status !== "done") ?? null, [rows]);
  const cd = useCountdown(headline?.starts_at ?? FIRST_TEST);
  if (!headline) return null;
  const date = new Date(headline.starts_at!).toLocaleString(lang === "en" ? "en-GB" : "cs-CZ", { weekday: "long", day: "numeric", month: "long", hour: "2-digit", minute: "2-digit", timeZone: "Europe/Prague" });
  return (
    <div className="rm-countdown ash-frame">
      <div>
        <div className="ash-kicker">{lang === "en" ? headline.title_en || headline.title_cs : headline.title_cs}</div>
        <b className="rm-date">{date}</b>
      </div>
      {cd.done ? (
        <div className="rm-live">{L("Právě probíhá!", "Happening now!")}</div>
      ) : (
        <div className="rm-clock" aria-label={L("Odpočet", "Countdown")}>
          {[
            [cd.d, L("dní", "days")],
            [cd.h, L("hod", "hrs")],
            [cd.m, L("min", "min")],
            [cd.s, L("s", "sec")],
          ].map(([v, label]) => (
            <span key={label as string}><b>{String(v).padStart(2, "0")}</b><small>{label}</small></span>
          ))}
        </div>
      )}
    </div>
  );
}

type AccessRow = { user_id: string; email: string; name: string | null; note: string | null; created_at: string };
type Rpc = { rpc: (fn: string, args?: Record<string, unknown>) => PromiseLike<{ data: unknown; error: { message: string } | null }> };
const rpc = supabase as unknown as Rpc;

/** Správce: kdo smí hrát před otevřením (kromě adminů a editorů). */
function AccessManager() {
  const [list, setList] = useState<AccessRow[] | null>(null);
  const [who, setWho] = useState("");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const run = useCallback(async (fn: string, args?: Record<string, unknown>, ok?: string) => {
    setBusy(true);
    const { data, error } = await rpc.rpc(fn, args);
    setBusy(false);
    if (error) {
      toast.error(error.message.replace(/^.*?ERROR:\s*/i, ""));
      return false;
    }
    setList((data as AccessRow[]) ?? []);
    if (ok) toast.success(ok);
    return true;
  }, []);
  useEffect(() => {
    void run("ashes_admin_access_list");
  }, [run]);
  return (
    <section className="rm-access ash-frame">
      <div className="ash-kicker">{L("Přístup do hry", "Game access")}</div>
      <p className="ashes-prose">{L("Dokud hra není otevřená všem, hrát mohou jen administrátoři, editoři a lidé z tohoto seznamu.", "Until the game opens to everyone, only admins, editors and people on this list can play.")}</p>
      <form
        className="rm-access-form"
        onSubmit={async (e) => {
          e.preventDefault();
          if (await run("ashes_admin_access_grant", { p_who: who.trim(), p_note: note.trim() || null }, L("Přístup povolen.", "Access granted."))) {
            setWho("");
            setNote("");
          }
        }}
      >
        <input className="ash-input" value={who} onChange={(e) => setWho(e.target.value)} placeholder={L("E-mail nebo přezdívka", "E-mail or nickname")} required />
        <input className="ash-input" value={note} onChange={(e) => setNote(e.target.value)} placeholder={L("Poznámka (např. ticket #12)", "Note (e.g. ticket #12)")} />
        <button className="ash-btn small" disabled={busy || who.trim().length < 2}>{L("Povolit", "Grant")}</button>
      </form>
      {list === null ? (
        <p className="ashes-prose">{L("Načítám…", "Loading…")}</p>
      ) : list.length === 0 ? (
        <p className="ashes-prose">{L("Zatím nikdo navíc.", "Nobody extra yet.")}</p>
      ) : (
        <ul className="rm-access-list">
          {list.map((a) => (
            <li key={a.user_id}>
              <span>
                <b>{a.name || a.email}</b>
                <small>{a.email}{a.note ? ` · ${a.note}` : ""}</small>
              </span>
              <button className="ash-btn ghost small" disabled={busy} onClick={() => void run("ashes_admin_access_revoke", { p_user: a.user_id }, L("Přístup odebrán.", "Access removed."))}>
                {L("Odebrat", "Remove")}
              </button>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

export default function AshesRoadmap() {
  const lang = useLang();
  const { isAdmin } = useAuth();
  const { rows, reload } = useRoadmap();
  const [editing, setEditing] = useState(false);
  const [access, setAccess] = useState(false);
  const tl = (r: Row, key: "when" | "title" | "text") => (lang === "en" ? r[`${key}_en`] || r[`${key}_cs`] : r[`${key}_cs`]);
  const headline = useMemo(() => rows.find((r) => r.starts_at && r.status !== "done") ?? null, [rows]);
  const cd = useCountdown(headline?.starts_at ?? FIRST_TEST);
  const statusLabel: Record<Status, string> = {
    now: L("Už brzy", "Coming up"),
    next: L("Další krok", "Next step"),
    planned: L("Plánováno", "Planned"),
    done: L("Hotovo", "Done"),
  };
  const headlineDate = headline?.starts_at
    ? new Date(headline.starts_at).toLocaleString(lang === "en" ? "en-GB" : "cs-CZ", { weekday: "long", day: "numeric", month: "long", hour: "2-digit", minute: "2-digit", timeZone: "Europe/Prague" })
    : "";

  return (
    <div className="ashes-root rm-root">
      <div className="rm-bg" aria-hidden />
      <header className="rm-top">
        <Link to="/ashes" className="rm-logo"><img src="/game/eryon/wordmark.webp" alt="Ashes of Eryon" /></Link>
        <div className="rm-actions">
          {isAdmin && (
            <button className={`ash-btn small ${access ? "" : "ghost"}`} onClick={() => setAccess(!access)}>
              {L("Přístup do hry", "Game access")}
            </button>
          )}
          {isAdmin && (
            <button className={`ash-btn small ${editing ? "" : "ghost"}`} onClick={() => setEditing(!editing)}>
              {editing ? L("Hotovo", "Done") : L("Upravit roadmapu", "Edit roadmap")}
            </button>
          )}
          <button className="ash-icon-btn lang" onClick={() => setLang(lang === "cs" ? "en" : "cs")}>{lang === "cs" ? "EN" : "CZ"}</button>
          <Link to="/desktop" className="ash-btn ghost small">{L("Stáhnout Connect", "Get Connect")}</Link>
          <Link to="/desktop" className="ash-btn small">{L("Hrát přes Connect", "Play via Connect")}</Link>
        </div>
      </header>

      <main className="rm-main">
        <section className="rm-hero">
          <div className="ash-kicker">{L("Roadmapa · sága o šesti aktech", "Roadmap · a saga in six acts")}</div>
          <h1 className="ash-title">{L("Cesta Kalidry", "The Road of Kalidra")}</h1>
          <p className="ashes-prose">
            {L(
              "Co a kdy v Ashes of Eryon čekat – od prvního testování až po finále ságy. Termíny vzdálenějších aktů jsou orientační a podle vývoje se mohou posunout.",
              "What to expect in Ashes of Eryon and when – from the first playtest to the finale of the saga. Dates of later acts are estimates and may shift as development goes on.",
            )}
          </p>

          {headline && (
            <div className="rm-countdown ash-frame">
              <div>
                <div className="ash-kicker">{tl(headline, "title")}</div>
                <b className="rm-date">{headlineDate}</b>
              </div>
              {cd.done ? (
                <div className="rm-live">{L("Právě probíhá!", "Happening now!")}</div>
              ) : (
                <div className="rm-clock" aria-label={L("Odpočet", "Countdown")}>
                  {[
                    [cd.d, L("dní", "days")],
                    [cd.h, L("hod", "hrs")],
                    [cd.m, L("min", "min")],
                    [cd.s, L("s", "sec")],
                  ].map(([v, label]) => (
                    <span key={label as string}><b>{String(v).padStart(2, "0")}</b><small>{label}</small></span>
                  ))}
                </div>
              )}
            </div>
          )}
        </section>

        {isAdmin && access && <AccessManager />}

        <ol className="rm-line">
          {rows.map((m, i) => (
            <li key={m.id} className="rm-item" data-status={m.status}>
              <div className="rm-node">{m.act ? <span>{m.act}</span> : null}</div>
              {editing ? (
                <MilestoneEditor row={m} first={i === 0} last={i === rows.length - 1} prev={rows[i - 1]} next={rows[i + 1]} onChanged={reload} />
              ) : (
                <article className="rm-card ash-frame">
                  <div className="rm-meta">
                    <span className="rm-when">{tl(m, "when")}</span>
                    <span className="rm-badge">{statusLabel[m.status]}</span>
                  </div>
                  <h2 className="ash-title">
                    {m.act && <small>{L("Akt", "Act")} {m.act} · </small>}
                    {tl(m, "title")}
                  </h2>
                  <p className="ashes-prose">{tl(m, "text")}</p>
                  {m.items.length > 0 && (
                    <ul>
                      {m.items.map((it, j) => <li key={j}>{lang === "en" ? it.en || it.cs : it.cs}</li>)}
                    </ul>
                  )}
                </article>
              )}
            </li>
          ))}
        </ol>
        {editing && (
          <button className="ash-btn" onClick={() => void addMilestone(rows, reload)}>{L("+ Přidat milník", "+ Add milestone")}</button>
        )}

        <footer className="rm-foot">
          <p>{L("Chceš být u prvního testování? Vytvoř si ticket na studiovoxario.com.", "Want to join the first playtest? Create a ticket on studiovoxario.com.")}</p>
          <Link to="/" className="ash-btn ghost small">StudioVoxario</Link>
        </footer>
      </main>
    </div>
  );
}

async function addMilestone(rows: Row[], reload: () => Promise<void>) {
  const sort = (rows[rows.length - 1]?.sort ?? 0) + 10;
  const { error } = await db.from("ashes_roadmap").insert({ sort, when_cs: "Termín", when_en: "Date", title_cs: "Nový milník", title_en: "New milestone", status: "planned" });
  if (error) toast.error(error.message);
  else await reload();
}

const toLocalInput = (iso: string | null) => {
  if (!iso) return "";
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
};

/** Úprava jednoho milníku (jen správce). Uloží se do databáze a ostatním se hned obnoví. */
function MilestoneEditor({ row, first, last, prev, next, onChanged }: { row: Row; first: boolean; last: boolean; prev?: Row; next?: Row; onChanged: () => Promise<void> }) {
  const [draft, setDraft] = useState(row);
  const [itemsText, setItemsText] = useState(row.items.map((it) => `${it.cs} | ${it.en}`).join("\n"));
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    setDraft(row);
    setItemsText(row.items.map((it) => `${it.cs} | ${it.en}`).join("\n"));
  }, [row]);
  const set = <K extends keyof Row>(k: K, v: Row[K]) => setDraft((d) => ({ ...d, [k]: v }));
  const fallback = row.id.startsWith("fallback-");

  const save = async () => {
    setBusy(true);
    const items = itemsText.split("\n").map((l) => l.trim()).filter(Boolean).map((l) => {
      const [cs, en] = l.split("|").map((x) => x.trim());
      return { cs, en: en ?? "" };
    });
    const { error } = await db.from("ashes_roadmap").update({
      when_cs: draft.when_cs, when_en: draft.when_en, title_cs: draft.title_cs, title_en: draft.title_en,
      act: draft.act || null, status: draft.status, text_cs: draft.text_cs, text_en: draft.text_en,
      starts_at: draft.starts_at || null, items,
    }).eq("id", row.id);
    setBusy(false);
    if (error) toast.error(error.message);
    else {
      toast.success("Uloženo – změna je vidět všem.");
      await onChanged();
    }
  };
  const remove = async () => {
    if (!window.confirm(`Smazat milník „${row.title_cs}“?`)) return;
    const { error } = await db.from("ashes_roadmap").delete().eq("id", row.id);
    if (error) toast.error(error.message);
    else await onChanged();
  };
  const swap = async (other?: Row) => {
    if (!other) return;
    await db.from("ashes_roadmap").update({ sort: other.sort }).eq("id", row.id);
    await db.from("ashes_roadmap").update({ sort: row.sort }).eq("id", other.id);
    await onChanged();
  };

  return (
    <article className="rm-card rm-edit ash-frame">
      {fallback && <p className="text-sm text-[#ffb4a0]">Roadmapa se nenačetla z databáze – úpravy teď nejdou uložit.</p>}
      <div className="rm-grid">
        <label>Termín (CZ)<input className="ash-input" value={draft.when_cs} onChange={(e) => set("when_cs", e.target.value)} /></label>
        <label>Termín (EN)<input className="ash-input" value={draft.when_en} onChange={(e) => set("when_en", e.target.value)} /></label>
        <label>Název (CZ)<input className="ash-input" value={draft.title_cs} onChange={(e) => set("title_cs", e.target.value)} /></label>
        <label>Název (EN)<input className="ash-input" value={draft.title_en} onChange={(e) => set("title_en", e.target.value)} /></label>
        <label>Akt<input className="ash-input" value={draft.act ?? ""} placeholder="I, II…" onChange={(e) => set("act", e.target.value)} /></label>
        <label>Stav
          <select className="ash-input" value={draft.status} onChange={(e) => set("status", e.target.value as Status)}>
            <option value="now">Už brzy (zvýrazněno)</option>
            <option value="next">Další krok</option>
            <option value="planned">Plánováno</option>
            <option value="done">Hotovo</option>
          </select>
        </label>
        <label className="wide">Přesný začátek pro odpočet (nepovinné)
          <input className="ash-input" type="datetime-local" value={toLocalInput(draft.starts_at)} onChange={(e) => set("starts_at", e.target.value ? new Date(e.target.value).toISOString() : null)} />
        </label>
        <label className="wide">Popis (CZ)<textarea className="ash-textarea" value={draft.text_cs} onChange={(e) => set("text_cs", e.target.value)} /></label>
        <label className="wide">Popis (EN)<textarea className="ash-textarea" value={draft.text_en} onChange={(e) => set("text_en", e.target.value)} /></label>
        <label className="wide">Body – jeden na řádek, „česky | anglicky“<textarea className="ash-textarea" rows={4} value={itemsText} onChange={(e) => setItemsText(e.target.value)} /></label>
      </div>
      <div className="rm-edit-actions">
        <button className="ash-btn small" disabled={busy || fallback} onClick={() => void save()}>Uložit</button>
        <button className="ash-btn ghost small" disabled={first || fallback} onClick={() => void swap(prev)}>↑</button>
        <button className="ash-btn ghost small" disabled={last || fallback} onClick={() => void swap(next)}>↓</button>
        <button className="ash-btn ghost small rm-danger" disabled={fallback} onClick={() => void remove()}>Smazat</button>
      </div>
    </article>
  );
}
