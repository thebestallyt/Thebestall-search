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
local spawnOf: { [Fighter]: CFrame } = {} -- Startpunkt jedes Spielers in der aktuellen Runde

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

-- Warum kann ein Spieler gerade NICHT in eine Runde? (nil = bereit)
-- Kurz untaetige Spieler sind bereit – erst wenn der Client "AFK" meldet (Config.Round.AfkTimeout), nicht mehr.
local function notReadyReason(player: Player): string?
	if not player:GetAttribute("DataLoaded") then
		return "data not loaded"
	end
	if player:GetAttribute("Busy") then
		return "busy (menu/tutorial/crate)"
	end
	if player:GetAttribute("AFK") then
		return "AFK"
	end
	if not player.Character then
		return "no character"
	end
	local f = CombatService.GetFighterFromPlayer(player)
	if not f then
		return "no character (still loading)"
	end
	if not f.Alive then
		return "dead (respawning)"
	end
	if f.InRound then
		return "still in round"
	end
	return nil
end

local function readyPlayers(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if notReadyReason(player) == nil then
			table.insert(list, player)
		end
	end
	return list
end

-- Diagnose fuer das Output-Fenster: eine Zeile pro Spieler, der NICHT in die Runde kommt
local function logNotJoining(player: Player, reason: string)
	print("[Rounds] " .. player.Name .. " not joining: " .. reason)
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
	if not table.find(participants, victim) then
		-- Tod in der Lobby (z.B. Trainingspuppe) zaehlt nicht
		return
	end
	-- Spieler ist raus: Status sofort zuruecksetzen – auch wenn er vor dem Kampfstart oder
	-- waehrend der Siegeranzeige stirbt (sonst bliebe "InRound" bis zum Rundenende haengen)
	if victim.Player then
		victim.Player:SetAttribute("InRound", false)
	end
	if not roundActive then
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

-- Falls ein Spieler nach dem Teleport wieder weggezogen wurde (z.B. von einer noch laufenden
-- Faehigkeit aus der Lobby), vor dem Kampfstart zurueck an seinen Startpunkt setzen.
-- Im Countdown sind alle eingefroren – wer weit weg vom Startpunkt ist, gehoert nicht dorthin.
local function ensureAtSpawns()
	for _, f in participants do
		local spawnCF = spawnOf[f]
		if f.Player and spawnCF and f.Alive and f.Character.Parent and (f.Root.Position - spawnCF.Position).Magnitude > 25 then
			f.Character:PivotTo(spawnCF)
			f.Root.AssemblyLinearVelocity = Vector3.zero
		end
	end
end

-- Runde sauber abbrechen (Fehler / zu wenige Kaempfer): alle Spieler zurueck, Bots weg
local function abortRound()
	roundActive = false
	botOnlyRound = false
	for _, f in participants do
		if f.Player then
			pcall(sendToLobby, f)
		end
	end
	pcall(BotService.ClearArenaBots)
	participants = {}
	spawnOf = {}
end

-- Sicherheitsnetz nach jeder Runde: Kein Spieler darf als "InRound"/"Frozen" haengen bleiben,
-- sonst wuerde er nie wieder in eine Runde teleportiert (readyPlayers verlangt "nicht InRound").
local function releaseStragglers()
	for _, player in Players:GetPlayers() do
		local f = CombatService.GetFighterFromPlayer(player)
		if f and (f.InRound or f.Frozen) then
			warn("[Rounds] " .. player.Name .. " was still marked as in-round/frozen after the round – sent back to the lobby")
			pcall(sendToLobby, f)
		end
		if player:GetAttribute("InRound") then
			player:SetAttribute("InRound", false)
		end
	end
end

local function runRound(botOnly: boolean)
	participants = {}
	eliminatedOrder = {}
	spawnOf = {}
	botOnlyRound = botOnly
	-- Ein "Runde beenden" aus der Pause davor gilt nicht fuer diese Runde
	forceEnd = false
	local spawns = shuffled(world.ArenaSpawns)
	local function spawnAt(index: number): CFrame
		return spawns[((index - 1) % #spawns) + 1]
	end

	-- 1) Wer macht mit? Alle anderen bekommen eine Zeile im Output (mit Grund).
	local joining: { Player } = if botOnly then {} else readyPlayers()
	for _, player in Players:GetPlayers() do
		if not table.find(joining, player) then
			logNotJoining(player, notReadyReason(player) or "not enough ready players (bot-only round)")
		end
	end

	-- 2) Zuerst die Bots erzeugen (das dauert etwas), damit echte Spieler nicht so lange
	--    eingefroren in der Arena warten muessen. Spieler bekommen die ersten Startpunkte.
	local bots: { Fighter } = {}
	if RoundConfig.FillWithBots or botOnly then
		local need = if botOnly
			then RoundConfig.BotOnlyFighters
			else math.min(RoundConfig.MinFighters - #joining, RoundConfig.MaxBots)
		for i = 1, need do
			local bot = BotService.SpawnArenaBot(spawnAt(#joining + i))
			if bot then
				CombatService.SetInRound(bot, true)
				CombatService.SetFrozen(bot, true)
				table.insert(bots, bot)
			end
		end
	end

	-- 3) Spieler in die Arena. Nochmal pruefen: Waehrend die Bots erzeugt wurden, kann jemand
	--    gestorben, gegangen oder beschaeftigt geworden sein.
	for i, player in joining do
		local reason = if player.Parent then notReadyReason(player) else "left the game"
		local f = CombatService.GetFighterFromPlayer(player)
		if reason or not f then
			logNotJoining(player, reason or "no character")
			continue
		end
		local fighter = f :: Fighter
		local spawnCF = spawnAt(i)
		-- Zuerst eintragen, dann Status setzen: so raeumt ein Fehler ihn garantiert wieder auf
		table.insert(participants, fighter)
		spawnOf[fighter] = spawnCF
		player:SetAttribute("InRound", true)
		CombatService.SetInRound(fighter, true)
		CombatService.SetFrozen(fighter, true)
		fighter.Character:PivotTo(spawnCF)
		fighter.Root.AssemblyLinearVelocity = Vector3.zero
		CombatService.HealFull(fighter)
	end
	local realCount = #participants
	for _, bot in bots do
		table.insert(participants, bot)
	end

	if #participants < 2 or (not botOnly and realCount == 0) then
		print("[Rounds] Round cancelled: not enough fighters (" .. realCount .. " player(s), " .. #bots .. " bot(s))")
		abortRound()
		broadcast()
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
		if forceEnd then
			break
		end
		timeLeft = i
		broadcast()
		announceTo(players, { Text = tostring(i), Style = "Count", Duration = 0.9 })
		task.wait(1)
	end

	-- Admin "Runde beenden" schon im Countdown -> Kampf ueberspringen
	if not forceEnd then
		ensureAtSpawns()
		for _, f in participants do
			if f.Alive then
				CombatService.SetFrozen(f, false)
			end
		end
		announceTo(participantPlayers(), { Text = "FIGHT!", Style = "Fight", Duration = 1.2 })

		setState("Fighting", if botOnly then RoundConfig.BotOnlyRoundTime else RoundConfig.RoundTime)
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
			-- pcall: ein Fehler bei einem Spieler darf die anderen nicht in der Arena lassen
			local ok, err = pcall(sendToLobby, f)
			if not ok then
				warn("[Rounds] Could not send " .. f.Name .. " to the lobby: " .. tostring(err))
			end
		end
	end
	BotService.ClearArenaBots()
	participants = {}
	spawnOf = {}
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
				abortRound()
			end
			releaseStragglers()
		end
	end)
end

return RoundService
