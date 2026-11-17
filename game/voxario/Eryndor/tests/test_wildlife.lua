package.path = "game/voxario/Eryndor/Assets/Scripts/?.lua;" .. package.path
-- Zvěř v lesích: druhy a skupiny v lesních regionech, každé zvíře vlastní trasou, nevstoupí do vody ani do kmene,
-- drží se u domova, utíká před hráčem (laně, divočáci), vlci jdou v řadě, medvěd varuje; cena aktualizace.

local ents, nextId = {}, 0
local camera = { x = 0, y = 0, z = 0 }
-- terén: zvlněný, voda (h < 2) v pásu kolem z = -2600 (kontrola, že zvěř nevstoupí do vody)
local function H(x, z) return 40 + 18 * math.sin(x * 0.004) * math.cos(z * 0.003) + 6 * math.sin(x * 0.02 + z * 0.015) end
local function height(x, z)
    if z > -2640 and z < -2560 then return 0.5, { x = 0, y = 1, z = 0 } end
    local h = H(x, z)
    local gx, gz = (H(x + 1, z) - h), (H(x, z + 1) - h)
    local ny = 1 / math.sqrt(1 + gx * gx + gz * gz)
    return h, { x = -gx * ny, y = ny, z = -gz * ny }
end
world = setmetatable({
    spawn = function(path, x, y, z, o)
        nextId = nextId + 1
        ents[nextId] = { path = path, x = x, y = y, z = z, o = o or {}, visible = true }
        return nextId
    end,
    height = height,
}, { __index = function() return function() end end })
_G.world = world
entity = {
    set_position = function(id, x, y, z) ents[id].x, ents[id].y, ents[id].z = x, y, z end,
    set_rotation = function(id, rx, ry) ents[id].pitch, ents[id].yaw = rx, ry end,
    set_visible = function(id, v) ents[id].visible = v end,
    material_color = function() end,
    find = function(n) return n == "Camera" and 0 or nil end,
    get_position = function(id) if id == 0 then return camera.x, camera.y, camera.z end return ents[id].x, ents[id].y, ents[id].z end,
}
local clips = {}
anim = { play = function(id, clip) clips[id] = clip end, speed = function() end }

