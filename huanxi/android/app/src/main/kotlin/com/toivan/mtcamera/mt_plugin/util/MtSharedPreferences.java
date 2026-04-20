package com.toivan.mtcamera.mt_plugin.util;

import android.content.Context;
import android.content.SharedPreferences;

import com.toivan.mtcamera.mt_plugin.model.MtSharedPrefKey;
import com.nimo.facebeauty.FBEffect;

public class MtSharedPreferences {
    public static final int WHITENESS_DEFAULT = 70;
    public static final int BLURRINESS_DEFAULT = 80;
    public static final int ROSINESS_DEFAULT = 10;
    public static final int CLEARNESS_DEFAULT = 5;
    public static final int BRIGHTNESS_DEFAULT = 0;
    public static final int UNDEREYE_CIRCLES_DEFAULT = 0;
    public static final int NASOLABIAL_FOLD_DEFAULT = 0;
    public static final int EYE_ENLARGE_DEFAULT = 60;
    public static final int CHEEK_THIN_DEFAULT = 30;
    public static final int CHEEK_NARROW_DEFAULT = 0;
    public static final int CHEEK_BONE_THIN_DEFAULT = 0;
    public static final int JAW_BONE_THIN_DEFAULT = 0;
    public static final int TEMPLE_ENLARGE_DEFAULT = 0;
    public static final int HEAD_LESSEN_DEFAULT = 0;
    public static final int FACE_LESSEN_DEFAULT = 0;
    public static final int CHIN_TRIM_DEFAULT = 0;
    public static final int PHILTRUM_TRIM_DEFAULT = 0;
    public static final int FOREHEAD_TRIM_DEFAULT = 0;
    public static final int EYE_SPACE_DEFAULT = 0;
    public static final int EYE_CORNER_TRIM_DEFAULT = 0;
    public static final int EYE_CORNER_ENLARGE_DEFAULT = 0;
    public static final int NOSE_ENLARGE_DEFAULT = 0;
    public static final int NOSE_THIN_DEFAULT = 0;
    public static final int NOSE_APEX_DEFAULT = 0;
    public static final int NOSE_ROOT_DEFAULT = 0;
    public static final int MOUTH_TRIM_DEFAULT = 0;
    public static final int MOUTH_SMILE_DEFAULT = 0;

    private static MtSharedPreferences instance;
    private SharedPreferences mSharedPreferences;
    private FBEffect fbEffect;

    private MtSharedPreferences() {}

    public static MtSharedPreferences getInstance() {
        if (instance == null) {
            synchronized (MtSharedPreferences.class) {
                if (instance == null) {
                    instance = new MtSharedPreferences();
                }
            }
        }
        return instance;
    }

    public void init(Context context, FBEffect fbEffect) {
        this.fbEffect = fbEffect;
        mSharedPreferences = context.getSharedPreferences("MtSharedPreferences", Context.MODE_PRIVATE);
    }

    private void setBooleanValue(String key, boolean value) {
        SharedPreferences.Editor editor = mSharedPreferences.edit();
        editor.putBoolean(key, value);
        editor.apply();
    }

    private void setIntValue(String key, int value) {
        SharedPreferences.Editor editor = mSharedPreferences.edit();
        editor.putInt(key, value);
        editor.apply();
    }

    public boolean isFaceBeautyEnable() {
        return mSharedPreferences.getBoolean(MtSharedPrefKey.BEAUTY_ENABLE, true);
    }

    public void setFaceBeautyEnable(boolean value) {
        setBooleanValue(MtSharedPrefKey.BEAUTY_ENABLE, value);
    }

    public int getWhitenessValue() {
        return mSharedPreferences.getInt(MtSharedPrefKey.BEAUTY_WHITENESS, WHITENESS_DEFAULT);
    }

    public int getBlurrinessValue() {
        return mSharedPreferences.getInt(MtSharedPrefKey.BEAUTY_BLURRINESS, BLURRINESS_DEFAULT);
    }

    public int getRosinessValue() {
        return mSharedPreferences.getInt(MtSharedPrefKey.BEAUTY_ROSINESS, ROSINESS_DEFAULT);
    }

    public int getClearnessValue() {
        return mSharedPreferences.getInt(MtSharedPrefKey.BEAUTY_CLEARNESS, CLEARNESS_DEFAULT);
    }

    public int getBrightnessValue() {
        return mSharedPreferences.getInt(MtSharedPrefKey.BEAUTY_BRIGHTNESS, BRIGHTNESS_DEFAULT);
    }

    public boolean isFaceShapeEnable() {
        return mSharedPreferences.getBoolean(MtSharedPrefKey.SHAPE_ENABLE, true);
    }

