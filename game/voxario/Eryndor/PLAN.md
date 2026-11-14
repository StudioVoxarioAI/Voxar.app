# Eryndor – testovací fantasy kanál (plán a stav)

Zadání (vlastník, 2026-11-04): nový kanál launcheru „Fantasy“, nová hra od základu podle lore
„Svět Eryndor a Velký Rozkol“ (Sylvaria vs. Aethelgard, Ozvěna, Aetherium, Umbra). Jen testovací
počáteční lokace, ať je vidět, jak by hra mohla vypadat. Styl jako stylizovaná MMO (4Story, World of
Warcraft) – **ale vše vlastní** (žádné převzaté modely, textury, postavy ani hudba z cizích her; assety
se generují kódem v `tools/`). Bojový systém podle principů 4Story (tab-target). Vítr, počasí, obloha,
voda. Vše přes Voxario Studio Engine.

## Postup (zaškrtnuté = hotovo; při přerušení pokračovat od prvního nezaškrtnutého)

### A. Engine (Voxario-Studio-Engine)
- [x] A1 Počasí: déšť, sníh, bouřka s blesky, mokré povrchy, sněhová pokrývka (`world.weather`)
- [x] A2 Globální vítr (směr, síla, nárazy): tráva, stromy, mraky, vlny vody
- [x] A2b Oblékání: `entity.show_part`, `entity.parts`, `entity.equip` (díly z jiného modelu na kostře nositele)
- [ ] A3 Částice (kouzla, jiskry krystalů, světlušky, prach) – `world.particles`
- [x] A4 Vydání enginu (1.9.0)

### B. Assety (generátor `tools/eryndor_assets.py`, vlastní tvorba)
- [x] B1 Postavy: Ozvěna (muž / žena), zbroj Sylvarie a Aethelgardu – kostra od začátku (tuhé díly = bez natažení)
- [x] B2 Nepřátelé: Zkažený vlk (krystaly Umbria), Kultista Prázdnoty, Drtič popela
- [x] B3 Krajina: obří živý strom, bioluminiscenční houby a kapradí, krystaly Aetheria, skály, bílý mramor
- [x] B4 Stavby: sylvarská mramorová svatyně, aethelgardská železná strážní věž s ozubenými koly, Stínová trhlina
- [x] B5 Lávový pavouk (Creature Forge enginu): `tools/creatures/lavovy_pavouk.creature.json` →
      `VoxarioCreatureForge … Assets/Models/chars/lavovy_pavouk.glb --lod …_lo.glb` (kostra, klipy Idle/Walk/Run/Attack/Hit/Death,
      lávové praskliny a žhnoucí klouby jako emise). Ve hře `spider` v `eryndor/combat.lua`: úroveň 4, hnízdo na popelavém
      návrší (78, 88), (92, 74), (66, 102), svítí kolem sebe. Samotest `VOXARIO_SELFTEST_ONLY=spider`, v `game` záběry g9–g12.
- [x] B6 Ledový drak (Creature Forge, archetyp `dragon`): `tools/creatures/ledovy_drak.creature.json` →
      `Assets/Models/chars/ledovy_drak.glb` (+ `_lo`): 3 materiály (šupiny s normálovou a ORM mapou, průsvitný led,
      průsvitná blána), 32 kostí, klipy Idle/Walk/Run/Flap/Attack/Roar/Hit/Death. Ve hře `dragon` (elita, úroveň 6) na
      severozápadních skalách (−58, 152), při zahlédnutí hráče zařve. Samotest `VOXARIO_SELFTEST_ONLY=dragon`, v `game` g13–g16.
      Model je teď z obrázku `tools/creatures/ledovy_drak.jpg` (Meshy image-to-3D, PBR 2048 px, ~103k trojúhelníků)
      napasovaný na kostru draka: `VoxarioImageTo3D ledovy_drak.jpg ledovy_drak.glb --rig ledovy_drak.creature.json --glow 4`.
      LOD `_lo`: `gltf-transform simplify --ratio 0.25 --error 0.002` + `resize 1024` (~44k trojúhelníků).
      Kostra a 8 klipů zůstávají z Creature Forge. Záře prasklin: `--glow 4` (emisní mapa z namalované azurové).
