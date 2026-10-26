package com.knoxboxprobe;

import java.io.File;
import java.util.List;
import java.util.HashMap;
import java.util.Map;
import java.util.Locale;
import me.zed_0xff.zombie_buddy.Exposer;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.inventory.InventoryItem;
import zombie.inventory.InventoryItemFactory;
import zombie.iso.IsoObject;
import zombie.iso.objects.IsoWorldInventoryObject;

/** Render-only video surfaces for supported 6277 television models. */
@Exposer.LuaClass(name="KBMPremiumTVBridge")
public final class KBMPremiumTVBridge {
    private static final String MODEL_ID="dd019a4e-dfaf-42ed-a358-1a96ef5b2d4b";
    private static final String VALUTECH_MODEL_ID="aa67963a-497c-4b12-95c7-96ffc6eea700";
    // Individually fitted facings, recorded after parent-height attachment.
    // Z is relative to the TV, excluding its furniture's render offset.
    private static final Map<String,float[]> defaults=Map.of(
        "appliances_television_01_0",new float[]{.584961f,.400391f,-.003750f,0,0,90,.666667f},
        "appliances_television_01_1",new float[]{.510000f,.500000f,-.003750f,0,0,0,.666667f},
        "appliances_television_01_2",new float[]{.291016f,.474609f,-.008958f,0,0,270,.666667f},
        "appliances_television_01_3",new float[]{.370000f,.410000f,-.006104f,0,0,180,.666667f},
        "appliances_television_01_4",new float[]{.418945f,.415039f,-.010417f,0,0,0,.666667f},
        "appliances_television_01_5",new float[]{.830000f,.490000f,-.003750f,0,0,90,.666667f},
        "appliances_television_01_6",new float[]{.442555f,.509261f,-.003750f,0,0,180,.666667f},
        "appliances_television_01_7",new float[]{.060000f,.440000f,-.003750f,0,0,270,.666667f});
    private static IsoObject television;
    private static PremiumSurface surface;
    private static String status="idle";
    private static boolean captured;
    private static final Map<String,float[]> calibration=new HashMap<>();

    private KBMPremiumTVBridge() {}

    private static Object binding(IsoObject tv) throws ReflectiveOperationException {
        if (tv==null || tv.getSquare()==null || tv.getSprite()==null) return null;
        String sprite=tv.getSprite().getName();
        if (sprite==null || !sprite.matches("appliances_television_01_[0-7]")) return null;
        Object bind=Class.forName("viewpoint.packs.ModelPacks").getMethod("bind",String.class).invoke(null,sprite);
        if (bind==null) return null;
        Object model=bind.getClass().getField("model").get(bind);
        File obj=(File)model.getClass().getField("obj").get(model);
        // Decline other packs/disabled bindings rather than guessing their geometry.
        String expected=sprite.matches(".*_[4-7]") ? VALUTECH_MODEL_ID : MODEL_ID;
        return obj.getPath().replace('\\','/').contains("/"+expected+"/") ? bind : null;
    }

    public static boolean supports(IsoObject tv) {
        try { return binding(tv)!=null; }
        catch (ReflectiveOperationException | LinkageError unavailable) { return false; }
    }

    public static boolean start(IsoObject tv) {
        stop();
        try {
            Object bind=binding(tv);
            if (bind==null) return false;
            InventoryItem item=InventoryItemFactory.CreateItem(getScreenModel(tv));
            if (item==null) { status="TV video-surface item script unavailable"; return false; }
            Class<?> type=bind.getClass();
            float x=type.getField("x").getFloat(bind), y=type.getField("y").getFloat(bind);
            float z=type.getField("z").getFloat(bind), scale=type.getField("scale").getFloat(bind);
            float cos=type.getField("cos").getFloat(bind), sin=type.getField("sin").getFloat(bind);
            surface=new PremiumSurface(item,tv,.5f+x,.5f+y,z);
            item.setWorldItem(surface);
            // Viewpoint scales native rigid items by 1.5; pack models use tile units.
            item.setWorldScale(scale/1.5f);
            item.setWorldZRotation((float)((360-Math.toDegrees(Math.atan2(sin,cos)))%360));
            float[] saved=calibration.get(tv.getSprite().getName());
            if (saved==null) saved=defaults.get(tv.getSprite().getName());
            if (saved!=null) {
                surface.setOffX(saved[0]); surface.setOffY(saved[1]); surface.setOffZ(saved[2]);
                item.setWorldXRotation(saved[3]); item.setWorldYRotation(saved[4]);
                item.setWorldZRotation(saved[5]); item.setWorldScale(saved[6]);
            }
            surface.setExtendedPlacement(true);
            surface.setNoPicking(true);
            surface.followOwnerHeight();
            television=tv;
            captured=false;
            status="Premium surface ready: "+tv.getSprite().getName();
            System.out.println("[KBMPremiumTV] "+status);
            return true;
        } catch (ReflectiveOperationException | RuntimeException | LinkageError failure) {
            stop(); status="surface setup failed: "+failure; return false;
        }
    }

