package.path = "game/voxario/Eryndor/Assets/Scripts/?.lua;" .. package.path
-- Valorie Harbor (předloha): brána VALORIE, obloukový most k bráně, ulice s domy a lucernami, čtvrti, katedrála,
-- věže, hrad na skále, hradby, přístav s moly a loděmi, létající ostrovy, portály

local calls, instanceCalls = {}, {}
local function ground(x, z)
    -- plošina 50 m (mírně zvlněná), hradní skála 62 m, kolem moře
    local dx, dz = x - 3000, z - 2400
    if (dx / 150) ^ 2 + ((dz + 235) / 115) ^ 2 < 0.3 then return 62 + 0.1 * math.sin(x) end
    if (dx / 300) ^ 2 + ((dz + 20) / 400) ^ 2 < 1 then return 50 + 0.3 * math.sin(x * 0.1) * math.cos(z * 0.13) end
    if x > 2605 and x < 2690 and z > 2430 and z < 2640 then return 2.4 end
    return -20
end
world = {
    height = function(x, z) return ground(x, z), { y = 1 } end,
    spawn = function(...)
        calls[#calls + 1] = { ... }
        return #calls
    end,
    instances = function(...)
        instanceCalls[#instanceCalls + 1] = { ... }
        return #instanceCalls
    end,
}

local valoria = require("eryndor.valoria")
valoria.Build()

local function find(path)
    local out = {}
    for i, c in ipairs(calls) do if c[1] == path then out[#out + 1] = { i = i, c = c } end end
    return out
end
local C = "Models/valoria/city/"

-- brána a most: mostovka navazuje na podlahu průjezdu (žádný schod), most má kolizi
local gate = find(C .. "gate_valorie.glb")
assert(#gate == 1 and gate[1].c[5].yaw == -90 and gate[1].c[5].collider == "mesh", "gate VALORIE faces the bridge")
local gx, gz = valoria.Gate.x, valoria.Gate.z
local hi = -math.huge
for dx = -valoria.Gate.depth / 2, valoria.Gate.depth / 2, 1 do
    for dz = -valoria.Gate.width / 2, valoria.Gate.width / 2, 1 do hi = math.max(hi, ground(gx + dx, gz + dz)) end
end
assert(math.abs(valoria.GateY - hi - 0.06) < 1e-6, "gate floor clears the terrain")
local sky = calls[valoria.SkybridgeEntity]
assert(sky[1] == "Models/valoria/skybridge.glb" and sky[5].collider == "mesh")
assert(sky[2] == valoria.Skybridge.start.x and sky[4] == valoria.Skybridge.start.z and sky[3] == valoria.GateY,
    "arched bridge starts at the gate at the gate floor level")
assert(math.abs(valoria.Skybridge.start.x - (gx - valoria.Gate.depth / 2)) < 3, "bridge meets the outer face of the gate")
assert(math.abs(valoria.Skybridge.points[1][3]) < 0.1, "no step between bridge and gate")

-- start na mostě před branou, pohled na město
assert(valoria.Spawn.x < gx and valoria.Spawn.x > gx - 80 and valoria.Spawn.z == gz and valoria.Spawn.yaw == 90)

-- lucerny (most, ulice, náměstí, přístav) a světla
local lamps = find(C .. "lamp_post.glb")
assert(#lamps >= 40, "lamp posts along bridge and streets: " .. #lamps)
local lights = find("light")
assert(#lights >= 20)

-- domy podél hlavní ulice (kolizní síť) a husté čtvrti (instance s kolizí kmenem)
local street = 0
for k = 0, 3 do street = street + #find(C .. "house_" .. k .. ".glb") end
assert(street >= 30, "street houses: " .. street)
assert(valoria.DistrictHouses and valoria.DistrictHouses >= 150, "dense districts: " .. tostring(valoria.DistrictHouses))
for _, ic in ipairs(instanceCalls) do
    if ic[1]:find("house_", 1, true) then assert(ic[3].collider == "capsule") end
end

-- panorama: katedrála s kopulí, gotické věže, hrad na skále, hradby
assert(#find(C .. "dome_hall.glb") == 2, "cathedral on the plaza and rotunda behind the gate")
local towers = #find(C .. "tower_a.glb") + #find(C .. "tower_b.glb") + #find(C .. "tower_c.glb") + #find(C .. "tower_round.glb")
assert(towers >= 10, "towers: " .. towers)
assert(#find("Models/valoria/keep.glb") == 1 and #find("Models/valoria/keep_floor.glb") == 1)
assert(#find(C .. "city_wall.glb") >= 20, "city walls along the cliff rim")

-- přístav: tři mola, lodě, schodiště na plošinu
assert(#find(C .. "dock.glb") == 3)
local ships = #find(C .. "ship_0.glb") + #find(C .. "ship_1.glb") + #find(C .. "ship_2.glb")
assert(ships >= 5, "ships in the harbor: " .. ships)
assert(#find(C .. "harbor_stairs.glb") == 1)
local s = valoria.Stairs
assert(ground(s.x0, s.z0) < 5 and ground(s.x1, s.z1) > 45, "stairs lead from the harbor up to the city")

-- létající ostrovy na obloze, portály
local isles = #find(C .. "sky_island_0.glb") + #find(C .. "sky_island_1.glb") + #find(C .. "sky_island_2.glb")
assert(isles >= 5)
for _, c in ipairs(calls) do
    if c[1]:find("sky_island", 1, true) then assert(c[3] > 100, "islands float high above the sea") end
end
assert(#find("Models/nature/aetherium_big.glb") == 2, "both portals must be visible")
assert(valoria.NearPortal(valoria.CityPortal.x, valoria.CityPortal.z) == valoria.OutpostPortal)
assert(valoria.NearPortal(valoria.OutpostPortal.x, valoria.OutpostPortal.z) == valoria.CityPortal)
assert(valoria.NearPortal(0, 0) == nil)

-- tráva neroste na ulici, náměstí ani pod domy; dlažba ulice
assert(#valoria.GrassExclude > 100)
local paving
for _, ic in ipairs(instanceCalls) do if ic[1] == "Models/valoria/paving.glb" then paving = ic end end
assert(paving and #paving[2] > 500, "street and plaza paving")
for _, tile in ipairs(paving[2]) do
    local x, y, z = tile[1], tile[2], tile[3]
    if x > gx + valoria.Gate.depth / 2 + 1 then
        local top = -math.huge
        for dx = -1, 1 do for dz = -1, 1 do top = math.max(top, ground(x + dx, z + dz)) end end
        assert(y >= top + 0.03 - 1e-6, "paving clears the terrain")
    end
end
print("Valorie Harbor: OK")
