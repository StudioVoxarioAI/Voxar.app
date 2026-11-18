-- Ozvěna (hráč): kapsle pro pohyb po terénu, model KayKit s výbavou, kamera za zády (MMO).
--   WASD / šipky pohyb, Shift sprint, Ctrl chůze, Space skok, pravé tlačítko myši otáčí kamerou, kolečko zoom.
local map = require("eryndor.map")
local humans = require("eryndor.humans")
local M = { cam = { yaw = 180, pitch = 18, distance = 7.5 }, facing = 180, speed = 0, moving = false,
            inputEnabled = true, runSpeed = 6.2, walkSpeed = 2.0, sprintSpeed = 9.0,
            swimSpeed = 3.2, swimFast = 5.0, oxygenMax = 20, oxygen = 20 }
-- rychlosti, při kterých pohybové klipy enginu nekloužou (tools/motion/humanoid_motion.py, REF) – při jiné
-- rychlosti se klip zrychlí / zpomalí; menší rasy (výška) dělají kratší kroky
M.ClipSpeed = { walk = 1.5, run = 5.0, sprint = 7.5 }

local sin, cos, rad, deg, sqrt, exp, max, min, atan = math.sin, math.cos, math.rad, math.deg, math.sqrt, math.exp, math.max, math.min, math.atan

function M.Pos(id)
    local p = entity.get_position(id or M.body)
    if not p then return 0, 0, 0 end
    return p.x or p[1], p.y or p[2], p.z or p[3]
end

-- appearance = vzhled z tvorby postavy (eryndor.races); bez něj model povolání
function M.Create(class, spawn, appearance)
    M.class = class
    M.appearance = appearance
    local x, z = spawn.x, spawn.z
    if spawn.yaw then M.facing = spawn.yaw; M.cam.yaw = spawn.yaw end   -- výchozí pohled (Valorie: na bránu)
    local y = map.HeightAt(x, z)
    local hit = physics.raycast(x, y + 60, z, 0, -1, 0, 80)   -- start na mostě / podlaze, ne pod nimi
    if hit and hit.point and hit.point.y > y then y = hit.point.y end
    M.viewY, M.footOffset = nil, nil
    M.body = _G.world.spawn("cylinder", x, y + 1.0, z, { visible = false, name = "Player", tag = "player",
        character = { radius = 0.35, height = 1.7, step = 0.45, slope = 50 } })
    if appearance then
        M.view, M.items, M.weapons = require("eryndor.races").Spawn(appearance, x, y, z, { name = appearance.name,
            right = class.look.right, left = class.look.left })
    else
        M.view = humans.Spawn(class.model, x, y, z, { name = class.name, right = class.look.right, left = class.look.left,
            helm = class.look.helm })
    end
    M.camera = entity.find("Camera")
    M.lamp = _G.world.spawn("light", x, y + 2.5, z, { light = { color = { 1.0, 0.8, 0.6 }, intensity = 8, range = 10, night_only = true } })
    M.anim = nil
    M.Play("Idle")
end

function M.Teleport(x, z)
    -- nejvyšší povrch v místě (mostovka, podlaha budovy), jinak terén
    local y = map.HeightAt(x, z)
    local hit = physics.raycast(x, y + 60, z, 0, -1, 0, 80, M.body)
    if hit and hit.point and hit.point.y > y then y = hit.point.y end
    entity.set_position(M.body, x, y + 1.0, z)
    entity.set_velocity(M.body, 0, 0, 0)
    M.viewY = nil
    if M.cam then M.cam.x, M.cam.y, M.cam.z = nil, nil, nil end   -- kamera skočí s hráčem (bez dlouhého dojezdu)
end

-- animace pohybu (útoky a kouzla hrají jako jednorázové přes M.Action); s holí varianta „_Staff“
local STAFF = { Idle = true, ["2H_Melee_Idle"] = true, Walking_A = true, Walking_Backwards = true, Running_A = true,
                Running_B = true, Running_Strafe_Left = true, Running_Strafe_Right = true }
function M.Clip(clip, class, appearance)
    class = class or M.class
    local w = require("eryndor.races").Weapon(appearance or M.appearance, class)
    if (w == "staff" or w == "gear/hul") and STAFF[clip] then return clip .. "_Staff" end
    return clip
end
function M.Play(clip, fade, loop)
    clip = M.Clip(clip)
    if M.anim == clip then return end
    M.anim = clip
    anim.play(M.view, clip, fade or 0.15, loop ~= false)
end

