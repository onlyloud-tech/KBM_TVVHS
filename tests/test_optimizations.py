"""Exercise repository Lua with mocked PZ objects. Requires lupa (Lua 5.1)."""
from pathlib import Path
import os
import sys
import unittest

if os.environ.get('KBM_LUA_TEST_PATH'):
    sys.path.insert(0, os.environ['KBM_LUA_TEST_PATH'])
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
LUA = ROOT / 'common/media/lua'


def runtime():
    vm = LuaRuntime(unpack_returned_tuples=True)
    paths = [LUA/'shared/?.lua', LUA/'client/?.lua', LUA/'server/?.lua', ROOT/'42/media/lua/client/?.lua']
    vm.execute('package.path=... .. ";" .. package.path', ';'.join(p.as_posix() for p in paths))
    vm.execute('''
        print=function() end
        now=0
        function getTimestampMs() return now end
        function list(t) return {size=function() return #t end,get=function(_,i) return t[i+1] end} end
        callbacks={}
        Events=setmetatable({}, {__index=function(t,k)
            local e={Add=function(fn) callbacks[k]=callbacks[k] or {}; table.insert(callbacks[k],fn) end}
            rawset(t,k,e); return e
        end})
        function fire(name) for _,fn in ipairs(callbacks[name] or {}) do fn() end end
    ''')
    return vm


class RegistryTests(unittest.TestCase):
    def setUp(self):
        self.vm = runtime()
        self.vm.execute('''
            R=require 'KBMGB/Movie/MoviePackRegistry'
            entries={}
            for i=1,1000 do entries[i]={itemType='Pack.Movie'..i,video='movie.mp4',recMediaId='Movie'..i} end
            R.register{packId='first',modId='Pack',entries=entries}
            P=require 'KBMMP/Protocol'
            id='Movie999'; reads=0
            local media={getId=function() reads=reads+1; return id end}
            local dd={getIsTelevision=function() return true end,hasMedia=function() return true end,
                getMediaData=function() return media end}
            device={getDeviceData=function() return dd end}
        ''')

    def test_device_lookup_reads_id_once_and_does_not_scan_catalog(self):
        self.vm.execute('''
            R.allEntries=function() error('linear catalog scan') end
            assert(P.entry(device).itemType=='Pack.Movie999'); assert(reads==1)
            id='vanilla'; assert(P.entry(device)==nil); assert(reads==2)
        ''')

    def test_late_registration_changed_tape_and_missing_media(self):
        self.vm.execute('''
            id='Later'; assert(P.entry(device)==nil)
            R.register{packId='second',modId='LaterPack',entries={{itemType='LaterPack.Tape',video='later.mp4',recMediaId='Later'}}}
            assert(P.entry(device).itemType=='LaterPack.Tape')
            id='Movie1'; assert(P.entry(device).itemType=='Pack.Movie1')
            assert(P.entry(nil)==nil)
            assert(P.entry{getDeviceData=function() return {getIsTelevision=function() return true end,hasMedia=function() return false end} end}==nil)
        ''')

    def test_existing_registry_errors_and_duplicate_media_compatibility(self):
        self.vm.execute('''
            assert(not pcall(R.register,{packId='first',modId='Pack',entries={}}))
            assert(not pcall(R.register,{packId='third',modId='Pack',entries={{itemType='Pack.Movie1',video='x.mp4'}}}))
            -- Shared media IDs were not rejected by the old registry; keep accepting them.
            R.register{packId='fourth',modId='Other',entries={{itemType='Other.Tape',video='x.mp4',recMediaId='Movie1'}}}
            assert(R.get('Other.Tape')); assert(R.getByMediaId('Movie1').itemType=='Pack.Movie1')
            assert(R.getByMediaId(nil)==nil)
        ''')


