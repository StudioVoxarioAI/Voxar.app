-- Zvěř v lesích Aethelgardu: stáda laní s jelenem, tlupy divočáků, vlčí smečky a medvědi samotáři.
-- Modely: Quadruped Forge (engine, tools/creatures/quadruped_forge.py) – anatomická síť, srst z vrstev (shell fur),
-- kostra a klipy Walk / Trot / Run (nohy přes IK, referenční rychlosti níže), Idle, Idle_Look, Graze, Attack, Hit,
-- Death, Howl (vlk), Roar (jelen, medvěd).
-- Každé zvíře má vlastní trasu: skupina má domov a vůdce, který vybírá cíle v lese (region, výška, sklon, mimo
-- vodu a stavby); ostatní jdou za ním ve vlastních odstupech, s vlastním tempem a zastávkami, pasou se každý zvlášť.
-- Obcházejí kmeny stromů a sebe navzájem, natáčejí se podle svahu. Na hráče reagují podle druhu (ostražitost,
-- útěk, odstup, varovný řev).
-- Výkon: plný pohyb do 120 m od kamery, do 400 m 5x za sekundu, dál skryté (nekreslí se, neanimují) a jen
-- jednou za sekundu posun skupiny; engine animované modely mimo zorné pole nekreslí, do dálky kreslí LOD.
local map = require("eryndor.map")
local M = { list = {}, groups = {} }
local sin, cos, sqrt, atan, floor, max, min, pi, abs = math.sin, math.cos, math.sqrt, math.atan, math.floor, math.max,
    math.min, math.pi, math.abs

local seed = 97531
local function rnd(a, b)
    seed = (seed * 1103515245 + 12345) % 2147483648
    local r = seed / 2147483648
    if a then return a + (b - a) * r end
    return r
end

-- ------------------------------------------------------------------ druhy
-- ref: rychlosti klipů bez klouzání (quadruped_forge.SPEEDS); r = poloměr těla (odstupy, kmeny)
M.Species = {
    doe  = { model = "doe",  name = "Laň",       ref = { walk = 1.2, trot = 3.0, run = 8.0 }, r = 0.45, len = 1.5, turn = 140 },
    stag = { model = "stag", name = "Jelen",     ref = { walk = 1.25, trot = 3.1, run = 8.0 }, r = 0.5, len = 1.7, turn = 120 },
    boar = { model = "boar", name = "Divočák",   ref = { walk = 1.0, trot = 2.4, run = 6.0 }, r = 0.4, len = 1.3, turn = 150 },
    wolf = { model = "wolf", name = "Vlk",       ref = { walk = 1.3, trot = 3.2, run = 7.5 }, r = 0.35, len = 1.2, turn = 170 },
    bear = { model = "bear", name = "Medvěd",    ref = { walk = 1.15, trot = 2.6, run = 7.0 }, r = 0.7, len = 2.0, turn = 90 },
}

-- skupiny: regiony (kódy mřížky světa), počet, složení, dosah domova (m)
M.Groups = {
    { kind = "deer", codes = "v", count = 3, members = { "stag", "doe", "doe", "doe", "doe" }, range = 140 },
    { kind = "deer", codes = "f", count = 1, members = { "stag", "doe", "doe" }, range = 160, hmax = 220 },
    { kind = "boar", codes = "v", count = 3, members = { "boar", "boar", "boar", "boar" }, range = 100 },
    { kind = "wolf", codes = "v", count = 1, members = { "wolf", "wolf", "wolf", "wolf" }, range = 260 },
    { kind = "wolf", codes = "f", count = 2, members = { "wolf", "wolf", "wolf", "wolf", "wolf" }, range = 300, hmax = 240 },
    { kind = "bear", codes = "v", count = 2, members = { "bear" }, range = 220 },
    { kind = "bear", codes = "f", count = 2, members = { "bear" }, range = 240, hmax = 230 },
}