-- jednorázová akce (útok, kouzlo, zásah): po dohrání se vrátí k pohybu
function M.Action(clip, dur, speed)
    M.actionT = game.time() + (dur or 0.8)
    M.anim = clip
    anim.play(M.view, clip, 0.08, false, true)
    anim.speed(M.view, speed or 1)
    if M.onAction then M.onAction(clip, dur) end   -- ostatní hráči (eryndor.presence)
end

local function angleLerp(a, b, t)
    local d = (b - a + 540) % 360 - 180
    return a + d * t
end

-- moveTo = {x, z} – automatický přesun k cíli (útok na vzdálený cíl, jako v 4Story)
-- výška povrchu pod bodem: paprsek dolů (kolize mostů, budov, terénu), záloha výšková mapa
function M.GroundY(x, y, z)
    local hit = physics.raycast(x, y + 0.6, z, 0, -1, 0, 8, M.body)
    if hit and hit.point then return hit.point.y end
    return map.HeightAt(x, z)
end

function M.Update(dt, combatPose, moveTo, rooted)
    if not M.body then return end
    local c = M.cam
    local fx, fz = sin(rad(c.yaw)), cos(rad(c.yaw))
    local rx, rz = -fz, fx
    local ix, iz = 0, 0
    if M.inputEnabled and not M.dead then
        if input.key("W") or input.key("Up") then iz = iz + 1 end
        if input.key("S") or input.key("Down") then iz = iz - 1 end
        if input.key("D") or input.key("Right") then ix = ix + 1 end
        if input.key("A") or input.key("Left") then ix = ix - 1 end
    end
    local mx, mz = fx * iz + rx * ix, fz * iz + rz * ix
    M.manual = (ix ~= 0 or iz ~= 0)
    if M.emote and (M.manual or (M.inputEnabled and input.pressed("Space"))) then require("eryndor.emotes").StopSelf() end
    local px, py, pz = M.Pos()
    if not M.manual and moveTo then
        local dx, dz = moveTo[1] - px, moveTo[2] - pz
        local d = sqrt(dx * dx + dz * dz)
        if d > 0.2 then mx, mz = dx / d, dz / d end
    end
    if rooted or M.dead then mx, mz = 0, 0 end
    local ml = sqrt(mx * mx + mz * mz)
    if ml > 1 then mx, mz, ml = mx / ml, mz / ml, 1 end
    local spd = M.runSpeed
    if M.inputEnabled and input.key("Shift") and M.manual then spd = M.sprintSpeed
    elseif M.inputEnabled and input.key("Ctrl") then spd = M.walkSpeed end
    if M.mount then spd = M.mount.Speed(M.inputEnabled and input.key("Shift") and M.manual, M.inputEnabled and input.key("Ctrl")) end
    if M.UpdateSwim(dt, mx, mz, ml) then return end
    local k = 1 - exp(-14 * dt)
    M.vx = (M.vx or 0) + (mx * spd - (M.vx or 0)) * k
    M.vz = (M.vz or 0) + (mz * spd - (M.vz or 0)) * k
    local jump = (M.inputEnabled and not M.dead and not M.swim and not M.emote and input.pressed("Space")) and (M.mount and 7.0 or 6.0) or 0
    local grounded = physics.move_character(M.body, M.vx, M.vz, jump)
    if jump > 0 and not M.mount then M.Action("Jump_Full_Short", 0.9) end
    if ml > 0.05 then M.facing = angleLerp(M.facing, deg(atan(mx, mz)), 1 - exp(-12 * dt)) end
    if M.faceTarget and ml < 0.05 then M.facing = angleLerp(M.facing, M.faceTarget, 1 - exp(-10 * dt)) end
    M.speed = sqrt(M.vx * M.vx + M.vz * M.vz)
    M.moving = M.speed > 0.4

    -- model na zemi pod kapslí
    px, py, pz = M.Pos()
    -- skutečný povrch pod kapslí (most, dlažba, podlaha hradu, terén) – výšková mapa terénu by na mostě ukazovala
    -- zem pod ním a na svazích se lišila od kolizní sítě (model pak poskakoval mezi dvěma výškami)
    local th = M.GroundY(px, py, pz)
    -- chodidla: odsazení kapsle od země se změří jednou, když stojí na zemi (pak už je pevné)
    if grounded then
        local measured = py - th
        if not M.footOffset then M.footOffset = measured
        elseif math.abs(measured - M.footOffset) < 0.3 then   -- jen pomalé doladění, žádné skoky
            M.footOffset = M.footOffset + (measured - M.footOffset) * (1 - exp(-2 * dt))
        end
    end
    local gy = py - (M.footOffset or 0)
    if grounded and math.abs(gy - th) < 0.35 then gy = th end
    -- svislá poloha modelu plynule (kapsle na schodech a hranách dlaždic skáče o centimetry)
    if M.viewY and math.abs(gy - M.viewY) < 0.6 and grounded then
        gy = M.viewY + (gy - M.viewY) * (1 - exp(-22 * dt))
    end
    M.viewY = gy
    if M.mount then   -- na koni: kůň nese jezdce (eryndor.mount)
        M.mount.Pose(dt, px, gy, pz, M.facing, M.speed)
        return
    end
    entity.set_position(M.view, px, gy, pz)
    entity.set_rotation(M.view, 0, M.facing, 0)
    entity.set_position(M.lamp, px, gy + 2.6, pz)

    if M.dead then
        -- leží (animace smrti hraje z combat)
    elseif M.actionT and game.time() < M.actionT then
        -- probíhá akce
    else
        M.actionT = nil
        local h = (M.appearance and M.appearance.height) or 1
        local ref
        if M.speed > 7.4 then M.Play("Running_B"); ref = M.ClipSpeed.sprint
        elseif M.speed > 3.2 then M.Play("Running_A"); ref = M.ClipSpeed.run
        elseif M.speed > 0.4 then M.Play("Walking_A"); ref = M.ClipSpeed.walk
        elseif combatPose then M.Play("2H_Melee_Idle")
        else M.Play("Idle") end
        anim.speed(M.view, ref and math.max(0.5, math.min(2.2, M.speed / (ref * h))) or 1)
    end