- [x] A6 Textury z listu přírodních textur (`tools/textures/prirodni_textury.jpg` → `tools/eryndor_textures.sh <engine/bin>`,
      `VoxarioTextureTool`: výřez, navazující dlaždice, vyrovnaný jas): terén (tráva, tyrkysový mech Sylvarie, hlína
      Aethelgardu, skála), dno jezera (písek), stromy a smrky (kůra, listí), obří strom (bělavá kůra, tyrkysové listí),
      kameny a kamenné díly staveb (skála). Modely: `meshkit.write_glb` umí `texture` + UV promítnutím ze tří stran.
      Nepoužité zatím: voda, mrak, slunce, úplněk, oheň, blesk, vítr, krystaly (efekty a obloha), sníh a led, láva.
- [x] A7 Svět Aethelgard (podle „Herní dokumentace: Svět Aethelgard“, nahradil Hraniční údolí Zlomu): kontinent 8 x 8 km
      v Azure Ocean – Verdant Canopy (západ, prastaré lesy, tisícileté stromy, elfí svatyně a ruiny), Frostfang Peaks
      (sever, štíty do 700 m, zamrzlé jezero), Ignis Scar (jih, čedič, sopky s krátery, lávové řeky – svítící povrch),
      Crystalarium (východ, terasy a obří krystaly, Stínová trhlina), Serpentine River (na úrovni moře – voda nikde
      nevisí ve vzduchu) s mosty. Členitá krajina (kopce, hřbety, údolí). Generátor `tools/aethelgard_world.py` →
      `Assets/Terrain/*.png`, `UI/aethelgard_map.jpg`, `eryndor/world_data.lua`. Klávesa **M** = mapa světa, minimapa
      v rohu, počasí podle regionu. Samotest bez proměnné = 22 záběrů regionů, noci, mapy a počasí. Engine ≥ 1.11.0.
- [x] A8 Azure Ocean a mořská monstra (podle „Herní dokumentace: Azurový oceán a mořská monstra“, kreslený styl):
      `tools/eryndor_sea.py` → `Assets/Models/sea/` – Abyssal Leviathan (3 kroužící v hlubině, na mapě M), Coral Siren
      (nepřítel u pobřeží), Razorfin Eel (nepřítel v řece Serpentine), zářící korály; černé obrysy (inverted hull,
      `meshkit.outline`). Oceán `style = "stylized"` (engine ≥ 1.12.0): pásma barev, kudrlinky pěny, svítící korály na dně.
- [x] A5 Realistické vykreslování (`world.environment{style = "realistic"}`): fyzikální PBR + SSAO, textury drsnosti,
      průsvitné materiály (engine, větev `claude/creature-forge-ice-dragon`). Eryndor ho zapíná v `on_start`.
      Pozn.: stávající krajina Eryndoru (stromy, tráva) je stylizovaná low-poly – pro plně realistický vzhled potřebuje
      nové assety.

- [x] A9 Rasy a tvorba postavy (podle „Rasy a tvorba postavy“, engine ≥ 1.13.0): 6 ras z Meshy napasovaných na kostru
      postav (76 animací) – `tools/eryndor_races.sh <engine/bin>` → `Assets/Models/races/*.glb`. Kamenný obr a Kočičí lid
      z obrázků dokumentace (`tools/races/*.png`), Víla tvar z textu (ve stoje) + textura podle obrázku, Člověk, Trpaslík
      a Elf vlastní z textu (obrázky připomínají skutečné herce). Tvorba postavy `eryndor/creator.lua` (rasa, povolání,
      jméno, výška, končetiny, ramena, svaly, hlava, barevný nádech, záře; náhled s animacemi), vzhled `eryndor/races.lua`.
      Ostatní testeři: `eryndor/presence.lua` (veřejný Realtime kanál `eryndor:fantasy:world`, vzhled v presence,
      poloha a akce broadcastem, jmenovky). Samotesty `VOXARIO_SELFTEST_ONLY=creator`, `=mp` (+ `VOXARIO_MP_ROLE=a|b`).

