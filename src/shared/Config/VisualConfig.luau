--[[
	VisualConfig
	Dirección artística de SKYBONK (Fase 2.5): paletas, perfiles de aura,
	convenciones de armas, animaciones del personaje y niveles de calidad.
	Solo presentación: nada de aquí afecta al combate. Guía completa en
	docs/ART_DIRECTION.md.

	Texturas: las incluidas en el propio cliente de Roblox (rbxasset://),
	comprobadas con ContentProvider en Studio; no requieren subir assets.
]]

local VisualConfig = {}

local function particle(name: string): string
	return "rbxasset://textures/particles/" .. name .. ".dds"
end

VisualConfig.Textures = {
	Sparkle = particle("sparkles_main"),
	Fire = particle("fire_main"),
	FireSparks = particle("fire_sparks_main"),
	Smoke = particle("smoke_main"),
	Core = particle("explosion01_core_main"),
	Shockwave = particle("explosion01_shockwave_main"),
	Implosion = particle("explosion01_implosion_main"),
	Glow = particle("forcefield_glow_main"),
	Vortex = particle("forcefield_vortex_main"),
}

VisualConfig.Palette = {
	Player = Color3.fromRGB(120, 235, 255),
	PlayerCore = Color3.fromRGB(235, 252, 255),
	Danger = Color3.fromRGB(255, 70, 90),
	Void = Color3.fromRGB(132, 72, 214),
	Reward = Color3.fromRGB(255, 196, 92),
	Crit = Color3.fromRGB(255, 176, 64),
}

--[[
	Niveles de calidad. El jugador alterna con la tecla G o el botón FX.
	ParticleScale multiplica la emisión de todas las auras y ráfagas.
]]
VisualConfig.Quality = {
	High = { ParticleScale = 1, EnemyAuras = true, Ambient = true, Lights = true, Speedlines = true },
	Low = { ParticleScale = 0.35, EnemyAuras = false, Ambient = false, Lights = false, Speedlines = false },
}
VisualConfig.DefaultQuality = "High"

--[[
	Perfiles de aura. Capas (todas opcionales):
	  Rise    partículas que suben (llamas, motas)
	  Orbit   motas que giran alrededor (velocidad angular)
	  Sparks  chispas rápidas en ráfagas
	  Ring    anillo en el suelo que pulsa (Pulse = segundos por pulso)
	  Light   luz puntual (solo calidad alta y en el jugador o jefes)
	MaxDistance: más lejos de la cámara la aura se apaga (rendimiento).
]]
VisualConfig.Auras = {
	Electric = {
		Color = Color3.fromRGB(110, 200, 255),
		Accent = Color3.fromRGB(235, 250, 255),
		Radius = 2.6,
		Rise = { Texture = "Sparkle", Rate = 16, Size = 0.5, Speed = 4, Lifetime = 0.5 },
		Sparks = { Texture = "FireSparks", Rate = 22, Size = 0.35, Speed = 9, Lifetime = 0.18 },
		Ring = { Pulse = 0.9, Size = 6.5, Transparency = 0.55 },
		Light = { Brightness = 1.2, Range = 10 },
		MaxDistance = 140,
	},
	Fire = {
		Color = Color3.fromRGB(255, 100, 60),
		Accent = Color3.fromRGB(255, 210, 120),
		Radius = 2.4,
		Rise = { Texture = "Fire", Rate = 22, Size = 1.4, Speed = 6, Lifetime = 0.55 },
		Sparks = { Texture = "FireSparks", Rate = 10, Size = 0.3, Speed = 7, Lifetime = 0.5 },
		Ring = { Pulse = 1.2, Size = 6, Transparency = 0.6 },
		Light = { Brightness = 1.4, Range = 10 },
		MaxDistance = 140,
	},
	Arcane = {
		Color = Color3.fromRGB(176, 110, 255),
		Accent = Color3.fromRGB(240, 200, 255),
		Radius = 2.8,
		Rise = { Texture = "Smoke", Rate = 8, Size = 2, Speed = 1.5, Lifetime = 1.1 },
		Orbit = { Texture = "Sparkle", Rate = 12, Size = 0.45, Speed = 3, Lifetime = 1.2, Spin = 2.2 },
		Ring = { Pulse = 1.6, Size = 7, Transparency = 0.6 },
		Light = { Brightness = 1, Range = 9 },
		MaxDistance = 140,
	},
	Celestial = {
		Color = Color3.fromRGB(255, 214, 110),
		Accent = Color3.fromRGB(255, 250, 220),
		Radius = 2.8,
		Rise = { Texture = "Sparkle", Rate = 18, Size = 0.6, Speed = 3, Lifetime = 1 },
		Orbit = { Texture = "Glow", Rate = 6, Size = 0.9, Speed = 1, Lifetime = 1.4, Spin = 1.4 },
		Ring = { Pulse = 1.1, Size = 7.5, Transparency = 0.45, Double = true },
		Light = { Brightness = 1.6, Range = 12 },
		MaxDistance = 160,
	},
	Void = {
		Color = Color3.fromRGB(70, 30, 110),
		Accent = Color3.fromRGB(255, 80, 120),
		Radius = 2.6,
		Rise = { Texture = "Smoke", Rate = 14, Size = 2.4, Speed = 2, Lifetime = 0.9, Dark = true },
		Sparks = { Texture = "Sparkle", Rate = 8, Size = 0.4, Speed = 5, Lifetime = 0.4 },
		Ring = { Pulse = 0.7, Size = 6, Transparency = 0.5 },
		MaxDistance = 140,
	},
	-- Violeta y oro: contrasta con el rojo de las zonas de peligro (nunca se confunden).
	Boss = {
		Color = Color3.fromRGB(130, 70, 235),
		Accent = Color3.fromRGB(255, 205, 100),
		Radius = 5,
		Rise = { Texture = "Fire", Rate = 22, Size = 3, Speed = 7, Lifetime = 0.8 },
		Orbit = { Texture = "Sparkle", Rate = 14, Size = 0.8, Speed = 2, Lifetime = 1.2, Spin = 1.6 },
		Sparks = { Texture = "FireSparks", Rate = 12, Size = 0.5, Speed = 10, Lifetime = 0.4 },
		Ring = { Pulse = 0.8, Size = 13, Transparency = 0.72, Double = true },
		Light = { Brightness = 1.1, Range = 14 },
		MaxDistance = 220,
	},
}

-- Qué aura lleva el jugador según su build real (estadísticas del HUD).
VisualConfig.PlayerAuraRules = {
	CriticalHealthPct = 0.3, -- por debajo: aura de Vacío (vida crítica)
	ChainForElectric = 1, -- saltos de rayo para el aura Eléctrica
	CritPctForFire = 24, -- % de crítico para el aura Ígnea
	XpBonusForArcane = 20, -- % de bonus de XP (o Suerte ≥ 2) para la Arcana
	DefenseForCelestial = 2, -- regeneración o reducción ≥ 20 %
	LevelUpBurst = 2.2, -- segundos de aura Celestial al subir de nivel
	Default = "Electric", -- la Espada del Vendaval es de viento/tormenta
}

-- Animaciones del personaje: paquete «Ninja», propiedad de Roblox (creador 1).
VisualConfig.PlayerAnimations = {
	idle = { Animation1 = "rbxassetid://656117400", Animation2 = "rbxassetid://656118341" },
	walk = { WalkAnim = "rbxassetid://656121766" },
	run = { RunAnim = "rbxassetid://656118852" },
	jump = { JumpAnim = "rbxassetid://656117878" },
	fall = { FallAnim = "rbxassetid://656115606" },
}

-- Movimiento procedural del personaje (cliente, solo visual).
VisualConfig.Motion = {
	MaxLean = math.rad(14), -- inclinación máxima al girar o frenar
	LeanResponsiveness = 9,
	SpeedlineSpeed = 19, -- studs/s a partir de los que aparecen líneas de velocidad
	LandingMinFall = 18, -- velocidad vertical mínima para el polvo al aterrizar
	HitRecoil = math.rad(10),
}

-- Cámara: todos los cambios son temporales y se restauran.
VisualConfig.Camera = {
	CritFovKick = 3,
	LevelUpFovKick = 5,
	BossFovKick = 6,
	FovRecover = 0.35,
	LetterboxTime = 2.2,
}

-- Convenciones de armas (ver docs/ART_DIRECTION.md §5).
VisualConfig.Weapons = {
	GaleSword = {
		Family = "Viento",
		Blade = Color3.fromRGB(170, 245, 255),
		Edge = Color3.fromRGB(120, 235, 255),
		Guard = Color3.fromRGB(230, 196, 110),
		Slash = Color3.fromRGB(150, 240, 255),
		SlashCrit = Color3.fromRGB(255, 200, 90),
	},
}

-- Zonas del mapa: paletas propias (MapBuilder) y región aproximada (cliente:
-- pétalos, gradación de color). Center/Radius en planta.
VisualConfig.Zones = {
	Forest = {
		Center = Vector3.new(-38, 0, -58),
		Radius = 38,
		Leaf = Color3.fromRGB(255, 160, 205),
		Grass = Color3.fromRGB(110, 196, 92),
		Lantern = Color3.fromRGB(255, 170, 90),
		Tint = Color3.fromRGB(255, 240, 246),
	},
	Corrupted = {
		Center = Vector3.new(44, 0, -48),
		Radius = 34,
		Tint = Color3.fromRGB(236, 222, 255),
		Rock = Color3.fromRGB(70, 54, 86),
		Crystal = Color3.fromRGB(200, 40, 90),
		Crystal2 = Color3.fromRGB(150, 70, 255),
		Grass = Color3.fromRGB(86, 96, 92),
	},
	Celestial = {
		Center = Vector3.new(0, 2, 120),
		Radius = 26,
		Tint = Color3.fromRGB(255, 246, 228),
		Stone = Color3.fromRGB(245, 240, 228),
		Gold = Color3.fromRGB(255, 205, 110),
		Torii = Color3.fromRGB(214, 52, 52),
	},
	Ruins = {
		Center = Vector3.new(62, 7, 40),
		Radius = 24,
		Tint = Color3.fromRGB(240, 250, 255),
		Stone = Color3.fromRGB(230, 222, 204),
		Rune = Color3.fromRGB(110, 220, 255),
	},
}

-- Ciclo local de luz (solo cliente): oscila entre la tarde y el atardecer dorado.
VisualConfig.DayCycle = { From = 14.6, To = 17.5, Period = 420 }

return VisualConfig
