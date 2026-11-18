-- Profese (okno: klávesa P): Hornictví, Stahování kůží, Bylinkářství a Rybolov, každá do úrovně 300.
-- Úroveň roste sběrem: oranžový cíl (těsně na hranici dovednosti) přidá bod vždy, žlutý často, zelený zřídka,
-- šedý už nic – jako v klasických MMO. Uloženo v nastavení hry (eryndor.professions).
--
--   Hornictví:   rudné žíly v dolech (stříbro 1, zlato 75, diamant 150, mitril 225) – těží se krumpáčem (E)
--   Bylinkářství: květiny v regionech (Mírumilka 1 … Ledový květ 240) – trhání (E)
--   Stahování:   ulovená zvěř (vlk, kanec, jelen, medvěd, ledový drak) – u mrtvoly E, potřeba stahovací nůž
--   Rybolov:     prut z tašky u vody (E nebo pravé tlačítko na prut), splávek, při záběru rychle E / levé tlačítko
--
-- Doly: vchod se štolou zapuštěný do svahu, koleje s vozíkem, lucerny a skupina žil před ním; na mapě značka.
local map = require("eryndor.map")
local player = require("eryndor.player")
local inv = require("eryndor.inventory")
local M = { nodes = {}, mines = {}, open = false }
local sqrt, floor, min, max, random, rad, deg, sin, cos, atan = math.sqrt, math.floor, math.min, math.max, math.random,
    math.rad, math.deg, math.sin, math.cos, math.atan

M.Skills = {
    { id = "mining", name = "Hornictví", tool = "pickaxe", color = "#c9a46a" },
    { id = "herbalism", name = "Bylinkářství", color = "#7fd36b" },
    { id = "skinning", name = "Stahování kůží", tool = "knife", color = "#d08a5a" },
    { id = "fishing", name = "Rybolov", tool = "rod", color = "#6fb8ff" },
}
M.MaxSkill = 300
M.skill = { mining = 1, herbalism = 1, skinning = 1, fishing = 1 }

M.Ores = {
    silver = { name = "Stříbrná žíla", item = "ore_silver", req = 1, model = "Models/prof/ore_silver.glb" },
    gold = { name = "Zlatá žíla", item = "ore_gold", req = 75, model = "Models/prof/ore_gold.glb" },
    diamond = { name = "Diamantová žíla", item = "ore_diamond", req = 150, model = "Models/prof/ore_diamond.glb" },
    mithril = { name = "Mitrilová žíla", item = "ore_mithril", req = 225, model = "Models/prof/ore_mithril.glb" },
}
M.Herbs = {
    mirumilka = { name = "Mírumilka", item = "herb_mirumilka", req = 1, codes = "mvb", model = "Models/prof/herb_mirumilka.glb", n = 70 },
    stribrolist = { name = "Stříbrolist", item = "herb_stribrolist", req = 50, codes = "vc", model = "Models/prof/herb_stribrolist.glb", n = 60 },
    krvavy_trn = { name = "Krvavý trn", item = "herb_krvavy_trn", req = 100, codes = "i", model = "Models/prof/herb_krvavy_trn.glb", n = 50 },
    mesicni_lilie = { name = "Měsíční lilie", item = "herb_mesicni_lilie", req = 175, codes = "c", model = "Models/prof/herb_mesicni_lilie.glb", n = 50 },
    ledovy_kvet = { name = "Ledový květ", item = "herb_ledovy_kvet", req = 240, codes = "fk", model = "Models/prof/herb_ledovy_kvet.glb", n = 50 },
}
-- stahovatelná zvěř (druh nepřítele v eryndor.combat)
M.Skins = {
    wolf = { item = "hide_wolf", req = 1 }, boar = { item = "hide_boar", req = 1 }, stag = { item = "hide_stag", req = 60 },
    bear = { item = "hide_bear", req = 120 }, dragon = { item = "scale_dragon", req = 220 },
}
-- ryby: req = minimální rybolov, codes = regiony (nil = všude), night = jen v noci
M.Fish = {
    { item = "fish_pstruh", req = 1, codes = "rmvb" },
    { item = "fish_okoun", req = 40, codes = "rmv" },
    { item = "fish_losos", req = 90, codes = "obr" },
    { item = "fish_stika", req = 150, codes = "fk" },
    { item = "fish_ohnivy", req = 200, codes = "il" },
    { item = "fish_kapr", req = 250, night = true },
}

