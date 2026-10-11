-- Admin-Panel (nur fuer Admins sichtbar) + Titel ueber dem Kopf + Chat-Tag.
-- Der Server prueft jeden Befehl erneut – das Panel allein gibt keine Rechte.
-- Stil: "Chunky Game UI" (UI.Window mit goldener Kopfleiste, beschriftete Gruppen, Inset-Eingabefeld).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local Controllers = script.Parent :: Instance
local HUD = require(Controllers:WaitForChild("HUD"))
local Client = Controllers.Parent :: Instance
local UIFolder = Client:WaitForChild("UI")
local UI = require(UIFolder:WaitForChild("UI"))
local Theme = require(UIFolder:WaitForChild("Theme"))

local Admin = {}

local player = Players.LocalPlayer
local Make = UI.Make
local C = Theme.Colors
local F = Theme.Fonts
local WHITE = Color3.new(1, 1, 1)

local WINDOW_W, WINDOW_H = 760, 596
local PAD = 24
local MAX_ANNOUNCE = 120

local window: UI.Window
local statusLabel: TextLabel
local statusToken = 0
local HINT = "Chat works too: /coins 1000, /start, /end, /cd, /heal, /unlockall, /resettutorial, /killbots, /announce text"

local function textWidth(text: string, size: number, font: Enum.Font): number
	local ok, v = pcall(function()
		return TextService:GetTextSize(text, size, font, Vector2.new(2000, 200))
	end)
	if ok and v then
		return v.X
	end
	return #text * size * 0.6
end

-- Titel ueber dem Kopf ----------------------------------------------------------------
-- Dunkles Schild mit goldenem Rand, goldene Schrift mit Kontur, schwebt sanft auf und ab.

local function attachTitle(plr: Player, character: Model)
	local head = character:WaitForChild("Head", 10)
	if not head or not head:IsA("BasePart") then
		return
	end
	local old = head:FindFirstChild("NovaTitle")
	if old then
		old:Destroy()
	end
	local title = plr:GetAttribute("Title")
	if type(title) ~= "string" or title == "" then
		return
	end
	local textSize = 20
	local w = math.clamp(math.ceil(textWidth(title, textSize, F.Heading)) + 32, 90, 280)
	local h = 34
	local gui = Make("BillboardGui", {
		Name = "NovaTitle",
		Size = UDim2.fromOffset(w + 12, h + 14),
		StudsOffset = Vector3.new(0, 3.1, 0),
		AlwaysOnTop = false,
		LightInfluence = 0,
		MaxDistance = 120,
		ResetOnSpawn = false,
		Parent = head,
	})
	-- Schatten
	local shadow = Make("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 4),
		Size = UDim2.fromOffset(w, h),
		Parent = gui,
	})
	UI.Corner(shadow, 10)
	local plate = Make("Frame", {
		Name = "Plate",
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(w, h),
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = gui,
	})
	UI.Corner(plate, 10)
	UI.Stroke(plate, C.Gold, 2.5, 0)
	UI.Text({
		Name = "Label",
		Text = title,
		Font = F.Heading,
		TextSize = textSize,
		TextColor3 = C.Gold,
		TextWrapped = false,
		RichText = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Stroke = 2,
		Parent = plate,
	})
	-- dezenter Glanz, der alle paar Sekunden ueber das Schild huscht
	UI.Shine(plate, 4.5)
	-- sanftes Schweben (Tween-Endlosschleife, endet automatisch mit dem Kopf)
	TweenService:Create(
		gui,
		TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ StudsOffset = Vector3.new(0, 3.35, 0) }
	):Play()
end

local function watchPlayer(plr: Player)
	plr.CharacterAdded:Connect(function(character)
		attachTitle(plr, character)
	end)
	if plr.Character then
		task.spawn(attachTitle, plr, plr.Character)
	end
	plr:GetAttributeChangedSignal("Title"):Connect(function()
		local character = plr.Character
		if character then
			task.spawn(attachTitle, plr, character)
		end
	end)
end

-- Chat-Tag [ADMIN] ----------------------------------------------------------------------

local function escapeRich(s: string): string
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function setupChatTag()
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		return
	end
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local props = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		if source then
			local plr = Players:GetPlayerByUserId(source.UserId)
			local title = plr and plr:GetAttribute("Title")
			if type(title) == "string" and title ~= "" then
				props.PrefixText = "<font color='#FFBB28'>[" .. escapeRich(title) .. "]</font> " .. message.PrefixText
			end
		end
		return props
	end
end

