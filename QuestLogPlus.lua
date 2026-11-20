-- Quest Log Plus  (World of Warcraft: Forever, interface 16001)
--
-- A stand-alone quest log window styled like the default one, with:
--   * a Show/Hide Map toggle (the world map opens docked beside the log)
--   * "+1,234 xp" on every quest
--   * completed quests painted green with a check mark and "Ready to turn in"
--   * Share mode / Abandon mode to batch-select quests
--
-- The default quest log is left untouched; this addon only takes over the
-- quest log key (L by default). "/qlp key" gives L back to the default log.

local ADDON_NAME = ...

BINDING_HEADER_QUESTLOGPLUS = "Quest Log Plus"
BINDING_NAME_QUESTLOGPLUS_TOGGLE = "Toggle Quest Log Plus"

local DEFAULTS = {
	showMap = false,          -- open the world map next to the log
	showLevel = true,         -- "[12] Quest name"
	completedFirst = true,    -- ready-to-turn-in quests sort to the top of each zone
	takeOverKey = true,       -- the quest log key opens this log instead of the default one
	hideDefaultMapPanel = true, -- close the map's own quest side panel when we open the map
	collapsed = {},
	pos = nil,
}

local FRAME_W, FRAME_H = 384, 600
local READY_ICON = "Interface\\RaidFrame\\ReadyCheck-Ready"
local FAILED_ICON = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local PLUS_TEX = "Interface\\Buttons\\UI-PlusButton-Up"
local MINUS_TEX = "Interface\\Buttons\\UI-MinusButton-Up"
local BOX_TEX = "Interface\\Buttons\\UI-CheckBox-Up"
local BOXCHECK_TEX = "Interface\\Buttons\\UI-CheckBox-Check"
local BOOK_ICON = "Interface\\Icons\\INV_Misc_Book_08"

local XP_COLOR = "|cff9fc8ff"
local GREEN = "|cff55ff55"
local GREY = "|cff9d9d9d"

local db
local frame, inset, listScroll, listContent, detailScroll, detailContent
local emptyText, headerText, mapButton
local rows = {}
local groups = {}
local questsByID = {}
local view = "list"        -- "list" | "detail"
local detailQuestID
local mode                 -- nil | "share" | "abandon"
local selected = {}
local busy = false         -- a batch share/abandon is running
local docked, openedMap = false, false
local buttons = {}
local detail = {}
local pendingAbandon

local Refresh, RequestRefresh, UpdateBottom

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Quest Log Plus|r: " .. tostring(msg))
end

local function Pass(ok, ...)
	if ok then return ... end
end

-- pcall wrapper: returns the function's results, or nothing if it is missing or errors.
local function SafeCall(fn, ...)
	if type(fn) ~= "function" then return end
	return Pass(pcall(fn, ...))
end

local function IsSecret(v)
	return issecretvalue and issecretvalue(v) or false
end

local function HasTemplate(name)
	if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
		return SafeCall(C_XMLUtil.GetTemplateInfo, name) ~= nil
	end
	return false
end

local function FirstTemplate(...)
	for i = 1, select("#", ...) do
		local t = select(i, ...)
		if HasTemplate(t) then return t end
	end
end

local function FormatNumber(n)
	if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
	return tostring(n)
end

local function CopyDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			CopyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

local function IconStr(tex, size)
	return ("|T%s:%d:%d|t"):format(tostring(tex), size, size)
end

local function LevelPercent(xp)
	local max = UnitXPMax and UnitXPMax("player") or 0
	if IsSecret(max) or type(max) ~= "number" or max <= 0 then return nil end
	return math.floor(xp / max * 100 + 0.5)
end

---------------------------------------------------------------------------
-- Quest data
---------------------------------------------------------------------------

local function GetQuestXP(questID)
	local xp = SafeCall(GetQuestLogRewardXP, questID)
	if IsSecret(xp) or type(xp) ~= "number" then return 0 end
	return xp
end

local function GetQuestState(questID)
	if SafeCall(C_QuestLog.IsFailed, questID) then return "failed" end
	if SafeCall(C_QuestLog.ReadyForTurnIn, questID) or SafeCall(C_QuestLog.IsComplete, questID) then
		return "complete"
	end
	return "active"
end

local function GetObjectives(questID)
	local list = SafeCall(C_QuestLog.GetQuestObjectives, questID)
	return type(list) == "table" and list or {}
end

local function QuestColor(q)
	if C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer and GetDifficultyColor then
		local diff = SafeCall(C_PlayerInfo.GetContentDifficultyQuestForPlayer, q.questID)
		local c = diff and SafeCall(GetDifficultyColor, diff)
		if type(c) == "table" and c.r then return c.r, c.g, c.b end
	end
	if GetQuestDifficultyColor and q.level then
		local c = SafeCall(GetQuestDifficultyColor, q.level)
		if type(c) == "table" and c.r then return c.r, c.g, c.b end
	end
	return 1, 0.82, 0
end

local function QuestTitle(q)
	if db.showLevel and q.level and q.level > 0 then
		return ("[%d] %s"):format(q.level, q.title or "?")
	end
	return q.title or "?"
end

-- The default log can collapse zone headers server-side, which can hide their
-- quests from the API. This log keeps its own collapse state, so expand them.
local function EnsureExpanded()
	if not C_QuestLog.ExpandQuestHeader then return end
	local n = C_QuestLog.GetNumQuestLogEntries() or 0
	for i = n, 1, -1 do
		local info = C_QuestLog.GetInfo(i)
		if info and info.isHeader and info.isCollapsed then
			SafeCall(C_QuestLog.ExpandQuestHeader, i)
		end
	end
