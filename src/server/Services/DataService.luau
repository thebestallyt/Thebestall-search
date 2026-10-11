-- Speichert und laedt Spielerdaten (Muenzen, Faehigkeiten, Ausruestung, Statistiken).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Abilities = require(Shared:WaitForChild("Abilities"))
local Signal = require(Shared:WaitForChild("Signal"))
local Net = require(Shared:WaitForChild("Net"))

export type Profile = {
	Coins: number,
	Owned: { [string]: number },
	Equipped: { string },
	TutorialDone: boolean,
	FreeCrate: boolean,
	Stats: { Wins: number, Kills: number, Deaths: number, CratesOpened: number, Rounds: number },
	Purchases: { string },
	Version: number,
}

local DataService = {}
DataService.ProfileLoaded = Signal.new()

local profiles: { [Player]: Profile } = {}
local canSave: { [Player]: boolean } = {}
local dirty: { [Player]: boolean } = {}
local store: DataStore? = nil

local ProfileUpdated = Net.Event("ProfileUpdated")

local function defaultProfile(): Profile
	return {
		Coins = Config.StartingCoins,
		Owned = { [Config.StartingAbility] = 1 },
		Equipped = { Config.StartingAbility, "", "", "" },
		TutorialDone = false,
		FreeCrate = true,
		Stats = { Wins = 0, Kills = 0, Deaths = 0, CratesOpened = 0, Rounds = 0 },
		Purchases = {},
		Version = 1,
	}
end

-- Fehlende Felder (z.B. nach Updates) mit Standardwerten auffuellen
local function reconcile(data: any): Profile
	local base = defaultProfile()
	if type(data) ~= "table" then
		return base
	end
	for key, value in base do
		if data[key] == nil then
			data[key] = value
		elseif type(value) == "table" and type(data[key]) == "table" and key == "Stats" then
			for k, v in value do
				if data[key][k] == nil then
					data[key][k] = v
				end
			end
		end
	end
	-- Ungueltige Ausruestung entfernen
	for i = 1, 4 do
		local id = data.Equipped[i]
		if type(id) ~= "string" or (id ~= "" and (not Abilities.Get(id) or not data.Owned[id])) then
			data.Equipped[i] = ""
		end
	end
	return data
end

local function withRetries<T>(fn: () -> T, attempts: number): (boolean, T | string)
	local lastErr: any = nil
	for i = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		task.wait(math.min(2 ^ i, 8))
	end
	return false, tostring(lastErr)
end

local function key(player: Player): string
	return "Player_" .. player.UserId
end

-- Leaderboard in der Spielerliste
local function setupLeaderstats(player: Player, profile: Profile)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local wins = Instance.new("IntValue")
	wins.Name = "Siege"
	wins.Value = profile.Stats.Wins
	wins.Parent = folder
	local kills = Instance.new("IntValue")
	kills.Name = "Kills"
	kills.Value = profile.Stats.Kills
	kills.Parent = folder
	folder.Parent = player
end

local function updateLeaderstats(player: Player, profile: Profile)
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		return
	end
	local wins = folder:FindFirstChild("Siege") :: IntValue?
	local kills = folder:FindFirstChild("Kills") :: IntValue?
	if wins then
		wins.Value = profile.Stats.Wins
	end
	if kills then
		kills.Value = profile.Stats.Kills
	end
end

function DataService.Snapshot(player: Player): any
	local p = profiles[player]
	if not p then
		return nil
	end
	return {
		Coins = p.Coins,
		Owned = table.clone(p.Owned),
		Equipped = table.clone(p.Equipped),
		TutorialDone = p.TutorialDone,
		FreeCrate = p.FreeCrate,
		Stats = table.clone(p.Stats),
		SavingEnabled = canSave[player] == true,
	}
end

-- Schickt die aktuellen Daten an den Client
function DataService.Push(player: Player)
	local snap = DataService.Snapshot(player)
	if snap then
		ProfileUpdated:FireClient(player, snap)
		updateLeaderstats(player, profiles[player])
	end
end

function DataService.Get(player: Player): Profile?
	return profiles[player]
end

function DataService.WaitFor(player: Player, timeout: number?): Profile?
	local start = os.clock()
	while player.Parent and not profiles[player] and os.clock() - start < (timeout or 30) do
		task.wait(0.1)
	end
	return profiles[player]
end

function DataService.MarkDirty(player: Player)
	dirty[player] = true
