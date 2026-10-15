--!strict
--[[
	WeaponConfig
	Definición de las armas automáticas. CombatService programa los ataques
	de forma centralizada según `Pattern`; añadir un arma nueva consiste en
	añadir una entrada aquí y, si su patrón es nuevo, un manejador en
	CombatService.Patterns.

	Ritmo (Fase 2): 15 de daño contra slimes de 13 de vida = 1 golpe al
	empezar; la dificultad los lleva a 2 golpes hacia el minuto 1,7, y la
	primera mejora de daño vuelve a dejarlos en 1 golpe (salto de poder visible). El impacto ocurre cuando la
	hoja visual llega (anticipación + distancia / velocidad), no al lanzarla.
]]

local Types = require(script.Parent.Parent.Types)

local WeaponConfig: { [string]: Types.WeaponDef } = {
	GaleSword = {
		Id = "GaleSword",
		DisplayName = "Espada del Vendaval",
		Description = "Cada tajo lanza hojas espectrales de viento contra los enemigos más cercanos.",
		Pattern = "NearestTargets",
		Damage = 15, -- daño base por impacto
		Cooldown = 1.0, -- segundos entre tajos
		MinCooldown = 0.3, -- límite inferior tras mejoras
		Range = 30, -- alcance máximo (studs)
		Projectiles = 1, -- hojas por tajo (cada una a un objetivo distinto)
		MaxProjectiles = 5, -- máximo admitido (limita la mejora Hoja Doble)
		TargetsPerProjectile = 1, -- enemigos que golpea cada hoja (Filo de Tormenta añade saltos)
		MaxTargetsPerProjectile = 4,
		ProjectileSpeed = 140,
		WindupTime = 0.1,
		ChainRange = 11,
		Color = Color3.fromRGB(120, 235, 255),
	},
}

return WeaponConfig
