-- HUD: Lebensbalken, Faehigkeiten-Leiste mit Cooldowns, Muenzen, Rundenstatus,
-- grosse Ansagen, Killfeed, Benachrichtigungen, Kombo-Zaehler und Menue-Knoepfe.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Abilities = require(Shared:WaitForChild("Abilities"))
local Rarities = require(Shared:WaitForChild("Rarities"))
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Signal"))

local Controllers = script.Parent :: Instance
local State = require(Controllers:WaitForChild("State"))
local Client = Controllers.Parent :: Instance
local UIFolder = Client:WaitForChild("UI")
local UI = require(UIFolder:WaitForChild("UI"))
local Theme = require(UIFolder:WaitForChild("Theme"))

local HUD = {}
HUD.MenuButtonPressed = Signal.new() -- (name)
HUD.AbilitySlotPressed = Signal.new() -- (slot)

local player = Players.LocalPlayer
local C = Theme.Colors
local Make = UI.Make

local gui: ScreenGui
local root: Frame
local cooldowns: { [string]: { Start: number, Duration: number } } = {}
local slotFrames: { any } = {}
local menuButtons: { [string]: GuiObject } = {}
HUD.MenuButtons = menuButtons
local coinLabel: TextLabel
local shownCoins = 0
local healthFill: Frame
local healthTrail: Frame
local healthText: TextLabel
local roundLabel: TextLabel
local roundSub: TextLabel
local roundPill: Frame
local announceHolder: Frame
local feed: Frame
local toastHolder: Frame
local comboLabel: TextLabel
local comboCount = 0
local lastHit = 0
local dashBar: Frame
local lowHealth: Frame

-- Hilfsfunktionen ----------------------------------------------------------

