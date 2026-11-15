-- Úvodní výprava „Ozvěna“ (lore: Archivářka Lyrise, Zkažení, Kultisté Prázdnoty, Drtič popela, Stínová trhlina)
local map = require("eryndor.map")
local player = require("eryndor.player")
local combat = require("eryndor.combat")
local humans = require("eryndor.humans")
local M = { step = 0, dialog = nil }

local STEPS = {
    { title = "Valorie Harbor", goal = "Setkej se s kapitánem Aerinem v přístavu (F)", npc = "aerin" },
    { title = "Ozvěna", goal = "Promluv s Archivářkou Lyrise (F)" },
    { title = "Zkažená fauna", goal = "Zab Zkažené vlky na loukách Serpentine", kind = "wolf", need = 4 },
    { title = "Kultisté Prázdnoty", goal = "Zab Kultisty u Stínové trhliny v Crystalariu (východ)", kind = "cultist", need = 3 },
    { title = "Drtič popela", goal = "Poraz Drtiče popela u trhliny v Crystalariu", kind = "crusher", need = 1 },
    { title = "Ozvěna", goal = "Vrať se k Lyrise (F)" },
}

-- kapitán Aerin: na molu přístavu Valorie (první úkol – jako na předloze „Meet Captain Aerin“)
M.Aerin = { x = 2622, z = 2536 }
M.Location = "Valorie Harbor"

function M.Spawn()
    local a = M.Aerin
    M.aerin = humans.Spawn("aeth_heavy_m", a.x, 2.45, a.z, { yaw = 100, name = "Kapitán Aerin", helm = false })
    anim.play(M.aerin, "Idle", 0.2, true)
    M.aerinLight = _G.world.spawn("light", a.x, 5.0, a.z, { light = { color = { 1.0, 0.75, 0.45 }, intensity = 12, range = 8 } })
    local l = map.Lyrise
    M.npc = humans.Spawn("lyrise", l.x, map.HeightAt(l.x, l.z) + 0.25, l.z, { yaw = 160, name = "Archivářka Lyrise", left = "book" })
    anim.play(M.npc, "Spellcasting", 0.2, true)
    anim.speed(M.npc, 0.45)
    M.light = _G.world.spawn("light", l.x, map.HeightAt(l.x, l.z) + 2.4, l.z, { light = { color = { 0.4, 0.55, 1.0 }, intensity = 25, range = 10 } })
    M.step, M.count = 1, 0
    combat.onKill = function(m)
        local st = STEPS[M.step]
        if st and st.kind == m.kind then
            M.count = M.count + 1
            if M.count >= st.need then M.Advance() end
        end
    end
end

function M.Advance()
    M.step, M.count = M.step + 1, 0
    local st = STEPS[M.step]
    if st then combat.Log("Nový úkol: " .. st.goal, { 1.0, 0.85, 0.4 }) end
end

function M.Tracker()
    local st = STEPS[M.step]
    if not st then return { title = "Ozvěna", lines = { { text = "Aethelgard je zatím v bezpečí.", done = true } } } end
    local text = st.goal
    if st.need then text = string.format("%s: %d / %d", st.goal, M.count, st.need) end
    return { title = st.title, lines = { { text = text } } }
end

local function near(p)
    local px, _, pz = player.Pos()
    return (px - p.x) ^ 2 + (pz - p.z) ^ 2 < 4.5 * 4.5
end

function M.NearAerin() return near(M.Aerin) end

function M.NearNpc()
    return near(map.Lyrise) or M.NearAerin()
end

function M.Talk()
    if not M.NearNpc() then return end
    local close = function() M.dialog = nil end
    if M.NearAerin() then
        if M.step == 1 then
            M.dialog = { who = "Kapitán Aerin", text =
                "Vítej ve Valorii, Ozvěno. Celý přístav o tobě mluví. Od chvíle, kdy se Rozkol otevřel, nevyplouvají lodě " ..
                "daleko – na hlavním ostrově se zvířata mění a z východu táhne Umbra. Archivářka Lyrise tě čeká v základně " ..
                "Serpentine. Přejdi obloukový most z brány Valorie, nebo použij portál na náměstí.",
                options = { { label = "Vydám se k Lyrise", fn = function() M.Advance(); close() end }, { label = "Později", fn = close } } }
        else
            M.dialog = { who = "Kapitán Aerin", text = "Moře je klidné, Ozvěno. Ať tě vítr nese.", options = { { label = "Na shledanou", fn = close } } }
        end
        return
    end
    if M.step == 1 then M.Advance() end   -- k Lyrise lze jít i bez kapitána
    if M.step == 2 then
        M.dialog = { who = "Archivářka Lyrise", text =
            "Probudil ses, Ozvěno. Vítej v Aethelgardu. Na západě šumí prastaré lesy Verdant Canopy, na severu se tyčí " ..
            "ledové Frostfang Peaks, na jihu doutná sopečná Ignis Scar a na východě září Crystalarium. Řeka Serpentine je " ..
            "drží od sebe… jenže z trhliny v Crystalariu prosakuje Umbra a zvířata na loukách se mění. Zastav je. " ..
            "(Klávesa M ukáže mapu celého světa.)",
            options = { { label = "Přijímám", fn = function() M.Advance(); close() end }, { label = "Později", fn = close } } }
    elseif M.step == #STEPS then
        M.dialog = { who = "Archivářka Lyrise", text =
            "Drtič popela padl a trhlina na chvíli utichla. Ale Vakarion, Pán Rozkolu, se probouzí – cítím, jak se čas láme. " ..
            "Až budeš připraven, pošlu tě do Časového zlomu. Tam uvidíš, co se doopravdy stalo před pěti sty lety.",
            options = { { label = "Rozumím", fn = function() M.Advance(); close() end } } }
    else
        local st = STEPS[M.step]
        M.dialog = { who = "Archivářka Lyrise", text = "Hvězdy šeptají: " .. (st and st.goal or "") .. ". Vrať se, až bude hotovo.",
            options = { { label = "Jdu na to", fn = close } } }
    end
end

return M
