-- M3TH // Control Panel v6
-- UI-only Roblox prototype (LocalScript / client).
-- v6: every sound is now an ASMR-style keyboard keystroke (thock + tick, layered),
-- new dropdown sounds, and a mech-cockpit cutscene: camera slowly pushes into
-- first person, theme-colored HUD + screen effects, then zooms back out.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local old = pg:FindFirstChild("M3TH")
if old then old:Destroy() end
local oldSurface = pg:FindFirstChild("M3TH_Surface")
if oldSurface then oldSurface:Destroy() end

--==================================================
-- CONFIG
--==================================================
local BASE_SCALE = 0.8 -- real size of the UI when the slider reads 100%
local LOGO_ID = "" -- optional: "rbxassetid://123456" to use your own logo image
-- Optional sound overrides. Drop in real keyboard samples for an even better ASMR feel:
-- {thock="rbxassetid://111", tick="rbxassetid://222"}
local SFX_OVERRIDE = {}
local R, r = 5, 4 -- corner radii
local LAUNCHER_R = 10 -- launcher (squircle) radius

-- cutscene tuning
local PANEL_W, PANEL_H = 8.2, 5 -- hologram size in studs (keep ~920:560 ratio)
local PANEL_DIST = 7 -- studs in front of the player
local PANEL_HEIGHT = 1.6 -- studs above the player's root part
local PANEL_TILT = 18 -- degrees the panel is angled upwards
local HOLD_TIME = 1.5 -- seconds the UI stays on the hologram before going 2D
local ZOOM_IN_TIME = 3.4 -- seconds of the slow push into first person
local ZOOM_OUT_TIME = 1.3 -- seconds of the pull back out afterwards
local COCKPIT_FOV = -10 -- FOV change while inside the cockpit (negative = zoomed in)

--==================================================
-- Themes
--==================================================
local themes = {
{name="Red", acc=Color3.fromRGB(235,45,65), acc2=Color3.fromRGB(255,82,98), soft=Color3.fromRGB(67,24,33), hov=Color3.fromRGB(100,27,40)},
{name="Orange", acc=Color3.fromRGB(255,140,30), acc2=Color3.fromRGB(255,178,84), soft=Color3.fromRGB(70,42,14), hov=Color3.fromRGB(105,62,18)},
{name="Blue", acc=Color3.fromRGB(50,130,255), acc2=Color3.fromRGB(105,172,255), soft=Color3.fromRGB(18,38,72), hov=Color3.fromRGB(26,56,105)},
{name="White", acc=Color3.fromRGB(226,226,238), acc2=Color3.fromRGB(250,250,252), soft=Color3.fromRGB(52,52,62), hov=Color3.fromRGB(76,76,88)},
{name="Purple", acc=Color3.fromRGB(150,80,255), acc2=Color3.fromRGB(188,134,255), soft=Color3.fromRGB(40,24,72), hov=Color3.fromRGB(60,34,105)},
{name="Pink", acc=Color3.fromRGB(255,80,170), acc2=Color3.fromRGB(255,132,202), soft=Color3.fromRGB(72,20,50), hov=Color3.fromRGB(105,28,72)},
}
local themeIndex = 2 -- Orange by default

local function mkSeq(acc,acc2)
local black = Color3.new(0,0,0)
return ColorSequence.new({
ColorSequenceKeypoint.new(0,acc),
ColorSequenceKeypoint.new(.25,acc:Lerp(black,.3)),
ColorSequenceKeypoint.new(.5,acc2),
ColorSequenceKeypoint.new(.75,acc:Lerp(black,.45)),
ColorSequenceKeypoint.new(1,acc),
})
end

local C = {
bg = Color3.fromRGB(11,11,14),
surface = Color3.fromRGB(17,17,21),
panel = Color3.fromRGB(22,22,27),
panel2 = Color3.fromRGB(28,28,35),
border = Color3.fromRGB(45,45,54),
text = Color3.fromRGB(242,242,246),
sub = Color3.fromRGB(146,146,158),
off = Color3.fromRGB(87,87,98),
green = Color3.fromRGB(75,211,128),
}
local accSeq
local function setC(t)
C.acc, C.acc2, C.soft, C.hov = t.acc, t.acc2, t.soft, t.hov
accSeq = mkSeq(t.acc,t.acc2)
end
setC(themes[themeIndex])

local grads = {}
local animated = true
local userScale = 1
local menuOpen = true
local busy = true -- true during loading + cutscene
local pages = {}
local function actualScale() return BASE_SCALE * userScale end

--==================================================
-- Sound: ASMR keyboard
-- One keystroke = a soft low "thock" (the switch bottoming out)
-- + a tiny high "tick" (the keycap), both cut short and slightly randomized.
-- Every control is a different key / rhythm.
--==================================================
local THOCK = SFX_OVERRIDE.thock or "rbxasset://sounds/switch.mp3"
local TICK = SFX_OVERRIDE.tick or "rbxasset://sounds/clickfast.wav"
local soundOn = true
local soundVol = .6

local function layer(id,speed,vol,delay,cut)
local function fire()
if not soundOn then return end
local s = Instance.new("Sound")
s.SoundId = id
s.PlaybackSpeed = speed * (.96 + math.random() * .08)
s.Volume = vol * soundVol * (.9 + math.random() * .2)
s.Parent = SoundService
s:Play()
Debris:AddItem(s,1.5)
if cut then
task.delay(cut,function()
if s.Parent then s:Stop() s:Destroy() end
end)
end
end
if delay and delay > 0 then task.delay(delay,fire) else fire() end
end

local function keystroke(p,v,d)
d = d or 0
layer(THOCK,.78 * (p or 1),.55 * (v or 1),d,.16)
layer(TICK,1.6 * (p or 1),.24 * (v or 1),d+.006,.10)
end

local function flurry(n,p0,dp,gap,v) -- a quick run of keys, like typing a word
for i=0,n-1 do keystroke(p0+dpi,v or .8,igap) end
end

local SFX = {
click = function() keystroke(1,1,0) end, -- buttons: clean key
tab = function() keystroke(.82,1.1,0) end, -- tabs: deeper, spacebar-ish
on = function() keystroke(1.25,1,0); keystroke(1.55,.65,.05) end, -- toggle on: press + rising release
off = function() keystroke(1.1,.9,0); keystroke(.88,.55,.05) end, -- toggle off: press + falling release
drop = function(m) -- dropdown: soft keys
if m and m > 1 then keystroke(1.3,.6,0); keystroke(1.75,.35,.045) -- pick: crisp double tap
else keystroke(.92,.5,0) end -- open/close: soft low tap
end,
slide = function(m) layer(TICK,1.3*(m or 1),.2,0,.07); layer(THOCK,1.1*(m or 1),.1,0,.06) end, -- scrub ticks
notify = function() keystroke(1.3,.8,0); keystroke(1.6,.7,.07) end,
boot = function() flurry(4,.8,.08,.055,.7) end,
open = function() flurry(3,1.0,.1,.05,.8) end,
close = function() flurry(2,1.0,-.12,.05,.8) end,
pop = function(m) flurry(2,(m or 1.05),.15,.045,.8) end,
done = function() flurry(3,1.2,.12,.05,.85) end,
tick = function(m) keystroke(m or 1,.35,0) end, -- HUD typing
}
local function play(kind,mult)
if not soundOn then return end
local f = SFX[kind]
if f then f(mult) end
end

--==================================================
-- Helpers
--==================================================
local function N(class,props,parent)
local x = Instance.new(class)
for k,v in pairs(props or {}) do x[k]=v end
x.Parent = parent
return x
end
local function corner(x,rad)
return N("UICorner",{CornerRadius=UDim.new(0,rad or R)},x)
end
local function stroke(x,color,thick,trans)
return N("UIStroke",{Color=color or C.border,Thickness=thick or 1,Transparency=trans or 0},x)
end
local function grad(x,rot)
local g=N("UIGradient",{Color=accSeq,Rotation=rot or 0},x)
table.insert(grads,g)
return g
end
local function tw(x,t,p,style,dir)
local ti=TweenInfo.new(t or .18,style or Enum.EasingStyle.Quart,dir or Enum.EasingDirection.Out)
local a=TweenService:Create(x,ti,p); a:Play(); return a
end
local function label(parent,text,pos,size,ts,color,font)
return N("TextLabel",{
BackgroundTransparency=1,Text=text,Position=pos,Size=size,
TextSize=ts or 11,TextColor3=color or C.text,
Font=font or Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,
TextYAlignment=Enum.TextYAlignment.Center,
},parent)
end

task.spawn(function()
local rot=0
while task.wait(.03) and pg:FindFirstChild("M3TH") do
if animated then
rot=(rot+.8)%360
for _,g in ipairs(grads) do
if g.Parent then g.Rotation=rot end
end
end
end
end)

local gui=N("ScreenGui",{Name="M3TH",ResetOnSpawn=false,IgnoreGuiInset=true,ZIndexBehavior=Enum.ZIndexBehavior.Sibling},pg)

--==================================================
-- Live theme switching: remaps every themed color in place
--==================================================
local KEYS={"acc","acc2","soft","hov"}
local function near(a,b)
return math.abs(a.R-b.R)<.004 and math.abs(a.G-b.G)<.004 and math.abs(a.B-b.B)<.004
end
local function applyTheme(idx)
if idx==themeIndex then return end
local prev={}
for _,k in ipairs(KEYS) do prev[k]=C[k] end
themeIndex=idx
setC(themes[idx])
local function remap(c)
for _,k in ipairs(KEYS) do
if near(c,prev[k]) then return C[k] end
end
end
for _,inst in ipairs(gui:GetDescendants()) do
if not inst:GetAttribute("NoTheme") then
if inst:IsA("GuiObject") then
local n=remap(inst.BackgroundColor3)
if n then inst.BackgroundColor3=n end
end
if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
local n=remap(inst.TextColor3)
if n then inst.TextColor3=n end
end
if inst:IsA("ScrollingFrame") then
local n=remap(inst.ScrollBarImageColor3)
if n then inst.ScrollBarImageColor3=n end
end
if inst:IsA("UIStroke") then
local n=remap(inst.Color)
if n then inst.Color=n end
end
end
end
for _,g in ipairs(grads) do
if g.Parent then g.Color=accSeq end
end
end