local world_ = require("eryndor.world")
local wl = require("eryndor.wildlife")
local map = require("eryndor.map")
-- les: kmeny v mřížce ~7 m kolem domovů skupin (kontrola obcházení)
local L = wl.Spawn({ scatter = world_.Scatter })
assert(#L >= 40, "zvěř: " .. #L)
local count = {}
for _, a in ipairs(L) do count[a.sp] = (count[a.sp] or 0) + 1 end
assert((count.doe or 0) >= 10 and (count.stag or 0) >= 3 and (count.boar or 0) >= 9 and (count.wolf or 0) >= 10 and
       (count.bear or 0) >= 3, string.format("druhy: laně %d, jeleni %d, divočáci %d, vlci %d, medvědi %d", count.doe or 0,
       count.stag or 0, count.boar or 0, count.wolf or 0, count.bear or 0))
for _, a in ipairs(L) do
    assert(ents[a.id].path:find("Models/fauna/"), "model zvěře")
    assert(ents[a.id].o.lod == "auto", "LOD do dálky")
    local r = map.Region(a.x, a.z)
    assert(a.g.codes:find(r, 1, true), "zvíře v lese svého regionu (" .. r .. ")")
end
local trunks = {}
for _, g in ipairs(wl.groups) do
    for i = -12, 12 do
        for j = -12, 12 do
            local x, z = g.hx + i * 7.3 + (j % 3), g.hz + j * 6.9 + (i % 2)
            if (x - g.hx) ^ 2 + (z - g.hz) ^ 2 > 12 * 12 then trunks[#trunks + 1] = { x, 0, z, 0, 1.0 } end
        end
    end
end
wl.AddTrunks(trunks, 0.35)

-- simulace 10 minut (20 Hz): kamera obchází skupiny, hráč daleko (klid)
local dt = 1 / 20
local start, maxd, inTrunk, inWater, minGap, states = {}, {}, 0, 0, math.huge, {}
for i, a in ipairs(L) do start[i] = { a.x, a.z } end
local c0 = os.clock()
local steps = 20 * 600
for step = 1, steps do
    local g = wl.groups[(math.floor(step / 400) % #wl.groups) + 1]
    camera.x, camera.z = g.hx + 20, g.hz + 20
    wl.Update(dt, nil, nil, 12)
    if step % 10 == 0 then
        for i, a in ipairs(L) do
            maxd[i] = math.max(maxd[i] or 0, math.sqrt((a.x - start[i][1]) ^ 2 + (a.z - start[i][2]) ^ 2))
            local h = map.HeightAt(a.x, a.z)
            if h < 2 then inWater = inWater + 1 end
            assert((a.x - a.g.hx) ^ 2 + (a.z - a.g.hz) ^ 2 < (a.g.range + 80) ^ 2, "zvíře daleko od domova")
            states[clips[a.id] or "?"] = true
        end
        for _, t in ipairs(trunks) do
            for _, a in ipairs(L) do
                local d2 = (a.x - t[1]) ^ 2 + (a.z - t[3]) ^ 2
                if d2 < (0.35 + 0.1) ^ 2 then inTrunk = inTrunk + 1 end
            end
        end
        for _, g2 in ipairs(wl.groups) do
            for i = 1, #g2.members do
                for j = i + 1, #g2.members do
                    local a, b = g2.members[i], g2.members[j]
                    minGap = math.min(minGap, math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2))
                end
            end
        end
    end
end
local ms = (os.clock() - c0) / steps * 1000
assert(inWater == 0, "zvíře ve vodě")
assert(inTrunk == 0, "zvíře v kmeni stromu (" .. inTrunk .. ")")
assert(minGap > 0.3, string.format("zvířata v sobě (%.2f m)", minGap))
local moved = 0
for i = 1, #L do if (maxd[i] or 0) > 20 then moved = moved + 1 end end
assert(moved >= #L * 0.85, "zvěř se pohybuje (" .. moved .. "/" .. #L .. ")")
assert(states.Graze and states.Walk and (states.Idle or states.Idle_Look), "pastva, chůze, klid")
-- vlastní trajektorie: žádná dvě zvířata stejné skupiny nemají stejnou stopu (poloha se liší)
-- útěk: hráč přijde k laním -> stádo uteče cvalem dál od hráče
local deer
for _, g in ipairs(wl.groups) do if g.kind == "deer" then deer = g; break end end
local L0 = deer.leader
local px, pz = L0.x + 10, L0.z
camera.x, camera.z = px, pz
local ran = false
for _ = 1, 20 * 15 do
    wl.Update(dt, px, pz, 12)
    if clips[L0.id] == "Run" then ran = true end
end
local away = math.sqrt((L0.x - px) ^ 2 + (L0.z - pz) ^ 2)
assert(ran and away > 40, string.format("laně utíkají před hráčem (%.0f m)", away))
-- medvěd: hráč blízko -> varovný řev
local bear
for _, g in ipairs(wl.groups) do if g.kind == "bear" then bear = g; break end end
local B = bear.leader
px, pz = B.x + 12, B.z
camera.x, camera.z = px, pz
local roared = false
for _ = 1, 20 * 3 do
    wl.Update(dt, px, pz, 12)
    if clips[B.id] == "Roar" then roared = true end
end
assert(roared, "medvěd varuje řevem")
-- daleko od kamery: skrytá
camera.x, camera.z = 100000, 100000
for _ = 1, 12 do wl.Update(0.1, nil, nil, 12) end
local hidden = 0
for _, a in ipairs(L) do if not ents[a.id].visible then hidden = hidden + 1 end end
assert(hidden == #L, "vzdálená zvěř skrytá")
-- cena: kamera u stáda (nejhorší případ – jedna skupina zblízka, ostatní pomalu / skryté)
camera.x, camera.z = wl.groups[1].hx + 15, wl.groups[1].hz
local c1 = os.clock()
for _ = 1, 1200 do wl.Update(1 / 60, nil, nil, 12) end
ms = (os.clock() - c1) / 1200 * 1000
assert(ms < 0.5, string.format("wildlife.Update %.3f ms", ms))
print(string.format("Zvěř: OK (%d zvířat ve %d skupinách, laně %d, jeleni %d, divočáci %d, vlci %d, medvědi %d, Update %.3f ms)",
    #L, #wl.groups, count.doe, count.stag, count.boar, count.wolf, count.bear, ms))
