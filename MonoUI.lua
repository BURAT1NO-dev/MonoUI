--[[
	MONO UI — Roblox UI library (Luau)
	Black & white, gradients, animations, tabs, theme manager, notifications,
	toggles / checkboxes / buttons / sliders / dropdowns / keybinds / 2D color pickers / textboxes.
	Hide / minimize / unload, config save & load (if the executor has a filesystem).
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

local Library = {
	Flags = {}, Options = {}, Registry = {}, Hooks = {}, Connections = {}, UnloadCallbacks = {},
	ThemePickers = {}, Folder = "MonoUI", ToggleKey = Enum.KeyCode.RightShift,
	Listening = false, Unloaded = false, _n = 0,
}

Library.Themes = {
	["Mono Dark"] = {
		Background = C3(10, 10, 10), Panel = C3(16, 16, 16), Element = C3(24, 24, 24), Border = C3(42, 42, 42),
		Text = C3(242, 242, 242), SubText = C3(150, 150, 150), Accent = C3(255, 255, 255), Accent2 = C3(160, 160, 160), OnAccent = C3(10, 10, 10),
	},
	["Mono Light"] = {
		Background = C3(236, 236, 236), Panel = C3(246, 246, 246), Element = C3(228, 228, 228), Border = C3(200, 200, 200),
		Text = C3(16, 16, 16), SubText = C3(95, 95, 95), Accent = C3(16, 16, 16), Accent2 = C3(90, 90, 90), OnAccent = C3(245, 245, 245),
	},
	["Graphite"] = {
		Background = C3(14, 14, 16), Panel = C3(20, 20, 23), Element = C3(29, 29, 33), Border = C3(48, 48, 54),
		Text = C3(235, 235, 238), SubText = C3(140, 140, 150), Accent = C3(225, 225, 232), Accent2 = C3(120, 120, 135), OnAccent = C3(14, 14, 16),
	},
	["OLED"] = {
		Background = C3(0, 0, 0), Panel = C3(6, 6, 6), Element = C3(15, 15, 15), Border = C3(34, 34, 34),
		Text = C3(255, 255, 255), SubText = C3(130, 130, 130), Accent = C3(255, 255, 255), Accent2 = C3(110, 110, 110), OnAccent = C3(0, 0, 0),
	},
}
Library.ThemeName = "Mono Dark"
Library.Theme = {}
for k, v in pairs(Library.Themes["Mono Dark"]) do Library.Theme[k] = v end

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local TEXT = { TextLabel = true, TextButton = true, TextBox = true }

local function Create(class, props, children)
	local o = Instance.new(class)
	if o:IsA("GuiObject") then o.BorderSizePixel = 0 end
	if TEXT[class] then
		o.BackgroundTransparency = 1; o.Font = Enum.Font.Gotham; o.TextSize = 13; o.Text = ""
	end
	if class == "TextButton" then o.AutoButtonColor = false end
	if class == "ScrollingFrame" then o.ScrollBarThickness = 2; o.BackgroundTransparency = 1 end
	local theme, parent
	for k, v in pairs(props or {}) do
		if k == "Theme" then theme = v elseif k == "Parent" then parent = v else o[k] = v end
	end
	for _, c in ipairs(children or {}) do c.Parent = o end
	if theme then Library:Themed(o, theme) end
	o.Parent = parent
	return o
end

local function Corner(r) return Create("UICorner", { CornerRadius = UDim.new(0, r) }) end
local function Round() return Create("UICorner", { CornerRadius = UDim.new(1, 0) }) end
local function Stroke(key, th) return Create("UIStroke", { Thickness = th or 1, Theme = { Color = key or "Border" } }) end
local function Grad(rot) return Create("UIGradient", { Rotation = rot or 0, Theme = { Color = { "Accent", "Accent2" } } }) end

local function Tween(o, goal, t, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t or .2, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

local function resolve(key)
	if type(key) == "table" then return ColorSequence.new(Library.Theme[key[1]], Library.Theme[key[2]]) end
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
	for key, picker in pairs(self.ThemePickers) do picker:Set(self.Theme[key], true) end
end

function Library:RegisterTheme(name, tbl)
	local t = {}
	for k, v in pairs(self.Themes["Mono Dark"]) do t[k] = tbl[k] or v end
	self.Themes[name] = t
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
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16), Size = UDim2.new(0, 264, 1, -32),
		BackgroundTransparency = 1, Parent = gui,
	}, { Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 8) }) })
	return gui
