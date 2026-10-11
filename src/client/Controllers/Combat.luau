-- Kampf-Eingaben: Linksklick (M1), F (Block), Q (Dash), 1-4 (Faehigkeiten).
-- Auf Touch-Geraeten erscheinen grosse Kampf-Knoepfe.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))
local Abilities = require(Shared:WaitForChild("Abilities"))

local Controllers = script.Parent :: Instance
local State = require(Controllers:WaitForChild("State"))
local HUD = require(Controllers:WaitForChild("HUD"))
local Client = Controllers.Parent :: Instance
local VFX = Client:WaitForChild("VFX")
local CombatVFX = require(VFX:WaitForChild("CombatVFX"))
local Effects = require(VFX:WaitForChild("Effects"))
local UIFolder = Client:WaitForChild("UI")
local UI = require(UIFolder:WaitForChild("UI"))
local Theme = require(UIFolder:WaitForChild("Theme"))

local Combat = {}

local player = Players.LocalPlayer
local CombatInput = Net.Event("CombatInput")
local CombatConfig = Config.Combat

local combo = 0
local lastM1 = 0
local nextM1 = 0
local blocking = false
local mouseDown = false

local function character(): Model?
	return player.Character
end

local function root(): BasePart?
	local c = character()
	return if c then c:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

-- Darf der Spieler gerade kaempfen?
local function canFight(): boolean
	if State.MenuOpen or State.InCrateOpening or State.InCutscene or UI.AnyWindowOpen() then
		return false
	end
	local c = character()
	if not c then
		return false
	end
	local hum = c:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return false
	end
	if c:GetAttribute("Stunned") or c:GetAttribute("Frozen") or c:GetAttribute("InCutscene") then
		return false
	end
	return true
end

