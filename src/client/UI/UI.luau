-- UI-Bausteine im "Chunky Game UI"-Stil (siehe Theme.luau):
-- Panels mit dicken Umrissen, 3D-Buttons mit Lippe, Fenster mit farbiger Kopfleiste,
-- Faehigkeits-Kacheln, Fortschrittsbalken, Tabs, Konfetti, Zaehler.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Make = require(Shared:WaitForChild("Make"))
local Signal = require(Shared:WaitForChild("Signal"))
local Abilities = require(Shared:WaitForChild("Abilities"))
local Rarities = require(Shared:WaitForChild("Rarities"))

local UIFolder = script.Parent :: Instance
local Theme = require(UIFolder:WaitForChild("Theme"))
local Client = UIFolder.Parent :: Instance
local VFX = Client:WaitForChild("VFX")
local Effects = require(VFX:WaitForChild("Effects"))

local UI = {}
UI.Make = Make
UI.Theme = Theme

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local C = Theme.Colors
local F = Theme.Fonts

-- Allgemein ----------------------------------------------------------------

function UI.Tween(inst: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?, delay: number?): Tween
	local t = TweenService:Create(
		inst,
		TweenInfo.new(time, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out, 0, false, delay or 0),
		props
	)
	t:Play()
	return t
end

function UI.Sound(name: string, pitch: number?)
	Effects.Sound(name, nil, { Pitch = pitch or 1, Variance = 0.02 })
end

