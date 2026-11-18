-- Hlasový chat (Nastavení → Zvuk: zapnout / vypnout, režim „stisknout V“ nebo „otevřený mikrofon“, hlasitost).
-- Mikrofon hráče (engine 1.31: audio.mic_*) se po 100 ms kóduje (8 kHz μ-law) a posílá kanálem Realtime
-- (eryndor.presence, zpráva „voice“); ostatní ho slyší prostorově u postavy mluvčího (audio.voice_open/push).
--
-- Pohyb úst: engine rozloží řeč na hlásky po 20 ms (viseme: tvar úst + otevření 0–9 – zavřené rty m/b/p, a, e, i,
-- o, u, f/v, sykavky s/z/c) a hra podle nich hýbe čelistí postavy: otevření (natočení kosti „jaw“), šířka úst
-- (široké e/i, úzké kulaté o/u – měřítko čelisti do stran) a vysunutí rtů (o, u). U vlastní postavy hned,
-- u ostatních synchronně se zvukem (stejné zpoždění jako zásobník přehrávání).
local M = { speaking = false, level = 0, lips = {} }

-- tvar úst -> {otevření čelisti při plné hlasitosti (°), šířka (měřítko X), vysunutí (m)}
M.Shapes = {
    X = { 0, 1.0, 0 }, M = { 0, 1.0, 0.002 }, A = { 14, 1.05, 0 }, E = { 8, 1.12, 0 }, I = { 5, 1.14, -0.002 },
    O = { 10, 0.86, 0.006 }, U = { 6, 0.8, 0.009 }, F = { 3, 1.03, -0.002 }, S = { 2, 1.08, 0 },
}
local DELAY = 0.12   -- zásobník přehrávání (960 vzorků při 8 kHz)

function M.Settings()
    local s = settings and settings.get("eryndor.voice") or {}
    if type(s) ~= "table" then s = {} end
    if s.enabled == nil then s.enabled = true end
    s.mode = s.mode or "ptt"
    s.volume = tonumber(s.volume) or 1.0
    return s
end
function M.SaveSettings(s) if settings then settings.set("eryndor.voice", s) end end

local function micOn()
    if M.mic then return true end
    if not (audio and audio.mic_start) then return false end
    local ok, name = audio.mic_start()
    M.mic = ok and true or false
    M.device = name
    if not ok and not M.warned then
        M.warned = true
        require("eryndor.combat").Log("Hlasový chat: mikrofon nenalezen.", { 1.0, 0.6, 0.5 })
    end
    return M.mic
end
local function micOff()
    if M.mic and audio and audio.mic_stop then audio.mic_stop() end
    M.mic = false
end

