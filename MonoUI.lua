--[[
        MONO UI — Roblox UI library (Luau)
        Black & white, multi-tier surfaces, transparent hairlines, glow strips,
        animated tabs, theme manager, notifications, command palette (fuzzy search),
        toggles / checkboxes / buttons / sliders / dropdowns / keybinds / 2D color pickers / textboxes.
        Hide / minimize / unload, config save & load (if the executor has a filesystem).

        Visual language inspired by Slate (transparency-based borders, hairline fades,
        multi-level surfaces, glow strips, embossed title, squash-stretch knobs).
        Strictly monochrome — every accent is white-on-black or black-on-white.

        API is backward-compatible with the previous MonoUI release:
          Library:CreateWindow / :Notify / :SetTheme / :RegisterTheme / :RefreshTheme
          / :Connect / :OnUnload / :SaveConfig / :LoadConfig / :SetToggleKey / :Unload
          Window:AddTab / :AddSettingsTab / :SelectTab / :SetVisible / :Toggle / :SetMinimized
          Tab:AddSection (auto-balanced left/right)
          Section:AddLabel / :AddButton / :AddToggle / :AddCheckbox / :AddSlider
                  / :AddDropdown / :AddKeybind / :AddTextbox / :AddColorPicker
        New additions sit alongside — nothing existing was removed or renamed.
]]

local cloneref = cloneref or function(o) return o end
local function S(n) return cloneref(game:GetService(n)) end

local Players, TweenService, UIS, HttpService, CoreGui =
        S("Players"), S("TweenService"), S("UserInputService"), S("HttpService"), S("CoreGui")

local genv = (getgenv and getgenv()) or _G
if genv.MonoUI and genv.MonoUI.Unload then
        pcall(function() genv.MonoUI:Unload(true) end) -- kill the previous copy on re-execute
end

local C3 = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

----------------------------------------------------------------------
-- fonts (carried over from Slate's full font vocabulary)
----------------------------------------------------------------------
local FONT = {
        Title       = Enum.Font.BuilderSansBold,
        Heading     = Enum.Font.GothamBold,
        Body        = Enum.Font.BuilderSans,
        Medium      = Enum.Font.BuilderSansMedium,
        Small       = Enum.Font.BuilderSans,
        Micro       = Enum.Font.Gotham,
        Value       = Enum.Font.JetBrainsMono,
        BuilderBold = Enum.Font.BuilderSansBold,
        GothamBold  = Enum.Font.GothamBold,
        GothamMed   = Enum.Font.GothamMedium,
        Gotham      = Enum.Font.Gotham,
}

local SIZE = {
        Title   = 16,
        Heading = 14,
        Body    = 13,
        Medium  = 13,
        Small   = 12,
        Micro   = 11,
        Value   = 12,
        Glyph   = 15,
}

----------------------------------------------------------------------
-- library table
----------------------------------------------------------------------
local Library = {
        Flags = {}, Options = {}, Registry = {}, Hooks = {}, Connections = {}, UnloadCallbacks = {},
        ThemePickers = {}, Folder = "MonoUI", ToggleKey = Enum.KeyCode.RightShift,
        Listening = false, Unloaded = false, _n = 0,
        SearchIndex = {}, -- for command palette
}

----------------------------------------------------------------------
-- theme palettes (strictly monochrome + desaturated semantic accents)
-- Border/Line are stored as Color3 (WHITE for dark, BLACK for light);
-- the actual transparency comes from the BorderT/LineT metrics below.
----------------------------------------------------------------------
local METRICS = {
        Radius       = 6,
        RadiusSm     = 3,
        RowHeight    = 34,
        Pad          = 14,
        Gap          = 8,
        RailWidth    = 164,
        HeaderHeight = 48,
        FooterHeight = 24,
        BorderT      = 0.90,
        BorderT_Hov  = 0.62,
        BorderT_Act  = 0.30,
        LineT        = 0.86,
        HoverT       = 0.965,
        FieldRest    = 0.45,
        FieldHov     = 0.30,
        FieldAct     = 0.22,
        ScrollBar    = 2,
}

-- helper: assemble a complete theme table from a partial palette
local function makeTheme(p)
        -- fill defaults from a strict-mono dark baseline
        local t = {
                Background = p.Background or C3(10, 10, 10),
                Surface    = p.Surface    or C3(16, 16, 16),
                SurfaceAlt = p.SurfaceAlt or C3(22, 22, 22),
                Elevated   = p.Elevated   or C3(28, 28, 28),
                Border     = p.Border     or WHITE,
                Line       = p.Line       or WHITE,
                Text       = p.Text       or C3(242, 242, 242),
                Muted      = p.Muted      or C3(160, 160, 160),
                Faint      = p.Faint      or C3(110, 110, 110),
                Accent     = p.Accent     or WHITE,
                Accent2    = p.Accent2    or C3(180, 180, 180),
                OnAccent   = p.OnAccent   or C3(10, 10, 10),
                ToggleOn   = p.ToggleOn   or WHITE,
                ToggleKnob = p.ToggleKnob or C3(10, 10, 10),
                Success    = p.Success    or C3(160, 200, 170),
                Warning    = p.Warning    or C3(220, 200, 160),
                Danger     = p.Danger     or C3(220, 150, 150),
                Info       = p.Info       or C3(170, 190, 220),
        }
        -- legacy aliases so any pre-existing user theme table keeps working
        t.Panel   = t.Surface
        t.Element = t.SurfaceAlt
        t.SubText = t.Muted
        return t
end

Library.Themes = {
        ["Mono Dark"] = makeTheme({
                Background = C3(10, 10, 10), Surface = C3(16, 16, 16), SurfaceAlt = C3(22, 22, 22), Elevated = C3(28, 28, 28),
                Text = C3(242, 242, 242), Muted = C3(160, 160, 160), Faint = C3(110, 110, 110),
                Accent = WHITE, Accent2 = C3(180, 180, 180), OnAccent = C3(10, 10, 10),
        }),
        ["Mono Light"] = makeTheme({
                Background = C3(236, 236, 236), Surface = C3(246, 246, 246), SurfaceAlt = C3(228, 228, 228), Elevated = C3(252, 252, 252),
                Border = BLACK, Line = BLACK,
                Text = C3(16, 16, 16), Muted = C3(95, 95, 95), Faint = C3(150, 150, 150),
                Accent = C3(16, 16, 16), Accent2 = C3(90, 90, 90), OnAccent = C3(245, 245, 245),
                ToggleOn = C3(16, 16, 16), ToggleKnob = C3(245, 245, 245),
                Success = C3(60, 130, 80), Warning = C3(150, 110, 30), Danger = C3(170, 60, 60), Info = C3(60, 100, 150),
        }),
        ["Graphite"] = makeTheme({
                Background = C3(14, 14, 16), Surface = C3(20, 20, 23), SurfaceAlt = C3(29, 29, 33), Elevated = C3(36, 36, 42),
                Text = C3(235, 235, 238), Muted = C3(140, 140, 150), Faint = C3(95, 95, 105),
                Accent = C3(225, 225, 232), Accent2 = C3(120, 120, 135), OnAccent = C3(14, 14, 16),
                ToggleOn = C3(225, 225, 232), ToggleKnob = C3(14, 14, 16),
        }),
        ["OLED"] = makeTheme({
                Background = C3(0, 0, 0), Surface = C3(6, 6, 6), SurfaceAlt = C3(13, 13, 13), Elevated = C3(20, 20, 20),
                Text = C3(255, 255, 255), Muted = C3(140, 140, 140), Faint = C3(90, 90, 90),
                Accent = WHITE, Accent2 = C3(120, 120, 120), OnAccent = C3(0, 0, 0),
        }),
        ["Noir"] = makeTheme({
                Background = C3(8, 8, 9), Surface = C3(14, 14, 16), SurfaceAlt = C3(20, 20, 23), Elevated = C3(28, 28, 32),
                Text = C3(248, 248, 250), Muted = C3(170, 170, 178), Faint = C3(120, 120, 130),
                Accent = WHITE, Accent2 = C3(200, 200, 210), OnAccent = C3(8, 8, 9),
                ToggleOn = WHITE, ToggleKnob = C3(8, 8, 9),
        }),
        ["Paper"] = makeTheme({
                Background = C3(244, 242, 238), Surface = C3(252, 250, 246), SurfaceAlt = C3(236, 234, 228), Elevated = C3(255, 254, 250),
                Border = BLACK, Line = BLACK,
                Text = C3(28, 26, 22), Muted = C3(108, 104, 96), Faint = C3(160, 156, 148),
                Accent = C3(28, 26, 22), Accent2 = C3(90, 86, 78), OnAccent = C3(252, 250, 246),
                ToggleOn = C3(28, 26, 22), ToggleKnob = C3(252, 250, 246),
                Success = C3(60, 130, 80), Warning = C3(150, 110, 30), Danger = C3(170, 60, 60), Info = C3(60, 100, 150),
        }),
}
Library.ThemeName = "Mono Dark"
Library.Theme = {}
Library.Metrics = {}
for k, v in pairs(Library.Themes["Mono Dark"]) do Library.Theme[k] = v end
for k, v in pairs(METRICS) do Library.Metrics[k] = v end

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local TEXT = { TextLabel = true, TextButton = true, TextBox = true }

local function Create(class, props, children)
        local o = Instance.new(class)
        if o:IsA("GuiObject") then o.BorderSizePixel = 0 end
        if TEXT[class] then
                o.BackgroundTransparency = 1; o.Font = FONT.Body; o.TextSize = SIZE.Body; o.Text = ""
        end
        if class == "TextButton" then o.AutoButtonColor = false end
        if class == "ScrollingFrame" then o.ScrollBarThickness = METRICS.ScrollBar; o.BackgroundTransparency = 1 end
        local theme, parent
        for k, v in pairs(props or {}) do
                if k == "Theme" then theme = v elseif k == "Parent" then parent = v else o[k] = v end
        end
        for _, c in ipairs(children or {}) do c.Parent = o end
        if theme then Library:Themed(o, theme) end
        o.Parent = parent
        return o
end

local function Corner(r) return Create("UICorner", { CornerRadius = UDim.new(0, r or METRICS.Radius) }) end
local function CornerSm() return Create("UICorner", { CornerRadius = UDim.new(0, METRICS.RadiusSm) }) end
local function Round() return Create("UICorner", { CornerRadius = UDim.new(1, 0) }) end

-- Stroke now takes optional transparency; defaults to BorderT metric.
-- Supports an optional "key" that is a theme token (Border / Accent / Danger / ...).
local function Stroke(key, th, transparency)
        return Create("UIStroke", {
                Thickness = th or 1,
                Transparency = transparency or Library.Metrics.BorderT,
                ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                Theme = { Color = key or "Border" },
        })
end

local function Grad(rot, keyA, keyB)
        return Create("UIGradient", {
                Rotation = rot or 0,
                Theme = { Color = { keyA or "Accent", keyB or "Accent2" } },
        })
end

-- Hairline: thin separator with optional fade (1 -> 0 -> 1) at the ends.
-- The line color is the theme "Line" token, transparency is LineT.
local function Hairline(parent, opts)
        opts = opts or {}
        local line = Create("Frame", {
                Name = "Hairline",
                AnchorPoint = opts.anchor or Vector2.new(0, 1),
                Position = opts.position or UDim2.fromScale(0, 1),
                Size = opts.vertical and UDim2.new(0, 1, 1, 0) or UDim2.new(1, 0, 0, 1),
                BackgroundTransparency = opts.transparency or Library.Metrics.LineT,
                ZIndex = opts.zindex or 2,
                Theme = { BackgroundColor3 = opts.token or "Line" },
                Parent = parent,
        })
        if opts.fade then
                local edge = opts.edge or 0.18
                Create("UIGradient", {
                        Rotation = opts.vertical and 90 or 0,
                        Transparency = NumberSequence.new({
                                NumberSequenceKeypoint.new(0, 1),
                                NumberSequenceKeypoint.new(edge, 0),
                                NumberSequenceKeypoint.new(1 - edge, 0),
                                NumberSequenceKeypoint.new(1, 1),
                        }),
                        Parent = line,
                })
        end
        return line
end

-- Glow: thin horizontal/vertical strip with a soft radial-like gradient.
-- Used under accent lines, on active tabs, behind markers.
local function Glow(parent, opts)
        opts = opts or {}
        local glow = Create("Frame", {
                Name = "Glow",
                AnchorPoint = opts.anchor or Vector2.new(0, 1),
                Position = opts.position or UDim2.new(0, 0, 1, 0),
                Size = opts.size or UDim2.new(1, 0, 0, 3),
                BackgroundTransparency = 1,
                ZIndex = opts.zindex or 1,
                Theme = { BackgroundColor3 = opts.token or "Accent" },
                Parent = parent,
        })
        Create("UIGradient", {
                Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 1),
                        NumberSequenceKeypoint.new(0.22, 0.55),
                        NumberSequenceKeypoint.new(0.5, 0),
                        NumberSequenceKeypoint.new(0.78, 0.55),
                        NumberSequenceKeypoint.new(1, 1),
                }),
                Parent = glow,
        })
        return glow