- [x] A10 Vlastní animace a čisté váhy (engine ≥ 1.14 / Motion Forge, `tools/motion` v enginu): žádné klipy z KayKit –
      rasy i lidské postavy a NPC mají 86 klipů enginu (chůze, běh, sprint s IK, boj, kouzla, bloky, úhyby, skoky,
      smrt…) ve stylu rasy, varianty `*_Staff` pro hůl, víla se vznáší a mává křídly (kosti `wing_l/r`). Klouby kostry
      napasované na modely (paže, nohy), váhy bez natahování sítě (`--reweight`). Kočičí lid nově z Meshy (sněžný
      levhart / zrzavý mourek), víla nově z Meshy. Shift = sprint, Ctrl = chůze. Výroba `tools/eryndor_races.sh`.

- [x] A11 Výbava z obrázku (Meshy, 10 kusů): dlouhý meč a štít + ocelový kyrys (člověk), válečné kladivo + kroužková
      košile (trpaslík), luk s toulcem + kožená vesta s kápí (elf), hůl s krystalem + hůlka (víla), kladivo + kožešinová
      vesta (obr), meč + dýka (kočičí lid). Zbraně `Models/gear/*.glb` (fit_prop.py), zbroje napasované na rasu
      (`*_<rasa>.glb`, fit_garment.py, `entity.equip`). V tvorbě postavy přepínač „Zbraně a zbroj rasy“.
      Štít a róba z obrázku zatím nevygenerované (došly kredity Meshy) – člověk má štít KayKit.

### C. Hra `game/voxario/Eryndor`
- [x] C1 Kostra projektu (game.vgame, main.lua, balení, samotest)
- [x] C2 Počáteční lokace „Hraniční údolí Zlomu“: terén, křišťálové jezero, les Sylvarie, tábor Aethelgardu, trhlina
- [x] C3 Obloha, den a noc, cyklus počasí
- [x] C4 Boj (4Story styl): zaměření cíle (Tab / klik), automatický útok, lišta dovedností 1–0 s cooldowny a globálním
      cooldownem, mana, sesílání s ukazatelem, agro a návrat nepřítele, čísla poškození, zkušenosti a úrovně, respawn
- [x] C5 HUD: rámeček hráče a cíle, lišta dovedností, ukazatel sesílání, minimapa, chat/log boje
- [x] C6 NPC z lore (Archivářka Lyrise jako průvodce), první úkol
- [x] C7 Snímky

### D. Launcher a vydání
- [x] D1 Kanál „fantasy“ v launcheru (vlastní složka `…-fantasy`, manifest `unity/latest-fantasy.json`)
- [x] D2 Workflow pro sestavení a nahrání Eryndoru do kanálu
- [x] D3 Vydání launcheru s novým kanálem

