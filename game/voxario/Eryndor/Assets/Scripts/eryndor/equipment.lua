-- Vybavení postavy (okno postavy: klávesa C). Sloty hlava, ramena, hruď, ruce, nohy, chodidla, hlavní a vedlejší ruka.
-- Nová postava začíná BEZ zbraní a bez zbroje – jen v základním oděvu rasy; výbavu sbírá (kořist z nepřátel, E).
--
-- Vzhled se mění podle výbavy:
--   * zbroj: kus z Armor Forge na míru rase (Models/armor/<sada>_<slot>_<rasa>.glb) se oblékne entity.equip –
--     kosti kusu kopírují pózu postavy (ohýbá se se všemi animacemi); vzácnost přebarví lemy (epické záře),
--   * zbraně: úchyty handslot.r / handslot.l (rukojeť v počátku, čepel po +Y – fit_prop / eryndor_weapons);
--     MIMO BOJ jsou zbraně zasunuté (záda / bok / stehno) a postava má volné ruce, V BOJI je tasí do rukou,
--   * animace: sada podle druhu zbraně v ruce (Motion Forge weapon_sets.py: _1H, _1HS, _2H, _DW, _ST, _BOW),
--     útoky podle zbraně (pěsti bez zbraně, švihy obouruční zbraní, dvě zbraně…).
local items = require("eryndor.items")
local M = { slots = {}, open = false, drawn = false, visuals = {} }
local floor, max, min = math.floor, math.max, math.min

local KEY = "eryndor.equipment"

-- ------------------------------------------------------------------ ukládání
function M.Load()
    M.slots = {}
    local s = settings and settings.get(KEY)
    if type(s) == "table" then
        for _, slot in ipairs(items.Slots) do
            local it = s[slot]
            if type(it) == "table" and items.Base[it.id] and type(it.g) == "table" then M.slots[slot] = { id = it.id, n = 1, g = it.g } end
        end
    end
end
function M.Save()
    if not settings then return end
    local out = {}
    for _, slot in ipairs(items.Slots) do out[slot] = M.slots[slot] or false end
    settings.set(KEY, out)
end

-- ------------------------------------------------------------------ pravidla nošení
local function classId()
    local c = require("eryndor.combat").me
    return c and c.class and c.class.id or "knight"
end

function M.CanEquip(item)
    local b = items.Base[item.id]
    if not b then return false, "Neznámý předmět." end
    local rules = items.ClassRules[classId()] or items.ClassRules.knight
    if b.armor == "plate" and not rules.plate then return false, "Plátovou zbroj tvé povolání nosit nemůže." end
    local k = b.kind and items.Kinds[b.kind]
    if k and b.kind == "shield" and not rules.shield then return false, "Štít tvé povolání nosit nemůže." end
    return true
end

-- kam předmět patří (u jednoruční zbraně do vedlejší ruky, když je hlavní obsazená a povolání smí dvě zbraně)
local function targetSlot(item, prefer)
    local b = items.Base[item.id]
    if b.slot ~= "main" then return b.slot end
    local k = items.Kinds[b.kind]
    if prefer == "off" and k.hand == "either" then return "off" end
    if k.hand == "either" and M.slots.main and items.Kinds[items.Base[M.slots.main.id].kind].hand == "either" and not M.slots.off then
        local rules = items.ClassRules[classId()] or {}
        if rules.dual then return "off" end
    end
    return "main"
end

