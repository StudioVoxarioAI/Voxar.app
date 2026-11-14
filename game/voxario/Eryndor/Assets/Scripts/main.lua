-- Eryndor – testovací fantasy kanál (Voxario Studio Engine).
-- Svět Aethelgard (8 x 8 km) podle „Herní dokumentace: Svět Aethelgard“: Verdant Canopy, Frostfang Peaks,
-- Ignis Scar, Crystalarium, Serpentine River a Azure Ocean. Klávesa M = mapa světa.
local map = require("eryndor.map")
local world = require("eryndor.world")
local player = require("eryndor.player")
local combat = require("eryndor.combat")
local hud = require("eryndor.hud")
local quest = require("eryndor.quest")
local valoria = require("eryndor.valoria")

local deg, atan, sqrt = math.deg, math.atan, math.sqrt
local game_ = { built = false, camera = nil, shot = nil }
_G.eryndor = game_

local function lookFrom(x, y, z, tx, ty, tz)
    local cam = game_.camera or entity.find("Camera")
    game_.camera = cam
    local dx, dy, dz = tx - x, ty - y, tz - z
    entity.set_position(cam, x, y, z)
    entity.set_rotation(cam, deg(atan(dy, sqrt(dx * dx + dz * dz))), deg(atan(-dx, -dz)), 0)
end
game_.LookFrom = lookFrom

local function shot(name) game.screenshot(name .. ".png"); timer.sleep(0.3) end
local G = map.HeightAt

-- první spawn daného druhu nepřítele (samotest)
local function spawnOf(kind)
    for _, s in ipairs(map.Data.Spawns) do if s[1] == kind then return s[2], s[3] end end
    return map.Start.x, map.Start.z
end