end

----------------------------------------------------------------------
-- notifications
----------------------------------------------------------------------
function Library:Notify(o)
	if type(o) == "string" then o = { Content = o } end
	self:_Gui()
	self._n += 1
	local dur = o.Duration or 4
	local holder = Create("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
		LayoutOrder = self._n, Parent = self.NotifyHolder,
	})
	local card = Create("CanvasGroup", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.new(0, 40, 0, 0),
		GroupTransparency = 1, Theme = { BackgroundColor3 = "Panel" }, Parent = holder,
	}, { Corner(10), Stroke("Border") })
	local inner = Create("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = card,
	}, {
		Create("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
		Create("UIPadding", { PaddingTop = UDim.new(0, 11), PaddingBottom = UDim.new(0, 11), PaddingLeft = UDim.new(0, 13), PaddingRight = UDim.new(0, 13) }),
	})
	Create("TextLabel", {
		LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamBold, TextSize = 13, Text = o.Title or "Notification",
		Theme = { TextColor3 = "Text" }, Parent = inner,
	})
	if o.Content and o.Content ~= "" then
		Create("TextLabel", {
			LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextSize = 12, Text = o.Content,
			Theme = { TextColor3 = "SubText" }, Parent = inner,
		})
	end
	local track = Create("Frame", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 2), Theme = { BackgroundColor3 = "Border" }, Parent = inner }, { Round() })
	local fill = Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, Parent = track }, { Round(), Grad(0) })

	Tween(card, { Position = UDim2.new(0, 0, 0, 0), GroupTransparency = 0 }, .45, Enum.EasingStyle.Back)
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
	for k, c in pairs(data.Theme or {}) do
		if self.Theme[k] and type(c) == "table" then self.Theme[k] = Color3.new(c.R, c.G, c.B) end
	end
	self:RefreshTheme()
	for key, picker in pairs(self.ThemePickers) do picker:Set(self.Theme[key], true) end
	return true
end

----------------------------------------------------------------------
-- element helpers
----------------------------------------------------------------------
local Section = {}
Section.__index = Section

local function MakeRow(sec, h)
	return Create("Frame", {
		Size = UDim2.new(1, 0, 0, h), Theme = { BackgroundColor3 = "Element" }, Parent = sec.Content,
	}, { Corner(8) })
end

local function RowLabel(row, text, w)
	return Create("TextLabel", {
		Text = text, Position = UDim2.fromOffset(10, 0), Size = w or UDim2.new(1, -20, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamMedium, TextSize = 13,
		TextTruncate = Enum.TextTruncate.AtEnd, Theme = { TextColor3 = "Text" }, Parent = row,
	})
end

local function RowButton(row)
	local btn = Create("TextButton", { Size = UDim2.new(1, 0, 0, 34), Parent = row })
	Library:Connect(btn.MouseEnter, function() Tween(row, { BackgroundColor3 = Library.Theme.Border }, .15) end)
	Library:Connect(btn.MouseLeave, function() Tween(row, { BackgroundColor3 = Library.Theme.Element }, .15) end)
	return btn
end

function Section:AddLabel(text)
	local row = MakeRow(self, 28)
	local lbl = Create("TextLabel", {
		Text = text, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextSize = 12, Theme = { TextColor3 = "SubText" }, Parent = row,
	})
	return { SetText = function(_, t) lbl.Text = t end }
end

function Section:AddButton(o)
	o = o or {}
	local obj = { Type = "Button" }
	local row = Create("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = WHITE, Parent = self.Content }, {
		Corner(8), Create("UIScale"),
	})
	local grad = Grad(0); grad.Parent = row
	local scale = row:FindFirstChildOfClass("UIScale")
	local btn = Create("TextButton", {
		Size = UDim2.fromScale(1, 1), Text = o.Name or "Button", Font = Enum.Font.GothamBold, TextSize = 13,
		Theme = { TextColor3 = "OnAccent" }, Parent = row,
	})
	Library:Connect(btn.MouseEnter, function() Tween(grad, { Rotation = 35 }, .3) end)
	Library:Connect(btn.MouseLeave, function() Tween(grad, { Rotation = 0 }, .3) end)
	Library:Connect(btn.MouseButton1Down, function() Tween(scale, { Scale = .96 }, .08) end)
	Library:Connect(btn.MouseButton1Up, function() Tween(scale, { Scale = 1 }, .15, Enum.EasingStyle.Back) end)
	Library:Connect(btn.MouseLeave, function() Tween(scale, { Scale = 1 }, .15) end)
	Library:Connect(btn.MouseButton1Click, function()
		if o.Callback then task.spawn(o.Callback) end
	end)
	function obj:SetText(t) btn.Text = t end
	return obj
