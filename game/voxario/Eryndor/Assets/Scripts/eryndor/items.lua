-- Výbava (zbraně a zbroj) jako v klasických MMO: každý kus je samostatný předmět s vlastnostmi
--   ItemLevel (ilvl), Rarity (vzácnost), AttackPower / Defense (útok, obrana, magie), EnhancementLevel (+0 až +15)
-- a náhodnými doplňkovými vlastnostmi u vzácnějších kusů. Modely jsou fotorealistické a vyrobil je engine (bez AI):
-- zbraně tools/eryndor_weapons.py (Models/gear/real), zbroj Armor Forge enginu na míru každé rase (Models/armor).
--
-- Předmět v tašce / ve slotu:  { id = "sword_1h", g = { r = "rare", il = 12, enh = 3, atk = 31, def = 0, matk = 0, hp = 40, crit = 2 } }
local M = {}
local floor, random, max, min = math.floor, math.random, math.max, math.min

-- vzácnost: barva, násobek hlavních vlastností, počet doplňkových vlastností, šance při kořisti
M.Rarity = {
    common    = { name = "Běžný",       color = "#c8c8c8", mult = 1.00, extras = 0, order = 1 },
    uncommon  = { name = "Neobvyklý",   color = "#3ed14a", mult = 1.15, extras = 1, order = 2 },
    rare      = { name = "Vzácný",      color = "#3d8bff", mult = 1.32, extras = 2, order = 3 },
    epic      = { name = "Epický",      color = "#b55cff", mult = 1.55, extras = 3, order = 4 },
    legendary = { name = "Legendární",  color = "#ff9a1f", mult = 1.85, extras = 4, order = 5 },
}
M.RarityOrder = { "common", "uncommon", "rare", "epic", "legendary" }

-- sloty postavy
M.Slots = { "head", "shoulders", "chest", "hands", "legs", "feet", "main", "off" }
M.SlotNames = { head = "Hlava", shoulders = "Ramena", chest = "Hruď", hands = "Ruce", legs = "Nohy", feet = "Chodidla",
                main = "Hlavní ruka", off = "Vedlejší ruka" }

-- druh zbraně -> sada animací (Motion Forge: weapon_sets.py) a způsob nošení
--   hand: "main" | "two" (obouruční – vedlejší ruka zůstane prázdná) | "off" (jen vedlejší ruka) | "either"
M.Kinds = {
    sword1h  = { set = "_1H", hand = "either", sheath = "hip" },
    axe1h    = { set = "_1H", hand = "either", sheath = "hip" },
    mace1h   = { set = "_1H", hand = "either", sheath = "hip" },
    dagger   = { set = "_1H", hand = "either", sheath = "thigh" },
    crossbow = { set = "_1H", hand = "main", sheath = "back", ranged = true },
    wand     = { set = "_1H", hand = "main", sheath = "thigh", magic = true },
    twohand  = { set = "_2H", hand = "two", sheath = "back" },
    staff    = { set = "_ST", hand = "two", sheath = "back", magic = true },
    bow      = { set = "_BOW", hand = "two", sheath = "back", ranged = true, left = true },
    shield   = { hand = "off", sheath = "back" },
    book     = { hand = "off", sheath = "hip", magic = true },
}