end

-- ------------------------------------------------------------------ plavání a potápění
-- Hlubší voda než po hrudník: postava plave (nesahá na dno). U hladiny kraul / šlapání vody, Ctrl (C) ponoří,
-- Space vynoří, pod vodou plave směrem kamery (W s kamerou dolů = dolů). Dech: 20 s pod vodou, pak se postava udusí.
local function waterY(x, z)
    local f = _G.world.water_height
    if not f then return nil end
    return f(x, z)
end
M.WaterY = waterY

function M.UpdateSwim(dt, mx, mz, ml)
    local px, py, pz = M.Pos()
    local th = map.HeightAt(px, pz)
    local wy = waterY(px, pz)
    local h = (M.appearance and M.appearance.height) or 1
    local foot = M.footOffset or 0.95
    local deep = wy and (wy - th) > 1.45 * h
    local s = M.swim
    if not s then
        -- vstup: voda hlubší než po hrudník a chodidla pod hladinou
        if not (deep and (py - foot) < wy - 1.2 * h) or M.dead then
            M.UpdateOxygen(dt, false)
            return false
        end
        s = { y = py, vy = 0, dive = false, tilt = 0, off = 0 }
        M.swim = s
        M.vx, M.vz = M.vx or 0, M.vz or 0
    end
    if M.dead then M.swim = nil; return false end
    -- výstup na mělčinu: zase chodí
    if not wy or (wy - th) < 1.2 * h then
        M.swim = nil
        entity.set_position(M.body, px, math.max(py, th + foot), pz)
        entity.set_velocity(M.body, 0, 0, 0)
        return false
    end
    local inp = M.inputEnabled
    local up = inp and input.key("Space")
    local down = inp and (input.key("Ctrl") or input.key("C"))
    local fast = inp and input.key("Shift")
    local surfaceY = wy - 1.25 * h + foot          -- kapsle: hrudník u hladiny
    if down then s.dive = true end
    local spd = fast and M.swimFast or M.swimSpeed
    local k = 1 - exp(-6 * dt)
    M.vx = (M.vx or 0) + (mx * spd - (M.vx or 0)) * k
    M.vz = (M.vz or 0) + (mz * spd - (M.vz or 0)) * k
    local tvy
    if s.dive then
        -- pod vodou: vertikálně Space / Ctrl, při pohybu vpřed i podle sklonu kamery; bez vstupu pomalu stoupá
        tvy = (up and 2.4 or 0) - (down and 2.4 or 0)
        if ml > 0.05 and M.manual then tvy = tvy - math.sin(rad(M.cam.pitch - 12)) * spd * 0.9 end
        if not up and not down and not (ml > 0.05 and M.manual) then tvy = 0.35 end
    else
        tvy = (surfaceY - s.y) * 4.0                 -- u hladiny: houpe se s vlnami
    end
    s.vy = s.vy + (tvy - s.vy) * (1 - exp(-5 * dt))
    local nx, nz = px + M.vx * dt, pz + M.vz * dt
    local nth = map.HeightAt(nx, nz)
    local nwy = waterY(nx, nz) or wy
    if (nwy - nth) < 0.9 * h and nth > th then nx, nz = px, pz end   -- strmý břeh: nevyplave do skály
    s.y = s.y + s.vy * dt
    local bottom = map.HeightAt(nx, nz) + foot * 0.55               -- nad dnem (nikdy nechodí po dně)
    if s.y < bottom then s.y, s.vy = bottom, math.max(s.vy, 0) end
    if s.y >= surfaceY then
        s.y = math.min(s.y, surfaceY + 0.05)
        if s.dive and not down then s.dive = false end
    end
    entity.set_position(M.body, nx, s.y, nz)
    entity.set_velocity(M.body, 0, 0, 0)
    M.speed = sqrt(M.vx * M.vx + M.vz * M.vz)
    M.moving = M.speed > 0.3
    if ml > 0.05 then M.facing = angleLerp(M.facing, deg(atan(mx, mz)), 1 - exp(-8 * dt)) end
    -- model: kraul leží u hladiny, šlapání vody stojí (hlava nad vodou)
    local swimming = M.speed > 0.6
    local target = swimming and (0.15 * h) or (1.3 * h)
    s.off = s.off + (target - s.off) * (1 - exp(-6 * dt))
    local tilt = 0
    if s.dive and swimming then tilt = math.max(-50, math.min(50, deg(math.atan(-s.vy, math.max(M.speed, 0.1))))) end
    s.tilt = s.tilt + (tilt - s.tilt) * (1 - exp(-6 * dt))
    local bodyY = s.y - foot                          -- výška chodidel kapsle
    local vy_ = s.dive and (bodyY + 1.25 * h - s.off) or (wy - s.off)
    entity.set_position(M.view, nx, vy_, nz)
    entity.set_rotation(M.view, s.tilt, M.facing, 0)
    entity.set_position(M.lamp, nx, vy_ + 2.6, nz)
    s.head = swimming and (vy_ + 0.12 * h) or (vy_ + 1.6 * h)
    M.UpdateOxygen(dt, s.head < (nwy or wy) - 0.05)
    if not (M.actionT and game.time() < M.actionT) then
        M.actionT = nil
        if swimming then M.Play("Swimming") else M.Play("Swim_Idle") end
        anim.speed(M.view, swimming and math.max(0.7, math.min(1.6, M.speed / M.swimSpeed)) or 1)
    end
    return true
