--!strict
--[[
	UpgradeConfig
	Catálogo de mejoras. El cliente solo envía el `Id` de la opción elegida;
	el servidor aplica `Effects` mediante StatSheet.applyEffects.

	Campos:
	  Id          identificador estable (nunca cambiar una vez publicado)
	  Rarity      Common/Rare/Epic -> peso base en Rarities
	  MaxLevel    veces que puede elegirse (nil = ilimitado)
	  Requires    requisito con nombre evaluado en UpgradeLogic.Requirements
	  Enabled     false -> nunca aparece (efecto aún sin mecánica real)
	  IsFallback  solo se ofrece cuando no hay suficientes opciones válidas
]]

local Types = require(script.Parent.Parent.Types)

local UpgradeConfig = {}

UpgradeConfig.OfferSize = 3

-- Hasta este nivel, cada oferta incluye al menos una mejora de esta categoría:
-- el jugador nota enseguida un aumento de poder, sin depender de la suerte.
UpgradeConfig.EarlyGuarantee = { Category = "Ataque", UntilLevel = 4 }

-- Peso base de cada rareza. La Suerte multiplica el peso de Rare y Epic por
-- (1 + Suerte * LuckRarityBonus).
UpgradeConfig.LuckRarityBonus = 0.25

UpgradeConfig.Rarities = {
	Common = { DisplayName = "Común", Weight = 100, Color = Color3.fromRGB(176, 196, 214), Order = 1 },
	Rare = { DisplayName = "Rara", Weight = 45, Color = Color3.fromRGB(84, 170, 255), Order = 2 },
	Epic = { DisplayName = "Épica", Weight = 16, Color = Color3.fromRGB(196, 110, 255), Order = 3 },
}

-- Categorías: color e icono comunes en las cartas (se reconocen de un vistazo).
UpgradeConfig.Categories = {
	Ataque = { Color = Color3.fromRGB(255, 120, 90), Icon = "⚔" },
	Defensa = { Color = Color3.fromRGB(120, 210, 140), Icon = "🛡" },
	Movilidad = { Color = Color3.fromRGB(120, 200, 255), Icon = "💨" },
	Experiencia = { Color = Color3.fromRGB(190, 140, 255), Icon = "💎" },
	["Curación"] = { Color = Color3.fromRGB(255, 220, 120), Icon = "💖" },
	Habilidad = { Color = Color3.fromRGB(200, 200, 200), Icon = "✨" },
}

