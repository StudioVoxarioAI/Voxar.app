-- Okno postavy (klávesa C): výbava ve slotech kolem siluety (jako ve WoW / 4Story), vlastnosti postavy
-- a kovárna – vylepšení vybraného kusu (+0 až +15) rudami z Hornictví (items.UpgradeItem).
local items = require("eryndor.items")
local M = { open = false, sel = nil, result = nil }
local GOLD, TEXT, DIM = "#d8b25a", "#efe6d2", "#9a8f7c"

function M.Toggle() M.open = not M.open end

local LEFT = { "head", "shoulders", "chest", "hands" }
local RIGHT = { "legs", "feet", "main", "off" }
local EMPTY = { head = "g_plate_head", shoulders = "g_plate_shoulders", chest = "g_plate_chest", hands = "g_plate_hands",
                legs = "g_plate_legs", feet = "g_plate_feet", main = "g_sword_1h", off = "g_shield_kite" }

function M.Draw(widgets)
    if not M.open then return end
    local eq = require("eryndor.equipment")
    local inv = require("eryndor.inventory")
    local combat = require("eryndor.combat")
    local s = combat.me
    local sw, sh = ui.screen()
    local w, h = 860, 600
    local x, y = math.max(300, sw / 2 - w / 2 - 230), sh / 2 - h / 2 + 10
    ui.rect(x + 8, y + 8, w - 16, h - 16, "#0a0c11ee", 10)
    ui.panel("UI/hud/panel_ornate_light.png", x, y, w, h, 28, 40)
    if widgets then widgets.Block(x, y, w, h) end
    local p = require("eryndor.player")
    ui.font("h2"); ui.text(x + w / 2, y + 16, (p.appearance and p.appearance.name or "Postava") .. " · úroveň " .. (s and s.level or 1),
        { align = "center", color = GOLD, shadow = true }); ui.pop_font()
    local mx, my = ui.mouse()
    local size, gap = 68, 14
    local hover
    local function slotBox(slot, sx, sy)
        ui.draw_image("UI/hud/slot.png", sx, sy, size, size)
        local it = eq.slots[slot]
        if it then
            ui.draw_image("UI/icons/i_" .. items.Base[it.id].icon .. ".png", sx + 4, sy + 4, size - 8, size - 8)
            ui.rect(sx + 3, sy + 3, size - 6, 2, items.Color(it), 0); ui.rect(sx + 3, sy + size - 5, size - 6, 2, items.Color(it), 0)
            if (it.g.enh or 0) > 0 then ui.font("small"); ui.text(sx + 7, sy + 5, "+" .. it.g.enh, { color = "#ffe08a", shadow = true }); ui.pop_font() end
        else
            ui.draw_image("UI/icons/i_" .. EMPTY[slot] .. ".png", sx + 10, sy + 10, size - 20, size - 20, "#ffffff28")
        end
        if M.sel == slot then ui.rect(sx - 2, sy - 2, size + 4, size + 4, "#ffd86040", 6) end
        if mx >= sx and mx < sx + size and my >= sy and my < sy + size then
            hover = { slot = slot, it = it, x = sx, y = sy }
            if input.pressed("Mouse1") then M.sel = slot; M.result = nil end
            if input.pressed("Mouse2") and it then eq.Unequip(slot); if M.sel == slot then M.sel = nil end end
        end
    end
    local top = y + 70
    for i, slot in ipairs(LEFT) do slotBox(slot, x + 30, top + (i - 1) * (size + gap)) end
    for i, slot in ipairs(RIGHT) do slotBox(slot, x + 410, top + (i - 1) * (size + gap)) end
    -- střed: stav zbraní; jména slotů vedle ikon (vlevo za ikonou, vpravo před ikonou)
    ui.rect(x + 196, top, 138, 4 * (size + gap) - gap, "#00000055", 8)
    ui.font("small")
    for i, slot in ipairs(LEFT) do
        local it = eq.slots[slot]
        ui.text(x + 30 + size + 8, top + (i - 1) * (size + gap) + 8, items.SlotNames[slot], { color = DIM })
        if it then ui.text(x + 30 + size + 8, top + (i - 1) * (size + gap) + 30, "+" .. (it.g.enh or 0), { color = items.Color(it) }) end
    end
    for i, slot in ipairs(RIGHT) do
        local it = eq.slots[slot]
        ui.text(x + 410 - 8, top + (i - 1) * (size + gap) + 8, items.SlotNames[slot], { color = DIM, align = "right" })
        if it then ui.text(x + 410 - 8, top + (i - 1) * (size + gap) + 30, "+" .. (it.g.enh or 0), { color = items.Color(it), align = "right" }) end
    end
    ui.pop_font()
    ui.font("small")
    ui.text(x + 265, top + 2 * (size + gap) - 30, eq.drawn and "Tasené" or "Zasunuté", { align = "center", color = eq.drawn and "#ff9a6a" or "#9fd4ff" })
    ui.text(x + 265, top + 2 * (size + gap) - 8, "v boji se tasí", { align = "center", color = DIM })
    ui.pop_font()

    -- vlastnosti postavy
    local sx = x + 510
    ui.font("body"); ui.text(sx, top - 6, "Vlastnosti", { color = GOLD, shadow = true }); ui.pop_font()
    if s then
        local t = s.gear or eq.Totals()
        local st = combat.Stat
        local rows = {
            { "Životy", math.floor(s.maxhp), t.hp > 0 and ("+" .. t.hp .. " z výbavy") or "" },
            { "Útok", math.floor(st(s, "atk")), t.atk > 0 and ("+" .. t.atk) or (s.weaponKind and "" or "bez zbraně −40 %") },
            { "Obrana", math.floor(st(s, "def")), t.def > 0 and ("+" .. t.def) or "" },
            { "Magická síla", math.floor((s.class.matk or 0) + (t.matk or 0)), t.matk > 0 and ("+" .. t.matk) or "" },
            { "Kritický zásah", string.format("%.1f %%", 8 + ((s.mods or {}).crit or 0) + (t.crit or 0)), "" },
        }
        ui.font("small")
        for i, r in ipairs(rows) do
            local ry = top + 30 + (i - 1) * 30
            ui.text(sx, ry, r[1], { color = DIM })
            ui.text(sx + 160, ry, tostring(r[2]), { color = TEXT })
            ui.text(sx + 240, ry, r[3], { color = "#7fd36b" })
        end
        ui.pop_font()
    end

    -- kovárna: vylepšení vybraného kusu
    local fy = top + 200
    ui.font("body"); ui.text(sx, fy, "Kovárna – vylepšení", { color = GOLD, shadow = true }); ui.pop_font()
    local it = M.sel and eq.slots[M.sel]
    ui.font("small")
    if not it then
        ui.text(sx, fy + 34, "Klikni na kus výbavy vlevo.", { color = DIM, wrap = 300 })
    else
        local enh = it.g.enh or 0
        ui.text(sx, fy + 32, items.Name(it), { color = items.Color(it) })
        if enh >= items.MaxEnhancement then
            ui.text(sx, fy + 58, "Maximální vylepšení +15.", { color = "#ffe08a" })
        else
            local mat, need = items.UpgradeMaterial(enh + 1)
            local have = inv.Count(mat)
            local chance = items.UpgradeChance[enh + 1]
            ui.text(sx, fy + 58, string.format("+%d → +%d   šance %d %%", enh, enh + 1, math.floor(chance * 100 + 0.5)), { color = TEXT })
            ui.draw_image("UI/icons/i_" .. inv.Items[mat].icon .. ".png", sx, fy + 84, 34, 34)
            ui.text(sx + 42, fy + 92, string.format("%s  %d / %d", inv.Items[mat].name, have, need), { color = have >= need and "#7fd36b" or "#ff7a6a" })
            if enh >= 7 then ui.text(sx, fy + 126, "Při neúspěchu klesne o úroveň.", { color = "#ff9a6a" }) end
            if ui.button_at(sx, fy + 150, 200, 40, "Vylepšit") then
                local r = items.UpgradeItem(it, { id = mat, have = have })
                if r.used then inv.Remove(mat, r.used) end
                M.result = r
                local c = require("eryndor.combat")
                c.Log(r.msg, r.ok and { 0.6, 1.0, 0.6 } or { 1.0, 0.6, 0.5 })
                if r.used then
                    local px, py, pz = p.Pos()
                    _G.world.particles(px, py + 1.2, pz, { preset = r.ok and "holy" or "spark", burst = r.ok and 80 or 30, duration = 0.1, life = 1.0 })
                end
                eq.Changed()
            end
        end
        if M.result then ui.text(sx, fy + 200, M.result.msg, { color = M.result.ok and "#7fd36b" or "#ff9a6a", wrap = 300 }) end
    end
    ui.pop_font()
    ui.font("small")
    ui.text(x + w / 2, y + h - 34, "[C] zavřít · pravé tlačítko na slot = sundat · pravé tlačítko v tašce = vybavit", { align = "center", color = DIM })
    ui.pop_font()
    if hover and hover.it then inv.GearTooltip(hover.it, hover.x + size + 12, hover.y, false) end
end

return M
