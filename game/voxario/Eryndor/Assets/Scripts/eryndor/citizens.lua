-- Obyvatelé Valorie: 30 pohyblivých NPC (rytíři, těžkooděnci, lukostřelci) a hlavní kapitán na náměstí.
-- Chodí jen po dlážděné hlavní ulici a náměstí (nikdy branou ven, nikdy do domů), každý vlastním tempem,
-- vlastní stopou a s vlastními zastávkami; dvojice se zastaví a povídají si (Talking_A / Talking_B / Listening),
-- stráže stojí na stanovištích, hlídky chodí ve dvojici. Vyhýbají se sobě navzájem i hráči.
-- Výkon: pohyb jen pro NPC v dosahu kamery (vzdálené 10x za sekundu, za 320 m nic a skryté), žádné raycasty
-- (ulice i náměstí jsou rovné – výška = podlaha brány), engine animuje vzdálené a skryté postavy úsporně.
local humans = require("eryndor.humans")
local M = { list = {}, captain = nil }
local sin, cos, sqrt, atan, floor, max, min, pi, abs = math.sin, math.cos, math.sqrt, math.atan, math.floor, math.max,
    math.min, math.pi, math.abs

-- pochozí plochy (shodné s valoria.lua / tools/valoria_city.py): ulice od brány k náměstí a kruhové náměstí
M.Street = { x0 = 2729.0, x1 = 2932.0, z = 2400.0, half = 3.6 }    -- lucerny v |dz| = 4,6, domy v 6 m; ulice vbíhá do náměstí
M.Plaza = { x = 2945.0, z = 2400.0, r = 20.5 }                     -- sochy hrdinů v r = 26
M.Center = { x = 2830.0, z = 2400.0 }
M.Count = 30
local WALK_REF = 1.5      -- rychlost, pro kterou je klip chůze (Walking_A) bez klouzání chodidel

-- deterministický náhodný generátor (stejné rozestavení u všech hráčů)
local seed = 1234567
local function rnd(a, b)
    seed = (seed * 1103515245 + 12345) % 2147483648
    local r = seed / 2147483648
    if a then return a + (b - a) * r end
    return r
end

local function inStreet(x, z) return x >= M.Street.x0 and x <= M.Street.x1 and abs(z - M.Street.z) <= M.Street.half end
local function inPlaza(x, z) return (x - M.Plaza.x) ^ 2 + (z - M.Plaza.z) ^ 2 <= M.Plaza.r ^ 2 end
M.InStreet, M.InPlaza = inStreet, inPlaza
function M.Walkable(x, z) return inStreet(x, z) or inPlaza(x, z) end

-- nejbližší bod pochozí plochy
local function project(x, z)
    if inStreet(x, z) or inPlaza(x, z) then return x, z end
    local sx = min(max(x, M.Street.x0), M.Street.x1)
    local sz = min(max(z, M.Street.z - M.Street.half), M.Street.z + M.Street.half)
    local dx, dz = x - M.Plaza.x, z - M.Plaza.z
    local d = sqrt(dx * dx + dz * dz)
    local px, pz = M.Plaza.x + dx / d * M.Plaza.r * 0.999, M.Plaza.z + dz / d * M.Plaza.r * 0.999
    if (x - sx) ^ 2 + (z - sz) ^ 2 < (x - px) ^ 2 + (z - pz) ^ 2 then return sx, sz end
    return px, pz
end
M.Project = project

local function randomSpot(prefPlaza)
    if rnd() < prefPlaza then
        local a, r = rnd(0, 2 * pi), M.Plaza.r * sqrt(rnd(0.05, 0.92))
        return M.Plaza.x + cos(a) * r, M.Plaza.z + sin(a) * r
    end
    return rnd(M.Street.x0 + 2, M.Street.x1 - 1), M.Street.z + rnd(-M.Street.half, M.Street.half) * 0.92
end

