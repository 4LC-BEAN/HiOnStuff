-- M3TH // Control Panel v6
-- UI-only Roblox prototype (LocalScript / client).
-- v6: every sound is now an ASMR-style keyboard keystroke (thock + tick, layered),
--     new dropdown sounds, and a mech-cockpit cutscene: camera slowly pushes into
--     first person, theme-colored HUD + screen effects, then zooms back out.

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
local BASE_SCALE = 0.8   -- real size of the UI when the slider reads 100%
local LOGO_ID = ""       -- optional: "rbxassetid://123456" to use your own logo image
-- Optional sound overrides. Drop in real keyboard samples for an even better ASMR feel:
-- {thock="rbxassetid://111", tick="rbxassetid://222"}
local SFX_OVERRIDE = {}
local R, r = 5, 4        -- corner radii
local LAUNCHER_R = 10    -- launcher (squircle) radius

-- cutscene tuning
local PANEL_W, PANEL_H = 8.2, 5      -- hologram size in studs (keep ~920:560 ratio)
local PANEL_DIST = 7                 -- studs in front of the player
local PANEL_HEIGHT = 1.6             -- studs above the player's root part
local PANEL_TILT = 18                -- degrees the panel is angled upwards
local HOLD_TIME = 1.5                -- seconds the UI stays on the hologram before going 2D
local ZOOM_IN_TIME = 3.4             -- seconds of the slow push into first person
local ZOOM_OUT_TIME = 1.3            -- seconds of the pull back out afterwards
local COCKPIT_FOV = -10              -- FOV change while inside the cockpit (negative = zoomed in)