    public static void stop() { television=null; surface=null; captured=false; }
    public static String getStatus() { return status; }

    public static String getScreenModel(IsoObject tv) {
        String sprite=tv!=null && tv.getSprite()!=null ? tv.getSprite().getName() : "";
        return sprite!=null && sprite.matches("appliances_television_01_[4-7]")
            ? "KBM.ValuTechScreen" : "KBM.PremiumScreen";
    }

    public static IsoWorldInventoryObject getSurface(IsoObject tv) {
        if (television!=tv || surface==null || !surface.isExistInTheWorld()) return null;
        surface.followOwnerHeight();
        return surface;
    }

    public static float getSurfaceScale(IsoObject tv) {
        return getSurface(tv)==null ? 0 : surface.getItem().worldScale;
    }

    public static String captureCalibration(IsoObject tv) {
        if (getSurface(tv)==null) return null;
        InventoryItem item=surface.getItem();
        float[] values={surface.getOffX(),surface.getOffY(),surface.getOffZ()-surface.ownerLift,
            item.getWorldXRotation(),item.getWorldYRotation(),item.getWorldZRotation(),item.worldScale};
        for (float value:values) if (!Float.isFinite(value)) return null;
        calibration.put(tv.getSprite().getName(),values);
        String result=String.format(Locale.ROOT,
            "sprite=%s offset=(%.6f,%.6f,%.6f) rotation=(%.6f,%.6f,%.6f) scale=%.6f offsetSpace=parent-relative parentLift=%.6f",
            tv.getSprite().getName(),values[0],values[1],values[2],values[3],values[4],values[5],values[6],surface.ownerLift);
        System.out.println("[KBMPremiumTV][Placement] "+result);
        return result;
    }

    /** Gives the native placement gizmo a live render target without world insertion. */
    public static class PremiumSurface extends IsoWorldInventoryObject {
        private final IsoObject owner;
        private float ownerLift;
        public PremiumSurface(InventoryItem item,IsoObject tv,float x,float y,float z) {
            super(item,tv.getSquare(),x,y,z); owner=tv;
        }
        private void followOwnerHeight() {
            // Viewpoint WorldMesher.rise(owner) is renderYOffset / 96 * sqrt(6).
            // Native rigid world items already multiply their tile Z by sqrt(6),
            // so inherit the same furniture lift in tile units, exactly once.
            float next=owner.getRenderYOffset()/96.0f;
            if (!Float.isFinite(next)) return;
            if (next!=ownerLift) {
                setOffZ(getOffZ()+next-ownerLift);
                ownerLift=next;
            }
        }
        @Override public boolean isExistInTheWorld() {
            return surface==this && television==owner && owner.getObjectIndex()>=0
                && owner.getSquare()==getSquare();
        }
    }

    @SuppressWarnings("unchecked")
    public static void addToFrame(Object frame) {
        if (surface==null || television==null || !KBMViewModeBridge.isViewpointActive()) return;
        if (television.getObjectIndex()<0 || television.getSquare()!=surface.getSquare()) { stop(); return; }
        surface.followOwnerHeight();
        try {
            List<Object> items=(List<Object>)frame.getClass().getField("modelItems").get(frame);
            if (!items.contains(surface)) items.add(surface);
            if (!captured) {
                captured=true;
                System.out.println("[KBMPremiumTV] render-only surface added to Viewpoint frame");
            }
        } catch (ReflectiveOperationException | RuntimeException failure) {
            status="frame integration failed: "+failure;
            stop();
        }
    }

    @SuppressWarnings("unchecked")
    public static void removeFromFrame(Object frame) {
        try {
            List<Object> items=(List<Object>)frame.getClass().getField("modelItems").get(frame);
            // No placement, inventory, square, save, or networking lists are touched.
            items.removeIf(item -> item instanceof PremiumSurface);
        } catch (ReflectiveOperationException | RuntimeException failure) {
            status="frame cleanup failed: "+failure;
        }
    }

    @Patch(className="viewpoint.models.Models",methodName="snapshot")
    public static class Capture {
        @Patch.OnEnter
        public static void enter(@Patch.AllArguments Object[] args) { KBMPremiumTVBridge.addToFrame(args[0]); }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.AllArguments Object[] args) { KBMPremiumTVBridge.removeFromFrame(args[0]); }
    }
}
