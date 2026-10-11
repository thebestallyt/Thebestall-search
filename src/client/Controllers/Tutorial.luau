-- Interaktives Tutorial: Schritt-Karte, Leuchtpfad zu den Trainingspuppen, Pfeile auf HUD-Knoepfe.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Signal"))

local Controllers = script.Parent :: Instance
local State = require(Controllers:WaitForChild("State"))
local HUD = require(Controllers:WaitForChild("HUD"))
local Client = Controllers.Parent :: Instance
local UIFolder = Client:WaitForChild("UI")
local UI = require(UIFolder:WaitForChild("UI"))
local Theme = require(UIFolder:WaitForChild("Theme"))
local VFX = Client:WaitForChild("VFX")
local Effects = require(VFX:WaitForChild("Effects"))

local Tutorial = {}
Tutorial.Finished = Signal.new()

local player = Players.LocalPlayer
local Make = UI.Make
local C = Theme.Colors

local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

type Step = { Title: string, Text: string, Wait: string?, Count: number?, Button: string?, Highlight: string?, Guide: boolean?, Skip: (() -> boolean)? }

local STEPS: { Step } = {
	{
		Title = "WELCOME TO NOVA CLASH!",
		Text = "Battle in the arena with spectacular abilities. Let's learn the basics – it only takes a minute!",
		Button = "LET'S GO",
	},
	{
		Title = "MOVEMENT",
		Text = if touch then "Use the joystick to move and the jump button to jump." else "Move with  W A S D  and jump with  SPACE.",
		Wait = "Move",
	},
	{
		Title = "ATTACK",
		Text = (if touch then "Follow the glowing path to the TRAINING DUMMIES and tap 👊 to attack." else "Follow the glowing path to the TRAINING DUMMIES and attack with LEFT CLICK.")
			.. " Land 4 hits for a full combo!",
		Wait = "DummyHit",
		Count = 4,
		Guide = true,
	},
	{
		Title = "BLOCK",
		Text = (if touch then "Hold 🛡️ to BLOCK." else "Hold  F  to BLOCK.") .. " Blocking reduces damage by 75% – but the 4th hit of a combo breaks your guard!",
		Wait = "Block",
	},
	{
		Title = "DASH",
		Text = (if touch then "Tap 💨 to DASH" else "Press  Q  to DASH") .. " and dodge incoming attacks.",
		Wait = "Dash",
	},
	{
		Title = "ABILITIES",
		Text = (if touch then "Tap ability slot 1" else "Press  1") .. " to unleash your first ability: EMBER PUNCH! Try it on a dummy.",
		Wait = "AbilityUsed",
		Guide = true,
	},
	{
		Title = "CRATES",
		Text = "New abilities come from CRATES – the rarer, the more insane the VFX. Open your FREE starter crate!",
		Wait = "CrateOpened",
		Highlight = "Crates",
		Skip = function()
			return not (State.Profile and State.Profile.FreeCrate)
		end,
	},
	{
		Title = "YOUR LOADOUT",
		Text = "New abilities are placed on a free key automatically. Open ABILITIES to preview them or swap slots.",
		Button = "GOT IT",
		Highlight = "Inventory",
	},
	{
		Title = "ROUNDS",
		Text = "Rounds start automatically – the last fighter standing wins coins! MYTHIC and DIVINE abilities even have their own CUTSCENES. And check out the exclusive BLACK HOLE in the 💎 SHOP!",
		Button = "START PLAYING",
		Highlight = "Shop",
	},
}

local gui: ScreenGui
local card: Frame
local stepLabel: TextLabel
local titleLabel: TextLabel
local textLabel: TextLabel
local progressBack: Frame
local progressFill: Frame
local nextButton: TextButton
local pointer: TextLabel
local running = false
local currentHighlight: string? = nil
local guide: { Beam: Beam?, A0: Attachment?, Anchor: BasePart? } = {}

local DUMMY_SPOT = Config.World.LobbyCenter + Vector3.new(-36, 2, -22)

local function setGuide(on: boolean)
	if guide.Beam then
		guide.Beam:Destroy()
	end
	if guide.A0 then
		guide.A0:Destroy()
	end
	if guide.Anchor then
		guide.Anchor:Destroy()
	end
	guide = {}
	if not on then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local anchor, a1 = Effects.Anchor(DUMMY_SPOT)
	local a0 = Make("Attachment", { Position = Vector3.new(0, -2.5, 0), Parent = root })
	local beam = Make("Beam", {
		Attachment0 = a0,
		Attachment1 = a1,
		Color = ColorSequence.new(C.Cyan, C.Gold),
		Width0 = 0.6,
		Width1 = 1.2,
		LightEmission = 1,
		LightInfluence = 0,
		FaceCamera = true,
		Segments = 20,
		CurveSize0 = 6,
		CurveSize1 = -4,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(0.5, 0.1),
			NumberSequenceKeypoint.new(1, 0.2),
		}),
		Parent = anchor,
	})
	-- Pulsierender Ring am Ziel
	task.spawn(function()
		while beam.Parent do
			Effects.GroundRing(DUMMY_SPOT - Vector3.new(0, 1.6, 0), 1, 8, C.Gold, 0.9, 0.5)
			task.wait(1)
		end
	end)
	guide = { Beam = beam, A0 = a0, Anchor = anchor }
end

local function showCard(index: number, step: Step)
	stepLabel.Text = "STEP " .. index .. " / " .. #STEPS
	titleLabel.Text = step.Title
	textLabel.Text = step.Text
	progressBack.Visible = step.Count ~= nil
	progressFill.Size = UDim2.fromScale(0, 1)
	nextButton.Visible = step.Button ~= nil
	if step.Button then
		UI.SetButtonText(nextButton, step.Button)
	end
	currentHighlight = step.Highlight
	pointer.Visible = step.Highlight ~= nil
	UI.Pop(card, 0.85, 0.35)
	UI.Sound("Tutorial")
