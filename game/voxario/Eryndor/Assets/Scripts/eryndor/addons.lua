-- Doplňky (addony) Eryndoru nad módy enginu (require("voxario.mods")): složka Dokumenty/Eryndor/AddOns,
-- každý doplněk = <složka>/mod.json + main.lua v sandboxu. Zapnutí / vypnutí se ukládá (settings) a projeví
-- se hned (doplňky se znovu načtou). API doplňku: tabulka `eryndor`
--   eryndor.on("update" | "draw" | "level_up" | "kill" | "enter_world", fn)
--   eryndor.notify(text [, "#rrggbb"]), eryndor.player() -> {name, level, hp, maxhp, mp, maxmp, x, y, z, swimming, oxygen}
--   ui.* (kreslení v "draw"), print(...)
local M = { open = false, list = {}, scroll = 0 }
local KEY = "eryndor.addons"

local function mods()
    local ok, m = pcall(require, "voxario.mods")
    return ok and m or nil
end

function M.Dir()
    local docs = fs and fs.documents and fs.documents()
    return docs and (docs .. "/Eryndor/AddOns") or nil
end

local function enabledMap()
    local s = settings and settings.get and settings.get(KEY)
    return type(s) == "table" and s or {}
end

-- ukázkový doplněk při prvním spuštění (souřadnice a FPS), ať je vidět, jak se píše
local EXAMPLE_JSON = [[{ "name": "Souřadnice a FPS", "version": "1.0", "author": "Eryndor", "description": "Ukázkový doplněk: vpravo nahoře ukazuje polohu postavy a FPS. Zkopíruj složku a uprav main.lua." }]]
local EXAMPLE_LUA = [[
-- Ukázkový doplněk Eryndoru: poloha a FPS pod minimapou
local fps, acc, n = 0, 0, 0
eryndor.on("update", function(dt)
  acc, n = acc + dt, n + 1
  if acc >= 0.5 then fps = n / acc; acc, n = 0, 0 end
end)
eryndor.on("draw", function()
  local p = eryndor.player()
  if not p then return end
  local sw = ui.screen()
  ui.text(sw - 20, 300, string.format("%.0f, %.0f, %.0f  ·  %.0f FPS", p.x, p.y, p.z, fps), { align = "right", color = "#c8e0ff", shadow = true })
end)
eryndor.notify("Doplněk Souřadnice a FPS je zapnutý.")
]]

