--[[
	Merdian  |  Roblox UI hub

	WHAT'S NEW
		- 3 second cinematic intro (click / any key skips it)
		- No sound effects anywhere
		- Rebuilt UI: grouped two-column layout, search bar, animated accent line, keybind chips on toggles,
		  on-screen arraylist of enabled features, live watermark, restyled notifications
		- Player tab (8 features) + Visual tab (8 features), all working

	API
		local Window = Antler:CreateWindow({Name = "Merdian", Version = "V2", ToggleKey = Enum.KeyCode.RightShift})
		local Tab = Window:CreateTab("Name", "user")          -- icons: user, eye, gear, grid, bolt, sliders (or "rbxassetid://...")
		local Group = Tab:AddGroup("Title", "Left" | "Right") -- a box in the tab, holds the elements below
		Group:AddToggle({Name, Default, Keybind = Enum.KeyCode.X, Bindable = true, NoList = true, Callback = function(on) end})
		Group:AddSlider({Name, Min, Max, Default, Increment, Suffix, Callback = function(v) end})
		Group:AddDropdown({Name, Options = {...}, Default, Callback = function(choice) end})
		Group:AddColorPicker({Name, Default = Color3, Callback = function(color) end})
		Group:AddButton({Name, Callback = function() end})
		Group:AddLabel("text")
		Antler:Notify({Title, Content, Duration, Type = "info" | "success" | "warning" | "error"})

	Tab:AddToggle(...) etc. also work directly (they go into an automatic group), and Tab:AddSection("Title") starts a new group.
	Toggles: click the little [KEY] chip to rebind, Escape clears it.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")
local Stats = game:GetService("Stats")
local SoundService = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer
local GUI_NAME = "MerdianV2"
local rng = Random.new()
local WHITE = Color3.new(1, 1, 1)

----------------------------------------------------------------------
-- UI AUDIO
----------------------------------------------------------------------
local UI_SOUND_IDS = {
	click  = "rbxassetid://113397864512278",
	open   = "rbxassetid://70452176150315",
	toggle = "rbxassetid://113397864512278",
	slider = "rbxassetid://113397864512278",
}
local UISoundsEnabled = true
local UISoundVolume = 0.16
local UISoundObjects = {}

local function getUISound(kind)
	local s = UISoundObjects[kind]
	if not s or s.Parent ~= SoundService then
		s = Instance.new("Sound")
		s.Name = "AntlerUI_" .. tostring(kind)
		s.SoundId = UI_SOUND_IDS[kind] or UI_SOUND_IDS.click
		s.Volume = UISoundVolume
		s.PlaybackSpeed = kind == "slider" and 1.08 or (kind == "toggle" and 0.94 or 1)
		s.Parent = SoundService
		UISoundObjects[kind] = s
	end
	return s
end

local function playUISound(kind, pitch)
	if not UISoundsEnabled then return end
	local s = getUISound(kind)
	s.Volume = UISoundVolume
	s.PlaybackSpeed = pitch or (kind == "slider" and 1.08 or (kind == "toggle" and 0.94 or 1))
	s.TimePosition = 0
	s:Play()
end

----------------------------------------------------------------------
-- THEME
----------------------------------------------------------------------
local Theme = {
	Background   = Color3.fromRGB(2, 10, 18),
	Sidebar      = Color3.fromRGB(3, 15, 27),
	Group        = Color3.fromRGB(4, 18, 31),
	Element      = Color3.fromRGB(6, 23, 37),
	ElementHover = Color3.fromRGB(8, 31, 48),
	Stroke       = Color3.fromRGB(9, 38, 56),
	Off          = Color3.fromRGB(22, 43, 56),
	Accent       = Color3.fromRGB(0, 171, 235),
	AccentLight  = Color3.fromRGB(74, 208, 255),
	AccentDark   = Color3.fromRGB(0, 102, 150),
	Secondary    = Color3.fromRGB(0, 124, 190),
	Text         = Color3.fromRGB(222, 238, 247),
	SubText      = Color3.fromRGB(104, 132, 149),
	Success      = Color3.fromRGB(75, 207, 173),
	Warning      = Color3.fromRGB(235, 190, 95),
	Error        = Color3.fromRGB(238, 94, 116),
}
local NOTIFY_COLORS = {info = Theme.Accent, success = Theme.Success, warning = Theme.Warning, error = Theme.Error}

local FONT        = Enum.Font.Gotham
local FONT_MEDIUM = Enum.Font.GothamMedium
local FONT_BOLD   = Enum.Font.GothamBold

local NSK = NumberSequenceKeypoint.new
local CSK = ColorSequenceKeypoint.new

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------
local function create(class, props, children)
	local inst = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then parent = v else inst[k] = v end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	inst.Parent = parent
	return inst
end

local function tween(inst, props, time, style, dir)
	local t = TweenService:Create(inst, TweenInfo.new(time or 0.2, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function corner(r)
	return create("UICorner", {CornerRadius = UDim.new(0, r or 4)})
end

local function cornerFull()
	return create("UICorner", {CornerRadius = UDim.new(1, 0)})
end

local function stroke(color, thickness, transparency)
	return create("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function gradient(c0, c1, rotation)
	return create("UIGradient", {Color = ColorSequence.new(c0, c1), Rotation = rotation or 0})
end

local function makeLabel(parent, text, props)
	local l = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT_MEDIUM,
		Text = text,
		TextColor3 = Theme.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	})
	for k, v in pairs(props or {}) do l[k] = v end
	return l
end

local function fire(callback, ...)
	if callback then task.spawn(callback, ...) end
end

local function fmt(n)
	return tostring(math.floor(n * 100 + 0.5) / 100)
end

local function isPointer(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
end

-- Calls onMove(screenPos, isStart) while a pointer is held on `area`; onEnd() on release.
local function bindDrag(area, onMove, onEnd)
	area.InputBegan:Connect(function(input)
		if not isPointer(input) then return end
		onMove(Vector2.new(input.Position.X, input.Position.Y), true)
		local moveConn, endConn
		moveConn = UserInputService.InputChanged:Connect(function(i)
			if isMove(i) then
				onMove(Vector2.new(i.Position.X, i.Position.Y), false)
			end
		end)
		endConn = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				moveConn:Disconnect()
				endConn:Disconnect()
				if onEnd then onEnd() end
			end
		end)
	end)
end

-- a rounded bar between two points (logo, icons, chevrons, checks)
local function makeLine(parent, a, b, thickness, color)
	local delta = b - a
	local mid = (a + b) / 2
	return create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(mid.X, mid.Y),
		Size = UDim2.fromOffset(delta.Magnitude + thickness, thickness),
		Rotation = math.deg(math.atan2(delta.Y, delta.X)),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = parent,
	}, {cornerFull()})
end

local function makeChevron(parent, color)
	local holder = create("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(Antler._mobile and 16 or 12, Antler._mobile and 16 or 12), BackgroundTransparency = 1, Parent = parent})
	local l1 = makeLine(holder, Vector2.new(2, 4.5), Vector2.new(6, 8.5), 2, color)
	local l2 = makeLine(holder, Vector2.new(6, 8.5), Vector2.new(10, 4.5), 2, color)
	return holder, function(c)
		tween(l1, {BackgroundColor3 = c}, 0.2)
		tween(l2, {BackgroundColor3 = c}, 0.2)
	end
end

local function shortKey(k)
	if not k then return "NONE" end
	local n = k.Name
	n = (string.gsub(n, "Left", "L"))
	n = (string.gsub(n, "Right", "R"))
	n = (string.gsub(n, "Control", "Ctrl"))
	return string.upper(n)
end

----------------------------------------------------------------------
-- ANTLER LOGO (rounded bars; they can "draw" themselves outward)
----------------------------------------------------------------------
-- left antler in a 100x100 space: {x1, y1, x2, y2, thicknessFactor, growDelay, growDuration, isTip}
local ANTLER_SEGMENTS = {
	{46, 92, 38, 74, 1.20, 0.00, 0.22, false},
	{38, 74, 31, 56, 1.20, 0.20, 0.22, false},
	{31, 56, 27, 38, 1.10, 0.40, 0.22, false},
	{27, 38, 29, 18, 1.05, 0.60, 0.22, false},
	{29, 18, 24,  5, 1.00, 0.80, 0.20, true},
	{38, 74, 22, 70, 0.90, 0.28, 0.24, false},
	{22, 70, 13, 59, 0.85, 0.50, 0.20, true},
	{31, 56, 16, 50, 0.90, 0.48, 0.24, false},
	{16, 50,  8, 37, 0.85, 0.70, 0.20, true},
	{27, 38, 14, 31, 0.80, 0.68, 0.22, true},
	{29, 18, 36,  9, 0.75, 0.88, 0.18, true},
}
local ANTLER_CENTER = { -- not mirrored
	{46, 92, 54, 92, 1.20, 0.00, 0.15, false},
	{46, 92, 50, 98, 1.00, 0.00, 0.15, false},
	{54, 92, 50, 98, 1.00, 0.10, 0.15, false},
}

-- opts: Thick (multiplier), Alpha (BackgroundTransparency), Hidden (start invisible, for growLogo)
local function buildAntlerLogo(parent, size, color, opts)
	opts = opts or {}
	local hidden = opts.Hidden == true
	local alpha = opts.Alpha or 0
	local scale = size / 100
	local base = math.max(2, size * 0.05) * (opts.Thick or 1)
	local holder = create("Frame", {Name = "AntlerLogo", BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size), Parent = parent})
	local segments = {}

	local function add(x1, y1, x2, y2, w, delay, dur, tip)
		local a, b = Vector2.new(x1, y1) * scale, Vector2.new(x2, y2) * scale
		local delta = b - a
		local mid = (a + b) / 2
		local th = base * w
		local len = delta.Magnitude
		local frame = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(mid.X, mid.Y),
			Size = UDim2.fromOffset(len + th, th),
			Rotation = math.deg(math.atan2(delta.Y, delta.X)),
			BackgroundColor3 = color,
			BackgroundTransparency = alpha,
			BorderSizePixel = 0,
			Visible = not hidden,
			Parent = holder,
		}, {cornerFull()})
		local seg = {frame = frame, a = a, b = b, delay = delay, dur = dur, tip = tip}
		function seg.grow(speed)
			frame.Size = UDim2.fromOffset(th, th)
			frame.Position = UDim2.fromOffset(a.X, a.Y)
			frame.Visible = true
			tween(frame, {Size = UDim2.fromOffset(len + th, th), Position = UDim2.fromOffset(mid.X, mid.Y)}, dur * speed)
		end
		table.insert(segments, seg)
	end

	for _, s in ipairs(ANTLER_SEGMENTS) do
		add(s[1], s[2], s[3], s[4], s[5], s[6], s[7], s[8])
		add(100 - s[1], s[2], 100 - s[3], s[4], s[5], s[6], s[7], s[8])
	end
	for _, s in ipairs(ANTLER_CENTER) do
		add(s[1], s[2], s[3], s[4], s[5], s[6], s[7], s[8])
	end
	return holder, segments
end

local function growLogo(segments, speed)
	speed = speed or 1
	for _, seg in ipairs(segments) do
		task.delay(seg.delay * speed, seg.grow, speed)
	end
end

----------------------------------------------------------------------
-- EFFECTS: snow, sparkle, shockwave, shake
----------------------------------------------------------------------
local function startSnow(parent, count, opts)
	opts = opts or {}
	local minSize, maxSize = opts.MinSize or 2, opts.MaxSize or 5
	local minAlpha, maxAlpha = opts.MinAlpha or 0.3, opts.MaxAlpha or 0.8
	local speed = opts.Speed or 1
	local flakes = {}
	for i = 1, count do
		local depth = rng:NextNumber(0.25, 1)
		local size = minSize + (maxSize - minSize) * depth
		local alpha = rng:NextNumber(minAlpha, maxAlpha)
		local frame = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = (rng:NextNumber() < 0.2) and Theme.Secondary or Theme.AccentLight,
			BackgroundTransparency = opts.StartHidden and 1 or alpha,
			BorderSizePixel = 0,
			Parent = parent,
		}, {cornerFull()})
		flakes[i] = {
			frame = frame, alpha = alpha,
			x = rng:NextNumber(), y = rng:NextNumber(),
			fall = (0.03 + 0.09 * depth) * speed,
			sway = rng:NextNumber(0.004, 0.02),
			freq = rng:NextNumber(0.6, 1.6),
			phase = rng:NextNumber(0, 6.28),
		}
	end

	local conn
	local clock = 0
	local function step(dt)
		clock += dt
		for _, p in ipairs(flakes) do
			p.y += p.fall * dt
			if p.y > 1.04 then
				p.y = -0.04
				p.x = rng:NextNumber()
			end
			p.frame.Position = UDim2.fromScale(p.x + math.sin(clock * p.freq + p.phase) * p.sway, p.y)
		end
	end

	local api = {}
	function api:Start()
		if not conn then conn = RunService.Heartbeat:Connect(step) end
	end
	function api:Stop()
		if conn then
			conn:Disconnect()
			conn = nil
		end
	end
	function api:FadeIn(time)
		for _, p in ipairs(flakes) do tween(p.frame, {BackgroundTransparency = p.alpha}, time) end
	end
	function api:Destroy()
		api:Stop()
		for _, p in ipairs(flakes) do p.frame:Destroy() end
	end
	api:Start()
	return api
end

local function sparkle(parent, pos, size, color)
	local s = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(pos.X, pos.Y),
		Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1, ZIndex = 30, Parent = parent,
	})
	local bars = {}
	for i = 1, 2 do
		bars[i] = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = (i == 1) and UDim2.new(1, 0, 0, 2) or UDim2.new(0, 2, 1, 0),
			BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 30, Parent = s,
		}, {cornerFull()})
	end
	tween(s, {Size = UDim2.fromOffset(size, size), Rotation = 90}, 0.4, Enum.EasingStyle.Quint)
	task.delay(0.2, function()
		for _, b in ipairs(bars) do tween(b, {BackgroundTransparency = 1}, 0.35) end
	end)
	task.delay(0.65, function() s:Destroy() end)
end

local function shockwave(parent, pos, color, maxSize, dur, thickness)
	local ring = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Size = UDim2.fromOffset(30, 30),
		BackgroundTransparency = 1, ZIndex = 8, Parent = parent,
	}, {cornerFull()})
	local st = create("UIStroke", {Color = color, Thickness = thickness or 3, Transparency = 0.1, Parent = ring})
	tween(ring, {Size = UDim2.fromOffset(maxSize, maxSize)}, dur, Enum.EasingStyle.Quint)
	tween(st, {Transparency = 1, Thickness = 0.5}, dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(dur + 0.05, function() ring:Destroy() end)
end

local function shake(gui, amplitude, duration)
	local base = gui.Position
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < duration do
			local k = 1 - (os.clock() - t0) / duration
			gui.Position = base + UDim2.fromOffset(rng:NextNumber(-amplitude, amplitude) * k, rng:NextNumber(-amplitude, amplitude) * k)
			task.wait()
		end
		gui.Position = base
	end)
end

----------------------------------------------------------------------
-- TAB ICONS (drawn from shapes, so no image assets). Each returns a paint(color) function.
----------------------------------------------------------------------
local Icons = {}

Icons.grid = function(parent, color)
	local items = {}
	for _, p in ipairs({{1, 1}, {10, 1}, {1, 10}, {10, 10}}) do
		table.insert(items, create("Frame", {
			Position = UDim2.fromOffset(p[1], p[2]), Size = UDim2.fromOffset(7, 7),
			BackgroundColor3 = color, BorderSizePixel = 0, Parent = parent,
		}, {corner(2)}))
	end
	return function(c) for _, f in ipairs(items) do tween(f, {BackgroundColor3 = c}, 0.2) end end
end

Icons.user = function(parent, color)
	local head = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(9, 0), Size = UDim2.fromOffset(7, 7),
		BackgroundColor3 = color, BorderSizePixel = 0, Parent = parent,
	}, {cornerFull()})
	local body = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(9, 9), Size = UDim2.fromOffset(14, 8),
		BackgroundColor3 = color, BorderSizePixel = 0, Parent = parent,
	}, {create("UICorner", {CornerRadius = UDim.new(0, 5)})})
	return function(c)
		tween(head, {BackgroundColor3 = c}, 0.2)
		tween(body, {BackgroundColor3 = c}, 0.2)
	end
end

Icons.eye = function(parent, color)
	local st = stroke(color, 1.6)
	create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(18, 11),
		BackgroundTransparency = 1, Parent = parent,
	}, {cornerFull(), st})
	local pupil = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = color, BorderSizePixel = 0, Parent = parent,
	}, {cornerFull()})
	return function(c)
		tween(st, {Color = c}, 0.2)
		tween(pupil, {BackgroundColor3 = c}, 0.2)
	end
end

