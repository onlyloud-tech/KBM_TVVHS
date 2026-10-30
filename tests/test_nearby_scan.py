import unittest
from test_optimizations import runtime


class NearbyScanTests(unittest.TestCase):
    def setUp(self):
        self.vm = runtime()
        self.vm.execute('''
            Scan=require 'KBMGB/Movie/NearbyDeviceScan'
            scan=Scan.new(10,16); reads=0; visits=0; x=0; y=0; z=0
            device={getDeviceData=function() end,getChatElement=function() end}
            targetX,targetY,targetZ=0,0,0
            cell={getGridSquare=function(_,sx,sy,sz)
                reads=reads+1
                if sx==targetX and sy==targetY and sz==targetZ then
                    return {getObjects=function() return list{device} end}
                end
            end}
            player={getX=function() return x end,getY=function() return y end,
                getZ=function() return z end,getCell=function() return cell end}
            function visit(o) assert(o==device); visits=visits+1 end
            function step(interval)
                local before=reads
                local result,invalid=scan:update(player,now,interval or 5000,visit)
                assert(reads-before<=16,'unbounded square scan')
                return result,invalid
            end
            function finish(interval)
                for i=1,28 do local result=step(interval); if result then return result end end
                error('scan did not finish')
            end
        ''')

    def test_idle_work_and_late_chunk_discovery(self):
        self.vm.execute('''
            targetX=100
            assert(next(finish())==nil); assert(reads==441)
            targetX=0 -- Chunk or device arrives without moving the player.
            for i=1,299 do now=i*1000/60; assert(step()==nil) end
            assert(reads==441)
            now=5001; assert(finish()[device]); assert(visits==1)
        ''')

    def test_active_playback_shortens_idle_wait_and_publishes_complete_sets(self):
        self.vm.execute('''
            assert(finish()[device]); local before=reads
            now=100; assert(step(1000)==nil); assert(reads==before+16)
            assert(finish(1000)[device])
            before=reads; now=1099; step(1000); assert(reads==before)
            now=1101; assert(finish(1000)[device])
        ''')

    def test_walk_does_not_starve_scan_and_floor_teleport_resets_it(self):
        self.vm.execute('''
            for i=1,10 do x=i/2; now=now+16; step() end
            assert(finish()[device]); assert(visits==1)
            x=100; targetX=100
            local _,invalid=step(); assert(invalid)
            assert(finish()[device]); assert(visits==2)
            z=1; targetZ=1
            _,invalid=step(); assert(invalid)
            assert(finish()[device]); assert(visits==3)
            player=nil; _,invalid=step(); assert(invalid)
            assert(scan.found==nil and scan.cell==nil)
        ''')

    def test_real_caption_handler_discovers_late_playback_and_clears_each_tick(self):
        vm = runtime()
        vm.execute('''
            function isClient() return false end
            ISDeviceMediaAction={invoke=function() end}; ISRadioAction={}
            package.preload['TimedActions/ISDeviceMediaAction']=function() return ISDeviceMediaAction end
            package.preload['RadioCom/ISRadioAction']=function() return ISRadioAction end
            for _,name in ipairs({'KBMGB/Movie/JavaMoviePlayerApp','KBMGB/Movie/TVMovieWindow',
                    'KBMGB/Movie/PremiumScreen','KBMGB/Movie/ViewMode'}) do
                package.preload[name]=function() return {} end
            end
            package.preload['KBMGB/System/VTUtils']=function()
                return {isTelevisionObject=function(o) return o==tv end}
            end
            local R=require 'KBMGB/Movie/MoviePackRegistry'
            R.register{packId='pack',modId='Pack',entries={{itemType='Pack.Tape',video='a.mp4',recMediaId='Movie'}}}
            reads,clears,playing=0,0,false
            local dd={isPlayingMedia=function() return playing end}
            tv={getDeviceData=function() return dd end,getChatElement=function() end,
                getModData=function() return {KBMGB_TV_Movie={fullType='Pack.Tape'}} end}
            KBMTVCaptionBridge={clear=function(o) assert(o==tv); clears=clears+1 end}
            cell={getGridSquare=function(_,x,y,z)
                reads=reads+1
                if x==0 and y==0 and z==0 then return {getObjects=function() return list{tv} end} end
            end}
            local player={getCell=function() return cell end,getX=function() return 0 end,
                getY=function() return 0 end,getZ=function() return 0 end}
            function getPlayer() return player end
            require 'KBMGB/ZZMovie/TVMovieRadioPatch'
            for i=1,1200 do
                now=(i-1)*1000/60; local before=reads; fire('OnTick'); assert(reads-before<=16)
            end
            assert(reads==1764,'idle discovery unexpectedly repeated')
            assert(clears==0)
            playing=true -- A movie starts outside this client's action hooks.
            for i=1,330 do now=now+1000/60; fire('OnTick') end
            assert(clears>0,'already-playing TV was not discovered')
            local before=clears; fire('OnTick'); assert(clears>before,'known movie captions were not cleared immediately')
            playing=false; before=clears; fire('OnTick'); assert(clears==before)
        ''')


if __name__ == '__main__':
    unittest.main(verbosity=2)
