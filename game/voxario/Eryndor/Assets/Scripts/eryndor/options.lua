-- Nastavení hry (Technický blueprint – 3. Optimalizace výkonu a Settings): grafické předvolby, kvalita stínů,
-- rozlišení textur, dohled, hustota trávy, ořez drobných předmětů, voda, mraky, DLSS / FSR s profilem, měřítko
-- vykreslování, limit FPS, VSync, režim okna. Ukládá se (settings.set) a použije se při startu hry.
local M = { open = false, tab = "graphics" }
local KEY = "eryndor.graphics"

local GOLD, TEXT, DIM = "#d8b25a", "#efe6d2", "#a8a090"

M.Presets = {
    { id = "low", name = "Nízké", shadows = "low", texture = 1, view = 0.6, detail = 0.25, water = 0, clouds = 0, cull = 70 },
    { id = "medium", name = "Střední", shadows = "medium", texture = 2, view = 0.85, detail = 0.55, water = 1, clouds = 1, cull = 100 },
    { id = "high", name = "Vysoké", shadows = "high", texture = 3, view = 1.0, detail = 0.8, water = 2, clouds = 2, cull = 140 },
    { id = "ultra", name = "Ultra", shadows = "ultra", texture = 3, view = 1.35, detail = 1.0, water = 3, clouds = 3, cull = 220 },
}
M.Shadows = { "off", "low", "medium", "high", "ultra" }
M.ShadowNames = { "Vypnuto", "Nízké", "Střední", "Vysoké", "Ultra" }
M.TextureNames = { "512 px", "1024 px", "2048 px", "Plné" }
M.Upscalers = { "off", "dlss", "fsr", "scale" }
M.UpscalerNames = { "Vypnuto (nativní)", "NVIDIA DLSS", "AMD FSR", "Vlastní měřítko" }
M.Profiles = { "quality", "balanced", "performance", "ultra_performance", "dlaa" }
M.ProfileNames = { "Quality", "Balanced", "Performance", "Ultra Performance", "DLAA" }
M.Modes = { "windowed", "borderless", "fullscreen" }
M.ModeNames = { "V okně", "Okno přes celou obrazovku", "Celá obrazovka" }

local function defaults()
    local p = M.Presets[3]
    return { preset = "high", shadows = p.shadows, texture = p.texture, view = p.view, detail = p.detail, water = p.water,
             clouds = p.clouds, cull = p.cull, upscaler = "off", profile = "quality", scale = 1.0, fps = 0, vsync = true,
             mode = "borderless", fov = 60, hud_minimap = 1.0, hud_tracker = true, hud_log = true }
end

function M.Load()
    local saved = settings and settings.get and settings.get(KEY)
    M.s = defaults()
    if type(saved) == "table" then for k, v in pairs(saved) do M.s[k] = v end end
    return M.s
end

function M.Save()
    if settings and settings.set then settings.set(KEY, M.s) end
end

local function call(fn, ...)
    if fn then pcall(fn, ...) end
end

-- použije nastavení na engine (konzolové příkazy enginu = graphics.*)
function M.Apply()
    local s = M.s
    local g = graphics or {}
    call(g.shadows, s.shadows)
    call(g.texture_quality, s.texture)
    call(g.view_distance, s.view)
    call(g.detail_density, s.detail)
    call(g.water_quality, s.water)
    call(g.clouds, s.clouds)
    call(g.object_cull, s.cull)
    call(g.upscaler, s.upscaler)
    if s.upscaler == "dlss" then call(g.dlss_quality, s.profile) end
    if s.upscaler == "fsr" or s.upscaler == "scale" then
        local k = ({ quality = 0.77, balanced = 0.67, performance = 0.5, ultra_performance = 0.4, dlaa = 1.0 })[s.profile] or 0.77
        call(g.render_scale, s.upscaler == "scale" and s.scale or k)
    elseif s.upscaler == "off" then
        call(g.render_scale, 1.0)
    end
    -- rozhraní (HUD podle předlohy Valorie Harbor)
    local okHud, hud = pcall(require, "eryndor.hud")
    if okHud and hud then
        hud.MinimapSize = s.hud_minimap or 1.0
        hud.ShowTracker = s.hud_tracker ~= false
        hud.ShowLog = s.hud_log ~= false
    end
    call(g.fps_limit, s.fps)
    call(g.vsync, s.vsync)
    if not game.selftest() then call(g.window_mode, s.mode) end
end

function M.SetPreset(id)
    for _, p in ipairs(M.Presets) do
        if p.id == id then
            for _, k in ipairs({ "shadows", "texture", "view", "detail", "water", "clouds", "cull" }) do M.s[k] = p[k] end
            M.s.preset = id
        end
    end
end

local function indexOf(list, v)
    for i, x in ipairs(list) do if x == v then return i end end
    return 1
end

function M.Toggle() M.open = not M.open end

