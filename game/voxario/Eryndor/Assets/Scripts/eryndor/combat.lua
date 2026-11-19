-- Boj (principy tab-target MMO jako 4Story): zaměření cíle (Tab / levé tlačítko), automatický útok
-- (pravé tlačítko na cíl nebo R – postava doběhne na dosah a útočí v rytmu rychlosti útoku, kombo
-- tří úderů), dovednosti 1–6 s manou, cooldownem a globálním cooldownem, sesílání s ukazatelem
-- (pohyb ho přeruší), minutí / kritický zásah / obrana, úrovně a zkušenosti, agro nepřátel,
-- návrat nepřítele na místo (leash) s doplněním života, oživení.
local map = require("eryndor.map")
local player = require("eryndor.player")
local humans = require("eryndor.humans")
local fx = require("eryndor.fx")
local M = { mobs = {}, floats = {}, log = {}, target = nil, auto = false }

local sqrt, max, min, floor, random, deg, atan, sin, cos, pi = math.sqrt, math.max, math.min, math.floor, math.random, math.deg, math.atan, math.sin, math.cos, math.pi
local GCD = 1.0

-- ------------------------------------------------------------------ povolání (podle armád z lore)
M.Classes = {
    {
        id = "knight", faction = "Sylvaria", name = "Duchovní rytíř", model = "syl_knight_m",
        look = { right = "sword", left = "shield", helm = false }, combatIdle = "Idle",
        desc = "Rytíř v lehké, magií protkané zbroji. Drží nepřátele u sebe a chrání spojence.",
        hp = 260, mp = 90, atk = 22, def = 14, range = 2.4, speed = 1.5, combo = { "1H_Melee_Attack_Chop", "1H_Melee_Attack_Slice_Diagonal", "1H_Melee_Attack_Stab" },
        skills = {
            { name = "Úder Zřídla", key = "1", mp = 12, cd = 5, mult = 1.7, anim = "1H_Melee_Attack_Slice_Horizontal", color = { 0.35, 0.85, 1.0 } },
            { name = "Štítový náraz", key = "2", mp = 15, cd = 12, mult = 1.0, stun = 2.5, anim = "Block_Attack", color = { 0.9, 0.85, 0.5 } },
            { name = "Vír čepele", key = "3", mp = 25, cd = 14, mult = 1.25, aoe = 3.5, anim = "2H_Melee_Attack_Spin", color = { 0.5, 0.9, 0.7 } },
            { name = "Požehnání půlměsíce", key = "4", mp = 30, cd = 30, cast = 1.2, heal = 0.3, self = true, anim = "Spellcast_Raise", color = { 0.4, 1.0, 0.8 } },
            { name = "Výzva", key = "5", mp = 10, cd = 20, buff = { def = 12, t = 10 }, self = true, anim = "Cheer", color = { 1.0, 0.75, 0.3 } },
        },
    },
    {
        id = "mage", faction = "Sylvaria", name = "Válečná mágyně", model = "syl_mage_f",
        look = { right = "staff" }, combatIdle = "Idle",
        desc = "Ovládá surovou elementární magii Zřídla. Útočí zdálky, je ale zranitelný.",
        hp = 170, mp = 220, atk = 18, def = 6, range = 16, speed = 1.9, ranged = true, matk = 30,
        combo = { "Spellcast_Shoot" },
        skills = {
            { name = "Aetheriová střela", key = "1", mp = 18, cd = 0, cast = 1.5, mult = 2.3, magic = true, anim = "Spellcast_Shoot", color = { 0.35, 0.8, 1.0 } },
            { name = "Mrazivý kruh", key = "2", mp = 30, cd = 10, mult = 1.3, aoe = 5, self_aoe = true, slow = 4, magic = true, anim = "Spellcast_Raise", color = { 0.6, 0.9, 1.0 } },
            { name = "Bouře krystalů", key = "3", mp = 45, cd = 14, cast = 2.0, mult = 2.6, aoe = 4, magic = true, anim = "Spellcast_Long", color = { 0.7, 0.5, 1.0 } },
            { name = "Kůra Půlměsíce", key = "4", mp = 25, cd = 25, buff = { def = 18, t = 12 }, self = true, anim = "Spellcast_Raise", color = { 0.5, 0.8, 0.5 } },
            { name = "Soustředění", key = "5", mp = 0, cd = 40, cast = 2.0, mana = 0.4, self = true, anim = "Spellcasting", color = { 0.3, 0.5, 1.0 } },
        },
    },
    {
        id = "warden", faction = "Aethelgard", name = "Těžkooděnec", model = "aeth_heavy_m",
        look = { right = "sword2", helm = true }, combatIdle = "2H_Melee_Idle",
        desc = "Disciplína Ocelového slunce v plátové zbroji a s obouručním mečem. Silné, pomalé údery.",
        hp = 300, mp = 80, atk = 28, def = 16, range = 2.6, speed = 2.0, combo = { "2H_Melee_Attack_Chop", "2H_Melee_Attack_Slice", "2H_Melee_Attack_Stab" },
        skills = {
            { name = "Drtivý sek", key = "1", mp = 12, cd = 6, mult = 1.9, anim = "2H_Melee_Attack_Chop", color = { 1.0, 0.6, 0.3 } },
            { name = "Runový výpad", key = "2", mp = 15, cd = 10, mult = 1.4, stun = 1.5, anim = "2H_Melee_Attack_Stab", color = { 1.0, 0.8, 0.4 } },
            { name = "Ocelová smršť", key = "3", mp = 28, cd = 15, mult = 1.3, aoe = 3.8, anim = "2H_Melee_Attack_Spinning", color = { 0.9, 0.5, 0.3 } },
            { name = "Válečný pokřik", key = "4", mp = 20, cd = 30, buff = { atk = 10, t = 12 }, self = true, anim = "Cheer", color = { 1.0, 0.4, 0.2 } },
            { name = "Krystalové jádro", key = "5", mp = 20, cd = 35, heal = 0.25, self = true, anim = "Use_Item", color = { 1.0, 0.7, 0.3 } },
        },
    },
    {
        id = "engineer", faction = "Aethelgard", name = "Inženýrka", model = "aeth_engineer_f",
        look = { right = "crossbow", left = "dagger" }, combatIdle = "Idle",
        desc = "Runová kuše a výbušné krystaly. Střílí zdálky a nepřátele zpomaluje.",
        hp = 200, mp = 140, atk = 24, def = 9, range = 18, speed = 1.4, ranged = true,
        combo = { "1H_Ranged_Shoot" },
        skills = {
            { name = "Mířená rána", key = "1", mp = 14, cd = 4, cast = 1.0, mult = 2.0, anim = "1H_Ranged_Aiming", color = { 1.0, 0.7, 0.3 } },
            { name = "Krystalová bomba", key = "2", mp = 25, cd = 12, mult = 1.5, aoe = 4, anim = "Throw", color = { 1.0, 0.5, 0.2 } },
            { name = "Zpomalující šipka", key = "3", mp = 12, cd = 10, mult = 1.0, slow = 5, anim = "1H_Ranged_Shoot", color = { 0.6, 0.8, 1.0 } },
            { name = "Úskok", key = "4", mp = 10, cd = 8, dodge = true, self = true, anim = "Dodge_Backward", color = { 0.8, 0.8, 0.8 } },
            { name = "Lektvar", key = "5", mp = 0, cd = 30, heal = 0.3, self = true, anim = "Use_Item", color = { 1.0, 0.3, 0.3 } },
        },
    },
}

