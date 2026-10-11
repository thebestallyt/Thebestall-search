-- Robux-Shop: Black-Hole-Game-Pass und Muenzpakete (Developer Products).
-- IDs stehen in Shared/Config (Config.Shop). Ist eine ID 0, wird der Kauf in Studio simuliert.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local Services = script.Parent :: Instance
local DataService = require(Services:WaitForChild("DataService"))
local CombatService = require(Services:WaitForChild("CombatService"))

local ShopService = {}

local Notify = Net.Event("Notify")
local Reward = Net.Event("Reward")

local BLACK_HOLE = "BlackHole"

local function ownsBlackHole(player: Player): boolean
	local profile = DataService.Get(player)
	return profile ~= nil and (profile.Owned[BLACK_HOLE] or 0) > 0
end

local function grantBlackHole(player: Player, celebrate: boolean)
	local profile = DataService.Get(player)
	if not profile or ownsBlackHole(player) then
		return
	end
	DataService.GrantAbility(player, BLACK_HOLE)
	-- Falls alle Slots voll waren: in Slot 4 legen
	if not table.find(profile.Equipped, BLACK_HOLE) then
		profile.Equipped[4] = BLACK_HOLE
	end
	DataService.MarkDirty(player)
	DataService.Push(player)
	task.spawn(DataService.Save, player)
	if celebrate then
		local char = player.Character
		if char then
			CombatService.Broadcast("Unlock", { Character = char, Id = BLACK_HOLE })
		end
		Notify:FireClient(player, {
			Text = "BLACK HOLE unlocked! Press its slot key to unleash it.",
			Color = Color3.fromRGB(180, 110, 255),
			Icon = "🕳️",
		})
		for _, other in Players:GetPlayers() do
			if other ~= player then
				Notify:FireClient(other, {
					Text = player.DisplayName .. " unlocked the BLACK HOLE ability!",
					Color = Color3.fromRGB(180, 110, 255),
					Icon = "🕳️",
				})
			end
		end
	end
end

local function buyItem(player: Player, kind: any, index: any)
	if kind == "BlackHole" then
		if ownsBlackHole(player) then
			return { Ok = false, Message = "You already own Black Hole!" }
		end
		local id = Config.Shop.BlackHoleGamePassId
		if id == 0 then
			if RunService:IsStudio() then
				grantBlackHole(player, true)
				return { Ok = true, Granted = true, Simulated = true }
			end
			return { Ok = false, Message = "The shop is not set up yet (Game Pass ID missing)." }
		end
		MarketplaceService:PromptGamePassPurchase(player, id)
		return { Ok = true, Prompted = true }
	elseif kind == "Coins" then
		local pack = if type(index) == "number" then Config.Shop.CoinPacks[index] else nil
		if not pack then
			return { Ok = false, Message = "Unknown pack." }
		end
		if pack.ProductId == 0 then
			if RunService:IsStudio() then
				DataService.AddCoins(player, pack.Coins)
				Reward:FireClient(player, pack.Coins, "Purchase (Studio test)")
				return { Ok = true, Granted = true, Simulated = true }
			end
			return { Ok = false, Message = "This pack is not set up yet (Product ID missing)." }
		end
		MarketplaceService:PromptProductPurchase(player, pack.ProductId)
		return { Ok = true, Prompted = true }
	end
	return { Ok = false, Message = "Unknown item." }
end

local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = DataService.WaitFor(player, 15)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if table.find(profile.Purchases, info.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local pack = nil
	for _, p in Config.Shop.CoinPacks do
		if p.ProductId ~= 0 and p.ProductId == info.ProductId then
			pack = p
			break
		end
	end
	if not pack then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(profile.Purchases, info.PurchaseId)
	while #profile.Purchases > 50 do
		table.remove(profile.Purchases, 1)
	end
	DataService.AddCoins(player, pack.Coins)
	DataService.Save(player)
	Reward:FireClient(player, pack.Coins, "Thanks for your purchase!")
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function ShopService.Init()
	Net.Function("BuyItem").OnServerInvoke = buyItem
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased and passId == Config.Shop.BlackHoleGamePassId and passId ~= 0 then
			grantBlackHole(player, true)
		end
	end)

	-- Game Pass beim Beitreten pruefen (z.B. auf der Website gekauft)
	DataService.ProfileLoaded:Connect(function(player: Player)
		local id = Config.Shop.BlackHoleGamePassId
		if id == 0 then
			return
		end
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
		end)
		if ok and owns then
			grantBlackHole(player, false)
		end
	end)
end

return ShopService
