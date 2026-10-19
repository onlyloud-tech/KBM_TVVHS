-- The pictured remote controls the same IsoRadio as the native TV panel.
require "ISUI/ISPanel"
require "RadioCom/ISRadioAction"
require "TimedActions/ISDeviceMediaAction"
require "TimedActions/ISTimedActionQueue"

local Remote = ISPanel:derive("KBMViewpointTVRemote")
local instances = {}
local IMAGE_W, IMAGE_H = 157, 381
local IMAGE = "media/ui/KBM_TV_Remote.png"
-- Coordinates are measured on remote_overlay.png, before UI scaling.
local buttons = {
    { name="power",   x1=17,  y1=55,  x2=65,  y2=89 },
    { name="eject",   x1=93,  y1=55,  x2=142, y2=89 },
    { name="rewind",  x1=16,  y1=117, x2=68,  y2=153 },
    { name="forward", x1=90,  y1=117, x2=142, y2=153 },
    { name="play",    x1=31,  y1=175, x2=77,  y2=212 },
    { name="pause",   x1=78,  y1=175, x2=125, y2=212 },
    { name="down",    x1=21,  y1=248, x2=78,  y2=287 },
    { name="up",      x1=80,  y1=248, x2=141, y2=287 },
    { name="close",   x1=132, y1=0,   x2=157, y2=30 },
}

local function deviceData(self)
    if not self.device or not self.device.getSquare or not self.device:getSquare() then return nil end
    return self.device.getDeviceData and self.device:getDeviceData() or nil
end

local function canUse(self)
    local data = deviceData(self)
    return data and self.player and data:canPlayerRemoteInteract(self.player) or false
end

function Remote:buttonAt(x, y)
    local px, py = x / self.scale, y / self.scale
    for _, button in ipairs(buttons) do
        if px >= button.x1 and px <= button.x2 and py >= button.y1 and py <= button.y2 then
            return button.name
        end
    end
end

function Remote:queue(mode, value)
    if canUse(self) then
        ISTimedActionQueue.add(ISRadioAction:new(mode, self.player, self.device, value))
    end
end

function Remote:activate(action)
    if action == "close" then self:close(); return end
    local data = deviceData(self)
    if not data or not canUse(self) then
        print("[KBMViewpointTVRemote] " .. tostring(action) .. " unavailable: TV out of range")
        return
    end
    local playing = self.controls.isActive and self.controls.isActive(self.device)
    print("[KBMViewpointTVRemote] " .. tostring(action) .. " active=" .. tostring(playing))
    if action == "power" then
        self:queue("ToggleOnOff")
    elseif action == "eject" then
        if data:hasMedia() then
            ISTimedActionQueue.add(ISDeviceMediaAction:new(
                self.player, true, nil, self.device:getSquare()))
        end
    elseif action == "play" then
        if playing then
            if self.controls.isPaused(self.device) then self.controls.togglePause(self.device) end
        elseif data:getIsTurnedOn() and data:hasMedia() then
            self:queue("TogglePlayMedia")
        end
    elseif action == "pause" then
        if playing and not self.controls.isPaused(self.device) then
            self.controls.togglePause(self.device)
        end
    elseif action == "rewind" or action == "forward" then
        if playing and self.controls.seek then
            self.controls.seek(self.device, action == "rewind" and -10 or 10)
        end
    elseif action == "down" or action == "up" then
        if not data:getIsTurnedOn() then return end
        local volume = math.max(0, math.min(1,
            data:getDeviceVolume() + (action == "up" and 0.1 or -0.1)))
        self:queue("SetVolume", volume)
    end
end

function Remote:prerender()
    ISPanel.prerender(self)
    if self.texture then self:drawTextureScaled(self.texture, 0, 0, self.width, self.height, 1) end
    -- The supplied artwork has no close glyph; keep this small and unobtrusive.
    self:drawText("X", self.width - 17, 5, 0.8, 0.8, 0.8, 1, UIFont.Small)
end

function Remote:onMouseDown(x, y)
    self:bringToTop()
    self.pressed = self:buttonAt(x, y)
    print("[KBMViewpointTVRemote] click x=" .. tostring(x) .. " y=" .. tostring(y)
        .. " button=" .. tostring(self.pressed))
    if not self.pressed then self.moving = true end
    return true
end

function Remote:onMouseUp(x, y)
    if self.pressed and self.pressed == self:buttonAt(x, y) then
        self:activate(self.pressed)
    end
    self.pressed, self.moving = nil, false
    return true
end

function Remote:onMouseUpOutside()
    self.pressed, self.moving = nil, false
    return true
end

function Remote:onMouseMove(dx, dy)
    if self.moving then
        self:setX(math.max(0, math.min(getCore():getScreenWidth() - self.width, self.x + dx)))
        self:setY(math.max(0, math.min(getCore():getScreenHeight() - self.height, self.y + dy)))
    end
    return true
end

function Remote:onMouseMoveOutside(dx, dy)
    return self:onMouseMove(dx, dy)
end

function Remote:onRightMouseUp()
    self:close()
    return true
end

function Remote:close()
    self.pressed, self.moving = nil, false
    self:removeFromUIManager()
end

function Remote:new(player, device, controls)
    local scale = math.min(1.5, (getCore():getScreenHeight() - 70) / IMAGE_H)
    local width, height = math.floor(IMAGE_W * scale), math.floor(IMAGE_H * scale)
    local x = math.max(0, getCore():getScreenWidth() - width - 25)
    local y = math.max(0, math.floor((getCore():getScreenHeight() - height) / 2))
    local o = ISPanel.new(self, x, y, width, height)
    o.player, o.device, o.controls = player, device, controls
    o.scale = scale
    o.texture = getTexture(IMAGE)
    o.background = false
    return o
end

local Overlay = {}

function Overlay.open(player, device, controls)
    if not player or not device or not controls then return end
    local playerNum = player:getPlayerNum()
    local win = instances[playerNum]
    if not win then
        win = Remote:new(player, device, controls)
        win:initialise()
        win:instantiate()
        instances[playerNum] = win
    end
    win.player, win.device, win.controls = player, device, controls
    win:addToUIManager()
    win:setVisible(true)
    win:bringToTop()
end

return Overlay