local list: { Types.UpgradeDef } = {
	{
		Id = "SharpEdge",
		DisplayName = "Filo Afilado",
		Description = "+20 % de daño de las armas.",
		Rarity = "Common",
		Category = "Ataque",
		Icon = "🗡",
		MaxLevel = 8,
		Effects = { { Op = "Add", Stat = "DamagePct", Value = 0.2 } },
	},
	{
		Id = "SwiftStrike",
		DisplayName = "Golpe Veloz",
		Description = "-12 % de tiempo entre tajos.",
		Rarity = "Common",
		Category = "Ataque",
		Icon = "⚡",
		MaxLevel = 6,
		Effects = { { Op = "Mul", Stat = "CooldownMult", Value = 0.88 } },
	},
	{
		Id = "AstralReach",
		DisplayName = "Alcance Astral",
		Description = "+20 % de alcance: las hojas buscan enemigos más lejanos.",
		Rarity = "Common",
		Category = "Ataque",
		Icon = "🌠",
		MaxLevel = 5,
		Effects = { { Op = "Add", Stat = "RangePct", Value = 0.2 } },
	},
	{
		Id = "KeenStrike",
		DisplayName = "Golpe Certero",
		Description = "+12 % de probabilidad de crítico (daño x2).",
		Rarity = "Common",
		Category = "Ataque",
		Icon = "💥",
		MaxLevel = 5,
		Effects = { { Op = "Add", Stat = "CritChance", Value = 0.12 } },
	},
	{
		Id = "TwinBlade",
		DisplayName = "Hoja Doble",
		Description = "+1 hoja por tajo (cada hoja busca un enemigo distinto).",
		Rarity = "Rare",
		Category = "Ataque",
		Icon = "⚔",
		MaxLevel = 4,
		Weight = 2.2, -- más hojas es la mejora más vistosa: aparece a menudo
		Requires = "WeaponAcceptsExtraProjectile",
		Effects = { { Op = "Add", Stat = "ExtraProjectiles", Value = 1 } },
	},
	{
		Id = "StormEdge",
		DisplayName = "Filo de Tormenta",
		Description = "Cada hoja salta con un rayo a +1 enemigo cercano.",
		Rarity = "Rare",
		Category = "Ataque",
		Icon = "🌩",
		MaxLevel = 3,
		Weight = 1.6,
		Requires = "WeaponAcceptsExtraChain",
		Effects = { { Op = "Add", Stat = "ExtraChain", Value = 1 } },
	},
	{
		Id = "BasaltHeart",
		DisplayName = "Corazón de Basalto",
		Description = "+20 % de vida máxima (y te cura esa cantidad).",
		Rarity = "Common",
		Category = "Defensa",
		Icon = "❤",
		MaxLevel = 5,
		Effects = { { Op = "Add", Stat = "MaxHealthPct", Value = 0.2 } },
	},
	{
		Id = "StoneSkin",
		DisplayName = "Piel de Piedra",
		Description = "-10 % de daño recibido.",
		Rarity = "Rare",
		Category = "Defensa",
		Icon = "🪨",
		MaxLevel = 5,
		Effects = { { Op = "Mul", Stat = "DamageTakenMult", Value = 0.9 } },
	},
	{
		Id = "VitalSap",
		DisplayName = "Savia Vital",
		Description = "Regeneras 1 punto de vida por segundo.",
		Rarity = "Rare",
		Category = "Defensa",
		Icon = "🌿",
		MaxLevel = 4,
		Effects = { { Op = "Add", Stat = "HealthRegen", Value = 1 } },
	},
	{
		Id = "HawkSteps",
		DisplayName = "Pasos del Halcón",
		Description = "+12 % de velocidad de movimiento.",
		Rarity = "Common",
		Category = "Movilidad",
		Icon = "🦅",
		MaxLevel = 5,
		Effects = { { Op = "Add", Stat = "MoveSpeedPct", Value = 0.12 } },
	},
	{
		Id = "CelestialMagnet",
		DisplayName = "Imán Celeste",
		Description = "+35 % de radio de atracción de las gemas.",
		Rarity = "Common",
		Category = "Experiencia",
		Icon = "🧲",
		MaxLevel = 4,
		Effects = { { Op = "Add", Stat = "MagnetPct", Value = 0.35 } },
	},
	{
		Id = "ConcentratedEssence",
		DisplayName = "Esencia Concentrada",
		Description = "+20 % de experiencia obtenida.",
		Rarity = "Rare",
		Category = "Experiencia",
		Icon = "💎",
		MaxLevel = 5,
		Effects = { { Op = "Add", Stat = "XpGainPct", Value = 0.2 } },
	},
	{
		Id = "CelestialFortune",
		DisplayName = "Fortuna Celeste",
		Description = "+1 Suerte: más mejoras raras/épicas y más gemas doradas (x3 XP).",
		Rarity = "Rare",
		Category = "Experiencia",
		Icon = "🍀",
		MaxLevel = 5,
		Effects = { { Op = "Add", Stat = "Luck", Value = 1 } },
	},
	{
		-- Sin habilidades activas todavía: queda fuera de las opciones
		-- seleccionables hasta que exista la mecánica (no mostramos mejoras vacías).
		Id = "ArcaneImpulse",
		DisplayName = "Impulso Arcano",
		Description = "-10 % de enfriamiento de habilidades activas.",
		Rarity = "Rare",
		Category = "Habilidad",
		Icon = "✨",
		MaxLevel = 5,
		Enabled = false,
		DisabledReason = "Requiere habilidades activas (fase posterior).",
		Effects = {},
	},
	{
		-- Comodín: completa la oferta cuando quedan menos de 3 mejoras válidas.
		Id = "SkyBlessing",
		DisplayName = "Bendición del Cielo",
		Description = "Recupera un 30 % de la vida máxima.",
		Rarity = "Common",
		Category = "Curación",
		Icon = "💖",
		IsFallback = true,
		Effects = { { Op = "HealPct", Value = 0.3 } },
	},
}

UpgradeConfig.List = list

local byId: { [string]: Types.UpgradeDef } = {}
for _, def in list do
	assert(byId[def.Id] == nil, "Id de mejora duplicado: " .. def.Id)
	byId[def.Id] = def
end
UpgradeConfig.ById = byId

return UpgradeConfig
