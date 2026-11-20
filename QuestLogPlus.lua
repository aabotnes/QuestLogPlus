-- Quest Log Plus  (World of Warcraft: Forever, interface 16001)
--
-- A stand-alone quest log window styled like the default one, with:
--   * a Show/Hide Map toggle: the world map is attached to the log's right
--     side, scaled to the log's height, and moves with it
--   * "+1,234 xp" on every quest
--   * completed quests painted green with a check mark and "Ready to turn in"
--   * rewards shown like the default log (hover for the item tooltip,
--     shift-click to link), plus optional small reward icons in the list
--   * a filter for quests you already hold quest items for
--   * Share mode / Abandon mode to batch-select quests
--
-- The default quest log is left untouched; this addon only takes over the
-- quest log key (L by default). "/qlp key" gives L back to the default log.

local ADDON_NAME = ...

BINDING_HEADER_QUESTLOGPLUS = "Quest Log Plus"
BINDING_NAME_QUESTLOGPLUS_TOGGLE = "Toggle Quest Log Plus"

local DEFAULTS = {
	showMap = false,            -- open the world map next to the log
	showLevel = true,           -- "[12] Quest name"
	completedFirst = true,      -- ready-to-turn-in quests sort to the top of each zone
	takeOverKey = true,         -- the quest log key opens this log instead of the default one
	hideDefaultMapPanel = true, -- close the map's own quest side panel when we open the map
	listRewards = true,         -- small reward icons in the quest list
	filterItems = false,        -- only quests you hold quest items for
	gameWindow = true,          -- move aside when game windows (character sheet, ...) open
	detailPopout = true,        -- quest details open in a separate panel on the log's right side
	popoutWidth = 360,
	collapsed = {},
	pos = nil,                  -- log position { point, relativePoint, x, y }
	size = nil,                 -- log size { w, h }
}

local FRAME_W, FRAME_H = 384, 600
local MIN_W, MIN_H, MAX_W, MAX_H = 320, 380, 900, 1400
local ICON = 20                 -- reward icon size in the list
local READY_ICON = "Interface\\RaidFrame\\ReadyCheck-Ready"
local FAILED_ICON = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local PLUS_TEX = "Interface\\Buttons\\UI-PlusButton-Up"
local MINUS_TEX = "Interface\\Buttons\\UI-MinusButton-Up"
local BOX_TEX = "Interface\\Buttons\\UI-CheckBox-Up"
local BOXCHECK_TEX = "Interface\\Buttons\\UI-CheckBox-Check"
local BOOK_ICON = "Interface\\Icons\\INV_Misc_Book_08"
local QUESTION_ICON = 134400
local ICON_BORDER = "Interface\\Common\\WhiteIconFrame"
local GRIP_UP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
local GRIP_DOWN = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down"
local GRIP_HL = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight"

local XP_COLOR = "|cff9fc8ff"
local GREEN = "|cff55ff55"
local GREY = "|cff9d9d9d"

local TXT_CHOOSE = REWARD_CHOICES or "You will be able to choose one of these rewards:"
local TXT_RECEIVE = REWARD_ITEMS_ONLY or "You will receive:"
local TXT_ALSO = REWARD_ITEMS or "You will also receive:"

local db
local frame, inset, listScroll, listContent, detailScroll, detailContent
local emptyText, headerText, mapButton
local rows = {}
local groups = {}
local questsByID = {}
local totalQuests, shownQuests = 0, 0
local view = "list"        -- "list" | "detail"
local detailQuestID
local mode                 -- nil | "share" | "abandon"
local selected = {}
local busy = false         -- a batch share/abandon is running
local buttons = {}
local detail = {}
local detailButtons = {}
local rewardCache = {}
local pendingAbandon
local logMoving = false
local popout, popInset         -- the separate quest details panel
local popButtons = {}
local allChecks = {}           -- every settings checkbox, kept in sync with db
local settingsFrame

local Refresh, RequestRefresh, UpdateBottom, OnRowClick, ApplyMapLayout, SetOption, AttachDetail, AdaptToPanels
local logPushed = false      -- the log is moved aside for a game window (its home position is db.pos)

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

-- nil for secret values, so they can be compared and printed safely
local function Clean(v)
	if IsSecret(v) then return nil end
	return v
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
	local max = Clean(UnitXPMax and UnitXPMax("player"))
	if type(max) ~= "number" or max <= 0 then return nil end
	return math.floor(xp / max * 100 + 0.5)
end

local function QualityColor(quality)
	if type(quality) ~= "number" then return 1, 1, 1 end
	if C_Item and C_Item.GetItemQualityColor then
		local r, g, b = SafeCall(C_Item.GetItemQualityColor, quality)
		if type(r) == "number" then return r, g, b end
	end
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

local function HideTooltip()
	GameTooltip:Hide()
end

-- position of a frame's top-left corner in UIParent units (nil if unknown or secret)
local function TopLeftInUI(f)
	local left, top, eff = Clean(f:GetLeft()), Clean(f:GetTop()), Clean(f:GetEffectiveScale())
	local ui = UIParent:GetEffectiveScale()
	if not left or not top or not eff then return end
	return left * eff / ui, top * eff / ui
end

---------------------------------------------------------------------------
-- Quest data
---------------------------------------------------------------------------

local function GetQuestXP(questID)
	local xp = Clean(SafeCall(GetQuestLogRewardXP, questID))
	return type(xp) == "number" and xp or 0
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

-- true if you hold something for this quest: a usable quest item, or at
-- least one item collected for an item objective
local function HasQuestItems(q)
	local link = Clean(SafeCall(GetQuestLogSpecialItemInfo, q.index))
	if link then return true end
	for _, o in ipairs(GetObjectives(q.questID)) do
		local have = Clean(o.numFulfilled)
		if o.type == "item" and type(have) == "number" and have > 0 then return true end
	end
	return false
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

-- kind: "choice" or "reward" (the names GameTooltip:SetQuestLogItem uses)
local function ReadRewardList(kind, questID)
	local countFn = kind == "choice" and GetNumQuestLogChoices or GetNumQuestLogRewards
	local infoFn = kind == "choice" and GetQuestLogChoiceInfo or GetQuestLogRewardInfo
	local list, complete = {}, true
	local n = Clean(SafeCall(countFn, questID))
	if type(n) ~= "number" then return list, false end
	for i = 1, n do
		local name, tex, count, quality, isUsable, itemID = SafeCall(infoFn, i, questID)
		name, tex, count, quality, isUsable, itemID =
			Clean(name), Clean(tex), Clean(count), Clean(quality), Clean(isUsable), Clean(itemID)
		if not name or name == "" then
			complete = false
			if itemID and C_Item and C_Item.RequestLoadItemDataByID then
				SafeCall(C_Item.RequestLoadItemDataByID, itemID)
			end
		end
		list[#list + 1] = {
			kind = kind, index = i, questID = questID,
			name = name, texture = tex, count = count,
			quality = quality, isUsable = isUsable, itemID = itemID,
		}
	end
	return list, complete
end