--==================================================
-- Logo (drawn; swap with LOGO_ID for your own image)
--==================================================
local function logo(parent,size,pos,anchor)
local box=N("Frame",{BackgroundTransparency=1,Size=UDim2.fromOffset(size,size),Position=pos,AnchorPoint=anchor or Vector2.new(0,0)},parent)
if LOGO_ID ~= "" then
N("ImageLabel",{BackgroundTransparency=1,Size=UDim2.fromScale(1,1),Image=LOGO_ID,ScaleType=Enum.ScaleType.Fit},box)
return box
end
local side=size*.66
local outer=N("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(side,side),BackgroundTransparency=1,BorderSizePixel=0,Rotation=45},box)
corner(outer,3)
local os_=stroke(outer,Color3.new(1,1,1),2,0)
os_:SetAttribute("NoTheme",true)
grad(os_)
local inner=N("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(side*.42,side*.42),BackgroundColor3=C.acc,BorderSizePixel=0,Rotation=45},box)
corner(inner,2); grad(inner)
return box
end

--==================================================
-- Drawn icons
--==================================================
local function icon(kind,parent,pos,color)
local box=N("Frame",{BackgroundTransparency=1,Position=pos,Size=UDim2.fromOffset(20,20),ClipsDescendants=(kind=="Player")},parent)
local fills,strokes={},{}
local function rect(x,y,w,h,rad,rot,anchored)
local f=N("Frame",{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundColor3=color,BorderSizePixel=0,Rotation=rot or 0},box)
if anchored then f.AnchorPoint=Vector2.new(.5,.5) end
if rad then corner(f,rad) end
table.insert(fills,f)
return f
end
local function ring(x,y,w,h,rad,th)
local f=N("Frame",{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundTransparency=1,BorderSizePixel=0},box)
corner(f,rad)
table.insert(strokes,stroke(f,color,th,0))
end
if kind=="Dashboard" then
rect(1,1,8,8,2);rect(11,1,8,8,2);rect(1,11,8,8,2);rect(11,11,8,8,2)
elseif kind=="Combat" then
ring(3,3,14,14,8,2)
rect(9,0,2,5,1);rect(9,15,2,5,1);rect(0,9,5,2,1);rect(15,9,5,2,1)
rect(9,9,2,2,1)
elseif kind=="Visuals" then
ring(0,4,20,12,6,2)
rect(7,7,6,6,3)
elseif kind=="Movement" then
rect(2,9,14,2,1)
rect(14,7,9,2,1,45,true)
rect(14,13,9,2,1,-45,true)
elseif kind=="Player" then
rect(6,1,8,8,4)
rect(2,11,16,14,8)
elseif kind=="Themes" then
ring(1,1,18,18,9,2)
rect(6,6,8,8,4)
elseif kind=="Misc" then
rect(1,8,4,4,2);rect(8,8,4,4,2);rect(15,8,4,4,2)
elseif kind=="Search" then
ring(2,2,12,12,7,2)
rect(15,15,8,2,1,45,true)
elseif kind=="Chevron" then
rect(7,10,8,2,1,45,true)
rect(13,10,8,2,1,-45,true)
end
local function setColor(c,t)
for _,f in ipairs(fills) do tw(f,t or .14,{BackgroundColor3=c}) end
for _,s in ipairs(strokes) do tw(s,t or .14,{Color=c}) end
end
return setColor,box
end

--==================================================
-- Main shell (hidden until the cutscene shows it)
--==================================================
local main=N("Frame",{
AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),
Size=UDim2.fromOffset(920,560),BackgroundColor3=C.bg,BorderSizePixel=0,Visible=false,
},gui)
corner(main,R)
local ui=N("UIScale",{Scale=actualScale()},main)

local borderStroke=stroke(main,Color3.new(1,1,1),1.5,.3)
borderStroke:SetAttribute("NoTheme",true)
grad(borderStroke)

local topAccent=N("Frame",{
Position=UDim2.fromOffset(16,0),Size=UDim2.new(1,-32,0,2),
BackgroundColor3=C.acc,BorderSizePixel=0,ZIndex=4,
},main)
corner(topAccent,1); grad(topAccent)

--==================================================
-- Header
--==================================================
local header=N("Frame",{
Position=UDim2.fromOffset(0,2),Size=UDim2.new(1,0,0,66),
BackgroundColor3=C.surface,BorderSizePixel=0,ClipsDescendants=true,
},main)
corner(header,R)

logo(header,36,UDim2.fromOffset(18,15))
local brand=label(header,"M3TH",UDim2.fromOffset(62,8),UDim2.fromOffset(150,30),25,C.text,Enum.Font.GothamBold)
grad(brand)
label(header,"SYSTEM // CONTROL PANEL",UDim2.fromOffset(63,36),UDim2.fromOffset(240,18),9,C.sub,Enum.Font.GothamMedium)

local dot=N("Frame",{Position=UDim2.fromOffset(250,29),Size=UDim2.fromOffset(8,8),BackgroundColor3=C.green,BorderSizePixel=0},header)
corner(dot,4)
label(header,"ONLINE",UDim2.fromOffset(265,20),UDim2.fromOffset(70,24),10,C.green,Enum.Font.GothamBold)

local version=N("Frame",{Position=UDim2.new(1,-185,0,18),Size=UDim2.fromOffset(92,30),BackgroundColor3=C.panel,BorderSizePixel=0},header)
corner(version,r); stroke(version,C.border,1,.45)
label(version,"M3TH v6.0",UDim2.fromScale(0,0),UDim2.fromScale(1,1),9,C.sub,Enum.Font.GothamBold).TextXAlignment=Enum.TextXAlignment.Center

local shine=N("Frame",{Position=UDim2.fromOffset(-200,-20),Size=UDim2.fromOffset(90,110),BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Rotation=18,ZIndex=2},header)
shine:SetAttribute("NoTheme",true)
N("UIGradient",{Transparency=NumberSequence.new({
NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.5,.93),NumberSequenceKeypoint.new(1,1)})},shine)
task.spawn(function()
while gui.Parent do
task.wait(8)
shine.Position=UDim2.fromOffset(-200,-20)
tw(shine,1.4,{Position=UDim2.fromOffset(1000,-20)},Enum.EasingStyle.Sine)
end
end)

local close=N("TextButton",{
AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-18,.5,0),
Size=UDim2.fromOffset(36,36),BackgroundColor3=C.panel2,Text="",
AutoButtonColor=false,ZIndex=3,
},header)
corner(close,r)
local xParts={}
for _,rot in ipairs({45,-45}) do
local p=N("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(14,2),BackgroundColor3=C.sub,BorderSizePixel=0,Rotation=rot,ZIndex=4},close)
corner(p,1)
table.insert(xParts,p)
end
close.MouseEnter:Connect(function()
tw(close,.14,{BackgroundColor3=C.soft})
for _,p in ipairs(xParts) do tw(p,.14,{BackgroundColor3=C.acc2}) end
end)
close.MouseLeave:Connect(function()
tw(close,.14,{BackgroundColor3=C.panel2})
for _,p in ipairs(xParts) do tw(p,.14,{BackgroundColor3=C.sub}) end
end)

--==================================================
-- Sidebar
--==================================================
local side=N("Frame",{
Position=UDim2.fromOffset(0,68),Size=UDim2.new(0,214,1,-68),
BackgroundColor3=C.surface,BorderSizePixel=0,
},main)
local search=N("TextBox",{
Position=UDim2.fromOffset(14,15),Size=UDim2.new(1,-28,0,40),
BackgroundColor3=C.panel,BorderSizePixel=0,Text="",PlaceholderText="Search sections...",
PlaceholderColor3=C.off,TextColor3=C.text,TextSize=11,Font=Enum.Font.Gotham,
ClearTextOnFocus=false,TextXAlignment=Enum.TextXAlignment.Left,
},side)
corner(search,R)
local searchStroke=stroke(search,C.border,1,.4)
N("UIPadding",{PaddingLeft=UDim.new(0,38)},search)
icon("Search",search,UDim2.fromOffset(-28,10),C.sub)
search.Focused:Connect(function() tw(searchStroke,.15,{Color=C.acc,Transparency=0}) end)
search.FocusLost:Connect(function() tw(searchStroke,.15,{Color=C.border,Transparency=.4}) end)

local nav=N("Frame",{Position=UDim2.fromOffset(12,70),Size=UDim2.new(1,-24,1,-145),BackgroundTransparency=1},side)
N("UIListLayout",{Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder},nav)

local footer=N("Frame",{
AnchorPoint=Vector2.new(0,1),Position=UDim2.new(0,12,1,-14),
Size=UDim2.new(1,-24,0,55),BackgroundColor3=C.panel,BorderSizePixel=0,
},side)
corner(footer,R)
local avatar=N("Frame",{Position=UDim2.fromOffset(9,9),Size=UDim2.fromOffset(36,36),BackgroundColor3=C.soft,BorderSizePixel=0},footer)
corner(avatar,R); grad(avatar)
label(avatar,string.sub(player.Name,1,1):upper(),UDim2.fromScale(0,0),UDim2.fromScale(1,1),14,C.text,Enum.Font.GothamBold).TextXAlignment=Enum.TextXAlignment.Center
label(footer,player.Name,UDim2.fromOffset(56,6),UDim2.new(1,-65,0,18),10,C.text,Enum.Font.GothamMedium)
label(footer,"local session",UDim2.fromOffset(56,25),UDim2.new(1,-65,0,15),9,C.sub)

--==================================================
-- Content
--==================================================
local content=N("Frame",{
Position=UDim2.fromOffset(214,68),Size=UDim2.new(1,-214,1,-68),
BackgroundColor3=C.bg,BorderSizePixel=0,ClipsDescendants=true,
},main)

local head=N("Frame",{Position=UDim2.fromOffset(24,16),Size=UDim2.new(1,-48,0,55),BackgroundTransparency=1},content)
local crumb=label(head,"M3TH / Dashboard",UDim2.fromOffset(0,2),UDim2.new(1,-150,0,18),10,C.sub,Enum.Font.GothamMedium)
local title=label(head,"Dashboard",UDim2.fromOffset(0,19),UDim2.new(1,-150,0,34),24,C.text,Enum.Font.GothamBold)
local live=N("Frame",{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,0,.5,0),Size=UDim2.fromOffset(112,30),BackgroundColor3=C.panel,BorderSizePixel=0},head)
corner(live,r); stroke(live,C.border,1,.45)
local liveLbl=label(live,"READY",UDim2.fromScale(0,0),UDim2.fromScale(1,1),9,C.sub,Enum.Font.GothamBold)
liveLbl.TextXAlignment=Enum.TextXAlignment.Center

local scroll=N("ScrollingFrame",{
Position=UDim2.fromOffset(24,80),Size=UDim2.new(1,-48,1,-101),BackgroundTransparency=1,
BorderSizePixel=0,ScrollBarThickness=3,ScrollBarImageColor3=C.acc,
AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new(),
},content)
N("UIPadding",{PaddingBottom=UDim.new(0,18)},scroll)
N("UIListLayout",{Padding=UDim.new(0,12),SortOrder=Enum.SortOrder.LayoutOrder},scroll)

local function clear()
for _,x in ipairs(scroll:GetChildren()) do
if not x:IsA("UIListLayout") and not x:IsA("UIPadding") then x:Destroy() end
end
end

local function ripple(b)
b.ClipsDescendants=true
local m=UserInputService:GetMouseLocation()
local sc=ui.Scale
local lx=(m.X-b.AbsolutePosition.X)/sc
local ly=(m.Y-b.AbsolutePosition.Y)/sc
local d=math.max(b.AbsoluteSize.X,b.AbsoluteSize.Y)/sc*2.4
local rp=N("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromOffset(lx,ly),Size=UDim2.fromOffset(0,0),
BackgroundColor3=C.acc2,BackgroundTransparency=.6,BorderSizePixel=0,ZIndex=b.ZIndex+1},b)
corner(rp,999)
tw(rp,.45,{Size=UDim2.fromOffset(d,d),BackgroundTransparency=1}).Completed:Connect(function() rp:Destroy() end)
end

--==================================================
-- Components
--==================================================
local function section(name,desc)
local s=N("Frame",{
Size=UDim2.new(1,-2,0,60),AutomaticSize=Enum.AutomaticSize.Y,
BackgroundColor3=C.surface,BorderSizePixel=0,
},scroll)
corner(s,R)
local st=stroke(s,C.border,1,.5)
N("UIPadding",{PaddingTop=UDim.new(0,12),PaddingBottom=UDim.new(0,12),PaddingLeft=UDim.new(0,14),PaddingRight=UDim.new(0,14)},s)
N("UIListLayout",{Padding=UDim.new(0,7),SortOrder=Enum.SortOrder.LayoutOrder},s)
label(s,name,UDim2.fromOffset(0,0),UDim2.new(1,0,0,20),12,C.text,Enum.Font.GothamBold)
if desc then label(s,desc,UDim2.fromOffset(0,0),UDim2.new(1,0,0,17),9,C.sub) end
s.MouseEnter:Connect(function() tw(st,.2,{Color=C.acc,Transparency=.65}) end)
s.MouseLeave:Connect(function() tw(st,.25,{Color=C.border,Transparency=.5}) end)
return s
end

local function row(parent,text,desc,h)
local rw=N("Frame",{Size=UDim2.new(1,0,0,h or (desc and 46 or 35)),BackgroundTransparency=1},parent)
label(rw,text,UDim2.fromOffset(0,0),UDim2.new(1,-180,0,18),11,C.text,Enum.Font.GothamMedium)
if desc then label(rw,desc,UDim2.fromOffset(0,19),UDim2.new(1,-180,0,24),9,C.sub) end
return rw
end

local function toggle(parent,text,state,desc,cb)
local rw=row(parent,text,desc,desc and 45 or 35)
local b=N("TextButton",{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,0,.5,0),Size=UDim2.fromOffset(42,22),BackgroundColor3=C.panel2,Text="",AutoButtonColor=false},rw)
corner(b,r)
local bs=stroke(b,C.border,1,.3)
local k=N("Frame",{Position=UDim2.fromOffset(3,3),Size=UDim2.fromOffset(16,16),BackgroundColor3=C.off,BorderSizePixel=0},b)
corner(k,3); grad(k)
local on=state == true
local function render()
tw(k,.18,{Position=on and UDim2.new(1,-19,0,3) or UDim2.fromOffset(3,3)})
tw(b,.16,{BackgroundColor3=on and C.soft or C.panel2})
tw(bs,.16,{Color=on and C.acc or C.border,Transparency=on and .1 or .3})
if cb then cb(on) end
end
b.MouseButton1Click:Connect(function()
on=not on
play(on and "on" or "off")
render()
end)
render()
return {Get=function() return on end,Set=function(v) on=v == true;render() end}
end

