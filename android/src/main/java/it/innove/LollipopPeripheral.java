package it.innove;

import android.bluetooth.BluetoothDevice;
import android.bluetooth.le.ScanRecord;
import android.bluetooth.le.ScanResult;
import android.os.Build;
import android.os.ParcelUuid;
import android.util.Log;
import java.io.ByteArrayOutputStream;
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
				// iOS merges multiple 0xFF (Manufacturer Specific Data) segments from
				// advertising + scan response into a single array, with a single
				// manufacturer ID prefix. Recreate that behavior here by parsing the
				// raw scan record and concatenating payloads that share the same ID.
				byte[] mergedMfg = getMergedManufacturerData();
				if (mergedMfg != null && mergedMfg.length > 0) {
					advertising.putMap("manufacturerData", byteArrayToWritableMap(mergedMfg));
				}

			}

			map.putMap("advertising", advertising);
		} catch (Exception e) { // this shouldn't happen
			e.printStackTrace();
		}

		return map;
	}

	// Parse advertisingDataBytes to merge all Manufacturer Specific Data (type 0xFF)
	// blocks into a single byte array with a single 2-byte manufacturer ID prefix
	// (little-endian), matching iOS behavior.
	private byte[] getMergedManufacturerData() {
		try {
			if (advertisingData == null) return null;
			byte[] record = advertisingData.getBytes();
			if (record == null || record.length == 0) return null;

			int index = 0;
			int firstManufacturerId = -1;
			boolean found = false;
			ByteArrayOutputStream out = new ByteArrayOutputStream();

			while (index < record.length) {
				int length = unsignedToBytes(record[index++]);
				if (length == 0) break; // no more fields
				if (index + length > record.length) break; // malformed, stop parsing

				int type = unsignedToBytes(record[index++]);
				int dataLen = length - 1;

				if (type == 0xFF && dataLen >= 2) { // Manufacturer Specific Data
					int id = (unsignedToBytes(record[index]) | (unsignedToBytes(record[index + 1]) << 8));
					if (!found) {
						firstManufacturerId = id;
						// write 2-byte manufacturer ID (little-endian)
						out.write((byte) (id & 0xFF));
						out.write((byte) ((id >> 8) & 0xFF));
						found = true;
						// append payload after the 2-byte ID
						if (dataLen - 2 > 0) out.write(record, index + 2, dataLen - 2);
					} else {
						if (id == firstManufacturerId) {
							// append additional payload, omit repeating the ID
							if (dataLen - 2 > 0) out.write(record, index + 2, dataLen - 2);
						} else {
							// Different manufacturer ID encountered; skip to keep a single ID
							Log.w(BleManager.LOG_TAG, "Manufacturer data with different ID found: " + id + ", expected: " + firstManufacturerId);
						}
					}
				}

				// move to next field
				index += dataLen;
			}

			return found ? out.toByteArray() : null;
		} catch (Exception ex) {
			Log.w(BleManager.LOG_TAG, "Failed to merge manufacturer data", ex);
			return null;
		}
	}

	public void updateData(ScanResult result) {
		advertisingData = result.getScanRecord();
		advertisingDataBytes = advertisingData.getBytes();
	}


}
