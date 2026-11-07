-- FeedMePLZ : deux boutons flottants (nourriture simple / nourriture à stats)
-- qui choisissent la nourriture selon un classement de critères configurable.
local ADDON = ...
local PREFIX = "|cffff8800FeedMePLZ|r : "

---------------------------------------------------------------------------
-- Langues de l'interface (la détection de la nourriture n'en dépend pas :
-- elle se base sur les sorts « Nourriture » / « Boisson » du client).
---------------------------------------------------------------------------
local LANGS = {
    enUS = {
        name = "English",
        ui = {
            subtitle = "Automatically picks the food to eat.",
            kind_plain = "Plain food",
            kind_stats = "Stat food",
            kind_drink = "Drink",
            empty = "Nothing in your bags.",
            btn_hint = "Shift + drag: move   /fmp: options",
            opt_plain = "Show the \"Plain food\" button",
            opt_stats = "Show the \"Stat food\" button (gold border)",
            opt_drink = "Show the \"Drink\" button (blue border, mana classes)",
            opt_lock = "Lock button positions",
            opt_minimap = "Show the minimap icon",
            opt_reset = "Reset positions",
            opt_priority = "Priority order",
            opt_priority_help = "The first ticked criterion decides; on a tie, the next one is used.",
            opt_lang = "Language",
            opt_lang_hint = "Interface language. Auto = game language.",
            lang_auto = "Auto (game)",
            crit_stackLow = "Lowest stack",
            crit_stackHigh = "Highest stack",
            crit_levelLow = "Lowest level",
            crit_levelHigh = "Highest level",
            mm_left = "Left-click: options",
            mm_right = "Right-click: show / hide the buttons",
            mm_drag = "Drag: move around the minimap",
            msg_combat = "not possible in combat.",
            msg_locked = "buttons locked.",
            msg_unlocked = "buttons unlocked (Shift + drag).",
            msg_reset = "positions reset.",
            msg_usage = "/fmp (options) | lock | unlock | reset",
        },
    },
    frFR = {
        name = "Français",
        ui = {
            subtitle = "Choix automatique de la nourriture à manger.",
            kind_plain = "Nourriture simple",
            kind_stats = "Nourriture à stats",
            kind_drink = "Boisson",
            empty = "Rien dans les sacs.",
            btn_hint = "Maj + glisser : déplacer   /fmp : options",
            opt_plain = "Afficher le bouton « Nourriture simple »",
            opt_stats = "Afficher le bouton « Nourriture à stats » (bordure dorée)",
            opt_drink = "Afficher le bouton « Boisson » (bordure bleue, classes à mana)",
            opt_lock = "Verrouiller la position des boutons",
            opt_minimap = "Afficher l'icône autour de la minimap",
            opt_reset = "Réinitialiser positions",
            opt_priority = "Ordre de priorité",
            opt_priority_help = "Le 1er critère coché départage ; en cas d'égalité, on passe au suivant.",
            opt_lang = "Langue",
            opt_lang_hint = "Langue de l'interface. Auto = langue du jeu.",
            lang_auto = "Auto (jeu)",
            crit_stackLow = "Stack la plus basse",
            crit_stackHigh = "Stack la plus haute",
            crit_levelLow = "Niveau le plus faible",
            crit_levelHigh = "Niveau le plus élevé",
            mm_left = "Clic gauche : options",
            mm_right = "Clic droit : afficher / masquer les boutons",
            mm_drag = "Glisser : déplacer autour de la minimap",
            msg_combat = "impossible en combat.",
            msg_locked = "boutons verrouillés.",
            msg_unlocked = "boutons déverrouillés (Maj + glisser).",
            msg_reset = "positions réinitialisées.",
            msg_usage = "/fmp (options) | lock | unlock | reset",
        },
    },
}
local LANG_CHOICES = { "auto", "enUS", "frFR" }

local DB
local L = LANGS[GetLocale() == "frFR" and "frFR" or "enUS"]

-- Langue effective : celle choisie, sinon celle du client (anglais par défaut).
local function ResolveLang()
    local choice = DB and DB.lang or "auto"
    if LANGS[choice] then return LANGS[choice] end
    return LANGS[GetLocale() == "frFR" and "frFR" or "enUS"]
end

local function T(key) return L.ui[key] or LANGS.enUS.ui[key] or key end

-- Textes à retraduire quand on change de langue : { objet, clé }.
local localized = {}
local function Loc(obj, key)
    table.insert(localized, { obj, key })
    obj:SetText(T(key))
    return obj
end

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
    stackLow  = { value = function(e) return e.count end, low = true  },
    stackHigh = { value = function(e) return e.count end, low = false },
    levelLow  = { value = function(e) return e.level end, low = true  },
    levelHigh = { value = function(e) return e.level end, low = false },
}
local DEFAULT_ORDER = {
    { key = "stackLow",  on = true  },
    { key = "levelLow",  on = true  },
    { key = "stackHigh", on = false },
    { key = "levelHigh", on = false },
}

