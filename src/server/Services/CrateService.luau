-- Kisten oeffnen: Muenzen abziehen, Seltenheit wuerfeln, Faehigkeit vergeben.
-- Das Ergebnis wird IMMER auf dem Server bestimmt – der Client spielt nur die Animation ab.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crates = require(Shared:WaitForChild("Crates"))
local Abilities = require(Shared:WaitForChild("Abilities"))
local Rarities = require(Shared:WaitForChild("Rarities"))
local Net = require(Shared:WaitForChild("Net"))

local Services = script.Parent :: Instance
local DataService = require(Services:WaitForChild("DataService"))
local CombatService = require(Services:WaitForChild("CombatService"))

local CrateService = {}

local rng = Random.new()
local lastOpen: { [Player]: number } = {}

-- Muenzen fuer doppelte Faehigkeiten
local DUPLICATE_REFUND = {
	Common = 20,
	Uncommon = 40,
	Rare = 80,
	Epic = 160,
	Legendary = 350,
	Mythic = 900,
	Divine = 2500,
}

local function rollRarity(weights: { [string]: number }): string
	local total = 0
	for _, w in weights do
		total += w
	end
	local roll = rng:NextNumber(0, total)
	-- in fester Reihenfolge (von selten nach haeufig ist egal, Hauptsache deterministisch)
	for _, rarity in Rarities.List do
		local w = weights[rarity.Id]
		if w then
			if roll <= w then
				return rarity.Id
			end
			roll -= w
		end
	end
	-- Fallback: haeufigste Stufe
	for _, rarity in Rarities.List do
		if weights[rarity.Id] then
			return rarity.Id
		end
	end
	return "Common"
end

local function pickAbility(rarityId: string): any
	local tier = Rarities.Get(rarityId).Tier
	for t = tier, 1, -1 do
		local pool = Abilities.ByRarity(Rarities.ByTier(t).Id)
		if #pool > 0 then
			return pool[rng:NextInteger(1, #pool)]
		end
	end
	return Abilities.List[1]
end

local function openCrate(player: Player, crateId: any)
	if type(crateId) ~= "string" then
		return { Ok = false, Message = "Invalid crate." }
	end
	local crate = Crates.Get(crateId)
	if not crate then
		return { Ok = false, Message = "That crate does not exist." }
	end
	local t = os.clock()
	if lastOpen[player] and t - lastOpen[player] < 1.2 then
		return { Ok = false, Message = "Not so fast!" }
	end
	local profile = DataService.Get(player)
	if not profile then
		return { Ok = false, Message = "Your data is still loading..." }
	end
	local f = CombatService.GetFighterFromPlayer(player)
	if f and f.InRound then
		return { Ok = false, Message = "You can't open crates during a round." }
	end

	if crate.Free then
		if not profile.FreeCrate then
			return { Ok = false, Message = "You already opened this crate." }
		end
		profile.FreeCrate = false
	elseif not DataService.SpendCoins(player, crate.Price) then
		return { Ok = false, Message = "Not enough coins!" }
	end
	lastOpen[player] = t

	local rarityId = rollRarity(crate.Weights)
	local def = pickAbility(rarityId)
	local isNew = DataService.GrantAbility(player, def.Id)
	local refund = 0
	if not isNew then
		refund = DUPLICATE_REFUND[def.Rarity] or 20
		profile.Coins += refund
	end
	profile.Stats.CratesOpened += 1
	DataService.MarkDirty(player)
	DataService.Push(player)

	local tier = Rarities.Get(def.Rarity).Tier
	if tier >= 5 then
		task.spawn(DataService.Save, player)
	end
	if tier >= 6 then
		-- Allen anderen Spielern Bescheid geben (nach der Animation)
		task.delay(6, function()
			local rarity = Rarities.Get(def.Rarity)
			for _, other in Players:GetPlayers() do
				if other ~= player then
					Net.Event("Notify"):FireClient(other, {
						Text = player.DisplayName .. " unboxed " .. def.Name .. " (" .. rarity.Name .. ")!",
						Color = rarity.Color,
						Icon = def.Icon,
					})
				end
			end
		end)
	end

	return {
		Ok = true,
		AbilityId = def.Id,
		Rarity = def.Rarity,
		IsNew = isNew,
		Refund = refund,
		Coins = profile.Coins,
	}
end

function CrateService.Init()
	Net.Function("OpenCrate").OnServerInvoke = openCrate
	Players.PlayerRemoving:Connect(function(player)
		lastOpen[player] = nil
	end)
end

return CrateService