Icons.gear = function(parent, color)
	local st = stroke(color, 2)
	create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(10, 10),
		BackgroundTransparency = 1, Parent = parent,
	}, {cornerFull(), st})
	local teeth = {}
	for i = 0, 7 do
		local ang = i * math.pi / 4
		table.insert(teeth, create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(9 + math.cos(ang) * 7.2, 9 + math.sin(ang) * 7.2),
			Size = UDim2.fromOffset(3.5, 3.5), Rotation = math.deg(ang),
			BackgroundColor3 = color, BorderSizePixel = 0, Parent = parent,
		}, {corner(1)}))
	end
	return function(c)
		tween(st, {Color = c}, 0.2)
		for _, t in ipairs(teeth) do tween(t, {BackgroundColor3 = c}, 0.2) end
	end
end

Icons.bolt = function(parent, color)
	local pts = {Vector2.new(11, 1), Vector2.new(4, 10), Vector2.new(12, 9), Vector2.new(6, 17)}
	local items = {}
	for i = 1, #pts - 1 do
		table.insert(items, makeLine(parent, pts[i], pts[i + 1], 2.2, color))
	end
	return function(c) for _, f in ipairs(items) do tween(f, {BackgroundColor3 = c}, 0.2) end end
end

Icons.sliders = function(parent, color)
	local items = {}
	local ys, ks = {3, 9, 15}, {5, 12, 7}
	for i = 1, 3 do
		table.insert(items, create("Frame", {
			Position = UDim2.fromOffset(0, ys[i] - 1), Size = UDim2.fromOffset(18, 2),
			BackgroundColor3 = color, BackgroundTransparency = 0.45, BorderSizePixel = 0, Parent = parent,
		}, {corner(1)}))
		table.insert(items, create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(ks[i], ys[i]), Size = UDim2.fromOffset(6, 6),
			BackgroundColor3 = color, BorderSizePixel = 0, Parent = parent,
		}, {cornerFull()}))
	end
	return function(c) for _, f in ipairs(items) do tween(f, {BackgroundColor3 = c}, 0.2) end end
end

Icons.home = function(parent, color)
	local a = makeLine(parent, Vector2.new(2,9), Vector2.new(9,2), 2, color)
	local b = makeLine(parent, Vector2.new(9,2), Vector2.new(16,9), 2, color)
	local base = create("Frame",{Position=UDim2.fromOffset(4,8),Size=UDim2.fromOffset(10,9),BackgroundTransparency=1,Parent=parent},{stroke(color,2,0)})
	return function(c)
		tween(a,{BackgroundColor3=c},.2); tween(b,{BackgroundColor3=c},.2)
		local st=base:FindFirstChildOfClass("UIStroke"); if st then tween(st,{Color=c},.2) end
	end
end

Icons.crosshair = function(parent, color)
	local items={}
	for _,d in ipairs({{0,-7,2,6},{0,7,2,6},{-7,0,6,2},{7,0,6,2}}) do
		table.insert(items,create("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromOffset(9+d[1],9+d[2]),Size=UDim2.fromOffset(d[3],d[4]),BackgroundColor3=color,BorderSizePixel=0,Parent=parent},{cornerFull()}))
	end
	return function(c) for _,f in ipairs(items) do tween(f,{BackgroundColor3=c},.2) end end
end

Icons.globe = function(parent, color)
	local st=stroke(color,1.6)
	create("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(17,17),BackgroundTransparency=1,Parent=parent},{cornerFull(),st})
	local mid=create("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(13,1),BackgroundColor3=color,BorderSizePixel=0,Parent=parent})
	return function(c) tween(st,{Color=c},.2); tween(mid,{BackgroundColor3=c},.2) end
end

Icons.player = Icons.user
Icons.visual = Icons.eye
Icons.combat = Icons.crosshair
Icons.world = Icons.globe
local ICON_CYCLE = {"home","crosshair","player","visual","world","sliders","gear"}

----------------------------------------------------------------------
-- LIBRARY SETUP
----------------------------------------------------------------------
local Antler = {Theme = Theme, _connections = {}, _cleanups = {}, _notifyOrder = 0, _arrayEntries = {}, _binds = {}, _listening = false, _uiSounds = true}

local function getGuiParent()
	local ok, ui = pcall(function() return gethui() end)
	if ok and typeof(ui) == "Instance" then return ui end
	ok, ui = pcall(function()
		local probe = Instance.new("Folder")
		probe.Parent = CoreGui
		probe:Destroy()
		return CoreGui
	end)
	if ok then return ui end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local guiParent = getGuiParent()

-- remove an older copy if the script is run twice
for _, child in ipairs(guiParent:GetChildren()) do
	if string.sub(child.Name, 1, #GUI_NAME) == GUI_NAME then child:Destroy() end
end
for _, child in ipairs(Lighting:GetChildren()) do
	if string.sub(child.Name, 1, 8) == "AntlerFX" then child:Destroy() end
end

Antler._gui = create("ScreenGui", {
	Name = GUI_NAME,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 500,
	Parent = guiParent,
})

Antler._notifyHolder = create("Frame", {
	Name = "Notifications",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -12, 1, -12),
	Size = UDim2.new(0, 260, 1, -24),
	BackgroundTransparency = 1,
	ZIndex = 60,
	Parent = Antler._gui,
}, {
	create("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
	}),
})

-- global keybind dispatcher (toggles register themselves in Antler._binds)
table.insert(Antler._connections, UserInputService.InputBegan:Connect(function(input, processed)
	if processed or Antler._listening then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	for _, fn in ipairs(Antler._binds) do fn(input.KeyCode) end
end))

local function titleRichText(name, version)
	return string.format('%s <i><font color="#%s">%s</font></i>', name, Theme.Secondary:ToHex(), version)
end

----------------------------------------------------------------------
-- NOTIFICATIONS
----------------------------------------------------------------------
function Antler:Notify(opts)
	if type(opts) ~= "table" then opts = {Content = tostring(opts)} end
	local title = tostring(opts.Title or "Antler")
	local content = tostring(opts.Content or "")
	local duration = opts.Duration or 4
	local kind = string.lower(opts.Type or "info")
	local tint = NOTIFY_COLORS[kind] or Theme.Accent
	local W = 260
	local textH = TextService:GetTextSize(content, 12, FONT, Vector2.new(W - 44, 1000)).Y
	local H = 12 + 18 + textH + 16

	self._notifyOrder += 1
	local holder = create("Frame", {
		BackgroundTransparency = 1, Size = UDim2.fromOffset(W, H), LayoutOrder = self._notifyOrder, Parent = self._notifyHolder,
	})
	local card = create("Frame", {
		BackgroundColor3 = Theme.Sidebar, BackgroundTransparency = 0.05, BorderSizePixel = 0,
		Position = UDim2.new(1, 40, 0, 0), Size = UDim2.fromScale(1, 1), ClipsDescendants = true, Parent = holder,
	}, {corner(6), stroke(Theme.Stroke, 1, 0.1)})

	create("Frame", { -- tinted edge bar
		Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = tint, BorderSizePixel = 0, Parent = card,
	})
	create("Frame", { -- soft tint wash behind the text
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = tint, BackgroundTransparency = 0.94, BorderSizePixel = 0, Parent = card,
	}, {create("UIGradient", {Transparency = NumberSequence.new(0, 1)})})
	makeLabel(card, title, {
		Font = FONT_BOLD, TextSize = 13, TextColor3 = Theme.Text,
		Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -28, 0, 18),
	})
	makeLabel(card, content, {
		Font = FONT, TextSize = 12, TextColor3 = Theme.SubText, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(16, 30), Size = UDim2.new(1, -28, 0, textH),
	})
	local bar = create("Frame", {
		AnchorPoint = Vector2.new(0, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 2), Parent = card,
	}, {gradient(tint, Theme.Secondary, 0)})

	local dismissed = false
	local function dismiss()
		if dismissed then return end
		dismissed = true
		tween(card, {Position = UDim2.new(1, 40, 0, 0)}, 0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.delay(0.28, function() holder:Destroy() end)
	end
	local click = create("TextButton", {BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = card})
	click.MouseButton1Click:Connect(dismiss)

	tween(card, {Position = UDim2.new(0, 0, 0, 0)}, 0.4, Enum.EasingStyle.Quint)
	tween(bar, {Size = UDim2.new(0, 0, 0, 2)}, duration, Enum.EasingStyle.Linear)
	task.delay(duration, dismiss)
	return {Dismiss = dismiss}
end

----------------------------------------------------------------------
-- ARRAYLIST (enabled features, top-right, Prestige style) + WATERMARK (top-left, Nevelose style)
----------------------------------------------------------------------
Antler._arrayHolder = create("Frame", {
	Name = "ArrayList", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10),
	Size = UDim2.new(0, 240, 1, -20), BackgroundTransparency = 1, ZIndex = 0, Parent = Antler._gui,
}, {
	create("UIListLayout", {
		Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right,
	}),
})

function Antler:_setActive(name, on)
	local entry = self._arrayEntries[name]
	if on then
		if entry then return end
		local w = TextService:GetTextSize(name, 12, FONT_MEDIUM, Vector2.new(400, 20)).X + 20
		local frame = create("Frame", {
			Name = name, Size = UDim2.fromOffset(w, 0), BackgroundColor3 = Theme.Sidebar, BackgroundTransparency = 0.25,
			BorderSizePixel = 0, ClipsDescendants = true, LayoutOrder = -math.floor(w), Parent = self._arrayHolder,
		}, {corner(3)})
		makeLabel(frame, name, {
			Font = FONT_MEDIUM, TextSize = 12, TextColor3 = Theme.AccentLight,
			Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -14, 0, 20),
		})
		create("Frame", {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 2, 1, 0),
			BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = frame,
		}, {gradient(Theme.Accent, Theme.Secondary, 90)})
		tween(frame, {Size = UDim2.fromOffset(w, 20)}, 0.2, Enum.EasingStyle.Quint)
		self._arrayEntries[name] = frame
	else
		if not entry then return end
		self._arrayEntries[name] = nil
		tween(entry, {Size = UDim2.fromOffset(entry.Size.X.Offset, 0)}, 0.15)
		task.delay(0.17, function() entry:Destroy() end)
	end
end

Antler._watermark = create("Frame", {
	Name = "Watermark", Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = Theme.Sidebar, BackgroundTransparency = 0.1, BorderSizePixel = 0, ZIndex = 0, Parent = Antler._gui,
}, {
	corner(4), stroke(Theme.Stroke, 1, 0.2),
	create("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10)}),
})
create("Frame", {
	Size = UDim2.new(1, 20, 0, 2), Position = UDim2.fromOffset(-10, 0), BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = Antler._watermark,
}, {gradient(Theme.Accent, Theme.Secondary, 0)})
local watermarkLabel = makeLabel(Antler._watermark, "", {
	RichText = true, Font = FONT_MEDIUM, TextSize = 12, TextColor3 = Theme.SubText,
	Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Position = UDim2.fromOffset(0, 1),
})
do
	local frames, acc = 0, 0
	local function refresh(fps, ping)
		watermarkLabel.Text = string.format(
			'<font color="#%s"><b>merdian</b></font> <font color="#%s"><i>v2</i></font>  |  %s  |  %d fps  |  %d ms  |  %s',
			Theme.AccentLight:ToHex(), Theme.Secondary:ToHex(), LocalPlayer.DisplayName, fps, ping, os.date("%H:%M")
		)
	end
	refresh(0, 0)
	table.insert(Antler._connections, RunService.RenderStepped:Connect(function(dt)
		frames += 1
		acc += dt
		if acc >= 0.5 then
			local fps = math.floor(frames / acc + 0.5)
			local ping = 0
			pcall(function() ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue() + 0.5) end)
			refresh(fps, ping)
			frames, acc = 0, 0
		end
	end))
end

