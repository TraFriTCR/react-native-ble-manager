"use strict";
var React = require("react-native");
var bleManager = React.NativeModules.BleManager;

class BleError extends Error {
  constructor(data) {
    super();
    this.data = data;
  }
}

class BleManager {
   BTErrorType = {
    ATT_RESPONSE: 1,
    INVALID_STATE: 2,
    INVALID_ARGUMENT: 3,
    UNEXPECTED: 4, 
  }

  ATTResponseCode = {
    SUCCESS: 0x00,
    INVALID_HANDLE: 0x01,
    READ_NOT_PERMIT: 0x02,
    WRITE_NOT_PERMIT: 0x03,
    INVALID_PDU: 0x04,
    INSUF_AUTHENTICATION: 0x05,
    REQ_NOT_SUPPORTED: 0x06,
    INVALID_OFFSET: 0x07,
    INSUF_AUTHORIZATION: 0x08,
    PREPARE_Q_FULL: 0x09,
    NOT_FOUND: 0x0a,
    NOT_LONG: 0x0b,
    INSUF_KEY_SIZE: 0x0c,
    INVALID_ATTR_LEN: 0x0d,
    ERR_UNLIKELY: 0x0e,
    INSUF_ENCRYPTION: 0x0f,
    UNSUPPORT_GRP_TYPE: 0x10,
    INSUF_RESOURCE: 0x11,
    DATABASE_OUT_OF_SYNC: 0x12,
    VALUE_NOT_ALLOWED: 0x13,
    
    WRITE_REJECTED: 0xFC,
    CCC_CFG_ERR: 0xFD,
    PRC_IN_PROGRESS: 0xFE,
    OUT_OF_RANGE: 0xFF,
  }

  InvalidStateCode = {
    UNKNOWN_BTERROR: 1, // Error is related to BLE but otherwise unknown, not necessarily a bug
    NOT_SUPPORTED: 2, // Feature not available on this platform or device
    CONNECTION_ATTEMPT_FAILED: 3, // Attempt to start a connection but it failed to
    PERIPHERAL_NOT_CONNECTED: 4, // The peripheral is not connected
    PERIPHERAL_DISCONNECTED: 5, // The peripheral was recently connected but lost connection
    PERIPHERAL_NOT_FOUND: 6, // The peripheral is not known, for example it was not found during a connection event
    RESOURCE_NOT_FOUND: 7, // The characteristic, service, descriptor does not exist
    BT_DISABLED: 8, // BLE is disabled
    BT_UNSUPPORTED: 9, // BLE is unsupported on the provided device
    GUI_RESOURCE_UNAVAILABLE: 10, // Failed to get UI resource like the current acitivity, likely b
    CONNECTION_LIMIT_REACHED: 11, // Connection limit reached
  }

  constructor() {
    this.isPeripheralConnected = this.isPeripheralConnected.bind(this);
  }

  read(peripheralId, serviceUUID, characteristicUUID) {
    return new Promise((fulfill, reject) => {
      bleManager.read(
        peripheralId,
        serviceUUID,
        characteristicUUID,
        (error, data) => {
          if (error) {
            reject(new BleError(error));
          } else {
            fulfill(data);
          }
        }
      );
    });
  }

  readRSSI(peripheralId) {
    return new Promise((fulfill, reject) => {
      bleManager.readRSSI(peripheralId, (error, rssi) => {
        if (error) {
          reject(new BleError(error));
        } else {
          fulfill(rssi);
        }
      });
    });
  }

  refreshCache(peripheralId) {
    return new Promise((fulfill, reject) => {
      bleManager.refreshCache(peripheralId, (error, result) => {
        if (error) {
          reject(new BleError(error));
        } else {
          fulfill(result);
        }
      });
    });
  }

  retrieveServices(peripheralId, services) {
    return new Promise((fulfill, reject) => {
      bleManager.retrieveServices(
        peripheralId,
        services,
        (error, peripheral) => {
          if (error) {
            reject(new BleError(error));
          } else {
            fulfill(peripheral);
          }
        }
      );
    });
  }