-- ------------------------------------------------------------------ samotest: záběry lokace a počasí
local Selftest
function Selftest()
    local only = game.env and game.env("VOXARIO_SELFTEST_ONLY")
    game_.SetMode("test")
    if graphics and graphics.detail_density then graphics.detail_density(0.35) end   -- software Vulkan v CI
    _G.world.environment({ real_time = false, day_night = true, time_of_day = 15, day_length = 0 })
    _G.world.weather({ rain = 0, snow = 0, storm = 0, wind = 0.3, instant = true })
    timer.sleep(3)
    local function view(name, x, y, z, tx, ty, tz, wait)
        lookFrom(x, G(x, z) + y, z, tx, G(tx, tz) + ty, tz)
        timer.sleep(wait or 2.5)
        shot(name)
    end
    if only == "krajina" then
        -- tráva (world.grass), fotorealistické stromy, cesty a voda (engine ≥ 1.22)
        _G.world.environment({ time_of_day = 10.5 })
        _G.world.weather({ rain = 0, storm = 0, wind = 0.35, instant = true })
        if graphics and graphics.detail_density then graphics.detail_density(1.0) end
        local s, gt, lake = map.Start, map.Giant, map.FrozenLake
        timer.sleep(2)
        view("k1-louka-zblizka", s.x + 40, 1.7, s.z + 30, s.x + 70, 1.0, s.z + 60, 4)
        view("k2-louka-siroko", s.x + 20, 14, s.z - 40, s.x + 160, 2, s.z + 120, 4)
        view("k3-les-verdant", gt.x + 70, 2.0, gt.z + 50, gt.x + 20, 6, gt.z + 10, 4)
        view("k4-smrky", lake.x + 260, 3.0, lake.z + 200, lake.x + 120, 12, lake.z + 80, 4)
        lookFrom(3070, valoria.BridgeY + 5, 2700, 2960, valoria.BridgeY + 4, 2560); timer.sleep(4); shot("k5-valoria-trava")
        local sky = valoria.Skybridge.points
        local e = sky[#sky]
        view("k6-cesta-od-mostu", e[1] - 30, 3.0, e[2] - 10, e[1] - 140, 1, e[2] - 60, 4)
        -- cesty: královská cesta, most přes lávu, cesta k zamrzlému jezeru
        local roads = world.Roads
        local royal = roads[1].segments[1]
        local p1, p2 = royal[#royal - 25], royal[#royal - 15]
        view("k8-kralovska-cesta", p1[1], 2.2, p1[2], p2[1], 1.0, p2[2], 4)
        local lb = roads[1].lava_bridges[1]
        if lb then
            local mx, mz = (lb[1] + lb[3]) / 2, (lb[2] + lb[4]) / 2
            local dx, dz = lb[3] - lb[1], lb[4] - lb[2]
            local len = math.sqrt(dx * dx + dz * dz)
            local cx, cz = mx - dz / len * 110, mz + dx / len * 110   -- kolmo k mostu, z boku
            lookFrom(cx, math.max(G(cx, cz), G(mx, mz)) + 45, cz, mx, G(mx, mz) + 8, mz)
            timer.sleep(4); shot("k9-most-pres-lavu")
        end
        local lakeRoad = roads[2].segments[#roads[2].segments]
        local q1, q2 = lakeRoad[#lakeRoad - 12], lakeRoad[#lakeRoad]
        view("k10-cesta-k-jezeru", q1[1], 2.2, q1[2], q2[1], 1.0, q2[2], 4)
        _G.world.environment({ time_of_day = 18.4 })
        view("k7-louka-vecer", s.x + 40, 1.7, s.z + 30, s.x + 140, 2.0, s.z + 70, 4)
        game.log("SELFTEST hotovo")
        game.quit()
        return
    end
    if only == "teren" then
        -- fotorealistické PBR povrchy terénu (engine ≥ 1.19): každý biom zblízka a z výšky, útesy triplanárně
        _G.world.environment({ time_of_day = 10.5 })
        timer.sleep(2)
        -- VOXARIO_TEREN = vybrané záběry (např. "t4-utesy,t6-lava"), jinak všechny
        local pick = game.env and game.env("VOXARIO_TEREN")
        local function want(name) return not pick or pick:find(name, 1, true) ~= nil end
        local function tv(name, ...) if want(name) then view(name, ...) end end
        tv("t1-louka", -1824, 2.2, 228, -1800, 0.5, 250)
        tv("t2-lesni-puda", -2324, 2.0, -252, -2306, 0.3, -236)
        tv("t3-plaz", -780, 2.4, 504, -756, 0.0, 520)
        tv("t4-utesy", 141, 10, -1426, 84, 4, -1496)
        tv("t5-snih", 396, 2.5, -2628, 420, 1.0, -2606)
        _G.world.environment({ time_of_day = 19.2 })
        timer.sleep(1)
        tv("t6-lava", 284, 4.0, 1960, 306, 0.0, 1980)
        _G.world.environment({ time_of_day = 10.5 })
        tv("t7-cedic", 768, 2.6, 1884, 790, 0.5, 1906)
        tv("t8-ametyst", 2588, 2.4, -360, 2610, 0.5, -338)
        tv("t9-valoria", 3000, 3, 2620, 3000, 16, 2480)
        -- tekoucí láva: řeka ze sopky zblízka za soumraku, sopka s lávovými řekami v noci, animace toku
        if want("t11") or want("t12") or want("t13") then
            _G.world.environment({ time_of_day = 19.4 })
            timer.sleep(1)
            tv("t11-lava-reka", 402, 4, 2134, 440, 0.0, 2135)
            if want("t13") then
                for i = 1, 24 do
                    timer.sleep(0.2)
                    shot(string.format("t13-anim-%02d", i))
                end
            end
            _G.world.environment({ time_of_day = 21.0 })
            timer.sleep(1)
            tv("t12-lava-sopka", 720, 70, 2420, 330, 150, 2020)
            _G.world.environment({ time_of_day = 10.5 })
        end
        if want("t10-ostrov") then
            lookFrom(3670, 130, 3070, 3000, 16, 2400)
            timer.sleep(3)
            shot("t10-ostrov")
        end
        game.log("SELFTEST hotovo")
        game.quit()
        return
    end
    if only == "valoria" then
        local gateY = G(3000, 2165) + 2.0
        local passage = physics.spherecast(3000, gateY, 2183, 0.35, 0, 0, -1, 12)
        local wall = physics.spherecast(3006, gateY, 2183, 0.35, 0, 0, -1, 12)
        local floor = physics.spherecast(3008, valoria.KeepFloorY + 1, 2168, 0.1, 0, -1, 0, 1.5)
        assert(not passage, "castle entrance is obstructed")
        assert(wall, "castle wall collision is missing")
        assert(floor and floor.entity == valoria.KeepFloor, "castle floor collision is missing")
        assert(valoria.KeepFloorY - 0.4 - G(3000, 2181) <= 0.45, "castle steps are too high for the player")
        lookFrom(3670, 130, 3070, 3000, 16, 2400)
        timer.sleep(3)
        shot("v0-ostrov")
        view("v1-udoli-hrdinu", 3000, 3, 2620, 3000, 16, 2480)
        view("v2-obchodni-ctvrt", 3000, 5, 2455, 3000, 12, 2335)
        view("v2b-fasady-domu", 3002, 4, 2428, 2975, 4, 2400)
        view("v3-kralovsky-hrad", 3080, 35, 2300, 3000, 30, 2165)
        view("v3b-pruceli-hradu", 3000, 8, 2210, 3000, 12, 2165)
        view("v3c-interier-hradu", 3000, 2, 2176, 3008, 4, 2158)
        assert(valoria.NearPortal(valoria.CityPortal.x, valoria.CityPortal.z) == valoria.OutpostPortal)
        assert(valoria.NearPortal(valoria.OutpostPortal.x, valoria.OutpostPortal.z) == valoria.CityPortal)
        -- obloukový most na hlavní ostrov: mostovka nad mořem má kolizi a vede až na útes
        local sky = valoria.Skybridge.points
        for _, i in ipairs({ 2, math.floor(#sky / 2), #sky - 4 }) do
            local p = sky[i]
            local y = valoria.SkybridgeY(i)
            local hit = physics.raycast(p[1], y + 3, p[2], 0, -1, 0, 6)
            assert(hit and hit.entity == valoria.SkybridgeEntity and hit.point and math.abs(hit.point.y - y) < 0.6,
                "arched bridge deck collision is missing at point " .. i)
        end
        local mid = sky[math.floor(#sky / 2)]
        lookFrom(mid[1] + 260, 150, mid[2] + 330, mid[1], 40, mid[2])
        timer.sleep(3)
        shot("v5-obloukovy-most")
        lookFrom(3040, valoria.BridgeY + 6, 2600, 2900, valoria.BridgeY + 12, 2760)
        timer.sleep(2.5); shot("v6-most-z-valorie")
        local q = sky[#sky - 14]
        lookFrom(q[1] + 40, valoria.SkybridgeY(#sky - 14) + 8, q[2] + 30,
            sky[#sky][1], valoria.SkybridgeY(#sky), sky[#sky][2])
        timer.sleep(2.5); shot("v7-najezd-na-utes")
        game_.EnterWorld(1)
        timer.sleep(2)
        shot("v4-start")
        player.Teleport(valoria.OutpostPortal.x + 8, valoria.OutpostPortal.z)
        local x, _, z = player.Pos()
        assert(math.abs(x - (valoria.OutpostPortal.x + 8)) < 1 and math.abs(z - valoria.OutpostPortal.z) < 1)
        game.log("SELFTEST hotovo")
        game.quit()
        return
    end
    if only == "game" then
        -- výběr povolání, vstup, boj s vlky (Tab, automatický útok, dovednosti), rozhovor s Lyrise
        _G.world.environment({ time_of_day = 15.5 })
        game_.SetMode("select"); game_.Preview(1)
        timer.sleep(2.5); shot("g0-vyber")
        game_.EnterWorld(1)
        timer.sleep(2)
        local wx, wz = spawnOf("wolf")
        player.Teleport(wx - 7, wz - 7)
        player.cam.yaw = 45
        timer.sleep(2); shot("g1-hrac")
        combat.TabTarget(); combat.StartAttack()
        timer.sleep(3.5); shot("g2-boj")
        combat.UseSkill(1); timer.sleep(0.45); shot("g3-dovednost")
        timer.sleep(1.2); combat.UseSkill(3); timer.sleep(0.5); shot("g4-vir-cepele")
        timer.sleep(5); shot("g5-boj-dal")
        player.Teleport(map.Lyrise.x + 1.5, map.Lyrise.z - 2.5)
        player.cam.yaw = -20
        timer.sleep(1.5); quest.Talk(); timer.sleep(0.6); shot("g6-lyrise")
        quest.dialog = nil
        -- mág u trhliny
        game_.Reset()
        game_.EnterWorld(2)
        local cx, cz = spawnOf("cultist")
        player.Teleport(cx - 10, cz - 6); player.cam.yaw = 60
        timer.sleep(2)
        combat.TabTarget(); combat.UseSkill(1)
        timer.sleep(0.8); shot("g7-mag-sesilani")
        timer.sleep(2.5); shot("g8-mag-boj")
        -- rytíř proti lávovému pavoukovi (Creature Forge) na popelavém návrší
        game_.Reset()
        game_.EnterWorld(1)
        local sx, sz = spawnOf("spider")
        player.Teleport(sx - 8, sz - 8); player.cam.yaw = 45
        timer.sleep(2.5); shot("g9-lavovy-pavouk")
        combat.TabTarget(); combat.StartAttack()
        timer.sleep(3.0); shot("g10-boj-s-pavoukem")
        combat.UseSkill(1); timer.sleep(0.5); shot("g11-uder-zridla-pavouk")
        timer.sleep(3.5); shot("g12-pavouk-utoci")
        -- ledový drak (elitní, Creature Forge): řev při zahlédnutí, boj
        game_.Reset()
        game_.EnterWorld(3)
        local dx, dz = spawnOf("dragon")
        player.Teleport(dx - 12, dz + 10); player.cam.yaw = -50
        timer.sleep(2.5); shot("g13-ledovy-drak")
        combat.TabTarget(); combat.StartAttack()
        timer.sleep(1.2); shot("g14-drak-rve")
        timer.sleep(3.0); shot("g15-boj-s-drakem")
        combat.UseSkill(1); timer.sleep(0.5); shot("g16-drak-utok")
        game.log("SELFTEST hotovo")
        game.quit()
        return
    end
    if only == "ui" then
        -- rozhraní podle Technického blueprintu: tvorba postavy (obličej, osvětlení), HUD a akční lišta s dobou obnovení,
        -- strom talentů, nastavení
        local races = require("eryndor.races")
        local cr = game_.Creator
        local talents = require("eryndor.talents")
        local talentui = require("eryndor.talentui")
        local options = require("eryndor.options")
        _G.world.environment({ time_of_day = 15 })
        game_.SetMode("select"); cr.Show()
        cr.a = races.Default("elf"); cr.a.name = "Lyriel"; cr.a.cls = 2
        cr.a.eyes, cr.a.nose, cr.a.jaw = 1.3, 0.8, 0.9
        cr.rebuild = true; cr.forceTab, cr.tab = "face", "face"
        timer.sleep(3); shot("u1-tvorba-oblicej")
        cr.forceTab, cr.tab = "look", "look"
        cr.light.mode = 4; cr.light.time = 23.0; cr.ApplyLight()
        timer.sleep(2.5); shot("u2-tvorba-noc-studio")
        cr.light.mode = 2; cr.light.time = 18.2; cr.ApplyLight()
        timer.sleep(2); shot("u3-tvorba-zlata-hodina")
        game_.EnterWorld()
        _G.world.environment({ time_of_day = 14 })
        local wx, wz = spawnOf("wolf")
        player.Teleport(wx - 7, wz - 7); player.cam.yaw = 45
        local s = combat.me
        s.level = 6
        talents.Apply(s)
        local tree = talents.Tree(s.class.id)
        for _, id in ipairs({ "m_chill", "m_chill", "m_chill", "m_frostbite", "m_frostbite", "m_frostbite", "t_mage_nova", "m_focus" }) do
            talents.Learn(s, talents.Find(tree, id))
        end
        timer.sleep(2)
        combat.TabTarget(); combat.UseSkill(2); timer.sleep(0.4)
        combat.UsePotion("hp")
        timer.sleep(1.2); shot("u4-hud-akcni-lista")
        timer.sleep(2.0); combat.UseSkill(6); timer.sleep(1.0); shot("u5-hud-talent-na-liste")
        talentui.open = true
        timer.sleep(0.6); shot("u6-strom-talentu")
        talentui.open = false
        options.Load(); options.open = true
        timer.sleep(0.6); shot("u7-nastaveni")
        options.open = false
        game_.Menu.open = true
        timer.sleep(0.6); shot("u8-esc-menu")
        game_.Menu.confirm = { title = "Ukončit hru", text = "Opravdu chceš ukončit Eryndor?", icon = "m_quit", fn = function() end }
        timer.sleep(0.5); shot("u9-potvrzeni")
        game_.Menu.open, game_.Menu.confirm = false, nil
        game_.Addons.Load(); game_.Addons.open = true
        timer.sleep(0.8); shot("u10-doplnky")
        game_.Addons.open = false
        timer.sleep(0.5); shot("u11-doplnek-bezi")
        game.log("DOPLNKY: " .. #game_.Addons.list)
        game.log("SELFTEST hotovo")
        game.quit()
        return
    end
    if only == "oblicej" then
        -- obličejové kosti (oči, nos, čelist): vlevo výchozí, vpravo upravené posuvníky
        _G.world.environment({ time_of_day = 13 })
        local list = {}
        for p in (game.env("VOXARIO_MODELS") or "Models/races/clovek.glb"):gmatch("[^,]+") do list[#list + 1] = p end
        local bx, bz = map.Start.x - 24, map.Start.z - 3
        local n = 0
        for _, path in ipairs(list) do
            local a = _G.world.spawn(path, bx - 0.45, G(bx, bz), bz, { yaw = 180 })
            local b = _G.world.spawn(path, bx + 0.45, G(bx, bz), bz, { yaw = 180 })
            anim.play(a, "Idle", 0, true); anim.play(b, "Idle", 0, true)
            entity.bone_scale(b, "eye_l", 1.35, 1.35, 1.35, false); entity.bone_scale(b, "eye_r", 1.35, 1.35, 1.35, false)
            entity.bone_scale(b, "nose", 1.45, 1.45, 1.45, false); entity.bone_scale(b, "jaw", 1.3, 1.0, 1.15, false)
            timer.sleep(2.5)
            local hy = G(bx, bz) + 1.75
            lookFrom(bx, hy, bz - 1.4, bx, hy - 0.03, bz)
            timer.sleep(0.6); n = n + 1; shot(string.format("f%02d", n))
            entity.destroy(a); entity.destroy(b)
        end
        game.log("SELFTEST hotovo")
        game.quit()
        return
    end
    if only == "kouzla" then
        -- efekty kouzel: všechny živly vedle sebe (výbuch, kruh, aura, střela), pak mág a rytíř v boji
        local fx = require("eryndor.fx")
        _G.world.environment({ time_of_day = 19.2 })
        _G.world.weather({ rain = 0, storm = 0, wind = 0.2, instant = true })
        local bx, bz = map.Start.x - 30, map.Start.z - 6
        local els = { "fire", "frost", "arcane", "lightning", "heal", "holy", "poison", "shadow", "spark" }
        timer.sleep(2)
        for i, e in ipairs(els) do
            local x = bx + (i - 5) * 3.2
            _G.world.particles(x, G(x, bz) + 0.4, bz, { preset = e, duration = 6, radius = 0.35 })
        end
        lookFrom(bx, G(bx, bz) + 3.2, bz - 16, bx, G(bx, bz) + 1.0, bz)
        timer.sleep(1.4); shot("k1-zivly")
        for i, e in ipairs(els) do
            local x = bx + (i - 5) * 3.2
            fx.Impact(x, G(x, bz) + 1.6, bz, e, 1.2)
        end
        timer.sleep(0.25); shot("k2-vybuchy")
        timer.sleep(3)
        fx.Burst(bx - 5, bz + 2, 4, { 0.6, 0.9, 1.0 }, "frost")
        fx.Burst(bx + 5, bz + 2, 4, { 1.0, 0.5, 0.2 }, "fire")
        timer.sleep(0.3); shot("k3-mrazivy-kruh-a-meteor")
        timer.sleep(1.5)
        fx.Aura(bx - 3, bz, { 0.4, 1.0, 0.8 }, "heal")
        fx.Aura(bx + 3, bz, { 1.0, 0.9, 0.5 }, "holy")
        timer.sleep(0.6); shot("k4-leceni-a-pozehnani")
        timer.sleep(2)
        -- mág v boji
        _G.world.environment({ time_of_day = 15.5 })
        game_.EnterWorld(2)
        local cx, cz = spawnOf("cultist")
        player.Teleport(cx - 9, cz - 6); player.cam.yaw = 60; player.cam.distance = 6
        timer.sleep(2)
        combat.TabTarget(); combat.UseSkill(1)
        timer.sleep(0.9); shot("k5-mag-sesilani")
        timer.sleep(0.75); shot("k6-aetheriova-strela")
        timer.sleep(1.5); combat.me.mp = combat.me.maxmp; combat.me.gcd = 0
        combat.UseSkill(2)
        timer.sleep(0.25); shot("k7-mrazivy-kruh")
        -- kouř: průhledné předvolby vedle sebe, táborák (oheň + kouř), dýmající sopka
        game_.Reset()
        game_.freeCam = true
        _G.world.environment({ time_of_day = 14 })
        local sx, sz = map.Start.x - 30, map.Start.z - 6
        for i, e in ipairs({ "smoke", "smoke_dark", "steam", "dust", "mist" }) do
            local x = sx + (i - 3) * 5
            _G.world.particles(x, G(x, sz) + 0.3, sz, { preset = e, duration = 30 })
        end
        _G.world.particles(sx, G(sx, sz + 8) + 0.2, sz + 8, { preset = "fire", radius = 0.3 })
        _G.world.particles(sx, G(sx, sz + 8) + 1.0, sz + 8, { preset = "smoke", rate = 10, prewarm = 4 })
        lookFrom(sx, G(sx, sz) + 3.0, sz - 14, sx, G(sx, sz) + 2.2, sz)
        timer.sleep(4); shot("k8-koure")
        lookFrom(sx + 4, G(sx, sz + 8) + 1.6, sz + 3, sx, G(sx, sz + 8) + 1.6, sz + 8)
        timer.sleep(1); shot("k9-taborak")
        local v = map.Data.Volcanoes and map.Data.Volcanoes[1]
        if v then
            local vy = G(v.x, v.z)
            _G.world.weather({ rain = 0, storm = 0, instant = true })
            lookFrom(v.x - 420, vy + 60, v.z - 420, v.x, vy + 140, v.z)
            timer.sleep(6); shot("k10-sopka")
        end
        game.log("SELFTEST hotovo")
        game.quit()
        return
    end
    if only == "plavani" then
        -- plavání u hladiny, potápění, mlha pod vodou, kyslík (hráč v hluboké vodě u pobřeží)
        _G.world.environment({ time_of_day = 13.5 })
        _G.world.weather({ rain = 0, storm = 0, wind = 0.35, instant = true })
        game_.EnterWorld(1)
        timer.sleep(2)
        local sx, sz
        for _, sp in ipairs(map.Data.Spawns) do if sp[1] == "siren" then sx, sz = sp[2], sp[3]; break end end
        local dl = math.sqrt(sx * sx + sz * sz)
        local ux, uz = sx / dl, sz / dl      -- od pevniny ven na moře
        local px, pz = sx, sz
        for k = 0, 600, 4 do
            local x, z = sx + ux * k, sz + uz * k
            if map.SeaY - G(x, z) > 6 then px, pz = x, z; break end
        end
        player.Teleport(px, pz)
        player.cam.yaw = math.deg(math.atan(ux, uz)) + 150; player.cam.pitch = 14; player.cam.distance = 6
        timer.sleep(3); shot("p1-slapani-vody")
        combat.moveTo = { px + ux * 60, pz + uz * 60 }
        timer.sleep(2.5); shot("p2-kraul")
        player.cam.yaw = math.deg(math.atan(ux, uz)) + 90
        timer.sleep(1.2); shot("p3-kraul-z-boku")
        if player.swim then player.swim.dive = true; player.swim.y = player.swim.y - 3.5 end
        player.cam.pitch = 8; player.cam.distance = 4.5
        for _ = 1, 20 do
            if player.swim then player.swim.dive = true; player.swim.vy = -0.6 end
            timer.sleep(0.1)
        end
        local cx, cy, cz = player.Pos()
        game.log(string.format("PLAVANI: swim=%s dive=%s kyslik=%.1f y=%.2f hladina=%.2f dno=%.2f", tostring(player.swim ~= nil),
            tostring(player.swim and player.swim.dive), player.oxygen, cy, _G.world.water_height(cx, cz) or -1, G(cx, cz)))
        shot("p4-pod-vodou")
        combat.moveTo = nil
        player.oxygen = 4
        timer.sleep(1.5); shot("p5-kyslik-dochazi")
        game.log(string.format("PLAVANI: kyslik=%.1f hp=%d", player.oxygen, combat.me and combat.me.hp or -1))
        game.log("SELFTEST hotovo")
        game.quit()
        return
    end
    if only == "voda" then
        -- realistická voda: pláž jako referenční snímek, západ slunce, vítr a bouře, noc, řeka; výška vln na CPU
        local races = require("eryndor.races")
        _G.world.environment({ time_of_day = 13.5 })
        _G.world.weather({ rain = 0, storm = 0, wind = 0.45, instant = true })
        -- pláž: od sirény (mělčina u pobřeží) směrem ke středu kontinentu, první místo těsně nad hladinou
        local sx, sz
        for _, sp in ipairs(map.Data.Spawns) do if sp[1] == "siren" then sx, sz = sp[2], sp[3]; break end end
        local dl = math.sqrt(sx * sx + sz * sz)
        local ux, uz = -sx / dl, -sz / dl
        local bx, bz = sx, sz
        for k = 1, 400 do
            local x, z = sx + ux * k, sz + uz * k
            if G(x, z) > map.SeaY + 0.6 then bx, bz = x + ux * 3, z + uz * 3; break end
        end
        local a = races.Default("kocka")
        local hero = races.Spawn(a, bx, G(bx, bz), bz, { yaw = math.deg(math.atan(-ux, -uz)) })
        anim.play(hero, "Idle", 0, true)
        local function beach(name, wait)
            lookFrom(bx + ux * 4.5, G(bx, bz) + 2.4, bz + uz * 4.5, bx - ux * 30, map.SeaY, bz - uz * 30); timer.sleep(wait or 2.5); shot(name)
        end
        timer.sleep(3)
        beach("w1-plaz-jako-reference", 3)
        lookFrom(bx + ux * 2 + uz * 8, G(bx + ux * 2 + uz * 8, bz + uz * 2 - ux * 8) + 2.5, bz + uz * 2 - ux * 8, bx - ux * 6, map.SeaY, bz - uz * 6); timer.sleep(2); shot("w2-prilivova-pena")
        lookFrom(bx - ux * 15, map.SeaY + 3, bz - uz * 15, bx - ux * 120, map.SeaY, bz - uz * 120); timer.sleep(2); shot("w3-otevrene-more")
        local h = _G.world.water_height(bx - ux * 15, bz - uz * 15)
        game.log(string.format("VODA: výška hladiny na CPU = %.2f (klidná %.2f)", h or -999, map.SeaY))
        _G.world.environment({ time_of_day = 18.6 })
        beach("w4-zapad-slunce", 3)
        _G.world.weather({ wind = 1.0, rain = 0.6, storm = 0.4, instant = true })
        _G.world.environment({ time_of_day = 15 })
        lookFrom(bx - ux * 15, map.SeaY + 3, bz - uz * 15, bx - ux * 120, map.SeaY, bz - uz * 120); timer.sleep(3); shot("w5-vitr-boure")
        _G.world.weather({ wind = 0.3, rain = 0, storm = 0, instant = true })
        _G.world.environment({ time_of_day = 22.5 })
        beach("w6-noc", 3)
        _G.world.environment({ time_of_day = 12 })
        local riv = map.Data.River[math.floor(#map.Data.River * 0.45)]
        lookFrom(riv[1] + 25, 14, riv[2] - 20, riv[1], 0, riv[2]); timer.sleep(3); shot("w7-reka")
        game.log("SELFTEST hotovo")
        game.quit()
        return
    end
    if only == "snaps" then
        -- ladění pohybů: statické snímky klipů (VOXARIO_SNAPS = klip@fáze,...) ze 3/4 pohledu
        _G.world.environment({ time_of_day = 14.5 })
        local list = {}
        for p in (game.env("VOXARIO_MODELS") or ""):gmatch("[^,]+") do list[#list + 1] = p end
        local bx, bz = map.Start.x - 24, map.Start.z - 3
        local ids = {}
        for i, p in ipairs(list) do
            local x = bx + (i - (#list + 1) / 2) * 1.7
            ids[i] = _G.world.spawn(p, x, G(x, bz), bz, { yaw = 125 })
            local wl = game.env("VOXARIO_WEAPONS")
            if wl then
                local r, l = wl:match("([^,]*),?(.*)")
                require("eryndor.humans").Dress(ids[i], { right = r ~= "" and r or nil, left = l ~= "" and l or nil })
            end
        end
        local w = #list * 1.7
        timer.sleep(3)
        local n = 0
        for snap in (game.env("VOXARIO_SNAPS") or ""):gmatch("[^,]+") do
            for _, id in ipairs(ids) do anim.play(id, snap, 0, true, true) end
            n = n + 1
            lookFrom(bx + 0.3, G(bx, bz) + 1.1, bz - (1.6 + w * 0.55), bx, G(bx, bz) + 0.95, bz)
            timer.sleep(0.35); shot(string.format("s%02d_%s", n, snap:gsub("[@]", "-")))
        end
        game.log("SELFTEST hotovo")
        game.quit()
        return
    end
    if only == "models" then
        -- náhled modelů vedle sebe (VOXARIO_MODELS = cesty oddělené čárkou): klid zepředu, zezadu, chůze, běh, útok
        _G.world.environment({ time_of_day = 15.5 })
        local list = {}
        for p in (game.env("VOXARIO_MODELS") or ""):gmatch("[^,]+") do list[#list + 1] = p end
        local bx, bz = map.Start.x - 24, map.Start.z - 3
        local ids = {}
        for i, p in ipairs(list) do
            local x = bx + (i - (#list + 1) / 2) * 1.6
            ids[i] = _G.world.spawn(p, x, G(x, bz), bz, { yaw = 180 })
        end
        local w = #list * 1.6
        local function cam(name, dz, t)
            lookFrom(bx, G(bx, bz) + 1.25, bz + dz * (1.6 + w * 0.55), bx, G(bx, bz) + 1.0, bz); timer.sleep(t or 0.4); shot(name)
        end
        timer.sleep(3)
        local function all(clip, yaw, loop)
            for _, id in ipairs(ids) do entity.set_rotation(id, 0, yaw, 0); anim.play(id, clip, 0, loop ~= false) end
        end
        cam("p1-predek", -1, 1)
        all("Idle", 0); cam("p2-zezadu", -1, 0.6)
        all("Walking_A", 90); cam("p3-chuze", -1, 0.35)
        all("Running_A", 90); cam("p4-beh", -1, 0.25)
        all("Running_B", 90); cam("p5-sprint", -1, 0.2)
        all("2H_Melee_Idle", 150); cam("p6-bojovy-postoj", -1, 0.8)
        all("1H_Melee_Attack_Chop", 150, false); cam("p7-utok", -1, 0.45)
        all("Spellcast_Shoot", 150, false); cam("p8-kouzlo", -1, 0.6)
        all("Walking_A", 150); cam("p9-chuze-zepredu", -1, 0.5)
        game.log("SELFTEST hotovo")
        game.quit()
        return
    end
    if only == "creator" then
        -- tvorba postavy: všechny rasy, tvar těla, nádech a záře, animace
        local races = require("eryndor.races")
        local cr = game_.Creator
        _G.world.environment({ time_of_day = 16 })
        game_.SetMode("select"); cr.Show()
        local n = 0
        local function set(r, tab, fn)
            cr.a = races.Default(r); cr.a.name = "Tester"; cr.rebuild = true
            if fn then fn(cr.a) end
            cr.forceTab, cr.tab = tab, tab
            timer.sleep(2.5)
        end
        local function snap(name) n = n + 1; shot(string.format("c%02d-%s", n, name)) end
        for _, r in ipairs(races.Order) do
            set(r, "race"); snap(r)
            cr.rot = 150; timer.sleep(0.8); snap(r .. "-zezadu"); cr.rot = 0
        end
        set("clovek", "body", function(a) a.height, a.shoulders, a.muscle, a.limbs = 1.15, 1.25, 1.28, 1.1 end); snap("telo-mohutne")
        set("clovek", "body", function(a) a.height, a.shoulders, a.muscle, a.limbs = 0.85, 0.85, 0.82, 0.9 end); snap("telo-stihle")
        set("vila", "look", function(a) a.glow, a.glowColor = 0.8, races.Hex("#b06cff") end); snap("vzhled-zare")
        set("obr", "look", function(a) a.tint, a.tintAmount = races.Hex("#d8e8ff"), 0.7 end); snap("vzhled-nadech")
        set("elf", "race"); cr.Pose("Spellcast_Shoot"); timer.sleep(0.6); snap("animace-kouzlo")
        set("trpaslik", "race"); cr.Pose(combat.Classes[1].skills[1].anim); timer.sleep(0.5); snap("animace-utok")
        set("kocka", "race"); cr.Pose("Running_A"); timer.sleep(0.5); snap("animace-beh")
        game.log("SELFTEST hotovo")
        game.quit()
        return
    end
    if only == "mp" then
        -- dva testeři naráz (dvě instance hry): VOXARIO_MP_ROLE = a | b
        local races = require("eryndor.races")
        local presence = require("eryndor.presence")
        local role = game.env("VOXARIO_MP_ROLE") or "a"
        _G.world.environment({ time_of_day = 15.5 })
        game_.SetMode("select")
        local cr = game_.Creator
        cr.Load()
        cr.a = races.Default(role == "a" and "obr" or "vila")
        cr.a.name = role == "a" and "Tester Obr" or "Testerka Víla"
        cr.a.cls = role == "a" and 1 or 2
        game_.EnterWorld()
        local S = map.Start
        if role == "a" then
            player.Teleport(S.x + 4, S.z - 6)
            for i = 1, 60 do   -- chodí sem a tam a útočí
                timer.sleep(0.5)
                player.Teleport(S.x + 4 + math.sin(i * 0.3) * 2, S.z - 6)
                if i % 8 == 0 then player.Action("1H_Melee_Attack_Chop", 0.9) end
            end
        else
            player.Teleport(S.x + 1, S.z - 1)
            player.cam.yaw = 160
            local t = 0
            while presence.count == 0 and t < 40 do timer.sleep(0.5); t = t + 0.5 end
            game.log("MP: ostatních hráčů = " .. presence.count)
            timer.sleep(3); shot("m1-dalsi-tester")
            local o
            for _, v in pairs(presence.others) do o = v end
            if o then
                lookFrom(o.pos[1] - 3, G(o.pos[1], o.pos[2]) + 1.8, o.pos[2] + 3.5, o.pos[1], G(o.pos[1], o.pos[2]) + 1.1, o.pos[2])
                player.inputEnabled = false
                game_.freeCam = true
                timer.sleep(1.5); shot("m2-tester-zblizka")
                timer.sleep(2.5); shot("m3-tester-utok")
            end
        end
        game.log("SELFTEST hotovo")
        game.quit()
        return
    end
    if only == "spider" or only == "dragon" then
        -- tvor z Creature Forge zblízka: klid, chůze, útok, smrt, ve dne a v noci
        combat.SpawnAll()
        local sp
        for _, m in ipairs(combat.mobs) do if m.kind == only then sp = m; break end end
        if only == "dragon" then
            local x, z = sp.x, sp.z
            local function at(name, dx, dy, dz, ty, wait)
                lookFrom(x + dx, G(x, z) + dy, z + dz, x, G(x, z) + ty, z); timer.sleep(wait or 1.5); shot(name)
            end
            entity.set_rotation(sp.id, 0, 200, 0)
            at("d1-drak", -6.5, 3.2, -7.5, 2.2, 3)
            at("d2-drak-bok", -9.5, 2.6, 1.5, 2.2)
            at("d3-drak-hlava", -2.4, 4.0, -4.8, 3.6)
            anim.play(sp.id, "Roar", 0.1, false, true); at("d4-rev", -6.5, 3.2, -7.5, 2.4, 0.8)
            anim.play(sp.id, "Flap", 0.1, true, true); at("d5-kridla", -6.5, 3.2, -7.5, 2.4, 0.45)
            anim.play(sp.id, "Attack", 0.05, false, true); at("d6-utok", -6.5, 3.2, -7.5, 2.2, 0.62)
            anim.play(sp.id, "Idle", 0.1, true, true)
            _G.world.weather({ snow = 0.8, wind = 0.5, instant = true })
            at("d7-snezeni", -6.5, 3.2, -7.5, 2.2, 2)
            _G.world.weather({ snow = 0, wind = 0.25, instant = true })
            _G.world.environment({ time_of_day = 22.5 })
            at("d8-drak-noc", -6.5, 3.2, -7.5, 2.2, 3)
            game.log("SELFTEST hotovo")
            game.quit()
            return
        end
        local x, z = sp.x, sp.z
        entity.set_rotation(sp.id, 0, 215, 0)
        local function at(name, dx, dy, dz, wait) lookFrom(x + dx, G(x, z) + dy, z + dz, x, G(x, z) + 0.7, z); timer.sleep(wait or 1.5); shot(name) end
        at("s1-pavouk", -3.6, 1.8, -3.4, 3)
        at("s2-pavouk-bok", -4.4, 1.4, 0.6)
        at("s3-pavouk-oci", -1.4, 1.0, -2.0)
        anim.play(sp.id, "Walk", 0.1, true, true); at("s4-chuze", -3.6, 1.8, -3.4, 0.5)
        anim.play(sp.id, "Attack", 0.05, false, true); at("s5-utok", -3.6, 1.8, -3.4, 0.42)
        anim.play(sp.id, "Death", 0.1, false, true); at("s6-smrt", -3.6, 1.8, -3.4, 1.6)
        anim.play(sp.id, "Idle", 0.1, true, true)
        _G.world.environment({ time_of_day = 22.5 })
        at("s7-pavouk-noc", -3.6, 1.8, -3.4, 3)
        at("s8-hnizdo-noc", -14, 6, -14, 1.5)
        game.log("SELFTEST hotovo")
        game.quit()
        return
    end
    if only == "humans" then
        -- realistické postavy (MakeHuman CC0) v animacích přenesených z KayKitu
        _G.world.environment({ time_of_day = 15.5 })
        local list = game.env("VOXARIO_HUMANS") or "test_male"
        local ids = {}
        local bx, bz = map.Start.x + 6, map.Start.z - 8
        local n = 0
        for name in list:gmatch("[^,]+") do n = n + 1 end
        local i = 0
        local looks = { syl_knight_m = { right = "sword", left = "shield" }, syl_mage_f = { right = "staff" },
                        aeth_heavy_m = { right = "sword2", helm = true }, aeth_engineer_f = { right = "crossbow", left = "dagger" },
                        cultist_m = { right = "dagger", left = "dagger" }, crusher = { right = "axe2" }, lyrise = { left = "book" } }
        for name in list:gmatch("[^,]+") do
            i = i + 1
            local x = bx + (i - (n + 1) / 2) * 1.4
            ids[#ids + 1] = require("eryndor.humans").Spawn(name, x, G(x, bz), bz, looks[name] or {})
        end
        lookFrom(bx + 0.6, G(bx, bz) + 1.45, bz + 2.2 + n * 0.9, bx, G(bx, bz) + 1.0, bz)
        timer.sleep(3)
        local function all(clip, t, name)
            for _, id in ipairs(ids) do anim.play(id, clip, 0, not clip:find("Death")) end
            timer.sleep(t); shot(name)
        end
        all("Idle", 1.0, "h1-klid")
        all("Walking_A", 0.3, "h2-chuze")
        all("1H_Melee_Attack_Chop", 0.45, "h3-sek")
        all("2H_Melee_Attack_Spin", 0.5, "h4-rotace")
        all("Spellcasting", 0.5, "h5-kouzlo")
        all("Block", 0.4, "h6-blok")
        lookFrom(bx + 3.2, G(bx, bz) + 1.3, bz + 0.4, bx, G(bx, bz) + 1.0, bz)
        all("Running_A", 0.25, "h7-beh-bok")
        lookFrom(bx + 0.25, G(bx, bz) + 1.72, bz + 0.85, bx, G(bx, bz) + 1.62, bz)
        all("Idle", 0.5, "h8-oblicej")
        game.log("SELFTEST hotovo")
        game.quit()
        return
    end
    if only ~= "weather" then
        local S, Gi, Sh, R, L = map.Start, map.Giant, map.Shrine, map.Rift, map.DragonLair
        local V1 = map.Data.Volcanoes[1]
        local riv = map.Data.River[math.floor(#map.Data.River * 0.45)]
        local br = map.Data.Bridges[2]
        view("01-zakladna", S.x - 34, 12, S.z + 30, map.Tower.x, 6, map.Tower.z, 5)
        view("02-verdant-canopy", Gi.x + 150, 40, Gi.z + 120, Gi.x, 20, Gi.z, 4)
        view("03-tisicilety-strom", Gi.x + 34, 5, Gi.z + 26, Gi.x, 16, Gi.z, 3)
        view("04-elfi-svatyne", Sh.x + 26, 6, Sh.z + 22, Sh.x, 3, Sh.z, 3)
        view("05-serpentine-most", br.x + 90, 22, br.z + 70, br.x, 2, br.z, 4)
        view("06-serpentine-reka", riv[1] + 160, 45, riv[2] - 120, riv[1], 0, riv[2], 3)
        view("07-frostfang-peaks", L.x + 30, 30, L.z + 220, L.x, 120, L.z - 400, 4)
        view("08-zamrzle-jezero", L.x + 40, 12, L.z + 40, map.FrozenLake.x, 0, map.FrozenLake.z, 3)
        view("09-ignis-sopka", V1.x + 520, 40, V1.z - 520, V1.x, 140, V1.z, 4)
        view("10-lavove-reky", V1.x + 60, 70, V1.z + 200, V1.x, 20, V1.z + 500, 3)
        view("11-crystalarium", R.x - 110, 30, R.z + 90, R.x, 8, R.z, 4)
        view("12-stinova-trhlina", R.x - 22, 6, R.z + 16, R.x, 3, R.z, 3)
        view("13-pobrezi-ocean", -3000, 30, 1200, -3600, 0, 900, 3)
        view("14-vyhled-kontinent", S.x + 400, 900, S.z + 1900, S.x, 0, S.z - 600, 5)
        _G.world.environment({ time_of_day = 22.5 })
        view("15-noc-crystalarium", R.x - 110, 30, R.z + 90, R.x, 8, R.z, 3)
        view("16-noc-ignis", V1.x + 520, 40, V1.z - 520, V1.x, 140, V1.z, 3)
        view("17-noc-zakladna", S.x - 34, 12, S.z + 30, map.Tower.x, 6, map.Tower.z, 3)
        -- Azure Ocean a mořská monstra (kreslený styl)
        local function firstMob(kind)
            for _, sp in ipairs(map.Data.Spawns) do if sp[1] == kind then return sp[2], sp[3] end end
        end
        local lev = world.Leviathans[1]
        _G.world.environment({ time_of_day = 14 })
        timer.sleep(1)
        -- pobřeží u první sirény: kamera nad mělčinou, pohled dál na moře (od středu kontinentu ven)
        local ox, oz = firstMob("siren")
        local dl = math.sqrt(ox * ox + oz * oz)
        local ux, uz = ox / dl, oz / dl
        local cx, cz = ox - ux * 60, oz - uz * 60
        lookFrom(cx, math.max(G(cx, cz), 0) + 14, cz, ox + ux * 400, 0, oz + uz * 400); timer.sleep(3); shot("23-azure-ocean")
        if lev then
            local lx, lz = lev.x, lev.z
            lookFrom(lx + 70, 26, lz + 60, lx, 0, lz); timer.sleep(2); shot("24-abyssal-leviathan")
        end
        combat.SpawnAll()
        local sx, sz = firstMob("siren")
        if sx then lookFrom(sx + 7, 2.6, sz + 6, sx, 1.4, sz); timer.sleep(2.5); shot("25-coral-siren") end
        local ex, ez = firstMob("eel")
        if ex then lookFrom(ex + 8, 4.5, ez + 7, ex, 0.2, ez); timer.sleep(2.5); shot("26-razorfin-eel") end
        _G.world.environment({ time_of_day = 22.5 })
        lookFrom(cx, math.max(G(cx, cz), 0) + 14, cz, ox + ux * 400, 0, oz + uz * 400); timer.sleep(3); shot("27-noc-zarici-koraly")
        if lev then lookFrom(lev.x + 70, 26, lev.z + 60, lev.x, 0, lev.z); timer.sleep(2); shot("28-noc-leviathan") end
        game_.Reset()
        -- mapa světa (M) a minimapa ve hře
        _G.world.environment({ time_of_day = 15 })
        game_.SetMode("select"); game_.EnterWorld(1)
        player.cam.yaw = 200
        timer.sleep(2.5); shot("18-hra-minimapa")
        game_.mapOpen = true
        timer.sleep(0.6); shot("19-mapa-sveta-M")
        game_.mapOpen = false
        game_.Reset()
        game_.SetMode("test")
    end
    -- počasí
    local S, L = map.Start, map.DragonLair
    _G.world.environment({ time_of_day = 14 })
    _G.world.weather({ rain = 0.9, wind = 0.6, instant = true })
    view("20-dest", S.x - 34, 12, S.z + 30, map.Tower.x, 6, map.Tower.z, 3)
    _G.world.weather({ rain = 1, storm = 1, wind = 1, instant = true })
    _G.world.environment({ time_of_day = 19.5 })
    for i = 1, 40 do   -- počkat na blesk
        timer.sleep(0.25)
        if _G.world.weather().flash > 0.4 then break end
    end
    view("21-bourka-blesk", S.x - 60, 25, S.z + 60, S.x, 3, S.z, 0.05)
    _G.world.weather({ rain = 0, storm = 0, snow = 1, wind = 0.4, instant = true })
    _G.world.environment({ time_of_day = 11 })
    view("22-snih-frostfang", L.x + 40, 12, L.z + 40, map.FrozenLake.x, 0, map.FrozenLake.z, 3)
    _G.world.weather({ snow = 0, wind = 0.25, instant = true })
    game.log("SELFTEST hotovo")
    game.quit()
end

-- ------------------------------------------------------------------ tvorba postavy a vstup do hry
local creator = require("eryndor.creator")
local actionbar = require("eryndor.actionbar")
local talentui = require("eryndor.talentui")
local options = require("eryndor.options")
local presence = require("eryndor.presence")
local widgets = require("eryndor.widgets")
local menu = require("eryndor.menu")
local addons = require("eryndor.addons")
local mode = "select"
game_.Creator = creator

local function showPreview() creator.Show() end

local function enterWorld()
    if not creator.a then creator.Load() end
    creator.Hide()
    local a = creator.a
    if a.name == "" then a.name = require("eryndor.races").Defs[a.race].name:match("^(%S+)") .. " Ozvěna" end
    local c = combat.Classes[a.cls] or combat.Classes[1]
    player.Create(c, valoria.Spawn, a)
    combat.SetupPlayer(c)
    combat.SpawnAll()
    quest.Spawn()
    local rname = require("eryndor.races").Defs[a.race].name
    combat.Log("Vítej ve Valorii, " .. a.name .. " (" .. rname .. ", " .. c.name .. "). Portál tě zavede k Lyrise.", { 0.8, 0.9, 1.0 })
    combat.Log("Tab cíl · R útok · 1–5 dovednosti · Shift sprint · Ctrl chůze · F mluvit · M mapa · pravé tlačítko kamera", { 0.7, 0.7, 0.7 })
    mode = "play"
    game_.mode = mode
    presence.Start(a)
end
game_.EnterWorld = function(i)
    if not creator.a then creator.Load() end
    if i then creator.a.cls = i end
    enterWorld()
end
game_.SetMode = function(m) mode = m; game_.mode = m end
game_.Preview = function(i)
    creator.Show()
    if i then creator.a.cls = i; creator.rebuild = true end
end
-- (samotest) zpět před vstup: hráč, nepřátelé a Lyrise pryč
game_.Reset = function()
    for _, m in ipairs(combat.mobs) do entity.destroy(m.id); if m.light then entity.destroy(m.light) end end
    combat.mobs, combat.target, combat.auto, combat.floats = {}, nil, false, {}
    if player.view then entity.destroy(player.view); entity.destroy(player.body); entity.destroy(player.lamp) end
    if quest.npc then entity.destroy(quest.npc); entity.destroy(quest.light) end
    player.dead = false
end

-- počasí se v údolí střídá (jasno, oblačno, déšť, bouřka; v noci občas mlha)
local nextWeather = 0
local lastRegion
local function weatherCycle()
    -- ve Frostfang Peaks sněží, v Ignis Scar je sucho (popel), jinde se počasí střídá
    local px, _, pz = player.Pos()
    local region = map.Region(px, pz)
    if region ~= lastRegion then
        if region == "f" or region == "k" then _G.world.weather({ rain = 0, storm = 0, snow = 0.7, wind = 0.6 })
        elseif lastRegion == "f" or lastRegion == "k" then _G.world.weather({ snow = 0, wind = 0.3 }) end
        if region == "i" or region == "l" then _G.world.weather({ rain = 0, storm = 0, snow = 0 }) end
        lastRegion = region
        combat.Log("Vstupuješ: " .. map.RegionName(px, pz), { 1.0, 0.85, 0.45 })
    end
    if region == "f" or region == "k" or region == "i" or region == "l" then return end
    if game.time() < nextWeather then return end
    nextWeather = game.time() + 150 + math.random() * 150
    local r = math.random()
    if r < 0.45 then _G.world.weather({ rain = 0, storm = 0, wind = 0.25 })
    elseif r < 0.7 then _G.world.weather({ rain = 0, storm = 0, wind = 0.55 }); _G.world.environment({ clouds = 0.75 })
    elseif r < 0.9 then _G.world.weather({ rain = 0.8, storm = 0, wind = 0.5 })
    else _G.world.weather({ rain = 1, storm = 1, wind = 0.9 }) end
end

-- streaming: modely nepřátel v okolí (250 m) se načtou dopředu na pozadí – bez záseků při příchodu do oblasti
local preloadAt, preloaded = 0, {}
local function streamPreload()
    if not _G.world.preload or game.time() < preloadAt then return end
    preloadAt = game.time() + 2
    local px, _, pz = player.Pos()
    for _, sp in ipairs(map.Data.Spawns) do
        local t = combat.MobTypes and combat.MobTypes[sp[1]]
        if t and not preloaded[sp[1]] and (sp[2] - px) ^ 2 + (sp[3] - pz) ^ 2 < 250 * 250 then
            preloaded[sp[1]] = true
            if t.model then _G.world.preload(t.model) end
            if t.human then _G.world.preload("Models/humans/" .. t.human .. ".glb") end
        end
    end
end

-- API pro doplňky (sandbox voxario.mods): události, oznámení do deníku, stav postavy
addons.Setup(function(info)
    local mods = require("voxario.mods")
    return {
        on = function(event, fn) mods.on(info, event, fn) end,
        notify = function(text, color)
            local c = { 0.85, 0.8, 1.0 }
            if type(color) == "string" and color:match("^#%x%x%x%x%x%x$") then
                c = { tonumber(color:sub(2, 3), 16) / 255, tonumber(color:sub(4, 5), 16) / 255, tonumber(color:sub(6, 7), 16) / 255 }
            end
            combat.Log("[" .. tostring(info.name or info.id) .. "] " .. tostring(text), c)
        end,
        player = function()
            local s = combat.me
            if not s or not player.body then return nil end
            local x, y, z = player.Pos()
            return { name = creator.a and creator.a.name, level = s.level, hp = s.hp, maxhp = s.maxhp, mp = s.mp, maxmp = s.maxmp,
                     x = x, y = y, z = z, swimming = player.swim ~= nil, oxygen = player.oxygen }
        end,
    }
end)

-- akce ESC menu a mikro lišty
local function logout()
    presence.Stop()
    game_.Reset()
    talentui.open, options.open, addons.open, game_.mapOpen = false, false, false, false
    mode = "select"; game_.mode = mode
    showPreview()
end
local menuActions = {
    options = function() options.open = true end,
    addons = function() addons.open = true end,
    talents = function() talentui.open = true end,
    map = function() game_.mapOpen = true end,
    logout = logout,
    quit = function() game.quit() end,
}
game_.Menu, game_.Addons, game_.MenuActions = menu, addons, menuActions

-- mikro lišta vpravo dole: klikatelná tlačítka oken (jako v MMO)
local function microBar()
    local sw, sh = ui.screen()
    local s, gap = 46, 10
    local items = {
        { "m_talents", "Strom talentů", "N", talentui.open, function() talentui.Toggle() end },
        { "m_map", "Mapa světa", "M", game_.mapOpen, function() game_.mapOpen = not game_.mapOpen end },
        { "m_settings", "Nastavení", "O", options.open, function() options.Toggle() end },
        { "m_addons", "Doplňky", nil, addons.open, function() addons.Toggle() end },
        { "m_menu", "Menu", "Esc", menu.open, function() menu.Toggle() end },
    }
    local w = #items * s + (#items - 1) * gap
    local x0, y0 = sw - w - 34, sh - 82
    ui.panel("UI/hud/frame_thin.png", x0 - 16, y0 - 14, w + 32, s + 28, 10, 14)
    widgets.Block(x0 - 16, y0 - 14, w + 32, s + 28)
    for i, it in ipairs(items) do
        if widgets.IconButton(x0 + (i - 1) * (s + gap), y0, s, it[1], it[2], it[3], it[4]) then it[5]() end
    end
end

-- ------------------------------------------------------------------ měření výkonu (VoxarioPlayer --benchmark)
-- VOXARIO_BENCH_PRESET = low|medium|high|ultra (výchozí ultra), VOXARIO_BENCH_PLACE = valoria|ignis|frost|verdant,
-- VOXARIO_BENCH_RUN = 1: postava běží a kamera se otáčí (streamování, LOD terénu – záseky = trhání kamery)
local function Benchmark()
    local env = game.env or function() return nil end
    options.SetPreset(env("VOXARIO_BENCH_PRESET") or "ultra")
    options.s.upscaler = "off"
    -- VOXARIO_BENCH_SET = "detail=0,view=1,shadows=high" – jednotlivá nastavení navíc (měření jejich ceny)
    for k, v in (env("VOXARIO_BENCH_SET") or ""):gmatch("(%w+)=([%w%.]+)") do
        options.s[k] = tonumber(v) or v
    end
    options.s.fps = 0
    options.s.vsync = false
    options.Apply()
    game_.EnterWorld(1)
    -- srovnatelná měření: pevná denní doba a jasno (bez střídání počasí)
    nextWeather = math.huge
    _G.world.environment({ time_of_day = 14, day_length = 0 })
    _G.world.weather({ rain = 0, snow = 0, storm = 0, instant = true })
    local place = env("VOXARIO_BENCH_PLACE")
    local r = place and map.Data.Regions[({ ignis = "ignis", frost = "frost", verdant = "verdant", crystal = "crystal" })[place] or ""]
    if r then player.Teleport(r.x, r.z) end
    timer.sleep(1)
    timer.wait_until(function() return _G.world.loading() == 0 end)
    timer.sleep(2)
    if env("VOXARIO_BENCH_RUN") then
        local x, _, z = player.Pos()
        combat.moveTo = { x, z - 400 }
        timer.every(0, function() player.cam.yaw = player.cam.yaw + 0.35 end)
    end
    game.benchmark_begin()
    if env("VOXARIO_BENCH_SHOT") then timer.sleep(1); game.screenshot(env("VOXARIO_BENCH_SHOT")) end
end

function on_start()
    hud.Init()
    options.Load()
    options.Apply()   -- uložené grafické nastavení (předvolba, stíny, textury, DLSS / FSR, FPS…)
    _G.world.environment({ day_night = true, real_time = false, time_of_day = 15, day_length = 60, fog = 0.0006,
                           shadow_distance = 260, haze = 0.45, exposure = 0.85, night_exposure = 1.6,
                           contrast = 1.1, saturation = 1.22, clouds = 0.45, bloom = 0.12,
                           style = "realistic" })   -- realistické vykreslování enginu (fyzikální PBR + SSAO)
    world.Build()
    game_.built = true
    pcall(addons.Load)
    if game.custom_pause then game.custom_pause(true) end
    if game.selftest() then timer.start(Selftest); return end
    if game.benchmark and game.benchmark() then timer.start(Benchmark); return end
    showPreview()
    nextWeather = game.time() + 120
end

local lastThunder = 0
function on_update(dt)
    if game_.built then world.Update(dt) end   -- leviatani na moři (i v samotestu)
    if mode ~= "play" and mode ~= "select" then return end
    if mode == "select" then creator.Update(dt); return end
    presence.Update(dt)
    if not ui.wants_keyboard() and not quest.dialog then
        local overlay = talentui.open or options.open or menu.open or addons.open
        if not overlay then
            if input.pressed("Tab") then combat.TabTarget() end
            if input.pressed("R") then combat.StartAttack() end
            actionbar.HandleKeys()            -- 1–0, -, = : dovednosti, aktivní talenty, lektvary, útok, cíl
        end
        if input.pressed("N") then talentui.Toggle() end
        if input.pressed("O") then options.Toggle() end
        if input.pressed("Escape") then
            if menu.open then menu.Toggle()
            elseif addons.open then addons.open = false
            elseif talentui.open then talentui.open = false
            elseif options.open then options.open = false
            elseif game_.mapOpen then game_.mapOpen = false
            elseif combat.target then combat.target, combat.auto = nil, false
            else menu.Toggle() end
        end
        if input.pressed("F") and not overlay then
            local x, _, z = player.Pos()
            local destination = valoria.NearPortal(x, z)
            if destination and not player.dead then
                combat.target, combat.auto, combat.moveTo = nil, false, nil
                player.Teleport(destination.x + 8, destination.z)
                combat.Log("Portál: " .. (destination == valoria.OutpostPortal and "základna Serpentine" or "Valoria"),
                    { 0.6, 0.8, 1.0 })
            else
                quest.Talk()
            end
        end
        if input.pressed("M") then game_.mapOpen = not game_.mapOpen end
    end
    addons.Fire("update", dt)
    combat.Update(dt)
    player.Update(dt, combat.inCombat, combat.moveTo, combat.me and combat.me.casting ~= nil)
    if not game_.freeCam then player.UpdateCamera(dt) end
    weatherCycle()
    streamPreload()
    local w = _G.world.weather()
    if w.lightning ~= lastThunder then lastThunder = w.lightning end
end

-- výběr cíle myší: nejbližší nepřítel u kurzoru (levé tlačítko vybere, pravé vybere a zaútočí)
local rightDown
local function pick()
    local mx, my = ui.mouse()
    local best, bd = nil, 70 * 70
    for _, m in ipairs(combat.Hostiles()) do
        local x, y, vis = ui.world_to_screen(m.x, G(m.x, m.z) + 1.0 * (m.t.scale or 1), m.z)
        if vis then
            local d = (x - mx) ^ 2 + (y - my) ^ 2
            if d < bd then best, bd = m, d end
        end
    end
    return best
end

function on_gui()
    widgets.BeginFrame()
    if mode == "select" then
        creator.Draw()
        if creator.enter then creator.enter = false; enterWorld() end
        return
    end
    if mode ~= "play" then return end
    if not ui.wants_mouse() and not talentui.open and not options.open and not menu.open and not addons.open
        and not widgets.MouseOverUI() then
        if input.pressed("Mouse1") then
            local m = pick()
            if m then combat.Select(m) end
        end
        if input.pressed("Mouse2") then rightDown = { game.time(), ui.mouse() } end
        if rightDown and not input.key("Mouse2") then
            if game.time() - rightDown[1] < 0.3 then
                local m = pick()
                if m then combat.Select(m); combat.StartAttack() end
            end
            rightDown = nil
        end
    end
    -- jmenovka Lyrise
    local l = map.Lyrise
    ui.world_label(l.x, G(l.x, l.z) + 2.6, l.z, quest.step == 1 and "! Archivářka Lyrise" or "Archivářka Lyrise",
        { color = "#9fc8ff", size = 20, max_distance = 40 })
    if quest.NearNpc() and not quest.dialog then
        local sw, sh = ui.screen()
        ui.font("body"); ui.text(sw / 2, sh - 190, "[F] Mluvit", { align = "center", color = "#ffe8b0", shadow = true }); ui.pop_font()
    elseif not quest.dialog then
        local px, _, pz = player.Pos()
        if valoria.NearPortal(px, pz) then
            local sw, sh = ui.screen()
            ui.font("body"); ui.text(sw / 2, sh - 190, "[F] Použít portál", { align = "center", color = "#a9d8ff", shadow = true }); ui.pop_font()
        end
    end
    presence.DrawLabels()
    hud.DrawGame()
    hud.DrawQuest(quest.Tracker())
    hud.DrawDialog(quest.dialog)
    if game_.mapOpen then hud.DrawWorldMap() else hud.DrawMinimap() end
    addons.Fire("draw")
    microBar()
    talentui.Draw()
    options.Draw()
    addons.Draw(widgets)
    menu.Draw(menuActions)
end
