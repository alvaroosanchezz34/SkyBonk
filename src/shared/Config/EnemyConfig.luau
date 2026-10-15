--!strict
--[[
	EnemyConfig
	Definición de criaturas. EnemyService usa la misma IA para todas
	(aparición → persecución → anticipación → ataque → recuperación); cada
	criatura solo cambia sus números, su tipo de ataque y su modelo
	(ServerStorage/EnemyModels, construido por World/ModelFactory).

	La anticipación (AttackWindup) es el tiempo que el jugador ve la señal
	antes de que el servidor aplique el daño: los ataques se pueden esquivar.
]]

local Types = require(script.Parent.Parent.Types)

local EnemyConfig: { [string]: Types.EnemyDef } = {
	VoidSlime = {
		Id = "VoidSlime",
		DisplayName = "Slime del Vacío",
		ModelName = "VoidSlime",
		Rig = "Slime",
		Scale = 1,
		MaxHealth = 13, -- 1 golpe al empezar; 2 golpes hacia el minuto 1,7 si no se mejora el daño
		ContactDamage = 4,
		MoveSpeed = 12, -- velocidad máxima del salto; la media ronda el 75 %
		AttackKind = "Lunge",
		AttackRange = 5.5,
		HitRange = 4.2,
		AttackWindup = 0.4,
		AttackCooldown = 1.35,
		Poise = false,
		Knockback = 22,
		HopFrequency = 1.9,
		XpReward = 1,
		Color = Color3.fromRGB(132, 72, 214),
	},
	BoneWanderer = {
		Id = "BoneWanderer",
		DisplayName = "Hueso Errante",
		ModelName = "BoneWanderer",
		Rig = "Skeleton",
		Scale = 1.15,
		MaxHealth = 55,
		ContactDamage = 9,
		MoveSpeed = 10.5,
		AttackKind = "Melee",
		AttackRange = 5.5,
		HitRange = 5.8,
		AttackWindup = 0.5,
		AttackCooldown = 1.5,
		Poise = false,
		Knockback = 12,
		HopFrequency = nil,
		XpReward = 3,
		Color = Color3.fromRGB(214, 196, 150),
	},
	VoidKing = {
		Id = "VoidKing",
		DisplayName = "Rey Slime del Vacío",
		ModelName = "VoidKing",
		Rig = "Slime",
		Scale = 2.1,
		MaxHealth = 240,
		ContactDamage = 18,
		MoveSpeed = 8,
		AttackKind = "Slam",
		AttackRange = 8,
		HitRange = 10, -- radio del golpe en área alrededor del rey
		AttackWindup = 0.95,
		AttackCooldown = 2.4,
		Poise = true,
		Knockback = 4,
		HopFrequency = 1.1,
		XpReward = 15,
		Color = Color3.fromRGB(196, 54, 120),
	},
}

return EnemyConfig
