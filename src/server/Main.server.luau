-- NOVA CLASH - Server-Start
-- Startet alle Dienste in der richtigen Reihenfolge.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net")) -- erstellt alle RemoteEvents
local Config = require(Shared:WaitForChild("Config"))

local Services = (script.Parent :: Instance):WaitForChild("Services")
local DataService = require(Services:WaitForChild("DataService"))
local WorldBuilder = require(Services:WaitForChild("WorldBuilder"))
local CombatService = require(Services:WaitForChild("CombatService"))
local AbilityService = require(Services:WaitForChild("AbilityService"))
local BotService = require(Services:WaitForChild("BotService"))
local CrateService = require(Services:WaitForChild("CrateService"))
local ShopService = require(Services:WaitForChild("ShopService"))
local RoundService = require(Services:WaitForChild("RoundService"))
local AdminService = require(Services:WaitForChild("AdminService"))

local world = WorldBuilder.Build()

-- Spieler, die schon waehrend des Weltaufbaus gespawnt sind, zur Lobby bringen
for _, player in Players:GetPlayers() do
	local character = player.Character
	if character then
		character:PivotTo(world.LobbySpawn)
	end
end

DataService.Init()
CombatService.Init()
AbilityService.Init()
BotService.Init()
BotService.SpawnDummies(world.DummySpots)
CrateService.Init()
ShopService.Init()
RoundService.Init(world)
RoundService.Start()
AdminService.Init()

-- Spieler ist im Menue / Tutorial / oeffnet eine Kiste -> nimmt nicht an Runden teil
Net.Event("SetBusy").OnServerEvent:Connect(function(player, busy)
	player:SetAttribute("Busy", busy == true)
end)

-- Tutorial abgeschlossen -> einmalige Belohnung
Net.Event("TutorialDone").OnServerEvent:Connect(function(player)
	local profile = DataService.Get(player)
	if profile and not profile.TutorialDone then
		profile.TutorialDone = true
		DataService.AddCoins(player, Config.Rewards.TutorialComplete)
		Net.Event("Reward"):FireClient(player, Config.Rewards.TutorialComplete, "Tutorial complete")
		DataService.MarkDirty(player)
	end
end)

-- Ausruesten von Faehigkeiten
Net.Function("EquipAbility").OnServerInvoke = function(player, abilityId, slot)
	if type(abilityId) ~= "string" or type(slot) ~= "number" then
		return false
	end
	local f = CombatService.GetFighterFromPlayer(player)
	if f and f.InRound then
		return false, "You can't change your loadout during a round."
	end
	return DataService.Equip(player, abilityId, slot)
end

-- Neue Spieler starten "beschaeftigt" (im Startmenue), bis der Client sich meldet
Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("Busy", true)
end)
for _, player in Players:GetPlayers() do
	player:SetAttribute("Busy", true)
end

print("[NOVA CLASH] Server started.")
