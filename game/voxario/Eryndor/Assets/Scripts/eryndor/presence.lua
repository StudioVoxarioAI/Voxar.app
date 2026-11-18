-- Ostatní testeři v kanálu Fantasy (Supabase Realtime, veřejný kanál eryndor:fantasy:world).
-- Presence nese jméno, rasu a celý vzhled z tvorby postavy (kompaktně, barvy jako hex), povolání a úroveň;
-- broadcast „pos“ = poloha, rychlost a natočení (≈ 6× za s, jen při pohybu), „act“ = útok / kouzlo / skok.
-- Přihlášení z launcheru (lístek) dá stálé id účtu; bez něj má hra náhodné id uložené v nastavení.
local map = require("eryndor.map")
local races = require("eryndor.races")
local player = require("eryndor.player")
local combat = require("eryndor.combat")

local M = { others = {}, count = 0, joined = false }
M.Url = "https://rioexuvgvmdwvidfakxy.supabase.co"
M.Key = "sb_publishable_s0KxdrY9Wm7_j2mtI-PnJg_eYbQln9-"
M.Topic = "eryndor:fantasy:world"

local channel, uid, appearance
local lastSent, lastVel, lastSendTime, sendAt, retrackAt = { 0, 0 }, { 0, 0 }, 0, 0, 0

local function r2(v) return math.floor(v * 100 + 0.5) / 100 end
local function ground(x, z) return map.HeightAt(x, z) end

local function localId()
    local id = settings.get("eryndor.uid", "")
    if id == "" then
        id = string.format("p-%08x%04x", math.floor(math.random() * 0xffffffff), math.floor(math.random() * 0xffff))
        settings.set("eryndor.uid", id)
    end
    local role = game.env and game.env("VOXARIO_MP_ROLE")   -- samotest: dvě instance na jednom počítači
    return role and (id .. "-" .. role) or id
end

local function track()
    if not M.joined then return end
    local x, _, z = player.Pos()
    local c = player.class or {}
    channel:track({ uid = uid, name = appearance.name, race = appearance.race, cls = c.id or "knight",
                    level = combat.me and combat.me.level or 1, a = races.Pack(appearance),
                    x = r2(x), z = r2(z), ry = r2(player.facing or 0) })
end

local function leave(key)
    local o = M.others[key]
    if not o then return end
    if o.id then entity.destroy(o.id) end
    for _, w in ipairs(o.items or {}) do entity.destroy(w) end
    if o.horse then entity.destroy(o.horse) end
    if o.saddle then entity.destroy(o.saddle) end
    if o.voice and audio then audio.stop(o.voice) end
    M.others[key] = nil
    M.count = M.count - 1
end

local function classById(id)
    for _, c in ipairs(combat.Classes) do if c.id == id then return c end end
    return combat.Classes[1]
end