end

-- dech: 20 s, ubývá jen když je celá postava pod hladinou (i hlava); nad hladinou se rychle doplní.
-- Dojde-li dech, postava se udusí a zemře.
function M.UpdateOxygen(dt, under)
    M.underwater = under
    if under then
        M.oxygen = math.max(0, M.oxygen - dt)
        if M.oxygen <= 0 and not M.dead then
            local c = require("eryndor.combat")
            if c.me then c.HurtPlayer(c.me.hp + c.me.maxhp, "Došel ti dech – utonul jsi. Ozvěna se vrací ke Zřídlu…") end
        end
    else
        M.oxygen = math.min(M.oxygenMax, M.oxygen + dt * 6)
        M.drownT = 0
    end
end

function M.UpdateCamera(dt)
    if not M.camera or not M.body then return end
    local c = M.cam
    if M.inputEnabled and not ui.wants_mouse() then
        if input.key("Mouse2") then
            local dx, dy = input.mouse_delta()
            c.yaw = c.yaw - dx * 0.25
            c.pitch = max(-5, min(70, c.pitch + dy * 0.2))
        end
        c.distance = max(2.5, min(20, c.distance - input.wheel() * 0.9))
    end
    local px, py, pz = M.Pos()
    local tx, ty, tz = px, py + 0.9, pz
    local cp, sp = cos(rad(c.pitch)), sin(rad(c.pitch))
    local fx, fy, fz = sin(rad(c.yaw)) * cp, -sp, cos(rad(c.yaw)) * cp
    local wx, wy, wz = tx - fx * c.distance, ty - fy * c.distance, tz - fz * c.distance
    local ground = map.HeightAt(wx, wz) + 0.5
    if wy < ground then wy = ground end
    c.x = c.x and c.x + (wx - c.x) * (1 - exp(-16 * dt)) or wx
    c.y = c.y and c.y + (wy - c.y) * (1 - exp(-16 * dt)) or wy
    c.z = c.z and c.z + (wz - c.z) * (1 - exp(-16 * dt)) or wz
    local dx, dy, dz = tx - c.x, ty - c.y, tz - c.z
    entity.set_position(M.camera, c.x, c.y, c.z)
    entity.set_rotation(M.camera, deg(atan(dy, sqrt(dx * dx + dz * dz))), deg(atan(-dx, -dz)), 0)
end

return M
