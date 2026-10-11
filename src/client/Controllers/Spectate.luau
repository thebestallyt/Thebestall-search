-- Zuschauen: Wer nicht in der Runde ist, kann den Kaempfern in der Arena zuschauen.
-- Untere Leiste im "Chunky"-Stil: Pfeil-Knoepfe, Name + Lebensbalken des Kaempfers, Stopp-Knopf.

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
local C = Theme.Colors
local F = Theme.Fonts

local gui: ScreenGui
local cluster: Frame
local scaler: Frame
local nameRow: Frame
local nameLabel: TextLabel
local botTag: Frame
local headerLabel: TextLabel
local hpBar: any
local active = false
local index = 1
local current: Model? = nil
local targetConns: { RBXScriptConnection } = {}

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
					table.insert(list, c :: Model)
				end
			end
		end
	end
	return list
end

local function clearTargetConns()
	for _, conn in targetConns do
		conn:Disconnect()
	end
	table.clear(targetConns)
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
	local changed = current ~= target
	current = target

	nameLabel.Text = tostring(target:GetAttribute("DisplayName") or target.Name)
	botTag.Visible = Players:GetPlayerFromCharacter(target) == nil
	headerLabel.Text = "SPECTATING  " .. index .. " / " .. #list

	-- Lebensbalken des beobachteten Kaempfers
	clearTargetConns()
	if hum then
		local h = hum :: Humanoid
		local function refresh(instant: boolean?)
			local maxH = math.max(h.MaxHealth, 1)
			local hp = math.max(0, h.Health)
			local ratio = math.clamp(hp / maxH, 0, 1)
			hpBar.Set(ratio, instant)
			hpBar.Label.Text = tostring(math.ceil(hp))
			hpBar.Fill.BackgroundColor3 = if ratio > 0.5 then C.Health elseif ratio > 0.25 then C.Gold else C.HealthLow
		end
		refresh(true)
		table.insert(targetConns, h.HealthChanged:Connect(function()
			refresh()
		end))
		-- Ziel gestorben -> kurz danach zum naechsten Kaempfer
		table.insert(targetConns, h.Died:Connect(function()
			task.delay(1.4, function()
				if active and current == target then
					focus()
				end
			end)
		end))
	end
	if changed then
		UI.Pop(nameRow, 0.8, 0.25)
	end
end

function Spectate.Begin()
	if active then
		return
	end
	active = true
	gui.Enabled = true
	State.SetHUDHidden("Spectate", false)
	focus()
	if active then
		UI.Pop(scaler, 0.85, 0.3)
	end
end

function Spectate.Stop()
	if not active then
		return
	end
	active = false
	current = nil
	clearTargetConns()
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

-- Leiste sitzt ueber der HUD-Leiste unten (die mit UI.Scale mitwaechst)
local function place()
	cluster.Position = UDim2.new(0.5, 0, 1, -math.floor(12 + 158 * UI.Scale + 14))
end

function Spectate.Init()
	gui = UI.Screen("NovaSpectate", 7)
	gui.Enabled = false

	cluster = Make("Frame", {
		Name = "Spectate",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -184),
		Size = UDim2.fromOffset(470, 152),
		Parent = gui,
	})
	UI.Scaled(cluster)
	-- innerer Rahmen: UI.Pop legt hier seine eigene UIScale an (nicht mit AutoScale kollidieren)
	scaler = Make("Frame", {
		Name = "Scaler",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = cluster,
	})

	-- Schatten + Hauptplatte
	local plate = UI.Panel({
		Name = "Plate",
		Radius = 16,
		Size = UDim2.new(1, 0, 0, 94),
		Parent = scaler,
	})
	UI.Shadow(plate, 6, 0.55)

	headerLabel = UI.Text({
		Name = "Header",
		Text = "SPECTATING",
		Font = F.Heading,
		TextSize = 14,
		TextColor3 = C.Gold,
		TextWrapped = false,
		Position = UDim2.fromOffset(80, 8),
		Size = UDim2.new(1, -160, 0, 16),
		Stroke = 1.5,
		Parent = plate,
	})

	-- Name + BOT-Schild (zentriert)
	nameRow = Make("Frame", {
		Name = "NameRow",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(80, 24),
		Size = UDim2.new(1, -160, 0, 34),
		Parent = plate,
	})
	Make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = nameRow,
	})
	nameLabel = UI.Text({
		Name = "FighterName",
		Text = "",
		Font = F.Heading,
		TextSize = 26,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		LayoutOrder = 1,
		Stroke = 2.5,
		Parent = nameRow,
	})
	Make("UISizeConstraint", { MaxSize = Vector2.new(250, 40), Parent = nameLabel })
	botTag = Make("Frame", {
		Name = "Bot",
		BackgroundColor3 = C.Grey,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(38, 20),
		LayoutOrder = 2,
		Visible = false,
		Parent = nameRow,
	})
	UI.Corner(botTag, 6)
	UI.Stroke(botTag, C.Ink, 2, 0)
	UI.Text({
		Text = "BOT",
		Font = F.Heading,
		TextSize = 13,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Stroke = 1.5,
		Parent = botTag,
	})

	-- Lebensbalken des Ziels
	hpBar = UI.ProgressBar({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.new(1, -180, 0, 18),
		Color = C.Health,
		Parent = plate,
	})
	hpBar.Label.TextSize = 13

	-- Pfeile links/rechts
	UI.Button({
		Name = "Prev",
		Text = "<",
		Style = "Blue",
		TextSize = 32,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(56, 62),
		Parent = plate,
		OnClick = function()
			index -= 1
			focus()
		end,
	})
	UI.Button({
		Name = "Next",
		Text = ">",
		Style = "Blue",
		TextSize = 32,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(56, 62),
		Parent = plate,
		OnClick = function()
			index += 1
			focus()
		end,
	})

	UI.Button({
		Name = "Stop",
		Text = "STOP WATCHING",
		Style = "Red",
		TextSize = 18,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(220, 48),
		Parent = scaler,
		OnClick = function()
			Spectate.Stop()
		end,
	})

	place()
	UI.ScaleChanged:Connect(place)
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
