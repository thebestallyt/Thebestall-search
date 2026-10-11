-- Startmenue mit Intro-Animation. Beim allerersten Beitritt gibt es ein laengeres,
-- cineastisches Intro (Energiering, Buchstaben fallen ein, Lichtblitz).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Signal"))

local Controllers = script.Parent :: Instance
local State = require(Controllers:WaitForChild("State"))
local Client = Controllers.Parent :: Instance
local UIFolder = Client:WaitForChild("UI")
local UI = require(UIFolder:WaitForChild("UI"))
local Theme = require(UIFolder:WaitForChild("Theme"))
local VFX = Client:WaitForChild("VFX")
local Effects = require(VFX:WaitForChild("Effects"))

local Menu = {}
Menu.Played = Signal.new() -- (wantsTutorial: boolean)
Menu.OpenCrates = Signal.new()
Menu.OpenShop = Signal.new()

local player = Players.LocalPlayer
local Make = UI.Make
local C = Theme.Colors
local WHITE = Color3.new(1, 1, 1)

local gui: ScreenGui
local camStart = 0
local camOverride: CFrame? = nil

local function orbitCFrame(t: number): CFrame
	local center = Config.World.LobbyCenter + Vector3.new(0, 6, 0)
	local a = t * 0.07 + 0.6
	local pos = center + Vector3.new(math.cos(a) * 78, 30 + math.sin(t * 0.2) * 4, math.sin(a) * 78)
	return CFrame.lookAt(pos, center)
end

local function startCamera()
	local cam = workspace.CurrentCamera :: Camera
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = 60
	camStart = os.clock()
	RunService:BindToRenderStep("NovaMenuCam", Enum.RenderPriority.Camera.Value + 1, function()
		cam.CFrame = camOverride or orbitCFrame(os.clock() - camStart)
	end)
end

local function letterRow(parent: Instance, text: string, size: number, order: number): { TextLabel }
	local row = Make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, size + 10),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.List(row, true, 2, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local letters = {}
	for i = 1, #text do
		local ch = string.sub(text, i, i)
		local holder = Make("Frame", {
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(if ch == " " then size * 0.3 else 0, size),
			LayoutOrder = i,
			Parent = row,
		})
		local label = UI.Text({
			Text = ch,
			Font = Theme.Fonts.Title,
			TextSize = size,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, size),
			TextWrapped = false,
			TextTransparency = 1,
			Parent = holder,
		})
		local stroke = Make("UIStroke", { Thickness = 5, Color = Color3.fromRGB(20, 6, 40), Transparency = 1, Parent = label })
		local g = UI.Gradient(label, Theme.Gradients.Main, 90)
		UI.Animate(g, 0.35, "Offset")
		local _ = stroke
		table.insert(letters, label)
	end
	return letters
end