class InventoryTests(unittest.TestCase):
    def setUp(self):
        self.vm = runtime()
        self.vm.execute('''
            R=require 'KBMGB/Movie/MoviePackRegistry'
            R.register{packId='pack',modId='Pack',entries={{itemType='Pack.Tape',video='a.mp4',recMediaId='Movie'}}}
            catalog={}; directReads=0; categoryReads=0; repairs=0; lookups=0
            rm={getMediaData=function(_,id) directReads=directReads+1; return catalog[id] end,
                getAllMediaForCategory=function() categoryReads=categoryReads+1; local out={}; for _,v in pairs(catalog) do out[#out+1]=v end; return list(out) end}
            function getZomboidRadio() return {getRecordedMedia=function() return rm end} end
            function item(kind)
                return {kind=kind,media=nil,mediaType=0,
                    getFullType=function(s) lookups=lookups+1; return s.kind end,
                    getMediaType=function(s) return s.mediaType end,
                    isRecordedMedia=function(s) return s.media~=nil end,
                    getMediaData=function(s) return s.media end,
                    setMediaType=function(s,v) s.mediaType=v end,
                    setRecordedMediaData=function(s,v) repairs=repairs+1; s.media=v end}
            end
            function media(id) return {getId=function() return id end} end
            items={}; inv={getItems=function() return list(items) end}
            player={getInventory=function() return inv end}
            function getPlayer() return player end
            require 'KBMGB/Movie/TVMovieAutoAttach'
            function pass() now=now+2001; for i=1,math.max(1,math.ceil(#items/32)) do fire('OnTick') end end
        ''')

    def test_idle_scan_is_bounded_and_throttled(self):
        self.vm.execute('''
            for i=1,500 do items[i]=item('Base.Nails') end
            for i=1,1200 do
                now=(i-1)*1000/60
                local before=lookups; fire('OnTick'); assert(lookups-before<=32)
            end
            assert(lookups<6000, 'idle scan was not throttled')
            print(lookups)
        ''')
        print('500 items / 1200 ticks: optimized lookups =', self.vm.globals().lookups, '(baseline 600000)')

    def test_repair_waits_for_media_and_retries_without_rescanning_per_item(self):
        self.vm.execute('''
            for i=1,64 do items[i]=item('Pack.Tape') end
            pass(); assert(repairs==0); assert(categoryReads==1)
            catalog.Movie=media('Movie'); pass(); assert(repairs==64)
            pass(); assert(repairs==64, 'already-correct tape unnecessarily modified')
        ''')

    def test_wrong_media_and_newly_transferred_tape_are_repaired(self):
        self.vm.execute('''
            catalog.Movie=media('Movie'); items[1]=item('Pack.Tape')
            items[1].media=media('Vanilla'); items[1].mediaType=1
            pass(); assert(items[1].media:getId()=='Movie')
            items[2]=item('Pack.Tape'); pass(); assert(items[2].media:getId()=='Movie')
            assert(repairs==2)
        ''')

    def test_inventory_shrink_player_change_and_no_player(self):
        self.vm.execute('''
            for i=1,100 do items[i]=item('Base.Nails') end
            fire('OnTick'); assert(lookups==32)
            items={}; fire('OnTick'); pass()
            player=nil; pass()
            catalog.Movie=media('Movie'); items={item('Pack.Tape')}
            inv={getItems=function() return list(items) end}
            player={getInventory=function() return inv end}
            pass(); assert(repairs==1)
        ''')

    def test_fallback_index_and_manager_replacement(self):
        self.vm.execute('''
            rm.getMediaData=nil; catalog.Movie=media('Movie')
            for i=1,64 do items[i]=item('Pack.Tape') end
            pass(); assert(repairs==64); assert(categoryReads==1)
            local nextMedia=media('Movie')
            rm={getMediaData=function() return nextMedia end}
            items={item('Pack.Tape')}; pass(); assert(items[1].media==nextMedia)
        ''')


class MultiplayerTests(unittest.TestCase):
    def setUp(self):
        self.vm = runtime()
        self.vm.execute('''
            function isServer() return true end
            package.preload['TimedActions/ISDeviceMediaAction']=function() return {} end
            R=require 'KBMGB/Movie/MoviePackRegistry'
            R.register{packId='pack',modId='Pack',entries={{itemType='Pack.Tape',video='a.mp4',recMediaId='Movie'}}}
            function player(name,admin)
                return {x=0,y=0,z=0,getUsername=function() return name end,
                    getAccessLevel=function() return admin and 'Admin' or 'None' end,
                    getX=function(s) return s.x end,getY=function(s) return s.y end,getZ=function(s) return s.z end}
            end
            alice,bob,admin=player('alice'),player('bob'),player('admin',true)
            function getOnlinePlayers() return list{alice,bob,admin} end
            objects={}
            sq={getX=function() return 0 end,getY=function() return 0 end,getZ=function() return 0 end,
                getObjects=function() return list(objects) end}
            function getCell() return {getGridSquare=function(_,x,y,z) if x==0 and y==0 and z==0 then return sq end end} end
            function tv()
                local md={}
                local dd={on=true,volume=1,media=false}
                local device={getSquare=function() return sq end,getDeviceData=function() return dd end,
                    getModData=function() return md end}
                objects[#objects+1]=device
                device.getObjectIndex=function() for i,o in ipairs(objects) do if o==device then return i-1 end end; return -1 end
                dd.getParent=function() return device end
                dd.getIsTelevision=function() return true end
                dd.hasMedia=function(s) return s.media end
                dd.getMediaData=function(s) return s.media and {getId=function() return 'Movie' end} end
                dd.getDeviceVolume=function(s) return s.volume end
                dd.setDeviceVolume=function(s,v) s.volume=v end
                dd.getIsTurnedOn=function(s) return s.on end
                dd.setIsTurnedOn=function(s,v) s.on=v end
                dd.canBePoweredHere=function() return true end
                return device
            end
            messages={}
            function sendServerCommand(p,m,c,a) messages[#messages+1]={player=p,command=c,args=a} end
            ISDeviceMediaAction={invoke=function(s) s.deviceData.media=not s.isRemove end}
            require 'KBMMP_Server'
            function insert(p,device,remove)
                ISDeviceMediaAction.invoke{character=p,deviceData=device:getDeviceData(),isRemove=remove,
                    secondaryItem=not remove and {getFullType=function() return 'Pack.Tape' end},
                    isValid=function() return true end}
            end
            function command(p,cmd,a)
                now=now+2000
                callbacks.OnClientCommand[1]('KBM_MP',cmd,p,a or {})
            end
            function state(p,device)
                command(p,'Sync')
                for i=#messages,1,-1 do
                    if messages[i].player==p and messages[i].command=='Snapshot' then
                        for _,s in ipairs(messages[i].args.states) do
                            if s.address.index==device:getObjectIndex() then return s end
                        end
                        return nil
                    end
                end
            end
            function control(p,device,cmd,extra)
                local s=state(p,device)
                local a={address=s.address,token=s.token,revision=s.revision}
                for k,v in pairs(extra or {}) do a[k]=v end
                command(p,cmd,a)
            end
            a,b=tv(),tv(); insert(alice,a,false); insert(bob,b,false)
        ''')

    def test_ownership_and_independent_devices(self):
        self.vm.execute('''
            control(bob,a,'Play'); assert(not state(alice,a).playing)
            control(alice,a,'Play'); assert(state(bob,a).playing); assert(not state(bob,b).playing)
            control(admin,a,'Stop'); assert(not state(alice,a).playing)
        ''')

    def test_pause_seek_and_late_join_snapshot(self):
        self.vm.execute('''
            control(alice,a,'Play'); now=now+10000
            assert(state(bob,a).position>=10)
            control(alice,a,'Pause'); local paused=state(bob,a).position
            now=now+10000; assert(state(bob,a).position==paused)
            control(alice,a,'Seek',{delta=5}); assert(state(bob,a).position==paused+5)
            control(alice,a,'Pause'); assert(not state(bob,a).paused)
        ''')

    def test_eject_stale_revision_and_power_loss(self):
        self.vm.execute('''
            local old=state(alice,a); control(alice,a,'Play')
            command(alice,'Stop',{address=old.address,token=old.token,revision=old.revision})
            assert(state(bob,a).playing)
            insert(bob,a,true); assert(a:getDeviceData():hasMedia())
            a:getDeviceData().on=false; now=now+2000; fire('OnTick')
            assert(not state(bob,a).playing)
            insert(alice,a,true); assert(state(bob,a)==nil)
        ''')