-- 12345 -> "12,345"
function UI.Format(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

function UI.Screen(name: string, displayOrder: number): ScreenGui
	local existing = playerGui:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	return Make("ScreenGui", {
		Name = name,
		DisplayOrder = displayOrder,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
end

-- Globale Skalierung je nach Bildschirmgroesse --------------------------------------

UI.ScaleChanged = Signal.new()
UI.Scale = 1
local scaled: { UIScale } = {}

local function computeScale(): number
	local cam = workspace.CurrentCamera
	if not cam then
		return 1
	end
	local v = cam.ViewportSize
	return math.clamp(math.min(v.X / 1400, v.Y / 820), 0.5, 1.2)
end

local function updateScale()
	UI.Scale = computeScale()
	for i = #scaled, 1, -1 do
		local s = scaled[i]
		if s.Parent then
			s.Scale = UI.Scale
		else
			table.remove(scaled, i)
		end
	end
	UI.ScaleChanged:Fire(UI.Scale)
end

-- Haengt eine UIScale an, die der Bildschirmgroesse folgt
function UI.Scaled(obj: GuiObject): UIScale
	local s = Make("UIScale", { Name = "AutoScale", Scale = UI.Scale, Parent = obj })
	table.insert(scaled, s)
	return s
end

task.defer(function()
	updateScale()
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
end)

-- Dekoration --------------------------------------------------------------------

function UI.Corner(parent: Instance, radius: number?): UICorner
	return Make("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Radius), Parent = parent })
end

function UI.Round(parent: Instance): UICorner
	return Make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = parent })
end

function UI.Stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	return Make("UIStroke", {
		Color = color or C.Ink,
		Thickness = thickness or Theme.Outline,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

-- Text-Kontur (fuer gut lesbaren Text ueber der Welt)
function UI.TextStroke(label: Instance, thickness: number?, color: Color3?): UIStroke
	return Make("UIStroke", {
		Color = color or C.Ink,
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = label,
	})
end

function UI.Gradient(parent: Instance, color: ColorSequence?, rotation: number?, transparency: NumberSequence?): UIGradient
	return Make("UIGradient", {
		Color = color or ColorSequence.new(Color3.new(1, 1, 1)),
		Rotation = rotation or 0,
		Transparency = transparency or NumberSequence.new(0),
		Parent = parent,
	})
end

-- Dezente Licht-von-oben-Schattierung auf farbigen Flaechen
function UI.Shade(parent: Instance, soft: boolean?): UIGradient
	return UI.Gradient(parent, if soft then Theme.Gradients.SoftShade else Theme.Gradients.Shade, 90)
end

function UI.Padding(parent: Instance, px: number)
	return Make("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		Parent = parent,
	})
end

function UI.List(parent: Instance, horizontal: boolean?, padding: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	return Make("UIListLayout", {
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 8),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

-- Text ------------------------------------------------------------------------------
-- Zusatz-Props: Stroke = Dicke der Textkontur (z.B. 2), StrokeColor = Farbe der Kontur

function UI.Text(props: { [string]: any }): TextLabel
	local label = Make("TextLabel", {
		BackgroundTransparency = 1,
		Font = F.Bold,
		TextColor3 = C.Text,
		TextSize = 18,
		Text = "",
		TextWrapped = true,
		RichText = true,
	})
	for k, v in props do
		if k ~= "Parent" and k ~= "Stroke" and k ~= "StrokeColor" then
			(label :: any)[k] = v
		end
	end
	if props.Stroke then
		UI.TextStroke(label, props.Stroke, props.StrokeColor)
	end
	label.Parent = props.Parent
	return label
end

-- Panels ---------------------------------------------------------------------------
-- Zusatz-Props: Color (Color3), Radius, NoStroke, StrokeColor (Color3), NoShade

function UI.Panel(props: { [string]: any }): Frame
	local frame = Make("Frame", {
		BackgroundColor3 = props.Color or C.Panel,
		BorderSizePixel = 0,
	})
	for k, v in props do
		if k ~= "Parent" and k ~= "StrokeColor" and k ~= "Radius" and k ~= "NoStroke" and k ~= "Color" and k ~= "NoShade" then
			(frame :: any)[k] = v
		end
	end
	UI.Corner(frame, props.Radius or Theme.Radius)
	if not props.NoShade then
		UI.Shade(frame, true)
	end
	if not props.NoStroke then
		local strokeColor = props.StrokeColor
		if typeof(strokeColor) == "ColorSequence" then
			strokeColor = (strokeColor :: ColorSequence).Keypoints[1].Value
		end
		UI.Stroke(frame, strokeColor or C.Ink, Theme.Outline, 0)
	end
	frame.Parent = props.Parent
	return frame
end

-- Erhobene Karte innerhalb eines Panels
function UI.Card(props: { [string]: any }): Frame
	props.Color = props.Color or C.PanelLight
	props.Radius = props.Radius or 10
	return UI.Panel(props)
end

-- Vertiefte Flaeche (Slots, Listen)
function UI.Inset(props: { [string]: any }): Frame
	props.Color = props.Color or C.PanelDark
	props.NoShade = true
	local f = UI.Panel(props)
	local stroke = f:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = 2
		stroke.Transparency = 0.3
	end
	return f
end

-- Schlagschatten hinter einem Element (als Geschwister, folgt Position/Groesse)
function UI.Shadow(target: GuiObject, offset: number?, transparency: number?): Frame
	local o = offset or 6
	local shadow = Make("Frame", {
		Name = target.Name .. "_Shadow",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = transparency or 0.55,
		BorderSizePixel = 0,
		ZIndex = target.ZIndex - 1,
	})
	local corner = target:FindFirstChildOfClass("UICorner")
	if corner then
		Make("UICorner", { CornerRadius = corner.CornerRadius, Parent = shadow })
	end
	local function sync()
		shadow.AnchorPoint = target.AnchorPoint
		shadow.Size = target.Size
		shadow.Position = target.Position + UDim2.fromOffset(0, o)
		shadow.Visible = target.Visible
		shadow.LayoutOrder = target.LayoutOrder
	end
	sync()
	for _, prop in { "Position", "Size", "AnchorPoint", "Visible" } do
		target:GetPropertyChangedSignal(prop):Connect(sync)
	end
	target.AncestryChanged:Connect(function()
		if not target.Parent then
			shadow:Destroy()
		end
	end)
	shadow.Parent = target.Parent
	return shadow
end

-- Animierte Verlaeufe (ein gemeinsamer Loop) ----------------------------------------

type GradAnim = { g: UIGradient, speed: number, mode: string }
local gradAnims: { GradAnim } = {}

function UI.Animate(g: UIGradient, speed: number, mode: string?)
	table.insert(gradAnims, { g = g, speed = speed, mode = mode or "Offset" })
end

RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	for i = #gradAnims, 1, -1 do
		local a = gradAnims[i]
		if not a.g.Parent then
			table.remove(gradAnims, i)
			continue
		end
		if a.mode == "Rotate" then
			a.g.Rotation = (a.g.Rotation + a.speed * dt) % 360
		else
			local x = ((t * a.speed) % 2) - 1
			a.g.Offset = Vector2.new(x, 0)
		end
	end
end)

-- Glanz, der ueber ein Element huscht (sparsam einsetzen: nur PLAY / Premium)
function UI.Shine(button: GuiObject, interval: number?)
	local holder = button:FindFirstChild("Face") or button
	local shine = Make("Frame", {
		Name = "Shine",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.new(0.18, 0, 2, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(-0.3, 0.5),
		Rotation = 18,
		BackgroundTransparency = 0.7,
		ZIndex = (holder :: GuiObject).ZIndex + 1,
		Parent = holder,
	})
	UI.Gradient(shine, nil, 0, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	}))
	task.spawn(function()
		while shine.Parent do
			shine.Position = UDim2.fromScale(-0.3, 0.5)
			UI.Tween(shine, 0.6, { Position = UDim2.fromScale(1.3, 0.5) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
			task.wait((interval or 3.2) + math.random() * 1.2)
		end
	end)
end

-- 3D-Buttons ----------------------------------------------------------------------------
-- Aufbau: TextButton (unsichtbar)  ->  "Lip" (dunkle Unterkante)  +  "Face" (Farbflaeche) -> "Label"

export type ButtonProps = {
	Text: string?,
	Style: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	TextSize: number?,
	Parent: Instance?,
	OnClick: (() -> ())?,
	LayoutOrder: number?,
	Font: Enum.Font?,
	ZIndex: number?,
	Name: string?,
	Shine: boolean?,
	Lip: number?,
}

local function styleOf(name: string?): { Fill: Color3, Lip: Color3 }
	return Theme.ButtonStyles[name or "Green"] or Theme.ButtonStyles.Green
end

function UI.Button(props: ButtonProps): TextButton
	local style = styleOf(props.Style)
	local lipH = props.Lip or Theme.Lip
	local z = props.ZIndex or 1
	local button = Make("TextButton", {
		Name = props.Name or "Button",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Text = "",
		Size = props.Size or UDim2.fromOffset(200, 56),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = z,
	})
	local lip = Make("Frame", {
		Name = "Lip",
		BackgroundColor3 = style.Lip,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, lipH),
		Size = UDim2.new(1, 0, 1, -lipH),
		ZIndex = z,
		Parent = button,
	})
	UI.Corner(lip, 12)
	UI.Stroke(lip, C.Ink, 2.5, 0)
	local face = Make("Frame", {
		Name = "Face",
		BackgroundColor3 = style.Fill,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -lipH),
		ZIndex = z + 1,
		ClipsDescendants = true,
		Parent = button,
	})
	UI.Corner(face, 12)
	UI.Stroke(face, C.Ink, 2.5, 0)
	UI.Shade(face)
	-- Glanzkante oben
	local gloss = Make("Frame", {
		Name = "Gloss",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 5, 0, 4),
		Size = UDim2.new(1, -10, 0.38, 0),
		ZIndex = z + 1,
		Parent = face,
	})
	UI.Corner(gloss, 8)
	local label = UI.Text({
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		Text = props.Text or "",
		TextSize = props.TextSize or 22,
		Font = props.Font or F.Heading,
		TextWrapped = false,
		ZIndex = z + 2,
		Stroke = 2,
		StrokeColor = Theme.Darken(style.Lip, 0.45),
		Parent = face,
	})
	local _ = label
	if props.Shine then
		UI.Shine(button)
	end

	local hovering = false
	local function setPressed(pressed: boolean)
		UI.Tween(face, 0.07, { Position = UDim2.fromOffset(0, if pressed then lipH - 1 else 0) }, Enum.EasingStyle.Quad)
	end
	button.MouseEnter:Connect(function()
		hovering = true
		local s = styleOf(button:GetAttribute("Style") or props.Style)
		UI.Tween(face, 0.12, { BackgroundColor3 = Theme.Lighten(s.Fill, 0.14) })
		UI.Sound("Hover")
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		local s = styleOf(button:GetAttribute("Style") or props.Style)
		UI.Tween(face, 0.15, { BackgroundColor3 = s.Fill })
		setPressed(false)
	end)
	button.MouseButton1Down:Connect(function()
		setPressed(true)
	end)
	button.MouseButton1Up:Connect(function()
		setPressed(false)
	end)
	button.Activated:Connect(function()
		if button:GetAttribute("Disabled") then
			UI.Shake(button)
			return
		end
		UI.Sound("Click")
		if not hovering then
			setPressed(true)
			task.delay(0.08, function()
				setPressed(false)
			end)
		end
		if props.OnClick then
			task.spawn(props.OnClick)
		end
	end)
	button:SetAttribute("Style", props.Style or "Green")
	button.Parent = props.Parent
	return button
end

local function labelOf(button: Instance): TextLabel?
	local face = button:FindFirstChild("Face")
	local label = (face and face:FindFirstChild("Label")) or button:FindFirstChild("Label", true)
	return if label and label:IsA("TextLabel") then label else nil
end

function UI.SetButtonText(button: GuiObject, text: string)
	local label = labelOf(button)
	if label then
		label.Text = text
	end
end

function UI.SetButtonStyle(button: GuiObject, styleName: string)
	local style = Theme.ButtonStyles[styleName]
	if not style then
		return
	end
	button:SetAttribute("Style", styleName)
	local face = button:FindFirstChild("Face")
	local lip = button:FindFirstChild("Lip")
	if face and face:IsA("Frame") then
		face.BackgroundColor3 = style.Fill
	end
	if lip and lip:IsA("Frame") then
		lip.BackgroundColor3 = style.Lip
	end
	local label = labelOf(button)
	local stroke = label and label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Theme.Darken(style.Lip, 0.45)
	end
end

-- Deaktiviert = grau, Klick wackelt nur
function UI.SetButtonEnabled(button: GuiObject, enabled: boolean, enabledStyle: string?)
	button:SetAttribute("Disabled", not enabled)
	if enabled then
		local saved = button:GetAttribute("EnabledStyle")
		UI.SetButtonStyle(button, enabledStyle or (if type(saved) == "string" then saved else "Green"))
	else
		if not button:GetAttribute("EnabledStyle") then
			button:SetAttribute("EnabledStyle", button:GetAttribute("Style"))
		end
		UI.SetButtonStyle(button, "Grey")
	end
end

-- Quadratischer Icon-Button (z.B. HUD-Menue): grosses Symbol + kleine Beschriftung
function UI.IconButton(props: { Icon: string, Caption: string?, Style: string?, Size: number?, Parent: Instance?, LayoutOrder: number?, Name: string?, OnClick: (() -> ())? }): TextButton
	local size = props.Size or 76
	local button = UI.Button({
		Name = props.Name,
		Text = "",
		Style = props.Style or "Dark",
		Size = UDim2.fromOffset(size, size),
		LayoutOrder = props.LayoutOrder,
		Parent = props.Parent,
		OnClick = props.OnClick,
	})
	local face = button:FindFirstChild("Face") :: Frame
	UI.Text({
		Name = "Icon",
		Text = props.Icon,
		TextSize = math.floor(size * 0.42),
		Font = F.Heading,
		Position = UDim2.fromOffset(0, if props.Caption then -4 else 0),
		Size = UDim2.fromScale(1, if props.Caption then 0.78 else 1),
		ZIndex = face.ZIndex + 1,
		Parent = face,
	})
	if props.Caption then
		UI.Text({
			Name = "Caption",
			Text = props.Caption,
			TextSize = math.max(10, math.floor(size * 0.15)),
			Font = F.Heading,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, -3),
			Size = UDim2.new(1, 0, 0, math.floor(size * 0.22)),
			TextWrapped = false,
			ZIndex = face.ZIndex + 1,
			Stroke = 1.5,
			Parent = face,
		})
	end
	return button
end

-- Faehigkeits-Kachel ---------------------------------------------------------------------
-- Farbige Kachel in Seltenheitsfarbe mit dunkler Lippe und dem Symbol der Faehigkeit.

function UI.AbilityTile(props: { AbilityId: string?, Size: number, Parent: Instance?, LayoutOrder: number?, Locked: boolean?, Position: UDim2? }): Frame
	local def = Abilities.Get(props.AbilityId)
	local size = props.Size
	local lipH = math.max(3, math.floor(size * 0.06))
	local rarity = if def then Rarities.Get(def.Rarity) else nil
	local fill = if rarity and not props.Locked then rarity.Color else C.Grey
	local holder = Make("Frame", {
		Name = "AbilityTile",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Position = props.Position or UDim2.new(),
		LayoutOrder = props.LayoutOrder or 0,
	})
	local lip = Make("Frame", {
		Name = "Lip",
		BackgroundColor3 = Theme.Darken(fill, 0.45),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, lipH),
		Size = UDim2.new(1, 0, 1, -lipH),
		Parent = holder,
	})
	UI.Corner(lip, math.floor(size * 0.18))
	UI.Stroke(lip, C.Ink, 2.5, 0)
	local face = Make("Frame", {
		Name = "Face",
		BackgroundColor3 = fill,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -lipH),
		ZIndex = 2,
		ClipsDescendants = true,
		Parent = holder,
	})
	UI.Corner(face, math.floor(size * 0.18))
	UI.Stroke(face, C.Ink, 2.5, 0)
	UI.Gradient(face, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170)), 90)
	-- dunkler Kreis hinter dem Symbol fuer Tiefe
	local disc = Make("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.78,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.74, 0.74),
		ZIndex = 2,
		Parent = face,
	})
	UI.Round(disc)
	UI.Text({
		Name = "Icon",
		Text = if def and not props.Locked then def.Icon else "?",
		Font = F.Heading,
		TextSize = math.floor(size * 0.48),
		TextColor3 = if props.Locked then C.Muted else C.Text,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = face,
	})
	holder.Parent = props.Parent
	return holder