end

function DataService.AddCoins(player: Player, amount: number)
	local p = profiles[player]
	if not p then
		return
	end
	p.Coins = math.max(0, p.Coins + math.floor(amount))
	dirty[player] = true
	DataService.Push(player)
end

function DataService.SpendCoins(player: Player, amount: number): boolean
	local p = profiles[player]
	if not p or p.Coins < amount then
		return false
	end
	p.Coins -= amount
	dirty[player] = true
	return true
end

-- Gibt true zurueck, wenn die Faehigkeit neu ist
function DataService.GrantAbility(player: Player, abilityId: string): boolean
	local p = profiles[player]
	if not p or not Abilities.Get(abilityId) then
		return false
	end
	local isNew = (p.Owned[abilityId] or 0) == 0
	p.Owned[abilityId] = (p.Owned[abilityId] or 0) + 1
	-- Neue Faehigkeiten automatisch in einen freien Slot legen
	if isNew then
		for i = 1, 4 do
			if p.Equipped[i] == "" then
				p.Equipped[i] = abilityId
				break
			end
		end
	end
	dirty[player] = true
	return isNew
end

function DataService.Equip(player: Player, abilityId: string, slot: number): boolean
	local p = profiles[player]
	if not p or slot < 1 or slot > 4 or slot % 1 ~= 0 then
		return false
	end
	if abilityId == "" then
		p.Equipped[slot] = ""
	else
		if not p.Owned[abilityId] then
			return false
		end
		-- Wenn schon in einem anderen Slot: tauschen
		for i = 1, 4 do
			if p.Equipped[i] == abilityId then
				p.Equipped[i] = p.Equipped[slot]
			end
		end
		p.Equipped[slot] = abilityId
	end
	dirty[player] = true
	DataService.Push(player)
	return true
end

function DataService.Save(player: Player)
	local p = profiles[player]
	if not p or not canSave[player] or not store then
		return
	end
	local ds = store :: DataStore
	local ok, err = withRetries(function()
		ds:UpdateAsync(key(player), function()
			return p
		end)
		return true
	end, 3)
	if ok then
		dirty[player] = false
	else
		warn("[DataService] Speichern fehlgeschlagen fuer " .. player.Name .. ": " .. tostring(err))
	end
end

local function onPlayerAdded(player: Player)
	local data: any = nil
	local loadedOk = false
	if store then
		local ds = store :: DataStore
		local ok, result = withRetries(function()
			return ds:GetAsync(key(player))
		end, if RunService:IsStudio() then 1 else 3)
		if ok then
			data = result
			loadedOk = true
		else
			warn("[DataService] Laden fehlgeschlagen fuer " .. player.Name .. ": " .. tostring(result))
		end
	end
	if not player.Parent then
		return
	end
	local profile = reconcile(data)
	profiles[player] = profile
	-- Nur speichern, wenn das Laden geklappt hat (sonst wuerden Daten ueberschrieben)
	canSave[player] = loadedOk
	setupLeaderstats(player, profile)
	player:SetAttribute("DataLoaded", true)
	DataService.Push(player)
	DataService.ProfileLoaded:Fire(player, profile)
	if store and not loadedOk and not RunService:IsStudio() then
		Net.Event("Notify"):FireClient(player, {
			Text = "Your data could not be loaded – progress will not be saved this session.",
			Color = Color3.fromRGB(255, 90, 90),
		})
	end
end

local function onPlayerRemoving(player: Player)
	DataService.Save(player)
	profiles[player] = nil
	canSave[player] = nil
	dirty[player] = nil
end

function DataService.Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStore nicht verfuegbar (in Studio: Game Settings > Security > 'Enable Studio Access to API Services'). Daten werden nicht gespeichert.")
	end

	Net.Function("GetProfile").OnServerInvoke = function(player: Player)
		DataService.WaitFor(player, 20)
		return DataService.Snapshot(player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Automatisches Speichern
	task.spawn(function()
		while true do
			task.wait(Config.AutoSaveInterval)
			for player in profiles do
				if dirty[player] then
					task.spawn(DataService.Save, player)
				end
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() and not store then
			return
		end
		local threads = 0
		for player in profiles do
			threads += 1
			task.spawn(function()
				DataService.Save(player)
				threads -= 1
			end)
		end
		local start = os.clock()
		while threads > 0 and os.clock() - start < 25 do
			task.wait(0.1)
		end
	end)
end

return DataService