class PlaybackTickTests(unittest.TestCase):
    def test_projector_shares_one_decoder_tick_and_keeps_its_audio_clock(self):
        vm = runtime()
        vm.execute('''
            function isClient() return false end
            ISDeviceMediaAction={invoke=function() end}
            ISRadioAction={performTogglePlayMedia=function() end,performToggleOnOff=function() end}
            package.preload['TimedActions/ISDeviceMediaAction']=function() return ISDeviceMediaAction end
            package.preload['RadioCom/ISRadioAction']=function() return ISRadioAction end
            for _,name in ipairs({'KBMGB/Movie/DeviceWindow','KBM_ViewpointTVRemote','KBMGB/Movie/WatchReward'}) do
                package.preload[name]=function() return {} end
            end
            package.preload['KBMGB/Movie/PremiumScreen']=function() return {update=function() end} end
            package.preload['KBMGB/Movie/ViewMode']=function() return {isViewpointActive=function() return true end} end
            ticks,clockWrites,uploads=0,0,0
            KBMMovieScreenBridge={
                tick=function() ticks=ticks+1 end,setAudioClockMs=function() clockWrites=clockWrites+1 end,
                getStatus=function() return '' end,stop=function() end,
                playFromMod=function() return true end,setTvDisplay=function() end,
                getCurrentFrame=function() return 1 end,getFps=function() return 12 end,
                isFinished=function() return false end,pause=function() end,resume=function() end}
            KBMProjectorFrameTap={start=function() end,stop=function() end,setScreenModel=function() end,
                update=function() uploads=uploads+1 end,getStatus=function() return '' end}
            require 'KBM_ViewpointProbe'
            require 'KBMProjector/ProjectorPlayback'
            local md={}
            device={getModData=function() return md end,
                getSquare=function() return {getX=function() return 0 end,getY=function() return 0 end,getZ=function() return 0 end} end,
                getDeviceData=function() return {getIsTurnedOn=function() return true end} end}
            fire('OnRenderTick'); assert(ticks==1)
            KBMProjectorPlayback.startRemote(device,{modId='Pack',video='a.mp4'})
            local previousClockWrites=clockWrites
            fire('OnRenderTick'); assert(ticks==2, 'decoder ticked twice'); assert(uploads==1)
            assert(clockWrites==previousClockWrites, 'TV cleared projector audio clock')
            KBMProjectorPlayback.pauseRemote(true); fire('OnRenderTick'); assert(ticks==3)
            KBMProjectorPlayback.stopRemote(); fire('OnRenderTick')
            assert(ticks==4); assert(uploads==2, 'stopped projector still uploads')
        ''')


class SyntaxTests(unittest.TestCase):
    def test_all_runtime_lua(self):
        vm = runtime()
        paths = list(LUA.rglob('*.lua')) + list((ROOT/'42/media/lua').rglob('*.lua'))
        for path in paths:
            with self.subTest(file=path.relative_to(ROOT)):
                vm.execute('assert(loadstring(...))', path.read_text(encoding='utf-8-sig'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
