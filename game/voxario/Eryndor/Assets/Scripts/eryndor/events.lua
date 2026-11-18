-- Světová událost „Pád z nebes“: jednou za herní den (den = 60 minut, vždy v xx:30 světového času UTC) spadne
-- někde v Aethelgardu z nebe anděl nebo démon. Dvě minuty předem se na obloze objeví hořící hvězda a hra to
-- ohlásí (místo je na mapě). Pak se z výšky 1 km řítí žhnoucí těleso s ohnivým ohonem a kouřem, rozzáří krajinu,
-- dopadne s výbuchem, otřesem země a kráterem – a z plamenů povstane anděl (zlatá křídla, svatozář) nebo démon
-- (rohy, blanitá křídla). Je to elitní boss: kruhová nova, sloupy světla / ohně a svolání ohně z nebe.
-- Kdo ho porazí, dostane trofej, úlomky meteoru a hodně zkušeností.
-- Čas a místo jsou deterministické (z čísla hodiny) – všichni hráči ho vidí na stejném místě ve stejnou chvíli.
local map = require("eryndor.map")
local player = require("eryndor.player")
local M = { state = "idle" }
local sin, cos, sqrt, floor, random, max, min = math.sin, math.cos, math.sqrt, math.floor, math.random, math.max, math.min

M.Kinds = {
    angel = { name = "Padlý anděl Seraphiel", short = "anděl", color = { 1.0, 0.85, 0.45 }, hex = "#ffe08a",
              trail = "holy", item = "feather_angel", nova = "holy", pillar = "holy" },
    demon = { name = "Démon Azgaroth", short = "démon", color = { 1.0, 0.3, 0.08 }, hex = "#ff6a3a",
              trail = "fire", item = "horn_demon", nova = "fire", pillar = "fire" },
}
M.Period, M.Offset, M.Warn = 3600, 1800, 120   -- každou hodinu v :30, ohlášení 2 min předem

local function hash(x)
    local h = sin(x * 78.233 + 12.9898) * 43758.5453
    return h - floor(h)
end

-- místo dopadu: z čísla události, rovná zem nad mořem mimo Valorii
function M.Site(n)
    local regions = { "verdant", "frost", "ignis", "crystal" }
    local r = map.Data.Regions[regions[floor(hash(n) * 4) + 1]]
    for k = 0, 60 do
        local a, d = hash(n * 3 + k) * 2 * math.pi, 120 + hash(n * 7 + k) * 520
        local x, z = r.x + cos(a) * d, r.z + sin(a) * d
        local h, ny = map.Ground(x, z)
        if h > 4 and ny > 0.9 and map.Region(x, z) ~= "a" then return x, z end
    end
    return map.Start.x + 120, map.Start.z + 80
end

function M.KindOf(n) return (n % 2 == 0) and "angel" or "demon" end

local function now() return (time and time.now and time.now()) or os.time() end

-- ------------------------------------------------------------------ průběh
local function log(text, c) require("eryndor.combat").Log(text, c or { 1.0, 0.85, 0.45 }) end

function M.Announce(kind, x, z)
    local k = M.Kinds[kind]
    M.banner = { text = "Na obloze hoří nová hvězda… Něco padá k " .. map.RegionName(x, z) .. "!", t = game.time(), color = k.hex }
    log("Pád z nebes: " .. k.short .. " dopadne u " .. map.RegionName(x, z) .. " (místo na mapě).", k.color)
    M.marker = { x = x, z = z, label = "Pád z nebes", color = k.hex }
end

local function particles(x, y, z, o) return _G.world.particles(x, y, z, o) end

