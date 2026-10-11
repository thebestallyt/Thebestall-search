--!strict
-- NOVA CLASH - zentrale Spieleinstellungen.
-- Alles was man zum Balancen oder Einrichten braucht, steht hier.

local Config = {}

Config.GameName = "NOVA CLASH"
Config.Subtitle = "ABILITY BATTLE ARENA"

-- Datenspeicher -----------------------------------------------------------
Config.DataStoreName = "NovaClash_PlayerData_v1"
Config.AutoSaveInterval = 120

-- Startwerte fuer neue Spieler
Config.StartingCoins = 250
Config.StartingAbility = "EmberPunch"

-- Runden ------------------------------------------------------------------
Config.Round = {
	IntermissionTime = 20, -- Sekunden in der Lobby vor der Runde
	CountdownTime = 3, -- 3-2-1-FIGHT
	RoundTime = 150, -- maximale Rundenlaenge
	EndScreenTime = 7, -- Siegeranzeige
	MinRealPlayers = 1, -- echte Spieler die "bereit" sein muessen
	MinFighters = 3, -- wird mit Bots aufgefuellt bis zu dieser Anzahl
	FillWithBots = true, -- Bots auffuellen wenn zu wenig Spieler da sind
	MaxBots = 3,
}

-- Belohnungen in Muenzen
Config.Rewards = {
	Kill = 30,
	BotKill = 12,
	Win = 120,
	Participation = 20,
	TutorialComplete = 150,
}

-- Kampf -------------------------------------------------------------------
Config.Combat = {
	MaxHealth = 100,
	M1Damage = { 4, 4, 5, 8 }, -- Kombo-Schaden pro Schlag
	M1Cooldown = 0.32,
	M1ComboReset = 1.1, -- Zeit bis die Kombo zurueckgesetzt wird
	M1FinisherCooldown = 0.9,
	M1Range = 6.5,
	BlockDamageMultiplier = 0.25,
	BlockWalkSpeed = 7,
	GuardBreakStun = 1.2,
	DashCooldown = 2.2,
	DashSpeed = 95,
	DashDuration = 0.18,
	KillCreditTime = 12, -- Sekunden in denen der letzte Treffer als Kill zaehlt
	NormalWalkSpeed = 18,
}

-- Robux Shop --------------------------------------------------------------
-- WICHTIG: Trage hier die IDs deines Game Passes / deiner Developer Products ein!
-- Solange eine ID 0 ist, wird der Kauf in Roblox Studio simuliert (Testmodus).
Config.Shop = {
	BlackHoleGamePassId = 0,
	BlackHoleDisplayPrice = "R$ 399",
	CoinPacks = {
		{ ProductId = 0, Coins = 600, DisplayPrice = "R$ 49", Name = "Stardust", Icon = "✨" },
		{ ProductId = 0, Coins = 1800, DisplayPrice = "R$ 129", Name = "Nebula Pile", Icon = "🌌" },
		{ ProductId = 0, Coins = 6000, DisplayPrice = "R$ 349", Name = "Galaxy Vault", Icon = "🪐" },
	},
}

-- Admins -------------------------------------------------------------------
-- Admins bekommen einen animierten Titel ueber dem Kopf, einen Chat-Tag
-- und ein Admin-Panel (Knopf links im HUD) + Chat-Befehle (/coins 1000, /start ...).
-- Der Ersteller des Spiels ist automatisch auch Admin.
Config.Admins = {
	Usernames = { "RealThebestall" },
	UserIds = {} :: { number },
	Title = "👑 ADMIN",
}

-- Welt --------------------------------------------------------------------
Config.World = {
	LobbyCenter = Vector3.new(0, 60, 0),
	ArenaCenter = Vector3.new(0, 60, 600),
	ArenaRadius = 78,
	LobbyRadius = 70,
	CrateStage = Vector3.new(0, 400, -3000), -- weit entfernt, nur lokal fuer Kisten-Animationen
}

return Config
