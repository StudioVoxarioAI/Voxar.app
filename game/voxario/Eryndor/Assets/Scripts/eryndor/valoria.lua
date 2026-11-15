-- Valorie Harbor – startovní město podle předlohy: město na skalní plošině (50 m) nad mořem, gotické věže se
-- špičatými olověnými střechami, kopulová katedrála, hrázděné domy, brána VALORIE s prapory, ulice s litinovými
-- lucernami, obloukový most přes moře k bráně, pod útesem přístav s moly a plachetnicemi, na obloze létající ostrovy.
-- Modely: tools/valoria_city.py (Models/valoria/city), most: tools/valoria_skybridge.py, ostrov: valoria_terrain.py.
local map = require("eryndor.map")
local M = {}
local W = _G.world
local cx, cz = 3000, 2400
local C = "Models/valoria/city/"
local sin, cos, sqrt, floor, atan, max, min, pi = math.sin, math.cos, math.sqrt, math.floor, math.atan, math.max,
    math.min, math.pi

-- tvar ostrova (stejně jako tools/valoria_terrain.py)
M.PlateauY, M.KeepY, M.HarborY = 50, 62, 2.4
M.Gate = { x = 2718, z = 2400, depth = 9, width = 12 }
M.Harbor = { x0 = 2605, x1 = 2690, z0 = 2430, z1 = 2640 }
M.Plaza = { x = 2945, z = 2400, r = 30 }
M.Street = { x0 = 2723, x1 = 2915, z = 2400, width = 12 }
-- schodiště z přístavu (tools/valoria_city.py -> valoria_stairs_data.lua; stejné jako valoria_terrain.py)
M.StairsData = require("eryndor.valoria_stairs_data")
M.Stairs = { x0 = M.StairsData.bottom.x, z0 = M.StairsData.bottom.z, x1 = M.StairsData.top.x, z1 = M.StairsData.top.z }

-- start: na obloukovém mostě před branou, pohled na město (jako na předloze)
M.Spawn = { x = 2672, z = 2400, yaw = 90 }   -- kamera i postava k bráně (na východ)
M.CityPortal = { x = 2968, z = 2440 }
M.OutpostPortal = { x = map.Start.x + 15, z = map.Start.z + 12 }

M.GrassExclude = {}   -- {x, z, r}: ulice, náměstí, stavby (tráva tu neroste)
M.SkybridgeAvoid = {} -- místa na souši pod mostem (nic tu neroste)
M.Placed = {}         -- seznam postavených staveb {kind, x, z} (testy, mapa)

local function plateauRadius(dx, dz)
    local a = atan(dz, dx)
    local rim = 1 + 0.045 * sin(a * 7 + 0.6) + 0.025 * sin(a * 13)
    return sqrt((dx / 300) ^ 2 + ((dz + 20) / 400) ^ 2) / rim
end
M.PlateauRadius = plateauRadius

-- nejnižší / nejvyšší terén pod obdélníkem (stavba se posadí tak, aby nikde nevisela)
local function groundRange(x, z, w, d, yaw)
    local lo, hi = math.huge, -math.huge
    local c, s = cos(math.rad(yaw or 0)), sin(math.rad(yaw or 0))
    for i = -1, 1, 0.5 do
        for j = -1, 1, 0.5 do
            local lx, lz = i * w / 2, j * d / 2
            local h = map.HeightAt(x + lx * c + lz * s, z - lx * s + lz * c)
            lo, hi = min(lo, h), max(hi, h)
        end
    end
    return lo, hi
end

