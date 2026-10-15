--[[
	Sfx
	Reproducción de sonidos locales definidos en GameConfig.Sounds. Cada
	sonido se crea una sola vez y se reproduce con SoundService:PlayLocalSound,
	que permite solapamientos sin clonar instancias.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local Sfx = {}

local sounds: { [string]: Sound } = {}
local folder: Folder? = nil

local function getFolder(): Folder
	if folder == nil then
		local created = Instance.new("Folder")
		created.Name = "SkyBonkSounds"
		created.Parent = SoundService
		folder = created
	end
	return folder :: Folder
end

local function getSound(name: string): Sound?
	local existing = sounds[name]
	if existing then
		return existing
	end
	local info = (GameConfig.Sounds :: any)[name]
	if info == nil then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = info.Id
	sound.Volume = info.Volume
	sound.Parent = getFolder()
	sounds[name] = sound
	return sound
end

-- `pitch` modifica la velocidad de reproducción (1 = normal).
function Sfx.Play(name: string, pitch: number?)
	local sound = getSound(name)
	if sound == nil then
		return
	end
	sound.PlaybackSpeed = pitch or 1
	SoundService:PlayLocalSound(sound)
end

function Sfx.Preload()
	for name in GameConfig.Sounds do
		getSound(name)
	end
end

return Sfx