local function fmtTime(s: number): string
	s = math.max(0, math.floor(s))
	return string.format("%d:%02d", s // 60, s % 60)
end

function HUD.IsOnCooldown(abilityId: string): boolean
	local cd = cooldowns[abilityId]
	return cd ~= nil and os.clock() < cd.Start + cd.Duration
end

function HUD.StartCooldown(abilityId: string, duration: number)
	if abilityId == "*" then
		table.clear(cooldowns)
		return
	end
	cooldowns[abilityId] = { Start = os.clock(), Duration = duration }
end

-- Muenzen -----------------------------------------------------------------------

local function buildCoins()
	local pill = UI.Panel({
		Name = "Coins",
		Position = UDim2.new(0, 20, 0, 70),
		Size = UDim2.fromOffset(230, 56),
		StrokeColor = Theme.Gradients.Gold,
		Radius = 28,
		Parent = root,
	})
	UI.Scaled(pill)
	local icon = UI.Text({
		Text = "🪙",
		TextSize = 34,
		Size = UDim2.fromOffset(56, 56),
		Parent = pill,
	})
	local _ = icon
	coinLabel = UI.Text({
		Text = "0",
		Font = Theme.Fonts.Title,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(58, 0),
		Size = UDim2.new(1, -64, 1, 0),
		Parent = pill,
	})
	UI.Gradient(coinLabel, Theme.Gradients.Gold, 90)
end

local function setCoins(value: number, animate: boolean)
	if animate and value ~= shownCoins then
		UI.CountTo(coinLabel, shownCoins, value, 0.8)
		if value > shownCoins then
			UI.Pop(coinLabel, 1.35, 0.4)
		end
	else
		coinLabel.Text = UI.Format(value)
	end
	shownCoins = value
end

function HUD.RewardPopup(amount: number, reason: string)
	local pop = UI.Text({
		Text = "+" .. UI.Format(amount) .. " 🪙  <font size='18' color='#d8d0ff'>" .. reason .. "</font>",
		Font = Theme.Fonts.Title,
		TextSize = 30,
		TextColor3 = C.Gold,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 30, 0, 150),
		Size = UDim2.fromOffset(420, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = root,
	})
	Make("UIStroke", { Thickness = 2, Color = Color3.fromRGB(60, 30, 0), Parent = pop })
	UI.Pop(pop, 0.4)
	UI.Tween(pop, 1.6, { Position = UDim2.new(0, 30, 0, 120), TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.9)
	task.delay(2.6, function()
		pop:Destroy()
	end)
	UI.Sound("Coins")
end

-- Menue-Knoepfe (links) -------------------------------------------------------------

local function buildMenu()
	local holder = Make("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 20, 0.5, 0),
		Size = UDim2.fromOffset(92, 580),
		Parent = root,
	})
	UI.Scaled(holder)
	UI.List(holder, false, 12)
	local entries = {
		{ "Crates", "🎁", "CRATES", Theme.Gradients.Gold },
		{ "Inventory", "🎒", "ABILITIES", Theme.Gradients.Main },
		{ "Shop", "💎", "SHOP", Theme.Gradients.Void },
		{ "Tutorial", "❓", "HELP", ColorSequence.new(C.PanelLighter, C.PanelLight) },
		{ "Spectate", "👁", "SPECTATE", ColorSequence.new(C.PanelLighter, C.Purple) },
	}
	for i, e in entries do
		local btn = Make("TextButton", {
			Name = e[1],
			AutoButtonColor = false,
			Text = "",
			BackgroundColor3 = Color3.new(1, 1, 1),
			Size = UDim2.fromOffset(84, 84),
			LayoutOrder = i,
			Parent = holder,
		})
		UI.Corner(btn, 20)
		UI.Gradient(btn, e[4], 45)
		local stroke = UI.Stroke(btn, Color3.new(1, 1, 1), 2, 0.5)
		UI.Text({ Text = e[2], TextSize = 36, Size = UDim2.new(1, 0, 0.7, 0), Parent = btn })
		local label = UI.Text({
			Text = e[3],
			TextSize = 13,
			Font = Theme.Fonts.Title,
			Position = UDim2.fromScale(0, 0.66),
			Size = UDim2.new(1, 0, 0.3, 0),
			Parent = btn,
		})
		Make("UIStroke", { Thickness = 1.5, Color = Color3.new(0, 0, 0), Transparency = 0.3, Parent = label })
		local scale = Make("UIScale", { Parent = btn })
		btn.MouseEnter:Connect(function()
			UI.Tween(scale, 0.15, { Scale = 1.1 })
			UI.Tween(stroke, 0.15, { Transparency = 0 })
			UI.Sound("Hover")
		end)
		btn.MouseLeave:Connect(function()
			UI.Tween(scale, 0.2, { Scale = 1 })
			UI.Tween(stroke, 0.2, { Transparency = 0.5 })
		end)
		btn.Activated:Connect(function()
			UI.Sound("Click")
			UI.Tween(scale, 0.06, { Scale = 0.9 })
			task.delay(0.06, function()
				UI.Tween(scale, 0.2, { Scale = 1.1 }, Enum.EasingStyle.Back)
			end)
			HUD.MenuButtonPressed:Fire(e[1])
		end)
		menuButtons[e[1]] = btn
		if e[1] == "Spectate" then
			btn.Visible = false
		end
		if e[1] == "Crates" then
			-- Hinweis-Punkt, wenn eine Gratis-Kiste wartet
			local dot = Make("Frame", {
				Name = "Dot",
				BackgroundColor3 = C.Danger,
				Size = UDim2.fromOffset(20, 20),
				Position = UDim2.new(1, -16, 0, -4),
				Visible = false,
				ZIndex = 3,
				Parent = btn,
			})
			UI.Round(dot)
			UI.Text({ Text = "!", TextSize = 14, Font = Theme.Fonts.Title, Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = dot })
		end
	end
end

-- Rundenstatus (oben Mitte) ------------------------------------------------------------

local function buildRound()
	roundPill = UI.Panel({
		Name = "Round",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(420, 70),
		Radius = 22,
		Parent = root,
	})
	UI.Scaled(roundPill)
	roundLabel = UI.Text({
		Text = "WAITING FOR PLAYERS",
		Font = Theme.Fonts.Title,
		TextSize = 26,
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.fromOffset(0, 4),
		Parent = roundPill,
	})
	roundSub = UI.Text({
		Text = "",
		Font = Theme.Fonts.Body,
		TextSize = 16,
		TextColor3 = C.SubText,
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, 42),
		Parent = roundPill,
	})
