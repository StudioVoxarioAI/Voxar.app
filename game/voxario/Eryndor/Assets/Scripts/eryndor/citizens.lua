-- Obyvatelé Valorie: 50 pohyblivých NPC (rytíři, těžkooděnci, lukostřelci) a hlavní kapitán na náměstí.
-- 30 jich chodí po dlážděné hlavní ulici a náměstí (nikdy branou ven, nikdy do domů), 14 po uličkách čtvrtí
-- a cestě ke hradu (síť uliček se při stavbě ověří proti půdorysům všech domů, věží a hradu), 6 po nábřeží
-- v přístavu. Každý vlastním tempem,
-- vlastní stopou a s vlastními zastávkami; dvojice se zastaví a povídají si (Talking_A / Talking_B / Listening),
-- stráže stojí na stanovištích, hlídky chodí ve dvojici. Vyhýbají se sobě navzájem i hráči.
-- Výkon: plný pohyb jen do 90 m od kamery (vzdálené 10x za sekundu), dál než 150 m skryté (nekreslí se ani
-- neanimují), žádné raycasty (výška: rovná ulice / nábřeží, v uličkách výškové pole terénu), vyhýbání jen
-- uvnitř vlastní skupiny.
local humans = require("eryndor.humans")
local map = require("eryndor.map")
local M = { list = {}, core = {}, town = {}, harbor = {}, captain = nil }
local sin, cos, sqrt, atan, floor, max, min, pi, abs = math.sin, math.cos, math.sqrt, math.atan, math.floor, math.max,
    math.min, math.pi, math.abs

-- pochozí plochy (shodné s valoria.lua / tools/valoria_city.py): ulice od brány k náměstí a kruhové náměstí
M.Street = { x0 = 2729.0, x1 = 2932.0, z = 2400.0, half = 3.6 }    -- lucerny v |dz| = 4,6, domy v 6 m; ulice vbíhá do náměstí
M.Plaza = { x = 2945.0, z = 2400.0, r = 20.5 }                     -- sochy hrdinů v r = 26
M.Center = { x = 2830.0, z = 2400.0 }
M.Count = 30            -- hlavní ulice a náměstí
M.TownCount = 14        -- uličky čtvrtí a cesta ke hradu
M.HarborCount = 6       -- nábřeží v přístavu
M.HideDistance = 150    -- dál od kamery se NPC skryjí (hystereze ±10 m)
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


-- ------------------------------------------------------------------ celé město: uličky čtvrtí, cesta ke hradu, nábřeží
-- půdorysy staveb (poloviční rozměry z modelů tools/valoria_city.py; u domů větší z obou stran osy Z)
local FOOT = { house_0 = { 5.3, 5.0 }, house_1 = { 5.0, 5.9 }, house_2 = { 5.8, 5.0 }, house_3 = { 4.8, 5.4 },
               tower_a = { 4.8, 4.8 }, tower_b = { 4.1, 4.1 }, tower_c = { 5.8, 5.8 }, tower_round = { 4.3, 4.3 },
               wall_tower = { 4.3, 4.3 }, dome_hall = { 11.5, 14.3 }, gate_valorie = { 15.8, 5.5 },
               city_wall = { 12.0, 1.6 }, city_wall_6 = { 3.0, 1.6 } }
local CELL = 16
local obstacles = {}   -- prostorový hash: buňka -> {x, z, hx, hz}