end

function Section:AddToggle(o)
	o = o or {}
	local obj = { Type = "Toggle", Value = o.Default == true, Callback = o.Callback or function() end }
	local row = MakeRow(self, 34)
	RowLabel(row, o.Name or "Toggle")
	local btn = RowButton(row)
	local track = Create("Frame", {
		AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -10, .5, 0), Size = UDim2.fromOffset(36, 18),
		Theme = { BackgroundColor3 = "Border" }, Parent = row,
	}, { Round() })
	local fill = Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, Parent = track }, { Round(), Grad(0) })
	local knob = Create("Frame", {
		AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 3, .5, 0), Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = Library.Theme.SubText, Parent = track,
	}, { Round() })
	local function render(instant)
		local on, t = obj.Value, instant and 0 or .22
		Tween(knob, {
			Position = on and UDim2.new(1, -15, .5, 0) or UDim2.new(0, 3, .5, 0),
			BackgroundColor3 = on and Library.Theme.OnAccent or Library.Theme.SubText,
		}, t)
		Tween(fill, { BackgroundTransparency = on and 0 or 1 }, t)
	end
	function obj:Set(v, silent) self.Value = v and true or false; render(); Library:_Fire(self, silent) end
	function obj:Get() return self.Value end
	Library:Hook(row, function() render(true) end)
	Library:Connect(btn.MouseButton1Click, function() obj:Set(not obj.Value) end)
	Register(obj, o)
	render(true)
	return obj
end

function Section:AddCheckbox(o)
	o = o or {}
	local obj = { Type = "Checkbox", Value = o.Default == true, Callback = o.Callback or function() end }
	local row = MakeRow(self, 34)
	RowLabel(row, o.Name or "Checkbox")
	local btn = RowButton(row)
	local box = Create("Frame", {
		AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -10, .5, 0), Size = UDim2.fromOffset(18, 18),
		Theme = { BackgroundColor3 = "Border" }, Parent = row,
	}, { Corner(5) })
	local mark = Create("Frame", {
		AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.fromOffset(0, 0),
		BackgroundColor3 = WHITE, Parent = box,
	}, { Corner(3), Grad(45) })
	local function render(instant)
		Tween(mark, { Size = obj.Value and UDim2.fromOffset(10, 10) or UDim2.fromOffset(0, 0) }, instant and 0 or .2, Enum.EasingStyle.Back)
	end
	function obj:Set(v, silent) self.Value = v and true or false; render(); Library:_Fire(self, silent) end
	function obj:Get() return self.Value end
	Library:Connect(btn.MouseButton1Click, function() obj:Set(not obj.Value) end)
	Register(obj, o)
	render(true)
	return obj
end

