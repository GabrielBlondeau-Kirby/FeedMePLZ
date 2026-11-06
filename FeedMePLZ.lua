-- FeedMePLZ : un bouton flottant qui mange la nourriture de la plus petite pile.
local ADDON = ...

-- Compatibilité API (Classic récent : C_Container / C_Spell ; anciens clients : globales)
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

-- Nom localisé du sort « Nourriture » (433) utilisé par quasiment toute la bouffe.
local FOOD_SPELL = SpellName(433)

local foodCache = {}
local function IsFood(itemID)
    local cached = foodCache[itemID]
    if cached ~= nil then return cached end
    local spell = GetItemSpellCompat(itemID)
    if spell == nil then
        -- Infos pas encore en cache client : on retentera au prochain scan.
        if not GetItemInfoCompat(itemID) then return false end
        foodCache[itemID] = false
        return false
    end
    local food = (spell == FOOD_SPELL)
    foodCache[itemID] = food
    return food
end

-- Renvoie bag, slot, itemID, count de la plus petite pile de nourriture.
local function FindSmallestFood()
    local bestBag, bestSlot, bestID, bestCount
    for bag = 0, 4 do
        for slot = 1, (GetNumSlots(bag) or 0) do
            local id = GetItemID(bag, slot)
            if id and IsFood(id) then
                local count = GetSlotCount(bag, slot)
                if not bestCount or count < bestCount then
                    bestBag, bestSlot, bestID, bestCount = bag, slot, id, count
                end
            end
        end
    end
    return bestBag, bestSlot, bestID, bestCount
end

-- Bouton sécurisé (utiliser un objet est une action protégée)
local button = CreateFrame("Button", "FeedMePLZButton", UIParent, "SecureActionButtonTemplate")
button:SetSize(40, 40)
button:SetMovable(true)
button:SetClampedToScreen(true)
button:RegisterForClicks("AnyUp", "AnyDown")
button:RegisterForDrag("LeftButton")
button:SetAttribute("type", "item")

local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetAllPoints()
icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

local border = button:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
border:SetPoint("CENTER")
border:SetSize(66, 66)

button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

local countText = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
countText:SetPoint("BOTTOMRIGHT", -2, 2)

local currentID
local pending = false -- mise à jour reportée à la sortie de combat

local function Refresh()
    if InCombatLockdown() then pending = true return end
    pending = false
    local bag, slot, id, count = FindSmallestFood()
    currentID = id
    if bag then
        button:SetAttribute("item", bag .. " " .. slot)
        icon:SetTexture(GetItemIconCompat(id))
        icon:SetDesaturated(false)
        countText:SetText(count > 1 and count or "")
    else
        button:SetAttribute("item", nil)
        icon:SetTexture("Interface\\Icons\\INV_Misc_Food_15")
        icon:SetDesaturated(true)
        countText:SetText("")
    end
end

-- Déplacement : Maj + glisser
button:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() and not InCombatLockdown() and not FeedMePLZDB.locked then
        self:StartMoving()
    end
end)
button:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    FeedMePLZDB.pos = { point, relPoint, x, y }
end)

button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if currentID then
        GameTooltip:SetItemByID(currentID)
    else
        GameTooltip:SetText("FeedMePLZ")
        GameTooltip:AddLine("Aucune nourriture dans les sacs.", 1, 0.3, 0.3)
    end
    GameTooltip:AddLine("Maj + glisser pour déplacer", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
button:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function ApplyPosition()
    button:ClearAllPoints()
    local p = FeedMePLZDB.pos
    if p then
        button:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        button:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    end
end

-- Regroupe les rafales de BAG_UPDATE en un seul scan
local throttle = CreateFrame("Frame")
throttle:Hide()
throttle.elapsed = 0
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
            FeedMePLZDB = FeedMePLZDB or {}
            ApplyPosition()
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
    if InCombatLockdown() then print("|cffff8800FeedMePLZ|r : pas en combat.") return end
    if msg == "lock" then
        FeedMePLZDB.locked = true
        print("|cffff8800FeedMePLZ|r : bouton verrouillé.")
    elseif msg == "unlock" then
        FeedMePLZDB.locked = false
        print("|cffff8800FeedMePLZ|r : bouton déverrouillé (Maj + glisser).")
    elseif msg == "reset" then
        FeedMePLZDB.pos = nil
        ApplyPosition()
        print("|cffff8800FeedMePLZ|r : position réinitialisée.")
    elseif msg == "hide" then
        button:Hide()
    elseif msg == "show" then
        button:Show()
    else
        print("|cffff8800FeedMePLZ|r : /fmp lock | unlock | reset | show | hide")
    end
end