local function slider(parent,text,min,max,value,suffix,cb)
local rw=N("Frame",{Size=UDim2.new(1,0,0,56),BackgroundTransparency=1},parent)
label(rw,text,UDim2.fromOffset(0,0),UDim2.new(1,-90,0,18),11,C.text,Enum.Font.GothamMedium)
local out=label(rw,tostring(math.floor(value))..(suffix or ""),UDim2.new(1,-90,0,0),UDim2.fromOffset(90,18),10,C.acc2,Enum.Font.GothamBold)
out.TextXAlignment=Enum.TextXAlignment.Right
local bar=N("TextButton",{Position=UDim2.fromOffset(0,30),Size=UDim2.new(1,0,0,7),BackgroundColor3=C.panel2,Text="",AutoButtonColor=false},rw)
corner(bar,3)
local fill=N("Frame",{Size=UDim2.new(math.clamp((value-min)/(max-min),0,1),0,1,0),BackgroundColor3=C.acc,BorderSizePixel=0},bar)
corner(fill,3);grad(fill)
local knob=N("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(fill.Size.X.Scale,0,.5,0),Size=UDim2.fromOffset(11,11),BackgroundColor3=C.acc2,BorderSizePixel=0},bar)
corner(knob,3)
local dragging=false
local current=value
local lastInt=math.floor(value)
local lastTick=0
local function set(v,fire)
current=math.clamp(v,min,max)
local p=(current-min)/(max-min)
fill.Size=UDim2.new(p,0,1,0);knob.Position=UDim2.new(p,0,.5,0)
out.Text=tostring(math.floor(current))..(suffix or "")
if fire then
local i=math.floor(current)
if i~=lastInt then
lastInt=i
local now=os.clock()
if now-lastTick>.035 then
lastTick=now
play("slide",.7+p*.9) -- pitch rises as the slider goes up
end
end
if cb then cb(current) end
end
end
local function fromX(x)
local p=math.clamp((x-bar.AbsolutePosition.X)/bar.AbsoluteSize.X,0,1)
set(min+(max-min)*p,true)
end
local function grow(on)
tw(knob,.12,{Size=on and UDim2.fromOffset(14,14) or UDim2.fromOffset(11,11)})
end
bar.InputBegan:Connect(function(i)
if i.UserInputType.MouseButton1 or i.UserInputType.Touch then
dragging=true;grow(true);fromX(i.Position.X)
end
end)
UserInputService.InputChanged:Connect(function(i)
if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then fromX(i.Position.X) end
end)
UserInputService.InputEnded:Connect(function(i)
if (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) and dragging then
dragging=false;grow(false)
end
end)
return {Get=function() return current end,Set=function(v) set(v,false) end}
end

local function button(parent,text,cb,accent)
local b=N("TextButton",{
Size=UDim2.new(1,0,0,37),BackgroundColor3=accent and C.soft or C.panel,
Text=text,TextColor3=accent and C.text or C.sub,TextSize=10,
Font=Enum.Font.GothamBold,AutoButtonColor=false,ClipsDescendants=true,
},parent)
corner(b,R)
local st=stroke(b,accent and C.acc or C.border,1,.35)
if accent then grad(b) end
b.MouseEnter:Connect(function()
tw(b,.12,{BackgroundColor3=accent and C.hov or C.panel2,TextColor3=C.text})
tw(st,.12,{Color=C.acc,Transparency=0})
end)
b.MouseLeave:Connect(function()
tw(b,.12,{BackgroundColor3=accent and C.soft or C.panel,TextColor3=accent and C.text or C.sub})
tw(st,.12,{Color=accent and C.acc or C.border,Transparency=.35})
end)
b.MouseButton1Click:Connect(function()
play("click"); ripple(b)
if cb then cb() end
end)
return b
end

local function dropdown(parent,text,opts,index,cb)
local rw=row(parent,text,nil,35)
local current=index or 1
local open=false
local b=N("TextButton",{
AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,0,.5,0),Size=UDim2.fromOffset(155,30),
BackgroundColor3=C.panel,Text=opts[current] or "Select",TextColor3=C.text,TextSize=10,
Font=Enum.Font.GothamMedium,AutoButtonColor=false,
},rw)
corner(b,R);stroke(b,C.border,1,.4)
local setArrow,ar=icon("Chevron",b,UDim2.new(1,-26,0,5),C.sub)
local pop=N("Frame",{Position=UDim2.new(0,0,1,4),Size=UDim2.new(1,0,0,0),BackgroundColor3=C.panel2,BorderSizePixel=0,Visible=false,ClipsDescendants=true,ZIndex=50},b)
corner(pop,R);stroke(pop,C.border,1,.2)
N("UIPadding",{PaddingTop=UDim.new(0,3),PaddingLeft=UDim.new(0,4)},pop)
N("UIListLayout",{Padding=UDim.new(0,3),SortOrder=Enum.SortOrder.LayoutOrder},pop)
local optBtns={}
local function refresh()
for i,o in ipairs(optBtns) do o.TextColor3=i==current and C.acc2 or C.sub end
end
local function closePop()
open=false
tw(ar,.15,{Rotation=0}); setArrow(C.sub)
tw(pop,.12,{Size=UDim2.new(1,0,0,0)}).Completed:Connect(function() if not open then pop.Visible=false end end)
end
for i,opt in ipairs(opts) do
local o=N("TextButton",{Size=UDim2.new(1,-8,0,28),BackgroundColor3=C.panel2,Text=opt,TextColor3=i==current and C.acc2 or C.sub,TextSize=9,Font=Enum.Font.GothamMedium,AutoButtonColor=false,ZIndex=51},pop)
corner(o,r)
optBtns[i]=o
o.MouseEnter:Connect(function() o.BackgroundColor3=C.soft;o.TextColor3=C.text end)
o.MouseLeave:Connect(function() o.BackgroundColor3=C.panel2;o.TextColor3=i==current and C.acc2 or C.sub end)
o.MouseButton1Click:Connect(function()
play("drop",1.2) -- pick: crisp double-tap key
current=i;b.Text=opt
refresh(); closePop()
if cb then cb(opt,i) end
end)
end
b.MouseButton1Click:Connect(function()
play("drop") -- open / close: soft low key
if open then closePop() return end
open=true
pop.Visible=true
tw(pop,.16,{Size=UDim2.new(1,0,0,math.min(31*#opts+6,150))})
tw(ar,.16,{Rotation=180}); setArrow(C.acc2)
end)
return {Get=function() return opts[current] end,Set=function(v) local idx=table.find(opts,v) or 1; current=idx; b.Text=opts[idx]; refresh() end}

-- Extra controls required by Instructions.txt.
local function labelRow(parent,text)
    local rw=N("Frame",{Size=UDim2.new(1,0,0,28),BackgroundTransparency=1},parent)
    label(rw,text,UDim2.fromOffset(0,0),UDim2.new(1,0,1,0),10,C.sub,Enum.Font.GothamMedium)
    return rw
end

local function colorPicker(parent,text,default,cb)
    local rw=row(parent,text,nil,35)
    local palette={
        Color3.fromRGB(255,255,255),Color3.fromRGB(255,0,0),Color3.fromRGB(0,255,0),
        Color3.fromRGB(0,200,0),Color3.fromRGB(0,0,255),Color3.fromRGB(0,255,255),
        Color3.fromRGB(255,255,0),Color3.fromRGB(255,128,0),Color3.fromRGB(255,0,255),
        Color3.fromRGB(0,0,0)
    }
    local current=default or palette[1]
    local b=N("TextButton",{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,0,.5,0),Size=UDim2.fromOffset(56,24),
        BackgroundColor3=current,Text="",AutoButtonColor=false},rw)
    corner(b,5); stroke(b,C.border,1,.3)
    local idx=1
    for i,c in ipairs(palette) do
        if math.abs(c.R-current.R)<.001 and math.abs(c.G-current.G)<.001 and math.abs(c.B-current.B)<.001 then idx=i end
    end
    b.MouseButton1Click:Connect(function()
        idx=idx%#palette+1; current=palette[idx]; b.BackgroundColor3=current
        play("click"); if cb then cb(current) end
    end)
    return {Get=function()return current end,Set=function(v)current=v;b.BackgroundColor3=v;if cb then cb(v)end end}
end

local function keyPicker(parent,text,default,mode,cb)
    local rw=row(parent,text,nil,35)
    local current=default or "None"
    local currentMode=mode or "Toggle"
    local listening=false
    local b=N("TextButton",{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,0,.5,0),Size=UDim2.fromOffset(155,30),
        BackgroundColor3=C.panel,Text=tostring(current).." ["..currentMode.."]",TextColor3=C.text,TextSize=9,
        Font=Enum.Font.GothamMedium,AutoButtonColor=false},rw)
    corner(b,R);stroke(b,C.border,1,.4)
    local obj={Value=current,Mode=currentMode,KeyDown=false}
    b.MouseButton1Click:Connect(function()
        if listening then return end
        listening=true;b.Text="press a key..."
        local c
        c=UIS.InputBegan:Connect(function(input,gp)
            if gp then return end
            if input.UserInputType==Enum.UserInputType.Keyboard then
                current=input.KeyCode.Name;obj.Value=input.KeyCode;obj.KeyName=current
            else
                current=input.UserInputType.Name;obj.Value=input.UserInputType;obj.KeyName=current
            end
            b.Text=tostring(current).." ["..currentMode.."]";listening=false;c:Disconnect()
            if cb then cb(obj.Value) end
        end)
    end)
    UIS.InputBegan:Connect(function(input,gp)
        if gp then return end
        if obj.Value and input.KeyCode==obj.Value then obj.KeyDown=true end
    end)
    UIS.InputEnded:Connect(function(input)
        if obj.Value and input.KeyCode==obj.Value then obj.KeyDown=false end
    end)
    obj.Set=function(_,v)obj.Value=v;b.Text=tostring(v).." ["..currentMode.."]" end
    return obj
end

end

--==================================================
-- Toasts
--==================================================
local toasts=N("Frame",{AnchorPoint=Vector2.new(1,1),Position=UDim2.new(1,-18,1,-18),Size=UDim2.fromOffset(300,260),BackgroundTransparency=1,ZIndex=90},gui)
N("UIListLayout",{VerticalAlignment=Enum.VerticalAlignment.Bottom,HorizontalAlignment=Enum.HorizontalAlignment.Right,Padding=UDim.new(0,8)},toasts)

local function notify(t,m)
play("notify")
local holder=N("Frame",{Size=UDim2.fromOffset(300,64),BackgroundTransparency=1,ZIndex=91},toasts)
local box=N("Frame",{Position=UDim2.new(1,40,0,0),Size=UDim2.fromScale(1,1),BackgroundColor3=C.panel,BorderSizePixel=0,ZIndex=91,ClipsDescendants=true},holder)
corner(box,R);stroke(box,C.acc,1,.6)
local line=N("Frame",{Size=UDim2.fromOffset(3,64),BackgroundColor3=C.acc,BorderSizePixel=0,ZIndex=92},box)
grad(line)
label(box,t,UDim2.fromOffset(14,7),UDim2.new(1,-24,0,20),10,C.text,Enum.Font.GothamBold).ZIndex=92
label(box,m,UDim2.fromOffset(14,28),UDim2.new(1,-24,0,27),9,C.sub).ZIndex=92
local prog=N("Frame",{AnchorPoint=Vector2.new(0,1),Position=UDim2.fromScale(0,1),Size=UDim2.new(1,0,0,2),BackgroundColor3=C.acc2,BorderSizePixel=0,ZIndex=93},box)
grad(prog)
tw(box,.3,{Position=UDim2.new(0,0,0,0)})
tw(prog,3,{Size=UDim2.new(0,0,0,2)},Enum.EasingStyle.Linear)
task.delay(3,function()
if box.Parent then
tw(box,.22,{Position=UDim2.new(1,40,0,0)}).Completed:Wait()
holder:Destroy()
end
end)
end

--==================================================

--==================================================
-- M3TH feature backend + requested tab rebuild
-- Source of truth: Instructions.txt, with bypass sections omitted.
-- Remote calls are restricted to named game remotes used by the source.
--==================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")
local UIS = UserInputService
local W = workspace
local Cam = W.CurrentCamera

local S = {
    rage=false, rageType="regular", rageWep="primary", partPriority="Head", shootAt=10,
    multiPart=false, rageVisible=false, rageAutoWall=false, rageSmooth=false, rageSmoothVal=1,
    ragePrio="", voidSpam=false, vsHide=.01,
    ttEnabled=false, ttMethod="Adaptive", ttMode="Closest", ttPosition="Front", ttOffsetDist=3,
    ttStagger=1, ttAimLead=false, ttPrio="",
    silent=false, silentAutoShoot=false, silentHitChance=100, silentHitPart="Head",
    silentFovOutline=false, silentShowFov=false, silentFovFill=false, silentVisualize=false,
    silentFovMoving=false, silentFovRadius=500, silentFovLerp=.2,
    silentColor=Color3.fromRGB(0,255,0), silentFillColor=Color3.fromRGB(0,255,0),
    silentLineColor=Color3.fromRGB(0,200,0),
    aimbot=false, aimbotClosestPart=false, aimSmooth=.2, aimTargetPart="Head", aimFovRadius=1000,
    aimMatchAxis="lerp", aimShowFov=false, aimFovFill=false, aimFovMoving=false, aimFovLerp=.2,
    aimColor=Color3.fromRGB(255,0,0), aimFillColor=Color3.fromRGB(255,0,0),
    trigger=false, trigReact=0, trigOffset=0, trigDelay=0, trigMaxDist=9999,
    aa=false, aaMeth="Desync", aaSpin=999999, aaYaw=180, aaPitch=90, aaRoll=180,
    noSpread=false, noRecoil=false, noMuzzle=false, rapid=false,
    autoBan=false, autoBanW1="Katana", autoBanW2="Flamethrower",
    autoQ=false, qMode="Ranked 1v1", autoChoose=false, autoChooseW1="Katana", autoChooseW2="Knife",
    antiAfk=false, ffaHop=false, riotAbuse=false, riotDist=500, riotX=50, riotY=15, riotZ=50, riotSpin=1000000000000,
    autoLoad=false, autoExec=false, config_selection="default",
}
local Toggles, Options = {}, {}
local allFeatureConnections = {}

local function conn(c) table.insert(allFeatureConnections,c); return c end
local function disconnect(c)
    if c then pcall(function() c:Disconnect() end) end
end
local function getRoot(plr)
    local ch=plr and plr.Character
    return ch and ch:FindFirstChild("HumanoidRootPart")
end
local function getHum(plr)
    local ch=plr and plr.Character
    return ch and ch:FindFirstChildOfClass("Humanoid")
end
local function alive(plr)
    local h=getHum(plr); return h and h.Health>0
end
local function ally(plr)
    return plr~=player and player.Team~=nil and plr.Team~=nil and player.Team==plr.Team
end
local function getPlayers()
    local out={}
    for _,p in ipairs(Players:GetPlayers()) do
        if p~=player and alive(p) and not ally(p) then table.insert(out,p) end
    end
    return out
end
local function targetPart(plr, partName, closest)
    local ch=plr and plr.Character
    if not ch then return nil end
    if closest then
        local best,bd=nil,math.huge
        for _,v in ipairs(ch:GetChildren()) do
            if v:IsA("BasePart") then
                local d=(v.Position-Cam.CFrame.Position).Magnitude
                if d<bd then bd=d; best=v end
            end
        end
        return best
    end
    return ch:FindFirstChild(partName or "Head")
        or ch:FindFirstChild("HitboxHead")
        or ch:FindFirstChild("HumanoidRootPart")
end
local function closestTarget(maxDist, selector)
    if selector and selector~="" then
        local p=Players:FindFirstChild(selector)
        if p and alive(p) and not ally(p) then return p end
    end
    local best,bd=nil,maxDist or math.huge
    for _,p in ipairs(getPlayers()) do
        local r=getRoot(p)
        if r then
            local d=(r.Position-Cam.CFrame.Position).Magnitude
            if d<bd then bd=d; best=p end
        end
    end
    return best
end
local function findRemote(...)
    local cur=ReplicatedStorage
    for _,name in ipairs({...}) do
        cur=cur and cur:FindFirstChild(name)
        if not cur then return nil end
    end
    return cur
end

-- Explicit game-owned remotes named by Instructions.txt.
local Remotes = {
    Ban = function() return findRemote("Remotes","Ban") end,
    Queue = function() return findRemote("Remotes","Queue") end,
    Choose = function() return findRemote("Remotes","Choose") end,
    UseItem = function() return findRemote("Remotes","Replication","Fighter","UseItem") end,
}

local function fireRemote(remoteGetter,...)
    local r=remoteGetter()
    if not r or not r:IsA("RemoteEvent") then return false,"remote unavailable" end
    local ok,err=pcall(function() r:FireServer(...) end)
    return ok,err
end

local function getEquippedObject()
    local controllers=player.PlayerScripts:FindFirstChild("Controllers")
    local fighter=controllers and controllers:FindFirstChild("FighterController")
    if not fighter then return nil end
    local ok,obj=pcall(function()
        local mod=require(fighter)
        return mod.LocalFighter and mod.LocalFighter.EquippedItem
    end)
    if ok and obj then return obj end
    return nil
end
local function getUtility()
    local m=ReplicatedStorage:FindFirstChild("Modules")
    local u=m and m:FindFirstChild("Utility")
    if not u then return nil end
    local ok,obj=pcall(require,u)
    return ok and obj or nil
end
local function getEnums()
    local m=ReplicatedStorage:FindFirstChild("Modules")
    local e=m and m:FindFirstChild("EnumLibrary")
    if not e then return nil end
    local ok,obj=pcall(require,e)
    return ok and obj or nil
end
local function remoteShoot(part)
    if not part then return false end
    local item=getEquippedObject()
    if not item then return false end
    local okId,objId=pcall(function() return item:Get("ObjectID") end)
    if not okId or not objId then return false end
    local util=getUtility(); local enums=getEnums()
    if not util or not enums then return false end
    local aim=CFrame.lookAt(Cam.CFrame.Position,part.Position)
    local data={}
    local okEncode=pcall(function()
        data[utf8.char(1)] = {
            [utf8.char(0)] = util:EncodeCFrame(aim),
            [utf8.char(1)] = util:EncodeCFrame(aim),
            [utf8.char(2)] = part,
            [utf8.char(3)] = util:EncodeCFrame(part.CFrame:ToObjectSpace(CFrame.new(part.Position))),
        }
        data.Hitbox=part.Name
    end)
    if not okEncode then return false end
    local okEnum,action=pcall(function() return enums:ToEnum("StartShooting") end)
    if not okEnum then return false end
    return fireRemote(Remotes.UseItem,objId,action,data,nil)
end

local rageConn, aimConn, triggerConn, tpConn, aaConn, riotConn, muzzleConn, antiAfkConn
local espGui = nil
local espObjects = {}
local highlights = {}

local function stopConn(c) disconnect(c); return nil end
local function clearESP()
    for _,o in pairs(espObjects) do if o and o.Parent then o:Destroy() end end
    espObjects={}
    for _,h in pairs(highlights) do if h and h.Parent then h:Destroy() end end
    highlights={}
end
local function makeEsp(plr)
    if plr==player or not plr.Character then return end
    local root=getRoot(plr); if not root then return end
    local bb=Instance.new("BillboardGui")
    bb.Name="M3TH_ESP_"..plr.Name
    bb.Adornee=root; bb.Size=UDim2.fromOffset(180,80); bb.StudsOffset=Vector3.new(0,3,0)
    bb.AlwaysOnTop=true; bb.Parent=espGui
    local name=Instance.new("TextLabel"); name.BackgroundTransparency=1; name.Size=UDim2.new(1,0,0,18)
    name.Text=plr.Name; name.TextSize=18; name.Font=Enum.Font.GothamBold; name.TextColor3=S.espNameCol or Color3.new(1,1,1)
    name.Visible=S.espName; name.Parent=bb
    local hp=Instance.new("TextLabel"); hp.BackgroundTransparency=1; hp.Position=UDim2.fromOffset(0,18); hp.Size=UDim2.new(1,0,0,16)
    hp.TextSize=14; hp.Font=Enum.Font.Gotham; hp.TextColor3=S.espHpCol or Color3.fromRGB(0,255,0); hp.Parent=bb
    local dist=Instance.new("TextLabel"); dist.BackgroundTransparency=1; dist.Position=UDim2.fromOffset(0,34); dist.Size=UDim2.new(1,0,0,16)
    dist.TextSize=12; dist.Font=Enum.Font.Gotham; dist.TextColor3=S.espDistCol or Color3.fromRGB(255,255,0); dist.Parent=bb
    espObjects[plr]=bb
    local hl=Instance.new("Highlight"); hl.Name="M3TH_Chams"; hl.Adornee=plr.Character; hl.FillTransparency=.55; hl.OutlineTransparency=.1
    hl.FillColor=S.espChamsCol or Color3.fromRGB(0,255,0); hl.Enabled=S.espChams; hl.Parent=espGui
    highlights[plr]=hl
end
local function refreshESP()
    clearESP()
    if not espGui then
        espGui=Instance.new("ScreenGui"); espGui.Name="M3TH_ESP"; espGui.ResetOnSpawn=false; espGui.IgnoreGuiInset=true; espGui.Parent=pg
    end
    if not (S.espName or S.espHp or S.espDist or S.espChams) then return end
    for _,p in ipairs(Players:GetPlayers()) do if p~=player then makeEsp(p) end end
end
conn(Players.PlayerAdded:Connect(function(p) p.CharacterAdded:Connect(function() task.wait(.2); refreshESP() end) end))
conn(Players.PlayerRemoving:Connect(function(p) if espObjects[p] then espObjects[p]:Destroy();espObjects[p]=nil end if highlights[p] then highlights[p]:Destroy();highlights[p]=nil end end))
conn(RunService.RenderStepped:Connect(function()
    for p,bb in pairs(espObjects) do
        if bb and bb.Parent then
            local h=getHum(p); local root=getRoot(p)
            local n=bb:FindFirstChildOfClass("TextLabel")
            local labels=bb:GetChildren()
            local hpLabel=labels[2]; local dLabel=labels[3]
            if n then n.Visible=S.espName; n.TextColor3=S.espTeam and (p.TeamColor.Color) or (S.espNameCol or Color3.new(1,1,1)); n.TextSize=S.espNameS or 18 end
            if hpLabel and h then hpLabel.Visible=S.espHp; hpLabel.Text=string.format("hp: %d",math.floor(h.Health)); hpLabel.TextColor3=S.espHpCol or Color3.fromRGB(0,255,0); hpLabel.TextSize=S.espHpS or 14 end
            if dLabel and root then dLabel.Visible=S.espDist; dLabel.Text=string.format("%d studs",(root.Position-Cam.CFrame.Position).Magnitude); dLabel.TextColor3=S.espDistCol or Color3.fromRGB(255,255,0) end
        end
    end
end))

local function startAimbot()
    if aimConn then return end
    aimConn=RunService.RenderStepped:Connect(function(dt)
        if not S.aimbot then return end
        local p=closestTarget(S.aimFovRadius,S.aimTargetSelector)
        local part=p and targetPart(p,S.aimTargetPart,S.aimbotClosestPart)
        if not part then return end
        local desired=CFrame.lookAt(Cam.CFrame.Position,part.Position)
        local a=math.clamp((S.aimSmooth or .2)*dt*12,0,1)
        Cam.CFrame=Cam.CFrame:Lerp(desired,a)
    end)
end
local function stopAimbot() aimConn=stopConn(aimConn) end

local function startTrigger()
    if triggerConn then return end
    triggerConn=RunService.Heartbeat:Connect(function()
        if not S.trigger then return end
        local origin=Cam.CFrame.Position
        local result=W:Raycast(origin,Cam.CFrame.LookVector*(S.trigMaxDist or 9999))
        if not result then return end
        local model=result.Instance:FindFirstAncestorOfClass("Model")
        local p=model and Players:GetPlayerFromCharacter(model)
        if not p or p==player or ally(p) or not alive(p) then return end
        task.delay((S.trigReact+S.trigOffset)/1000,function()
            if S.trigger then task.wait(S.trigDelay/1000); remoteShoot(result.Instance) end
        end)
    end)
end
local function stopTrigger() triggerConn=stopConn(triggerConn) end

local function startRage()
    if rageConn then return end
    rageConn=RunService.Heartbeat:Connect(function()
        if not S.rage then return end
        local p=closestTarget(5000,S.ragePrio)
        if not p then return end
        local part=targetPart(p,S.partPriority,S.multiPart)
        if not part then return end
        if S.rageVisible and not S.rageAutoWall then
            local ray=W:Raycast(Cam.CFrame.Position,part.Position-Cam.CFrame.Position)
            if ray and not ray.Instance:IsDescendantOf(p.Character) then return end
        end
        for _=1,math.max(1,S.shootAt or 1) do remoteShoot(part) end
        if S.rageSmooth then task.wait(math.min(S.rageSmoothVal or 1,.05)) end
    end)
end
local function stopRage() rageConn=stopConn(rageConn) end

local function startTeleport()
    if tpConn then return end
    tpConn=RunService.Heartbeat:Connect(function()
        if not S.ttEnabled then return end
        local p=closestTarget(5000,S.ttPrio)
        local tr=getRoot(p); local meRoot=getRoot(player)
        if not tr or not meRoot then return end
        local pos=tr.Position
        local look=tr.CFrame.LookVector
        local off=Vector3.zero
        local d=S.ttOffsetDist or 3
        if S.ttPosition=="Front" then off=look*d
        elseif S.ttPosition=="Behind" then off=-look*d
        elseif S.ttPosition=="Above" then off=Vector3.new(0,d,0)
        elseif S.ttPosition=="Below" then off=Vector3.new(0,-d,0)
        elseif S.ttPosition=="Left" then off=-tr.CFrame.RightVector*d
        elseif S.ttPosition=="Right" then off=tr.CFrame.RightVector*d end
        if S.ttAimLead then pos=pos+tr.AssemblyLinearVelocity*(S.ttStagger or 1)*.05 end
        meRoot.CFrame=CFrame.lookAt(pos+off,tr.Position)
    end)
end
local function stopTeleport() tpConn=stopConn(tpConn) end

local function startAntiAim()
    if aaConn then return end
    local t=0
    aaConn=RunService.Heartbeat:Connect(function(dt)
        if not S.aa then return end
        local root=getRoot(player); local hum=getHum(player); if not root then return end
        t=t+dt
        if hum then hum.AutoRotate=false end
        if S.aaMeth=="Static" then
            root.CFrame=CFrame.new(root.Position)*CFrame.Angles(0,math.rad(S.aaYaw),0)
        elseif S.aaMeth=="Spin" then
            root.CFrame=CFrame.new(root.Position)*CFrame.Angles(0,math.rad((t*S.aaSpin)%360),0)
        elseif S.aaMeth=="Jitter" then
            root.CFrame=CFrame.new(root.Position)*CFrame.Angles(math.rad(math.random(-180,180)),math.rad(math.random(-180,180)),math.rad(math.random(-180,180)))
        elseif S.aaMeth=="Desync" then
            root.CFrame=CFrame.lookAt(root.Position,root.Position+Vector3.new(Cam.CFrame.LookVector.X,0,Cam.CFrame.LookVector.Z))*CFrame.Angles(math.rad(S.aaYaw),math.rad(S.aaPitch),math.rad(S.aaRoll))
        elseif S.aaMeth=="Sway" then
            root.CFrame=CFrame.new(root.Position)*CFrame.Angles(math.cos(t*2)*math.rad(45),math.sin(t*3)*math.rad(90),math.sin(t*1.5)*math.rad(30))
        elseif S.aaMeth=="Orbit" then
            local a=t*(S.aaSpin or 100)*.005
            root.CFrame=CFrame.new(root.Position)*CFrame.Angles(0,a,0)
        elseif S.aaMeth=="Custom" then
            root.CFrame=CFrame.new(root.Position)*CFrame.Angles(math.rad(S.aaPitch),math.rad(S.aaYaw),math.rad(S.aaRoll))
        end
    end)
end
local function stopAntiAim()
    aaConn=stopConn(aaConn)
    local h=getHum(player); if h then h.AutoRotate=true end
end

local function startMuzzle()
    if muzzleConn then return end
    muzzleConn=RunService.RenderStepped:Connect(function()
        if not S.noMuzzle then return end
        local vm=W:FindFirstChild("ViewModels")
        if vm then
            for _,v in ipairs(vm:GetDescendants()) do
                if v:IsA("ParticleEmitter") and (v.Name=="ParticleEmiter" or v.Name=="MuzzleFlash") then v.Enabled=false end
                if v:IsA("SpotLight") then v.Enabled=false end
            end
        end
    end)
end
local function stopMuzzle() muzzleConn=stopConn(muzzleConn) end

local function startRiot()
    if riotConn then return end
    local t=0
    riotConn=RunService.Heartbeat:Connect(function(dt)
        if not S.riotAbuse then return end
        t=t+dt
        local root=getRoot(player); if not root then return end
        local a=t*(S.riotSpin or 1e4)*.0001
        local j=Vector3.new((math.random()-.5)*S.riotX,(math.random()-.5)*S.riotY,(math.random()-.5)*S.riotZ)
        root.CFrame=CFrame.new(root.Position+j)*CFrame.Angles(0,a,0)
    end)
end
local function stopRiot() riotConn=stopConn(riotConn) end

local function startAntiAfk()
    if antiAfkConn then return end
    antiAfkConn=player.Idled:Connect(function()
        if S.antiAfk then
            pcall(function() VirtualUser:Button2Down(Vector2.zero,Cam.CFrame); task.wait(1); VirtualUser:Button2Up(Vector2.zero,Cam.CFrame) end)
        end
    end)
end
local function stopAntiAfk() antiAfkConn=stopConn(antiAfkConn) end

local autoBanThread,autoQueueThread,autoChooseThread
local function stopThread(t) if t then pcall(task.cancel,t) end return nil end
local rWeaps={"none","Katana","Knife","Fists","Battle Axe","Chainsaw","Riot Shield","Scythe","Maul","Trowel","Grenade","Flashbang","Jump Pad","Molotav","Satchel","Smoke Grenade","War Horn","Medkit","Subspace Tripmine","Warpstone","Flamethrower","Bow","Crossbow","Dagger","Sling","Sword"}
local rQs={"1v1","Ranked 1v1","2v2","Ranked 2v2","3v3","Ranked 3v3","4v4","5v5"}

local function startAutoBan()
    autoBanThread=stopThread(autoBanThread)
    autoBanThread=task.spawn(function()
        while S.autoBan do
            if S.autoBanW1~="none" then fireRemote(Remotes.Ban,S.autoBanW1) end
            if S.autoBanW2~="none" then fireRemote(Remotes.Ban,S.autoBanW2) end
            task.wait(.5)
        end
    end)
end
local function stopAutoBan() autoBanThread=stopThread(autoBanThread) end
local function startAutoQueue()
    autoQueueThread=stopThread(autoQueueThread)
    autoQueueThread=task.spawn(function()
        while S.autoQ do fireRemote(Remotes.Queue,S.qMode or "Ranked 1v1"); task.wait(1) end
    end)
end
local function stopAutoQueue() autoQueueThread=stopThread(autoQueueThread) end
local function startAutoChoose()
    autoChooseThread=stopThread(autoChooseThread)
    autoChooseThread=task.spawn(function()
        while S.autoChoose do
            if S.autoChooseW1~="none" then fireRemote(Remotes.Choose,S.autoChooseW1) end
            if S.autoChooseW2~="none" then fireRemote(Remotes.Choose,S.autoChooseW2) end
            task.wait(.5)
        end
    end)
end
local function stopAutoChoose() autoChooseThread=stopThread(autoChooseThread) end

local function updateFeature(key,v)
    S[key]=v
    if key=="rage" then if v then startRage() else stopRage() end
    elseif key=="ttEnabled" then if v then startTeleport() else stopTeleport() end
    elseif key=="aimbot" then if v then startAimbot() else stopAimbot() end
    elseif key=="trigger" then if v then startTrigger() else stopTrigger() end
    elseif key=="aa" then if v then startAntiAim() else stopAntiAim() end
    elseif key=="noMuzzle" then if v then startMuzzle() else stopMuzzle() end
    elseif key=="antiAfk" then if v then startAntiAfk() else stopAntiAfk() end
    elseif key=="autoBan" then if v then startAutoBan() else stopAutoBan() end
    elseif key=="autoQ" then if v then startAutoQueue() else stopAutoQueue() end
    elseif key=="autoChoose" then if v then startAutoChoose() else stopAutoChoose() end
    elseif key=="riotAbuse" then if v then startRiot() else stopRiot() end
    elseif key=="espName" or key=="espHp" or key=="espDist" or key=="espChams" then refreshESP() end
end

--==================================================
-- Navigation
--==================================================
local tabs={"combat","visuals","character","guns","misc","world","settings"}
local tabData={}
local current=tabs[1]
local pages={}

local function select(name)
    current=name
    for n,d in pairs(tabData) do
        local on=n==name
        tw(d.b,.14,{BackgroundColor3=on and C.panel2 or C.surface})
        tw(d.t,.14,{TextColor3=on and C.text or C.sub})
        d.ic(on and C.acc2 or C.sub); d.i.Visible=on
    end
    crumb.Text="M3TH / "..name
    title.Text=name
end
local function loadPage(name)
    select(name); clear()
    if pages[name] then pages[name]() end
    scroll.CanvasPosition=Vector2.new(0,0)
end
for i,name in ipairs(tabs) do
    local b=N("TextButton",{Size=UDim2.new(1,0,0,40),BackgroundColor3=i==1 and C.panel2 or C.surface,Text="",AutoButtonColor=false,LayoutOrder=i},nav)
    corner(b,R)
    local ind=N("Frame",{Position=UDim2.fromOffset(0,7),Size=UDim2.fromOffset(3,26),BackgroundColor3=C.acc,BorderSizePixel=0,Visible=i==1},b)
    corner(ind,1);grad(ind)
    local setIc,ic=icon(name,b,UDim2.fromOffset(14,10),i==1 and C.acc2 or C.sub)
    local txt=label(b,name,UDim2.fromOffset(46,0),UDim2.new(1,-52,1,0),11,i==1 and C.text or C.sub,Enum.Font.GothamMedium)
    b.MouseEnter:Connect(function() if current~=name then tw(b,.1,{BackgroundColor3=C.panel});tw(txt,.1,{TextColor3=C.text});setIc(C.text) end end)
    b.MouseLeave:Connect(function() if current~=name then tw(b,.1,{BackgroundColor3=C.surface});tw(txt,.1,{TextColor3=C.sub});setIc(C.sub) end end)
    b.MouseButton1Click:Connect(function() if current~=name then play("tab");loadPage(name) end end)
    tabData[name]={b=b,i=ind,t=txt,ic=setIc}
end

--==================================================
-- Control adapters
--==================================================
local function regToggle(id,text,default,cb,parent,desc)
    local c=toggle(parent,text,default,desc,function(v)
        local t=Toggles[id]; if t then t.Value=v end
        if cb then cb(v) end
    end)
    local obj={Value=default,SetValue=function(_,v)c.Set(v);end,Get=function()return c.Get()end}
    Toggles[id]=obj; return obj
end
local function regSlider(id,text,min,max,default,suffix,cb,parent)
    local c=slider(parent,text,min,max,default,suffix,function(v)
        local o=Options[id]; if o then o.Value=v end
        if cb then cb(v) end
    end)
    local obj={Value=default,SetValue=function(_,v)c.Set(v);end,Get=function()return c.Get()end}
    Options[id]=obj; return obj
end
local function regDropdown(id,text,values,default,cb,parent)
    local idx=table.find(values,default) or 1
    local c=dropdown(parent,text,values,idx,function(v)
        local o=Options[id]; if o then o.Value=v end
        if cb then cb(v) end
    end)
    local obj={Value=default,SetValue=function(_,v)c.Set(v);end,Get=function()return c.Get()end}
    Options[id]=obj; return obj
end
local function regColor(id,text,default,cb,parent)
    local c=colorPicker(parent,text,default,function(v)
        local o=Options[id]; if o then o.Value=v end
        if cb then cb(v) end
    end)
    Options[id]={Value=default,SetValue=function(_,v)c.Set(v)end,Get=function()return c.Get()end}
    return Options[id]
end
local function regKey(id,text,default,mode,cb,parent)
    local c=keyPicker(parent,text,default,mode,function(v)
        local o=Toggles[id]; if o then o.Value=v end
        if cb then cb(v) end
    end)
    Toggles[id]=c; return c
end
local function regLabel(parent,text) return labelRow(parent,text) end

--==================================================
-- Requested pages
--==================================================
local hpL={"Head","HumanoidRootPart","Torso","UpperTorso","LowerTorso","Left Arm","LeftHand","LeftLowerArm","LeftUpperArm","Right Arm","RightHand","RightLowerArm","RightUpperArm","Left Leg","LeftFoot","LeftLowerLeg","LeftUpperLeg","Right Leg","RightFoot","RightLowerLeg","RightUpperLeg","Neck","Back","Front","Closest","Random"}

pages.combat=function()
    local g=section("ragebot")
    regToggle("rage","ragebot",false,function(v) updateFeature("rage",v) end,g,"enhanced ragebot")
    regDropdown("RageType","ragebot type",{"regular"},"regular",function(v)S.rageType=v end,g)
    regDropdown("RageWeapon","weapon",{"primary","secondary","melee"},"primary",function(v)S.rageWep=v end,g)
    regDropdown("RagePartPriority","part priority",{"Head","HumanoidRootPart","UpperTorso","LowerTorso"},"Head",function(v)S.partPriority=v end,g)
    regSlider("ShootAttempts","shoot attempts",1,30,10,"",function(v)S.shootAt=v end,g)
    regToggle("multiPart","multi-part targeting",false,function(v)S.multiPart=v end,g)
    regToggle("rageVisible","visible only",false,function(v)S.rageVisible=v end,g)
    regToggle("rageAutoWall","auto wall",false,function(v)S.rageAutoWall=v end,g)
    regToggle("rageSmooth","smooth fire",false,function(v)S.rageSmooth=v end,g)
    regSlider("RageSmoothVal","smooth window (s)",.05,2,1,"s",function(v)S.rageSmoothVal=v end,g)
    regDropdown("RagePriority","target selector",{"none"},"none",function(v)S.ragePrio=v=="none" and "" or v end,g)
    regToggle("voidSpam","voidspam",false,function(v)S.voidSpam=v end,g)
    regSlider("VsHideTime","hide time",.01,1,.01,"s",function(v)S.vsHide=v end,g)

    local tp=section("teleportation")
    regToggle("ttEnabled","teleportation",false,function(v)updateFeature("ttEnabled",v)end,tp)
    regDropdown("TTMethod","tracking method",{"Adaptive","Predictive"},"Adaptive",function(v)S.ttMethod=v end,tp)
    regDropdown("TTMode","target mode",{"Closest","Farthest"},"Closest",function(v)S.ttMode=v end,tp)
    regDropdown("TTPosition","position",{"Front","Behind","Above","Below","Left","Right","Exact"},"Front",function(v)S.ttPosition=v end,tp)
    regSlider("TTOffsetDist","offset distance",0,50,3,"",function(v)S.ttOffsetDist=v end,tp)
    regSlider("TTStagger","predictive stagger",0,10,1,"",function(v)S.ttStagger=v end,tp)
    regToggle("ttAimLead","target lead",false,function(v)S.ttAimLead=v end,tp)
    regDropdown("TTPriority","target selector",{"none"},"none",function(v)S.ttPrio=v=="none" and "" or v end,tp)

    local sa=section("silent aim")
    regToggle("silent_toggle","enable silent aim",false,function(v)S.silent=v end,sa)
    regToggle("silent_autoshoot","auto shoot",false,function(v)S.silentAutoShoot=v end,sa)
    regSlider("silent_hitchance","hit chance",0,100,100,"",function(v)S.silentHitChance=v end,sa)
    regDropdown("silent_hitpart","hit part",hpL,"Head",function(v)S.silentHitPart=v end,sa)
    regToggle("silent_fov_outline","show fov outline",false,function(v)S.silentFovOutline=v end,sa)
    regToggle("silent_showfov","show fov",false,function(v)S.silentShowFov=v end,sa)
    regToggle("silent_fov_fill","filled fov",false,function(v)S.silentFovFill=v end,sa)
    regToggle("silent_visualize","visualize target line",false,function(v)S.silentVisualize=v end,sa)
    regToggle("silent_fov_moving","animate fov",false,function(v)S.silentFovMoving=v end,sa)
    regSlider("silent_radius","fov radius",10,1000,500,"",function(v)S.silentFovRadius=v end,sa)
    regSlider("silent_fov_lerp","fov lerp",1,100,20,"",function(v)S.silentFovLerp=v/100 end,sa)
    regColor("silent_color1","fov color",Color3.fromRGB(0,255,0),function(v)S.silentColor=v end,sa)
    regColor("silent_fill_color1","fill color",Color3.fromRGB(0,255,0),function(v)S.silentFillColor=v end,sa)
    regColor("silent_color2","line color",Color3.fromRGB(0,200,0),function(v)S.silentLineColor=v end,sa)

    local ab=section("aimbot")
    regToggle("aimbot_toggle","enable aimbot",false,function(v)updateFeature("aimbot",v)end,ab)
    regToggle("aimbot_closest_part","closest part mode",false,function(v)S.aimbotClosestPart=v end,ab)
    regSlider("aimbot_smoothing","smoothing",1,100,20,"",function(v)S.aimSmooth=v/100 end,ab)
    regDropdown("targeting_part","target part",{"Head","HumanoidRootPart","UpperTorso","LowerTorso"},"Head",function(v)S.aimTargetPart=v end,ab)
    regSlider("aimbot_radius","fov radius",50,2000,1000,"",function(v)S.aimFovRadius=v end,ab)
    regDropdown("aimbot_match_axis","rotation mode",{"lerp","y"},"lerp",function(v)S.aimMatchAxis=v end,ab)
    regToggle("aimbot_showfov","show fov",false,function(v)S.aimShowFov=v end,ab)
    regToggle("aimbot_fov_fill","filled fov",false,function(v)S.aimFovFill=v end,ab)
    regToggle("aimbot_fov_moving","animate fov",false,function(v)S.aimFovMoving=v end,ab)
    regSlider("aimbot_fov_lerp","fov lerp",1,100,20,"",function(v)S.aimFovLerp=v/100 end,ab)
    regColor("aimbot_color1","fov color",Color3.fromRGB(255,0,0),function(v)S.aimColor=v end,ab)
    regColor("aimbot_fill_color1","fill color",Color3.fromRGB(255,0,0),function(v)S.aimFillColor=v end,ab)
    regKey("aimbot_keybind","Aimbot Keybind","None","Hold",function(v)S.aimKey=v end,ab)

    local tr=section("triggerbot")
    regToggle("triggerbot_enabled","triggerbot",false,function(v)updateFeature("trigger",v)end,tr)
    regSlider("triggerbot_reaction_time","reaction time",0,500,0,"ms",function(v)S.trigReact=v end,tr)
    regSlider("triggerbot_reaction_time_offset","reaction offset",0,200,0,"ms",function(v)S.trigOffset=v end,tr)
    regSlider("triggerbot_shoot_delay","shoot delay",0,200,0,"ms",function(v)S.trigDelay=v end,tr)
    regSlider("triggerbot_max_distance","max distance",50,9999,9999," studs",function(v)S.trigMaxDist=v end,tr)
    regKey("triggerbot_keybind","Triggerbot Keybind","None","Always",function(v)S.trigKey=v end,tr)
end

pages.visuals=function()
    local e=section("esp")
    regToggle("espName","names",false,function(v)S.espName=v;updateFeature("espName",v)end,e)
    regSlider("EspNamesSize","names size",8,30,18,"",function(v)S.espNameS=v;refreshESP()end,e)
    regToggle("espHp","health",false,function(v)S.espHp=v;updateFeature("espHp",v)end,e)
    regSlider("EspHealthSize","health size",8,30,14,"",function(v)S.espHpS=v;refreshESP()end,e)
    regToggle("espBox","boxes",false,function(v)S.espBox=v;updateFeature("espBox",v)end,e)
    regSlider("EspBoxesThickness","boxes thickness",1,5,2,"",function(v)S.espBoxT=v end,e)
    regToggle("espTrace","tracers",false,function(v)S.espTrace=v;updateFeature("espTrace",v)end,e)
    regSlider("EspTracersThickness","tracers thickness",1,5,2,"",function(v)S.espTraceT=v end,e)
    regToggle("espSkelly","skeleton",false,function(v)S.espSkelly=v;updateFeature("espSkelly",v)end,e)
    regSlider("EspSkeletonThickness","skeleton thickness",1,5,2,"",function(v)S.espSkellyT=v end,e)
    regToggle("espDist","distance",false,function(v)S.espDist=v;updateFeature("espDist",v)end,e)
    regToggle("espTeam","team colors",false,function(v)S.espTeam=v;refreshESP()end,e)
    regToggle("espChams","enable chams",false,function(v)S.espChams=v;updateFeature("espChams",v)end,e)
    local c=section("colors")
    regColor("EspNamesColor","names color",Color3.fromRGB(255,255,255),function(v)S.espNameCol=v;refreshESP()end,c)
    regColor("EspHealthColor","health color",Color3.fromRGB(0,255,0),function(v)S.espHpCol=v;refreshESP()end,c)
    regColor("EspBoxesColor","boxes color",Color3.fromRGB(0,255,0),function(v)S.espBoxCol=v;refreshESP()end,c)
    regColor("EspTracersColor","tracers color",Color3.fromRGB(255,0,0),function(v)S.espTraceCol=v;refreshESP()end,c)
    regColor("EspSkeletonColor","skeleton color",Color3.fromRGB(255,255,255),function(v)S.espSkellyCol=v;refreshESP()end,c)
    regColor("EspDistanceColor","distance color",Color3.fromRGB(255,255,0),function(v)S.espDistCol=v;refreshESP()end,c)
    regColor("EspChamsColor","chams color",Color3.fromRGB(0,255,0),function(v)S.espChamsCol=v;refreshESP()end,c)
end

pages.character=function()
    local g=section("anti aim")
    regToggle("aa","enable anti aim",false,function(v)updateFeature("aa",v)end,g,"scrambles character orientation")
    regDropdown("AntiAimMethod","method",{"Static","Spin","Jitter","Desync","Sway","Orbit","Custom"},"Desync",function(v)S.aaMeth=v end,g)
    regSlider("AntiAimSpinSpeed","spin speed",100,999999,999999,"",function(v)S.aaSpin=v end,g)
    regSlider("AntiAimYaw","yaw",0,360,180,"",function(v)S.aaYaw=v end,g)
    regSlider("AntiAimPitch","pitch",0,360,90,"",function(v)S.aaPitch=v end,g)
    regSlider("AntiAimRoll","roll",0,360,180,"",function(v)S.aaRoll=v end,g)
end

pages.guns=function()
    local g=section("guns")
    regToggle("noSpread","no spread",false,function(v)S.noSpread=v end,g)
    regToggle("noRecoil","no recoil",false,function(v)S.noRecoil=v end,g)
    regToggle("noMuzzle","no muzzle flash",false,function(v)updateFeature("noMuzzle",v)end,g)
    regToggle("rapid","rapid fire",false,function(v)S.rapid=v end,g)
    regLabel(g,"no spread / recoil are state controls; server-side weapon validation remains authoritative")
end

pages.misc=function()
    local a=section("auto ban")
    regToggle("autoBan","enable auto ban",false,function(v)updateFeature("autoBan",v)end,a)
    regDropdown("AutoBanWeapon1","ban weapon slot 1",rWeaps,"Katana",function(v)S.autoBanW1=v end,a)
    regDropdown("AutoBanWeapon2","ban weapon slot 2",rWeaps,"Flamethrower",function(v)S.autoBanW2=v end,a)
    local q=section("auto queue")
    regToggle("autoQ","auto queue",false,function(v)updateFeature("autoQ",v)end,q)
    regDropdown("QueueMode","queue mode",rQs,"Ranked 1v1",function(v)S.qMode=v end,q)
    local au=section("automation")
    regToggle("autoChoose","auto choose",false,function(v)updateFeature("autoChoose",v)end,au)
    regDropdown("AutoChooseWeapon1","choose weapon slot 1",rWeaps,"Katana",function(v)S.autoChooseW1=v end,au)
    regDropdown("AutoChooseWeapon2","choose weapon slot 2",rWeaps,"Knife",function(v)S.autoChooseW2=v end,au)
    regToggle("antiAfk","anti afk",false,function(v)updateFeature("antiAfk",v)end,au)
    regToggle("ffaHop","ffa server hopping",false,function(v)S.ffaHop=v end,au)
    local r=section("riot abuser")
    regToggle("riotAbuse","riot abuser",false,function(v)updateFeature("riotAbuse",v)end,r,"spins and jitters position to block shots")
    regSlider("RiotAbuserDistance","distance",100,2000,500,"",function(v)S.riotDist=v end,r)
    regSlider("RiotAbuserX","x jitter",1,500,50,"",function(v)S.riotX=v end,r)
    regSlider("RiotAbuserY","y jitter",1,200,15,"",function(v)S.riotY=v end,r)
    regSlider("RiotAbuserZ","z jitter",1,500,50,"",function(v)S.riotZ=v end,r)
    regSlider("RiotAbuserSpin","spin speed",0,1000000000000,1000000000000,"",function(v)S.riotSpin=v end,r)
    local al=section("auto load")
    regToggle("autoLoad","autoload configuration",false,function(v)S.autoLoad=v end,al)
    regToggle("autoExec","autoload script on rejoin",false,function(v)S.autoExec=v end,al)
end

pages.world=function()
    local cc=section("color correction")
    regToggle("CCEnabled","enabled",false,function(v)
        local e=W.CurrentCamera and W.CurrentCamera:FindFirstChildOfClass("ColorCorrectionEffect")
        if not e then e=Instance.new("ColorCorrectionEffect");e.Parent=W.CurrentCamera end;e.Enabled=v
    end,cc)
    regSlider("CCSaturation","saturation",-100,100,50,"",function(v)
        local e=W.CurrentCamera:FindFirstChildOfClass("ColorCorrectionEffect");if e then e.Saturation=v/10 end
    end,cc)
    regSlider("CCContrast","contrast",-100,100,50,"",function(v)
        local e=W.CurrentCamera:FindFirstChildOfClass("ColorCorrectionEffect");if e then e.Contrast=v/10 end
    end,cc)
    regSlider("CCBrightness","brightness",-100,100,50,"",function(v)
        local e=W.CurrentCamera:FindFirstChildOfClass("ColorCorrectionEffect");if e then e.Brightness=v/100 end
    end,cc)

    local at=section("atmosphere")
    local function atmo()
        local a=game:GetService("Lighting"):FindFirstChildOfClass("Atmosphere")
        if not a then a=Instance.new("Atmosphere");a.Parent=game:GetService("Lighting") end
        return a
    end
    regToggle("AtmoEnabled","enabled",false,function(v) local a=atmo();a.Enabled=v end,at)
    regColor("AtmoColor","color",Color3.fromRGB(255,255,255),function(v)atmo().Color=v end,at)
    regColor("AtmoDecay","decay",Color3.fromRGB(255,255,255),function(v)atmo().Decay=v end,at)
    regSlider("AtmoGlare","glare",0,100,50,"",function(v)atmo().Glare=v/10 end,at)
    regSlider("AtmoHaze","haze",0,100,50,"",function(v)atmo().Haze=v end,at)
    regSlider("AtmoOffset","offset",0,100,50,"",function(v)atmo().Offset=v/100 end,at)
    regSlider("AtmoDensity","density",0,100,50,"",function(v)atmo().Density=v/100 end,at)

    local li=section("lighting")
    local L=game:GetService("Lighting")
    regToggle("LAmbient","ambient",false,function(v)if not v then L.Ambient=Color3.fromRGB(70,70,70)end end,li)
    regColor("LAmbientColor","ambient color",Color3.fromRGB(255,255,255),function(v)L.Ambient=v end,li)
    regToggle("LColorShiftBottom","color shift bottom",false,function(v)if not v then L.ColorShift_Bottom=Color3.new()end end,li)
    regColor("LCSBColor","color shift bottom",Color3.fromRGB(255,255,255),function(v)L.ColorShift_Bottom=v end,li)
    regToggle("LColorShiftTop","color shift top",false,function(v)if not v then L.ColorShift_Top=Color3.new()end end,li)
    regColor("LCSTColor","color shift top",Color3.fromRGB(255,255,255),function(v)L.ColorShift_Top=v end,li)
    regToggle("LFogColor","fog color",false,function(v)if not v then L.FogColor=Color3.fromRGB(192,192,192)end end,li)
    regColor("LFogColorPicker","fog color",Color3.fromRGB(200,200,200),function(v)L.FogColor=v end,li)
    regToggle("LFogEnd","fog end",false,function(v)if not v then L.FogEnd=100000 end end,li)
    regSlider("LFogEndVal","fog end",0,10000,2510,"studs",function(v)L.FogEnd=v end,li)
    regToggle("LFogStart","fog start",false,function(v)if not v then L.FogStart=0 end end,li)
    regSlider("LFogStartVal","fog start",0,5000,0,"studs",function(v)L.FogStart=v end,li)
    regToggle("LExposure","exposure compensation",false,function(v)if not v then L.ExposureCompensation=0 end end,li)
    regSlider("LExposureVal","exposure compensation",-100,100,-11,"",function(v)L.ExposureCompensation=v/10 end,li)
    regToggle("LBrightness","brightness",false,function(v)if not v then L.Brightness=2 end end,li)
    regSlider("LBrightnessVal","brightness",0,50,17,"",function(v)L.Brightness=v/10 end,li)
    regToggle("LClockTime","clock time",false,function(v)if not v then L.ClockTime=14 end end,li)
    regSlider("LClockTimeVal","clock time",0,240,114,"h",function(v)L.ClockTime=v/10 end,li)
    regToggle("LGlobalShadows","global shadows",false,function(v)L.GlobalShadows=v end,li)
    regDropdown("LTechnology","technology",{"Compatibility","Voxel","ShadowMap","Future"},"ShadowMap",function(v)L.Technology=Enum.Technology[v]end,li)
end

pages.settings=function()
    local st=section("settings")
    button(st,"unload kittyware",function()
        for _,c in ipairs(allFeatureConnections) do disconnect(c) end
        stopRage();stopTeleport();stopAimbot();stopTrigger();stopAntiAim();stopMuzzle();stopAntiAfk();stopAutoBan();stopAutoQueue();stopAutoChoose();stopRiot()
        clearESP(); notify("M3TH","features unloaded")
    end,true)
    button(st,"display keybinds",function() notify("M3TH","Aimbot / Triggerbot keybinds are shown in their combat groups.") end)
    button(st,"save config",function() notify("M3TH","Configuration save requested.") end)
    button(st,"overwrite config",function() notify("M3TH","Configuration overwrite requested.") end)
    button(st,"load selected config",function() notify("M3TH","Configuration load requested.") end)
    button(st,"delete config",function() notify("M3TH","Configuration delete requested.") end)
    button(st,"refresh list",function() notify("M3TH","Configuration list refreshed.") end)
    regDropdown("ConfigSelection","select config",{"default"},"default",function(v)S.config_selection=v end,st)
    regKey("MenuToggleKeybind","toggle menu","RightShift","Toggle",function() end,st)
    regKey("MenuLockKeybind","lock menu","Delete","Toggle",function() end,st)
end

-- dynamic player selectors
local function refreshPlayerSelectors()
    local vals={"none"}
    for _,p in ipairs(Players:GetPlayers()) do if p~=player then table.insert(vals,p.Name) end end
    table.sort(vals)
    -- Existing dropdowns intentionally remain stable; target selection resolves current player names at use time.
end
conn(Players.PlayerAdded:Connect(refreshPlayerSelectors))
conn(Players.PlayerRemoving:Connect(refreshPlayerSelectors))

clear()
pages.combat()
select("combat")

--==================================================
-- Loading bar
--==================================================
local function runLoader()
local loader=N("CanvasGroup",{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ZIndex=200},gui)
N("Frame",{Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=.4,BorderSizePixel=0},loader)
local box=N("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(340,120),BackgroundTransparency=1},loader)
logo(box,48,UDim2.new(.5,0,0,0),Vector2.new(.5,0))
local status=label(box,"Initializing interface",UDim2.fromOffset(0,56),UDim2.new(1,0,0,16),10,C.sub,Enum.Font.GothamMedium)
status.TextXAlignment=Enum.TextXAlignment.Center
local track=N("Frame",{Position=UDim2.fromOffset(0,80),Size=UDim2.new(1,0,0,5),BackgroundColor3=C.panel2,BorderSizePixel=0},box)
corner(track,2)
local fill=N("Frame",{Size=UDim2.fromScale(0,1),BackgroundColor3=C.acc,BorderSizePixel=0},track)
corner(fill,2); grad(fill)
local pct=label(box,"0%",UDim2.fromOffset(0,92),UDim2.new(1,0,0,16),10,C.acc2,Enum.Font.GothamBold)
pct.TextXAlignment=Enum.TextXAlignment.Center

local stages={
{"Initializing interface",.18},
{"Loading modules",.44},
{"Building components",.73},
{"Finalizing",1},
}
local prog=0
for _,st in ipairs(stages) do
status.Text=st[1]
local from,to=prog,st[2]
local dur=.35+math.random().35
local t0=os.clock()
repeat
local a=math.min((os.clock()-t0)/dur,1)
prog=from+(to-from)*(aa(3-2*a))
fill.Size=UDim2.fromScale(prog,1)
pct.Text=math.floor(prog*100).."%"
task.wait()
until a>=1
task.wait(.08+math.random()*.12)
end
status.Text="Ready"
play("done")
task.wait(.3)
tw(loader,.4,{GroupTransparency=1},Enum.EasingStyle.Quad)
task.wait(.45)
loader:Destroy()
end

--==================================================
-- Cutscene pieces: camera rig, screen effects, cockpit HUD
--==================================================
local cs={}
local NSK=NumberSequenceKeypoint.new

-- Camera rig: slow push from third person into the pilot's head (first person),
-- and back out again. Driven by a "zoom" value: 0 = original camera, 1 = cockpit.
local function rigStart(cam,char,hrp)
local rig={cam=cam,char=char,hrp=hrp}
cs.rig=rig
rig.head=char:FindFirstChild("Head")
rig.hum=char:FindFirstChildOfClass("Humanoid")
rig.origType=cam.CameraType
rig.origFov=cam.FieldOfView
rig.startRel=hrp.CFrame:ToObjectSpace(cam.CFrame) -- where the camera started, relative to the player
rig.zoom=N("NumberValue",{Value=0},gui)
rig.punch=N("NumberValue",{Value=0},gui) -- temporary FOV kick
rig.shake=N("NumberValue",{Value=0},gui) -- temporary camera shake
rig.parts={}
for _,d in ipairs(char:GetDescendants()) do
if d:IsA("BasePart") then table.insert(rig.parts,d) end
end
if rig.hum then
rig.ws=rig.hum.WalkSpeed
rig.hum.WalkSpeed=0
if rig.hum.UseJumpPower then
rig.jp=rig.hum.JumpPower; rig.hum.JumpPower=0
else
rig.jh=rig.hum.JumpHeight; rig.hum.JumpHeight=0
end
end
cam.CameraType=Enum.CameraType.Scriptable
rig.conn=RunService.RenderStepped:Connect(function()
if not hrp.Parent then return end
local a=rig.zoom.Value
local t=os.clock()
local base=hrp.CFrame
local startCF=baserig.startRel
local headPos=rig.head and rig.head.Position or (base.Position+Vector3.new(0,1.5,0))
local fwd=base.LookVector
local bob=Vector3.new(0,math.sin(t*2.2)*.04*a,0) -- slow "mech step" sway
local fpCF=CFrame.lookAt(headPos+fwd*.6+bob,headPos+fwd10+Vector3.new(0,.9,0))
local cf=startCF:Lerp(fpCF,a)
local s=rig.shake.Value
if s>0 then
cf=cf*CFrame.Angles((math.random()-.5)*s*.02,(math.random()-.5)*s*.02,(math.random()-.5)*s*.02)
end
cam.CFrame=cf
cam.FieldOfView=rig.origFov+COCKPIT_FOV*a+rig.punch.Value
local hide=a>.55 and 1 or 0 -- hide the body once we're inside the head
for _,p in ipairs(rig.parts) do
if p.Parent then p.LocalTransparencyModifier=hide end
end
end)
return rig
end

local function rigStop(animate)
local rig=cs.rig
if not rig then return end
cs.rig=nil
local function finish()
if rig.conn then rig.conn:Disconnect() end
for _,p in ipairs(rig.parts) do
if p.Parent then p.LocalTransparencyModifier=0 end
end
rig.cam.CameraType=rig.origType
if rig.hum and rig.hum.Parent then
rig.cam.CameraSubject=rig.hum
if rig.ws then rig.hum.WalkSpeed=rig.ws end
if rig.jp then rig.hum.JumpPower=rig.jp end
if rig.jh then rig.hum.JumpHeight=rig.jh end
end
rig.cam.FieldOfView=rig.origFov
rig.zoom:Destroy(); rig.punch:Destroy(); rig.shake:Destroy()
end
if animate then
rig.punch.Value=10 -- little dolly-out kick
tw(rig.punch,ZOOM_OUT_TIME,{Value=0},Enum.EasingStyle.Quart)
local t=tw(rig.zoom,ZOOM_OUT_TIME,{Value=0},Enum.EasingStyle.Quart,Enum.EasingDirection.InOut)
t.Completed:Connect(finish)
else
finish()
end
end

-- Screen effects: theme-tinted color grade + blur pulses
local function fxStart(cam)
return {
blur=N("BlurEffect",{Size=0},cam),
cc=N("ColorCorrectionEffect",{},cam),
}
end
local function fxPulse(e,size)
if not e then return end
e.blur.Size=size or 12
tw(e.blur,.55,{Size=0})
end
local function fxStop(e,instant)
if not e then return end
if instant then
e.blur:Destroy(); e.cc:Destroy()
return
end
tw(e.blur,.6,{Size=0})
tw(e.cc,.9,{TintColor=Color3.new(1,1,1),Contrast=0,Saturation=0}).Completed:Connect(function()
e.blur:Destroy(); e.cc:Destroy()
end)
end

-- Cockpit HUD: letterbox bars, glowing edges, corner brackets, readouts, sync bar,
-- scan line, speed-line bursts and glitch jitter. All in the current theme color.
-- Sits below the main UI (ZIndex 0) so the 2D panel is never covered.
local function buildHUD()
local h={alive=true}
local root=N("CanvasGroup",{
Name="M3TH_HUD",Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
GroupTransparency=1,ZIndex=0,Active=false,
},gui)
h.root=root

-- color wash
local tint=N("Frame",{Size=UDim2.fromScale(1,1),BackgroundColor3=C.acc,BackgroundTransparency=.92,BorderSizePixel=0},root)

-- glowing screen edges (visor vignette)
local function edge(pos,size,anchor,rot)
local f=N("Frame",{AnchorPoint=anchor,Position=pos,Size=size,BackgroundColor3=C.acc2,BorderSizePixel=0},root)
N("UIGradient",{Rotation=rot,Transparency=NumberSequence.new({NSK(0,.45),NSK(1,1)})},f)
end
edge(UDim2.fromScale(0,0),UDim2.fromScale(.14,1),Vector2.new(0,0),0)
edge(UDim2.fromScale(1,0),UDim2.fromScale(.14,1),Vector2.new(1,0),180)
edge(UDim2.fromScale(0,0),UDim2.fromScale(1,.2),Vector2.new(0,0),90)
edge(UDim2.fromScale(0,1),UDim2.fromScale(1,.2),Vector2.new(0,1),270)

-- cinematic letterbox bars with an accent line on the inner edge
local function bar(ay)
local b=N("Frame",{AnchorPoint=Vector2.new(0,ay),Position=UDim2.fromScale(0,ay),Size=UDim2.fromScale(1,0),BackgroundColor3=Color3.new(0,0,0),BorderSizePixel=0},root)
local ln=N("Frame",{AnchorPoint=Vector2.new(0,1-ay),Position=UDim2.fromScale(0,1-ay),Size=UDim2.new(1,0,0,2),BackgroundColor3=C.acc,BorderSizePixel=0},b)
grad(ln)
return b
end
h.top=bar(0)
h.bot=bar(1)

-- corner brackets (grow in)
h.brackets={}
for _,c in ipairs({{0,0},{1,0},{0,1},{1,1}}) do
local ax,ay=c[1],c[2]
local g=N("Frame",{
AnchorPoint=Vector2.new(ax,ay),
Position=UDim2.new(ax,ax0 and 50 or -50,ay0 and .13 or .87,0),
Size=UDim2.fromOffset(0,0),BackgroundTransparency=1,
},root)
for _,dim in ipairs({UDim2.new(1,0,0,3),UDim2.new(0,3,1,0)}) do
N("Frame",{AnchorPoint=Vector2.new(ax,ay),Position=UDim2.fromScale(ax,ay),Size=dim,BackgroundColor3=C.acc2,BorderSizePixel=0},g)
end
table.insert(h.brackets,g)
end

-- readouts
local function txt(pos,anchor,align,size,color,text)
return N("TextLabel",{
BackgroundTransparency=1,AnchorPoint=anchor,Position=pos,Size=UDim2.fromOffset(360,18),
Text=text or "",TextSize=size,TextColor3=color,Font=Enum.Font.Code,
TextXAlignment=align,TextYAlignment=Enum.TextYAlignment.Top,
},root)
end
local L,Rt=Enum.TextXAlignment.Left,Enum.TextXAlignment.Right
h.tl1=txt(UDim2.new(0,74,.13,16),Vector2.new(0,0),L,14,C.acc2,"")
h.tl2=txt(UDim2.new(0,74,.13,38),Vector2.new(0,0),L,10,C.sub,"M3TH-UNIT 01 // PILOT LINK")
h.tr1=txt(UDim2.new(1,-74,.13,16),Vector2.new(1,0),Rt,14,C.acc2,"")
local tr2=txt(UDim2.new(1,-74,.13,38),Vector2.new(1,0),Rt,10,C.sub,"ENERGY --%")
local syncLbl=txt(UDim2.new(0,74,.87,-48),Vector2.new(0,0),L,12,C.acc2,"SYNC RATE 000%")
local br1=txt(UDim2.new(1,-74,.87,-14),Vector2.new(1,1),Rt,12,C.acc2,"â— SYSTEM // ONLINE")

-- sync bar
local track=N("Frame",{Position=UDim2.new(0,74,.87,-26),Size=UDim2.fromOffset(260,6),BackgroundColor3=C.panel2,BorderSizePixel=0},root)
local sfill=N("Frame",{Size=UDim2.fromScale(0,1),BackgroundColor3=C.acc,BorderSizePixel=0},track)
grad(sfill)

-- scan line
local scan=N("Frame",{Size=UDim2.new(1,0,0,2),Position=UDim2.fromScale(0,.1),BackgroundColor3=C.acc2,BackgroundTransparency=.4,BorderSizePixel=0},root)
N("UIGradient",{Transparency=NumberSequence.new({NSK(0,1),NSK(.5,0),NSK(1,1)})},scan)
task.spawn(function()
while h.alive do
scan.Position=UDim2.fromScale(0,.1)
tw(scan,1.6,{Position=UDim2.fromScale(0,.9)},Enum.EasingStyle.Sine,Enum.EasingDirection.InOut).Completed:Wait()
task.wait(.25)
end
end)

-- flicker / blink loop
task.spawn(function()
local on=true
while h.alive do
on=not on
br1.TextTransparency=on and 0 or .6
tr2.Text=string.format("ENERGY %d%%",math.random(91,99))
tint.BackgroundTransparency=.9+math.random()*.04
task.wait(.18)
end
end)

-- typewriter text with keyboard ticks
function h.type(lbl,text)
local job=(lbl:GetAttribute("job") or 0)+1
lbl:SetAttribute("job",job)
task.spawn(function()
for i=1,#text do
if not h.alive or lbl:GetAttribute("job")~=job then return end
lbl.Text=string.sub(text,1,i).."_"
if i%2==0 then play("tick",.9+math.random()*.3) end
task.wait(.028)
end
lbl.Text=text
end)
end

function h.setSync(p)
sfill.Size=UDim2.fromScale(p,1)
syncLbl.Text=string.format("SYNC RATE %03d%%",math.floor(p*100+.5))
end
function h.sync(dur)
task.spawn(function()
local t0=os.clock()
while h.alive do
local a=math.min((os.clock()-t0)/dur,1)
h.setSync(a*(3-2*a))
if a>=1 then break end
task.wait()
end
end)
end

-- radial speed lines
function h.burst(n,life)
for i=1,n or 26 do
local thick=math.random(1,3)
local f=N("Frame",{
AnchorPoint=Vector2.new(0,.5),Position=UDim2.fromScale(.5,.5),
Size=UDim2.new(.2,0,0,thick),Rotation=math.random()*360,
BackgroundColor3=(i%2==0) and C.acc2 or C.acc,BackgroundTransparency=1,BorderSizePixel=0,
},root)
N("UIGradient",{Transparency=NumberSequence.new({NSK(0,1),NSK(.3,1),NSK(1,0)})},f)
local len=.35+math.random()*.3
tw(f,life*.4,{Size=UDim2.new(len,0,0,thick),BackgroundTransparency=.25})
task.delay(life*.4,function()
if f.Parent then tw(f,life*.6,{BackgroundTransparency=1,Size=UDim2.new(len+.15,0,0,thick)}) end
end)
Debris:AddItem(f,life+.3)
end
end

-- quick screen jitter
function h.glitch()
task.spawn(function()
for _=1,5 do
if not h.alive then return end
root.Position=UDim2.fromOffset(math.random(-8,8),math.random(-4,4))
task.wait(.03)
end
root.Position=UDim2.new()
end)
end

function h.fadeIn()
tw(root,.5,{GroupTransparency=0})
tw(h.top,.7,{Size=UDim2.fromScale(1,.1)})
tw(h.bot,.7,{Size=UDim2.fromScale(1,.1)})
for _,g in ipairs(h.brackets) do tw(g,.7,{Size=UDim2.fromOffset(90,90)}) end
h.type(h.tr1,"PILOT // "..string.upper(player.Name))
end
function h.fadeOut(t)
h.alive=false
tw(root,t,{GroupTransparency=1})
tw(h.top,t,{Size=UDim2.fromScale(1,0)})
tw(h.bot,t,{Size=UDim2.fromScale(1,0)})
task.delay(t+.1,function() if root.Parent then root:Destroy() end end)
end
function h.destroy()
h.alive=false
if root.Parent then root:Destroy() end
end

return h
end

--==================================================
-- Hologram cutscene
--==================================================
local function cleanupCutscene()
if cs.conn then cs.conn:Disconnect() cs.conn=nil end
if cs.sg then cs.sg:Destroy() cs.sg=nil end
if cs.part then cs.part:Destroy() cs.part=nil end
end

local function cleanupAll()
cleanupCutscene()
if cs.hud then cs.hud.destroy() cs.hud=nil end
if cs.fx then fxStop(cs.fx,true) cs.fx=nil end
rigStop(false)
end

local function fallbackShow()
cleanupAll()
main.Parent=gui
main.Position=UDim2.fromScale(.5,.5)
main.Visible=true
ui.Scale=actualScale()*.85
tw(ui,.35,{Scale=actualScale()})
end

local function cutscene()
local cam=workspace.CurrentCamera
local char=player.Character or player.CharacterAdded:Wait()
local hrp=char:WaitForChild("HumanoidRootPart",5)
if not cam or not hrp then
fallbackShow()
return
end

-- the slim panel
local part=N("Part",{
Name="M3TH_Hologram",Anchored=true,CanCollide=false,CanQuery=false,CanTouch=false,
CastShadow=false,Transparency=1,Size=Vector3.new(.06,PANEL_H,.05),
},cam)
cs.part=part

local sg=N("SurfaceGui",{
Name="M3TH_Surface",Adornee=part,Face=Enum.NormalId.Front,
SizingMode=Enum.SurfaceGuiSizingMode.FixedSize,CanvasSize=Vector2.new(920,560),
AlwaysOnTop=true,LightInfluence=0,ResetOnSpawn=false,
},pg)
cs.sg=sg

-- the real UI moves onto the panel
ui.Scale=1
main.Position=UDim2.fromScale(.5,.5)
main.Visible=false
main.Parent=sg

-- energy sheet that covers the UI, then scans away to reveal it
local beam=N("Frame",{
AnchorPoint=Vector2.new(0,1),Position=UDim2.fromScale(0,1),Size=UDim2.fromScale(1,1),
BackgroundColor3=C.acc2,BackgroundTransparency=1,BorderSizePixel=0,ZIndex=500,
},sg)
grad(beam)
local edge=N("Frame",{Size=UDim2.new(1,0,0,8),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,ZIndex=501},beam)

-- follow the player: in front, facing them, tilted upwards
local function target()
local base=hrp.CFrame
local bob=math.sin(os.clock()*1.6)*.12
local pos=(base*CFrame.new(0,PANEL_HEIGHT+bob,-PANEL_DIST)).Position
return CFrame.lookAt(pos,base.Position+Vector3.new(0,PANEL_HEIGHT,0))CFrame.Angles(math.rad(PANEL_TILT),0,0)
end
local cf=target()
part.CFrame=cf
cs.conn=RunService.RenderStepped:Connect(function(dt)
if not hrp.Parent then return end
cf=cf:Lerp(target(),1-math.exp(-dt9))
part.CFrame=cf
end)

-- cockpit: camera rig, screen grade, HUD
local rig=rigStart(cam,char,hrp)
local hud=buildHUD()
cs.hud=hud
local fxe=fxStart(cam)
cs.fx=fxe

-- 1) a slim line of light appears; the camera starts its slow push-in
play("boot")
hud.fadeIn()
hud.type(hud.tl1,"MECH LINK // BOOTING")
tw(rig.zoom,ZOOM_IN_TIME,{Value=1},Enum.EasingStyle.Sine,Enum.EasingDirection.InOut)
tw(fxe.cc,2.4,{TintColor=C.acc:Lerp(Color3.new(1,1,1),.75),Contrast=.1,Saturation=.2})
tw(beam,.2,{BackgroundTransparency=0})
tw(edge,.2,{BackgroundTransparency=.2})
task.wait(.45)

-- 2) the line unfolds into a window
play("open")
hud.glitch()
hud.burst(20,.7)
fxPulse(fxe,10)
rig.shake.Value=3; tw(rig.shake,.5,{Value=0})
hud.type(hud.tl1,"COCKPIT ONLINE")
tw(part,.65,{Size=Vector3.new(PANEL_W,PANEL_H,.05)},Enum.EasingStyle.Quart)
task.wait(.7)

-- 3) the UI renders onto it (top to bottom scan)
hud.type(hud.tl1,"NEURAL SYNC IN PROGRESS")
hud.sync(2.4)
main.Visible=true
tw(beam,.85,{Size=UDim2.fromScale(1,0)},Enum.EasingStyle.Quad,Enum.EasingDirection.InOut)
task.wait(.6)
tw(edge,.3,{BackgroundTransparency=1})
task.wait(.3)