local function place(kind, x, z, opts)
    opts = opts or {}
    local lo = groundRange(x, z, opts.w or 8, opts.d or 8, opts.yaw)
    local y = (opts.y or lo) - (opts.sink or 0.25)
    local id = W.spawn(C .. kind .. ".glb", x, y, z, { yaw = opts.yaw or 0, name = opts.name or "Valorie",
        collider = opts.collider == false and nil or (opts.collider or "mesh"), scale = opts.scale })
    M.Placed[#M.Placed + 1] = { kind = kind, x = x, z = z, id = id }
    if opts.exclude then M.GrassExclude[#M.GrassExclude + 1] = { x, z, opts.exclude } end
    return id, y
end

local function lamp(x, z, y, lit)
    y = y or map.HeightAt(x, z)
    W.spawn(C .. "lamp_post.glb", x, y - 0.05, z, { name = "Lucerna", collider = "box" })
    if lit then
        -- svítí i za zlaté hodiny (předloha); ve dne je jejich světlo proti slunci zanedbatelné
        W.spawn("light", x, y + 5.0, z, { light = { color = { 1.0, 0.68, 0.36 }, intensity = 16, range = 18 } })
    end
end

local function portal(p)
    local y = map.HeightAt(p.x, p.z)
    W.spawn("Models/nature/aetherium_big.glb", p.x, y, p.z, { name = "Portál", scale = 1.0 })
    W.spawn("light", p.x, y + 3, p.z, { light = { color = { 0.4, 0.7, 1.0 }, intensity = 25, range = 12 } })
end

-- ------------------------------------------------------------------ obloukový most k bráně
M.Skybridge = require("eryndor.skybridge_data")
M.SkybridgeEntity = nil
M.BridgeY = nil   -- výška mostovky u brány (= podlaha průjezdu)

function M.SkybridgeY(i)
    return M.BridgeY + M.Skybridge.points[i][3]
end

local function gateFloor()
    local hi = -math.huge
    for dx = -M.Gate.depth / 2, M.Gate.depth / 2, 1 do
        for dz = -M.Gate.width / 2, M.Gate.width / 2, 1 do
            hi = max(hi, map.HeightAt(M.Gate.x + dx, M.Gate.z + dz))
        end
    end
    return hi + 0.06
end

local function skybridge()
    local d = M.Skybridge
    M.SkybridgeEntity = W.spawn("Models/valoria/skybridge.glb", d.start.x, M.BridgeY, d.start.z,
        { name = "Obloukový most Valorie", collider = "mesh" })
    local pts = d.points
    for _, p in ipairs(pts) do
        if p[4] == 0 then M.SkybridgeAvoid[#M.SkybridgeAvoid + 1] = { x = p[1], z = p[2], r = d.width } end
    end
    -- litinové lucerny po 30 m po obou stranách (světlo v noci každá druhá)
    for i = 2, #pts - 3, 3 do
        local a, b = pts[max(i - 1, 1)], pts[i + 1]
        local tx, tz = b[1] - a[1], b[2] - a[2]
        local len = sqrt(tx * tx + tz * tz)
        for side = -1, 1, 2 do
            local ox, oz = tz / len * 6.2 * side, -tx / len * 6.2 * side
            lamp(pts[i][1] + ox, pts[i][2] + oz, M.SkybridgeY(i), (floor(i / 3) + (side > 0 and 1 or 0)) % 2 == 0)
        end
    end
end

-- ------------------------------------------------------------------ ulice a náměstí (dlažba z kočičích hlav)
-- world.road: pás leží přímo na terénu (výšky z kolizní mřížky) – postava se do dlažby nepropadá
local COBBLE = "Textures/valoria/pbr/cobble"
local function street(points, width, lift)
    W.road({ points = points, width = width, tile = 2.0, lift = lift or 0.05, texture = COBBLE .. "_basecolor.jpg",
        normal = COBBLE .. "_normal.jpg", orm = COBBLE .. "_orm.jpg", distance = 1500 })
end
M.StreetStart = nil
local function paving()
    local s = M.Street
    -- hlavní ulice a náměstí: jeden dlážděný model s pískovcovými lemy a obrubníkem (tools/valoria_city.py),
    -- na rovné plošině přesně v úrovni podlahy brány; kolizní síť – nic se nepropadá, žádné zubaté okraje
    local x0 = M.Gate.x + M.Gate.depth / 2
    M.StreetStart = x0
    M.Paving = W.spawn(C .. "city_paving.glb", M.Plaza.x, M.GateY, M.Plaza.z, { name = "Dlažba Valorie",
        collider = "mesh" })
    for x = x0, M.Plaza.x, 8 do M.GrassExclude[#M.GrassExclude + 1] = { x, s.z, 8 } end
    local p = M.Plaza
    M.GrassExclude[#M.GrassExclude + 1] = { p.x, p.z, p.r + 3 }
    -- cesta z náměstí ke Královskému hradu (sever)
    local path = {}
    for z = M.Plaza.z - M.Plaza.r + 2, cz - 222, -8 do
        path[#path + 1] = { 2990 + (2368 - z) * 0.08, z }
        M.GrassExclude[#M.GrassExclude + 1] = { 2990 + (2368 - z) * 0.08, z, 6 }
    end
    street(path, 6)
end

-- ------------------------------------------------------------------ hradby po okraji plošiny
local function walls()
    -- body okraje (plateau radius 0,93) po 24 m
    local rim = {}
    for k = 0, 359, 1 do
        local a = math.rad(k)
        local lo, hi = 0, 600
        for _ = 1, 30 do
            local r = (lo + hi) / 2
            if plateauRadius(cos(a) * r, sin(a) * r) < 0.93 then lo = r else hi = r end
        end
        rim[#rim + 1] = { cx + cos(a) * lo, cz + sin(a) * lo }
    end
    local seg, acc, last = {}, 0, rim[1]
    for i = 2, #rim + 1 do
        local p = rim[(i - 1) % #rim + 1]
        acc = acc + sqrt((p[1] - last[1]) ^ 2 + (p[2] - last[2]) ^ 2)
        last = p
        if acc >= 24 then seg[#seg + 1] = p; acc = 0 end
    end
    local anchors = {}   -- konce ponechaných úseků nejblíž bráně (sever, jih)
    for i, p in ipairs(seg) do
        local q = seg[i % #seg + 1]
        local mx, mz = (p[1] + q[1]) / 2, (p[2] + q[2]) / 2
        local nearGate = (mx - M.Gate.x) ^ 2 + (mz - M.Gate.z) ^ 2 < 40 ^ 2
        local nearStairs = (mx - M.Stairs.x1) ^ 2 + (mz - M.Stairs.z1) ^ 2 < 16 ^ 2
        local nearKeep = (mx - cx) ^ 2 / 160 ^ 2 + (mz - (cz - 235)) ^ 2 / 125 ^ 2 < 1
        if not nearGate and not nearStairs and not nearKeep then
            local yaw = math.deg(atan(q[1] - p[1], q[2] - p[2])) - 90
            place("city_wall", mx, mz, { yaw = yaw, w = 24, d = 3, sink = 1.2, name = "Hradby Valorie" })
            if i % 4 == 0 then place("wall_tower", p[1], p[2], { w = 7, d = 7, sink = 0.6, name = "Hradební věž" }) end
            for _, e in ipairs({ p, q }) do
                local side = e[2] < M.Gate.z and "n" or "s"
                local d2 = (e[1] - M.Gate.x) ^ 2 + (e[2] - M.Gate.z) ^ 2
                if d2 < 70 ^ 2 and (not anchors[side] or d2 < anchors[side].d2) then
                    anchors[side] = { x = e[1], z = e[2], d2 = d2 }
                end
            end
        end
    end
    -- hradby od věží brány k nejbližším úsekům (6m díly): žádná mezera mezi bránou a hradbou
    for side, sg in pairs({ n = -1, s = 1 }) do
        local an = anchors[side]
        if an then
            local x0, z0 = M.Gate.x, M.Gate.z + sg * 15.0
            local len = sqrt((an.x - x0) ^ 2 + (an.z - z0) ^ 2)
            local n = math.max(1, math.ceil(len / 5.5))
            local yaw = math.deg(atan(an.x - x0, an.z - z0)) - 90
            for k = 0, n - 1 do
                local t = (k + 0.5) / n
                place("city_wall_6", x0 + (an.x - x0) * t, z0 + (an.z - z0) * t,
                    { yaw = yaw, w = 6, d = 3, sink = 1.2, name = "Hradby Valorie" })
            end
            place("wall_tower", an.x, an.z, { w = 7, d = 7, sink = 0.6, name = "Hradební věž" })
        end
    end
end

-- ------------------------------------------------------------------ stavba města
function M.Build()
    M.BridgeY = gateFloor()
    M.GateY = M.BridgeY
    skybridge()
    paving()

    -- brána VALORIE (průjezd podél osy X, průčelí na západ k mostu)
    place("gate_valorie", M.Gate.x, M.Gate.z, { yaw = -90, w = 32, d = 9, y = M.GateY, sink = 0,
        name = "Brána Valorie", exclude = 20 })

    -- hlavní ulice: hrázděné domy po obou stranách, lucerny, sochy hrdinů
    local s = M.Street
    local k = 0
    for x = s.x0 + 8, s.x1 - 6, 11 do
        k = k + 1
        place("house_" .. (k % 4), x, s.z - 10.5, { yaw = 0, w = 10, d = 9, name = "Měšťanský dům", exclude = 7 })
        place("house_" .. ((k + 2) % 4), x + 3, s.z + 10.5, { yaw = 180, w = 10, d = 9, name = "Měšťanský dům",
            exclude = 7 })
        if k % 2 == 0 then
            lamp(x - 5.5, s.z - 4.6, nil, true)
            lamp(x - 2.5, s.z + 4.6, nil, k % 4 == 0)
        end
    end

    -- čtvrti: husté bloky domů po celé plošině (instance – 4 druhy domů, natočené podle uliček, kolize kmenem)
    local blocked = { { 2820, 2296, 16 }, { 2786, 2350, 24 }, { 2840, 2462, 15 }, { 3062, 2425, 15 }, { 3105, 2318, 14 }, { 2880, 2300, 16 },
                      { 3150, 2520, 16 }, { 2945, 2345, 26 }, { M.Plaza.x, M.Plaza.z, M.Plaza.r + 10 }, { cx, cz - 235, 70 },
                      { M.Gate.x, M.Gate.z, 30 }, { 2722, 2490, 18 }, { M.CityPortal.x, M.CityPortal.z, 10 } }
    local district = { {}, {}, {}, {} }
    for gx = 2730, 3290, 13 do
        for gz = 1990, 2790, 12 do
            local jx, jz = ((gx * 13 + gz * 7) % 5) - 2, ((gx * 3 + gz * 11) % 3) - 1
            local x, z = gx + jx, gz + jz
            local pr = plateauRadius(x - cx, z - cz)
            local free = pr < 0.86 and math.abs(z - s.z) > 21 and math.abs(x - 2990) > 8   -- hlavní ulice, cesta k hradu
            if free and ((gx - 2730) / 13) % 4 == 3 then free = false end      -- uličky sever–jih
            if free and ((gz - 1990) / 12) % 5 == 4 then free = false end      -- uličky západ–východ
            for _, bl in ipairs(blocked) do
                if free and (x - bl[1]) ^ 2 + (z - bl[2]) ^ 2 < bl[3] ^ 2 then free = false end
            end
            if free then
                local kind = (floor(gx / 13) + floor(gz / 12)) % 4
                local yaw = ((floor(gx / 13) % 2 == 0) and 0 or 180) + ((floor(gz / 12) % 3 == 0) and 90 or 0)
                local lo = groundRange(x, z, 10, 9, yaw)
                local list = district[kind + 1]
                list[#list + 1] = { x, lo - 0.25, z, yaw, 1 }
                M.GrassExclude[#M.GrassExclude + 1] = { x, z, 6.5 }
            end
        end
    end
    M.DistrictHouses = 0
    for k = 1, 4 do
        if #district[k] > 0 then
            W.instances(C .. "house_" .. (k - 1) .. ".glb", district[k], { distance = 1600, collider = "capsule",
                radius = 4.2, height = 10 })
            M.DistrictHouses = M.DistrictHouses + #district[k]
        end
    end

    -- náměstí s katedrálou (kopule) a sochami hrdinů
    place("dome_hall", 2945, 2345, { yaw = 0, w = 24, d = 30, name = "Katedrála Valorie", exclude = 22 })
    for i = 0, 5 do
        local a = i / 6 * 2 * pi + 0.5
        local x, z = M.Plaza.x + cos(a) * (M.Plaza.r - 4), M.Plaza.z + sin(a) * (M.Plaza.r - 4)
        if z > M.Plaza.z - 18 then
            W.spawn("Models/valoria/hero.glb", x, map.HeightAt(x, z) - 0.05, z,
                { yaw = math.deg(atan(M.Plaza.x - x, M.Plaza.z - z)), name = "Hrdina", collider = "box" })
        end
        lamp(M.Plaza.x + cos(a + 0.5) * (M.Plaza.r + 1.5), M.Plaza.z + sin(a + 0.5) * (M.Plaza.r + 1.5), nil, i % 2 == 0)
    end

    -- panorama věží (jako na předloze): vysoké gotické věže se špičatými střechami po celém městě
    place("tower_a", 2820, 2296, { w = 10, d = 10, name = "Věž mágů", exclude = 8 })
    -- kopulová rotunda hned za branou (na předloze vlevo od brány nad viaduktem)
    place("dome_hall", 2786, 2350, { yaw = 180, w = 22, d = 26, scale = 0.85, name = "Rotunda Valorie", exclude = 20 })
    place("tower_b", 2840, 2462, { w = 9, d = 9, name = "Strážní věž", exclude = 7 })
    place("tower_b", 3062, 2425, { w = 9, d = 9, name = "Zvonice", exclude = 7 })
    place("tower_round", 3105, 2318, { w = 8, d = 8, name = "Kruhová věž", exclude = 7 })
    place("tower_a", 2880, 2300, { w = 10, d = 10, name = "Věž rady", exclude = 8 })
    place("tower_a", 3150, 2520, { w = 10, d = 10, name = "Věž", exclude = 8 })

    -- Královský hrad na skále na severu: hradní palác + věže se špičatými střechami
    place("tower_c", cx, cz - 262, { w = 12, d = 12, name = "Královská věž", exclude = 10 })
    for _, o in ipairs({ { -26, -10 }, { 26, -10 }, { -24, 22 }, { 24, 22 } }) do
        place("tower_a", cx + o[1], cz - 235 + o[2], { w = 10, d = 10, name = "Hradní věž", exclude = 8 })
    end
    W.spawn("Models/valoria/keep.glb", cx, map.HeightAt(cx, cz - 235), cz - 235, { name = "Královský hrad",
        collider = "mesh" })
    local floorY = -math.huge
    for x = -16, 16, 2 do
        for z = -11, 13, 2 do floorY = max(floorY, map.HeightAt(cx + x, cz - 235 + z)) end
    end
    M.KeepFloorY = floorY + 0.05
    M.KeepFloor = W.spawn("Models/valoria/keep_floor.glb", cx, M.KeepFloorY - 0.02, cz - 235,
        { name = "Podlaha hradu", collider = "mesh" })
    for i = 1, 2 do
        W.spawn("Models/valoria/keep_step.glb", cx, M.KeepFloorY - 0.02 - i * 0.2, cz - 223 + (i * 2 - 1),
            { name = "Schod hradu", collider = "mesh" })
    end
    for _, x in ipairs({ -8, 8 }) do
        W.spawn("light", cx + x, M.KeepFloorY + 4, cz - 235, { light = { color = { 1.0, 0.72, 0.42 }, intensity = 22, range = 13 } })
    end
    M.GrassExclude[#M.GrassExclude + 1] = { cx, cz - 235, 30 }

    walls()

    -- přístav pod útesem: mola, plachetnice, domy, lucerny, schodiště na plošinu
    local h = M.Harbor
    local sails = { 0, 1, 2, 1, 0 }
    for i, z in ipairs({ 2468, 2532, 2596 }) do
        W.spawn(C .. "dock.glb", h.x0 + 8, M.HarborY - 1.35, z, { yaw = -90, name = "Molo", collider = "mesh" })
        W.spawn(C .. "ship_" .. sails[i] .. ".glb", h.x0 - 34, map.SeaY - 0.35, z + 7.5,
            { yaw = -90 + (i - 2) * 6, name = "Plachetnice", collider = "mesh" })
        lamp(h.x0 + 4, z - 2.8, M.HarborY + 0.05, true)
    end
    W.spawn(C .. "ship_2.glb", h.x0 - 120, map.SeaY - 0.35, 2560, { yaw = -60, name = "Plachetnice" })
    W.spawn(C .. "ship_0.glb", h.x0 - 210, map.SeaY - 0.35, 2700, { yaw = -110, name = "Plachetnice" })
    for z = h.z0 + 14, h.z1 - 45, 17 do
        place("house_" .. floor(z / 17) % 4, h.x1 - 9, z, { yaw = -90, w = 10, d = 9, name = "Přístavní dům",
            y = M.HarborY, sink = 0.3 })
    end
    -- dlážděné nábřeží od schodiště k molům
    W.spawn(C .. "harbor_quay.glb", (2604 + 2677) / 2, M.HarborY + 0.06, (2446 + 2636) / 2,
        { name = "Nábřeží", collider = "mesh" })
    M.GrassExclude[#M.GrassExclude + 1] = { 2640, 2540, 60 }
    -- schodiště vytesané do útesu (model v absolutních výškách, počátek = spodní konec osy)
    local st = M.StairsData
    W.spawn(C .. "harbor_stairs.glb", st.bottom.x, 0, st.bottom.z, { name = "Přístavní schodiště", collider = "mesh" })
    for i, l in ipairs(st.landings) do   -- lucerny na podestách (střídavě po stranách)
        local side = (i % 2 == 0) and 1 or -1
        lamp(l[1] + l[4] * side * 2.0, l[2] + l[5] * side * 2.0, l[3], i % 2 == 1)
    end

    -- létající ostrovy na obloze (fantasy svět předlohy)
    local isles = { { 3650, 1900, 150, 0 }, { 2300, 1850, 175, 1 }, { 3700, 2900, 130, 2 }, { 3050, 1500, 210, 0 },
                    { 2150, 2850, 160, 2 }, { 3400, 2250, 240, 1 } }
    for i, s2 in ipairs(isles) do
        W.spawn(C .. "sky_island_" .. s2[4] .. ".glb", s2[1], s2[3], s2[2], { yaw = s2[1] % 360, name = "Létající ostrov" })
        for t2 = 0, 5 do   -- stromy na vrcholu
            local a = t2 * 1.05 + i
            local rr = (t2 % 2 == 0) and 14 or 24
            W.spawn("Models/nature/tree_" .. (t2 % 3) .. ".glb", s2[1] + cos(a) * rr, s2[3] - 0.2, s2[2] + sin(a) * rr,
                { yaw = t2 * 60, scale = 1.6, name = "Strom" })
        end
    end

    -- zeleň: stromy na nižších svazích ostrova pod útesy a pár zahrad ve městě (předloha: zelené útesy a terasy)
    local green = { {}, {}, {} }
    local seed = 7
    local function rnd()
        seed = (seed * 1103515245 + 12345) % 2147483648
        return seed / 2147483648
    end
    for _ = 1, 900 do
        local a, r = rnd() * 2 * pi, 260 + rnd() * 300
        local x, z = cx + cos(a) * r * 1.0, cz + sin(a) * r * 1.15
        local h = map.HeightAt(x, z)
        local pr = plateauRadius(x - cx, z - cz)
        local inHarbor = x > M.Harbor.x0 - 10 and x < M.Harbor.x1 + 5 and z > M.Harbor.z0 - 10 and z < M.Harbor.z1 + 10
        if pr > 1.1 and h > 3.5 and h < 30 and not inHarbor then
            local k = floor(rnd() * 3) + 1
            green[k][#green[k] + 1] = { x, h - 0.2, z, rnd() * 360, 0.9 + rnd() * 0.7 }
        end
    end
    for k = 1, 3 do
        if #green[k] > 0 then
            W.instances("Models/nature/tree_" .. (k - 1) .. ".glb", green[k], { distance = 700, wind = 0.08, collider = "capsule",
                radius = 0.35, height = 4 })
            W.instances("Models/nature/tree_" .. (k - 1) .. "_far.glb", green[k], { distance = 2200, min_distance = 616, shadow = false })
        end
    end
    portal(M.CityPortal)
    portal(M.OutpostPortal)
end

function M.NearPortal(x, z)
    local function near(p)
        return (x - p.x) ^ 2 + (z - p.z) ^ 2 < 7 ^ 2
    end
    if near(M.CityPortal) then return M.OutpostPortal end
    if near(M.OutpostPortal) then return M.CityPortal end
end

return M