-- doly: region, název, žíly (druh -> počet)
M.MineDefs = {
    { region = "verdant", codes = "vm", name = "Stříbrný důl Šedý hřeben", ores = { silver = 7, gold = 1 } },
    { region = "ignis", codes = "i", name = "Zlatý důl Žhavá žíla", ores = { gold = 6, silver = 2 } },
    { region = "crystal", codes = "c", name = "Diamantový důl Křišťálová hlubina", ores = { diamond = 6, gold = 2 } },
    { region = "frost", codes = "fk", name = "Mitrilový důl Ledová brána", ores = { mithril = 6, diamond = 2 } },
}

-- ------------------------------------------------------------------ úrovně
local KEY = "eryndor.professions"
function M.Load()
    local s = settings and settings.get(KEY)
    if type(s) == "table" then
        for k in pairs(M.skill) do M.skill[k] = math.max(1, math.min(M.MaxSkill, tonumber(s[k]) or 1)) end
    end
end
function M.Save() if settings then settings.set(KEY, M.skill) end end

-- barva obtížnosti: oranžová, žlutá, zelená, šedá (červená = nedostupné)
function M.Difficulty(skill, req)
    if skill < req then return "red", "#ff5a4a" end
    local d = skill - req
    if d < 25 then return "orange", "#ff9a3a" end
    if d < 50 then return "yellow", "#ffe060" end
    if d < 100 then return "green", "#60d060" end
    return "grey", "#9a9a9a"
end

function M.Gain(id, req)
    local s = M.skill[id]
    if s >= M.MaxSkill then return end
    local diff = M.Difficulty(s, req)
    local chance = ({ orange = 1, yellow = 0.7, green = 0.25, grey = 0 })[diff] or 0
    if random() < chance then
        M.skill[id] = s + 1
        M.Save()
        local def
        for _, d in ipairs(M.Skills) do if d.id == id then def = d end end
        local c = require("eryndor.combat")
        c.Log(string.format("Tvá dovednost %s se zvýšila na %d.", def.name, M.skill[id]), { 0.55, 0.75, 1.0 })
        M.flash = { id = id, t = game.time() }
    end
end

-- ------------------------------------------------------------------ nástroj v ruce
function M.HoldTool(model, scale)
    M.ReleaseTool()
    if not player.view then return end
    for _, w in ipairs(player.weapons or {}) do entity.set_visible(w, false) end
    local t = _G.world.spawn(model, 0, 0, 0, { name = "tool", scale = scale or 1 })
    entity.attach(t, player.view, "handslot.r")
    entity.set_position(t, 0, 0, 0)
    entity.set_rotation(t, 0, 0, 0)
    M.tool = t
end
function M.ReleaseTool()
    if M.tool then entity.destroy(M.tool); M.tool = nil end
    for _, w in ipairs(player.weapons or {}) do entity.set_visible(w, true) end
end

-- ------------------------------------------------------------------ stavba: doly, žíly, byliny
local function hash(x)   -- deterministické náhodné číslo (stejné rozmístění pro všechny hráče)
    local h = sin(x * 12.9898) * 43758.5453
    return h - floor(h)
end