end

-- EmbossText: layered shadow stack + crisp face. Pure-white embossed title.
local function EmbossText(parent, opts)
        opts = opts or {}
        local text = opts.text or "MONO"
        local depth = opts.depth or 4
        local step = opts.step or 1
        local container = Create("Frame", {
                Name = "Emboss",
                Size = opts.size or UDim2.new(1, 0, 1, 0),
                Position = opts.position or UDim2.fromOffset(0, 0),
                BackgroundTransparency = 1,
                Parent = parent,
        })
        for i = depth, 1, -1 do
                Create("TextLabel", {
                        Name = "Depth" .. i,
                        Size = UDim2.fromScale(1, 1),
                        Position = UDim2.fromOffset(i * step, i * step),
                        Text = text, TextSize = opts.textSize or SIZE.Title, Font = opts.font or FONT.Title,
                        TextXAlignment = opts.align or Enum.TextXAlignment.Left,
                        TextYAlignment = opts.valign or Enum.TextYAlignment.Center,
                        TextTransparency = 0.18 + (i / (depth + 1)) * 0.62,
                        ZIndex = 1, Theme = { TextColor3 = opts.shadowToken or "Background" }, Parent = container,
                })
        end
        Create("TextLabel", {
                Name = "Face",
                Size = UDim2.fromScale(1, 1),
                Text = text, TextSize = opts.textSize or SIZE.Title, Font = opts.font or FONT.Title,
                TextXAlignment = opts.align or Enum.TextXAlignment.Left,
                TextYAlignment = opts.valign or Enum.TextYAlignment.Center,
                ZIndex = 3, Theme = { TextColor3 = opts.token or "Text" }, Parent = container,
        })
        return container
end

local function Tween(o, goal, t, style, dir)
        local tw = TweenService:Create(o, TweenInfo.new(t or .2, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), goal)
        tw:Play()
        return tw
end

-- resolve a theme key. Tables become ColorSequences; numbers (transparency tokens)
-- come straight from Library.Metrics; strings resolve against Library.Theme.
local function resolve(key)
        if type(key) == "table" then
                return ColorSequence.new(Library.Theme[key[1]] or WHITE, Library.Theme[key[2]] or BLACK)
        end
        if type(key) == "number" then return key end
        return Library.Theme[key]
end

function Library:Themed(inst, map)
        table.insert(self.Registry, { Inst = inst, Map = map })
        for p, k in pairs(map) do inst[p] = resolve(k) end
        return inst
end

function Library:Hook(inst, fn)
        table.insert(self.Hooks, { Inst = inst, Fn = fn })
end

function Library:RefreshTheme(instant)
        for i = #self.Registry, 1, -1 do
                local e = self.Registry[i]
                if not e.Inst.Parent then
                        table.remove(self.Registry, i)
                else
                        local goal = {}
                        for p, k in pairs(e.Map) do
                                if type(k) == "table" then e.Inst[p] = resolve(k) else goal[p] = resolve(k) end
                        end
                        if instant then
                                for p, v in pairs(goal) do e.Inst[p] = v end
                        else
                                Tween(e.Inst, goal, .25)
                        end
                end
        end
        for i = #self.Hooks, 1, -1 do
                local h = self.Hooks[i]
                if not h.Inst.Parent then table.remove(self.Hooks, i) else pcall(h.Fn) end
        end
end

function Library:SetTheme(name)
        local t = self.Themes[name]
        if not t then return end
        self.ThemeName = name
        for k, v in pairs(t) do self.Theme[k] = v end
        self:RefreshTheme()
        for key, picker in pairs(self.ThemePickers) do
                if picker and picker.Set then picker:Set(self.Theme[key], true) end
        end
end

-- RegisterTheme: backward-compatible — accepts both old-style partial tables
-- (Background/Panel/Element/Border/Text/SubText/Accent/Accent2/OnAccent) and
-- new-style full tables (Surface/SurfaceAlt/Elevated/Muted/Faint/...).
function Library:RegisterTheme(name, tbl)
        self.Themes[name] = makeTheme(tbl)
end

-- RegisterMetric: tweak a numeric metric (Radius, BorderT, HeaderHeight, ...)
function Library:RegisterMetric(key, value)
        self.Metrics[key] = value
        self:RefreshTheme(true)
end

function Library:Connect(sig, fn)
        local c = sig:Connect(fn)
        table.insert(self.Connections, c)
        return c
end

function Library:OnUnload(fn) table.insert(self.UnloadCallbacks, fn) end

function Library:_Fire(obj, silent)
        if obj.Flag then self.Flags[obj.Flag] = obj.Value end
        if not silent and obj.Callback then task.spawn(obj.Callback, obj.Value) end
end

-- register an element for the command palette
function Library:_Index(label, kind, hint, activate)
        table.insert(self.SearchIndex, {
                Label = label, Kind = kind or "Element", Hint = hint or "",
                Activate = activate or function() end,
        })
end

local function Register(obj, o)
        obj.Flag = o.Flag or o.Name
        obj.Ignore = o.Ignore
        if obj.Flag then
                Library.Flags[obj.Flag] = obj.Value
                Library.Options[obj.Flag] = obj
        end
end

local function MouseOrTouch(i)
        return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end

local function MakeDrag(target, onMove, onStart, onEnd)
        local dragging = false
        Library:Connect(target.InputBegan, function(i)
                if MouseOrTouch(i) then
                        dragging = true
                        local p = Vector2.new(i.Position.X, i.Position.Y)
                        if onStart then onStart(p) end
                        onMove(p)
                end
        end)
        Library:Connect(UIS.InputChanged, function(i)
                if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                        onMove(Vector2.new(i.Position.X, i.Position.Y))
                end
        end)
        Library:Connect(UIS.InputEnded, function(i)
                if dragging and MouseOrTouch(i) then
                        dragging = false
                        if onEnd then onEnd() end
                end
        end)
end

local function randomName()
        local t = {}
        for i = 1, 12 do t[i] = string.char(math.random(97, 122)) end
        return table.concat(t)
end

-- fuzzy score: returns nil if no match, else a number (lower is better).
local function fuzzyMatch(query, text)
        if query == "" then return 0 end
        query = string.lower(query); text = string.lower(text)
        if text:find(query, 1, true) then return 0.1 end
        local qi, score, last = 1, 0, -1
        for i = 1, #text do
                if qi <= #query and string.sub(text, i, i) == string.sub(query, qi, qi) then
                        score = score + (i - last == 1 and 1 or 2)
                        last = i; qi = qi + 1
                end
        end
        if qi <= #query then return nil end
        return score + #text * 0.001