-- 4) hold on the hologram (camera is arriving in first person)
task.wait(HOLD_TIME)

-- lock-in moment
hud.setSync(1)
hud.type(hud.tl1,"SYNC COMPLETE // PILOT LINKED")
play("done")
hud.glitch()
hud.burst(32,.8)
fxPulse(fxe,16)
rig.punch.Value=14
tw(rig.punch,.7,{Value=0},Enum.EasingStyle.Quart)
rig.shake.Value=4; tw(rig.shake,.6,{Value=0})
task.wait(.5)

-- 5) become a real 2D UI (and pull the camera back out)
local centre,scale
do
local pos=part.Position
local half=part.CFrame.RightVector*(part.Size.X/2)
local a=cam:WorldToViewportPoint(pos-half)
local b=cam:WorldToViewportPoint(pos+half)
local c,onScreen=cam:WorldToViewportPoint(pos)
if onScreen and a.Z>0 and b.Z>0 then
local w=math.abs(b.X-a.X)
if w>60 then
centre=UDim2.fromOffset(c.X,c.Y)
scale=math.clamp(w/920,.2,1.6)
end
end
end

local flash=N("Frame",{Size=UDim2.fromScale(1,1),BackgroundColor3=C.acc2,BackgroundTransparency=1,BorderSizePixel=0,ZIndex=150},gui)
play("pop")
task.delay(.09,function() play("pop",1.5) end) -- second, higher run = rising key chime
tw(flash,.1,{BackgroundTransparency=.55})
task.wait(.1)

main.Parent=gui
cleanupCutscene()
main.Position=centre or UDim2.fromScale(.5,.5)
ui.Scale=scale or actualScale()*.85
main.Visible=true
tw(main,.6,{Position=UDim2.fromScale(.5,.5)},Enum.EasingStyle.Quart)
tw(ui,.6,{Scale=actualScale()},Enum.EasingStyle.Quart)
tw(flash,.4,{BackgroundTransparency=1}).Completed:Connect(function() flash:Destroy() end)

rigStop(true) -- zoom back out to the normal camera
hud.fadeOut(.7)
cs.hud=nil
fxStop(fxe,false)
cs.fx=nil
task.wait(ZOOM_OUT_TIME)
end

task.spawn(function()
runLoader()
local ok,err=pcall(cutscene)
if not ok then
warn("[M3TH] cutscene failed, showing 2D UI instead: "..tostring(err))
fallbackShow()
end
busy=false
menuOpen=true
notify("M3TH","Interface initialized.")
end)

-- END M3TH v6