end

local function updateRound()
	local r = State.Round
	local s = r.State
	local inRound = player:GetAttribute("InRound") == true
	if s == "Waiting" then
		roundLabel.Text = "⏳ WAITING FOR PLAYERS"
		roundSub.Text = "Rounds start as soon as someone is ready"
	elseif s == "Intermission" then
		roundLabel.Text = "⚔️ ROUND IN " .. r.TimeLeft .. "s"
		roundSub.Text = "Get ready – everyone in the lobby joins the fight!"
	elseif s == "Countdown" then
		roundLabel.Text = "🔥 STARTING..."
		roundSub.Text = r.Total .. " fighters"
	elseif s == "Fighting" then
		roundLabel.Text = "⚔️ FIGHT  " .. fmtTime(r.TimeLeft)
		roundSub.Text = r.Alive .. " / " .. r.Total .. " left" .. (if inRound then "" else "  •  You are watching")
	elseif s == "Ended" then
		roundLabel.Text = "🏆 ROUND OVER"
		roundSub.Text = "Back to the lobby..."
	end
	local spectate = menuButtons.Spectate
	if spectate then
		spectate.Visible = s == "Fighting" and not inRound
	end
end

-- Lebensbalken + Faehigkeiten (unten Mitte) ---------------------------------------------