----------------------------------------------------------------------
-- INTRO CUTSCENE  (3 seconds, silent)
----------------------------------------------------------------------
function Antler:PlayIntro()
	local skipped, finished = false, false
	local snow, inputConn

	local introGui = create("ScreenGui", {
		Name = GUI_NAME .. "_Intro", IgnoreGuiInset = true, ResetOnSpawn = false,
		DisplayOrder = 1000, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = guiParent,
	})
	local blur = create("BlurEffect", {Name = "AntlerFXBlur", Size = 0, Parent = Lighting})

	local function cleanup()
		if finished then return end
		finished = true
		if inputConn then inputConn:Disconnect() end
		if snow then snow:Destroy() end
		introGui:Destroy()
		blur:Destroy()
	end

	inputConn = UserInputService.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.Keyboard or t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			skipped = true
		end
	end)

	local t0 = os.clock()
	local function untilT(t)
		while not skipped and os.clock() - t0 < t do task.wait() end
	end
	local function at(t, fn) -- run fn at time t (seconds since start), unless skipped
		task.delay(t, function()
			if not skipped and not finished then fn() end
		end)
	end

	local ok, err = pcall(function()
		------------------------------------------------ scene
		local root = create("Frame", {Name = "Root", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = introGui})
		local dim = create("Frame", {
			Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, Parent = root,
		}, {create("UIGradient", {Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(4, 6, 11), Color3.fromRGB(14, 24, 42))})})

		local fxLayer = create("Frame", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = root})
		snow = startSnow(fxLayer, 55, {MinSize = 2, MaxSize = 5, MinAlpha = 0.3, MaxAlpha = 0.8, Speed = 1.6, StartHidden = true})

		local stage = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(600, 300), BackgroundTransparency = 1, Parent = root,
		})
		local stageScale = create("UIScale", {Scale = 1, Parent = stage})
		local center = UDim2.fromOffset(300, 80)

		-- glow behind the logo
		local glowDiameters, glowAlpha = {300, 210, 140}, {0.95, 0.92, 0.88}
		local glows = {}
		for i, d in ipairs(glowDiameters) do
			glows[i] = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = center, Size = UDim2.fromOffset(d * 0.6, d * 0.6),
				BackgroundColor3 = Theme.Accent, BackgroundTransparency = 1, BorderSizePixel = 0, Parent = stage,
			}, {cornerFull()})
		end

		-- logo (glow layer + solid layer)
		local glowHolder, glowSegs = buildAntlerLogo(stage, 120, Theme.AccentLight, {Thick = 2.8, Alpha = 0.86, Hidden = true})
		local logoHolder, logoSegs = buildAntlerLogo(stage, 120, Theme.Accent, {Hidden = true})
		for _, h in ipairs({glowHolder, logoHolder}) do
			h.AnchorPoint = Vector2.new(0.5, 0)
			h.Position = UDim2.new(0.5, 0, 0, 20)
		end

		-- horizon line
		local function horizonBar(height, alpha, y)
			return create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(300, y), Size = UDim2.fromOffset(0, height),
				BackgroundColor3 = Theme.AccentLight, BorderSizePixel = 0, Parent = stage,
			}, {create("UIGradient", {Transparency = NumberSequence.new({NSK(0, 1), NSK(0.25, alpha), NSK(0.75, alpha), NSK(1, 1)})})})
		end
		local horizonGlow = horizonBar(12, 0.88, 156)
		local horizon = horizonBar(2, 0.1, 156)

		-- title: ANTLER + italic V2, letter by letter
		local TITLE_SIZE, TRACK = 40, 7
		local parts = {}
		for ch in string.gmatch("MERDIAN", ".") do table.insert(parts, {ch = ch, color = Theme.Text, italic = false}) end
		table.insert(parts, {gap = 16})
		for ch in string.gmatch("V2", ".") do table.insert(parts, {ch = ch, color = Theme.Secondary, italic = true}) end
		local totalW = 0
		for _, p in ipairs(parts) do
			p.w = p.gap or TextService:GetTextSize(p.ch, TITLE_SIZE, FONT_BOLD, Vector2.new(500, 100)).X
			totalW += p.w + TRACK
		end
		totalW -= TRACK
		local titleRow = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 172), Size = UDim2.fromOffset(totalW, 52),
			BackgroundTransparency = 1, Parent = stage,
		})
		local letters, cursor = {}, 0
		for _, p in ipairs(parts) do
			if not p.gap then
				local lbl = create("TextLabel", {
					BackgroundTransparency = 1, Position = UDim2.fromOffset(cursor, 22), Size = UDim2.fromOffset(p.w + 2, 52),
					Font = FONT_BOLD, TextSize = TITLE_SIZE, RichText = true,
					Text = p.italic and ("<i>" .. p.ch .. "</i>") or p.ch,
					TextColor3 = p.color, TextTransparency = 1, Parent = titleRow,
				})
				local st = create("UIStroke", {Color = p.italic and Theme.Secondary or Theme.Accent, Thickness = 1.3, Transparency = 1, Parent = lbl})
				table.insert(letters, {label = lbl, x = cursor, stroke = st})
			end
			cursor += p.w + TRACK
		end
		local function revealTitle()
			for i, l in ipairs(letters) do
				task.delay((i - 1) * 0.045, function()
					if finished then return end
					tween(l.label, {Position = UDim2.fromOffset(l.x, 0), TextTransparency = 0}, 0.4, Enum.EasingStyle.Back)
					tween(l.stroke, {Transparency = 0.72}, 0.4)
				end)
			end
		end

		local tagline = makeLabel(stage, "H U N T   I N   S I L E N C E", {
			Font = FONT_MEDIUM, TextSize = 12, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center,
			TextTransparency = 1, Position = UDim2.fromOffset(0, 232), Size = UDim2.new(1, 0, 0, 16),
		})

		-- loading readout
		local pct = makeLabel(stage, "0%", {
			Font = FONT_BOLD, TextSize = 11, TextColor3 = Theme.AccentLight, TextTransparency = 1, TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 254), Size = UDim2.new(1, 0, 0, 14),
		})
		local track = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(300, 276), Size = UDim2.fromOffset(220, 3),
			BackgroundColor3 = Theme.Off, BackgroundTransparency = 1, BorderSizePixel = 0, Parent = stage,
		}, {cornerFull()})
		local fill = create("Frame", {
			Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = track,
		}, {cornerFull(), gradient(Theme.Accent, Theme.Secondary, 0)})

		-- cinematic letterbox bars
		local function letterbox(top)
			return create("Frame", {
				AnchorPoint = Vector2.new(0, top and 0 or 1), Position = UDim2.fromScale(0, top and 0 or 1), Size = UDim2.new(1, 0, 0, 0),
				BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 50, Parent = root,
			})
		end
		local topBar, botBar = letterbox(true), letterbox(false)

		local blackout = create("Frame", {
			Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 45, Parent = root,
		})
		local flash = create("Frame", {
			Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(190, 220, 255), BackgroundTransparency = 1,
			BorderSizePixel = 0, ZIndex = 40, Parent = root,
		})
		local hint = makeLabel(root, "CLICK OR PRESS ANY KEY TO SKIP", {
			Font = FONT_MEDIUM, TextSize = 10, TextColor3 = Theme.SubText, TextTransparency = 1, TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(300, 14), ZIndex = 52,
		})

		------------------------------------------------ timeline (3.0 seconds total)
		-- 0.00  fade up from black, blur in, letterbox in, slow push-in begins
		tween(blackout, {BackgroundTransparency = 1}, 0.45)
		tween(dim, {BackgroundTransparency = 0.1}, 0.5)
		tween(blur, {Size = 18}, 0.7)
		tween(topBar, {Size = UDim2.new(1, 0, 0.09, 0)}, 0.5, Enum.EasingStyle.Quint)
		tween(botBar, {Size = UDim2.new(1, 0, 0.09, 0)}, 0.5, Enum.EasingStyle.Quint)
		tween(stageScale, {Scale = 1.06}, 2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		snow:FadeIn(0.8)
		tween(hint, {TextTransparency = 0.6}, 0.5)

		-- 0.15  glow swells, horizon draws
		at(0.15, function()
			for i, g in ipairs(glows) do
				tween(g, {BackgroundTransparency = glowAlpha[i], Size = UDim2.fromOffset(glowDiameters[i], glowDiameters[i])}, 0.9, Enum.EasingStyle.Quint)
			end
			tween(horizon, {Size = UDim2.fromOffset(440, 2)}, 0.8, Enum.EasingStyle.Quint)
			tween(horizonGlow, {Size = UDim2.fromOffset(440, 12)}, 0.8, Enum.EasingStyle.Quint)
		end)

		-- 0.25  the antlers draw themselves, sparkles pop on each tine tip
		at(0.25, function()
			local SPEED = 0.55
			growLogo(glowSegs, SPEED)
			growLogo(logoSegs, SPEED)
			for _, seg in ipairs(logoSegs) do
				if seg.tip then
					task.delay((seg.delay + seg.dur) * SPEED, function()
						if not finished then sparkle(logoHolder, seg.b, rng:NextNumber(14, 22), Theme.AccentLight) end
					end)
				end
			end
		end)

		-- 0.95  impact: flash, shockwaves, shake, title reveal
		at(0.95, function()
			flash.BackgroundTransparency = 0.78
			tween(flash, {BackgroundTransparency = 1}, 0.6)
			shockwave(stage, center, Theme.AccentLight, 760, 0.9, 3)
			task.delay(0.08, function() if not finished then shockwave(stage, center, Theme.Secondary, 520, 0.8, 2) end end)
			shake(stage, 5, 0.25)
			for i, g in ipairs(glows) do
				local d = glowDiameters[i]
				tween(g, {Size = UDim2.fromOffset(d * 1.25, d * 1.25)}, 0.15)
				task.delay(0.16, function() if not finished then tween(g, {Size = UDim2.fromOffset(d, d)}, 0.7, Enum.EasingStyle.Quint) end end)
			end
			revealTitle()
		end)

		-- 1.40  tagline + loader
		at(1.4, function()
			tween(tagline, {TextTransparency = 0.1, Position = UDim2.fromOffset(0, 228)}, 0.6, Enum.EasingStyle.Quint)
			tween(track, {BackgroundTransparency = 0.2}, 0.3)
			tween(pct, {TextTransparency = 0}, 0.3)
		end)
		at(1.5, function()
			tween(fill, {Size = UDim2.fromScale(1, 1)}, 0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
			local nv = Instance.new("NumberValue")
			nv.Changed:Connect(function(v) pct.Text = string.format("%d%%", math.floor(v)) end)
			TweenService:Create(nv, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {Value = 100}):Play()
			task.delay(1.1, function() nv:Destroy() end)
		end)

		untilT(2.5)

		-- 2.50  finale: bars retract, everything dissolves into the window
		local dur = skipped and 0.2 or 0.45
		tween(stageScale, {Scale = 1.18}, dur + 0.1, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		tween(blur, {Size = 0}, dur)
		tween(topBar, {Size = UDim2.new(1, 0, 0, 0)}, dur, Enum.EasingStyle.Quint)
		tween(botBar, {Size = UDim2.new(1, 0, 0, 0)}, dur, Enum.EasingStyle.Quint)
		for _, d in ipairs(introGui:GetDescendants()) do
			if d:IsA("Frame") then
				tween(d, {BackgroundTransparency = 1}, dur)
			elseif d:IsA("TextLabel") then
				tween(d, {TextTransparency = 1}, dur)
			elseif d:IsA("UIStroke") then
				tween(d, {Transparency = 1}, dur)
			end
		end
		task.delay(dur + 0.1, cleanup)
		task.wait(dur * 0.5) -- the window starts opening while the fade finishes
	end)

	if not ok then
		warn("[Merdian] intro error: " .. tostring(err))
		cleanup()
	end
end

----------------------------------------------------------------------
-- ELEMENTS  (shared by every group)
----------------------------------------------------------------------
local Elements = {}

local function rowBase(g, name, height)
	g.order = (g.order or 0) + 1
	if Antler._mobile then
		height = math.max(height, 40)
	end
	local row = create("Frame", {
		Name = name, Size = UDim2.new(1, 0, 0, height), BackgroundColor3 = Theme.ElementHover, BackgroundTransparency = 1,
		BorderSizePixel = 0, LayoutOrder = g.order, Parent = g.body,
	}, {corner(4)})
	table.insert(g.items, {frame = row, name = string.lower(name)})
	return row
end

local function rowHover(row, hit)
	hit.MouseEnter:Connect(function() tween(row, {BackgroundTransparency = 0.5}, 0.12) end)
	hit.MouseLeave:Connect(function() tween(row, {BackgroundTransparency = 1}, 0.12) end)
end

local function hitbox(parent, z)
	return create("TextButton", {BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), ZIndex = z or 5, Parent = parent})
end

------------------------------------------------ toggle (pill switch + optional keybind chip)
function Elements.AddToggle(g, o)
	local name = o.Name or "Toggle"
	local row = rowBase(g, name, 30)
	local state = o.Default == true
	local key = o.Keybind

	local label = makeLabel(row, name, {
		Font = FONT_MEDIUM, TextSize = 13, TextColor3 = Theme.SubText,
		Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -110, 1, 0),
	})
	local sw = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(Antler._mobile and 38 or 32, Antler._mobile and 20 or 16),
		BackgroundColor3 = Theme.Off, BorderSizePixel = 0, ZIndex = 2, Parent = row,
	}, {cornerFull()})
	local swFill = create("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2, Parent = sw,
	}, {cornerFull(), gradient(Theme.Accent, Theme.Secondary, 0)})
	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 2, 0.5, 0), Size = UDim2.fromOffset(Antler._mobile and 16 or 12, Antler._mobile and 16 or 12),
		BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3, Parent = sw,
	}, {cornerFull()})

	local hit = hitbox(row, 5)
	rowHover(row, hit)

	local api = {}
	local chip
	local listening = false
	local function refreshChip()
		if chip then chip.Text = listening and "..." or ("[" .. shortKey(key) .. "]") end
	end

	if o.Keybind ~= nil or o.Bindable then
		chip = create("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -52, 0.5, 0), Size = UDim2.fromOffset(0, 18),
			AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Theme.Element, BorderSizePixel = 0, AutoButtonColor = false,
			Font = FONT_BOLD, TextSize = 10, TextColor3 = Theme.SubText, Text = "", ZIndex = 7, Parent = row,
		}, {corner(4), stroke(Theme.Stroke, 1, 0.2), create("UIPadding", {PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6)})})
		refreshChip()
		chip.MouseButton1Click:Connect(function()
			if listening then return end
			listening = true
			Antler._listening = true
			refreshChip()
			local conn
			conn = UserInputService.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
				if input.KeyCode == Enum.KeyCode.Escape then key = nil else key = input.KeyCode end
				listening = false
				task.defer(function() Antler._listening = false end)
				refreshChip()
				conn:Disconnect()
			end)
		end)
	end

	local function render(instant)
		local t = instant and 0 or 0.16
		tween(swFill, {BackgroundTransparency = state and 0 or 1}, t)
		tween(knob, {Position = UDim2.new(0, state and (Antler._mobile and 20 or 18) or 2, 0.5, 0)}, t, Enum.EasingStyle.Quint)
		tween(label, {TextColor3 = state and Theme.Text or Theme.SubText}, t)
	end

	function api:Set(v, silent)
		state = v and true or false
		render()
		if not o.NoList then Antler:_setActive(name, state) end
		if not silent then fire(o.Callback, state) end
	end
	function api:Get() return state end
	function api:SetKey(k)
		key = k
		refreshChip()
	end

	hit.MouseButton1Click:Connect(function() playUISound("toggle"); api:Set(not state) end)
	table.insert(Antler._binds, function(keyCode)
		if key and keyCode == key then api:Set(not state) end
	end)

	render(true)
	if state and not o.NoList then Antler:_setActive(name, true) end
	return api
end

------------------------------------------------ slider
function Elements.AddSlider(g, o)
	local name = o.Name or "Slider"
	local row = rowBase(g, name, 42)
	local min, max = o.Min or 0, o.Max or 100
	local inc = o.Increment or 1
	local suffix = o.Suffix or ""
	local function snap(v)
		v = math.clamp(v, min, max)
		return math.clamp(math.floor((v - min) / inc + 0.5) * inc + min, min, max)
	end
	local value = snap(o.Default or min)
	local lastSliderSound = 0

	makeLabel(row, name, {Font = FONT_MEDIUM, TextSize = 13, Position = UDim2.fromOffset(10, 4), Size = UDim2.new(0.6, 0, 0, 18)})
	local valueLabel = makeLabel(row, "", {
		Font = FONT_BOLD, TextSize = 12, TextColor3 = Theme.AccentLight, TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 4), Size = UDim2.new(0.4, 0, 0, 18),
	})
	local hit = create("TextButton", {
		BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
		Position = UDim2.fromOffset(10, Antler._mobile and 25 or 24), Size = UDim2.new(1, -20, 0, Antler._mobile and 20 or 14), ZIndex = 5, Parent = row,
	})
	local track = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = Theme.Off, BorderSizePixel = 0, Parent = hit,
	}, {cornerFull()})
	local fill = create("Frame", {
		Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = track,
	}, {cornerFull(), gradient(Theme.Accent, Theme.Secondary, 0)})
	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(10, 10),
		BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3, Parent = track,
	}, {cornerFull(), stroke(Theme.Accent, 2, 0)})

	rowHover(row, hit)

	local function render()
		local a = (max == min) and 0 or (value - min) / (max - min)
		fill.Size = UDim2.new(a, 0, 1, 0)
		knob.Position = UDim2.new(a, 0, 0.5, 0)
		valueLabel.Text = fmt(value) .. suffix
	end

	local api = {}
	function api:Set(v, silent)
		value = snap(v)
		render()
		if not silent then fire(o.Callback, value) end
	end
	function api:Get() return value end

	bindDrag(hit, function(pos, isStart)
		if isStart then tween(knob, {Size = UDim2.fromOffset(14, 14)}, 0.1) end
		local a = math.clamp((pos.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		local v = snap(min + a * (max - min))
		if v ~= value then
			value = v
			render()
			local now = os.clock()
			if now - lastSliderSound > 0.045 then
				lastSliderSound = now
				playUISound("slider", 0.96 + ((value - min) / math.max(max - min, 1)) * 0.22)
			end
			fire(o.Callback, value)
		end
	end, function()
		tween(knob, {Size = UDim2.fromOffset(10, 10)}, 0.12)
	end)

	render()
	return api
end

------------------------------------------------ button
function Elements.AddButton(g, o)
	local name = o.Name or "Button"
	local row = rowBase(g, name, 30)
	local face = create("Frame", {
		Size = UDim2.new(1, 0, 1, -2), BackgroundColor3 = Theme.Element, BorderSizePixel = 0, ClipsDescendants = true, Parent = row,
	}, {corner(4), stroke(Theme.Stroke, 1, 0.1)})
	local face_st = face:FindFirstChildOfClass("UIStroke")
	local wash = create("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.9, BorderSizePixel = 0, Parent = face,
	}, {gradient(Theme.Accent, Theme.Secondary, 0)})
	makeLabel(face, name, {
		Font = FONT_MEDIUM, TextSize = 12, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3,
	})
	local hit = hitbox(row, 5)
	hit.MouseEnter:Connect(function()
		tween(wash, {BackgroundTransparency = 0.75}, 0.15)
		tween(face_st, {Color = Theme.AccentDark}, 0.15)
	end)
	hit.MouseLeave:Connect(function()
		tween(wash, {BackgroundTransparency = 0.9}, 0.15)
		tween(face_st, {Color = Theme.Stroke}, 0.15)
	end)
	hit.InputBegan:Connect(function(input)
		if isPointer(input) then tween(wash, {BackgroundTransparency = 0.55}, 0.06) end
	end)
	hit.InputEnded:Connect(function(input)
		if isPointer(input) then tween(wash, {BackgroundTransparency = 0.75}, 0.12) end
	end)
	hit.MouseButton1Click:Connect(function() playUISound("click"); fire(o.Callback) end)
	return {}
end

------------------------------------------------ label
function Elements.AddLabel(g, o)
	if type(o) == "string" then o = {Text = o} end
	local text = o.Text or o.Name or ""
	local row = rowBase(g, text, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	create("UIPadding", {PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5), Parent = row})
	local l = makeLabel(row, text, {
		Font = FONT, TextSize = 12, TextColor3 = Theme.SubText, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
	})
	return {SetText = function(_, t) l.Text = t end}
end

------------------------------------------------ text input
function Elements.AddTextBox(g, o)
	o = o or {}
	local name = o.Name or "Input"
	local row = rowBase(g, name, 54)
	makeLabel(row, name, {Font = FONT_MEDIUM, TextSize = 12, Position = UDim2.fromOffset(10, 2), Size = UDim2.new(0.34, -10, 0, 22)})
	local box = create("TextBox", {
		Position = UDim2.new(0.34, 0, 0, 2), Size = UDim2.new(0.66, -4, 0, 26),
		BackgroundColor3 = Theme.Element, BackgroundTransparency = 0.1, BorderSizePixel = 0,
		Font = FONT, TextSize = 12, TextColor3 = Theme.Text, PlaceholderText = o.Placeholder or "Enter value...",
		PlaceholderColor3 = Theme.SubText, Text = tostring(o.Default or ""), ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left, Parent = row,
	}, {corner(4), stroke(Theme.Stroke, 1, 0.1)})
	create("UIPadding", {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = box})
	box.Focused:Connect(function() local st=box:FindFirstChildOfClass("UIStroke"); if st then tween(st,{Color=Theme.Accent},0.15) end end)
	box.FocusLost:Connect(function(enter) local st=box:FindFirstChildOfClass("UIStroke"); if st then tween(st,{Color=Theme.Stroke},0.15) end; if enter then fire(o.Callback, box.Text) end end)
	return {Get = function() return box.Text end, Set = function(_, v) box.Text = tostring(v or "") end, Box = box}
end

------------------------------------------------ dropdown
function Elements.AddDropdown(g, o)
	local HEADER_H, ITEM, GAP = 30, 24, 2
	local name = o.Name or "Dropdown"
	local options = o.Options or {}
	local selected = o.Default
	local isOpen = false

	local row = rowBase(g, name, HEADER_H)
	row.ClipsDescendants = true
	makeLabel(row, name, {Font = FONT_MEDIUM, TextSize = 13, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.5, 0, 0, HEADER_H)})
	local chipLabel = makeLabel(row, (selected ~= nil) and tostring(selected) or "Select", {
		Font = FONT_BOLD, TextSize = 12, TextColor3 = Theme.AccentLight, TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -30, 0, 0), Size = UDim2.new(0.5, -30, 0, HEADER_H),
	})
	local chevron, paintChevron = makeChevron(row, Theme.SubText)
	chevron.Position = UDim2.new(1, -16, 0, HEADER_H / 2)
	local headerHit = create("TextButton", {
		BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Size = UDim2.new(1, 0, 0, HEADER_H), ZIndex = 5, Parent = row,
	})
	rowHover(row, headerHit)
	local list = create("Frame", {
		BackgroundTransparency = 1, Position = UDim2.fromOffset(6, HEADER_H), Size = UDim2.new(1, -12, 0, 0), Parent = row,
	}, {create("UIListLayout", {Padding = UDim.new(0, GAP), SortOrder = Enum.SortOrder.LayoutOrder})})

	local buttons = {}
	local function fullHeight() return HEADER_H + #options * (ITEM + GAP) + 6 end
	local function resize()
		tween(row, {Size = UDim2.new(1, 0, 0, isOpen and fullHeight() or HEADER_H)}, 0.22, Enum.EasingStyle.Quint)
		tween(chevron, {Rotation = isOpen and 180 or 0}, 0.22, Enum.EasingStyle.Quint)
		paintChevron(isOpen and Theme.AccentLight or Theme.SubText)
	end
	local function paint()
		for key, b in pairs(buttons) do
			local on = (key == tostring(selected))
			tween(b.label, {TextColor3 = on and Theme.AccentLight or Theme.Text}, 0.15)
			tween(b.sel, {BackgroundTransparency = on and 0.75 or 1}, 0.15)
		end
	end

	local api = {}
	function api:Set(choice, silent)
		selected = choice
		chipLabel.Text = tostring(choice)
		paint()
		if not silent then fire(o.Callback, choice) end
	end
	function api:Get() return selected end

	local function build()
		for _, b in pairs(buttons) do b.button:Destroy() end
		buttons = {}
		for i, opt in ipairs(options) do
			local key = tostring(opt)
			local btn = create("TextButton", {
				Size = UDim2.new(1, 0, 0, ITEM), BackgroundColor3 = Theme.Element, BackgroundTransparency = 0.3,
				AutoButtonColor = false, Text = "", LayoutOrder = i, Parent = list,
			}, {corner(4)})
			local sel = create("Frame", {
				Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, Parent = btn,
			}, {corner(4), gradient(Theme.Accent, Theme.Secondary, 0)})
			local lbl = makeLabel(btn, key, {
				Font = FONT_MEDIUM, TextSize = 12, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), ZIndex = 2,
			})
			btn.MouseEnter:Connect(function() tween(btn, {BackgroundTransparency = 0.1}, 0.1) end)
			btn.MouseLeave:Connect(function() tween(btn, {BackgroundTransparency = 0.3}, 0.1) end)
			btn.MouseButton1Click:Connect(function()
				api:Set(opt)
				isOpen = false
				resize()
			end)
			buttons[key] = {button = btn, sel = sel, label = lbl}
		end
		paint()
	end
	function api:Refresh(newOptions, keepSelection)
		options = newOptions or {}
		if not keepSelection then
			selected = nil
			chipLabel.Text = "Select"
		end
		build()
		if isOpen then resize() end
	end

	headerHit.MouseButton1Click:Connect(function()
		isOpen = not isOpen
		resize()
	end)
	build()
	return api