local function join(key, metas)
    if key == uid then return end
    local meta = metas and metas[#metas]
    if type(meta) ~= "table" or type(meta.a) ~= "table" then return end
    local a = races.Unpack(meta.a)
    if a.name == "" then a.name = "Ozvěna" end
    local c = classById(meta.cls)
    local o = M.others[key]
    local sig = json and json.encode and json.encode(meta.a) or tostring(meta.a)
    if o then
        o.level = tonumber(meta.level) or o.level
        if o.sig == sig then return end   -- vzhled beze změny
        leave(key)
    end
    local x, z = tonumber(meta.x) or map.Start.x, tonumber(meta.z) or map.Start.z
    o = { a = a, name = a.name, race = a.race, cls = c, level = tonumber(meta.level) or 1, sig = sig, height = a.height,
          pos = { x, z }, target = { x, z }, vel = { 0, 0 }, stamp = game.time(), yaw = tonumber(meta.ry) or 0,
          ry = tonumber(meta.ry) or 0 }
    o.id, o.items, o.weapons = races.Spawn(a, x, ground(x, z), z, { yaw = o.yaw, name = a.name, tag = "other_player",
                                                        right = c.look.right, left = c.look.left })
    o.anim = nil
    M.others[key] = o
    M.count = M.count + 1
    combat.Log(a.name .. " (" .. races.Defs[a.race].name .. ") je v Aethelgardu.", { 0.6, 0.85, 1.0 })
end

local function play(o, clip, loop)
    clip = player.Clip(clip, o.cls, o.a)
    if o.anim == clip then return end
    o.anim = clip
    anim.play(o.id, clip, 0.15, loop ~= false)
end

function M.Start(a)
    M.Stop()
    if not realtime or not realtime.channel then return end
    appearance = a
    net.configure(M.Url, M.Key)
    local function open()
        local s = net.session and net.session()
        uid = (s and s.user_id) or localId()
        channel = realtime.channel(M.Topic, { private = false, presence_key = uid, self = false })
        channel:on("presence", function(kind, data)
            if kind == "sync" then
                for key, metas in pairs(data) do join(key, metas) end
                for key in pairs(M.others) do if not data[key] then leave(key) end end
            elseif kind == "join" then join(data.key, data.metas)
            elseif kind == "leave" then
                local o = M.others[data.key]
                if o then combat.Log(o.name .. " odešel(a).", { 0.6, 0.6, 0.7 }) end
                leave(data.key)
            end
        end)
        channel:on("broadcast", "pos", function(p)
            local o = p.uid and p.uid ~= uid and M.others[p.uid]
            if not o then return end
            local x, z = tonumber(p.x), tonumber(p.z)
            if not x or not z or math.abs(x) > 5000 or math.abs(z) > 5000 then return end
            o.target = { x, z }
            o.vel = { tonumber(p.vx) or 0, tonumber(p.vz) or 0 }
            if o.vel[1] ^ 2 + o.vel[2] ^ 2 > 400 then o.vel = { 0, 0 } end
            o.stamp = game.time()
            o.ry = tonumber(p.ry) or o.ry
        end)
        channel:on("broadcast", "act", function(p)
            local o = p.uid and M.others[p.uid]
            if not o or type(p.clip) ~= "string" or #p.clip > 48 then return end
            o.anim = p.clip
            o.actionT = game.time() + math.min(tonumber(p.dur) or 0.8, 3)
            anim.play(o.id, p.clip, 0.08, false, true)
        end)
        -- emoty, hlas a jízda na koni ostatních hráčů
        channel:on("broadcast", "emote", function(p)
            local o = p.uid and M.others[p.uid]
            if not o then return end
            local em = require("eryndor.emotes")
            if type(p.e) == "string" and #p.e < 16 then
                em.Start(o.id, p.e, o.weapons); o.emote = p.e
            else
                em.Stop(o.id); o.emote = nil; o.anim = nil
            end
        end)
        channel:on("broadcast", "voice", function(p)
            local o = p.uid and M.others[p.uid]
            if o and type(p.c) == "string" then require("eryndor.voice").Receive(o, p.c) end
        end)
        channel:on("broadcast", "mount", function(p)
            local o = p.uid and M.others[p.uid]
            if not o then return end
            if p.on and not o.horse then
                o.horse = _G.world.spawn("Models/fauna/horse.glb", o.pos[1], ground(o.pos[1], o.pos[2]), o.pos[2],
                    { yaw = o.yaw, name = "Kůň", lod = "auto", lod_distance = 35 })
                o.saddle = _G.world.spawn("Models/prof/saddle.glb", o.pos[1], 0, o.pos[2], { name = "Sedlo" })
                anim.play(o.id, "Sit_Chair_Idle", 0.2, true)
                o.anim = "Sit_Chair_Idle"
                entity.bone_rotate(o.id, "thigh_l", 0, 0, -24); entity.bone_rotate(o.id, "thigh_r", 0, 0, 24)
                entity.bone_rotate(o.id, "calf_l", 28, 0, 0); entity.bone_rotate(o.id, "calf_r", 28, 0, 0)
            elseif not p.on and o.horse then
                entity.destroy(o.horse); entity.destroy(o.saddle)
                o.horse, o.saddle, o.anim = nil, nil, nil
                for _, b in ipairs({ "thigh_l", "thigh_r", "calf_l", "calf_r", "spine_01" }) do entity.bone_rotate(o.id, b) end
            end
        end)
        channel:subscribe(function(status)
            M.joined = status == "subscribed"
            M.status = status
            if M.joined then track() end
        end)
    end
    -- lístek z launcheru -> id účtu StudioVoxario (jinak místní id)
    if net.launcher_ticket and net.launcher_ticket() and not (net.session and net.session()) then
        net.sign_in_ticket(function() open() end)
    else
        open()
    end
    -- akce vlastní postavy (útoky, kouzla, skok) uvidí i ostatní
    player.onAction = function(clip, dur)
        if M.joined then channel:send("act", { uid = uid, clip = clip, dur = r2(dur or 0.8) }) end
    end
end

-- zpráva ostatním (emote, voice, mount)
function M.Send(event, payload)
    if not (M.joined and channel) then return end
    payload = payload or {}
    payload.uid = uid
    channel:send(event, payload)
end

function M.Stop()
    if channel then channel:leave() end
    channel, M.joined = nil, false
    for key in pairs(M.others) do leave(key) end
    player.onAction = nil
end

-- vzhled se změnil (např. nová postava) -> nová presence
function M.Retrack(a) appearance = a or appearance; track() end

function M.Update(dt)
    if not channel then return end
    local now = game.time()
    if M.joined and player.body and now > sendAt then
        sendAt = now + 0.16
        local x, _, z = player.Pos()
        local since = now - lastSendTime
        local vx, vz = player.vx or 0, player.vz or 0
        local moved = (x - lastSent[1]) ^ 2 + (z - lastSent[2]) ^ 2 > 0.0025
        local turned = (vx - lastVel[1]) ^ 2 + (vz - lastVel[2]) ^ 2 > 0.8
        local stopped = not moved and (lastVel[1] ^ 2 + lastVel[2] ^ 2) > 0.01
        if (moved and (turned or since > 0.33)) or stopped or since > 5 then
            if stopped then vx, vz = 0, 0 end
            lastSent, lastVel, lastSendTime = { x, z }, { vx, vz }, now
            channel:send("pos", { uid = uid, x = r2(x), z = r2(z), vx = r2(vx), vz = r2(vz), ry = r2(player.facing or 0) })
        end
        -- presence s polohou a úrovní občas obnovit (nově příchozí hráč uvidí postavu na správném místě)
        if now > retrackAt then retrackAt = now + 20; track() end
    end
    for _, o in pairs(M.others) do
        local age = math.min(now - o.stamp, 0.6)
        local px, pz = o.target[1] + o.vel[1] * age, o.target[2] + o.vel[2] * age
        local k = 1 - math.exp(-10 * dt)
        local ox, oz = o.pos[1], o.pos[2]
        if (px - ox) ^ 2 + (pz - oz) ^ 2 > 900 then o.pos = { px, pz } end   -- teleport
        o.pos[1], o.pos[2] = o.pos[1] + (px - o.pos[1]) * k, o.pos[2] + (pz - o.pos[2]) * k
        local spd = dt > 0 and math.sqrt((o.pos[1] - ox) ^ 2 + (o.pos[2] - oz) ^ 2) / dt or 0
        o.yaw = o.yaw + ((o.ry - o.yaw + 540) % 360 - 180) * k
        if o.voice and audio then audio.set_position(o.voice, o.pos[1], ground(o.pos[1], o.pos[2]) + 1.6, o.pos[2]) end
        if o.horse then   -- jede na koni: kůň nese postavu
            require("eryndor.mount").PoseEntities(o.horse, o.saddle, o.id, o.pos[1], ground(o.pos[1], o.pos[2]), o.pos[2], o.yaw, spd, o, dt)
            goto continue
        end
        if o.emote and spd > 0.6 then require("eryndor.emotes").Stop(o.id); o.emote = nil end
        entity.set_position(o.id, o.pos[1], ground(o.pos[1], o.pos[2]), o.pos[2])
        entity.set_rotation(o.id, 0, o.yaw, 0)
        if o.emote then
            -- tančí / sedí (eryndor.emotes)
        elseif o.actionT and now < o.actionT then
            -- probíhá akce
        else
            o.actionT = nil
            local ref
            if spd > 7.4 then play(o, "Running_B"); ref = player.ClipSpeed.sprint
            elseif spd > 3.2 then play(o, "Running_A"); ref = player.ClipSpeed.run
            elseif spd > 0.4 then play(o, "Walking_A"); ref = player.ClipSpeed.walk
            else play(o, "Idle") end
            anim.speed(o.id, ref and math.max(0.5, math.min(2.2, spd / (ref * (o.height or 1)))) or 1)
        end
        ::continue::
    end
end

-- jmenovky ostatních hráčů
function M.DrawLabels()
    for _, o in pairs(M.others) do
        local y = ground(o.pos[1], o.pos[2]) + 2.15
        if o.horse then y = y + 1.1 end
        local talking = o.talkT and game.time() < o.talkT
        ui.world_label(o.pos[1], y, o.pos[2], (talking and "(( " or "") .. o.name .. (talking and " ))" or ""), { size = 19, color = talking and "#8ff0b0" or "#bfe6ff", max_distance = 45 })
        ui.world_label(o.pos[1], y - 0.27, o.pos[2], "úroveň " .. tostring(o.level) .. " · " .. races.Defs[o.race].name .. " · " .. o.cls.name,
            { size = 15, color = "#d8c8a0", max_distance = 25 })
    end
    if channel then
        local sw = ui.screen()
        ui.font("small")
        ui.text(sw / 2, 8, (M.joined and ("Online · testerů v Aethelgardu: " .. (M.count + 1)) or "Připojování…"),
            { align = "center", color = M.joined and "#9fe0a0" or "#a8a090", shadow = true })
        ui.pop_font()
    end
end

return M