end

function Library:_Gui()
        if self.Gui and self.Gui.Parent then return self.Gui end
        local gui = Create("ScreenGui", {
                Name = randomName(), ResetOnSpawn = false, IgnoreGuiInset = true,
                ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999,
        })
        pcall(function()
                if syn and syn.protect_gui then syn.protect_gui(gui) end
                gui.Parent = (gethui and gethui()) or CoreGui
        end)
        if not gui.Parent then gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end
        self.Gui = gui
        self.NotifyHolder = Create("Frame", {
                AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16), Size = UDim2.new(0, 300, 1, -32),
                BackgroundTransparency = 1, Parent = gui,
        }, { Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 8) }) })
        return gui
end

----------------------------------------------------------------------
-- notifications — hairline border, top glow, back-easing slide-in
----------------------------------------------------------------------
function Library:Notify(o)
        if type(o) == "string" then o = { Content = o } end
        self:_Gui()
        self._n += 1
        local dur = o.Duration or 4
        local accentToken = o.Accent or "Accent"
        local holder = Create("Frame", {
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
                LayoutOrder = self._n, Parent = self.NotifyHolder,
        })
        local card = Create("CanvasGroup", {
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.new(0, 40, 0, 0),
                GroupTransparency = 1, Theme = { BackgroundColor3 = "Surface" }, ClipsDescendants = true, Parent = holder,
        }, { Corner(METRICS.Radius), Stroke("Border", 1, METRICS.BorderT) })
        -- top accent glow strip
        Glow(card, { size = UDim2.new(1, 0, 0, 2), position = UDim2.fromScale(0, 0), anchor = Vector2.new(0, 0), token = accentToken, zindex = 4 })
        local inner = Create("Frame", {
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = card,
        }, {
                Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
                Create("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 12), PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }),
        })
        Create("TextLabel", {
                LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left, Font = FONT.Heading, TextSize = SIZE.Heading, Text = o.Title or "Notification",
                Theme = { TextColor3 = "Text" }, Parent = inner,
        })
        if o.Content and o.Content ~= "" then
                Create("TextLabel", {
                        LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true,
                        TextXAlignment = Enum.TextXAlignment.Left, Font = FONT.Body, TextSize = SIZE.Small, Text = o.Content,
                        Theme = { TextColor3 = "Muted" }, Parent = inner,
                })
        end
        local track = Create("Frame", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 2), BackgroundTransparency = 0.7, Theme = { BackgroundColor3 = "Line" }, Parent = inner }, { Round() })
        local fill = Create("Frame", { Size = UDim2.fromScale(1, 1), Theme = { BackgroundColor3 = accentToken }, Parent = track }, { Round(), Grad(0, accentToken, accentToken) })

        Tween(card, { Position = UDim2.new(0, 0, 0, 0), GroupTransparency = 0 }, .5, Enum.EasingStyle.Back)
        Tween(fill, { Size = UDim2.fromScale(0, 1) }, dur, Enum.EasingStyle.Linear)

        task.delay(dur, function()
                if not holder.Parent then return end
                Tween(card, { Position = UDim2.new(0, 40, 0, 0), GroupTransparency = 1 }, .3)
                task.wait(.3)
                if not holder.Parent then return end
                holder.AutomaticSize = Enum.AutomaticSize.None
                holder.Size = UDim2.new(1, 0, 0, holder.AbsoluteSize.Y)
                Tween(holder, { Size = UDim2.new(1, 0, 0, 0) }, .2)
                task.wait(.2)
                holder:Destroy()
        end)
end

----------------------------------------------------------------------
-- config
----------------------------------------------------------------------
local function fsOk()
        return (writefile and readfile and isfile and makefolder and isfolder) and true or false
end

function Library:SaveConfig(name)
        if not fsOk() then return false, "filesystem is not available" end
        if not name or name == "" then return false, "empty config name" end
        if not isfolder(self.Folder) then makefolder(self.Folder) end
        local data = { Flags = {}, Theme = {} }
        for flag, opt in pairs(self.Options) do
                if not opt.Ignore then
                        local v = opt.Value
                        if opt.Type == "ColorPicker" then v = { R = v.R, G = v.G, B = v.B }
                        elseif opt.Type == "Keybind" then v = v and v.Name or "None" end
                        data.Flags[flag] = v
                end
        end
        for k, c in pairs(self.Theme) do data.Theme[k] = { R = c.R, G = c.G, B = c.B } end
        data.ThemeName = self.ThemeName
        writefile(self.Folder .. "/" .. name .. ".json", HttpService:JSONEncode(data))
        return true
end

function Library:LoadConfig(name)
        if not fsOk() then return false, "filesystem is not available" end
        local path = self.Folder .. "/" .. tostring(name) .. ".json"
        if not isfile(path) then return false, "config not found" end
        local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
        if not ok or type(data) ~= "table" then return false, "broken config" end
        for flag, v in pairs(data.Flags or {}) do
                local opt = self.Options[flag]
                if opt and not opt.Ignore then
                        if opt.Type == "ColorPicker" and type(v) == "table" then v = Color3.new(v.R, v.G, v.B)
                        elseif opt.Type == "Keybind" then
                                local okk, kc = pcall(function() return Enum.KeyCode[v] end)
                                v = okk and kc or nil
                        end
                        pcall(function() opt:Set(v) end)
                end
        end
        if data.ThemeName and self.Themes[data.ThemeName] then
                self:SetTheme(data.ThemeName)
        else
                for k, c in pairs(data.Theme or {}) do
                        if self.Theme[k] and type(c) == "table" then self.Theme[k] = Color3.new(c.R, c.G, c.B) end
                end
                self:RefreshTheme()
                for key, picker in pairs(self.ThemePickers) do
                        if picker and picker.Set then picker:Set(self.Theme[key], true) end
                end
        end
        return true
end

-- ExportTheme / ImportTheme: share palette as a JSON string
function Library:ExportTheme()
        local t = {}
        for k, c in pairs(self.Theme) do t[k] = string.format("#%02X%02X%02X",
                math.floor(c.R * 255 + .5), math.floor(c.G * 255 + .5), math.floor(c.B * 255 + .5)) end
        return HttpService:JSONEncode(t)
end

function Library:ImportTheme(json)
        local ok, t = pcall(function() return HttpService:JSONDecode(json) end)
        if not ok or type(t) ~= "table" then return false end
        for k, hex in pairs(t) do
                local r, g, b = tostring(hex):match("^#?(%x%x)(%x%x)(%x%x)$")
                if r and self.Theme[k] then self.Theme[k] = C3(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)) end
        end
        self:RefreshTheme()
        for key, picker in pairs(self.ThemePickers) do
                if picker and picker.Set then picker:Set(self.Theme[key], true) end
        end
        return true
end

----------------------------------------------------------------------
-- element helpers
----------------------------------------------------------------------
local Section = {}
Section.__index = Section

-- MakeRow now uses SurfaceAlt with a transparent Border-hairline on hover.
local function MakeRow(sec, h)
        local row = Create("Frame", {
                Size = UDim2.new(1, 0, 0, h), Theme = { BackgroundColor3 = "SurfaceAlt" }, Parent = sec.Content,
        }, { Corner(METRICS.Radius) })
        return row
end

local function RowLabel(row, text, w)
        return Create("TextLabel", {
                Text = text, Position = UDim2.fromOffset(12, 0), Size = w or UDim2.new(1, -24, 0, 34),
                TextXAlignment = Enum.TextXAlignment.Left, Font = FONT.Body, TextSize = SIZE.Body,
                TextTruncate = Enum.TextTruncate.AtEnd, Theme = { TextColor3 = "Text" }, Parent = row,
        })
end

-- RowButton: full-size hit area + subtle hover lift on the row.
local function RowButton(row)
        local btn = Create("TextButton", { Size = UDim2.new(1, 0, 0, 34), Parent = row })
        local function enter() Tween(row, { BackgroundColor3 = Library.Theme.Elevated }, .15) end
        local function leave() Tween(row, { BackgroundColor3 = Library.Theme.SurfaceAlt }, .15) end
        Library:Connect(btn.MouseEnter, enter)
        Library:Connect(btn.MouseLeave, leave)
        return btn
end

function Section:AddLabel(text)
        local row = MakeRow(self, 28)
        local lbl = Create("TextLabel", {
                Text = text, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
                Font = FONT.Body, TextSize = SIZE.Small, Theme = { TextColor3 = "Muted" }, Parent = row,
        })
        return { SetText = function(_, t) lbl.Text = t end }
end

-- Button: white gradient face with sheen rotation on hover + press-scale.
function Section:AddButton(o)
        o = o or {}
        local obj = { Type = "Button" }
        local row = Create("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = WHITE, Parent = self.Content }, {
                Corner(METRICS.Radius), Create("UIScale", { Scale = 1 }),
        })
        local grad = Grad(0); grad.Parent = row
        local sheen = Create("Frame", {
                Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, Parent = row,
        }, { Corner(METRICS.Radius),
                Create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.5, 0.92), NumberSequenceKeypoint.new(1, 0.7),
                }) }),
        })
        local scale = row:FindFirstChildOfClass("UIScale")
        local btn = Create("TextButton", {
                Size = UDim2.fromScale(1, 1), Text = o.Name or "Button", Font = FONT.Heading, TextSize = SIZE.Heading,
                Theme = { TextColor3 = "OnAccent" }, Parent = row,
        })
        Library:Connect(btn.MouseEnter, function() Tween(grad, { Rotation = 35 }, .3); Tween(sheen, { BackgroundTransparency = 0.85 }, .2) end)
        Library:Connect(btn.MouseLeave, function() Tween(grad, { Rotation = 0 }, .3); Tween(sheen, { BackgroundTransparency = 1 }, .2) end)
        Library:Connect(btn.MouseButton1Down, function() Tween(scale, { Scale = .96 }, .08) end)
        Library:Connect(btn.MouseButton1Up, function() Tween(scale, { Scale = 1 }, .15, Enum.EasingStyle.Back) end)
        Library:Connect(btn.MouseLeave, function() Tween(scale, { Scale = 1 }, .15) end)
        Library:Connect(btn.MouseButton1Click, function()
                if o.Callback then task.spawn(o.Callback) end
        end)
        function obj:SetText(t) btn.Text = t end
        Library:_Index((o.Name or "Button"), "Button", nil, function() if o.Callback then task.spawn(o.Callback) end end)
        return obj
