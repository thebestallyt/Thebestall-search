-- Rundensystem: Lobby -> Countdown -> Kampf in der Arena -> Sieger -> zurueck in die Lobby.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local Services = script.Parent :: Instance
local CombatService = require(Services:WaitForChild("CombatService"))
local DataService = require(Services:WaitForChild("DataService"))
local BotService = require(Services:WaitForChild("BotService"))
local WorldBuilder = require(Services:WaitForChild("WorldBuilder"))

type Fighter = CombatService.Fighter

local RoundConfig = Config.Round

local RoundService = {}

local RoundState = Net.Event("RoundState")
local Announce = Net.Event("Announce")
local KillFeed = Net.Event("KillFeed")
local Reward = Net.Event("Reward")

local world: WorldBuilder.WorldInfo
local state = "Waiting"
local timeLeft = 0
local participants: { Fighter } = {}
local roundActive = false
local eliminatedOrder: { Fighter } = {}
local forceStart = false
local forceEnd = false
local botOnlyRound = false

-- Admin: Runde sofort starten / beenden
function RoundService.ForceStart()
	forceStart = true
end

function RoundService.ForceEnd()
	forceEnd = true
end

local function aliveParticipants(): { Fighter }
	local list = {}
	for _, f in participants do
		if f.Alive and f.Character.Parent and f.Humanoid.Health > 0 then
			table.insert(list, f)
		end
	end
	return list
end

local function snapshot(): { [string]: any }
	local fighters = {}
	for _, f in participants do
		table.insert(fighters, { Name = f.Name, Alive = f.Alive and f.Character.Parent ~= nil, IsBot = f.IsBot })
	end
	return {
		State = state,
		TimeLeft = timeLeft,
		Alive = #aliveParticipants(),
		Total = #participants,
		Fighters = fighters,
		BotOnly = botOnlyRound,
	}
end

local function broadcast()
	RoundState:FireAllClients(snapshot())
end

local function setState(newState: string, t: number?)
	state = newState
	timeLeft = t or 0
	broadcast()
end

local function announceTo(targets: { Player }?, data: { [string]: any })
	if targets then
		for _, p in targets do
			Announce:FireClient(p, data)
		end
	else
		Announce:FireAllClients(data)
	end
end

local function participantPlayers(): { Player }
	local list = {}
	for _, f in participants do
		if f.Player and f.Player.Parent then
			table.insert(list, f.Player)
		end
	end
	return list
end

