-- Gemeinsamer Client-Zustand (Profil, Runde, UI-Sichtbarkeit, Cutscenes).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Signal"))
local Net = require(Shared:WaitForChild("Net"))

local State = {}

State.Profile = nil :: any
State.ProfileChanged = Signal.new()

State.Round = { State = "Waiting", TimeLeft = 0, Alive = 0, Total = 0, Fighters = {} } :: any
State.RoundChanged = Signal.new()

State.HUDVisibilityChanged = Signal.new()
State.PanelChanged = Signal.new()
State.CutsceneChanged = Signal.new()
State.TutorialEvent = Signal.new() -- (name, data) fuer das Tutorial

State.OpenPanel = nil :: string?
State.InCutscene = false
State.InCrateOpening = false
State.MenuOpen = true
State.TutorialActive = false

local hiddenReasons: { [string]: boolean? } = {}
local busyReasons: { [string]: boolean? } = {}
local lastBusy: boolean? = nil

function State.SetHUDHidden(reason: string, hidden: boolean)
	hiddenReasons[reason] = if hidden then true else nil
	State.HUDVisibilityChanged:Fire(State.IsHUDHidden())
end

function State.IsHUDHidden(): boolean
	return next(hiddenReasons) ~= nil
end

-- "Beschaeftigt" = nimmt nicht an der naechsten Runde teil (Menue, Tutorial, Kiste ...)
function State.SetBusy(reason: string, busy: boolean)
	busyReasons[reason] = if busy then true else nil
	local now = next(busyReasons) ~= nil
	if now ~= lastBusy then
		lastBusy = now
		Net.Event("SetBusy"):FireServer(now)
	end
end

function State.SetPanel(name: string?)
	if State.OpenPanel == name then
		return
	end
	State.OpenPanel = name
	State.PanelChanged:Fire(name)
end

function State.SetCutscene(on: boolean)
	State.InCutscene = on
	State.SetHUDHidden("Cutscene", on)
	State.CutsceneChanged:Fire(on)
end

function State.Owned(abilityId: string): number
	local p = State.Profile
	return if p and p.Owned then (p.Owned[abilityId] or 0) else 0
end

return State
