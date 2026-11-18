-- Emoty (klávesa G = nabídka, nebo klávesy v nabídce 1–6): tanec, mávání, jásot, úklona, sednout, lehnout.
-- Tanec, mávání a úklona jsou procedurální (natočení kostí přes entity.bone_rotate nad klidovou pózou),
-- ostatní používají klipy postav. Pohyb emotu ukončí. Ostatní hráči je vidí (eryndor.presence, zpráva „emote“).
local M = { list = {}, open = false, active = {} }
local sin, cos, pi, abs = math.sin, math.cos, math.pi, math.abs

M.List = {
    { id = "dance", name = "Tanec", loop = true },
    { id = "wave", name = "Mávání", dur = 2.6 },
    { id = "cheer", name = "Jásot", clip = "Cheer", dur = 2.2 },
    { id = "bow", name = "Úklona", dur = 2.2 },
    { id = "sit", name = "Sednout", clip = "Sit_Floor_Down", hold = "Sit_Floor_Idle", loop = true },
    { id = "lie", name = "Lehnout", clip = "Lie_Down", hold = "Lie_Idle", loop = true },
}
local byId = {}
for _, e in ipairs(M.List) do byId[e.id] = e end

local BONES = { "pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head", "upperarm_l", "upperarm_r", "lowerarm_l",
                "lowerarm_r", "hand_l", "hand_r", "thigh_l", "thigh_r", "calf_l", "calf_r", "clavicle_l", "clavicle_r" }

local function clear(id)
    for _, b in ipairs(BONES) do entity.bone_rotate(id, b) end
end

-- spustí emote na entitě postavy (hráč i ostatní hráči)
function M.Start(id, eid, weapons)
    local e = byId[eid]
    if not id or not e then return end
    M.Stop(id)
    M.active[id] = { e = e, t0 = game.time(), weapons = weapons }
    for _, w in ipairs(weapons or {}) do entity.set_visible(w, false) end   -- zbraně při emotu pryč z rukou
    if e.clip then anim.play(id, e.clip, 0.2, e.hold == nil and not e.loop, true)
    else anim.play(id, "Idle", 0.2, true) end
end

function M.Stop(id)
    if not id or not M.active[id] then return end
    for _, w in ipairs(M.active[id].weapons or {}) do if entity.exists(w) then entity.set_visible(w, true) end end
    M.active[id] = nil
    clear(id)
end

function M.Is(id) return M.active[id] ~= nil end

-- procedurální pózy (stupně; osy kostí rigu ras: X = předklon / zvednutí vpřed, Z = do strany)
local POSE = {}
function POSE.dance(t)
    -- osy rigu ras (ověřeno samotestem „osy“): páteř X = předklon, Y = otočení, Z = úklon do strany;
    -- paže Z = upažení / vzpažení, Y = předpažení; čelist -X = otevřít
    local b = t * 2 * pi * 1.05          -- ~126 BPM: krok na každou dobu
    local s, c2 = sin(b), sin(b * 2)
    local up = math.min(1, t / 0.4)
    return {
        spine_01 = { 3, s * 12, s * 7 },
        spine_02 = { 0, s * 6, s * 4 },
        neck_01 = { 0, -s * 8, -s * 6 },
        head = { c2 * 5, 0, -s * 4 },
        upperarm_l = { 0, 20 * c2 * up, (75 + 30 * s) * up },
        upperarm_r = { 0, -20 * c2 * up, -(75 - 30 * s) * up },   -- pravá strana zrcadlově (záporná Z)
        lowerarm_l = { 0, 0, (35 + 25 * c2) * up },
        lowerarm_r = { 0, 0, -(35 - 25 * c2) * up },
        hand_l = { 0, 0, 20 * c2 * up },
        hand_r = { 0, 0, 20 * c2 * up },
        thigh_l = { 0, 0, 10 * math.max(0, s) },
        thigh_r = { 0, 0, 10 * math.max(0, -s) },
    }
end
function POSE.wave(t)
    local up = math.min(1, t / 0.35) * math.min(1, math.max(0, (2.6 - t) / 0.35))
    local w = sin(t * 2 * pi * 2.2)
    return {
        upperarm_r = { 0, -15 * up, -150 * up },
        lowerarm_r = { 0, 0, -(30 + 28 * w) * up },
        hand_r = { 0, 0, -12 * w * up },
        head = { 0, -10 * up, 4 * up },
    }
end
function POSE.bow(t)
    local k = math.min(1, t / 0.5) * math.min(1, math.max(0, (2.2 - t) / 0.5))
    return {
        spine_01 = { 30 * k, 0, 0 }, spine_02 = { 18 * k, 0, 0 }, neck_01 = { 12 * k, 0, 0 },
        upperarm_r = { -20 * k, 0, 0 }, lowerarm_r = { -70 * k, 0, 0 },
        upperarm_l = { 10 * k, 0, 0 },
    }
end

function M.Update(dt)
    local now = game.time()
    for id, s in pairs(M.active) do
        if not entity.exists(id) then M.active[id] = nil
        else
            local e, t = s.e, now - s.t0
            if e.hold and not s.held and t > (e.holdAt or 1.6) then
                s.held = true
                anim.play(id, e.hold, 0.25, true)
            end
            local f = POSE[e.id]
            if f then
                for bone, r in pairs(f(t)) do entity.bone_rotate(id, bone, r[1], r[2], r[3]) end
            end
            if e.dur and t > e.dur then
                M.Stop(id)
                if s.onEnd then s.onEnd() end
            end
        end
    end
end

-- ------------------------------------------------------------------ vlastní postava
function M.Play(eid)
    local player = require("eryndor.player")
    if not player.view or player.dead or player.swim or player.mount then return end
    M.Start(player.view, eid, player.weapons)
    M.active[player.view].onEnd = function() player.emote = nil; player.anim = nil end
    player.emote = eid
    player.anim = nil
    player.actionT = game.time() + 3600
    if M.onPlay then M.onPlay(eid) end
end

function M.StopSelf()
    local player = require("eryndor.player")
    if player.emote then
        M.Stop(player.view)
        player.emote, player.actionT, player.anim = nil, nil, nil
        if M.onPlay then M.onPlay(nil) end
    end
end

function M.Toggle() M.open = not M.open end

function M.HandleKeys()
    if not M.open then return false end
    for i = 1, #M.List do
        if input.pressed(tostring(i)) then M.Play(M.List[i].id); M.open = false; return true end
    end
    return false
end

-- nabídka emotů
function M.Draw(widgets)
    if not M.open then return end
    local sw, sh = ui.screen()
    local w, rowh = 300, 44
    local h = 70 + #M.List * rowh + 30
    local x, y = sw / 2 - w / 2, sh / 2 - h / 2
    ui.panel("UI/hud/panel_ornate_light.png", x, y, w, h, 28, 40)
    if widgets then widgets.Block(x, y, w, h) end
    ui.font("h2"); ui.text(x + w / 2, y + 16, "Emoty", { align = "center", color = "#d8b25a", shadow = true }); ui.pop_font()
    for i, e in ipairs(M.List) do
        if ui.button_at(x + 30, y + 60 + (i - 1) * rowh, w - 60, rowh - 8, i .. "   " .. e.name) then
            M.Play(e.id)
            M.open = false
        end
    end
    ui.font("small")
    ui.text(x + w / 2, y + h - 30, "[G] zavřít · pohyb emote ukončí", { align = "center", color = "#9a8f7c", shadow = true })
    ui.pop_font()
end

return M