  write(peripheralId, serviceUUID, characteristicUUID, data, maxByteSize) {
    if (maxByteSize == null) {
      maxByteSize = 20;
    }
    return new Promise((fulfill, reject) => {
      bleManager.write(
        peripheralId,
        serviceUUID,
        characteristicUUID,
        data,
        maxByteSize,
        error => {
          if (error) {
            reject(new BleError(error));
          } else {
            fulfill();
          }
        }
      );
    });
  }

  writeWithoutResponse(
    peripheralId,
    serviceUUID,
    characteristicUUID,
    data,
    maxByteSize,
    queueSleepTime
  ) {
    if (maxByteSize == null) {
      maxByteSize = 20;
    }
    if (queueSleepTime == null) {
      queueSleepTime = 10;
    }
    return new Promise((fulfill, reject) => {
      bleManager.writeWithoutResponse(
        peripheralId,
        serviceUUID,
        characteristicUUID,
        data,
        maxByteSize,
        queueSleepTime,
        error => {
          if (error) {
            reject(new BleError(error));
          } else {
            fulfill();
          }
        }
      );
    });
  }

  connect(peripheralId) {
    return new Promise((fulfill, reject) => {
      bleManager.connect(peripheralId, error => {
        if (error) {
          reject(new BleError(error));
        } else {
          fulfill();
        }
      });
    });
  }

  createBond(peripheralId,peripheralPin=null) {
    return new Promise((fulfill, reject) => {
      bleManager.createBond(peripheralId,peripheralPin, error => {
        if (error) {
          reject(new BleError(error));
        } else {
          fulfill();
        }
      });
    });
  }

  removeBond(peripheralId) {
    return new Promise((fulfill, reject) => {
      bleManager.removeBond(peripheralId, error => {
        if (error) {
          reject(new BleError(error));
        } else {
          fulfill();
        }
      });
    });
  }

  disconnect(peripheralId, force = true) {
    return new Promise((fulfill, reject) => {
      bleManager.disconnect(peripheralId, force, error => {
        if (error) {
          reject(new BleError(error));
        } else {
          fulfill();
        }
      });
    });
  }

  startNotification(peripheralId, serviceUUID, characteristicUUID) {
    return new Promise((fulfill, reject) => {
      bleManager.startNotification(
        peripheralId,
        serviceUUID,
        characteristicUUID,
        error => {
          if (error) {
            reject(new BleError(error));
          } else {
            fulfill();
          }
        }
      );
    });
  }

  startNotificationUseBuffer(
    peripheralId,
    serviceUUID,
    characteristicUUID,
    buffer
  ) {
    return new Promise((fulfill, reject) => {
      bleManager.startNotificationUseBuffer(
        peripheralId,
        serviceUUID,
        characteristicUUID,
        buffer,
        error => {
          if (error) {
            reject(new BleError(error));
          } else {
            fulfill();
          }
        }
      );
    });
  }

  stopNotification(peripheralId, serviceUUID, characteristicUUID) {
    return new Promise((fulfill, reject) => {
      bleManager.stopNotification(
        peripheralId,
        serviceUUID,
        characteristicUUID,
        error => {
          if (error) {
            reject(new BleError(error));
          } else {
            fulfill();
          }
        }
      );
    });
  }

  checkState() {
    bleManager.checkState();
  }

  start(options) {
    return new Promise((fulfill, reject) => {
      if (options == null) {
        options = {};
      }
      bleManager.start(options, error => {
        if (error) {
          reject(new BleError(error));
        } else {
          fulfill();
        }
      });
    });
  }

