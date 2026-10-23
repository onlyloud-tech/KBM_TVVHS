local AppWindowBase = require("KBMGB/UI/AppWindowBase")
local AppHost = require("KBMGB/System/AppHost")
local VTUtils = require("KBMGB/System/VTUtils")

local TVMovieWindow = AppWindowBase:derive("TVMovieWindow")

local BASE_W, BASE_H = 800, 735
-- Temporary layout calibration. Left-clicks record coordinates instead of
-- activating controls; right-click clears the recorded points.
local CALIBRATION_MODE = false
-- Recorded in-game bounds of the replacement CRT's visible screen.
local VIEW_X, VIEW_Y, VIEW_W, VIEW_H = 74, 59, 661, 418
local SCREEN_X, SCREEN_Y, SCREEN_W, SCREEN_H = 74, 59, 661, 418

local BUTTONS = {
    { x=72,  y=647, w=70, h=41, action="power" },
    { x=157, y=647, w=46, h=41, action="volumeDown" },
    { x=203, y=647, w=45, h=41, action="volumeUp" },
    { x=347, y=647, w=48, h=41, action="play" },
    { x=394, y=647, w=47, h=41, action="eject" },
    { x=454, y=647, w=58, h=41, action="stop" },
    { x=518, y=647, w=37, h=41, action="rewind" },
    { x=553, y=647, w=37, h=41, action="fastForward" },
    { x=584, y=647, w=37, h=41, action="pause" },
}

local MOVEMENT_KEYS = {
    [Keyboard.KEY_W] = true, [Keyboard.KEY_A] = true,
    [Keyboard.KEY_S] = true, [Keyboard.KEY_D] = true,
    [Keyboard.KEY_UP] = true, [Keyboard.KEY_DOWN] = true,
    [Keyboard.KEY_LEFT] = true, [Keyboard.KEY_RIGHT] = true,
}

local function computeWindowSize()
    local sw, sh = VTUtils.safeGetScreen()
    local scale = math.min((sw * 0.95) / BASE_W, (sh * 0.95) / BASE_H)
    return math.floor(BASE_W * scale), math.floor(BASE_H * scale), sw, sh
end

function TVMovieWindow:new(monitorUI, AppModule, args)
    local ww, wh, sw, sh = computeWindowSize()
    local o = AppWindowBase.new(self, math.floor((sw - ww) / 2), math.floor((sh - wh) / 2), ww, wh)
    setmetatable(o, self)
    self.__index = self
    o.monitorUI = monitorUI
    o.AppModule = AppModule
    o.args = args or {}
    o.moveWithMouse = false
    -- The replacement shell has transparent outer corners. Keep the panel
    -- itself transparent and paint black only behind the CRT aperture.
    o.backgroundColor = { r=0, g=0, b=0, a=0 }
    o.borderColor = { r=0, g=0, b=0, a=0 }
    o.modalLockId = "kbmgbmoviewindow"
    o.captureMouse = true
    o.calibrationMode = CALIBRATION_MODE
    o.calibrationClicks = {}
    o.playerObj = (args and args.playerObj)
        or (_G.getSpecificPlayer and getSpecificPlayer(0))
        or (_G.getPlayer and getPlayer())
    o.signalTex = getTexture("media/textures/Item_tv_overlay_kbm.png")
    o.noSignalTex = getTexture("media/textures/Item_tv_overlay_no_signal_kbm.png")
    o.overlayTex = o.noSignalTex or o.signalTex
    o.hiddenForMovement = false
    o.playerX = o.playerObj and o.playerObj.getX and o.playerObj:getX() or nil
    o.playerY = o.playerObj and o.playerObj.getY and o.playerObj:getY() or nil
    return o
end

function TVMovieWindow:hideForMovement()
    if self.hiddenForMovement then return end
    self.hiddenForMovement = true
    self.captureMouse = false
    if self.setCapture then self:setCapture(false) end
    if self.setWantKeyEvents then self:setWantKeyEvents(false) end
    self:setVisible(false)
end

function TVMovieWindow:continueMovie()
    if not self.hiddenForMovement then return end
    self.hiddenForMovement = false
    self.captureMouse = true
    self.playerX = self.playerObj and self.playerObj.getX and self.playerObj:getX() or nil
    self.playerY = self.playerObj and self.playerObj.getY and self.playerObj:getY() or nil
    self:setVisible(true)
    self:_ensureTopAndFocus()
    if self.bringToFront then self:bringToFront() end
end

