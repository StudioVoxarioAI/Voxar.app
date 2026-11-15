-- HUD Eryndoru: rámeček hráče a cíle, lišta dovedností s cooldowny, ukazatel sesílání, čísla
-- poškození, záznam boje, sledování výpravy, výběr povolání a rozhovor s Lyrise.
local combat = require("eryndor.combat")
local player = require("eryndor.player")
local map = require("eryndor.map")
local M = {}

local floor, max, min = math.floor, math.max, math.min
local GOLD, DARK, TEXT, DIM = "#d8b25a", "#0d0f16e0", "#efe6d2", "#a8a090"

function M.Init()
    ui.load_font("title", "UI/Cinzel-SemiBold.ttf", 46, 56)
    ui.load_font("h1", "UI/Cinzel-SemiBold.ttf", 26, 32)
    ui.load_font("h2", "UI/Cinzel-SemiBold.ttf", 19, 24)
    ui.load_font("body", "UI/Cormorant-SemiBold.ttf", 21, 26)
    ui.load_font("small", "UI/Cormorant-Medium.ttf", 17, 20)
    ui.load_font("panel", "UI/Cormorant-SemiBold.ttf", 27, 33)   -- tvorba postavy
    ui.style({ window_bg = "#0d0f16e8", text = TEXT, button = "#2a2418", button_hover = "#4a3c22", button_active = "#6a5428",
               border = "#d8b25a80", rounding = 4, border_size = 1, padding = 10, font_size = 20 })
end

local function frame(x, y, w, h)
    ui.rect(x, y, w, h, DARK, 6)
    ui.rect(x, y, w, 2, GOLD, 0)
    ui.rect(x, y + h - 2, w, 2, "#d8b25a60", 0)
end

local function unitFrame(x, y, name, level, hp, maxhp, mp, maxmp, hostile, elite)
    frame(x, y, 330, mp and 92 or 74)
    -- kolečko úrovně
    ui.rect(x + 10, y + 12, 50, 50, hostile and "#5a1a1a" or "#1a3a4a", 25)
    ui.font("h2")
    ui.text(x + 35, y + 22, tostring(level), { align = "center", color = elite and "#ffd060" or TEXT })
    ui.pop_font()
    ui.font("body")
    ui.text(x + 72, y + 8, name .. (elite and "  · Elita" or ""), { color = hostile and "#ff9a80" or "#d8f0ff", shadow = true })
    ui.pop_font()
    ui.bar(x + 72, y + 36, 246, 18, min(1, hp / max(1, maxhp)), hostile and "#a02a1c" or "#3a9a3a",
        string.format("%d / %d", floor(hp), maxhp))
    if mp then ui.bar(x + 72, y + 58, 246, 14, min(1, mp / max(1, maxmp)), "#2a5ab8", string.format("%d / %d", floor(mp), maxmp)) end
end