-- item rewards are cached once every name has loaded
local function GetRewards(questID)
	local cached = rewardCache[questID]
	if cached then return cached end
	local choices, ok1 = ReadRewardList("choice", questID)
	local items, ok2 = ReadRewardList("reward", questID)
	local r = { choices = choices, items = items }
	if ok1 and ok2 then rewardCache[questID] = r end
	return r
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
	totalQuests, shownQuests = 0, 0
	local n = C_QuestLog.GetNumQuestLogEntries() or 0
	for i = 1, n do
		local info = C_QuestLog.GetInfo(i)
		if info then
			if info.isHeader then
				current = { title = info.title or "?", quests = {} }
				result[#result + 1] = current
			elseif not info.isHidden and not info.isInternalOnly and info.questID and info.questID > 0 then
				totalQuests = totalQuests + 1
				local q = {
					questID = info.questID,
					index = i,
					title = info.title,
					level = info.level,
				}
				if not db.filterItems or HasQuestItems(q) then
					if not current then
						current = { title = OTHER or "Other", quests = {} }
						result[#result + 1] = current
					end
					q.order = #current.quests
					q.state = GetQuestState(q.questID)
					q.xp = GetQuestXP(q.questID)
					current.quests[#current.quests + 1] = q
					questsByID[q.questID] = q
					shownQuests = shownQuests + 1
				end
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
-- Reward tooltips (shared by the detail buttons and the list icons)
---------------------------------------------------------------------------

local function ShowRewardTooltip(self)
	local d = self.reward
	if not d then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	local ok = pcall(GameTooltip.SetQuestLogItem, GameTooltip, d.kind, d.index, d.questID)
	if (not ok or GameTooltip:NumLines() == 0) and d.itemID then
		pcall(GameTooltip.SetItemByID, GameTooltip, d.itemID)
	end
	GameTooltip:Show()
end

-- shift-click links the item, ctrl-click previews it; returns true if handled
local function RewardModifiedClick(self)
	local d = self.reward
	if not d or not IsModifiedClick or not HandleModifiedItemClick then return false end
	if not (IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown()) then return false end
	local link = Clean(SafeCall(GetQuestLogItemLink, d.kind, d.index, d.questID))
	if link then
		HandleModifiedItemClick(link)
		return true
	end
	return false
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
-- Log position / size
---------------------------------------------------------------------------

local function RestoreLogGeometry()
	local s = db.size
	if s and s[1] and s[2] then
		frame:SetSize(math.min(MAX_W, math.max(MIN_W, s[1])), math.min(MAX_H, math.max(MIN_H, s[2])))
	else
		frame:SetSize(FRAME_W, FRAME_H)
	end
	frame:ClearAllPoints()
	local p = db.pos
	if p then
		frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 24, -110)
	end
end

local function SaveLogGeometry()
	local x, y = TopLeftInUI(frame)
	if x and not logPushed then -- a pushed-aside position is not the home position
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
		db.pos = { "TOPLEFT", "BOTTOMLEFT", x, y }
	end
	db.size = { frame:GetWidth(), frame:GetHeight() }
end

-- move the log (and everything attached to it) with the cursor
local function StartLogMove()
	logMoving = true
	frame:StartMoving()
end

local function StopLogMove()
	if not logMoving then return end
	frame:StopMovingOrSizing()
	logMoving = false
	logPushed = false -- where you drop it is the new home position
	SaveLogGeometry()
	ApplyMapLayout()
end

---------------------------------------------------------------------------
-- Map: attached to the right side of the log (or of the details panel when
-- it is open), scaled to the log's height, like one window. Dragging the
-- map's title bar moves the log and the map together.
---------------------------------------------------------------------------

local mapApplied, mapOrigScale = false, nil
local mapHandle

local function CanChangeMap()
	return WorldMapFrame and (not InCombatLockdown() or not WorldMapFrame:IsProtected())
end

local function MapMaximized()
	return WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized()
end

local function MapActive()
	return frame and frame:IsShown() and db.showMap and WorldMapFrame and WorldMapFrame:IsShown() and not MapMaximized()
end

-- the map scale that makes it exactly as tall as the log
local function TargetMapScale()
	local mapH = Clean(WorldMapFrame:GetHeight())
	local mapScale = Clean(WorldMapFrame:GetScale())
	local mapEff = Clean(WorldMapFrame:GetEffectiveScale())
	local logEff = Clean(frame:GetEffectiveScale())
	if not mapH or not mapScale or not mapEff or not logEff or mapH <= 0 or mapScale <= 0 then return end
	local parentEff = mapEff / mapScale
	local scale = frame:GetHeight() * logEff / (mapH * parentEff)
	return math.min(2, math.max(0.2, scale))
end

-- where the map's top-left corner belongs, in UIParent units
local function MapTarget()
	local anchor = (popout and popout:IsShown()) and popout or frame
	local lx, ly = TopLeftInUI(anchor)
	if not lx then return end
	return lx + anchor:GetWidth() * anchor:GetEffectiveScale() / UIParent:GetEffectiveScale() + 2, ly
end

local function RestoreMapDefaults()
	if not mapApplied or not WorldMapFrame or not CanChangeMap() then return end
	mapApplied = false
	if mapOrigScale then WorldMapFrame:SetScale(mapOrigScale) end
	if mapHandle then mapHandle:Hide() end
end

function ApplyMapLayout()
	if not WorldMapFrame then return end
	if not MapActive() then
		RestoreMapDefaults()
		return
	end
	if not CanChangeMap() then return end
	if not mapApplied then
		mapOrigScale = WorldMapFrame:GetScale()
		mapApplied = true
	end

	local scale = TargetMapScale()
	if scale and math.abs(WorldMapFrame:GetScale() - scale) > 0.001 then
		WorldMapFrame:SetScale(scale)
	end

	local x, y = MapTarget()
	if x and y then
		local k = UIParent:GetEffectiveScale() / WorldMapFrame:GetEffectiveScale()
		WorldMapFrame:ClearAllPoints()
		WorldMapFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x * k, y * k)
	end
	if mapHandle then mapHandle:Show() end
end

-- run after the game (and Leatrix Maps) have finished placing the map
local mapLayoutPending = false
local function ScheduleMapLayout()
	if mapLayoutPending then return end
	mapLayoutPending = true
	C_Timer.After(0, function()
		mapLayoutPending = false
		ApplyMapLayout()
	end)
end

-- If the game or another addon moves or rescales the map, dock it again.
-- Checked a few times a second while the log is open.
local mapWatchElapsed = 0
local function WatchMap(elapsed)
	mapWatchElapsed = mapWatchElapsed + (elapsed or 0)
	if mapWatchElapsed < 0.2 then return end
	mapWatchElapsed = 0
	if not MapActive() or not CanChangeMap() then return end
	local x, y = MapTarget()
	local mx, my = TopLeftInUI(WorldMapFrame)
	if not x or not mx then return end
	local scale = TargetMapScale()
	if math.abs(mx - x) > 1 or math.abs(my - y) > 1
		or (scale and math.abs(WorldMapFrame:GetScale() - scale) > 0.005) then
		ApplyMapLayout()
	end
end

local function GetMapForQuest(questID)
	if questID then
		local id = Clean(SafeCall(GetQuestUiMapID, questID))
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
	if not WorldMapFrame:IsShown() then
		local mapID = GetMapForQuest(detailQuestID)
		if OpenWorldMap then SafeCall(OpenWorldMap, mapID) else SafeCall(ShowUIPanel, WorldMapFrame) end
	elseif detailQuestID then
		local mapID = GetMapForQuest(detailQuestID)
		if mapID then SafeCall(WorldMapFrame.SetMapID, WorldMapFrame, mapID) end
	end
	-- a full-screen map can't sit next to the log; use the windowed map
	if WorldMapFrame:IsShown() and MapMaximized() and not InCombatLockdown() and WorldMapFrame.Minimize then
		SafeCall(WorldMapFrame.Minimize, WorldMapFrame)
	end
	HideDefaultQuestPanel()
	ScheduleMapLayout()
end

local function HideMap()
	if WorldMapFrame and WorldMapFrame:IsShown() and mapApplied then
		SafeCall(HideUIPanel, WorldMapFrame)
	end
	RestoreMapDefaults()
end

local function UpdateMapButton()
	if mapButton then mapButton:SetText(db.showMap and "Hide Map" or "Show Map") end
end

local function ToggleMapSetting()
	SetOption("showMap", not db.showMap)
end

local mapHooked = false
local function HookMap()
	if mapHooked or not WorldMapFrame then return end
	mapHooked = true

	WorldMapFrame:HookScript("OnShow", ScheduleMapLayout)
	WorldMapFrame:HookScript("OnHide", function()
		if logMoving and frame then StopLogMove() end
		RestoreMapDefaults()
	end)
	-- the game (and Leatrix Maps) re-place the map on these; put it back after them
	if WorldMapFrame.SynchronizeDisplayState then
		hooksecurefunc(WorldMapFrame, "SynchronizeDisplayState", ScheduleMapLayout)
	end
	if WorldMapFrame.OnFrameSizeChanged then
		hooksecurefunc(WorldMapFrame, "OnFrameSizeChanged", ScheduleMapLayout)
	end

	-- the map's title bar moves the log and map together (close/maximize buttons stay free)
	mapHandle = CreateFrame("Frame", nil, WorldMapFrame)
	mapHandle:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", 60, 0)
	mapHandle:SetPoint("TOPRIGHT", WorldMapFrame, "TOPRIGHT", -70, 0)
	mapHandle:SetHeight(22)
	mapHandle:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 100)
	mapHandle:EnableMouse(true)
	mapHandle:SetScript("OnMouseDown", function(_, btn)
		if btn == "LeftButton" and frame and MapActive() then StartLogMove() end
	end)
	mapHandle:SetScript("OnMouseUp", function() StopLogMove() end)
	mapHandle:Hide()
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