end

local function BuildQuestList()
	local result, current = {}, nil
	wipe(questsByID)
	local n = C_QuestLog.GetNumQuestLogEntries() or 0
	for i = 1, n do
		local info = C_QuestLog.GetInfo(i)
		if info then
			if info.isHeader then
				current = { title = info.title or "?", quests = {} }
				result[#result + 1] = current
			elseif not info.isHidden and not info.isInternalOnly and info.questID and info.questID > 0 then
				if not current then
					current = { title = OTHER or "Other", quests = {} }
					result[#result + 1] = current
				end
				local q = {
					questID = info.questID,
					index = i,
					title = info.title,
					level = info.level,
					order = #current.quests,
				}
				q.state = GetQuestState(q.questID)
				q.xp = GetQuestXP(q.questID)
				current.quests[#current.quests + 1] = q
				questsByID[q.questID] = q
			end
		end
	end

	-- drop empty headers, optionally float finished quests to the top
	local out = {}
	for _, g in ipairs(result) do
		if #g.quests > 0 then
			if db.completedFirst then
				table.sort(g.quests, function(a, b)
					local ac, bc = a.state == "complete", b.state == "complete"
					if ac ~= bc then return ac end
					return a.order < b.order
				end)
			end
			out[#out + 1] = g
		end
	end
	return out
end

local function IsSelectable(q)
	if mode == "share" then
		return SafeCall(C_QuestLog.IsPushableQuest, q.questID) == true
	elseif mode == "abandon" then
		if C_QuestLog.CanAbandonQuest then
			return SafeCall(C_QuestLog.CanAbandonQuest, q.questID) == true
		end
		return true
	end
	return false
end

local function SelectedList()
	local ids = {}
	for _, g in ipairs(groups) do
		for _, q in ipairs(g.quests) do
			if selected[q.questID] and IsSelectable(q) then ids[#ids + 1] = q.questID end
		end
	end
	return ids
end

local function IsTracked(questID)
	return SafeCall(C_QuestLog.GetQuestWatchType, questID) ~= nil
end

local function ToggleTrack(questID)
	if IsTracked(questID) then
		SafeCall(C_QuestLog.RemoveQuestWatch, questID)
	else
		SafeCall(C_QuestLog.AddQuestWatch, questID)
	end
	RequestRefresh()
end

---------------------------------------------------------------------------
-- Share / abandon
---------------------------------------------------------------------------

local function ShareOne(questID)
	local index = C_QuestLog.GetLogIndexForQuestID(questID)
	C_QuestLog.SetSelectedQuest(questID)
	QuestLogPushQuest(index)
end

local function AbandonOne(questID)
	C_QuestLog.SetSelectedQuest(questID)
	C_QuestLog.SetAbandonQuest()
	C_QuestLog.AbandonQuest()
end

-- Runs fn(id) for each id with a delay in between so the server does not drop any.
local function RunQueue(ids, delay, fn, onDone)
	busy = true
	UpdateBottom()
	local i = 0
	local function step()
		i = i + 1
		local id = ids[i]
		if not id then
			busy = false
			if onDone then onDone() end
			RequestRefresh()
			return
		end
		local ok, err = pcall(fn, id)
		if not ok then Print("|cffff5555" .. tostring(err) .. "|r") end
		C_Timer.After(delay, step)
	end
	step()
end

local function SetMode(newMode)
	mode = newMode
	wipe(selected)
	view = "list"
	Refresh()
end

local function ShareQuests(ids)
	if #ids == 0 then return end
	if not IsInGroup() then
		Print("Join a group first, there is nobody to share with.")
		return
	end
	RunQueue(ids, 0.6, ShareOne, function()
		Print(("Shared %d quest%s."):format(#ids, #ids == 1 and "" or "s"))
		if mode == "share" then SetMode(nil) end
	end)
end

local function AskAbandon(ids)
	if #ids == 0 then return end
	pendingAbandon = ids
	local names = {}
	for i, id in ipairs(ids) do
		if i > 12 then
			names[#names + 1] = ("...and %d more"):format(#ids - 12)
			break
		end
		local q = questsByID[id]
		names[#names + 1] = "|cffffd100" .. (q and q.title or tostring(id)) .. "|r"
	end
	local text = ("Abandon %d quest%s?\n\n%s"):format(#ids, #ids == 1 and "" or "s", table.concat(names, "\n"))
	StaticPopup_Show("QUESTLOGPLUS_ABANDON", text)
end

StaticPopupDialogs["QUESTLOGPLUS_ABANDON"] = {
	text = "%s",
	button1 = ABANDON_QUEST_ABBREV or "Abandon",
	button2 = CANCEL or "Cancel",
	OnAccept = function()
		local ids = pendingAbandon
		pendingAbandon = nil
		if not ids then return end
		RunQueue(ids, 0.3, AbandonOne, function()
			Print(("Abandoned %d quest%s."):format(#ids, #ids == 1 and "" or "s"))
			if mode == "abandon" then SetMode(nil) end
		end)
	end,
	OnCancel = function() pendingAbandon = nil end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	showAlert = true,
	preferredIndex = 3,
}

---------------------------------------------------------------------------
-- Map docking
---------------------------------------------------------------------------

local function RestorePosition()
	frame:ClearAllPoints()
	local p = db.pos
	if p then
		frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 24, -110)
	end
	docked = false
end

local function Dock()
	if not (WorldMapFrame and WorldMapFrame:IsShown() and frame and frame:IsShown()) then return end
	local ms, fs, us = WorldMapFrame:GetEffectiveScale(), frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
	local mapLeft = (WorldMapFrame:GetLeft() or 0) * ms
	local mapRight = (WorldMapFrame:GetRight() or 0) * ms
	local myW = frame:GetWidth() * fs
	local screenW = UIParent:GetWidth() * us
	frame:ClearAllPoints()
	if mapRight + myW <= screenW then
		frame:SetPoint("TOPLEFT", WorldMapFrame, "TOPRIGHT", 2, 0)
	elseif mapLeft - myW >= 0 then
		frame:SetPoint("TOPRIGHT", WorldMapFrame, "TOPLEFT", -2, 0)
	else
		frame:SetPoint("TOPRIGHT", WorldMapFrame, "TOPRIGHT", 0, 0)
	end
	docked = true
end

local function GetMapForQuest(questID)
	if questID then
		local id = SafeCall(GetQuestUiMapID, questID)
		if type(id) == "number" and id > 0 then return id end
	end
	return C_Map and SafeCall(C_Map.GetBestMapForUnit, "player")
end

local function HideDefaultQuestPanel()
	if not db.hideDefaultMapPanel or not WorldMapFrame then return end
	if QuestMapFrame and QuestMapFrame:IsShown() and WorldMapFrame.HandleUserActionCloseSidePanel then
		SafeCall(WorldMapFrame.HandleUserActionCloseSidePanel, WorldMapFrame)
	end
end

local function ShowMap()
	if not WorldMapFrame then return end
	local mapID = GetMapForQuest(view == "detail" and detailQuestID or nil)
	if not WorldMapFrame:IsShown() then
		if OpenWorldMap then SafeCall(OpenWorldMap, mapID) else SafeCall(ShowUIPanel, WorldMapFrame) end
		openedMap = WorldMapFrame:IsShown()
	elseif mapID and view == "detail" then
		SafeCall(WorldMapFrame.SetMapID, WorldMapFrame, mapID)
	end
	HideDefaultQuestPanel()
	Dock()
end

-- force: close the map even if the player opened it themselves
local function HideMap(force)
	if (openedMap or force) and WorldMapFrame and WorldMapFrame:IsShown() then
		SafeCall(HideUIPanel, WorldMapFrame)
	end
	openedMap = false
	if docked then RestorePosition() end
end

local function UpdateMapButton()
	if mapButton then mapButton:SetText(db.showMap and "Hide Map" or "Show Map") end
end

local function ToggleMapSetting()
	db.showMap = not db.showMap
	if frame and frame:IsShown() then
		if db.showMap then ShowMap() else HideMap(true) end
	end
	UpdateMapButton()
end

local mapHooked = false
local function HookMap()
	if mapHooked or not WorldMapFrame then return end
	mapHooked = true
	WorldMapFrame:HookScript("OnShow", function()
		if frame and frame:IsShown() and db.showMap then
			C_Timer.After(0, Dock)
		end
	end)
	WorldMapFrame:HookScript("OnHide", function()
		openedMap = false
		if docked and frame then RestorePosition() end
	end)
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------

local BUTTON_T

local function MakeButton(parent, text, onClick)
	local b = CreateFrame("Button", nil, parent, BUTTON_T)
	b:SetSize(90, 22)
	if not BUTTON_T then
		b:SetNormalFontObject("GameFontNormalSmall")
		b:SetHighlightFontObject("GameFontHighlightSmall")
		b:SetDisabledFontObject("GameFontDisableSmall")
		local bg = b:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.25, 0.05, 0.05, 0.9)
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.12)
	end
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

local function MakeScroll(parent)
	local tpl = FirstTemplate("UIPanelScrollFrameTemplate", "ScrollFrameTemplate")
	local s = CreateFrame("ScrollFrame", nil, parent, tpl)
	s:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -4)
	s:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", tpl and -26 or -4, 4)
	local c = CreateFrame("Frame", nil, s)
	c:SetSize(1, 1)
	s:SetScrollChild(c)
	if not tpl then
		s:EnableMouseWheel(true)
		s:SetScript("OnMouseWheel", function(self, delta)
			local max = math.max(0, c:GetHeight() - self:GetHeight())
			self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - delta * 40)))
		end)
	end
	return s, c
end

---------------------------------------------------------------------------
-- List rows
---------------------------------------------------------------------------

local function OpenDetail(questID)
	view = "detail"
	detailQuestID = questID
	detailScroll:SetVerticalScroll(0)
	Refresh()
	if db.showMap and WorldMapFrame and WorldMapFrame:IsShown() then
		local mapID = GetMapForQuest(questID)
		if mapID then SafeCall(WorldMapFrame.SetMapID, WorldMapFrame, mapID) end
	end
end

local function OnRowClick(self)
	if busy then return end
	local data = self.data
	if self.kind == "header" then
		if mode then
			local allOn, any = true, false
			for _, q in ipairs(data.quests) do
				if IsSelectable(q) then
					any = true
					if not selected[q.questID] then allOn = false end
				end
			end
			if any then
				for _, q in ipairs(data.quests) do
					if IsSelectable(q) then selected[q.questID] = (not allOn) or nil end
				end
			end
		else
			db.collapsed[data.title] = (not db.collapsed[data.title]) or nil
		end
		Refresh()
		return
	end

	local q = data
	if mode then
		if IsSelectable(q) then selected[q.questID] = (not selected[q.questID]) or nil end
		Refresh()
	elseif IsShiftKeyDown() then
		ToggleTrack(q.questID)
	else
		OpenDetail(q.questID)
	end
end

local function OnRowEnter(self)
	if self.kind ~= "quest" then return end
	local q = self.data
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(q.title or "?", 1, 1, 1)
	if q.state == "complete" then
		GameTooltip:AddLine("Ready to turn in", 0.35, 1, 0.35)
	elseif q.state == "failed" then
		GameTooltip:AddLine("Failed", 1, 0.3, 0.3)
	end
	for _, o in ipairs(GetObjectives(q.questID)) do
		if o.text and o.text ~= "" then
			if o.finished then
				GameTooltip:AddLine(o.text, 0.6, 0.6, 0.6)
			else
				GameTooltip:AddLine(o.text, 1, 1, 1)
			end
		end
	end
	if q.xp > 0 then
		local pct = LevelPercent(q.xp)
		GameTooltip:AddLine(("+%s xp%s"):format(FormatNumber(q.xp), pct and (" (%d%% of a level)"):format(pct) or ""), 0.62, 0.78, 1)
	end
	if mode then
		if not IsSelectable(q) then
			GameTooltip:AddLine(mode == "share" and "This quest can't be shared." or "This quest can't be abandoned.", 1, 0.4, 0.4)
		end
	else
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Click: details   Shift-click: " .. (IsTracked(q.questID) and "untrack" or "track"), 0.5, 0.5, 0.5)
	end
	GameTooltip:Show()
end

local function CreateRow()
	local r = CreateFrame("Button", nil, listContent)
	r:RegisterForClicks("LeftButtonUp")
	r.bg = r:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints()
	r.accent = r:CreateTexture(nil, "BORDER")
	r.accent:SetPoint("TOPLEFT")
	r.accent:SetPoint("BOTTOMLEFT")
	r.accent:SetWidth(3)
	local hl = r:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.08)

	r.expand = r:CreateTexture(nil, "ARTWORK")
	r.expand:SetSize(14, 14)
	r.box = r:CreateTexture(nil, "ARTWORK")
	r.box:SetSize(18, 18)
	r.box:SetTexture(BOX_TEX)
	r.boxCheck = r:CreateTexture(nil, "OVERLAY")
	r.boxCheck:SetAllPoints(r.box)
	r.boxCheck:SetTexture(BOXCHECK_TEX)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(16, 16)

	r.xp = r:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	r.xp:SetPoint("TOPRIGHT", r, "TOPRIGHT", -6, -5)
	r.xp:SetJustifyH("RIGHT")
	r.title = r:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	r.title:SetJustifyH("LEFT")
	r.title:SetWordWrap(false)
	r.sub = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	r.sub:SetJustifyH("LEFT")
	r.sub:SetJustifyV("TOP")

	r:SetScript("OnClick", OnRowClick)
	r:SetScript("OnEnter", OnRowEnter)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return r
end

local function GetRow(i)
	local r = rows[i]
	if not r then
		r = CreateRow()
		rows[i] = r
	end
	r:Show()
	r:SetAlpha(1)
	return r
end

local function SetupHeader(r, g, width)
	r.kind, r.data = "header", g
	r:SetWidth(width)
	r:SetHeight(22)
	r.box:Hide(); r.boxCheck:Hide(); r.icon:Hide(); r.sub:Hide(); r.accent:Hide()
	r.bg:SetColorTexture(0, 0, 0, 0.35)

	r.expand:Show()
	r.expand:ClearAllPoints()
	r.expand:SetPoint("LEFT", r, "LEFT", 4, 0)
	r.expand:SetTexture(db.collapsed[g.title] and PLUS_TEX or MINUS_TEX)

	r.title:ClearAllPoints()
	r.title:SetPoint("LEFT", r, "LEFT", 22, 0)
	r.title:SetPoint("RIGHT", r.xp, "LEFT", -4, 0)
	r.title:SetText(g.title)
	r.title:SetTextColor(1, 0.82, 0)

	local ready, nsel = 0, 0
	for _, q in ipairs(g.quests) do
		if q.state == "complete" then ready = ready + 1 end
		if mode and selected[q.questID] then nsel = nsel + 1 end
	end
	local right = ""
	if mode and nsel > 0 then
		right = ("|cffffffff%d selected|r"):format(nsel)
	elseif ready > 0 then
		right = ("%s%d ready|r"):format(GREEN, ready)
	end
	r.xp:SetText(right)
	r.xp:ClearAllPoints()
	r.xp:SetPoint("RIGHT", r, "RIGHT", -6, 0)
end

local function SetupQuest(r, q, width)
	r.kind, r.data = "quest", q
	r:SetWidth(width)
	r.expand:Hide()

	local x = 8
	local selectable = mode and IsSelectable(q)
	local isSel = mode and selected[q.questID]

	if mode then
		r.box:Show()
		r.box:ClearAllPoints()
		r.box:SetPoint("TOPLEFT", r, "TOPLEFT", x - 2, -1)
		r.box:SetDesaturated(not selectable)
		r.boxCheck:SetShown(isSel and true or false)
		x = x + 18
	else
		r.box:Hide()
		r.boxCheck:Hide()
	end

	if q.state == "complete" or q.state == "failed" then
		r.icon:Show()
		r.icon:SetTexture(q.state == "complete" and READY_ICON or FAILED_ICON)
		r.icon:ClearAllPoints()
		r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", x, -2)
		x = x + 18
	else
		r.icon:Hide()
	end

	r.xp:ClearAllPoints()
	r.xp:SetPoint("TOPRIGHT", r, "TOPRIGHT", -6, -5)
	r.xp:SetText(q.xp > 0 and (XP_COLOR .. "+" .. FormatNumber(q.xp) .. " xp|r") or "")

	r.title:ClearAllPoints()
	r.title:SetPoint("TOPLEFT", r, "TOPLEFT", x, -4)
	r.title:SetPoint("TOPRIGHT", r.xp, "TOPLEFT", -6, 1)
	r.title:SetText(QuestTitle(q))

	-- sub lines: objectives, or the turn-in hint
	local lines = {}
	if q.state == "complete" then
		lines[#lines + 1] = GREEN .. "Ready to turn in|r"
		local comp = SafeCall(GetQuestLogCompletionText, q.index)
		if type(comp) == "string" and comp ~= "" and not IsSecret(comp) then
			lines[#lines + 1] = GREY .. comp .. "|r"
		end
	elseif q.state == "failed" then
		lines[#lines + 1] = "|cffff5555Failed|r"
	else
		for _, o in ipairs(GetObjectives(q.questID)) do
			if o.text and o.text ~= "" then
				lines[#lines + 1] = (o.finished and GREY or "|cffe6e6e6") .. "- " .. o.text .. "|r"
			end
		end
	end

	r.sub:ClearAllPoints()
	local subW = width - (x + 6) - 8
	r.sub:SetWidth(subW)
	r.sub:SetPoint("TOPLEFT", r, "TOPLEFT", x + 6, -21)
	local subH = 0
	if #lines > 0 then
		r.sub:SetText(table.concat(lines, "\n"))
		r.sub:Show()
		subH = r.sub:GetStringHeight() + 2
	else
		r.sub:SetText("")
		r.sub:Hide()
	end
	r:SetHeight(22 + subH + 4)

	-- colors
	if isSel then
		if mode == "share" then
			r.bg:SetColorTexture(0.15, 0.4, 0.85, 0.35)
			r.accent:SetColorTexture(0.4, 0.7, 1, 1)
		else
			r.bg:SetColorTexture(0.7, 0.12, 0.08, 0.40)
			r.accent:SetColorTexture(1, 0.3, 0.2, 1)
		end
		r.accent:Show()
	elseif q.state == "complete" then
		r.bg:SetColorTexture(0.10, 0.50, 0.10, 0.35)
		r.accent:SetColorTexture(0.35, 1, 0.35, 1)
		r.accent:Show()
	elseif q.state == "failed" then
		r.bg:SetColorTexture(0.5, 0.08, 0.08, 0.30)
		r.accent:SetColorTexture(1, 0.25, 0.25, 1)
		r.accent:Show()
	else
		r.bg:SetColorTexture(0, 0, 0, 0)
		r.accent:Hide()
	end

	if q.state == "complete" then
		r.title:SetTextColor(0.45, 1, 0.45)
	elseif q.state == "failed" then
		r.title:SetTextColor(1, 0.35, 0.35)
	else
		r.title:SetTextColor(QuestColor(q))
	end

	if mode and not selectable then r:SetAlpha(0.4) end
end

local function RenderList()
	local width = math.max(200, listScroll:GetWidth() or 300)
	listContent:SetWidth(width)
	local y, n = 0, 0
	for _, g in ipairs(groups) do
		n = n + 1
		local h = GetRow(n)
		SetupHeader(h, g, width)
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -y)
		y = y + h:GetHeight() + 2
		if not db.collapsed[g.title] then
			for _, q in ipairs(g.quests) do
				n = n + 1
				local r = GetRow(n)
				SetupQuest(r, q, width)
				r:ClearAllPoints()
				r:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -y)
				y = y + r:GetHeight() + 2
			end
		end
		y = y + 4
	end
	for i = n + 1, #rows do rows[i]:Hide() end
	listContent:SetHeight(math.max(y, 1))
	emptyText:SetShown(#groups == 0)
end

---------------------------------------------------------------------------
-- Detail view
---------------------------------------------------------------------------

local function CreateDetailWidgets()
	local function FS(font, gap)
		local fs = detailContent:CreateFontString(nil, "ARTWORK", font)
		fs:SetJustifyH("LEFT")
		fs:SetJustifyV("TOP")
		fs.gap = gap
		detail.order[#detail.order + 1] = fs
		return fs
	end
	detail.order = {}
	detail.title = FS("GameFontNormalLarge", 8)
	detail.status = FS("GameFontNormal", 12)
	detail.objHeader = FS("GameFontNormal", 4)
	detail.objText = FS("GameFontHighlight", 6)
	detail.objList = FS("GameFontHighlight", 14)
	detail.rewHeader = FS("GameFontNormal", 4)
	detail.rewText = FS("GameFontHighlight", 14)
	detail.descHeader = FS("GameFontNormal", 4)
	detail.descText = FS("GameFontHighlight", 10)

	detail.statusBg = detailContent:CreateTexture(nil, "BACKGROUND")
	detail.statusBg:SetPoint("TOPLEFT", detail.status, "TOPLEFT", -4, 4)
	detail.statusBg:SetPoint("BOTTOMRIGHT", detail.status, "BOTTOMRIGHT", 4, -4)
end

local function RenderDetail(q)
	SafeCall(C_QuestLog.SetSelectedQuest, q.questID)
	local width = math.max(200, (detailScroll:GetWidth() or 300) - 8)
	detailContent:SetWidth(width + 8)

	detail.title:SetText(QuestTitle(q))
	if q.state == "complete" then
		detail.title:SetTextColor(0.45, 1, 0.45)
	elseif q.state == "failed" then
		detail.title:SetTextColor(1, 0.35, 0.35)
	else
		detail.title:SetTextColor(QuestColor(q))
	end

	-- status banner
	if q.state == "complete" then
		local comp = SafeCall(GetQuestLogCompletionText, q.index)
		local extra = (type(comp) == "string" and comp ~= "" and not IsSecret(comp)) and ("\n|cffdddddd" .. comp .. "|r") or ""
		detail.status:SetText(IconStr(READY_ICON, 18) .. " " .. GREEN .. "READY TO TURN IN|r" .. extra)
		detail.statusBg:SetColorTexture(0.10, 0.50, 0.10, 0.35)
		detail.statusBg:Show()
	elseif q.state == "failed" then
		detail.status:SetText(IconStr(FAILED_ICON, 18) .. " |cffff5555FAILED|r")
		detail.statusBg:SetColorTexture(0.5, 0.08, 0.08, 0.30)
		detail.statusBg:Show()
	else
		detail.status:SetText("")
		detail.statusBg:Hide()
	end

	local desc, objSummary = SafeCall(GetQuestLogQuestText, q.index)
	if IsSecret(desc) then desc = nil end
	if IsSecret(objSummary) then objSummary = nil end

	local objLines = {}
	for _, o in ipairs(GetObjectives(q.questID)) do
		if o.text and o.text ~= "" then
			if o.finished then
				objLines[#objLines + 1] = IconStr(READY_ICON, 14) .. " " .. GREY .. o.text .. "|r"
			else
				objLines[#objLines + 1] = "- " .. o.text
			end
		end
	end
	detail.objHeader:SetText((objSummary or #objLines > 0) and "Objectives" or "")
	detail.objText:SetText(type(objSummary) == "string" and objSummary or "")
	detail.objList:SetText(table.concat(objLines, "\n"))

	local rew = {}
	if q.xp > 0 then
		local pct = LevelPercent(q.xp)
		rew[#rew + 1] = ("%s+%s xp|r%s"):format(XP_COLOR, FormatNumber(q.xp), pct and (GREY .. "  (" .. pct .. "% of a level)|r") or "")
	end
	local money = SafeCall(GetQuestLogRewardMoney, q.questID)
	if type(money) == "number" and not IsSecret(money) and money > 0 and GetCoinTextureString then
		rew[#rew + 1] = GetCoinTextureString(money)
	end
	local nItems = SafeCall(GetNumQuestLogRewards, q.questID) or 0
	if IsSecret(nItems) then nItems = 0 end
	for i = 1, nItems do
		local name, tex, count = SafeCall(GetQuestLogRewardInfo, i, q.questID)
		if name and not IsSecret(name) then
			rew[#rew + 1] = IconStr(tex or 134400, 16) .. " " .. name .. ((count and not IsSecret(count) and count > 1) and (" x" .. count) or "")
		end
	end
	local nChoices = SafeCall(GetNumQuestLogChoices, q.questID, true) or 0
	if IsSecret(nChoices) then nChoices = 0 end
	if nChoices > 0 then
		rew[#rew + 1] = "|cffffd100Choose one:|r"
		for i = 1, nChoices do
			local name, tex, count = SafeCall(GetQuestLogChoiceInfo, i)
			if name and not IsSecret(name) then
				rew[#rew + 1] = "   " .. IconStr(tex or 134400, 16) .. " " .. name .. ((count and not IsSecret(count) and count > 1) and (" x" .. count) or "")
			end
		end
	end
	detail.rewHeader:SetText(#rew > 0 and "Rewards" or "")
	detail.rewText:SetText(table.concat(rew, "\n"))

	detail.descHeader:SetText((type(desc) == "string" and desc ~= "") and "Description" or "")
	detail.descText:SetText(type(desc) == "string" and desc or "")

	local y = 6
	for _, fs in ipairs(detail.order) do
		local t = fs:GetText()
		if t and t ~= "" then
			fs:Show()
			fs:ClearAllPoints()
			fs:SetWidth(width)
			fs:SetPoint("TOPLEFT", detailContent, "TOPLEFT", 6, -y)
			y = y + fs:GetStringHeight() + (fs.gap or 6)
		else
			fs:Hide()
		end
	end
	detailContent:SetHeight(y + 8)
end

---------------------------------------------------------------------------
-- Bottom bar / header text
---------------------------------------------------------------------------

local function LayoutButtons(list)
	for _, b in pairs(buttons) do b:Hide() end
	local n = #list
	if n == 0 then return end
	local total = frame:GetWidth() - 16
	local w = (total - (n - 1) * 4) / n
	for i, b in ipairs(list) do
		b:ClearAllPoints()
		b:SetWidth(w)
		b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8 + (i - 1) * (w + 4), 5)
		b:Show()
	end
end

function UpdateBottom()
	if not frame then return end
	if view == "detail" then
		local q = questsByID[detailQuestID]
		buttons.track:SetText(q and IsTracked(q.questID) and "Untrack" or "Track")
		buttons.share:SetEnabled(q and not busy and IsInGroup() and SafeCall(C_QuestLog.IsPushableQuest, q.questID) == true or false)
		local canAbandon = q and (not C_QuestLog.CanAbandonQuest or SafeCall(C_QuestLog.CanAbandonQuest, q.questID) == true)
		buttons.abandon:SetEnabled((canAbandon and not busy) and true or false)
		LayoutButtons({ buttons.back, buttons.track, buttons.share, buttons.abandon })
	elseif mode then
		local n = #SelectedList()
		buttons.action:SetText(("%s (%d)"):format(mode == "share" and "Share" or "Abandon", n))
		local ok = n > 0 and not busy and (mode ~= "share" or IsInGroup())
		buttons.action:SetEnabled(ok and true or false)
		LayoutButtons({ buttons.all, buttons.none, buttons.action, buttons.cancel })
	else
		buttons.shareMode:SetEnabled(not busy)
		buttons.abandonMode:SetEnabled(not busy)
		LayoutButtons({ buttons.shareMode, buttons.abandonMode })
	end

	if busy then
		headerText:SetText("|cffffd100Working...|r")
	elseif mode == "share" then
		headerText:SetText(IsInGroup() and "|cff66aaffSHARE MODE|r - click quests to select"
			or "|cff66aaffSHARE MODE|r - |cffff6666join a group to share|r")
	elseif mode == "abandon" then
		headerText:SetText("|cffff5544ABANDON MODE|r - click quests to select")
	else
		local _, numQuests = C_QuestLog.GetNumQuestLogEntries()
		local max = SafeCall(C_QuestLog.GetMaxNumQuestsCanAccept) or MAX_QUESTS or 0
		headerText:SetText(("Quests: |cffffffff%d/%d|r"):format(numQuests or 0, max))
	end
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

function Refresh()
	if not frame or not frame:IsShown() then return end
	EnsureExpanded()
	groups = BuildQuestList()

	for id in pairs(selected) do
		if not questsByID[id] then selected[id] = nil end
	end
	if view == "detail" and not questsByID[detailQuestID] then
		view, detailQuestID = "list", nil
	end

	listScroll:SetShown(view == "list")
	detailScroll:SetShown(view == "detail")
	if view == "list" then
		RenderList()
	else
		emptyText:Hide()
		RenderDetail(questsByID[detailQuestID])
	end
	UpdateBottom()
end

local refreshPending = false
function RequestRefresh()
	if refreshPending or not frame or not frame:IsShown() then return end
	refreshPending = true
	C_Timer.After(0.05, function()
		refreshPending = false
		Refresh()
	end)
end

---------------------------------------------------------------------------
-- Main frame
---------------------------------------------------------------------------

local function CreateUI()
	BUTTON_T = FirstTemplate("UIPanelButtonTemplate")
	local frameT = FirstTemplate("ButtonFrameTemplate", "PortraitFrameTemplate", "BasicFrameTemplateWithInset")
	frame = CreateFrame("Frame", "QuestLogPlusFrame", UIParent, frameT or FirstTemplate("BackdropTemplate"))
	frame:SetSize(FRAME_W, FRAME_H)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
	frame:Hide()
	tinsert(UISpecialFrames, "QuestLogPlusFrame")

	if not frameT then
		local bg = frame:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.05, 0.05, 0.05, 0.94)
	end

	-- title + portrait
	if frame.SetTitle then
		frame:SetTitle(QUEST_LOG or "Quest Log")
	elseif frame.TitleText then
		frame.TitleText:SetText(QUEST_LOG or "Quest Log")
	else
		local t = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		t:SetPoint("TOP", 0, -6)
		t:SetText(QUEST_LOG or "Quest Log")
	end
	if frame.SetPortraitToAsset then
		SafeCall(frame.SetPortraitToAsset, frame, BOOK_ICON)
	end

	-- close button
	local close = frame.CloseButton
	if not close then
		close = CreateFrame("Button", nil, frame, FirstTemplate("UIPanelCloseButton"))
		close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
		if not FirstTemplate("UIPanelCloseButton") then
			close:SetSize(20, 20)
			close:SetNormalFontObject("GameFontNormal")
			close:SetText("x")
		end
	end
	close:SetScript("OnClick", function() frame:Hide() end)

	-- inset
	inset = frame.Inset
	if not inset then
		inset = CreateFrame("Frame", nil, frame, FirstTemplate("InsetFrameTemplate"))
		if not FirstTemplate("InsetFrameTemplate") then
			local ibg = inset:CreateTexture(nil, "BACKGROUND")
			ibg:SetAllPoints()
			ibg:SetColorTexture(0, 0, 0, 0.5)
		end
	end
	inset:ClearAllPoints()
	inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -60)
	inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 30)

	-- toolbar
	headerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	headerText:SetPoint("TOPLEFT", frame, "TOPLEFT", 64, -38)
	headerText:SetWidth(FRAME_W - 64 - 104)
	headerText:SetJustifyH("LEFT")
	headerText:SetWordWrap(false)

	mapButton = MakeButton(frame, "Show Map", ToggleMapSetting)
	mapButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -32)
	UpdateMapButton()

	-- scroll areas
	listScroll, listContent = MakeScroll(inset)
	detailScroll, detailContent = MakeScroll(inset)
	detailScroll:Hide()
	CreateDetailWidgets()

	emptyText = inset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	emptyText:SetPoint("CENTER")
	emptyText:SetText("Your quest log is empty.")
	emptyText:Hide()

	-- bottom buttons
	buttons.shareMode = MakeButton(frame, "Share Quests", function() SetMode("share") end)
	buttons.abandonMode = MakeButton(frame, "Abandon Quests", function() SetMode("abandon") end)
	buttons.all = MakeButton(frame, "All", function()
		for _, g in ipairs(groups) do
			for _, q in ipairs(g.quests) do
				if IsSelectable(q) then selected[q.questID] = true end
			end
		end
		Refresh()
	end)
	buttons.none = MakeButton(frame, "None", function() wipe(selected); Refresh() end)
	buttons.action = MakeButton(frame, "Go", function()
		local ids = SelectedList()
		if mode == "share" then ShareQuests(ids) elseif mode == "abandon" then AskAbandon(ids) end
	end)
	buttons.cancel = MakeButton(frame, CANCEL or "Cancel", function() SetMode(nil) end)
	buttons.back = MakeButton(frame, "< Back", function()
		view = "list"
		Refresh()
	end)
	buttons.track = MakeButton(frame, "Track", function()
		if detailQuestID then ToggleTrack(detailQuestID) end
	end)
	buttons.share = MakeButton(frame, "Share", function()
		if detailQuestID then ShareQuests({ detailQuestID }) end
	end)
	buttons.abandon = MakeButton(frame, "Abandon", function()
		if detailQuestID then AskAbandon({ detailQuestID }) end
	end)

	-- scripts
	frame:SetScript("OnDragStart", function(self)
		if not docked then self:StartMoving() end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, rp, x, y = self:GetPoint()
		db.pos = { p, rp, x, y }
	end)
	frame:SetScript("OnShow", function()
		if PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_OPEN then PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN) end
		if not docked then RestorePosition() end
		Refresh()
		if db.showMap then ShowMap() end
	end)
	frame:SetScript("OnHide", function()
		if PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_CLOSE then PlaySound(SOUNDKIT.IG_QUEST_LOG_CLOSE) end
		GameTooltip:Hide()
		if not busy then
			mode = nil
			wipe(selected)
		end
		HideMap()
	end)
	frame:SetScript("OnSizeChanged", function() RequestRefresh() end)

	RestorePosition()
end

function QuestLogPlus_Toggle()
	if not frame then return end
	if frame:IsShown() then frame:Hide() else frame:Show() end
end

---------------------------------------------------------------------------
-- Take over the quest log key
---------------------------------------------------------------------------

local toggleButton = CreateFrame("Button", "QuestLogPlusToggleButton", UIParent)
toggleButton:RegisterForClicks("AnyUp", "AnyDown")
local lastToggle = 0
toggleButton:SetScript("OnClick", function()
	-- a key binding can deliver both the down and the up click; act once
	local now = GetTime()
	if now - lastToggle < 0.25 then return end
	lastToggle = now
	QuestLogPlus_Toggle()
end)

local lastKeySig, pendingBind
local function ApplyKeyOverride()
	if not db then return end
	if InCombatLockdown() then
		pendingBind = true
		return
	end
	pendingBind = false
	local keys = { GetBindingKey("TOGGLEQUESTLOG") }
	local sig = (db.takeOverKey and "1" or "0") .. ":" .. table.concat(keys, ",")
	if sig == lastKeySig then return end
	lastKeySig = sig
	ClearOverrideBindings(toggleButton)
	if db.takeOverKey then
		for _, key in ipairs(keys) do
			SetOverrideBindingClick(toggleButton, false, key, "QuestLogPlusToggleButton")
		end
	end
end

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

local function OnOff(v) return v and "|cff55ff55on|r" or "|cffff5555off|r" end

SLASH_QUESTLOGPLUS1 = "/qlp"
SLASH_QUESTLOGPLUS2 = "/questlogplus"
SlashCmdList.QUESTLOGPLUS = function(msg)
	msg = strlower(strtrim(msg or ""))
	if msg == "" then
		QuestLogPlus_Toggle()
	elseif msg == "map" then
		ToggleMapSetting()
		Print("Map " .. OnOff(db.showMap))
	elseif msg == "key" then
		db.takeOverKey = not db.takeOverKey
		ApplyKeyOverride()
		Print("Quest log key opens Quest Log Plus: " .. OnOff(db.takeOverKey))
	elseif msg == "level" then
		db.showLevel = not db.showLevel
		RequestRefresh()
		Print("Quest levels " .. OnOff(db.showLevel))
	elseif msg == "sort" then
		db.completedFirst = not db.completedFirst
		RequestRefresh()
		Print("Completed quests first " .. OnOff(db.completedFirst))
	elseif msg == "panel" then
		db.hideDefaultMapPanel = not db.hideDefaultMapPanel
		Print("Close the map's own quest panel " .. OnOff(db.hideDefaultMapPanel))
	elseif msg == "reset" then
		db.pos = nil
		if frame then RestorePosition() end
		Print("Position reset.")
	else
		Print("commands:")
		Print("/qlp - toggle the log")
		Print("/qlp map - map " .. OnOff(db.showMap))
		Print("/qlp key - take over the quest log key " .. OnOff(db.takeOverKey))
		Print("/qlp level - show quest levels " .. OnOff(db.showLevel))
		Print("/qlp sort - completed quests first " .. OnOff(db.completedFirst))
		Print("/qlp panel - close the map's own quest panel " .. OnOff(db.hideDefaultMapPanel))
		Print("/qlp reset - reset window position")
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
local function Register(ev) pcall(events.RegisterEvent, events, ev) end

Register("ADDON_LOADED")
Register("PLAYER_LOGIN")
Register("UPDATE_BINDINGS")
Register("PLAYER_REGEN_ENABLED")
for _, ev in ipairs({
	"QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
	"QUEST_WATCH_LIST_CHANGED", "UNIT_QUEST_LOG_CHANGED", "GROUP_ROSTER_UPDATE",
	"PLAYER_LEVEL_UP", "QUEST_DATA_LOAD_RESULT",
}) do Register(ev) end

events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON_NAME then
			QuestLogPlusDB = QuestLogPlusDB or {}
			CopyDefaults(DEFAULTS, QuestLogPlusDB)
			db = QuestLogPlusDB
		elseif arg1 == "Blizzard_WorldMap" then
			HookMap()
		end
	elseif event == "PLAYER_LOGIN" then
		CreateUI()
		HookMap()
		ApplyKeyOverride()
	elseif event == "UPDATE_BINDINGS" then
		ApplyKeyOverride()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pendingBind then ApplyKeyOverride() end
	elseif event == "UNIT_QUEST_LOG_CHANGED" then
		if arg1 == "player" then RequestRefresh() end
	else
		RequestRefresh()
	end
end)