-- fronta hlásek pro entitu (vlastní i cizí postava)
local function queueVisemes(id, vis, startAt)
    if not id or type(vis) ~= "string" then return end
    local L = M.lips[id]
    if not L then L = { q = {}, t = startAt, open = 0, wide = 1, fwd = 0 }; M.lips[id] = L end
    local now = game.time()
    if not L.t or L.t < now then L.t = startAt end
    for i = 1, #vis - 1, 2 do
        local shape, open = vis:sub(i, i), tonumber(vis:sub(i + 1, i + 1)) or 0
        L.q[#L.q + 1] = { at = L.t, s = shape, o = open / 9 }
        L.t = L.t + 0.02
    end
end
M.Queue = queueVisemes

local function applyLips(dt)
    local now = game.time()
    for id, L in pairs(M.lips) do
        if not entity.exists(id) then M.lips[id] = nil
        else
            -- aktuální hláska (zahodit prošlé)
            local cur
            while L.q[1] and L.q[1].at <= now do cur = table.remove(L.q, 1) end
            if cur then L.cur = cur end
            if L.cur and now - L.cur.at > 0.08 then L.cur = nil end   -- ticho
            local sh = L.cur and M.Shapes[L.cur.s] or M.Shapes.X
            local amt = L.cur and L.cur.o or 0
            local tOpen, tWide, tFwd = sh[1] * (0.35 + 0.65 * amt), 1 + (sh[2] - 1) * math.min(1, amt * 1.5 + 0.3), sh[3]
            if not L.cur then tWide, tFwd = 1, 0 end
            -- plynulé přechody (rty se nehýbou skokem): otevírání rychleji než zavírání
            local k1 = 1 - math.exp(-(tOpen > L.open and 38 or 22) * dt)
            local k2 = 1 - math.exp(-20 * dt)
            L.open = L.open + (tOpen - L.open) * k1
            L.wide = L.wide + (tWide - L.wide) * k2
            L.fwd = L.fwd + (tFwd - L.fwd) * k2
            if L.open > 0.05 or math.abs(L.wide - 1) > 0.005 or L.active then
                entity.bone_rotate(id, "jaw", -L.open, 0, 0)   -- záporná X = brada dolů (ústa se otevřou)
                entity.bone_scale(id, "jaw", L.wide, 1, 1, false)
                L.active = L.open > 0.05 or math.abs(L.wide - 1) > 0.005
                if not L.active then entity.bone_rotate(id, "jaw"); entity.bone_scale(id, "jaw", 1, 1, 1, false) end
            end
        end
    end
end

-- příjem hlasu jiného hráče (eryndor.presence)
function M.Receive(o, chunk)
    local s = M.Settings()
    if not s.enabled or type(chunk) ~= "string" or #chunk > 4000 or not (audio and audio.voice_open) then return end
    local x, y, z = o.pos[1], require("eryndor.map").HeightAt(o.pos[1], o.pos[2]) + 1.6, o.pos[2]
    if not o.voice or not audio.playing(o.voice) then
        o.voice = audio.voice_open(x, y, z, { volume = s.volume, min_distance = 3, max_distance = 45 })
    end
    local vis = audio.voice_push(o.voice, chunk)
    queueVisemes(o.id, vis, game.time() + DELAY)
    o.talkT = game.time() + 0.4
end

local sendT = 0
function M.Update(dt, send)
    local s = M.Settings()
    local player = require("eryndor.player")
    local want = s.enabled and (s.mode == "open" or (input.key("V") and not ui.wants_keyboard()))
    if want and not M.mic then micOn() end
    if not s.enabled and M.mic then micOff() end
    M.speaking = false
    if M.mic and audio.mic_read then
        sendT = sendT - dt
        if sendT <= 0 then
            sendT = 0.1
            local chunk, level, vis = audio.mic_read()
            M.level = level or 0
            if want and chunk and #chunk > 0 and (M.level > 0.02) then
                M.speaking = true
                M.talkT = game.time() + 0.3
                queueVisemes(player.view, vis, game.time())
                if send then send(chunk) end
            end
        end
        -- mikrofon v režimu V se po puštění klávesy po chvíli vypne (ikonka mikrofonu v systému zhasne)
        if not want and s.mode == "ptt" and game.time() > (M.talkT or 0) + 3 then micOff() end
    end
    applyLips(dt)
end

-- ukazatel „mluvíš“ (vpravo nad akční lištou)
function M.DrawHud()
    local s = M.Settings()
    if not s.enabled then return end
    local sw, sh = ui.screen()
    local talking = game.time() < (M.talkT or 0)
    if talking or (s.mode == "ptt" and input.key("V")) then
        local x, y = sw / 2 + 260, sh - 214
        ui.circle(x, y, 14, talking and "#48d07a" or "#4a5a50", true)
        ui.rect(x - 3, y - 8, 6, 11, "#0b0d12", 3)
        ui.rect(x - 1, y + 4, 2, 5, "#0b0d12", 0)
        for i = 1, 4 do
            local hgt = 4 + math.min(1, (M.level or 0) * 3) * 14 * (0.6 + 0.4 * math.sin(game.time() * 18 + i))
            ui.rect(x + 18 + i * 6, y - hgt / 2, 4, hgt, talking and "#8ff0b0" or "#6a7a70", 1)
        end
    end
end

function M.Shutdown() micOff() end

return M
