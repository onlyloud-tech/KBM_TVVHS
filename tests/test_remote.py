import unittest
from test_optimizations import runtime


def remote_runtime():
    vm = runtime()
    vm.execute('''
        clientMode=false
        function isClient() return clientMode end
        function instanceof(o,kind) return o and o.kind==kind end
        ISPanel={}
        function ISPanel:derive() local c={}; c.__index=c; return setmetatable(c,{__index=self}) end
        function ISPanel:new(x,y,w,h) return setmetatable({x=x,y=y,width=w,height=h},{__index=self}) end
        for _,name in ipairs({'initialise','instantiate','setVisible','bringToTop','removeFromUIManager'}) do ISPanel[name]=function() end end
        function ISPanel:addToUIManager() openedWindow=self end
        package.preload['ISUI/ISPanel']=function() return ISPanel end
        queued={}
        ISRadioAction={new=function(_,mode,p,device,value) return {mode=mode,character=p,device=device,deviceData=device:getDeviceData(),secondaryItem=value} end}
        for _,name in ipairs({'TogglePlayMedia','ToggleOnOff','SetVolume','MuteVolume','UnMuteVolume'}) do
            ISRadioAction['perform'..name]=function() end
        end
        ISDeviceMediaAction={invoke=function() end,new=function(_,p,remove,item,square) return {eject=true,square=square} end}
        ISTimedActionQueue={add=function(a) queued[#queued+1]=a end}
        package.preload['RadioCom/ISRadioAction']=function() return ISRadioAction end
        package.preload['TimedActions/ISDeviceMediaAction']=function() return ISDeviceMediaAction end
        package.preload['TimedActions/ISTimedActionQueue']=function() return ISTimedActionQueue end
        for _,name in ipairs({'KBMGB/Movie/DeviceWindow','KBMGB/Movie/WatchReward'}) do
            package.preload[name]=function() return {} end
        end
        package.preload['KBMGB/Movie/PremiumScreen']=function() return {update=function() end,canRender=function() return false end} end
        package.preload['KBMGB/Movie/ViewMode']=function() return {isViewpointActive=function() return false end} end
        function getCore() return {getScreenWidth=function() return 1920 end,getScreenHeight=function() return 1080 end} end
        function getTexture() return {} end
        grid={}
        function square(x,y,z)
            local sq={x=x,y=y,z=z or 0,objects={},worlds={}}
            sq.getX=function(s) return s.x end; sq.getY=function(s) return s.y end; sq.getZ=function(s) return s.z end
            sq.getObjects=function(s) return list(s.objects) end; sq.getWorldObjects=function(s) return list(s.worlds) end
            sq.getCell=function() return cell end
            grid[x..','..y..','..sq.z]=sq; return sq
        end
        cell={getGridSquare=function(_,x,y,z) return grid[x..','..y..','..z] end}
        origin=square(0,0)
        player={getSquare=function() return origin end,getPlayerNum=function() return 0 end,
            getX=function() return 0 end,getY=function() return 0 end,getZ=function() return 0 end,
            getUsername=function() return 'alice' end,getAccessLevel=function() return 'None' end}
        function getSpecificPlayer() return player end
        function getPlayer() return player end
        function tv(face,x,y,z)
            local sq=square(x,y,z); local md={}
            local dd={allowed=true,on=true,volume=.5}
            dd.getIsTelevision=function() return true end
            dd.canPlayerRemoteInteract=function(s) return s.allowed end
            dd.getIsTurnedOn=function(s) return s.on end; dd.hasMedia=function() return true end
            dd.getMediaData=function() return {getId=function() return 'RemoteMovie' end} end
            dd.getDeviceVolume=function(s) return s.volume end
            local device={getSquare=function() return sq end,getDeviceData=function() return dd end,
                getModData=function() return md end,getObjectIndex=function() return 0 end,
                getSprite=function() return {getName=function() return 'appliances_television_01_'..face end} end}
            sq.objects[1]=device; return device
        end
        function context()
            local c={options={}}
            c.addOption=function(s,name,target,fn) local o={name=name,target=target,callback=fn};s.options[#s.options+1]=o;return o end
            c.getOptionFromName=function(s,name) for _,o in ipairs(s.options) do if o.name==name then return o end end end
            return c
        end
        function worldMenu(device)
            local c=context()
            for _,fn in ipairs(callbacks.OnFillWorldObjectContextMenu or {}) do fn(0,c,{device},false) end
            return c
        end
        require 'KBM_ViewpointProbe'
        Targets=require 'KBMGB/Movie/TVRemoteTargets'
    ''')
    return vm