end

-- Toggle: squash-stretch knob + transparent track + gradient sheen on knob.
function Section:AddToggle(o)
        o = o or {}
        local obj = { Type = "Toggle", Value = o.Default == true, Callback = o.Callback or function() end }
        local row = MakeRow(self, 34)
        RowLabel(row, o.Name or "Toggle")
        local btn = RowButton(row)
        local TRACK_W, TRACK_H, KNOB, INSET = 38, 20, 14, 3
        local track = Create("Frame", {
                AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -10, .5, 0), Size = UDim2.fromOffset(TRACK_W, TRACK_H),
                BackgroundTransparency = .55, Theme = { BackgroundColor3 = "SurfaceAlt" }, ClipsDescendants = true, Parent = row,
        }, { Round(),
                Create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.14) }) }),
        })
        local trackStroke = Stroke("Border", 1, METRICS.BorderT); trackStroke.Parent = track
        local fill = Create("Frame", {
                Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Theme = { BackgroundColor3 = "ToggleOn" }, Parent = track,
        }, { Round() })
        local knob = Create("Frame", {
                AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, INSET, .5, 0), Size = UDim2.fromOffset(KNOB, KNOB),
                Theme = { BackgroundColor3 = "Muted" }, ZIndex = 3, Parent = track,
        }, { Round(),
                Create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.22) }) }),
        })
        local function render(instant)
                local on, t = obj.Value, instant and 0 or .22
                local target = on and (TRACK_W - KNOB - INSET) or INSET
                if instant then
                        knob.Position = UDim2.new(0, target, .5, 0)
                        knob.Size = UDim2.fromOffset(KNOB, KNOB)
                else
                        -- squash-stretch: grow + slide fast, then settle with Back easing
                        Tween(knob, {
                                Size = UDim2.fromOffset(KNOB + 4, KNOB - 2),
                                Position = UDim2.new(0, on and (target - 2) or (target - 1), .5, 0),
                        }, .08, Enum.EasingStyle.Sine)
                        task.delay(.08, function()
                                if not knob.Parent then return end
                                Tween(knob, {
                                        Size = UDim2.fromOffset(KNOB, KNOB),
                                        Position = UDim2.new(0, target, .5, 0),
                                }, .22, Enum.EasingStyle.Back)
                        end)
                end
                Tween(track, { BackgroundTransparency = on and 0 or .55 }, t)
                Tween(trackStroke, { Transparency = on and 0.5 or METRICS.BorderT, Color = on and Library.Theme.ToggleOn or Library.Theme.Border }, t)
                Tween(fill, { BackgroundTransparency = on and 0.4 or 1 }, t)
                Tween(knob, { BackgroundColor3 = on and Library.Theme.ToggleKnob or Library.Theme.Muted }, t)
        end
        function obj:Set(v, silent) self.Value = v and true or false; render(); Library:_Fire(self, silent) end
        function obj:Get() return self.Value end
        Library:Hook(row, function() render(true) end)
        Library:Connect(btn.MouseButton1Click, function() obj:Set(not obj.Value) end)
        Register(obj, o)
        render(true)
        Library:_Index((o.Name or "Toggle"), "Toggle", obj.Value and "on" or "off", function() obj:Set(not obj.Value) end)
        return obj
end

-- Checkbox: bounce-check + transparent field.
function Section:AddCheckbox(o)
        o = o or {}
        local obj = { Type = "Checkbox", Value = o.Default == true, Callback = o.Callback or function() end }
        local row = MakeRow(self, 34)
        RowLabel(row, o.Name or "Checkbox")
        local btn = RowButton(row)
        local box = Create("Frame", {
                AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -10, .5, 0), Size = UDim2.fromOffset(18, 18),
                BackgroundTransparency = .55, Theme = { BackgroundColor3 = "SurfaceAlt" }, Parent = row,
        }, { CornerSm() })
        local boxStroke = Stroke("Border", 1, METRICS.BorderT); boxStroke.Parent = box
        local mark = Create("Frame", {
                AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.fromOffset(0, 0),
                BackgroundColor3 = WHITE, Parent = box,
        }, { CornerSm(), Grad(45, "Accent", "Accent2") })
        local function render(instant)
                local on = obj.Value
                Tween(mark, { Size = on and UDim2.fromOffset(10, 10) or UDim2.fromOffset(0, 0) }, instant and 0 or .22, Enum.EasingStyle.Back)
                Tween(boxStroke, { Transparency = on and 0.5 or METRICS.BorderT, Color = on and Library.Theme.Accent or Library.Theme.Border }, .2)
                Tween(box, { BackgroundTransparency = on and 0.2 or .55 }, .2)
        end
        function obj:Set(v, silent) self.Value = v and true or false; render(); Library:_Fire(self, silent) end
        function obj:Get() return self.Value end
        Library:Connect(btn.MouseButton1Click, function() obj:Set(not obj.Value) end)
        Register(obj, o)
        render(true)
        Library:_Index((o.Name or "Checkbox"), "Checkbox", obj.Value and "on" or "off", function() obj:Set(not obj.Value) end)
        return obj
end

-- Slider: 6px track, 14px grip, hover lift, monospace value.
function Section:AddSlider(o)
        o = o or {}
        local min, max, inc = o.Min or 0, o.Max or 100, o.Increment or 1
        local dec = #(tostring(inc):match("%.(%d+)") or "")
        local obj = { Type = "Slider", Callback = o.Callback or function() end }
        local row = MakeRow(self, 48)
        local label = RowLabel(row, o.Name or "Slider", UDim2.new(.6, -12, 0, 28))
        label.Position = UDim2.fromOffset(12, 4)
        local val = Create("TextLabel", {
                AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 4), Size = UDim2.new(.4, -12, 0, 26),
                TextXAlignment = Enum.TextXAlignment.Right, Font = FONT.Value, TextSize = SIZE.Value,
                Theme = { TextColor3 = "Muted" }, Parent = row,
        })
        local hit = Create("Frame", { Position = UDim2.new(0, 12, 1, -26), Size = UDim2.new(1, -24, 0, 22), BackgroundTransparency = 1, Parent = row })
        local track = Create("Frame", {
                AnchorPoint = Vector2.new(0, .5), Position = UDim2.fromScale(0, .5), Size = UDim2.new(1, 0, 0, 6),
                BackgroundTransparency = .55, Theme = { BackgroundColor3 = "SurfaceAlt" }, Parent = hit,
        }, { Round() })
        local trackStroke = Stroke("Border", 1, METRICS.BorderT); trackStroke.Parent = track
        local fill = Create("Frame", { Size = UDim2.fromScale(0, 1), Theme = { BackgroundColor3 = "Accent" }, Parent = track }, { Round(), Grad(0, "Accent", "Accent2") })
        local knob = Create("Frame", {
                AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(0, .5), Size = UDim2.fromOffset(14, 14),
                Theme = { BackgroundColor3 = "Accent" }, Parent = track, ZIndex = 3,
        }, { Round(),
                Create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.22) }) }),
        })
        local knobScale = Create("UIScale", { Scale = 1 }); knobScale.Parent = knob

        local function snap(v)
                v = math.clamp(v, min, max)
                v = min + math.floor((v - min) / inc + .5) * inc
                return tonumber(string.format("%." .. dec .. "f", math.clamp(v, min, max)))
        end
        function obj:Set(v, silent)
                v = snap(tonumber(v) or min)
                local changed = v ~= self.Value
                self.Value = v
                local a = (max == min) and 0 or (v - min) / (max - min)
                Tween(fill, { Size = UDim2.fromScale(a, 1) }, .12)
                Tween(knob, { Position = UDim2.fromScale(a, .5) }, .12)
                val.Text = tostring(v) .. (o.Suffix or "")
                if changed or silent == false then Library:_Fire(self, silent) elseif obj.Flag then Library.Flags[obj.Flag] = v end
        end
        function obj:Get() return self.Value end
        MakeDrag(hit, function(p)
                local a = math.clamp((p.X - hit.AbsolutePosition.X) / hit.AbsoluteSize.X, 0, 1)
                obj:Set(min + (max - min) * a)
        end)
        Library:Connect(hit.MouseEnter, function() Tween(knobScale, { Scale = 1.18 }, .15, Enum.EasingStyle.Back) end)
        Library:Connect(hit.MouseLeave, function() Tween(knobScale, { Scale = 1 }, .15) end)
        Register(obj, o)
        obj:Set(o.Default or min, true)
        Library:_Index((o.Name or "Slider"), "Slider", tostring(obj.Value), function() obj:Set(obj.Value) end)
        return obj
end