local function revealLetters(letters: { TextLabel }, delayEach: number, fromY: number)
	for i, label in letters do
		task.delay((i - 1) * delayEach, function()
			label.Position = UDim2.fromOffset(0, fromY)
			label.Rotation = math.random(-25, 25)
			local s = Make("UIScale", { Scale = 1.8, Parent = label })
			UI.Tween(label, 0.55, { Position = UDim2.fromOffset(0, 0), Rotation = 0, TextTransparency = 0 }, Enum.EasingStyle.Back)
			UI.Tween(s, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				UI.Tween(stroke, 0.4, { Transparency = 0 })
			end
			if label.Text ~= " " then
				UI.Sound("Hover", 0.8 + i * 0.05)
			end
		end)
	end
end

function Menu.Show(firstTime: boolean)
	State.MenuOpen = true
	State.SetBusy("Menu", true)
	State.SetHUDHidden("Menu", true)
	startCamera()

	gui = UI.Screen("NovaMenu", 15)
	local root = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	-- Vignette
	for _, d in { { 90, UDim2.fromScale(0, 0) }, { -90, UDim2.fromScale(0, 0.55) } } do
		local v = Make("Frame", {
			BackgroundColor3 = C.Background,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 0.45),
			Position = d[2],
			Parent = root,
		})
		UI.Gradient(v, nil, d[1], NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) }))
	end
	UI.Ambient(root, { Interval = 0.08 })

	local content = Make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1100, 760),
		Parent = root,
	})
	UI.Scaled(content)

	-- Titel
	local titleBox = Make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 80),
		Size = UDim2.new(1, 0, 0, 300),
		Parent = content,
	})
	UI.List(titleBox, false, -18, Enum.HorizontalAlignment.Center)
	local words = string.split(Config.GameName, " ")
	local nova = letterRow(titleBox, words[1] or "NOVA", 150, 1)
	local clash = letterRow(titleBox, words[2] or "CLASH", 150, 2)
	local subtitle = UI.Text({
		Text = "",
		Font = Theme.Fonts.Accent,
		TextSize = 24,
		TextColor3 = C.Text,
		Position = UDim2.fromOffset(0, 400),
		Size = UDim2.new(1, 0, 0, 32),
		Parent = content,
	})
	Make("UIStroke", { Thickness = 2, Color = Color3.fromRGB(20, 6, 40), Parent = subtitle })

	-- Knoepfe
	local buttons = Make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 470),
		Size = UDim2.fromOffset(560, 260),
		Parent = content,
	})
	local playButton = UI.Button({
		Text = "▶  PLAY",
		Style = "Primary",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(380, 84),
		TextSize = 38,
		Parent = buttons,
	})
	local small = Make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 104),
		Size = UDim2.new(1, 0, 0, 60),
		Parent = buttons,
	})
	UI.List(small, true, 14, Enum.HorizontalAlignment.Center)
	local tutorialButton = UI.Button({ Text = "📖 TUTORIAL", Style = "Secondary", Size = UDim2.fromOffset(176, 56), TextSize = 18, LayoutOrder = 1, Parent = small })
	local cratesButton = UI.Button({ Text = "🎁 CRATES", Style = "Gold", Size = UDim2.fromOffset(176, 56), TextSize = 18, LayoutOrder = 2, Parent = small })
	local shopButton = UI.Button({ Text = "💎 SHOP", Style = "Robux", Size = UDim2.fromOffset(176, 56), TextSize = 18, LayoutOrder = 3, Parent = small })
	buttons.Visible = false

	local welcome = UI.Text({
		Text = "Loading your data...",
		Font = Theme.Fonts.Bold,
		TextSize = 18,
		TextColor3 = C.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -20),
		Size = UDim2.fromOffset(600, 26),
		Parent = root,
	})
	local function updateWelcome()
		local p = State.Profile
		if p then
			welcome.Text = (if p.TutorialDone then "Welcome back, " else "Welcome, ") .. player.DisplayName .. "!   🪙 " .. UI.Format(p.Coins)
		end
	end
	updateWelcome()
	local welcomeConn = State.ProfileChanged:Connect(updateWelcome)

	-- Intro-Overlay
	local black = Make("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
		Parent = root,
	})

	local played = false
	local function play(wantsTutorial: boolean)
		if played then
			return
		end
		played = true
		welcomeConn:Disconnect()
		UI.Sound("Fight")
		UI.Tween(buttons, 0.4, { Position = UDim2.new(0.5, 0, 0, 900) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		for _, l in nova do
			UI.Tween(l, 0.5, { TextTransparency = 1, Position = UDim2.fromOffset(0, -120) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		for _, l in clash do
			UI.Tween(l, 0.5, { TextTransparency = 1, Position = UDim2.fromOffset(0, 120) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		UI.Tween(subtitle, 0.3, { TextTransparency = 1 })
		UI.Tween(welcome, 0.3, { TextTransparency = 1 })

		-- Kamerafahrt zum eigenen Charakter
		local char = player.Character or player.CharacterAdded:Wait()
		local root3d = char:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		local cam = workspace.CurrentCamera :: Camera
		local from = cam.CFrame
		if root3d then
			local to = CFrame.lookAt((root3d.CFrame * CFrame.new(0, 4.5, 13)).Position, root3d.Position + Vector3.new(0, 2, 0))
			local t0 = os.clock()
			while os.clock() - t0 < 1.1 do
				local a = Effects.Ease((os.clock() - t0) / 1.1, "InOut")
				camOverride = from:Lerp(to, a)
				cam.FieldOfView = 60 + 10 * a
				task.wait()
			end
		end
		RunService:UnbindFromRenderStep("NovaMenuCam")
		camOverride = nil
		cam.CameraType = Enum.CameraType.Custom
		cam.FieldOfView = 70
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			cam.CameraSubject = hum
		end
		UI.Tween(root, 0.3, { BackgroundTransparency = 1 })
		gui:Destroy()
		State.MenuOpen = false
		State.SetHUDHidden("Menu", false)
		State.SetBusy("Menu", false)
		Menu.Played:Fire(wantsTutorial)
	end
	playButton.Activated:Connect(function()
		play(false)
	end)
	tutorialButton.Activated:Connect(function()
		play(true)
	end)
	cratesButton.Activated:Connect(function()
		Menu.OpenCrates:Fire()
	end)
	shopButton.Activated:Connect(function()
		Menu.OpenShop:Fire()
	end)

	-- Intro abspielen
	task.spawn(function()
		if firstTime then
			task.wait(0.6)
			-- Energiering + Blitz
			local ring = Make("Frame", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.42),
				Size = UDim2.fromOffset(10, 10),
				ZIndex = 21,
				Parent = root,
			})
			UI.Round(ring)
			local rs = UI.Stroke(ring, WHITE, 8, 0)
			UI.Gradient(rs, Theme.Gradients.Main, 0)
			local core = Make("Frame", {
				BackgroundColor3 = WHITE,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.42),
				Size = UDim2.fromOffset(4, 4),
				ZIndex = 21,
				Parent = root,
			})
			UI.Round(core)
			UI.Sound("Charge", 0.8)
			UI.Tween(core, 0.8, { Size = UDim2.fromOffset(60, 60) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.wait(0.8)
			UI.Sound("Holy", 0.6)
			UI.Tween(core, 0.4, { Size = UDim2.fromOffset(2400, 2400), BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
			UI.Tween(ring, 0.9, { Size = UDim2.fromOffset(1800, 1800) }, Enum.EasingStyle.Quart)
			UI.Tween(rs, 0.9, { Transparency = 1, Thickness = 1 }, Enum.EasingStyle.Quart)
			UI.Tween(black, 0.9, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
			UI.Burst(root, UDim2.fromScale(0.5, 0.42), { C.Cyan, C.Magenta, C.Purple, WHITE }, 60, 700)
			task.delay(1, function()
				ring:Destroy()
				core:Destroy()
			end)
			task.wait(0.3)
			revealLetters(nova, 0.09, -160)
			task.wait(0.45)
			revealLetters(clash, 0.09, 160)
			task.wait(0.7)
		else
			UI.Tween(black, 0.7, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
			revealLetters(nova, 0.04, -100)
			revealLetters(clash, 0.04, 100)
			task.wait(0.5)
		end
		-- Untertitel tippen
		local full = string.gsub(Config.Subtitle, "(.)", "%1 ")
		for i = 1, #full do
			subtitle.Text = string.sub(full, 1, i)
			if i % 3 == 0 then
				task.wait(0.02)
			end
		end
		-- Knoepfe hereinfliegen lassen
		buttons.Visible = true
		buttons.Position = UDim2.new(0.5, 0, 0, 640)
		UI.Tween(buttons, 0.6, { Position = UDim2.new(0.5, 0, 0, 470) }, Enum.EasingStyle.Back)
		UI.Sound("Open")
		-- Titel schwebt sanft
		while gui.Parent do
			UI.Tween(titleBox, 2, { Position = UDim2.fromOffset(0, 70) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			task.wait(2)
			if not gui.Parent then
				break
			end
			UI.Tween(titleBox, 2, { Position = UDim2.fromOffset(0, 86) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			task.wait(2)
		end
	end)
end

function Menu.Init() end
function Menu.Start() end

return Menu
