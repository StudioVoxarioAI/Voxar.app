-- Mazlíček: Šedý vlk (Quadruped Forge, světlejší srst). Chodí s hráčem (vedle a kousek za ním, přizpůsobí tempo),
-- a chrání ho: vrhne se na každého nepřítele, který na hráče útočí, a pomáhá s cílem, na který hráč útočí.
-- Klávesa K = přivolat / poslat domů (nebo pravé tlačítko na obojek v tašce). Obojek má každá Ozvěna od začátku.
local map = require("eryndor.map")
local player = require("eryndor.player")
local inv = require("eryndor.inventory")
local M = { active = false, name = "Šedý vlk" }
local sin, cos, rad, deg, sqrt, atan, exp, max, min, random = math.sin, math.cos, math.rad, math.deg, math.sqrt, math.atan,
    math.exp, math.max, math.min, math.random

local REF = { Walk = 1.3, Trot = 3.2, Run = 7.5 }
local KEY = "eryndor.pet"

function M.Load()
    if inv.Count("wolf_pet") == 0 then inv.Add("wolf_pet", 1, true) end
    M.wanted = not settings or settings.get(KEY, true) ~= false
end

local function play(clip, speed, loop)
    if M.clip ~= clip then anim.play(M.id, clip, 0.25, loop ~= false, loop == false); M.clip = clip end
    if speed and math.abs((M.animSpeed or 1) - speed) > 0.03 then anim.speed(M.id, speed); M.animSpeed = speed end
end

local function groundY(x, z, y)
    local hit = physics.raycast(x, (y or map.HeightAt(x, z)) + 1.5, z, 0, -1, 0, 6, player.body)
    if hit and hit.point then return hit.point.y end
    return map.HeightAt(x, z)
end

function M.Summon(quiet)
    if M.active or not player.body then return end
    local px, py, pz = player.Pos()
    local a = rad(player.facing + 140)
    M.x, M.z = px + sin(a) * 2.5, pz + cos(a) * 2.5
    M.y = groundY(M.x, M.z, py)
    M.yaw = player.facing
    M.id = _G.world.spawn("Models/fauna/wolf.glb", M.x, M.y, M.z, { yaw = M.yaw, name = M.name, scale = 0.95, lod = "auto",
        lod_distance = 35, tag = "pet" })
    entity.material_color(M.id, "Coat*", { 0.92, 0.94, 1.0 })   -- světlejší, stříbřitá srst
    M.clip, M.animSpeed, M.target, M.nextBite = nil, nil, nil, 0
    play("Idle")
    M.active = true
    if not quiet then
        _G.world.particles(M.x, M.y + 0.4, M.z, { preset = "arcane", burst = 24, duration = 0.1, life = 0.9 })
        require("eryndor.combat").Log(M.name .. " je s tebou.", { 0.75, 0.85, 1.0 })
    end
    if settings then settings.set(KEY, true) end
end

function M.Dismiss(quiet)
    if not M.active then return end
    if M.id then entity.destroy(M.id) end
    M.id, M.active = nil, false
    if not quiet then require("eryndor.combat").Log(M.name .. " odběhl domů.", { 0.75, 0.85, 1.0 }) end
    if settings and not quiet then settings.set(KEY, false) end
end

function M.Toggle() if M.active then M.Dismiss() else M.Summon() end end

-- koho chránit: nepřítel, který útočí na hráče (nejbližší), jinak cíl hráčova útoku
local function pickTarget(px, pz)
    local c = require("eryndor.combat")
    local best, bd = nil, 22 * 22
    for _, m in ipairs(c.mobs or {}) do
        if m.state == "chase" or m.state == "attack" then
            local d = (m.x - px) ^ 2 + (m.z - pz) ^ 2
            if d < bd then best, bd = m, d end
        end
    end
    if not best and c.auto and c.target and c.target.state ~= "dead" then best = c.target end
    return best
end