-- základní předměty: model, druh / slot, základní vlastnosti na ilvl 1 (rostou s ilvl), povolená povolání
M.Base = {
    -- zbraně (Models/gear/real/*.glb – rukojeť v počátku, čepel po +Y)
    sword_1h  = { name = "Meč",                 model = "sword_1handed",   kind = "sword1h",  slot = "main", atk = 9,  icon = "g_sword_1h" },
    axe_1h    = { name = "Válečná sekera",      model = "axe_1handed",     kind = "axe1h",    slot = "main", atk = 10, icon = "g_axe_1h" },
    mace_1h   = { name = "Palcát",              model = "mace_1handed",    kind = "mace1h",   slot = "main", atk = 10, icon = "g_mace_1h" },
    dagger    = { name = "Dýka",                model = "dagger",          kind = "dagger",   slot = "main", atk = 7,  crit = 2, icon = "g_dagger" },
    sword_2h  = { name = "Obouruční meč",       model = "sword_2handed",   kind = "twohand",  slot = "main", atk = 17, icon = "g_sword_2h" },
    axe_2h    = { name = "Obouruční sekera",    model = "axe_2handed",     kind = "twohand",  slot = "main", atk = 18, icon = "g_axe_2h" },
    hammer_2h = { name = "Válečné kladivo",     model = "hammer_2handed",  kind = "twohand",  slot = "main", atk = 19, icon = "g_hammer_2h" },
    staff     = { name = "Hůl Zřídla",          model = "staff",           kind = "staff",    slot = "main", atk = 5, matk = 15, icon = "g_staff" },
    wand      = { name = "Hůlka",               model = "wand",            kind = "wand",     slot = "main", atk = 3, matk = 10, icon = "g_wand" },
    bow       = { name = "Dlouhý luk",          model = "bow_long",        kind = "bow",      slot = "main", atk = 14, icon = "g_bow" },
    crossbow  = { name = "Runová kuše",         model = "crossbow_1handed", kind = "crossbow", slot = "main", atk = 13, icon = "g_crossbow" },
    shield_round = { name = "Kulatý štít",      model = "shield_round",    kind = "shield",   slot = "off",  def = 8,  icon = "g_shield_round" },
    shield_kite  = { name = "Erbovní štít",     model = "shield_kite",     kind = "shield",   slot = "off",  def = 11, icon = "g_shield_kite" },
    spellbook    = { name = "Kniha kouzel",     model = "spellbook_open",  kind = "book",     slot = "off",  matk = 6, icon = "g_spellbook" },
}
-- zbroj: kožená a plátová sada (Armor Forge: <sada>_<slot>_<rasa>.glb)
local ARMOR_DEF = { head = 4, shoulders = 4, chest = 8, hands = 3, legs = 6, feet = 3 }
local ARMOR_NAMES = {
    leather = { head = "Kožená kápě", shoulders = "Kožené nárameníky", chest = "Kožená brigantina", hands = "Kožené rukavice",
                legs = "Kožené chrániče nohou", feet = "Kožené holínky" },
    plate = { head = "Plátová přilba", shoulders = "Plátové nárameníky", chest = "Plátový kyrys", hands = "Plátové rukavice",
              legs = "Plátové holeně", feet = "Plátové sabatony" },
}
for set, names in pairs(ARMOR_NAMES) do
    for slot, nm in pairs(names) do
        M.Base[set .. "_" .. slot] = { name = nm, armor = set, slot = slot, def = floor(ARMOR_DEF[slot] * (set == "plate" and 1.7 or 1.0)),
                                       hp = set == "leather" and floor(ARMOR_DEF[slot] * 2) or 0, icon = "g_" .. set .. "_" .. slot }
    end
end

-- kdo co smí nosit (jako ve WoW: plát jen bojovníci, štít rytíř a těžkooděnec, dvě zbraně těžkooděnec a inženýrka)
M.ClassRules = {
    knight   = { plate = true, shield = true, dual = false },
    mage     = { plate = false, shield = false, dual = false },
    warden   = { plate = true, shield = true, dual = true },
    engineer = { plate = false, shield = false, dual = true },
}

-- ------------------------------------------------------------------ vlastnosti a výroba
local EXTRAS = { "hp", "crit", "atk", "def", "matk" }

-- hlavní vlastnosti kusu z ilvl, vzácnosti a vylepšení (+6 % základu za úroveň, od +10 navíc +4 %)
function M.Stats(item)
    local b, g = M.Base[item.id], item.g
    if not b or not g then return {} end
    local r = M.Rarity[g.r] or M.Rarity.common
    local lvl = 1 + (g.il - 1) * 0.11
    local enh = g.enh or 0
    local em = 1 + enh * 0.06 + max(0, enh - 9) * 0.04
    local s = {}
    for _, k in ipairs({ "atk", "def", "matk", "hp", "crit" }) do
        local base = (b[k] or 0) * (k == "crit" and 1 or lvl) * r.mult * (k == "crit" and 1 or em)
        local v = base + (g.x and g.x[k] or 0)
        if v > 0 then s[k] = (k == "crit") and floor(v * 10 + 0.5) / 10 or floor(v + 0.5) end
    end
    return s
end

-- nový kus: base, ilvl, vzácnost (nil = náhodně podle šancí kořisti)
function M.Roll(baseId, ilvl, rarity)
    local b = M.Base[baseId]
    if not b then return nil end
    if not rarity then
        local x = random()
        rarity = x < 0.01 and "legendary" or x < 0.05 and "epic" or x < 0.18 and "rare" or x < 0.45 and "uncommon" or "common"
    end
    local g = { r = rarity, il = max(1, floor(ilvl or 1)), enh = 0, x = {} }
    for _ = 1, M.Rarity[rarity].extras do
        local k = EXTRAS[random(#EXTRAS)]
        local add = (k == "crit") and (0.5 + random() * 1.5) or (k == "hp" and (6 + g.il * 2.5 * random()) or (1 + g.il * 0.5 * random()))
        g.x[k] = (g.x[k] or 0) + (k == "crit" and floor(add * 10) / 10 or floor(add + 0.5))
    end
    return { id = baseId, n = 1, g = g }
end

function M.Name(item)
    local b = M.Base[item.id]
    if not b then return "?" end
    local enh = item.g and item.g.enh or 0
    return (enh > 0 and ("+" .. enh .. " ") or "") .. b.name
end
function M.Color(item) return (M.Rarity[item.g and item.g.r or "common"] or M.Rarity.common).color end

-- ------------------------------------------------------------------ vylepšování (+0 až +15)
-- šance na úspěch podle cílové úrovně; při neúspěchu od +7 klesne o úroveň (pod +7 se nic nestane)
M.UpgradeChance = { 1.0, 1.0, 1.0, 0.85, 0.75, 0.65, 0.55, 0.45, 0.38, 0.30, 0.24, 0.18, 0.12, 0.08, 0.05 }
M.MaxEnhancement = 15
-- materiál podle cílové úrovně (rudy z Hornictví): stříbro +1–5, zlato +6–9, diamant +10–12, mitril +13–15
function M.UpgradeMaterial(target)
    if target <= 5 then return "ore_silver", 1 + floor(target / 3) end
    if target <= 9 then return "ore_gold", 1 + floor((target - 5) / 2) end
    if target <= 12 then return "ore_diamond", target - 9 end
    return "ore_mithril", target - 11
end

--- UpgradeItem(targetItem, material) – vyhodnotí šanci, zvýší EnhancementLevel (nebo při neúspěchu od +7 sníží)
--  a vrátí výsledek; vlastnosti se přepočítají (M.Stats) a hra je promítne do statů postavy (equipment.Recalc).
--  material = { id = "ore_gold", have = <počet v tašce> }   ->  { ok, level, chance, used, msg }
function M.UpgradeItem(targetItem, material)
    local g = targetItem and targetItem.g
    if not g then return { ok = false, msg = "Tento předmět nejde vylepšit." } end
    local enh = g.enh or 0
    if enh >= M.MaxEnhancement then return { ok = false, level = enh, msg = "Předmět je už vylepšený na maximum (+15)." } end
    local target = enh + 1
    local mat, need = M.UpgradeMaterial(target)
    if not material or material.id ~= mat or (material.have or 0) < need then
        return { ok = false, level = enh, need = need, mat = mat, msg = "Chybí materiál pro vylepšení." }
    end
    local chance = M.UpgradeChance[target]
    if random() < chance then
        g.enh = target
        return { ok = true, level = target, chance = chance, used = need, mat = mat, msg = "Vylepšení se podařilo! +" .. target }
    end
    if enh >= 7 then g.enh = enh - 1 end
    return { ok = false, failed = true, level = g.enh, chance = chance, used = need, mat = mat,
             msg = enh >= 7 and ("Vylepšení selhalo – předmět klesl na +" .. g.enh .. ".") or "Vylepšení selhalo (předmět se nepoškodil)." }
end

-- kořist z nepřítele: šance, druh a vzácnost podle síly nepřítele (ilvl = úroveň nepřítele)
local POOL_WEAPONS = { "sword_1h", "axe_1h", "mace_1h", "dagger", "sword_2h", "axe_2h", "hammer_2h", "staff", "wand", "bow",
                       "crossbow", "shield_round", "shield_kite", "spellbook" }
local POOL_ARMOR = {}
for id, b in pairs(M.Base) do if b.armor then POOL_ARMOR[#POOL_ARMOR + 1] = id end end
table.sort(POOL_ARMOR)

function M.LootFor(mob)
    local t = mob.t
    local chance = t.boss and 1 or (t.elite and 0.85 or (t.hunt and 0.12 or 0.32))
    local drops = {}
    if random() < chance then
        local pool = random() < 0.45 and POOL_WEAPONS or POOL_ARMOR
        local rarity
        if t.boss then rarity = random() < 0.4 and "legendary" or "epic" elseif t.elite then rarity = random() < 0.5 and "rare" or "epic" end
        drops[#drops + 1] = M.Roll(pool[random(#pool)], (mob.level or 1) + floor(random() * 2), rarity)
    end
    if t.boss then drops[#drops + 1] = M.Roll(POOL_ARMOR[random(#POOL_ARMOR)], mob.level + 2, "epic") end
    return drops
end

-- startovní kořist pro povolání (první zabitý nepřítel – aby nováček nebojoval pěstmi dlouho)
M.ClassStarter = { knight = "sword_1h", mage = "staff", warden = "sword_2h", engineer = "crossbow" }

return M
