-- Kořist na zemi: z poražených nepřátel padá výbava (items.LootFor). Leží u mrtvoly – zbraň jako model zbraně
-- položený na zem, zbroj v koženém vaku – se sloupcem světla v barvě vzácnosti (od Neobvyklého výš) a jmenovkou.
-- Klávesa E u kořisti ji zvedne do tašky (stejně jako sbírání u profesí). Po 5 minutách zmizí.
local map = require("eryndor.map")
local items = require("eryndor.items")
local M = { list = {} }
local sin, cos, random = math.sin, math.cos, math.random

local BEAM = {
    uncommon = { 0.25, 1.0, 0.3 }, rare = { 0.25, 0.55, 1.0 }, epic = { 0.75, 0.35, 1.0 }, legendary = { 1.0, 0.6, 0.12 },
}

function M.Drop(item, x, z)
    local a = random() * 2 * math.pi
    x, z = x + cos(a) * (0.6 + random() * 0.8), z + sin(a) * (0.6 + random() * 0.8)
    local y = map.HeightAt(x, z)
    local b = items.Base[item.id]
    local d = { item = item, x = x, z = z, y = y, t = game.time() }
    if b.armor then
        d.id = _G.world.spawn("Models/prof/loot_bag.glb", x, y, z, { yaw = random() * 360, name = b.name })
    else
        d.id = _G.world.spawn("Models/gear/real/" .. b.model .. ".glb", x, y + 0.05, z, { name = b.name })
        entity.set_rotation(d.id, 90, random() * 360, 0)   -- leží na zemi
    end
    local col = BEAM[item.g.r]
    if col then
        d.light = _G.world.spawn("light", x, y + 0.8, z, { light = { color = col, intensity = item.g.r == "legendary" and 10 or 6, range = 6 } })
        d.beam = _G.world.particles(x, y + 0.1, z, { preset = "holy", rate = 18, speed = 2.2, spread = 0.05, dir = { 0, 1, 0 },
            life = 1.3, size = 0.6, color = col, radius = 0.15, distance = 160 })
    end
    M.list[#M.list + 1] = d
    return d
end

local function remove(i)
    local d = M.list[i]
    for _, k in ipairs({ "id", "light", "beam" }) do if d[k] then entity.destroy(d[k]) end end
    table.remove(M.list, i)
end

-- nejbližší kořist u hráče (pro nápovědu a E)
function M.Near(px, pz)
    local best, bi, bd = nil, nil, 2.6 * 2.6
    for i, d in ipairs(M.list) do
        local dd = (d.x - px) ^ 2 + (d.z - pz) ^ 2
        if dd < bd then best, bi, bd = d, i, dd end
    end
    return best, bi
end

function M.PickUp(px, pz)
    local d, i = M.Near(px, pz)
    if not d then return false end
    local inv = require("eryndor.inventory")
    if not inv.PutGear(d.item) then require("eryndor.combat").Log("Taška je plná.", { 1, 0.5, 0.4 }); return true end
    require("eryndor.combat").Log("Získáno: " .. items.Name(d.item) .. " (" .. items.Rarity[d.item.g.r].name .. ")", { 0.6, 1.0, 0.6 })
    require("eryndor.player").Action("PickUp", 0.8)
    remove(i)
    return true
end

-- po zabití nepřítele (combat.killHooks)
local firstKill = true
function M.OnKill(m)
    local drops = items.LootFor(m)
    if firstKill and not m.t.boss then
        -- první zabitý nepřítel: zbraň pro povolání (ať se dlouho nebojuje pěstmi)
        firstKill = false
        local eq = require("eryndor.equipment")
        if not eq.slots.main then
            local cls = require("eryndor.combat").me
            local id = items.ClassStarter[cls and cls.class.id or "knight"] or "sword_1h"
            drops[#drops + 1] = items.Roll(id, 1, "common")
        end
    end
    for _, it in ipairs(drops) do M.Drop(it, m.x, m.z) end
end

function M.Update(dt)
    local now = game.time()
    for i = #M.list, 1, -1 do
        local d = M.list[i]
        if now - d.t > 300 then remove(i)
        elseif d.light then entity.set_position(d.light, d.x, d.y + 0.8 + 0.08 * sin(now * 3 + d.x), d.z) end
    end
end

function M.DrawLabels()
    for _, d in ipairs(M.list) do
        ui.world_label(d.x, d.y + 0.7, d.z, items.Name(d.item), { color = items.Color(d.item), size = 16, max_distance = 35 })
    end
end

function M.Clear() for i = #M.list, 1, -1 do remove(i) end end

return M