-- Dropdown: hairline-separated list, fade-in on open, transparent hover.
function Section:AddDropdown(o)
        o = o or {}
        local multi = o.Multi == true
        local obj = { Type = "Dropdown", Multi = multi, Options = o.Options or {}, Callback = o.Callback or function() end }
        if multi then
                obj.Value = {}
                for _, v in ipairs(o.Default or {}) do obj.Value[v] = true end
        else
                obj.Value = o.Default or obj.Options[1]
        end
        local row = MakeRow(self, 34)
        row.ClipsDescendants = true
        RowLabel(row, o.Name or "Dropdown", UDim2.new(.45, -12, 0, 34))
        local valueLbl = Create("TextLabel", {
                AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.new(.55, -16, 0, 34),
                TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, TextSize = SIZE.Small,
                Font = FONT.Value, Theme = { TextColor3 = "Muted" }, Parent = row,
        })
        local chev = Create("TextLabel", {
                AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -2, 0, 0), Size = UDim2.fromOffset(0, 34),
                Text = "", Font = FONT.Gotham, TextSize = 10, TextColor3 = Library.Theme.Faint, Parent = row,
        })
        local btn = RowButton(row)
        local list = Create("ScrollingFrame", {
                Position = UDim2.new(0, 6, 0, 38), Size = UDim2.new(1, -12, 0, 0), CanvasSize = UDim2.new(),
                AutomaticCanvasSize = Enum.AutomaticSize.Y, Theme = { ScrollBarImageColor3 = "Faint" }, Parent = row,
        }, { Create("UIListLayout", { Padding = UDim.new(0, 1), SortOrder = Enum.SortOrder.LayoutOrder }) })

        local buttons, open = {}, false
        local function listHeight()
                local n = math.min(#obj.Options, 6)
                return n * 26 + math.max(n - 1, 0) * 1
        end
        local function resize()
                local h = listHeight()
                Tween(row, { Size = UDim2.new(1, 0, 0, open and (34 + 4 + h + 6) or 34) }, .28)
                Tween(list, { Size = UDim2.new(1, -12, 0, h) }, .28)
                Tween(chev, { Rotation = open and 180 or 0 }, .2)
        end
        local function text()
                if multi then
                        local t = {}
                        for _, opt in ipairs(obj.Options) do if obj.Value[opt] then table.insert(t, opt) end end
                        return #t > 0 and table.concat(t, ", ") or "None"
                end
                return obj.Value and tostring(obj.Value) or "None"
        end
        local function refresh()
                valueLbl.Text = text()
                for opt, b in pairs(buttons) do
                        local sel = multi and obj.Value[opt] or obj.Value == opt
                        Tween(b, { TextColor3 = sel and Library.Theme.Text or Library.Theme.Muted, BackgroundTransparency = sel and 0 or 1 }, .15)
                        local st = b:FindFirstChildOfClass("UIStroke")
                        if st then Tween(st, { Transparency = sel and 0.4 or 1 }, .15) end
                end
        end
        local function build()
                for _, b in pairs(buttons) do b:Destroy() end
                buttons = {}
                for i, opt in ipairs(obj.Options) do
                        local b = Create("TextButton", {
                                LayoutOrder = i, Size = UDim2.new(1, -4, 0, 26), Text = opt, TextSize = SIZE.Small, Font = FONT.Body,
                                TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
                                Theme = { BackgroundColor3 = "Elevated" }, Parent = list,
                        }, { CornerSm(), Stroke("Border", 1, 1),
                                Create("UIPadding", { PaddingLeft = UDim.new(0, 10) }) })
                        buttons[opt] = b
                        Library:Connect(b.MouseButton1Click, function()
                                if multi then
                                        obj.Value[opt] = not obj.Value[opt] or nil
                                else
                                        obj.Value = opt
                                        open = false; resize()
                                end
                                refresh(); Library:_Fire(obj)
                        end)
                end
                refresh()
                if open then resize() end
        end
        function obj:Set(v, silent)
                if multi then
                        self.Value = {}
                        if type(v) == "table" then
                                for k, x in pairs(v) do
                                        if type(k) == "number" then self.Value[x] = true elseif x then self.Value[k] = true end
                                end
                        end
                else
                        self.Value = v
                end
                refresh(); Library:_Fire(self, silent)
        end
        function obj:Get() return self.Value end
        function obj:SetOptions(opts) self.Options = opts; build() end
        Library:Hook(row, refresh)
        Library:Connect(btn.MouseButton1Click, function() open = not open; resize() end)
        Register(obj, o)
        build()
        chev.Text = "\226\150\190" -- ▾
        chev.TextXAlignment = Enum.TextXAlignment.Right
        chev.TextYAlignment = Enum.TextYAlignment.Center
        chev.Rotation = 0
        chev.Position = UDim2.new(1, -4, 0, 0)
        chev.Size = UDim2.fromOffset(12, 34)
        chev.AnchorPoint = Vector2.new(1, 0)
        Library:_Index((o.Name or "Dropdown"), "Dropdown", tostring(obj.Value), function() open = not open; resize() end)
        return obj
end

-- Keybind: pill with hover/active stroke + listening glow.
function Section:AddKeybind(o)
        o = o or {}
        local obj = { Type = "Keybind", Value = o.Default, Callback = o.Callback or function() end }
        local row = MakeRow(self, 34)
        RowLabel(row, o.Name or "Keybind", UDim2.new(.5, -12, 0, 34))
        local btn = Create("TextButton", {
                AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -10, .5, 0), Size = UDim2.fromOffset(0, 24),
                AutomaticSize = Enum.AutomaticSize.X, Font = FONT.Value, TextSize = SIZE.Small,
                BackgroundTransparency = .55, Theme = { BackgroundColor3 = "SurfaceAlt", TextColor3 = "Text" }, Parent = row,
        }, { CornerSm(), Stroke("Border", 1, METRICS.BorderT),
                Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }) })
        local stroke = btn:FindFirstChildOfClass("UIStroke")
        local listening = false
        local function render()
                btn.Text = listening and "..." or (obj.Value and obj.Value.Name or "None")
                if listening then
                        Tween(stroke, { Transparency = 0.2, Color = Library.Theme.Accent }, .2)
                else
                        Tween(stroke, { Transparency = METRICS.BorderT, Color = Library.Theme.Border }, .2)
                end
        end
        function obj:Set(key, silent)
                self.Value = key
                render()
                if self.Flag then Library.Flags[self.Flag] = key end
                if not silent and o.Changed then task.spawn(o.Changed, key) end
        end
        function obj:Get() return self.Value end
        Library:Connect(btn.MouseEnter, function() if not listening then Tween(stroke, { Transparency = METRICS.BorderT_Hov }, .15) end end)
        Library:Connect(btn.MouseLeave, function() if not listening then Tween(stroke, { Transparency = METRICS.BorderT }, .15) end end)
        Library:Connect(btn.MouseButton1Click, function()
                if listening then return end
                listening = true; Library.Listening = true; render()
        end)
        Library:Connect(UIS.InputBegan, function(i, gpe)
                if listening then
                        if i.UserInputType == Enum.UserInputType.Keyboard then
                                listening = false
                                task.defer(function() Library.Listening = false end)
                                if i.KeyCode == Enum.KeyCode.Escape or i.KeyCode == Enum.KeyCode.Backspace then obj:Set(nil) else obj:Set(i.KeyCode) end
                        end
                elseif not gpe and obj.Value and i.KeyCode == obj.Value then
                        task.spawn(obj.Callback, obj.Value)
                end
        end)
        Register(obj, o)
        render()
        Library:_Index((o.Name or "Keybind"), "Keybind", obj.Value and obj.Value.Name or "None", function() btn.MouseButton1Click:Fire() end)
        return obj
end

-- Textbox: field with rest/hover/active transparency + accent stroke on focus.
function Section:AddTextbox(o)
        o = o or {}
        local obj = { Type = "Textbox", Value = o.Default or "", Callback = o.Callback or function() end }
        local row = MakeRow(self, 34)
        RowLabel(row, o.Name or "Textbox", UDim2.new(.4, -12, 0, 34))
        local box = Create("TextBox", {
                AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -10, .5, 0), Size = UDim2.new(.6, -14, 0, 24),
                BackgroundTransparency = METRICS.FieldRest, Text = obj.Value, PlaceholderText = o.Placeholder or "...", ClearTextOnFocus = false,
                Font = FONT.Value, TextSize = SIZE.Small, ClipsDescendants = true,
                Theme = { BackgroundColor3 = "SurfaceAlt", TextColor3 = "Text", PlaceholderColor3 = "Faint" }, Parent = row,
        }, { CornerSm(), Stroke("Border", 1, METRICS.BorderT),
                Create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }) })
        local stroke = box:FindFirstChildOfClass("UIStroke")
        Library:Connect(box.MouseEnter, function() if not box:IsFocused() then
                Tween(box, { BackgroundTransparency = METRICS.FieldHov }, .15)
                Tween(stroke, { Transparency = METRICS.BorderT_Hov }, .15)
        end end)
        Library:Connect(box.MouseLeave, function() if not box:IsFocused() then
                Tween(box, { BackgroundTransparency = METRICS.FieldRest }, .15)
                Tween(stroke, { Transparency = METRICS.BorderT }, .15)
        end end)
        Library:Connect(box.Focused, function()
                Tween(box, { BackgroundTransparency = METRICS.FieldAct }, .15)
                Tween(stroke, { Transparency = 0.25, Color = Library.Theme.Accent }, .15)
        end)
        Library:Connect(box.FocusLost, function()
                Tween(box, { BackgroundTransparency = METRICS.FieldRest }, .15)
                Tween(stroke, { Transparency = METRICS.BorderT, Color = Library.Theme.Border }, .15)
                obj:Set(box.Text)
        end)
        function obj:Set(v, silent) self.Value = tostring(v); box.Text = self.Value; Library:_Fire(self, silent) end
        function obj:Get() return self.Value end
        Register(obj, o)
        return obj
end

