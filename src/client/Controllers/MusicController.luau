--[[
	MusicController
	Música de la partida en el grupo "Music": una pista de exploración y otra
	de combate que se mezclan según la intensidad (enemigos cercanos y minuto
	de partida). Se calcula 4 veces por segundo; los volúmenes se suavizan en
	cada frame para que el cambio no sea brusco. Se atenúa en la pantalla de
	mejoras y tras la derrota.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)
local Sfx = require(script.Parent.Parent.Util.Sfx)

local MusicController = {}

local MUSIC = GameConfig.Audio.Music
local player = Players.LocalPlayer
local controllers
local explore: Sound
local combat: Sound
local intensity = 0 -- 0 exploración, 1 combate
local targetIntensity = 0
local duck = 1 -- atenuación (mejoras / derrota)
local targetDuck = 1
local nextEvaluateAt = 0
local gameOver = false

local function makeTrack(name: string, id: number): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = "rbxassetid://" .. id
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = Sfx.GetGroup("Music")
	sound.Parent = Sfx.GetGroup("Music")
	return sound
end

local function evaluate()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local snapshot = controllers.HUDController.GetSnapshot()
	if root == nil or snapshot == nil then
		targetIntensity = 0
		return
	end
	local nearby = 0
	local position = root.Position
	for _, model in Workspace.ActiveEnemies:GetChildren() do
		local enemyRoot = (model :: Model).PrimaryPart
		if enemyRoot and not model:GetAttribute("Dead") and (enemyRoot.Position - position).Magnitude < 45 then
			nearby += 1
		end
	end
	local fromEnemies = math.clamp(nearby / MUSIC.CombatEnemies, 0, 1)
	local fromTime = math.clamp((snapshot.Elapsed - 20) / 160, 0, 0.6)
	targetIntensity = math.clamp(math.max(fromEnemies, fromTime), 0, 1)
	local upgrades = controllers.UpgradeController.IsOpen()
	targetDuck = if gameOver then 0.25 elseif upgrades then 0.55 else 1
end

function MusicController.Init(allControllers)
	controllers = allControllers
end

function MusicController.Start()
	explore = makeTrack("ExploreMusic", MUSIC.Explore.Id)
	combat = makeTrack("CombatMusic", MUSIC.Combat.Id)
	explore:Play()
	combat:Play()

	Net.GameOver.OnClientEvent:Connect(function()
		gameOver = true
	end)
	Net.HudUpdate.OnClientEvent:Connect(function(snapshot)
		if type(snapshot) == "table" and snapshot.Phase ~= "GameOver" then
			gameOver = false
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		if now >= nextEvaluateAt then
			nextEvaluateAt = now + 0.25
			evaluate()
		end
		local rate = dt / MUSIC.CrossfadeTime
		intensity += math.clamp(targetIntensity - intensity, -rate, rate)
		duck += math.clamp(targetDuck - duck, -dt * 2, dt * 2)
		-- Mezcla de potencia constante: no hay hueco de volumen a mitad del cambio.
		explore.Volume = MUSIC.Explore.Volume * math.cos(intensity * math.pi / 2) * duck
		combat.Volume = MUSIC.Combat.Volume * math.sin(intensity * math.pi / 2) * duck
	end)
end

return MusicController