local function InitDB()
    FeedMePLZDB = FeedMePLZDB or {}
    DB = FeedMePLZDB
    DB.lang = LANGS[DB.lang or ""] and DB.lang or "auto"
    DB.pos = (type(DB.pos) == "table" and DB.pos.plain == nil and DB.pos[1]) and { plain = DB.pos } or (DB.pos or {})
    if DB.showPlain == nil then DB.showPlain = true end
    if DB.showStats == nil then DB.showStats = true end
    if DB.showDrink == nil then DB.showDrink = true end
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
local FOOD_SPELL = SpellName(433)  -- « Nourriture », localisé
local DRINK_SPELL = SpellName(430) -- « Boisson », localisé
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

local infoCache = {} -- itemID -> { kind = "plain"|"stats"|"drink"|false, level = n }
local function GetFoodInfo(itemID)
    local cached = infoCache[itemID]
    if cached then return cached end
    local _, _, _, _, minLevel = GetItemInfoCompat(itemID)
    if minLevel == nil then return nil end -- pas encore chargé, retenté plus tard
    local spell = GetItemSpellCompat(itemID)
    local info = { kind = false, level = minLevel }
    if spell == FOOD_SPELL then
        local stats = TooltipHasWellFed(itemID)
        if stats == nil then return nil end
        info.kind = stats and "stats" or "plain"
    elseif spell == DRINK_SPELL then
        info.kind = "drink"
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

-- Renvoie la meilleure entrée par catégorie : { plain = e, stats = e, drink = e }.
local function FindBestFoods()
    local best = {}
    for bag = 0, 4 do
        for slot = 1, (GetNumSlots(bag) or 0) do
            local id = GetItemID(bag, slot)
            local info = id and GetFoodInfo(id)
            local kind = info and info.kind
            if kind then
                local e = { bag = bag, slot = slot, id = id, count = GetSlotCount(bag, slot), level = info.level }
                if not best[kind] or IsBetter(e, best[kind]) then best[kind] = e end
            end
        end
    end
    return best
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