function Section:AddSlider(o)
	o = o or {}
	local min, max, inc = o.Min or 0, o.Max or 100, o.Increment or 1
	local dec = #(tostring(inc):match("%.(%d+)") or "")
	local obj = { Type = "Slider", Callback = o.Callback or function() end }
	local row = MakeRow(self, 46)
	local label = RowLabel(row, o.Name or "Slider", UDim2.new(.6, -10, 0, 28))
	label.Position = UDim2.fromOffset(10, 2)
	local val = Create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 2), Size = UDim2.new(.4, -10, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.GothamMedium, TextSize = 12,
		Theme = { TextColor3 = "SubText" }, Parent = row,
	})
	local hit = Create("Frame", { Position = UDim2.new(0, 10, 1, -24), Size = UDim2.new(1, -20, 0, 20), BackgroundTransparency = 1, Parent = row })
	local track = Create("Frame", {
		AnchorPoint = Vector2.new(0, .5), Position = UDim2.fromScale(0, .5), Size = UDim2.new(1, 0, 0, 4),
		Theme = { BackgroundColor3 = "Border" }, Parent = hit,
	}, { Round() })
	local fill = Create("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE, Parent = track }, { Round(), Grad(0) })
	local knob = Create("Frame", {
		AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(0, .5), Size = UDim2.fromOffset(12, 12),
		Theme = { BackgroundColor3 = "Accent" }, Parent = track,
	}, { Round() })

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
		Tween(fill, { Size = UDim2.fromScale(a, 1) }, .1)
		Tween(knob, { Position = UDim2.fromScale(a, .5) }, .1)
		val.Text = tostring(v) .. (o.Suffix or "")
		if changed or silent == false then Library:_Fire(self, silent) elseif obj.Flag then Library.Flags[obj.Flag] = v end
	end
	function obj:Get() return self.Value end
	MakeDrag(hit, function(p)
		local a = math.clamp((p.X - hit.AbsolutePosition.X) / hit.AbsoluteSize.X, 0, 1)
		obj:Set(min + (max - min) * a)
	end)
	Register(obj, o)
	obj:Set(o.Default or min, true)
	return obj
end

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
	RowLabel(row, o.Name or "Dropdown", UDim2.new(.45, -10, 0, 34))
	local valueLbl = Create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.new(.55, -14, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, TextSize = 12,
		Font = Enum.Font.GothamMedium, Theme = { TextColor3 = "SubText" }, Parent = row,
	})
	local btn = RowButton(row)
	local list = Create("ScrollingFrame", {
		Position = UDim2.new(0, 6, 0, 38), Size = UDim2.new(1, -12, 0, 0), CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, Theme = { ScrollBarImageColor3 = "SubText" }, Parent = row,
	}, { Create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }) })

	local buttons, open = {}, false
	local function listHeight()
		local n = math.min(#obj.Options, 6)
		return n * 26 + math.max(n - 1, 0) * 2
	end
	local function resize()
		local h = listHeight()
		Tween(row, { Size = UDim2.new(1, 0, 0, open and (34 + 4 + h + 6) or 34) }, .28)
		Tween(list, { Size = UDim2.new(1, -12, 0, h) }, .28)
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
			Tween(b, { TextColor3 = sel and Library.Theme.Text or Library.Theme.SubText, BackgroundTransparency = sel and 0 or 1 }, .15)
		end
	end
	local function build()
		for _, b in pairs(buttons) do b:Destroy() end
		buttons = {}
		for i, opt in ipairs(obj.Options) do
			local b = Create("TextButton", {
				LayoutOrder = i, Size = UDim2.new(1, -6, 0, 26), Text = opt, TextSize = 12, Font = Enum.Font.GothamMedium,
				TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
				Theme = { BackgroundColor3 = "Border" }, Parent = list,
			}, { Corner(6), Create("UIPadding", { PaddingLeft = UDim.new(0, 10) }) })
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
	return obj
end

function Section:AddKeybind(o)
	o = o or {}
	local obj = { Type = "Keybind", Value = o.Default, Callback = o.Callback or function() end }
	local row = MakeRow(self, 34)
	RowLabel(row, o.Name or "Keybind", UDim2.new(.5, -10, 0, 34))
	local btn = Create("TextButton", {
		AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -8, .5, 0), Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X, Font = Enum.Font.GothamMedium, TextSize = 12,
		BackgroundTransparency = 0, Theme = { BackgroundColor3 = "Border", TextColor3 = "Text" }, Parent = row,
	}, { Corner(6), Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }) })
	local listening = false
	local function render() btn.Text = listening and "..." or (obj.Value and obj.Value.Name or "None") end
	function obj:Set(key, silent)
		self.Value = key
		render()
		if self.Flag then Library.Flags[self.Flag] = key end
		if not silent and o.Changed then task.spawn(o.Changed, key) end
	end
	function obj:Get() return self.Value end
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
	return obj