function TVMovieWindow:prerender()
    local player = self.playerObj
    if player and self.playerX and self.playerY and player.getX and player.getY then
        if math.abs(player:getX() - self.playerX) > 0.01
            or math.abs(player:getY() - self.playerY) > 0.01 then
            self:hideForMovement()
            return
        end
    end
    AppWindowBase.prerender(self)
    local sx, sy = self.width / BASE_W, self.height / BASE_H
    self:drawRect(
        math.floor(SCREEN_X * sx), math.floor(SCREEN_Y * sy),
        math.floor(SCREEN_W * sx), math.floor(SCREEN_H * sy),
        1, 0, 0, 0
    )
end

function TVMovieWindow:getAppViewport()
    local sx, sy = self.width / BASE_W, self.height / BASE_H
    return math.floor(VIEW_X * sx), math.floor(VIEW_Y * sy),
        math.floor(VIEW_W * sx), math.floor(VIEW_H * sy)
end

function TVMovieWindow:render()
    local signal = self.app and self.app.isSignalActive and self.app:isSignalActive()
    self.overlayTex = signal and self.signalTex or self.noSignalTex
    AppWindowBase.render(self)
    if self.calibrationMode then
        self:drawRect(8, 8, 348, 24, 0.85, 0, 0, 0)
        self:drawText("TV CALIBRATION: left-click points; right-click clears", 14, 13, 1, 0.3, 0.3, 1, UIFont.Small)
        local sx, sy = self.width / BASE_W, self.height / BASE_H
        for index, point in ipairs(self.calibrationClicks) do
            local px, py = math.floor(point.x * sx), math.floor(point.y * sy)
            self:drawRect(px - 4, py - 4, 9, 9, 1, 1, 0, 0)
            self:drawText(tostring(index) .. ": " .. tostring(point.x) .. "," .. tostring(point.y), px + 7, py - 8, 1, 0.2, 0.2, 1, UIFont.Small)
        end
    end
end

function TVMovieWindow:_actionAt(x, y)
    local bx, by = x * BASE_W / self.width, y * BASE_H / self.height
    for _, button in ipairs(BUTTONS) do
        if VTUtils.pointInRect(bx, by, button.x, button.y, button.w, button.h) then
            return button.action
        end
    end
    return nil
end

function TVMovieWindow:onMouseDown(x, y)
    self:_ensureTopAndFocus()
    if self.calibrationMode then
        local bx = math.floor(x * BASE_W / self.width + 0.5)
        local by = math.floor(y * BASE_H / self.height + 0.5)
        self.calibrationClicks[#self.calibrationClicks + 1] = { x=bx, y=by }
        print("[KBMGB][TVCal] point " .. tostring(#self.calibrationClicks)
            .. " base=" .. tostring(bx) .. "," .. tostring(by)
            .. " local=" .. tostring(math.floor(x)) .. "," .. tostring(math.floor(y)))
        return true
    end
    local action = self:_actionAt(x, y)
    local app = self.app
    if not action or not app then return true end
    if action == "power" then app:togglePower()
    elseif action == "volumeUp" then app:adjustVolume(0.1)
    elseif action == "volumeDown" then app:adjustVolume(-0.1)
    elseif action == "eject" then self:close()
    elseif action == "stop" then app:stop()
    elseif action == "rewind" then app:seekChunk(-1)
    elseif action == "play" then app:play()
    elseif action == "fastForward" then app:seekChunk(1)
    elseif action == "pause" then app:togglePause()
    end
    return true
end

function TVMovieWindow:onRightMouseDown(_x, _y)
    if self.calibrationMode then
        self.calibrationClicks = {}
        print("[KBMGB][TVCal] points cleared")
    end
    return true
end
function TVMovieWindow:onMouseUp(_x, _y) return true end
function TVMovieWindow:onMouseUpOutside(_x, _y) return true end
function TVMovieWindow:isKeyConsumed(key)
    return key == Keyboard.KEY_BACK or key == Keyboard.KEY_DELETE
        or key == Keyboard.KEY_ESCAPE or key == Keyboard.KEY_SPACE or key == Keyboard.KEY_R
end

function TVMovieWindow:onKeyDown(key)
    if MOVEMENT_KEYS[key] then self:hideForMovement() end
    return false
end

function TVMovieWindow:onKeyPress(key)
    if MOVEMENT_KEYS[key] then self:hideForMovement(); return false end
    if key == Keyboard.KEY_BACK or key == Keyboard.KEY_DELETE or key == Keyboard.KEY_ESCAPE then
        self:close()
        return true
    end
    if self.app then return AppHost.onKey(self.app, self, key) == true end
    return false
end

function TVMovieWindow:close()
    -- This window never locked movement, so closing it must not clear another
    -- device's player lock through AppWindowBase.close().
    self.playerObj = nil
    AppWindowBase.close(self)
    if self.onClosed then self.onClosed(self) end
end

return TVMovieWindow