-- spustí pád (kind, místo); samotest a ladění mohou volat přímo
function M.Trigger(kind, x, z, fallTime)
    if M.state ~= "idle" then M.Clear() end
    local k = M.Kinds[kind]
    M.kind, M.k, M.x, M.z = kind, k, x, z
    M.y = map.HeightAt(x, z)
    M.state = "falling"
    M.t0 = game.time()
    M.fall = fallTime or 7.5
    M.marker = { x = x, z = z, label = k.name, color = k.hex }
    -- start vysoko a stranou (šikmý pád přes oblohu)
    local a = hash(x + z) * 2 * math.pi
    M.from = { x + cos(a) * 700, M.y + 1100, z + sin(a) * 700 }
    M.meteor = _G.world.spawn("Models/prof/meteor.glb", M.from[1], M.from[2], M.from[3], { scale = 4.5, name = "Meteor" })
    M.light = _G.world.spawn("light", M.from[1], M.from[2], M.from[3], { light = { color = k.color, intensity = 120, range = 260 } })
    M.trail = particles(M.from[1], M.from[2], M.from[3], { preset = k.trail == "holy" and "holy" or "fire", rate = 900, speed = 3,
        spread = 1, life = 1.8, size = 9, distance = 3000 })
    M.smoke = particles(M.from[1], M.from[2], M.from[3], { preset = "smoke_dark", rate = 220, speed = 1.5, spread = 1, life = 5,
        size = 10, distance = 3000 })
    M.banner = { text = (kind == "angel" and "Z nebe padá anděl!" or "Z pekla se řítí démon!"), t = game.time(), color = k.hex }
    if audio and audio.tone then audio.tone(55, M.fall, "noise", 0.25, 30) end
end

local function impact()
    local k, x, y, z = M.k, M.x, M.y, M.z
    entity.destroy(M.trail); entity.destroy(M.smoke)
    entity.set_position(M.meteor, x, y - 1.2, z)   -- zaryté v kráteru, dál žhne
    entity.set_scale(M.meteor, 1.6, 1.6, 1.6)
    entity.set_position(M.light, x, y + 6, z)
    M.crater = _G.world.spawn("Models/prof/crater.glb", x, y - 0.25, z, { name = "Kráter", scale = 1.4 })
    particles(x, y + 1, z, { preset = "explosion", burst = 400, duration = 0.1, speed = 22, spread = 1, life = 2.2, size = 5, distance = 3000 })
    particles(x, y + 0.5, z, { preset = "dust", burst = 200, duration = 0.1, radius = 6, ring = true, speed = 14, spread = 0.3,
        dir = { 0, 0.25, 0 }, life = 3.5, size = 4, distance = 2000 })
    M.column = particles(x - 4, y + 1, z - 4, { preset = "smoke", rate = 5, speed = 6, spread = 0.15, dir = { 0, 1, 0 }, life = 5,
        size = 3, duration = 20, distance = 3000, opacity = 0.45 })
    M.embers = particles(x, y + 0.5, z, { preset = k.trail == "holy" and "holy" or "fire", rate = 50, radius = 5, speed = 1.5, life = 1.4,
        duration = 600 })
    if audio and audio.tone then
        audio.tone(42, 2.5, "noise", 0.9, 20)
        audio.tone(70, 1.8, "sine", 0.6, 30)
    end
    -- otřes země podle vzdálenosti
    local px, _, pz = player.Pos()
    local d = sqrt((px - x) ^ 2 + (pz - z) ^ 2)
    M.shake = { t = game.time(), power = max(0, 1 - d / 700) }
    if d < 14 then require("eryndor.combat").HurtPlayer(60, "Smetla tě rázová vlna dopadu.") end
    M.state = "impact"
    M.riseT = game.time() + 3.0
end