function M.Update(dt)
    if not player.body then return end
    if M.wanted and not M.active and not player.dead and game.time() > (M.retryT or 0) then
        M.retryT = game.time() + 3
        M.Summon(true)
    end
    if not M.active or not M.id then return end
    local now = game.time()
    local px, py, pz = player.Pos()
    local level = (require("eryndor.combat").me or {}).level or 1
    -- daleko (teleport, portál) = přiběhne hned za hráčem
    if (M.x - px) ^ 2 + (M.z - pz) ^ 2 > 60 * 60 then
        local a = rad(player.facing + 160)
        M.x, M.z = px + sin(a) * 3, pz + cos(a) * 3
    end
    local tgt = M.target
    if not tgt or tgt.state == "dead" or tgt.state == "return" then tgt = pickTarget(px, pz); M.target = tgt end
    local tx, tz, speed, stop
    if tgt and not player.dead then
        tx, tz = tgt.x, tgt.z
        local d = sqrt((tx - M.x) ^ 2 + (tz - M.z) ^ 2)
        local reach = 1.6 + (tgt.t.scale or 1) * 0.6
        if d > reach then
            speed = 8.5
        else
            speed, stop = 0, true
            M.yaw = deg(atan(tx - M.x, tz - M.z))
            if now >= M.nextBite then
                M.nextBite = now + 1.4
                play("Attack1", 1, false)
                M.biteT = now + 0.45
            end
        end
        if M.biteT and now >= M.biteT then
            M.biteT = nil
            local c = require("eryndor.combat")
            local dmg = math.floor((7 + level * 3) * (0.85 + random() * 0.3))
            c.HitMob(tgt, dmg, { 0.8, 0.85, 1.0 })
        end
    else
        -- doprovod: vedle hráče vlevo vzadu
        local a = rad(player.facing - 125)
        tx, tz = px + sin(a) * 2.2, pz + cos(a) * 2.2
        local d = sqrt((tx - M.x) ^ 2 + (tz - M.z) ^ 2)
        local ps = player.speed or 0
        if d < 0.6 then speed = 0
        else speed = min(max(ps * 1.1, d * 1.6), 11) end
        if player.mount then speed = min(max(ps * 1.05, d * 1.6), 17) end
    end
    if speed and speed > 0.05 then
        local dx, dz = tx - M.x, tz - M.z
        local l = sqrt(dx * dx + dz * dz)
        if l > 0.01 then
            local step = min(l, speed * dt)
            M.x, M.z = M.x + dx / l * step, M.z + dz / l * step
            local want = deg(atan(dx, dz))
            local diff = (want - M.yaw + 540) % 360 - 180
            M.yaw = M.yaw + diff * (1 - exp(-10 * dt))
        end
    end
    M.v = (M.v or 0) + ((speed or 0) - (M.v or 0)) * (1 - exp(-8 * dt))
    M.y = groundY(M.x, M.z, M.y)
    if (player.WaterY(M.x, M.z) or -999) > M.y + 0.4 then M.y = player.WaterY(M.x, M.z) - 0.45 end   -- plave
    entity.set_position(M.id, M.x, M.y, M.z)
    entity.set_rotation(M.id, 0, M.yaw, 0)
    if not stop and not (M.clip == "Attack1" and now < M.nextBite - 0.6) then
        local v = M.v
        if v < 0.3 then
            if player.dead then play("Howl") else play(tgt and "Idle_Look" or "Idle") end
        elseif v < 2.4 then play("Walk", max(0.6, v / REF.Walk))
        elseif v < 5.5 then play("Trot", max(0.7, v / REF.Trot))
        else play("Run", max(0.7, min(1.7, v / REF.Run))) end
    end
end

function M.DrawLabel()
    if M.active and M.id then
        ui.world_label(M.x, M.y + 1.25, M.z, M.name, { color = "#b9d4ff", size = 15, max_distance = 30 })
    end
end

return M
