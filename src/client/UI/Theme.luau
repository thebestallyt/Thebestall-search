-- Farben, Schriften und Verlaeufe fuer die gesamte Benutzeroberflaeche (kosmischer Neon-Stil).

local Theme = {}

local C = Color3.fromRGB

Theme.Colors = {
	Background = C(9, 7, 20),
	Panel = C(18, 15, 36),
	PanelLight = C(30, 25, 58),
	PanelLighter = C(44, 37, 82),
	Stroke = C(100, 80, 190),
	Cyan = C(0, 225, 255),
	Magenta = C(255, 60, 200),
	Purple = C(150, 70, 255),
	Gold = C(255, 200, 70),
	Text = C(242, 240, 255),
	SubText = C(170, 165, 205),
	Muted = C(110, 104, 140),
	Danger = C(255, 70, 95),
	Success = C(70, 235, 140),
	Robux = C(0, 176, 111),
}

Theme.Fonts = {
	Title = Enum.Font.GothamBlack,
	Bold = Enum.Font.GothamBold,
	Body = Enum.Font.GothamMedium,
	Accent = Enum.Font.Michroma,
}

local function seq(...: Color3): ColorSequence
	local colors = { ... }
	local kps = {}
	for i, c in colors do
		table.insert(kps, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
	end
	return ColorSequence.new(kps)
end

Theme.Gradients = {
	Main = seq(C(0, 225, 255), C(150, 70, 255), C(255, 60, 200)),
	Gold = seq(C(255, 160, 30), C(255, 230, 120), C(255, 170, 40)),
	Panel = seq(C(26, 21, 52), C(14, 11, 30)),
	Danger = seq(C(255, 60, 90), C(255, 120, 60)),
	Success = seq(C(40, 210, 120), C(120, 255, 180)),
	Robux = seq(C(0, 150, 95), C(40, 220, 140)),
	Health = seq(C(60, 255, 160), C(0, 220, 255)),
	HealthLow = seq(C(255, 60, 80), C(255, 160, 60)),
	Void = seq(C(20, 6, 40), C(150, 60, 255), C(255, 140, 50)),
}

return Theme
