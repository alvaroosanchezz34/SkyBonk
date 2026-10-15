--[[
	Sfx
	Sonidos locales definidos en GameConfig.Audio.Sounds.

	• Categorías con su SoundGroup (Music, Ambient, Ui, Combat) y volumen
	  configurable (GameConfig.Audio.Volumes, Sfx.SetVolume).
	• Variaciones: se elige un id distinto del último en cada reproducción.
	• PitchJitter: pequeñas diferencias de tono para evitar fatiga auditiva.
	• Cooldown por sonido: limita repeticiones cuando muchos eventos coinciden.
	• `Sfx.PlayAt` atenúa el volumen con la distancia a la cámara (sonidos del mundo).
	Cada variación se crea una sola vez y se reproduce con
	SoundService:PlayLocalSound, que permite solapamientos sin clonar.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local Sfx = {}

local AUDIO = GameConfig.Audio
local folder: Folder? = nil
local groups: { [string]: SoundGroup } = {}
local variants: { [string]: { Sound } } = {}
local lastVariant: { [string]: number } = {}
local lastPlayed: { [string]: number } = {}

local function getFolder(): Folder
	if folder == nil then
		local created = Instance.new("Folder")
		created.Name = "SkyBonkSounds"
		created.Parent = SoundService
		folder = created
	end
	return folder :: Folder
end

function Sfx.GetGroup(category: string): SoundGroup
	local existing = groups[category]
	if existing then
		return existing
	end
	local group = Instance.new("SoundGroup")
	group.Name = category
	group.Volume = (AUDIO.Volumes :: any)[category] or 1
	group.Parent = getFolder()
	groups[category] = group
	return group
end

function Sfx.SetVolume(category: string, volume: number)
	if category == "Master" then
		for name, group in groups do
			group.Volume = ((AUDIO.Volumes :: any)[name] or 1) * volume
		end
		return
	end
	Sfx.GetGroup(category).Volume = volume * AUDIO.Volumes.Master
end

local function getVariants(name: string): { Sound }?
	local existing = variants[name]
	if existing then
		return existing
	end
	local info = (AUDIO.Sounds :: any)[name]
	if info == nil then
		return nil
	end
	local list = {}
	for index, id in info.Ids do
		local sound = Instance.new("Sound")
		sound.Name = name .. index
		sound.SoundId = "rbxassetid://" .. id
		sound.Volume = info.Volume
		sound.SoundGroup = Sfx.GetGroup(info.Category)
		sound.Parent = getFolder()
		table.insert(list, sound)
	end
	variants[name] = list
	return list
end

--[[
	Reproduce un sonido. `pitch` multiplica la velocidad (1 = normal) y
	`volumeScale` el volumen. Devuelve false si se omitió por el enfriamiento.
]]
function Sfx.Play(name: string, pitch: number?, volumeScale: number?): boolean
	local list = getVariants(name)
	local info = (AUDIO.Sounds :: any)[name]
	if list == nil or #list == 0 then
		return false
	end
	local now = os.clock()
	if now - (lastPlayed[name] or -1) < (info.Cooldown or 0) then
		return false
	end
	lastPlayed[name] = now

	local index = 1
	if #list > 1 then
		index = math.random(1, #list - 1)
		if index >= (lastVariant[name] or 0) then
			index += 1
		end
	end
	lastVariant[name] = index
	local sound = list[index]
	local jitter = info.PitchJitter or 0
	sound.PlaybackSpeed = (pitch or 1) * (1 + (math.random() * 2 - 1) * jitter)
	sound.Volume = info.Volume * (volumeScale or 1)
	SoundService:PlayLocalSound(sound)
	return true
end

-- Sonido del mundo: más bajo cuanto más lejos de la cámara (silencio a `range` studs).
function Sfx.PlayAt(name: string, position: Vector3, pitch: number?, range: number?): boolean
	local camera = Workspace.CurrentCamera
	local maxRange = range or 90
	local scale = 1
	if camera then
		local distance = (camera.CFrame.Position - position).Magnitude
		scale = math.clamp(1 - (distance - 20) / (maxRange - 20), 0, 1)
	end
	if scale <= 0.03 then
		return false
	end
	return Sfx.Play(name, pitch, scale)
end

function Sfx.Preload(): { Instance }
	local all = {}
	for name in AUDIO.Sounds do
		for _, sound in getVariants(name) or {} do
			table.insert(all, sound)
		end
	end
	return all
end

return Sfx
