--!strict
--[[
	GameConfig
	Parámetros globales de la partida. Todo valor de balance o de presentación
	que pueda necesitar ajustes debe vivir aquí (o en WeaponConfig, EnemyConfig
	y UpgradeConfig), nunca repartido por los servicios.
]]

local GameConfig = {}

-- Geometría general. La forma exacta de la isla (lóbulos, mesetas, puente,
-- santuario) está en ServerScriptService/World/MapLayout.
GameConfig.Map = {
	Center = Vector3.new(0, 0, 0),
	-- Radio de referencia de la isla principal (sin el santuario flotante).
	PlayableRadius = 100,
	-- Más allá de este radio cualquier entidad está fuera de los límites.
	BoundsRadius = 175,
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
	BaseWalkSpeed = 20,
	-- Distancia a la que una gema que vuela hacia el jugador se considera recogida.
	PickupRadius = 3.5,
	-- Las gemas a menos de esta distancia empiezan a volar hacia el jugador
	-- (Imán Celeste la aumenta). Nunca supera MaxMagnetRadius.
	MagnetRadius = 11,
	MaxMagnetRadius = 30,
	-- Penalización al caer al vacío: porcentaje de la vida máxima.
	FallDamagePct = 0.2,
	-- Invulnerabilidad tras reaparecer por una caída (segundos de partida).
	FallInvulnerability = 1.5,
	-- Invulnerabilidad breve tras cada golpe: un enjambre no derrite al jugador
	-- en un instante (daño máximo ≈ golpe / HitInvulnerability por segundo).
	HitInvulnerability = 0.4,
	-- Armas con las que empieza cada partida (ids de WeaponConfig).
	StartingWeapons = { "GaleSword" },
	-- Zoom inicial de la cámara en tercera persona (studs).
	CameraStartZoom = 26,
	CameraMinZoom = 10,
	CameraMaxZoom = 52,
	CameraFieldOfView = 72,
}

--[[
	Curva de experiencia: xpToNext(n) = Base + Linear*(n-1) + Quadratic*(n-1)^2
	Nv1→2: 9, Nv2→3: 12, Nv3→4: 18, Nv4→5: 26, Nv5→6: 36, Nv6→7: 48, Nv7→8: 63 ...
	Los primeros niveles son muy rápidos (varias decisiones en el primer
	minuto) y la curva cuadrática ralentiza el ritmo a partir del minuto 3-4.
]]
GameConfig.Progression = {
	BaseXp = 9,
	LinearXp = 2.5,
	QuadraticXp = 1.1,
}

-- Aparición de enemigos (SpawnService).
GameConfig.Spawn = {
	MaxActiveEnemies = 48,
	-- El tope crece con el tiempo: 22 al empezar, +7 por minuto, hasta MaxActiveEnemies (~min 4).
	MaxActiveStart = 22,
	MaxActivePerMinute = 7,
	InitialInterval = 1.1, -- segundos entre oleadas al inicio
	MinInterval = 0.3, -- intervalo mínimo alcanzable
	IntervalMultiplierPerMinute = 0.8, -- el intervalo se multiplica por esto cada minuto
	InitialBatch = 1, -- enemigos por oleada al inicio
	BatchGrowthPerMinute = 0.5, -- enemigos extra por oleada por minuto
	MaxBatch = 6,
	OpeningWave = 4, -- enemigos que aparecen juntos al terminar el periodo de gracia
	MinRadius = 22, -- distancia mínima al jugador
	MaxRadius = 38, -- distancia máxima al jugador
	EdgeMargin = 5, -- distancia mínima al borde de la isla
	Attempts = 10, -- intentos para encontrar una posición válida por enemigo
	GracePeriod = 1.5, -- segundos sin enemigos al empezar la partida
	--[[
		Tipos de enemigo con peso según el minuto de partida:
		peso = Weight + WeightPerMinute * (minutos - FromMinute), solo si minutos >= FromMinute.
		MaxAlive limita cuántos de ese tipo puede haber a la vez.
	]]
	EnemyTypes = {
		{ Id = "VoidSlime", FromMinute = 0, Weight = 10, WeightPerMinute = 0 },
		{ Id = "BoneWanderer", FromMinute = 0.85, Weight = 2, WeightPerMinute = 1.6, MaxAlive = 16 },
		{ Id = "VoidKing", FromMinute = 2.5, Weight = 0.6, WeightPerMinute = 0.25, MaxAlive = 2 },
	},
}