-- ------------------------------------------------------------------ vybavení z tašky / svlečení do tašky
function M.Equip(bagIndex, prefer)
    local inv = require("eryndor.inventory")
    local c = require("eryndor.combat")
    local item = inv.slots[bagIndex]
    if not item or not item.g then return false end
    local ok, why = M.CanEquip(item)
    if not ok then c.Log(why, { 1, 0.5, 0.4 }); return false end
    local slot = targetSlot(item, prefer)
    local b = items.Base[item.id]
    local back = {}
    inv.slots[bagIndex] = nil
    if M.slots[slot] then back[#back + 1] = M.slots[slot] end
    M.slots[slot] = item
    -- obouruční zbraň uvolní vedlejší ruku; štít / kniha / zbraň do vedlejší ruky sundá obouruční zbraň
    if slot == "main" and items.Kinds[b.kind].hand == "two" and M.slots.off then back[#back + 1] = M.slots.off; M.slots.off = nil end
    if slot == "off" and M.slots.main and items.Kinds[items.Base[M.slots.main.id].kind].hand == "two" then
        back[#back + 1] = M.slots.main; M.slots.main = nil
    end
    for _, it in ipairs(back) do inv.PutGear(it) end
    c.Log("Vybaveno: " .. items.Name(item), { 0.75, 0.9, 1.0 })
    M.Changed()
    return true
end

function M.Unequip(slot)
    local inv = require("eryndor.inventory")
    local it = M.slots[slot]
    if not it then return end
    if not inv.PutGear(it) then require("eryndor.combat").Log("Taška je plná.", { 1, 0.5, 0.4 }); return end
    M.slots[slot] = nil
    M.Changed()
end

-- ------------------------------------------------------------------ vlastnosti postavy
function M.Totals()
    local t = { atk = 0, def = 0, matk = 0, hp = 0, crit = 0 }
    for _, slot in ipairs(items.Slots) do
        local it = M.slots[slot]
        if it then for k, v in pairs(items.Stats(it)) do t[k] = (t[k] or 0) + v end end
    end
    return t
end

-- promítne výbavu do statů boje (combat.Stat čte s.gear) a životů
function M.Recalc()
    local c = require("eryndor.combat")
    local s = c.me
    if not s then return end
    local t = M.Totals()
    s.gear = t
    local base = s.baseHp or s.maxhp
    local talents = require("eryndor.talents")
    talents.Apply(s)                      -- přepočet max. životů z talentů …
    s.maxhp = s.maxhp + t.hp              -- … a navrch výbava
    s.hp = min(s.hp, s.maxhp)
    s.weaponKind = M.WeaponKind()
    local _ = base
end

-- ------------------------------------------------------------------ zbraně: druh v ruce, animace, útoky
function M.WeaponKind()
    local m = M.slots.main and items.Base[M.slots.main.id]
    return m and m.kind or nil
end

-- přípona sady animací (Motion Forge) podle toho, co drží v rukou; zasunuté zbraně = volné ruce
function M.ClipSet()
    if not M.drawn then return "" end
    local m = M.slots.main and items.Base[M.slots.main.id]
    local o = M.slots.off and items.Base[M.slots.off.id]
    if not m then return (o and o.kind == "shield") and "_1HS" or "" end
    local k = items.Kinds[m.kind]
    if k.set == "_1H" then
        if o and o.kind == "shield" then return "_1HS" end
        if o and items.Kinds[o.kind] and items.Kinds[o.kind].hand == "either" then return "_DW" end
    end
    return k.set or ""
end

-- útoky a dovednosti podle zbraně: klip povolání se přemapuje na druh zbraně, kterou postava drží
local ATTACKS = {
    none = { "Unarmed_Melee_Attack_Punch_A", "Unarmed_Melee_Attack_Punch_B", "Unarmed_Melee_Attack_Kick" },
    _1H = { "1H_Melee_Attack_Chop", "1H_Melee_Attack_Slice_Diagonal", "1H_Melee_Attack_Stab", "1H_Melee_Attack_Slice_Horizontal" },
    _2H = { "2H_Melee_Attack_Chop", "2H_Melee_Attack_Slice", "2H_Melee_Attack_Stab" },
    _DW = { "Dualwield_Melee_Attack_Chop", "Dualwield_Melee_Attack_Slice", "Dualwield_Melee_Attack_Stab" },
}
local count = 0
function M.MapClip(clip)
    if type(clip) ~= "string" then return clip end
    local melee = clip:match("^1H_Melee") or clip:match("^2H_Melee_Attack") or clip:match("^Dualwield") or clip:match("^Unarmed_Melee")
    local ranged = clip:match("_Ranged_")
    local kind = M.WeaponKind()
    local k = kind and items.Kinds[kind]
    if ranged then
        if kind == "bow" then return (clip:gsub("^1H_Ranged", "2H_Ranged")) end
        if kind == "crossbow" then return (clip:gsub("^2H_Ranged", "1H_Ranged")) end
        return "Throw"   -- bez střelné zbraně hází (vrhací nože, krystaly)
    end
    if not melee then return clip end
    local set = not kind and "none" or (k.set == "_1H" and M.ClipSet() == "_DW" and "_DW") or (k.set == "_2H" and "_2H") or
        (k.set == "_1H" and "_1H") or nil
    if not set then return clip end   -- hůl, luk: útok povolání zůstává (kouzla, střelba)
    local list = ATTACKS[set]
    if clip:match("Spin") and set ~= "none" then return set == "_2H" and "2H_Melee_Attack_Spin" or clip end
    if clip:match("^Block") and M.slots.off and items.Base[M.slots.off.id].kind == "shield" then return clip end
    for _, c in ipairs(list) do if c == clip then return clip end end
    count = count + 1
    return list[(count - 1) % #list + 1]
end

-- ------------------------------------------------------------------ vzhled (zbroj + zbraně) pro libovolnou postavu
-- uložené polohy zbraní mimo boj (kost, posun v klidové póze postavy, natočení) – postava kouká po +Z, její pravá je −X
M.Sheath = {
    back = { bone = "spine_03", pos = { -0.13, 0.22, -0.17 }, rot = { 0, 0, 205 } },      -- jílec nad pravým ramenem
    back_shield = { bone = "spine_03", pos = { 0.0, 0.0, -0.2 }, rot = { 0, 180, 0 } },   -- štít lícem dozadu
    back_bow = { bone = "spine_03", pos = { 0.12, 0.05, -0.16 }, rot = { 0, 0, 155 } },
    hip = { bone = "pelvis", pos = { 0.17, -0.02, 0.0 }, rot = { 20, 0, 180 } },          -- levý bok, čepel dolů
    hip_off = { bone = "pelvis", pos = { -0.17, -0.02, 0.0 }, rot = { 20, 0, 180 } },
    thigh = { bone = "pelvis", pos = { -0.15, -0.1, 0.06 }, rot = { 10, 0, 180 } },
}

local function modelFor(item, raceModel)
    local b = items.Base[item.id]
    if b.armor then return "Models/armor/" .. b.armor .. "_" .. b.slot .. "_" .. raceModel .. ".glb" end
    return "Models/gear/real/" .. b.model .. ".glb"
end

-- vzácnost: lemy zbroje a čepele (epické a legendární jemně září)
local function tintRarity(id, item, armor)
    local r = item.g and item.g.r or "common"
    local trim = armor and "*_trim" or "*"
    if r == "rare" then entity.material_color(id, trim, { 0.75, 0.85, 1.15 })
    elseif r == "epic" then entity.material_color(id, trim, { 0.95, 0.7, 1.2 }, { 0.25, 0.05, 0.4 })
    elseif r == "legendary" then entity.material_color(id, trim, { 1.25, 0.85, 0.45 }, { 0.45, 0.2, 0.02 }) end
    local enh = item.g and item.g.enh or 0
    if enh >= 10 and not armor then entity.material_color(id, "*", { 1, 1, 1 }, { 0.1 * (enh - 9), 0.06 * (enh - 9), 0.2 }) end
end

-- nasadí vzhled výbavy na entitu postavy; v = stav vzhledu (tabulka se seznamem entit), eq = { slot = item }
function M.Apply(id, v, eq, raceModel, drawn, scale)
    for _, e in ipairs(v.ents or {}) do entity.destroy(e) end
    v.ents, v.weapons = {}, {}
    scale = scale or 1
    for _, slot in ipairs({ "head", "shoulders", "chest", "hands", "legs", "feet" }) do
        local it = eq[slot]
        if it and items.Base[it.id] then
            local p = _G.world.spawn(modelFor(it, raceModel), 0, 0, 0, { name = items.Base[it.id].name })
            entity.equip(p, id)
            tintRarity(p, it, true)
            v.ents[#v.ents + 1] = p
        end
    end
    for _, slot in ipairs({ "main", "off" }) do
        local it = eq[slot]
        local b = it and items.Base[it.id]
        if b then
            local w = _G.world.spawn(modelFor(it), 0, 0, 0, { name = b.name, scale = scale })
            local k = items.Kinds[b.kind]
            if drawn then
                local hand = (slot == "off" or k.left) and "handslot.l" or "handslot.r"
                entity.attach(w, id, hand)
                entity.set_position(w, 0, 0, 0)
                entity.set_rotation(w, 0, 0, 0)
            else
                local key = k.sheath
                if b.kind == "shield" then key = "back_shield" elseif b.kind == "bow" then key = "back_bow"
                elseif slot == "off" and key == "hip" then key = "hip_off" end
                local sh = M.Sheath[key] or M.Sheath.hip
                entity.attach(w, id, sh.bone)
                entity.set_position(w, sh.pos[1] * scale, sh.pos[2] * scale, sh.pos[3] * scale)
                entity.set_rotation(w, sh.rot[1], sh.rot[2], sh.rot[3])
            end
            tintRarity(w, it, false)
            v.ents[#v.ents + 1] = w
            v.weapons[#v.weapons + 1] = w
        end
    end
end

-- kompaktní zápis pro síť (ostatní hráči): { slot = "id:vzácnost:vylepšení" }
function M.Pack()
    local out = {}
    for _, slot in ipairs(items.Slots) do
        local it = M.slots[slot]
        if it then out[slot] = it.id .. ":" .. (it.g.r or "common") .. ":" .. (it.g.enh or 0) end
    end
    return out
end
function M.Unpack(p)
    local eq = {}
    if type(p) ~= "table" then return eq end
    for _, slot in ipairs(items.Slots) do
        local s = p[slot]
        if type(s) == "string" then
            local id, r, e = s:match("^([%w_]+):(%a+):(%d+)$")
            if id and items.Base[id] and items.Rarity[r] then eq[slot] = { id = id, n = 1, g = { r = r, enh = tonumber(e), il = 1 } } end
        end
    end
    return eq
end

-- ------------------------------------------------------------------ vlastní postava
local function raceModelName()
    local p = require("eryndor.player")
    local a = p.appearance
    if not a then return "clovek" end
    local v = (require("eryndor.races").Defs[a.race] or {}).variants
    return v and v[a.variant or 1] and v[a.variant or 1][1] or a.race
end
M.RaceModel = raceModelName

function M.Refresh()
    local p = require("eryndor.player")
    if not p.view then return end
    local gear = require("eryndor.races").Gear[p.appearance and p.appearance.race or "clovek"]
    M.Apply(p.view, M.visuals, M.slots, raceModelName(), M.drawn, gear and gear.scale or 1)
    p.weapons = M.visuals.weapons or {}   -- jen zbraně (kůň, nástroje profesí a emoty je schovávají, zbroj ne)
    p.anim = nil
end

-- tasit / zasunout (boj začne -> tasí; 6 s po boji zasune)
function M.SetDrawn(on)
    if M.drawn == on then return end
    M.drawn = on
    local p = require("eryndor.player")
    if p.view and not p.dead and not p.swim and not p.mount then
        p.Action(on and "Use_Item" or "Interact", 0.35, 1.6)   -- krátké sáhnutí po zbrani
    end
    M.Refresh()
    if M.onChange then M.onChange() end
end

function M.Changed()
    M.Save()
    M.Recalc()
    M.Refresh()
    if M.onChange then M.onChange() end
end

local idleT = 0
function M.Update(dt)
    local c = require("eryndor.combat")
    local fight = c.inCombat or c.auto or (c.me and c.me.casting)
    if fight then
        idleT = 0
        if not M.drawn and (M.slots.main or M.slots.off) then M.SetDrawn(true) end
    else
        idleT = idleT + dt
        if M.drawn and idleT > 6 then M.SetDrawn(false) end
    end
end

return M
