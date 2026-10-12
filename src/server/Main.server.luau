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

-- Rundenteilnahme: "Busy" und "AFK" ----------------------------------------------------------
-- WICHTIG: Muss VOR WorldBuilder.Build() verbunden werden! Der Weltaufbau (Terrain) dauert einige
-- Sekunden. Frueher wurde der Status erst danach verbunden und am Ende fuer alle Spieler hart auf
-- "Busy = true" gesetzt – dabei konnte ein "nicht beschaeftigt" vom Client ueberschrieben werden.
-- Der Client meldet nur bei Aenderungen, also blieb der Spieler fuer immer von Runden ausgeschlossen.
--   Busy = im Menue / Tutorial / oeffnet eine Kiste            -> nimmt nicht an Runden teil
--   AFK  = laenger als Config.Round.AfkTimeout keine Eingabe   -> nimmt nicht an Runden teil
--          (misst der Client; kurz untaetige Spieler werden weiterhin teleportiert)

local initialised: { [Player]: boolean } = {}

local function initPlayer(player: Player)
	if initialised[player] then
		return
	end
	initialised[player] = true
	-- Neue Spieler starten "beschaeftigt" (Startmenue), bis der Client sich meldet.
	-- Nur setzen, wenn noch nichts gemeldet wurde – einen Wert vom Client NIE ueberschreiben.
	if player:GetAttribute("Busy") == nil then
		player:SetAttribute("Busy", true)
	end
	if player:GetAttribute("AFK") == nil then
		player:SetAttribute("AFK", false)
	end
end

Net.Event("SetBusy").OnServerEvent:Connect(function(player: Player, busy: any)
	if type(busy) ~= "boolean" then
		return
	end
	player:SetAttribute("Busy", busy)
end)

Net.Event("SetAFK").OnServerEvent:Connect(function(player: Player, afk: any)
	if type(afk) ~= "boolean" or player:GetAttribute("AFK") == afk then
		return
	end
	player:SetAttribute("AFK", afk)
	if afk then
		print("[AFK] " .. player.Name .. " is AFK – won't be teleported into rounds until they move again")
	else
		print("[AFK] " .. player.Name .. " is back")
	end
end)

Players.PlayerAdded:Connect(initPlayer)
Players.PlayerRemoving:Connect(function(player)
	initialised[player] = nil
end)
-- Spieler, die schon vor dem Verbinden da waren (genau einmal, dank "initialised")
for _, player in Players:GetPlayers() do
	initPlayer(player)
end

-- Welt ---------------------------------------------------------------------------------------

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

-- Sicherheitsnetz: Wer kaempft, ist nicht AFK (der Client meldet SetAFK(false) normalerweise selbst).
-- Erst nach CombatService.Init() verbinden, damit sich am Verhalten von CombatInput nichts aendert.
Net.Event("CombatInput").OnServerEvent:Connect(function(player: Player)
	if player:GetAttribute("AFK") == true then
		player:SetAttribute("AFK", false)
		print("[AFK] " .. player.Name .. " is back")
	end
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

print("[NOVA CLASH] Server started.")
