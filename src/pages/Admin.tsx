import { Link } from "react-router-dom";
import { Navbar } from "@/components/Navbar";
import { Card } from "@/components/ui/card";
import {
  Shield, Users, Settings, BarChart3, MessageSquareWarning,
  Palette, Gamepad2, MessageCircle, Radio, Newspaper, MessageSquare, Bot,
  Package, ClipboardList, KeyRound, Terminal, Sparkles, ShoppingBag, Receipt,
} from "lucide-react";

type Section = {
  icon: typeof Users;
  title: string;
  desc: string;
  to: string;
};

type Group = {
  key: string;
  label: string;
  hint: string;
  sections: Section[];
};

const groups: Group[] = [
  {
    key: "community",
    label: "Komunita",
    hint: "Uživatelé, role a podpora",
    sections: [
      { icon: Users, title: "Uživatelé, role & oprávnění", desc: "Účty, role a co každá role smí", to: "/admin/users" },
      { icon: Shield, title: "Moderace", desc: "Log filtrovaného a zablokovaného obsahu", to: "/admin/moderation" },
      { icon: Sparkles, title: "Kosmetika", desc: "Přidělovat uživatelům rámečky avatarů", to: "/admin/cosmetics" },
      { icon: Sparkles, title: "Badge & rámečky", desc: "Nahrát badge a odstranit pozadí", to: "/admin/cosmetics?tab=badges" },
      { icon: MessageSquareWarning, title: "Tickety", desc: "Helpdesk pro uživatele", to: "/tickets" },
    ],
  },
  {
    key: "content",
    label: "Obsah",
    hint: "Stránky, fórum, novinky a streamy",
    sections: [
      { icon: Palette, title: "Page Builder", desc: "Drag & drop editor stránek", to: "/admin/pages" },
      { icon: MessageSquare, title: "Kategorie fóra", desc: "Vytvářet a spravovat diskuzní kategorie", to: "/admin/forum-categories" },
      { icon: Radio, title: "Streamy", desc: "Featured streamery (Twitch, YouTube, Kick)", to: "/admin/streams" },
      { icon: Bot, title: "Chat bot (Twitch & YouTube)", desc: "Automod, anti-scam, uvítání a vlastní příkazy v chatu", to: "/admin/chat-bot" },
    ],
  },
  {
    key: "integrations",
    label: "Integrace & Hry",
    hint: "Externí služby a katalogy",
    sections: [
      { icon: Gamepad2, title: "Hry", desc: "Katalog her pro server list", to: "/admin/games" },
      { icon: Gamepad2, title: "Přístupy ke hrám", desc: "Kdo smí v StudioVoxario Connect hrát Ashes of Eryon a Fantasy", to: "/admin/game-access" },
      { icon: MessageCircle, title: "Discord servery", desc: "Spravovat invite odkazy a featured tlačítko", to: "/admin/discord" },
    ],
  },
  {
    key: "orders",
    label: "Zakázky",
    hint: "3D tisk – objednávky a katalog modelů",
    sections: [
      { icon: ClipboardList, title: "Přehled zakázek", desc: "Skrytý přehled všech zakázek od zákazníků", to: "/zakazky" },
      { icon: Package, title: "Katalog 3D modelů", desc: "Public Domain modely nabízené v objednávkovém formuláři", to: "/admin/order-models" },
      { icon: Receipt, title: "Nákupy a dary", desc: "Kdo si co koupil, za kolik a kolik daroval", to: "/admin/nakupy" },
      { icon: ShoppingBag, title: "Obchod", desc: "Rámečky, plugin licence, ceny a platební nastavení", to: "/obchod" },
    ],
  },
  {
    key: "system",
    label: "Nastavení & Přehled",
    hint: "Konfigurace a statistiky webu",
    sections: [
      { icon: BarChart3, title: "Statistiky", desc: "Návštěvnost, komunita a stav webu", to: "/admin/stats" },
      { icon: Settings, title: "Nastavení webu", desc: "Texty na úvodce, navbaru, logo a zápatí", to: "/admin/settings" },
      { icon: KeyRound, title: "Kódy ke stažení", desc: "Generovat a spravovat přístupové/promo kódy pro /desktop", to: "/admin/download-codes" },
      { icon: Terminal, title: "Konzole", desc: "Živý log konzole, chyby a diagnostika prohlížeče", to: "/admin/console" },
    ],
  },
];

const Admin = () => {
  return (
    <div className="min-h-screen relative">
      <div className="fixed inset-0 -z-10 gradient-hero" />
      <Navbar />
      <main className="container py-10 animate-fade-in">
        <div className="mb-10">
          <p className="text-sm uppercase tracking-[0.3em] text-primary text-glow">Administrace</p>
          <h1 className="font-display font-black text-4xl md:text-5xl mt-2">Control Panel</h1>
          <p className="text-muted-foreground mt-2 max-w-2xl">
            Vše pro správu webu rozdělené do přehledných kategorií.
          </p>
        </div>

        <div className="space-y-10">
          {groups.map((group) => (
            <section key={group.key}>
              <div className="flex items-end justify-between mb-4 border-b border-border/60 pb-2">
                <div>
                  <h2 className="font-display font-bold text-xl text-glow">{group.label}</h2>
                  <p className="text-xs uppercase tracking-wider text-muted-foreground mt-1">
                    {group.hint}
                  </p>
                </div>
                <span className="text-xs text-muted-foreground">
                  {group.sections.length} {group.sections.length === 1 ? "sekce" : "sekcí"}
                </span>
              </div>

              <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-5">
                {group.sections.map((s) => (
                  <Link key={s.title} to={s.to}>
                    <Card className="glass border-border p-6 hover:border-primary/60 transition-all hover:translate-y-[-4px] cursor-pointer group h-full">
                      <div className="w-11 h-11 rounded-lg bg-primary/10 border border-primary/30 flex items-center justify-center mb-4 group-hover:bg-primary/20 transition-all">
                        <s.icon className="h-5 w-5 text-primary" />
                      </div>
                      <h3 className="font-display font-bold text-lg">{s.title}</h3>
                      <p className="text-sm text-muted-foreground mt-1">{s.desc}</p>
                    </Card>
                  </Link>
                ))}
              </div>
            </section>
          ))}
        </div>
      </main>
    </div>
  );
};

export default Admin;