-- Admin-Panel ---------------------------------------------------------------------------

local function setStatus(text: string, color: Color3)
	statusToken += 1
	local token = statusToken
	statusLabel.Text = text
	statusLabel.TextColor3 = color
	task.delay(2.6, function()
		if statusToken == token then
			statusLabel.Text = HINT
			statusLabel.TextColor3 = C.Muted
		end
	end)
end

local function command(name: string, arg: any?, label: string)
	local ok = pcall(function()
		Net.Event("AdminCommand"):FireServer(name, arg)
	end)
	if ok then
		setStatus("Sent: " .. label, C.Green)
	else
		setStatus("Could not reach the server.", C.Red)
	end
end

function Admin.Open()
	if player:GetAttribute("Admin") and window then
		window:Open()
	end
end

-- Beschriftete Gruppe: Karte mit kleinem Farbstreifen + Titel
local function section(parent: Instance, title: string, color: Color3, y: number, height: number): Frame
	local card = UI.Card({
		Name = title,
		Position = UDim2.fromOffset(PAD, y),
		Size = UDim2.new(1, -PAD * 2, 0, height),
		Parent = parent,
	})
	local chip = Make("Frame", {
		Name = "Chip",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.fromOffset(6, 18),
		Parent = card,
	})
	UI.Corner(chip, 3)
	UI.Stroke(chip, C.Ink, 1.5, 0)
	UI.Text({
		Name = "Title",
		Text = title,
		Font = F.Heading,
		TextSize = 16,
		TextColor3 = C.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		Position = UDim2.fromOffset(30, 10),
		Size = UDim2.new(1, -46, 0, 22),
		Stroke = 1.5,
		Parent = card,
	})
	return card
end

type ButtonSpec = { Text: string, Style: string, Command: string, Arg: any? }

local function buttonRow(card: Frame, specs: { ButtonSpec })
	local row = Make("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 42),
		Size = UDim2.new(1, -32, 0, 52),
		Parent = card,
	})
	UI.List(row, true, 12, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	local n = #specs
	for i, spec in specs do
		UI.Button({
			Text = spec.Text,
			Style = spec.Style,
			Size = UDim2.new(1 / n, -math.ceil(12 * (n - 1) / n), 0, 52),
			TextSize = 18,
			LayoutOrder = i,
			Parent = row,
			OnClick = function()
				command(spec.Command, spec.Arg, spec.Text)
			end,
		})
	end
end

local function buildPanel()
	window = UI.Window({ Title = "ADMIN PANEL", Size = Vector2.new(WINDOW_W, WINDOW_H), Name = "Admin", Color = C.Gold })
	local content = window.Content
	local cardH = 106
	local gap = 12
	local y = 16

	local economy = section(content, "ECONOMY", C.Gold, y, cardH)
	buttonRow(economy, {
		{ Text = "+1,000 COINS", Style = "Gold", Command = "Coins", Arg = 1000 },
		{ Text = "+10,000 COINS", Style = "Gold", Command = "Coins", Arg = 10000 },
		{ Text = "UNLOCK ALL", Style = "Purple", Command = "UnlockAll" },
	})
	y += cardH + gap

	local round = section(content, "ROUND", C.Green, y, cardH)
	buttonRow(round, {
		{ Text = "START ROUND", Style = "Green", Command = "StartRound" },
		{ Text = "END ROUND", Style = "Red", Command = "EndRound" },
		{ Text = "REMOVE BOTS", Style = "Grey", Command = "KillBots" },
	})
	y += cardH + gap

	local me = section(content, "PLAYER", C.Blue, y, cardH)
	buttonRow(me, {
		{ Text = "RESET COOLDOWNS", Style = "Blue", Command = "ResetCooldowns" },
		{ Text = "FULL HEAL", Style = "Green", Command = "Heal" },
		{ Text = "RESET TUTORIAL", Style = "Grey", Command = "ResetTutorial" },
	})
	y += cardH + gap

	-- Ansage an alle: vertieftes Eingabefeld + Knopf
	local announce = section(content, "ANNOUNCEMENT", C.Purple, y, cardH)
	local field = UI.Inset({
		Name = "Field",
		Radius = 12,
		Position = UDim2.fromOffset(16, 42),
		Size = UDim2.new(1, -32 - 192 - 12, 0, 48),
		Parent = announce,
	})
	local fieldStroke = field:FindFirstChildOfClass("UIStroke")
	local box = Make("TextBox", {
		Name = "Input",
		BackgroundTransparency = 1,
		PlaceholderText = "Type a message for everyone...",
		PlaceholderColor3 = C.Muted,
		Text = "",
		ClearTextOnFocus = false,
		Font = F.Bold,
		TextSize = 17,
		TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -28, 1, 0),
		Parent = field,
	})
	box:GetPropertyChangedSignal("Text"):Connect(function()
		if #box.Text > MAX_ANNOUNCE then
			box.Text = string.sub(box.Text, 1, MAX_ANNOUNCE)
		end
	end)
	box.Focused:Connect(function()
		if fieldStroke then
			fieldStroke.Color = C.Blue
			fieldStroke.Transparency = 0
		end
	end)
	box.FocusLost:Connect(function()
		if fieldStroke then
			fieldStroke.Color = C.Ink
			fieldStroke.Transparency = 0.3
		end
	end)
	local function sendAnnouncement()
		local text = string.gsub(box.Text, "^%s+", "")
		if #text == 0 then
			UI.Shake(field)
			return
		end
		command("Announce", text, "ANNOUNCEMENT")
		box.Text = ""
	end
	box.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			sendAnnouncement()
		end
	end)
	UI.Button({
		Text = "ANNOUNCE",
		Style = "Blue",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 40),
		Size = UDim2.fromOffset(192, 52),
		TextSize = 19,
		Parent = announce,
		OnClick = sendAnnouncement,
	})
	y += cardH + 10

	statusLabel = UI.Text({
		Name = "Status",
		Text = HINT,
		Font = F.Bold,
		TextSize = 13,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		RichText = false,
		Position = UDim2.fromOffset(PAD + 4, y),
		Size = UDim2.new(1, -PAD * 2 - 8, 0, 20),
		Parent = content,
	})