class RemoteTargetTests(unittest.TestCase):
    def setUp(self):
        self.vm = remote_runtime()

    def test_all_premium_and_valutech_facings_open_same_remote(self):
        self.vm.execute('''
            for face=0,7 do
                local device=tv(face,1,0)
                assert(Targets.isNativeTV(device))
                local c=worldMenu(device)
                local option=c:getOptionFromName('KnoxBox TV Remote'); assert(option)
                assert(not c:getOptionFromName('Device Options (KnoxBox TV)'), 'native device panel replaced')
                option.callback(option.target); assert(openedWindow.device==device)
            end
        ''')

    def test_nearest_selection_range_and_floor(self):
        self.vm.execute('''
            far=tv(0,5,0); near=tv(4,2,0); upper=tv(5,0,0,1)
            assert(Targets.nearest(player)==near)
            near:getDeviceData().allowed=false
            assert(Targets.nearest(player)==far)
            far:getDeviceData().allowed=false
            assert(Targets.nearest(player)==nil)
            local c=worldMenu(near); assert(not c:getOptionFromName('KnoxBox TV Remote'))
            assert(not Targets.isNativeTV(tv(8,6,0)))
            assert(not Targets.isNativeTV(nil))
        ''')

    def test_custom_tv_remains_targetable_and_remote_inventory_selects_native(self):
        self.vm.execute('''
            local sq=square(3,0)
            local dd={canPlayerRemoteInteract=function() return true end}
            local radio={kind='IsoRadio',getModData=function() return {RadioItemID=42} end,getDeviceData=function() return dd end}
            local item={getFullType=function() return 'KBM.ScreenTV' end,getID=function() return 42 end}
            sq.objects={radio};sq.worlds={{getItem=function() return item end}}
            assert(Targets.nearest(player)==radio)
            local native=tv(7,1,0)
            local c=context()
            local remote={getFullType=function() return 'Base.Remote' end}
            for _,fn in ipairs(callbacks.OnFillInventoryObjectContextMenu) do fn(0,c,{remote}) end
            local option=c:getOptionFromName('Use KnoxBox TV Remote');assert(option)
            option.callback(option.target);assert(openedWindow.device==native)
        ''')

    def test_remote_buttons_use_selected_native_device_and_iso_playback(self):
        self.vm.execute('''
            local device=tv(4,1,0); local c=worldMenu(device)
            local option=c:getOptionFromName('KnoxBox TV Remote');option.callback(option.target)
            local paused=false;local delta=0
            KBMMPVanillaPlayback={isActive=function(d) return d==device end,isPaused=function() return paused end,
                togglePause=function(d) assert(d==device); paused=not paused end,
                seek=function(d,n) assert(d==device);delta=delta+n end}
            openedWindow:activate('pause');assert(paused)
            openedWindow:activate('play');assert(not paused)
            openedWindow:activate('forward');assert(delta==10)
            openedWindow:activate('rewind');assert(delta==0)
            openedWindow:activate('power');assert(queued[#queued].device==device and queued[#queued].mode=='ToggleOnOff')
            openedWindow:activate('up');assert(queued[#queued].device==device and queued[#queued].secondaryItem==.6)
            local before=#queued;device:getDeviceData().allowed=false
            openedWindow:activate('power');assert(#queued==before)
        ''')

    def test_mp_remote_uses_server_state_and_requests(self):
        self.vm.execute('''
            clientMode=true; sent={}
            function sendClientCommand(module,command,args) sent[#sent+1]={command=command,args=args} end
            require 'KBMMP_Client'
            local registry=require 'KBMGB/Movie/MoviePackRegistry'
            registry.register{packId='remote-pack',modId='Pack',entries={{itemType='Pack.RemoteTape',video='remote.mp4',recMediaId='RemoteMovie'}}}
            fire('OnGameStart')
            local device=tv(2,1,0)
            KBMMPClient.states={{address={x=1,y=0,z=0,index=0},token='token',revision=7,playing=true,paused=false,owner='alice'}}
            local c=worldMenu(device);local option=c:getOptionFromName('KnoxBox TV Remote')
            option.callback(option.target)
            openedWindow:activate('pause');assert(sent[#sent].command=='Pause')
            assert(sent[#sent].args.token=='token' and sent[#sent].args.revision==7)
            openedWindow:activate('forward');assert(sent[#sent].command=='Seek' and sent[#sent].args.delta==10)
            -- Resume follows authoritative paused state, even with no local 3D renderer.
            KBMMPClient.states[1].paused=true
            openedWindow:activate('play');assert(sent[#sent].command=='Pause')
            openedWindow:activate('power')
            ISRadioAction.performToggleOnOff(queued[#queued]);assert(sent[#sent].command=='Power')
            openedWindow:activate('up')
            ISRadioAction.performSetVolume(queued[#queued]);assert(sent[#sent].command=='Volume' and sent[#sent].args.volume==.6)
            KBMMPClient.states[1].playing=false
            openedWindow:activate('play')
            ISRadioAction.performTogglePlayMedia(queued[#queued]);assert(sent[#sent].command=='Toggle')
        ''')

    def test_iso_remote_uses_real_overlay_api_and_clamps_seek(self):
        self.vm.execute('''
            local currentFrame,playing=101,true
            audioStops=0
            local app={kbm={isFinished=function() return false end,isPlaying=function() return playing end,
                getCurrentFrame=function() return currentFrame end,getTotalFrames=function() return 1000 end,
                getFps=function() return 10 end,seekFrame=function(n) currentFrame=n end}}
            app.togglePause=function() playing=not playing end
            app.pause=function() playing=false end
            app._stopAudio=function() audioStops=audioStops+1 end
            package.preload['KBMGB/Movie/JavaMoviePlayerApp']=function() return {} end
            package.preload['KBMGB/System/VTUtils']=function() return {
                isKnoxBox3DTV=function() return false end,
                isTelevisionObject=function(d) return d and d.getDeviceData~=nil end} end
            package.preload['KBMGB/Movie/TVMovieWindow']=function()
                return {new=function(_,_,_,args) return {app=app,args=args,initialise=function() end,
                    addToUIManager=function() end,close=function() end} end}
            end
            require 'KBMGB/ZZMovie/TVMovieRadioPatch'
            local device=tv(5,1,0)
            KBMMPVanillaPlayback.open(device,{itemType='Pack.Tape'})
            assert(KBMMPVanillaPlayback.isActive(device))
            assert(not KBMMPVanillaPlayback.isActive(tv(0,3,0)))
            local c=worldMenu(device);local option=c:getOptionFromName('KnoxBox TV Remote')
            option.callback(option.target)
            openedWindow:activate('pause');assert(KBMMPVanillaPlayback.isPaused(device))
            openedWindow:activate('forward');assert(currentFrame==201 and not playing and audioStops==1)
            openedWindow:activate('play');assert(playing)
            KBMMPVanillaPlayback.seek(device,10000);assert(currentFrame==1000)
            KBMMPVanillaPlayback.seek(device,-10000);assert(currentFrame==1)
            KBMMPVanillaPlayback.close();assert(not KBMMPVanillaPlayback.isActive(device))
        ''')


if __name__ == '__main__':
    unittest.main(verbosity=2)
