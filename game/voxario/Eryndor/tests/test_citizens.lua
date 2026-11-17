package.path = "game/voxario/Eryndor/Assets/Scripts/?.lua;" .. package.path
-- Obyvatelé Valorie: 30 NPC chodí jen po ulici a náměstí, nevycházejí branou, nestojí v sobě, povídají si,
-- každý jinou trajektorií; kapitán na náměstí.

local ents, nextId = {}, 0
local function newEnt(path, x, y, z, o)
    nextId = nextId + 1
    ents[nextId] = { path = path, x = x, y = y, z = z, o = o or {}, visible = true, parts = {} }
    return nextId
end
world = { spawn = newEnt }
_G.world = world
entity = {
    attach = function() end, set_position = function(id, x, y, z) ents[id].x, ents[id].y, ents[id].z = x, y, z end,
    set_rotation = function(id, rx, ry) ents[id].yaw = ry end, show_part = function(id, p, v) ents[id].parts[p or "*"] = v end,
    material_color = function() end, set_visible = function(id, v) ents[id].visible = v end,
    find = function() return nil end, get_position = function(id) return ents[id].x, ents[id].y, ents[id].z end,
}
local clips = {}
anim = { play = function(id, clip) clips[id] = clip end, speed = function() end }

local citizens = require("eryndor.citizens")
citizens.Spawn({ GateY = 50.13 })
local L = citizens.list
assert(#L == 30, "30 NPC: " .. #L)
local kinds = {}
for _, n in ipairs(L) do kinds[n.kind] = (kinds[n.kind] or 0) + 1 end
assert((kinds.knight or 0) >= 6 and (kinds.archer_m or 0) + (kinds.archer_f or 0) >= 6, "rytíři i lukostřelci")
local cap = citizens.captain
assert(cap and citizens.InPlaza(cap.x, cap.z) and ents[cap.id].path:find("aeth_heavy_m"), "kapitán na náměstí")

-- simulace 10 minut (30 Hz), hráč stojí uprostřed ulice
local dt = 1 / 30
local talks, minDist, tracks = 0, math.huge, {}
local px, pz = 2840, 2400
for step = 1, 30 * 600 do
    citizens.Update(dt, px, pz)
    for i, n in ipairs(L) do
        if n.role == "guard" then   -- stráže na stanovištích: na dlažbě ulice nebo náměstí (r <= 29 m)
            assert(citizens.InStreet(n.x, n.z) or (n.x - 2945) ^ 2 + (n.z - 2400) ^ 2 < 29 ^ 2, "stráž mimo dlažbu")
        else
            assert(citizens.Walkable(n.x, n.z), string.format("NPC %d mimo ulici/náměstí: %.2f %.2f", i, n.x, n.z))
        end
        assert(n.x >= citizens.Street.x0 - 1e-6, "NPC prošlo branou ven")
        assert(math.abs(ents[n.id].y - 50.13) < 1e-6, "NPC na dlažbě (nepropadá se)")
        if n.state == "talk" and n.speaker then talks = talks + dt end
        if step % 30 == 0 then
            tracks[i] = tracks[i] or {}
            tracks[i][#tracks[i] + 1] = { n.x, n.z, n.state == "walk" and n.v > 0.3, n.yaw }
        end
    end
    if step % 15 == 0 then
        for i = 1, #L do
            for j = i + 1, #L do
                local a, b = L[i], L[j]
                if a.partner ~= b then
                    local d = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
                    if d < minDist then minDist = d end
                end
            end
        end
    end
end
assert(minDist > 0.35, string.format("NPC se překrývají (min. vzdálenost %.2f m)", minDist))
assert(talks > 60, "dvojice si povídají (" .. math.floor(talks) .. " s)")
-- různé trajektorie: chodci nejdou za sebou po stejné čáře (blízko sebe, stejným směrem, oba v chůzi)
local walkers, distinct = 0, 0
for i, n in ipairs(L) do
    if n.role == "walker" then
        walkers = walkers + 1
        local moving, follow = 0, 0
        for k, a in ipairs(tracks[i]) do
            if a[3] then
                moving = moving + 1
                for j, o in ipairs(L) do
                    local b = tracks[j][k]
                    if j ~= i and o.role == "walker" and b and b[3] and (a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 < 2.5 * 2.5 and
                        math.abs((a[4] - b[4] + 540) % 360 - 180) < 25 then
                        follow = follow + 1
                        break
                    end
                end
            end
        end
        if moving > 20 and follow < moving * 0.2 then distinct = distinct + 1 end
    end
end
assert(distinct >= walkers - 2, "každý chodec má vlastní trajektorii (" .. distinct .. "/" .. walkers .. ")")
-- chodci opravdu chodí (ulice i náměstí)
local street, plaza = 0, 0
for i, n in ipairs(L) do
    for _, p in ipairs(tracks[i]) do
        if citizens.InPlaza(p[1], p[2]) then plaza = plaza + 1 elseif citizens.InStreet(p[1], p[2]) then street = street + 1 end
    end
end
assert(street > 1000 and plaza > 1000, "NPC chodí po ulici i po náměstí")
-- daleko od města: skryté a nepočítají se
entity.find = function() return 999 end
ents[999] = { x = 0, y = 0, z = 0 }
citizens.Update(dt, nil, nil)
assert(not ents[L[1].id].visible, "daleko od města jsou NPC skrytá")
print(string.format("Obyvatelé Valorie: OK (rozhovory %.0f s, nejmenší vzdálenost %.2f m)", talks, minDist))
