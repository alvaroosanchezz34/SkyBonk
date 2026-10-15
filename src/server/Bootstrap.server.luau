--[[
	Bootstrap (servidor)
	Orden de arranque:
	  1. Configuración del mundo: carpetas de runtime, mapa, iluminación,
	     grupos de colisión y plantillas de enemigos.
	  2. Init(services) de todos los servicios (inyección de dependencias).
	  3. Start() de todos los servicios.
	  4. En Studio: pruebas unitarias y API de depuración opcional.
]]

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MapBuilder = require(script.Parent.World.MapBuilder)

Players.CharacterAutoLoads = false

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- 1. Mundo ---------------------------------------------------------------
ensureFolder(workspace, "ActiveEnemies")
ensureFolder(workspace, "ExperienceOrbs")
local enemyModels = ensureFolder(ServerStorage, "EnemyModels")

local existingMap = workspace:FindFirstChild("Map")
if existingMap == nil or existingMap:FindFirstChild("Ground") == nil then
	if existingMap then
		existingMap:Destroy()
	end
	MapBuilder.build(workspace)
end
MapBuilder.applyLighting()
-- Nota: Workspace.FallenPartsDestroyHeight no se puede escribir desde scripts;
-- se fija en default.project.json (-445), por debajo de GameConfig.Map.KillY.

PhysicsService:RegisterCollisionGroup("Players")
PhysicsService:RegisterCollisionGroup("Enemies")
-- Los enemigos no empujan al jugador (evita lanzamientos físicos); el daño
-- por contacto se calcula por distancia en EnemyService.
PhysicsService:CollisionGroupSetCollidable("Players", "Enemies", false)

-- 2-3. Servicios -----------------------------------------------------------
local ServicesFolder = script.Parent.Services
local services = {
	MatchService = require(ServicesFolder.MatchService),
	LevelService = require(ServicesFolder.LevelService),
	UpgradeService = require(ServicesFolder.UpgradeService),
	EnemyService = require(ServicesFolder.EnemyService),
	SpawnService = require(ServicesFolder.SpawnService),
	ExperienceService = require(ServicesFolder.ExperienceService),
	CombatService = require(ServicesFolder.CombatService),
}
local START_ORDER = {
	"EnemyService",
	"ExperienceService",
	"SpawnService",
	"CombatService",
	"LevelService",
	"UpgradeService",
	"MatchService", -- el último: empieza a aceptar jugadores
}

services.EnemyService.EnsureTemplates(enemyModels)
for _, name in START_ORDER do
	services[name].Init(services)
end
for _, name in START_ORDER do
	services[name].Start()
end

print("[SkyBonk] Servidor listo")

-- 4. Herramientas de Studio ------------------------------------------------
if RunService:IsStudio() then
	if GameConfig.Debug.RunSelfTestsInStudio then
		task.spawn(function()
			local TestRunner = require(script.Parent.Tests.TestRunner)
			TestRunner.runFolder(script.Parent.Tests)
		end)
	end
	if GameConfig.Debug.ExposeStudioDebugApi then
		-- Uso desde la barra de comandos (vista de servidor) durante el Play:
		--   _G.SkyBonkDebug.GrantXp(30)     concede XP al primer jugador
		--   _G.SkyBonkDebug.Kill()          derrota inmediata
		local function firstRun()
			local player = Players:GetPlayers()[1]
			return player and services.MatchService.GetRun(player)
		end
		-- selene: allow(global_usage)
		_G.SkyBonkDebug = {
			GrantXp = function(amount: number)
				local run = firstRun()
				if run then
					services.LevelService.GrantExperience(run, amount)
				end
			end,
			Kill = function()
				local run = firstRun()
				if run then
					run.Humanoid.Health = 0
				end
			end,
			EnemyCount = function(): number
				local run = firstRun()
				return if run then services.EnemyService.Count(run) else 0
			end,
		}
	end
end
