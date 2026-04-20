package com.toivan.mtcamera.mt_plugin.model;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class ConstraintsMap {
    private final Map<String, Object> mMap;

    public ConstraintsMap() {
        mMap = new HashMap<>();
    }

    public ConstraintsMap(Map<String, Object> map) {
        this.mMap = map;
    }

    public Map<String, Object> toMap() {
        return mMap;
    }

    public boolean hasKey(String name) {
        return this.mMap.containsKey(name);
    }

    public boolean isNull(String name) {
        return mMap.get(name) == null;
    }

    public boolean getBoolean(String name) {
        return (boolean) mMap.get(name);
    }

    public double getDouble(String name) {
        return (double) mMap.get(name);
    }

    public int getInt(String name) {
        if (getType(name) == ObjectType.String) {
            return Integer.parseInt(((String) mMap.get(name)));
        }
        return (int) mMap.get(name);
    }

    public String getString(String name) {
        return (String) mMap.get(name);
    }

    @SuppressWarnings("unchecked")
    public ConstraintsMap getMap(String name) {
        return new ConstraintsMap((Map<String, Object>) mMap.get(name));
    }

    public ObjectType getType(String name) {
        Object value = mMap.get(name);
        if (value == null) return ObjectType.Null;
        if (value instanceof Number) return ObjectType.Number;
        if (value instanceof String) return ObjectType.String;
        if (value instanceof Boolean) return ObjectType.Boolean;
        if (value instanceof Map) return ObjectType.Map;
        if (value instanceof List) return ObjectType.Array;
        throw new IllegalArgumentException("Invalid value " + value.toString() + " for key " + name);
    }

    public void putBoolean(String key, boolean value) { mMap.put(key, value); }
    public void putDouble(String key, double value) { mMap.put(key, value); }
    public void putInt(String key, int value) { mMap.put(key, value); }
    public void putString(String key, String value) { mMap.put(key, value); }
    public void putNull(String key) { mMap.put(key, null); }
    public void putMap(String key, Map<String, Object> value) { mMap.put(key, value); }
    public void putArray(String key, ArrayList<Object> value) { mMap.put(key, value); }
    public void merge(Map<String, Object> value) { mMap.putAll(value); }
}