local function addObstacle(x, z, hx, hz)
    local o = { x, z, hx, hz }
    for cx = floor((x - hx - 3) / CELL), floor((x + hx + 3) / CELL) do
        for cz = floor((z - hz - 3) / CELL), floor((z + hz + 3) / CELL) do
            local k = cx * 100000 + cz
            local b = obstacles[k]
            if not b then b = {}; obstacles[k] = b end
            b[#b + 1] = o
        end
    end
end

local function addFootprint(kind, x, z, yaw, scale)
    local f = FOOT[kind]
    if not f then return end
    local hx, hz = f[1] * (scale or 1), f[2] * (scale or 1)
    local a = ((yaw or 0) % 180 + 180) % 180
    if abs(a - 90) < 1 then hx, hz = hz, hx
    elseif a > 1 and a < 179 then local r = sqrt(hx * hx + hz * hz); hx, hz = r, r end   -- šikmá hradba: obalový čtverec
    addObstacle(x, z, hx, hz)
end

-- volno v okruhu c metrů od všech staveb
local function clearAt(x, z, c)
    local b = obstacles[floor(x / CELL) * 100000 + floor(z / CELL)]
    if not b then return true end
    for i = 1, #b do
        local o = b[i]
        local dx, dz = max(abs(x - o[1]) - o[3], 0), max(abs(z - o[2]) - o[4], 0)
        if dx * dx + dz * dz < c * c then return false end
    end
    return true
end
M.ClearAt = clearAt

M.Nodes, M.Edges = {}, {}
local plateauRadius
-- bod sítě uliček: na plošině (ne na útesu), mimo hlavní ulici a náměstí (ty mají vlastní obyvatele), daleko od staveb
local function townPoint(x, z)
    if plateauRadius(x - 3000, z - 2400) > 0.84 then return false end
    if abs(z - M.Street.z) < 9 and x < M.Plaza.x then return false end
    if (x - M.Plaza.x) ^ 2 + (z - M.Plaza.z) ^ 2 < 36 * 36 then return false end
    if not clearAt(x, z, 1.7) then return false end
    return map.HeightAt(x, z) > M.Y - 4
end

local function segmentClear(a, b)
    local dx, dz = b.x - a.x, b.z - a.z
    local len = sqrt(dx * dx + dz * dz)
    local steps = max(1, floor(len))
    local prevH = map.HeightAt(a.x, a.z)
    for i = 1, steps do
        local x, z = a.x + dx * i / steps, a.z + dz * i / steps
        if not townPoint(x, z) then return false end
        local h = map.HeightAt(x, z)
        if abs(h - prevH) > 0.6 * len / steps then return false end   -- strmý svah / schod
        prevH = h
    end
    return true
end

local function buildTown(v)
    obstacles = {}
    for _, p in ipairs(v.Placed or {}) do addFootprint(p.kind, p.x, p.z, p.yaw, p.scale) end
    for _, h in ipairs(v.District or {}) do addFootprint(h.kind, h.x, h.z, h.yaw, h.scale) end
    addObstacle(3000, 2165, 23.2, 17.2)                       -- Královský hrad
    if v.CityPortal then addObstacle(v.CityPortal.x, v.CityPortal.z, 3, 3) end
    plateauRadius = v.PlateauRadius or function() return 0 end
    local nodes, edges = {}, {}
    local grid = {}
    local function node(x, z)
        if not townPoint(x, z) then return nil end
        nodes[#nodes + 1] = { x = x, z = z, i = #nodes + 1, links = {} }
        return nodes[#nodes]
    end
    local function link(a, b)
        if a and b and segmentClear(a, b) then
            a.links[#a.links + 1] = b
            b.links[#b.links + 1] = a
            edges[#edges + 1] = { a, b }
        end
    end
    -- uličky mezi bloky domů (valoria.lua: každý 4. sloupec a 5. řada mřížky domů zůstaly volné)
    local XS, ZS = {}, {}
    for k = 0, 10 do XS[#XS + 1] = 2730 + 13 * (4 * k + 3) end
    for k = 0, 12 do ZS[#ZS + 1] = 1990 + 12 * (5 * k + 4) end
    for i, x in ipairs(XS) do
        grid[i] = {}
        for j, z in ipairs(ZS) do grid[i][j] = node(x, z) end
    end
    for i = 1, #XS do
        for j = 1, #ZS do
            if i < #XS then link(grid[i][j], grid[i + 1][j]) end
            if j < #ZS then link(grid[i][j], grid[i][j + 1]) end
        end
    end
    -- cesta z náměstí ke Královskému hradu (valoria.lua: x = 2990 + (2368 - z) * 0,08)
    local prev
    for z = 2364, 2190, -14.5 do
        local r = node(2990 + (2368 - z) * 0.08, z)
        if r then
            link(prev, r)
            for i, x in ipairs(XS) do   -- napojení na příčnou uličku ve stejné výšce
                for j, zz in ipairs(ZS) do
                    if abs(zz - z) < 7.5 and abs(x - r.x) < 40 and grid[i][j] then
                        local c = { x = r.x, z = zz }
                        if abs(zz - z) < 0.5 or segmentClear(r, c) then link(r, grid[i][j]) end
                    end
                end
            end
        end
        prev = r
    end
    -- jen souvislé části sítě (aspoň 4 uzly)
    local comp, keep = {}, {}
    for _, n in ipairs(nodes) do
        if not comp[n] and #n.links > 0 then
            local list, q = { n }, 1
            comp[n] = list
            while q <= #list do
                for _, o in ipairs(list[q].links) do
                    if not comp[o] then comp[o] = list; list[#list + 1] = o end
                end
                q = q + 1
            end
            if #list >= 4 then for _, o in ipairs(list) do keep[#keep + 1] = o end end
        end
    end
    M.Nodes, M.Edges = keep, edges
    return keep
end

-- nábřeží v přístavu (harbor_quay.glb, rovné): obdélník mezi moly a stánky, překážky = náklad a lucerny
M.Quay = { x0 = 2615, x1 = 2658, z0 = 2452, z1 = 2628 }
local QUAY_OBST = { { 2625.7, 2482, 3.8 }, { 2625.7, 2534, 3.8 }, { 2625.7, 2610, 3.8 },
                    { 2609, 2465.2, 1.0 }, { 2609, 2529.2, 1.0 }, { 2609, 2593.2, 1.0 } }
local function quayPoint(x, z)
    local q = M.Quay
    if x < q.x0 or x > q.x1 or z < q.z0 or z > q.z1 then return false end
    for _, o in ipairs(QUAY_OBST) do
        if (x - o[1]) ^ 2 + (z - o[2]) ^ 2 < (o[3] + 0.6) ^ 2 then return false end
    end
    return true
end
M.QuayPoint = quayPoint

local function roamValid(n, x, z)
    if n.zone == "harbor" then return quayPoint(x, z) end
    return clearAt(x, z, 0.6) and plateauRadius(x - 3000, z - 2400) < 0.86
end
M.RoamValid = roamValid

local function groundY(n, x, z)
    if n.zone == "harbor" then return M.HarborY end
    return map.HeightAt(x, z)
end

local function spawnTown(v, add)
    local nodes = buildTown(v)
    M.HarborY = (v.HarborY or 2.4) + 0.06
    local kinds = { "knight", "archer_m", "heavy", "archer_f", "knight", "archer_m", "heavy" }
    -- rovnoměrně po městě: nejvzdálenější body (farthest point sampling) ze sítě uliček
    local chosen = {}
    if #nodes > 0 then
        local d = {}
        local first = nodes[floor(rnd(1, #nodes + 0.999))]
        chosen[1] = first
        for _, n in ipairs(nodes) do d[n] = (n.x - first.x) ^ 2 + (n.z - first.z) ^ 2 end
        while #chosen < min(M.TownCount, #nodes) do
            local best, bd = nil, -1
            for _, n in ipairs(nodes) do if d[n] > bd then best, bd = n, d[n] end end
            chosen[#chosen + 1] = best
            for _, n in ipairs(nodes) do d[n] = min(d[n], (n.x - best.x) ^ 2 + (n.z - best.z) ^ 2) end
        end
    end
    for i, nd in ipairs(chosen) do
        local o = nd.links[1]
        local t = rnd(0.15, 0.6)   -- kousek od křižovatky po uličce
        local x, z = nd.x + (o.x - nd.x) * t, nd.z + (o.z - nd.z) * t
        local n = add(kinds[(i - 1) % #kinds + 1], "town", x, z, rnd(0, 360))
        n.from, n.to = nd, o
        n.zone = "town"
        M.town[#M.town + 1] = n
    end
    for i = 1, M.HarborCount do
        local x, z
        for _ = 1, 40 do
            x, z = rnd(M.Quay.x0, M.Quay.x1), rnd(M.Quay.z0 + (i - 1) * 29, M.Quay.z0 + i * 29)
            if quayPoint(x, z) then break end
        end
        local n = add(kinds[(i + 2) % #kinds + 1], "harbor", x, z, rnd(0, 360))
        n.zone = "harbor"
        M.harbor[#M.harbor + 1] = n
    end
    for _, n in ipairs(M.town) do n.y = groundY(n, n.x, n.z) end
    for _, n in ipairs(M.harbor) do n.y = groundY(n, n.x, n.z) end
end

-- ------------------------------------------------------------------ stavba
local GUARDS = {   -- stanoviště stráží {x, z, pohled}
    { 2730.0, 2396.6, 90 }, { 2730.0, 2403.4, 90 },        -- hned za branou, čelem do ulice
    { 2933.0, 2381.5, 15 }, { 2957.0, 2381.5, -15 },       -- u katedrály na severu náměstí
    { 2850.0, 2396.8, 0 }, { 2800.0, 2403.2, 180 },        -- v půli ulice u domů
}

function M.Spawn(valoria)
    M.Y = valoria.GateY
    M.list, M.core, M.town, M.harbor = {}, {}, {}, {}
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
        n.zone = "core"
        M.list[#M.list + 1] = n
        M.core[#M.core + 1] = n
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
    -- uličky čtvrtí, cesta ke hradu a nábřeží (vlastní skupiny – nepletou se mezi obyvatele hlavní ulice)
    local function addRoamer(kind, zone, x, z, yaw)
        local n = add(kind, "walker", x, z, yaw)
        table.remove(M.core)   -- add() je zařadil k hlavní ulici
        n.zone = zone
        n.speed = rnd(0.95, 1.35)
        n.lane = rnd(-0.6, 0.6)
        return n
    end
    spawnTown(valoria, addRoamer)
    for _, n in ipairs(M.list) do
        entity.set_position(n.id, n.x, n.y or M.Y, n.z)
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
    for _, o in ipairs(M.core) do
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
                    for _, o in ipairs(M.core) do
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
        for _, o in ipairs(M.core) do
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
    for _, o in ipairs(M.core) do
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
    for _, o in ipairs(M.core) do
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


-- ------------------------------------------------------------------ obyvatelé uliček a nábřeží
local function roamPath(n)
    local pts = {}
    if n.zone == "harbor" then
        for _ = 1, 12 do
            local tx = min(M.Quay.x1, max(M.Quay.x0, n.x + rnd(-30, 30)))
            local tz = min(M.Quay.z1, max(M.Quay.z0, n.z + rnd(-45, 45)))
            local ok = quayPoint(tx, tz) and (tx - n.x) ^ 2 + (tz - n.z) ^ 2 > 36
            local dx, dz = tx - n.x, tz - n.z
            local len = sqrt(dx * dx + dz * dz)
            for i = 1, floor(len) do
                if not ok then break end
                ok = quayPoint(n.x + dx * i / len, n.z + dz * i / len)
            end
            if ok then pts[1] = { tx, tz }; break end
        end
    else
        -- náhodná procházka 1–4 úseky uliček (bez okamžitého návratu), každý úsek ve vlastní stopě
        local from, cur = n.from, n.to
        if (cur.x - n.x) ^ 2 + (cur.z - n.z) ^ 2 < 2.5 * 2.5 then   -- stojí na křižovatce: rovnou dál
            local opts = {}
            for _, o in ipairs(cur.links) do if o ~= from then opts[#opts + 1] = o end end
            if #opts == 0 then opts = cur.links end
            from, cur = cur, opts[floor(rnd(1, #opts + 0.999))]
        end
        local steps = floor(rnd(1, 4.99))
        for s = 1, steps do
            local dx, dz = cur.x - from.x, cur.z - from.z
            local len = max(sqrt(dx * dx + dz * dz), 1e-3)
            pts[#pts + 1] = { cur.x + dz / len * n.lane, cur.z - dx / len * n.lane }
            if s == steps then break end
            local opts = {}
            for _, o in ipairs(cur.links) do if o ~= from then opts[#opts + 1] = o end end
            if #opts == 0 then opts = cur.links end
            from, cur = cur, opts[floor(rnd(1, #opts + 0.999))]
        end
        -- první úsek: z místa, kde stojí (uprostřed uličky), k uzlu; pak dál
        n.nextFrom, n.nextTo = from, cur
    end
    n.path, n.pi = pts, 1
    n.state = #pts > 0 and "walk" or "idle"
    if n.state == "idle" then n.timer = rnd(1, 3) end
end

local function updateRoamer(n, dt, px, pz)
    local group = n.zone == "harbor" and M.harbor or M.town
    if n.state == "idle" then
        n.v = max(0, n.v - 3 * dt)
        setAnim(n, n.idleClip or "Idle", 0.35, n.idleSpeed or 1)
        n.timer = n.timer - dt
        if n.timer <= 0 then
            -- rozhovor s někým, kdo poblíž stojí (otočí se k sobě, bez přecházení)
            if rnd() < 0.5 then
                for _, o in ipairs(group) do
                    if o ~= n and o.state == "idle" and not o.talk then
                        local d2 = (o.x - n.x) ^ 2 + (o.z - n.z) ^ 2
                        if d2 > 1.2 * 1.2 and d2 < 4.5 * 4.5 then
                            n.talk, o.talk = o, n
                            n.state, o.state = "talk", "talk"
                            n.talkTime = rnd(8, 15)
                            o.talkTime = n.talkTime
                            n.speaker, o.speaker = true, false
                            n.turnTimer = rnd(2.5, 5)
                            return
                        end
                    end
                end
            end
            roamPath(n)
        end
        return
    end
    if n.state == "talk" then
        n.v = 0
        local o = n.talk
        if not o or o.talk ~= n then n.talk = nil; n.state = "idle"; n.timer = rnd(0.5, 2); return end
        turnTo(n, faceYaw(o.x - n.x, o.z - n.z), dt)
        n.turnTimer = (n.turnTimer or 0) - dt
        if n.speaker and n.turnTimer <= 0 then
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
            n.talk, o.talk = nil, nil
            n.state, o.state = "idle", "idle"
            n.timer, o.timer = 0, rnd(2, 4)
            roamPath(n)   -- po rozhovoru jeden odejde, druhý chvíli postojí
        end
        return
    end
    local p = n.path and n.path[n.pi]
    if not p then
        if n.nextFrom then n.from, n.to, n.nextFrom, n.nextTo = n.nextFrom, n.nextTo, nil, nil end
        n.state = "idle"
        n.timer = n.pause * rnd(0.6, 1.4)
        n.idleClip = rnd() < 0.4 and "Idle_LookAround" or "Idle"
        n.idleSpeed = rnd(0.85, 1.1)
        return
    end
    local dx, dz = p[1] - n.x, p[2] - n.z
    local d = sqrt(dx * dx + dz * dz)
    if d < 0.4 then
        n.pi = n.pi + 1
        return
    end
    local turn = turnTo(n, faceYaw(dx, dz), dt)
    local target = turn > 70 and 0 or n.speed
    -- vyhýbání ve vlastní skupině a hráči
    local ax, az, slow = 0, 0, 1
    local hx, hz = sin(math.rad(n.yaw)), cos(math.rad(n.yaw))
    for _, o in ipairs(group) do
        if o ~= n then
            local ex, ez = n.x - o.x, n.z - o.z
            local e2 = ex * ex + ez * ez
            if e2 < 1.6 and e2 > 1e-6 then
                local e = sqrt(e2)
                ax, az = ax + ex / e * (1.25 - e), az + ez / e * (1.25 - e)
                if -(ex * hx + ez * hz) > 0.4 * e then slow = min(slow, max(0.25, (e - 0.55) / 0.7)) end
            end
        end
    end
    if px then
        local ex, ez = n.x - px, n.z - pz
        local e2 = ex * ex + ez * ez
        if e2 < 3.0 and e2 > 1e-6 then
            local e = sqrt(e2)
            ax, az = ax + ex / e * (1.75 - e) * 1.4, az + ez / e * (1.75 - e) * 1.4
            if -(ex * hx + ez * hz) > 0.3 * e then slow = min(slow, max(0.0, (e - 0.8) / 0.9)) end
        end
    end
    target = target * slow
    if not n.path[n.pi + 1] then target = min(target, max(0.35, d * 1.2)) end
    n.v = n.v + max(-3.0 * dt, min(2.2 * dt, target - n.v))
    local nx, nz = n.x + (hx * n.v + ax * 0.9) * dt, n.z + (hz * n.v + az * 0.9) * dt
    if roamValid(n, nx, nz) then
        n.x, n.z = nx, nz
    elseif roamValid(n, n.x + hx * n.v * dt, n.z + hz * n.v * dt) then   -- bez úhybu (u zdi domu)
        n.x, n.z = n.x + hx * n.v * dt, n.z + hz * n.v * dt
    end
    n.y = groundY(n, n.x, n.z)
    if n.v > 0.08 then
        setAnim(n, "Walking_A", 0.28, max(0.45, n.v / WALK_REF))
    else
        setAnim(n, "Idle", 0.3, 1)
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
local function setVisible(n, v)
    if n.visible ~= v then
        n.visible = v
        entity.set_visible(n.id, v)
        if v then
            entity.set_position(n.id, n.x, n.y or M.Y, n.z)
            entity.set_rotation(n.id, 0, n.yaw, 0)
        end
    end
end

function M.Update(dt, px, pz)
    if #M.list == 0 then return end
    local cx, _, cz = cameraPos()
    cx, cz = cx or px or M.Center.x, cz or pz or M.Center.z
    local far = (cx - M.Center.x) ^ 2 + (cz - M.Center.z) ^ 2 > 700 * 700
    if far ~= M.hidden then   -- daleko od města: skrýt a nepočítat
        M.hidden = far
        for _, n in ipairs(M.list) do setVisible(n, not far) end
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
        for _, n in ipairs(M.list) do if n.visible ~= false then ensure(n.id, n.clip) end end
        if M.captain then ensure(M.captain.id, M.captain.clip) end
    end
    acc = acc + dt
    local slowTick = acc >= 0.1
    if slowTick then acc = 0 end
    local hide2, show2 = (M.HideDistance + 10) ^ 2, (M.HideDistance - 10) ^ 2
    for _, n in ipairs(M.list) do
        local d2 = (n.x - cx) ^ 2 + (n.z - cz) ^ 2
        -- dál než ~150 m: skrytá (engine je nekreslí ani neanimuje), chodí dál jen v pomalém kroku
        if slowTick then
            if d2 > hide2 then setVisible(n, false) elseif d2 < show2 then setVisible(n, true) end
        end
        local near = d2 < 90 * 90
        if near or slowTick then   -- vzdálené NPC jen 10x za sekundu (z dálky nerozeznatelné)
            local step = near and dt or max(dt, 0.1)
            if n.role == "guard" then
                updateGuard(n, step)
            else
                if n.zone == "core" then updateWalker(n, step, px, pz) else updateRoamer(n, step, px, pz) end
                if n.visible ~= false then
                    entity.set_position(n.id, n.x, n.y or M.Y, n.z)
                    entity.set_rotation(n.id, 0, n.yaw, 0)
                end
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
