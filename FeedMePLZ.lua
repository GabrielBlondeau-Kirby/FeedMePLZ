-- FeedMePLZ : une icône ronde qui ouvre un petit cadre avec trois boutons
-- (nourriture simple / nourriture à stats / boisson). Chaque bouton choisit
-- la nourriture selon un classement de critères configurable.
-- Le cadre se ferme tout seul en combat (on ne peut pas manger) et l'icône
-- devient transparente ; il se rouvre à la sortie du combat.
local ADDON = ...
local PREFIX = "|cffff8800FeedMePLZ|r : "
local ICON = "Interface\\AddOns\\FeedMePLZ\\Media\\icon"
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

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
            empty_frame = "No button shown (see /fmp).",
            btn_hint = "/fmp: options",
            tip_click = "Click: open / close",
            tip_drag = "Shift + drag: move   /fmp: options",
            tip_combat = "Closed during combat.",
            opt_plain = "Show the \"Plain food\" button",
            opt_stats = "Show the \"Stat food\" button (gold border)",
            opt_drink = "Show the \"Drink\" button (blue border, mana classes)",
            opt_lock = "Lock the position",
            opt_minimap = "Show the minimap icon",
            opt_combat = "Close automatically in combat (icon turns transparent)",
            opt_reset = "Reset position",
            opt_theme = "Theme",
            theme_dark = "Dark",
            theme_gold = "Gold",
            theme_arcane = "Arcane",
            theme_fel = "Fel",
            theme_blood = "Blood",
            opt_priority = "Priority order",
            opt_priority_help = "The first ticked criterion decides; on a tie, the next one is used.",
            opt_lang = "Language",
            opt_lang_hint = "Interface language. Auto = game language.",
            lang_auto = "Auto (game)",
            crit_stackLow = "Lowest stack",
            crit_stackHigh = "Highest stack",
            crit_levelLow = "Lowest level",
            crit_levelHigh = "Highest level",
            mm_left = "Left-click: open / close",
            mm_right = "Right-click: options",
            mm_drag = "Drag: move around the minimap",
            msg_combat = "not possible in combat.",
            msg_locked = "position locked.",
            msg_unlocked = "position unlocked (Shift + drag).",
            msg_reset = "position reset.",
            msg_usage = "/fmp (options) | lock | unlock | reset | scan",
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
            empty_frame = "Aucun bouton affiché (voir /fmp).",
            btn_hint = "/fmp : options",
            tip_click = "Clic : ouvrir / fermer",
            tip_drag = "Maj + glisser : déplacer   /fmp : options",
            tip_combat = "Fermé pendant le combat.",
            opt_plain = "Afficher le bouton « Nourriture simple »",
            opt_stats = "Afficher le bouton « Nourriture à stats » (bordure dorée)",
            opt_drink = "Afficher le bouton « Boisson » (bordure bleue, classes à mana)",
            opt_lock = "Verrouiller la position",
            opt_minimap = "Afficher l'icône autour de la minimap",
            opt_combat = "Fermer automatiquement en combat (icône transparente)",
            opt_reset = "Réinitialiser la position",
            opt_theme = "Thème",
            theme_dark = "Sombre",
            theme_gold = "Doré",
            theme_arcane = "Arcane",
            theme_fel = "Gangrène",
            theme_blood = "Sang",
            opt_priority = "Ordre de priorité",
            opt_priority_help = "Le 1er critère coché départage ; en cas d'égalité, on passe au suivant.",
            opt_lang = "Langue",
            opt_lang_hint = "Langue de l'interface. Auto = langue du jeu.",
            lang_auto = "Auto (jeu)",
            crit_stackLow = "Stack la plus basse",
            crit_stackHigh = "Stack la plus haute",
            crit_levelLow = "Niveau le plus faible",
            crit_levelHigh = "Niveau le plus élevé",
            mm_left = "Clic gauche : ouvrir / fermer",
            mm_right = "Clic droit : options",
            mm_drag = "Glisser : déplacer autour de la minimap",
            msg_combat = "impossible en combat.",
            msg_locked = "position verrouillée.",
            msg_unlocked = "position déverrouillée (Maj + glisser).",
            msg_reset = "position réinitialisée.",
            msg_usage = "/fmp (options) | lock | unlock | reset | scan",
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

