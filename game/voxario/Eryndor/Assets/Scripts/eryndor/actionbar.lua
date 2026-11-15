-- HUD Eryndoru podle „Technický blueprint: UI, Voda a Optimalizace“ (2A):
--   rámeček postavy vlevo nahoře (kované orámování, životy červeně, mana modře, plynulý úbytek – lerp + „stín“ ztráty),
--   akční lišta dole uprostřed: 12 slotů (1–0, -, =) s ikonou, klávesou a kruhovým zatměním doby obnovení.
local combat = require("eryndor.combat")
local player = require("eryndor.player")
local M = { shown = {}, ghost = {} }

local floor, max, min = math.floor, math.max, math.min
local GOLD, TEXT, DIM = "#d8b25a", "#efe6d2", "#a8a090"
M.Keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "Minus", "Equals" }
M.KeyLabel = { Minus = "-", Equals = "=" }

-- obsah slotů: 1–5 dovednosti povolání, 6–8 aktivní talenty, 9 / 0 lektvary, - útok, = cíl
function M.Slots()
    local s = combat.me
    local out = {}
    for k = 1, 12 do
        local sl = { key = M.Keys[k] }
        if k <= 8 then
            local sk = s and s.skills and s.skills[k]
            if sk then sl.kind, sl.i, sl.skill, sl.icon, sl.name = "skill", k, sk, sk.icon, sk.name
            else sl.kind, sl.icon, sl.name = "empty", "empty", k > 5 and "Aktivní talent (N)" or "" end
        elseif k == 9 then sl.kind, sl.icon, sl.name, sl.potion = "potion", "potion_hp", "Lektvar léčení", "hp"
        elseif k == 10 then sl.kind, sl.icon, sl.name, sl.potion = "potion", "potion_mp", "Lektvar many", "mp"
        elseif k == 11 then sl.kind, sl.icon, sl.name = "attack", "attack", "Automatický útok (R)"
        else sl.kind, sl.icon, sl.name = "target", "target", "Další cíl (Tab)" end
        out[k] = sl
    end
    return out
end

-- stisk klávesy / kliknutí na slot -> akce postavy (spustí i dobu obnovení)
function M.Activate(k)
    local sl = M.Slots()[k]
    if not sl then return end
    if sl.kind == "skill" then combat.UseSkill(sl.i)
    elseif sl.kind == "potion" then combat.UsePotion(sl.potion)
    elseif sl.kind == "attack" then combat.StartAttack()
    elseif sl.kind == "target" then combat.TabTarget() end
end

function M.HandleKeys()
    for k, key in ipairs(M.Keys) do
        if input.pressed(key) then M.Activate(k) end
    end
end

-- plynulá hodnota (lerp) a „stín“ ztráty, který dobíhá se zpožděním
local function smooth(id, value, dt)
    local cur = M.shown[id] or value
    cur = cur + (value - cur) * min(1, dt * 10)
    M.shown[id] = cur
    local g = M.ghost[id] or value
    if value >= g then g = value else g = max(value, g - dt * 0.35 * max(1, g)) end
    M.ghost[id] = g
    return cur, g
end

local function bar(x, y, w, h, frac, ghost, color, ghostColor, text)
    ui.rect(x, y, w, h, "#0a0806e8", 3)
    if ghost > frac then ui.rect(x + 1, y + 1, (w - 2) * ghost, h - 2, ghostColor, 2) end
    if frac > 0 then
        ui.rect(x + 1, y + 1, (w - 2) * frac, h - 2, color, 2)
        ui.rect(x + 1, y + 1, (w - 2) * frac, (h - 2) * 0.4, "#ffffff22", 2)   -- lesk
    end
    ui.rect(x, y, w, h, "#00000090", 3, false, 1.5)
    if text then
        ui.font("small")
        ui.text(x + w / 2, y + (h - 18) / 2 - 1, text, { align = "center", color = "#ffffff", shadow = true })
        ui.pop_font()
    end
end

local lastT
function M.UnitFrame(x, y, id, name, level, hp, maxhp, mp, maxmp, opts)
    opts = opts or {}
    local now = game.time()
    local dt = lastT and min(0.1, now - lastT) or 0.016
    local w, h = 360, mp and 104 or 84
    ui.panel("UI/hud/frame.png", x, y, w, h, 18, 22)
    -- portrét (kruh) s ikonou a úrovní
    ui.circle(x + 50, y + h / 2, 34, "#0a0806", true)
    if opts.icon then ui.draw_image("UI/icons/" .. opts.icon .. ".png", x + 26, y + h / 2 - 24, 48, 48) end
    ui.circle(x + 50, y + h / 2, 34, opts.hostile and "#a03020" or GOLD, false, 3)
    ui.circle(x + 78, y + h - 16, 13, "#0a0806", true)
    ui.circle(x + 78, y + h - 16, 13, opts.elite and "#ffd060" or GOLD, false, 2)
    ui.font("small"); ui.text(x + 78, y + h - 27, tostring(level), { align = "center", color = TEXT }); ui.pop_font()
    ui.font("body")
    ui.text(x + 96, y + 12, name .. (opts.elite and "  · Elita" or ""), { color = opts.hostile and "#ff9a80" or "#e8f0ff", shadow = true })
    ui.pop_font()
    local f, g = smooth(id .. "hp", hp / max(1, maxhp), dt)
    bar(x + 96, y + 42, 246, 20, f, g, opts.hostile and "#b02a1c" or "#c0282a", "#f0c06088", string.format("%d / %d", floor(hp), maxhp))
    if mp then
        local fm, gm = smooth(id .. "mp", mp / max(1, maxmp), dt)
        bar(x + 96, y + 66, 246, 16, fm, gm, "#2a5ad0", "#a0c0ff66", string.format("%d / %d", floor(mp), maxmp))
    end
    return w, h
