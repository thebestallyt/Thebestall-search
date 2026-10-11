-- Zuschauen: Wer nicht in der Runde ist, kann den Kaempfern in der Arena zuschauen.

local Players = game:GetService("Players")

local Controllers = script.Parent :: Instance
local State = require(Controllers:WaitForChild("State"))
local Client = Controllers.Parent :: Instance
local UIFolder = Client:WaitForChild("UI")
local UI = require(UIFolder:WaitForChild("UI"))
local Theme = require(UIFolder:WaitForChild("Theme"))

local Spectate = {}

local player = Players.LocalPlayer
local Make = UI.Make

local gui: ScreenGui
local nameLabel: TextLabel
local active = false
local index = 1

local function fighters(): { Model }
	local list = {}
	for _, plr in Players:GetPlayers() do
		local c = plr.Character
		if c and c:GetAttribute("InRound") then
			local h = c:FindFirstChildOfClass("Humanoid")
			if h and h.Health > 0 then
				table.insert(list, c)
			end
		end
	end
	local npcs = workspace:FindFirstChild("NPCs")
	if npcs then
		for _, c in npcs:GetChildren() do
			if c:IsA("Model") and c:GetAttribute("InRound") then
				local h = c:FindFirstChildOfClass("Humanoid")
				if h and h.Health > 0 then
					table.insert(list, c)
				end
			end
		end
	end
	return list
end

local function focus()
	local list = fighters()
	if #list == 0 then
		Spectate.Stop()
		return
	end
	index = ((index - 1) % #list) + 1
	local target = list[index]
	local hum = target:FindFirstChildOfClass("Humanoid")
	if hum then
		(workspace.CurrentCamera :: Camera).CameraSubject = hum
	end
	nameLabel.Text = "👁  " .. tostring(target:GetAttribute("DisplayName") or target.Name)
	UI.Pop(nameLabel, 0.8, 0.25)
end

function Spectate.Begin()
	if active then
		return
	end
	active = true
	gui.Enabled = true
	State.SetHUDHidden("Spectate", false)
	focus()
end

function Spectate.Stop()
	if not active then
		return
	end
	active = false
	gui.Enabled = false
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		(workspace.CurrentCamera :: Camera).CameraSubject = hum
	end
end

function Spectate.Toggle()
	if active then
		Spectate.Stop()
	else
		Spectate.Begin()
	end
end

function Spectate.Init()
	gui = UI.Screen("NovaSpectate", 7)
	gui.Enabled = false
	local bar = UI.Panel({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -230),
		Size = UDim2.fromOffset(520, 70),
		Radius = 20,
		Parent = gui,
	})
	UI.Scaled(bar)
	UI.Button({
		Text = "◀",
		Style = "Secondary",
		Size = UDim2.fromOffset(56, 50),
		Position = UDim2.fromOffset(10, 10),
		Parent = bar,
		OnClick = function()
			index -= 1
			focus()
		end,
	})
	UI.Button({
		Text = "▶",
		Style = "Secondary",
		Size = UDim2.fromOffset(56, 50),
		Position = UDim2.new(1, -66, 0, 10),
		Parent = bar,
		OnClick = function()
			index += 1
			focus()
		end,
	})
	nameLabel = UI.Text({
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 24,
		Position = UDim2.fromOffset(70, 0),
		Size = UDim2.new(1, -140, 1, 0),
		Parent = bar,
	})
	UI.Button({
		Text = "STOP WATCHING",
		Style = "Danger",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(220, 40),
		Position = UDim2.new(0.5, 0, 1, 10),
		TextSize = 16,
		Parent = bar,
		OnClick = function()
			Spectate.Stop()
		end,
	})
	local _ = Make
end

function Spectate.Start()
	State.RoundChanged:Connect(function()
		local s = State.Round.State
		if active and (s ~= "Fighting" or player:GetAttribute("InRound")) then
			Spectate.Stop()
		elseif active then
			-- Wenn das aktuelle Ziel gestorben ist -> naechstes
			local cam = workspace.CurrentCamera :: Camera
			local subject = cam.CameraSubject
			if not subject or not subject:IsA("Humanoid") or (subject :: Humanoid).Health <= 0 then
				focus()
			end
		end
	end)
	player.CharacterAdded:Connect(function()
		if active then
			task.wait(0.1)
			focus()
		end
	end)
end

return Spectate
