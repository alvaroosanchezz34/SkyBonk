--[[
	ClientBootstrap
	Arranca los controladores del cliente (Init -> Start) y avisa al servidor
	de que la interfaz está lista para empezar la partida.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(script.Parent.UI.Theme)

local ControllersFolder = script.Parent.Controllers
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