## Poznámky
- Rozpracovaná obnova Valorie: větev `copilot/valoria-restoration` v repozitáři hry a větev
  `copilot/valoria-rendering` v repozitáři enginu. Předchozí nepublikované sestavení není dostupné;
  podle logu vznikl nový ostrov na souřadnicích (3000, 2400), návrh mostu, brány, domů a hradu
  (`eryndor/valoria.lua`) a obousměrný portál k základně. Výškovou mapu i mapu regionů generuje
  `tools/aethelgard_world.py` s `tools/valoria_terrain.py`; modely generuje `tools/valoria_assets.py`.
  Generátory vyžadují NumPy, generátor terénu také Pillow. `VOXARIO_SELFTEST_ONLY=valoria` pořizuje
  záběry a ověřuje cíle portálů. Větev je **hrubý prototyp**, nikoli fotorealistické AAA:
  stavby a sochy jsou zástupné, první procedurální PBR kámen nestačí na cílový detail, ostatní materiály
  jsou zjednodušené a voda používá stávající renderer. Kámen se obnoví nástrojem z větve enginu:
  `python3 tools/content/stone_material.py <složka-hry>/Assets/Textures/valoria --seed 1337 --size 512`,
  potom `python3 tools/valoria_assets.py` ve složce Eryndor.
  Omítka domů se obnoví nástrojem z větve enginu
  `python3 tools/content/plaster_material.py <složka-hry>/Assets/Textures/valoria --seed 1337 --size 512`
  před spuštěním generátoru modelů. Domy nyní mají omítku, kamennou podezdívku, uzavřené štíty,
  boční okna a podpěry markýz; stále jde o opakované procedurální zástupné modely.
  Hradní kámen se obnoví příkazem
  `python3 tools/content/stone_material.py <složka-hry>/Assets/Textures/valoria --size 1024 --seed 4301 --rows 16 --columns 8 --prefix castle --variation 0.6 --mortar 0.25`
  z větve enginu (od commitu `305d791`); pak znovu vygenerovat modely Valorie.
  Zadání: startovní město na ostrově; kamenný most a sochy, modrozlaté prapory, obchodní čtvrť
  s dlažbou a červenými/modrými střechami, hrad na útesu a gryfové; přirozené světlo, mlha
  a realistická voda. Následně je třeba vytvořit vlastní detailní assety a materiály, zlepšit vodu
  v enginu, doplnit život města, průběžně kontrolovat snímky a výkon. Sestavení ani vydání do
  Fantasy nelze považovat za hotové, dokud nejsou tyto požadavky ověřeny.
  Dlažba obchodní čtvrti je rozdělena na instancované 2m díly, každý podle vzorků skutečné výšky
  terénu; předchozí dlouhá rovná deska se do něj propadala. Kontrola ve hře potvrdila spojitou
  ulici, ale zůstávají viditelné schody, spáry a opakování textury – cílem má být skutečně
  přizpůsobený povrch a kvalitnější materiál. Ostrov má variabilnější obrys, mírné vyvýšeniny a
  pásy písku, hlíny a skály; zázemí města a výšky mimo jeho původní půdorys ostrova se zachovávají.
  Celkový záběr `v0-ostrov` však ukazuje prázdnou krajinu a zástupný hrad; domy, hrad i okolí
  zůstávají daleko od fotorealismu a potřebují kvalitní detailní assety a osídlení.
  Model hradu má okna, cimbuří, věžové římsy a průchod s otevřenými křídly vrat. Samotest ověřuje
  volný průchod a kolizi sousední stěny koulemi o poloměru hráče; záběry `v3b-pruceli-hradu` a
  `v3c-interier-hradu` ukazují novou texturu a provizorní vnitřek. Chybí detailní interiér,
  výbava a hotové materiály. Dlaždice v interiéru nahrazuje souvislá rovná podlaha a práh
  se samostatnou kolizí, umístěné nad vrcholy terénu včetně detailního šumu; dva nášlapy
  vyrovnávají vyšší práh. Přístupnost nebyla ověřena průchodem skutečné postavy.
  V samotestu po vstupu do světa opakovaně hlásí příkladový mod `SouradniceFPS` chybu
  formátování necelého čísla; jde o stávající problém mimo úpravu hradu.
  Větve enginu zahrnují volitelný experiment `style = "natural"`: tlumí drobné vlnky, kaustiky,
  rozptyl a pěnu a od commitu `2ecdb35` přibližně počítá lom a dráhu světla vodou; původní a
  stylizovaný režim zachovává. Commit `5a2ba34` upravuje odrazivost hladiny podle indexu lomu vody.
  Vývojový VoxarioPlayer se sestavil a snímky pláže i moře vznikly,
  voda však stále obsahuje nerealistické opakování a pásy a není fotorealistická. Výpočet neřeší
  skutečný průsečík lomeného paprsku s měnícím se dnem; nutno zkontrolovat další počasí, denní
  doby, hlubinu, podvodní pohled a výkon.
  Hra nový styl zatím nezapíná a nepoužívá tento vývojový engine. Průběžný experiment není
  důvodem měnit Fantasy manifest ani vydávat finální engine.