-- místo pro vchod dolu: svah (normála 0,6–0,86) v regionu, nad vodou, co nejblíž středu regionu
local function findMineSite(def)
    local r = map.Data.Regions[def.region]
    local best
    for ring = 0, 55 do
        for k = 0, 23 do
            local a = k / 24 * 2 * math.pi + ring * 0.37
            local d = 60 + ring * 40
            local x, z = r.x + cos(a) * d, r.z + sin(a) * d
            if def.codes:find(map.Region(x, z), 1, true) then
                local h, ny = map.Ground(x, z)
                if h > 4 and ny > 0.55 and ny < 0.9 then
                    -- dole před vchodem musí být rovnější plocha (žíly, vozík)
                    local e = 3
                    local gx = (map.HeightAt(x + e, z) - map.HeightAt(x - e, z)) / (2 * e)
                    local gz = (map.HeightAt(x, z + e) - map.HeightAt(x, z - e)) / (2 * e)
                    local gl = sqrt(gx * gx + gz * gz)
                    if gl > 0.15 then
                        local dx, dz = -gx / gl, -gz / gl          -- z kopce dolů
                        local fx, fz = x + dx * 12, z + dz * 12
                        local fh, fny = map.Ground(fx, fz)
                        if fh > 2.5 and fny > 0.8 then
                            best = { x = x, z = z, y = h, dx = dx, dz = dz }
                            break
                        end
                    end
                end
            end
        end
        if best then break end
    end
    return best
end