local function buildBottom()
	local holder = Make("Frame", {
		Name = "Bottom",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(560, 190),
		Parent = root,
	})
	UI.Scaled(holder)

	-- Faehigkeiten
	local bar = Make("Frame", {
		Name = "Abilities",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 112),
		Parent = holder,
	})
	UI.List(bar, true, 14, Enum.HorizontalAlignment.Center)
	for slot = 1, 4 do
		local frame = Make("TextButton", {
			Name = "Slot" .. slot,
			AutoButtonColor = false,
			Text = "",
			BackgroundColor3 = Color3.new(1, 1, 1),
			Size = UDim2.fromOffset(92, 92),
			LayoutOrder = slot,
			Parent = bar,
		})
		UI.Corner(frame, 18)
		local bg = UI.Gradient(frame, Theme.Gradients.Panel, 90)
		local stroke = UI.Stroke(frame, C.Stroke, 3, 0)
		local icon = UI.Text({ Name = "Icon", Text = "", TextSize = 44, Size = UDim2.fromScale(1, 0.8), Parent = frame })
		local name = UI.Text({
			Name = "AbilityName",
			Text = "",
			TextSize = 11,
			Font = Theme.Fonts.Title,
			TextColor3 = C.SubText,
			Position = UDim2.new(0, 0, 1, 2),
			Size = UDim2.new(1, 0, 0, 16),
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = frame,
		})
		local key = Make("Frame", {
			BackgroundColor3 = C.Background,
			Size = UDim2.fromOffset(26, 26),
			Position = UDim2.fromOffset(-6, -6),
			ZIndex = 4,
			Parent = frame,
		})
		UI.Corner(key, 8)
		UI.Stroke(key, C.Cyan, 1.5, 0.2)
		UI.Text({ Text = tostring(slot), TextSize = 15, Font = Theme.Fonts.Title, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = key })
		local cdFrame = Make("Frame", {
			Name = "Cooldown",
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.35,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			ZIndex = 2,
			Parent = frame,
		})
		UI.Corner(cdFrame, 18)
		local cdText = UI.Text({
			Name = "CDText",
			Text = "",
			TextSize = 30,
			Font = Theme.Fonts.Title,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
			Parent = frame,
		})
		Make("UIStroke", { Thickness = 2, Parent = cdText })
		local scale = Make("UIScale", { Parent = frame })
		frame.Activated:Connect(function()
			HUD.AbilitySlotPressed:Fire(slot)
		end)
		slotFrames[slot] = {
			Frame = frame,
			Bg = bg,
			Stroke = stroke,
			Icon = icon,
			Name = name,
			Cooldown = cdFrame,
			CDText = cdText,
			Scale = scale,
			WasReady = true,
			Id = "",
		}
	end

	-- Lebensbalken
	local hp = Make("Frame", {
		Name = "Health",
		BackgroundColor3 = Color3.fromRGB(12, 10, 24),
		Position = UDim2.new(0, 30, 0, 140),
		Size = UDim2.new(1, -60, 0, 30),
		Parent = holder,
	})
	UI.Corner(hp, 15)
	UI.Stroke(hp, Color3.new(0, 0, 0), 3, 0.2)
	healthTrail = Make("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromScale(1, 1),
		Parent = hp,
	})
	UI.Corner(healthTrail, 15)
	healthFill = Make("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromScale(1, 1),
		Parent = hp,
	})
	UI.Corner(healthFill, 15)
	local hg = UI.Gradient(healthFill, Theme.Gradients.Health, 0)
	healthFill:SetAttribute("Low", false)
	local _ = hg
	local shine = Make("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.75,
		Size = UDim2.new(1, -10, 0.35, 0),
		Position = UDim2.fromOffset(5, 3),
		Parent = healthFill,
	})
	UI.Corner(shine, 8)
	healthText = UI.Text({
		Text = "100 / 100",
		Font = Theme.Fonts.Title,
		TextSize = 18,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = hp,
	})
	Make("UIStroke", { Thickness = 2, Parent = healthText })

	-- Dash-Anzeige
	local dash = Make("Frame", {
		Name = "Dash",
		BackgroundColor3 = Color3.fromRGB(12, 10, 24),
		Position = UDim2.new(0, 30, 0, 176),
		Size = UDim2.new(0.3, 0, 0, 8),
		Parent = holder,
	})
	UI.Corner(dash, 4)
	dashBar = Make("Frame", { BackgroundColor3 = C.Cyan, Size = UDim2.fromScale(1, 1), Parent = dash })
	UI.Corner(dashBar, 4)
	UI.Text({
		Text = "Q  DASH",
		TextSize = 11,
		Font = Theme.Fonts.Title,
		TextColor3 = C.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(1, 8, 0, -4),
		Size = UDim2.fromOffset(120, 16),
		Parent = dash,
	})
end

local function updateSlots()
	local profile = State.Profile
	for slot, s in slotFrames do
		local id = if profile then profile.Equipped[slot] or "" else ""
		s.Id = id
		local def = Abilities.Get(id)
		if def then
			local rarity = Rarities.Get(def.Rarity)
			s.Icon.Text = def.Icon
			s.Name.Text = string.upper(def.Name)
			s.Stroke.Color = rarity.Color
			s.Bg.Color = ColorSequence.new(rarity.Dark, Color3.fromRGB(14, 11, 30))
		else
			s.Icon.Text = "＋"
			s.Icon.TextColor3 = C.Muted
			s.Name.Text = "EMPTY"
			s.Stroke.Color = C.Stroke
			s.Bg.Color = Theme.Gradients.Panel
		end
		if def then
			s.Icon.TextColor3 = Color3.new(1, 1, 1)
		end
	end
end

local lastHealth = 100
local function updateHealth(humanoid: Humanoid)
	local ratio = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
	healthText.Text = math.ceil(humanoid.Health) .. " / " .. math.floor(humanoid.MaxHealth)
	UI.Tween(healthFill, 0.15, { Size = UDim2.fromScale(ratio, 1) })
	if humanoid.Health < lastHealth then
		task.delay(0.35, function()
			UI.Tween(healthTrail, 0.5, { Size = UDim2.fromScale(ratio, 1) }, Enum.EasingStyle.Quad)
		end)
	else
		healthTrail.Size = UDim2.fromScale(ratio, 1)
	end
	lastHealth = humanoid.Health
	local low = ratio < 0.3
	if healthFill:GetAttribute("Low") ~= low then
		healthFill:SetAttribute("Low", low)
		local g = healthFill:FindFirstChildOfClass("UIGradient")
		if g then
			g.Color = if low then Theme.Gradients.HealthLow else Theme.Gradients.Health
		end
	end
	lowHealth.Visible = low and humanoid.Health > 0
