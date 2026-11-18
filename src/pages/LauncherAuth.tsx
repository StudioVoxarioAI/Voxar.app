import { useEffect, useMemo, useState } from "react";
import { Link, useLocation, useNavigate, useSearchParams } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { Button } from "@/components/ui/button";
import { Gamepad2, Loader2, MonitorCheck, ShieldCheck, ShieldX, UserRound } from "lucide-react";
import { useSiteSettings } from "@/contexts/SiteSettingsContext";

/**
 * Přihlášení desktopové aplikace (launcher Ashes of Eryon, Voxario Studio Engine…) účtem StudioVoxario.
 * Aplikace otevře tuto stránku v prohlížeči (state, challenge, port, app). Přihlášený uživatel potvrdí,
 * web vydá jednorázový kód a předá ho aplikaci přes http://127.0.0.1:<port>/callback.
 * Heslo ani relace webu se do aplikace nikdy nedostanou. Postup: game/launcher/spec/AUTH_HANDOFF.md.
 */
const STORE = "voxario.launcherAuth";
const B64URL = /^[A-Za-z0-9_-]{16,128}$/;

type AppInfo = { name: string; ask: string; sees: string; back: string; download: string; downloadLabel: string };
const APPS: Record<string, AppInfo> = {
  connect: {
    name: "StudioVoxario Connect",
    ask: "Přihlásit StudioVoxario Connect?",
    sees: "Connect uvidí tvé jméno, knihovnu, přístupy a licence a bude moct spouštět hry pod tvým účtem.",
    back: "Connectu",
    download: "/desktop",
    downloadLabel: "Stáhnout StudioVoxario Connect",
  },
  ashes: {
    name: "launcher Ashes of Eryon",
    ask: "Přihlásit launcher Ashes of Eryon?",
    sees: "Launcher uvidí tvé jméno a bude moct spustit hru pod tvým účtem.",
    back: "launcheru",
    download: "/desktop#ashes",
    downloadLabel: "Stáhnout launcher",
  },
  studio: {
    name: "Voxario Studio Engine",
    ask: "Přihlásit Voxario Studio Engine?",
    sees: "Aplikace uvidí tvé jméno a stav tvé licence (aktualizace, Upgrade pass).",
    back: "aplikace",
    download: "/obchod?tab=software",
    downloadLabel: "Voxario Studio Engine v obchodě",
  },
};

type Request = { state: string; challenge: string; port: number; device: string; app: string; t: number };

function readRequest(params: URLSearchParams): Request | null {
  const state = params.get("state") ?? "";
  const challenge = params.get("challenge") ?? "";
  const port = Number(params.get("port"));
  if (B64URL.test(state) && B64URL.test(challenge) && Number.isInteger(port) && port >= 1024 && port <= 65535) {
    const appParam = params.get("app") ?? "ashes";
    const app = appParam in APPS ? appParam : "ashes";
    const req = { state, challenge, port, device: (params.get("device") ?? "").slice(0, 60), app, t: Date.now() };
    try { localStorage.setItem(STORE, JSON.stringify(req)); } catch { /* soukromý režim */ }
    return req;
  }
  // návrat z přihlášení (Google / Discord / e-mail) – požadavek launcheru je uložený
  try {
    const saved = JSON.parse(localStorage.getItem(STORE) ?? "null") as Request | null;
    if (saved && Date.now() - saved.t < 15 * 60_000) return { ...saved, app: saved.app in APPS ? saved.app : "ashes" };
  } catch { /* neplatná data */ }
  return null;
}