local function addNode(kind, def, x, z, extra)
    local n = { kind = kind, def = def, x = x, z = z, y = map.HeightAt(x, z), yaw = hash(x + z) * 360,
                scale = extra and extra.scale or 1, ready = true }
    M.nodes[#M.nodes + 1] = n
    return n
end

function M.Build(scatter)
    M.nodes, M.mines = {}, {}
    for mi, def in ipairs(M.MineDefs) do
        local s = findMineSite(def)
        if s then
            local yaw = deg(atan(s.dx, s.dz))
            -- vchod: o kus do kopce (tunel mizí ve svahu), mírně zapuštěný
            local ex, ez = s.x - s.dx * 1.5, s.z - s.dz * 1.5
            local ey = map.HeightAt(s.x + s.dx * 2, s.z + s.dz * 2) - 0.15
            local mine = { def = def, x = s.x + s.dx * 6, z = s.z + s.dz * 6, name = def.name }
            mine.id = _G.world.spawn("Models/prof/mine_entrance.glb", ex, ey, ez, { yaw = yaw, name = def.name, collider = "mesh" })
            mine.light = _G.world.spawn("light", ex + s.dx * 0.6, ey + 3.0, ez + s.dz * 0.6,
                { light = { color = { 1.0, 0.68, 0.32 }, intensity = 9, range = 14, flicker = true } })
            M.mines[#M.mines + 1] = mine
            -- žíly v půloblouku před vchodem a podél svahu
            local list = {}
            for kind, count in pairs(def.ores) do for _ = 1, count do list[#list + 1] = kind end end
            table.sort(list)
            for i, kind in ipairs(list) do
                local a = (i - 0.5) / #list * math.pi - math.pi / 2 + (hash(mi * 31 + i) - 0.5) * 0.25
                local d = 7 + hash(mi * 7 + i) * 9
                local px, pz = -s.dz, s.dx
                local x = mine.x + (s.dx * cos(a) + px * sin(a)) * d - s.dx * 4
                local z = mine.z + (s.dz * cos(a) + pz * sin(a)) * d - s.dz * 4
                addNode("ore", M.Ores[kind], x, z, { scale = 0.8 + hash(i + mi) * 0.35 })
            end
        end
    end
    -- několik osamocených žil v kopcích (stříbro na loukách, zlato v Ignis, diamant v Crystalariu, mitril v horách)
    if scatter then
        local lone = { { "silver", "mv", 14 }, { "gold", "i", 10 }, { "diamond", "c", 8 }, { "mithril", "fk", 8 } }
        for _, l in ipairs(lone) do
            for _, p in ipairs(scatter(l[3], l[2], { hmin = 4, slope = 0.3 })) do
                addNode("ore", M.Ores[l[1]], p[1], p[3], { scale = 0.75 })
            end
        end
        for _, h in pairs(M.Herbs) do
            for _, p in ipairs(scatter(h.n, h.codes, { hmin = 2.5, slope = 0.3 })) do
                addNode("herb", h, p[1], p[3], { scale = 0.9 + hash(p[1]) * 0.4 })
            end
        end
    end
    -- lovná zvěř pro Stahování (nepřátelé eryndor.combat, klidní dokud nejsou napadeni)
    if scatter then
        local S = map.Data.Spawns
        for _, h in ipairs({ { "boar", "v", 10 }, { "boar", "m", 6 }, { "stag", "vm", 10 }, { "bear", "v", 4 }, { "bear", "f", 4 } }) do
            for _, p in ipairs(scatter(h[3], h[2], { hmin = 4, slope = 0.25 })) do S[#S + 1] = { h[1], p[1], p[3] } end
        end
    end
    -- byliny blízko začátku (základna Serpentine), ať je nováček hned najde
    local st = map.Start
    for i = 1, 10 do
        local a, d = hash(i * 3.1) * 2 * math.pi, 25 + hash(i * 7.7) * 70
        addNode("herb", M.Herbs.mirumilka, st.x + cos(a) * d, st.z + sin(a) * d)
    end
end

-- ------------------------------------------------------------------ streamování modelů (jen okolí hráče)
local streamT = 0
local function stream(px, pz)
    for _, n in ipairs(M.nodes) do
        local d2 = (n.x - px) ^ 2 + (n.z - pz) ^ 2
        local want = n.ready and d2 < 200 * 200
        if want and not n.id then
            n.id = _G.world.spawn(n.def.model, n.x, n.y - 0.05, n.z, { yaw = n.yaw, scale = n.scale, name = n.def.name })
        elseif not want and n.id and d2 > 230 * 230 or (n.id and not n.ready) then
            entity.destroy(n.id)
            n.id = nil
        end
    end
end

-- ------------------------------------------------------------------ sběr (E)
local function nearest(px, pz)
    local best, bd = nil, 3.2 * 3.2
    for _, n in ipairs(M.nodes) do
        if n.ready then
            local r = n.kind == "ore" and 2.6 or 1.6
            local d = (n.x - px) ^ 2 + (n.z - pz) ^ 2
            if d < r * r and d < bd then best, bd = n, d end
        end
    end
    return best
end

local function corpse(px, pz)
    local c = require("eryndor.combat")
    local best, bd = nil, 3.5 * 3.5
    for _, m in ipairs(c.mobs or {}) do
        if m.state == "dead" and M.Skins[m.kind] and not m.skinned then
            local d = (m.x - px) ^ 2 + (m.z - pz) ^ 2
            if d < bd then best, bd = m, d end
        end
    end
    return best
end

-- co je teď u hráče k sebrání (pro nápovědu na obrazovce)
function M.Prompt()
    if not player.body or player.dead or player.swim then return nil end
    local px, _, pz = player.Pos()
    local n = nearest(px, pz)
    if n then
        local id = n.kind == "ore" and "mining" or "herbalism"
        local _, col = M.Difficulty(M.skill[id], n.def.req)
        return { text = (n.kind == "ore" and "[E] Těžit: " or "[E] Natrhat: ") .. n.def.name .. " (" .. n.def.req .. ")", color = col, node = n }
    end
    local m = corpse(px, pz)
    if m then
        local sk = M.Skins[m.kind]
        local _, col = M.Difficulty(M.skill.skinning, sk.req)
        return { text = "[E] Stáhnout kůži: " .. m.t.name .. " (" .. sk.req .. ")", color = col, mob = m }
    end
    if inv.Has("rod") and M.WaterAhead() then return { text = "[E] Rybařit", color = "#9fd4ff", fish = true } end
    return nil
end

local function startCast(kind, dur, clip, done, info)
    M.cast = { kind = kind, t0 = game.time(), dur = dur, clip = clip, done = done, info = info, nextSwing = 0 }
end

function M.Interact()
    local p = M.Prompt()
    if not p then return false end
    local c = require("eryndor.combat")
    if p.node then
        local n = p.node
        local id = n.kind == "ore" and "mining" or "herbalism"
        if M.skill[id] < n.def.req then c.Log("Potřebuješ " .. (id == "mining" and "Hornictví " or "Bylinkářství ") .. n.def.req .. ".", { 1, 0.5, 0.4 }); return true end
        if id == "mining" then
            if not inv.Has("pickaxe") then c.Log("Potřebuješ krumpáč.", { 1, 0.5, 0.4 }); return true end
            M.HoldTool("Models/prof/pickaxe.glb")
            startCast("Těžba", 3.2, "1H_Melee_Attack_Chop", function()
                local amount = 1 + (random() < 0.5 and 1 or 0) + (random() < 0.15 and 1 or 0)
                inv.Add(n.def.item, amount)
                M.Gain("mining", n.def.req)
                n.ready, n.respawn = false, game.time() + 120
                _G.world.particles(n.x, n.y + 0.6, n.z, { preset = "dust", burst = 30, duration = 0.1, life = 1.6 })
            end, n)
        else
            startCast("Sběr bylin", 2.0, "PickUp", function()
                inv.Add(n.def.item, 1 + (random() < 0.35 and 1 or 0))
                M.Gain("herbalism", n.def.req)
                n.ready, n.respawn = false, game.time() + 90
            end, n)
        end
        player.faceTarget = deg(atan(n.x - select(1, player.Pos()), n.z - select(3, player.Pos())))
        return true
    end
    if p.mob then
        local m, sk = p.mob, M.Skins[p.mob.kind]
        if not inv.Has("knife") then c.Log("Potřebuješ stahovací nůž.", { 1, 0.5, 0.4 }); return true end
        if M.skill.skinning < sk.req then c.Log("Potřebuješ Stahování kůží " .. sk.req .. ".", { 1, 0.5, 0.4 }); return true end
        M.HoldTool("Models/gear/real/dagger.glb")
        startCast("Stahování", 2.6, "Interact", function()
            inv.Add(sk.item, m.kind == "bear" and 2 or 1)
            M.Gain("skinning", sk.req)
            m.skinned = true
            m.deadT = math.min(m.deadT, game.time() - 18)   -- stažená mrtvola brzy zmizí
        end, m)
        return true
    end
    if p.fish then M.StartFishing(); return true end
    return false
end

-- ------------------------------------------------------------------ rybolov
-- voda před hráčem: první místo 3–16 m ve směru kamery s hloubkou aspoň 0,45 m
function M.WaterAhead()
    local px, py, pz = player.Pos()
    local yaw = rad(player.cam and player.cam.yaw or player.facing)
    for d = 3, 16, 1 do
        local x, z = px + sin(yaw) * d, pz + cos(yaw) * d
        local wy = player.WaterY(x, z)
        if wy and wy - map.HeightAt(x, z) > 0.45 and math.abs(wy - py) < 6 then
            -- splávek kousek dál do hlubší vody, pokud tam je
            local x2, z2 = px + sin(yaw) * (d + 3), pz + cos(yaw) * (d + 3)
            local wy2 = player.WaterY(x2, z2)
            if wy2 and wy2 - map.HeightAt(x2, z2) > 0.6 then return x2, wy2, z2 end
            return x, wy, z
        end
    end
    return nil
end

function M.StartFishing()
    local c = require("eryndor.combat")
    if M.fishing then return end
    if not inv.Has("rod") then c.Log("Potřebuješ rybářský prut.", { 1, 0.5, 0.4 }); return end
    if player.swim or player.dead then return end
    local x, wy, z = M.WaterAhead()
    if not x then c.Log("Musíš stát u vody a dívat se na ni.", { 1, 0.7, 0.5 }); return end
    M.HoldTool("Models/prof/fishing_rod.glb")
    local px, _, pz = player.Pos()
    player.faceTarget = deg(atan(x - px, z - pz))
    player.facing = player.faceTarget
    player.Action("Throw", 1.0)
    local wait = 4 + random() * (12 - min(6, M.skill.fishing / 50))
    M.fishing = { x = x, z = z, wy = wy, t0 = game.time(), bite = game.time() + 1.0 + wait, phase = "cast" }
    timer.after(0.55, function()
        if M.fishing and not M.fishing.bobber then
            M.fishing.bobber = _G.world.spawn("Models/prof/bobber.glb", x, wy, z, { name = "Splávek" })
            _G.world.particles(x, wy, z, { preset = "water_splash", burst = 14, duration = 0.1, life = 0.8 })
            M.fishing.phase = "wait"
        end
    end)
end

local function stopFishing(msg, color)
    local f = M.fishing
    if not f then return end
    if f.bobber then entity.destroy(f.bobber) end
    M.fishing = nil
    M.ReleaseTool()
    player.faceTarget = nil
    if msg then require("eryndor.combat").Log(msg, color or { 0.8, 0.8, 0.8 }) end
end
M.StopFishing = stopFishing

local function catchFish()
    local px, _, pz = player.Pos()
    local region = map.Region(px, pz)
    local tod = (_G.eryndor and _G.eryndor.tod) or 12
    local night = tod > 20.5 or tod < 4.5
    local pool = {}
    for _, f in ipairs(M.Fish) do
        local ok = M.skill.fishing >= f.req and (not f.codes or f.codes:find(region, 1, true)) and (not f.night or night)
        if ok then pool[#pool + 1] = f end
    end
    if #pool == 0 then pool = { M.Fish[1] } end
    -- vzácnější (vyšší) ryby méně často
    local f = pool[#pool - floor((random() ^ 1.8) * #pool)] or pool[1]
    inv.Add(f.item, 1)
    M.Gain("fishing", f.req)
end

local function updateFishing(dt)
    local f = M.fishing
    if not f then return end
    local now = game.time()
    if player.manual or player.dead or player.swim then stopFishing("Rybaření přerušeno."); return end
    if not (player.actionT and now < player.actionT) then player.Play("Idle") end
    if f.bobber then
        local bob = 0.03 * sin(now * 2.2)
        if f.phase == "wait" and now >= f.bite then
            f.phase, f.biteEnd = "bite", now + 1.6
            _G.world.particles(f.x, f.wy, f.z, { preset = "water_splash", burst = 22, duration = 0.1, life = 0.9 })
            if audio and audio.tone then audio.tone(520, 0.12, "sine", 0.25, 760) end
        end
        if f.phase == "bite" then
            bob = -0.12 - 0.06 * sin(now * 30)
            if now > f.biteEnd then stopFishing("Ryba utekla…", { 0.8, 0.6, 0.5 }); return end
        end
        entity.set_position(f.bobber, f.x, (player.WaterY(f.x, f.z) or f.wy) + bob, f.z)
    end
end

-- E / levé tlačítko při záběru
function M.Hook()
    local f = M.fishing
    if not f then return false end
    if f.phase == "bite" then
        player.Action("Use_Item", 0.8)
        catchFish()
        stopFishing()
    else
        stopFishing("Stáhl jsi udici.")
    end
    return true
end

-- ------------------------------------------------------------------ smyčka
function M.Update(dt)
    if not player.body then return end
    local now = game.time()
    local px, _, pz = player.Pos()
    streamT = streamT - dt
    if streamT <= 0 then
        streamT = 1.0
        for _, n in ipairs(M.nodes) do
            if not n.ready and n.respawn and now > n.respawn then n.ready, n.respawn = true, nil end
        end
        stream(px, pz)
    end
    local c = M.cast
    if c then
        if player.manual or player.dead then
            M.cast = nil
            M.ReleaseTool()
            player.faceTarget = nil
            require("eryndor.combat").Log(c.kind .. " přerušena.", { 0.9, 0.6, 0.5 })
        elseif now - c.t0 >= c.dur then
            M.cast = nil
            M.ReleaseTool()
            player.faceTarget = nil
            c.done()
        elseif now >= c.nextSwing then
            c.nextSwing = now + (c.clip == "1H_Melee_Attack_Chop" and 0.95 or c.dur + 1)
            player.Action(c.clip, c.clip == "1H_Melee_Attack_Chop" and 0.9 or c.dur, c.clip == "PickUp" and 0.9 or 1)
            if c.clip == "1H_Melee_Attack_Chop" and c.info then
                timer.after(0.45, function()
                    if M.cast == c then
                        _G.world.particles(c.info.x, c.info.y + 0.7, c.info.z, { preset = "spark", burst = 10, duration = 0.05, life = 0.5 })
                        if audio and audio.tone then audio.tone(1500 + random() * 400, 0.05, "noise", 0.18) end
                    end
                end)
            end
        end
    end
    updateFishing(dt)
end

-- ------------------------------------------------------------------ UI: lišta sesílání, nápověda, okno profesí
local GOLD, TEXT, DIM = "#d8b25a", "#efe6d2", "#9a8f7c"
function M.DrawHud()
    local sw, sh = ui.screen()
    local c = M.cast
    if c then
        local f = min(1, (game.time() - c.t0) / c.dur)
        ui.bar(sw / 2 - 160, sh - 250, 320, 22, f, "#d8b25a", c.kind, "#000000aa")
    elseif M.fishing then
        local f = M.fishing
        local txt = f.phase == "bite" and "ZÁBĚR! [E] zaseknout" or "Čekáš na záběr…  ([E] stáhnout)"
        ui.font("body"); ui.text(sw / 2, sh - 250, txt, { align = "center", color = f.phase == "bite" and "#ffd860" or "#a9d8ff", shadow = true }); ui.pop_font()
        -- vlasec od špičky prutu ke splávku
        if f.bobber and player.view then
            local hx = entity.bone_position(player.view, "hand_r")
            if hx then
                local yaw = rad(player.facing)
                local tx, ty, tz = hx.x + sin(yaw) * 1.6, hx.y + 1.5, hx.z + cos(yaw) * 1.6
                local ax, ay, va = ui.world_to_screen(tx, ty, tz)
                local bx, by, vb = ui.world_to_screen(f.x, f.wy + 0.05, f.z)
                if va and vb then ui.line(ax, ay, bx, by, "#e8e8e8aa", 1) end
            end
        end
    else
        local p = M.Prompt()
        if p then
            ui.font("body"); ui.text(sw / 2, sh - 220, p.text, { align = "center", color = p.color, shadow = true }); ui.pop_font()
        end
    end
end

function M.Toggle() M.open = not M.open end

function M.Draw(widgets)
    if not M.open then return end
    local sw, sh = ui.screen()
    local w, h = 460, 120 + #M.Skills * 74
    local x, y = 60, sh / 2 - h / 2
    ui.panel("UI/hud/panel_ornate_light.png", x, y, w, h, 28, 40)
    if widgets then widgets.Block(x, y, w, h) end
    ui.font("h2"); ui.text(x + w / 2, y + 16, "Profese", { align = "center", color = GOLD, shadow = true }); ui.pop_font()
    for i, d in ipairs(M.Skills) do
        local yy = y + 58 + (i - 1) * 74
        local v = M.skill[d.id]
        ui.font("body"); ui.text(x + 30, yy, d.name, { color = TEXT, shadow = true }); ui.pop_font()
        ui.bar(x + 30, yy + 30, w - 60, 20, v / M.MaxSkill, d.color, string.format("%d / %d", v, M.MaxSkill), "#000000aa")
        if M.flash and M.flash.id == d.id and game.time() - M.flash.t < 1.5 then ui.rect(x + 30, yy + 30, w - 60, 20, "#ffffff30", 3) end
    end
    ui.font("small")
    ui.text(x + w / 2, y + h - 34, "[P] zavřít · E = těžit / trhat / stahovat / rybařit", { align = "center", color = DIM, shadow = true })
    ui.pop_font()
end

-- značky dolů na mapě a štítky nad vchody
function M.DrawLabels()
    for _, m in ipairs(M.mines) do
        ui.world_label(m.x, map.HeightAt(m.x, m.z) + 5, m.z, m.name, { color = "#e8c27a", size = 18, max_distance = 120 })
    end
end

return M