end

-- Admin-Knopf im HUD-Menue: eigenes UI.IconButton mit gezeichneter Krone
local function drawCrown(face: Instance, accent: Color3)
	local g = Make("Frame", {
		Name = "Glyph",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(38, 30),
		ZIndex = 6,
		Parent = face,
	})
	-- drei Zacken (gedrehte Quadrate), die untere Haelfte verschwindet hinter dem Band
	for i, x in { 7, 19, 31 } do
		local tip = Make("Frame", {
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, if i == 2 then 12 else 15),
			Size = UDim2.fromOffset(13, 13),
			Rotation = 45,
			ZIndex = 6,
			Parent = g,
		})
		UI.Corner(tip, 3)
		UI.Stroke(tip, C.Ink, 2, 0)
		local ball = Make("Frame", {
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, if i == 2 then 3 else 6),
			Size = UDim2.fromOffset(7, 7),
			ZIndex = 6,
			Parent = g,
		})
		UI.Round(ball)
		UI.Stroke(ball, C.Ink, 2, 0)
	end
	local band = Make("Frame", {
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(2, 17),
		Size = UDim2.fromOffset(34, 12),
		ZIndex = 8,
		Parent = g,
	})
	UI.Corner(band, 3)
	UI.Stroke(band, C.Ink, 2, 0)
	for _, x in { 10, 19, 28 } do
		local jewel = Make("Frame", {
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x - 2, 6),
			Size = UDim2.fromOffset(5, 5),
			ZIndex = 9,
			Parent = band,
		})
		UI.Round(jewel)
	end
end

local function addMenuButton()
	local crates = HUD.MenuButtons.Crates
	if not crates or HUD.MenuButtons.Admin or not crates.Parent then
		return
	end
	local size = if crates.Size.X.Offset > 0 then crates.Size.X.Offset else 72
	local btn = UI.IconButton({
		Name = "Admin",
		Icon = "",
		Caption = "ADMIN",
		Style = "Gold",
		Size = size,
		LayoutOrder = 99,
		Parent = crates.Parent,
		OnClick = Admin.Open,
	})
	local face = btn:FindFirstChild("Face")
	if face then
		drawCrown(face, C.Red)
	end
	HUD.MenuButtons.Admin = btn
end

function Admin.Init()
	buildPanel()
	setupChatTag()
end

function Admin.Start()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, p in Players:GetPlayers() do
		watchPlayer(p)
	end
	if player:GetAttribute("Admin") then
		addMenuButton()
	end
	player:GetAttributeChangedSignal("Admin"):Connect(function()
		if player:GetAttribute("Admin") then
			addMenuButton()
			HUD.Toast({ Text = "Admin mode active – ADMIN button on the left.", Color = C.Gold, Icon = "!" })
		end
	end)
end

return Admin