-- ------------------------------------------------------------------ nepřátelé
M.MobTypes = {
    -- fotorealistický vlk (Quadruped Forge: srst z vrstev, IK nohou), do dálky zjednodušený model (lod)
    wolf = { name = "Zkažený vlk", model = "Models/fauna/wolf.glb", level = 1, hp = 90, atk = 9, def = 3, range = 1.9, speed = 1.6,
             aggro = 9, run = 6.5, walk = 1.6, xp = 28, anims = { idle = "Idle", walk = "Walk", run = "Run", attack = { "Attack1" }, hit = "Hit", death = "Death" },
             scale = 1.08, lod = true },
    -- lovná zvěř (Quadruped Forge): klidná, dokud ji hráč nenapadne (aggro 0) – kůže pro Stahování
    boar = { name = "Divoký kanec", model = "Models/fauna/boar.glb", level = 2, hp = 120, atk = 10, def = 4, range = 1.8, speed = 1.7,
             aggro = 0, run = 5.5, walk = 1.0, xp = 30, scale = 1.0, lod = true, hunt = true,
             anims = { idle = "Graze", walk = "Walk", run = "Run", attack = { "Attack" }, hit = "Hit", death = "Death" } },
    stag = { name = "Jelen", model = "Models/fauna/stag.glb", level = 3, hp = 150, atk = 12, def = 5, range = 2.2, speed = 1.8,
             aggro = 0, run = 7.0, walk = 1.25, xp = 40, scale = 1.0, lod = true, hunt = true,
             anims = { idle = "Graze", walk = "Walk", run = "Run", attack = { "Attack" }, hit = "Hit", death = "Death" } },
    bear = { name = "Hnědý medvěd", model = "Models/fauna/bear.glb", level = 5, hp = 520, atk = 24, def = 12, range = 2.4, speed = 2.2,
             aggro = 6, run = 6.0, walk = 1.15, xp = 160, scale = 1.0, lod = true, hunt = true, aggroTime = 1.6,
             anims = { idle = "Idle", walk = "Walk", run = "Run", attack = { "Attack" }, hit = "Hit", death = "Death", aggro = "Roar" } },
    -- bossové světové události „Pád z nebes“ (eryndor.events): obří postavy s křídly, nepřijdou o místo (bez leash)
    angel = { name = "Padlý anděl Seraphiel", human = "lyrise", level = 10, hp = 5200, atk = 38, def = 20, range = 3.6, speed = 1.9,
              aggro = 18, run = 5.0, walk = 1.6, xp = 2400, elite = true, scale = 2.4, labelY = 5.6, look = { right = "sword2" },
              leash = 80, attackTime = 1.0, hitDelay = 0.5,
              light = { color = { 1.0, 0.9, 0.6 }, intensity = 18, range = 16, flicker = false },
              anims = { idle = "2H_Melee_Idle", walk = "Walking_A", run = "Running_A", attack = { "2H_Melee_Attack_Chop", "2H_Melee_Attack_Slice", "2H_Melee_Attack_Spin" }, hit = "Hit_A", death = "Death_A" } },
    demon = { name = "Démon Azgaroth", human = "crusher", level = 10, hp = 5800, atk = 42, def = 18, range = 3.8, speed = 2.1,
              aggro = 18, run = 5.0, walk = 1.4, xp = 2400, elite = true, scale = 2.3, labelY = 5.4, look = { right = "axe2" },
              leash = 80, attackTime = 1.1, hitDelay = 0.55,
              light = { color = { 1.0, 0.35, 0.08 }, intensity = 18, range = 16, flicker = true },
              anims = { idle = "2H_Melee_Idle", walk = "Walking_A", run = "Running_B", attack = { "2H_Melee_Attack_Chop", "2H_Melee_Attack_Spin" }, hit = "Hit_B", death = "Death_B" } },
    cultist = { name = "Kultista Prázdnoty", human = "cultist_m", level = 3, hp = 150, atk = 13, def = 6, range = 2.0, speed = 1.7,
                aggro = 11, run = 5.2, walk = 1.5, xp = 55, look = { right = "dagger", left = "dagger" },
                anims = { idle = "Idle", walk = "Walking_A", run = "Running_A", attack = { "Dualwield_Melee_Attack_Chop", "Dualwield_Melee_Attack_Slice", "Dualwield_Melee_Attack_Stab" }, hit = "Hit_A", death = "Death_A" } },
    crusher = { name = "Drtič popela", human = "crusher", level = 5, hp = 620, atk = 26, def = 14, range = 2.8, speed = 2.4,
                aggro = 12, run = 4.6, walk = 1.3, xp = 220, elite = true, scale = 1.05, look = { right = "axe2" },
                anims = { idle = "2H_Melee_Idle", walk = "Walking_A", run = "Running_B", attack = { "2H_Melee_Attack_Chop", "2H_Melee_Attack_Spin" }, hit = "Hit_B", death = "Death_B" } },
    -- tvor z Creature Forge (VoxarioCreatureForge, tools/creatures/lavovy_pavouk.creature.json): kamenný zadeček
    -- s lávovými prasklinami, žhnoucí klouby, oči a klepítka; vlastní kostra a klipy, kolem sebe svítí
    spider = { name = "Lávový pavouk", model = "Models/chars/lavovy_pavouk.glb", level = 4, hp = 380, atk = 19, def = 10, range = 2.6,
               speed = 2.1, aggro = 11, run = 5.5, walk = 1.5, xp = 140, scale = 0.85, lod = true,
               attackTime = 1.05, hitDelay = 0.62, hitBone = "Cephalothorax",
               light = { color = { 1, 0.32, 0.06 }, intensity = 7, range = 7, flicker = true },
               anims = { idle = "Idle", walk = "Walk", run = "Run", attack = { "Attack" }, hit = "Hit", death = "Death" } },
    -- ledový drak z Creature Forge (tools/creatures/ledovy_drak.creature.json): elitní strážce severních skal,
    -- průsvitná ledová křídla, krystaly, žhnoucí praskliny; při zahlédnutí hráče zařve (Roar)
    dragon = { name = "Ledový drak", model = "Models/chars/ledovy_drak.glb", level = 6, hp = 1600, atk = 30, def = 16, range = 4.2,
               speed = 2.6, aggro = 16, run = 6.0, walk = 1.8, xp = 520, elite = true, scale = 0.8, lod = true, labelY = 5.4,
               attackTime = 1.25, hitDelay = 0.62, hitBone = "Pelvis", aggroTime = 2.0,
               light = { color = { 0.35, 0.7, 1.0 }, intensity = 10, range = 11, flicker = false },
               anims = { idle = "Idle", walk = "Walk", run = "Run", attack = { "Attack" }, hit = "Hit", death = "Death", aggro = "Roar" } },
    -- Azure Ocean (tools/eryndor_sea.py, kreslený styl s obrysy): plavou u hladiny a na souš nevylezou
    siren = { name = "Korálová siréna", model = "Models/sea/siren.glb", level = 4, hp = 300, atk = 17, def = 8, range = 3.4,
              speed = 1.8, aggro = 15, run = 4.5, walk = 1.2, xp = 120, scale = 1.25, swim = true, swimDepth = 0.85, labelY = 3.4,
              attackTime = 0.9, hitDelay = 0.5,
              light = { color = { 1.0, 0.35, 0.85 }, intensity = 6, range = 7, flicker = false },
              anims = { idle = "Idle", walk = "Swim", run = "Swim", attack = { "Attack" }, hit = "Hit", death = "Death" } },
    eel = { name = "Ostnatý úhoř", model = "Models/sea/eel.glb", level = 3, hp = 210, atk = 15, def = 6, range = 3.6,
            speed = 1.3, aggro = 13, run = 7.5, walk = 2.0, xp = 90, scale = 0.9, swim = true, swimDepth = 0.25, labelY = 1.6,
            attackTime = 0.7, hitDelay = 0.38,
            light = { color = { 0.35, 0.75, 1.0 }, intensity = 5, range = 6, flicker = true },
            anims = { idle = "Idle", walk = "Swim", run = "Swim", attack = { "Attack" }, hit = "Hit", death = "Death" } },
}