end

-- portrét družiny (vpravo nahoře, jako na předloze): zlatý rám, ikona povolání / nepřítele, úroveň, pod ním
-- životy (červeně) a mana (modře)
function M.Portrait(x, y, id, name, level, hp, maxhp, mp, maxmp, opts)
    opts = opts or {}
    local now = game.time()
    local dt = lastT and min(0.1, now - lastT) or 0.016
    local size = opts.size or 84
    ui.rect(x + 6, y + 6, size - 12, size - 12, opts.hostile and "#2a0c0a" or "#0c1424", 2)
    if opts.icon then ui.draw_image("UI/icons/" .. opts.icon .. ".png", x + 8, y + 8, size - 16, size - 16) end
    ui.draw_image("UI/hud/portrait_frame.png", x, y, size, size, opts.hostile and { 1, 0.62, 0.55, 1 } or nil)
    ui.circle(x + size - 6, y + size - 6, 13, "#0a0806", true)
    ui.circle(x + size - 6, y + size - 6, 13, opts.elite and "#ffd060" or GOLD, false, 2)
    ui.font("small"); ui.text(x + size - 6, y + size - 17, tostring(level), { align = "center", color = TEXT }); ui.pop_font()
    local f, g = smooth(id .. "hp", hp / max(1, maxhp), dt)
    bar(x, y + size + 4, size, 9, f, g, "#c0282a", "#f0c06088")
    if mp then
        local fm, gm = smooth(id .. "mp", mp / max(1, maxmp), dt)
        bar(x, y + size + 15, size, 7, fm, gm, "#2a6ae0", "#a0c0ff66")
    end
    if opts.label then
        ui.font("small")
        ui.text(x - 10, y + size / 2 - 12, name, { align = "right", color = opts.hostile and "#ff9a80" or "#e8f0ff", shadow = true })
        ui.pop_font()
    end
    return size, size + (mp and 22 or 13)
end

function M.EndFrame() lastT = game.time() end

-- ------------------------------------------------------------------ akční lišta
local function tooltip(x, y, lines)
    local w = 300
    local h = 16 + #lines * 24
    ui.panel("UI/hud/frame_thin.png", x, y - h, w, h, 10, 14)
    ui.font("small")
    for i, l in ipairs(lines) do ui.text(x + 14, y - h + 8 + (i - 1) * 24, l[1], { color = l[2] or TEXT, wrap = w - 28 }) end
    ui.pop_font()
end

