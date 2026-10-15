--!strict
--[[
	EnemyConfig
	Definición de criaturas. EnemyService usa la misma lógica para todas;
	una criatura nueva solo necesita su entrada aquí y un modelo en
	ServerStorage/EnemyModels (o un constructor en World/ModelFactory).
]]

local Types = require(script.Parent.Parent.Types)

local EnemyConfig: { [string]: Types.EnemyDef } = {
	VoidSlime = {
		Id = "VoidSlime",
		DisplayName = "Slime del Vacío",
		ModelName = "VoidSlime",
		MaxHealth = 35,
		ContactDamage = 5,
		MoveSpeed = 9, -- studs por segundo
		AttackRange = 3.6, -- distancia horizontal para golpear al jugador
		AttackCooldown = 1.0, -- segundos entre golpes del mismo slime
		XpReward = 1,
		Color = Color3.fromRGB(132, 72, 214),
	},
}

return EnemyConfig
