-- Hratelné rasy Eryndoru (podle „Rasy a tvorba postavy“): modely z Meshy (image-to-3d z obrázků dokumentace,
-- vlastní postavy z textu), engine je napasoval na kostru postav (VoxarioImageTo3D --rig-model --pose a-pose),
-- takže umí všech 76 animací (boj, kouzla, chůze, emoce). Výroba: tools/eryndor_races.sh.
-- Vzhled = tabulka `a` (ukládá se, posílá ostatním hráčům); Apply ho nasadí na entitu:
--   tvar těla entity.bone_scale / bone_offset, barevný nádech entity.material_color.
local M = {}

local function hex(h)
    return { tonumber(h:sub(2, 3), 16) / 255, tonumber(h:sub(4, 5), 16) / 255, tonumber(h:sub(6, 7), 16) / 255 }
end
M.Hex = hex

M.Order = { "clovek", "trpaslik", "elf", "vila", "obr", "kocka" }
M.Defs = {
    clovek = { name = "Člověk", tag = "Všestranný dobrodruh", gender = "m", height = 1.0,
        desc = "Lidé z tábořišť a hraničních pevností. Bez zvláštních darů, ale vytrvalí a přizpůsobiví – hodí se k jakémukoli povolání." },
    trpaslik = { name = "Trpaslík", tag = "Kovář z hlubin", gender = "m", height = 0.8, shoulders = 1.08,
        desc = "Malí, ale mohutní mistři výhní a run. Vousy si zdobí kroužky a kladivo nosí jako jiní meč." },
    elf = { name = "Elf", tag = "Strážkyně lesů", gender = "f", height = 1.04,
        desc = "Štíhlí strážci prastarých lesů Sylvarie. Bystré oči, tichý krok a luk, který nemine." },
    vila = { name = "Víla", tag = "Křídla a třpyt", gender = "f", height = 0.78,
        desc = "Křehké a éterické bytosti s průsvitnými křídly. Magie jim proudí v žilách jako světlo hub v noci." },
    obr = { name = "Kamenný obr", tag = "Kámen a kožešiny", gender = "m", height = 1.3, shoulders = 1.1,
        desc = "Obři z hor Frostfang s kůží jako žula. Mohutná ramena a hruď, pomalí, ale nezastavitelní." },
    kocka = { name = "Kočičí lid", tag = "Hbití lovci", gender = "f", height = 0.97,
        desc = "Kočkovití válečníci a lovci z horských průsmyků. Pružný krok, bleskové výpady a ostré smysly.",
        variants = { { "kocka", "Sněžný levhart" }, { "kocka_zrzava", "Zrzavý mourek" } } },
}
-- výbava rasy (Meshy z obrázku výbavy, Models/gear): zbraně do rukou, zbroj se oblékne na kostru (entity.equip)
M.Gear = {
    clovek = { right = "gear/mec_dlouhy", left = "shield", armor = "kyrys", label = "Dlouhý meč, štít, ocelový kyrys" },
    trpaslik = { right = "gear/kladivo", armor = "krouzkova", label = "Válečné kladivo, kroužková košile" },
    elf = { left = "gear/luk", armor = "kozena_vesta", label = "Luk s toulcem, kožená vesta s kápí" },
    vila = { right = "gear/hul", left = "gear/dyka", label = "Hůl s krystalem, hůlka" },
    obr = { right = "gear/kladivo", armor = "kozesina", scale = 1.45, label = "Válečné kladivo, kožešinová vesta" },   -- obří ruce
    kocka = { right = "gear/mec", left = "gear/dyka", label = "Meč, dýka" },
}
M.Tints = { "#ffffff", "#ffe2c8", "#d8e8ff", "#e0ffd8", "#ffd8f0", "#d0d0d0", "#fff0b0", "#c8b8ff" }

function M.Default(race)
    local d = M.Defs[race] or M.Defs.clovek
    return { v = 2, race = M.Defs[race] and race or "clovek", name = "", cls = 1, variant = 1,
             height = d.height or 1.0, limbs = 1.0, shoulders = d.shoulders or 1.0, muscle = 1.0, head = 1.0,
             tint = { 1, 1, 1 }, tintAmount = 0.0, glow = 0.0, glowColor = hex("#7fdfff"), gear = true,
             eyes = 1.0, eyeGap = 0.0, nose = 1.0, noseLen = 0.0, jaw = 1.0 }
end

local function num(v, lo, hi, def)
    v = tonumber(v) or def
    return math.max(lo, math.min(hi, v))
end
local function col(c, def)
    if type(c) ~= "table" then return def end
    return { num(c[1], 0, 1, def[1]), num(c[2], 0, 1, def[2]), num(c[3], 0, 1, def[3]) }
end

