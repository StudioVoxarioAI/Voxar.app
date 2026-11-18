import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { toast } from "sonner";
import { BookOpen, Camera, Castle, Coins, Flame, LogOut, ScrollText, Settings, Shield, Sparkles, Trophy, User, Volume2, VolumeX } from "lucide-react";
import { useAuth } from "@/contexts/AuthContext";
import { supabase } from "@/integrations/supabase/client";
import { ashesApi, type CharacterList, type CharacterSummary } from "./api";
import { heroPortraitUrl } from "./three/meshyFigure";
import { RoadmapCountdown } from "./AshesRoadmap";
import { music } from "./audio";
import { OpenWorld, getCameraMode, type BattleEvent, type CameraMode, type EnemyInfo, type Interactable, type WorldFrame } from "./world/openWorld";
import { QUALITIES, QUALITY, assets, getQuality, qualityChosen, setQuality, setQualityByUser, type Quality } from "./world/assets";
import { NPCS, REGION_NAME, SPAWN, type NpcId, type RegionId } from "./world/map";
import { questDef, beaconsLit, npcMark } from "./world/quests";
import {
  ArenaPanel, BardPanel, ChroniclePanel, CreateCharacter, HeroPanel, SmithyPanel, TavernPanel, WallsPanel, actName, actOf, fmtNum,
} from "./ui/panels";
import { Dialogue, JournalPanel, SettingsPanel, type NpcOpens } from "./ui/worldPanels";
import { Minimap } from "./ui/Minimap";
import { FACTION, RARITY, type Appearance, type Faction, type FightResult, type Fighter, type GameState, type HeroClass, type PresenceHero } from "./types";
import { L, classLabel, getLang, setLang, tr, trItem, useLang } from "./i18n";
import { playSfx } from "./sfx";
import { UPSCALE, applyDisplayMode, exitGame, getDisplay, isDesktop, saveDisplay, type DisplaySettings } from "./display";
import "./ashes.css";

/** Použije grafická nastavení na svět (rozlišení, zvětšování, limit snímků). */
function applyGraphics(w: OpenWorld, d: DisplaySettings) {
  w.setResolution(d.resolution || null);
  w.setUpscale(UPSCALE[d.upscale] ?? 1, d.sharpen);
  w.setFpsCap(d.fpsCap);
}

type PanelId = NpcOpens | "postava" | "kronika" | "denik" | "nastaveni";

const NAV: { id: PanelId; cs: string; en: string; icon: typeof User }[] = [
  { id: "postava", cs: "Hrdina", en: "Hero", icon: User },
  { id: "denik", cs: "Deník", en: "Journal", icon: BookOpen },
  { id: "hradby", cs: "Válka", en: "War", icon: Castle },
  { id: "kronika", cs: "Kronika", en: "Chronicle", icon: ScrollText },
  { id: "nastaveni", cs: "Nastavení", en: "Settings", icon: Settings },
];

const ROMAN = ["I", "II", "III"];

type BattleState = { f1: Fighter; f2: Fighter; max1: number; max2: number; hp1: number; hp2: number; done: boolean };
type Pop = { id: number; x: number; y: number; text: string; kind: "hit" | "crit" | "miss" };
type ResultKind = "quest" | "boss" | "arena" | "world" | "wq";
type Result = Partial<FightResult> & { kind: ResultKind; won: boolean; questTitle?: string; questText?: string };
type Pos = { x: number; z: number; ry: number };

function useServerNow(serverIso?: string) {
  const offset = useRef(0);
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    if (serverIso) offset.current = new Date(serverIso).getTime() - Date.now();
  }, [serverIso]);
  useEffect(() => {
    const t = window.setInterval(() => setNow(Date.now() + offset.current), 1000);
    return () => window.clearInterval(t);
  }, []);
  return now;
}

const POS_KEY = (f: Faction) => `ashes.pos.${f}`;
function loadPos(f: Faction): Pos | null {
  try {
    const v = JSON.parse(localStorage.getItem(POS_KEY(f)) ?? "null");
    return v && typeof v.x === "number" && typeof v.z === "number" ? v : null;
  } catch {
    return null;
  }
}
function savePos(f: Faction, p: Pos) {
  try {
    localStorage.setItem(POS_KEY(f), JSON.stringify(p));
  } catch {
    /* bez úložiště */
  }
}

const nearKey = (n: Interactable | null) => (n ? `${n.kind}:${"id" in n ? n.id : ""}` : "");