-- výška nepřítele: plavci u hladiny (moře a řeka Serpentine mají jednu hladinu), ostatní na terénu
function M.MobY(m)
    if m.t.swim then return map.SeaY - (m.t.swimDepth or 0.4) + 0.12 * math.sin(game.time() * 1.7 + m.hx) end
    return map.HeightAt(m.x, m.z)
end
-- plavec smí jen tam, kde je dost hluboká voda
local function water(t, x, z) return not t.swim or map.HeightAt(x, z) < map.SeaY - (t.minDepth or 0.7) end

-- rozmístění ve světě Aethelgard (tools/aethelgard_world.py -> world_data.lua): Zkažení vlci na loukách u základny
-- a v Verdant Canopy, kultisté a Drtič u Stínové trhliny v Crystalariu, lávoví pavouci u sopek v Ignis Scar,
-- ledový drak u zamrzlého jezera ve Frostfang Peaks
local SPAWNS = map.Data.Spawns   -- world.lua sem přidá mořská monstra (útesy a řeka)

local function pos(id) return player.Pos(id) end
local function dist2(ax, az, bx, bz) return (ax - bx) ^ 2 + (az - bz) ^ 2 end

function M.Log(text, color)
    table.insert(M.log, { text = text, color = color or { 0.9, 0.9, 0.85 }, t = game.time() })
    if #M.log > 8 then table.remove(M.log, 1) end
