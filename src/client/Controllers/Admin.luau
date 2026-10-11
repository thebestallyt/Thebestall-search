-- Admin-Panel (nur fuer Admins sichtbar) + animierte Titel ueber dem Kopf + Chat-Tag.
-- Der Server prueft jeden Befehl erneut – das Panel allein gibt keine Rechte.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

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
local WHITE = Color3.new(1, 1, 1)
local AdminCommand = Net.Event("AdminCommand")

local TITLE_GRADIENT = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 60)),
	ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(0.65, Color3.fromRGB(255, 80, 200)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 200, 60)),
})

local window: UI.Window

-- Titel ueber dem Kopf ----------------------------------------------------------

local function attachTitle(plr: Player, character: Model)
	local title = plr:GetAttribute("Title")
	if type(title) ~= "string" or title == "" then
		return
	end
	local head = character:WaitForChild("Head", 10) :: BasePart?
	if not head then
		return
	end
	local old = head:FindFirstChild("NovaTitle")
	if old then
		old:Destroy()
	end
	local gui = Make("BillboardGui", {
		Name = "NovaTitle",
		Size = UDim2.fromOffset(220, 44),
		StudsOffset = Vector3.new(0, 3.6, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 150,
		Parent = head,
	})
	local bg = Make("Frame", {
		BackgroundColor3 = Color3.fromRGB(14, 8, 26),
		BackgroundTransparency = 0.2,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.82),
		Parent = gui,
	})
	UI.Round(bg)
	local stroke = UI.Stroke(bg, WHITE, 2, 0)
	UI.Animate(UI.Gradient(stroke, TITLE_GRADIENT, 0), 140, "Rotate")
	local label = UI.Text({
		Text = title,
		Font = Theme.Fonts.Title,
		TextSize = 22,
		Size = UDim2.fromScale(1, 1),
		Parent = bg,
	})
	UI.Animate(UI.Gradient(label, TITLE_GRADIENT, 0), 0.5, "Offset")
	-- sanftes Schweben
	task.spawn(function()
		while gui.Parent do
			UI.Tween(gui, 1.2, { StudsOffset = Vector3.new(0, 3.9, 0) }, Enum.EasingStyle.Sine)
			task.wait(1.2)
			UI.Tween(gui, 1.2, { StudsOffset = Vector3.new(0, 3.6, 0) }, Enum.EasingStyle.Sine)
			task.wait(1.2)
		end
	end)
end

local function watchPlayer(plr: Player)
	plr.CharacterAdded:Connect(function(character)
		attachTitle(plr, character)
	end)
	if plr.Character then
		task.spawn(attachTitle, plr, plr.Character)
	end
	plr:GetAttributeChangedSignal("Title"):Connect(function()
		if plr.Character then
			attachTitle(plr, plr.Character)
		end
	end)
end

-- Chat-Tag [👑 ADMIN] -------------------------------------------------------------

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
				props.PrefixText = "<font color='#FFD24A'>[" .. title .. "]</font> " .. message.PrefixText
			end
		end
		return props
	end
end

-- Admin-Panel ---------------------------------------------------------------------

local function command(name: string, arg: any?)
	AdminCommand:FireServer(name, arg)
end

function Admin.Open()
	if player:GetAttribute("Admin") then
		window:Open()
	end
end

local function buildPanel()
	window = UI.Window({ Title = "ADMIN PANEL", Icon = "👑", Size = Vector2.new(720, 520), Name = "Admin" })
	local content = window.Content
	UI.Text({
		Text = "Welcome, " .. player.DisplayName .. "! Chat commands also work: /coins 1000, /start, /end, /cd, /heal, /unlockall, /resettutorial, /killbots, /announce text",
		Font = Theme.Fonts.Body,
		TextSize = 14,
		TextColor3 = C.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(26, 4),
		Size = UDim2.new(1, -52, 0, 40),
		Parent = content,
	})
	local grid = Make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(24, 52),
		Size = UDim2.new(1, -48, 0, 270),
		Parent = content,
	})
	Make("UIGridLayout", {
		CellSize = UDim2.fromOffset(212, 56),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	local buttons = {
		{ "🪙 +1,000 COINS", "Gold", "Coins", 1000 },
		{ "🪙 +10,000 COINS", "Gold", "Coins", 10000 },
		{ "🔓 UNLOCK ALL", "Primary", "UnlockAll" },
		{ "⚔️ START ROUND", "Success", "StartRound" },
		{ "🏁 END ROUND", "Danger", "EndRound" },
		{ "⏱️ RESET COOLDOWNS", "Secondary", "ResetCooldowns" },
		{ "❤️ FULL HEAL", "Secondary", "Heal" },
		{ "🔄 RESET TUTORIAL", "Secondary", "ResetTutorial" },
		{ "🤖 REMOVE BOTS", "Secondary", "KillBots" },
	}
	for i, b in buttons do
		UI.Button({
			Text = b[1],
			Style = b[2],
			TextSize = 17,
			LayoutOrder = i,
			Parent = grid,
			OnClick = function()
				command(b[3], b[4])
			end,
		})
	end
	-- Ansage an alle
	local box = Make("TextBox", {
		PlaceholderText = "Announcement for everyone...",
		Text = "",
		ClearTextOnFocus = false,
		Font = Theme.Fonts.Bold,
		TextSize = 18,
		TextColor3 = C.Text,
		PlaceholderColor3 = C.Muted,
		BackgroundColor3 = Color3.fromRGB(12, 10, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 24, 1, -80),
		Size = UDim2.new(1, -250, 0, 56),
		Parent = content,
	})
	UI.Corner(box, 12)
	UI.Stroke(box, C.Stroke, 2, 0.2)
	UI.Padding(box, 12)
	UI.Button({
		Text = "📢 ANNOUNCE",
		Style = "Primary",
		Size = UDim2.fromOffset(200, 56),
		Position = UDim2.new(1, -220, 1, -80),
		TextSize = 18,
		Parent = content,
		OnClick = function()
			if #box.Text > 0 then
				command("Announce", box.Text)
				box.Text = ""
			end
		end,
	})
end

local function addMenuButton()
	local crates = HUD.MenuButtons.Crates
	if not crates or HUD.MenuButtons.Admin then
		return
	end
	local btn = crates:Clone() :: TextButton
	btn.Name = "Admin"
	btn.LayoutOrder = 99
	local dot = btn:FindFirstChild("Dot")
	if dot then
		dot:Destroy()
	end
	local labels = {}
	for _, d in btn:GetChildren() do
		if d:IsA("TextLabel") then
			table.insert(labels, d)
		end
	end
	if labels[1] then
		labels[1].Text = "👑"
	end
	if labels[2] then
		labels[2].Text = "ADMIN"
	end
	local g = btn:FindFirstChildOfClass("UIGradient")
	if g then
		g.Color = TITLE_GRADIENT
	end
	local scale = btn:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 1
	end
	btn.Parent = crates.Parent
	btn.Activated:Connect(function()
		UI.Sound("Click")
		Admin.Open()
	end)
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
			HUD.Toast({ Text = "Admin mode active – 👑 button on the left.", Color = C.Gold, Icon = "👑" })
		end
	end)
end

return Admin