--[[
	Dificultad creciente según los minutos de partida (tiempo de juego, no real):
	multiplicador = 1 + Lineal * m + Cuadrático * m^2
	Vida: x1.1 al minuto 1, x1.4 al 3, x2.0 al 5, x3.3 al 8. Compensa el aumento
	de poder del jugador a partir del minuto 4-5.
]]
GameConfig.Difficulty = {
	HealthLinear = 0.06,
	HealthQuadratic = 0.028,
	DamageLinear = 0.06,
	DamageQuadratic = 0.012,
	SpeedPerMinute = 0.03,
	MaxSpeedMultiplier = 1.35,
}

-- Experiencia y gemas (ExperienceService).
GameConfig.Experience = {
	-- 0 = las gemas no caducan (nunca se pierde experiencia por no recogerla a tiempo).
	GemLifetime = 0,
	MaxGemsPerRun = 140, -- si se supera, la más antigua se funde en la nueva (no se pierde XP)
	PickupCheckInterval = 0.1, -- frecuencia de la comprobación de proximidad
	AttractSpeed = 38, -- studs/s iniciales de una gema atraída
	AttractAcceleration = 90, -- studs/s² (acelera según se acerca)
	-- Gemas brillantes: dependen de la Suerte (mejora Fortuna Celeste).
	LuckyGemBaseChance = 0.03,
	LuckyGemChancePerLuck = 0.05,
	LuckyGemMultiplier = 3,
	MaxXpPerGrant = 1000, -- cota de seguridad por concesión
	-- Cristales de Esencia del mapa: se rompen al tocarlos y sueltan gemas.
	EssenceCrystal = {
		TouchRadius = 5,
		Gems = 5,
		XpPerGem = 2,
		RespawnTime = 50, -- segundos de partida
	},
}

-- Combate (CombatService / EnemyService).
GameConfig.Combat = {
	-- Si un arma no encuentra objetivo, vuelve a buscar tras este tiempo.
	RetargetDelay = 0.12,
	-- Frecuencia de la IA de enemigos (movimiento y ataques).
	EnemyAiInterval = 0.05,
	-- Si un enemigo se desplaza menos que esto en StuckWindow, rodea el obstáculo.
	StuckDistance = 0.6,
	StuckWindow = 0.6,
	SidestepDuration = 0.7,
	-- Aparición: el enemigo emerge y no se mueve ni ataca durante este tiempo.
	SpawnDuration = 0.55,
	-- Tras morir, el modelo permanece este tiempo (sin colisión) para la animación de muerte.
	DeathDuration = 0.8,
	-- Retroceso breve al recibir un impacto (no bloquea la IA).
	StaggerTime = 0.14,
	-- Recuperación tras atacar: se mueve más despacio.
	RecoverTime = 0.35,
	RecoverSpeedMultiplier = 0.35,
	-- Margen extra de alcance al aplicar el golpe (latencia del jugador).
	HitTolerance = 0.6,
	CritMultiplier = 2,
	-- Altura máxima de diferencia para que un golpe cuerpo a cuerpo alcance.
	MeleeVerticalReach = 6,
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
	-- Frecuencia de la regeneración de vida (Savia Vital).
	RegenInterval = 0.5,
}

-- Presentación (solo cliente).
GameConfig.Effects = {
	DamageNumberLifetime = 0.6,
	MaxDamageNumbers = 24, -- números simultáneos (los demás se omiten)
	DeathBurstParticles = 12,
	HitFlashTime = 0.09,
	LevelUpBannerTime = 1.1,
	CameraShakeTime = 0.16,
	CameraShakeStrength = 0.22,
	DamageVignetteTime = 0.3,
	UpgradeCardStagger = 0.05,
	MaxRagdolls = 6, -- esqueletos desmontándose a la vez
	-- Ritmo máximo de reproducción de la animación del tajo (no se deforma).
	MaxSlashSpeed = 1.7,
}

