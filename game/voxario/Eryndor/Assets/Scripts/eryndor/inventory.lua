-- Inventář (klávesa B): taška se 30 sloty, předměty se skládají na sebe. Nástroje profesí (krumpáč, stahovací nůž,
-- rybářský prut) dostane každá Ozvěna na začátku. Ukládá se do nastavení hry (settings, eryndor.inventory).
-- Pravé tlačítko na předmět = použít (prut nahodí udici, píšťalka přivolá koně, obojek mazlíčka).
local M = { open = false, slots = {}, size = 30 }

-- předměty: name, icon (UI/icons/i_*.png), stack, tool = nástroj profese, use = co dělá použití
M.Items = {
    pickaxe = { name = "Krumpáč", icon = "pickaxe", stack = 1, tool = "mining", desc = "Těžba rud (Hornictví)." },
    knife = { name = "Stahovací nůž", icon = "knife", stack = 1, tool = "skinning", desc = "Stahování kůží z ulovené zvěře." },
    rod = { name = "Rybářský prut", icon = "rod", stack = 1, tool = "fishing", use = "fish", desc = "Pravým tlačítkem nahodíš u vody (nebo klávesa E)." },
    horse = { name = "Píšťalka – Hnědák", icon = "horse", stack = 1, use = "mount", desc = "Přivolá koně (klávesa H). Dar kapitána Roderika." },
    wolf_pet = { name = "Obojek – Šedý vlk", icon = "wolf_pet", stack = 1, use = "pet", desc = "Přivolá / pošle domů vlka (klávesa K)." },
    ore_silver = { name = "Stříbrná ruda", icon = "ore_silver", stack = 50 },
    ore_gold = { name = "Zlatá ruda", icon = "ore_gold", stack = 50 },
    ore_diamond = { name = "Surový diamant", icon = "ore_diamond", stack = 50 },
    ore_mithril = { name = "Mitrilová ruda", icon = "ore_mithril", stack = 50 },
    herb_mirumilka = { name = "Mírumilka", icon = "herb_mirumilka", stack = 50 },
    herb_stribrolist = { name = "Stříbrolist", icon = "herb_stribrolist", stack = 50 },
    herb_krvavy_trn = { name = "Krvavý trn", icon = "herb_krvavy_trn", stack = 50 },
    herb_mesicni_lilie = { name = "Měsíční lilie", icon = "herb_mesicni_lilie", stack = 50 },
    herb_ledovy_kvet = { name = "Ledový květ", icon = "herb_ledovy_kvet", stack = 50 },
    hide_wolf = { name = "Vlčí kůže", icon = "hide_wolf", stack = 50 },
    hide_boar = { name = "Kančí kůže", icon = "hide_boar", stack = 50 },
    hide_stag = { name = "Jelení kůže", icon = "hide_stag", stack = 50 },
    hide_bear = { name = "Medvědí kožešina", icon = "hide_bear", stack = 50 },
    scale_dragon = { name = "Dračí šupina", icon = "scale_dragon", stack = 50 },
    fish_pstruh = { name = "Pstruh", icon = "fish_pstruh", stack = 30 },
    fish_okoun = { name = "Okoun", icon = "fish_okoun", stack = 30 },
    fish_losos = { name = "Losos", icon = "fish_losos", stack = 30 },
    fish_stika = { name = "Ledová štika", icon = "fish_stika", stack = 30 },
    fish_ohnivy = { name = "Ohnivý úhoř", icon = "fish_ohnivy", stack = 30 },
    fish_kapr = { name = "Měsíční kapr", icon = "fish_kapr", stack = 30 },
    feather_angel = { name = "Andělské pero", icon = "feather_angel", stack = 20, desc = "Trofej z pádu anděla." },
    horn_demon = { name = "Démonův roh", icon = "horn_demon", stack = 20, desc = "Trofej z pádu démona." },
    meteor_shard = { name = "Úlomek meteoru", icon = "meteor_shard", stack = 50 },
}

local KEY = "eryndor.inventory"

function M.Load()
    M.slots = {}
    local saved = settings and settings.get(KEY)
    if type(saved) == "table" then
        for i = 1, M.size do
            local s = saved[i] or saved[tostring(i)]
            if type(s) == "table" and M.Items[s.id] then M.slots[i] = { id = s.id, n = s.n or 1 }
            elseif type(s) == "table" and type(s.g) == "table" and require("eryndor.items").Base[s.id] then
                M.slots[i] = { id = s.id, n = 1, g = s.g }   -- výbava (vlastnosti, vzácnost, vylepšení)
            end
        end
    end
    -- výchozí nástroje (i do starších uložení)
    for _, id in ipairs({ "pickaxe", "knife", "rod" }) do
        if M.Count(id) == 0 then M.Add(id, 1, true) end
    end