-- a checkbox bound to db[key]; changes go through SetOption
local function MakeCheck(parent, label, tooltip, key)
	local tpl = FirstTemplate("UICheckButtonTemplate")
	local cb = CreateFrame("CheckButton", nil, parent, tpl)
	cb:SetSize(22, 22)
	if not tpl then
		cb:SetNormalTexture(BOX_TEX)
		cb:SetCheckedTexture(BOXCHECK_TEX)
		cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
	end
	local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("LEFT", cb, "RIGHT", 0, 1)
	fs:SetText(label)
	cb.label = fs
	cb:SetHitRectInsets(0, -(fs:GetStringWidth() + 4), 0, 0)
	cb.key = key
	cb:SetChecked(db[key] and true or false)
	allChecks[#allChecks + 1] = cb
	cb:SetScript("OnClick", function(self) SetOption(key, self:GetChecked() and true or false) end)
	cb:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(label, 1, 1, 1)
		GameTooltip:AddLine(tooltip, 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	cb:SetScript("OnLeave", HideTooltip)
	return cb
end

local function MakeScroll(parent)
	local tpl = FirstTemplate("UIPanelScrollFrameTemplate", "ScrollFrameTemplate")
	local s = CreateFrame("ScrollFrame", nil, parent, tpl)
	s.padR = tpl and -26 or -4
	s:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -4)
	s:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", s.padR, 4)
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

local function MakeGrip(parent)
	local g = CreateFrame("Button", nil, parent)
	g:SetSize(16, 16)
	g:SetNormalTexture(GRIP_UP)
	g:SetPushedTexture(GRIP_DOWN)
	g:SetHighlightTexture(GRIP_HL)
	return g
end

---------------------------------------------------------------------------
-- List rows
---------------------------------------------------------------------------

local function OpenDetail(questID)
	detailQuestID = questID
	detailScroll:SetVerticalScroll(0)
	if db.detailPopout then
		view = "list"
		popout:Show()
	else
		view = "detail"
	end
	Refresh()
	if MapActive() then
		local mapID = GetMapForQuest(questID)
		if mapID then SafeCall(WorldMapFrame.SetMapID, WorldMapFrame, mapID) end
	end
end

-- how many of a zone's selectable quests are selected: selectedCount, selectableCount
local function GroupSelection(g)
	local on, total = 0, 0
	for _, q in ipairs(g.quests) do
		if IsSelectable(q) then
			total = total + 1
			if selected[q.questID] then on = on + 1 end
		end
	end
	return on, total
end

-- select every selectable quest in the zone, or clear them if all are selected
local function ToggleGroupSelect(g)
	if busy or not mode then return end
	local on, total = GroupSelection(g)
	if total == 0 then return end
	local selectAll = on < total
	for _, q in ipairs(g.quests) do
		if IsSelectable(q) then selected[q.questID] = selectAll or nil end
	end
	Refresh()
end

local function ToggleGroupCollapse(g)
	db.collapsed[g.title] = (not db.collapsed[g.title]) or nil
	Refresh()
end

function OnRowClick(self)
	if busy then return end
	local data = self.data
	if self.kind == "header" then
		if mode then ToggleGroupSelect(data) else ToggleGroupCollapse(data) end
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
		local text = Clean(o.text)
		if text and text ~= "" then
			if o.finished then
				GameTooltip:AddLine(text, 0.6, 0.6, 0.6)
			else
				GameTooltip:AddLine(text, 1, 1, 1)
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

local function SetIconBorder(border, quality)
	if type(quality) == "number" and quality >= 2 then
		border:SetVertexColor(QualityColor(quality))
		border:Show()
	else
		border:Hide()
	end
end

local function GetRowIcon(r, i)
	local b = r.rIcons[i]
	if not b then
		b = CreateFrame("Button", nil, r)
		b:SetSize(ICON, ICON)
		b.Icon = b:CreateTexture(nil, "ARTWORK")
		b.Icon:SetAllPoints()
		b.Border = b:CreateTexture(nil, "OVERLAY")
		b.Border:SetTexture(ICON_BORDER)
		b.Border:SetAllPoints()
		b.Count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		b.Count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -1)
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.25)
		b:SetScript("OnEnter", ShowRewardTooltip)
		b:SetScript("OnLeave", HideTooltip)
		b.UpdateTooltip = ShowRewardTooltip
		b:SetScript("OnClick", function(self)
			if not RewardModifiedClick(self) then OnRowClick(r) end
		end)
		r.rIcons[i] = b
	end
	b:Show()
	return b
end

local function GetRowLabel(r, i)
	local fs = r.rLabels[i]
	if not fs then
		fs = r:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		fs:SetJustifyH("LEFT")
		r.rLabels[i] = fs
	end
	fs:Show()
	return fs
end

local function HideRowRewards(r, fromIcon, fromLabel)
	for i = fromIcon or 1, #r.rIcons do r.rIcons[i]:Hide() end
	for i = fromLabel or 1, #r.rLabels do r.rLabels[i]:Hide() end
end