-- Animaciones: todas son propiedad de Roblox (creador id 1), así que pueden
-- reproducirse en cualquier experiencia. Verificadas con la API de economía.
GameConfig.Animations = {
	PlayerSlashR15 = "rbxassetid://522635514", -- "R15 Sword Slash"
	SkeletonIdle = "rbxassetid://616158929", -- "Zombie_Idle"
	SkeletonWalk = "rbxassetid://616168032", -- "Zombie_Walk"
	SkeletonRun = "rbxassetid://616163682", -- "Zombie_Run"
	SkeletonAttack = "rbxassetid://522635514", -- "R15 Sword Slash"
}

--[[
	Audio. Categorías con volumen propio (SoundGroups): Music, Ambient, Ui, Combat.
	Ids: Creator Store, cuentas oficiales con licencia para Roblox
	(ProSoundEffects 7462895450 y APMOfficial 7462718749). Cada sonido puede
	tener varias variaciones; Cooldown evita repeticiones excesivas y
	PitchJitter varía ligeramente el tono.
]]
GameConfig.Audio = {
	Volumes = { Master = 1, Music = 0.32, Ambient = 0.5, Ui = 0.7, Combat = 0.8 },
	Sounds = {
		Attack = {
			Category = "Combat",
			Ids = { 9126014020, 9126013811, 9119749145 },
			Volume = 0.35,
			PitchJitter = 0.08,
			Cooldown = 0.06,
		},
		Hit = { Category = "Combat", Ids = { 9117283360 }, Volume = 0.5, PitchJitter = 0.15, Cooldown = 0.035 },
		HitHeavy = { Category = "Combat", Ids = { 9113564874 }, Volume = 0.45, PitchJitter = 0.08, Cooldown = 0.06 },
		Crit = { Category = "Combat", Ids = { 9113513328 }, Volume = 0.5, PitchJitter = 0.06, Cooldown = 0.08 },
		Chain = { Category = "Combat", Ids = { 9125648149 }, Volume = 0.3, PitchJitter = 0.15, Cooldown = 0.08 },
		EnemyDeath = {
			Category = "Combat",
			Ids = { 9113663393, 9119990151 },
			Volume = 0.4,
			PitchJitter = 0.15,
			Cooldown = 0.05,
		},
		EnemySpawn = { Category = "Combat", Ids = { 9112872239 }, Volume = 0.18, PitchJitter = 0.2, Cooldown = 0.12 },
		EnemyWindup = { Category = "Combat", Ids = { 9125640290 }, Volume = 0.22, PitchJitter = 0.12, Cooldown = 0.15 },
		BossSlam = { Category = "Combat", Ids = { 9117982785 }, Volume = 0.55, PitchJitter = 0.05, Cooldown = 0.2 },
		PlayerHurt = { Category = "Combat", Ids = { 9118167124 }, Volume = 0.45, PitchJitter = 0.08, Cooldown = 0.15 },
		GemPickup = { Category = "Ui", Ids = { 9116394545 }, Volume = 0.22, PitchJitter = 0, Cooldown = 0.05 },
		CrystalBreak = { Category = "Combat", Ids = { 9116421827 }, Volume = 0.45, PitchJitter = 0.05, Cooldown = 0.2 },
		LevelUp = { Category = "Ui", Ids = { 9117885256 }, Volume = 0.55, PitchJitter = 0, Cooldown = 0.3 },
		UiSelect = { Category = "Ui", Ids = { 9117884499 }, Volume = 0.5, PitchJitter = 0, Cooldown = 0.1 },
		UiHover = { Category = "Ui", Ids = { 9119717523 }, Volume = 0.35, PitchJitter = 0.05, Cooldown = 0.04 },
	},
	Music = {
		-- "Crystal Forest" y "Heroic Battle" (APM Music). Se mezclan según la
		-- intensidad del combate (enemigos cercanos y minuto de partida).
		Explore = { Id = 1838990319, Volume = 0.7 },
		Combat = { Id = 1837222909, Volume = 0.75 },
		CrossfadeTime = 2.5,
		CombatEnemies = 14, -- enemigos a menos de 45 studs para intensidad máxima
	},
}

GameConfig.Debug = {
	-- Ejecuta las pruebas unitarias de ServerScriptService/Tests al iniciar en Studio.
	RunSelfTestsInStudio = true,
	-- Expone _G.SkyBonkDebug (solo en Studio) para forzar experiencia, etc.
	ExposeStudioDebugApi = true,
}

return GameConfig
