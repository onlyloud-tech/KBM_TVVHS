-- KBM devices use their own window so UI replacements can keep owning theirs.
require "ISUI/ISCollapsableWindow"
require "RadioCom/RadioWindowModules/RWMElement"
require "RadioCom/RadioWindowModules/RWMGeneral"
require "RadioCom/RadioWindowModules/RWMPower"
require "RadioCom/RadioWindowModules/RWMGridPower"
require "RadioCom/RadioWindowModules/RWMVolume"
require "RadioCom/RadioWindowModules/RWMMedia"
require "RadioCom/RadioWindowModules/RWMChannelTV"

local Window = ISCollapsableWindow:derive("KBMDeviceWindow")
local instances = {}

function Window:new(player)
    local width = 250 + getCore():getOptionFontSizeReal() * 50
    local window = ISCollapsableWindow.new(self, 100, 100, width, 500)
    window.playerNum = player:getPlayerNum()
    window.modules = {}
    window.resizable = false
    window.drawFrame = true
    window.pin = true
    window.overrideBPrompt = true
    window.backgroundColor = {r=0, g=0, b=0, a=0.85}
    window.title = "KnoxBox Device Options"
    return window
end

function Window:addDeviceModule(panelClass, label)
    local panel = panelClass:new(0, 0, self.width, 0)
    local element = RWMElement:new(0, 0, self.width, 0, panel, getText(label), self)
    self.modules[#self.modules + 1] = {element=element, enabled=false, panelClass=panelClass}
    self:addChild(element)
end

function Window:createChildren()
    ISCollapsableWindow.createChildren(self)
    self:addDeviceModule(RWMGeneral, "IGUI_RadioGeneral")
    self:addDeviceModule(RWMPower, "IGUI_RadioPower")
    self:addDeviceModule(RWMGridPower, "IGUI_RadioPower")
    self:addDeviceModule(RWMVolume, "IGUI_RadioVolume")
    self:addDeviceModule(RWMMedia, "IGUI_RadioMedia")
    self:addDeviceModule(RWMChannelTV, "IGUI_RadioChannel")
end

function Window:readFromObject(player, device)
    self.player = player
    self.device = device
    self.deviceData = device:getDeviceData()
    self.deviceType = instanceof(device, "Radio") and "InventoryItem" or "IsoObject"
    self.subFocus = nil
    local md = device.getModData and device:getModData()
    local cinema = md and md.KBMStaticProjector
    for _, module in ipairs(self.modules) do
        module.element:clear()
        module.enabled = not (cinema and module.panelClass == RWMChannelTV)
            and module.element:readFromObject(player, device, self.deviceData, self.deviceType) == true
        module.element:setVisible(module.enabled)
    end
end

function Window.activate(player, device)
    if not player or not device or not device.getDeviceData or not device:getDeviceData() then return nil end
    local index = player:getPlayerNum()
    local window = instances[index]
    if not window then
        window = Window:new(player)
        window:initialise()
        window:instantiate()
        instances[index] = window
    end
    window:readFromObject(player, device)
    window:addToUIManager()
    window:setVisible(true)
    window:bringToTop()
    window:stayOnSplitScreen()
    if JoypadState.players[index + 1] then setJoypadFocus(index, window) end
    return window
end

function Window:prerender()
    self:stayOnSplitScreen()
    local y = self:titleBarHeight() + 1
    for _, module in ipairs(self.modules) do
        if module.enabled then
            module.element:setY(y)
            y = y + module.element:getHeight() + 1
        end
    end
    self:setHeight(y)
    ISCollapsableWindow.prerender(self)
end

function Window:update()
    ISCollapsableWindow.update(self)
    if not self.player or not self.device or not self.deviceData then self:close(); return end
    if self.deviceType == "IsoObject" then
        local square = self.device:getSquare()
        if not square or math.abs(self.player:getX() - square:getX()) >= 10
                or math.abs(self.player:getY() - square:getY()) >= 10
                or self.player:getZ() ~= square:getZ() then self:close() end
    end
end

function Window:close()
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if getFocusForPlayer(self.playerNum) == self
            or (self.subFocus and getFocusForPlayer(self.playerNum) == self.subFocus.element) then
        setJoypadFocus(self.playerNum, nil)
    end
    for _, module in ipairs(self.modules) do module.element:clear() end
    self.player, self.device, self.deviceData, self.subFocus = nil, nil, nil, nil
end

function Window:focusSelf()
    self.subFocus = nil
    setJoypadFocus(self.playerNum, self)
end

function Window:unfocusSelf()
    setJoypadFocus(self.playerNum, nil)
end

function Window:focusNext(up)
    local enabled, current = {}, nil
    for _, module in ipairs(self.modules) do
        if module.enabled then
            enabled[#enabled + 1] = module
            if module == self.subFocus then current = #enabled end
        end
    end
    if #enabled == 0 then return end
    local index = current and ((current - 1 + (up and -1 or 1)) % #enabled + 1)
        or (up and #enabled or 1)
    self.subFocus = enabled[index]
    self.subFocus.element:setFocus(self.playerNum, self)
end

function Window:onJoypadDirUp() self:focusNext(true) end
function Window:onJoypadDirDown() self:focusNext(false) end
function Window:onJoypadDown(button)
    if button == Joypad.BButton then self:close()
    elseif button == Joypad.RBumper then self:focusNext(false)
    elseif button == Joypad.LBumper then self:unfocusSelf() end
end
function Window:getBPrompt() return getText("IGUI_RadioClose") end
function Window:isValidPrompt() return self.device ~= nil end

return Window
