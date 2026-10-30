import java.lang.reflect.*;
import java.nio.ByteBuffer;
import java.util.Arrays;
import zombie.core.textures.Texture;

/** Run with compile-only PZ stubs first on the test classpath; no OpenGL context. */
public final class TVUploadChecks {
    private static final Class<?> BRIDGE=com.knoxboxprobe.KBMMovieScreenBridge.class;
    private static void check(boolean ok,String why){if(!ok)throw new AssertionError(why);}
    private static void set(String name,Object value)throws Exception {
        Field f=BRIDGE.getDeclaredField(name);f.setAccessible(true);f.set(null,value);
    }
    private static final class FakeTexture extends Texture {
        final int id,width,height;
        ByteBuffer lastBuffer;
        byte[] uploaded;
        FakeTexture(int id,int width,int height){this.id=id;this.width=width;this.height=height;}
        @Override public int getID(){return id;}
        @Override public int getWidthHW(){return width;}
        @Override public int getHeightHW(){return height;}
        @Override public void setData(ByteBuffer bytes){
            check(bytes.remaining()==width*height*4,"Upload length changed");
            lastBuffer=bytes;uploaded=new byte[bytes.remaining()];bytes.duplicate().get(uploaded);
            // Current TextureID.setData can mutate the buffer cursor after the GL call.
            bytes.flip();
        }
    }
    private static void seed(FakeTexture texture,boolean legacy)throws Exception {
        byte[] cabinet=new byte[((texture.height+3)/4)*texture.width*4];Arrays.fill(cabinet,(byte)0x7a);
        String prefix=legacy?"legacyCabinet":"cabinet";
        set(prefix+"Pixels",cabinet);set(prefix+"TextureId",texture.id);
        set(prefix+"Width",texture.width);set(prefix+"Height",texture.height);
    }
    private static void validate(FakeTexture texture,int alpha){
        int cabinet=((texture.height+3)/4)*texture.width*4;
        for(int i=0;i<cabinet;i++)check(texture.uploaded[i]==(byte)0x7a,"Cabinet changed");
        for(int i=cabinet;i<texture.uploaded.length;i+=4){
            check((texture.uploaded[i]&255)==0x12&&(texture.uploaded[i+1]&255)==0x34
                &&(texture.uploaded[i+2]&255)==0x56,"Video colour changed");
            check((texture.uploaded[i+3]&255)==alpha,"Emissive alpha marker changed");
        }
    }
    public static void main(String[] args)throws Exception {
        Method upload=BRIDGE.getDeclaredMethod("uploadTexture",Texture.class,int[].class,int.class,boolean.class);
        upload.setAccessible(true);
        int[] frame=new int[512*384];Arrays.fill(frame,0xff123456);
        FakeTexture tv=new FakeTexture(10,512,512);seed(tv,false);
        upload.invoke(null,tv,frame,2,false);validate(tv,253);ByteBuffer first=tv.lastBuffer;
        upload.invoke(null,tv,frame,3,false);validate(tv,253);
        check(tv.lastBuffer==first,"TV direct buffer reallocated per frame");
        FakeTexture legacy=new FakeTexture(11,512,512);seed(legacy,true);
        upload.invoke(null,legacy,frame,4,true);validate(legacy,253);
        check(legacy.lastBuffer!=first,"Legacy/modern upload storage aliases");
        FakeTexture resized=new FakeTexture(12,256,256);seed(resized,false);
        upload.invoke(null,resized,frame,5,false);validate(resized,253);
        check(resized.lastBuffer.capacity()==256*256*4,"Resize did not reallocate buffer");
        upload.invoke(null,resized,frame,0,false);validate(resized,255);
        System.out.println("PASS reusable/independent/resized upload buffers, unchanged cabinet/RGB/alpha, idle alpha");
        Class<?> mode=com.knoxboxprobe.KBMViewModeBridge.class;
        if(args.length>0&&args[0].equals("present")){
            Field enabled=Class.forName("viewpoint.core.View").getField("enabled");
            enabled.setBoolean(null,true);check(com.knoxboxprobe.KBMViewModeBridge.isViewpointActive(),"Viewpoint true lost");
            enabled.setBoolean(null,false);check(!com.knoxboxprobe.KBMViewModeBridge.isViewpointActive(),"Viewpoint false cached as true");
            System.out.println("PASS cached Viewpoint field reads live mode changes");
        }else{
            check(!com.knoxboxprobe.KBMViewModeBridge.isViewpointActive(),"Missing Viewpoint reported active");
            Field retry=mode.getDeclaredField("retryAfterNanos");retry.setAccessible(true);long deadline=retry.getLong(null);
            for(int i=0;i<1000;i++)check(!com.knoxboxprobe.KBMViewModeBridge.isViewpointActive(),"Missing Viewpoint active");
            check(deadline!=0&&deadline==retry.getLong(null),"Repeated failed reflection during cooldown");
            System.out.println("PASS missing Viewpoint lookup cooldown");
        }
    }
}