local function spawnBoss()
    local c = require("eryndor.combat")
    local m = c.SpawnMob(M.kind, M.x, M.z)
    m.noRespawn = true
    m.boss = true
    M.boss = m
    -- křídla a svatozář / rohy na kostech bosse
    local w = _G.world.spawn("Models/prof/wings_" .. M.kind .. ".glb", 0, 0, 0, { name = "Křídla" })
    entity.attach(w, m.id, "spine_03")
    entity.set_position(w, 0, 0.02, -0.12)
    entity.set_rotation(w, 0, 0, 0)
    local extra = _G.world.spawn(M.kind == "angel" and "Models/prof/halo.glb" or "Models/prof/horns.glb", 0, 0, 0, { name = "Ozdoba" })
    entity.attach(extra, m.id, "head")
    entity.set_position(extra, 0, M.kind == "angel" and 0.32 or 0.12, 0)
    M.parts = { w, extra }
    -- aura: anděl svatá záře, démon plameny kolem těla (barvy modelu zůstávají – PBR textury)
    M.aura = particles(M.x, M.y + 1, M.z, { preset = M.kind == "angel" and "holy" or "fire", rate = 45, radius = 1.4,
        speed = 1.2, spread = 0.6, dir = { 0, 1, 0 }, life = 1.0, size = 1.6 })
    entity.attach(M.aura, m.id)
    entity.set_position(M.aura, 0, 1.0, 0)
    anim.play(m.id, "Spellcast_Raise", 0.1, false, true)
    m.actionT = game.time() + 2.0
    m.holdT = game.time() + 2.0
    particles(M.x, M.y + 1, M.z, { preset = M.k.nova, burst = 260, duration = 0.1, speed = 12, spread = 1, life = 1.4, size = 3 })
    M.banner = { text = M.k.name .. " povstal z kráteru!", t = game.time(), color = M.k.hex }
    log(M.k.name .. " povstal! Poraz ho (elitní, úroveň 10).", M.k.color)
    M.state = "boss"
    M.nextNova, M.nextRain, M.endT = game.time() + 7, game.time() + 12, game.time() + 20 * 60
    M.hazards = {}
end

