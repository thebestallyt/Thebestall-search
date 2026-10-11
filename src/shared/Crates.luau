--!strict
-- Kisten (Lootboxen). Gewichte bestimmen die Chance auf jede Seltenheit.

export type CrateDef = {
	Id: string,
	Name: string,
	Price: number,
	Free: boolean?,
	Hidden: boolean?,
	Order: number,
	Description: string,
	BodyColor: Color3,
	TrimColor: Color3,
	Material: EnumItem,
	Weights: { [string]: number },
}

local C = Color3.fromRGB

local defs: { CrateDef } = {
	{
		Id = "Starter",
		Name = "Starter Crate",
		Price = 0,
		Free = true,
		Hidden = true,
		Order = 0,
		Description = "A gift for new fighters – guaranteed RARE or better!",
		BodyColor = C(40, 44, 70),
		TrimColor = C(0, 230, 255),
		Material = Enum.Material.Metal,
		Weights = { Rare = 62, Epic = 30, Legendary = 8 },
	},
	{
		Id = "Basic",
		Name = "Nova Crate",
		Price = 120,
		Order = 1,
		Description = "The standard crate. With some luck, something huge is inside.",
		BodyColor = C(52, 56, 84),
		TrimColor = C(120, 200, 255),
		Material = Enum.Material.Metal,
		Weights = {
			Common = 52,
			Uncommon = 26,
			Rare = 13,
			Epic = 6,
			Legendary = 2.4,
			Mythic = 0.5,
			Divine = 0.1,
		},
	},
	{
		Id = "Premium",
		Name = "Pulsar Crate",
		Price = 400,
		Order = 2,
		Description = "Much better odds for Epic and Legendary abilities.",
		BodyColor = C(60, 30, 90),
		TrimColor = C(200, 100, 255),
		Material = Enum.Material.DiamondPlate,
		Weights = {
			Uncommon = 30,
			Rare = 34,
			Epic = 22,
			Legendary = 10,
			Mythic = 3.4,
			Divine = 0.6,
		},
	},
	{
		Id = "Cosmic",
		Name = "Cosmic Crate",
		Price = 1100,
		Order = 3,
		Description = "Only the best of the best. Your real shot at DIVINE power.",
		BodyColor = C(30, 12, 26),
		TrimColor = C(255, 190, 40),
		Material = Enum.Material.Foil,
		Weights = {
			Epic = 46,
			Legendary = 36,
			Mythic = 14,
			Divine = 4,
		},
	},
}

local Crates = {}
Crates.List = defs
Crates.ById = {} :: { [string]: CrateDef }
for _, def in defs do
	Crates.ById[def.Id] = def
end

function Crates.Get(id: string): CrateDef?
	return Crates.ById[id]
end

-- Liefert die Chancen in Prozent (fuer die Anzeige im Shop)
function Crates.GetOdds(crate: CrateDef): { [string]: number }
	local total = 0
	for _, w in crate.Weights do
		total += w
	end
	local odds = {}
	for rarity, w in crate.Weights do
		odds[rarity] = (w / total) * 100
	end
	return odds
end

return Crates