-- trasa: v ulici přímo (s mírným obloukem), mezi ulicí a náměstím přes ústí ulice ve vlastní stopě
local function route(n, tx, tz)
    local pts = {}
    local fromPlaza, toPlaza = inPlaza(n.x, n.z) and not inStreet(n.x, n.z), inPlaza(tx, tz) and not inStreet(tx, tz)
    if fromPlaza ~= toPlaza then
        local lane = M.Street.z + n.lane
        pts[#pts + 1] = { M.Street.x1 - 0.5, lane }
    elseif not toPlaza and abs(tx - n.x) > 25 then   -- dlouhá cesta ulicí: mírný oblouk
        local mx = (n.x + tx) / 2
        pts[#pts + 1] = { mx, M.Street.z + max(-M.Street.half * 0.9, min(M.Street.half * 0.9, n.lane + rnd(-1.2, 1.2))) }
    end
    pts[#pts + 1] = { tx, tz }
    n.path, n.pi = pts, 1
end

local function setAnim(n, clip, fade, speed)
    if n.clip ~= clip then
        anim.play(n.id, clip, fade or 0.3, true)
        n.clip = clip
    end
    if speed and abs((n.animSpeed or 1) - speed) > 0.02 then
        anim.speed(n.id, speed)
        n.animSpeed = speed
    end
end

-- ------------------------------------------------------------------ vzhled
local LOOKS = {
    knight = { model = "syl_knight_m", right = "sword", left = "shield" },
    heavy = { model = "aeth_heavy_m", right = "sword2" },
    archer_m = { model = "syl_archer_m", left = "bow", quiver = true },
    archer_f = { model = "aeth_archer_f", left = "bow", quiver = true },
}
-- barvy látek (tabardy, pláště): modrá Valorie, karmínová, tmavě zelená, šedá
local CLOTH = { { 0.55, 0.68, 1.0 }, { 1.0, 0.55, 0.5 }, { 0.6, 0.85, 0.6 }, { 0.85, 0.85, 0.85 }, { 1.0, 0.9, 0.65 } }

local function dress(kind, x, z, yaw, name)
    local L = LOOKS[kind]
    local helm = (kind == "knight" or kind == "heavy") and rnd() < 0.45
    local id = humans.Spawn(L.model, x, M.Y, z, { yaw = yaw, name = name, right = L.right, left = L.left, helm = helm,
        scale = rnd(0.95, 1.05), tag = "npc" })
    if kind == "archer_m" then   -- lukostřelec: lehčí výstroj bez plechových ramen a holení
        for _, p in ipairs({ "Armor_Shoulder_*", "Armor_Greaves*", "Helm*", "Emblem*" }) do entity.show_part(id, p, false) end
    elseif kind == "archer_f" then
        for _, p in ipairs({ "Goggles*" }) do entity.show_part(id, p, false) end
    end
    if rnd() < 0.35 then entity.show_part(id, "Cape", false) end
    local c = CLOTH[floor(rnd(1, #CLOTH + 0.999))]
    entity.material_color(id, "cloth*", c)
    if L.quiver then   -- toulec se šípy na zádech
        local q = _G.world.spawn("Models/gear/real/quiver.glb", 0, 0, 0, { name = "toulec" })
        entity.attach(q, id, "spine_03")
        entity.set_position(q, -0.08, 0.12, -0.17)
        entity.set_rotation(q, 8, 0, -22)
    end
    return id
end

-- ------------------------------------------------------------------ stavba
local GUARDS = {   -- stanoviště stráží {x, z, pohled}
    { 2730.0, 2396.6, 90 }, { 2730.0, 2403.4, 90 },        -- hned za branou, čelem do ulice
    { 2933.0, 2381.5, 15 }, { 2957.0, 2381.5, -15 },       -- u katedrály na severu náměstí
    { 2850.0, 2396.8, 0 }, { 2800.0, 2403.2, 180 },        -- v půli ulice u domů
}

function M.Spawn(valoria)
    M.Y = valoria.GateY
    M.list = {}
    seed = 1234567
    local kinds = { "knight", "knight", "heavy", "archer_m", "knight", "archer_f", "heavy", "archer_m", "knight", "archer_f" }
    local names = { knight = "Rytíř Valorie", heavy = "Těžkooděnec", archer_m = "Lukostřelec", archer_f = "Lukostřelkyně" }
    local idx = 0
    local function add(kind, role, x, z, yaw)
        idx = idx + 1
        local n = { kind = kind, role = role, x = x, z = z, yaw = yaw, v = 0, state = "idle", timer = rnd(0.5, 4),
                    speed = rnd(1.05, 1.42), lane = rnd(-M.Street.half * 0.85, M.Street.half * 0.85),
                    prefPlaza = rnd(0.25, 0.7), pause = rnd(2.5, 9), turnRate = rnd(150, 230), idx = idx }
        n.id = dress(kind, x, z, yaw, names[kind])
        setAnim(n, (role == "guard" and rnd() < 0.5) and "Idle_LookAround" or "Idle", 0, rnd(0.85, 1.1))
        M.list[#M.list + 1] = n
        return n
    end
    -- stráže
    for i, gpos in ipairs(GUARDS) do add(i % 3 == 0 and "archer_m" or (i % 2 == 0 and "heavy" or "knight"), "guard", gpos[1], gpos[2], gpos[3]) end
    -- dvě hlídky (dvojice jdou vedle sebe ulicí tam a zpět)
    for p = 1, 2 do
        local x = p == 1 and 2760 or 2880
        local a = add("knight", "patrol", x, M.Street.z - 1.0, 90)
        local b = add(p == 1 and "heavy" or "archer_m", "patrol", x, M.Street.z + 1.0, 90)
        a.partner, b.partner, b.follower = b, a, true
        a.speed, a.lane = 1.15, -1.0
        b.speed, b.lane = 1.15, 1.0
    end
    -- chodci po ulici a náměstí
    while #M.list < M.Count do
        local kind = kinds[(#M.list % #kinds) + 1]
        local x, z = randomSpot(0.45)
        add(kind, "walker", x, z, rnd(0, 360))
    end
    for _, n in ipairs(M.list) do
        entity.set_position(n.id, n.x, M.Y, n.z)
        entity.set_rotation(n.id, 0, n.yaw, 0)
    end
    -- hlavní kapitán na náměstí: plášť, brnění, obouruční meč, bez helmy; připravený zadávat úkoly
    local cx, cz = M.Plaza.x, M.Plaza.z - 13.0
    M.captain = { x = cx, z = cz, yaw = 0, baseYaw = 0, name = "Kapitán Roderik Valorský" }
    M.captain.id = humans.Spawn("aeth_heavy_m", cx, M.Y, cz, { yaw = 0, name = M.captain.name, right = "sword2", helm = false,
        tag = "npc" })
    entity.show_part(M.captain.id, "Cape", true)
    entity.material_color(M.captain.id, "cloth*", { 0.55, 0.12, 0.12 })   -- karmínový plášť a tabard velitele
    anim.play(M.captain.id, "Idle", 0, true)
    M.captain.clip, M.captain.timer = "Idle", 6
end

-- ------------------------------------------------------------------ chování
local function startWalk(n, tx, tz)
    if n.role == "walker" then n.lane = rnd(-M.Street.half * 0.88, M.Street.half * 0.88) end   -- vlastní stopa na každou cestu
    route(n, tx, tz)
    n.state = "walk"
end

local function startTalk(a, b)
    -- místo setkání: mezi nimi, na pochozí ploše; každý se postaví 0,7 m od středu čelem k druhému
    local mx, mz = project((a.x + b.x) / 2, (a.z + b.z) / 2)
    local dx, dz = b.x - a.x, b.z - a.z
    local d = sqrt(dx * dx + dz * dz)
    if d < 0.01 then dx, dz, d = 1, 0, 1 end
    dx, dz = dx / d, dz / d
    local ax, az = project(mx - dx * 0.72, mz - dz * 0.72)
    local bx, bz = project(mx + dx * 0.72, mz + dz * 0.72)
    if (ax - bx) ^ 2 + (az - bz) ^ 2 < 1.2 * 1.2 then   -- u okraje: a zůstane, b přijde k němu
        ax, az = a.x, a.z
        bx, bz = project(a.x + dx * 1.45, a.z + dz * 1.45)
        if (ax - bx) ^ 2 + (az - bz) ^ 2 < 1.2 * 1.2 then return false end
    end
    a.talk, b.talk = b, a
    a.talkTime = rnd(9, 18)
    b.talkTime = a.talkTime
    a.speaker, b.speaker = true, false
    a.turnTimer, b.turnTimer = rnd(2.5, 5), 0
    startWalk(a, ax, az)
    startWalk(b, bx, bz)
    a.state, b.state = "toTalk", "toTalk"
    return true
end

local function endTalk(n)
    if n.talk then n.away = { n.x - n.talk.x, n.z - n.talk.z } end   -- po rozhovoru každý jinam
    n.talk = nil
    n.state = "idle"
    n.timer = rnd(0.4, 2.5)
end

local function faceYaw(dx, dz) return math.deg(atan(dx, dz)) end
local function turnTo(n, target, dt)
    local d = (target - n.yaw + 540) % 360 - 180
    local step = n.turnRate * dt
    if abs(d) <= step then n.yaw = target else n.yaw = n.yaw + (d > 0 and step or -step) end
    return abs(d)
end

local function pickTarget(n)
    if n.role == "patrol" then
        if n.follower then return end
        local tx = (n.x < 2830) and rnd(2880, 2912) or rnd(2732, 2770)
        startWalk(n, tx, M.Street.z + n.lane)
        local p = n.partner
        startWalk(p, tx, M.Street.z + p.lane)
        return
    end
    local x, z
    if rnd() < 0.62 then   -- většinou kratší procházka v okolí (ulice / náměstí), jen občas přes celé město
        for _ = 1, 8 do
            if inPlaza(n.x, n.z) and not inStreet(n.x, n.z) then
                local a, r = rnd(0, 2 * pi), M.Plaza.r * sqrt(rnd(0.05, 0.92))
                x, z = M.Plaza.x + cos(a) * r, M.Plaza.z + sin(a) * r
            else
                x = min(M.Street.x1 - 2, max(M.Street.x0 + 2, n.x + rnd(-45, 45)))
                z = M.Street.z + rnd(-M.Street.half, M.Street.half) * 0.92
            end
            local away = not n.away or (x - n.x) * n.away[1] + (z - n.z) * n.away[2] > 0
            if (x - n.x) ^ 2 + (z - n.z) ^ 2 > 64 and away then break end
        end
        n.away = nil
    else
        x, z = randomSpot(n.prefPlaza)
    end
    startWalk(n, x, z)
end

-- vyhýbání: ostatní NPC (1,1 m), hráč (1,7 m); vrátí korekci směru a zpomalení
local function avoid(n, px, pz)
    local ax, az, slow = 0, 0, 1
    local hx, hz = sin(math.rad(n.yaw)), cos(math.rad(n.yaw))
    for _, o in ipairs(M.list) do
        if o ~= n and o ~= n.partner then
            local dx, dz = n.x - o.x, n.z - o.z
            local d2 = dx * dx + dz * dz
            if d2 < 1.6 and d2 > 1e-6 then
                local d = sqrt(d2)
                ax, az = ax + dx / d * (1.25 - d), az + dz / d * (1.25 - d)
                if -(dx * hx + dz * hz) > 0.4 * d and o.state ~= "walk" then slow = min(slow, max(0.25, (d - 0.55) / 0.7)) end
            end
        end
    end
    local cap = M.captain
    if cap then   -- kapitán stojí: obejít ho
        local dx, dz = n.x - cap.x, n.z - cap.z
        local d2 = dx * dx + dz * dz
        if d2 < 2.4 and d2 > 1e-6 then
            local d = sqrt(d2)
            ax, az = ax + dx / d * (1.55 - d), az + dz / d * (1.55 - d)
        end
    end
    if px then
        local dx, dz = n.x - px, n.z - pz
        local d2 = dx * dx + dz * dz
        if d2 < 3.0 and d2 > 1e-6 then
            local d = sqrt(d2)
            ax, az = ax + dx / d * (1.75 - d) * 1.4, az + dz / d * (1.75 - d) * 1.4
            if -(dx * hx + dz * hz) > 0.3 * d then slow = min(slow, max(0.0, (d - 0.8) / 0.9)) end
        end
    end
    return ax, az, slow
end

local function updateWalker(n, dt, px, pz)
    if n.state == "idle" then
        n.v = max(0, n.v - 3 * dt)
        setAnim(n, n.idleClip or "Idle", 0.35, n.idleSpeed or 1)
        n.timer = n.timer - dt
        if n.timer <= 0 and n.role ~= "guard" and not (n.follower and n.partner.state ~= "walk") then
            if n.role == "walker" and not n.talk then
                -- občas si najde partnera k rozhovoru (někoho blízko, kdo zrovna stojí nebo jde kolem)
                if rnd() < 0.42 then
                    local best, bd = nil, 18 * 18
                    for _, o in ipairs(M.list) do
                        if o ~= n and o.role == "walker" and not o.talk and (o.state == "idle" or o.state == "walk") then
                            local d = (o.x - n.x) ^ 2 + (o.z - n.z) ^ 2
                            if d < bd then best, bd = o, d end
                        end
                    end
                    if best and startTalk(n, best) then return end
                end
            end
            pickTarget(n)
        end
        return
    end
    if n.state == "talk" then
        n.v = 0
        local o = n.talk
        if not o or o.talk ~= n then endTalk(n); return end
        turnTo(n, faceYaw(o.x - n.x, o.z - n.z), dt)
        n.turnTimer = n.turnTimer - dt
        if n.speaker and n.turnTimer <= 0 then   -- střídání v řeči
            n.speaker, o.speaker = false, true
            o.turnTimer = rnd(2.5, 6)
        end
        if n.speaker then
            n.talkClip = n.talkClip or (rnd() < 0.5 and "Talking_A" or "Talking_B")
            setAnim(n, n.talkClip, 0.45, n.idleSpeed or 1)
        else
            n.talkClip = nil
            setAnim(n, "Listening", 0.45, n.idleSpeed or 1)
        end
        n.talkTime = n.talkTime - dt
        if n.talkTime <= 0 then
            endTalk(n)
            if o.talk == n then endTalk(o) end
        end
        return
    end
    -- chůze (walk / toTalk): směr k dalšímu bodu, plynulé zrychlení, otáčení, vyhýbání
    local p = n.path and n.path[n.pi]
    if not p then
        if n.state == "toTalk" then
            if n.talk and n.talk.talk == n and (n.talk.state == "talk" or n.talk.state == "toTalk") then
                n.state = "talk"
            else
                endTalk(n)
            end
        else
            n.state = "idle"
            n.timer = n.pause * rnd(0.6, 1.4)
            n.idleClip = rnd() < 0.35 and "Idle_LookAround" or "Idle"
            n.idleSpeed = rnd(0.85, 1.1)
        end
        return
    end
    local dx, dz = p[1] - n.x, p[2] - n.z
    local d = sqrt(dx * dx + dz * dz)
    if d < 0.35 then
        n.pi = n.pi + 1
        return
    end
    if not n.path[n.pi + 1] and d < 1.3 and n.state == "walk" then   -- cíl obsazený: zastaví se kousek před ním
        for _, o in ipairs(M.list) do
            if o ~= n and o.state ~= "walk" and (o.x - p[1]) ^ 2 + (o.z - p[2]) ^ 2 < 1.0 then
                n.path[n.pi] = nil
                return
            end
        end
    end
    local want = faceYaw(dx, dz)
    local turn = turnTo(n, want, dt)
    -- ostrá otočka: nejdřív se na místě natočí (bez klouzání), pak teprve vykročí
    local target = turn > 70 and 0 or n.speed * (n.state == "toTalk" and 0.9 or 1)
    if n.follower then target = n.partner.v end
    local ax, az, slow = avoid(n, px, pz)
    -- předcházení: pomalejší chodec před námi stejným směrem -> plynule bokem (strana s víc místem)
    local hy0 = math.rad(n.yaw)
    local fx, fz = sin(hy0), cos(hy0)
    for _, o in ipairs(M.list) do
        if o ~= n and o ~= n.partner then
            local dx2, dz2 = o.x - n.x, o.z - n.z
            local ahead = dx2 * fx + dz2 * fz
            local side = dx2 * fz - dz2 * fx
            if ahead > 0.3 and ahead < 3.5 and abs(side) < 1.2 then
                local same = abs((o.yaw - n.yaw + 540) % 360 - 180) < 50
                if (same and o.v < n.v * 0.95) or o.state ~= "walk" then
                    local sgn = side > 0 and -1 or 1
                    if not inStreet(n.x + fz * sgn * 1.5, n.z - fx * sgn * 1.5) and not inPlaza(n.x + fz * sgn * 1.5, n.z - fx * sgn * 1.5) then
                        sgn = -sgn
                    end
                    ax, az = ax + fz * sgn * 0.7, az - fx * sgn * 0.7
                end
            end
        end
    end
    -- v ulici drží svou stopu (vzdálenost od středu ulice), dokud nemíří do cíle napříč
    if inStreet(n.x, n.z) and not inPlaza(n.x, n.z) and abs(dx) > 4 * abs(dz) and d > 4 then
        az = az + (M.Street.z + n.lane - n.z) * 0.35
    end
    target = target * slow
    if not n.path[n.pi + 1] then target = min(target, max(0.35, d * 1.2)) end   -- zpomalení před cílem
    n.v = n.v + max(-3.0 * dt, min(2.2 * dt, target - n.v))
    local hy = math.rad(n.yaw)
    local mx, mz = sin(hy) * n.v + ax * 0.9, cos(hy) * n.v + az * 0.9
    local nx, nz = project(n.x + mx * dt, n.z + mz * dt)
    -- nikdy do sebe: minimální rozestup 0,6 m od ostatních (u partnera v hlídce 0,8 m)
    for _, o in ipairs(M.list) do
        if o ~= n then
            local ex, ez = nx - o.x, nz - o.z
            local e2 = ex * ex + ez * ez
            local lim = (o == n.partner) and 0.8 or 0.6
            if e2 < lim * lim then
                local e = sqrt(e2)
                if e < 1e-4 then ex, ez, e = cos(n.idx), sin(n.idx), 1 end
                nx, nz = project(o.x + ex / e * lim, o.z + ez / e * lim)
            end
        end
    end
    n.x, n.z = nx, nz
    if n.v > 0.08 then
        setAnim(n, "Walking_A", 0.28, max(0.45, n.v / WALK_REF))
    else
        setAnim(n, "Idle", 0.3, 1)
    end
end

local function updateGuard(n, dt)
    n.timer = n.timer - dt
    if n.timer <= 0 then
        n.timer = rnd(6, 14)
        local clip = rnd() < 0.4 and "Idle_LookAround" or "Idle"
        setAnim(n, clip, 0.5, rnd(0.85, 1.05))
    end
end

local function updateCaptain(dt, px, pz)
    local c = M.captain
    if not c then return end
    local target = c.baseYaw
    if px and (px - c.x) ^ 2 + (pz - c.z) ^ 2 < 9 * 9 then target = faceYaw(px - c.x, pz - c.z) end
    local d = (target - c.yaw + 540) % 360 - 180
    c.yaw = c.yaw + max(-120 * dt, min(120 * dt, d))
    entity.set_rotation(c.id, 0, c.yaw, 0)
    c.timer = c.timer - dt
    if c.timer <= 0 then   -- občas se rozhlédne po náměstí nebo gestikuluje (dává pokyny strážím)
        local r = rnd()
        c.clip = r < 0.3 and "Idle_LookAround" or (r < 0.5 and "Talking_A" or "Idle")
        anim.play(c.id, c.clip, 0.5, true)
        c.timer = c.clip == "Talking_A" and rnd(4, 7) or rnd(7, 14)
    end
end

local function cameraPos()
    local cam = entity.find and entity.find("Camera")
    if not cam then return nil end
    local a, b, c = entity.get_position(cam)
    if type(a) == "table" then return a.x or a[1], a.y or a[2], a.z or a[3] end
    return a, b, c
end

M.hidden = false
local acc = 0
function M.Update(dt, px, pz)
    if #M.list == 0 then return end
    local cx, _, cz = cameraPos()
    cx, cz = cx or px or M.Center.x, cz or pz or M.Center.z
    local far = (cx - M.Center.x) ^ 2 + (cz - M.Center.z) ^ 2 > 320 * 320
    if far ~= M.hidden then   -- daleko od města: skrýt a nepočítat
        M.hidden = far
        for _, n in ipairs(M.list) do entity.set_visible(n.id, not far) end
        if M.captain then entity.set_visible(M.captain.id, not far) end
    end
    if far then return end
    dt = min(dt, 0.1)
    -- pojistka: klip spuštěný ještě před načtením modelu se mohl ztratit -> každé 2 s ověřit a případně spustit znovu
    M.check = (M.check or 0) + dt
    if M.check > 2.0 then
        M.check = 0
        local function ensure(id, clip)
            if clip and anim.current and anim.current(id) ~= clip then anim.play(id, clip, 0.2, true) end
        end
        for _, n in ipairs(M.list) do ensure(n.id, n.clip) end
        if M.captain then ensure(M.captain.id, M.captain.clip) end
    end
    acc = acc + dt
    local slowTick = acc >= 0.1
    if slowTick then acc = 0 end
    for _, n in ipairs(M.list) do
        local near = (n.x - cx) ^ 2 + (n.z - cz) ^ 2 < 90 * 90
        if near or slowTick then   -- vzdálené NPC jen 10x za sekundu (z dálky nerozeznatelné)
            local step = near and dt or max(dt, 0.1)
            if n.role == "guard" then
                updateGuard(n, step)
            else
                updateWalker(n, step, px, pz)
                entity.set_position(n.id, n.x, M.Y, n.z)
                entity.set_rotation(n.id, 0, n.yaw, 0)
            end
        end
    end
    updateCaptain(dt, px, pz)
end

-- kapitán: hráč blízko (dialog F) – úkoly zatím nejsou, jen přivítání
function M.NearCaptain(px, pz)
    local c = M.captain
    return c and px and (px - c.x) ^ 2 + (pz - c.z) ^ 2 < 4.5 * 4.5
end

return M