  scan(serviceUUIDs, seconds, allowDuplicates, scanningOptions = {}) {
    return new Promise((fulfill, reject) => {
      if (allowDuplicates == null) {
        allowDuplicates = false;
      }

      // (ANDROID) Match as many advertisement per filter as hw could allow
      // dependes on current capability and availability of the resources in hw.
      if (scanningOptions.numberOfMatches == null) {
        scanningOptions.numberOfMatches = 3;
      }

      // (ANDROID) Defaults to MATCH_MODE_AGGRESSIVE
      if (scanningOptions.matchMode == null) {
        scanningOptions.matchMode = 1;
      }

      // (ANDROID) Defaults to SCAN_MODE_LOW_POWER on android
      if (scanningOptions.scanMode == null) {
        scanningOptions.scanMode = 0;
      }

      if (scanningOptions.reportDelay == null) {
        scanningOptions.reportDelay = 0;
      }

      bleManager.scan(
        serviceUUIDs,
        seconds,
        allowDuplicates,
        scanningOptions,
        error => {
          if (error) {
            reject(new BleError(error));
          } else {
            fulfill();
          }
        }
      );
    });
  }

  stopScan() {
    return new Promise((fulfill, reject) => {
      bleManager.stopScan(error => {
        if (error != null) {
          reject(new BleError(error));
        } else {
          fulfill();
        }
      });
    });
  }

  isBluetoothEnabled() {
    return new Promise((fulfill, reject) => {
      bleManager.isBluetoothEnabled((error, enabled) => {
        if (error != null) {
          reject(new BleError(error));
        } else {
          fulfill(enabled);
        }
      });
    });
  };

  enableBluetooth() {
    return new Promise((fulfill, reject) => {
      bleManager.enableBluetooth(error => {
        if (error != null) {
          reject(new BleError(error));
        } else {
          fulfill();
        }
      });
    });
  }

  getConnectedPeripherals(serviceUUIDs) {
    return new Promise((fulfill, reject) => {
      bleManager.getConnectedPeripherals(serviceUUIDs, (error, result) => {
        if (error) {
          reject(new BleError(error));
        } else {
          if (result != null) {
            fulfill(result);
          } else {
            fulfill([]);
          }
        }
      });
    });
  }

  getBondedPeripherals() {
    return new Promise((fulfill, reject) => {
      bleManager.getBondedPeripherals((error, result) => {
        if (error) {
          reject(new BleError(error));
        } else {
          if (result != null) {
            fulfill(result);
          } else {
            fulfill([]);
          }
        }
      });
    });
  }

  getDiscoveredPeripherals() {
    return new Promise((fulfill, reject) => {
      bleManager.getDiscoveredPeripherals((error, result) => {
        if (error) {
          reject(new BleError(error));
        } else {
          if (result != null) {
            fulfill(result);
          } else {
            fulfill([]);
          }
        }
      });
    });
  }

  removePeripheral(peripheralId) {
    return new Promise((fulfill, reject) => {
      bleManager.removePeripheral(peripheralId, error => {
        if (error) {
          reject(new BleError(error));
        } else {
          fulfill();
        }
      });
    });
  }

  isPeripheralConnected(peripheralId, serviceUUIDs) {
    return this.getConnectedPeripherals(serviceUUIDs).then(result => {
      if (
        result.find(p => {
          return p.id === peripheralId;
        })
      ) {
        return true;
      } else {
        return false;
      }
    });
  }

  requestConnectionPriority(peripheralId, connectionPriority) {
    return new Promise((fulfill, reject) => {
      bleManager.requestConnectionPriority(
        peripheralId,
        connectionPriority,
        (error, status) => {
          if (error) {
            reject(new BleError(error));
          } else {
            fulfill(status);
          }
        }
      );
    });
  }

  requestMTU(peripheralId, mtu) {
    return new Promise((fulfill, reject) => {
      bleManager.requestMTU(peripheralId, mtu, (error, mtu) => {
        if (error) {
          reject(new BleError(error));
        } else {
          fulfill(mtu);
        }
      });
    });
  }

  setName(name) {
    bleManager.setName(name);
  }
}

module.exports = new BleManager();
module.exports.BleError = BleError;
