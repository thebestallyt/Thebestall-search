-- Welt-Atmosphaere auf dem Client: rotierende/schwebende Deko, Lebensbalken ueber Kaempfern,
-- ProximityPrompts (Kisten-Altar / Black-Hole-Schrein).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")

local Controllers = script.Parent :: Instance
local Client = Controllers.Parent :: Instance
local UIFolder = Client:WaitForChild("UI")
local UI = require(UIFolder:WaitForChild("UI"))
local Theme = require(UIFolder:WaitForChild("Theme"))

local Ambient = {}
Ambient.PromptTriggered = nil :: ((string) -> ())?

local player = Players.LocalPlayer
local Make = UI.Make
local C = Theme.Colors

type Animated = { inst: Instance, base: CFrame, phase: number, spin: boolean, float: boolean }
local animated: { [Instance]: Animated } = {}

local function baseCFrame(inst: Instance): CFrame?
	if inst:IsA("Model") then
		return (inst :: Model):GetPivot()
	elseif inst:IsA("BasePart") then
		return (inst :: BasePart).CFrame
	end
	return nil
end

local function track(inst: Instance)
	local cf = baseCFrame(inst)
	if not cf then
		return
	end
	local entry = animated[inst]
	if not entry then
		entry = {
			inst = inst,
			base = cf,
			phase = (cf.Position.X * 0.13 + cf.Position.Z * 0.07) % (math.pi * 2),
			spin = false,
			float = false,
		}
		animated[inst] = entry
	end
	entry.spin = entry.spin or CollectionService:HasTag(inst, "Spin")
	entry.float = entry.float or CollectionService:HasTag(inst, "Float")
end

-- Lebensbalken ueber Kaempfern -----------------------------------------------------

local function attachBar(character: Model)
	if character == player.Character then
		return
	end
	local head = character:WaitForChild("Head", 10) :: BasePart?
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not head or not humanoid then
		return
	end
	if head:FindFirstChild("NovaBar") then
		return
	end
	local gui = Make("BillboardGui", {
		Name = "NovaBar",
		Size = UDim2.fromOffset(150, 46),
		StudsOffset = Vector3.new(0, 2.4, 0),
		AlwaysOnTop = false,
		LightInfluence = 0,
		MaxDistance = 110,
		Parent = head,
	})
	local name = UI.Text({
		Text = character:GetAttribute("DisplayName") or character.Name,
		Font = Theme.Fonts.Title,
		TextSize = 15,
		Size = UDim2.new(1, 0, 0, 18),
		TextWrapped = false,
		Parent = gui,
	})
	Make("UIStroke", { Thickness = 2, Parent = name })
	local back = Make("Frame", {
		BackgroundColor3 = Color3.fromRGB(12, 10, 24),
		Position = UDim2.fromOffset(15, 22),
		Size = UDim2.new(1, -30, 0, 10),
		Parent = gui,
	})
	UI.Round(back)
	UI.Stroke(back, Color3.new(0, 0, 0), 1.5, 0.2)
	local trail = Make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), Parent = back })
	UI.Round(trail)
	local fill = Make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), Parent = back })
	UI.Round(fill)
	local grad = UI.Gradient(fill, Theme.Gradients.Health, 0)
	local status = UI.Text({
		Text = "",
		TextSize = 14,
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = gui,
	})
	local function update()
		local ratio = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
		UI.Tween(fill, 0.15, { Size = UDim2.fromScale(ratio, 1) })
		task.delay(0.3, function()
			UI.Tween(trail, 0.4, { Size = UDim2.fromScale(ratio, 1) })
		end)
		grad.Color = if ratio < 0.3 then Theme.Gradients.HealthLow else Theme.Gradients.Health
	end
	local function updateStatus()
		local parts = {}
		if character:GetAttribute("Blocking") then
			table.insert(parts, "🛡️")
		end
		if character:GetAttribute("Stunned") then
			table.insert(parts, "💫")
		end
		if character:GetAttribute("Slowed") then
			table.insert(parts, "❄️")
		end
		status.Text = table.concat(parts, " ")
	end
	local function updateVisible()
		gui.Enabled = character:GetAttribute("InRound") == true or character:GetAttribute("Dummy") == true
	end
	humanoid.HealthChanged:Connect(update)
	for _, attr in { "Blocking", "Stunned", "Slowed" } do
		character:GetAttributeChangedSignal(attr):Connect(updateStatus)
	end
	character:GetAttributeChangedSignal("InRound"):Connect(updateVisible)
	update()
	updateStatus()
	updateVisible()
	local _ = C
end

local function watchCharacter(character: Instance)
	if character:IsA("Model") then
		if character:GetAttribute("Fighter") then
			task.spawn(attachBar, character :: Model)
		else
			character:GetAttributeChangedSignal("Fighter"):Connect(function()
				if character:GetAttribute("Fighter") then
					task.spawn(attachBar, character :: Model)
				end
			end)
		end
	end
end

function Ambient.Init() end

function Ambient.Start()
	for _, tag in { "Spin", "Float" } do
		for _, inst in CollectionService:GetTagged(tag) do
			track(inst)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(track)
	end
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for inst, e in animated do
			if not inst.Parent then
				animated[inst] = nil
				continue
			end
			local cf = e.base
			if e.float then
				cf = cf * CFrame.new(0, math.sin(t * 1.1 + e.phase) * 0.9, 0)
			end
			if e.spin then
				cf = cf * CFrame.Angles(0, t * 0.6 + e.phase, 0)
			end
			if inst:IsA("Model") then
				(inst :: Model):PivotTo(cf)
			elseif inst:IsA("BasePart") then
				(inst :: BasePart).CFrame = cf
			end
		end
	end)

	-- Lebensbalken fuer alle Kaempfer
	local function onPlayer(plr: Player)
		plr.CharacterAdded:Connect(watchCharacter)
		if plr.Character then
			watchCharacter(plr.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, plr in Players:GetPlayers() do
		onPlayer(plr)
	end
	task.spawn(function()
		local npcs = workspace:WaitForChild("NPCs", 30)
		if npcs then
			npcs.ChildAdded:Connect(watchCharacter)
			for _, m in npcs:GetChildren() do
				watchCharacter(m)
			end
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if Ambient.PromptTriggered then
			Ambient.PromptTriggered(prompt.Name)
		end
	end)
end

return Ambient
