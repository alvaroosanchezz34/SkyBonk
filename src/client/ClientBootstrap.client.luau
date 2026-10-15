--[[
	ClientBootstrap
	Arranca los controladores del cliente (Init -> Start) y avisa al servidor
	de que la interfaz está lista para empezar la partida.
]]

-- Espera a que termine la replicación inicial y a que Roblox copie el
-- contenido de StarterPlayerScripts a PlayerScripts: este script puede
-- ejecutarse antes de que existan sus carpetas hermanas.
if not game:IsLoaded() then
	game.Loaded:Wait()
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local root = script.Parent

local function waitFor(parent: Instance, path: { string }): Instance
	local current = parent
	for _, name in path do
		current = current:WaitForChild(name)
	end
	return current
end

local REQUIRED_CLIENT_MODULES = {
	{ "UI", "Theme" },
	{ "Util", "Sfx" },
	{ "Controllers", "InputController" },
	{ "Controllers", "CameraController" },
	{ "Controllers", "HUDController" },
	{ "Controllers", "UpgradeController" },
	{ "Controllers", "GameOverController" },
	{ "Controllers", "CombatEffectsController" },
}
for _, path in REQUIRED_CLIENT_MODULES do
	waitFor(root, path)
end
local Shared = ReplicatedStorage:WaitForChild("Shared")
for _, path in { { "Net" }, { "Signal" }, { "Types" }, { "Progression" }, { "Remotes" }, { "Config", "GameConfig" }, { "Config", "WeaponConfig" }, { "Config", "EnemyConfig" }, { "Config", "UpgradeConfig" } } do
	waitFor(Shared, path)
end

local Net = require(Shared.Net)
local Theme = require(root.UI.Theme)

local ControllersFolder = root.Controllers
local controllers = {
	InputController = require(ControllersFolder.InputController),
	CameraController = require(ControllersFolder.CameraController),
	HUDController = require(ControllersFolder.HUDController),
	UpgradeController = require(ControllersFolder.UpgradeController),
	GameOverController = require(ControllersFolder.GameOverController),
	CombatEffectsController = require(ControllersFolder.CombatEffectsController),
}
local START_ORDER = {
	"InputController",
	"CameraController",
	"HUDController",
	"UpgradeController",
	"GameOverController",
	"CombatEffectsController",
}

Theme.StartAutoScale()
for _, name in START_ORDER do
	controllers[name].Init(controllers)
end
for _, name in START_ORDER do
	local ok, err = pcall(controllers[name].Start)
	if not ok then
		warn("[SkyBonk] Error al iniciar", name, err)
	end
end

Net.ClientReady:FireServer()