-- ------------------------------------------------------------------ prostředí: kmeny, terén
local trunks, CELL = {}, 16
function M.AddTrunks(list, radius)
    for _, t in ipairs(list) do
        local x, z, r = t[1], t[3], radius * (t[5] or 1)
        local k = floor(x / CELL) * 100000 + floor(z / CELL)
        local b = trunks[k]
        if not b then b = {}; trunks[k] = b end
        b[#b + 1] = { x, z, r }
    end
end

-- nejbližší kmen v okruhu (x, z) – pro úhyb
local function trunksNear(x, z)
    local cx, cz = floor(x / CELL), floor(z / CELL)
    local out = nil
    for dx = -1, 1 do
        for dz = -1, 1 do
            local b = trunks[(cx + dx) * 100000 + cz + dz]
            if b then
                out = out or {}
                for i = 1, #b do out[#out + 1] = b[i] end
            end
        end
    end
    return out
end

local SEA = 0.0
-- místo, kam zvíře smí: les daného regionu, nad vodou, ne příliš strmě
local function okGround(g, x, z)
    local h, ny = map.Ground(x, z)
    if h < (g.hmin or 3.0) or h > (g.hmax or 400) or ny < 0.8 then return false end
    if g.codes and not g.codes:find(map.Region(x, z), 1, true) then return false end
    if M.Free and not M.Free(x, z) then return false end
    return true
end
M.OkGround = okGround

-- ------------------------------------------------------------------ stavba
local function spawnAnimal(sp, g, x, z, yaw, scale, tint)
    local S = M.Species[sp]
    local y = map.HeightAt(x, z)
    local id = _G.world.spawn("Models/fauna/" .. S.model .. ".glb", x, y, z, { yaw = yaw, name = S.name, scale = scale,
        lod = "auto", lod_distance = 35, tag = "fauna" })
    if tint then entity.material_color(id, "Coat*", tint) end
    local a = { id = id, sp = sp, S = S, g = g, x = x, z = z, y = y, yaw = yaw, pitch = 0, v = 0, scale = scale,
                state = "idle", timer = rnd(1, 6), clip = nil, speedMul = rnd(0.92, 1.08), visible = true,
                ox = 0, oz = 0, phase = rnd(0, 2 * pi) }
    M.list[#M.list + 1] = a
    g.members[#g.members + 1] = a
    return a
end

local function setAnim(a, clip, speed, fade)
    if a.clip ~= clip then
        anim.play(a.id, clip, fade or 0.35, clip ~= "Death")
        a.clip = clip
    end
    speed = speed or 1
    if abs((a.animSpeed or 1) - speed) > 0.03 then
        anim.speed(a.id, speed)
        a.animSpeed = speed
    end
end

local function pickTarget(g, dist0, dist1)
    for _ = 1, 24 do
        local a, d = rnd(0, 2 * pi), rnd(dist0, dist1)
        local tx, tz = g.lx + cos(a) * d, g.lz + sin(a) * d
        -- v dosahu domova (jinak zpět k domovu)
        if (tx - g.hx) ^ 2 + (tz - g.hz) ^ 2 > g.range ^ 2 then
            tx, tz = g.hx + (tx - g.hx) * 0.4, g.hz + (tz - g.hz) * 0.4
        end
        if okGround(g, tx, tz) then return tx, tz end
    end
    return g.hx, g.hz
end

function M.Spawn(opts)
    opts = opts or {}
    M.Free = opts.free
    M.list, M.groups = {}, {}
    seed = 97531
    for _, def in ipairs(M.Groups) do
        local homes = opts.scatter and opts.scatter(def.count * 6, def.codes, { hmin = 4, hmax = def.hmax or 400, slope = 0.18 }) or {}
        local placed = 0
        for _, h in ipairs(homes) do
            if placed >= def.count then break end
            local hx, hz = h[1], h[3]
            local far = true
            for _, o in ipairs(M.groups) do   -- skupiny od sebe (aspoň 350 m)
                if (o.hx - hx) ^ 2 + (o.hz - hz) ^ 2 < 350 * 350 then far = false end
            end
            if far then
                placed = placed + 1
                local g = { kind = def.kind, codes = def.codes, hmax = def.hmax, range = def.range, hx = hx, hz = hz,
                            lx = hx, lz = hz, members = {}, mode = "rest", timer = rnd(5, 20), tx = hx, tz = hz, alarm = 0 }
                M.groups[#M.groups + 1] = g
                for i, sp in ipairs(def.members) do
                    local a, d = rnd(0, 2 * pi), (i == 1) and 0 or rnd(3, 9)
                    local x, z = hx + cos(a) * d, hz + sin(a) * d
                    if not okGround(g, x, z) then x, z = hx, hz end
                    local scale = (sp == "stag" and rnd(1.0, 1.08)) or (sp == "bear" and rnd(0.92, 1.12)) or
                                  (sp == "boar" and (i == 1 and 1.1 or rnd(0.78, 0.98))) or rnd(0.9, 1.05)
                    -- odstín srsti jedince (o pár procent tmavší / světlejší, teplejší / chladnější)
                    local l, w = rnd(0.88, 1.12), rnd(-0.05, 0.05)
                    local an = spawnAnimal(sp, g, x, z, rnd(0, 360), scale, { l * (1 + w), l, l * (1 - w) })
                    an.slot = { cos(a) * d, sin(a) * d }
                    an.leader = (i == 1)
                end
                g.leader = g.members[1]
            end
        end
    end
    return M.list
end

-- ------------------------------------------------------------------ chování
local function faceYaw(dx, dz) return math.deg(atan(dx, dz)) end
local function angDiff(a, b) return (a - b + 540) % 360 - 180 end
local isNight = function() return false end

-- cíl zvířete v rámci skupiny: vůdce jde k cíli skupiny, ostatní za ním ve vlastním odstupu (vlci v řadě)
local function memberGoal(g, a, i)
    local L = g.leader
    if a == L or not L then return g.tx, g.tz end
    local hy = math.rad(L.yaw)
    local fx, fz = sin(hy), cos(hy)
    local rx, rz = fz, -fx
    local back, side
    if g.kind == "wolf" and (g.mode == "move" or g.mode == "flee") then
        back, side = (i - 1) * 2.4 + 1.0, ((i % 2 == 0) and 0.5 or -0.5) * (0.6 + 0.4 * sin(a.phase))
    else
        back, side = 2.0 + (a.slot[2] + 9) * 0.35, a.slot[1] * 0.9
    end
    -- každý vlastní, pomalu se měnící odchylka (trasy nejsou rovnoběžné)
    local wob = sin(a.phase + (g.t or 0) * 0.13) * 2.0
    return L.x - fx * back + rx * (side + wob), L.z - fz * back + rz * (side + wob)
end

local function groupUpdate(g, dt, px, pz)
    g.t = (g.t or 0) + dt
    local L = g.leader
    if not L or L.dead then return end
    g.lx, g.lz = L.x, L.z
    -- hráč: ostražitost a útěk podle druhu
    local dP = px and sqrt((px - L.x) ^ 2 + (pz - L.z) ^ 2) or 1e9
    local alert, flee = 0, 0
    if g.kind == "deer" then alert, flee = 45, 24
    elseif g.kind == "boar" then alert, flee = 25, 12
    elseif g.kind == "wolf" then alert, flee = 40, 16
    else alert, flee = 30, 0 end
    if flee > 0 and dP < flee and g.mode ~= "flee" then
        -- útěk: od hráče, 80–140 m, s ohledem na terén
        local ax, az = (L.x - px) / max(dP, 0.1), (L.z - pz) / max(dP, 0.1)
        local best, bx, bz = -1e9, nil, nil
        for k = -3, 3 do
            local an = atan(az, ax) + k * 0.35
            local d = rnd(80, 140)
            local tx, tz = L.x + cos(an) * d, L.z + sin(an) * d
            local score = (okGround(g, tx, tz) and 100 or 0) - abs(k) * 8
            if score > best then best, bx, bz = score, tx, tz end
        end
        g.tx, g.tz, g.mode, g.timer = bx, bz, "flee", 25
    elseif g.mode ~= "flee" and dP < alert and g.mode ~= "alert" and g.mode ~= "warn" then
        g.prevMode = g.mode
        g.mode, g.timer = (g.kind == "bear") and "warn" or "alert", (g.kind == "bear") and 2.6 or rnd(4, 7)
        g.watchX, g.watchZ = px, pz
    end
    g.timer = g.timer - dt
    if g.mode == "flee" then
        if (L.x - g.tx) ^ 2 + (L.z - g.tz) ^ 2 < 25 or g.timer <= 0 then g.mode, g.timer = "rest", rnd(10, 25) end
    elseif g.mode == "alert" or g.mode == "warn" then
        g.watchX, g.watchZ = px or g.watchX, pz or g.watchZ
        if g.timer <= 0 then
            if dP < alert * 0.8 then   -- hráč pořád blízko: odejít
                local ax, az = (L.x - (px or L.x)) / max(dP, 0.1), (L.z - (pz or L.z)) / max(dP, 0.1)
                g.tx, g.tz = L.x + ax * 50, L.z + az * 50
                if not okGround(g, g.tx, g.tz) then g.tx, g.tz = pickTarget(g, 30, 60) end
                g.mode, g.timer = "move", 40
            else
                g.mode, g.timer = "rest", rnd(4, 10)
            end
        end
    elseif g.mode == "move" then
        if (L.x - g.tx) ^ 2 + (L.z - g.tz) ^ 2 < 9 or g.timer <= 0 then
            g.mode, g.timer = "rest", (g.kind == "wolf") and rnd(15, 40) or rnd(25, 70)
        end
    elseif g.timer <= 0 then   -- rest -> move (nový cíl)
        local d0, d1 = 25, 70
        if g.kind == "wolf" then d0, d1 = 60, 160 elseif g.kind == "bear" then d0, d1 = 30, 90 end
        g.tx, g.tz = pickTarget(g, d0, d1)
        g.mode, g.timer = "move", 90
        g.gait = (g.kind == "wolf" and rnd() < 0.7) and "trot" or ((rnd() < 0.12) and "trot" or "walk")
    end
end

-- úhyb: kmeny, ostatní zvířata ve skupině a hráč
local function avoidance(a, px, pz)
    local ax, az = 0, 0
    local hx, hz = sin(math.rad(a.yaw)), cos(math.rad(a.yaw))
    local list = trunksNear(a.x, a.z)
    local R = a.S.r * a.scale
    if list then
        for i = 1, #list do
            local t = list[i]
            local dx, dz = a.x - t[1], a.z - t[2]
            local d = sqrt(dx * dx + dz * dz)
            local clear = t[3] + R + 0.35
            -- kmen před zvířetem v dosahu 3 m: uhnout do strany (podle toho, z které strany kmen je)
            local ahead = -(dx * hx + dz * hz)
            local side = dx * hz - dz * hx
            if ahead > -0.3 and ahead < 3.0 + R and abs(side) < clear then
                local s = side >= 0 and 1 or -1
                local k = (clear - abs(side)) / clear * (1 - max(0, ahead) / (3.5 + R))
                ax, az = ax + hz * s * k * 2.2, az - hx * s * k * 2.2
            end
            if d < clear and d > 1e-4 then   -- uvnitř: vytlačit
                ax, az = ax + dx / d * (clear - d) * 3, az + dz / d * (clear - d) * 3
            end
        end
    end
    for _, o in ipairs(a.g.members) do
        if o ~= a then
            local dx, dz = a.x - o.x, a.z - o.z
            local d2 = dx * dx + dz * dz
            local lim = R + o.S.r * o.scale + 0.3
            if d2 < lim * lim and d2 > 1e-6 then
                local d = sqrt(d2)
                ax, az = ax + dx / d * (lim - d) * 2, az + dz / d * (lim - d) * 2
            end
        end
    end
    if px then
        local dx, dz = a.x - px, a.z - pz
        local d2 = dx * dx + dz * dz
        if d2 < 4 and d2 > 1e-6 then
            local d = sqrt(d2)
            ax, az = ax + dx / d * (2 - d) * 2, az + dz / d * (2 - d) * 2
        end
    end
    return ax, az
end

local function animalUpdate(a, dt, px, pz, near)
    local g = a.g
    local i = 1
    for k, o in ipairs(g.members) do if o == a then i = k end end
    local mode = g.mode
    local S = a.S
    -- cíl a požadovaná rychlost
    local tx, tz, want, gait = a.x, a.z, 0, "walk"
    if mode == "move" or mode == "flee" then
        tx, tz = memberGoal(g, a, i)
        gait = (mode == "flee") and "run" or (g.gait or "walk")
        want = S.ref[gait] * a.speedMul
        if a ~= g.leader then   -- dohánění: daleko za vůdcem rychleji
            local d = sqrt((tx - a.x) ^ 2 + (tz - a.z) ^ 2)
            if d < 1.2 then want = g.leader.v * 0.6 end
            if d > 8 and gait == "walk" then gait, want = "trot", S.ref.trot * a.speedMul end
        end
    elseif mode == "rest" then
        -- klid: každý zvlášť – pase se, popojde pár metrů (vlastní stopa), rozhlíží se
        a.timer = a.timer - dt
        if a.timer <= 0 then
            local r = rnd()
            if r < 0.35 then
                local an, d = rnd(0, 2 * pi), rnd(2, 7)
                local nx, nz = a.x + cos(an) * d, a.z + sin(an) * d
                -- drží se u skupiny
                if (nx - g.leader.x) ^ 2 + (nz - g.leader.z) ^ 2 < 14 * 14 and okGround(g, nx, nz) then
                    a.wx, a.wz = nx, nz
                end
                a.timer = rnd(4, 9)
            else
                a.wx = nil
                a.restClip = nil
                a.timer = rnd(5, 16)
            end
        end
        if a.wx then
            tx, tz = a.wx, a.wz
            want = S.ref.walk * 0.8 * a.speedMul
            if (tx - a.x) ^ 2 + (tz - a.z) ^ 2 < 0.5 then a.wx = nil end
        end
    end
    -- pohyb: natočení, zrychlení, úhyb
    local dx, dz = tx - a.x, tz - a.z
    local dist = sqrt(dx * dx + dz * dz)
    if dist > 0.3 and want > 0 then
        local turn = angDiff(faceYaw(dx, dz), a.yaw)
        local step = S.turn * (gait == "run" and 1.3 or 1) * dt
        a.yaw = a.yaw + max(-step, min(step, turn))
        if abs(turn) > 75 then want = want * 0.25 end   -- ostrá otočka: nejdřív se natočí
        if dist < 2 and a.leader then want = min(want, max(0.4, dist)) end
    else
        want = 0
    end
    local acc = (gait == "run") and 6 or 2.5
    a.v = a.v + max(-acc * dt, min(acc * 0.8 * dt, want - a.v))
    local ax, az = avoidance(a, px, pz)
    local hy = math.rad(a.yaw)
    local nx = a.x + (sin(hy) * a.v + ax) * dt
    local nz = a.z + (cos(hy) * a.v + az) * dt
    -- kmen stromu: nikdy dovnitř – vysune se na okraj (sklouzne po kmeni do strany)
    local list = trunksNear(nx, nz)
    if list then
        local R = S.r * a.scale * 0.6
        for k = 1, #list do
            local t = list[k]
            local ex, ez = nx - t[1], nz - t[2]
            local lim = t[3] + R
            local e2 = ex * ex + ez * ez
            if e2 < lim * lim then
                local e = sqrt(e2)
                if e < 1e-4 then ex, ez, e = sin(hy + pi / 2), cos(hy + pi / 2), 1 end
                nx, nz = t[1] + ex / e * lim, t[2] + ez / e * lim
            end
        end
    end
    -- ostatní zvířata skupiny: nikdy v sobě (minimální odstup podle velikosti těl)
    for _, o in ipairs(g.members) do
        if o ~= a then
            local ex, ez = nx - o.x, nz - o.z
            local lim = (S.r * a.scale + o.S.r * o.scale) * 0.8
            local e2 = ex * ex + ez * ez
            if e2 < lim * lim then
                local e = sqrt(e2)
                if e < 1e-4 then ex, ez, e = cos(a.phase), sin(a.phase), 1 end
                nx, nz = o.x + ex / e * lim, o.z + ez / e * lim
            end
        end
    end
    -- nevstoupí do vody / na útes: zastaví a otočí se
    local h, ny = map.Ground(nx, nz)
    if h < 2.0 or ny < 0.72 then
        a.v = 0
        a.yaw = a.yaw + 90 * dt
        nx, nz = a.x, a.z
    else
        a.x, a.z = nx, nz
    end
    if near then
        -- výška a náklon podle svahu (před a za tělem)
        local half = S.len * 0.38 * a.scale
        local hf = map.HeightAt(a.x + sin(hy) * half, a.z + cos(hy) * half)
        local hb = map.HeightAt(a.x - sin(hy) * half, a.z - cos(hy) * half)
        a.y = (hf + hb) * 0.5
        local p = -math.deg(atan(hf - hb, 2 * half))
        a.pitch = a.pitch + (max(-22, min(22, p)) - a.pitch) * min(1, dt * 6)
    else
        a.y = map.HeightAt(a.x, a.z)
        a.pitch = 0
    end
    -- animace podle rychlosti a stavu
    if a.v > 0.15 then
        local clip, ref = "Walk", S.ref.walk
        if a.v > (S.ref.trot + S.ref.run) * 0.5 then clip, ref = "Run", S.ref.run
        elseif a.v > (S.ref.walk + S.ref.trot) * 0.55 then clip, ref = "Trot", S.ref.trot end
        setAnim(a, clip, max(0.5, min(1.6, a.v / ref)), 0.3)
    else
        local clip = "Idle"
        if mode == "alert" or mode == "warn" then
            clip = "Idle_Look"
            if g.watchX then   -- otočí se k hráči
                local t = angDiff(faceYaw(g.watchX - a.x, g.watchZ - a.z), a.yaw)
                a.yaw = a.yaw + max(-60 * dt, min(60 * dt, t))
            end
            if mode == "warn" and a.sp == "bear" then
                clip = (g.timer > 1.0) and "Roar" or "Idle_Look"
                if px and (px - a.x) ^ 2 + (pz - a.z) ^ 2 < 64 then clip = "Attack" end   -- výpad naoko
            end
        elseif mode == "rest" then
            -- vlastní volba: pastva / slídění, rozhlížení, u vlků v noci vytí, jelen občas troubí
            if not a.restClip then
                local r = rnd()
                if a.sp == "wolf" then
                    a.restClip = (isNight() and r < 0.3) and "Howl" or (r < 0.5 and "Graze" or (r < 0.75 and "Idle_Look" or "Idle"))
                elseif a.sp == "stag" and r < 0.12 then
                    a.restClip = "Roar"
                else
                    a.restClip = r < 0.62 and "Graze" or (r < 0.82 and "Idle" or "Idle_Look")
                end
            end
            clip = a.restClip
        end
        setAnim(a, clip, a.idleSpeed or 1, 0.45)
    end
end

local function cameraPos()
    local cam = entity.find and entity.find("Camera")
    if not cam then return nil end
    local x, y, z = entity.get_position(cam)
    if type(x) == "table" then return x.x or x[1], x.z or x[3] end
    return x, z
end

local acc, slowAcc = 0, 0
M.HideDistance = 400
function M.Update(dt, px, pz, timeOfDay)
    if #M.list == 0 then return end
    isNight = function() return timeOfDay and (timeOfDay > 20.5 or timeOfDay < 4.5) end
    local cx, cz = cameraPos()
    cx, cz = cx or px or 0, cz or pz or 0
    dt = min(dt, 0.1)
    acc, slowAcc = acc + dt, slowAcc + dt
    local mid = acc >= 0.2
    local slow = slowAcc >= 1.0
    if mid then acc = 0 end
    if slow then slowAcc = 0 end
    for _, g in ipairs(M.groups) do
        local L = g.leader
        local d2 = (L.x - cx) ^ 2 + (L.z - cz) ^ 2
        g.near = d2 < 120 * 120
        g.mid = d2 < (M.HideDistance + 60) ^ 2
        local step = g.near and dt or (g.mid and (mid and 0.2 or 0) or (slow and 1.0 or 0))
        if step > 0 then
            groupUpdate(g, step, px, pz)
            for _, a in ipairs(g.members) do
                local ad2 = (a.x - cx) ^ 2 + (a.z - cz) ^ 2
                local vis = ad2 < M.HideDistance ^ 2
                if vis ~= a.visible then
                    a.visible = vis
                    entity.set_visible(a.id, vis)
                end
                animalUpdate(a, step, px, pz, ad2 < 60 * 60)
                if a.visible then
                    entity.set_position(a.id, a.x, a.y, a.z)
                    entity.set_rotation(a.id, a.pitch, a.yaw, 0)
                end
            end
        end
    end
end

return M
