-- Mount: kůň Hnědák (Quadruped Forge, Models/fauna/horse.glb) se sedlem. Daruje ho kapitán Roderik Valorský
-- na náměstí Valorie (značka na mapě a „🐎“ nad kapitánem, dokud koně nemáš). Klávesa H = nasednout / sesednout
-- (nebo pravé tlačítko na píšťalku v tašce). Na koni: chůze Ctrl, klus/cval bez kláves, Shift = trysk.
-- Ve vodě, při útoku nebo smrti jezdec sesedne.
local map = require("eryndor.map")
local player = require("eryndor.player")
local inv = require("eryndor.inventory")
local M = { riding = false }
local sin, cos, rad, max, min, exp = math.sin, math.cos, math.rad, math.max, math.min, math.exp

M.Speeds = { walk = 3.2, run = 11.0, sprint = 16.0 }
M.Ref = { Walk = 1.7, Trot = 4.0, Run = 11.0 }   -- quadruped_forge.SPEEDS["horse"]
M.SeatUp = 0.30       -- sedlo nad kostí Spine1 koně
M.RiderDown = 0.50    -- pánev jezdce nad chodidly v póze Sit_Chair (kořen modelu jde níž)

function M.Has() return inv.Has("horse") end

function M.Give()
    if M.Has() then return end
    inv.Add("horse", 1)
    require("eryndor.combat").Log("Získal jsi koně Hnědáka! Klávesa H = nasednout.", { 1.0, 0.85, 0.4 })
end

function M.Mount()
    local c = require("eryndor.combat")
    if M.riding or not M.Has() or not player.body or player.dead then return end
    if player.swim then c.Log("Ve vodě nasednout nejde.", { 1, 0.6, 0.5 }); return end
    if c.inCombat then c.Log("V boji nemůžeš přivolat koně.", { 1, 0.6, 0.5 }); return end
    local px, py, pz = player.Pos()
    local gy = player.viewY or map.HeightAt(px, pz)
    M.horse = _G.world.spawn("Models/fauna/horse.glb", px, gy, pz, { yaw = player.facing, name = "Hnědák", lod = "auto",
        lod_distance = 35, tag = "mount" })
    M.saddle = _G.world.spawn("Models/prof/saddle.glb", px, gy + 1.5, pz, { name = "Sedlo" })
    M.hclip = nil
    for _, w in ipairs(player.weapons or {}) do entity.set_visible(w, false) end
    _G.world.particles(px, gy + 0.3, pz, { preset = "dust", burst = 40, duration = 0.1, life = 1.4, radius = 1.2 })
    if audio and audio.tone then audio.tone(380, 0.25, "triangle", 0.18, 260) end
    M.riding = true
    player.mount = M
    player.anim = nil
    anim.play(player.view, "Sit_Chair_Idle", 0.2, true)
    -- nohy do stran (obkročmo), chodidla dolů k třmenům
    entity.bone_rotate(player.view, "thigh_l", 0, 0, -24)
    entity.bone_rotate(player.view, "thigh_r", 0, 0, 24)
    entity.bone_rotate(player.view, "calf_l", 28, 0, 0)
    entity.bone_rotate(player.view, "calf_r", 28, 0, 0)
    if M.onChange then M.onChange(true) end
end

function M.Dismount(quiet)
    if not M.riding then return end
    M.riding = false
    player.mount = nil
    for _, b in ipairs({ "thigh_l", "thigh_r", "calf_l", "calf_r", "spine_01" }) do entity.bone_rotate(player.view, b) end
    for _, w in ipairs(player.weapons or {}) do entity.set_visible(w, true) end
    if M.horse then
        local x, y, z = player.Pos(M.horse)
        if not quiet then _G.world.particles(x, y + 0.3, z, { preset = "dust", burst = 30, duration = 0.1, life = 1.2, radius = 1.0 }) end
        entity.destroy(M.horse); M.horse = nil
    end
    if M.saddle then entity.destroy(M.saddle); M.saddle = nil end
    player.anim = nil
    player.viewY = nil
    if M.onChange then M.onChange(false) end
end

function M.Toggle() if M.riding then M.Dismount() else M.Mount() end end

-- rychlosti pro player.Update
function M.Speed(sprint, walk)
    if sprint then return M.Speeds.sprint end
    if walk then return M.Speeds.walk end
    return M.Speeds.run
end

-- poloha koně, sedla a jezdce; st = stav (klip, náklon) – vlastní kůň i koně ostatních hráčů (presence)
function M.PoseEntities(horse, saddle, rider, px, gy, pz, facing, speed, st, dt)
    entity.set_position(horse, px, gy, pz)
    -- náklon podle svahu (podélně)
    local f = rad(facing)
    local ahead = map.HeightAt(px + sin(f) * 1.2, pz + cos(f) * 1.2)
    local behind = map.HeightAt(px - sin(f) * 1.2, pz - cos(f) * 1.2)
    local pitch = math.deg(math.atan(behind - ahead, 2.4))
    st.pitch = (st.pitch or 0) + (max(-18, min(18, pitch)) - (st.pitch or 0)) * (1 - exp(-6 * dt))
    entity.set_rotation(horse, st.pitch, facing, 0)
    local function clip(name, sp)
        if st.hclip ~= name then anim.play(horse, name, 0.25, true); st.hclip = name end
        anim.speed(horse, sp or 1)
    end
    if speed < 0.4 then clip("Idle")
    elseif speed < 2.6 then clip("Walk", max(0.6, speed / M.Ref.Walk))
    elseif speed < 7.5 then clip("Trot", max(0.7, speed / M.Ref.Trot))
    else clip("Run", max(0.7, min(1.6, speed / M.Ref.Run))) end
    local b = entity.bone_position(horse, "Spine1")
    local sx, sy, sz = px, gy + 1.62, pz
    if b then sx, sy, sz = b.x or b[1], (b.y or b[2]) + M.SeatUp, b.z or b[3] end
    if saddle then
        entity.set_position(saddle, sx, sy - 0.02, sz)
        entity.set_rotation(saddle, st.pitch, facing, 0)
    end
    entity.set_position(rider, sx, sy - M.RiderDown, sz)
    entity.set_rotation(rider, st.pitch * 0.6, facing, 0)
    -- v cvalu se jezdec nakloní dopředu
    entity.bone_rotate(rider, "spine_01", min(1, speed / M.Speeds.run) * 14, 0, 0)
end

-- vlastní kůň (volá player.Update místo běžné animace)
function M.Pose(dt, px, gy, pz, facing, speed)
    if not M.horse then return end
    M.PoseEntities(M.horse, M.saddle, player.view, px, gy, pz, facing, speed, M, dt)
    entity.set_position(player.lamp, px, gy + 3.2, pz)
end

function M.Update(dt)
    if M.riding and (player.swim or player.dead) then M.Dismount() end
end

-- kapitán Roderik: kde koně získat (štítek nad hlavou a značka na mapě, dokud koně nemáš)
function M.Giver()
    return require("eryndor.citizens").captain
end

function M.DrawLabels()
    local c = M.Giver()
    if c and not M.Has() then
        ui.world_label(c.x, (require("eryndor.citizens").Y or 2) + 3.3, c.z, "! Kůň – Kapitán Roderik",
            { color = "#ffd890", size = 20, max_distance = 90 })
    end
end

return M