end

function M.Save()
    if not settings then return end
    local out = {}
    for i = 1, M.size do
        local s = M.slots[i]
        out[i] = s and { id = s.id, n = s.n, g = s.g } or false
    end
    settings.set(KEY, out)
end

function M.Count(id)
    local n = 0
    for i = 1, M.size do
        local s = M.slots[i]
        if s and s.id == id then n = n + s.n end
    end
    return n
end
function M.Has(id) return M.Count(id) > 0 end

-- přidá n kusů; vrátí kolik se vešlo
function M.Add(id, n, quiet)
    local def = M.Items[id]
    if not def then return 0 end
    n = n or 1
    local left = n
    for i = 1, M.size do   -- nejdřív doplnit načaté
        local s = M.slots[i]
        if left > 0 and s and s.id == id and s.n < def.stack then
            local k = math.min(left, def.stack - s.n)
            s.n, left = s.n + k, left - k
        end
    end
    for i = 1, M.size do
        if left > 0 and not M.slots[i] then
            local k = math.min(left, def.stack)
            M.slots[i] = { id = id, n = k }
            left = left - k
        end
    end
    local added = n - left
    if added > 0 then
        M.Save()
        M.flash = { id = id, t = game.time() }
        if not quiet then
            local c = require("eryndor.combat")
            c.Log(string.format("Získáno: %s%s", def.name, added > 1 and (" x" .. added) or ""), { 0.6, 1.0, 0.6 })
        end
    end
    if left > 0 and not quiet then require("eryndor.combat").Log("Taška je plná!", { 1.0, 0.5, 0.4 }) end
    return added
end

-- výbava do prvního volného místa (nikdy se neskládá)
function M.PutGear(item)
    for i = 1, M.size do
        if not M.slots[i] then
            M.slots[i] = item
            M.Save()
            M.flash = { id = item.id, t = game.time() }
            return true
        end
    end
    return false
end
function M.Free()
    local n = 0
    for i = 1, M.size do if not M.slots[i] then n = n + 1 end end
    return n
end

function M.Remove(id, n)
    n = n or 1
    for i = M.size, 1, -1 do
        local s = M.slots[i]
        if n > 0 and s and s.id == id then
            local k = math.min(n, s.n)
            s.n, n = s.n - k, n - k
            if s.n <= 0 then M.slots[i] = nil end
        end
    end
    M.Save()
end

function M.Toggle() M.open = not M.open end

-- použití předmětu (pravé tlačítko): akce zaregistrují moduly (professions, mount, pet)
M.Actions = {}
function M.Use(id)
    local def = M.Items[id]
    local fn = def and def.use and M.Actions[def.use]
    if fn then fn() end
end