end

local function float(x, y, z, text, color, size)
    M.floats[#M.floats + 1] = { x = x, y = y, z = z, text = text, color = color, t = game.time(), size = size or 22,
                                dx = (random() - 0.5) * 0.6 }
end

-- ------------------------------------------------------------------ hráč: statistiky
function M.SetupPlayer(class)
    local s = { class = class, level = 1, xp = 0, cd = {}, gcd = 0, buffs = {}, potionCd = 0 }
    s.baseHp, s.baseMp = class.hp, class.mp
    s.maxhp, s.maxmp = class.hp, class.mp
    s.hp, s.mp = s.maxhp, s.maxmp
    s.atk, s.def = class.atk, class.def
    local talents = require("eryndor.talents")
    talents.Load(s)
    talents.Apply(s)     -- modifikátory statů a aktivní talenty (akční lišta)
    M.me = s
    M.combo = 1
    M.nextSwing = 0
end

function M.XpNeed(level) return floor(80 * level ^ 1.6) end

local function stat(s, name)
    local v = (s[name] or 0) + ((s.mods or {})[name] or 0) + ((s.gear or {})[name] or 0)   -- výbava (eryndor.equipment)
    for _, b in pairs(s.buffs or {}) do
        if b.until_t > game.time() then v = v + (b[name] or 0) end
    end
    return v
end
M.Stat = stat

local function gainXp(amount)
    local s = M.me
    s.xp = s.xp + amount
    M.Log(string.format("+%d zkušeností", amount), { 0.75, 0.6, 1.0 })
    while s.xp >= M.XpNeed(s.level) do
        s.xp = s.xp - M.XpNeed(s.level)
        s.level = s.level + 1
        s.baseHp = floor(s.baseHp * 1.12)
        s.baseMp = floor(s.baseMp * 1.08)
        s.atk = s.atk + 3
        s.def = s.def + 2
        require("eryndor.talents").Apply(s)
        s.hp, s.mp = s.maxhp, s.maxmp
        M.Log("Nový bod talentu (N = strom talentů)", { 1.0, 0.85, 0.3 })
        local x, y, z = pos(player.view)
        float(x, y + 2.6, z, "ÚROVEŇ " .. s.level, { 1.0, 0.85, 0.3 }, 34)
        M.Log("Dosáhl jsi úrovně " .. s.level .. "!", { 1.0, 0.85, 0.3 })
        player.Action("Cheer", 1.6)
    end
end

