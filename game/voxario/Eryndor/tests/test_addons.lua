package.path = "game/voxario/Eryndor/Assets/Scripts/?.lua;" .. package.path
-- ukázkový doplněk SouradniceFPS: nová šablona i oprava staré kopie (formát %d s desetinným FPS padal)
local files = {}
fs = {
    exists = function(p) return files[p] ~= nil end,
    read = function(p) return files[p] end,
    write = function(p, s) files[p] = s end,
    mkdir = function() end,
}
settings = { get = function() return nil end, set = function() end }
local addons = require("eryndor.addons")
local dir = "/docs/Eryndor/AddOns"
local old = 'ui.text(sw - 20, 300, string.format("%.0f, %.0f, %.0f  ·  %d FPS", p.x, p.y, p.z, fps), {})\n-- vlastní poznámka\n'
files[dir .. "/SouradniceFPS/main.lua"] = old
addons.RepairExample(dir)
local fixed = files[dir .. "/SouradniceFPS/main.lua"]
assert(not fixed:find("%d FPS", 1, true), "broken format must be replaced")
assert(fixed:find("%.0f FPS", 1, true) and fixed:find("vlastní poznámka", 1, true), "player's other edits stay")
-- opravený formát funguje s desetinným FPS
assert(string.format("%.0f, %.0f, %.0f  ·  %.0f FPS", 1.5, 2, 3, 59.7) == "2, 2, 3  ·  60 FPS")
-- upravený doplněk (jiný text) zůstane beze změny
files[dir .. "/SouradniceFPS/main.lua"] = "print('moje')"
addons.RepairExample(dir)
assert(files[dir .. "/SouradniceFPS/main.lua"] == "print('moje')")
-- šablona pro nové hráče už %d nepoužívá
local src = io.open("game/voxario/Eryndor/Assets/Scripts/eryndor/addons.lua"):read("a")
local template = src:match("local EXAMPLE_LUA = %[%[(.-)%]%]")
assert(template and not template:find("%d FPS", 1, true))
print("Addons example: OK")