end

local function bindCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	lastHealth = humanoid.Health
	updateHealth(humanoid)
	humanoid.HealthChanged:Connect(function()
		updateHealth(humanoid)
	end)
end

-- Ansagen -------------------------------------------------------------------------

function HUD.Announce(data: { [string]: any })
	for _, c in announceHolder:GetChildren() do
		c:Destroy()
	end
	local style = data.Style or "Big"
	local color = data.Color or Color3.new(1, 1, 1)
	local size = if style == "Count" then 150 elseif style == "Fight" then 120 else 74
	local text = UI.Text({
		Text = data.Text or "",
		Font = Theme.Fonts.Title,
		TextSize = size,
		TextColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.new(1, 0, 0, size + 20),
		TextWrapped = false,
		Parent = announceHolder,
	})
	Make("UIStroke", { Thickness = 4, Color = Color3.new(0, 0, 0), Transparency = 0.1, Parent = text })
	local g: ColorSequence = if style == "Victory"
		then Theme.Gradients.Gold
		elseif style == "Eliminated" then Theme.Gradients.Danger
		elseif style == "Fight" then Theme.Gradients.Danger
		else Theme.Gradients.Main
	local grad = UI.Gradient(text, g, 0)
	UI.Animate(grad, 0.6, "Offset")
	local scale = Make("UIScale", { Scale = if style == "Count" then 2.4 else 0.4, Parent = text })
	UI.Tween(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	if data.Sub then
		local sub = UI.Text({
			Text = data.Sub,
			Font = Theme.Fonts.Bold,
			TextSize = 26,
			TextColor3 = C.Text,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.42, size / 2 + 14),
			Size = UDim2.new(1, 0, 0, 34),
			TextTransparency = 1,
			Parent = announceHolder,
		})
		Make("UIStroke", { Thickness = 2, Parent = sub })
		UI.Tween(sub, 0.4, { TextTransparency = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0.2)
		task.delay(data.Duration or 2, function()
			UI.Tween(sub, 0.3, { TextTransparency = 1 })
		end)
	end
	if style == "Count" then
		UI.Sound("Countdown", 1)
	elseif style == "Fight" then
		UI.Sound("Fight")
		UI.Burst(announceHolder, UDim2.fromScale(0.5, 0.42), { C.Danger, C.Gold, Color3.new(1, 1, 1) }, 40, 500)
	elseif style == "Victory" then
		UI.Sound("Victory")
		UI.Burst(announceHolder, UDim2.fromScale(0.5, 0.42), { C.Gold, C.Cyan, C.Magenta, Color3.new(1, 1, 1) }, 70, 600)
	elseif style == "Eliminated" then
		UI.Sound("Error")
	end
	task.delay(data.Duration or 2, function()
		if text.Parent then
			UI.Tween(scale, 0.3, { Scale = 1.4 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			UI.Tween(text, 0.3, { TextTransparency = 1 })
			task.delay(0.35, function()
				text:Destroy()
			end)
		end
	end)
end

-- Killfeed ------------------------------------------------------------------------

local function addKillFeed(data: { [string]: any })
	local entry = UI.Panel({
		Size = UDim2.fromOffset(330, 40),
		Radius = 12,
		NoStroke = true,
		BackgroundTransparency = 0.15,
		Parent = feed,
	})
	local killer = data.Killer or "The Void"
	UI.Text({
		Text = "<font color='#ffd34a'>" .. killer .. "</font>  ⚔️  <font color='#ff6e8a'>" .. tostring(data.Victim) .. "</font>",
		TextSize = 17,
		Size = UDim2.fromScale(1, 1),
		Parent = entry,
	})
	entry.Position = UDim2.fromOffset(340, 0)
	UI.Pop(entry, 0.6, 0.3)
	task.delay(6, function()
		UI.Tween(entry, 0.4, { BackgroundTransparency = 1 })
		for _, d in entry:GetDescendants() do
			if d:IsA("TextLabel") then
				UI.Tween(d, 0.4, { TextTransparency = 1 })
			end
		end
		task.delay(0.45, function()
			entry:Destroy()
		end)
	end)
end

-- Benachrichtigungen ----------------------------------------------------------------

function HUD.Toast(data: { [string]: any })
	local color: Color3 = data.Color or C.Cyan
	local toast = UI.Panel({
		Size = UDim2.fromOffset(380, 64),
		Radius = 14,
		StrokeColor = ColorSequence.new(color, color:Lerp(Color3.new(1, 1, 1), 0.4)),
		Parent = toastHolder,
	})
	UI.Text({ Text = data.Icon or "✨", TextSize = 30, Size = UDim2.fromOffset(60, 64), Parent = toast })
	UI.Text({
		Text = data.Text or "",
		TextSize = 16,
		Font = Theme.Fonts.Bold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(60, 0),
		Size = UDim2.new(1, -70, 1, 0),
		Parent = toast,
	})
	UI.Pop(toast, 0.7, 0.35)
	UI.Sound("Open", 1.3)
	task.delay(data.Duration or 4.5, function()
		UI.Tween(toast, 0.3, { BackgroundTransparency = 1, Size = UDim2.fromOffset(380, 0) })
		task.delay(0.32, function()
			toast:Destroy()
		end)
	end)
end

-- Kombo-Zaehler -------------------------------------------------------------------

function HUD.RegisterHit()
	local t = os.clock()
	if t - lastHit > 1.6 then
		comboCount = 0
	end
	lastHit = t
	comboCount += 1
	if comboCount >= 2 then
		comboLabel.Visible = true
		comboLabel.Text = comboCount .. "x COMBO"
		comboLabel.TextTransparency = 0
		UI.Pop(comboLabel, 1.5, 0.25)
		comboLabel.Rotation = math.random(-8, 8)
	end
	task.delay(1.7, function()
		if os.clock() - lastHit >= 1.6 then
			UI.Tween(comboLabel, 0.3, { TextTransparency = 1 })
		end
	end)
end

-- Aufbau ----------------------------------------------------------------------------

function HUD.SetVisible(visible: boolean)
	root.Visible = visible
end

function HUD.Init()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	gui = UI.Screen("NovaHUD", 5)
	root = Make("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })

	lowHealth = Make("Frame", { Name = "LowHealth", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = gui })
	for _, side in { { UDim2.fromScale(1, 0.25), UDim2.fromScale(0, 0), 90 }, { UDim2.fromScale(1, 0.25), UDim2.fromScale(0, 0.75), -90 } } do
		local f = Make("Frame", { BackgroundColor3 = C.Danger, BorderSizePixel = 0, Size = side[1], Position = side[2], Parent = lowHealth })
		local g = UI.Gradient(f, nil, side[3], NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }))
		local _ = g
	end

	buildCoins()
	buildMenu()
	buildRound()
	buildBottom()

	announceHolder = Make("Frame", { Name = "Announce", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	feed = Make("Frame", {
		Name = "KillFeed",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 80),
		Size = UDim2.fromOffset(340, 260),
		Parent = root,
	})
	UI.Scaled(feed)
	UI.List(feed, false, 6, Enum.HorizontalAlignment.Right)
	toastHolder = Make("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -150),
		Size = UDim2.fromOffset(390, 300),
		Parent = gui,
	})
	UI.Scaled(toastHolder)
	local tl = UI.List(toastHolder, false, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom)
	local _ = tl
	comboLabel = UI.Text({
		Name = "Combo",
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 40,
		TextColor3 = C.Gold,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -60, 0.5, 0),
		Size = UDim2.fromOffset(300, 50),
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
		Parent = root,
	})
	Make("UIStroke", { Thickness = 3, Color = Color3.fromRGB(80, 30, 0), Parent = comboLabel })
	UI.Gradient(comboLabel, Theme.Gradients.Gold, 90)

	State.HUDVisibilityChanged:Connect(function(hidden: boolean)
		root.Visible = not hidden
	end)
	root.Visible = not State.IsHUDHidden()
end

function HUD.Start()
	State.ProfileChanged:Connect(function()
		local p = State.Profile
		if not p then
			return
		end
		setCoins(p.Coins, not State.InCrateOpening)
		updateSlots()
		local dot = menuButtons.Crates and menuButtons.Crates:FindFirstChild("Dot")
		if dot and dot:IsA("GuiObject") then
			dot.Visible = p.FreeCrate == true
		end
	end)
	State.RoundChanged:Connect(updateRound)
	player:GetAttributeChangedSignal("InRound"):Connect(updateRound)

	Net.Event("Announce").OnClientEvent:Connect(HUD.Announce)
	Net.Event("KillFeed").OnClientEvent:Connect(addKillFeed)
	Net.Event("Notify").OnClientEvent:Connect(HUD.Toast)
	Net.Event("Reward").OnClientEvent:Connect(function(amount, reason)
		HUD.RewardPopup(amount, reason)
	end)
	Net.Event("CooldownStart").OnClientEvent:Connect(function(abilityId, duration)
		HUD.StartCooldown(abilityId, duration)
		State.TutorialEvent:Fire("AbilityUsed", abilityId)
	end)
	Net.Event("HitConfirm").OnClientEvent:Connect(function(data)
		HUD.RegisterHit()
		if data and data.IsDummy then
			State.TutorialEvent:Fire("DummyHit")
		end
	end)

	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end
	player.CharacterAdded:Connect(bindCharacter)

	-- Cooldown-Anzeige jeden Frame
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for _, s in slotFrames do
			local cd = cooldowns[s.Id]
			local remaining = if cd then (cd.Start + cd.Duration) - t else 0
			if remaining > 0 then
				local ratio = remaining / cd.Duration
				s.Cooldown.Size = UDim2.fromScale(1, ratio)
				s.CDText.Text = if remaining < 10 then string.format("%.1f", remaining) else tostring(math.ceil(remaining))
				s.WasReady = false
			else
				if not s.WasReady then
					s.WasReady = true
					-- "Bereit"-Blitz
					s.Scale.Scale = 1.25
					UI.Tween(s.Scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
					s.Stroke.Thickness = 6
					UI.Tween(s.Stroke, 0.4, { Thickness = 3 })
				end
				s.Cooldown.Size = UDim2.fromScale(1, 0)
				s.CDText.Text = ""
			end
		end
		local dashReady = HUD.DashReadyAt or 0
		local dashRatio = if dashReady > t then 1 - (dashReady - t) / Config.Combat.DashCooldown else 1
		dashBar.Size = UDim2.fromScale(math.clamp(dashRatio, 0, 1), 1)
		dashBar.BackgroundColor3 = if dashRatio >= 1 then C.Cyan else C.Muted
	end)

	-- Pulsierender Rand bei wenig Leben
	task.spawn(function()
		while true do
			if lowHealth.Visible then
				for _, f in lowHealth:GetChildren() do
					if f:IsA("Frame") then
						UI.Tween(f, 0.5, { BackgroundTransparency = 0.4 }, Enum.EasingStyle.Sine)
					end
				end
				task.wait(0.5)
				for _, f in lowHealth:GetChildren() do
					if f:IsA("Frame") then
						UI.Tween(f, 0.5, { BackgroundTransparency = 0 }, Enum.EasingStyle.Sine)
					end
				end
			end
			task.wait(0.5)
		end
	end)

	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		for _, s in slotFrames do
			s.Frame.Size = UDim2.fromOffset(84, 84)
		end
	end
	updateRound()
end

HUD.DashReadyAt = 0

return HUD
