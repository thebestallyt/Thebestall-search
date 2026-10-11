-- Admin-System: Admin-Titel, Admin-Panel-Befehle und Chat-Befehle.
-- Wer Admin ist, steht in Shared/Config (Config.Admins). Der Spiel-Ersteller ist immer Admin.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Abilities = require(Shared:WaitForChild("Abilities"))

local Services = script.Parent :: Instance
local DataService = require(Services:WaitForChild("DataService"))
local CombatService = require(Services:WaitForChild("CombatService"))
local RoundService = require(Services:WaitForChild("RoundService"))
local BotService = require(Services:WaitForChild("BotService"))

local AdminService = {}

local Notify = Net.Event("Notify")
local Announce = Net.Event("Announce")
local Reward = Net.Event("Reward")

function AdminService.IsAdmin(player: Player): boolean
	if player.UserId > 0 and player.UserId == game.CreatorId then
		return true
	end
	if table.find(Config.Admins.UserIds, player.UserId) then
		return true
	end
	local name = string.lower(player.Name)
	for _, n in Config.Admins.Usernames do
		if string.lower(n) == name then
			return true
		end
	end
	return false
end

local function notify(player: Player, text: string, icon: string?)
	Notify:FireClient(player, { Text = text, Color = Color3.fromRGB(255, 210, 80), Icon = icon or "🛠️" })
end

local function filterBroadcast(player: Player, text: string): string?
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, player.UserId)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	return if ok then result else nil
end

-- Alle Befehle (Panel und Chat benutzen dieselben)
local Commands: { [string]: (Player, any) -> () } = {}

Commands.Coins = function(player, amount)
	local n = math.clamp(math.floor(tonumber(amount) or 1000), 1, 1000000)
	DataService.AddCoins(player, n)
	Reward:FireClient(player, n, "Admin")
end

Commands.UnlockAll = function(player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	for _, def in Abilities.List do
		if (profile.Owned[def.Id] or 0) == 0 then
			profile.Owned[def.Id] = 1
		end
	end
	DataService.MarkDirty(player)
	DataService.Push(player)
	notify(player, "All abilities unlocked!", "🔓")
end

Commands.StartRound = function(player)
	RoundService.ForceStart()
	notify(player, "Round is starting now!", "⚔️")
end

Commands.EndRound = function(player)
	RoundService.ForceEnd()
	notify(player, "Round ended.", "🏁")
end

Commands.ResetCooldowns = function(player)
	local f = CombatService.GetFighterFromPlayer(player)
	if f then
		CombatService.ResetCooldowns(f)
		f.NextDash = 0
	end
	notify(player, "Cooldowns reset.", "⏱️")
end

Commands.Heal = function(player)
	local f = CombatService.GetFighterFromPlayer(player)
	if f then
		CombatService.HealFull(f)
	end
end

Commands.ResetTutorial = function(player)
	local profile = DataService.Get(player)
	if profile then
		profile.TutorialDone = false
		profile.FreeCrate = true
		DataService.MarkDirty(player)
		DataService.Push(player)
		notify(player, "Tutorial and free crate reset. Rejoin to see the first-join intro again.", "🔄")
	end
end

Commands.KillBots = function(player)
	BotService.ClearArenaBots()
	notify(player, "Arena bots removed.", "🤖")
end

Commands.Announce = function(player, text)
	if type(text) ~= "string" or #text == 0 then
		return
	end
	local clean = filterBroadcast(player, string.sub(text, 1, 80))
	if clean then
		Announce:FireAllClients({ Text = clean, Sub = "📢 " .. player.DisplayName .. " (Admin)", Style = "Big", Duration = 4 })
	end
end

local CHAT_ALIASES = {
	coins = "Coins",
	unlockall = "UnlockAll",
	start = "StartRound",
	startround = "StartRound",
	["end"] = "EndRound",
	endround = "EndRound",
	cd = "ResetCooldowns",
	cooldowns = "ResetCooldowns",
	heal = "Heal",
	resettutorial = "ResetTutorial",
	killbots = "KillBots",
	announce = "Announce",
	a = "Announce",
}

local function run(player: Player, command: any, arg: any)
	if not AdminService.IsAdmin(player) then
		return
	end
	local fn = if type(command) == "string" then Commands[command] else nil
	if fn then
		local ok, err = pcall(fn, player, arg)
		if not ok then
			warn("[Admin] " .. tostring(err))
		end
	end
end

local function onChatted(player: Player, message: string)
	if string.sub(message, 1, 1) ~= "/" and string.sub(message, 1, 1) ~= ";" then
		return
	end
	local cmd, rest = string.match(string.sub(message, 2), "^(%S+)%s*(.*)$")
	if not cmd then
		return
	end
	local name = CHAT_ALIASES[string.lower(cmd)]
	if name then
		run(player, name, if rest ~= "" then rest else nil)
	end
end

local function setup(player: Player)
	if AdminService.IsAdmin(player) then
		player:SetAttribute("Admin", true)
		player:SetAttribute("Title", Config.Admins.Title)
	end
	player.Chatted:Connect(function(message)
		onChatted(player, message)
	end)
end

function AdminService.Init()
	Net.Event("AdminCommand").OnServerEvent:Connect(run)
	Players.PlayerAdded:Connect(setup)
	for _, p in Players:GetPlayers() do
		setup(p)
	end
end

return AdminService