local function readyPlayers(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("DataLoaded") and not player:GetAttribute("Busy") then
			local f = CombatService.GetFighterFromPlayer(player)
			if f and f.Alive and not f.InRound then
				table.insert(list, player)
			end
		end
	end
	return list
end

local function give(player: Player?, coins: number, reason: string)
	if player and player.Parent and coins > 0 then
		DataService.AddCoins(player, coins)
		Reward:FireClient(player, coins, reason)
	end
end

local function shuffled<T>(list: { T }): { T }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = math.random(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

local function sendToLobby(f: Fighter)
	CombatService.SetInRound(f, false)
	CombatService.SetFrozen(f, false)
	if f.Player then
		f.Player:SetAttribute("InRound", false)
	end
	if f.Alive and f.Character.Parent then
		local offset = Vector3.new(math.random(-4, 4), 0, math.random(-4, 4))
		f.Character:PivotTo(world.LobbySpawn + offset)
		f.Root.AssemblyLinearVelocity = Vector3.zero
		CombatService.HealFull(f)
	end
end

local function onFighterDied(victim: Fighter, killer: Fighter?)
	if not roundActive or not table.find(participants, victim) then
		-- Tod in der Lobby (z.B. Trainingspuppe) zaehlt nicht
		return
	end
	table.insert(eliminatedOrder, victim)
	local killerName = if killer then killer.Name else nil
	KillFeed:FireAllClients({
		Killer = killerName,
		Victim = victim.Name,
		KillerIsBot = killer ~= nil and killer.IsBot,
		VictimIsBot = victim.IsBot,
	})
	if victim.Player then
		local profile = DataService.Get(victim.Player)
		if profile then
			profile.Stats.Deaths += 1
			DataService.MarkDirty(victim.Player)
		end
		local place = #aliveParticipants() + 1
		Announce:FireClient(victim.Player, {
			Text = "ELIMINATED",
			Sub = (if killerName then "by " .. killerName .. "  •  " else "") .. "Place #" .. place,
			Style = "Eliminated",
			Duration = 3,
		})
		victim.Player:SetAttribute("InRound", false)
	end
	if killer and killer.Player and killer ~= victim then
		local profile = DataService.Get(killer.Player)
		if profile then
			profile.Stats.Kills += 1
			DataService.MarkDirty(killer.Player)
		end
		give(killer.Player, if victim.IsBot then Config.Rewards.BotKill else Config.Rewards.Kill, "Kill")
	end
	broadcast()
end

local function runRound(botOnly: boolean)
	participants = {}
	eliminatedOrder = {}
	botOnlyRound = botOnly
	local spawns = shuffled(world.ArenaSpawns)
	local index = 0

	local joining: { Player } = if botOnly then {} else readyPlayers()
	for _, player in joining do
		local f = CombatService.GetFighterFromPlayer(player)
		if f then
			index += 1
			local spawnCF = spawns[((index - 1) % #spawns) + 1]
			CombatService.SetFrozen(f, true)
			f.Character:PivotTo(spawnCF)
			f.Root.AssemblyLinearVelocity = Vector3.zero
			CombatService.SetInRound(f, true)
			CombatService.HealFull(f)
			player:SetAttribute("InRound", true)
			table.insert(participants, f)
		end
	end

	if RoundConfig.FillWithBots or botOnly then
		local need = if botOnly
			then RoundConfig.BotOnlyFighters
			else math.min(RoundConfig.MinFighters - #participants, RoundConfig.MaxBots)
		for _ = 1, need do
			index += 1
			local bot = BotService.SpawnArenaBot(spawns[((index - 1) % #spawns) + 1])
			if bot then
				CombatService.SetInRound(bot, true)
				CombatService.SetFrozen(bot, true)
				table.insert(participants, bot)
			end
		end
	end

	if #participants < 2 then
		for _, f in participants do
			sendToLobby(f)
		end
		BotService.ClearArenaBots()
		participants = {}
		return
	end

	roundActive = true
	local players = participantPlayers()
	if botOnly then
		for _, p in Players:GetPlayers() do
			Net.Event("Notify"):FireClient(p, {
				Text = "Bot battle in the arena! Press SPECTATE to watch – a real round starts as soon as you're ready.",
				Color = Color3.fromRGB(255, 200, 80),
				Icon = "🤖",
			})
		end
	end
	setState("Countdown", RoundConfig.CountdownTime)
	announceTo(players, { Text = "GET READY", Sub = #participants .. " fighters in the arena", Style = "Big", Duration = 1.6 })
	task.wait(1.8)
	for i = RoundConfig.CountdownTime, 1, -1 do
		timeLeft = i
		broadcast()
		announceTo(players, { Text = tostring(i), Style = "Count", Duration = 0.9 })
		task.wait(1)
	end
	for _, f in participants do
		if f.Alive then
			CombatService.SetFrozen(f, false)
		end
	end
	announceTo(players, { Text = "FIGHT!", Style = "Fight", Duration = 1.2 })

	setState("Fighting", if botOnly then RoundConfig.BotOnlyRoundTime else RoundConfig.RoundTime)
	forceEnd = false
	local elapsed = 0
	while timeLeft > 0 and not forceEnd do
		local alive = aliveParticipants()
		if #alive <= 1 then
			break
		end
		if botOnly then
			-- Ein Spieler ist bereit -> Bot-Runde abbrechen, damit er mitspielen kann
			if elapsed >= 5 and #readyPlayers() >= RoundConfig.MinRealPlayers then
				announceTo(nil, { Text = "A CHALLENGER APPEARS!", Sub = "Get ready – a new round is starting", Style = "Big", Duration = 2.5 })
				break
			end
		else
			-- Keine echten Spieler mehr uebrig -> Runde beenden
			local realAlive = false
			for _, f in alive do
				if f.Player then
					realAlive = true
					break
				end
			end
			if not realAlive then
				break
			end
		end
		elapsed += 1
		task.wait(1)
		timeLeft -= 1
		broadcast()
	end

	-- Sieger bestimmen
	local alive = aliveParticipants()
	local winner: Fighter? = nil
	if #alive == 1 then
		winner = alive[1]
	elseif #alive > 1 then
		table.sort(alive, function(a, b)
			return a.Humanoid.Health / a.Humanoid.MaxHealth > b.Humanoid.Health / b.Humanoid.MaxHealth
		end)
		local h1 = alive[1].Humanoid.Health / alive[1].Humanoid.MaxHealth
		local h2 = alive[2].Humanoid.Health / alive[2].Humanoid.MaxHealth
		if h1 > h2 then
			winner = alive[1]
		end
	end
	roundActive = false
	setState("Ended", RoundConfig.EndScreenTime)

	for _, f in participants do
		if f.Alive then
			CombatService.SetFrozen(f, true)
		end
	end

	if winner then
		local w = winner :: Fighter
		CombatService.Broadcast("Victory", { Character = w.Character })
		announceTo(nil, { Text = string.upper(w.Name) .. " WINS!", Sub = "🏆 Winner of the round", Style = "Victory", Duration = 4.5 })
		if w.Player then
			local profile = DataService.Get(w.Player)
			if profile then
				profile.Stats.Wins += 1
				DataService.MarkDirty(w.Player)
			end
			give(w.Player, Config.Rewards.Win, "Victory")
		end
	else
		announceTo(nil, { Text = "DRAW", Sub = "Nobody won this round", Style = "Big", Duration = 3.5 })
	end
	for _, f in participants do
		if f.Player and f.Player.Parent then
			local profile = DataService.Get(f.Player)
			if profile then
				profile.Stats.Rounds += 1
				DataService.MarkDirty(f.Player)
			end
			give(f.Player, Config.Rewards.Participation, "Participation")
			DataService.Push(f.Player)
		end
	end

	task.wait(if botOnly then 3 else RoundConfig.EndScreenTime)
	for _, f in participants do
		if f.Player then
			sendToLobby(f)
		end
	end
	BotService.ClearArenaBots()
	participants = {}
	botOnlyRound = false
	broadcast()
end

function RoundService.Init(info: WorldBuilder.WorldInfo)
	world = info
	CombatService.FighterDied:Connect(onFighterDied)
	Players.PlayerAdded:Connect(function(player)
		task.wait(2)
		RoundState:FireClient(player, snapshot())
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(broadcast)
	end)
end

function RoundService.Start()
	task.spawn(function()
		while true do
			local ready = readyPlayers()
			local enoughPlayers = #ready >= RoundConfig.MinRealPlayers or (forceStart and #ready > 0)
			local canBotRound = RoundConfig.BotOnlyRounds and #Players:GetPlayers() > 0
			if not enoughPlayers and not canBotRound and not forceStart then
				if state ~= "Waiting" then
					setState("Waiting")
				end
				task.wait(1)
				continue
			end
			-- Pause zwischen den Runden (bei Bot-Runden kuerzer)
			setState("Intermission", if enoughPlayers then RoundConfig.IntermissionTime else RoundConfig.BotOnlyIntermission)
			while timeLeft > 0 and not forceStart do
				task.wait(1)
				timeLeft -= 1
				-- Wird waehrend einer Bot-Pause jemand bereit -> volle Pause fuer echte Runde
				if not enoughPlayers and #readyPlayers() >= RoundConfig.MinRealPlayers then
					enoughPlayers = true
					timeLeft = math.max(timeLeft, 10)
				end
				broadcast()
			end
			forceStart = false
			local botOnly = #readyPlayers() < RoundConfig.MinRealPlayers
			if botOnly and not RoundConfig.BotOnlyRounds then
				continue
			end
			local ok, err = pcall(runRound, botOnly)
			if not ok then
				warn("[RoundService] Fehler in der Runde: " .. tostring(err))
				roundActive = false
				botOnlyRound = false
				for _, f in participants do
					if f.Player then
						pcall(sendToLobby, f)
					end
				end
				BotService.ClearArenaBots()
				participants = {}
			end
		end
	end)
end

return RoundService
