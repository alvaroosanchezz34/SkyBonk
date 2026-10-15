--[[
	Ejecuta las pruebas unitarias de src/server/Tests fuera de Roblox:

	    lune run tests/run.luau

	Las mismas pruebas se ejecutan en Roblox Studio al pulsar Play (Bootstrap).
]]

local process = require("@lune/process")
local Harness = require("./lib/Harness")

local harness = Harness.new()
local TestRunner = harness.require(harness.path("src/server/Tests/TestRunner.luau"))
local report = TestRunner.runFolder(harness.path("src/server/Tests"))
if report.Failed > 0 then
	process.exit(1)
end