-- ošetří vzhled (z uložení nebo od jiného hráče přes síť)
function M.Sanitize(a)
    a = type(a) == "table" and a or {}
    local d = M.Default(a.race)
    local r = {}
    for k, v in pairs(d) do r[k] = v end
    r.name = type(a.name) == "string" and a.name:sub(1, 24) or ""
    r.cls = math.floor(num(a.cls, 1, 4, 1))
    r.variant = math.floor(num(a.variant, 1, #((M.Defs[r.race] or {}).variants or { 1 }), 1))
    r.height = num(a.height, 0.7, 1.4, d.height)
    for _, k in ipairs({ "limbs", "shoulders", "muscle", "head" }) do r[k] = num(a[k], 0.8, 1.3, d[k]) end
    r.tintAmount = num(a.tintAmount, 0, 1, 0)
    r.gear = a.gear ~= false
    -- obličej (kosti eye_l / eye_r / nose / jaw)
    r.eyes = num(a.eyes, 0.6, 1.6, 1.0)
    r.eyeGap = num(a.eyeGap, -0.015, 0.015, 0.0)
    r.nose = num(a.nose, 0.5, 1.9, 1.0)
    r.noseLen = num(a.noseLen, -0.02, 0.03, 0.0)
    r.jaw = num(a.jaw, 0.7, 1.45, 1.0)
    r.glow = num(a.glow, 0, 1, 0)
    r.tint = col(a.tint, d.tint)
    r.glowColor = col(a.glowColor, d.glowColor)
    return r
end

function M.Model(a)
    local v = (M.Defs[a.race] or {}).variants
    return "Models/races/" .. (v and v[a.variant or 1] and v[a.variant or 1][1] or a.race) .. ".glb"
end
-- zbraň v pravé ruce (pro varianty klipů s holí)
function M.Weapon(a, class)
    local gear = a and a.gear ~= false and M.Gear[a.race]
    if gear then return gear.right end
    return class and class.look and class.look.right
end
function M.Gender(a) return (M.Defs[a.race] or M.Defs.clovek).gender end

-- nasadí vzhled na entitu
function M.Apply(id, a)
    -- barevný nádech textury (0 = barvy z modelu) a magická záře
    entity.material_color(id)
    local t = a.tintAmount
    local c = { 1 + (a.tint[1] - 1) * t, 1 + (a.tint[2] - 1) * t, 1 + (a.tint[3] - 1) * t }
    local e = a.glow > 0.001 and { a.glowColor[1] * a.glow * 0.12, a.glowColor[2] * a.glow * 0.12, a.glowColor[3] * a.glow * 0.12 } or nil
    if t > 0.001 or e then entity.material_color(id, "*", c, e) end

    -- tvar těla (kosti lidské kostry; stejné měřítko ve všech osách – osy kostí se mezi modely liší)
    entity.bone_scale(id)
    local L, S, Mu, H = a.limbs, a.shoulders, a.muscle, a.head
    if math.abs(a.height - 1) > 0.001 then entity.bone_scale(id, "Root", a.height, a.height, a.height) end
    if math.abs(L - 1) > 0.001 then
        for _, b in ipairs({ "upperarm_l", "upperarm_r", "thigh_l", "thigh_r" }) do entity.bone_scale(id, b, L, L, L) end
        entity.bone_offset(id, "pelvis", 0, (L - 1) * M.LegLift, 0)   -- delší nohy -> pánev výš (chodidla na zemi)
    end
    if math.abs(S - 1) > 0.001 then
        entity.bone_scale(id, "clavicle_l", S, S, S); entity.bone_scale(id, "clavicle_r", S, S, S)
        entity.bone_scale(id, "spine_03", S, S, S, false)
    end
    if math.abs(Mu - 1) > 0.001 then
        for _, b in ipairs({ "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "thigh_l", "thigh_r", "calf_l", "calf_r", "spine_02" }) do
            entity.bone_scale(id, b, Mu, Mu, Mu, false)
        end
    end
    if math.abs(H - 1) > 0.001 then entity.bone_scale(id, "head", H, H, H, false) end
    -- obličejové rysy (morfologie bez blendshapes: kosti v obličeji modelu)
    local e, nz = a.eyes or 1, a.nose or 1
    if math.abs(e - 1) > 0.001 then
        entity.bone_scale(id, "eye_l", e, e, e, false); entity.bone_scale(id, "eye_r", e, e, e, false)
    end
    if math.abs(a.eyeGap or 0) > 0.0005 then
        entity.bone_offset(id, "eye_l", a.eyeGap, 0, 0); entity.bone_offset(id, "eye_r", -a.eyeGap, 0, 0)
    end
    if math.abs(nz - 1) > 0.001 then entity.bone_scale(id, "nose", nz, nz, nz, false) end
    if math.abs(a.noseLen or 0) > 0.0005 then entity.bone_offset(id, "nose", 0, 0, a.noseLen) end
    if math.abs((a.jaw or 1) - 1) > 0.001 then entity.bone_scale(id, "jaw", a.jaw, 1.0 + (a.jaw - 1) * 0.3, 1.0 + (a.jaw - 1) * 0.5, false) end
end
M.LegLift = 0.9

-- spawn postavy s rasou, vzhledem a zbraněmi povolání
function M.Spawn(a, x, y, z, opts)
    opts = opts or {}
    local id = _G.world.spawn(M.Model(a), x, y, z, { yaw = opts.yaw or 0, name = opts.name or a.name, tag = opts.tag })
    local gear = a.gear ~= false and M.Gear[a.race] or nil
    local right, left = opts.right, opts.left
    if gear then right, left = gear.right, gear.left end
    local items = require("eryndor.humans").Dress(id, { right = right, left = left, gearScale = gear and gear.scale })   -- zbraně na handslot
    local weapons = { table.unpack(items) }
    if gear and gear.armor then   -- zbroj na míru rase, hýbe se s kostrou nositele
        local ar = _G.world.spawn("Models/gear/" .. gear.armor .. "_" .. a.race .. ".glb", x, y, z, { name = gear.armor })
        entity.equip(ar, id)
        items[#items + 1] = ar
    end
    M.Apply(id, a)
    return id, items, weapons
end

-- kompaktní vzhled pro síť (barvy jako hex)
local function tohex(c) return string.format("#%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5)) end
function M.Pack(a)
    local p = {}
    for k, v in pairs(a) do p[k] = type(v) == "table" and tohex(v) or v end
    return p
end
function M.Unpack(p)
    if type(p) ~= "table" then return M.Sanitize(nil) end
    local a = {}
    for k, v in pairs(p) do
        if k ~= "name" and type(v) == "string" and v:match("^#%x%x%x%x%x%x$") then a[k] = hex(v) else a[k] = v end
    end
    return M.Sanitize(a)
end

return M
