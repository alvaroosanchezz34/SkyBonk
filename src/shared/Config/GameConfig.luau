--!strict
--[[
	GameConfig
	Parámetros globales de la partida. Todo valor de balance o de presentación
	que pueda necesitar ajustes debe vivir aquí (o en WeaponConfig, EnemyConfig
	y UpgradeConfig), nunca repartido por los servicios.
]]

local GameConfig = {}

-- Geometría de la isla. El centro de la isla es el origen del mundo.
GameConfig.Map = {
	Center = Vector3.new(0, 0, 0),
	-- Radio (horizontal) de la zona jugable. Más allá empieza el borde/vacío.
	PlayableRadius = 100,
	-- Radio a partir del cual cualquier entidad se considera fuera de los límites.
	BoundsRadius = 135,
	-- Altura de la superficie principal.
	SurfaceY = 0,
	PlayerSpawn = Vector3.new(0, 3, 0),
	-- Si el personaje baja de esta altura se considera caída fuera del mapa.
	KillY = -45,
	-- Semilla del generador procedural de decoración (mapa determinista).
	Seed = 7331,
}

-- Estadísticas base del jugador (antes de mejoras).
GameConfig.Player = {
	BaseMaxHealth = 100,
	BaseWalkSpeed = 18,
	-- Distancia a la que se recogen las gemas de experiencia.
	PickupRadius = 7.5,
	-- Penalización al caer al vacío: porcentaje de la vida máxima.
	FallDamagePct = 0.25,
	-- Invulnerabilidad tras reaparecer por una caída (segundos de partida).
	FallInvulnerability = 1.5,
	-- Armas con las que empieza cada partida (ids de WeaponConfig).
	StartingWeapons = { "GaleSword" },
	-- Zoom inicial de la cámara en tercera persona (studs).
	CameraStartZoom = 24,
	CameraMinZoom = 10,
	CameraMaxZoom = 48,
	CameraFieldOfView = 72,
}

-- Curva de experiencia: xpToNext(n) = Base + Linear*(n-1) + Quadratic*(n-1)^2
-- Nv1→2: 5, Nv2→3: 8, Nv3→4: 12, Nv4→5: 17, Nv5→6: 23 ...
GameConfig.Progression = {
	BaseXp = 5,
	LinearXp = 2.5,
	QuadraticXp = 0.5,
}

-- Aparición de enemigos (SpawnService).
GameConfig.Spawn = {
	MaxActiveEnemies = 35,
	InitialInterval = 1.5, -- segundos entre oleadas al inicio
	MinInterval = 0.45, -- intervalo mínimo alcanzable
	IntervalMultiplierPerMinute = 0.8, -- el intervalo se multiplica por esto cada minuto
	InitialBatch = 1, -- enemigos por oleada al inicio
	BatchGrowthPerMinute = 0.75, -- enemigos extra por oleada por minuto
	MaxBatch = 5,
	MinRadius = 30, -- distancia mínima al jugador
	MaxRadius = 50, -- distancia máxima al jugador
	EdgeMargin = 6, -- distancia mínima al borde de la isla
	Attempts = 8, -- intentos para encontrar una posición válida por enemigo
	GracePeriod = 3, -- segundos sin enemigos al empezar la partida
	EnemyTypes = { "VoidSlime" },
}

-- Dificultad creciente según los minutos de partida (tiempo de juego, no real).
GameConfig.Difficulty = {
	HealthPerMinute = 0.08, -- +20 % de vida enemiga por minuto
	DamagePerMinute = 0.1, -- +10 % de daño enemigo por minuto
	SpeedPerMinute = 0.04, -- +4 % de velocidad enemiga por minuto
	MaxSpeedMultiplier = 1.45,
}

-- Experiencia y gemas (ExperienceService).
GameConfig.Experience = {
	GemLifetime = 60, -- segundos de partida antes de desaparecer
	MaxGemsPerRun = 120, -- si se supera, se elimina la gema más antigua
	PickupCheckInterval = 0.1, -- frecuencia de la comprobación de proximidad
	-- Gemas brillantes: dependen de la Suerte (mejora Fortuna Celeste).
	LuckyGemBaseChance = 0.02,
	LuckyGemChancePerLuck = 0.05,
	LuckyGemMultiplier = 3,
	MaxXpPerGrant = 1000, -- cota de seguridad por concesión
}

-- Combate (CombatService / EnemyService).
GameConfig.Combat = {
	-- Si un arma no encuentra objetivo, vuelve a buscar tras este tiempo.
	RetargetDelay = 0.15,
	-- Frecuencia de la IA de enemigos (movimiento y ataques).
	EnemyAiInterval = 0.1,
	-- Si un enemigo se desplaza menos que esto en StuckWindow, rodea el obstáculo.
	StuckDistance = 0.6,
	StuckWindow = 0.6,
	SidestepDuration = 0.7,
}

-- Seguridad de los RemoteEvents: máximo de peticiones por ventana (segundos).
GameConfig.RateLimits = {
	ClientReady = { Max = 3, Window = 5 },
	ChooseUpgrade = { Max = 6, Window = 1 },
	RequestRestart = { Max = 2, Window = 2 },
}

GameConfig.Match = {
	-- Tiempo mínimo entre la derrota y el reinicio.
	RestartCooldown = 1.0,
	-- Tiempo tras la derrota antes de limpiar enemigos y gemas.
	CleanupDelay = 2.0,
	-- Si el cliente no avisa de que está listo, la partida empieza igualmente.
	ClientReadyTimeout = 8,
	-- Frecuencia máxima de envío del HUD al cliente.
	HudSendInterval = 0.1,
	-- Frecuencia de la comprobación de caída.
	FallCheckInterval = 0.2,
}

-- Presentación (solo cliente).
GameConfig.Effects = {
	BladeTravelTime = 0.14,
	DamageNumberLifetime = 0.7,
	DeathBurstParticles = 14,
	HitFlashTime = 0.1,
	LevelUpBannerTime = 1.4,
	CameraShakeTime = 0.18,
	CameraShakeStrength = 0.25,
	DamageVignetteTime = 0.35,
	GemFlyTime = 0.18,
	UpgradeCardStagger = 0.07,
}

-- Sonidos incluidos con el propio cliente de Roblox (rbxasset://), sin recursos
-- externos. Pueden sustituirse por ids propios desde aquí.
GameConfig.Sounds = {
	Attack = { Id = "rbxasset://sounds/swordslash.wav", Volume = 0.35 },
	Hit = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.25 },
	EnemyDeath = { Id = "rbxasset://sounds/splat.wav", Volume = 0.35 },
	GemPickup = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.25 },
	LevelUp = { Id = "rbxasset://sounds/victory.wav", Volume = 0.4 },
	UiSelect = { Id = "rbxasset://sounds/button.wav", Volume = 0.5 },
	UiHover = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.25 },
	PlayerHurt = { Id = "rbxasset://sounds/uuhhh.mp3", Volume = 0.3 },
}

GameConfig.Debug = {
	-- Ejecuta las pruebas unitarias de ServerScriptService/Tests al iniciar en Studio.
	RunSelfTestsInStudio = true,
	-- Expone _G.SkyBonkDebug (solo en Studio) para forzar experiencia, etc.
	ExposeStudioDebugApi = true,
}

return GameConfig