local THEMES = {
    { key = "dark",   bg = { 0, 0, 0, 0.80 },          border = { 0.55, 0.55, 0.55 } },
    { key = "gold",   bg = { 0.10, 0.07, 0.03, 0.88 }, border = { 1.00, 0.80, 0.20 } },
    { key = "arcane", bg = { 0.05, 0.03, 0.15, 0.88 }, border = { 0.65, 0.45, 1.00 } },
    { key = "fel",    bg = { 0.02, 0.10, 0.02, 0.88 }, border = { 0.35, 1.00, 0.20 } },
    { key = "blood",  bg = { 0.12, 0.02, 0.02, 0.88 }, border = { 0.90, 0.15, 0.15 } },
}
local THEME_BY_KEY = {}
for _, t in ipairs(THEMES) do THEME_BY_KEY[t.key] = t end

local function InitDB()
    FeedMePLZDB = FeedMePLZDB or {}
    DB = FeedMePLZDB
    DB.lang = LANGS[DB.lang or ""] and DB.lang or "auto"
    -- Une seule position (l'icône ronde) ; les anciennes positions par bouton sont abandonnées.
    if type(DB.pos) ~= "table" or not DB.pos[1] then DB.pos = nil end
    if DB.showPlain == nil then DB.showPlain = true end
    if DB.showStats == nil then DB.showStats = true end
    if DB.showDrink == nil then DB.showDrink = true end
    if DB.combatClose == nil then DB.combatClose = true end
    if DB.open == nil then DB.open = true end
    DB.theme = THEME_BY_KEY[DB.theme or ""] and DB.theme or "gold"
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
-- Indices d'une nourriture à stats dans la ligne « Utiliser : » (en minuscules) :
-- le buff « Bien nourri », la phrase des 10 secondes, ou le nom d'une caractéristique.
local STATS_HINTS = {
    "bien nourri", "well fed",
    "au moins 10 sec", "at least 10 sec",
    "endurance", "esprit", "intelligence", "agilit", "force", "puissance", "critique",
    "hâte", "maîtrise", "polyvalence", "toucher", "régénér", "par 5 sec",
    "stamina", "spirit", "intellect", "agility", "strength", "attack power", "spell power",
    "critical", "haste", "mastery", "versatility", "hit rating", "mana per 5", "every 5 sec",
}
local wellFedName = SpellName(19705)
if wellFedName and wellFedName ~= "" then table.insert(STATS_HINTS, wellFedName:lower()) end

-- Phrases qui trahissent une nourriture / une boisson, quel que soit le nom du sort.
local EAT_HINTS = { "pendant que vous mangez", "while eating", "secondes à manger", "seconds eating" }
local DRINK_HINTS = { "pendant que vous buvez", "while drinking" }

local function HasAny(s, words)
    for _, w in ipairs(words) do
        if s:find(w, 1, true) then return true end
    end
    return false
end

local scan = CreateFrame("GameTooltip", "FeedMePLZScanTip", nil, "GameTooltipTemplate")

-- Ligne(s) « Utiliser : » de la description, en minuscules ; nil si absente
-- (pas d'effet, ou description du sort pas encore chargée).
local function UseText(itemID)
    scan:SetOwner(WorldFrame, "ANCHOR_NONE")
    scan:ClearLines()
    scan:SetHyperlink("item:" .. itemID)
    local parts = {}
    for i = 2, scan:NumLines() do
        local line = _G["FeedMePLZScanTipTextLeft" .. i]
        local text = line and line:GetText()
        if text then
            text = text:lower()
            if text:find("^utiliser") or text:find("^use:") then
                parts[#parts + 1] = text
            end
        end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, " ")
end

local tries = {} -- itemID -> nombre de lectures sans ligne « Utiliser »
local MAX_TRIES = 10

-- Catégorie d'un objet : "plain" | "stats" | "drink" | false, ou nil s'il faut réessayer.
-- On regarde le nom du sort (Nourriture / Boisson) ET la description, car certains
-- plats lancent un sort au nom différent.
local function Classify(itemID, spell, classID)
    if not spell and classID ~= 0 then return false end -- ni effet ni consommable
    local use = UseText(itemID)
    if not use then
        if not spell then return false end -- consommable sans effet « Utiliser »
        tries[itemID] = (tries[itemID] or 0) + 1
        if tries[itemID] < MAX_TRIES then return nil end
        use = "" -- description jamais chargée : on se fie au nom du sort
    end
    if spell == FOOD_SPELL or HasAny(use, EAT_HINTS) then
        return HasAny(use, STATS_HINTS) and "stats" or "plain"
    elseif spell == DRINK_SPELL or HasAny(use, DRINK_HINTS) then
        return "drink"
    end
    return false
end

local infoCache = {} -- itemID -> { kind = "plain"|"stats"|"drink"|false, level = n }
local function GetFoodInfo(itemID)
    local cached = infoCache[itemID]
    if cached then return cached end
    local _, _, _, _, minLevel, _, _, _, _, _, _, classID = GetItemInfoCompat(itemID)
    if minLevel == nil then return nil end -- pas encore chargé, retenté plus tard
    local kind = Classify(itemID, GetItemSpellCompat(itemID), classID)
    if kind == nil then return nil end
    local info = { kind = kind, level = minLevel }
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

-- Renvoie la meilleure entrée par catégorie : { plain = e, stats = e, drink = e },
-- et true si au moins un objet n'a pas encore pu être analysé (à retenter).
local function FindBestFoods()
    local best, missing = {}, false
    for bag = 0, 4 do
        for slot = 1, (GetNumSlots(bag) or 0) do
            local id = GetItemID(bag, slot)
            local info = id and GetFoodInfo(id)
            if id and info == nil then missing = true end
            local kind = info and info.kind
            if kind then
                local e = { bag = bag, slot = slot, id = id, count = GetSlotCount(bag, slot), level = info.level }
                if not best[kind] or IsBetter(e, best[kind]) then best[kind] = e end
            end
        end
    end
    return best, missing
end

---------------------------------------------------------------------------
-- Icône ronde (ouvre / ferme le cadre)
---------------------------------------------------------------------------
local TOGGLE = 52
local k = TOGGLE / 31 -- mise à l'échelle du modèle « bouton de minimap »

local toggle = CreateFrame("Button", "FeedMePLZToggle", UIParent, "SecureHandlerClickTemplate")
toggle:SetSize(TOGGLE, TOGGLE)
toggle:SetFrameStrata("MEDIUM")
toggle:SetFrameLevel(20)
toggle:SetMovable(true)
toggle:SetClampedToScreen(true)
toggle:RegisterForClicks("AnyUp")
toggle:RegisterForDrag("LeftButton")

local tIcon = toggle:CreateTexture(nil, "ARTWORK")
tIcon:SetTexture(ICON)
tIcon:SetSize(20 * k, 20 * k)
tIcon:SetPoint("TOPLEFT", 6 * k, -5.5 * k)
if tIcon.SetMask then tIcon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask") end

local tRing = toggle:CreateTexture(nil, "OVERLAY")
tRing:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
tRing:SetSize(53 * k, 53 * k)
tRing:SetPoint("TOPLEFT")

local tHl = toggle:CreateTexture(nil, "HIGHLIGHT")
tHl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
tHl:SetBlendMode("ADD")
tHl:SetAllPoints(tIcon)

---------------------------------------------------------------------------
-- Le cadre (protégé : il contient des boutons sécurisés)
---------------------------------------------------------------------------
local frameTemplate = "SecureHandlerStateTemplate" .. (BACKDROP_TEMPLATE and "," .. BACKDROP_TEMPLATE or "")
local frame = CreateFrame("Frame", "FeedMePLZFrame", UIParent, frameTemplate)
frame:SetFrameStrata("MEDIUM")
frame:SetFrameLevel(5)
frame:SetPoint("TOPLEFT", toggle, "CENTER", 0, 2)
frame:SetSize(200, 60)
frame:Hide()

local emptyText = Loc(frame:CreateFontString(nil, "OVERLAY", "GameFontDisable"), "empty_frame")

-- Clic sur l'icône : ouvre / ferme, sauf en combat si la fermeture auto est active.
toggle:SetFrameRef("frame", frame)
toggle:SetAttribute("_onclick", [[
    local frame = self:GetFrameRef("frame")
    if frame:GetAttribute("incombat") and frame:GetAttribute("combatclose") then return end
    frame:SetAttribute("autoclosed", nil)
    if frame:IsShown() then frame:Hide() else frame:Show() end
]])

-- Entrée en combat : on ferme et l'icône devient transparente.
-- Sortie : l'icône redevient opaque et on rouvre si c'est le combat qui a fermé.
SecureHandlerSetFrameRef(frame, "toggle", toggle) -- le modèle « State » n'a pas de méthode SetFrameRef
frame:SetAttribute("_onstate-combat", [[
    local toggle = self:GetFrameRef("toggle")
    if newstate == "1" then
        self:SetAttribute("incombat", 1)
        if not self:GetAttribute("combatclose") then return end
        toggle:SetAlpha(0.35)
        if self:IsShown() then
            self:SetAttribute("autoclosed", 1)
            self:Hide()
        end
    else
        self:SetAttribute("incombat", nil)
        toggle:SetAlpha(1)
        if self:GetAttribute("autoclosed") then
            self:Show()
            self:SetAttribute("autoclosed", nil)
        end
    end
]])
RegisterStateDriver(frame, "combat", "[combat] 1; 0")

-- On ne mémorise que les ouvertures / fermetures manuelles.
frame:HookScript("OnShow", function(self) if DB and not self:GetAttribute("autoclosed") then DB.open = true end end)
frame:HookScript("OnHide", function(self) if DB and not self:GetAttribute("autoclosed") then DB.open = false end end)

local function ApplyTheme()
    local t = THEME_BY_KEY[DB.theme]
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        frame:SetBackdropColor(unpack(t.bg))
        frame:SetBackdropBorderColor(unpack(t.border))
    end
    tRing:SetVertexColor(unpack(t.border))
end

---------------------------------------------------------------------------
-- Les trois boutons (sécurisés : utiliser un objet est une action protégée)
---------------------------------------------------------------------------
local BTN, GAP = 40, 8
local buttons = {}

local function CreateFoodButton(kind, emptyIcon, borderColor)
    local btn = CreateFrame("Button", "FeedMePLZ" .. kind .. "Button", frame, "SecureActionButtonTemplate")
    btn.kind, btn.emptyIcon = kind, emptyIcon
    btn:SetSize(BTN, BTN)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:SetAttribute("type", "item")

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    border:SetPoint("CENTER")
    border:SetSize(BTN * 1.65, BTN * 1.65)
    if borderColor then border:SetVertexColor(unpack(borderColor)) end

    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

    btn.countText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    btn.countText:SetPoint("BOTTOMRIGHT", -2, 2)

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

CreateFoodButton("plain", "Interface\\Icons\\INV_Misc_Food_15")
CreateFoodButton("stats", "Interface\\Icons\\INV_Misc_Food_64", { 1, 0.82, 0 })
CreateFoodButton("drink", "Interface\\Icons\\INV_Drink_07", { 0.4, 0.7, 1 })

-- Classes sans mana : pas de bouton Boisson.
local NO_MANA = { WARRIOR = true, ROGUE = true, DEATHKNIGHT = true, DEMONHUNTER = true }
local _, playerClass = UnitClass("player")
local hasMana = not NO_MANA[playerClass]
local KINDS = { "plain", "stats", "drink" }

local function IsKindShown(kind)
    if kind == "plain" then return DB.showPlain end
    if kind == "stats" then return DB.showStats end
    return DB.showDrink and hasMana
end

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

-- Place les boutons visibles en ligne, à droite de l'icône ronde qui chevauche le coin.
local function Layout()
    local x0 = TOGGLE / 2 + 10
    local n = 0
    for _, kind in ipairs(KINDS) do
        local btn = buttons[kind]
        if IsKindShown(kind) then
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", frame, "TOPLEFT", x0 + n * (BTN + GAP), -12)
            btn:Show()
            n = n + 1
        else
            btn:Hide()
        end
    end
    if n == 0 then
        emptyText:ClearAllPoints()
        emptyText:SetPoint("LEFT", frame, "TOPLEFT", x0, -32)
        emptyText:Show()
        frame:SetSize(x0 + emptyText:GetStringWidth() + 14, 64)
    else
        emptyText:Hide()
        frame:SetSize(x0 + n * (BTN + GAP) + 6, BTN + 24)
    end
end

local pending = false -- mise à jour reportée à la sortie de combat

-- Nouvel essai 1 s plus tard quand une description n'était pas encore chargée.
local retry = CreateFrame("Frame")
retry:Hide()
local Refresh
retry:SetScript("OnUpdate", function(self, e)
    self.elapsed = self.elapsed + e
    if self.elapsed > 1 then
        self:Hide()
        Refresh()
    end
end)

Refresh = function()
    if not DB then return end
    if InCombatLockdown() then pending = true return end
    pending = false
    local best, missing = FindBestFoods()
    if missing and not retry:IsShown() then
        retry.elapsed = 0
        retry:Show()
    end
    for _, kind in ipairs(KINDS) do
        SetButtonFood(buttons[kind], best[kind])
    end
    Layout()
end

---------------------------------------------------------------------------
-- Déplacement et position (on déplace l'icône, le cadre suit)
---------------------------------------------------------------------------
toggle:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() and not InCombatLockdown() and not DB.locked then self:StartMoving() end
end)
toggle:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    DB.pos = { point, relPoint, x, y }
end)
toggle:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("FeedMePLZ", 1, 0.53, 0)
    if InCombatLockdown() and DB.combatClose then
        GameTooltip:AddLine(T("tip_combat"), 1, 0.3, 0.3)
    else
        GameTooltip:AddLine(T("tip_click"), 1, 1, 1)
    end
    GameTooltip:AddLine(T("tip_drag"), 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function ApplyPosition()
    toggle:ClearAllPoints()
    local p = DB.pos
    if p then
        toggle:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        toggle:SetPoint("CENTER", UIParent, "CENTER", -80, -150)
    end
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
local cbCombat = CheckBox(panel, "opt_combat", function(v)
    DB.combatClose = v
    frame:SetAttribute("combatclose", v)
end)
cbCombat:SetPoint("TOPLEFT", 16, -144)
local cbLock = CheckBox(panel, "opt_lock", function(v) DB.locked = v end)
cbLock:SetPoint("TOPLEFT", 16, -172)
local SetMinimapShown -- défini plus bas
local cbMinimap = CheckBox(panel, "opt_minimap", function(v) SetMinimapShown(v) end)
cbMinimap:SetPoint("TOPLEFT", 16, -200)

local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
resetBtn:SetSize(180, 22)
Loc(resetBtn, "opt_reset")
resetBtn:SetPoint("TOPLEFT", 20, -232)
resetBtn:SetScript("OnClick", function()
    if InCombatLockdown() then print(PREFIX .. T("msg_combat")) return end
    DB.pos = nil
    ApplyPosition()
end)

-- Thèmes
Label(panel, "opt_theme", "GameFontNormal"):SetPoint("TOPLEFT", 16, -270)
local themeButtons = {}
local function RefreshThemeButtons()
    for key, b in pairs(themeButtons) do
        b:SetEnabled(key ~= DB.theme) -- le thème actif apparaît grisé
    end
end
for i, t in ipairs(THEMES) do
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(100, 24)
    b:SetPoint("TOPLEFT", 16 + (i - 1) * 106, -292)
    Loc(b, "theme_" .. t.key)
    b:GetFontString():SetTextColor(unpack(t.border))
    b:SetScript("OnClick", function()
        DB.theme = t.key
        ApplyTheme()
        RefreshThemeButtons()
    end)
    themeButtons[t.key] = b
end

-- Ordre de priorité
local header = Label(panel, "opt_priority", "GameFontNormal")
header:SetPoint("TOPLEFT", 16, -334)
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
    local y = -372 - (i - 1) * 30
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
langHeader:SetPoint("TOPLEFT", 16, -500)
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
    if DB then
        RefreshRows()
        if not InCombatLockdown() then Layout() end -- largeur du texte « aucun bouton »
    end
end

for i, choice in ipairs(LANG_CHOICES) do
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(100, 24)
    b:SetPoint("TOPLEFT", 16 + (i - 1) * 106, -522)
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
    cbCombat:SetChecked(DB.combatClose)
    cbLock:SetChecked(DB.locked)
    cbMinimap:SetChecked(not DB.minimap.hide)
    RefreshThemeButtons()
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
-- Icône autour de la minimap
-- Clic gauche : ouvre / ferme le cadre (sécurisé). Clic droit : options.
-- Glisser : faire tourner autour de la minimap (hors combat).
---------------------------------------------------------------------------
local minimapBtn = CreateFrame("Button", "FeedMePLZMinimapButton", Minimap, "SecureHandlerClickTemplate")
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
mmIcon:SetTexture(ICON)
mmIcon:SetSize(17, 17)
mmIcon:SetPoint("TOPLEFT", 7, -6)
mmIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

local mmBorder = minimapBtn:CreateTexture(nil, "OVERLAY")
mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mmBorder:SetSize(53, 53)
mmBorder:SetPoint("TOPLEFT")

minimapBtn:SetFrameRef("frame", frame)
minimapBtn:SetAttribute("_onclick", [[
    if button ~= "LeftButton" then return end
    local frame = self:GetFrameRef("frame")
    if frame:GetAttribute("incombat") and frame:GetAttribute("combatclose") then return end
    frame:SetAttribute("autoclosed", nil)
    if frame:IsShown() then frame:Hide() else frame:Show() end
]])
minimapBtn:HookScript("OnClick", function(_, mouse)
    if mouse ~= "RightButton" then return end
    if InCombatLockdown() then print(PREFIX .. T("msg_combat")) return end
    OpenPanel()
end)

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

-- Bouton sécurisé : on ne le déplace qu'hors combat.
minimapBtn:SetScript("OnDragStart", function(self)
    if InCombatLockdown() then return end
    self:SetScript("OnUpdate", function()
        if InCombatLockdown() then self:SetScript("OnUpdate", nil) return end
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        DB.minimap.angle = math.deg(math.atan2(py / scale - my, px / scale - mx))
        PlaceMinimapButton()
    end)
end)
minimapBtn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

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
        if arg1 ~= ADDON then return end
        InitDB()
        ApplyLanguage()
        ApplyPosition()
        ApplyTheme()
        frame:SetAttribute("combatclose", DB.combatClose)
        if DB.open then frame:Show() end
        PlaceMinimapButton()
        minimapBtn:SetShown(not DB.minimap.hide)
        RegisterPanel()
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
    if msg == "scan" then
        -- Diagnostic : catégorie détectée pour chaque nourriture / boisson des sacs.
        wipe(infoCache)
        wipe(tries)
        local seen = {}
        for bag = 0, 4 do
            for slot = 1, (GetNumSlots(bag) or 0) do
                local id = GetItemID(bag, slot)
                if id and not seen[id] then
                    seen[id] = true
                    -- Tous les consommables : on voit aussi ceux que l'addon ignore.
                    local _, link, _, _, _, _, _, _, _, _, _, classID = GetItemInfoCompat(id)
                    local spell = GetItemSpellCompat(id)
                    if classID == 0 or spell then
                        local info = GetFoodInfo(id)
                        local kind = (info == nil and "?") or (info.kind and T("kind_" .. info.kind)) or "—"
                        print(PREFIX .. (link or id) .. " → " .. kind .. "  |cff888888(" .. tostring(spell) .. ")|r")
                        local use = UseText(id)
                        if use then print("    " .. use) end
                    end
                end
            end
        end
        Refresh()
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
        DB.pos = nil
        ApplyPosition()
        print(PREFIX .. T("msg_reset"))
    else
        print(PREFIX .. T("msg_usage"))
    end
end