end

function Section:AddTextbox(o)
	o = o or {}
	local obj = { Type = "Textbox", Value = o.Default or "", Callback = o.Callback or function() end }
	local row = MakeRow(self, 34)
	RowLabel(row, o.Name or "Textbox", UDim2.new(.4, -10, 0, 34))
	local box = Create("TextBox", {
		AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -8, .5, 0), Size = UDim2.new(.6, -12, 0, 24),
		BackgroundTransparency = 0, Text = obj.Value, PlaceholderText = o.Placeholder or "...", ClearTextOnFocus = false,
		TextSize = 12, ClipsDescendants = true,
		Theme = { BackgroundColor3 = "Border", TextColor3 = "Text", PlaceholderColor3 = "SubText" }, Parent = row,
	}, { Corner(6), Create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }) })
	function obj:Set(v, silent) self.Value = tostring(v); box.Text = self.Value; Library:_Fire(self, silent) end
	function obj:Get() return self.Value end
	Library:Connect(box.FocusLost, function() obj:Set(box.Text) end)
	Register(obj, o)
	return obj
end

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
	}, { Corner(5), Stroke("SubText") })

	local sv = Create("Frame", {
		Position = UDim2.fromOffset(10, 44), Size = UDim2.new(1, -46, 0, 110), ClipsDescendants = true, Parent = row,
	}, { Corner(6) })
	Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, Parent = sv }, {
		Corner(6), Create("UIGradient", { Transparency = NumberSequence.new(0, 1) }),
	})
	Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), Parent = sv }, {
		Corner(6), Create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0) }),
	})
	local cursor = Create("Frame", {
		AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = WHITE, ZIndex = 3, Parent = sv,
	}, { Round(), Create("UIStroke", { Thickness = 1.5, Color = Color3.new(0, 0, 0) }) })

	local keys = {}
	for i = 0, 6 do table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(math.min(i / 6, 1), 1, 1))) end
	local hue = Create("Frame", {
		Position = UDim2.new(1, -26, 0, 44), Size = UDim2.fromOffset(16, 110), BackgroundColor3 = WHITE, Parent = row,
	}, { Corner(6), Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(keys) }) })
	local hcur = Create("Frame", {
		AnchorPoint = Vector2.new(.5, .5), Size = UDim2.new(1, 4, 0, 4), BackgroundColor3 = WHITE, Parent = hue,
	}, { Corner(2), Create("UIStroke", { Thickness = 1, Color = Color3.new(0, 0, 0) }) })

	local hex = Create("TextBox", {
		Position = UDim2.fromOffset(10, 162), Size = UDim2.new(1, -20, 0, 24), BackgroundTransparency = 0, ClearTextOnFocus = false,
		TextSize = 12, Font = Enum.Font.GothamMedium, Theme = { BackgroundColor3 = "Border", TextColor3 = "Text" }, Parent = row,
	}, { Corner(6) })

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
	local size = o.Size or UDim2.fromOffset(660, 460)
	local W, H = size.X.Offset, size.Y.Offset
	local TOP, SIDE = 42, 150
	if o.ToggleKey then self.ToggleKey = o.ToggleKey end

	local Window = { Tabs = {}, Visible = true, Minimized = false }
	self.Window = Window

	local Root = Create("Frame", {
		Name = "Root", AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = size,
		BackgroundTransparency = 1, Parent = gui,
	}, { Create("UIScale", { Scale = .9 }) })
	local Scale = Root.UIScale

	local Main = Create("CanvasGroup", {
		Size = UDim2.fromScale(1, 1), GroupTransparency = 1, Theme = { BackgroundColor3 = "Background" }, Parent = Root,
	}, { Corner(12) })
	Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, Parent = Main }, {
		Create("UIGradient", { Rotation = 135, Theme = { Color = { "Background", "Panel" } } }),
	})
	local Outline = Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5, Parent = Root }, { Corner(12) })
	local OutlineStroke = Stroke("Border"); OutlineStroke.Transparency = 1; OutlineStroke.Parent = Outline

	-- top bar
	local Top = Create("Frame", { Size = UDim2.new(1, 0, 0, TOP), Theme = { BackgroundColor3 = "Panel" }, Parent = Main })
	Create("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1), Theme = { BackgroundColor3 = "Border" }, Parent = Top })
	Create("Frame", { Position = UDim2.fromOffset(14, 11), Size = UDim2.fromOffset(20, 20), BackgroundColor3 = WHITE, Parent = Top }, { Corner(6), Grad(45) })
	Create("TextLabel", {
		Position = UDim2.fromOffset(44, 0), Size = UDim2.new(0, 200, 1, 0), Text = o.Title or "MONO UI", TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamBold, TextSize = 14, Theme = { TextColor3 = "Text" }, Parent = Top,
	})
	local function TopButton(x, glyph)
		local b = Create("TextButton", {
			AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, x, .5, 0), Size = UDim2.fromOffset(28, 28), BackgroundTransparency = 0,
			Text = glyph, Font = Enum.Font.GothamBold, TextSize = 15, Theme = { BackgroundColor3 = "Element", TextColor3 = "Text" }, Parent = Top,
		}, { Corner(8) })
		Library:Connect(b.MouseEnter, function() Tween(b, { BackgroundColor3 = Library.Theme.Border }, .15) end)
		Library:Connect(b.MouseLeave, function() Tween(b, { BackgroundColor3 = Library.Theme.Element }, .15) end)
		return b
	end
	local btnClose, btnMin = TopButton(-12, "x"), TopButton(-46, "-")
	MakeDrag(Top, function(p)
		local d = p - Window._dragStart
		Root.Position = UDim2.new(Window._posStart.X.Scale, Window._posStart.X.Offset + d.X, Window._posStart.Y.Scale, Window._posStart.Y.Offset + d.Y)
	end, function(p) Window._dragStart = p; Window._posStart = Root.Position end)

	-- body
	local Body = Create("Frame", { Position = UDim2.fromOffset(0, TOP), Size = UDim2.new(1, 0, 1, -TOP), BackgroundTransparency = 1, Parent = Main })
	local Side = Create("Frame", { Size = UDim2.new(0, SIDE, 1, 0), BackgroundTransparency = 0.35, Theme = { BackgroundColor3 = "Panel" }, Parent = Body })
	Create("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 1, 1, 0), Theme = { BackgroundColor3 = "Border" }, Parent = Side })
	local TabList = Create("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -64), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = Side,
	}, {
		Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		Create("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 12) }),
	})
	Window.Hint = Create("TextLabel", {
		AnchorPoint = Vector2.new(.5, 1), Position = UDim2.new(.5, 0, 1, -10), Size = UDim2.new(1, -20, 0, 40),
		Text = "Menu key\n" .. self.ToggleKey.Name, TextSize = 11, Theme = { TextColor3 = "SubText" }, Parent = Side,
	})
	local Pages = Create("Frame", { Position = UDim2.fromOffset(SIDE, 0), Size = UDim2.new(1, -SIDE, 1, 0), BackgroundTransparency = 1, ClipsDescendants = true, Parent = Body })

	-- visibility / minimize
	function Window:SetVisible(v)
		self.Visible = v
		if v then
			Root.Visible = true
			Tween(Scale, { Scale = 1 }, .4, Enum.EasingStyle.Back)
			Tween(Main, { GroupTransparency = 0 }, .3)
			Tween(OutlineStroke, { Transparency = 0 }, .3)
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
	Library:Connect(UIS.InputBegan, function(i, gpe)
		if gpe or Library.Listening then return end
		if i.KeyCode == Library.ToggleKey then Window:Toggle() end
	end)

	-- tabs
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
		task.delay(old and .1 or 0, function()
			if self.Current ~= tab then return end
			Tween(tab.Page, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) }, .35)
		end)
	end

	function Window:AddTab(name)
		local Tab = { Name = name, Active = false, _count = { Left = 0, Right = 0 } }
		local btn = Create("TextButton", {
			Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = #self.Tabs + 1,
			Theme = { BackgroundColor3 = "Accent" }, Parent = TabList,
		}, { Corner(8) })
		local ind = Create("Frame", {
			AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 0, .5, 0), Size = UDim2.fromOffset(3, 0),
			BackgroundColor3 = WHITE, Parent = btn,
		}, { Round(), Grad(90) })
		local lbl = Create("TextLabel", {
			Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -14, 1, 0), Text = name, TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = Library.Theme.SubText, Parent = btn,
		})
		function Tab:SetActive(a)
			self.Active = a
			Tween(btn, { BackgroundTransparency = a and .9 or 1 }, .2)
			Tween(ind, { Size = UDim2.fromOffset(3, a and 16 or 0) }, .25, Enum.EasingStyle.Back)
			Tween(lbl, { TextColor3 = a and Library.Theme.Text or Library.Theme.SubText }, .2)
		end
		Library:Hook(btn, function() Tab:SetActive(Tab.Active) end)
		Library:Connect(btn.MouseEnter, function() if not Tab.Active then Tween(lbl, { TextColor3 = Library.Theme.Text }, .15) end end)
		Library:Connect(btn.MouseLeave, function() if not Tab.Active then Tween(lbl, { TextColor3 = Library.Theme.SubText }, .15) end end)
		Library:Connect(btn.MouseButton1Click, function() Window:SelectTab(Tab) end)

		Tab.Page = Create("CanvasGroup", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, GroupTransparency = 1, Visible = false, Parent = Pages })
		local function Column(x)
			return Create("ScrollingFrame", {
				Size = UDim2.fromScale(.5, 1), Position = UDim2.fromScale(x, 0), CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y, Theme = { ScrollBarImageColor3 = "Border" }, Parent = Tab.Page,
			}, {
				Create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
				Create("UIPadding", {
					PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12),
					PaddingLeft = UDim.new(0, x == 0 and 12 or 6), PaddingRight = UDim.new(0, x == 0 and 6 or 12),
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
				Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Theme = { BackgroundColor3 = "Panel" }, Parent = self[side],
			}, {
				Corner(10), Stroke("Border"),
				Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
				Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }),
			})
			Create("TextLabel", {
				Size = UDim2.new(1, 0, 0, 30), Text = string.upper(title or "Section"), TextXAlignment = Enum.TextXAlignment.Left,
				Font = Enum.Font.GothamBold, TextSize = 11, Theme = { TextColor3 = "SubText" }, Parent = frame,
			}, { Create("UIPadding", { PaddingLeft = UDim.new(0, 4) }) })
			return setmetatable({ Content = frame, Tab = self }, Section)
		end

		table.insert(self.Tabs, Tab)
		if not self.Current then self:SelectTab(Tab) end
		return Tab
	end

	-- built-in settings tab: theme manager, menu key, unload, configs
	function Window:AddSettingsTab(name)
		local Tab = self:AddTab(name or "Settings")
		local ui = Tab:AddSection("Interface", "Left")
		local names = {}
		for n in pairs(Library.Themes) do table.insert(names, n) end
		table.sort(names)
		ui:AddDropdown({ Name = "Theme", Options = names, Default = Library.ThemeName, Flag = "MonoUI_Theme", Ignore = true,
			Callback = function(v) Library:SetTheme(v) end })
		ui:AddKeybind({ Name = "Menu key", Default = Library.ToggleKey, Flag = "MonoUI_MenuKey", Ignore = true,
			Changed = function(k) Library:SetToggleKey(k) end })
		ui:AddButton({ Name = "Minimize / restore", Callback = function() Window:SetMinimized(not Window.Minimized) end })
		ui:AddButton({ Name = "Unload UI", Callback = function() Library:Unload() end })

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

		local ed = Tab:AddSection("Theme editor", "Right")
		for _, key in ipairs({ "Accent", "Accent2", "Background", "Panel", "Element", "Border", "Text", "SubText" }) do
			Library.ThemePickers[key] = ed:AddColorPicker({
				Name = key, Default = Library.Theme[key], Flag = "MonoUI_Theme_" .. key, Ignore = true,
				Callback = function(c) Library.Theme[key] = c; Library:RefreshTheme(true) end,
			})
		end
		return Tab
	end

	Window.Root = Root
	task.defer(function() Window:SetVisible(true) end)
	return Window
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