local function CreateRow()
	local r = CreateFrame("Button", nil, listContent)
	r:RegisterForClicks("LeftButtonUp")
	r.bg = r:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints()
	r.cur = r:CreateTexture(nil, "BACKGROUND", nil, 1) -- quest open in the details panel
	r.cur:SetAllPoints()
	r.cur:SetColorTexture(1, 0.82, 0, 0.16)
	r.cur:Hide()
	r.accent = r:CreateTexture(nil, "BORDER")
	r.accent:SetPoint("TOPLEFT")
	r.accent:SetPoint("BOTTOMLEFT")
	r.accent:SetWidth(3)
	local hl = r:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.08)

	-- header: +/- button (always expands/collapses) and a "select all" box for share/abandon mode
	r.expandBtn = CreateFrame("Button", nil, r)
	r.expandBtn:SetSize(18, 18)
	r.expandBtn:SetPoint("LEFT", r, "LEFT", 2, 0)
	r.expand = r.expandBtn:CreateTexture(nil, "ARTWORK")
	r.expand:SetSize(14, 14)
	r.expand:SetPoint("CENTER")
	local ehl = r.expandBtn:CreateTexture(nil, "HIGHLIGHT")
	ehl:SetAllPoints(r.expand)
	ehl:SetTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
	ehl:SetBlendMode("ADD")
	r.expandBtn:SetScript("OnClick", function() if r.kind == "header" then ToggleGroupCollapse(r.data) end end)

	r.allBtn = CreateFrame("Button", nil, r)
	r.allBtn:SetSize(18, 18)
	r.allBtn:SetPoint("LEFT", r, "LEFT", 22, 0)
	r.allBox = r.allBtn:CreateTexture(nil, "ARTWORK")
	r.allBox:SetAllPoints()
	r.allBox:SetTexture(BOX_TEX)
	r.allCheck = r.allBtn:CreateTexture(nil, "OVERLAY")
	r.allCheck:SetAllPoints()
	r.allCheck:SetTexture(BOXCHECK_TEX)
	r.allBtn:SetScript("OnClick", function() if r.kind == "header" then ToggleGroupSelect(r.data) end end)
	r.allBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Select all in this zone", 1, 1, 1)
		GameTooltip:Show()
	end)
	r.allBtn:SetScript("OnLeave", HideTooltip)
	r.box = r:CreateTexture(nil, "ARTWORK")
	r.box:SetSize(18, 18)
	r.box:SetTexture(BOX_TEX)
	r.boxCheck = r:CreateTexture(nil, "OVERLAY")
	r.boxCheck:SetAllPoints(r.box)
	r.boxCheck:SetTexture(BOXCHECK_TEX)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(16, 16)

	r.xp = r:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	r.xp:SetJustifyH("RIGHT")
	r.title = r:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	r.title:SetJustifyH("LEFT")
	r.title:SetWordWrap(false)
	r.sub = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	r.sub:SetJustifyH("LEFT")
	r.sub:SetJustifyV("TOP")
	r.rIcons, r.rLabels = {}, {}

	r:SetScript("OnClick", OnRowClick)
	r:SetScript("OnEnter", OnRowEnter)
	r:SetScript("OnLeave", HideTooltip)
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
	r.box:Hide(); r.boxCheck:Hide(); r.icon:Hide(); r.sub:Hide(); r.accent:Hide(); r.cur:Hide()
	HideRowRewards(r)
	r.bg:SetColorTexture(0, 0, 0, 0.35)

	r.expandBtn:Show()
	r.expand:SetTexture(db.collapsed[g.title] and PLUS_TEX or MINUS_TEX)

	local titleX = 22
	if mode then
		local on, total = GroupSelection(g)
		r.allBtn:Show()
		r.allBtn:SetEnabled(total > 0 and not busy)
		r.allBox:SetDesaturated(total == 0)
		r.allCheck:SetShown(on > 0)
		r.allCheck:SetAlpha(on == total and 1 or 0.45) -- faded check: some selected
		titleX = 42
	else
		r.allBtn:Hide()
	end

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

	r.title:ClearAllPoints()
	r.title:SetPoint("LEFT", r, "LEFT", titleX, 0)
	r.title:SetPoint("RIGHT", r.xp, "LEFT", -4, 0)
	r.title:SetText(g.title)
	r.title:SetTextColor(1, 0.82, 0)
end

