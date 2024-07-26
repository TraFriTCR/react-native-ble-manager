package it.innove;

import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothManager;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.IntentSender;
import android.content.pm.PackageManager;
import android.location.LocationManager;
import android.os.Build;

import androidx.annotation.Nullable;

import android.provider.Settings;
import android.util.Log;

import com.facebook.react.bridge.ActivityEventListener;
import com.facebook.react.bridge.BaseActivityEventListener;
import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.Callback;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.ReadableArray;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.WritableArray;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.modules.core.RCTNativeAppEventEmitter;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;

import static android.app.Activity.RESULT_OK;
import static android.bluetooth.BluetoothProfile.GATT;
import static android.os.Build.VERSION_CODES.LOLLIPOP;

import static it.innove.ErrorHelper.createInvalidStateErrorWritableMap;
import static it.innove.ErrorHelper.createtInvalidArgumentErrorWritableMap;
import static it.innove.ErrorHelper.createUnexpectedErrorWritableMap;
import static it.innove.ErrorHelper.InvalidStateCode;

import com.google.android.gms.common.api.ResolvableApiException;
import com.google.android.gms.location.LocationRequest;
import com.google.android.gms.location.LocationServices;
import com.google.android.gms.location.LocationSettingsRequest;
import com.google.android.gms.location.LocationSettingsResponse;
import com.google.android.gms.tasks.Task;

class BleManager extends ReactContextBaseJavaModule {

    public static final String LOG_TAG = "ReactNativeBleManager";
    private static final int ENABLE_BLUETOOTH_REQUEST = 539;
    private static final int ENABLE_LOCATION_REQUEST = 999;

    private BluetoothAdapter bluetoothAdapter;
    private LocationManager locationManager;
    private BluetoothManager bluetoothManager;
    private Context context;
    private ReactApplicationContext reactContext;
    private Callback enableBluetoothCallback;
    private Callback enableLocationCallback;
    private ScanManager scanManager;
    private boolean forceLegacy;

    public ReactApplicationContext getReactContext() {
        return reactContext;
    }

