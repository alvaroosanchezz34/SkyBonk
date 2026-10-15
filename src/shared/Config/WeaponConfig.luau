--!strict
--[[
	WeaponConfig
	Definición de las armas automáticas. CombatService programa los ataques
	de forma centralizada según `Pattern`; añadir un arma nueva consiste en
	añadir una entrada aquí y, si su patrón es nuevo, un manejador en
	CombatService.Patterns.
]]

local Types = require(script.Parent.Parent.Types)

local WeaponConfig: { [string]: Types.WeaponDef } = {
	GaleSword = {
		Id = "GaleSword",
		DisplayName = "Espada del Vendaval",
		Description = "Lanza hojas espectrales de viento contra el enemigo más cercano.",
		Pattern = "NearestTargets",
		Damage = 12, -- daño base por impacto
		Cooldown = 1.4, -- segundos entre ataques
		MinCooldown = 0.35, -- límite inferior tras mejoras
		Range = 28, -- alcance máximo (studs)
		Projectiles = 1, -- hojas lanzadas por ataque (cada una a un objetivo distinto)
		MaxProjectiles = 4, -- máximo admitido (limita la mejora Hoja Doble)
		TargetsPerProjectile = 1, -- enemigos que golpea cada hoja
		Color = Color3.fromRGB(120, 235, 255),
	},
}

return WeaponConfig