end

local function completeFlash()
	UI.Sound("Coins", 1.4)
	UI.Burst(gui, UDim2.new(0.5, 0, 0, 200), { C.Cyan, C.Gold, C.Success }, 24, 260)
end

-- Wartet auf eine Aktion des Spielers
local function waitFor(step: Step): boolean
	if step.Button then
		local pressed = false
		local conn = nextButton.Activated:Connect(function()
			pressed = true
		end)
		while running and not pressed do
			task.wait()
		end
		conn:Disconnect()
		return running
	end
	if step.Wait == "Move" then
		local char = player.Character or player.CharacterAdded:Wait()
		local root = char:WaitForChild("HumanoidRootPart") :: BasePart
		local start = root.Position
		while running do
			local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if r and (r.Position - start).Magnitude > 12 then
				break
			end
			task.wait(0.1)
		end
		return running
	end
	local needed = step.Count or 1
	local count = 0
	local conn = State.TutorialEvent:Connect(function(name)
		if name == step.Wait then
			count += 1
			if step.Count then
				UI.Tween(progressFill, 0.2, { Size = UDim2.fromScale(math.clamp(count / needed, 0, 1), 1) })
				UI.Sound("Hover", 1 + count * 0.15)
			end
		end
	end)
	while running and count < needed do
		task.wait()
	end
	conn:Disconnect()
	return running
end

local function finish(completed: boolean)
	running = false
	setGuide(false)
	gui.Enabled = false
	State.TutorialActive = false
	State.SetBusy("Tutorial", false)
	Net.Event("TutorialDone"):FireServer()
	if completed then
		HUD.Announce({ Text = "YOU'RE READY!", Sub = "Win rounds, open crates, collect them all.", Style = "Victory", Duration = 3 })
	end
	Tutorial.Finished:Fire()
end

function Tutorial.Begin()
	if running then
		return
	end
	running = true
	State.TutorialActive = true
	State.SetBusy("Tutorial", true)
	gui.Enabled = true
	task.spawn(function()
		for i, step in STEPS do
			if not running then
				return
			end
			if step.Skip and step.Skip() then
				continue
			end
			showCard(i, step)
			setGuide(step.Guide == true)
			if not waitFor(step) then
				return
			end
			setGuide(false)
			completeFlash()
			task.wait(0.5)
		end
		if running then
			finish(true)
		end
	end)
end

function Tutorial.IsRunning(): boolean
	return running
end

function Tutorial.Init()
	gui = UI.Screen("NovaTutorial", 25)
	gui.Enabled = false
	card = UI.Panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 100),
		Size = UDim2.fromOffset(640, 190),
		StrokeColor = Theme.Gradients.Gold,
		Parent = gui,
	})
	UI.Scaled(card)
	stepLabel = UI.Text({
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 13,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(24, 12),
		Size = UDim2.fromOffset(200, 18),
		Parent = card,
	})
	titleLabel = UI.Text({
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(24, 30),
		Size = UDim2.new(1, -48, 0, 34),
		TextWrapped = false,
		Parent = card,
	})
	UI.Gradient(titleLabel, Theme.Gradients.Main, 0)
	textLabel = UI.Text({
		Text = "",
		Font = Theme.Fonts.Body,
		TextSize = 17,
		TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(24, 68),
		Size = UDim2.new(1, -48, 0, 62),
		Parent = card,
	})
	progressBack = Make("Frame", {
		BackgroundColor3 = Color3.fromRGB(12, 10, 24),
		Position = UDim2.new(0, 24, 1, -36),
		Size = UDim2.new(1, -230, 0, 14),
		Parent = card,
	})
	UI.Round(progressBack)
	progressFill = Make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(0, 1), Parent = progressBack })
	UI.Round(progressFill)
	UI.Gradient(progressFill, Theme.Gradients.Success, 0)
	nextButton = UI.Button({
		Text = "NEXT",
		Style = "Primary",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -14),
		Size = UDim2.fromOffset(190, 48),
		TextSize = 18,
		Parent = card,
	})
	local skip = Make("TextButton", {
		Text = "Skip tutorial ✕",
		Font = Theme.Fonts.Bold,
		TextSize = 13,
		TextColor3 = C.Muted,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 10),
		Size = UDim2.fromOffset(130, 20),
		Parent = card,
	})
	skip.Activated:Connect(function()
		if running then
			finish(false)
		end
	end)
	pointer = UI.Text({
		Text = "👈",
		TextSize = 48,
		Size = UDim2.fromOffset(60, 60),
		AnchorPoint = Vector2.new(0, 0.5),
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	})
	State.HUDVisibilityChanged:Connect(function(hidden: boolean)
		if running then
			gui.Enabled = not hidden
		end
	end)
	RunService.RenderStepped:Connect(function()
		if not running or not currentHighlight then
			return
		end
		local target = HUD.MenuButtons[currentHighlight]
		if target and target.Visible then
			local pos = target.AbsolutePosition
			local size = target.AbsoluteSize
			local bounce = math.sin(os.clock() * 6) * 10
			pointer.Position = UDim2.fromOffset(pos.X + size.X + 10 + bounce, pos.Y + size.Y / 2)
		end
	end)
end

function Tutorial.Start()
	player.CharacterAdded:Connect(function()
		if running and guide.Beam then
			task.wait(0.5)
			setGuide(true)
		end
	end)
end

return Tutorial
