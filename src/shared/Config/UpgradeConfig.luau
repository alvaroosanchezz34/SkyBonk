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

-- Peso base de cada rareza. La Suerte multiplica el peso de Rare y Epic por
-- (1 + Suerte * LuckRarityBonus).
UpgradeConfig.LuckRarityBonus = 0.25

UpgradeConfig.Rarities = {
	Common = { DisplayName = "Común", Weight = 100, Color = Color3.fromRGB(176, 196, 214), Order = 1 },
	Rare = { DisplayName = "Rara", Weight = 45, Color = Color3.fromRGB(84, 170, 255), Order = 2 },
	Epic = { DisplayName = "Épica", Weight = 16, Color = Color3.fromRGB(196, 110, 255), Order = 3 },
}

local list: { Types.UpgradeDef } = {
	{
		Id = "SharpEdge",
		DisplayName = "Filo Afilado",
		Description = "+15 % de daño de las armas.",
		Rarity = "Common",
		Category = "Ataque",
		Icon = "⚔",
		MaxLevel = 8,
		Effects = { { Op = "Add", Stat = "DamagePct", Value = 0.15 } },
	},
	{
		Id = "SwiftStrike",
		DisplayName = "Golpe Veloz",
		Description = "-10 % de enfriamiento de ataque.",
		Rarity = "Common",
		Category = "Ataque",
		Icon = "⚡",
		MaxLevel = 6,
		Effects = { { Op = "Mul", Stat = "CooldownMult", Value = 0.9 } },
	},
	{
		Id = "AstralReach",
		DisplayName = "Alcance Astral",
		Description = "+15 % de alcance de las armas.",
		Rarity = "Common",
		Category = "Ataque",
		Icon = "✦",
		MaxLevel = 5,
		Effects = { { Op = "Add", Stat = "RangePct", Value = 0.15 } },
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
		Id = "HawkSteps",
		DisplayName = "Pasos del Halcón",
		Description = "+10 % de velocidad de movimiento.",
		Rarity = "Common",
		Category = "Movilidad",
		Icon = "➶",
		MaxLevel = 5,
		Effects = { { Op = "Add", Stat = "MoveSpeedPct", Value = 0.1 } },
	},
	{
		Id = "ConcentratedEssence",
		DisplayName = "Esencia Concentrada",
		Description = "+15 % de experiencia obtenida.",
		Rarity = "Rare",
		Category = "Utilidad",
		Icon = "◆",
		MaxLevel = 5,
		Effects = { { Op = "Add", Stat = "XpGainPct", Value = 0.15 } },
	},
	{
		Id = "StoneSkin",
		DisplayName = "Piel de Piedra",
		Description = "-10 % de daño recibido.",
		Rarity = "Rare",
		Category = "Defensa",
		Icon = "⛨",
		MaxLevel = 5,
		Effects = { { Op = "Mul", Stat = "DamageTakenMult", Value = 0.9 } },
	},
	{
		Id = "CelestialFortune",
		DisplayName = "Fortuna Celeste",
		Description = "+1 Suerte: más mejoras raras/épicas y más gemas brillantes (x3 XP).",
		Rarity = "Rare",
		Category = "Utilidad",
		Icon = "☘",
		MaxLevel = 5,
		Effects = { { Op = "Add", Stat = "Luck", Value = 1 } },
	},
	{
		Id = "TwinBlade",
		DisplayName = "Hoja Doble",
		Description = "+1 hoja por ataque (cada hoja busca un objetivo distinto).",
		Rarity = "Epic",
		Category = "Ataque",
		Icon = "⚔⚔",
		MaxLevel = 3,
		Requires = "WeaponAcceptsExtraProjectile",
		Effects = { { Op = "Add", Stat = "ExtraProjectiles", Value = 1 } },
	},
	{
		-- Sin habilidades activas en la Fase 1: queda fuera de las opciones
		-- seleccionables hasta que exista la mecánica (no mostramos mejoras vacías).
		Id = "ArcaneImpulse",
		DisplayName = "Impulso Arcano",
		Description = "-10 % de enfriamiento de habilidades activas.",
		Rarity = "Rare",
		Category = "Habilidad",
		Icon = "✺",
		MaxLevel = 5,
		Enabled = false,
		DisabledReason = "Requiere habilidades activas (Fase 2).",
		Effects = {},
	},
	{
		-- Comodín: completa la oferta cuando quedan menos de 3 mejoras válidas.
		Id = "SkyBlessing",
		DisplayName = "Bendición del Cielo",
		Description = "Recupera un 30 % de la vida máxima.",
		Rarity = "Common",
		Category = "Curación",
		Icon = "✚",
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
