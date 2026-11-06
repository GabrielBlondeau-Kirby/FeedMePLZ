-- FeedMePLZ : deux boutons flottants (nourriture simple / nourriture à stats)
-- qui choisissent la nourriture selon un classement de critères configurable.
local ADDON = ...
local PREFIX = "|cffff8800FeedMePLZ|r : "

---------------------------------------------------------------------------
-- Compatibilité API (Classic récent : C_Container / C_Item / C_Spell)
---------------------------------------------------------------------------
local GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local GetItemID   = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID

local function GetSlotCount(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        return info and info.stackCount or 0
    end
    local _, count = GetContainerItemInfo(bag, slot)
    return count or 0
end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return (GetSpellInfo(id))
end

local GetItemSpellCompat = (C_Item and C_Item.GetItemSpell) or GetItemSpell
local GetItemInfoCompat  = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemIconCompat  = (C_Item and C_Item.GetItemIconByID) or GetItemIcon

---------------------------------------------------------------------------
-- Réglages
---------------------------------------------------------------------------
local CRITERIA = {
    stackLow  = { label = "Stack la plus basse",  value = function(e) return e.count end,  low = true  },
    stackHigh = { label = "Stack la plus haute",  value = function(e) return e.count end,  low = false },
    levelLow  = { label = "Niveau le plus faible", value = function(e) return e.level end, low = true  },
    levelHigh = { label = "Niveau le plus élevé", value = function(e) return e.level end, low = false },
}
local DEFAULT_ORDER = {
    { key = "stackLow",  on = true  },
    { key = "levelLow",  on = true  },
    { key = "stackHigh", on = false },
    { key = "levelHigh", on = false },
}

local DB
local function InitDB()
    FeedMePLZDB = FeedMePLZDB or {}
    DB = FeedMePLZDB
    DB.pos = (type(DB.pos) == "table" and DB.pos.plain == nil and DB.pos[1]) and { plain = DB.pos } or (DB.pos or {})
    if DB.showPlain == nil then DB.showPlain = true end
    if DB.showStats == nil then DB.showStats = true end
    DB.minimap = DB.minimap or { angle = 225, hide = false }
    -- Classement : on garde l'ordre sauvegardé, on ajoute les critères manquants.
    local seen, order = {}, {}
    for _, c in ipairs(DB.criteria or {}) do
        if CRITERIA[c.key] and not seen[c.key] then
            seen[c.key] = true
            order[#order + 1] = { key = c.key, on = c.on and true or false }
        end
    end
    for _, c in ipairs(DEFAULT_ORDER) do
        if not seen[c.key] then order[#order + 1] = { key = c.key, on = c.on } end
    end
    DB.criteria = order
end

---------------------------------------------------------------------------
-- Analyse des objets
---------------------------------------------------------------------------
local FOOD_SPELL = SpellName(433) -- « Nourriture », localisé
local WELL_FED = {}
for _, s in ipairs({ SpellName(19705) or "", "Well Fed", "Bien nourri" }) do
    if s ~= "" then WELL_FED[#WELL_FED + 1] = s:lower() end
end

local scan = CreateFrame("GameTooltip", "FeedMePLZScanTip", nil, "GameTooltipTemplate")

-- true/false, ou nil si l'objet n'est pas encore en cache client.
local function TooltipHasWellFed(itemID)
    scan:SetOwner(WorldFrame, "ANCHOR_NONE")
    scan:ClearLines()
    scan:SetHyperlink("item:" .. itemID)
    local n = scan:NumLines()
    if n == 0 then return nil end
    for i = 2, n do
        local line = _G["FeedMePLZScanTipTextLeft" .. i]
        local text = line and line:GetText()
        if text then
            text = text:lower()
            for _, w in ipairs(WELL_FED) do
                if text:find(w, 1, true) then return true end
            end
        end
    end
    return false
end

local infoCache = {} -- itemID -> { food = bool, stats = bool, level = n }
local function GetFoodInfo(itemID)
    local cached = infoCache[itemID]
    if cached then return cached end
    local _, _, _, _, minLevel = GetItemInfoCompat(itemID)
    if minLevel == nil then return nil end -- pas encore chargé, retenté plus tard
    local info = { food = (GetItemSpellCompat(itemID) == FOOD_SPELL), stats = false, level = minLevel }
    if info.food then
        local stats = TooltipHasWellFed(itemID)
        if stats == nil then return nil end
        info.stats = stats
    end
    infoCache[itemID] = info
    return info
end

local function IsBetter(a, b)
    for _, c in ipairs(DB.criteria) do
        if c.on then
            local crit = CRITERIA[c.key]
            local va, vb = crit.value(a), crit.value(b)
            if va ~= vb then
                if crit.low then return va < vb else return va > vb end
            end
        end
    end
    return false
end

-- Renvoie la meilleure entrée pour chaque catégorie : plain, stats.
local function FindBestFoods()
    local best = {}
    for bag = 0, 4 do
        for slot = 1, (GetNumSlots(bag) or 0) do
            local id = GetItemID(bag, slot)
            local info = id and GetFoodInfo(id)
            if info and info.food then
                local e = { bag = bag, slot = slot, id = id, count = GetSlotCount(bag, slot), level = info.level }
                local kind = info.stats and "stats" or "plain"
                if not best[kind] or IsBetter(e, best[kind]) then best[kind] = e end
            end
        end
    end
    return best.plain, best.stats
end

---------------------------------------------------------------------------
-- Boutons sécurisés (utiliser un objet est une action protégée)
---------------------------------------------------------------------------
local buttons = {}

local function ApplyPosition(btn)
    btn:ClearAllPoints()
    local p = DB.pos[btn.kind]
    if p then
        btn:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        btn:SetPoint("CENTER", UIParent, "CENTER", btn.defaultX, -150)
    end
end

local function CreateFoodButton(kind, title, defaultX, emptyIcon, borderColor)
    local btn = CreateFrame("Button", "FeedMePLZ" .. kind .. "Button", UIParent, "SecureActionButtonTemplate")
    btn.kind, btn.title, btn.defaultX, btn.emptyIcon = kind, title, defaultX, emptyIcon
    btn:SetSize(40, 40)
    btn:SetMovable(true)
    btn:SetClampedToScreen(true)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:RegisterForDrag("LeftButton")
    btn:SetAttribute("type", "item")

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    border:SetPoint("CENTER")
    border:SetSize(66, 66)
    if borderColor then border:SetVertexColor(unpack(borderColor)) end

    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

    btn.countText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    btn.countText:SetPoint("BOTTOMRIGHT", -2, 2)

    btn:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() and not InCombatLockdown() and not DB.locked then self:StartMoving() end
    end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        DB.pos[self.kind] = { point, relPoint, x, y }
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.itemID then
            GameTooltip:SetHyperlink("item:" .. self.itemID)
        else
            GameTooltip:SetText(self.title)
            GameTooltip:AddLine("Rien dans les sacs.", 1, 0.3, 0.3)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("FeedMePLZ — " .. self.title, 1, 0.53, 0)
        GameTooltip:AddLine("Maj + glisser : déplacer   /fmp : options", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    buttons[kind] = btn
    return btn
end

CreateFoodButton("plain", "Nourriture simple", -24, "Interface\\Icons\\INV_Misc_Food_15")
CreateFoodButton("stats", "Nourriture à stats", 24, "Interface\\Icons\\INV_Misc_Food_64", { 1, 0.82, 0 })

local function SetButtonFood(btn, e)
    btn.itemID = e and e.id
    if e then
        btn:SetAttribute("item", e.bag .. " " .. e.slot)
        btn.icon:SetTexture(GetItemIconCompat(e.id))
        btn.icon:SetDesaturated(false)
        btn.countText:SetText(e.count > 1 and e.count or "")
    else
        btn:SetAttribute("item", nil)
        btn.icon:SetTexture(btn.emptyIcon)
        btn.icon:SetDesaturated(true)
        btn.countText:SetText("")
    end
end

local pending = false -- mise à jour reportée à la sortie de combat

local function Refresh()
    if not DB then return end
    if InCombatLockdown() then pending = true return end
    pending = false
    local plain, stats = FindBestFoods()
    SetButtonFood(buttons.plain, plain)
    SetButtonFood(buttons.stats, stats)
    buttons.plain:SetShown(DB.showPlain)
    buttons.stats:SetShown(DB.showStats)
end

---------------------------------------------------------------------------
-- Panneau de configuration
---------------------------------------------------------------------------
local panel = CreateFrame("Frame", "FeedMePLZOptions")
panel.name = "FeedMePLZ"
panel:Hide()

local function Label(parent, text, template)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    fs:SetText(text)
    return fs
end

local function CheckBox(parent, text, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb.label = Label(cb, text)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb:SetScript("OnClick", function(self)
        if InCombatLockdown() then
            print(PREFIX .. "impossible en combat.")
            self:SetChecked(not self:GetChecked())
            return
        end
        onClick(self:GetChecked() and true or false)
    end)
    return cb
end

local title = Label(panel, "FeedMePLZ", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)

local subtitle = Label(panel, "Choix automatique de la nourriture à manger.", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)

local cbPlain = CheckBox(panel, "Afficher le bouton « Nourriture simple »", function(v) DB.showPlain = v; Refresh() end)
cbPlain:SetPoint("TOPLEFT", 16, -60)
local cbStats = CheckBox(panel, "Afficher le bouton « Nourriture à stats » (bordure dorée)", function(v) DB.showStats = v; Refresh() end)
cbStats:SetPoint("TOPLEFT", 16, -88)
local cbLock = CheckBox(panel, "Verrouiller la position des boutons", function(v) DB.locked = v end)
cbLock:SetPoint("TOPLEFT", 16, -116)
local SetMinimapShown -- défini plus bas
local cbMinimap = CheckBox(panel, "Afficher l'icône autour de la minimap", function(v) SetMinimapShown(v) end)
cbMinimap:SetPoint("TOPLEFT", 16, -144)

local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
resetBtn:SetSize(160, 22)
resetBtn:SetText("Réinitialiser positions")
resetBtn:SetPoint("TOPLEFT", 20, -176)
resetBtn:SetScript("OnClick", function()
    if InCombatLockdown() then print(PREFIX .. "impossible en combat.") return end
    DB.pos = {}
    ApplyPosition(buttons.plain)
    ApplyPosition(buttons.stats)
end)

local header = Label(panel, "Ordre de priorité", "GameFontNormal")
header:SetPoint("TOPLEFT", 16, -218)
local help = Label(panel, "Le 1er critère coché départage ; en cas d'égalité, on passe au suivant.", "GameFontHighlightSmall")
help:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)

local rows = {}
local RefreshRows

local function MoveCriterion(i, delta)
    local j = i + delta
    local list = DB.criteria
    if not list[j] then return end
    list[i], list[j] = list[j], list[i]
    RefreshRows()
    Refresh()
end

local function ArrowButton(parent, dir)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(24, 24)
    local base = "Interface\\ChatFrame\\UI-ChatIcon-Scroll" .. dir
    b:SetNormalTexture(base .. "-Up")
    b:SetPushedTexture(base .. "-Down")
    b:SetDisabledTexture(base .. "-Disabled")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    return b
end

for i = 1, #DEFAULT_ORDER do
    local y = -258 - (i - 1) * 30
    local row = {}
    row.rank = Label(panel, i .. ".", "GameFontNormal")
    row.rank:SetPoint("TOPLEFT", 20, y - 6)
    row.cb = CheckBox(panel, "", function(v) DB.criteria[i].on = v; Refresh() end)
    row.cb:SetPoint("TOPLEFT", 40, y)
    row.up = ArrowButton(panel, "Up")
    row.up:SetPoint("TOPLEFT", 280, y)
    row.up:SetScript("OnClick", function() MoveCriterion(i, -1) end)
    row.down = ArrowButton(panel, "Down")
    row.down:SetPoint("LEFT", row.up, "RIGHT", 2, 0)
    row.down:SetScript("OnClick", function() MoveCriterion(i, 1) end)
    rows[i] = row
end

RefreshRows = function()
    for i, row in ipairs(rows) do
        local c = DB.criteria[i]
        row.cb.label:SetText(CRITERIA[c.key].label)
        row.cb:SetChecked(c.on)
        row.cb.label:SetTextColor(c.on and 1 or 0.5, c.on and 1 or 0.5, c.on and 1 or 0.5)
        row.up:SetEnabled(i > 1)
        row.down:SetEnabled(i < #rows)
    end
end

panel:SetScript("OnShow", function()
    cbPlain:SetChecked(DB.showPlain)
    cbStats:SetChecked(DB.showStats)
    cbLock:SetChecked(DB.locked)
    cbMinimap:SetChecked(not DB.minimap.hide)
    RefreshRows()
end)

local settingsCategory
local function RegisterPanel()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(settingsCategory)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

local function OpenPanel()
    if settingsCategory then
        Settings.OpenToCategory(settingsCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel) -- 2e appel : bug connu du 1er affichage
    end
end

---------------------------------------------------------------------------
-- Icône autour de la minimap (glisser pour la faire tourner)
---------------------------------------------------------------------------
local minimapBtn = CreateFrame("Button", "FeedMePLZMinimapButton", Minimap)
minimapBtn:SetSize(31, 31)
minimapBtn:SetFrameStrata("MEDIUM")
minimapBtn:SetFrameLevel(8)
minimapBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
minimapBtn:RegisterForDrag("LeftButton")
minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local mmBg = minimapBtn:CreateTexture(nil, "BACKGROUND")
mmBg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
mmBg:SetSize(20, 20)
mmBg:SetPoint("TOPLEFT", 7, -5)

local mmIcon = minimapBtn:CreateTexture(nil, "ARTWORK")
mmIcon:SetTexture("Interface\\Icons\\INV_Misc_Fork&Knife")
mmIcon:SetSize(17, 17)
mmIcon:SetPoint("TOPLEFT", 7, -6)
mmIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

local mmBorder = minimapBtn:CreateTexture(nil, "OVERLAY")
mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mmBorder:SetSize(53, 53)
mmBorder:SetPoint("TOPLEFT")

local function PlaceMinimapButton()
    local a = math.rad(DB.minimap.angle)
    local r = Minimap:GetWidth() / 2 + 5
    minimapBtn:ClearAllPoints()
    minimapBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

SetMinimapShown = function(shown)
    DB.minimap.hide = not shown
    minimapBtn:SetShown(shown)
end

minimapBtn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        DB.minimap.angle = math.deg(math.atan2(py / scale - my, px / scale - mx))
        PlaceMinimapButton()
    end)
end)
minimapBtn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

minimapBtn:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then
        if InCombatLockdown() then print(PREFIX .. "impossible en combat.") return end
        DB.showPlain = not (DB.showPlain or DB.showStats)
        DB.showStats = DB.showPlain
        Refresh()
    else
        OpenPanel()
    end
end)
minimapBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("FeedMePLZ", 1, 0.53, 0)
    GameTooltip:AddLine("Clic gauche : options", 1, 1, 1)
    GameTooltip:AddLine("Clic droit : afficher / masquer les boutons", 1, 1, 1)
    GameTooltip:AddLine("Glisser : déplacer autour de la minimap", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
minimapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------
-- Regroupe les rafales de BAG_UPDATE en un seul scan
local throttle = CreateFrame("Frame")
throttle:Hide()
throttle:SetScript("OnUpdate", function(self, e)
    self.elapsed = self.elapsed + e
    if self.elapsed > 0.2 then
        self:Hide()
        Refresh()
    end
end)
local function QueueRefresh()
    throttle.elapsed = 0
    throttle:Show()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("BAG_UPDATE")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            InitDB()
            ApplyPosition(buttons.plain)
            ApplyPosition(buttons.stats)
            RegisterPanel()
            PlaceMinimapButton()
            minimapBtn:SetShown(not DB.minimap.hide)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then Refresh() end
    else
        QueueRefresh()
    end
end)

SLASH_FEEDMEPLZ1 = "/fmp"
SLASH_FEEDMEPLZ2 = "/feedme"
SlashCmdList.FEEDMEPLZ = function(msg)
    msg = (msg or ""):lower()
    if msg == "" or msg == "config" or msg == "options" then
        OpenPanel()
        return
    end
    if InCombatLockdown() then print(PREFIX .. "pas en combat.") return end
    if msg == "lock" then
        DB.locked = true
        print(PREFIX .. "boutons verrouillés.")
    elseif msg == "unlock" then
        DB.locked = false
        print(PREFIX .. "boutons déverrouillés (Maj + glisser).")
    elseif msg == "reset" then
        DB.pos = {}
        ApplyPosition(buttons.plain)
        ApplyPosition(buttons.stats)
        print(PREFIX .. "positions réinitialisées.")
    else
        print(PREFIX .. "/fmp (options) | lock | unlock | reset")
    end
end
