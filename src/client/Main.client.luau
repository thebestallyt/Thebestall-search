-- NOVA CLASH - Client-Start
-- Laedt alle Controller, verbindet sie miteinander und zeigt das Startmenue.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local Controllers = (script.Parent :: Instance):WaitForChild("Controllers")
local State = require(Controllers:WaitForChild("State"))
local VFXController = require(Controllers:WaitForChild("VFXController"))
local HUD = require(Controllers:WaitForChild("HUD"))
local Ambient = require(Controllers:WaitForChild("Ambient"))
local Combat = require(Controllers:WaitForChild("Combat"))
local Crates = require(Controllers:WaitForChild("Crates"))
local Inventory = require(Controllers:WaitForChild("Inventory"))
local Shop = require(Controllers:WaitForChild("Shop"))
local Spectate = require(Controllers:WaitForChild("Spectate"))
local Admin = require(Controllers:WaitForChild("Admin"))
local Tutorial = require(Controllers:WaitForChild("Tutorial"))
local Menu = require(Controllers:WaitForChild("Menu"))

-- HUD verstecken, bis das Startmenue erscheint
State.SetHUDHidden("Menu", true)

local ordered = { VFXController, HUD, Ambient, Combat, Crates, Inventory, Shop, Spectate, Admin, Tutorial, Menu }

for _, controller in ordered do
	controller.Init()
end

-- Daten vom Server
Net.Event("ProfileUpdated").OnClientEvent:Connect(function(data)
	State.Profile = data
	State.ProfileChanged:Fire()
end)
Net.Event("RoundState").OnClientEvent:Connect(function(data)
	State.Round = data
	State.RoundChanged:Fire()
end)

for _, controller in ordered do
	controller.Start()
end

-- Knoepfe & Prompts verbinden
HUD.MenuButtonPressed:Connect(function(name: string)
	if State.InCrateOpening or State.InCutscene then
		return
	end
	if name == "Crates" then
		Crates.OpenWindow()
	elseif name == "Inventory" then
		Inventory.Open()
	elseif name == "Shop" then
		Shop.Open()
	elseif name == "Tutorial" then
		Tutorial.Begin()
	elseif name == "Spectate" then
		Spectate.Toggle()
	end
end)
Ambient.PromptTriggered = function(name: string)
	if State.MenuOpen or State.InCrateOpening then
		return
	end
	if name == "OpenCrates" then
		Crates.OpenWindow()
	elseif name == "OpenShop" then
		Shop.Open()
	end
end
Menu.OpenCrates:Connect(Crates.OpenWindow)
Menu.OpenShop:Connect(Shop.Open)

-- Profil laden (mit Wartezeit fuer langsame DataStores)
local profile = nil
local ok, result = pcall(function()
	return Net.Function("GetProfile"):InvokeServer()
end)
if ok and result then
	profile = result
	State.Profile = result
	State.ProfileChanged:Fire()
end

-- Startmenue
local firstTime = profile == nil or profile.TutorialDone ~= true
Menu.Show(firstTime)
Menu.Played:Connect(function(wantsTutorial: boolean)
	local p = State.Profile
	if wantsTutorial or (p and not p.TutorialDone) then
		task.wait(0.4)
		Tutorial.Begin()
	end
end)