    public int getEyeEnlargingValue() {
        return mSharedPreferences.getInt(MtSharedPrefKey.SHAPE_EYE_ENLARGING, EYE_ENLARGE_DEFAULT);
    }

    public int getCheekThinningValue() {
        return mSharedPreferences.getInt(MtSharedPrefKey.SHAPE_CHEEK_THINNING, CHEEK_THIN_DEFAULT);
    }

    public int getCheekNarrowingValue() {
        return mSharedPreferences.getInt(MtSharedPrefKey.SHAPE_CHEEK_NARROWING, CHEEK_NARROW_DEFAULT);
    }

    public int getCheekboneThinningValue() {
        return mSharedPreferences.getInt(MtSharedPrefKey.SHAPE_CHEEK_BONE_THINNING, CHEEK_BONE_THIN_DEFAULT);
    }

    public int getJawboneThinningValue() {
        return mSharedPreferences.getInt(MtSharedPrefKey.SHAPE_JAW_BONE_THINNING, JAW_BONE_THIN_DEFAULT);
    }

    public int getTempleEnlargingValue() {
        return mSharedPreferences.getInt(MtSharedPrefKey.SHAPE_TEMPLE_ENLARGING, TEMPLE_ENLARGE_DEFAULT);
    }

    public int getHeadLesseningValue() {
        return mSharedPreferences.getInt(MtSharedPrefKey.SHAPE_HEAD_LESSENING, HEAD_LESSEN_DEFAULT);
    }

    public int getFaceLesseningValue() {
        return mSharedPreferences.getInt(MtSharedPrefKey.SHAPE_FACE_LESSENING, FACE_LESSEN_DEFAULT);
    }

    public int getChinTrimmingValue() {
        return mSharedPreferences.getInt(MtSharedPrefKey.SHAPE_CHIN_TRIMMING, CHIN_TRIM_DEFAULT);
    }

    public int getPhiltrumTrimmingValue() {
        return mSharedPreferences.getInt(MtSharedPrefKey.SHAPE_PHILTRUM_TRIMMING, PHILTRUM_TRIM_DEFAULT);
    }

    public int getForeheadTrimmingValue() {
        return mSharedPreferences.getInt(MtSharedPrefKey.SHAPE_FOREHEAD_TRIMMING, FOREHEAD_TRIM_DEFAULT);
    }

    public int getEyeSpacingTrimmingValue() {
        return mSharedPreferences.getInt(MtSharedPrefKey.SHAPE_EYE_SPACING, EYE_SPACE_DEFAULT);
    }

    public int getEyeCornerTrimmingValue() {
        return mSharedPreferences.getInt(MtSharedPrefKey.SHAPE_EYE_CORNER_TRIMMING, EYE_CORNER_TRIM_DEFAULT);
    }

    public int getEyeCornerEnlargingValue() {
        return mSharedPreferences.getInt(MtSharedPrefKey.SHAPE_EYE_CORNER_ENLARGING, EYE_CORNER_ENLARGE_DEFAULT);
    }

    public int getNoseEnlargingValue() {
        return mSharedPreferences.getInt(MtSharedPrefKey.SHAPE_NOSE_ENLARGING, NOSE_ENLARGE_DEFAULT);
    }

    public int getNoseThinningValue() {
        return mSharedPreferences.getInt(MtSharedPrefKey.SHAPE_NOSE_THINNING, NOSE_THIN_DEFAULT);
    }

    public int getNoseApexLesseningValue() {
        return mSharedPreferences.getInt(MtSharedPrefKey.SHAPE_NOSE_APEX_LESSENING, NOSE_APEX_DEFAULT);
    }

    public int getNoseRootEnlargingValue() {
        return mSharedPreferences.getInt(MtSharedPrefKey.SHAPE_NOSE_ROOT_ENLARGING, NOSE_ROOT_DEFAULT);
    }

    public int getMouthTrimmingValue() {
        return mSharedPreferences.getInt(MtSharedPrefKey.SHAPE_MOUTH_TRIMMING, MOUTH_TRIM_DEFAULT);
    }

    public int getMouthSmilingEnlargingValue() {
        return mSharedPreferences.getInt(MtSharedPrefKey.SHAPE_MOUTH_SMILING, MOUTH_SMILE_DEFAULT);
    }

    public void initAllSPValues() {
        fbEffect.setRenderEnable(isFaceBeautyEnable());
        fbEffect.setBeauty(0, getWhitenessValue());
        fbEffect.setBeauty(1, getBlurrinessValue());
        fbEffect.setBeauty(2, getRosinessValue());
        fbEffect.setBeauty(3, getClearnessValue());
        fbEffect.setReshape(10, getEyeEnlargingValue());
        fbEffect.setReshape(20, getCheekThinningValue());
        fbEffect.setFilter(0, "ziran3");
    }
}