function M.ActionBar()
    local s = combat.me
    if not s then return end
    local sw, sh = ui.screen()
    local size, gap = 58, 6
    local n = 12
    local w = n * size + (n - 1) * gap + 18   -- mezera mezi dovednostmi a spotřebními předměty
    local x0, y0 = sw / 2 - w / 2, sh - 104
    ui.panel("UI/hud/panel_ornate.png", x0 - 20, y0 - 50, w + 40, size + 82, 32, 40)
    require("eryndor.widgets").Block(x0 - 20, y0 - 50, w + 40, size + 82)   -- kliknutí na lištu nevybírá cíl ve světě
    -- životy (vlevo, červeně) a mana (vpravo, modře) nad sloty, uprostřed erb Valorie
    local dt = lastT and min(0.1, game.time() - lastT) or 0.016
    local half = w / 2 - 38
    ui.panel("UI/hud/bar_frame.png", x0 - 2, y0 - 38, half + 4, 26, 10, 14)
    ui.panel("UI/hud/bar_frame.png", x0 + w - half - 2, y0 - 38, half + 4, 26, 10, 14)
    local f, g = smooth("barhp", s.hp / max(1, s.maxhp), dt)
    bar(x0 + 3, y0 - 33, half - 6, 16, f, g, "#c42a26", "#f0c06088", string.format("%d / %d", floor(s.hp), s.maxhp))
    local fm, gm = smooth("barmp", s.mp / max(1, s.maxmp), dt)
    bar(x0 + w - half + 3, y0 - 33, half - 6, 16, fm, gm, "#2a6ae0", "#a0c0ff66", string.format("%d / %d", floor(s.mp), s.maxmp))
    ui.draw_image("UI/hud/emblem.png", sw / 2 - 34, y0 - 60, 68, 68)
    -- zkušenosti pod lištou
    ui.bar(x0, y0 + size + 10, w, 6, s.xp / combat.XpNeed(s.level), "#8a5ad8")
    local now = game.time()
    local mx, my = ui.mouse()
    local hover
    for k, sl in ipairs(M.Slots()) do
        local x = x0 + (k - 1) * (size + gap)
        if k >= 9 then x = x + 18 end
        ui.draw_image("UI/hud/slot.png", x, y0, size, size)
        if sl.kind ~= "empty" then
            ui.draw_image("UI/icons/" .. sl.icon .. ".png", x + 3, y0 + 3, size - 6, size - 6)
        else
            ui.draw_image("UI/icons/empty.png", x + 3, y0 + 3, size - 6, size - 6, { 1, 1, 1, 0.35 })
        end
        local frac, left = 0, 0
        if sl.kind == "skill" then
            local sk = sl.skill
            left = (s.cd[sl.i] or 0) - now
            local total = (sk.cd or 0) * (1 - ((s.mods or {}).cdr or 0) / 100)
            if left > 0 and total > 0 then frac = left / total end
            local g = s.gcd - now
            if g > 0 and g / 1.0 > frac then frac = g / 1.0; if left <= 0 then left = 0 end end
            if s.mp < (sk.mp or 0) then ui.rect(x + 3, y0 + 3, size - 6, size - 6, "#1030b070", 4) end
        elseif sl.kind == "potion" then
            left = (s.potionCd or 0) - now
            if left > 0 then frac = left / combat.PotionCd end
        elseif sl.kind == "attack" and combat.auto then
            ui.rect(x + 2, y0 + 2, size - 4, size - 4, "#ff604080", 4, false, 3)
        end
        if frac > 0 then ui.cooldown(x + 3, y0 + 3, size - 6, size - 6, frac) end
        if left > 0.05 then
            ui.font("h2")
            ui.text(x + size / 2, y0 + size / 2 - 13, left > 9.5 and tostring(floor(left + 0.5)) or string.format("%.1f", left),
                { align = "center", color = "#ffffff", shadow = true })
            ui.pop_font()
        end
        ui.font("small")
        ui.text(x + 6, y0 + 3, M.KeyLabel[sl.key] or sl.key, { color = "#ffe8b0", shadow = true })
        ui.pop_font()
        if mx >= x and mx < x + size and my >= y0 and my < y0 + size then
            hover = { x = x, sl = sl }
            ui.rect(x, y0, size, size, "#ffffff22", 4)
            if input.pressed("Mouse1") then M.Activate(k) end
        end
    end
    if hover and hover.sl.kind ~= "empty" then
        local sl, lines = hover.sl, {}
        lines[#lines + 1] = { sl.name, GOLD }
        if sl.skill then
            local sk = sl.skill
            lines[#lines + 1] = { string.format("Mana %d · obnovení %d s%s", sk.mp or 0, floor((sk.cd or 0) * (1 - ((s.mods or {}).cdr or 0) / 100)),
                sk.cast and string.format(" · sesílání %.1f s", sk.cast) or "") }
            local d = {}
            if sk.mult then d[#d + 1] = string.format("poškození %d %%", floor(sk.mult * 100)) end
            if sk.aoe then d[#d + 1] = string.format("plocha %.0f m", sk.aoe) end
            if sk.heal then d[#d + 1] = string.format("léčí %d %% životů", floor(sk.heal * 100)) end
            if sk.stun then d[#d + 1] = string.format("omráčí %.1f s", sk.stun) end
            if sk.buff then d[#d + 1] = (sk.buff.def and ("+" .. sk.buff.def .. " obrana") or ("+" .. sk.buff.atk .. " útok")) .. " na " .. sk.buff.t .. " s" end
            if #d > 0 then lines[#lines + 1] = { table.concat(d, ", "), DIM } end
        elseif sl.kind == "potion" then
            lines[#lines + 1] = { (sl.potion == "hp" and "Obnoví 35 % životů" or "Obnoví 35 % many") .. ", obnovení 30 s", DIM }
        end
        tooltip(hover.x - 120, y0 - 24, lines)
    end
    -- ukazatel sesílání nad lištou
    if s.casting then
        local c = s.casting
        local f = min(1, (now - c.start) / (c.dur + (c.pushback or 0)))
        local sk = s.skills[c.i]
        ui.panel("UI/hud/frame_thin.png", sw / 2 - 190, y0 - 112, 380, 40, 10, 14)
        bar(sw / 2 - 176, y0 - 102, 352, 20, f, f, "#d8b25a", "#00000000", sk and sk.name)
    end
end

return M