-- ------------------------------------------------------------------ boj
function M.DrawGame()
    local s = combat.me
    if not s then return end
    local sw, sh = ui.screen()
    local ab = require("eryndor.actionbar")
    local name = (player.appearance and player.appearance.name ~= "" and player.appearance.name) or s.class.name
    -- portréty vpravo nahoře (předloha: družina pod sebou) – hráč, pod ním cíl
    local px0 = sw - 108
    local _, ph = ab.Portrait(px0, 18, "me", name, s.level, s.hp, s.maxhp, s.mp, s.maxmp,
        { icon = s.class.id .. "_1", label = true })
    M.portraitBottom = 18 + ph
    local talents = require("eryndor.talents")
    local free = talents.Points(s) - talents.Spent(s)
    if free > 0 then
        ui.font("small"); ui.text(sw - 20, M.portraitBottom + 4, free .. " volné body talentů – N", { align = "right", color = GOLD, shadow = true }); ui.pop_font()
        M.portraitBottom = M.portraitBottom + 24
    end
    -- buffy (vlevo od portrétu)
    local bx = px0 - 48
    for _, b in pairs(s.buffs) do
        local left = b.until_t - game.time()
        if left > 0 then
            ui.rect(bx, 84, 34, 34, "#0d0f16d0", 4)
            ui.rect(bx + 3, 87, 28, 28, b.color or "#888", 3)
            ui.rect(bx, 84, 34, 34, GOLD, 4, false, 1.5)
            ui.font("small"); ui.text(bx + 17, 120, tostring(floor(left)), { align = "center", color = TEXT }); ui.pop_font()
            bx = bx - 40
        end
    end
    -- cíl (druhý portrét)
    local t = combat.target
    if t and t.state ~= "dead" then
        local _, th = ab.Portrait(px0, M.portraitBottom + 14, "target", t.t.name, t.level, t.hp, t.maxhp, nil, nil,
            { hostile = true, elite = t.t.elite, icon = "target", label = true })
        if t.stunT and game.time() < t.stunT then
            ui.font("small"); ui.text(px0 - 10, M.portraitBottom + 50, "Omráčen", { align = "right", color = "#ffe080" }); ui.pop_font()
        end
        M.portraitBottom = M.portraitBottom + 14 + th
        -- značka nad cílem
        local p = entity.get_position(t.id)
        local x, y, vis = ui.world_to_screen(t.x, combat.MobY(t) + (t.t.labelY and t.t.labelY + 0.4 or (t.t.elite and 3.4 or 2.4)), t.z)
        if vis then
            ui.rect(x - 7, y - 7, 14, 14, combat.auto and "#ff5030" or "#ffd060", 7)
        end
    end
    -- jmenovky a životy nepřátel poblíž
    local px, _, pz = player.Pos()
    for _, m in ipairs(combat.mobs) do
        if m.state ~= "dead" and (m.x - px) ^ 2 + (m.z - pz) ^ 2 < 30 * 30 then
            local x, y, vis = ui.world_to_screen(m.x, combat.MobY(m) + (m.t.labelY or (m.t.elite and 3.0 or 2.0)), m.z)
            if vis then
                ui.font("small")
                ui.text(x, y - 26, m.t.name .. "  " .. m.level, { align = "center", color = m == t and "#ffe0a0" or "#ff9a80", shadow = true })
                ui.pop_font()
                ui.bar(x - 40, y - 6, 80, 6, m.hp / m.maxhp, "#c03020")
            end
        end
    end
    -- čísla poškození (stoupají a mizí)
    local now = game.time()
    for _, f in ipairs(combat.floats) do
        local age = now - f.t
        local x, y, vis = ui.world_to_screen(f.x + f.dx * age, f.y + age * 1.1, f.z)
        if vis then
            local a = max(0, 1 - age / 1.3)
            local c = f.color
            ui.font("h1", f.size)
            ui.text(x, y, f.text, { align = "center", color = { c[1], c[2], c[3], a }, shadow = true })
            ui.pop_font()
        end
    end
    -- akční lišta (12 slotů, kruhové zatmění doby obnovení) a ukazatel sesílání
    ab.ActionBar()
    -- kyslík (pod vodou): bublinky nad akční lištou
    if player.oxygen and player.oxygen < player.oxygenMax - 0.01 then
        local sw2, sh2 = ui.screen()
        local f = player.oxygen / player.oxygenMax
        local w, x, y = 300, sw2 / 2 - 150, sh2 - 176
        ui.panel("UI/hud/frame_thin.png", x - 12, y - 10, w + 24, 40, 10, 14)
        ui.rect(x, y, w, 20, "#0a0806e8", 3)
        if f > 0 then ui.rect(x + 1, y + 1, (w - 2) * f, 18, f > 0.25 and "#4ab8ff" or "#ff6a4a", 3) end
        for i = 0, 9 do
            local cx = x + 15 + i * 30
            if (i + 0.5) / 10 <= f then ui.circle(cx, y + 10, 6, "#e8f6ff", false, 1.5) end
        end
        ui.font("small")
        ui.text(x + w / 2, y - 2, f > 0 and string.format("Kyslík %d s", math.ceil(player.oxygen)) or "Topíš se!",
            { align = "center", color = "#ffffff", shadow = true })
        ui.pop_font()
    end
    ab.EndFrame()
    -- záznam boje (vlevo dole, průsvitný zdobený panel)
    if M.ShowLog ~= false then
        ui.panel("UI/hud/panel_ornate_light.png", 16, sh - 236, 430, 200, 28, 40)
        ui.font("small")
        for i, l in ipairs(combat.log) do
            local a = max(0.35, 1 - (now - l.t) / 25)
            ui.text(34, sh - 222 + (i - 1) * 22, l.text, { color = { l.color[1], l.color[2], l.color[3], a } })
        end
        ui.pop_font()
    end
    -- smrt
    if player.dead then
        ui.fade(0.45, "#000000")
        ui.font("title"); ui.text(sw / 2, sh / 2 - 60, "Padl jsi", { align = "center", color = "#e05040", shadow = true }); ui.pop_font()
        ui.font("body"); ui.text(sw / 2, sh / 2, "Ozvěna se za chvíli vrátí ke Zřídlu…", { align = "center", color = TEXT }); ui.pop_font()
    end
end

