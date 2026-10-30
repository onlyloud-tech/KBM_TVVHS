-- Incremental discovery only. Playback and caption clearing remain immediate.
local Scan = {}
Scan.__index = Scan

function Scan.new(radius, budget)
    return setmetatable({radius=radius, budget=budget, nextAt=0}, Scan)
end

function Scan:update(player, now, interval, visit)
    if self.interval and interval<self.interval then self.nextAt=math.min(self.nextAt,now) end
    self.interval=interval
    local cell = player and player:getCell()
    if not cell then
        self.cell, self.cursor, self.found = nil, nil, nil
        self.nextAt = 0
        return nil, true
    end
    local x, y, z = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    local far = self.x and (math.abs(x-self.x)>self.radius or math.abs(y-self.y)>self.radius)
    local invalid = cell~=self.cell or z~=self.z or far
    if invalid then self.cursor, self.found = nil, nil end
    if not self.cursor then
        local moved = x~=self.x or y~=self.y
        if not invalid and not moved and now<self.nextAt then return end
        self.cell, self.x, self.y, self.z = cell, x, y, z
        self.cursor, self.found = 0, {}
    end
    local width = self.radius*2+1
    local finish = math.min(width*width, self.cursor+self.budget)
    for at=self.cursor,finish-1 do
        local square = cell:getGridSquare(self.x-self.radius+math.floor(at/width),
            self.y-self.radius+at%width, self.z)
        local objects = square and square:getObjects()
        if objects then
            for i=0,objects:size()-1 do
                local object=objects:get(i)
                if object and object.getDeviceData and object.getChatElement then
                    self.found[object]=true
                    visit(object)
                end
            end
        end
    end
    self.cursor=finish
    if finish==width*width then
        local result=self.found
        self.cursor, self.found, self.nextAt = nil, nil, now+interval
        return result, invalid
    end
    return nil, invalid
end

return Scan
