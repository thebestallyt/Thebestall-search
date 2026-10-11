-- Design-System von NOVA CLASH ("Chunky Game UI"):
-- * flache, satte Farben statt Neon-Verlaeufen
-- * dicke dunkle Umrisse (Ink) um Panels, Buttons und Text
-- * 3D-Buttons mit dunkler "Lippe" unten, die sich beim Klicken eindruecken
-- * runde, fette Schrift (FredokaOne) fuer Titel/Buttons, LuckiestGuy fuer grosse Ansagen
-- Bitte nur diese Farben/Schriften benutzen, damit alles wie aus einem Guss wirkt.

local Theme = {}

local C = Color3.fromRGB

Theme.Colors = {
	-- Basis
	Ink = C(17, 19, 27), -- Umrisse, Text-Kontur, dunkelste Flaeche
	Panel = C(37, 42, 58), -- Fenster-Hintergrund
	PanelDark = C(25, 29, 41), -- vertiefte Flaechen (Slots, Listen, Eingabefelder)
	PanelLight = C(54, 61, 82), -- erhobene Karten
	Line = C(72, 81, 107), -- feine Trennlinien
	Text = C(255, 255, 255),
	SubText = C(203, 209, 225),
	Muted = C(134, 142, 163),

	-- Akzentfarben (Fill + dunkle Lippe)
	Green = C(104, 206, 70),
	GreenDark = C(55, 137, 36),
	Gold = C(255, 187, 40),
	GoldDark = C(196, 116, 10),
	Blue = C(62, 156, 255),
	BlueDark = C(28, 94, 196),
	Red = C(236, 72, 72),
	RedDark = C(156, 32, 40),
	Purple = C(150, 96, 255),
	PurpleDark = C(92, 50, 184),
	Grey = C(98, 108, 133),
	GreyDark = C(58, 65, 85),
	Robux = C(2, 183, 112),
	RobuxDark = C(0, 114, 68),

	Health = C(104, 214, 72),
	HealthLow = C(236, 68, 68),
	Coin = C(255, 205, 60),
}

-- Kompatibilitaet mit aelteren Namen
local K = Theme.Colors
K.Background = K.PanelDark
K.PanelLighter = K.PanelLight
K.Stroke = K.Ink
K.Cyan = K.Blue
K.Magenta = K.Purple
K.Danger = K.Red
K.Success = K.Green

Theme.Fonts = {
	Display = Enum.Font.LuckiestGuy, -- FIGHT!, VICTORY, Countdown
	Heading = Enum.Font.FredokaOne, -- Titel, Buttons, Zahlen
	Body = Enum.Font.GothamMedium, -- Beschreibungen
	Bold = Enum.Font.GothamBold, -- kleine Labels
}
Theme.Fonts.Title = Theme.Fonts.Heading
Theme.Fonts.Accent = Theme.Fonts.Heading

-- Masse
Theme.Radius = 12
Theme.Outline = 3
Theme.Lip = 5

local function seq(a: Color3, b: Color3): ColorSequence
	return ColorSequence.new(a, b)
end

-- Verlaeufe: nur dezente Zwei-Ton-Schattierung (oben heller, unten dunkler).
Theme.Gradients = {
	-- auf farbige Flaechen legen (multipliziert): wirkt wie Licht von oben
	Shade = seq(Color3.new(1, 1, 1), C(206, 206, 206)),
	SoftShade = seq(Color3.new(1, 1, 1), C(228, 228, 228)),
	-- Kompatibilitaet / Text
	Main = seq(C(120, 190, 255), C(62, 140, 255)),
	Gold = seq(C(255, 226, 110), C(255, 170, 30)),
	Panel = seq(C(40, 46, 63), C(31, 35, 49)),
	Danger = seq(C(255, 110, 100), C(226, 56, 56)),
	Success = seq(C(150, 232, 100), C(90, 192, 60)),
	Robux = seq(C(40, 210, 140), C(2, 170, 100)),
	Health = seq(C(150, 236, 100), C(90, 196, 62)),
	HealthLow = seq(C(255, 110, 90), C(220, 52, 52)),
	Void = seq(C(46, 22, 84), C(12, 6, 26)),
}

-- Button-Stile: Fill, Lippe, Textkontur
Theme.ButtonStyles = {
	Green = { Fill = K.Green, Lip = K.GreenDark },
	Gold = { Fill = K.Gold, Lip = K.GoldDark },
	Blue = { Fill = K.Blue, Lip = K.BlueDark },
	Red = { Fill = K.Red, Lip = K.RedDark },
	Purple = { Fill = K.Purple, Lip = K.PurpleDark },
	Grey = { Fill = K.Grey, Lip = K.GreyDark },
	Robux = { Fill = K.Robux, Lip = K.RobuxDark },
	Dark = { Fill = K.PanelLight, Lip = K.PanelDark },
}
local S = Theme.ButtonStyles
S.Primary = S.Green
S.Success = S.Green
S.Secondary = S.Grey
S.Danger = S.Red
S.Ghost = S.Dark

-- Etwas dunklere / hellere Variante einer Farbe
function Theme.Darken(c: Color3, amount: number?): Color3
	return c:Lerp(Color3.new(0, 0, 0), amount or 0.35)
end

function Theme.Lighten(c: Color3, amount: number?): Color3
	return c:Lerp(Color3.new(1, 1, 1), amount or 0.25)
end

return Theme