-- Zielpunkt: Maus (PC) oder Bildschirmmitte (Touch / Shift-Lock)
local function aimPoint(): Vector3
	local cam = workspace.CurrentCamera :: Camera
	local pos: Vector2
	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter or UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		pos = cam.ViewportSize / 2
	else
		pos = UserInputService:GetMouseLocation()
	end
	local ray = cam:ViewportPointToRay(pos.X, pos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { Effects.Folder }
	local c = character()
	if c then
		table.insert(exclude, c)
	end
	params.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	if hit then
		return hit.Position
	end
	return ray.Origin + ray.Direction * 120
end

local function faceTowards(point: Vector3)
	local r = root()
	if not r or r.Anchored then
		return
	end
	local pos = r.Position
	local target = Vector3.new(point.X, pos.Y, point.Z)
	if (target - pos).Magnitude > 0.5 then
		r.CFrame = CFrame.lookAt(pos, target)
	end
end

-- Aktionen ---------------------------------------------------------------------

function Combat.M1()
	if not canFight() or blocking then
		return
	end
	local t = os.clock()
	if t < nextM1 then
		return
	end
	if t - lastM1 > CombatConfig.M1ComboReset then
		combo = 0
	end
	combo = combo % 4 + 1
	lastM1 = t
	nextM1 = t + (if combo == 4 then CombatConfig.M1FinisherCooldown else CombatConfig.M1Cooldown)
	CombatVFX.M1({ Caster = character(), Combo = combo })
	CombatInput:FireServer("M1")
end

function Combat.SetBlock(on: boolean)
	if on and not canFight() then
		return
	end
	if blocking == on then
		return
	end
	blocking = on
	CombatInput:FireServer("Block", on)
	if on then
		State.TutorialEvent:Fire("Block")
	end
end

function Combat.Dash()
	if not canFight() or blocking then
		return
	end
	local t = os.clock()
	if t < HUD.DashReadyAt then
		return
	end
	local r = root()
	local c = character()
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if not r or not hum or r.Anchored then
		return
	end
	HUD.DashReadyAt = t + CombatConfig.DashCooldown
	local move = hum.MoveDirection
	local dir = if move.Magnitude > 0.1 then Vector3.new(move.X, 0, move.Z).Unit else Vector3.new(r.CFrame.LookVector.X, 0, r.CFrame.LookVector.Z).Unit
	-- Bewegung lokal (der Client besitzt die Physik seines Charakters)
	local att = Instance.new("Attachment")
	att.Parent = r
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.MaxForce = 50000
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PrimaryTangentAxis = Vector3.xAxis
	lv.SecondaryTangentAxis = Vector3.zAxis
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.PlaneVelocity = Vector2.new(dir.X, dir.Z) * CombatConfig.DashSpeed
	lv.Parent = r
	task.delay(CombatConfig.DashDuration, function()
		lv:Destroy()
		att:Destroy()
	end)
	CombatVFX.Dash({ Caster = c, Direction = dir })
	CombatInput:FireServer("Dash", dir)
	State.TutorialEvent:Fire("Dash")
end

function Combat.UseAbility(slot: number)
	if not canFight() or blocking then
		return
	end
	local profile = State.Profile
	if not profile then
		return
	end
	local id = profile.Equipped[slot]
	local def = Abilities.Get(id)
	if not def then
		return
	end
	if HUD.IsOnCooldown(def.Id) then
		return
	end
	local aim = aimPoint()
	if def.Aim ~= "Self" then
		faceTowards(aim)
	end
	CombatInput:FireServer("Ability", slot, aim)
end

-- Touch-Knoepfe -------------------------------------------------------------------

local function buildTouchButtons()
	local gui = UI.Screen("NovaTouch", 6)
	local holder = UI.Make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -220),
		Size = UDim2.fromOffset(260, 220),
		Parent = gui,
	})
	UI.Scaled(holder)
	local function round(icon: string, size: number, pos: UDim2, gradient: ColorSequence): TextButton
		local b = UI.Make("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.15,
			Size = UDim2.fromOffset(size, size),
			Position = pos,
			Parent = holder,
		})
		UI.Round(b)
		UI.Gradient(b, gradient, 45)
		UI.Stroke(b, Color3.new(1, 1, 1), 2, 0.4)
		UI.Text({ Text = icon, TextSize = size * 0.45, Size = UDim2.fromScale(1, 1), Parent = b })
		return b
	end
	local attack = round("👊", 110, UDim2.fromOffset(140, 100), Theme.Gradients.Danger)
	local block = round("🛡️", 76, UDim2.fromOffset(40, 140), Theme.Gradients.Main)
	local dash = round("💨", 76, UDim2.fromOffset(160, 0), ColorSequence.new(Theme.Colors.Cyan, Theme.Colors.Purple))
	attack.MouseButton1Down:Connect(function()
		mouseDown = true
		Combat.M1()
	end)
	attack.MouseButton1Up:Connect(function()
		mouseDown = false
	end)
	block.MouseButton1Down:Connect(function()
		Combat.SetBlock(true)
	end)
	block.MouseButton1Up:Connect(function()
		Combat.SetBlock(false)
	end)
	block.MouseLeave:Connect(function()
		Combat.SetBlock(false)
	end)
	dash.Activated:Connect(Combat.Dash)
	State.HUDVisibilityChanged:Connect(function(hidden: boolean)
		gui.Enabled = not hidden
	end)
	gui.Enabled = not State.IsHUDHidden()
end

-- Init ----------------------------------------------------------------------------

local KEY_SLOTS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.KeypadThree] = 3,
	[Enum.KeyCode.KeypadFour] = 4,
	[Enum.KeyCode.ButtonX] = 1,
	[Enum.KeyCode.ButtonY] = 2,
	[Enum.KeyCode.DPadLeft] = 3,
	[Enum.KeyCode.DPadUp] = 4,
}

function Combat.Init() end

function Combat.Start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouseDown = true
			Combat.M1()
		elseif input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonL2 then
			Combat.SetBlock(true)
		elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonR1 then
			Combat.Dash()
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			mouseDown = true
			Combat.M1()
		else
			local slot = KEY_SLOTS[input.KeyCode]
			if slot then
				Combat.UseAbility(slot)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			mouseDown = false
		elseif input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonL2 then
			Combat.SetBlock(false)
		end
	end)
	-- Gedrueckt halten = weiter schlagen
	RunService.Heartbeat:Connect(function()
		if mouseDown then
			Combat.M1()
		end
	end)
	HUD.AbilitySlotPressed:Connect(Combat.UseAbility)
	player.CharacterAdded:Connect(function()
		blocking = false
		combo = 0
	end)
	if UserInputService.TouchEnabled then
		buildTouchButtons()
	end
end

return Combat
