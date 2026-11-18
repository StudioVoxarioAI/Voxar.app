import { useCallback, useEffect, useState } from "react";
import { Navbar } from "@/components/Navbar";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { supabase } from "@/integrations/supabase/client";
import { useToast } from "@/hooks/use-toast";
import { Gamepad2, Loader2, Trash2, UserPlus } from "lucide-react";

/**
 * Přístupy ke hrám (StudioVoxario Connect): kdo smí stáhnout a hrát Ashes of Eryon a Fantasy.
 * Stejná data spravuje i stránka Správa v aplikaci StudioVoxario Connect (RPC game_admin_access_*).
 * Ashes of Eryon spravuje jen správce, Fantasy i editor.
 */
const GAMES = [
  { id: "ashes-of-eryon", name: "Ashes of Eryon" },
  { id: "fantasy", name: "Fantasy" },
] as const;

type Row = { user_id: string; email: string | null; name: string | null; note: string | null; created_at: string };
type Rpc = (fn: string, args?: Record<string, unknown>) => PromiseLike<{ data: unknown; error: { message: string } | null }>;
const rpc = (fn: string, args?: Record<string, unknown>) => (supabase.rpc as unknown as Rpc).call(supabase, fn, args);

export default function AdminGameAccess() {
  const { toast } = useToast();
  const [game, setGame] = useState<(typeof GAMES)[number]["id"]>("fantasy");
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);
  const [who, setWho] = useState("");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);

  const run = useCallback(async (fn: string, args: Record<string, unknown>, ok?: string) => {
    setBusy(true);
    const { data, error } = await rpc(fn, args);
    setBusy(false);
    setLoading(false);
    if (error) { toast({ title: "Nepovedlo se", description: error.message, variant: "destructive" }); return false; }
    setRows(Array.isArray(data) ? (data as Row[]) : []);
    if (ok) toast({ title: ok });
    return true;
  }, [toast]);

  useEffect(() => { setLoading(true); void run("game_admin_access_list", { p_game: game }); }, [game, run]);

  const grant = async () => {
    if (await run("game_admin_access_grant", { p_game: game, p_who: who.trim(), p_note: note.trim() || null }, "Přístup povolen")) { setWho(""); setNote(""); }
  };

  return (
    <div className="min-h-screen bg-background">
      <Navbar />
      <main className="container mx-auto max-w-4xl px-4 py-10">
        <h1 className="mb-1 flex items-center gap-2 text-3xl font-bold"><Gamepad2 className="h-7 w-7 text-primary" /> Přístupy ke hrám</h1>
        <p className="mb-6 text-sm text-muted-foreground">
          Kdo smí ve StudioVoxario Connect stáhnout a hrát. Správci a editoři mají přístup vždy. Totéž lze spravovat přímo v Connectu (Správa).
        </p>

        <div className="mb-6 flex flex-wrap gap-2">
          {GAMES.map((g) => (
            <Button key={g.id} variant={game === g.id ? "default" : "outline"} onClick={() => setGame(g.id)}>{g.name}</Button>
          ))}
        </div>

        <Card className="mb-6 p-5">
          <div className="grid gap-3 md:grid-cols-[1fr_1fr_auto] md:items-end">
            <div className="space-y-1.5"><Label htmlFor="ga-who">E-mail nebo přezdívka</Label><Input id="ga-who" value={who} onChange={(e) => setWho(e.target.value)} placeholder="hrac@example.com" /></div>
            <div className="space-y-1.5"><Label htmlFor="ga-note">Poznámka (nepovinné)</Label><Input id="ga-note" value={note} onChange={(e) => setNote(e.target.value)} placeholder="např. tester" /></div>
            <Button disabled={busy || who.trim().length < 2} onClick={() => void grant()}>
              {busy ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <UserPlus className="mr-2 h-4 w-4" />}Povolit přístup
            </Button>
          </div>
        </Card>

        <Card className="divide-y divide-border">
          {loading ? (
            <div className="flex justify-center p-8"><Loader2 className="h-6 w-6 animate-spin text-primary" /></div>
          ) : rows.length === 0 ? (
            <p className="p-6 text-center text-sm text-muted-foreground">Zatím nikdo nemá přístup (kromě správců a editorů).</p>
          ) : rows.map((r) => (
            <div key={r.user_id} className="flex items-center gap-4 p-4">
              <div className="min-w-0 flex-1">
                <div className="truncate font-medium">{r.name ?? r.email ?? r.user_id}</div>
                <div className="truncate text-xs text-muted-foreground">{r.email}{r.note ? ` · ${r.note}` : ""} · od {new Date(r.created_at).toLocaleDateString("cs-CZ")}</div>
              </div>
              <Button variant="ghost" size="sm" disabled={busy} onClick={() => void run("game_admin_access_revoke", { p_game: game, p_user: r.user_id }, "Přístup odebrán")}>
                <Trash2 className="mr-1.5 h-4 w-4" />Odebrat
              </Button>
            </div>
          ))}
        </Card>
      </main>
    </div>
  );
}