local function SetupQuest(r, q, width)
	r.kind, r.data = "quest", q
	r:SetWidth(width)
	r.expandBtn:Hide()
	r.allBtn:Hide()

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
		local comp = Clean(SafeCall(GetQuestLogCompletionText, q.index))
		if type(comp) == "string" and comp ~= "" then
			lines[#lines + 1] = GREY .. comp .. "|r"
		end
	elseif q.state == "failed" then
		lines[#lines + 1] = "|cffff5555Failed|r"
	else
		for _, o in ipairs(GetObjectives(q.questID)) do
			local text = Clean(o.text)
			if text and text ~= "" then
				lines[#lines + 1] = (o.finished and GREY or "|cffe6e6e6") .. "- " .. text .. "|r"
			end
		end
	end

	local innerX = x + 6
	local innerW = width - innerX - 8
	r.sub:ClearAllPoints()
	r.sub:SetWidth(innerW)
	r.sub:SetPoint("TOPLEFT", r, "TOPLEFT", innerX, -21)
	local y = 21
	if #lines > 0 then
		r.sub:SetText(table.concat(lines, "\n"))
		r.sub:Show()
		y = y + r.sub:GetStringHeight() + 2
	else
		r.sub:SetText("")
		r.sub:Hide()
	end

	-- optional reward icons
	local iconN, labelN = 0, 0
	if db.listRewards then
		local rw = GetRewards(q.questID)
		local perRow = math.max(1, math.floor((innerW + 3) / (ICON + 3)))
		local function Block(label, list)
			if #list == 0 then return end
			labelN = labelN + 1
			local fs = GetRowLabel(r, labelN)
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", r, "TOPLEFT", innerX, -(y + 2))
			fs:SetText(label)
			y = y + 14
			for i, d in ipairs(list) do
				iconN = iconN + 1
				local b = GetRowIcon(r, iconN)
				b.reward = d
				b.Icon:SetTexture(d.texture or QUESTION_ICON)
				if d.isUsable == false then b.Icon:SetVertexColor(1, 0.2, 0.2) else b.Icon:SetVertexColor(1, 1, 1) end
				SetIconBorder(b.Border, d.quality)
				b.Count:SetText((type(d.count) == "number" and d.count > 1) and d.count or "")
				local col, ro = (i - 1) % perRow, math.floor((i - 1) / perRow)
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", r, "TOPLEFT", innerX + col * (ICON + 3), -(y + ro * (ICON + 3)))
			end
			y = y + math.ceil(#list / perRow) * (ICON + 3) + 1
		end
		Block("Choose one:", rw.choices)
		Block(#rw.choices > 0 and "You will also receive:" or "You will receive:", rw.items)
	end
	HideRowRewards(r, iconN + 1, labelN + 1)
	r:SetHeight(y + 5)

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

	local isCurrent = popout and popout:IsShown() and detailQuestID == q.questID
	r.cur:SetShown(isCurrent and not isSel and true or false)
	if isCurrent and not isSel and not r.accent:IsShown() then
		r.accent:SetColorTexture(1, 0.82, 0, 1)
		r.accent:Show()
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
	if #groups == 0 then
		emptyText:SetText(db.filterItems and totalQuests > 0 and "No quests with quest items in your bags."
			or "Your quest log is empty.")
		emptyText:Show()
	else
		emptyText:Hide()
	end
end

---------------------------------------------------------------------------
-- Detail view
---------------------------------------------------------------------------

local function CreateDetailWidgets()
	local function FS(font)
		local fs = detailContent:CreateFontString(nil, "ARTWORK", font)
		fs:SetJustifyH("LEFT")
		fs:SetJustifyV("TOP")
		return fs
	end
	detail.title = FS("GameFontNormalLarge")
	detail.status = FS("GameFontNormal")
	detail.objHeader = FS("GameFontNormalLarge")
	detail.objText = FS("GameFontHighlight")
	detail.objList = FS("GameFontHighlight")
	detail.descHeader = FS("GameFontNormalLarge")
	detail.descText = FS("GameFontHighlight")
	detail.rewHeader = FS("GameFontNormalLarge")
	detail.choiceLabel = FS("GameFontHighlight")
	detail.itemsLabel = FS("GameFontHighlight")
	detail.extraText = FS("GameFontHighlight")

	detail.statusBg = detailContent:CreateTexture(nil, "BACKGROUND")
	detail.statusBg:SetPoint("TOPLEFT", detail.status, "TOPLEFT", -4, 4)
	detail.statusBg:SetPoint("BOTTOMRIGHT", detail.status, "BOTTOMRIGHT", 4, -4)
end

-- reward item button like the default quest log: icon, count, name in a frame
local function GetRewardButton(i)
	local b = detailButtons[i]
	if not b then
		b = CreateFrame("Button", nil, detailContent)
		b:SetHeight(42)
		b.NameBg = b:CreateTexture(nil, "BACKGROUND")
		b.NameBg:SetColorTexture(0, 0, 0, 0.45)
		b.Icon = b:CreateTexture(nil, "ARTWORK")
		b.Icon:SetSize(38, 38)
		b.Icon:SetPoint("LEFT", b, "LEFT", 1, 0)
		b.NameBg:SetPoint("TOPLEFT", b.Icon, "TOPRIGHT", -2, -2)
		b.NameBg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 3)
		b.Border = b:CreateTexture(nil, "OVERLAY")
		b.Border:SetTexture(ICON_BORDER)
		b.Border:SetAllPoints(b.Icon)
		b.Count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		b.Count:SetPoint("BOTTOMRIGHT", b.Icon, "BOTTOMRIGHT", -2, 2)
		b.Name = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		b.Name:SetPoint("LEFT", b.Icon, "RIGHT", 6, 0)
		b.Name:SetJustifyH("LEFT")
		if b.Name.SetMaxLines then b.Name:SetMaxLines(2) end
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
		hl:SetBlendMode("ADD")
		hl:SetAllPoints(b.Icon)
		b:SetScript("OnEnter", ShowRewardTooltip)
		b:SetScript("OnLeave", HideTooltip)
		b.UpdateTooltip = ShowRewardTooltip
		b:SetScript("OnClick", RewardModifiedClick)
		detailButtons[i] = b
	end
	b:Show()
	return b
end

local function SetupRewardButton(b, d, w)
	b.reward = d
	b:SetWidth(w)
	b.Icon:SetTexture(d.texture or QUESTION_ICON)
	if d.isUsable == false then b.Icon:SetVertexColor(1, 0.2, 0.2) else b.Icon:SetVertexColor(1, 1, 1) end
	SetIconBorder(b.Border, d.quality)
	b.Count:SetText((type(d.count) == "number" and d.count > 1) and d.count or "")
	b.Name:SetWidth(w - 48)
	b.Name:SetText(d.name or RETRIEVING_ITEM_INFO or "Loading...")
	b.Name:SetTextColor(QualityColor(d.quality))
end

local function RenderDetail(q)
	if not q then return end
	SafeCall(C_QuestLog.SetSelectedQuest, q.questID)
	local width = math.max(200, (detailScroll:GetWidth() or 300) - 8)
	detailContent:SetWidth(width + 8)
	local y = 6
	local btnN = 0

	local function Text(fs, text, gap)
		if not text or text == "" then
			fs:Hide()
			return
		end
		fs:ClearAllPoints()
		fs:SetWidth(width)
		fs:SetText(text)
		fs:SetPoint("TOPLEFT", detailContent, "TOPLEFT", 6, -y)
		fs:Show()
		y = y + fs:GetStringHeight() + (gap or 6)
	end

	local function Items(list)
		local cols = width >= 300 and 2 or 1
		local bw = math.floor((width - (cols - 1) * 6) / cols)
		for i, d in ipairs(list) do
			btnN = btnN + 1
			local b = GetRewardButton(btnN)
			SetupRewardButton(b, d, bw)
			local col, ro = (i - 1) % cols, math.floor((i - 1) / cols)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", detailContent, "TOPLEFT", 6 + col * (bw + 6), -(y + ro * 44))
		end
		y = y + math.ceil(#list / cols) * 44 + 6
	end

	-- title
	if q.state == "complete" then
		detail.title:SetTextColor(0.45, 1, 0.45)
	elseif q.state == "failed" then
		detail.title:SetTextColor(1, 0.35, 0.35)
	else
		detail.title:SetTextColor(QuestColor(q))
	end
	Text(detail.title, QuestTitle(q), 10)

	-- status banner
	if q.state == "complete" then
		local comp = Clean(SafeCall(GetQuestLogCompletionText, q.index))
		local extra = (type(comp) == "string" and comp ~= "") and ("\n|cffdddddd" .. comp .. "|r") or ""
		detail.statusBg:SetColorTexture(0.10, 0.50, 0.10, 0.35)
		detail.statusBg:Show()
		y = y + 4
		Text(detail.status, IconStr(READY_ICON, 18) .. " " .. GREEN .. "READY TO TURN IN|r" .. extra, 14)
	elseif q.state == "failed" then
		detail.statusBg:SetColorTexture(0.5, 0.08, 0.08, 0.30)
		detail.statusBg:Show()
		y = y + 4
		Text(detail.status, IconStr(FAILED_ICON, 18) .. " |cffff5555FAILED|r", 14)
	else
		detail.statusBg:Hide()
		Text(detail.status, nil)
	end

	-- objectives
	local desc, objSummary = SafeCall(GetQuestLogQuestText, q.index)
	desc, objSummary = Clean(desc), Clean(objSummary)
	local objLines = {}
	for _, o in ipairs(GetObjectives(q.questID)) do
		local text = Clean(o.text)
		if text and text ~= "" then
			if o.finished then
				objLines[#objLines + 1] = IconStr(READY_ICON, 14) .. " " .. GREY .. text .. "|r"
			else
				objLines[#objLines + 1] = "- " .. text
			end
		end
	end
	local hasObj = (type(objSummary) == "string" and objSummary ~= "") or #objLines > 0
	Text(detail.objHeader, hasObj and (QUEST_OBJECTIVES or "Quest Objectives") or nil, 4)
	Text(detail.objText, type(objSummary) == "string" and objSummary or nil, 6)
	Text(detail.objList, table.concat(objLines, "\n"), 14)

	-- description
	local hasDesc = type(desc) == "string" and desc ~= ""
	Text(detail.descHeader, hasDesc and (QUEST_DESCRIPTION or "Description") or nil, 4)
	Text(detail.descText, hasDesc and desc or nil, 14)

	-- rewards, laid out like the default log
	local rw = GetRewards(q.questID)
	local money = Clean(SafeCall(GetQuestLogRewardMoney, q.questID))
	if type(money) ~= "number" then money = 0 end
	local extras = {}
	if money > 0 and GetCoinTextureString then extras[#extras + 1] = GetCoinTextureString(money) end
	if q.xp > 0 then
		local pct = LevelPercent(q.xp)
		extras[#extras + 1] = ("%s: %s+%s|r%s"):format(EXPERIENCE_COLON and EXPERIENCE_COLON:gsub(":%s*$", "") or "Experience",
			XP_COLOR, FormatNumber(q.xp), pct and (GREY .. "  (" .. pct .. "% of a level)|r") or "")
	end
	local hasRewards = #rw.choices > 0 or #rw.items > 0 or #extras > 0
	Text(detail.rewHeader, hasRewards and (QUEST_REWARDS or "Rewards") or nil, 6)
	if #rw.choices > 0 then
		Text(detail.choiceLabel, TXT_CHOOSE, 6)
		Items(rw.choices)
	else
		Text(detail.choiceLabel, nil)
	end
	if #rw.items > 0 or #extras > 0 then
		Text(detail.itemsLabel, #rw.choices > 0 and TXT_ALSO or TXT_RECEIVE, 6)
		if #rw.items > 0 then Items(rw.items) end
	else
		Text(detail.itemsLabel, nil)
	end
	Text(detail.extraText, table.concat(extras, "\n"), 10)

	for i = btnN + 1, #detailButtons do detailButtons[i]:Hide() end
	detailContent:SetHeight(y + 8)
end

---------------------------------------------------------------------------
-- Bottom bar / header text
---------------------------------------------------------------------------

-- lay out `list` along the bottom of `owner`, hiding the rest of `pool`
local function LayoutButtons(owner, pool, list)
	for _, b in pairs(pool) do b:Hide() end
	local n = #list
	if n == 0 then return end
	local total = owner:GetWidth() - 34 -- room for the resize grip
	local w = (total - (n - 1) * 4) / n
	for i, b in ipairs(list) do
		b:ClearAllPoints()
		b:SetWidth(w)
		b:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", 8 + (i - 1) * (w + 4), 5)
		b:Show()
	end
end

local function UpdateDetailButtons(set)
	local q = questsByID[detailQuestID]
	set.track:SetText(q and IsTracked(q.questID) and "Untrack" or "Track")
	set.share:SetEnabled(q and not busy and IsInGroup() and SafeCall(C_QuestLog.IsPushableQuest, q.questID) == true or false)
	local canAbandon = q and (not C_QuestLog.CanAbandonQuest or SafeCall(C_QuestLog.CanAbandonQuest, q.questID) == true)
	set.abandon:SetEnabled((canAbandon and not busy) and true or false)
end

function UpdateBottom()
	if not frame then return end
	if popout and popout:IsShown() then
		UpdateDetailButtons(popButtons)
		LayoutButtons(popout, popButtons, { popButtons.track, popButtons.share, popButtons.abandon })
	end
	if view == "detail" then
		UpdateDetailButtons(buttons)
		LayoutButtons(frame, buttons, { buttons.back, buttons.track, buttons.share, buttons.abandon })
	elseif mode then
		local n = #SelectedList()
		buttons.action:SetText(("%s (%d)"):format(mode == "share" and "Share" or "Abandon", n))
		local ok = n > 0 and not busy and (mode ~= "share" or IsInGroup())
		buttons.action:SetEnabled(ok and true or false)
		LayoutButtons(frame, buttons, { buttons.all, buttons.none, buttons.action, buttons.cancel })
	else
		buttons.shareMode:SetEnabled(not busy)
		buttons.abandonMode:SetEnabled(not busy)
		LayoutButtons(frame, buttons, { buttons.shareMode, buttons.abandonMode })
	end

	if busy then
		headerText:SetText("|cffffd100Working...|r")
	elseif mode == "share" then
		headerText:SetText(IsInGroup() and "|cff66aaffSHARE MODE|r - click quests to select"
			or "|cff66aaffSHARE MODE|r - |cffff6666join a group to share|r")
	elseif mode == "abandon" then
		headerText:SetText("|cffff5544ABANDON MODE|r - click quests to select")
	else
		local max = SafeCall(C_QuestLog.GetMaxNumQuestsCanAccept) or MAX_QUESTS or 0
		if db.filterItems then
			headerText:SetText(("Showing |cffffffff%d|r of %d (%d/%d)"):format(shownQuests, totalQuests, totalQuests, max))
		else
			headerText:SetText(("Quests: |cffffffff%d/%d|r"):format(totalQuests, max))
		end
	end
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

-- move the details scroll area into the log's inset or the separate panel
function AttachDetail(container)
	if detailScroll:GetParent() == container then return end
	detailScroll:SetParent(container)
	detailScroll:ClearAllPoints()
	detailScroll:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -4)
	detailScroll:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", detailScroll.padR, 4)
end

function Refresh()
	if not frame or not frame:IsShown() then return end
	EnsureExpanded()
	groups = BuildQuestList()

	for id in pairs(selected) do
		if not questsByID[id] then selected[id] = nil end
	end
	if detailQuestID and not questsByID[detailQuestID] then
		detailQuestID = nil
		if view == "detail" then view = "list" end
	end

	if db.detailPopout then
		-- details live in the separate panel; the log always shows the list
		view = "list"
		if detailQuestID and popout:IsShown() then
			AttachDetail(popInset)
			detailScroll:Show()
			RenderDetail(questsByID[detailQuestID])
		elseif popout:IsShown() then
			popout:Hide()
		end
		listScroll:Show()
		RenderList()
	else
		if popout:IsShown() then popout:Hide() end
		AttachDetail(inset)
		listScroll:SetShown(view == "list")
		detailScroll:SetShown(view == "detail")
		if view == "list" then
			RenderList()
		else
			emptyText:Hide()
			RenderDetail(questsByID[detailQuestID])
		end
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

local function SetFrameTitle(f, text)
	if f.SetTitle then
		f:SetTitle(text)
	elseif f.TitleText then
		f.TitleText:SetText(text)
	else
		local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		t:SetPoint("TOP", 0, -6)
		t:SetText(text)
	end
end

-- a framed window: template if available, plain dark frame otherwise
local function CreateWindow(name, parent, ...)
	local tpl = FirstTemplate(...)
	local f = CreateFrame("Frame", name, parent, tpl)
	if tpl == "ButtonFrameTemplate" and ButtonFrameTemplate_HidePortrait then
		ButtonFrameTemplate_HidePortrait(f)
	end
	if not tpl then
		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.05, 0.05, 0.05, 0.94)
	end
	if not f.CloseButton then
		local closeT = FirstTemplate("UIPanelCloseButton")
		f.CloseButton = CreateFrame("Button", nil, f, closeT)
		f.CloseButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
		if not closeT then
			f.CloseButton:SetSize(20, 20)
			f.CloseButton:SetNormalFontObject("GameFontNormal")
			f.CloseButton:SetText("x")
		end
	end
	f.CloseButton:SetScript("OnClick", function() f:Hide() end)
	return f
end

local function AnchorPopout()
	popout:ClearAllPoints()
	popout:SetPoint("TOPLEFT", frame, "TOPRIGHT", 2, 0)
	popout:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 2, 0)
	popout:SetWidth(math.min(700, math.max(280, db.popoutWidth or 360)))
end

-- the separate quest details panel, attached to the log's right side
local function CreatePopout()
	popout = CreateWindow("QuestLogPlusDetailFrame", frame, "ButtonFrameTemplate", "BasicFrameTemplateWithInset")
	popout:SetToplevel(true)
	popout:EnableMouse(true)
	popout:SetResizable(true)
	if popout.SetResizeBounds then
		popout:SetResizeBounds(280, MIN_H, 700, MAX_H)
	elseif popout.SetMinResize then
		popout:SetMinResize(280, MIN_H)
		popout:SetMaxResize(700, MAX_H)
	end
	SetFrameTitle(popout, "Quest Details")
	popout.CloseButton:SetScript("OnClick", function()
		detailQuestID = nil
		popout:Hide()
	end)

	popInset = popout.Inset
	if not popInset then
		local insetT = FirstTemplate("InsetFrameTemplate")
		popInset = CreateFrame("Frame", nil, popout, insetT)
		if not insetT then
			local ibg = popInset:CreateTexture(nil, "BACKGROUND")
			ibg:SetAllPoints()
			ibg:SetColorTexture(0, 0, 0, 0.5)
		end
	end
	popInset:ClearAllPoints()
	popInset:SetPoint("TOPLEFT", popout, "TOPLEFT", 4, -26)
	popInset:SetPoint("BOTTOMRIGHT", popout, "BOTTOMRIGHT", -6, 30)

	popButtons.track = MakeButton(popout, "Track", function()
		if detailQuestID then ToggleTrack(detailQuestID) end
	end)
	popButtons.share = MakeButton(popout, "Share", function()
		if detailQuestID then ShareQuests({ detailQuestID }) end
	end)
	popButtons.abandon = MakeButton(popout, "Abandon", function()
		if detailQuestID then AskAbandon({ detailQuestID }) end
	end)

	-- width grip (the height always follows the log)
	local grip = MakeGrip(popout)
	grip:SetPoint("BOTTOMRIGHT", popout, "BOTTOMRIGHT", -3, 4)
	grip:SetFrameLevel(popout:GetFrameLevel() + 10)
	grip:SetScript("OnMouseDown", function(_, btn)
		if btn ~= "LeftButton" then return end
		logMoving = true
		popout:StartSizing("RIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		popout:StopMovingOrSizing()
		logMoving = false
		db.popoutWidth = math.floor(popout:GetWidth() + 0.5)
		AnchorPopout()
		ApplyMapLayout()
		Refresh()
	end)

	popout:SetScript("OnShow", ScheduleMapLayout) -- an attached map moves right
	popout:SetScript("OnHide", function()
		ScheduleMapLayout()
		RequestRefresh()
	end)
	popout:SetScript("OnSizeChanged", function() RequestRefresh() end)
	AnchorPopout()
	popout:Hide()
end

local function CreateUI()
	BUTTON_T = FirstTemplate("UIPanelButtonTemplate")
	local frameT = FirstTemplate("ButtonFrameTemplate", "PortraitFrameTemplate", "BasicFrameTemplateWithInset")
	frame = CreateFrame("Frame", "QuestLogPlusFrame", UIParent, frameT or FirstTemplate("BackdropTemplate"))
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	if frame.SetResizeBounds then
		frame:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
	elseif frame.SetMinResize then
		frame:SetMinResize(MIN_W, MIN_H)
		frame:SetMaxResize(MAX_W, MAX_H)
	end
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
		local closeT = FirstTemplate("UIPanelCloseButton")
		close = CreateFrame("Button", nil, frame, closeT)
		close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
		if not closeT then
			close:SetSize(20, 20)
			close:SetNormalFontObject("GameFontNormal")
			close:SetText("x")
		end
	end
	close:SetScript("OnClick", function() frame:Hide() end)

	-- inset
	inset = frame.Inset
	if not inset then
		local insetT = FirstTemplate("InsetFrameTemplate")
		inset = CreateFrame("Frame", nil, frame, insetT)
		if not insetT then
			local ibg = inset:CreateTexture(nil, "BACKGROUND")
			ibg:SetAllPoints()
			ibg:SetColorTexture(0, 0, 0, 0.5)
		end
	end
	inset:ClearAllPoints()
	inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -60)
	inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 30)

	-- toolbar: quest count, settings gear, map button
	mapButton = MakeButton(frame, "Show Map", ToggleMapSetting)
	mapButton:SetSize(84, 20)
	mapButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -32)
	UpdateMapButton()

	local gear = CreateFrame("Button", nil, frame)
	gear:SetSize(20, 20)
	gear:SetPoint("RIGHT", mapButton, "LEFT", -4, 0)
	local gearTex = gear:CreateTexture(nil, "ARTWORK")
	gearTex:SetAllPoints()
	if C_Texture and C_Texture.GetAtlasInfo and SafeCall(C_Texture.GetAtlasInfo, "QuestLog-icon-setting") then
		gearTex:SetAtlas("QuestLog-icon-setting")
	else
		gearTex:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
	end
	local gearHl = gear:CreateTexture(nil, "HIGHLIGHT")
	gearHl:SetAllPoints()
	gearHl:SetColorTexture(1, 1, 1, 0.2)
	gear:SetScript("OnClick", function() QuestLogPlus_ToggleSettings() end)
	gear:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Settings", 1, 1, 1)
		GameTooltip:Show()
	end)
	gear:SetScript("OnLeave", HideTooltip)

	headerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	headerText:SetPoint("TOPLEFT", frame, "TOPLEFT", 62, -36)
	headerText:SetPoint("TOPRIGHT", gear, "TOPLEFT", -6, -2)
	headerText:SetJustifyH("LEFT")
	headerText:SetWordWrap(false)

	-- scroll areas
	listScroll, listContent = MakeScroll(inset)
	detailScroll, detailContent = MakeScroll(inset)
	detailScroll:Hide()
	CreateDetailWidgets()
	CreatePopout()

	emptyText = inset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	emptyText:SetPoint("CENTER")
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

	-- resize grip
	local grip = MakeGrip(frame)
	grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 4)
	grip:SetFrameLevel(frame:GetFrameLevel() + 10)
	grip:SetScript("OnMouseDown", function(_, btn)
		if btn ~= "LeftButton" then return end
		logMoving = true
		frame:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		logMoving = false
		SaveLogGeometry()
		ApplyMapLayout()
		Refresh()
	end)

	-- scripts
	frame:SetScript("OnDragStart", StartLogMove)
	frame:SetScript("OnDragStop", StopLogMove)
	-- keep the attached map next to the log: live while moving/resizing, else a light check
	frame:SetScript("OnUpdate", function(_, elapsed)
		if logMoving then
			if MapActive() then ApplyMapLayout() end
		else
			WatchMap(elapsed)
		end
	end)
	frame:SetScript("OnShow", function()
		if PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_OPEN then PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN) end
		AdaptToPanels()
		Refresh()
		if db.showMap then ShowMap() end
	end)
	frame:SetScript("OnHide", function()
		if PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_CLOSE then PlaySound(SOUNDKIT.IG_QUEST_LOG_CLOSE) end
		HideTooltip()
		if logMoving then
			frame:StopMovingOrSizing()
			logMoving = false
			SaveLogGeometry()
		end
		if not busy then
			mode = nil
			wipe(selected)
		end
		HideMap()
	end)
	frame:SetScript("OnSizeChanged", function() RequestRefresh() end)

	RestoreLogGeometry()
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
-- Move aside for game windows (character sheet, spellbook, vendors, ...)
-- The log keeps a home position; when a game window would overlap it, the
-- log moves to the right of that window, and returns when it closes.
---------------------------------------------------------------------------

local KNOWN_PANELS = {
	"CharacterFrame", "PlayerSpellsFrame", "SpellBookFrame", "PlayerTalentFrame", "TalentFrame",
	"ProfessionsFrame", "TradeSkillFrame", "FriendsFrame", "GossipFrame", "QuestFrame",
	"MerchantFrame", "MailFrame", "OpenMailFrame", "TradeFrame", "BankFrame", "AuctionHouseFrame",
	"ClassTrainerFrame", "TaxiFrame", "FlightMapFrame", "PVEFrame", "CommunitiesFrame",
	"AchievementFrame", "CollectionsJournal", "EncounterJournal", "DressUpFrame", "LootFrame",
	"InspectFrame", "GuildBankFrame", "ItemUpgradeFrame", "ItemSocketingFrame",
}

local function GameWindowRects()
	local list, seen = {}, {}
	local function Add(f)
		if not f or seen[f] or f == frame or f == popout or f == WorldMapFrame then return end
		seen[f] = true
		if not f.IsShown or not f:IsShown() then return end
		local l, r, eff = Clean(f:GetLeft()), Clean(f:GetRight()), Clean(f:GetEffectiveScale())
		if not l or not r or not eff then return end
		local k = eff / UIParent:GetEffectiveScale()
		list[#list + 1] = { left = l * k, right = r * k }
	end
	if GetUIPanel then
		for _, area in ipairs({ "left", "center", "right", "doublewide" }) do
			Add(SafeCall(GetUIPanel, area))
		end
	end
	for _, name in ipairs(KNOWN_PANELS) do Add(_G[name]) end
	table.sort(list, function(a, b) return a.left < b.left end)
	return list
end

function AdaptToPanels()
	if not frame or not frame:IsShown() or logMoving then return end
	if not db.gameWindow then
		if logPushed then
			logPushed = false
			RestoreLogGeometry()
			ApplyMapLayout()
		end
		return
	end
	RestoreLogGeometry() -- home position
	local x, y = TopLeftInUI(frame)
	if not x then return end
	local w = frame:GetWidth()
	local startX = x
	for _, p in ipairs(GameWindowRects()) do
		if p.left < x + w and p.right > x then x = p.right + 4 end
	end
	logPushed = x ~= startX
	if logPushed then
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
	end
	ApplyMapLayout()
end

local adaptPending = false
local function ScheduleAdapt()
	if adaptPending then return end
	adaptPending = true
	C_Timer.After(0, function()
		adaptPending = false
		AdaptToPanels()
	end)
end

local panelsHooked = false
local function HookPanels()
	if panelsHooked then return end
	panelsHooked = true
	for _, fn in ipairs({ "ShowUIPanel", "HideUIPanel", "UpdateUIPanelPositions" }) do
		if type(_G[fn]) == "function" then hooksecurefunc(fn, ScheduleAdapt) end
	end
	-- windows that open without the panel manager
	for _, name in ipairs(KNOWN_PANELS) do
		local f = _G[name]
		if f and f.HookScript then
			f:HookScript("OnShow", ScheduleAdapt)
			f:HookScript("OnHide", ScheduleAdapt)
		end
	end
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local OPTIONS = {
	{ "showMap", "Show the map next to the quest log",
		"Attaches the world map to the log's right side, scaled to the log's height, like one window. Drag the map's title bar or the log to move them together; resize the log and the map follows." },
	{ "detailPopout", "Open quest details in a separate panel",
		"Clicking a quest opens its details in a panel on the log's right side (between the log and the map) instead of inside the log." },
	{ "listRewards", "Reward icons in the quest list",
		"Small reward icons under each quest, with \"Choose one\" / \"You will receive\" above them. Hover an icon for the item tooltip." },
	{ "filterItems", "Only quests with quest items",
		"Only show quests you hold quest items for: a usable quest item, or at least one item collected for an objective." },
	{ "showLevel", "Show quest levels", "Shows [12] in front of each quest name." },
	{ "completedFirst", "Ready-to-turn-in quests at the top", "Completed quests sort to the top of their zone." },
	{ "gameWindow", "Move aside for game windows",
		"When the character sheet, spellbook, a vendor or another game window would cover the log, the log moves to its right, and moves back when it closes." },
	{ "hideDefaultMapPanel", "Close the map's own quest list",
		"When Quest Log Plus opens the map, close the map's built-in quest list so quests aren't shown twice." },
	{ "takeOverKey", "Quest log key opens Quest Log Plus",
		"Your quest log key binding (L by default) opens this log. Turn it off to get the default quest log back on that key." },
}

local OPTION_LABEL = {}
for _, o in ipairs(OPTIONS) do OPTION_LABEL[o[1]] = o[2] end

local function SyncChecks()
	for _, cb in ipairs(allChecks) do cb:SetChecked(db[cb.key] and true or false) end
end

function SetOption(key, value)
	db[key] = value and true or false
	if key == "showMap" then
		if frame and frame:IsShown() then
			if db.showMap then ShowMap() else HideMap() end
		end
		UpdateMapButton()
	elseif key == "takeOverKey" then
		ApplyKeyOverride()
	elseif key == "detailPopout" then
		if frame and detailQuestID then
			if db.detailPopout then
				view = "list"
				if frame:IsShown() then popout:Show() end
			else
				view = "detail"
			end
		end
		if frame then Refresh() end
	elseif key == "gameWindow" then
		AdaptToPanels()
	elseif key == "hideDefaultMapPanel" then
		if db.hideDefaultMapPanel and MapActive() then HideDefaultQuestPanel() end
	elseif frame then
		Refresh()
	end
	SyncChecks()
end

local function ResetGeometry()
	db.pos, db.size, db.popoutWidth = nil, nil, 360
	if frame then
		RestoreLogGeometry()
		AnchorPopout()
		AdaptToPanels()
		ApplyMapLayout()
	end
	Print("Window and map position/size reset.")
end

local function BuildOptions(parent, x, y)
	for _, o in ipairs(OPTIONS) do
		local cb = MakeCheck(parent, o[2], o[3], o[1])
		cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
		y = y - 26
	end
	local reset = MakeButton(parent, "Reset window positions", ResetGeometry)
	reset:SetSize(190, 22)
	reset:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 4, y - 8)
	return y - 30
end

function QuestLogPlus_ToggleSettings()
	if not db then return end
	if not settingsFrame then
		settingsFrame = CreateWindow("QuestLogPlusSettingsFrame", UIParent, "BasicFrameTemplateWithInset", "ButtonFrameTemplate")
		settingsFrame:SetFrameStrata("DIALOG")
		settingsFrame:SetToplevel(true)
		settingsFrame:SetClampedToScreen(true)
		settingsFrame:SetMovable(true)
		settingsFrame:EnableMouse(true)
		settingsFrame:RegisterForDrag("LeftButton")
		settingsFrame:SetScript("OnDragStart", settingsFrame.StartMoving)
		settingsFrame:SetScript("OnDragStop", settingsFrame.StopMovingOrSizing)
		SetFrameTitle(settingsFrame, "Quest Log Plus Settings")
		local bottom = BuildOptions(settingsFrame, 14, -32)
		settingsFrame:SetSize(330, -bottom + 14)
		settingsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
		settingsFrame:SetScript("OnShow", SyncChecks)
		settingsFrame:Hide()
		tinsert(UISpecialFrames, "QuestLogPlusSettingsFrame")
	end
	settingsFrame:SetShown(not settingsFrame:IsShown())
end

-- the same options under Options > AddOns
local function RegisterBlizzardOptions()
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
	local panel = CreateFrame("Frame")
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
	title:SetText("Quest Log Plus")
	BuildOptions(panel, 14, -48)
	panel:SetScript("OnShow", SyncChecks)
	local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Quest Log Plus")
	if ok and category then pcall(Settings.RegisterAddOnCategory, category) end
end

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

local function OnOff(v) return v and "|cff55ff55on|r" or "|cffff5555off|r" end

local SLASH_TOGGLES = {
	map = "showMap", popout = "detailPopout", rewards = "listRewards", items = "filterItems",
	level = "showLevel", sort = "completedFirst", windows = "gameWindow",
	panel = "hideDefaultMapPanel", key = "takeOverKey",
}
local SLASH_ORDER = { "map", "popout", "rewards", "items", "level", "sort", "windows", "panel", "key" }

SLASH_QUESTLOGPLUS1 = "/qlp"
SLASH_QUESTLOGPLUS2 = "/questlogplus"
SlashCmdList.QUESTLOGPLUS = function(msg)
	msg = strlower(strtrim(msg or ""))
	if msg == "" then
		QuestLogPlus_Toggle()
	elseif msg == "config" or msg == "settings" or msg == "options" then
		QuestLogPlus_ToggleSettings()
	elseif SLASH_TOGGLES[msg] then
		local key = SLASH_TOGGLES[msg]
		SetOption(key, not db[key])
		Print(OPTION_LABEL[key] .. ": " .. OnOff(db[key]))
	elseif msg == "reset" then
		ResetGeometry()
	else
		Print("commands:")
		Print("/qlp - toggle the log")
		Print("/qlp config - settings window")
		for _, cmd in ipairs(SLASH_ORDER) do
			local key = SLASH_TOGGLES[cmd]
			Print(("/qlp %s - %s %s"):format(cmd, OPTION_LABEL[key], OnOff(db[key])))
		end
		Print("/qlp reset - reset log and map position/size")
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
Register("PLAYER_LEVEL_UP")
for _, ev in ipairs({
	"QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
	"QUEST_WATCH_LIST_CHANGED", "UNIT_QUEST_LOG_CHANGED", "GROUP_ROSTER_UPDATE",
	"QUEST_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED", "BAG_UPDATE_DELAYED",
}) do Register(ev) end

events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON_NAME then
			QuestLogPlusDB = QuestLogPlusDB or {}
			-- 1.2: new defaults for settings saved by older versions
			if (QuestLogPlusDB.settingsVersion or 1) < 2 then
				QuestLogPlusDB.detailPopout = true
				QuestLogPlusDB.listRewards = true
				QuestLogPlusDB.filterItems = false
				QuestLogPlusDB.map = nil
				QuestLogPlusDB.settingsVersion = 2
			end
			CopyDefaults(DEFAULTS, QuestLogPlusDB)
			db = QuestLogPlusDB
		elseif arg1 == "Blizzard_WorldMap" then
			HookMap()
		end
	elseif event == "PLAYER_LOGIN" then
		CreateUI()
		HookMap()
		HookPanels()
		RegisterBlizzardOptions()
		ApplyKeyOverride()
	elseif event == "UPDATE_BINDINGS" then
		ApplyKeyOverride()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pendingBind then ApplyKeyOverride() end
		if MapActive() then ScheduleMapLayout() end
	elseif event == "PLAYER_LEVEL_UP" then
		wipe(rewardCache)
		RequestRefresh()
	elseif event == "UNIT_QUEST_LOG_CHANGED" then
		if arg1 == "player" then RequestRefresh() end
	else
		RequestRefresh()
	end
end)