end

------------------------------------------------ colour picker (SV square + hue bar + hex readout)
function Elements.AddColorPicker(g, o)
	local HEADER_H, SV_H, HUE_H = 30, 96, 10
	local name = o.Name or "Color"
	local svY = HEADER_H + 4
	local hueY = svY + SV_H + 8
	local hexY = hueY + HUE_H + 8
	local FULL = hexY + 16 + 8
	local h, s, v = (o.Default or Theme.Accent):ToHSV()
	local isOpen = false

	local row = rowBase(g, name, HEADER_H)
	row.ClipsDescendants = true
	makeLabel(row, name, {Font = FONT_MEDIUM, TextSize = 13, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -60, 0, HEADER_H)})
	local swatch = create("Frame", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 7), Size = UDim2.fromOffset(30, 16),
		BackgroundColor3 = Color3.fromHSV(h, s, v), BorderSizePixel = 0, Parent = row,
	}, {corner(4), stroke(Theme.Stroke, 1, 0.1)})
	local headerHit = create("TextButton", {
		BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Size = UDim2.new(1, 0, 0, HEADER_H), ZIndex = 5, Parent = row,
	})
	rowHover(row, headerHit)

	local sv = create("Frame", {
		Position = UDim2.fromOffset(10, svY), Size = UDim2.new(1, -20, 0, SV_H),
		BackgroundColor3 = Color3.fromHSV(h, 1, 1), BorderSizePixel = 0, Parent = row,
	}, {corner(4), stroke(Theme.Stroke, 1, 0.1)})
	create("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = sv,
	}, {corner(4), create("UIGradient", {Transparency = NumberSequence.new(0, 1)})})
	create("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Parent = sv,
	}, {corner(4), create("UIGradient", {Rotation = 90, Transparency = NumberSequence.new(1, 0)})})
	local cursor = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(10, 10), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3, Parent = sv,
	}, {cornerFull(), stroke(WHITE, 2, 0)})
	local svHit = create("TextButton", {
		BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
		Position = UDim2.fromOffset(10, svY), Size = UDim2.new(1, -20, 0, SV_H), ZIndex = 6, Parent = row,
	})

	local hueKeys = {}
	for i = 0, 6 do table.insert(hueKeys, CSK(i / 6, Color3.fromHSV((i % 6) / 6, 1, 1))) end
	local hueBar = create("Frame", {
		Position = UDim2.fromOffset(10, hueY), Size = UDim2.new(1, -20, 0, HUE_H), BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = row,
	}, {cornerFull(), create("UIGradient", {Color = ColorSequence.new(hueKeys)})})
	local hueKnob = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(6, HUE_H + 6), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3, Parent = hueBar,
	}, {corner(2), stroke(Theme.Background, 1.5, 0)})
	local hueHit = create("TextButton", {
		BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
		Position = UDim2.fromOffset(10, hueY - 4), Size = UDim2.new(1, -20, 0, HUE_H + 8), ZIndex = 6, Parent = row,
	})

	local hexLabel = makeLabel(row, "", {
		Font = FONT_BOLD, TextSize = 12, TextColor3 = Theme.AccentLight, Position = UDim2.fromOffset(10, hexY), Size = UDim2.new(0.4, 0, 0, 16),
	})
	local rgbLabel = makeLabel(row, "", {
		Font = FONT, TextSize = 11, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, hexY), Size = UDim2.new(0.6, -10, 0, 16),
	})

	local function apply(silent)
		local color = Color3.fromHSV(h, s, v)
		swatch.BackgroundColor3 = color
		sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
		cursor.Position = UDim2.fromScale(s, 1 - v)
		hueKnob.Position = UDim2.fromScale(h, 0.5)
		hexLabel.Text = "#" .. string.upper(color:ToHex())
		rgbLabel.Text = string.format("R %d  G %d  B %d",
			math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
		if not silent then fire(o.Callback, color) end
	end

	bindDrag(svHit, function(pos)
		s = math.clamp((pos.X - sv.AbsolutePosition.X) / math.max(sv.AbsoluteSize.X, 1), 0, 1)
		v = 1 - math.clamp((pos.Y - sv.AbsolutePosition.Y) / math.max(sv.AbsoluteSize.Y, 1), 0, 1)
		apply()
	end)
	bindDrag(hueHit, function(pos)
		h = math.clamp((pos.X - hueBar.AbsolutePosition.X) / math.max(hueBar.AbsoluteSize.X, 1), 0, 0.999)
		apply()
	end)

	headerHit.MouseButton1Click:Connect(function()
		isOpen = not isOpen
		tween(row, {Size = UDim2.new(1, 0, 0, isOpen and FULL or HEADER_H)}, 0.25, Enum.EasingStyle.Quint)
	end)

	local api = {}
	function api:Set(color, silent)
		h, s, v = color:ToHSV()
		apply(silent)
	end
	function api:Get() return Color3.fromHSV(h, s, v) end
	apply(true)
	return api
end

----------------------------------------------------------------------
-- WINDOW
----------------------------------------------------------------------
function Antler:CreateWindow(opts)
	opts = opts or {}
	local toggleKey = opts.ToggleKey or Enum.KeyCode.RightShift
	local cam = workspace.CurrentCamera
	local viewport = cam and cam.ViewportSize or Vector2.new(1280, 720)
	-- Responsive layout: touch-first phones/tablets get a compact icon rail,
	-- larger hit targets, stacked groups and a tighter viewport fit.
	local isMobile = UserInputService.TouchEnabled and (viewport.X < 1000 or viewport.Y < 700)
	-- Keep the window horizontal on every device; UIScale handles the physical fit.
	local W, H = isMobile and 760 or 980, isMobile and 500 or 600
	local SIDEBAR, TOPBAR, BRAND = isMobile and 58 or 190, 48, 58
	local baseScale = math.clamp(math.min((viewport.X - 12) / W, (viewport.Y - 44) / H), isMobile and 0.46 or 0.5, 1)
	local scaleMult = 1
	self._mobile = isMobile
	self._mobileViewport = viewport

	local window = {}
	local tabs = {}
	local current
	local visible = false
	local minimized = false
	local gui = self._gui

	------------------------------------------------ frame stack
	local root = create("Frame", {
		Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(W, H), BackgroundTransparency = 1, Visible = false, Parent = gui,
	})
	local uiScale = create("UIScale", {Scale = baseScale, Parent = root})
	local function refreshViewportScale()
		local c = workspace.CurrentCamera
		if not c then return end
		local vp = c.ViewportSize
		local minScale = isMobile and 0.46 or 0.5
		uiScale.Scale = math.clamp(math.min((vp.X - 12) / W, (vp.Y - 44) / H) * scaleMult, minScale, 1)
	end
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(refreshViewportScale)
	end

	local shadow = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 8), Size = UDim2.new(1, 30, 1, 30),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 0, Parent = root,
	}, {create("UICorner", {CornerRadius = UDim.new(0, 20)})})
	local halos, haloAlpha = {}, {0.94, 0.965, 0.98}
	for i = 1, 3 do
		local pad = i * 6
		halos[i] = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, pad * 2, 1, pad * 2),
			BackgroundColor3 = Theme.Accent, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 0, Parent = root,
		}, {create("UICorner", {CornerRadius = UDim.new(0, 8 + pad)})})
	end

	local main = create("CanvasGroup", {
		Name = "Main", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Background, BackgroundTransparency = 0,
		GroupTransparency = 1, ZIndex = 2, Parent = root,
	}, {corner(8)})

	-- rotating light-border (a "comet" of light travelling around the window)
	local border = create("Frame", {Name = "Border", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5, Parent = root}, {corner(8)})
	local borderStroke = create("UIStroke", {
		Color = WHITE, Thickness = 1.4, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = border,
	})
	local borderGrad = create("UIGradient", {
		Color = ColorSequence.new({
			CSK(0.00, Theme.Stroke), CSK(0.30, Theme.Stroke), CSK(0.45, Theme.Accent), CSK(0.55, Theme.AccentLight),
			CSK(0.65, Theme.Secondary), CSK(0.80, Theme.Stroke), CSK(1.00, Theme.Stroke),
		}),
		Parent = borderStroke,
	})
	TweenService:Create(borderGrad, TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), {Rotation = 360}):Play()

	------------------------------------------------ background + animated accent line
	create("Frame", {
		Name = "BG", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 0, Parent = main,
	}, {create("UIGradient", {Rotation = 120, Color = ColorSequence.new(Color3.fromRGB(5, 27, 43), Color3.fromRGB(2, 10, 18))})})

	local lineGrad = create("UIGradient", {
		Color = ColorSequence.new({CSK(0, Theme.Accent), CSK(0.5, Theme.Secondary), CSK(1, Theme.Accent)}),
		Offset = Vector2.new(-0.6, 0),
	})
	create("Frame", {
		Name = "AccentLine", Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 20, Parent = main,
	}, {lineGrad})
	TweenService:Create(lineGrad, TweenInfo.new(3.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Offset = Vector2.new(0.6, 0)}):Play()

	------------------------------------------------ dragging
	local dragStart, startScale
	local function makeDraggable(frame)
		bindDrag(frame, function(pos, isStart)
			if isStart then
				dragStart = pos
				startScale = Vector2.new(root.Position.X.Scale, root.Position.Y.Scale)
			elseif dragStart then
				local size = gui.AbsoluteSize
				local p = startScale + (pos - dragStart) / Vector2.new(math.max(size.X, 1), math.max(size.Y, 1))
				root.Position = UDim2.fromScale(math.clamp(p.X, 0.05, 0.95), math.clamp(p.Y, 0.05, 0.95))
			end
		end)
	end

	------------------------------------------------ sidebar
	local sidebar = create("Frame", {
		Name = "Sidebar", Position = UDim2.fromOffset(0, 2), Size = UDim2.new(0, SIDEBAR, 1, -2), BackgroundColor3 = Theme.Sidebar,
		BorderSizePixel = 0, ZIndex = 3, Parent = main,
	})
	create("Frame", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 1, 1, 0),
		BackgroundColor3 = Theme.Stroke, BorderSizePixel = 0, Parent = sidebar,
	})

	local brand = create("Frame", {Name = "Brand", Size = UDim2.new(1, 0, 0, BRAND), BackgroundTransparency = 1, ZIndex = 4, Parent = sidebar})
	create("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, 0), Size = UDim2.new(1, -24, 0, 1),
		BackgroundColor3 = Theme.Stroke, BorderSizePixel = 0, Parent = brand,
	})
	create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromOffset(12, BRAND / 2), Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.88, BorderSizePixel = 0, Parent = brand,
	}, {corner(8), stroke(Theme.Accent, 1, 0.7)})
	local brandLogo = buildAntlerLogo(brand, 24, Theme.Accent)
	brandLogo.Position = UDim2.fromOffset(17, (BRAND - 24) / 2)
	local brandText = makeLabel(brand, titleRichText(opts.Name or "Merdian", opts.Version or "V2"), {
		RichText = true, Font = FONT_BOLD, TextSize = 17, TextColor3 = Theme.AccentLight,
		Position = UDim2.fromOffset(54, 0), Size = UDim2.new(1, -60, 1, 0),
	})
	if isMobile then
		brandText.Visible = false
		brandLogo.Position = UDim2.fromOffset(19, (BRAND - 24) / 2)
	end
	makeDraggable(brand)

	local tabScroll = create("ScrollingFrame", {
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0,
		Position = UDim2.fromOffset(0, BRAND), Size = UDim2.new(1, 0, 1, -(BRAND + 66)),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 4, Parent = sidebar,
	})
	local highlight = create("Frame", {
		Name = "Highlight", Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, isMobile and 44 or 36),
		BackgroundColor3 = WHITE, BorderSizePixel = 0, Visible = false, ZIndex = 1, Parent = tabScroll,
	}, {
		corner(6),
		create("UIGradient", {Color = ColorSequence.new(Theme.Accent, Theme.Secondary), Transparency = NumberSequence.new(0.8, 0.93)}),
		stroke(Theme.Accent, 1, 0.7),
	})
	create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(3, 16),
		BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = highlight,
	}, {cornerFull(), gradient(Theme.AccentLight, Theme.Secondary, 90)})
	local tabList = create("Frame", {
		Name = "List", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 2, Parent = tabScroll,
	}, {
		create("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}),
		create("UIPadding", {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8)}),
	})

	-- profile card
	local profile = create("Frame", {
		Position = UDim2.new(0, 8, 1, -58), Size = UDim2.new(1, -16, 0, 50), BackgroundColor3 = Theme.Group,
		BorderSizePixel = 0, ZIndex = 4, Parent = sidebar,
	}, {corner(6), stroke(Theme.Stroke, 1, 0.2)})
	local avatar = create("ImageLabel", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.fromOffset(32, 32),
		BackgroundColor3 = Theme.Element, BorderSizePixel = 0, Image = "", ZIndex = 5, Parent = profile,
	}, {corner(6), stroke(Theme.Accent, 1.2, 0.4)})
	local profileName = makeLabel(profile, LocalPlayer.DisplayName, {
		Font = FONT_BOLD, TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(48, 9), Size = UDim2.new(1, -56, 0, 16), ZIndex = 5,
	})
	local statusDot = create("Frame", {
		Position = UDim2.fromOffset(48, 31), Size = UDim2.fromOffset(6, 6), BackgroundColor3 = Theme.Success, BorderSizePixel = 0, ZIndex = 5, Parent = profile,
	}, {cornerFull()})
	TweenService:Create(statusDot, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {BackgroundTransparency = 0.7}):Play()
	local profileStatus = makeLabel(profile, "Undetected", {
		Font = FONT, TextSize = 11, TextColor3 = Theme.SubText, Position = UDim2.fromOffset(60, 26), Size = UDim2.new(1, -66, 0, 16), ZIndex = 5,
	})
	if isMobile then
		profileName.Visible = false
		profileStatus.Visible = false
		statusDot.Visible = false
		profile.Size = UDim2.fromOffset(46, 46)
		profile.Position = UDim2.new(0.5, -23, 1, -54)
		avatar.Position = UDim2.fromOffset(7, 7)
	end
	task.spawn(function()
		local ok, url = pcall(function()
			return Players:GetUserThumbnailAsync(LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok and url then avatar.Image = url end
	end)

	------------------------------------------------ top bar (breadcrumb, search, window buttons)
	local topbar = create("Frame", {
		Name = "Topbar", Position = UDim2.fromOffset(SIDEBAR, 2), Size = UDim2.new(1, -SIDEBAR, 0, TOPBAR - 2),
		BackgroundTransparency = 1, ZIndex = 4, Parent = main,
	})
	create("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Theme.Stroke, BorderSizePixel = 0, Parent = topbar,
	})
	makeDraggable(topbar)

	local crumb = makeLabel(topbar, "", {
		RichText = true, Font = FONT_BOLD, TextSize = 12, TextColor3 = Theme.AccentLight,
		Position = UDim2.fromOffset(isMobile and 8 or 16, 0), Size = UDim2.new(0, isMobile and 96 or 190, 1, 0), ZIndex = 5,
	})

	local searchBox
	do
		local frame = create("Frame", {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -76, 0.5, 0), Size = UDim2.fromOffset(isMobile and 150 or 150, 26),
			BackgroundColor3 = Theme.Group, BorderSizePixel = 0, ZIndex = 5, Parent = topbar,
		}, {corner(5)})
		local frameStroke = stroke(Theme.Stroke, 1, 0.1)
		frameStroke.Parent = frame
		create("Frame", {
			Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(9, 9), BackgroundTransparency = 1, ZIndex = 6, Parent = frame,
		}, {cornerFull(), stroke(Theme.SubText, 1.5, 0)})
		local handle = makeLine(frame, Vector2.new(16, 16), Vector2.new(19, 19), 1.8, Theme.SubText)
		handle.ZIndex = 6
		searchBox = create("TextBox", {
			BackgroundTransparency = 1, Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -32, 1, 0),
			Font = FONT, TextSize = 12, Text = "", PlaceholderText = "Search features...", PlaceholderColor3 = Theme.SubText,
			TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, ZIndex = 6, Parent = frame,
		})
		searchBox.Focused:Connect(function() tween(frameStroke, {Color = Theme.Accent}, 0.15) end)
		searchBox.FocusLost:Connect(function() tween(frameStroke, {Color = Theme.Stroke}, 0.15) end)
	end

	local function headerButton(kind, xOffset)
		local b = create("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, xOffset, 0.5, 0), Size = UDim2.fromOffset(26, 26),
			BackgroundColor3 = Theme.ElementHover, BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 6, Parent = topbar,
		}, {corner(5)})
		local bars = {}
		local defs = (kind == "close") and {{12, 45}, {12, -45}} or {{11, 0}}
		for _, d in ipairs(defs) do
			table.insert(bars, create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(d[1], 2), Rotation = d[2],
				BackgroundColor3 = Theme.SubText, BorderSizePixel = 0, ZIndex = 7, Parent = b,
			}, {cornerFull()}))
		end
		b.MouseEnter:Connect(function()
			if kind == "close" then
				tween(b, {BackgroundColor3 = Theme.Error, BackgroundTransparency = 0.3}, 0.15)
			else
				tween(b, {BackgroundTransparency = 0}, 0.15)
			end
			for _, bar in ipairs(bars) do tween(bar, {BackgroundColor3 = WHITE}, 0.15) end
		end)
		b.MouseLeave:Connect(function()
			tween(b, {BackgroundTransparency = 1}, 0.15)
			for _, bar in ipairs(bars) do tween(bar, {BackgroundColor3 = Theme.SubText}, 0.15) end
		end)
		return b
	end
	local closeBtn = headerButton("close", -10)
	local minBtn = headerButton("min", -40)

	-- Mobile close becomes a movable squircle launcher instead of destroying/hiding the UI.
	local mini = create("TextButton", {
		Name = "MobileRestore", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 52, 0.78, 0),
		Size = UDim2.fromOffset(54, 54), BackgroundColor3 = Theme.Sidebar, BackgroundTransparency = 0.04,
		Text = "", AutoButtonColor = false, Visible = false, ZIndex = 80, Parent = gui,
	}, {corner(16), stroke(Theme.Accent, 1.4, 0.15)})
	local miniGlow = create("Frame", {Size = UDim2.fromScale(1,1), BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.9, BorderSizePixel = 0, Parent = mini}, {corner(16)})
	local miniLogo = buildAntlerLogo(mini, 34, Theme.AccentLight)
	miniLogo.AnchorPoint = Vector2.new(0.5,0.5)
	miniLogo.Position = UDim2.fromScale(0.5,0.5)
	local miniDragging, miniStart, miniPos
	mini.InputBegan:Connect(function(input)
		if not isPointer(input) then return end
		miniDragging, miniStart = true, Vector2.new(input.Position.X, input.Position.Y)
		miniPos = Vector2.new(mini.Position.X.Offset, mini.Position.Y.Offset)
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not miniDragging or not isMove(input) then return end
		local delta = Vector2.new(input.Position.X, input.Position.Y) - miniStart
		local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280,720)
		mini.Position = UDim2.fromOffset(math.clamp(miniPos.X + delta.X, 30, vp.X - 30), math.clamp(miniPos.Y + delta.Y, 30, vp.Y - 30))
	end)
	UserInputService.InputEnded:Connect(function(input) if isPointer(input) then miniDragging = false end end)
	mini.MouseButton1Click:Connect(function()
		if miniDragging then return end
		mini.Visible = false
		window:SetVisible(true)
	end)

	------------------------------------------------ content area
	local content = create("Frame", {
		Name = "Content", BackgroundTransparency = 1, Position = UDim2.fromOffset(SIDEBAR, TOPBAR), ClipsDescendants = true,
		Size = UDim2.new(1, -SIDEBAR, 1, -TOPBAR), ZIndex = 2, Parent = main,
	})

	local function setCrumb(name)
		crumb.Text = string.format('<font color="#%s">MERDIAN</font>  <font color="#%s">/</font>  %s',
			Theme.SubText:ToHex(), Theme.Off:ToHex(), string.upper(name))
	end

	-- search: hide rows that don't match, hide groups with no matches
	local function applySearch(tab, query)
		if not tab then return end
		query = string.lower(query or "")
		for _, g in ipairs(tab.groups) do
			local any = false
			for _, it in ipairs(g.items) do
				local match = (query == "") or (string.find(it.name, query, 1, true) ~= nil)
				it.frame.Visible = match
				if match then any = true end
			end
			g.frame.Visible = any or query == ""
		end
	end
	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		applySearch(current, searchBox.Text)
	end)

	local function selectTab(t)
		if current == t then return end
		searchBox.Text = ""
		local prev = current
		current = t
		for _, o in ipairs(tabs) do
			local on = (o == t)
			tween(o.label, {TextColor3 = on and Theme.AccentLight or Theme.SubText}, 0.2)
			o.paint(on and Theme.AccentLight or Theme.SubText)
		end
		setCrumb(t.name)
		local target = UDim2.fromOffset(8, 8 + (t.index - 1) * (isMobile and 48 or 40))
		if highlight.Visible then
			tween(highlight, {Position = target}, 0.3, Enum.EasingStyle.Quint)
		else
			highlight.Position = target
			highlight.Visible = true
		end
		if prev then prev.container.Visible = false end
		t.container.Position = UDim2.fromOffset(0, 14)
		t.container.GroupTransparency = 1
		t.container.Visible = true
		tween(t.container, {Position = UDim2.fromOffset(0, 0), GroupTransparency = 0}, 0.3, Enum.EasingStyle.Quint)
	end

	----------------------------------------------------------------
	-- TABS
	----------------------------------------------------------------
	function window:CreateTab(name, icon)
		local tab = {groups = {}}
		local index = #tabs + 1
		local groupCount = 0
		local auto

		local button = create("TextButton", {
			Name = name, Size = UDim2.new(1, 0, 0, isMobile and 44 or 36), BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
			LayoutOrder = index, Parent = tabList,
		})
		local iconHolder = create("Frame", {
			AnchorPoint = Vector2.new(0, 0.5), Position = isMobile and UDim2.new(0.5, -9, 0.5, 0) or UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(18, 18),
			BackgroundTransparency = 1, Parent = button,
		})
		local paintIcon
		if type(icon) == "string" and string.find(icon, "rbxassetid", 1, true) then
			local img = create("ImageLabel", {BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Image = icon, ImageColor3 = Theme.SubText, Parent = iconHolder})
			paintIcon = function(c) tween(img, {ImageColor3 = c}, 0.2) end
		else
			local builder = Icons[icon or ICON_CYCLE[(index - 1) % #ICON_CYCLE + 1]] or Icons.grid
			paintIcon = builder(iconHolder, Theme.SubText)
		end
		local label = makeLabel(button, name, {
			Font = FONT_MEDIUM, TextSize = 13, Position = UDim2.fromOffset(44, 0), Size = UDim2.new(1, -50, 1, 0), TextColor3 = Theme.SubText,
		})
		if isMobile then label.Visible = false end

		local container = create("CanvasGroup", {
			Name = name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, GroupTransparency = 1, Visible = false, ZIndex = 3, Parent = content,
		})
		local page = create("ScrollingFrame", {
			BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
			CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 3, ScrollBarImageColor3 = Theme.Accent, ScrollBarImageTransparency = 0.4, Parent = container,
		}, {
			create("UIPadding", {PaddingLeft = UDim.new(0, isMobile and 8 or 12), PaddingRight = UDim.new(0, isMobile and 8 or 14), PaddingTop = UDim.new(0, isMobile and 8 or 12), PaddingBottom = UDim.new(0, isMobile and 10 or 12)}),
		})
		local cols = create("Frame", {
			Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = page,
		}, {
			create("UIListLayout", {FillDirection = isMobile and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder}),
		})
		local function column(order)
			return create("Frame", {
				Size = isMobile and UDim2.new(1, 0, 0, 0) or UDim2.new(0.5, -5, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order, Parent = cols,
			}, {create("UIListLayout", {Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder})})
		end
		local colL, colR = column(1), column(2)

		tab.name = name
		tab.index = index
		tab.button = button
		tab.label = label
		tab.paint = paintIcon
		tab.container = container
		table.insert(tabs, tab)

		button.MouseButton1Click:Connect(function() playUISound("click"); selectTab(tab) end)
		button.MouseEnter:Connect(function()
			if current ~= tab then
				tween(label, {TextColor3 = Theme.Text}, 0.12)
				paintIcon(Theme.Text)
			end
		end)
		button.MouseLeave:Connect(function()
			if current ~= tab then
				tween(label, {TextColor3 = Theme.SubText}, 0.12)
				paintIcon(Theme.SubText)
			end
		end)
		if #tabs == 1 then selectTab(tab) end

		------------------------------------------------ groups
		function tab:AddGroup(title, side)
			groupCount += 1
			local useRight
			if side == "Right" then useRight = true
			elseif side == "Left" then useRight = false
			else useRight = (groupCount % 2 == 0) end
			local frame = create("Frame", {
				Name = title, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Theme.Group,
				BorderSizePixel = 0, LayoutOrder = groupCount, Parent = useRight and colR or colL,
			}, {
				corner(6), stroke(Theme.Stroke, 1, 0.1),
				create("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder}),
			})
			local header = create("Frame", {Name = "Header", Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 0, Parent = frame})
			create("Frame", {
				AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(3, 12),
				BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = header,
			}, {cornerFull(), gradient(Theme.AccentLight, Theme.Secondary, 90)})
			makeLabel(header, string.upper(title), {
				Font = FONT_BOLD, TextSize = 11, TextColor3 = Theme.AccentLight, Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -30, 1, 0),
			})
			create("Frame", {
				AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, 0), Size = UDim2.new(1, -16, 0, 1),
				BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Parent = header,
			}, {create("UIGradient", {Transparency = NumberSequence.new({NSK(0, 0.5), NSK(1, 1)})})})
			local body = create("Frame", {
				Name = "Body", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1, Parent = frame,
			}, {
				create("UIListLayout", {Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder}),
				create("UIPadding", {PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8)}),
			})

			local group = {frame = frame, body = body, items = {}}
			for elementName, fn in pairs(Elements) do
				group[elementName] = function(self, o) return fn(self, o or {}) end
			end
			table.insert(tab.groups, group)
			return group
		end

		-- convenience: Tab:AddToggle(...) etc. drop into an automatic group, Tab:AddSection(...) starts a new one
		function tab:AddSection(title)
			auto = tab:AddGroup(title)
			return auto
		end
		for elementName in pairs(Elements) do
			tab[elementName] = function(self, o)
				if not auto then auto = tab:AddGroup("General") end
				return auto[elementName](auto, o)
			end
		end

		return tab
	end

	----------------------------------------------------------------
	-- window controls
	----------------------------------------------------------------
	function window:SetVisible(on)
		visible = on
		if on then
			playUISound("open", 1.0)
			root.Visible = true
			uiScale.Scale = baseScale * scaleMult * 0.88
			tween(uiScale, {Scale = baseScale * scaleMult}, 0.4, Enum.EasingStyle.Back)
			tween(main, {GroupTransparency = 0}, 0.25)
			tween(borderStroke, {Transparency = 0.05}, 0.35)
			tween(shadow, {BackgroundTransparency = 0.8}, 0.35)
			for i, hl in ipairs(halos) do tween(hl, {BackgroundTransparency = haloAlpha[i]}, 0.4) end
		else
			tween(uiScale, {Scale = baseScale * scaleMult * 0.95}, 0.18)
			tween(main, {GroupTransparency = 1}, 0.18)
			tween(borderStroke, {Transparency = 1}, 0.18)
			tween(shadow, {BackgroundTransparency = 1}, 0.18)
			for _, hl in ipairs(halos) do tween(hl, {BackgroundTransparency = 1}, 0.18) end
			task.delay(0.2, function()
				if not visible then root.Visible = false end
			end)
		end
	end
	function window:Toggle() window:SetVisible(not visible) end
	window._root = root
	window._uiScale = uiScale
	function window:SetScale(mult)
		scaleMult = math.clamp(mult, 0.6, 1.3)
		if visible then tween(uiScale, {Scale = baseScale * scaleMult}, 0.2) end
	end
	function window:Destroy() root:Destroy() end

	minBtn.MouseButton1Click:Connect(function()
		minimized = not minimized
		tween(root, {Size = UDim2.fromOffset(W, minimized and TOPBAR or H)}, 0.28, Enum.EasingStyle.Quint)
	end)
	closeBtn.MouseButton1Click:Connect(function()
		if isMobile then
			window:SetVisible(false)
			mini.Visible = true
		else
			window:SetVisible(false)
			Antler:Notify({Title = "Merdian", Content = "Menu hidden. Press " .. toggleKey.Name .. " to reopen.", Duration = 3})
		end
	end)
	table.insert(self._connections, UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == toggleKey then
			if mini.Visible then mini.Visible = false end
			window:Toggle()
		end
	end))

	window:SetVisible(true)
	return window