    private final ActivityEventListener mActivityEventListener = new BaseActivityEventListener() {

        @Override
        public void onActivityResult(Activity activity, int requestCode, int resultCode, Intent intent) {
            Log.d(LOG_TAG, "onActivityResult");
            if (requestCode == ENABLE_BLUETOOTH_REQUEST) {
                if (enableBluetoothCallback != null) {
                    if (resultCode == RESULT_OK) {
                        enableBluetoothCallback.invoke();
                    } else {
                        enableBluetoothCallback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.BT_DISABLED));
                    }
                    enableBluetoothCallback = null;
                }
            }
            if (requestCode == ENABLE_LOCATION_REQUEST) {
                if (enableLocationCallback != null) {
                    if (resultCode == RESULT_OK) {
                        enableLocationCallback.invoke();
                    } else {
                        enableLocationCallback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.BT_DISABLED));
                    }
                    enableLocationCallback = null;
                }
            }
        }
    };

    // key is the MAC Address
    private final Map<String, Peripheral> peripherals = new LinkedHashMap<>();
    // scan session id

    // wrapper to use completable future as a callback
    private class CompletableFutureCallback implements Callback {
        private CompletableFuture<Object[]> future;
        CompletableFutureCallback(CompletableFuture<Object[]> future) {
            this.future = future;
        }
        @Override
        public void invoke(Object... args) {
            this.future.complete(args);
        }
    }

    public BleManager(ReactApplicationContext reactContext) {
        super(reactContext);
        context = reactContext;
        this.reactContext = reactContext;
        reactContext.addActivityEventListener(mActivityEventListener);
        Log.d(LOG_TAG, "BleManager created");
    }

    @Override
    public String getName() {
        return "BleManager";
    }

    private BluetoothAdapter getBluetoothAdapter() {
        if (bluetoothAdapter == null) {
            BluetoothManager manager = (BluetoothManager) context.getSystemService(Context.BLUETOOTH_SERVICE);
            bluetoothAdapter = manager.getAdapter();
        }
        return bluetoothAdapter;
    }

    private LocationManager getLocationManager() {
        if (locationManager == null) {
            locationManager = (LocationManager) context.getSystemService(Context.LOCATION_SERVICE);
        }
        return locationManager;
    }

    private BluetoothManager getBluetoothManager() {
        if (bluetoothManager == null) {
            bluetoothManager = (BluetoothManager) context.getSystemService(Context.BLUETOOTH_SERVICE);
        }
        return bluetoothManager;
    }

    public void sendEvent(String eventName, @Nullable WritableMap params) {
        getReactApplicationContext().getJSModule(RCTNativeAppEventEmitter.class).emit(eventName, params);
    }

    public static boolean handledInvalidState(BluetoothAdapter bluetoothAdapter, Callback callback) {

        // Is Bluetooth available?
        if (bluetoothAdapter == null) {
            Log.d(LOG_TAG, "No bluetooth support");
            callback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.BT_UNSUPPORTED));
            return true;
        }

        // Is Bluetooth enabled?
        if (!bluetoothAdapter.isEnabled()) {
            Log.d(LOG_TAG, "Bluetooth not enabled");
            callback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.BT_DISABLED));
            return true;
        }

        return false;
    }

    @ReactMethod
    public void start(ReadableMap options, Callback callback) {
        Log.d(LOG_TAG, "start");
        if (getBluetoothAdapter() == null) {
            Log.d(LOG_TAG, "No bluetooth support");
            callback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.BT_UNSUPPORTED));
            return;
        }
        if (getLocationManager() == null) {
            Log.d(LOG_TAG, "No location support");
            callback.invoke("No location service support");
            return;
        }
        forceLegacy = false;
        if (options.hasKey("forceLegacy")) {
            forceLegacy = options.getBoolean("forceLegacy");
        }

        if (Build.VERSION.SDK_INT >= LOLLIPOP && !forceLegacy) {
            scanManager = new LollipopScanManager(reactContext, this);
        } else {
            scanManager = new LegacyScanManager(reactContext, this);
        }

        IntentFilter locationIntentFilter = new IntentFilter(LocationManager.MODE_CHANGED_ACTION);
        locationIntentFilter.setPriority(IntentFilter.SYSTEM_HIGH_PRIORITY);
        context.registerReceiver(mReceiver, locationIntentFilter);

        IntentFilter filter = new IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED);
        filter.addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED);
        context.registerReceiver(mReceiver, filter);

        IntentFilter intentFilter = new IntentFilter(BluetoothDevice.ACTION_PAIRING_REQUEST);
        intentFilter.setPriority(IntentFilter.SYSTEM_HIGH_PRIORITY);
        context.registerReceiver(mReceiver, intentFilter);

        callback.invoke();
        Log.d(LOG_TAG, "BleManager initialized");
    }

    @ReactMethod
    public void isBluetoothEnabled(Callback callback) {
        if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled()) {
          callback.invoke(null, false);
        } else {
          callback.invoke(null, true);
        }
    }

    private boolean isLocationServicesEnabled() {
        if (getLocationManager() == null) {
            return false;
        } else {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                return locationManager.isLocationEnabled();
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                int mode = Settings.Secure.getInt(context.getContentResolver(), Settings.Secure.LOCATION_MODE,
                        Settings.Secure.LOCATION_MODE_OFF);
                return mode != Settings.Secure.LOCATION_MODE_OFF;
            } else {
                boolean gpsEnabled = locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER);
                boolean networkEnabled = locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER);
                return gpsEnabled || networkEnabled;
            }
        }
    }

    @ReactMethod
    public void isLocationEnabled(Callback callback) {
        callback.invoke(null, isLocationServicesEnabled());
    }

    @ReactMethod
    public void enableBluetooth(Callback callback) {
        if (getBluetoothAdapter() == null) {
            Log.d(LOG_TAG, "No bluetooth support");
            callback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.BT_UNSUPPORTED));
            return;
        }
        if (!getBluetoothAdapter().isEnabled()) {
            enableBluetoothCallback = callback;
            Intent intentEnable = new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE);
            if (getCurrentActivity() == null)
                callback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.GUI_RESOURCE_UNAVAILABLE));
            else
                getCurrentActivity().startActivityForResult(intentEnable, ENABLE_BLUETOOTH_REQUEST);
        } else
            callback.invoke();
    }

    @ReactMethod
    public void enableLocation(Callback callback) {
        if (getLocationManager() == null) {
            Log.d(LOG_TAG, "Location services not supported");
            callback.invoke("No location service support");
            return;
        }
        if (!isLocationServicesEnabled()) {

            LocationRequest locationRequest = LocationRequest.create();
            LocationSettingsRequest.Builder builder = new LocationSettingsRequest.Builder()
                    .addLocationRequest(locationRequest);

            Task<LocationSettingsResponse> task = LocationServices.getSettingsClient(reactContext)
                    .checkLocationSettings(builder.build());
            task.addOnSuccessListener(locationSettingsResponse -> {
                callback.invoke();
            });

            task.addOnFailureListener(e -> {
                if (e instanceof ResolvableApiException) {
                    try {
                        enableLocationCallback = callback;
                        // Show the dialog by calling startResolutionForResult(),
                        // and check the result in onActivityResult().
                        ResolvableApiException resolvable = (ResolvableApiException) e;
                        resolvable.startResolutionForResult(getCurrentActivity(), ENABLE_LOCATION_REQUEST);
                    } catch (IntentSender.SendIntentException sendEx) {
                        // Ignore the error.
                    }
                }
            });
        } else
            callback.invoke();
    }

    @ReactMethod
    public void scan(ReadableArray serviceUUIDs, final int scanSeconds, boolean allowDuplicates, ReadableMap options,
                     Callback callback) {
        Log.d(LOG_TAG, "scan");
        if (handledInvalidState(getBluetoothAdapter(), callback)) return;

        synchronized (peripherals) {
            for (Iterator<Map.Entry<String, Peripheral>> iterator = peripherals.entrySet().iterator(); iterator
                    .hasNext(); ) {
                Map.Entry<String, Peripheral> entry = iterator.next();
                if (!(entry.getValue().isConnected() || entry.getValue().isConnecting())) {
                    iterator.remove();
                }
            }
        }

        if (scanManager != null)
            scanManager.scan(serviceUUIDs, scanSeconds, options, callback);
    }

    @ReactMethod
    public void stopScan(Callback callback) {
        Log.d(LOG_TAG, "Stop scan");
        if (handledInvalidState(getBluetoothAdapter(), callback)) return;

        if (scanManager != null) {
            scanManager.stopScan(callback);
            WritableMap map = Arguments.createMap();
						map.putInt("status", 0);
            sendEvent("BleManagerStopScan", map);
        }
    }

    @ReactMethod
    public void createBond(String peripheralUUID, String peripheralPin, Callback callback) {
        callback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.NOT_SUPPORTED));
    }

    @ReactMethod
    private void removeBond(String peripheralUUID, Callback callback) {
        callback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.NOT_SUPPORTED));
    }

    @ReactMethod
    public void connect(String peripheralUUID, Callback callback) {
        Log.d(LOG_TAG, "Connect to: " + peripheralUUID);

        Peripheral peripheral = retrieveOrCreatePeripheral(peripheralUUID);
        if (peripheral == null) {
            callback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.PERIPHERAL_NOT_FOUND));
            return;
        }
        peripheral.connect(callback, getCurrentActivity());
    }

    @ReactMethod
    public void disconnect(String peripheralUUID, boolean force, Callback callback) {
        Log.d(LOG_TAG, "Disconnect from: " + peripheralUUID);

        Peripheral peripheral = peripherals.get(peripheralUUID);
        if (peripheral != null) {
            peripheral.disconnect(callback, force);
        } else
            callback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.PERIPHERAL_NOT_FOUND));
    }

    @ReactMethod
    public void startNotificationUseBuffer(String deviceUUID, String serviceUUID, String characteristicUUID,
                                           Integer buffer, Callback callback) {
        Log.d(LOG_TAG, "startNotification");

        if (serviceUUID == null || characteristicUUID == null) {
            callback.invoke(createtInvalidArgumentErrorWritableMap("ServiceUUID and characteristicUUID required."));
            return;
        }
        Peripheral peripheral = peripherals.get(deviceUUID);
        if (peripheral != null) {
            peripheral.registerNotify(UUIDHelper.uuidFromString(serviceUUID),
                    UUIDHelper.uuidFromString(characteristicUUID), buffer, callback);
        } else
            callback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.PERIPHERAL_NOT_FOUND));
    }

    @ReactMethod
    public void startNotification(String deviceUUID, String serviceUUID, String characteristicUUID, Callback callback) {
        Log.d(LOG_TAG, "startNotification");

        if (serviceUUID == null || characteristicUUID == null) {
            callback.invoke(createtInvalidArgumentErrorWritableMap("ServiceUUID and characteristicUUID required."));
            return;
        }
        Peripheral peripheral = peripherals.get(deviceUUID);
        if (peripheral != null) {
            peripheral.registerNotify(UUIDHelper.uuidFromString(serviceUUID),
                    UUIDHelper.uuidFromString(characteristicUUID), 1, callback);
        } else
            callback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.PERIPHERAL_NOT_FOUND));
    }

    @ReactMethod
    public void stopNotification(String deviceUUID, String serviceUUID, String characteristicUUID, Callback callback) {
        Log.d(LOG_TAG, "stopNotification");

        if (serviceUUID == null || characteristicUUID == null) {
            callback.invoke(createtInvalidArgumentErrorWritableMap("ServiceUUID and characteristicUUID required."));
            return;
        }
        Peripheral peripheral = peripherals.get(deviceUUID);
        if (peripheral != null) {
            peripheral.removeNotify(UUIDHelper.uuidFromString(serviceUUID),
                    UUIDHelper.uuidFromString(characteristicUUID), callback);
        } else
            callback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.PERIPHERAL_NOT_FOUND));
    }

    @ReactMethod
    public void write(String deviceUUID, String serviceUUID, String characteristicUUID, ReadableArray message,
                      Integer maxByteSize, Callback callback) {
        Log.d(LOG_TAG, "Write to: " + deviceUUID);

        if (serviceUUID == null || characteristicUUID == null) {
            callback.invoke(createtInvalidArgumentErrorWritableMap("ServiceUUID and characteristicUUID required."));
            return;
        }
        Peripheral peripheral = peripherals.get(deviceUUID);
        if (peripheral != null) {
            byte[] decoded = new byte[message.size()];
            for (int i = 0; i < message.size(); i++) {
                decoded[i] = new Integer(message.getInt(i)).byteValue();
            }
            Log.d(LOG_TAG, "Message(" + decoded.length + "): " + bytesToHex(decoded));
            peripheral.write(UUIDHelper.uuidFromString(serviceUUID), UUIDHelper.uuidFromString(characteristicUUID),
                    decoded, maxByteSize, null, callback, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT);
        } else
            callback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.PERIPHERAL_NOT_FOUND));
    }

    @ReactMethod
    public void writeWithoutResponse(String deviceUUID, String serviceUUID, String characteristicUUID,
                                     ReadableArray message, Integer maxByteSize, Integer queueSleepTime, Callback callback) {
        Log.d(LOG_TAG, "Write without response to: " + deviceUUID);

        if (serviceUUID == null || characteristicUUID == null) {
            callback.invoke(createtInvalidArgumentErrorWritableMap("ServiceUUID and characteristicUUID required."));
            return;
        }
        Peripheral peripheral = peripherals.get(deviceUUID);
        if (peripheral != null) {
            byte[] decoded = new byte[message.size()];
            for (int i = 0; i < message.size(); i++) {
                decoded[i] = new Integer(message.getInt(i)).byteValue();
            }
            Log.d(LOG_TAG, "Message(" + decoded.length + "): " + bytesToHex(decoded));
            peripheral.write(UUIDHelper.uuidFromString(serviceUUID), UUIDHelper.uuidFromString(characteristicUUID),
                    decoded, maxByteSize, queueSleepTime, callback, BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE);
        } else
            callback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.PERIPHERAL_NOT_FOUND));
    }

    @ReactMethod
    public void read(String deviceUUID, String serviceUUID, String characteristicUUID, Callback callback) {
        Log.d(LOG_TAG, "Read from: " + deviceUUID);

        if (serviceUUID == null || characteristicUUID == null) {
            callback.invoke(createtInvalidArgumentErrorWritableMap("ServiceUUID and characteristicUUID required."));
            return;
        }
        Peripheral peripheral = peripherals.get(deviceUUID);
        if (peripheral != null) {
            peripheral.read(UUIDHelper.uuidFromString(serviceUUID), UUIDHelper.uuidFromString(characteristicUUID),
                    callback);
        } else
            callback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.PERIPHERAL_NOT_FOUND));
    }

    @ReactMethod
    public void retrieveServices(String deviceUUID, ReadableArray services, Callback callback) {
        Log.d(LOG_TAG, "Retrieve services from: " + deviceUUID);

        Peripheral peripheral = peripherals.get(deviceUUID);
        if (peripheral != null) {
            peripheral.retrieveServices(callback);
        } else
            callback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.PERIPHERAL_NOT_FOUND));
    }

    @ReactMethod
    public void refreshCache(String deviceUUID, Callback callback) {
        Log.d(LOG_TAG, "Refershing cache for: " + deviceUUID);

        Peripheral peripheral = peripherals.get(deviceUUID);
        if (peripheral != null) {
            peripheral.refreshCache(callback);
        } else
            callback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.PERIPHERAL_NOT_FOUND));
    }

    @ReactMethod
    public void readRSSI(String deviceUUID, Callback callback) {
        Log.d(LOG_TAG, "Read RSSI from: " + deviceUUID);

        Peripheral peripheral = peripherals.get(deviceUUID);
        if (peripheral != null) {
            peripheral.readRSSI(callback);
        } else
            callback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.PERIPHERAL_NOT_FOUND));
    }

    private CompletableFuture<Peripheral> saveConnectedPeripheral(final BluetoothDevice device) {
        String address = device.getAddress();
        synchronized (peripherals) {
            if (!peripherals.containsKey(address)) {
                Peripheral peripheral;
                if (Build.VERSION.SDK_INT >= LOLLIPOP && !forceLegacy) {
                    peripheral = new LollipopPeripheral(device, reactContext);
                } else {
                    peripheral = new Peripheral(device, reactContext);
                }
                peripherals.put(device.getAddress(), peripheral);
            }
        }
        CompletableFuture<Object[]> future = new CompletableFuture();
        Callback callback = new CompletableFutureCallback(future);
        final Peripheral peripheral = peripherals.get(address);
        peripheral.connect(callback, getCurrentActivity());
        return future.thenComposeAsync((Object... args) -> {
            if (args.length == 0 || args[0] == null) {
                return CompletableFuture.completedFuture(peripheral);
            } else {
                CompletableFuture<Peripheral> failedFuture = new CompletableFuture<>();
                failedFuture.completeExceptionally(new Exception((String)args[0]));
                return failedFuture;
            }
        });
    }

    public Peripheral getPeripheral(BluetoothDevice device) {
        String address = device.getAddress();
        return peripherals.get(address);
    }

    public Peripheral savePeripheral(Peripheral peripheral) {
        synchronized (peripherals) {
            peripherals.put(peripheral.getDevice().getAddress(), peripheral);
        }
        return peripheral;
    }

    @ReactMethod
    public void checkState() {
        Log.d(LOG_TAG, "checkState");

        BluetoothAdapter adapter = getBluetoothAdapter();
        String state = "off";
        if (!context.getPackageManager().hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)) {
            state = "unsupported";
        } else if (adapter != null) {
            switch (adapter.getState()) {
                case BluetoothAdapter.STATE_ON:
                    state = "on";
                    break;
                case BluetoothAdapter.STATE_OFF:
                    state = "off";
            }
        }

        WritableMap map = Arguments.createMap();
        map.putString("state", state);
        Log.d(LOG_TAG, "state:" + state);
        sendEvent("BleManagerDidUpdateState", map);
    }

    private final BroadcastReceiver mReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            Log.d(LOG_TAG, "onReceive");
            final String action = intent.getAction();

            if (action.equals(BluetoothAdapter.ACTION_STATE_CHANGED)) {
                final int state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR);
                String stringState = "";

                switch (state) {
                    case BluetoothAdapter.STATE_OFF:
                        stringState = "off";
                        clearPeripherals();
                        break;
                    case BluetoothAdapter.STATE_TURNING_OFF:
                        stringState = "turning_off";
                        disconnectPeripherals();
                        break;
                    case BluetoothAdapter.STATE_ON:
                        stringState = "on";
                        break;
                    case BluetoothAdapter.STATE_TURNING_ON:
                        stringState = "turning_on";
                        break;
                }

                WritableMap map = Arguments.createMap();
                map.putString("state", stringState);
                Log.d(LOG_TAG, "state: " + stringState);
                sendEvent("BleManagerDidUpdateState", map);
            }

            if (action.equals(LocationManager.MODE_CHANGED_ACTION)) {
                boolean isLocationEnabled = intent.getBooleanExtra(LocationManager.EXTRA_LOCATION_ENABLED, false);

                WritableMap map = Arguments.createMap();
                map.putBoolean("state", isLocationEnabled);
                Log.d(LOG_TAG, "state: " + isLocationEnabled);
                sendEvent("BleManagerDidUpdateLocationState", map);
            }
        }
    };

    private void clearPeripherals() {
        if (!peripherals.isEmpty()) {
            synchronized (peripherals) {
                peripherals.clear();
            }
        }
    }

    private void disconnectPeripherals() {
        if (!peripherals.isEmpty()) {
            synchronized (peripherals) {
                for (Peripheral peripheral : peripherals.values()) {
                    if (peripheral.isConnected()) {
                        peripheral.handleExternalDisconnect();;
                    }
                }
            }
        }
    }

    @ReactMethod
    public void getDiscoveredPeripherals(Callback callback) {
        Log.d(LOG_TAG, "Get discovered peripherals");
        if (handledInvalidState(getBluetoothAdapter(), callback)) return;

        WritableArray map = Arguments.createArray();
        synchronized (peripherals) {
            for (Map.Entry<String, Peripheral> entry : peripherals.entrySet()) {
                Peripheral peripheral = entry.getValue();
                WritableMap jsonBundle = peripheral.asWritableMap();
                map.pushMap(jsonBundle);
            }
        }
        callback.invoke(null, map);
    }

    @ReactMethod
    public void getConnectedPeripherals(ReadableArray serviceUUIDs, Callback callback) {
        Log.d(LOG_TAG, "Get connected peripherals");
        if (handledInvalidState(getBluetoothAdapter(), callback)) return;

        WritableArray map = Arguments.createArray();

        List<BluetoothDevice> periperals = getBluetoothManager().getConnectedDevices(GATT);
        ArrayList<CompletableFuture<Peripheral>> futures = new ArrayList();
        for (BluetoothDevice entry : periperals) {
            futures.add(saveConnectedPeripheral(entry));
        }
        CompletableFuture.allOf(futures.toArray(new CompletableFuture<?>[0])).handle((v, e) -> {
            if (e != null) {
                callback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.PERIPHERAL_NOT_CONNECTED));
                return v;
            }
            try {
                for (CompletableFuture<Peripheral> future : futures) {
                    Peripheral peripheral = future.get();
                    WritableMap jsonBundle = peripheral.asWritableMap();
                    map.pushMap(jsonBundle);
                }
                callback.invoke(null, map);
            } catch (Exception ex) {
                callback.invoke(createUnexpectedErrorWritableMap("peripheral.asWritableMap threw an exception: " + ex));
            }
            return v;
        });
    }

    @ReactMethod
    public void getBondedPeripherals(Callback callback) {
        callback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.NOT_SUPPORTED));
    }

    @ReactMethod
    public void removePeripheral(String deviceUUID, Callback callback) {
        Log.d(LOG_TAG, "Removing from list: " + deviceUUID);
        if (handledInvalidState(getBluetoothAdapter(), callback)) return;

        Peripheral peripheral = peripherals.get(deviceUUID);
        if (peripheral != null) {
            synchronized (peripherals) {
                if (peripheral.isConnected()) {
                    callback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.NOT_SUPPORTED));
                } else {
                    peripherals.remove(deviceUUID);
                    callback.invoke();
                }
            }
        } else
            callback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.PERIPHERAL_NOT_FOUND));
    }

    @ReactMethod
    public void requestConnectionPriority(String deviceUUID, int connectionPriority, Callback callback) {
        Log.d(LOG_TAG, "Request connection priority of " + connectionPriority + " from: " + deviceUUID);

        Peripheral peripheral = peripherals.get(deviceUUID);
        if (peripheral != null) {
            peripheral.requestConnectionPriority(connectionPriority, callback);
        } else {
            callback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.PERIPHERAL_NOT_FOUND));
        }
    }

    @ReactMethod
    public void requestMTU(String deviceUUID, int mtu, Callback callback) {
        Log.d(LOG_TAG, "Request MTU of " + mtu + " bytes from: " + deviceUUID);

        Peripheral peripheral = peripherals.get(deviceUUID);
        if (peripheral != null) {
            peripheral.requestMTU(mtu, callback);
        } else {
            callback.invoke(createInvalidStateErrorWritableMap(InvalidStateCode.PERIPHERAL_NOT_FOUND));
        }
    }

    private final static char[] hexArray = "0123456789ABCDEF".toCharArray();

    public static String bytesToHex(byte[] bytes) {
        char[] hexChars = new char[bytes.length * 2];
        for (int j = 0; j < bytes.length; j++) {
            int v = bytes[j] & 0xFF;
            hexChars[j * 2] = hexArray[v >>> 4];
            hexChars[j * 2 + 1] = hexArray[v & 0x0F];
        }
        return new String(hexChars);
    }

    public static WritableArray bytesToWritableArray(byte[] bytes) {
        WritableArray value = Arguments.createArray();
        for (int i = 0; i < bytes.length; i++)
            value.pushInt((bytes[i] & 0xFF));
        return value;
    }


    private Peripheral retrieveOrCreatePeripheral(String peripheralUUID) {
        Peripheral peripheral = peripherals.get(peripheralUUID);
        if (peripheral == null) {
            synchronized (peripherals) {
                if (peripheralUUID != null) {
                    peripheralUUID = peripheralUUID.toUpperCase();
                }
                if (BluetoothAdapter.checkBluetoothAddress(peripheralUUID)) {
                    BluetoothDevice device = bluetoothAdapter.getRemoteDevice(peripheralUUID);
                    if (Build.VERSION.SDK_INT >= LOLLIPOP && !forceLegacy) {
                        peripheral = new LollipopPeripheral(device, reactContext);
                    } else {
                        peripheral = new Peripheral(device, reactContext);
                    }
                    peripherals.put(peripheralUUID, peripheral);
                }
            }
        }
        return peripheral;
    }

   @ReactMethod
    public void addListener(String eventName) {
      // Keep: Required for RN built in Event Emitter Calls.
    }

    @ReactMethod
     public void removeListeners(Integer count) {
      // Keep: Required for RN built in Event Emitter Calls.
    }

    @Override
    public void onCatalystInstanceDestroy() {
        try {
            // Disconnect all known peripherals, otherwise android system will think we are still connected
            // while we have lost the gatt instance
            disconnectPeripherals();
        }catch(Exception e) {
            Log.d(LOG_TAG, "Could not disconnect peripherals", e);
        }

        if (scanManager != null) {
            // Stop scan in case one was started to stop events from being emitted after destroy
            scanManager.stopScan(args -> {});
        }
    }
}