-- popisek výbavy (taška i okno postavy): jméno v barvě vzácnosti, slot, úroveň předmětu, vlastnosti, vylepšení
function M.GearTooltip(it, x, y, compare)
    local items = require("eryndor.items")
    local b = items.Base[it.id]
    local st = items.Stats(it)
    local lines = {}
    local NAMES = { atk = "Útok", def = "Obrana", matk = "Magická síla", hp = "Životy", crit = "Kritický zásah %" }
    for _, k in ipairs({ "atk", "matk", "def", "hp", "crit" }) do
        if st[k] then lines[#lines + 1] = { "+" .. st[k] .. " " .. NAMES[k], "#e8f0ff" } end
    end
    local slotName = items.SlotNames[b.slot] or ""
    local kind = b.armor and (b.armor == "plate" and "Plát" or "Kůže") or (b.kind and ({ twohand = "Obouruční", staff = "Obouruční",
        bow = "Obouruční", shield = "Štít", book = "Vedlejší ruka" })[b.kind] or "Jednoruční")
    local h = 112 + #lines * 24 + (compare and 26 or 0)
    local w = 340
    x = math.max(10, x)
    ui.rect(x, y, w, h, "#0b0d12f2", 6)
    ui.rect(x, y, w, 2, items.Color(it), 0)
    ui.font("body"); ui.text(x + 12, y + 8, items.Name(it), { color = items.Color(it), shadow = true }); ui.pop_font()
    ui.font("small")
    ui.text(x + 12, y + 38, items.Rarity[it.g.r].name .. " · " .. slotName .. " · " .. kind, { color = "#9a8f7c" })
    ui.text(x + w - 12, y + 38, "Úroveň předmětu " .. (it.g.il or 1), { color = "#d8b25a", align = "right" })
    for i, l in ipairs(lines) do ui.text(x + 12, y + 60 + (i - 1) * 24, l[1], { color = l[2] }) end
    ui.text(x + 12, y + 66 + #lines * 24, "Vylepšení +" .. (it.g.enh or 0) .. " / +" .. items.MaxEnhancement, { color = "#ffe08a" })
    if compare then ui.text(x + 12, y + 92 + #lines * 24, "Pravé tlačítko: vybavit", { color = "#7fd36b" }) end
    ui.pop_font()
end

-- ------------------------------------------------------------------ okno tašky
local GOLD, TEXT, DIM = "#d8b25a", "#efe6d2", "#9a8f7c"
function M.Draw(widgets)
    if not M.open then return end
    local sw, sh = ui.screen()
    local cols, s, gap = 6, 64, 8
    local rows = math.ceil(M.size / cols)
    local w = cols * s + (cols - 1) * gap + 48
    local h = rows * s + (rows - 1) * gap + 112
    local x, y = sw - w - 40, sh - h - 150
    ui.panel("UI/hud/panel_ornate_light.png", x, y, w, h, 28, 40)
    if widgets then widgets.Block(x, y, w, h) end
    ui.font("h2"); ui.text(x + w / 2, y + 16, "Taška", { align = "center", color = GOLD, shadow = true }); ui.pop_font()
    local mx, my = ui.mouse()
    local hover
    for i = 1, M.size do
        local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
        local sx, sy = x + 24 + c * (s + gap), y + 56 + r * (s + gap)
        ui.draw_image("UI/hud/slot.png", sx, sy, s, s)
        local it = M.slots[i]
        if it and it.g then   -- výbava: ikona, rámeček v barvě vzácnosti, +vylepšení
            local items = require("eryndor.items")
            local b = items.Base[it.id]
            ui.draw_image("UI/icons/i_" .. b.icon .. ".png", sx + 4, sy + 4, s - 8, s - 8)
            ui.rect(sx + 3, sy + 3, s - 6, 2, items.Color(it), 0); ui.rect(sx + 3, sy + s - 5, s - 6, 2, items.Color(it), 0)
            if (it.g.enh or 0) > 0 then
                ui.font("small"); ui.text(sx + 7, sy + 5, "+" .. it.g.enh, { color = "#ffe08a", shadow = true }); ui.pop_font()
            end
            if mx >= sx and mx < sx + s and my >= sy and my < sy + s then
                hover = { gear = it, x = sx, y = sy }
                ui.rect(sx, sy, s, s, "#ffffff22", 4)
                if input.pressed("Mouse2") then require("eryndor.equipment").Equip(i) end
            end
        elseif it then
            local def = M.Items[it.id]
            ui.draw_image("UI/icons/i_" .. def.icon .. ".png", sx + 4, sy + 4, s - 8, s - 8)
            if it.n > 1 then
                ui.font("small"); ui.text(sx + s - 6, sy + s - 22, tostring(it.n), { align = "right", color = "#ffffff", shadow = true }); ui.pop_font()
            end
            if M.flash and M.flash.id == it.id and game.time() - M.flash.t < 1.2 then
                ui.rect(sx, sy, s, s, "#fff2b040", 4)
            end
            if mx >= sx and mx < sx + s and my >= sy and my < sy + s then
                hover = { def = def, it = it, x = sx, y = sy }
                ui.rect(sx, sy, s, s, "#ffffff22", 4)
                if input.pressed("Mouse2") then M.Use(it.id) end
            end
        end
    end
    ui.font("small")
    ui.text(x + w / 2, y + h - 34, "[B] zavřít · pravé tlačítko = použít", { align = "center", color = DIM, shadow = true })
    ui.pop_font()
    if hover and hover.gear then
        M.GearTooltip(hover.gear, hover.x - 352, hover.y, true)
    elseif hover then
        local tw = 300
        local tx, ty = hover.x - tw - 12, hover.y
        ui.rect(tx, ty, tw, 76, "#0b0d12ee", 6)
        ui.rect(tx, ty, tw, 2, GOLD, 0)
        ui.font("body"); ui.text(tx + 12, ty + 8, hover.def.name, { color = TEXT, shadow = true }); ui.pop_font()
        ui.font("small")
        ui.text(tx + 12, ty + 38, hover.def.desc or (hover.def.tool and "Nástroj" or "Surovina profesí"), { color = DIM, wrap = tw - 24 })
        ui.pop_font()
    end
end

return M