--==================================================
-- Themes
--==================================================
local themes = {
    {name="Red",    acc=Color3.fromRGB(235,45,65),   acc2=Color3.fromRGB(255,82,98),   soft=Color3.fromRGB(67,24,33),  hov=Color3.fromRGB(100,27,40)},
    {name="Orange", acc=Color3.fromRGB(255,140,30),  acc2=Color3.fromRGB(255,178,84),  soft=Color3.fromRGB(70,42,14),  hov=Color3.fromRGB(105,62,18)},
    {name="Blue",   acc=Color3.fromRGB(50,130,255),  acc2=Color3.fromRGB(105,172,255), soft=Color3.fromRGB(18,38,72),  hov=Color3.fromRGB(26,56,105)},
    {name="White",  acc=Color3.fromRGB(226,226,238), acc2=Color3.fromRGB(250,250,252), soft=Color3.fromRGB(52,52,62),  hov=Color3.fromRGB(76,76,88)},
    {name="Purple", acc=Color3.fromRGB(150,80,255),  acc2=Color3.fromRGB(188,134,255), soft=Color3.fromRGB(40,24,72),  hov=Color3.fromRGB(60,34,105)},
    {name="Pink",   acc=Color3.fromRGB(255,80,170),  acc2=Color3.fromRGB(255,132,202), soft=Color3.fromRGB(72,20,50),  hov=Color3.fromRGB(105,28,72)},
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
local busy = true           -- true during loading + cutscene
local pages = {}
local function actualScale() return BASE_SCALE * userScale end

--==================================================
-- Sound: ASMR keyboard
-- One keystroke = a soft low "thock" (the switch bottoming out)
-- + a tiny high "tick" (the keycap), both cut short and slightly randomized.
-- Every control is a different key / rhythm.
--==================================================
local THOCK = SFX_OVERRIDE.thock or "rbxasset://sounds/switch.mp3"
local TICK  = SFX_OVERRIDE.tick  or "rbxasset://sounds/clickfast.wav"
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
    layer(THOCK,.78*p,.55*v,d,.16)
    layer(TICK,1.6*p,.24*v,d+.006,.10)
end

local function flurry(n,p0,dp,gap,v)   -- a quick run of keys, like typing a word
    for i=0,n-1 do keystroke(p0+dp*i,v or .8,i*gap) end
end

local SFX = {
    click  = function()  keystroke(1,1,0) end,                                  -- buttons: clean key
    tab    = function()  keystroke(.82,1.1,0) end,                              -- tabs: deeper, spacebar-ish
    on     = function()  keystroke(1.25,1,0); keystroke(1.55,.65,.05) end,      -- toggle on: press + rising release
    off    = function()  keystroke(1.1,.9,0); keystroke(.88,.55,.05) end,       -- toggle off: press + falling release
    drop   = function(m)                                                        -- dropdown: soft keys
        if m and m > 1 then keystroke(1.3,.6,0); keystroke(1.75,.35,.045)      --   pick: crisp double tap
        else keystroke(.92,.5,0) end                                            --   open/close: soft low tap
    end,
    slide  = function(m) layer(TICK,1.3*(m or 1),.2,0,.07); layer(THOCK,1.1*(m or 1),.1,0,.06) end, -- scrub ticks
    notify = function()  keystroke(1.3,.8,0); keystroke(1.6,.7,.07) end,
    boot   = function()  flurry(4,.8,.08,.055,.7) end,
    open   = function()  flurry(3,1.0,.1,.05,.8) end,
    close  = function()  flurry(2,1.0,-.12,.05,.8) end,
    pop    = function(m) flurry(2,(m or 1.05),.15,.045,.8) end,
    done   = function()  flurry(3,1.2,.12,.05,.85) end,
    tick   = function(m) keystroke(m or 1,.35,0) end,                            -- HUD typing
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
local crumb=label(head,"M3TH  /  Dashboard",UDim2.fromOffset(0,2),UDim2.new(1,-150,0,18),10,C.sub,Enum.Font.GothamMedium)
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
    local on=state==true
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
    return {Get=function() return on end,Set=function(v) on=v==true;render() end}
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
                    play("slide",.7+p*.9)   -- pitch rises as the slider goes up
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
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            dragging=true;grow(true);fromX(i.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then fromX(i.Position.X) end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if (i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch) and dragging then
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
            play("drop",1.2)            -- pick: crisp double-tap key
            current=i;b.Text=opt
            refresh(); closePop()
            if cb then cb(opt,i) end
        end)
    end
    b.MouseButton1Click:Connect(function()
        play("drop")                    -- open / close: soft low key
        if open then closePop() return end
        open=true
        pop.Visible=true
        tw(pop,.16,{Size=UDim2.new(1,0,0,math.min(31*#opts+6,150))})
        tw(ar,.16,{Rotation=180}); setArrow(C.acc2)
    end)
    return {Get=function() return opts[current],current end}
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
-- Navigation (instant; click sound only when changing tab)
--==================================================
local tabs={"Dashboard","Combat","Visuals","Movement","Player","Themes","Misc"}
local tabData={}
local current="Dashboard"

local function select(name)
    current=name
    for n,d in pairs(tabData) do
        local on=n==name
        tw(d.b,.14,{BackgroundColor3=on and C.panel2 or C.surface})
        tw(d.t,.14,{TextColor3=on and C.text or C.sub})
        d.ic(on and C.acc2 or C.sub)
        d.i.Visible=on
    end
    crumb.Text="M3TH  /  "..name
    title.Text=name
end

local function loadPage(name)
    select(name)
    clear()
    local f=pages[name]
    if f then f() end
    scroll.CanvasPosition=Vector2.new(0,0)
end

for i,name in ipairs(tabs) do
    local b=N("TextButton",{Size=UDim2.new(1,0,0,40),BackgroundColor3=i==1 and C.panel2 or C.surface,Text="",AutoButtonColor=false,LayoutOrder=i},nav)
    corner(b,R)
    local ind=N("Frame",{Position=UDim2.fromOffset(0,7),Size=UDim2.fromOffset(3,26),BackgroundColor3=C.acc,BorderSizePixel=0,Visible=i==1},b)
    corner(ind,1);grad(ind)
    local setIc=icon(name,b,UDim2.fromOffset(14,10),i==1 and C.acc2 or C.sub)
    local txt=label(b,name,UDim2.fromOffset(46,0),UDim2.new(1,-52,1,0),11,i==1 and C.text or C.sub,Enum.Font.GothamMedium)
    b.MouseEnter:Connect(function()
        if current~=name then tw(b,.1,{BackgroundColor3=C.panel});tw(txt,.1,{TextColor3=C.text});setIc(C.text) end
    end)
    b.MouseLeave:Connect(function()
        if current~=name then tw(b,.1,{BackgroundColor3=C.surface});tw(txt,.1,{TextColor3=C.sub});setIc(C.sub) end
    end)
    b.MouseButton1Click:Connect(function()
        if current==name then return end   -- already on this tab: no sound, no reload
        play("tab")
        loadPage(name)
    end)
    tabData[name]={b=b,i=ind,t=txt,ic=setIc}
end

--==================================================
-- Pages
--==================================================
local fx

local function scaleSlider(parent,text)
    slider(parent,text,70,130,userScale*100,"%",function(v)
        userScale=v/100
        if menuOpen and not busy then ui.Scale=actualScale() end
    end)
end

local themeNames={}
for i,t in ipairs(themes) do themeNames[i]=t.name end

pages.Dashboard=function()
    local s=section("WELCOME BACK","A denser, cleaner M3TH panel with motion in the accents.")
    label(s,"Everything is where you expect it.",UDim2.fromOffset(0,0),UDim2.new(1,0,0,37),17,C.text,Enum.Font.GothamBold)
    label(s,"Drag the header, switch pages, test the controls, then minimize. RightShift toggles the menu.",UDim2.fromOffset(0,0),UDim2.new(1,0,0,32),9,C.sub)

    local state=section("SESSION","Local interface diagnostics.")
    toggle(state,"Interface enabled",true,"Controls the visual demo state.")
    toggle(state,"Animated gradients",animated,"Move the accent gradients continuously.",function(v) animated=v end)
    toggle(state,"Sound effects",soundOn,"Soft ASMR keyboard clicks on interaction.",function(v) soundOn=v end)
    toggle(state,"Particles",fx and fx.Visible or true,"Faint particles in the background.",function(v) if fx then fx.Visible=v end end)
    slider(state,"Sound volume",0,100,soundVol*100,"%",function(v) soundVol=v/100 end)
    scaleSlider(state,"UI scale")

    local quick=section("QUICK ACTIONS","Small interactions built into the panel.")
    button(quick,"SHOW TEST NOTIFICATION",function() notify("M3TH","Interface interaction confirmed.") end,true)
    button(quick,"RESET DASHBOARD",function() loadPage("Dashboard");notify("M3TH","Dashboard refreshed.") end)

    local style=section("STYLE","Quick cosmetic selectors.")
    dropdown(style,"Accent theme",themeNames,themeIndex,function(_,i) applyTheme(i) end)
    dropdown(style,"Density",{"Comfortable","Compact","Spacious"},1)
end

pages.Combat=function()
    local s=section("COMBAT PANEL","UI placeholders for your own game systems.")
    toggle(s,"Assist preview",false,"Visual switch only; no gameplay logic.")
    slider(s,"Field of view",20,240,120,"deg")
    slider(s,"Target distance",25,500,200,"m")
    dropdown(s,"Focus",{"Head","Torso","Nearest point"},1)
    dropdown(s,"Priority",{"Closest","Angle","Health"},1)

    local f=section("FEEDBACK","Control how feedback is presented.")
    toggle(f,"Target indicator",true)
    toggle(f,"Smooth transitions",true)
    toggle(f,"Hit confirmation",false)
    slider(f,"Response",0,100,65,"%")
    slider(f,"Accent intensity",0,100,80,"%")
end

pages.Visuals=function()
    local p=section("PLAYERS","Display configuration examples.")
    toggle(p,"Box overlay",true);toggle(p,"Skeleton preview",false)
    toggle(p,"Name labels",true);toggle(p,"Health bars",false)
    dropdown(p,"Element mode",{"Box + Name","Minimal","Detailed"},1)
    local w=section("WORLD","Visual-only settings.")
    toggle(w,"High visibility",false)
    slider(w,"Render distance",0,1500,850,"m")
    slider(w,"Ambient level",0,100,55,"%")
    dropdown(w,"Time preset",{"Morning","Afternoon","Evening","Night"},2)
    local a=section("ACCENTS","Tune the menu personality.")
    dropdown(a,"Gradient style",{"Sweep","Pulse","Hotline"},1)
    slider(a,"Glow amount",0,100,70,"%")
end

pages.Movement=function()
    local m=section("MOVEMENT PREVIEW","Non-functional presentation controls.")
    toggle(m,"Movement module",false,"Visual placeholder only.")
    slider(m,"Speed amount",0,100,32,"%")
    toggle(m,"Jump preview",false)
    slider(m,"Jump amount",0,100,50,"%")
    toggle(m,"Momentum display",true)
    local c=section("COORDINATES","Presentation-only coordinate widgets.")
    slider(c,"X",0,1000,56);slider(c,"Y",0,1000,12);slider(c,"Z",0,1000,764)
    button(c,"SET WAYPOINT",function() notify("M3TH","Waypoint preview saved locally.") end,true)
end

pages.Player=function()
    local p=section("PLAYER","Local display preferences.")
    toggle(p,"Show profile card",true);toggle(p,"Compact labels",false);toggle(p,"Status badge",true)
    dropdown(p,"Display mode",{"Modern","Classic","Minimal"},1)
    local i=section("INTERFACE","Control the shape and scale of the UI.")
    scaleSlider(i,"Interface scale")
    dropdown(i,"Corner radius",{"Soft","Rounded","Sharp"},2)
    toggle(i,"Reduced motion",false)
    local rs=section("RESET","Return the local panel to defaults.")
    button(rs,"RESTORE DEFAULTS",function()
        userScale=1; ui.Scale=actualScale(); animated=true; soundOn=true; soundVol=.6
        applyTheme(2)
        loadPage("Player")
        notify("M3TH","Defaults restored.")
    end,true)
end

pages.Themes=function()
    local s=section("THEME","Pick an accent color. It applies instantly everywhere.")
    local grid=N("Frame",{Size=UDim2.new(1,0,0,152),BackgroundTransparency=1},s)
    N("UIGridLayout",{CellSize=UDim2.fromOffset(196,70),CellPadding=UDim2.fromOffset(12,12),SortOrder=Enum.SortOrder.LayoutOrder},grid)
    local swatches={}
    local function refreshSwatches()
        for i,sw in ipairs(swatches) do
            local active=i==themeIndex
            sw.st.Color=active and C.acc2 or C.border
            sw.st.Thickness=active and 2 or 1
            sw.st.Transparency=active and 0 or .4
            sw.tag.Text=active and "ACTIVE" or "APPLY"
            sw.tag.TextColor3=active and C.acc2 or C.sub
        end
    end
    for i,t in ipairs(themes) do
        local b=N("TextButton",{BackgroundColor3=C.panel,Text="",AutoButtonColor=false,LayoutOrder=i},grid)
        corner(b,R)
        local st=stroke(b,C.border,1,.4)
        local chip=N("Frame",{Position=UDim2.fromOffset(12,12),Size=UDim2.fromOffset(46,46),BackgroundColor3=t.acc,BorderSizePixel=0},b)
        chip:SetAttribute("NoTheme",true)
        corner(chip,R)
        N("UIGradient",{Color=mkSeq(t.acc,t.acc2),Rotation=45},chip)
        label(b,t.name,UDim2.fromOffset(72,14),UDim2.new(1,-82,0,20),12,C.text,Enum.Font.GothamBold)
        local tag=label(b,"APPLY",UDim2.fromOffset(72,36),UDim2.new(1,-82,0,16),9,C.sub,Enum.Font.GothamBold)
        swatches[i]={st=st,tag=tag}
        b.MouseEnter:Connect(function() if i~=themeIndex then tw(st,.12,{Color=C.sub,Transparency=0}) end end)
        b.MouseLeave:Connect(function() if i~=themeIndex then tw(st,.12,{Color=C.border,Transparency=.4}) end end)
        b.MouseButton1Click:Connect(function()
            if i==themeIndex then return end
            play("click")
            applyTheme(i)
            refreshSwatches()
            notify("THEME",t.name.." theme applied.")
        end)
    end
    refreshSwatches()
end

pages.Misc=function()
    local g=section("GENERAL","Utility switches and presentation options.")
    toggle(g,"Notifications",true)
    toggle(g,"Animated gradients",animated,"Enable the moving accent system.",function(v) animated=v end)
    toggle(g,"Blur-style depth",false)
    dropdown(g,"UI theme",themeNames,themeIndex,function(_,i) applyTheme(i) end)

    local cfg=section("CONFIGS","A lightweight preset browser mockup.")
    dropdown(cfg,"Current preset",{"Default","Aggressive","Minimal","Streamer"},1)
    button(cfg,"SAVE CURRENT PRESET",function() notify("PRESET","Current visual configuration saved.") end,true)
    button(cfg,"LOAD PRESET",function() notify("PRESET","Selected visual preset loaded.") end)

    local act=section("SESSION","Buttons matching the reference style.")
    button(act,"REJOIN PREVIEW",function() notify("M3TH","Rejoin is a UI placeholder in this build.") end)
    button(act,"COPY SESSION INFO",function() notify("M3TH","Session info prepared for display.") end)
    button(act,"SEND TEST NOTIFICATION",function() notify("HELLO","This is a M3TH test notification.") end,true)
end

--==================================================
-- Search
--==================================================
search:GetPropertyChangedSignal("Text"):Connect(function()
    local q=string.lower(search.Text or "")
    for name,d in pairs(tabData) do
        d.b.Visible=q=="" or string.find(string.lower(name),q,1,true)~=nil
    end
end)

--==================================================
-- Drag utility
--==================================================
local function draggable(target,handle)
    local dragging=false
    local moved=false
    local input,dragStart,startPos
    handle.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            dragging=true;moved=false;dragStart=i.Position;startPos=target.Position
            i.Changed:Connect(function()
                if i.UserInputState==Enum.UserInputState.End then dragging=false end
            end)
        end
    end)
    handle.InputChanged:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch then input=i end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and i==input then
            local d=i.Position-dragStart
            if d.Magnitude>4 then moved=true end
            target.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
        end
    end)
    return function() return moved end
end

draggable(main,header)

--==================================================
-- Particles
--==================================================
fx=N("Frame",{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ClipsDescendants=true,ZIndex=3,Active=false},main)
local parts={}
for i=1,14 do
    local sz=math.random(2,3)
    local p=N("Frame",{Size=UDim2.fromOffset(sz,sz),BackgroundColor3=(i%3==0) and C.acc2 or C.acc,
        BackgroundTransparency=.6+math.random()*.3,BorderSizePixel=0},fx)
    corner(p,1)
    parts[i]={f=p,x=math.random()*920,y=math.random()*560,v=10+math.random()*22,ph=math.random()*6.28,a=6+math.random()*12}
end

--==================================================
-- Launcher
--==================================================
local reopen=N("TextButton",{
    Position=UDim2.fromOffset(24,120),Size=UDim2.fromOffset(48,48),
    BackgroundColor3=C.surface,Text="",AutoButtonColor=false,Visible=false,ZIndex=70,
},gui)
corner(reopen,LAUNCHER_R)
local reopenStroke=stroke(reopen,Color3.new(1,1,1),1.5,.2)
reopenStroke:SetAttribute("NoTheme",true)
grad(reopenStroke)
logo(reopen,30,UDim2.fromScale(.5,.5),Vector2.new(.5,.5))
reopen.MouseEnter:Connect(function() tw(reopen,.14,{BackgroundColor3=C.soft}) end)
reopen.MouseLeave:Connect(function() tw(reopen,.14,{BackgroundColor3=C.surface}) end)
local launcherMoved=draggable(reopen,reopen)

--==================================================
-- Open / close
--==================================================
local function setMenu(open)
    if busy or open==menuOpen then return end
    menuOpen=open
    if open then
        reopen.Visible=false
        main.Visible=true
        ui.Scale=actualScale()*.9
        play("open")
        tw(ui,.25,{Scale=actualScale()})
    else
        play("close")
        tw(ui,.15,{Scale=actualScale()*.9},Enum.EasingStyle.Quad)
        task.delay(.15,function()
            if not menuOpen then
                main.Visible=false
                reopen.Visible=true
                reopen.Size=UDim2.fromOffset(36,36)
                tw(reopen,.2,{Size=UDim2.fromOffset(48,48)})
            end
        end)
    end
end

close.MouseButton1Click:Connect(function() setMenu(false) end)
reopen.MouseButton1Click:Connect(function()
    if launcherMoved() then return end
    setMenu(true)
end)
UserInputService.InputBegan:Connect(function(i,gp)
    if gp then return end
    if i.KeyCode==Enum.KeyCode.RightShift then setMenu(not menuOpen) end
end)

--==================================================
-- Per-frame motion
--==================================================
local pulse=0
local fpsAcc,fpsFrames=0,0
RunService.RenderStepped:Connect(function(dt)
    if not gui.Parent then return end
    pulse+=dt
    local wave=(math.sin(pulse*1.4)+1)/2
    if animated then
        topAccent.BackgroundTransparency=.05+wave*.10
        dot.BackgroundTransparency=wave*.15
        borderStroke.Transparency=.25+wave*.25
        reopenStroke.Transparency=.15+wave*.35
        for _,p in ipairs(parts) do
            p.y-=p.v*dt
            if p.y<-6 then p.y=566;p.x=math.random()*920 end
            p.f.Position=UDim2.fromOffset(p.x+math.sin(pulse*.8+p.ph)*p.a,p.y)
        end
    else
        topAccent.BackgroundTransparency=0
        dot.BackgroundTransparency=0
        borderStroke.Transparency=.35
        reopenStroke.Transparency=.2
    end
    fpsAcc+=dt;fpsFrames+=1
    if fpsAcc>=.5 then
        liveLbl.Text=math.floor(fpsFrames/fpsAcc+.5).." FPS"
        liveLbl.TextColor3=C.green
        fpsAcc,fpsFrames=0,0
    end
end)

--==================================================
-- Initial page (built while hidden)
--==================================================
clear()
pages.Dashboard()
select("Dashboard")

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
        local dur=.35+math.random()*.35
        local t0=os.clock()
        repeat
            local a=math.min((os.clock()-t0)/dur,1)
            prog=from+(to-from)*(a*a*(3-2*a))
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
    rig.startRel=hrp.CFrame:ToObjectSpace(cam.CFrame)   -- where the camera started, relative to the player
    rig.zoom=N("NumberValue",{Value=0},gui)
    rig.punch=N("NumberValue",{Value=0},gui)             -- temporary FOV kick
    rig.shake=N("NumberValue",{Value=0},gui)             -- temporary camera shake
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
        local startCF=base*rig.startRel
        local headPos=rig.head and rig.head.Position or (base.Position+Vector3.new(0,1.5,0))
        local fwd=base.LookVector
        local bob=Vector3.new(0,math.sin(t*2.2)*.04*a,0)   -- slow "mech step" sway
        local fpCF=CFrame.lookAt(headPos+fwd*.6+bob,headPos+fwd*10+Vector3.new(0,.9,0))
        local cf=startCF:Lerp(fpCF,a)
        local s=rig.shake.Value
        if s>0 then
            cf=cf*CFrame.Angles((math.random()-.5)*s*.02,(math.random()-.5)*s*.02,(math.random()-.5)*s*.02)
        end
        cam.CFrame=cf
        cam.FieldOfView=rig.origFov+COCKPIT_FOV*a+rig.punch.Value
        local hide=a>.55 and 1 or 0                          -- hide the body once we're inside the head
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
        rig.punch.Value=10                                   -- little dolly-out kick
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
            Position=UDim2.new(ax,ax==0 and 50 or -50,ay==0 and .13 or .87,0),
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
    h.tl2=txt(UDim2.new(0,74,.13,38),Vector2.new(0,0),L,10,C.sub,"M3TH-UNIT 01  //  PILOT LINK")
    h.tr1=txt(UDim2.new(1,-74,.13,16),Vector2.new(1,0),Rt,14,C.acc2,"")
    local tr2=txt(UDim2.new(1,-74,.13,38),Vector2.new(1,0),Rt,10,C.sub,"ENERGY  --%")
    local syncLbl=txt(UDim2.new(0,74,.87,-48),Vector2.new(0,0),L,12,C.acc2,"SYNC RATE  000%")
    local br1=txt(UDim2.new(1,-74,.87,-14),Vector2.new(1,1),Rt,12,C.acc2,"● SYSTEM // ONLINE")

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
            tr2.Text=string.format("ENERGY  %d%%",math.random(91,99))
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
        syncLbl.Text=string.format("SYNC RATE  %03d%%",math.floor(p*100+.5))
    end
    function h.sync(dur)
        task.spawn(function()
            local t0=os.clock()
            while h.alive do
                local a=math.min((os.clock()-t0)/dur,1)
                h.setSync(a*a*(3-2*a))
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
        return CFrame.lookAt(pos,base.Position+Vector3.new(0,PANEL_HEIGHT,0))*CFrame.Angles(math.rad(PANEL_TILT),0,0)
    end
    local cf=target()
    part.CFrame=cf
    cs.conn=RunService.RenderStepped:Connect(function(dt)
        if not hrp.Parent then return end
        cf=cf:Lerp(target(),1-math.exp(-dt*9))
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
    task.delay(.09,function() play("pop",1.5) end)  -- second, higher run = rising key chime
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

    rigStop(true)          -- zoom back out to the normal camera
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
