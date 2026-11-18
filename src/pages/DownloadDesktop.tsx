import { Download as DownloadIcon, Monitor, KeyRound, Library, RefreshCw, ShieldCheck, Swords, Sparkles, Globe, Cpu } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Navbar } from "@/components/Navbar";

/**
 * Ke stažení = jen StudioVoxario Connect (obchod, knihovna, stahování, aktualizace a spouštění všech produktů).
 * Samostatné instalátory Voxar.app, VoxarioBrowser a launcheru Ashes of Eryon se už nenabízejí – instaluje je Connect.
 * Přístupová pravidla zůstávají: Voxar.app (a VoxarioProtect) jen s přístupovým klíčem zadaným v Connectu,
 * Ashes of Eryon jen s přístupem ke hře u účtu, Voxario Studio Engine s licencí z obchodu.
 * Stabilní URL: workflow vydání Connectu nahrává i kopii instalátoru bez čísla verze.
 */
const CONNECT_SETUP_URL =
  "https://github.com/StudioVoxarioAI/StudioVoxario-Connect/releases/latest/download/StudioVoxarioConnectSetup.exe";

const products = [
  { icon: Swords, name: "Ashes of Eryon", note: "Vyžaduje přístup ke hře u tvého účtu." },
  { icon: Sparkles, name: "Fantasy", note: "Zdarma." },
  { icon: Cpu, name: "Voxario Studio Engine", note: "Licence z obchodu StudioVoxario." },
  { icon: Monitor, name: "Voxar.app", note: "Instalace jen s přístupovým klíčem." },
  { icon: ShieldCheck, name: "VoxarioProtect", note: "Součást Voxar.app – stejný klíč." },
  { icon: Globe, name: "VoxarioBrowser", note: "Zdarma." },
];

const features = [
  { icon: Library, title: "Knihovna a obchod", desc: "Všechny hry a software studia na jednom místě, s tvým účtem StudioVoxario." },
  { icon: RefreshCw, title: "Aktualizace", desc: "Stahuje jen změněné soubory, navazuje po přerušení a vrátí verzi, když se nová nespustí." },
  { icon: KeyRound, title: "Přístup a klíče", desc: "Klíč k Voxar.app i přístup k Ashes of Eryon se ověřují u účtu – bez nich se nic nestáhne." },
  { icon: ShieldCheck, title: "Bezpečné přihlášení", desc: "Přihlášení přes web v prohlížeči, heslo aplikace nikdy nevidí." },
];

export default function Download() {
  return (
    <div className="min-h-screen bg-background">
      <Navbar />
      <div className="container mx-auto px-4 py-16 max-w-5xl">
        <div className="text-center mb-10">
          <div className="inline-flex items-center justify-center w-20 h-20 rounded-2xl bg-primary/10 border border-primary/30 mb-6 icon-cube-3d">
            <Library className="w-10 h-10 text-primary" />
          </div>
          <h1 className="text-4xl md:text-5xl font-bold mb-4">
            StudioVoxario <span className="text-primary text-glow">Connect</span>
          </h1>
          <p className="text-lg text-muted-foreground max-w-3xl mx-auto">
            Jedna aplikace pro všechny hry a software StudioVoxario – obchod, knihovna, stahování, aktualizace a spouštění.
          </p>
        </div>

        <Card id="connect" className="p-8 mb-10 border-primary/35 bg-card/80 relative overflow-hidden text-center">
          <div className="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-primary to-transparent" />
          <Button size="lg" variant="hero" className="btn-3d group w-full max-w-md mx-auto" asChild>
            <a href={CONNECT_SETUP_URL}>
              <DownloadIcon className="h-5 w-5 mr-2 group-hover:animate-bounce" />
              Stáhnout StudioVoxario Connect
            </a>
          </Button>
          <p className="text-xs text-muted-foreground mt-3">
            StudioVoxarioConnectSetup.exe · Windows 10 / 11 (64 bit) · instalace bez práv správce · aktualizuje se sám
          </p>
        </Card>

        <Card id="ashes" className="p-6 mb-10">
          <h2 className="text-xl font-semibold mb-4">Co v Connectu najdeš</h2>
          <div className="grid sm:grid-cols-2 gap-4">
            {products.map((p) => (
              <div key={p.name} className="flex gap-3">
                <div className="w-10 h-10 rounded-lg bg-primary/10 border border-primary/20 flex items-center justify-center shrink-0">
                  <p.icon className="w-5 h-5 text-primary" />
                </div>
                <div>
                  <div className="font-medium">{p.name}</div>
                  <div className="text-sm text-muted-foreground">{p.note}</div>
                </div>
              </div>
            ))}
          </div>
        </Card>

        <Card className="p-6 mb-10">
          <div className="grid sm:grid-cols-2 gap-4">
            {features.map((f) => (
              <div key={f.title} className="flex gap-3">
                <div className="w-10 h-10 rounded-lg bg-primary/10 border border-primary/20 flex items-center justify-center shrink-0">
                  <f.icon className="w-5 h-5 text-primary" />
                </div>
                <div>
                  <div className="font-medium">{f.title}</div>
                  <div className="text-sm text-muted-foreground">{f.desc}</div>
                </div>
              </div>
            ))}
          </div>
        </Card>

        <Card className="p-6">
          <h2 className="text-xl font-semibold mb-3">Instalace</h2>
          <ol className="space-y-2 text-sm text-muted-foreground list-decimal pl-5">
            <li>Stáhni a spusť <code className="bg-muted px-1 rounded">StudioVoxarioConnectSetup.exe</code>.</li>
            <li>V Connectu se přihlas svým účtem StudioVoxario (otevře se prohlížeč).</li>
            <li>V Obchodě nebo Knihovně vyber hru či aplikaci a klikni na Instalovat. U Voxar.app zadej přístupový klíč.</li>
            <li>Máš už nainstalovanou hru přes launcher Ashes of Eryon? Connect ji převezme bez nového stahování.</li>
          </ol>
          <p className="mt-4 text-xs text-muted-foreground">
            Aplikace zatím není podepsaná – při prvním spuštění může Windows zobrazit varování „Windows chránil váš počítač".
            Klikni na <b>Další informace → Přesto spustit</b>.
          </p>
        </Card>
      </div>
    </div>
  );
}
