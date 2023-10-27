package it.innove;

import android.bluetooth.BluetoothDevice;
import android.bluetooth.le.ScanRecord;
import android.bluetooth.le.ScanResult;
import android.os.Build;
import android.os.ParcelUuid;
import android.util.Log;
import android.util.SparseArray;

import androidx.annotation.RequiresApi;

import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContext;
import com.facebook.react.bridge.WritableArray;
import com.facebook.react.bridge.WritableMap;

import java.util.Map;

@RequiresApi(Build.VERSION_CODES.LOLLIPOP)
public class LollipopPeripheral extends Peripheral {

	private ScanRecord advertisingData;
	private ScanResult scanResult;

	public LollipopPeripheral(ReactContext reactContext, ScanResult result) {
		super(result.getDevice(), result.getRssi(), result.getScanRecord().getBytes(), reactContext);
		this.advertisingData = result.getScanRecord();
		this.scanResult = result;
	}

	public LollipopPeripheral(BluetoothDevice device, ReactApplicationContext reactContext) {
		super(device, reactContext);
	}

	@Override
	public WritableMap asWritableMap() {
		WritableMap map = super.asWritableMap();
		WritableMap advertising = Arguments.createMap();

		try {

			if (advertisingData != null) {

				// localName
				String deviceName = advertisingData.getDeviceName();
				if (deviceName != null) {
					advertising.putString("localName", deviceName.replace("\0", ""));
				}

				// isConnectable
				if (android.os.Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
					// We can check if peripheral is connectable using the scanresult
					if (this.scanResult != null) {
						advertising.putBoolean("isConnectable", scanResult.isConnectable());
					}
				}

				// txPowerLevel
				int txPowerLevel = advertisingData.getTxPowerLevel();
				if (txPowerLevel > 0) {
					advertising.putInt("txPowerLevel", txPowerLevel);
				}

				// serviceData
				if (advertisingData.getServiceData() != null && advertisingData.getServiceData().size() != 0) {
					WritableMap serviceData = Arguments.createMap();
					for (Map.Entry<ParcelUuid, byte[]> entry : advertisingData.getServiceData().entrySet()) {
						if (entry.getValue() != null) {
							serviceData.putMap(UUIDHelper.uuidToString((entry.getKey()).getUuid()), byteArrayToWritableMap(entry.getValue()));
						}
					}
					advertising.putMap("serviceData", serviceData);
				}

				// serviceUUIDs
				if (advertisingData.getServiceUuids() != null && advertisingData.getServiceUuids().size() != 0) {
					WritableArray serviceUuids = Arguments.createArray();
					for (ParcelUuid uuid : advertisingData.getServiceUuids()) {
						serviceUuids.pushString(UUIDHelper.uuidToString(uuid.getUuid()));
					}
					advertising.putArray("serviceUUIDs", serviceUuids);
				}
;
				// manufacturerData
				if (advertisingData.getManufacturerSpecificData() != null && advertisingData.getManufacturerSpecificData().size() != 0) {
					WritableMap manufacturerDataArray = Arguments.createMap();
					SparseArray<byte[]> manufacturerDataMapSparse = advertisingData.getManufacturerSpecificData();
					if (manufacturerDataMapSparse.size() > 1) {
						Log.e(BleManager.LOG_TAG, "Found manufacturing data that has length greater than 1!");
					}

					int manufacturerID = manufacturerDataMapSparse.keyAt(0);
					byte[] manufacturerDataBytes = manufacturerDataMapSparse.valueAt(0);

					byte[] result = new byte[manufacturerDataBytes.length + 2];
					result[1] = (byte) (manufacturerID >> 8);
					result[0] = (byte) (manufacturerID);
					System.arraycopy(manufacturerDataBytes, 0, result, 2, manufacturerDataBytes.length);

					advertising.putMap("manufacturerData", byteArrayToWritableMap(result));
				}

			}

			map.putMap("advertising", advertising);
		} catch (Exception e) { // this shouldn't happen
			e.printStackTrace();
		}

		return map;
	}

	public void updateData(ScanResult result) {
		advertisingData = result.getScanRecord();
		advertisingDataBytes = advertisingData.getBytes();
	}


}