function M.Draw()
    if not M.open then return end
    local s = M.s or M.Load()
    local sw, sh = ui.screen()
    local w, h = 760, 720
    local x, y = sw / 2 - w / 2, sh / 2 - h / 2
    ui.fade(0.4, "#000000")
    ui.panel("UI/hud/panel_ornate.png", x - 10, y - 10, w + 20, h + 20, 32, 40)
    local changed = false
    ui.window("Nastavení##eryndor", x + 14, y + 14, w - 28, h - 28, { title = false, move = false, resize = false, background = false,
        font = "panel", font_size = 26 }, function()
        ui.font("h2"); ui.label("Nastavení", GOLD); ui.pop_font()
        if ui.begin_tabs("##opt") then
            if ui.tab("Grafika") then
                ui.label("Předvolba", DIM)
                for i, p in ipairs(M.Presets) do
                    if i > 1 then ui.same_line() end
                    if ui.selectable(p.name .. "##p" .. i, s.preset == p.id) then M.SetPreset(p.id); changed = true end
                end
                ui.separator()
                local function combo(label, key, values, names)
                    ui.label(label, DIM)
                    ui.item_width(-1)
                    local i, ch = ui.combo("##" .. key, indexOf(values, s[key]), names)
                    if ch then s[key] = values[i]; s.preset = "custom"; changed = true end
                end
                local function slider(label, key, lo, hi, fmt)
                    ui.label(label, DIM)
                    ui.item_width(-1)
                    local v, ch = ui.slider("##" .. key, s[key], lo, hi, fmt or "%.2f")
                    if ch then s[key] = v; s.preset = "custom"; changed = true end
                end
                combo("Kvalita stínů", "shadows", M.Shadows, M.ShadowNames)
                combo("Rozlišení textur (po restartu oblasti)", "texture", { 0, 1, 2, 3 }, M.TextureNames)
                slider("Dohled", "view", 0.4, 1.6)
                slider("Hustota trávy a keřů", "detail", 0.0, 1.0)
                slider("Ořez drobných předmětů (m)", "cull", 40, 300, "%.0f m")
                combo("Kvalita vody", "water", { 0, 1, 2, 3 }, { "Nízká", "Střední", "Vysoká", "Ultra" })
                combo("Mraky", "clouds", { 0, 1, 2, 3 }, { "Vypnuto", "Nízké", "Střední", "Vysoké" })
                ui.end_tab()
            end
            if ui.tab("Výkon a obraz") then
                local function combo(label, key, values, names)
                    ui.label(label, DIM)
                    ui.item_width(-1)
                    local i, ch = ui.combo("##" .. key, indexOf(values, s[key]), names)
                    if ch then s[key] = values[i]; changed = true end
                end
                combo("Upscaling (AI / prostorový)", "upscaler", M.Upscalers, M.UpscalerNames)
                if s.upscaler == "dlss" or s.upscaler == "fsr" then combo("Profil", "profile", M.Profiles, M.ProfileNames) end
                if s.upscaler == "scale" then
                    ui.label("Měřítko vykreslování", DIM)
                    ui.item_width(-1)
                    local v, ch = ui.slider("##scale", s.scale, 0.5, 1.0, "%.2f")
                    if ch then s.scale = v; changed = true end
                end
                if s.upscaler == "dlss" and graphics and graphics.dlss then
                    local _, avail = graphics.dlss()
                    if not avail then ui.text_wrapped("DLSS není na této grafické kartě dostupné – použije se FSR.", "#ff9a80") end
                end
                ui.label("Limit FPS", DIM)
                ui.item_width(-1)
                local fi, fch = ui.combo("##fps", indexOf({ 0, 30, 60, 90, 120, 144, 165, 240 }, s.fps),
                    { "Bez limitu", "30", "60", "90", "120", "144", "165", "240" })
                if fch then s.fps = ({ 0, 30, 60, 90, 120, 144, 165, 240 })[fi]; changed = true end
                local v, vch = ui.checkbox("Vertikální synchronizace (VSync)", s.vsync)
                if vch then s.vsync = v; changed = true end
                combo("Režim okna", "mode", M.Modes, M.ModeNames)
                if graphics and graphics.info then
                    local gi = graphics.info()
                    ui.spacing()
                    ui.label(string.format("%s · %d FPS · %s · %d x %d", gi.gpu or "?", math.floor(gi.fps or 0), gi.upscaler or "",
                        gi.render_width or 0, gi.render_height or 0), DIM)
                end
                ui.end_tab()
            end
            if ui.tab("Rozhraní") then
                ui.label("Velikost minimapy (kompas vlevo nahoře)", DIM)
                ui.item_width(-1)
                local v, ch = ui.slider("##hud_minimap", s.hud_minimap or 1.0, 0.7, 1.4, "%.2f")
                if ch then s.hud_minimap = v; changed = true end
                local t1, c1 = ui.checkbox("Sledování úkolů vpravo (J)", s.hud_tracker ~= false)
                if c1 then s.hud_tracker = t1; changed = true end
                local t2, c2 = ui.checkbox("Záznam boje vlevo dole", s.hud_log ~= false)
                if c2 then s.hud_log = t2; changed = true end
                ui.end_tab()
            end
            if ui.tab("Ovládání") then
                ui.text_wrapped("WASD pohyb · Shift sprint · Ctrl chůze · Space skok · pravé tlačítko kamera · kolečko přiblížení\n" ..
                    "1–8 dovednosti a aktivní talenty · 9 / 0 lektvary · - automatický útok (R) · = další cíl (Tab)\n" ..
                    "N strom talentů · M mapa světa · J sledování úkolů · F mluvit · Esc menu / zrušit cíl", TEXT)
                ui.end_tab()
            end
            ui.end_tabs()
        end
        ui.spacing(); ui.separator()
        if ui.button("Zavřít", 160, 40) then M.open = false end
        ui.same_line()
        if ui.button("Výchozí", 160, 40) then M.s = defaults(); changed = true end
    end)
    if changed then M.Apply(); M.Save() end
end

return M