end

-- Fortschrittsbalken ----------------------------------------------------------------------

export type Bar = { Frame: Frame, Fill: Frame, Trail: Frame, Label: TextLabel, Set: (ratio: number, instant: boolean?) -> () }

function UI.ProgressBar(props: { Size: UDim2, Position: UDim2?, AnchorPoint: Vector2?, Color: Color3?, Parent: Instance?, Text: string? }): Bar
	local frame = Make("Frame", {
		BackgroundColor3 = C.PanelDark,
		BorderSizePixel = 0,
		Size = props.Size,
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Parent = props.Parent,
	})
	UI.Round(frame)
	UI.Stroke(frame, C.Ink, 2.5, 0)
	local trail = Make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = frame })
	UI.Round(trail)
	local fill = Make("Frame", { BackgroundColor3 = props.Color or C.Green, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = frame })
	UI.Round(fill)
	UI.Shade(fill)
	local gloss = Make("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 4, 0, 3),
		Size = UDim2.new(1, -8, 0.3, 0),
		Parent = fill,
	})
	UI.Round(gloss)
	local label = UI.Text({
		Text = props.Text or "",
		Font = F.Heading,
		TextSize = 16,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Stroke = 2,
		Parent = frame,
	})
	local function set(ratio: number, instant: boolean?)
		local r = math.clamp(ratio, 0, 1)
		if instant then
			fill.Size = UDim2.fromScale(r, 1)
			trail.Size = UDim2.fromScale(r, 1)
			return
		end
		local shrinking = r < fill.Size.X.Scale
		UI.Tween(fill, 0.15, { Size = UDim2.fromScale(r, 1) })
		if shrinking then
			UI.Tween(trail, 0.45, { Size = UDim2.fromScale(r, 1) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0.3)
		else
			trail.Size = UDim2.fromScale(r, 1)
		end
	end
	return { Frame = frame, Fill = fill, Trail = trail, Label = label, Set = set }
end

-- Tabs ----------------------------------------------------------------------------------

function UI.Tabs(props: { Tabs: { string }, Parent: Instance, Position: UDim2?, Size: UDim2?, OnSelect: (string) -> (), Style: string? }): Frame
	local holder = Make("Frame", {
		BackgroundTransparency = 1,
		Position = props.Position or UDim2.new(),
		Size = props.Size or UDim2.new(1, 0, 0, 50),
		Parent = props.Parent,
	})
	UI.List(holder, true, 10)
	local buttons: { [string]: TextButton } = {}
	local function select(name: string)
		for n, b in buttons do
			UI.SetButtonStyle(b, if n == name then (props.Style or "Blue") else "Dark")
		end
		props.OnSelect(name)
	end
	for i, name in props.Tabs do
		local b = UI.Button({
			Text = name,
			Style = "Dark",
			Size = UDim2.fromOffset(math.max(120, #name * 13 + 40), 46),
			TextSize = 18,
			LayoutOrder = i,
			Parent = holder,
			OnClick = function()
				select(name)
			end,
		})
		buttons[name] = b
	end
	if props.Tabs[1] then
		task.defer(select, props.Tabs[1])
	end
	return holder
end

-- Animationen ---------------------------------------------------------------------------

function UI.Pop(obj: GuiObject, from: number?, time: number?)
	local s = obj:FindFirstChild("PopScale") :: UIScale?
	if not s then
		s = Make("UIScale", { Name = "PopScale", Parent = obj })
	end
	local sc = s :: UIScale
	sc.Scale = from or 0.5
	UI.Tween(sc, time or 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
end

function UI.Shake(obj: GuiObject)
	local origin = obj.Position
	task.spawn(function()
		for i = 1, 6 do
			local dx = (if i % 2 == 0 then 1 else -1) * (8 - i)
			obj.Position = origin + UDim2.fromOffset(dx, 0)
			task.wait(0.03)
		end
		obj.Position = origin
	end)
	UI.Sound("Error")
end

-- Zahl hochzaehlen
function UI.CountTo(label: TextLabel, from: number, to: number, time: number, fmt: ((number) -> string)?)
	local f = fmt or UI.Format
	local start = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - start) / time, 0, 1)
		local e = 1 - (1 - a) ^ 3
		label.Text = f(from + (to - from) * e)
		if a >= 1 then
			conn:Disconnect()
		end
	end)
end

-- Langsam aufsteigende Staubkoernchen im Hintergrund (sehr dezent)
function UI.Ambient(container: Instance, opts: { [string]: any }?): () -> ()
	local o = opts or {}
	local running = true
	local colors: { Color3 } = o.Colors or { Color3.new(1, 1, 1) }
	task.spawn(function()
		while running and container.Parent do
			local size = math.random(o.MinSize or 2, o.MaxSize or 4)
			local dot = Make("Frame", {
				BackgroundColor3 = colors[math.random(1, #colors)],
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(size, size),
				Position = UDim2.fromScale(math.random(), 1.05),
				BackgroundTransparency = o.Transparency or 0.6,
				ZIndex = o.ZIndex or 1,
				Parent = container,
			})
			UI.Round(dot)
			local life = math.random(60, 110) / 10
			UI.Tween(dot, life, {
				Position = UDim2.fromScale(dot.Position.X.Scale + (math.random() - 0.5) * 0.1, -0.05),
				BackgroundTransparency = 1,
			}, Enum.EasingStyle.Linear)
			task.delay(life, function()
				dot:Destroy()
			end)
			task.wait(o.Interval or 0.25)
		end
	end)
	return function()
		running = false
	end
end

-- Konfetti-Explosion von einem Punkt aus
function UI.Burst(container: Instance, at: UDim2, colors: { Color3 }, count: number, spread: number?)
	for _ = 1, count do
		local s = math.random(6, 12)
		local piece = Make("Frame", {
			BackgroundColor3 = colors[math.random(1, #colors)],
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(s, s * (if math.random() > 0.5 then 1.8 else 1)),
			Position = at,
			Rotation = math.random(0, 360),
			ZIndex = 20,
			Parent = container,
		})
		UI.Stroke(piece, C.Ink, 1.5, 0.2)
		local ang = math.random() * math.pi * 2
		local dist = math.random(80, spread or 380)
		local life = math.random(7, 13) / 10
		UI.Tween(piece, life, {
			Position = at + UDim2.fromOffset(math.cos(ang) * dist, math.sin(ang) * dist + 90),
			Rotation = piece.Rotation + math.random(-360, 360),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quart)
		task.delay(life, function()
			piece:Destroy()
		end)
	end
end

-- Weichzeichner hinter Fenstern ---------------------------------------------------------

local blur = Lighting:FindFirstChild("NovaUIBlur") or Make("BlurEffect", { Name = "NovaUIBlur", Size = 0, Parent = Lighting })
local blurUsers = 0

function UI.SetBlur(on: boolean)
	blurUsers = math.max(0, blurUsers + (if on then 1 else -1))
	UI.Tween(blur, 0.3, { Size = if blurUsers > 0 then 12 else 0 })
end

-- Fenster -----------------------------------------------------------------------------
-- Farbige Kopfleiste (opts.Color), roter X-Knopf, Panel mit dickem Umriss + Schlagschatten.

export type Window = {
	Root: Frame,
	Panel: Frame,
	Header: Frame,
	Content: Frame,
	IsOpen: boolean,
	Opened: any,
	Closed: any,
	Open: (self: Window) -> (),
	Close: (self: Window) -> (),
}

local windowsGui: ScreenGui? = nil
local openWindows: { Window } = {}

function UI.Window(opts: { Title: string, Icon: string?, Size: Vector2, Name: string, Color: Color3? }): Window
	if not windowsGui then
		windowsGui = UI.Screen("NovaWindows", 20)
	end
	local gui = windowsGui :: ScreenGui
	local headerColor = opts.Color or C.Blue
	local root = Make("Frame", {
		Name = opts.Name,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	local holder = Make("Frame", {
		Name = "Holder",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.fromOffset(opts.Size.X, opts.Size.Y),
		Parent = root,
	})
	UI.Scaled(holder)
	local popScale = Make("UIScale", { Name = "PopScale", Parent = holder })
	-- Schatten
	local shadow = Make("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.fromScale(1, 1),
		Parent = holder,
	})
	UI.Corner(shadow, 18)
	local panel = UI.Panel({
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		Radius = 18,
		Parent = holder,
	})
	-- Kopfleiste
	local header = Make("Frame", {
		Name = "Header",
		BackgroundColor3 = headerColor,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 64),
		Parent = panel,
	})
	UI.Corner(header, 18)
	UI.Shade(header)
	-- untere Ecken der Kopfleiste eckig machen
	Make("Frame", {
		BackgroundColor3 = headerColor,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -18),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = header,
	})
	Make("Frame", {
		BackgroundColor3 = C.Ink,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 3),
		Parent = header,
	})
	UI.Text({
		Text = (if opts.Icon then opts.Icon .. "  " else "") .. opts.Title,
		Font = F.Heading,
		TextSize = 34,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(24, 0),
		Size = UDim2.new(1, -110, 1, 0),
		TextWrapped = false,
		Stroke = 3,
		StrokeColor = Theme.Darken(headerColor, 0.55),
		Parent = header,
	})
	local content = Make("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 70),
		Size = UDim2.new(1, 0, 1, -70),
		Parent = panel,
	})

	local win = {
		Root = root,
		Panel = panel,
		Header = header,
		Content = content,
		IsOpen = false,
		Opened = Signal.new(),
		Closed = Signal.new(),
	} :: any

	UI.Button({
		Text = "X",
		Style = "Red",
		Size = UDim2.fromOffset(50, 50),
		Position = UDim2.new(1, -64, 0, 6),
		TextSize = 26,
		Parent = panel,
		OnClick = function()
			win:Close()
		end,
	})

	function win.Open(self: Window)
		if self.IsOpen then
			return
		end
		for _, other in table.clone(openWindows) do
			other:Close()
		end
		self.IsOpen = true
		table.insert(openWindows, self)
		root.Visible = true
		root.BackgroundTransparency = 1
		UI.Tween(root, 0.2, { BackgroundTransparency = 0.5 })
		popScale.Scale = 0.85
		UI.Tween(popScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		UI.SetBlur(true)
		UI.Sound("Open")
		self.Opened:Fire()
	end

	function win.Close(self: Window)
		if not self.IsOpen then
			return
		end
		self.IsOpen = false
		local i = table.find(openWindows, self)
		if i then
			table.remove(openWindows, i)
		end
		UI.Tween(root, 0.15, { BackgroundTransparency = 1 })
		UI.Tween(popScale, 0.15, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		UI.SetBlur(false)
		UI.Sound("Close")
		task.delay(0.15, function()
			if not self.IsOpen then
				root.Visible = false
			end
		end)
		self.Closed:Fire()
	end

	-- Klick auf den dunklen Hintergrund schliesst
	root.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local pos = input.Position
			local ap, as = holder.AbsolutePosition, holder.AbsoluteSize
			if pos.X < ap.X or pos.X > ap.X + as.X or pos.Y < ap.Y or pos.Y > ap.Y + as.Y then
				win:Close()
			end
		end
	end)
	return win :: Window
end

function UI.CloseAllWindows()
	for _, w in table.clone(openWindows) do
		w:Close()
	end
end

function UI.AnyWindowOpen(): boolean
	return #openWindows > 0
end

UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Escape then
		UI.CloseAllWindows()
	end
end)

-- Scroll-Bereich
function UI.Scroll(parent: Instance, props: { [string]: any }): ScrollingFrame
	local sf = Make("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = C.Line,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
	})
	for k, v in props do
		(sf :: any)[k] = v
	end
	sf.Parent = parent
	return sf
end

-- 3D-Vorschau in der UI (ViewportFrame + Kamera). Teile einfach in den Viewport parenten.
function UI.Viewport(props: { Size: UDim2, Position: UDim2?, Parent: Instance?, CameraCFrame: CFrame?, FieldOfView: number? }): (ViewportFrame, Camera)
	local vp = Make("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = props.Size,
		Position = props.Position or UDim2.new(),
		Ambient = Color3.fromRGB(170, 170, 185),
		LightColor = Color3.fromRGB(255, 248, 235),
		LightDirection = Vector3.new(-1, -1.4, -0.8),
		Parent = props.Parent,
	})
	local cam = Make("Camera", { FieldOfView = props.FieldOfView or 40, Parent = vp })
	cam.CFrame = props.CameraCFrame or CFrame.lookAt(Vector3.new(0, 3, 10), Vector3.zero)
	vp.CurrentCamera = cam
	return vp, cam
end

return UI