const LauncherAuth = () => {
  const navigate = useNavigate();
  const location = useLocation();
  const [params] = useSearchParams();
  const { user, loading } = useAuth();
  const { settings } = useSiteSettings();
  const siteName = settings.site_name || "StudioVoxario";
  const request = useMemo(() => readRequest(params), [params]);
  const app = APPS[request?.app ?? (location.pathname.startsWith("/game") ? "ashes" : "studio")] ?? APPS.ashes;
  const loginUrl = `/auth?next=${encodeURIComponent(location.pathname)}`;
  const [name, setName] = useState<string>("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<"ok" | "denied" | null>(null);

  useEffect(() => {
    if (loading || !request) return;
    if (!user) navigate(loginUrl, { replace: true });
  }, [loading, user, request, navigate, loginUrl]);

  useEffect(() => {
    if (!user) return;
    void supabase.from("profiles").select("display_name, username").eq("user_id", user.id).maybeSingle()
      .then(({ data }) => setName(data?.display_name || data?.username || user.email || ""));
  }, [user]);

  const finish = (query: string, result: "ok" | "denied") => {
    try { localStorage.removeItem(STORE); } catch { /* nic */ }
    setDone(result);
    window.location.href = `http://127.0.0.1:${request!.port}/callback?${query}&state=${encodeURIComponent(request!.state)}`;
  };

  const approve = async () => {
    if (!request) return;
    setBusy(true);
    setError(null);
    const { data, error: err } = await supabase.functions.invoke("launcher-auth", {
      body: { action: "start", challenge: request.challenge, device: request.device || "Windows" },
    });
    setBusy(false);
    if (err || !data?.code) {
      setError(data?.error || `Přihlášení se nepodařilo. Zkus to v ${app.back} znovu.`);
      return;
    }
    finish(`code=${encodeURIComponent(data.code)}`, "ok");
  };

  const switchAccount = async () => {
    await supabase.auth.signOut();
    navigate(loginUrl, { replace: true });
  };

  return (
    <div className="min-h-screen relative flex items-center justify-center p-4 overflow-hidden">
      <div className="fixed inset-0 -z-10 gradient-hero" />
      <div className="fixed inset-0 -z-10 neon-grid opacity-40" />
      <div className="fixed top-1/3 left-1/4 w-96 h-96 rounded-full bg-primary/25 blur-[120px] animate-float-slow" />

      <div className="w-full max-w-md animate-scale-in">
        <Link to="/" className="flex items-center justify-center gap-2 mb-8 group">
          <Gamepad2 className="h-8 w-8 text-primary group-hover:scale-110 transition-transform" />
          <span className="font-display font-bold text-2xl tracking-widest text-glow">{siteName}</span>
        </Link>

        <div className="glass rounded-2xl p-8 border-glow">
          {!request ? (
            <div className="space-y-4 text-center">
              <ShieldX className="h-10 w-10 mx-auto text-destructive" />
              <h1 className="font-display text-xl font-bold">Odkaz pro přihlášení vypršel</h1>
              <p className="text-sm text-muted-foreground">
                Tuhle stránku otevírá {app.name}. V {app.back} klikni znovu na <b>Přihlásit se</b>.
              </p>
              <Button variant="outline" className="w-full" onClick={() => navigate(app.download)}>{app.downloadLabel}</Button>
            </div>
          ) : done ? (
            <div className="space-y-4 text-center">
              {done === "ok" ? <MonitorCheck className="h-10 w-10 mx-auto text-primary" /> : <ShieldX className="h-10 w-10 mx-auto text-muted-foreground" />}
              <h1 className="font-display text-xl font-bold">{done === "ok" ? `Hotovo – vrať se do ${app.back}` : "Přihlášení zamítnuto"}</h1>
              <p className="text-sm text-muted-foreground">
                {done === "ok" ? "Přihlášení proběhlo. Tohle okno prohlížeče můžeš zavřít." : "Přihlášení neproběhlo. Okno můžeš zavřít."}
              </p>
            </div>
          ) : loading || !user ? (
            <div className="flex justify-center py-10"><Loader2 className="h-8 w-8 animate-spin text-primary" /></div>
          ) : (
            <div className="space-y-5">
              <div className="text-center space-y-2">
                <ShieldCheck className="h-10 w-10 mx-auto text-primary" />
                <h1 className="font-display text-xl font-bold">{app.ask}</h1>
                <p className="text-sm text-muted-foreground">
                  {request.app === "ashes" ? "Launcher" : "Aplikace"} {request.device ? <>na zařízení <b className="text-foreground">{request.device}</b> </> : null}
                  žádá o přístup k tvému účtu. Potvrď jen tehdy, když jsi ho právě spustil ty.
                </p>
              </div>

              <div className="flex items-center gap-3 rounded-xl border border-border/60 bg-background/40 p-3">
                <div className="h-10 w-10 rounded-full bg-primary/15 flex items-center justify-center">
                  <UserRound className="h-5 w-5 text-primary" />
                </div>
                <div className="min-w-0 flex-1">
                  <div className="font-semibold truncate">{name || "…"}</div>
                  <div className="text-xs text-muted-foreground truncate">{user.email}</div>
                </div>
                <button type="button" onClick={switchAccount} className="text-xs text-muted-foreground hover:text-primary">Jiný účet</button>
              </div>

              <ul className="text-xs text-muted-foreground space-y-1 list-disc pl-5">
                <li>{app.sees}</li>
                <li>Heslo aplikace nikdy nedostane. Odhlásit ji můžeš kdykoli přímo v ní.</li>
              </ul>

              {error && <p className="text-sm text-destructive">{error}</p>}

              <div className="grid grid-cols-2 gap-3">
                <Button variant="outline" disabled={busy} onClick={() => finish("error=denied", "denied")}>Zamítnout</Button>
                <Button disabled={busy} onClick={approve} className="bg-primary text-primary-foreground hover:bg-primary-glow">
                  {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : "Povolit"}
                </Button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default LauncherAuth;