- Assety: `python3 tools/eryndor_nature.py` (krajina, stavby). Knihovna tvarů a zápisu GLB: `tools/meshkit.py`.
- Samotest: `tools/package-game.sh <engine/bin> <výstup>` a `Eryndor --selftest <složka>` (záběry lokace a počasí).
- Engine: `world.weather{rain, snow, storm, wind, wind_direction, instant}` (docs/LUA_API.md).
- Postavy: KayKit Adventurers (CC0, Kay Lousberg) – `Assets/Models/kaykit`, frakční varianty `python3 tools/kaykit_variants.py`.
- Boj: `eryndor/combat.lua` (povolání, dovednosti, nepřátelé), HUD `eryndor/hud.lua`, výprava `eryndor/quest.lua`, efekty `eryndor/fx.lua`.
- Samotesty: `VOXARIO_SELFTEST_ONLY=game` (výběr, boj, Lyrise), `=chars` (postavy), `=weather`, bez proměnné = lokace a počasí.
- Ovládání: WASD, Shift chůze, Space skok, pravé tlačítko kamera / klik na nepřítele = útok, levé = cíl, Tab cíl,
  R automatický útok, 1–5 dovednosti, F mluvit, Esc zrušit cíl.
- Realistické postavy: `ERYNDOR_MH_DIR=<složka s mpfb2 a mhsys> python3 tools/mh_build.py` (MakeHuman CC0: MPFB2 data
  `src/mpfb/data` z github.com/makehumancommunity/mpfb2 a `makehuman_system_assets_cc0.zip` z files.makehumancommunity.org).
  Tělo + morfy + kůže + oči/obočí/řasy/vlasy, kostra game_engine, brnění a oděvy na míru tělu (skořepiny z oblastí těla, panely
  sukní, plášť, tuhé nárameníky a helmy), animace přenesené z KayKit Knight.glb (76 klipů), úchyty zbraní handslot.r/l.
  Výstup `Assets/Models/humans/*.glb`. Test: `VOXARIO_SELFTEST_ONLY=humans VOXARIO_HUMANS=syl_knight_m,...`.
- Vydáno (2026-11-05): engine v1.9.0, Eryndor 0.1.0 v kanálu Fantasy (unity/latest-fantasy.json), launcher 0.7.0.
  Vydání: workflow `eryndor-game.yml` (engine_tag, version, publish, publish_launcher).
- Další kroky (návrhy): částice (A3), více lokací a výprav, ladění 4Story mechanik podle podkladů vlastníka.
- UI, optimalizace a voda (dokument „Herní dokumentace: UI, Optimalizace a Systém Vody“, Eryndor 0.7.0 / engine v1.16.0):
  HUD `eryndor/actionbar.lua` (kované rámečky postavy a cíle, plynulý úbytek životů/many se „stínem“ ztráty, akční lišta
  12 slotů 1–0, -, = s ikonou, klávesou a kruhovým zatměním obnovení, lektvary 9/0), stromy talentů `eryndor/talents.lua` +
  okno `eryndor/talentui.lua` (klávesa N; 3 větve × 4 úrovně, pasivní = čtverce, aktivní kouzla = kruhy na lištu 6–8,
  rozsvícené spojnice, požadované body a předpoklady), nastavení `eryndor/options.lua` (klávesa O; předvolby, stíny,
  textury, dohled, tráva, ořez, voda, mraky, DLSS/FSR s profily, FPS, VSync, okno – ukládá se), tvorba postavy:
  obličej (oči, rozestup, nos, čelist přes obličejové kosti), hex barvy, osvětlení scény (den / zlatá hodina / soumrak /
  noc + studiová světla). Ikony a rámečky: `python3 tools/eryndor_icons.py`. Oceán realistický (Gerstner, příliv,
  hloubkové zbarvení, měkká pěna). Samotesty `VOXARIO_SELFTEST_ONLY=voda|ui|oblicej`.