-- ColorPicker: refined swatch (centered), better SV/Hue cursors, hairline border.
function Section:AddColorPicker(o)
        o = o or {}
        local obj = { Type = "ColorPicker", Callback = o.Callback or function() end }
        local h, s, v = (o.Default or WHITE):ToHSV()
        local row = MakeRow(self, 34)
        row.ClipsDescendants = true
        RowLabel(row, o.Name or "Color")
        local btn = RowButton(row)
        local swatch = Create("Frame", {
                AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -10, .5, 0), Size = UDim2.fromOffset(30, 16), Parent = row,
        }, { CornerSm(), Stroke("Border", 1, METRICS.BorderT) })

        local sv = Create("Frame", {
                Position = UDim2.fromOffset(10, 44), Size = UDim2.new(1, -46, 0, 110), ClipsDescendants = true, Parent = row,
        }, { Corner(METRICS.RadiusSm) })
        Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, Parent = sv }, {
                CornerSm(), Create("UIGradient", { Transparency = NumberSequence.new(0, 1) }),
        })
        Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, Parent = sv }, {
                CornerSm(), Create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0) }),
        })
        local cursor = Create("Frame", {
                AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = WHITE, ZIndex = 3, Parent = sv,
        }, { Round(), Create("UIStroke", { Thickness = 1.5, Color = BLACK }) })

        local keys = {}
        for i = 0, 6 do table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(math.min(i / 6, 1), 1, 1))) end
        local hue = Create("Frame", {
                Position = UDim2.new(1, -26, 0, 44), Size = UDim2.fromOffset(16, 110), BackgroundColor3 = WHITE, Parent = row,
        }, { CornerSm(), Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(keys) }) })
        local hcur = Create("Frame", {
                AnchorPoint = Vector2.new(.5, .5), Size = UDim2.new(1, 4, 0, 4), BackgroundColor3 = WHITE, Parent = hue,
        }, { CornerSm(), Create("UIStroke", { Thickness = 1, Color = BLACK }) })

        local hex = Create("TextBox", {
                Position = UDim2.fromOffset(10, 162), Size = UDim2.new(1, -20, 0, 24), BackgroundTransparency = METRICS.FieldRest, ClearTextOnFocus = false,
                Font = FONT.Value, TextSize = SIZE.Small, Theme = { BackgroundColor3 = "SurfaceAlt", TextColor3 = "Text" }, Parent = row,
        }, { CornerSm(), Stroke("Border", 1, METRICS.BorderT),
                Create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }) })

        local function render()
                local c = Color3.fromHSV(h, s, v)
                obj.Value = c
                swatch.BackgroundColor3 = c
                sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
                cursor.Position = UDim2.fromScale(s, 1 - v)
                hcur.Position = UDim2.fromScale(.5, h)
                hex.Text = string.format("#%02X%02X%02X", math.floor(c.R * 255 + .5), math.floor(c.G * 255 + .5), math.floor(c.B * 255 + .5))
        end
        function obj:Set(c, silent) h, s, v = c:ToHSV(); render(); Library:_Fire(self, silent) end
        function obj:Get() return self.Value end

        MakeDrag(sv, function(p)
                s = math.clamp((p.X - sv.AbsolutePosition.X) / sv.AbsoluteSize.X, 0, 1)
                v = 1 - math.clamp((p.Y - sv.AbsolutePosition.Y) / sv.AbsoluteSize.Y, 0, 1)
                render(); Library:_Fire(obj)
        end)
        MakeDrag(hue, function(p)
                h = math.clamp((p.Y - hue.AbsolutePosition.Y) / hue.AbsoluteSize.Y, 0, 1)
                render(); Library:_Fire(obj)
        end)
        Library:Connect(hex.FocusLost, function()
                local r, g, b = hex.Text:match("^#?(%x%x)(%x%x)(%x%x)$")
                if r then obj:Set(C3(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16))) else render() end
        end)
        local open = false
        Library:Connect(btn.MouseButton1Click, function()
                open = not open
                Tween(row, { Size = UDim2.new(1, 0, 0, open and 196 or 34) }, .3)
        end)
        Register(obj, o)
        render()
        Library:_Index((o.Name or "Color"), "Color", obj.Value and "ok" or "—", function() btn.MouseButton1Click:Fire() end)
        return obj
end

----------------------------------------------------------------------
-- window
----------------------------------------------------------------------
function Library:SetToggleKey(key)
        self.ToggleKey = key or Enum.KeyCode.RightShift
        if self.Window and self.Window.Hint then self.Window.Hint.Text = "Menu key\n" .. self.ToggleKey.Name end
end

