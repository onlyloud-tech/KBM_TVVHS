require "ISUI/ISInventoryPaneContextMenu"

local BOX_TYPE = "KBM.VHSCollectionBox"
local WRITING_TOOLS = {
    ["Base.Pen"] = true, ["Base.Pencil"] = true,
    ["Base.BluePen"] = true, ["Base.GreenPen"] = true,
    ["Base.RedPen"] = true, ["Base.PenFancy"] = true,
    ["Base.PenMultiColor"] = true, ["Base.PenSpiffo"] = true,
    ["Base.PencilSpiffo"] = true, ["Base.MarkerBlack"] = true,
    ["Base.MarkerBlue"] = true, ["Base.MarkerGreen"] = true,
    ["Base.MarkerRed"] = true,
}

local function isCollectionBox(item)
    return item and item.getFullType and item:getFullType() == BOX_TYPE
end

local function hasWritingTool(player)
    local inventory = player and player.getInventory and player:getInventory() or nil
    if not inventory then return false end
    for fullType in pairs(WRITING_TOOLS) do
        if inventory:containsTypeRecurse(fullType) then return true end
    end
    return false
end

local function requireWritingTool(player)
    if hasWritingTool(player) then return true end
    if player and player.Say then
        player:Say("A pen, pencil, or marker is needed to label the box.")
    end
    return false
end

local originalRenameBag = ISInventoryPaneContextMenu.onRenameBag
ISInventoryPaneContextMenu.onRenameBag = function(bag, playerNum)
    if isCollectionBox(bag) and not requireWritingTool(getSpecificPlayer(playerNum)) then return end
    return originalRenameBag(bag, playerNum)
end

local originalRenameBagClick = ISInventoryPaneContextMenu.onRenameBagClick
function ISInventoryPaneContextMenu:onRenameBagClick(button, player, item)
    if button and button.internal == "OK" and isCollectionBox(item)
        and not requireWritingTool(player) then return end
    return originalRenameBagClick(self, button, player, item)
end
