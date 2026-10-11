--!strict
-- Seltenheitsstufen. Je hoeher "Tier", desto seltener und desto aufwendiger die Effekte.

export type Rarity = {
	Id: string,
	Name: string,
	Tier: number,
	Color: Color3,
	Glow: Color3,
	Dark: Color3,
	Gradient: ColorSequence,
}

local function seq(...: Color3): ColorSequence
	local colors = { ... }
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local keypoints = {}
	for i, c in colors do
		table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
	end
	return ColorSequence.new(keypoints)
end

local list: { Rarity } = {
	{
		Id = "Common",
		Name = "COMMON",
		Tier = 1,
		Color = Color3.fromRGB(196, 202, 214),
		Glow = Color3.fromRGB(235, 240, 255),
		Dark = Color3.fromRGB(70, 74, 86),
		Gradient = seq(Color3.fromRGB(150, 156, 170), Color3.fromRGB(230, 234, 245)),
	},
	{
		Id = "Uncommon",
		Name = "UNCOMMON",
		Tier = 2,
		Color = Color3.fromRGB(70, 232, 120),
		Glow = Color3.fromRGB(150, 255, 180),
		Dark = Color3.fromRGB(18, 80, 40),
		Gradient = seq(Color3.fromRGB(40, 170, 80), Color3.fromRGB(140, 255, 170)),
	},
	{
		Id = "Rare",
		Name = "RARE",
		Tier = 3,
		Color = Color3.fromRGB(52, 150, 255),
		Glow = Color3.fromRGB(140, 205, 255),
		Dark = Color3.fromRGB(14, 46, 110),
		Gradient = seq(Color3.fromRGB(30, 90, 230), Color3.fromRGB(100, 210, 255)),
	},
	{
		Id = "Epic",
		Name = "EPIC",
		Tier = 4,
		Color = Color3.fromRGB(176, 80, 255),
		Glow = Color3.fromRGB(215, 160, 255),
		Dark = Color3.fromRGB(56, 18, 100),
		Gradient = seq(Color3.fromRGB(120, 40, 230), Color3.fromRGB(230, 120, 255)),
	},
	{
		Id = "Legendary",
		Name = "LEGENDARY",
		Tier = 5,
		Color = Color3.fromRGB(255, 190, 40),
		Glow = Color3.fromRGB(255, 232, 140),
		Dark = Color3.fromRGB(110, 62, 6),
		Gradient = seq(Color3.fromRGB(255, 130, 20), Color3.fromRGB(255, 225, 90), Color3.fromRGB(255, 160, 30)),
	},
	{
		Id = "Mythic",
		Name = "MYTHIC",
		Tier = 6,
		Color = Color3.fromRGB(255, 45, 95),
		Glow = Color3.fromRGB(255, 140, 170),
		Dark = Color3.fromRGB(100, 6, 30),
		Gradient = seq(Color3.fromRGB(255, 20, 70), Color3.fromRGB(255, 90, 200), Color3.fromRGB(255, 30, 60)),
	},
	{
		Id = "Divine",
		Name = "DIVINE",
		Tier = 7,
		Color = Color3.fromRGB(120, 255, 245),
		Glow = Color3.fromRGB(255, 255, 255),
		Dark = Color3.fromRGB(20, 70, 90),
		Gradient = seq(
			Color3.fromRGB(255, 120, 120),
			Color3.fromRGB(255, 230, 120),
			Color3.fromRGB(120, 255, 160),
			Color3.fromRGB(110, 210, 255),
			Color3.fromRGB(220, 130, 255)
		),
	},
	{
		Id = "Exclusive",
		Name = "SINGULARITY",
		Tier = 8,
		Color = Color3.fromRGB(150, 70, 255),
		Glow = Color3.fromRGB(255, 150, 60),
		Dark = Color3.fromRGB(8, 4, 18),
		Gradient = seq(Color3.fromRGB(20, 6, 40), Color3.fromRGB(150, 60, 255), Color3.fromRGB(255, 140, 50)),
	},
}

local Rarities = {}
Rarities.List = list
Rarities.ById = {} :: { [string]: Rarity }
for _, r in list do
	Rarities.ById[r.Id] = r
end

function Rarities.Get(id: string): Rarity
	return Rarities.ById[id] or list[1]
end

function Rarities.ByTier(tier: number): Rarity
	return list[math.clamp(tier, 1, #list)]
end

return Rarities