-- verze ukázky do 0.13.0 měla ve formátu %d s desetinným FPS a hned po zapnutí padala ("number has no integer
-- representation") – neupravenou starou kopii hráčům tiše opraví
local function repairExample(dir)
    if not (fs and fs.read and fs.write and fs.exists) then return end
    local path = dir .. "/SouradniceFPS/main.lua"
    if not fs.exists(path) then return end
    local ok, text = pcall(fs.read, path)
    if not ok or type(text) ~= "string" then return end
    local broken = '"%.0f, %.0f, %.0f  ·  %d FPS"'
    local s, e = text:find(broken, 1, true)
    if s then
        fs.write(path, text:sub(1, s - 1) .. '"%.0f, %.0f, %.0f  ·  %.0f FPS"' .. text:sub(e + 1))
    end
end
M.RepairExample = repairExample

local function ensureExample(dir)
    if not (fs and fs.exists and fs.mkdir and fs.write) then return end
    repairExample(dir)
    if fs.exists(dir .. "/SouradniceFPS/mod.json") then return end
    if fs.exists(dir .. "/.example") then return end   -- hráč ukázku smazal
    fs.mkdir(dir)
    fs.mkdir(dir .. "/SouradniceFPS")
    fs.write(dir .. "/SouradniceFPS/mod.json", EXAMPLE_JSON)
    fs.write(dir .. "/SouradniceFPS/main.lua", EXAMPLE_LUA)
    fs.write(dir .. "/.example", "1")
end

-- api = funkce(info) -> tabulka pro doplněk (hra doplní hráče a oznámení)
function M.Setup(api)
    M.api = api
end

function M.Load()
    local m = mods()
    local dir = M.Dir()
    M.list = {}
    if not m or not dir then return end
    pcall(ensureExample, dir)
    m.clear()
    if M.api then m.expose("eryndor", M.api) end
    m.expose("ui", ui)   -- kreslení v události "draw"
    local en = enabledMap()
    for _, name in ipairs((fs.list and fs.list(dir)) or {}) do
        local root = dir .. "/" .. name
        if fs.is_dir(root) and fs.exists(root .. "/mod.json") then
            if en[name] == false then
                local info = { id = name, root = root, disabled = true, off = true }
                local text = fs.read(root .. "/mod.json")
                local ok, j = pcall(function() return json and json.decode(text) end)
                if ok and type(j) == "table" then for k, v in pairs(j) do info[k] = v end end
                M.list[#M.list + 1] = info
            else
                M.list[#M.list + 1] = m.load(root)
            end
        end
    end
    table.sort(M.list, function(a, b) return tostring(a.name or a.id) < tostring(b.name or b.id) end)
end

function M.Fire(event, ...)
    local m = mods()
    if m then m.fire(event, ...) end
end

function M.SetEnabled(id, on)
    local en = enabledMap()
    en[id] = on and true or false
    if settings and settings.set then settings.set(KEY, en) end
    M.Load()
end

function M.Toggle() M.open = not M.open end

function M.Draw(W)
    if not M.open then return end
    local sw, sh = ui.screen()
    local w, h = 820, 640
    local x, y = sw / 2 - w / 2, sh / 2 - h / 2
    ui.fade(0.45, "#000000")
    local ix, iy, iw, ih, closed = W.Window(x, y, w, h, "Doplňky", true)
    if closed then M.open = false end
    ui.font("small")
    ui.text(ix, iy, "Složka: " .. (M.Dir() or "?"), { color = W.DIM, wrap = iw })
    ui.pop_font()
    local rowH, ry = 96, iy + 34
    if #M.list == 0 then
        ui.font("body"); ui.text(ix, ry, "Žádné doplňky. Vlož složku s mod.json a main.lua do složky výše.", { color = W.TEXT, wrap = iw }); ui.pop_font()
    end
    for i, a in ipairs(M.list) do
        local yy = ry + (i - 1) * (rowH + 8)
        if yy + rowH > iy + ih - 50 then break end
        ui.rect(ix, yy, iw, rowH, "#1a140ccc", 6)
        ui.rect(ix, yy, iw, rowH, a.error and "#a03020" or (a.off and "#4a4030" or "#8a6a30"), 6, false, 1.5)
        ui.font("body")
        ui.text(ix + 16, yy + 10, tostring(a.name or a.id), { color = a.off and W.DIM or "#ffe8b0", shadow = true })
        ui.pop_font()
        ui.font("small")
        local meta = (a.version and ("v" .. a.version) or "") .. (a.author and ("  ·  " .. a.author) or "")
        ui.text(ix + iw - 190, yy + 12, meta, { color = W.DIM, align = "right" })
        local desc = a.error and ("Chyba: " .. tostring(a.error):sub(1, 140)) or (a.disabled and not a.off and "Vypnut kvůli chybám" or tostring(a.description or ""))
        ui.text(ix + 16, yy + 44, desc, { color = a.error and "#ff9a80" or W.TEXT, wrap = iw - 220 })
        ui.pop_font()
        local on = not a.off
        if W.Button(ix + iw - 170, yy + 24, 154, 48, on and "Zapnuto" or "Vypnuto", nil,
            { center = true, color = on and "#9fe0a0" or "#c0b0a0" }) then
            M.SetEnabled(a.id, not on)
            return
        end
    end
    if W.Button(ix, iy + ih - 44, 230, 50, "Znovu načíst", "m_addons") then M.Load() end
    if W.Button(ix + iw - 180, iy + ih - 44, 180, 50, "Zavřít", nil, { center = true }) then M.open = false end
end

return M