local function hazard(x, z, r, delay, dmg, preset)
    local y = map.HeightAt(x, z)
    local mark = particles(x, y + 0.15, z, { preset = preset, rate = 0, burst = floor(30 + r * 12), duration = 0, radius = r,
        ring = true, speed = 0.6, spread = 0.1, dir = { 0, 1, 0 }, life = delay })
    M.hazards[#M.hazards + 1] = { x = x, z = z, r = r, at = game.time() + delay, dmg = dmg, preset = preset, mark = mark }
end

local function bossUpdate(dt)
    local m = M.boss
    local t = game.time()
    if not m then return end
    if m.state == "dead" then
        if not M.looted then
            M.looted = true
            local inv = require("eryndor.inventory")
            inv.Add(M.k.item, 1)
            inv.Add("meteor_shard", 2 + floor(random() * 3))
            M.banner = { text = M.k.name .. " byl poražen!", t = t, color = M.k.hex }
            log("Vítězství! " .. M.k.name .. " padl. Trofej a úlomky meteoru jsou tvé.", { 1.0, 0.9, 0.5 })
            M.endT = t + 40
        end
    else
        local px, _, pz = player.Pos()
        local d = sqrt((px - m.x) ^ 2 + (pz - m.z) ^ 2)
        if m.aggro and t >= M.nextNova and d < 40 then   -- kruhová nova kolem bosse
            M.nextNova = t + 9
            anim.play(m.id, "Spellcast_Long", 0.1, false, true)
            m.actionT, m.holdT = t + 1.6, t + 1.6
            hazard(m.x, m.z, 9, 1.6, 70, M.k.nova)
        end
        if m.aggro and t >= M.nextRain and d < 60 then   -- sloupy světla / ohně z nebe na hráče a kolem něj
            M.nextRain = t + 14
            anim.play(m.id, "Spellcast_Raise", 0.1, false, true)
            m.actionT = t + 1.2
            hazard(px, pz, 3, 1.5, 90, M.k.pillar)
            for i = 1, 3 do
                local a = random() * 2 * math.pi
                hazard(px + cos(a) * 6, pz + sin(a) * 6, 3, 1.8 + i * 0.3, 90, M.k.pillar)
            end
        end
    end
    -- dopady
    local keep = {}
    for _, h in ipairs(M.hazards) do
        if t >= h.at then
            local y = map.HeightAt(h.x, h.z)
            particles(h.x, y + 0.5, h.z, { preset = h.preset, burst = 160, duration = 0.1, speed = 9, spread = 0.4, dir = { 0, 1, 0 },
                life = 1.0, radius = h.r * 0.5, size = 2.5 })
            local px, _, pz = player.Pos()
            if (px - h.x) ^ 2 + (pz - h.z) ^ 2 < h.r * h.r and not player.dead then
                require("eryndor.combat").HurtPlayer(h.dmg, "Padl jsi v plamenech nebes. Ozvěna se vrací ke Zřídlu…")
            end
        else
            keep[#keep + 1] = h
        end
    end
    M.hazards = keep
    if t > M.endT then
        if m.state ~= "dead" then log(M.k.name .. " se vznesl zpět do oblak.", { 0.8, 0.8, 0.9 }) end
        M.Clear()
    end
end

function M.Clear()
    for _, k in ipairs({ "meteor", "light", "trail", "smoke", "crater", "column", "embers", "aura" }) do
        if M[k] then entity.destroy(M[k]); M[k] = nil end
    end
    for _, p in ipairs(M.parts or {}) do entity.destroy(p) end
    M.parts = nil
    if M.boss then
        local c = require("eryndor.combat")
        for i, m in ipairs(c.mobs) do if m == M.boss then table.remove(c.mobs, i); break end end
        entity.destroy(M.boss.id)
        if c.target == M.boss then c.target, c.auto = nil, false end
        M.boss = nil
    end
    M.state, M.looted, M.marker, M.hazards = "idle", false, nil, {}
end

function M.Update(dt)
    if not player.body then return end
    local t = game.time()
    -- plán: další událost podle světového času
    if M.state == "idle" and not M.manual then
        local u = now()
        local n = floor((u - M.Offset) / M.Period) + 1     -- číslo příští události
        local at = n * M.Period + M.Offset
        local untilT = at - u
        if untilT <= M.Warn and M.warned ~= n then
            M.warned = n
            local x, z = M.Site(n)
            M.Announce(M.KindOf(n), x, z)
        end
        if untilT <= 0.5 and M.fired ~= n then
            M.fired = n
            local x, z = M.Site(n)
            M.Trigger(M.KindOf(n), x, z)
        end
    end
    if M.state == "falling" then
        local f = min(1, (t - M.t0) / M.fall)
        local e = f * f   -- zrychluje
        local x = M.from[1] + (M.x - M.from[1]) * e
        local y = M.from[2] + (M.y - M.from[2]) * e
        local z = M.from[3] + (M.z - M.from[3]) * e
        entity.set_position(M.meteor, x, y, z)
        entity.set_rotation(M.meteor, t * 90, t * 40, 0)
        entity.set_position(M.light, x, y, z)
        entity.set_position(M.trail, x, y, z)
        entity.set_position(M.smoke, x, y, z)
        if f >= 1 then impact() end
    elseif M.state == "impact" then
        if t >= M.riseT then spawnBoss() end
    elseif M.state == "boss" then
        bossUpdate(dt)
    end
    -- otřes kamery
    if M.shake and player.camera then
        local k = 1 - (t - M.shake.t) / 2.2
        if k > 0 and M.shake.power > 0 then
            local p = M.shake.power * k * 0.35
            entity.translate(player.camera, (random() - 0.5) * p, (random() - 0.5) * p, (random() - 0.5) * p)
        elseif k <= 0 then M.shake = nil end
    end
end

-- nápis přes obrazovku a štítek nad místem
function M.DrawHud()
    local sw, sh = ui.screen()
    local b = M.banner
    if b then
        local age = game.time() - b.t
        if age < 6 then
            local a = min(1, age * 3) * min(1, (6 - age) / 1.0)
            ui.font("h1")
            ui.text(sw / 2, sh * 0.22, b.text, { align = "center", color = b.color .. string.format("%02x", floor(a * 255)), shadow = true })
            ui.pop_font()
        else M.banner = nil end
    end
    if M.marker then
        local x, z = M.marker.x, M.marker.z
        ui.world_label(x, map.HeightAt(x, z) + (M.state == "boss" and 9 or 4), z, M.marker.label, { color = M.marker.color, size = 22, max_distance = 4000 })
    end
end

return M