local function CreateFoodButton(kind, defaultX, emptyIcon, borderColor)
    local btn = CreateFrame("Button", "FeedMePLZ" .. kind .. "Button", UIParent, "SecureActionButtonTemplate")
    btn.kind, btn.defaultX, btn.emptyIcon = kind, defaultX, emptyIcon
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
        local title = T("kind_" .. self.kind)
        if self.itemID then
            GameTooltip:SetHyperlink("item:" .. self.itemID)
        else
            GameTooltip:SetText(title)
            GameTooltip:AddLine(T("empty"), 1, 0.3, 0.3)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("FeedMePLZ — " .. title, 1, 0.53, 0)
        GameTooltip:AddLine(T("btn_hint"), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    buttons[kind] = btn
    return btn
end

CreateFoodButton("plain", -24, "Interface\\Icons\\INV_Misc_Food_15")
CreateFoodButton("stats", 24, "Interface\\Icons\\INV_Misc_Food_64", { 1, 0.82, 0 })
CreateFoodButton("drink", 72, "Interface\\Icons\\INV_Drink_07", { 0.4, 0.7, 1 })

-- Classes sans mana : pas de bouton Boisson.
local NO_MANA = { WARRIOR = true, ROGUE = true, DEATHKNIGHT = true, DEMONHUNTER = true }
local _, playerClass = UnitClass("player")
local hasMana = not NO_MANA[playerClass]
local KINDS = { "plain", "stats", "drink" }

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
    local best = FindBestFoods()
    for _, kind in ipairs(KINDS) do
        SetButtonFood(buttons[kind], best[kind])
    end
    buttons.plain:SetShown(DB.showPlain)
    buttons.stats:SetShown(DB.showStats)
    buttons.drink:SetShown(DB.showDrink and hasMana)
end

local function ResetPositions()
    DB.pos = {}
    for _, kind in ipairs(KINDS) do ApplyPosition(buttons[kind]) end
end

---------------------------------------------------------------------------
-- Panneau de configuration
---------------------------------------------------------------------------
local panel = CreateFrame("Frame", "FeedMePLZOptions")
panel.name = "FeedMePLZ"
panel:Hide()

-- key : clé de traduction (texte retraduit au changement de langue), ou nil.
local function Label(parent, key, template)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    if key then Loc(fs, key) end
    return fs
end

local function CheckBox(parent, key, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb.label = Label(cb, key)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb:SetScript("OnClick", function(self)
        if InCombatLockdown() then
            print(PREFIX .. T("msg_combat"))
            self:SetChecked(not self:GetChecked())
            return
        end
        onClick(self:GetChecked() and true or false)
    end)
    return cb
end

local title = Label(panel, nil, "GameFontNormalLarge")
title:SetText("FeedMePLZ")
title:SetPoint("TOPLEFT", 16, -16)

local subtitle = Label(panel, "subtitle", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)

local cbPlain = CheckBox(panel, "opt_plain", function(v) DB.showPlain = v; Refresh() end)
cbPlain:SetPoint("TOPLEFT", 16, -60)
local cbStats = CheckBox(panel, "opt_stats", function(v) DB.showStats = v; Refresh() end)
cbStats:SetPoint("TOPLEFT", 16, -88)
local cbDrink = CheckBox(panel, "opt_drink", function(v) DB.showDrink = v; Refresh() end)
cbDrink:SetPoint("TOPLEFT", 16, -116)
local cbLock = CheckBox(panel, "opt_lock", function(v) DB.locked = v end)
cbLock:SetPoint("TOPLEFT", 16, -144)
local SetMinimapShown -- défini plus bas
local cbMinimap = CheckBox(panel, "opt_minimap", function(v) SetMinimapShown(v) end)
cbMinimap:SetPoint("TOPLEFT", 16, -172)

local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
resetBtn:SetSize(160, 22)
Loc(resetBtn, "opt_reset")
resetBtn:SetPoint("TOPLEFT", 20, -204)
resetBtn:SetScript("OnClick", function()
    if InCombatLockdown() then print(PREFIX .. T("msg_combat")) return end
    ResetPositions()
end)

local header = Label(panel, "opt_priority", "GameFontNormal")
header:SetPoint("TOPLEFT", 16, -246)
local help = Label(panel, "opt_priority_help", "GameFontHighlightSmall")
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
    local y = -286 - (i - 1) * 30
    local row = {}
    row.rank = Label(panel, nil, "GameFontNormal")
    row.rank:SetText(i .. ".")
    row.rank:SetPoint("TOPLEFT", 20, y - 6)
    row.cb = CheckBox(panel, nil, function(v) DB.criteria[i].on = v; Refresh() end)
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
        row.cb.label:SetText(T("crit_" .. c.key))
        row.cb:SetChecked(c.on)
        row.cb.label:SetTextColor(c.on and 1 or 0.5, c.on and 1 or 0.5, c.on and 1 or 0.5)
        row.up:SetEnabled(i > 1)
        row.down:SetEnabled(i < #rows)
    end
end

-- Langue
local langHeader = Label(panel, "opt_lang", "GameFontNormal")
langHeader:SetPoint("TOPLEFT", 16, -416)
local langHint = Label(panel, "opt_lang_hint", "GameFontHighlightSmall")
langHint:SetPoint("LEFT", langHeader, "RIGHT", 10, 0)
local langButtons = {}
local function RefreshLangButtons()
    for key, b in pairs(langButtons) do
        b:SetEnabled(key ~= DB.lang) -- la langue active apparaît grisée
    end
end

local function ApplyLanguage()
    L = ResolveLang()
    for _, entry in ipairs(localized) do entry[1]:SetText(T(entry[2])) end
    if DB then RefreshRows() end
end

for i, choice in ipairs(LANG_CHOICES) do
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(100, 24)
    b:SetPoint("TOPLEFT", 16 + (i - 1) * 106, -438)
    if LANGS[choice] then b:SetText(LANGS[choice].name) else Loc(b, "lang_auto") end
    b:SetScript("OnClick", function()
        DB.lang = choice
        ApplyLanguage()
        RefreshLangButtons()
    end)
    langButtons[choice] = b
end

panel:SetScript("OnShow", function()
    cbPlain:SetChecked(DB.showPlain)
    cbStats:SetChecked(DB.showStats)
    cbDrink:SetChecked(DB.showDrink)
    cbDrink:SetEnabled(hasMana)
    cbDrink.label:SetTextColor(hasMana and 1 or 0.5, hasMana and 1 or 0.5, hasMana and 1 or 0.5)
    cbLock:SetChecked(DB.locked)
    cbMinimap:SetChecked(not DB.minimap.hide)
    RefreshRows()
    RefreshLangButtons()
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
mmIcon:SetTexture("Interface\\AddOns\\FeedMePLZ\\Media\\icon")
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
        if InCombatLockdown() then print(PREFIX .. T("msg_combat")) return end
        local show = not (DB.showPlain or DB.showStats or DB.showDrink)
        DB.showPlain, DB.showStats, DB.showDrink = show, show, show
        Refresh()
    else
        OpenPanel()
    end
end)
minimapBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("FeedMePLZ", 1, 0.53, 0)
    GameTooltip:AddLine(T("mm_left"), 1, 1, 1)
    GameTooltip:AddLine(T("mm_right"), 1, 1, 1)
    GameTooltip:AddLine(T("mm_drag"), 0.6, 0.6, 0.6)
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
            ApplyLanguage()
            for _, kind in ipairs(KINDS) do ApplyPosition(buttons[kind]) end
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
    if InCombatLockdown() then print(PREFIX .. T("msg_combat")) return end
    if msg == "lock" then
        DB.locked = true
        print(PREFIX .. T("msg_locked"))
    elseif msg == "unlock" then
        DB.locked = false
        print(PREFIX .. T("msg_unlocked"))
    elseif msg == "reset" then
        ResetPositions()
        print(PREFIX .. T("msg_reset"))
    else
        print(PREFIX .. T("msg_usage"))
    end
end