export default function AshesGame() {
  const { user, loading: authLoading } = useAuth();
  const lang = useLang();
  const [state, setState] = useState<GameState | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [entered, setEntered] = useState(false);
  const [selectOpen, setSelectOpen] = useState(false);
  const [charList, setCharList] = useState<CharacterList | null>(null);
  const [panel, setPanel] = useState<PanelId | null>(null);
  const [talk, setTalk] = useState<NpcId | null>(null);
  const [busy, setBusy] = useState(false);
  const [battle, setBattle] = useState<BattleState | null>(null);
  const [pops, setPops] = useState<Pop[]>([]);
  const [result, setResult] = useState<Result | null>(null);
  const [others, setOthers] = useState<PresenceHero[]>([]);
  const [near, setNear] = useState<Interactable | null>(null);
  const [safe, setSafe] = useState(false);
  const [camMode, setCamMode] = useState<CameraMode>(getCameraMode());
  const [regionBanner, setRegionBanner] = useState<RegionId | null>(null);
  const [world, setWorld] = useState<OpenWorld | null>(null);
  const [worldGen, setWorldGen] = useState(0);
  const [slow, setSlow] = useState<null | { software: boolean }>(null);
  const [showFps, setShowFps] = useState(getDisplay().showFps);
  const [fps, setFps] = useState<number | undefined>(undefined);
  const [, forceMusic] = useState(0);
  const hostRef = useRef<HTMLDivElement>(null);
  const overlayRef = useRef<HTMLDivElement>(null);
  const enemyLayerRef = useRef<HTMLDivElement>(null);
  const worldRef = useRef<OpenWorld | null>(null);
  const popId = useRef(0);
  const stateRef = useRef<GameState | null>(null);
  const busyRef = useRef(false);
  const uiOpenRef = useRef(false);
  const talkRef = useRef<NpcId | null>(null);
  const panelRef = useRef<PanelId | null>(null);
  const positions = useRef<Record<string, Pos>>({});
  const myPos = useRef<Pos | null>(null);
  const channelRef = useRef<ReturnType<typeof supabase.channel> | null>(null);
  const othersRef = useRef<PresenceHero[]>([]);
  const uidRef = useRef<string | null>(null);
  const liveRef = useRef(false);
  const now = useServerNow(state?.now);

  const character = state?.character ?? null;
  const faction: Faction = (character?.faction ?? "kalidra") as Faction;
  stateRef.current = state;
  othersRef.current = others;
  uidRef.current = user?.id ?? null;
  busyRef.current = busy;
  uiOpenRef.current = !!(panel || talk || result || battle);
  talkRef.current = talk;
  panelRef.current = panel;

  // ------------------------------------------------------------ stav ze serveru
  const refresh = useCallback(async () => {
    try {
      const next = await ashesApi.state();
      setState(next);
      setLoadError(null);
    } catch (error) {
      setLoadError(error instanceof Error ? error.message : L("Svět se nepodařilo načíst.", "The world could not be loaded."));
    }
  }, []);

  useEffect(() => {
    if (authLoading || !user) return;
    void refresh();
    const t = window.setInterval(() => void refresh(), 45_000);
    return () => window.clearInterval(t);
  }, [authLoading, user, refresh]);

  useEffect(() => {
    const off = music.subscribe(() => forceMusic((n) => n + 1));
    return () => {
      off();
    };
  }, []);
  useEffect(() => () => music.stop(), []);

  const act = useCallback(async (fn: () => Promise<GameState>, success?: string) => {
    setBusy(true);
    try {
      const next = await fn();
      setState(next);
      if (success) toast.success(success);
      return next;
    } catch (error) {
      toast.error(error instanceof Error ? error.message : L("Akce se nepodařila.", "The action failed."));
      return null;
    } finally {
      setBusy(false);
    }
  }, []);

  // ------------------------------------------------------------ souboje (výpravy, boss, aréna, svět)
  const runFight = useCallback(async (kind: ResultKind, promise: () => Promise<FightResult>, encounterKey?: string) => {
    const w = worldRef.current;
    if (!w) return;
    setBusy(true);
    w.setInputEnabled(false);
    let res: FightResult;
    try {
      res = await promise();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : L("Souboj se nepodařil.", "The fight failed."));
      if (encounterKey) w.resolveEncounter(encounterKey, false);
      w.setInputEnabled(true);
      setBusy(false);
      return;
    }
    setPanel(null);
    setTalk(null);
    const onEvent = (e: BattleEvent) => {
      if (e.type === "start") {
        setBattle({ f1: e.f1, f2: e.f2, max1: e.hp1, max2: e.hp2, hp1: e.hp1, hp2: e.hp2, done: false });
      } else if (e.type === "round") {
        setBattle((b) => (b ? { ...b, hp1: e.hp1, hp2: e.hp2 } : b));
        const id = (popId.current += 1);
        const text = e.evaded ? L("Úhyb!", "Dodge!") : e.blocked ? L("Blok!", "Block!") : `${e.crit ? L("Kritický! ", "Critical! ") : ""}-${fmtNum(e.damage)}`;
        setPops((list) => [...list, { id, x: e.at.x, y: e.at.y, text, kind: e.evaded || e.blocked ? "miss" : e.crit ? "crit" : "hit" }]);
        window.setTimeout(() => setPops((list) => list.filter((p) => p.id !== id)), 1200);
        playSfx(e.evaded ? "evade" : e.blocked ? "block" : e.crit ? "crit" : "hit");
      } else {
        setBattle((b) => (b ? { ...b, done: true } : b));
      }
    };
    await w.playFight(res.fight, onEvent, res.ally ?? (res.eryon_ally ? "eryon" : null));
    if (encounterKey) w.resolveEncounter(encounterKey, res.won);
    setResult({ ...res, kind });
    playSfx(res.won ? ((res.levels ?? 0) > 0 ? "level" : "victory") : "defeat");
    setState(res.state);
    setBusy(false);
  }, []);

  const closeResult = () => {
    const leveled = (result?.levels ?? 0) > 0;
    const lostWorld = result?.kind === "world" && !result.won;
    setResult(null);
    setBattle(null);
    setPops([]);
    const w = worldRef.current;
    if (w) {
      w.setMode("explore");
      if (lostWorld) w.respawn();
      w.setInputEnabled(true);
    }
    if (leveled) toast.success(L("Nová úroveň! Tvé síly rostou.", "Level up! Your strength grows."));
  };

  // ------------------------------------------------------------ interakce ve světě
  const onInteract = useCallback(async (target: Interactable) => {
    const s = stateRef.current;
    const w = worldRef.current;
    if (!s?.character || !w || busyRef.current || uiOpenRef.current) return;
    const map = new Map((s.wquests ?? []).map((q) => [q.quest_id, q]));
    const f = (s.character.faction ?? "kalidra") as Faction;
    if (target.kind === "npc") {
      const def = NPCS.find((n) => n.id === target.id);
      if (!def) return;
      // rozhovorový úkol, který míří k tomuto NPC → splnit
      const talkQuest = (s.wquests ?? []).find((q) => q.state === "active" && questDef(q.quest_id)?.type === "talk" && questDef(q.quest_id)?.target === target.id);
      if (talkQuest) await act(() => ashesApi.wqEvent("talk", target.id));
      w.setInputEnabled(false);
      w.setMode("talk", { x: def.x, z: def.z });
      setTalk(target.id);
      return;
    }
    if (target.kind === "beacon") {
      const q = map.get(f === "legie" ? "l4" : "k4");
      if (q?.state === "active" && !q.targets.includes(target.id)) {
        const next = await act(() => ashesApi.wqEvent("beacon", target.id));
        const nq = next?.wquests?.find((x) => x.quest_id === q.quest_id);
        if (next) playSfx("fire");
        if (next) toast.success(f === "legie" ? `${L("Vatra uhasla", "The beacon is out")} (${nq?.progress ?? q.progress + 1}/3)` : `${L("Vatra hoří", "The beacon blazes")} (${nq?.progress ?? q.progress + 1}/3)`);
      } else {
        toast(f === "legie" ? L("Strážní vatra obránců. Oren chce, aby zhasla.", "A defenders' watchfire. Oren wants it out.") : L("Strážní vatra na kopci. Damon chce, aby hořely všechny.", "A watchfire on the hill. Damon wants them all burning."));
      }
      return;
    }
    if (target.kind === "memorial") {
      const q = map.get("k7");
      if (q?.state === "active") {
        const next = await act(() => ashesApi.wqEvent("visit", "memorial"));
        if (next) toast.success(L("Položil jsi květ k památníku padlých.", "You laid a flower at the memorial of the fallen."));
      } else {
        toast(L("Památník padlých. Kámen si pamatuje jejich jména.", "The memorial of the fallen. The stone remembers their names."));
      }
    }
  }, [act]);

  const onEncounter = useCallback((e: EnemyInfo) => {
    if (busyRef.current || uiOpenRef.current || !stateRef.current?.character) {
      worldRef.current?.resolveEncounter(e.key, false);
      return;
    }
    void runFight("world", () => ashesApi.worldFight(e.region, e.def.id), e.key);
  }, [runFight]);

  // ------------------------------------------------------------ 3D svět
  useEffect(() => {
    if (!state?.allowed || !hostRef.current || worldRef.current) return;
    let disposed = false;
    let w: OpenWorld | null = null;
    void assets.ready.then(() => {
      if (disposed || !hostRef.current) return;
      try {
        w = new OpenWorld(hostRef.current, faction, QUALITY[getQuality()]);
      } catch {
        setLoadError(L("Tvůj prohlížeč nepodporuje WebGL, bez kterého 3D svět nepoběží.", "Your browser does not support WebGL, which the 3D world needs."));
        return;
      }
      applyGraphics(w, getDisplay());
      // bez grafické karty (vypnutá hardwarová akcelerace) rovnou úsporná grafika
      if (w.gpuInfo().software && !qualityChosen() && getQuality() !== "potato") {
        setQuality("potato");
        const d = getDisplay();
        if (d.upscale === "off") saveDisplay({ ...d, upscale: "performance", fpsCap: 30 });
        const old = w;
        w = null;
        old.dispose();
        setWorldGen((n) => n + 1);
        return;
      }
      if (import.meta.env.DEV) (window as unknown as { __ashesWorld?: OpenWorld }).__ashesWorld = w;
      worldRef.current = w;
      setWorld(w);
    });
    return () => {
      disposed = true;
      if (w) {
        if (myPos.current) savePos(faction, myPos.current);
        w.dispose();
      }
      worldRef.current = null;
      setWorld(null);
    };
    // svět se staví jednou (nebo po změně kvality); strana se řeší přes populate
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state?.allowed, worldGen]);

  // počítadlo FPS (v nastavení a volitelně v rohu obrazovky)
  useEffect(() => {
    if (!world) return;
    const t = window.setInterval(() => setFps(world.fps), 1000);
    return () => window.clearInterval(t);
  }, [world]);

  // hra se seká: po chvíli nabídnout nižší grafiku, zapnutí akcelerace nebo launcher
  useEffect(() => {
    if (!world) return;
    let dismissed = false;
    try {
      dismissed = sessionStorage.getItem("ashes.slow.dismissed") === "1";
    } catch {
      /* bez úložiště */
    }
    if (dismissed) return;
    const software = world.gpuInfo().software;
    let bad = 0;
    const t = window.setInterval(() => {
      if (document.hidden) return;
      bad = world.struggling ? bad + 1 : 0;
      if (bad >= 3) {
        window.clearInterval(t);
        const q = getQuality();
        const i = QUALITIES.indexOf(q);
        // automatika: hráč si kvalitu nevybral → sama sníží o stupeň (a zapne zvětšování obrazu)
        if (!qualityChosen() && i > 0) {
          setQuality(QUALITIES[i - 1]);
          const d = getDisplay();
          if (d.upscale === "off") saveDisplay({ ...d, upscale: "balanced" });
          setWorldGen((n) => n + 1);
          return;
        }
        setSlow({ software });
      }
    }, 4000);
    return () => window.clearInterval(t);
  }, [world]);

  // napojení událostí
  useEffect(() => {
    if (!world) return;
    world.onInteract = (t) => void onInteract(t);
    world.onEncounter = onEncounter;
    world.onCameraMode = setCamMode;
    world.onRegion = (r) => {
      setRegionBanner(r);
      window.setTimeout(() => setRegionBanner((x) => (x === r ? null : x)), 3200);
    };
    let lastSave = 0;
    let lastSend = 0;
    world.onMove = (x, z, ry) => {
      myPos.current = { x, z, ry };
      const t = performance.now();
      if (t - lastSave > 1500 && stateRef.current?.character) {
        lastSave = t;
        savePos((stateRef.current.character.faction ?? "kalidra") as Faction, { x, z, ry });
      }
      if (t - lastSend > 250 && channelRef.current && liveRef.current) {
        lastSend = t;
        void channelRef.current.send({ type: "broadcast", event: "pos", payload: { x, z, ry, uid: uidRef.current } });
      }
    };
    let lastNear = "";
    let lastSafe = false;
    world.onFrame = (frame: WorldFrame) => {
      const k = nearKey(frame.near);
      if (k !== lastNear) {
        lastNear = k;
        setNear(frame.near);
      }
      if (frame.safe !== lastSafe) {
        lastSafe = frame.safe;
        setSafe(frame.safe);
      }
      const overlay = overlayRef.current;
      if (!overlay) return;
      overlay.querySelectorAll<HTMLElement>("[data-npc]").forEach((el) => {
        const p = frame.npcs[el.dataset.npc as string];
        el.style.display = p?.visible ? "" : "none";
        if (p) el.style.transform = `translate(${p.x}px, ${p.y}px) translate(-50%, -100%)`;
      });
      overlay.querySelectorAll<HTMLElement>("[data-other]").forEach((el) => {
        const p = frame.others[el.dataset.other as string];
        el.style.display = p?.visible ? "" : "none";
        if (p) el.style.transform = `translate(${p.x}px, ${p.y}px) translate(-50%, -100%)`;
      });
      const layer = enemyLayerRef.current;
      if (layer) {
        while (layer.children.length < frame.enemies.length) {
          const d = document.createElement("div");
          d.className = "ash-tag enemy";
          layer.appendChild(d);
        }
        Array.from(layer.children).forEach((node, i) => {
          const el = node as HTMLElement;
          const e = frame.enemies[i];
          if (!e || !e.p.visible) {
            el.style.display = "none";
            return;
          }
          el.style.display = "";
          const label = `${tr(e.name)} · ${e.level}`;
          if (el.textContent !== label) el.textContent = label;
          el.style.transform = `translate(${e.p.x}px, ${e.p.y}px) translate(-50%, -100%)`;
        });
      }
    };
    return () => {
      world.onInteract = null;
      world.onEncounter = null;
      world.onCameraMode = null;
      world.onRegion = null;
      world.onMove = null;
      world.onFrame = null;
    };
  }, [world, onInteract, onEncounter]);

  // obyvatelé a hráč
  const shieldOn = !!state?.items?.some((i) => i.equipped && i.slot === "stit");
  const hasCharacter = !!character;
  useEffect(() => {
    if (!world || !hasCharacter) return;
    world.populate(faction);
    const saved = loadPos(faction);
    const p = saved ?? { x: SPAWN[faction][0], z: SPAWN[faction][1], ry: 0 };
    world.teleport(p.x, p.z);
    myPos.current = p;
  }, [world, faction, hasCharacter]);

  useEffect(() => {
    if (!world || !character) return;
    world.setPlayer(
      character.class,
      character.appearance ?? {},
      character.is_eryon ? "eryon" : character.is_azkar ? "azkar" : null,
      shieldOn || character.class === "hoplit",
      character.faction === "legie",
    );
  }, [world, character?.class, character?.appearance, character?.is_eryon, character?.is_azkar, character?.faction, shieldOn, character]);

  useEffect(() => {
    if (!world || !character) return;
    world.setBeacons(beaconsLit(faction, state?.wquests));
  }, [world, faction, state?.wquests, character]);

  // režim kamery
  useEffect(() => {
    if (!world || battle) return;
    if (!character) {
      world.setMode("create");
      world.setInputEnabled(false);
      return;
    }
    if (talk) return;
    if (panel === "postava") world.setMode("portrait");
    else world.setMode("explore");
    world.setInputEnabled(!panel && !result);
  }, [world, panel, talk, character, battle, result]);

  // ------------------------------------------------------------ ostatní hráči (realtime)
  useEffect(() => {
    if (!character || !user) return;
    const channel = supabase.channel("ashes:world:all", { config: { private: true, presence: { key: user.id }, broadcast: { self: false } } });
    channelRef.current = channel;
    channel.on("presence", { event: "sync" }, () => {
      const raw = channel.presenceState<PresenceHero & Partial<Pos>>();
      const list: PresenceHero[] = [];
      for (const [key, metas] of Object.entries(raw)) {
        if (key === user.id) continue;
        const m = metas[0];
        if (!m || typeof m.name !== "string") continue;
        m.name = m.name.slice(0, 24);
        if (typeof m.x === "number" && !positions.current[key]) positions.current[key] = { x: m.x, z: m.z ?? 0, ry: m.ry ?? 0 };
        list.push({ ...m, key });
      }
      setOthers(list);
    });
    channel.on("broadcast", { event: "pos" }, ({ payload }) => {
      const p = payload as Pos & { uid?: string };
      if (!p?.uid || p.uid === user.id) return;
      // jen hráči přítomní v kanálu a rozumné souřadnice (ochrana proti podvrženým zprávám)
      if (!othersRef.current.some((o) => o.key === p.uid)) return;
      if (![p.x, p.z, p.ry].every((v) => typeof v === "number" && Number.isFinite(v)) || Math.abs(p.x) > 200 || Math.abs(p.z) > 200) return;
      positions.current[p.uid] = { x: p.x, z: p.z, ry: p.ry };
      worldRef.current?.setOthers(othersRef.current.map((o) => ({ ...o, ...positions.current[o.key] })));
    });
    channel.subscribe((status) => {
      liveRef.current = status === "SUBSCRIBED";
      if (status === "SUBSCRIBED") {
        const p = myPos.current;
        void channel.track({
          name: character.display_name,
          cls: character.class,
          level: character.level,
          appearance: character.appearance ?? {},
          eryon: character.is_eryon,
          azkar: character.is_azkar,
          faction: character.faction,
          uid: user.id,
          ...(p ?? {}),
        });
      }
    });
    return () => {
      channelRef.current = null;
      liveRef.current = false;
      void supabase.removeChannel(channel);
    };
  }, [character?.display_name, character?.level, character?.is_eryon, character?.is_azkar, character?.faction, character?.class, user, character]);

  useEffect(() => {
    world?.setOthers(others.map((o) => ({ ...o, ...positions.current[o.key] })));
  }, [others, world]);

  // hudba podle aktu
  useEffect(() => {
    if (!entered || !character) return;
    void music.loadAlbum().then(() => music.play(music.trackForChapter(character.chapter)));
  }, [entered, character?.chapter, character]);

  const enter = () => {
    setEntered(true);
    void music.loadAlbum().then(() => void music.play(music.trackForChapter(character?.chapter ?? 1)));
  };

  const onPreview = useCallback((cls: HeroClass, appearance: Appearance, f: Faction) => {
    const w = worldRef.current;
    if (!w) return;
    w.teleport(SPAWN[f][0], SPAWN[f][1]);
    w.setPlayer(cls, appearance, null, cls === "hoplit", f === "legie");
  }, []);

  /** Odhlášení: zpět na přihlašovací obrazovku hry (svět se uvolní). */
  const logout = useCallback(async () => {
    if (myPos.current && stateRef.current?.character) savePos((stateRef.current.character.faction ?? "kalidra") as Faction, myPos.current);
    music.stop();
    setPanel(null);
    setTalk(null);
    setResult(null);
    setBattle(null);
    setEntered(false);
    setState(null);
    await supabase.auth.signOut();
  }, []);

  // ------------------------------------------------------------ výběr postav
  const loadCharacters = useCallback(async () => {
    try {
      setCharList(await ashesApi.characters());
    } catch (error) {
      toast.error(error instanceof Error ? error.message : L("Postavy se nepodařilo načíst.", "Characters could not be loaded."));
    }
  }, []);
  const openSelect = useCallback(() => {
    if (myPos.current && stateRef.current?.character) savePos((stateRef.current.character.faction ?? "kalidra") as Faction, myPos.current);
    setPanel(null);
    setTalk(null);
    setEntered(false);
    setSelectOpen(true);
    void loadCharacters();
  }, [loadCharacters]);
  const playCharacter = async (c: CharacterSummary) => {
    if (c.id) {
      const next = await act(() => ashesApi.switchCharacter(c.id!), L(`Hraješ za postavu ${c.name}.`, `Now playing ${c.name}.`));
      if (!next) return;
    }
    setSelectOpen(false);
    enter();
  };
  const newCharacter = async () => {
    const next = await act(() => ashesApi.newCharacter());
    if (!next) return;
    setSelectOpen(false);
    setEntered(true);
    void loadCharacters();
  };
  const deleteCharacter = async (c: CharacterSummary) => {
    if (!c.id) return;
    if (!window.confirm(L(`Opravdu smazat postavu ${c.name}? Přijdeš o její úroveň, výbavu i úkoly.`, `Really delete ${c.name}? Their level, gear and quests will be lost.`))) return;
    setBusy(true);
    try {
      setCharList(await ashesApi.deleteCharacter(c.id));
      toast.success(L("Postava smazána.", "Character deleted."));
    } catch (error) {
      toast.error(error instanceof Error ? error.message : L("Akce se nepodařila.", "The action failed."));
    } finally {
      setBusy(false);
    }
  };
  /** Zpět z tvorby postavy: vrátit poslední uloženou postavu. */
  const backFromCreate = async () => {
    const last = charList?.others[0];
    if (!last?.id) return;
    const next = await act(() => ashesApi.switchCharacter(last.id!));
    if (!next) return;
    setEntered(false);
    setSelectOpen(true);
    void loadCharacters();
  };

  // uložený režim zobrazení (v aplikaci okno / celá obrazovka) při spuštění
  useEffect(() => {
    if (isDesktop()) void applyDisplayMode(getDisplay());
  }, []);

  // v prohlížeči: když hráč opustí celou obrazovku klávesou Esc, uložit režim okna
  useEffect(() => {
    if (isDesktop()) return;
    const fn = () => {
      if (!document.fullscreenElement && getDisplay().mode === "fullscreen") saveDisplay({ ...getDisplay(), mode: "windowed" });
    };
    document.addEventListener("fullscreenchange", fn);
    return () => document.removeEventListener("fullscreenchange", fn);
  }, []);

  // Esc zavře rozhovor nebo panel, jinak otevře nastavení
  useEffect(() => {
    const fn = (e: KeyboardEvent) => {
      if (e.key !== "Escape" || !stateRef.current?.character || busyRef.current) return;
      const tag = (e.target as HTMLElement | null)?.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA") return;
      if (talkRef.current) {
        setTalk(null);
        worldRef.current?.setMode("explore");
        worldRef.current?.setInputEnabled(true);
      } else if (panelRef.current) setPanel(null);
      else if (!uiOpenRef.current) setPanel("nastaveni");
    };
    window.addEventListener("keydown", fn);
    return () => window.removeEventListener("keydown", fn);
  }, []);

  const changeQuality = (q: Quality) => {
    setQualityByUser(q);
    setWorldGen((n) => n + 1);
  };

  // ------------------------------------------------------------ úkoly od NPC
  const acceptQuest = async (id: string) => {
    const def = questDef(id);
    await act(() => ashesApi.wqAccept(id), def ? `${L("Nový úkol", "New quest")}: ${def.title[getLang()]}` : undefined);
  };
  const turnInQuest = async (id: string) => {
    setBusy(true);
    try {
      const res = await ashesApi.wqTurnIn(id);
      setState(res.state);
      const def = questDef(id);
      setTalk(null);
      playSfx(res.levels > 0 ? "level" : "quest");
      setResult({ kind: "wq", won: true, xp: res.xp, gold: res.gold, levels: res.levels, item: res.item, questTitle: def?.title[getLang()], questText: def?.done[getLang()] });
    } catch (error) {
      toast.error(error instanceof Error ? error.message : L("Akce se nepodařila.", "The action failed."));
    } finally {
      setBusy(false);
    }
  };
  const closeTalk = () => {
    setTalk(null);
    const w = worldRef.current;
    if (w) {
      w.setMode("explore");
      w.setInputEnabled(true);
    }
  };

  const shoutFresh = useMemo(() => {
    const w = state?.world;
    if (!w) return null;
    const day = 1000 * 60 * 60 * 24;
    const list = [
      { hero: "Eryon", text: w.eryon_shout, at: w.eryon_shout_at ? new Date(w.eryon_shout_at).getTime() : 0, legion: false },
      { hero: "Azkar", text: w.azkar_shout, at: w.azkar_shout_at ? new Date(w.azkar_shout_at).getTime() : 0, legion: true },
    ].filter((x) => x.text && now - x.at < day);
    list.sort((a, b) => b.at - a.at);
    return list[0] ?? null;
  }, [state?.world, now]);

  const activeQuest = state?.quests?.find((q) => q.state === "active");
  const questReady = activeQuest?.ends_at ? new Date(activeQuest.ends_at).getTime() <= now : false;
  const readyCount = (state?.wquests ?? []).filter((q) => q.state === "ready").length;

  // ------------------------------------------------------------ obrazovky mimo hru
  const langToggle = (
    <button className="ash-icon-btn lang" onClick={() => setLang(lang === "cs" ? "en" : "cs")} aria-label={L("Jazyk", "Language")} title={L("Přepnout do angličtiny", "Switch to Czech")}>
      {lang === "cs" ? "EN" : "CZ"}
    </button>
  );

  if (authLoading || (user && !state && !loadError)) {
    return <div className="ashes-root"><div className="ash-loading">{L("Probouzím svět…", "Waking the world…")}</div></div>;
  }

  if (!user || (state && !state.allowed) || (loadError && !state)) {
    // brána: hrát mohou jen administrátoři, editoři a testeři s povolením (kontroluje server)
    const closed = !!user && !!state && !state.allowed;
    return (
      <div className="ashes-root">
        <div className="ash-title-screen">
          <div className="ash-title-inner ash-gate">
            <img src="/game/eryon/wordmark.webp" alt="Ashes of Eryon" />
            <div className="tag">{L("Uzavřené testování", "Closed playtest")}</div>
            <RoadmapCountdown />
            {!user ? (
              <LoginForm />
            ) : loadError && !state ? (
              <p className="ashes-prose">{loadError}</p>
            ) : closed ? (
              <>
                <p className="ashes-prose">
                  {L(
                    "Brány Kalidry jsou zatím zavřené. Hrát mohou jen testeři, kterým jsme dali povolení. Chceš se přidat? Napiš nám ticket a ozveme se.",
                    "The gates of Kalidra are still closed. Only testers we have invited can play. Want to join? Send us a ticket and we will get back to you.",
                  )}
                </p>
                <Link to="/tickets" className="ash-btn">{L("Požádat o přístup", "Request access")}</Link>
              </>
            ) : null}
            <Link to="/ashes" className="text-sm text-[var(--ash-gold)] underline">{L("Roadmapa – co a kdy čekat", "Roadmap – what to expect and when")}</Link>
            <div className="flex gap-2">
              {user && <button className="ash-btn ghost small" onClick={() => void logout()}>{L("Odhlásit se", "Sign out")}</button>}
              <button className="ash-btn ghost small" onClick={exitGame}>{isDesktop() ? L("Ukončit hru", "Quit game") : L("Zpět na StudioVoxario", "Back to StudioVoxario")}</button>
              {langToggle}
            </div>
          </div>
        </div>
      </div>
    );
  }

  if (!state) return null;
  const war = state.world;
  const legion = faction === "legie";
  const actNo = character ? actOf(character.chapter) : 1;
  const nearName = (() => {
    if (!near) return "";
    if (near.kind === "npc") {
      const n = NPCS.find((x) => x.id === near.id);
      return n ? `${L("Mluvit", "Talk")}: ${n.name[lang]}` : "";
    }
    if (near.kind === "beacon") return legion ? L("Uhasit vatru", "Put out the beacon") : L("Zapálit vatru", "Light the beacon");
    return L("Památník padlých", "Memorial of the Fallen");
  })();
  const inWorld = !!character && !battle && !result;

  return (
    <div className="ashes-root" data-lang={lang}>
      <div ref={hostRef} className="ashes-canvas" />
      <div className="ashes-vignette" />

      {/* popisky ve 3D scéně */}
      <div ref={overlayRef} className="ash-overlay" style={{ visibility: inWorld && !talk ? "visible" : "hidden" }}>
        {character && NPCS.filter((n) => n.faction === faction).map((n) => {
          const mark = npcMark(n.id, faction, state.wquests);
          return (
            <div key={n.id} data-npc={n.id} className={`ash-npc-tag ${n.hero ? "hero" : ""}`} style={{ display: "none" }}>
              {mark && <i className={`mark ${mark}`}>{mark === "offer" ? "!" : "?"}</i>}
              <b>{n.name[lang]}</b>
              <small>{n.role[lang]}</small>
            </div>
          );
        })}
        {others.map((o) => (
          <div key={o.key} data-other={o.key} className={`ash-tag ${o.eryon || o.azkar ? "eryon" : ""}`} style={{ display: "none" }}>
            {o.name} · {o.level}
          </div>
        ))}
        <div ref={enemyLayerRef} />
      </div>

      {/* horní lišta */}
      <header className="ash-hud">
        <img className="wordmark" src="/game/eryon/wordmark.webp" alt="Ashes of Eryon" />
        {character && state.chapter && (
          <div className="chapter">
            <span style={{ color: FACTION[faction].color }}>
              {character.chapter > 6 ? L("Ukázka dohrána", "Preview complete") : `${L("Akt", "Act")} ${ROMAN[actNo - 1]} · ${actName(actNo)}${actNo > 1 ? L(" (ukázka)", " (preview)") : ""}`}
            </span>
            <b>{tr(state.chapter.title)}</b>
          </div>
        )}
        <div className="stats">
          {character && (
            <>
              <span className="ash-pill" title={L("Zlato", "Gold")}><Coins />{fmtNum(character.gold)}</span>
              <span className="ash-pill hide-sm" title={L("Čest", "Honor")}><Trophy />{fmtNum(character.honor)}</span>
              <span className="ash-pill hide-sm" title={L("Odvaha", "Courage")}><Flame />{character.courage}</span>
              <span className="ash-pill hide-sm" title={L("Síla hradeb Kalidry", "Strength of Kalidra's walls")}><Shield />{war ? ((war.wall / war.wall_max) * 100).toFixed(0) : "—"} %</span>
              <div className="ash-hero-chip">
                <div className="lvl">{character.level}</div>
                <div className="hidden min-w-[120px] sm:block">
                  <div className="name">{character.display_name}</div>
                  <div className="ash-bar mt-1" style={{ height: 5 }}><i style={{ width: `${(character.xp / character.xp_need) * 100}%` }} /></div>
                </div>
              </div>
            </>
          )}
          {character && (
            <button
              className="ash-icon-btn"
              onClick={() => worldRef.current?.setCameraMode(camMode === "top" ? "third" : "top")}
              aria-label={L("Přepnout kameru", "Switch camera")}
              title={camMode === "top" ? L("Kamera: pohled shora (V = třetí osoba)", "Camera: top-down (V = third person)") : L("Kamera: třetí osoba (V = pohled shora)", "Camera: third person (V = top-down)")}
            >
              <Camera className="h-4 w-4" />
            </button>
          )}
          {langToggle}
          <button className="ash-icon-btn" onClick={() => (music.playing ? music.pause() : music.current ? void music.resume() : enter())} aria-label={L("Hudba", "Music")}>
            {music.playing && !music.muted ? <Volume2 className="h-4 w-4" /> : <VolumeX className="h-4 w-4" />}
          </button>
          <button className="ash-icon-btn" onClick={exitGame} aria-label={L("Ukončit hru", "Quit game")} title={isDesktop() ? L("Ukončit hru a vrátit se do launcheru", "Quit to the launcher") : L("Ukončit hru", "Quit game")}><LogOut className="h-4 w-4" /></button>
        </div>
      </header>

      {shoutFresh && inWorld && !talk && (
        <div className={`ash-eryon-banner ${shoutFresh.legion ? "legion" : ""}`}><b>{shoutFresh.hero} {L("promlouvá", "speaks")}</b>„{shoutFresh.text}“</div>
      )}

      {regionBanner && inWorld && !talk && !panel && (
        <div className="ash-region" key={regionBanner}>
          <small>{L("Vstupuješ", "Entering")}</small>
          <b>{REGION_NAME[regionBanner][lang]}</b>
        </div>
      )}

      {showFps && fps !== undefined && <div className="ash-fps">{fps} FPS</div>}

      {slow && inWorld && !panel && (
        <div className="ash-slow" role="status">
          <b>{slow.software ? L("Hra běží bez grafické karty", "The game is running without your graphics card") : L("Hra se ti seká?", "Is the game stuttering?")}</b>
          <span>
            {slow.software
              ? L("V prohlížeči je vypnutá hardwarová akcelerace. Zapni ji (Nastavení prohlížeče → Systém → Používat grafickou akceleraci) a prohlížeč restartuj – nebo si stáhni launcher.", "Hardware acceleration is off in your browser. Turn it on (browser Settings → System → Use graphics acceleration) and restart the browser – or download the launcher.")
              : L("Sniž grafiku, nebo si stáhni launcher – běží plynuleji než prohlížeč s mnoha záložkami.", "Lower the graphics, or download the launcher – it runs smoother than a browser full of tabs.")}
          </span>
          <div className="flex flex-wrap gap-2">
            {getQuality() !== "potato" && (
              <button className="ash-btn small" onClick={() => { changeQuality(QUALITIES[Math.max(0, QUALITIES.indexOf(getQuality()) - 1)]); setSlow(null); }}>
                {L("Snížit grafiku", "Lower graphics")}
              </button>
            )}
            {!isDesktop() && <Link className="ash-btn ghost small" to="/desktop">{L("Stáhnout StudioVoxario Connect", "Download StudioVoxario Connect")}</Link>}
            <button
              className="ash-btn ghost small"
              onClick={() => {
                try {
                  sessionStorage.setItem("ashes.slow.dismissed", "1");
                } catch {
                  /* bez úložiště */
                }
                setSlow(null);
              }}
            >
              {L("Zavřít", "Close")}
            </button>
          </div>
        </div>
      )}

      {inWorld && safe && !talk && !panel && !regionBanner && (
        <div className="ash-safe">{L("Bezpečná zóna", "Safe zone")}</div>
      )}

      {/* tvorba postavy */}
      {!character && entered && (
        <CreateCharacter
          busy={busy}
          onBack={charList?.others.length ? () => void backFromCreate() : undefined}
          onPreview={onPreview}
          onCreate={(name, cls, appearance, f) =>
            act(
              () => ashesApi.createCharacter(name, cls, appearance, f),
              f === "legie" ? L(`Vítej v Legii Rudého slunce, ${name}.`, `Welcome to the Legion of the Red Sun, ${name}.`) : L(`Vítej na Bezejmenném břehu, ${name}.`, `Welcome to the Nameless Shore, ${name}.`),
            )
          }
        />
      )}

      {/* nabídka */}
      {inWorld && (
        <nav className="ash-nav" aria-label={L("Nabídka", "Menu")}>
          {NAV.map((item) => (
            <button key={item.id} data-active={panel === item.id} onClick={() => { setTalk(null); setPanel(panel === item.id ? null : item.id); }}>
              <item.icon />
              <span>{item.id === "hradby" && legion ? L("Tábor a válka", "Camp and war") : item[lang]}</span>
              {item.id === "denik" && readyCount > 0 && <i className="badge">{readyCount}</i>}
              {item.id === "hradby" && state.chapter && character.chapter <= 6 && character.chapter_progress >= state.chapter.need && <i className="badge">⚔</i>}
            </button>
          ))}
        </nav>
      )}

      {inWorld && !panel && !talk && <Minimap world={world} faction={faction} wquests={state.wquests} />}

      {inWorld && !panel && !talk && near && (
        <button className="ash-prompt" onClick={() => void onInteract(near)}>
          <kbd>E</kbd> {nearName}
        </button>
      )}

      {inWorld && !panel && !talk && questReady && (
        <button className="ash-hint" onClick={() => setPanel("krcma")}>⚔ {L("Výprava skončila – vrať se do krčmy", "Expedition over – back to the tavern")}</button>
      )}

      {/* rozhovor */}
      {inWorld && talk && (
        <Dialogue
          key={talk}
          npc={talk}
          state={state}
          busy={busy}
          onAccept={(id) => void acceptQuest(id)}
          onTurnIn={(id) => void turnInQuest(id)}
          onOpen={(p) => { setTalk(null); setPanel(p); }}
          onClose={closeTalk}
        />
      )}

      {/* panely */}
      {inWorld && panel === "krcma" && (
        <TavernPanel state={state} now={now} act={act} busy={busy} onClose={() => setPanel(null)} onFinish={(skip) => runFight("quest", () => ashesApi.finishQuest(skip))} />
      )}
      {inWorld && panel === "postava" && <HeroPanel state={state} act={act} busy={busy} onClose={() => setPanel(null)} />}
      {inWorld && panel === "kovarna" && <SmithyPanel state={state} act={act} busy={busy} onClose={() => setPanel(null)} />}
      {inWorld && panel === "arena" && (
        <ArenaPanel state={state} now={now} busy={busy} onClose={() => setPanel(null)} onFight={(id) => runFight("arena", () => ashesApi.arenaFight(id))} />
      )}
      {inWorld && panel === "hradby" && (
        <WallsPanel state={state} now={now} act={act} busy={busy} onClose={() => setPanel(null)} onBoss={() => runFight("boss", () => ashesApi.fightBoss())} />
      )}
      {inWorld && panel === "bard" && <BardPanel chapter={character.chapter} onClose={() => setPanel(null)} />}
      {inWorld && panel === "kronika" && <ChroniclePanel state={state} others={others} onClose={() => setPanel(null)} />}
      {inWorld && panel === "denik" && <JournalPanel state={state} onClose={() => setPanel(null)} />}
      {inWorld && panel === "nastaveni" && (
        <SettingsPanel
          email={user.email}
          cameraMode={camMode}
          onCameraMode={(m) => worldRef.current?.setCameraMode(m)}
          onQuality={changeQuality}
          onDisplay={(d) => {
            const w = worldRef.current;
            if (w) applyGraphics(w, d);
            setShowFps(d.showFps);
          }}
          fps={fps}
          onLogout={() => void logout()}
          onCharacters={openSelect}
          onExit={exitGame}
          onClose={() => setPanel(null)}
        />
      )}

      {/* souboj */}
      {battle && (
        <>
          <div className="ash-battle-hud">
            {[1, 2].map((side) => {
              const f = side === 1 ? battle.f1 : battle.f2;
              const hp = side === 1 ? battle.hp1 : battle.hp2;
              const max = side === 1 ? battle.max1 : battle.max2;
              const plate = (
                <div key={side} className="ash-frame ash-fplate" style={{ textAlign: side === 1 ? "left" : "right" }}>
                  <div className="n">{tr(f.name)}</div>
                  <div className="s">{classLabel(f.class)} · {L("úroveň", "level")} {f.level}</div>
                  <div className="ash-bar hp"><i style={side === 2 ? { width: `${(hp / max) * 100}%`, left: "auto", right: 0 } : { width: `${(hp / max) * 100}%` }} /></div>
                  <div className="hpnum">{fmtNum(hp)} / {fmtNum(max)}</div>
                </div>
              );
              return side === 1 ? [plate, <div key="vs" className="ash-vs">VS</div>] : plate;
            })}
          </div>
          {pops.map((p) => (
            <div key={p.id} className={`ash-pop ${p.kind === "crit" ? "crit" : p.kind === "miss" ? "miss" : ""}`} style={{ left: p.x, top: p.y }}>{p.text}</div>
          ))}
          {!battle.done && (
            <div className="ash-battle-controls">
              <button className="ash-btn ghost small" onClick={() => worldRef.current?.setBattleSpeed(3)}>{L("Zrychlit ×3", "Speed ×3")}</button>
              <button className="ash-btn ghost small" onClick={() => worldRef.current?.abortBattle()}>{L("Přeskočit", "Skip")}</button>
            </div>
          )}
        </>
      )}

      {result && (
        <div className="ash-modal-wrap">
          <div className="ash-modal ash-frame">
            <div className="ash-kicker">
              {result.kind === "boss" ? L("Rozhodující bitva", "Decisive battle") : result.kind === "arena" ? L("Aréna", "Arena") : result.kind === "wq" ? L("Úkol splněn", "Quest complete") : tr(result.title)}
            </div>
            <h2 className={`ash-title ${result.won ? "win" : "lose"}`}>
              {result.kind === "wq" ? result.questTitle : result.won ? L("Vítězství", "Victory") : L("Porážka", "Defeat")}
            </h2>
            {result.kind === "wq" && result.questText && <p className="ashes-prose">„{result.questText}“</p>}
            {result.kind === "boss" && result.won && result.boss?.win && <p className="ashes-prose">{tr(result.boss.win)}</p>}
            {result.kind === "boss" && !result.won && <p className="ashes-prose">{L("Padl jsi, ale válka pokračuje. Posil se a vrať se.", "You fell, but the war goes on. Grow stronger and return.")}</p>}
            {(result.kind === "quest" || result.kind === "world") && !result.won && (
              <p className="ashes-prose">{result.kind === "world" ? L("Nepřítel tě srazil k zemi. Probouzíš se v bezpečí mezi svými.", "The enemy struck you down. You wake in safety among your own.") : L("Nepřítel tě zahnal. Aspoň sis odnesl zkušenost.", "The enemy drove you off. At least you gained experience.")}</p>
            )}
            <div className="ash-rewards">
              {!!result.xp && <span><Sparkles className="mr-1 inline h-4 w-4 text-[var(--ash-gold)]" />+{fmtNum(result.xp)} {L("zkušeností", "XP")}</span>}
              {!!result.gold && <span><Coins className="mr-1 inline h-4 w-4 text-[var(--ash-gold)]" />+{fmtNum(result.gold)} {L("zlata", "gold")}</span>}
              {typeof result.honor === "number" && <span><Trophy className="mr-1 inline h-4 w-4 text-[var(--ash-gold)]" />{result.honor > 0 ? "+" : ""}{result.honor} {L("cti", "honor")}</span>}
              {(result.levels ?? 0) > 0 && <b className="text-[#f2cf86]">{L("Nová úroveň!", "Level up!")}</b>}
            </div>
            {(result.quests ?? []).map((id) => {
              const def = questDef(id);
              const q = state.wquests?.find((x) => x.quest_id === id);
              if (!def || !q) return null;
              return (
                <p key={id} className="mb-2 text-sm text-[var(--ash-muted)]">
                  {def.title[lang]}: <b className="text-[var(--ash-text)]">{q.progress}/{def.count}</b>{q.state === "ready" && <b className="text-[var(--ash-good)]"> · {L("splněno, vrať se pro odměnu", "complete, return for your reward")}</b>}
                </p>
              );
            })}
            {result.item && (
              <p className="mb-3">
                {L("Kořist", "Loot")}: <b style={{ color: RARITY[result.item.rarity]?.color }}>{trItem(result.item.name)}</b>
              </p>
            )}
            <button className="ash-btn" onClick={closeResult}>{L("Pokračovat", "Continue")}</button>
          </div>
        </div>
      )}

      {!entered && selectOpen && (
        <CharacterSelect
          list={charList}
          busy={busy}
          onPlay={(c) => void playCharacter(c)}
          onNew={() => void newCharacter()}
          onDelete={(c) => void deleteCharacter(c)}
          onClose={() => setSelectOpen(false)}
        />
      )}

      {!entered && !selectOpen && (
        <div className="ash-title-screen">
          <div className="ash-title-inner">
            <img src="/game/eryon/wordmark.webp" alt="Ashes of Eryon" />
            <div className="tag">{L("Akt I · Poslední štít", "Act I · The Last Shield")}</div>
            <p className="ashes-prose">
              {character
                ? legion
                  ? L(`${character.display_name} čeká u černých plachet. Kalidra ještě stojí.`, `${character.display_name} waits by the black sails. Kalidra still stands.`)
                  : L(`${character.display_name} čeká na Bezejmenném břehu. Kalidra stále stojí.`, `${character.display_name} waits on the Nameless Shore. Kalidra still stands.`)
                : L("Moře tě vyplavilo na Bezejmenném břehu. V dálce hoří světla Kalidry.", "The sea cast you onto the Nameless Shore. The lights of Kalidra burn in the distance.")}
            </p>
            <button className="ash-btn" onClick={enter}>{character ? L("Vstoupit do světa", "Enter the world") : L("Začít dobrodružství", "Begin the adventure")}</button>
            {character && (
              <button className="ash-btn ghost small" onClick={() => { setSelectOpen(true); void loadCharacters(); }}>{L("Výběr postavy", "Choose character")}</button>
            )}
            <div className="flex items-center gap-2">
              <span className="text-xs text-[var(--ash-muted)]">{L("Alfa · otevřený svět · hudba: album „Eryon“", "Alpha · open world · music: the “Eryon” album")}</span>
              <Link to="/ashes" className="text-xs text-[var(--ash-gold)] underline">{L("Roadmapa", "Roadmap")}</Link>
              {langToggle}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

const CLASS_ICON: Record<HeroClass, string> = { hoplit: "🛡", lucistnik: "🏹", vestec: "🔥" };

/** Výběr postavy: aktivní a uložené postavy účtu, nová postava, smazání. */
function CharacterSelect({ list, busy, onPlay, onNew, onDelete, onClose }: {
  list: CharacterList | null;
  busy: boolean;
  onPlay: (c: CharacterSummary) => void;
  onNew: () => void;
  onDelete: (c: CharacterSummary) => void;
  onClose: () => void;
}) {
  useLang();
  const all = list ? [...(list.active ? [list.active] : []), ...list.others] : [];
  const canNew = !!list && all.length < list.max;
  return (
    <div className="ash-title-screen">
      <section className="ash-select ash-frame">
        <header>
          <div className="ash-kicker">{L("Tvoje postavy", "Your characters")}</div>
          <h2 className="ash-title m-0 text-xl">{L("Za koho budeš hrát?", "Who will you play?")}</h2>
          {list && <small>{all.length} / {list.max}</small>}
        </header>
        {!list ? (
          <p className="ashes-prose">{L("Načítám postavy…", "Loading characters…")}</p>
        ) : (
          <div className="ash-select-list">
            {all.map((c) => {
              const active = !c.id;
              const f = (c.faction ?? "kalidra") as Faction;
              return (
                <div key={c.id ?? "active"} className="ash-select-card" data-active={active} data-faction={f}>
                  <div className={`portrait ${c.appearance?.gender === "f" ? "f" : "m"}`} aria-hidden>
                    <img src={heroPortraitUrl(c.class, c.appearance?.gender === "f" ? "f" : "m")} alt="" />
                  </div>
                  <div className="info">
                    <b>{c.eryon ? "Eryon" : c.azkar ? "Azkar" : c.name}</b>
                    <small>
                      {CLASS_ICON[c.class]} {classLabel(c.class)} · {L("úroveň", "level")} {c.level}
                    </small>
                    <small style={{ color: FACTION[f].color }}>{f === "legie" ? L("Legie Rudého slunce", "Legion of the Red Sun") : L("Obránci Kalidry", "Defenders of Kalidra")}{active ? ` · ${L("naposledy hraná", "last played")}` : ""}</small>
                  </div>
                  <div className="actions">
                    <button className="ash-btn small" disabled={busy} onClick={() => onPlay(c)}>{L("Hrát", "Play")}</button>
                    {!active && <button className="ash-btn ghost small" disabled={busy} onClick={() => onDelete(c)} aria-label={L("Smazat postavu", "Delete character")}>✕</button>}
                  </div>
                </div>
              );
            })}
            {canNew && (
              <button className="ash-select-new" disabled={busy} onClick={onNew}>
                <b>＋ {L("Nová postava", "New character")}</b>
                <small>{L("Muž nebo žena, libovolné povolání i strana. Ostatní postavy zůstanou uložené.", "Man or woman, any class and side. Your other characters stay saved.")}</small>
              </button>
            )}
          </div>
        )}
        <footer>
          <button className="ash-btn ghost small" onClick={onClose}>{L("Zpět", "Back")}</button>
        </footer>
      </section>
    </div>
  );
}

/** Přihlášení přímo ve hře (stejný účet StudioVoxario). */
function LoginForm() {
  useLang();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const { error: err } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    setBusy(false);
    if (err) setError(L("Přihlášení se nepodařilo. Zkontroluj e-mail a heslo.", "Sign-in failed. Check your e-mail and password."));
  };
  return (
    <form className="ash-login" onSubmit={submit}>
      <p className="ashes-prose text-center">{L("Do světa Kalidry vstoupíš se svým účtem StudioVoxario.", "Enter the world of Kalidra with your StudioVoxario account.")}</p>
      <label htmlFor="ash-login-email">{L("E-mail", "E-mail")}</label>
      <input id="ash-login-email" className="ash-input" type="email" autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
      <label htmlFor="ash-login-pass">{L("Heslo", "Password")}</label>
      <input id="ash-login-pass" className="ash-input" type="password" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} required />
      {error && <p className="text-sm text-[#ffb4a0]">{error}</p>}
      <button className="ash-btn" type="submit" disabled={busy}>{busy ? L("Přihlašuji…", "Signing in…") : L("Přihlásit se", "Sign in")}</button>
      <Link className="text-center text-xs text-[var(--ash-muted)] underline" to="/auth?next=/hra">{L("Nemáš účet nebo se přihlašuješ přes Google/Discord? Pokračuj sem.", "No account, or sign in with Google/Discord? Continue here.")}</Link>
    </form>
  );
}
