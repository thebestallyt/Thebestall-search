--!strict
-- Kleine Hilfe fuer RemoteEvents/RemoteFunctions.
-- Der Server erstellt alle Remotes beim Start, der Client wartet darauf.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	"ProfileUpdated", -- S->C  Profil-Daten haben sich geaendert
	"CombatInput", -- C->S  M1, Block, Dash, Faehigkeiten
	"PlayVFX", -- S->C  Effekte abspielen (alle Clients)
	"HitConfirm", -- S->C  Treffer-Bestaetigung an den Angreifer
	"CooldownStart", -- S->C  Faehigkeit wurde benutzt
	"RoundState", -- S->C  Rundenstatus
	"Announce", -- S->C  grosse Ansage in der Bildschirmmitte
	"KillFeed", -- S->C
	"Notify", -- S->C  kleine Benachrichtigung
	"SetBusy", -- C->S  Spieler ist im Menue / Tutorial / Kistenoeffnung
	"SetAFK", -- C->S  (boolean) Spieler ist laenger untaetig (Config.Round.AfkTimeout) bzw. wieder aktiv
	"TutorialDone", -- C->S
	"Reward", -- S->C  Muenzen erhalten (fuer Animation)
	"AdminCommand", -- C->S  Admin-Befehle (werden auf dem Server geprueft!)
}

local FUNCTIONS = {
	"GetProfile",
	"OpenCrate",
	"EquipAbility",
	"BuyItem",
}

local Net = {}

local folder: Folder

if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing then
		folder = existing :: Folder
	else
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		for _, name in EVENTS do
			local e = Instance.new("RemoteEvent")
			e.Name = name
			e.Parent = folder
		end
		for _, name in FUNCTIONS do
			local f = Instance.new("RemoteFunction")
			f.Name = name
			f.Parent = folder
		end
		folder.Parent = ReplicatedStorage
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Net.Event(name: string): RemoteEvent
	local r = folder:WaitForChild(name, 10)
	assert(r and r:IsA("RemoteEvent"), "Unbekanntes RemoteEvent: " .. name)
	return r :: RemoteEvent
end

function Net.Function(name: string): RemoteFunction
	local r = folder:WaitForChild(name, 10)
	assert(r and r:IsA("RemoteFunction"), "Unbekannte RemoteFunction: " .. name)
	return r :: RemoteFunction
end

return Net