- Eryndor 0.8.0 (engine v1.17.0): plavání a potápění (`player.UpdateSwim`: hlubší voda než po hrudník = plave, nesahá na dno;
  Space nahoru, Ctrl / C dolů, pod vodou směr kamery), kyslík 30 s + ukazatel, tonutí (`combat.HurtPlayer`), podvodní mlha
  z enginu; efekty kouzel částicemi enginu (`eryndor/fx.lua`, živel dovednosti `combat.SkillFx`: oheň, mráz, arkána, blesk,
  léčení, svatost, jed, stín, jiskry; stopa střel, výbuchy, kruhy, aury, sesílání); ESC menu (`eryndor/menu.lua`: pokračovat,
  nastavení, doplňky, talenty, mapa, změna postavy, ukončit s potvrzením), doplňky (`eryndor/addons.lua`, Dokumenty/Eryndor/AddOns,
  mod.json + main.lua, API `eryndor.on/notify/player` + `ui`), klikatelná mikro lišta vpravo dole (`eryndor/widgets.lua`),
  zbroje obepnuté kolem trupu (fit_garment), větší zbraně obra. Samotesty `plavani`, `kouzla`, `ui` (menu, doplňky).
- Eryndor 0.9.0 (engine v1.18.0): průhledný kouř enginu – dýmající sopky (`world.lua`, smoke_dark s předehřátím, dosah 1400 m),
  kouř po ohnivých výbuších a pára po mrazivých kouzlech (`fx.lua`), kouzla jako měkké zářící částice; samotest `kouzla` (k8–k10).
- Fotorealistické PBR povrchy terénu (engine v1.19.0, větev `claude/happy-bardeen-psq6y3`, zatím nevydáno): všech 8 vrstev
  Aethelgardu (louky, lesní půda, pláže, skála, sníh, láva, čedič a popel, ametyst) z fotoskenů Poly Haven (CC0) –
  `python3 tools/terrain_pbr.py` stáhne 2k mapy do cache a sbalí `Assets/Textures/terrain/pbr/<vrstva>_albedo.jpg`
  (2048 px, zapečená okluze) a `_surface.png` (1024 px: normála RG, drsnost B, výška A). Láva = rozpraskaná skála se
  žhnoucími prasklinami, ametyst = přebarvená rozpraskaná skála; meshy.ai se nepoužívá. Engine: prolínání vrstev podle
  skutečné výšky, triplanární útesy, měřítko dlaždice na vrstvu (`scale`), vzdálené přemíchání proti opakování,
  anizotropní filtrování. Starší engine povrchové mapy ignoruje (jen barva). Samotest `VOXARIO_SELFTEST_ONLY=teren`
  (t1–t10: biomy zblízka, útesy, Valoria). Zbývá: tráva/kamínky jako 3D detail na zemi, mokrý písek u vody,
  vydání enginu 1.19 a přepnutí `engine_tag` v CI – až po schválení vlastníkem.
- Tekoucí láva (engine v1.19.0 `flowmap`, zatím nevydáno): `python3 tools/lava_flow.py` spočítá
  `Assets/Terrain/aethelgard_lava_flow.png` (RG = směr a rychlost, B = žár) – směr podél koryta ze strukturního tenzoru
  masky lávy, láva teče od kráteru (vzdálenost měřená korytem), rychlost podle spádu, v kráterech víří lávové jezero.
  Shader: pláty chladnoucí kůry se žhnoucími švy plují korytem, barva žáru podle teploty. Generátor terénu dělá lávové
  řeky, které místy mírně stoupají – láva tam teče pomalu „do kopce“; čistým řešením je monotónní dno koryt
  v `aethelgard_world.py`. Samotest `teren`: t11 (řeka zblízka), t12 (sopka v noci), t13 (24 snímků animace).
- Valoria – fotorealistické materiály staveb (zatím nevydáno): `python3 tools/valoria_pbr.py` stáhne fotoskeny Poly Haven
  (CC0) a uloží `Assets/Textures/valoria/pbr/<materiál>_{basecolor,normal,orm}.jpg` (1024 px); `tools/valoria_assets.py`
  je vloží do modelů s reálnou velikostí dlaždice: hrad = kvádrové zdivo (medieval_blocks_03), brána/most/sokly =
  kamenné zdivo, dlažba a podlaha hradu = kočičí hlavy, omítka, dubové trámy, břidlice, pálené tašky (řady podél
  hřebene díky `uv_swap`), lněné markýzy a prapory, mramor soch. Záběry před/po: `docs/screenshots/valoria`.
  Zbývá: tvary budov jsou stále jednoduché bloky (chybí geometrický detail – římsy, okenní ostění, trámové konce,
  zvlněné tašky), dlažba z 2m dílů má viditelné spáry a schody, interiér hradu je prázdný.