function Library:CreateWindow(o)
        o = o or {}
        assert(not self.Window, "MonoUI: window already created")
        local gui = self:_Gui()
        local size = o.Size or UDim2.fromOffset(680, 480)
        local W, H = size.X.Offset, size.Y.Offset
        local TOP, FOOT, SIDE = METRICS.HeaderHeight, METRICS.FooterHeight, METRICS.RailWidth
        if o.ToggleKey then self.ToggleKey = o.ToggleKey end

        local Window = { Tabs = {}, Visible = true, Minimized = false }
        self.Window = Window

        local Root = Create("Frame", {
                Name = "Root", AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = size,
                BackgroundTransparency = 1, Parent = gui,
        }, { Create("UIScale", { Scale = .9 }) })
        local Scale = Root.UIScale

        -- Main: clipped body with surface gradient (Background -> Surface) for depth.
        local Main = Create("CanvasGroup", {
                Size = UDim2.fromScale(1, 1), GroupTransparency = 1, ClipsDescendants = true,
                Theme = { BackgroundColor3 = "Background" }, Parent = Root,
        }, { Corner(METRICS.Radius + 1) })
        Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, Parent = Main }, {
                Create("UIGradient", { Rotation = 135, Theme = { Color = { "Background", "Surface" } } }),
        })
        -- Outline stroke (transparent white/black) — luminous edge.
        local Outline = Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5, Parent = Root }, { Corner(METRICS.Radius + 1) })
        local OutlineStroke = Stroke("Border", 1, METRICS.BorderT - 0.04); OutlineStroke.Transparency = 1; OutlineStroke.Parent = Outline

        -- ===== header =====
        local Top = Create("Frame", { Size = UDim2.new(1, 0, 0, TOP), Theme = { BackgroundColor3 = "Surface" }, Parent = Main })
        -- hairline fade under header (1 -> 0 -> 1 transparency)
        Hairline(Top, { fade = true, edge = 0.12 })
        -- embossed brand square + title
        Create("Frame", {
                AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 16, .5, 0),
                Size = UDim2.fromOffset(22, 22), BackgroundColor3 = WHITE, Parent = Top,
        }, { Corner(METRICS.RadiusSm), Grad(45, "Accent", "Accent2") })
        EmbossText(Top, {
                text = o.Title or "MONO", position = UDim2.fromOffset(46, 0), size = UDim2.new(0, 260, 1, 0),
                textSize = SIZE.Title, font = FONT.Title,
        })
        local sub = Create("TextLabel", {
                AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -110, .5, 0), Size = UDim2.new(0, 80, 0, 14),
                Text = (o.Subtitle or "v2.0"), TextXAlignment = Enum.TextXAlignment.Right,
                Font = FONT.Micro, TextSize = SIZE.Micro, Theme = { TextColor3 = "Faint" }, Parent = Top,
        })
        -- header action buttons: search / minimize / close
        local function TopButton(x, glyph, key)
                local b = Create("TextButton", {
                        AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, x, .5, 0), Size = UDim2.fromOffset(28, 28),
                        BackgroundTransparency = .55, Text = glyph, Font = FONT.Gotham, TextSize = SIZE.Glyph,
                        Theme = { BackgroundColor3 = "SurfaceAlt", TextColor3 = "Text" }, Parent = Top,
                }, { CornerSm(), Stroke("Border", 1, METRICS.BorderT) })
                local st = b:FindFirstChildOfClass("UIStroke")
                Library:Connect(b.MouseEnter, function() Tween(st, { Transparency = METRICS.BorderT_Hov }, .15) end)
                Library:Connect(b.MouseLeave, function() Tween(st, { Transparency = METRICS.BorderT }, .15) end)
                return b, st
        end
        local btnSearch, btnSearchStroke = TopButton(-46, "?")
        local btnMin,     btnMinStroke     = TopButton(-80, "—")
        local btnClose,   btnCloseStroke   = TopButton(-12, "x")
        -- search button uses the "?" glyph; we trigger the palette on click.
        MakeDrag(Top, function(p)
                local d = p - Window._dragStart
                Root.Position = UDim2.new(Window._posStart.X.Scale, Window._posStart.X.Offset + d.X, Window._posStart.Y.Scale, Window._posStart.Y.Offset + d.Y)
        end, function(p) Window._dragStart = p; Window._posStart = Root.Position end)

        -- ===== body =====
        local Body = Create("Frame", { Position = UDim2.fromOffset(0, TOP), Size = UDim2.new(1, 0, 1, -TOP - FOOT), BackgroundTransparency = 1, Parent = Main })
        local Side = Create("Frame", { Size = UDim2.new(0, SIDE, 1, 0), BackgroundTransparency = .35, Theme = { BackgroundColor3 = "Surface" }, Parent = Body })
        Hairline(Side, { vertical = true, fade = true, edge = 0.06, position = UDim2.fromScale(1, 0), anchor = Vector2.new(1, 0) })
        local TabList = Create("ScrollingFrame", {
                Size = UDim2.new(1, 0, 1, -64), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = Side,
        }, {
                Create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
                Create("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 14) }),
        })
        Window.Hint = Create("TextLabel", {
                AnchorPoint = Vector2.new(.5, 1), Position = UDim2.new(.5, 0, 1, -10), Size = UDim2.new(1, -20, 0, 36),
                Text = "Menu key\n" .. self.ToggleKey.Name, TextSize = SIZE.Micro, Font = FONT.Micro,
                Theme = { TextColor3 = "Faint" }, Parent = Side,
        })
        local Pages = Create("Frame", { Position = UDim2.fromOffset(SIDE, 0), Size = UDim2.new(1, -SIDE, 1, 0), BackgroundTransparency = 1, ClipsDescendants = true, Parent = Body })

        -- ===== footer =====
        local Foot = Create("Frame", {
                AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, FOOT),
                Theme = { BackgroundColor3 = "Surface" }, Parent = Main,
        })
        Hairline(Foot, { fade = true, edge = 0.12, position = UDim2.fromScale(0, 0), anchor = Vector2.new(0, 0) })
        Create("TextLabel", {
                Position = UDim2.fromOffset(16, 0), Size = UDim2.new(.5, -16, 1, 0), Text = "MONO UI",
                TextXAlignment = Enum.TextXAlignment.Left, Font = FONT.Micro, TextSize = SIZE.Micro,
                Theme = { TextColor3 = "Faint" }, Parent = Foot,
        })
        local footRight = Create("TextLabel", {
                AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0), Size = UDim2.new(.5, -16, 1, 0),
                Text = "Theme: " .. self.ThemeName, TextXAlignment = Enum.TextXAlignment.Right,
                Font = FONT.Micro, TextSize = SIZE.Micro, Theme = { TextColor3 = "Faint" }, Parent = Foot,
        })
        self._FooterThemeLabel = footRight

        -- ===== visibility / minimize =====
        function Window:SetVisible(v)
                self.Visible = v
                if v then
                        Root.Visible = true
                        Tween(Scale, { Scale = 1 }, .4, Enum.EasingStyle.Back)
                        Tween(Main, { GroupTransparency = 0 }, .3)
                        Tween(OutlineStroke, { Transparency = METRICS.BorderT - 0.04 }, .3)
                else
                        Tween(Scale, { Scale = .92 }, .22)
                        Tween(Main, { GroupTransparency = 1 }, .22)
                        Tween(OutlineStroke, { Transparency = 1 }, .22)
                        task.delay(.24, function() if not self.Visible then Root.Visible = false end end)
                end
        end
        function Window:Toggle() self:SetVisible(not self.Visible) end
        function Window:SetMinimized(m)
                if self.Minimized == m then return end
                self.Minimized = m
                local p, shift = Root.Position, (H - TOP) / 2
                Tween(Root, {
                        Size = m and UDim2.fromOffset(W, TOP) or size,
                        Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset + (m and -shift or shift)),
                }, .35, Enum.EasingStyle.Quint)
        end
        Library:Connect(btnMin.MouseButton1Click, function() Window:SetMinimized(not Window.Minimized) end)
        Library:Connect(btnClose.MouseButton1Click, function()
                Window:SetVisible(false)
                Library:Notify({ Title = "UI hidden", Content = "Press " .. Library.ToggleKey.Name .. " to show it again", Duration = 3 })
        end)
        Library:Connect(btnSearch.MouseButton1Click, function() Library:_OpenSearch() end)
        Library:Connect(UIS.InputBegan, function(i, gpe)
                if gpe or Library.Listening then return end
                if i.KeyCode == Library.ToggleKey then Window:Toggle() end
                -- Ctrl+K opens command palette
                if i.KeyCode == Enum.KeyCode.K and (UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)) then
                        Library:_OpenSearch()
                end
        end)

        -- ===== tabs =====
        -- glow behind active tab marker + vertical bar
        local markerGlow = Create("Frame", {
                Name = "MarkerGlow", AnchorPoint = Vector2.new(0, .5), Position = UDim2.fromOffset(0, 0),
                Size = UDim2.fromOffset(22, 28), BackgroundTransparency = 1, Visible = false, ZIndex = 4, Parent = Side,
        }, { Corner(METRICS.RadiusSm), Theme = { BackgroundColor3 = "Accent" },
                Create("UIGradient", { Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }) }),
        })

        function Window:SelectTab(tab)
                if self.Current == tab then return end
                local old = self.Current
                self.Current = tab
                if old then
                        old:SetActive(false)
                        Tween(old.Page, { GroupTransparency = 1 }, .15)
                        task.delay(.16, function() if self.Current ~= old then old.Page.Visible = false end end)
                end
                tab:SetActive(true)
                tab.Page.Position = UDim2.fromOffset(0, 16)
                tab.Page.Visible = true
                -- move glow + marker to the active tab
                local tabPos = tab.Button.AbsolutePosition.Y - Side.AbsolutePosition.Y
                local tabSize = tab.Button.AbsoluteSize.Y
                Tween(markerGlow, { Position = UDim2.fromOffset(0, tabPos + tabSize / 2), BackgroundTransparency = 0.6 }, .25, Enum.EasingStyle.Quint)
                task.delay(old and .1 or 0, function()
                        if self.Current ~= tab then return end
                        Tween(tab.Page, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) }, .35)
                end)
        end

        function Window:AddTab(name)
                local Tab = { Name = name, Active = false, _count = { Left = 0, Right = 0 } }
                local btn = Create("TextButton", {
                        Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = #self.Tabs + 1,
                        Theme = { BackgroundColor3 = "Accent" }, Parent = TabList,
                }, { Corner(METRICS.RadiusSm), Create("UIScale", { Scale = 1 }) })
                local btnScale = btn:FindFirstChildOfClass("UIScale")
                -- vertical accent bar (left)
                local ind = Create("Frame", {
                        AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 0, .5, 0), Size = UDim2.fromOffset(3, 0),
                        BackgroundColor3 = WHITE, Parent = btn,
                }, { Round(), Grad(90, "Accent", "Accent2") })
                local lbl = Create("TextLabel", {
                        Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -14, 1, 0), Text = name, TextXAlignment = Enum.TextXAlignment.Left,
                        Font = FONT.Body, TextSize = SIZE.Body, TextColor3 = Library.Theme.Muted, Parent = btn,
                })
                function Tab:SetActive(a)
                        self.Active = a
                        Tween(btn, { BackgroundTransparency = a and .9 or 1 }, .2)
                        Tween(ind, { Size = UDim2.fromOffset(3, a and 16 or 0) }, .25, Enum.EasingStyle.Back)
                        Tween(lbl, { TextColor3 = a and Library.Theme.Text or Library.Theme.Muted }, .2)
                        if a then
                                Tween(btnScale, { Scale = 1.02 }, .15, Enum.EasingStyle.Back)
                                task.delay(.15, function() if self.Active then Tween(btnScale, { Scale = 1 }, .15) end end)
                        end
                end
                Tab.Button = btn
                Library:Hook(btn, function() Tab:SetActive(Tab.Active) end)
                Library:Connect(btn.MouseEnter, function()
                        if not Tab.Active then
                                Tween(lbl, { TextColor3 = Library.Theme.Text }, .15)
                                Tween(btn, { BackgroundTransparency = .97 }, .15)
                                Tween(btnScale, { Scale = 1.02 }, .15, Enum.EasingStyle.Back)
                        end
                end)
                Library:Connect(btn.MouseLeave, function()
                        if not Tab.Active then
                                Tween(lbl, { TextColor3 = Library.Theme.Muted }, .15)
                                Tween(btn, { BackgroundTransparency = 1 }, .15)
                                Tween(btnScale, { Scale = 1 }, .15)
                        end
                end)
                Library:Connect(btn.MouseButton1Click, function() Window:SelectTab(Tab) end)

                Tab.Page = Create("CanvasGroup", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, GroupTransparency = 1, Visible = false, Parent = Pages })
                local function Column(x)
                        return Create("ScrollingFrame", {
                                Size = UDim2.fromScale(.5, 1), Position = UDim2.fromScale(x, 0), CanvasSize = UDim2.new(),
                                AutomaticCanvasSize = Enum.AutomaticSize.Y, Theme = { ScrollBarImageColor3 = "Faint" }, Parent = Tab.Page,
                        }, {
                                Create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
                                Create("UIPadding", {
                                        PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14),
                                        PaddingLeft = UDim.new(0, x == 0 and 14 or 7), PaddingRight = UDim.new(0, x == 0 and 7 or 14),
                                }),
                        })
                end
                Tab.Left, Tab.Right = Column(0), Column(.5)

                function Tab:AddSection(title, side)
                        if side ~= "Left" and side ~= "Right" then
                                side = (self._count.Left <= self._count.Right) and "Left" or "Right"
                        end
                        self._count[side] += 1
                        local frame = Create("Frame", {
                                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                                Theme = { BackgroundColor3 = "Surface" }, Parent = self[side],
                        }, {
                                Corner(METRICS.Radius), Stroke("Border", 1, METRICS.BorderT),
                                Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
                                Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }),
                        })
                        Create("TextLabel", {
                                Size = UDim2.new(1, 0, 0, 28), Text = string.upper(title or "Section"), TextXAlignment = Enum.TextXAlignment.Left,
                                Font = FONT.Micro, TextSize = SIZE.Micro, Theme = { TextColor3 = "Faint" }, Parent = frame,
                        }, { Create("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingTop = UDim.new(0, 6) }) })
                        local sec = setmetatable({ Content = frame, Tab = self }, Section)
                        Library:_Index((title or "Section"), "Section", nil, function() Window:SelectTab(self) end)
                        return sec
                end

                table.insert(self.Tabs, Tab)
                if not self.Current then
                        self.Current = Tab
                        task.defer(function()
                                if Window.Current ~= Tab then return end
                                Tab:SetActive(true)
                                Tab.Page.Visible = true
                                Tween(Tab.Page, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) }, .35)
                                local tabPos = btn.AbsolutePosition.Y - Side.AbsolutePosition.Y
                                local tabSize = btn.AbsoluteSize.Y
                                markerGlow.Visible = true
                                Tween(markerGlow, { Position = UDim2.fromOffset(0, tabPos + tabSize / 2), BackgroundTransparency = 0.6 }, .25, Enum.EasingStyle.Quint)
                        end)
                end
                return Tab
        end

        -- ===== settings tab: theme manager, menu key, unload, configs, palette editor =====
        function Window:AddSettingsTab(name)
                local Tab = self:AddTab(name or "Settings")
                local ui = Tab:AddSection("Interface", "Left")
                local names = {}
                for n in pairs(Library.Themes) do table.insert(names, n) end
                table.sort(names)
                ui:AddDropdown({ Name = "Theme", Options = names, Default = Library.ThemeName, Flag = "MonoUI_Theme", Ignore = true,
                        Callback = function(v) Library:SetTheme(v); if Library._FooterThemeLabel then Library._FooterThemeLabel.Text = "Theme: " .. v end end })

                local cfg = Tab:AddSection("Config", "Left")
                local nameBox = cfg:AddTextbox({ Name = "Name", Default = "default", Placeholder = "config name", Flag = "MonoUI_CfgName", Ignore = true })
                cfg:AddButton({ Name = "Save config", Callback = function()
                        local ok, err = Library:SaveConfig(nameBox.Value)
                        Library:Notify({ Title = ok and "Config saved" or "Save failed", Content = ok and nameBox.Value or tostring(err), Duration = 3 })
                end })
                cfg:AddButton({ Name = "Load config", Callback = function()
                        local ok, err = Library:LoadConfig(nameBox.Value)
                        Library:Notify({ Title = ok and "Config loaded" or "Load failed", Content = ok and nameBox.Value or tostring(err), Duration = 3 })
                end })

                local keys = Tab:AddSection("Keys & window", "Left")
                keys:AddKeybind({ Name = "Menu key", Default = Library.ToggleKey, Flag = "MonoUI_MenuKey", Ignore = true,
                        Changed = function(k) Library:SetToggleKey(k) end })
                keys:AddButton({ Name = "Minimize / restore", Callback = function() Window:SetMinimized(not Window.Minimized) end })
                keys:AddButton({ Name = "Open command palette", Callback = function() Library:_OpenSearch() end })
                keys:AddButton({ Name = "Unload UI", Callback = function() Library:Unload() end })

                -- palette editor (every theme token gets a color picker)
                local ed = Tab:AddSection("Palette editor", "Right")
                local order = { "Background", "Surface", "SurfaceAlt", "Elevated", "Border", "Line", "Text", "Muted", "Faint", "Accent", "Accent2", "OnAccent", "ToggleOn", "ToggleKnob", "Success", "Warning", "Danger", "Info" }
                for _, key in ipairs(order) do
                        Library.ThemePickers[key] = ed:AddColorPicker({
                                Name = key, Default = Library.Theme[key], Flag = "MonoUI_Theme_" .. key, Ignore = true,
                                Callback = function(c) Library.Theme[key] = c; Library:RefreshTheme(true) end,
                        })
                end
                -- import / export
                local io = Tab:AddSection("Share theme", "Right")
                io:AddButton({ Name = "Copy theme as JSON", Callback = function()
                        local s = Library:ExportTheme()
                        if setclipboard then setclipboard(s); Library:Notify({ Title = "Theme copied", Content = "JSON is on your clipboard", Duration = 3 })
                        else Library:Notify({ Title = "Clipboard unavailable", Content = "setclipboard not present in this executor", Duration = 4 }) end
                end })
                local imp = io:AddTextbox({ Name = "Paste theme JSON", Placeholder = '{"Background":"#0a0a0a",...}', Flag = "MonoUI_ThemeJSON", Ignore = true })
                imp:Set("")
                io:AddButton({ Name = "Apply pasted theme", Callback = function()
                        local ok = Library:ImportTheme(imp:Get())
                        Library:Notify({ Title = ok and "Theme applied" or "Import failed", Content = ok and "Palette updated" or "Bad JSON", Duration = 3 })
                end })
                return Tab
        end

        Window.Root = Root
        task.defer(function() Window:SetVisible(true) end)
        return Window
end

----------------------------------------------------------------------
-- command palette (fuzzy search across all indexed elements)
----------------------------------------------------------------------
function Library:_OpenSearch()
        if self._SearchOpen then return end
        self._SearchOpen = true
        self:_Gui()
        local gui = self.Gui

        local overlay = Create("Frame", {
                Name = "SearchOverlay", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui,
        }, { Create("UIScale", { Scale = .96 }) })
        local scale = overlay.UIScale

        local card = Create("CanvasGroup", {
                AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, 0, 80), Size = UDim2.fromOffset(480, 360),
                GroupTransparency = 1, Theme = { BackgroundColor3 = "Surface" }, ClipsDescendants = true, Parent = overlay,
        }, { Corner(METRICS.Radius + 1), Stroke("Border", 1, METRICS.BorderT - 0.04) })
        Glow(card, { size = UDim2.new(1, 0, 0, 2), position = UDim2.fromScale(0, 0), anchor = Vector2.new(0, 0), zindex = 4 })

        local input = Create("TextBox", {
                Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = .55,
                Text = "", PlaceholderText = "Search elements...", ClearTextOnFocus = false,
                Font = FONT.Title, TextSize = SIZE.Heading, TextXAlignment = Enum.TextXAlignment.Left,
                Theme = { BackgroundColor3 = "SurfaceAlt", TextColor3 = "Text", PlaceholderColor3 = "Faint" }, Parent = card,
        }, { Corner(METRICS.Radius + 1),
                Create("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }),
        })
        Hairline(input, { fade = true, edge = 0.1, position = UDim2.fromScale(0, 1), anchor = Vector2.new(0, 1) })

        local list = Create("ScrollingFrame", {
                Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40), CanvasSize = UDim2.new(),
                AutomaticCanvasSize = Enum.AutomaticSize.Y, Theme = { ScrollBarImageColor3 = "Faint" }, Parent = card,
        }, { Create("UIListLayout", { Padding = UDim.new(0, 1), SortOrder = Enum.SortOrder.LayoutOrder }),
                Create("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }) })

        local items = {}
        local function rebuild(query)
                for _, it in ipairs(items) do it:Destroy() end
                items = {}
                local scored = {}
                for _, e in ipairs(self.SearchIndex) do
                        local s = fuzzyMatch(query or "", e.Label .. " " .. (e.Hint or "") .. " " .. (e.Kind or ""))
                        if s then table.insert(scored, { entry = e, score = s }) end
                end
                table.sort(scored, function(a, b) return a.score < b.score end)
                local limit = math.min(#scored, 12)
                for i = 1, limit do
                        local sc = scored[i]
                        local e = sc.entry
                        local row = Create("TextButton", {
                                LayoutOrder = i, Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1,
                                Text = "", Font = FONT.Body, TextSize = SIZE.Body, Parent = list,
                        }, { CornerSm(),
                                Create("TextLabel", {
                                        Position = UDim2.fromOffset(12, 0), Size = UDim2.new(.55, -12, 1, 0), Text = e.Label,
                                        TextXAlignment = Enum.TextXAlignment.Left, Font = FONT.Body, TextSize = SIZE.Body,
                                        Theme = { TextColor3 = "Text" }, Parent = row,
                                }),
                                Create("TextLabel", {
                                        Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -12, 1, 0), Text = (e.Hint or ""),
                                        TextXAlignment = Enum.TextXAlignment.Right, Font = FONT.Micro, TextSize = SIZE.Micro,
                                        Theme = { TextColor3 = "Faint" }, Parent = row,
                                }),
                                Create("UIStroke", { Thickness = 1, Transparency = 1, Theme = { Color = "Border" } }),
                        })
                        local stroke = row:FindFirstChildOfClass("UIStroke")
                        Library:Connect(row.MouseEnter, function() Tween(row, { BackgroundTransparency = .55 }, .1); Tween(stroke, { Transparency = METRICS.BorderT_Hov }, .1) end)
                        Library:Connect(row.MouseLeave, function() Tween(row, { BackgroundTransparency = 1 }, .1); Tween(stroke, { Transparency = 1 }, .1) end)
                        Library:Connect(row.MouseButton1Click, function()
                                local ok = pcall(e.Activate)
                                self:_CloseSearch()
                        end)
                        table.insert(items, row)
                end
        end
        rebuild("")

        Library:Connect(input:GetPropertyChangedSignal("Text"), function() rebuild(input.Text) end)

        function self:_CloseSearch()
                if not self._SearchOpen then return end
                self._SearchOpen = false
                Tween(scale, { Scale = .96 }, .15)
                Tween(card, { GroupTransparency = 1 }, .15)
                task.delay(.16, function() if overlay.Parent then overlay:Destroy() end end)
        end

        Library:Connect(UIS.InputBegan, function(i, gpe)
                if i.KeyCode == Enum.KeyCode.Escape then self:_CloseSearch() end
        end)

        Tween(scale, { Scale = 1 }, .25, Enum.EasingStyle.Back)
        Tween(card, { GroupTransparency = 0 }, .2)
        task.defer(function() input:CaptureFocus() end)
end

----------------------------------------------------------------------
-- unload
----------------------------------------------------------------------
function Library:Unload(instant)
        if self.Unloaded then return end
        self.Unloaded = true
        for _, cb in ipairs(self.UnloadCallbacks) do pcall(cb) end
        local function destroy()
                for _, c in ipairs(self.Connections) do pcall(function() c:Disconnect() end) end
                table.clear(self.Connections)
                if self.Gui then self.Gui:Destroy() end
                table.clear(self.Registry); table.clear(self.Hooks)
                if genv.MonoUI == self then genv.MonoUI = nil end
        end
        if instant or not self.Window then
                destroy()
        else
                self.Window:SetVisible(false)
                task.delay(.35, destroy)
        end
end

genv.MonoUI = Library
return Library