-- ------------------------------------------------------------------ nepřátelé: život
local function spawnMob(kind, x, z)
    local t = M.MobTypes[kind]
    local m = { kind = kind, t = t, hx = x, hz = z, x = x, z = z, yaw = random() * 360, hp = t.hp, maxhp = t.hp,
                level = t.level, state = "idle", wanderT = game.time() + random() * 5 }
    local y0 = t.swim and map.SeaY - (t.swimDepth or 0.4) or map.HeightAt(x, z)
    if t.human then
        m.id = humans.Spawn(t.human, x, y0, z, { yaw = m.yaw, name = t.name, scale = t.scale or 1, tag = "enemy",
            right = t.look.right, left = t.look.left })
    else
        m.id = _G.world.spawn(t.model, x, y0, z, { yaw = m.yaw, name = t.name, scale = t.scale or 1, tag = "enemy",
            lod = t.lod and "auto" or nil, lod_distance = 30 })
    end
    if t.light then m.light = _G.world.spawn("light", x, y0 + 0.6, z, { light = t.light }) end
    anim.play(m.id, t.anims.idle, 0.2, true)
    m.anim = t.anims.idle
    M.mobs[#M.mobs + 1] = m
    return m
end

M.SpawnMob = spawnMob
function M.SpawnAll()
    for _, s in ipairs(SPAWNS) do spawnMob(s[1], s[2], s[3]) end
end

local function mobPlay(m, clip, loop, restart)
    if m.anim == clip and not restart then return end
    m.anim = clip
    anim.play(m.id, clip, 0.12, loop ~= false, restart)
end

local function hitChance(attLevel, defLevel)
    return max(0.6, min(0.98, 0.94 + (attLevel - defLevel) * 0.04))
end

-- poškození (atk * násobek, náhodný rozptyl, obrana tlumí); vrací číslo, nil = minutí
local function roll(atk, def, mult, attLevel, defLevel, critChance)
    if random() > hitChance(attLevel, defLevel) then return nil end
    local dmg = atk * (mult or 1) * (0.9 + random() * 0.2) - def * 0.5
    local crit = random() < (critChance or 0.08)
    if crit then dmg = dmg * 1.8 end
    return max(1, floor(dmg + 0.5)), crit
end

local function damageMob(m, mult, magic, skill)
    if m.state == "dead" then return end
    local s = M.me
    local atk = magic and (s.class.matk or s.atk) + (s.level - 1) * 3 + ((s.mods or {}).matk or 0) + ((s.gear or {}).matk or 0) or stat(s, "atk")
    if not magic and not (s.gear and s.weaponKind) then atk = atk * 0.6 end   -- pěstmi slaběji
    local dmg, crit = roll(atk, m.t.def, mult, s.level, m.level, 0.08 + (((s.mods or {}).crit or 0) + ((s.gear or {}).crit or 0)) / 100)
    local x, y, z = pos(m.id)
    if not dmg then
        float(x, y + 2.0, z, "Minutí", { 0.8, 0.8, 0.8 }, 20)
        return
    end
    m.hp = m.hp - dmg
    float(x, y + 2.1, z, tostring(dmg) .. (crit and "!" or ""), crit and { 1.0, 0.85, 0.2 } or { 1.0, 1.0, 1.0 }, crit and 32 or 24)
    if skill then M.Log(string.format("%s zasáhl %s za %d%s", skill, m.t.name, dmg, crit and " (kritický)" or ""), { 0.7, 0.9, 1.0 }) end
    if m.state ~= "return" then m.state = "chase"; m.aggro = true end
    if m.hp <= 0 then
        m.hp = 0
        m.state = "dead"
        m.deadT = game.time()
        mobPlay(m, m.t.anims.death, false, true)
        M.Log(m.t.name .. " padl.", { 1.0, 0.8, 0.5 })
        gainXp(m.t.xp)
        if M.onKill then M.onKill(m) end
        for _, fn in ipairs(M.killHooks or {}) do fn(m) end
        if M.target == m then M.target, M.auto = nil, false end
    elseif random() < 0.35 then
        anim.layer(m.id, m.t.anims.hit, m.t.hitBone or "spine", 0.06, false)
    end
end

M.DamageMob = damageMob
-- poškození od mazlíčka / prostředí: pevné číslo, nepřítel se otočí na hráče
function M.HitMob(m, dmg, color)
    if m.state == "dead" then return end
    local x, y, z = pos(m.id)
    m.hp = m.hp - dmg
    float(x, y + 2.0, z, tostring(dmg), color or { 0.85, 0.85, 1.0 }, 20)
    if m.state ~= "return" then m.state = "chase"; m.aggro = true end
    if m.hp <= 0 then
        m.hp = 0
        m.state = "dead"
        m.deadT = game.time()
        mobPlay(m, m.t.anims.death, false, true)
        M.Log(m.t.name .. " padl.", { 1.0, 0.8, 0.5 })
        gainXp(m.t.xp)
        for _, fn in ipairs(M.killHooks or {}) do fn(m) end
        if M.target == m then M.target, M.auto = nil, false end
    end
end
M.GainXp = function(a) gainXp(a) end

local function damagePlayer(m)
    local s = M.me
    if player.dead then return end
    if s.dodgeT and game.time() < s.dodgeT then
        local x, y, z = pos(player.view)
        float(x, y + 2.2, z, "Úhyb", { 0.8, 0.9, 1.0 }, 20)
        return
    end
    local dmg, crit = roll(m.t.atk + (m.level - 1) * 2, stat(s, "def"), 1, m.level, s.level)
    local x, y, z = pos(player.view)
    if not dmg then
        float(x, y + 2.2, z, "Minul", { 0.8, 0.8, 0.8 }, 18)
        return
    end
    s.hp = s.hp - dmg
    s.lastHit = game.time()
    float(x + 0.4, y + 2.2, z, "-" .. dmg, { 1.0, 0.35, 0.3 }, crit and 28 or 22)
    if s.casting then
        s.casting.pushback = (s.casting.pushback or 0) + 0.25   -- zásah při sesílání ho zdrží
    end
    if s.hp <= 0 then
        s.hp = 0
        player.dead = true
        player.Action("Death_A", 99)
        M.auto, s.casting = false, nil
        M.Log("Padl jsi. Ozvěna se vrací ke Zřídlu…", { 1.0, 0.4, 0.4 })
        M.respawnT = game.time() + 5
    elseif random() < 0.3 and not (player.actionT and game.time() < player.actionT) then
        anim.layer(player.view, "Hit_A", "spine", 0.06, false)
    end
end

-- živel efektu dovednosti (částice enginu: eryndor.fx)
M.SkillFx = {
    ["Úder Zřídla"] = "arcane", ["Štítový náraz"] = "spark", ["Vír čepele"] = "spark", ["Požehnání půlměsíce"] = "heal",
    ["Výzva"] = "holy", ["Aetheriová střela"] = "arcane", ["Mrazivý kruh"] = "frost", ["Bouře krystalů"] = "lightning",
    ["Kůra Půlměsíce"] = "poison", ["Soustředění"] = "arcane", ["Drtivý sek"] = "fire", ["Runový výpad"] = "holy",
    ["Ocelová smršť"] = "spark", ["Válečný pokřik"] = "fire", ["Krystalové jádro"] = "holy", ["Mířená rána"] = "spark",
    ["Krystalová bomba"] = "fire", ["Zpomalující šipka"] = "frost", ["Úskok"] = "shadow", ["Lektvar"] = "heal",
    ["Hradba"] = "holy", ["Rozsudek"] = "holy", ["Léčivý pramen"] = "heal", ["Ledová nova"] = "frost", ["Meteor"] = "fire",
    ["Záblesk"] = "arcane", ["Rozpolcení"] = "fire", ["Ocelová zeď"] = "spark", ["Runa slunce"] = "holy",
    ["Salva"] = "spark", ["Krystalová mina"] = "fire", ["Opravný mechanismus"] = "heal",
}
function M.Element(sk) return sk and (sk.fx or M.SkillFx[sk.name]) or "spark" end

-- poškození z prostředí (tonutí): bez úhybu a obrany
function M.HurtPlayer(amount, text)
    local s = M.me
    if not s or player.dead then return end
    local dmg = math.max(1, floor(amount))
    s.hp = s.hp - dmg
    local x, y, z = pos(player.view)
    float(x + 0.4, y + 1.2, z, "-" .. dmg, { 0.5, 0.7, 1.0 }, 22)
    if s.hp <= 0 then
        s.hp = 0
        player.dead = true
        player.swim = nil
        player.Action("Death_A", 99)
        M.auto, s.casting = false, nil
        M.Log(text or "Utonul jsi. Ozvěna se vrací ke Zřídlu…", { 1.0, 0.4, 0.4 })
        M.respawnT = game.time() + 5
    end
end

-- ------------------------------------------------------------------ zaměření
function M.Hostiles()
    local out = {}
    for _, m in ipairs(M.mobs) do if m.state ~= "dead" then out[#out + 1] = m end end
    return out
end

-- Tab: nejbližší živý nepřítel před hráčem, opakovaně další v pořadí
function M.TabTarget()
    local px, _, pz = pos(player.body)
    local list = {}
    for _, m in ipairs(M.Hostiles()) do
        local d = dist2(px, pz, m.x, m.z)
        if d < 40 * 40 then list[#list + 1] = { m = m, d = d } end
    end
    table.sort(list, function(a, b) return a.d < b.d end)
    if #list == 0 then M.target = nil; return end
    local idx = 1
    for i, e in ipairs(list) do if e.m == M.target then idx = i % #list + 1 end end
    M.target = list[idx].m
end

function M.Select(m)
    if m and m.state ~= "dead" then
        M.target = m
    end
end

-- lektvary (akční lišta 9 a 0): sdílená doba obnovení 30 s
M.PotionCd = 30
function M.UsePotion(kind)
    local s = M.me
    if not s or player.dead then return end
    local now = game.time()
    if now < (s.potionCd or 0) then M.Log("Lektvar ještě není připraven.", { 0.8, 0.6, 0.6 }); return end
    s.potionCd = now + M.PotionCd
    local px, py, pz = pos(player.view)
    player.Action("Use_Item", 0.9)
    if kind == "mp" then
        local g = floor(s.maxmp * 0.35)
        s.mp = min(s.maxmp, s.mp + g)
        float(px, py + 2.3, pz, "+" .. g .. " many", { 0.4, 0.6, 1.0 }, 24)
    else
        local h = floor(s.maxhp * 0.35)
        s.hp = min(s.maxhp, s.hp + h)
        float(px, py + 2.3, pz, "+" .. h, { 0.4, 1.0, 0.5 }, 26)
    end
end

function M.StartAttack()
    if M.target and M.target.state ~= "dead" then M.auto = true end
end

-- ------------------------------------------------------------------ dovednosti
function M.UseSkill(i)
    local s = M.me
    local sk = s and (s.skills or s.class.skills)[i]
    if not sk or player.dead then return end
    local now = game.time()
    if s.casting then return end
    if now < s.gcd then return end
    if (s.cd[i] or 0) > now then M.Log(sk.name .. " ještě není připravena.", { 0.8, 0.6, 0.6 }); return end
    if s.mp < sk.mp then M.Log("Nedostatek many.", { 0.5, 0.6, 1.0 }); return end
    local tgt = M.target
    if not sk.self and not sk.self_aoe then
        if not tgt or tgt.state == "dead" then M.Log("Nemáš cíl.", { 0.8, 0.6, 0.6 }); return end
        local px, _, pz = pos(player.body)
        local range = s.class.ranged and s.class.range or s.class.range + 0.6
        if dist2(px, pz, tgt.x, tgt.z) > range * range then
            M.pendingSkill = i            -- jako v 4Story: doběhne na dosah a pak použije
            M.auto = true
            return
        end
    end
    if sk.cast then
        s.casting = { i = i, start = now, dur = sk.cast, target = tgt }
        do   -- sesílání: částice živlu u postavy
            local cx, cy, cz = pos(player.view)
            local f = math.rad(player.facing or 0)
            fx.Cast(cx + math.sin(f) * 0.45, cy + 1.25, cz + math.cos(f) * 0.45, M.Element(sk), sk.cast)
        end
        player.Action(sk.anim == "Spellcast_Shoot" and "Spellcasting" or (sk.anim or "Spellcasting"), sk.cast + 0.3)
        return
    end
    M.Execute(i, tgt)
end

function M.Execute(i, tgt)
    local s = M.me
    local sk = (s.skills or s.class.skills)[i]
    local now = game.time()
    s.mp = s.mp - sk.mp
    s.cd[i] = now + (sk.cd or 0) * (1 - ((s.mods or {}).cdr or 0) / 100)   -- talenty zkracují obnovení
    s.gcd = now + GCD
    player.Action(sk.anim or "Spellcast_Shoot", 0.9)
    local px, py, pz = pos(player.view)
    if tgt and not sk.self then player.faceTarget = deg(atan(tgt.x - px, tgt.z - pz)) end
    if sk.heal then
        local h = floor(s.maxhp * sk.heal)
        s.hp = min(s.maxhp, s.hp + h)
        float(px, py + 2.3, pz, "+" .. h, { 0.4, 1.0, 0.5 }, 26)
        fx.Aura(px, pz, sk.color, M.Element(sk))
        M.Log(sk.name .. ": +" .. h .. " života", { 0.5, 1.0, 0.6 })
    end
    if sk.mana then
        local g = floor(s.maxmp * sk.mana)
        s.mp = min(s.maxmp, s.mp + g)
        float(px, py + 2.3, pz, "+" .. g .. " many", { 0.4, 0.6, 1.0 }, 22)
    end
    if sk.buff then
        s.buffs[sk.name] = { until_t = now + sk.buff.t, atk = sk.buff.atk, def = sk.buff.def, name = sk.name, color = sk.color }
        M.Log(sk.name .. " (" .. sk.buff.t .. " s)", sk.color)
        fx.Aura(px, pz, sk.color, M.Element(sk))
    end
    if sk.dodge then
        s.dodgeT = now + 1.2
        local fx, fz = sin(math.rad(player.facing)), cos(math.rad(player.facing))
        player.vx, player.vz = -fx * 14, -fz * 14
        require("eryndor.fx").Impact(px, py + 0.8, pz, M.Element(sk))
    end
    if sk.mult then
        local hits = {}
        if sk.aoe then
            local cx, cz = (sk.self_aoe or not tgt) and px or tgt.x, (sk.self_aoe or not tgt) and pz or tgt.z
            for _, m in ipairs(M.Hostiles()) do
                if dist2(cx, cz, m.x, m.z) < sk.aoe * sk.aoe then hits[#hits + 1] = m end
            end
            fx.Burst(cx, cz, sk.aoe, sk.color, M.Element(sk))
        elseif tgt then
            hits[1] = tgt
        end
        -- střelecké a kouzelné dovednosti na jeden cíl: střela, zásah po doletu
        if not sk.aoe and tgt and (s.class.ranged or sk.magic) then
            local m = tgt
            fx.Bolt(px, py + 1.3, pz, m.id, sk.color, s.class.matk and 18 or 30, function()
                damageMob(m, sk.mult, sk.magic, sk.name)
                if sk.slow and m.state ~= "dead" then m.slowT = game.time() + sk.slow end
            end, s.class.matk and 0.45 or 0.18, M.Element(sk))
            return
        end
        for _, m in ipairs(hits) do
            if not sk.aoe then fx.Impact(m.x, M.MobY(m) + 1.0, m.z, M.Element(sk)) end   -- zásah zblízka
            damageMob(m, sk.mult, sk.magic, sk.name)
            if sk.stun and m.state ~= "dead" then m.stunT = now + sk.stun; M.Log(m.t.name .. " je omráčen.", { 1.0, 0.9, 0.5 }) end
            if sk.slow and m.state ~= "dead" then m.slowT = now + sk.slow end
        end
    end
end

-- ------------------------------------------------------------------ snímek
function M.Update(dt)
    local s = M.me
    if not s then return end
    local now = game.time()
    local px, py, pz = pos(player.body)

    -- oživení po smrti u Archivářky Lyrise
    if player.dead and M.respawnT and now > M.respawnT then
        player.dead = false
        player.Teleport(map.Start.x, map.Start.z)
        s.hp, s.mp = floor(s.maxhp * 0.5), floor(s.maxmp * 0.5)
        player.anim = nil
        player.actionT = nil
        M.respawnT = nil
        M.Log("Ozvěna znovu povstala.", { 0.6, 0.9, 1.0 })
    end

    -- regenerace mimo boj
    local inCombat = (s.lastHit and now - s.lastHit < 6) or M.auto
    M.inCombat = inCombat
    if not player.dead then
        local rate = inCombat and 0.004 or 0.03
        s.hp = min(s.maxhp, s.hp + s.maxhp * rate * dt)
        s.mp = min(s.maxmp, s.mp + s.maxmp * (inCombat and 0.012 or 0.04) * dt)
    end
    for k, b in pairs(s.buffs) do if b.until_t < now then s.buffs[k] = nil end end

    -- sesílání: pohyb ho přeruší
    if s.casting then
        local c = s.casting
        if player.manual or player.dead then
            s.casting = nil
            player.actionT = nil
            M.Log("Sesílání přerušeno.", { 0.9, 0.6, 0.5 })
        elseif now - c.start >= c.dur + (c.pushback or 0) then
            s.casting = nil
            if not c.target or c.target.state ~= "dead" then M.Execute(c.i, c.target) end
        end
    end

    -- automatický útok a doběhnutí k cíli
    local tgt = M.target
    M.moveTo = nil
    if tgt and tgt.state == "dead" then M.auto = false end
    if M.auto and tgt and not player.dead then
        local range = s.class.ranged and s.class.range or s.class.range
        local d = sqrt(dist2(px, pz, tgt.x, tgt.z))
        player.faceTarget = deg(atan(tgt.x - px, tgt.z - pz))
        if d > range then
            if not player.manual then M.moveTo = { tgt.x, tgt.z } end
        elseif not s.casting then
            if M.pendingSkill then
                local i = M.pendingSkill
                M.pendingSkill = nil
                M.UseSkill(i)
            elseif now >= M.nextSwing and not player.moving then
                M.nextSwing = now + s.class.speed
                local clip = s.class.combo[(M.combo - 1) % #s.class.combo + 1]
                M.combo = M.combo + 1
                player.Action(clip, min(0.9, s.class.speed * 0.8))
                -- zásah v polovině švihu (střela letí o chvíli déle)
                if s.class.ranged then
                    local m = tgt
                    local col = s.class.matk and { 0.4, 0.85, 1.0 } or { 1.0, 0.8, 0.5 }
                    M.pendingShot = { t = now + 0.35, m = m, col = col }
                else
                    M.pendingHit = { t = now + 0.3, m = tgt }
                end
            end
        end
    else
        player.faceTarget = nil
    end
    if M.pendingHit and now >= M.pendingHit.t then
        local h = M.pendingHit
        M.pendingHit = nil
        if h.m.state ~= "dead" then damageMob(h.m, 1, s.class.ranged and s.class.matk ~= nil) end
    end

    if M.pendingShot and now >= M.pendingShot.t then
        local sh = M.pendingShot
        M.pendingShot = nil
        if sh.m.state ~= "dead" then
            local vx, vy, vz = pos(player.view)
            fx.Bolt(vx, vy + 1.3, vz, sh.m.id, sh.col, s.class.matk and 18 or 32, function()
                if sh.m.state ~= "dead" then damageMob(sh.m, 1, s.class.matk ~= nil) end
            end, s.class.matk and 0.35 or 0.15, s.class.matk and "arcane" or "spark")
        end
    end
    fx.Update(dt, function(id) return pos(id) end)

    -- nepřátelé
    for _, m in ipairs(M.mobs) do M.UpdateMob(m, dt, now, px, pz) end

    -- čísla nad hlavami zmizí
    local keep = {}
    for _, f in ipairs(M.floats) do if now - f.t < 1.3 then keep[#keep + 1] = f end end
    M.floats = keep
end

function M.UpdateMob(m, dt, now, px, pz)
    local t = m.t
    if m.state == "dead" then
        if m.light and now - m.deadT > 1.2 then entity.set_visible(m.light, false) end   -- žár po smrti vyhasne
        if m.noRespawn then
            if now - m.deadT > 30 and not m.gone then m.gone = true; entity.set_visible(m.id, false) end
            return
        end
        local keep = (require("eryndor.professions").Skins[m.kind] and not m.skinned) and 60 or 22   -- mrtvola ke stažení
        if now - m.deadT > keep then   -- respawn na původním místě
            m.x, m.z, m.hp, m.state, m.aggro, m.skinned = m.hx, m.hz, m.maxhp, "idle", false, nil
            if m.light then entity.set_visible(m.light, true); entity.set_position(m.light, m.x, M.MobY(m) + 0.6, m.z) end
            entity.set_position(m.id, m.x, M.MobY(m), m.z)
            mobPlay(m, t.anims.idle, true, true)
        end
        return
    end
    local stunned = (m.stunT and now < m.stunT) or (m.holdT and now < m.holdT)
    local speedMul = (m.slowT and now < m.slowT) and 0.5 or 1
    local d = sqrt(dist2(px, pz, m.x, m.z))
    local home = sqrt(dist2(m.hx, m.hz, m.x, m.z))
    local moveX, moveZ, spd = 0, 0, 0
    if m.state == "idle" then
        if not player.dead and d < t.aggro then
            m.state = "chase"; m.aggro = true
            if t.anims.aggro then   -- řev: chvíli stojí, pak vyrazí
                mobPlay(m, t.anims.aggro, false, true)
                m.actionT = now + (t.aggroTime or 1.5)
                m.holdT = now + (t.aggroTime or 1.5)   -- stojí (není omráčený)
                m.yaw = deg(atan(px - m.x, pz - m.z))
            end
        end
        if now > m.wanderT then
            m.wanderT = now + 4 + random() * 6
            local a = random() * 2 * pi
            m.wx, m.wz = m.hx + cos(a) * 5, m.hz + sin(a) * 5
        end
        if m.wx then
            local dx, dz = m.wx - m.x, m.wz - m.z
            local l = sqrt(dx * dx + dz * dz)
            if l > 0.4 then moveX, moveZ, spd = dx / l, dz / l, t.walk end
        end
    elseif m.state == "chase" then
        if player.dead or home > (t.leash or 28) then
            m.state = "return"     -- leash: zpět na místo, mezitím nezranitelný a doplní život
        elseif d > t.range then
            moveX, moveZ, spd = (px - m.x) / d, (pz - m.z) / d, t.run
        else
            m.state = "attack"
            m.nextAttack = now + 0.4
        end
    elseif m.state == "attack" then
        if player.dead then m.state = "return"
        elseif d > t.range + 0.6 then m.state = "chase"
        elseif not stunned and now >= m.nextAttack then
            m.nextAttack = now + t.speed
            local clips = t.anims.attack
            mobPlay(m, clips[random(#clips)], false, true)
            m.actionT = now + (t.attackTime or 0.8)
            m.hitT = now + (t.hitDelay or 0.35)
        end
        m.yaw = deg(atan(px - m.x, pz - m.z))
    elseif m.state == "return" then
        local dx, dz = m.hx - m.x, m.hz - m.z
        local l = sqrt(dx * dx + dz * dz)
        m.hp = min(m.maxhp, m.hp + m.maxhp * 0.25 * dt)
        if l < 0.8 then m.state = "idle"; m.aggro = false; m.hp = m.maxhp
        else moveX, moveZ, spd = dx / l, dz / l, t.run end
        if M.target == m and l > 0 then M.auto = false end
    end
    if m.hitT and now >= m.hitT then
        m.hitT = nil
        if m.state == "attack" and d <= t.range + 0.8 then damagePlayer(m) end
    end
    if stunned then spd = 0 end
    spd = spd * speedMul
    if spd > 0 then
        local nx, nz = m.x + moveX * spd * dt, m.z + moveZ * spd * dt
        if water(t, nx, nz) then m.x, m.z = nx, nz
        else spd = 0; if m.state == "idle" then m.wx = nil end end   -- plavec nevyleze na břeh
        m.yaw = deg(atan(moveX, moveZ))
    end
    local my = M.MobY(m)
    entity.set_position(m.id, m.x, my, m.z)
    entity.set_rotation(m.id, 0, m.yaw, 0)
    if m.light then entity.set_position(m.light, m.x, my + 0.6, m.z) end
    if not (m.actionT and now < m.actionT) then
        if spd > 3 then mobPlay(m, t.anims.run)
        elseif spd > 0.2 then mobPlay(m, t.anims.walk)
        else mobPlay(m, t.anims.idle) end
    end
end

return M