- Vydání Eryndor 0.10.0 (engine v1.19.0, schváleno vlastníkem 2026-11-12): fotorealistický terén (PBR fotoskeny), tekoucí láva,
  fotorealistické materiály Valorie; workflow `eryndor-game.yml` používá výchozí `engine_tag` v1.19.0.
- Výkon a plynulost (engine v1.21.0): měření `VoxarioPlayer --benchmark 25` (hra sama vstoupí do světa v předvolbě
  Ultra; `VOXARIO_BENCH_PRESET`, `VOXARIO_BENCH_PLACE`, `VOXARIO_BENCH_SET="detail=0,shadows=high"`,
  `VOXARIO_BENCH_RUN=1` = běh a otáčení kamery, `VOXARIO_BENCH_SHOT`), log vypíše čas GPU po průchodech.
  Ve Valorii: čas GPU snímku 3,4x kratší (terénní shader, early-Z, superdlaždice, stíny, světla), asynchronní
  nahrávání sítí a textur odstranilo záseky při pohybu. Postava: výška modelu z paprsku na skutečný povrch
  (most, dlažba) a plynule (dřív poskakovala mezi výškovou mapou a kolizí), teleport a start na horní povrch.
  Most hrdinů leží nad nejvyšším místem terénu (detail terénu ±0,45 m prorůstal mostovkou), ulice k němu stoupá.
- Obloukový most Valoria – hlavní ostrov (Eryndor 0.12.0): `python3 tools/valoria_skybridge.py` vygeneruje
  `Models/valoria/skybridge.glb` a `Scripts/eryndor/skybridge_data.lua` (osa po 10 m). Most navazuje na jižní konec
  Mostu hrdinů, stáčí se obloukem (poloměr 70 m) na západ a 1136 m dlouhým viaduktem s 32 pilíři a kamennými
  klenbami přes Azure Ocean vystoupá (max. 11 %, mírné klenutí nad mořem) na útes hlavního ostrova nad údolím
  Serpentine; konec mostovky se zanoří pod terén. Mostovka je vždy ≥ 0,55 m nad terénem (detail neprorůstá),
  kolize celého modelu, lucerny po 60 m (světlo v noci), pod mostem na souši nic neroste. Samotest `valoria`: v5–v7.
- Krajina AAA (Eryndor 0.13.0, engine v1.22.0):
  - Voda `style = "realistic"`: vlny na pixel bez aliasingu (pryč „kostičky“ z mřížky moře), fyzikální barva,
    krajková pěna. Záběry před/po: `docs/screenshots/voda-aaa`.
  - Tráva `world.grass`: trsy z fotoskenu `grass_medium_01` (`tools/eryndor_foliage.py`, karty s výřezem,
    materiál `foliage`) rostou hustě kolem kamery všude, kde je povrch „tráva“; ne na stavbách, mostech a cestách.
  - Stromy: listnáče (kůra `bark_brown_02`, koruna z karet větviček složených z fotek listů `island_tree_02`)
    a smrky (kůra `pine_bark`, karty jehličí `fir_tree_01`); engine kompenzuje alfu v mipmapách (v dálce neholé).
  - Cesty `world.road` (`tools/eryndor_roads.py`, A* po terénu, voda zakázaná mimo mosty): Královská cesta
    z obloukového mostu Valorie (strážnice, lucerny) přes kamenný most nad lávovou řekou k rozcestí u základny,
    odtud cesta k zamrzlému jezeru, lesní cesta přes Serpentine k elfí svatyni a Tisíciletému stromu,
    Popelavá stezka k Ignis Scar a Krystalová stezka k trhlině. Krajnice cest jsou ve splat mapách hlína.
  - Samotest `krajina` (k1–k10). Zbývá: mapa (M) zatím cesty nekreslí.