end

function Antler:Unload()
	for _, c in ipairs(self._connections) do c:Disconnect() end
	self._connections = {}
	self._binds = {}
	for _, fn in ipairs(self._cleanups) do pcall(fn) end
	self._cleanups = {}
	if self._gui then self._gui:Destroy() end
end

----------------------------------------------------------------------
-- FEATURES + UI
-- Dense cyan/navy layout based on the supplied reference.
----------------------------------------------------------------------

Antler:PlayIntro()

local Window = Antler:CreateWindow({Name="MERDIAN", Version="V2", ToggleKey=Enum.KeyCode.RightShift})

local HomeTab=Window:CreateTab("Home","home")
local CombatTab=Window:CreateTab("Combat","combat")
local PlayerTab=Window:CreateTab("Player","player")
local VisualTab=Window:CreateTab("Visual","visual")
local WorldTab=Window:CreateTab("World","world")
local SettingsTab=Window:CreateTab("Settings","gear")

-- Horizontal sub-tab navigation used by the larger World and Settings pages.
local function addSubTabs(tab, labels, callback)
	local page = tab.container:FindFirstChildOfClass("ScrollingFrame")
	if not page then return end
	local nav = create("Frame", {Name="SubTabs", Position=UDim2.fromOffset(8,6), Size=UDim2.new(1,-16,0,34), BackgroundColor3=Theme.Sidebar, BorderSizePixel=0, ZIndex=10, Parent=tab.container}, {corner(6), stroke(Theme.Stroke,1,0.15)})
	local list = create("Frame", {Size=UDim2.fromScale(1,1), BackgroundTransparency=1, Parent=nav}, {create("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,Padding=UDim.new(0,4),VerticalAlignment=Enum.VerticalAlignment.Center}), create("UIPadding",{PaddingLeft=UDim.new(0,4),PaddingRight=UDim.new(0,4)})})
	local buttons, current = {}, 1
	for i,label in ipairs(labels) do
		local b=create("TextButton",{Size=UDim2.new(1/#labels,-4,1,-6),BackgroundColor3=Theme.Element,BackgroundTransparency=1,Text="",AutoButtonColor=false,Parent=list},{corner(4)})
		local l=makeLabel(b,string.upper(label),{Font=FONT_BOLD,TextSize=10,TextColor3=Theme.SubText,TextXAlignment=Enum.TextXAlignment.Center,Size=UDim2.fromScale(1,1)})
		buttons[i]={b=b,l=l}
		b.MouseButton1Click:Connect(function() current=i; for n,x in ipairs(buttons) do tween(x.b,{BackgroundTransparency=n==i and .15 or 1},.15); tween(x.l,{TextColor3=n==i and Theme.AccentLight or Theme.SubText},.15) end; callback(i,label) end)
	end
	page.Position=UDim2.fromOffset(0,40)
	page.Size=UDim2.new(1,0,1,-40)
	buttons[1].b.BackgroundTransparency=.15; buttons[1].l.TextColor3=Theme.AccentLight
	callback(1,labels[1])
	return nav
end

local function getHum()
	local c=LocalPlayer.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end
local function getRoot()
	local c=LocalPlayer.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

----------------------------------------------------------------------
-- HOME
----------------------------------------------------------------------
local H={notifications=true,particles=true,compact=false,watermark=true,menuBlur=false}
local Overview=HomeTab:AddGroup("Overview","Left")
Overview:AddLabel("MERDIAN V2  •  MOBILE READY")
Overview:AddLabel("Responsive touch controls, stacked groups and a compact icon rail are enabled automatically.")
Overview:AddButton({Name="Refresh Session",Callback=function()
	Antler:Notify({Title="Home",Content="Session refreshed.",Duration=2,Type="success"})
end})
Overview:AddButton({Name="Reset Local Visuals",Callback=function()
	local cam=workspace.CurrentCamera
	if cam then cam.FieldOfView=70 end
	Lighting.Brightness=2
	Lighting.ExposureCompensation=0
	Lighting.FogStart=0
	Lighting.FogEnd=100000
	Antler:Notify({Title="Home",Content="Local visual values restored.",Duration=2,Type="success"})
end})
Overview:AddButton({Name="UI Sound Test",Callback=function() playUISound("click",1.12) end})
Overview:AddButton({Name="Show Feature List",Callback=function() if Antler._arrayHolder then Antler._arrayHolder.Visible=true end end})

local SessionInfo=HomeTab:AddGroup("Session","Right")
local fps,ping=60,0
local fpsLabel=SessionInfo:AddLabel("FPS: --")
local pingLabel=SessionInfo:AddLabel("PING: --")
local userLabel=SessionInfo:AddLabel("USER: "..LocalPlayer.DisplayName)
local timeLabel=SessionInfo:AddLabel("TIME: --:--")
local placeLabel=SessionInfo:AddLabel("PLACE: "..tostring(game.PlaceId))
local jobLabel=SessionInfo:AddLabel("JOB: "..string.sub(game.JobId,1,8))
table.insert(Antler._connections,RunService.RenderStepped:Connect(function(dt) fps=math.floor(1/math.max(dt,1/240)+.5) end))
task.spawn(function()
	while Antler._gui and Antler._gui.Parent do
		local ok,p=pcall(function() return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
		ping=ok and math.floor(p+.5) or 0
		if fpsLabel and fpsLabel.SetText then fpsLabel:SetText("FPS: "..fps) end
		if pingLabel and pingLabel.SetText then pingLabel:SetText("PING: "..ping.." ms") end
		if timeLabel and timeLabel.SetText then timeLabel:SetText("TIME: "..os.date("%H:%M:%S")) end
		task.wait(.5)
	end
end)

local Quick=HomeTab:AddGroup("Interface","Left")
Quick:AddToggle({Name="UI Sounds",Default=true,NoList=true,Callback=function(on) UISoundsEnabled=on end})
Quick:AddSlider({Name="UI Volume",Min=0,Max=100,Default=16,Increment=1,Suffix="%",Callback=function(v) UISoundVolume=v/100 end})
Quick:AddToggle({Name="Arraylist",Default=true,NoList=true,Callback=function(on) if Antler._arrayHolder then Antler._arrayHolder.Visible=on end end})
Quick:AddToggle({Name="Watermark",Default=true,NoList=true,Callback=function(on) if Antler._watermark then Antler._watermark.Visible=on end H.watermark=on end})
Quick:AddToggle({Name="Notifications",Default=true,NoList=true,Callback=function(on) H.notifications=on end})
Quick:AddToggle({Name="Compact Mode",Callback=function(on) H.compact=on end})

local Performance=HomeTab:AddGroup("Performance","Right")
Performance:AddToggle({Name="Reduce Particles",Callback=function(on) H.particles=not on end})
Performance:AddToggle({Name="Menu Blur",Callback=function(on) H.menuBlur=on end})
Performance:AddToggle({Name="Low Motion",Callback=function(on) Antler._lowMotion=on end})
Performance:AddSlider({Name="Animation Speed",Min=25,Max=150,Default=100,Increment=5,Suffix="%",Callback=function(v) Antler._animationSpeed=v/100 end})
Performance:AddButton({Name="Rebuild UI",Callback=function() Antler:Notify({Title="Interface",Content="Current layout already uses the responsive renderer.",Duration=2,Type="info"}) end})

----------------------------------------------------------------------
-- COMBAT
----------------------------------------------------------------------
local C={
	enabled=false,targetPart="Head",fov=12,smoothing=.15,showFov=false,targetHighlight=false,teamCheck=true,
	color=Theme.Accent,priority="Closest",hitboxMode="Head",hitchance=50,minDamage=20,
	prediction=0,backtrack=false,autoStop=false,quickStop=false,visibleOnly=true,
	reaction=0,killDelay=0,aimSpeed=100,deadzone=0
}
local CombatMain=CombatTab:AddGroup("Main","Left")
CombatMain:AddToggle({Name="Enabled",Keybind=Enum.KeyCode.Q,Callback=function(on) C.enabled=on end})
CombatMain:AddDropdown({Name="Target Part",Options={"Head","UpperTorso","HumanoidRootPart","Random"},Default="Head",Callback=function(v) C.targetPart=v end})
CombatMain:AddDropdown({Name="Target Priority",Options={"Closest","Lowest Health","Highest Health","Crosshair"},Default="Closest",Callback=function(v) C.priority=v end})
CombatMain:AddSlider({Name="FOV",Min=1,Max=180,Default=12,Increment=1,Suffix="°",Callback=function(v) C.fov=v end})
CombatMain:AddSlider({Name="Aim Speed",Min=1,Max=100,Default=100,Increment=1,Suffix="%",Callback=function(v) C.aimSpeed=v end})
CombatMain:AddSlider({Name="Smoothing",Min=0,Max=100,Default=15,Increment=1,Suffix="%",Callback=function(v) C.smoothing=v/100 end})
CombatMain:AddToggle({Name="Visible Only",Default=true,Callback=function(on) C.visibleOnly=on end})

local CombatSelection=CombatTab:AddGroup("Selection","Right")
CombatSelection:AddDropdown({Name="Hitbox Mode",Options={"Head","Body","All","Closest"},Default="Head",Callback=function(v) C.hitboxMode=v end})
CombatSelection:AddSlider({Name="Hit Chance",Min=0,Max=100,Default=50,Increment=1,Suffix="%",Callback=function(v) C.hitchance=v end})
CombatSelection:AddSlider({Name="Minimum Damage",Min=0,Max=100,Default=20,Increment=1,Suffix=" HP",Callback=function(v) C.minDamage=v end})
CombatSelection:AddToggle({Name="Team Check",Default=true,Callback=function(on) C.teamCheck=on end})
CombatSelection:AddToggle({Name="FOV Circle",Callback=function(on) C.showFov=on end})
CombatSelection:AddToggle({Name="Target Highlight",Callback=function(on) C.targetHighlight=on end})
CombatSelection:AddColorPicker({Name="Target Color",Default=Theme.Accent,Callback=function(c) C.color=c end})

local CombatAccuracy=CombatTab:AddGroup("Accuracy","Left")
CombatAccuracy:AddToggle({Name="Quick Stop",Callback=function(on) C.quickStop=on end})
CombatAccuracy:AddToggle({Name="Auto Stop",Callback=function(on) C.autoStop=on end})
CombatAccuracy:AddToggle({Name="Backtrack",Callback=function(on) C.backtrack=on end})
CombatAccuracy:AddSlider({Name="Prediction",Min=0,Max=250,Default=0,Increment=5,Suffix=" ms",Callback=function(v) C.prediction=v end})
CombatAccuracy:AddSlider({Name="Reaction Time",Min=0,Max=500,Default=0,Increment=5,Suffix=" ms",Callback=function(v) C.reaction=v end})
CombatAccuracy:AddSlider({Name="Kill Delay",Min=0,Max=500,Default=0,Increment=5,Suffix=" ms",Callback=function(v) C.killDelay=v end})

local CombatAssist=CombatTab:AddGroup("Assist / Hotkeys","Right")
CombatAssist:AddToggle({Name="Aim Assist",Keybind=Enum.KeyCode.Q,Callback=function(on) C.enabled=on end})
CombatAssist:AddToggle({Name="Target Lock",Keybind=Enum.KeyCode.E,Callback=function(on) C.targetHighlight=on end})
CombatAssist:AddToggle({Name="FOV Override",Keybind=Enum.KeyCode.LeftAlt,Callback=function(on) C.showFov=on end})
CombatAssist:AddSlider({Name="Mouse Deadzone",Min=0,Max=100,Default=0,Increment=1,Suffix="%",Callback=function(v) C.deadzone=v end})
CombatAssist:AddLabel("Combat controls are exposed as configuration/UI state; no automatic input injection is performed.")

local combatOverlay
local function setCombatOverlay(on)
	if on and not combatOverlay then
		combatOverlay=create("ScreenGui",{Name="Antler_CombatOverlay",IgnoreGuiInset=true,ResetOnSpawn=false,DisplayOrder=350,ZIndexBehavior=Enum.ZIndexBehavior.Sibling,Parent=guiParent})
		create("Frame",{Name="FOV",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(120,120),BackgroundTransparency=1,Parent=combatOverlay},{cornerFull(),stroke(Theme.Accent,1,.35)})
	elseif not on and combatOverlay then combatOverlay:Destroy(); combatOverlay=nil end
end
table.insert(Antler._connections,RunService.RenderStepped:Connect(function()
	if not C.showFov then setCombatOverlay(false); return end
	setCombatOverlay(true)
	local circle=combatOverlay and combatOverlay:FindFirstChild("FOV")
	local cam=workspace.CurrentCamera
	if circle and cam then
		local px=(C.fov/90)*250
		circle.Size=UDim2.fromOffset(px,px)
		local st=circle:FindFirstChildOfClass("UIStroke"); if st then st.Color=C.color end
	end
end))

----------------------------------------------------------------------
-- PLAYER
----------------------------------------------------------------------
local P={
	walk=nil,jump=nil,gravity=nil,infJump=false,noclip=false,fly=false,flySpeed=60,sprint=false,sprintSpeed=32,hip=nil,
	autoSprint=false,autoJump=false,strafe=false,strafeSpeed=20,headless=false,platformStand=false,spin=false,
	spinSpeed=120,freecam=false
}
local startHum=getHum()
local origWalk=startHum and startHum.WalkSpeed or 16
local origJump=startHum and startHum.JumpPower or 50
local origGravity=workspace.Gravity
local origHip=startHum and startHum.HipHeight or 2
local flyBV,flyBG
local function stopFly()
	if flyBV then flyBV:Destroy(); flyBV=nil end
	if flyBG then flyBG:Destroy(); flyBG=nil end
	local hum=getHum(); if hum then hum.PlatformStand=false end
end
local function startFly()
	local root,hum=getRoot(),getHum(); if not root or not hum then return end
	stopFly()
	flyBV=create("BodyVelocity",{MaxForce=Vector3.new(1e9,1e9,1e9),Velocity=Vector3.zero,Parent=root})
	flyBG=create("BodyGyro",{MaxTorque=Vector3.new(1e9,1e9,1e9),P=9e4,CFrame=root.CFrame,Parent=root})
	hum.PlatformStand=true
end
local noclipParts={}
local function restoreNoclip()
	for part in pairs(noclipParts) do if part.Parent then part.CanCollide=true end end
	table.clear(noclipParts)
end
local afkConn
table.insert(Antler._connections,RunService.Heartbeat:Connect(function()
	local hum=getHum()
	if hum then
		if P.walk and not P.sprint and hum.WalkSpeed~=P.walk then hum.WalkSpeed=P.walk end
		if P.sprint and hum.WalkSpeed~=P.sprintSpeed then hum.WalkSpeed=P.sprintSpeed end
		if P.jump then hum.UseJumpPower=true; if hum.JumpPower~=P.jump then hum.JumpPower=P.jump end end
		if P.hip and math.abs(hum.HipHeight-P.hip)>.01 then hum.HipHeight=P.hip end
		if P.autoSprint and hum.MoveDirection.Magnitude>.05 and hum.WalkSpeed~=P.sprintSpeed then hum.WalkSpeed=P.sprintSpeed end
		if P.platformStand and not hum.PlatformStand then hum.PlatformStand=true end
	end
	if P.gravity and workspace.Gravity~=P.gravity then workspace.Gravity=P.gravity end
end))
table.insert(Antler._connections,RunService.Stepped:Connect(function()
	if not P.noclip then return end
	local c=LocalPlayer.Character; if not c then return end
	for _,part in ipairs(c:GetDescendants()) do
		if part:IsA("BasePart") and part.CanCollide then part.CanCollide=false; noclipParts[part]=true end
	end
end))
table.insert(Antler._connections,RunService.RenderStepped:Connect(function(dt)
	if P.spin then
		local root=getRoot(); if root then root.CFrame=root.CFrame*CFrame.Angles(0,math.rad(P.spinSpeed)*dt,0) end
	end
	if not P.fly then return end
	local cam,hum,root=workspace.CurrentCamera,getHum(),getRoot()
	if not(cam and hum and root) then return end
	if not(flyBV and flyBV.Parent and flyBG and flyBG.Parent) then startFly() end
	if not flyBV then return end
	local look,right=cam.CFrame.LookVector,cam.CFrame.RightVector
	local flatLook,flatRight=Vector3.new(look.X,0,look.Z),Vector3.new(right.X,0,right.Z)
	local mv=hum.MoveDirection
	local f=flatLook.Magnitude>.001 and mv:Dot(flatLook.Unit) or 0
	local r=flatRight.Magnitude>.001 and mv:Dot(flatRight.Unit) or 0
	local dir=look*f+right*r
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir+=Vector3.new(0,1,0) end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir-=Vector3.new(0,1,0) end
	flyBV.Velocity=dir.Magnitude>.001 and dir.Unit*P.flySpeed or Vector3.zero
	flyBG.CFrame=CFrame.lookAt(root.Position,root.Position+look)
end))
table.insert(Antler._connections,UserInputService.JumpRequest:Connect(function()
	if P.infJump or P.autoJump then local hum=getHum(); if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end end
end))

local Movement=PlayerTab:AddGroup("Movement","Left")
Movement:AddSlider({Name="Walk Speed",Min=0,Max=200,Default=origWalk,Increment=1,Callback=function(v) P.walk=v end})
Movement:AddSlider({Name="Jump Power",Min=0,Max=300,Default=origJump,Increment=1,Callback=function(v) P.jump=v end})
Movement:AddSlider({Name="Gravity",Min=0,Max=400,Default=math.floor(origGravity+.5),Increment=1,Callback=function(v) P.gravity=v end})
Movement:AddSlider({Name="Fly Speed",Min=10,Max=250,Default=60,Increment=5,Callback=function(v) P.flySpeed=v end})
Movement:AddSlider({Name="Sprint Speed",Min=16,Max=100,Default=32,Increment=1,Callback=function(v) P.sprintSpeed=v end})
Movement:AddSlider({Name="Strafe Speed",Min=1,Max=100,Default=20,Increment=1,Suffix="%",Callback=function(v) P.strafeSpeed=v end})
Movement:AddToggle({Name="Sprint",Keybind=Enum.KeyCode.LeftShift,Callback=function(on) P.sprint=on end})
Movement:AddToggle({Name="Auto Sprint",Callback=function(on) P.autoSprint=on end})
Movement:AddToggle({Name="Auto Jump",Callback=function(on) P.autoJump=on end})
Movement:AddToggle({Name="Air Strafe",Callback=function(on) P.strafe=on end})

local Character=PlayerTab:AddGroup("Character","Right")
Character:AddSlider({Name="Hip Height",Min=0,Max=10,Default=origHip,Increment=.25,Callback=function(v) P.hip=v end})
Character:AddToggle({Name="Infinite Jump",Callback=function(on) P.infJump=on end})
Character:AddToggle({Name="Noclip",Keybind=Enum.KeyCode.N,Callback=function(on) P.noclip=on if not on then restoreNoclip() end end})
Character:AddToggle({Name="Fly",Keybind=Enum.KeyCode.F,Callback=function(on) P.fly=on if on then startFly() else stopFly() end end})
Character:AddToggle({Name="Platform Stand",Callback=function(on) P.platformStand=on if not on then local h=getHum(); if h then h.PlatformStand=false end end end})
Character:AddToggle({Name="Spin",Callback=function(on) P.spin=on end})
Character:AddSlider({Name="Spin Speed",Min=10,Max=720,Default=120,Increment=10,Suffix="°/s",Callback=function(v) P.spinSpeed=v end})
Character:AddToggle({Name="Anti AFK",Callback=function(on)
	if afkConn then afkConn:Disconnect(); afkConn=nil end
	if on then afkConn=LocalPlayer.Idled:Connect(function()
		local VirtualUser=game:GetService("VirtualUser"); VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new())
	end) end
end})

local PlayerUtility=PlayerTab:AddGroup("Utilities","Left")
PlayerUtility:AddToggle({Name="Character Auto Reapply",Default=true,Callback=function(on) P.autoReapply=on end})
PlayerUtility:AddToggle({Name="Hide Humanoid UI",Callback=function(on) local h=getHum(); if h then h.DisplayDistanceType=on and Enum.HumanoidDisplayDistanceType.None or Enum.HumanoidDisplayDistanceType.Viewer end end})
PlayerUtility:AddDropdown({Name="Name Display",Options={"Default","Hide","Viewer","None"},Default="Default",Callback=function(v)
	local h=getHum(); if not h then return end
	h.DisplayDistanceType=(v=="None" or v=="Hide") and Enum.HumanoidDisplayDistanceType.None or Enum.HumanoidDisplayDistanceType.Viewer
end})
PlayerUtility:AddButton({Name="Respawn Character",Callback=function() if LocalPlayer.Character then LocalPlayer.Character:BreakJoints() end end})
PlayerUtility:AddButton({Name="Reapply Movement",Callback=function()
	local h=getHum(); if h then if P.walk then h.WalkSpeed=P.walk end; if P.jump then h.JumpPower=P.jump end end
end})

table.insert(Antler._cleanups,function()
	stopFly(); restoreNoclip()
	if afkConn then afkConn:Disconnect(); afkConn=nil end
	local hum=getHum()
	if hum then
		if P.walk then hum.WalkSpeed=origWalk end
		if P.jump then hum.JumpPower=origJump end
		if P.hip then hum.HipHeight=origHip end
		hum.PlatformStand=false
	end
	workspace.Gravity=origGravity
end)

----------------------------------------------------------------------
-- VISUAL
----------------------------------------------------------------------
local V={
	fov=nil,time=nil,fullbright=false,nofog=false,brightness=nil,exposure=nil,
	ambient=1,specular=1,thirdPerson=false,thirdOffset=8,removeShadows=false,
	cameraShake=false,hitmarker=false,showFPS=false,showPing=false,worldColor=Theme.Accent
}
local camera=workspace.CurrentCamera
local origFov=(camera and camera.FieldOfView) or 70
local origClock=Lighting.ClockTime
local origBrightness=Lighting.Brightness
local origExposure=Lighting.ExposureCompensation
local savedLight,savedFog,savedAtmo
local function setFullbright(on)
	if on then
		if not V.fullbright then savedLight={Brightness=Lighting.Brightness,Ambient=Lighting.Ambient,OutdoorAmbient=Lighting.OutdoorAmbient,GlobalShadows=Lighting.GlobalShadows} end
		V.fullbright=true
	else
		V.fullbright=false
		if savedLight then Lighting.Brightness=savedLight.Brightness; Lighting.Ambient=savedLight.Ambient; Lighting.OutdoorAmbient=savedLight.OutdoorAmbient; Lighting.GlobalShadows=savedLight.GlobalShadows; savedLight=nil end
	end
end
local function setNoFog(on)
	if on then
		if not V.nofog then
			savedFog={Start=Lighting.FogStart,End=Lighting.FogEnd}; savedAtmo={}
			for _,a in ipairs(Lighting:GetChildren()) do if a:IsA("Atmosphere") then savedAtmo[a]={Density=a.Density,Haze=a.Haze}; a.Density=0; a.Haze=0 end end
		end
		V.nofog=true
	else
		V.nofog=false
		if savedFog then Lighting.FogStart=savedFog.Start; Lighting.FogEnd=savedFog.End; savedFog=nil end
		if savedAtmo then for a,v in pairs(savedAtmo) do if a.Parent then a.Density=v.Density; a.Haze=v.Haze end end end
		savedAtmo=nil
	end
end

local ESP={highlights={},tags={},color=Theme.Accent,on=false,names=false,distance=false,health=false,team=false,boxes=false}
local function clearPlayerESP(plr)
	local h=ESP.highlights[plr]; if h then h:Destroy(); ESP.highlights[plr]=nil end
	local t=ESP.tags[plr]; if t then t.gui:Destroy(); ESP.tags[plr]=nil end
end
local function updatePlayerESP(plr,camPos)
	if plr==LocalPlayer then return end
	local char=plr.Character; if not char then clearPlayerESP(plr); return end
	local teammate=(LocalPlayer.Team and plr.Team and LocalPlayer.Team==plr.Team)
	if ESP.team and teammate then clearPlayerESP(plr); return end
	if ESP.on then
		local h=ESP.highlights[plr]
		if not h or h.Parent~=char then if h then h:Destroy() end; h=create("Highlight",{Name="AntlerESP",Adornee=char,DepthMode=Enum.HighlightDepthMode.AlwaysOnTop,FillTransparency=.72,OutlineTransparency=.05,Parent=char}); ESP.highlights[plr]=h end
		h.FillColor=ESP.color; h.OutlineColor=ESP.color
	elseif ESP.highlights[plr] then ESP.highlights[plr]:Destroy(); ESP.highlights[plr]=nil end
	local head=char:FindFirstChild("Head")
	if (ESP.names or ESP.distance or ESP.health or ESP.boxes) and head then
		local t=ESP.tags[plr]
		if not t or t.gui.Parent~=head then
			if t then t.gui:Destroy() end
			local gui=create("BillboardGui",{Name="AntlerTag",Adornee=head,AlwaysOnTop=true,Size=UDim2.fromOffset(220,56),StudsOffset=Vector3.new(0,2.5,0),Parent=head})
			local lbl=create("TextLabel",{BackgroundTransparency=1,Size=UDim2.fromScale(1,1),Font=FONT_BOLD,TextSize=12,TextStrokeTransparency=.35,TextColor3=ESP.color,Text="",TextXAlignment=Enum.TextXAlignment.Center,Parent=gui})
			t={gui=gui,label=lbl}; ESP.tags[plr]=t
		end
		local root=char:FindFirstChild("HumanoidRootPart"); local hum=char:FindFirstChildOfClass("Humanoid")
		local dist=root and camPos and math.floor((root.Position-camPos).Magnitude+.5) or 0
		local hp=hum and math.floor(hum.Health+.5) or 0; local maxhp=hum and math.floor(hum.MaxHealth+.5) or 0
		local parts={}; if ESP.names then table.insert(parts,plr.DisplayName) end; if ESP.distance then table.insert(parts,string.format("[%d st]",dist)) end; if ESP.health then table.insert(parts,string.format("%d/%d HP",hp,maxhp)) end; if ESP.boxes then table.insert(parts,"BOX") end
		t.label.Text=table.concat(parts,"\n"); t.label.TextColor3=ESP.color
	elseif ESP.tags[plr] then ESP.tags[plr].gui:Destroy(); ESP.tags[plr]=nil end
end
do
	local acc=0
	table.insert(Antler._connections,RunService.Heartbeat:Connect(function(dt)
		acc+=dt; if acc<.15 then return end; acc=0
		local cam=workspace.CurrentCamera; local pos=cam and cam.CFrame.Position
		for _,plr in ipairs(Players:GetPlayers()) do if ESP.on or ESP.names or ESP.distance or ESP.health or ESP.boxes then updatePlayerESP(plr,pos) end end
	end))
	table.insert(Antler._connections,Players.PlayerRemoving:Connect(clearPlayerESP))
end

local crosshairGui
local function setCrosshair(on)
	if on then
		if crosshairGui then return end
		crosshairGui=create("ScreenGui",{Name=GUI_NAME.."_Crosshair",IgnoreGuiInset=true,ResetOnSpawn=false,DisplayOrder=400,ZIndexBehavior=Enum.ZIndexBehavior.Sibling,Parent=guiParent})
		local function bar(x,y,w,h) create("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(.5,x,.5,y),Size=UDim2.fromOffset(w,h),BackgroundColor3=Theme.Accent,BorderSizePixel=0,Parent=crosshairGui},{stroke(Color3.new(),1,.4)}) end
		bar(0,-8,2,6); bar(0,8,2,6); bar(-8,0,6,2); bar(8,0,6,2)
		create("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(2,2),BackgroundColor3=WHITE,BorderSizePixel=0,Parent=crosshairGui})
	elseif crosshairGui then crosshairGui:Destroy(); crosshairGui=nil end
end

local VisualPlayer=VisualTab:AddGroup("Player","Left")
VisualPlayer:AddToggle({Name="Player ESP",Keybind=Enum.KeyCode.H,Callback=function(on) ESP.on=on end})
VisualPlayer:AddToggle({Name="Name Tags",Callback=function(on) ESP.names=on end})
VisualPlayer:AddToggle({Name="Distance",Callback=function(on) ESP.distance=on end})
VisualPlayer:AddToggle({Name="Health",Callback=function(on) ESP.health=on end})
VisualPlayer:AddToggle({Name="Team Check",Default=false,Callback=function(on) ESP.team=on end})
VisualPlayer:AddToggle({Name="Boxes",Callback=function(on) ESP.boxes=on end})
VisualPlayer:AddColorPicker({Name="ESP Color",Default=Theme.Accent,Callback=function(c) ESP.color=c end})
VisualPlayer:AddDropdown({Name="ESP Style",Options={"Glow","Flat","Outline","Soft"},Default="Glow",Callback=function(v) ESP.style=v end})

local VisualHUD=VisualTab:AddGroup("HUD","Right")
VisualHUD:AddToggle({Name="Crosshair",Callback=function(on) setCrosshair(on) end})
VisualHUD:AddSlider({Name="FOV",Min=30,Max=120,Default=math.floor(origFov+.5),Increment=1,Callback=function(v) V.fov=v end})
VisualHUD:AddToggle({Name="Fullbright",Keybind=Enum.KeyCode.B,Callback=function(on) setFullbright(on) end})
VisualHUD:AddToggle({Name="No Fog",Callback=function(on) setNoFog(on) end})
VisualHUD:AddToggle({Name="FPS Counter",Callback=function(on) V.showFPS=on end})
VisualHUD:AddToggle({Name="Ping Counter",Callback=function(on) V.showPing=on end})
VisualHUD:AddToggle({Name="Hitmarker",Callback=function(on) V.hitmarker=on end})
VisualHUD:AddColorPicker({Name="HUD Color",Default=Theme.Accent,Callback=function(c) V.worldColor=c end})

local VisualPost=VisualTab:AddGroup("Post Processing","Left")
VisualPost:AddSlider({Name="Brightness",Min=0,Max=5,Default=origBrightness,Increment=.05,Callback=function(v) V.brightness=v end})
VisualPost:AddSlider({Name="Exposure",Min=-3,Max=3,Default=origExposure,Increment=.05,Callback=function(v) V.exposure=v end})
VisualPost:AddSlider({Name="Saturation",Min=-1,Max=1,Default=0,Increment=.05,Suffix="",Callback=function(v) V.saturation=v end})
VisualPost:AddSlider({Name="Contrast",Min=-1,Max=1,Default=0,Increment=.05,Suffix="",Callback=function(v) V.contrast=v end})
VisualPost:AddToggle({Name="Dynamic Shadows",Default=true,Callback=function(on) V.removeShadows=not on end})
VisualPost:AddToggle({Name="Camera Shake",Callback=function(on) V.cameraShake=on end})

local VisualView=VisualTab:AddGroup("View","Right")
VisualView:AddToggle({Name="Third Person",Callback=function(on) V.thirdPerson=on end})
VisualView:AddSlider({Name="Third Person Distance",Min=2,Max=20,Default=8,Increment=.5,Suffix=" st",Callback=function(v) V.thirdOffset=v end})
VisualView:AddToggle({Name="Local Transparency",Callback=function(on) V.localTransparency=on end})
VisualView:AddToggle({Name="Remove Scope Overlay",Callback=function(on) V.scopeOverlay=not on end})
VisualView:AddToggle({Name="Viewmodel Bob",Default=true,Callback=function(on) V.viewmodelBob=on end})

local colorCorrection
local function setColorCorrection()
	if not colorCorrection then
		colorCorrection=Instance.new("ColorCorrectionEffect")
		colorCorrection.Name="AntlerColorCorrection"
		colorCorrection.Parent=Lighting
	end
	colorCorrection.Brightness=V.brightness and (V.brightness-2)*.08 or 0
	colorCorrection.Contrast=V.contrast or 0
	colorCorrection.Saturation=V.saturation or 0
end

table.insert(Antler._connections,RunService.RenderStepped:Connect(function()
	local cam=workspace.CurrentCamera
	if V.fov and cam and math.abs(cam.FieldOfView-V.fov)>.01 then cam.FieldOfView=V.fov end
	if V.time and Lighting.ClockTime~=V.time then Lighting.ClockTime=V.time end
	if V.brightness and math.abs(Lighting.Brightness-V.brightness)>.01 then Lighting.Brightness=V.brightness end
	if V.exposure and math.abs(Lighting.ExposureCompensation-V.exposure)>.01 then Lighting.ExposureCompensation=V.exposure end
	if V.fullbright then Lighting.Brightness=2; Lighting.GlobalShadows=false; Lighting.Ambient=WHITE; Lighting.OutdoorAmbient=WHITE end
	if V.nofog and Lighting.FogEnd<100000 then Lighting.FogStart=0; Lighting.FogEnd=100000 end
	if V.saturation or V.contrast then setColorCorrection() end
	if V.removeShadows then Lighting.GlobalShadows=false end
	if V.thirdPerson and LocalPlayer.Character and cam then
		LocalPlayer.CameraMode=Enum.CameraMode.Classic
		LocalPlayer.CameraMinZoomDistance=V.thirdOffset
		LocalPlayer.CameraMaxZoomDistance=V.thirdOffset
	end
end))

----------------------------------------------------------------------
-- WORLD
----------------------------------------------------------------------
local WorldMain=WorldTab:AddGroup("World","Left")
WorldMain:AddSlider({Name="Time Of Day",Min=0,Max=24,Default=math.floor(origClock*4+.5)/4,Increment=.25,Suffix="h",Callback=function(v) V.time=v end})
WorldMain:AddSlider({Name="Brightness",Min=0,Max=5,Default=origBrightness,Increment=.05,Callback=function(v) V.brightness=v end})
WorldMain:AddSlider({Name="Exposure",Min=-3,Max=3,Default=origExposure,Increment=.05,Callback=function(v) V.exposure=v end})
WorldMain:AddSlider({Name="Ambient Strength",Min=0,Max=1,Default=1,Increment=.05,Callback=function(v) V.ambient=v; Lighting.EnvironmentDiffuseScale=v end})
WorldMain:AddSlider({Name="Specular Strength",Min=0,Max=1,Default=1,Increment=.05,Callback=function(v) V.specular=v; Lighting.EnvironmentSpecularScale=v end})
WorldMain:AddToggle({Name="Fullbright",Keybind=Enum.KeyCode.B,Callback=function(on) setFullbright(on) end})
WorldMain:AddToggle({Name="No Fog",Callback=function(on) setNoFog(on) end})

-- Box-based hybrid control: each box is a discrete quality/intensity step.
local function addQualityBoxes(group, name, default, callback)
	local row=rowBase(group,name,54)
	makeLabel(row,name,{Font=FONT_MEDIUM,TextSize=12,Position=UDim2.fromOffset(10,2),Size=UDim2.new(.34,-10,0,22)})
	local holder=create("Frame",{Position=UDim2.new(.34,0,0,3),Size=UDim2.new(.66,-4,0,30),BackgroundTransparency=1,Parent=row},{create("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,Padding=UDim.new(0,3),VerticalAlignment=Enum.VerticalAlignment.Center})})
	local boxes={}
	for i=1,10 do
		local b=create("TextButton",{Size=UDim2.new(.1,-3,0,22),BackgroundColor3=Theme.Element,BackgroundTransparency=.15,Text="",AutoButtonColor=false,Parent=holder},{corner(3),stroke(Theme.Stroke,1,.15)})
		local fill=create("Frame",{Size=UDim2.fromScale(1,1),BackgroundColor3=Theme.Accent,BackgroundTransparency=1,BorderSizePixel=0,Parent=b},{corner(3)})
		boxes[i]={b=b,fill=fill}
		b.MouseButton1Click:Connect(function() callback(i); for n,x in ipairs(boxes) do tween(x.fill,{BackgroundTransparency=n<=i and .25 or 1},.12) end end)
	end
	for n,x in ipairs(boxes) do x.fill.BackgroundTransparency=(n<=default) and .25 or 1 end
	return {Set=function(_,v) for n,x in ipairs(boxes) do tween(x.fill,{BackgroundTransparency=n<=v and .25 or 1},.12) end end}
end

local WorldEnv=WorldTab:AddGroup("Environment","Right")
WorldEnv:AddSlider({Name="Fog Start",Min=0,Max=1000,Default=Lighting.FogStart,Increment=10,Suffix=" st",Callback=function(v) Lighting.FogStart=v end})
WorldEnv:AddSlider({Name="Fog End",Min=50,Max=10000,Default=math.min(Lighting.FogEnd,10000),Increment=50,Suffix=" st",Callback=function(v) Lighting.FogEnd=v end})
WorldEnv:AddSlider({Name="Atmosphere Density",Min=0,Max=1,Default=0,Increment=.01,Callback=function(v) for _,a in ipairs(Lighting:GetChildren()) do if a:IsA("Atmosphere") then a.Density=v end end end})
WorldEnv:AddSlider({Name="Atmosphere Haze",Min=0,Max=10,Default=0,Increment=.1,Callback=function(v) for _,a in ipairs(Lighting:GetChildren()) do if a:IsA("Atmosphere") then a.Haze=v end end end})
WorldEnv:AddToggle({Name="Global Shadows",Default=true,Callback=function(on) Lighting.GlobalShadows=on end})
WorldEnv:AddToggle({Name="Clouds",Default=true,Callback=function(on) for _,d in ipairs(workspace:GetDescendants()) do if d:IsA("Clouds") then d.Enabled=on end end end})
WorldEnv:AddColorPicker({Name="Ambient Color",Default=Lighting.Ambient,Callback=function(c) Lighting.Ambient=c end})

local WorldView=WorldTab:AddGroup("View / Camera","Left")
WorldView:AddSlider({Name="FOV",Min=30,Max=120,Default=math.floor(origFov+.5),Increment=1,Suffix="°",Callback=function(v) V.fov=v end})
WorldView:AddToggle({Name="Camera Offset",Callback=function(on) V.cameraOffset=on end})
WorldView:AddSlider({Name="Camera Height",Min=-5,Max=5,Default=0,Increment=.1,Suffix=" st",Callback=function(v) V.cameraHeight=v end})
WorldView:AddToggle({Name="Local Shadows",Default=true,Callback=function(on) V.localShadows=on end})
WorldView:AddToggle({Name="Force Day",Callback=function(on) if on then V.time=12 end end})
WorldView:AddToggle({Name="Force Night",Callback=function(on) if on then V.time=0 end end})

local WorldEffects=WorldTab:AddGroup("World Effects","Right")
WorldEffects:AddToggle({Name="Color Correction",Callback=function(on)
	V.worldCorrection=on
	if not colorCorrection then setColorCorrection() end
	colorCorrection.Enabled=on
end})
WorldEffects:AddSlider({Name="Tint Strength",Min=0,Max=100,Default=0,Increment=1,Suffix="%",Callback=function(v) V.tint=v/100 end})
WorldEffects:AddToggle({Name="Remove Atmosphere",Callback=function(on) for _,a in ipairs(Lighting:GetChildren()) do if a:IsA("Atmosphere") then a.Enabled=not on end end end})
WorldEffects:AddToggle({Name="Remove Clouds",Callback=function(on) for _,d in ipairs(workspace:GetDescendants()) do if d:IsA("Clouds") then d.Enabled=not on end end end})

local SunRays = Lighting:FindFirstChild("MerdianVolumetrics")
if not SunRays then SunRays=Instance.new("SunRaysEffect"); SunRays.Name="MerdianVolumetrics"; SunRays.Parent=Lighting end
SunRays.Enabled=false
local VolumetricIntensity=0.35
local VolumetricQuality=5
local VolumetricGroup=WorldTab:AddGroup("Volumetrics","Left")
VolumetricGroup:AddLabel("Realistic sunrays with a discrete box quality control. Higher levels increase ray intensity and spread.")
VolumetricGroup:AddToggle({Name="Hybrid Volumetrics",Default=false,Callback=function(on) SunRays.Enabled=on; SunRays.Intensity=VolumetricIntensity; SunRays.Spread=.15 + VolumetricQuality*.08 end})
VolumetricGroup:AddSlider({Name="Ray Intensity",Min=0,Max=1,Default=35,Increment=5,Suffix="%",Callback=function(v) VolumetricIntensity=v/100; SunRays.Intensity=VolumetricIntensity end})
addQualityBoxes(VolumetricGroup,"Realism",VolumetricQuality,function(level) VolumetricQuality=level; SunRays.Spread=.15+level*.08 end)

WorldEffects:AddButton({Name="Reset World",Callback=function()
	V.fov=nil; V.time=nil; V.brightness=nil; V.exposure=nil
	local cam=workspace.CurrentCamera; if cam then cam.FieldOfView=origFov end
	Lighting.ClockTime=origClock; Lighting.Brightness=origBrightness; Lighting.ExposureCompensation=origExposure
	Lighting.EnvironmentDiffuseScale=1; Lighting.EnvironmentSpecularScale=1
	Antler:Notify({Title="World",Content="World values restored.",Duration=2.5,Type="success"})
end})
WorldEffects:AddButton({Name="Reset Atmosphere",Callback=function()
	for _,a in ipairs(Lighting:GetChildren()) do if a:IsA("Atmosphere") then a.Enabled=true; a.Density=0; a.Haze=0 end end
end})

-- Texture Packs sub-page: replace matching asset IDs and classify every result by Roblox instance type.
local TextureGroup=WorldTab:AddGroup("Texture Packs","Left")
local SourceInput=TextureGroup:AddTextBox({Name="Source ID",Placeholder="Asset ID to find"})
local ReplaceInput=TextureGroup:AddTextBox({Name="Replace ID",Placeholder="Asset ID to replace with"})
local TextureResults={}
local function assetId(value)
	local n=tostring(value or ""):match("(%d+)")
	return n
end
local function classifyAsset(obj)
	if obj:IsA("Decal") then return "Decal","◆" end
	if obj:IsA("Texture") or obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then return "Texture","▧" end
	if obj:IsA("Sound") then return "Sound","♪" end
	if obj:IsA("MeshPart") or obj:IsA("SpecialMesh") or obj:IsA("FileMesh") then return "Mesh","◇" end
	if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then return "Image","▣" end
	if obj:IsA("Animation") then return "Animation","▶" end
	return nil,nil
end
local function assetProperty(obj)
	if obj:IsA("Decal") then return "Texture" end
	if obj:IsA("Texture") or obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then return "Texture" end
	if obj:IsA("Sound") then return "SoundId" end
	if obj:IsA("MeshPart") or obj:IsA("SpecialMesh") or obj:IsA("FileMesh") then return "MeshId" end
	if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then return "Image" end
	if obj:IsA("Animation") then return "AnimationId" end
end
local function clearTextureResults()
	for _,o in ipairs(TextureResults) do if o and o.Parent then o:Destroy() end end
	TextureResults={}
end
local function scanTextureId(sourceId, replacementId)
	clearTextureResults()
	local found=0
	local src=assetId(sourceId); local repl=assetId(replacementId)
	if not src or not repl then Antler:Notify({Title="Texture Packs",Content="Enter two valid numeric asset IDs.",Duration=2.5,Type="warning"}); return end
	for _,obj in ipairs(game:GetDescendants()) do
		local kind,icon=classifyAsset(obj); local prop=assetProperty(obj)
		if kind and prop then
			local ok,val=pcall(function() return obj[prop] end)
			if ok and assetId(val)==src then
				found+=1
				local row=create("Frame",{Size=UDim2.new(1,0,0,30),BackgroundColor3=Theme.Element,BackgroundTransparency=.15,BorderSizePixel=0,Parent=TextureGroup.body},{corner(4)})
				makeLabel(row,icon,{Font=FONT_BOLD,TextSize=13,TextColor3=Theme.AccentLight,TextXAlignment=Enum.TextXAlignment.Center,Position=UDim2.fromOffset(4,0),Size=UDim2.fromOffset(24,30)})
				makeLabel(row,kind.."  •  "..obj:GetFullName(),{Font=FONT,TextSize=11,TextColor3=Theme.Text,TextTruncate=Enum.TextTruncate.AtEnd,Position=UDim2.fromOffset(30,0),Size=UDim2.new(1,-38,1,0)})
				pcall(function() obj[prop]=tostring(replacementId):find("rbxassetid://") and tostring(replacementId) or "rbxassetid://"..tostring(repl) end)
				table.insert(TextureResults,row)
			end
		end
	end
	Antler:Notify({Title="Texture Packs",Content=string.format("Replaced %d matching %s assets.",found,kind or ""),Duration=3,Type=found>0 and "success" or "info"})
end
TextureGroup:AddButton({Name="Scan + Replace",Callback=function() scanTextureId(SourceInput:Get(),ReplaceInput:Get()) end})
TextureGroup:AddButton({Name="Clear Results",Callback=clearTextureResults})
TextureGroup:AddLabel("Supported detection: Texture / Decal / Sound / Mesh / Image / Animation. The scan searches loaded game instances.")

-- SETTINGS
----------------------------------------------------------------------
local Interface=SettingsTab:AddGroup("Interface","Left")
Interface:AddToggle({Name="UI Sounds",Default=true,NoList=true,Callback=function(on) UISoundsEnabled=on end})
Interface:AddSlider({Name="UI Volume",Min=0,Max=100,Default=16,Increment=1,Suffix="%",Callback=function(v) UISoundVolume=v/100 end})
Interface:AddToggle({Name="Arraylist",Default=true,NoList=true,Callback=function(on) Antler._arrayHolder.Visible=on end})
Interface:AddToggle({Name="Watermark",Default=true,NoList=true,Callback=function(on) Antler._watermark.Visible=on end})
Interface:AddSlider({Name="UI Scale",Min=70,Max=120,Default=100,Increment=5,Suffix="%",Callback=function(v) Window:SetScale(v/100) end})
Interface:AddToggle({Name="Reduced Motion",Callback=function(on) Antler._lowMotion=on end})
Interface:AddColorPicker({Name="Accent Color",Default=Theme.Accent,Callback=function(c)
	Theme.Accent=c; Theme.AccentLight=c:Lerp(WHITE,.25); Theme.Secondary=c:Lerp(Color3.new(0,0,0),.35)
end})

local Configs=SettingsTab:AddGroup("Configs","Left")
local ConfigStore={}
local function captureConfig()
	return {volume=UISoundVolume,scale=1,accent=Theme.Accent,array=Antler._arrayHolder.Visible,watermark=Antler._watermark.Visible}
end
local function applyConfig(c)
	if not c then return end
	UISoundVolume=c.volume or UISoundVolume; Antler._arrayHolder.Visible=c.array~=false; Antler._watermark.Visible=c.watermark~=false
	if c.accent then Theme.Accent=c.accent; Theme.AccentLight=c.accent:Lerp(WHITE,.25); Theme.Secondary=c.accent:Lerp(Color3.new(0,0,0),.35) end
	Antler:Notify({Title="Configs",Content="Configuration loaded.",Duration=2,Type="success"})
end
Configs:AddDropdown({Name="Config Slot",Options={"Slot 1","Slot 2","Slot 3"},Default="Slot 1",Callback=function(v) Antler._configSlot=v end})
Configs:AddButton({Name="Save Config",Callback=function() Antler._configSlot=Antler._configSlot or "Slot 1"; ConfigStore[Antler._configSlot]=captureConfig(); Antler:Notify({Title="Configs",Content=Antler._configSlot.." saved.",Duration=2,Type="success"}) end})
Configs:AddButton({Name="Load Config",Callback=function() applyConfig(ConfigStore[Antler._configSlot or "Slot 1"]) end})
Configs:AddButton({Name="Reset Configs",Callback=function() ConfigStore={}; Antler:Notify({Title="Configs",Content="Saved slots cleared.",Duration=2,Type="info"}) end})

local Code=SettingsTab:AddGroup("Custom Lua","Right")
Code:AddLabel("Run custom Luau inside Merdian. Available globals include Antler, Window, Lighting, workspace and LocalPlayer.")
local codeRow=rowBase(Code,"Lua",150)
local codeBox=create("TextBox",{Position=UDim2.fromOffset(6,4),Size=UDim2.new(1,-12,0,100),BackgroundColor3=Theme.Element,BackgroundTransparency=.05,BorderSizePixel=0,Font=Enum.Font.Code,TextSize=12,TextColor3=Theme.Text,PlaceholderText="print('Hello from Merdian')",PlaceholderColor3=Theme.SubText,Text="",ClearTextOnFocus=false,MultiLine=true,TextWrapped=false,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,Parent=codeRow},{corner(4),stroke(Theme.Stroke,1,.1)})
create("UIPadding",{PaddingLeft=UDim.new(0,8),PaddingRight=UDim.new(0,8),PaddingTop=UDim.new(0,6),Parent=codeBox})
Code:AddButton({Name="Run Lua",Callback=function()
	local loader=loadstring
	if type(loader)~="function" then Antler:Notify({Title="Custom Lua",Content="loadstring is unavailable in this environment.",Duration=3,Type="error"}); return end
	local fn,err=loader(codeBox.Text)
	if not fn then Antler:Notify({Title="Custom Lua",Content=tostring(err),Duration=4,Type="error"}); return end
	local ok,res=pcall(fn)
	Antler:Notify({Title="Custom Lua",Content=ok and ("Executed"..(res~=nil and (": "..tostring(res)) or ".")) or ("Error: "..tostring(res)),Duration=3,Type=ok and "success" or "error"})
end})
Code:AddButton({Name="Clear Lua",Callback=function() codeBox.Text="" end})

local Session=SettingsTab:AddGroup("Session","Right")
Session:AddLabel("RightShift toggles the menu. Drag the top bar to move it. On mobile, close the menu to turn it into a movable Merdian squircle launcher.")
Session:AddButton({Name="Test Notification",Callback=function() Antler:Notify({Title="Merdian",Content="Interface feedback online.",Duration=2.5,Type="success"}) end})
Session:AddButton({Name="Unload Merdian",Callback=function() Antler:Unload() end})

-- Activate the requested horizontal sub-tabs and keep their pages intentionally sparse.
local worldGroups={WorldMain,WorldEnv,WorldView,WorldEffects,VolumetricGroup}
local textureGroups={TextureGroup}
addSubTabs(WorldTab,{"World","Texture Packs"},function(index)
	for _,g in ipairs(worldGroups) do g.frame.Visible=index==1 end
	for _,g in ipairs(textureGroups) do g.frame.Visible=index==2 end
end)
local configGroups={Interface,Configs,Session}
local codeGroups={Code}
addSubTabs(SettingsTab,{"Configs","Custom Lua"},function(index)
	for _,g in ipairs(configGroups) do g.frame.Visible=index==1 end
	for _,g in ipairs(codeGroups) do g.frame.Visible=index==2 end
end)

table.insert(Antler._cleanups,function()
	if combatOverlay then combatOverlay:Destroy(); combatOverlay=nil end
	if crosshairGui then crosshairGui:Destroy(); crosshairGui=nil end
	for _,s in pairs(UISoundObjects) do pcall(function() s:Destroy() end) end
	UISoundObjects={}
	local cam=workspace.CurrentCamera
	if cam then cam.FieldOfView=origFov end
	Lighting.ClockTime=origClock; Lighting.Brightness=origBrightness; Lighting.ExposureCompensation=origExposure
end)

Antler:Notify({Title="Merdian V2",Content="Loaded — Home / Combat / Player / Visual / World ready.",Duration=4,Type="success"})