-- ------------------------------------------------------------------ výprava (sledování vpravo)
-- počet řádků textu zalomeného na šířku w (písmo „small“ ~ 8,6 px na znak)
local function wrapLines(text, w)
    local n = utf8 and utf8.len(text) or #text
    return math.max(1, math.ceil((n or #text) * 8.6 / math.max(w, 40)))
end

-- sledování úkolů (vpravo pod portréty, zdobený panel jako na předloze; X skryje, J znovu ukáže)
M.ShowTracker = true
function M.DrawQuest(q)
    if not q then return end
    local sw, sh = ui.screen()
    if input.pressed("J") then M.ShowTracker = not M.ShowTracker end
    if not M.ShowTracker then return end
    local w = 300
    local x, y = sw - w - 20, max(M.portraitBottom or 150, 150) + 24
    local lines = {}
    for _, l in ipairs(q.lines) do lines[#lines + 1] = l end
    local h = 76
    for _, l in ipairs(lines) do h = h + 8 + 22 * wrapLines("Cíl: " .. l.text, w - 80) end
    ui.panel("UI/hud/panel_ornate.png", x, y, w, h, 32, 40)
    require("eryndor.widgets").Block(x, y, w, h)
    ui.font("h2"); ui.text(x + w / 2, y + 16, "Sledování úkolů", { align = "center", color = "#f0dcaa", shadow = true }); ui.pop_font()
    ui.rect(x + 24, y + 46, w - 48, 1, "#d8b25a80", 0)
    -- zavřít
    local mx, my = ui.mouse()
    local cx, cy = x + w - 34, y + 14
    local hot = mx >= cx and mx < cx + 22 and my >= cy and my < cy + 22
    ui.rect(cx, cy, 22, 22, hot and "#7a2a1a" or "#3a1410", 3)
    ui.rect(cx, cy, 22, 22, GOLD, 3, false, 1)
    ui.font("small"); ui.text(cx + 11, cy + 1, "X", { align = "center", color = TEXT }); ui.pop_font()
    if hot and input.pressed("Mouse1") then M.ShowTracker = false end
    ui.font("body")
    ui.text(x + 26, y + 54, "• " .. q.title, { color = "#ffe8b0", shadow = true })
    ui.pop_font()
    ui.font("small")
    local yy = y + 84
    for _, l in ipairs(lines) do
        ui.text(x + 40, yy, "•", { color = l.done and "#80d080" or GOLD })
        ui.text(x + 58, yy, (l.done and "" or "Cíl: ") .. l.text, { color = l.done and "#80d080" or TEXT, wrap = w - 80 })
        yy = yy + 8 + 22 * wrapLines("Cíl: " .. l.text, w - 80)
    end
    ui.pop_font()
end

-- ------------------------------------------------------------------ výběr povolání
function M.DrawSelect(state)
    local sw, sh = ui.screen()
    ui.vignette(0.6)
    ui.font("title"); ui.text(sw / 2, 46, "ERYNDOR", { align = "center", color = GOLD, shadow = true }); ui.pop_font()
    ui.font("body"); ui.text(sw / 2, 108, "Velký Rozkol – testovací kanál", { align = "center", color = DIM }); ui.pop_font()
    local classes = combat.Classes
    local x = sw / 2 - (#classes * 300 + (#classes - 1) * 20) / 2
    for i, c in ipairs(classes) do
        local cx = x + (i - 1) * 320
        local sel = state.index == i
        ui.rect(cx, sh - 330, 300, 230, sel and "#2a2418f0" or "#0d0f16e0", 6)
        ui.rect(cx, sh - 330, 300, 3, c.faction == "Sylvaria" and "#3fc8c0" or "#c04030", 0)
        ui.font("small"); ui.text(cx + 150, sh - 318, c.faction == "Sylvaria" and "SYLVARIA · Společenství Půlměsíce" or "AETHELGARD · Řád Ocelového slunce",
            { align = "center", color = c.faction == "Sylvaria" and "#7fe0d8" or "#ff9a80" }); ui.pop_font()
        ui.font("h1"); ui.text(cx + 150, sh - 292, c.name, { align = "center", color = sel and GOLD or TEXT }); ui.pop_font()
        ui.font("small"); ui.text(cx + 16, sh - 250, c.desc, { wrap = 268, color = DIM }); ui.pop_font()
        if ui.button_at(cx + 60, sh - 150, 180, 38, sel and "Vybráno" or "Vybrat") then state.index = i; state.changed = true end
    end
    if ui.button_at(sw / 2 - 130, sh - 84, 260, 50, "Vstoupit do Eryndoru") then state.enter = true end
end

-- ------------------------------------------------------------------ rozhovor
function M.DrawDialog(d)
    if not d then return end
    local sw, sh = ui.screen()
    frame(sw / 2 - 380, sh - 420, 760, 250)
    ui.font("h1"); ui.text(sw / 2 - 360, sh - 408, d.who, { color = "#9fc8ff" }); ui.pop_font()
    ui.font("body"); ui.text(sw / 2 - 360, sh - 368, d.text, { wrap = 720, color = TEXT }); ui.pop_font()
    for i, o in ipairs(d.options) do
        if ui.button_at(sw / 2 - 360 + (i - 1) * 250, sh - 222, 240, 40, o.label) then o.fn() end
    end
end


-- ------------------------------------------------------------------ mapa světa Aethelgard
local MAP_IMG = "UI/aethelgard_map.jpg"
local REGION_LABELS = {
    { "verdant", "Verdant Canopy", "#c8f0a0" }, { "frost", "Frostfang Peaks", "#e8f4ff" },
    { "ignis", "Ignis Scar", "#ffb070" }, { "crystal", "Crystalarium", "#f0b0ff" },
}

local function playerArrow(cx, cy, size, yaw)
    local a = math.rad(yaw or 0)
    local fx, fy = math.sin(a), math.cos(a)          -- dopředu na mapě (+X vpravo, +Z dolů; sever nahoře)
    local rx, ry = -fy, fx
    ui.line(cx - fx * size * 0.5 + rx * size * 0.45, cy - fy * size * 0.5 + ry * size * 0.45, cx + fx * size, cy + fy * size, "#ffe070", 3)
    ui.line(cx - fx * size * 0.5 - rx * size * 0.45, cy - fy * size * 0.5 - ry * size * 0.45, cx + fx * size, cy + fy * size, "#ffe070", 3)
    ui.rect(cx - 4, cy - 4, 8, 8, "#fff6c0", 4)
end

-- minimapa vlevo nahoře (předloha): kulatý výřez mapy kolem hráče v kompasu se zlatým prstencem (N/E/S/W),
-- pod ní panel s názvem místa a aktuálním cílem
M.MinimapSize = 1.0   -- násobek velikosti (nastavení → Rozhraní)
local function locationName(px, pz)
    if map.Region(px, pz) == "a" then
        local q = require("eryndor.quest")
        if (px - (q.Aerin and q.Aerin.x or 0)) ^ 2 + (pz - (q.Aerin and q.Aerin.z or 0)) ^ 2 < 140 ^ 2 then return "Valorie Harbor" end
        return "Valorie"
    end
    return map.RegionName(px, pz)
end
M.LocationName = locationName

function M.DrawMinimap()
    local R = floor(118 * (M.MinimapSize or 1))
    local cx, cy = 24 + R, 20 + R
    local px, _, pz = player.Pos()
    local u, v = map.ToMap(px, pz)
    local span = 520 / map.Size          -- 520 m přes průměr mapy
    local r = R * 0.78
    ui.circle(cx, cy, r + 2, "#0a0e16", true)
    ui.draw_image_round(MAP_IMG, cx, cy, r, nil, u - span / 2, v - span / 2, u + span / 2, v + span / 2)
    -- body zájmu v dosahu (portály, kapitán Aerin, Lyrise)
    local q = require("eryndor.quest")
    local val = require("eryndor.valoria")
    local marks = { { val.CityPortal, "#6fd8ff" }, { val.OutpostPortal, "#6fd8ff" }, { map.Lyrise, "#9fc8ff" },
                    { q.Aerin, "#ffd890" } }
    for _, m in ipairs(marks) do
        if m[1] then
            local dx, dz = (m[1].x - px) / (span * map.Size) * 2 * r, (m[1].z - pz) / (span * map.Size) * 2 * r
            if dx * dx + dz * dz < (r - 8) ^ 2 then
                ui.circle(cx + dx, cy + dz, 5, m[2], true)
                ui.circle(cx + dx, cy + dz, 5, "#10141c", false, 1.5)
            end
        end
    end
    playerArrow(cx, cy, 10, player.facing)
    ui.draw_image("UI/hud/compass_ring.png", cx - R, cy - R, 2 * R, 2 * R)
    -- lokace a cíl
    local w = 2 * R + 40
    local x, y = cx - w / 2, cy + R + 6
    local goal = q.Tracker and q.Tracker()
    local line = goal and goal.lines[1] and goal.lines[1].text
    local nl = line and wrapLines(line, w - 70) or 0
    ui.panel("UI/hud/panel_ornate_light.png", x, y, w, 52 + nl * 22, 28, 40)
    ui.font("h2"); ui.text(cx, y + 12, locationName(px, pz), { align = "center", color = "#fff2d0", shadow = true }); ui.pop_font()
    if line then
        ui.font("small")
        ui.text(x + 18, y + 42, "Cíl:", { color = GOLD, shadow = true })
        ui.text(x + 52, y + 42, line, { color = TEXT, shadow = true, wrap = w - 64 })
        ui.pop_font()
    end
end

-- velká mapa celého světa (klávesa M)
function M.DrawWorldMap()
    local sw, sh = ui.screen()
    ui.rect(0, 0, sw, sh, "#05070cd8", 0)
    local size = math.floor(math.min(sw, sh) - 90)
    local x, y = math.floor((sw - size) / 2), 60
    ui.draw_image(MAP_IMG, x, y, size, size)
    ui.rect(x, y, size, 2, GOLD, 0); ui.rect(x, y + size - 2, size, 2, GOLD, 0)
    local function at(wx, wz) local u, v = map.ToMap(wx, wz); return x + u * size, y + v * size end
    ui.font("h1")
    ui.text(sw / 2, 14, "Aethelgard", { align = "center", color = GOLD, shadow = true })
    ui.pop_font()
    -- názvy regionů
    ui.font("h2")
    for _, r in ipairs(REGION_LABELS) do
        local d = map.Data.Regions[r[1]]
        local lx, ly = at(d.x, d.z)
        ui.text(lx, ly - 12, r[2], { align = "center", color = r[3], shadow = true })
    end
    ui.pop_font()
    ui.font("small")
    local labels = {
        { map.Data.River[math.floor(#map.Data.River * 0.55)], "Serpentine River", "#bfe8ff" },
        { { -3300, 3700 }, "Azure Ocean", "#a8d0ff" }, { { 3300, -3500 }, "Azure Ocean", "#a8d0ff" },
    }
    for _, l in ipairs(labels) do
        local lx, ly = at(l[1][1] or l[1].x, l[1][2] or l[1].z)
        ui.text(lx, ly, l[2], { align = "center", color = l[3], shadow = true })
    end
    -- cesty (tečky po ose) a obloukový most do Valorie
    local okRoads, roads = pcall(require, "eryndor.roads_data")
    if okRoads then
        for _, r in ipairs(roads) do
            local color = r.surface == "stone" and "#e8d9b0" or "#c9a46a"
            for _, seg in ipairs(r.segments) do
                for i = 1, #seg, 2 do
                    local rx, ry = at(seg[i][1], seg[i][2])
                    ui.rect(rx - 1, ry - 1, 3, 3, color, 1)
                end
            end
        end
    end
    local okSky, sky = pcall(require, "eryndor.skybridge_data")
    if okSky then
        for i = 1, #sky.points, 3 do
            local bx, by = at(sky.points[i][1], sky.points[i][2])
            ui.rect(bx - 1, by - 1, 3, 3, "#f0e6c8", 1)
        end
    end
    -- body zájmu
    local pois = { { map.Start, "Základna Serpentine" }, { { x = 3000, z = 2300 }, "Valoria" }, { map.Giant, "Tisíciletý strom" }, { map.Shrine, "Elfí svatyně" },
                   { map.Rift, "Stínová trhlina" }, { map.DragonLair, "Zamrzlé jezero" }, { map.SpiderNest, "Sopky" } }
    for _, p in ipairs(pois) do
        local lx, ly = at(p[1].x, p[1].z)
        ui.rect(lx - 4, ly - 4, 8, 8, "#d8b25a", 4)
        ui.text(lx + 8, ly - 10, p[2], { color = TEXT, shadow = true })
    end
    ui.pop_font()
    -- Abyssal Leviathan (živé polohy)
    local ok, world = pcall(require, "eryndor.world")
    if ok and world.Leviathans then
        for _, l in ipairs(world.Leviathans) do
            local lx, ly = at(l.x, l.z)
            ui.rect(lx - 6, ly - 6, 12, 12, "#3ff4ff", 6)
            ui.text(lx + 9, ly - 10, "Abyssal Leviathan", { color = "#9ff8ff", shadow = true })
        end
    end
    -- hráč
    local px, _, pz = player.Pos()
    local lx, ly = at(px, pz)
    playerArrow(lx, ly, 14, player.facing)
    ui.font("body")
    ui.text(sw / 2, y + size + 6, string.format("%s  ·  %.1f x %.1f km  ·  [M] zavřít", map.RegionName(px, pz),
        map.Size / 1000, map.Size / 1000), { align = "center", color = DIM, shadow = true })
    ui.pop_font()
end

return M
