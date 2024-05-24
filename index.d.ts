declare module "react-native-ble-manager" {
  export enum BTErrorType {
    ATT_RESPONSE = 1,
    INVALID_STATE = 2,
    INVALID_ARGUMENT = 3,
    UNEXPECTED = 4, 
  }

  // See Bluetooth spec for error code definitions
  export enum ATTResponseCode {
    SUCCESS = 0x00,
    INVALID_HANDLE = 0x01,
    READ_NOT_PERMIT = 0x02,
    WRITE_NOT_PERMIT = 0x03,
    INVALID_PDU = 0x04,
    INSUF_AUTHENTICATION = 0x05,
    REQ_NOT_SUPPORTED = 0x06,
    INVALID_OFFSET = 0x07,
    INSUF_AUTHORIZATION = 0x08,
    PREPARE_Q_FULL = 0x09,
    NOT_FOUND = 0x0a,
    NOT_LONG = 0x0b,
    INSUF_KEY_SIZE = 0x0c,
    INVALID_ATTR_LEN = 0x0d,
    ERR_UNLIKELY = 0x0e,
    INSUF_ENCRYPTION = 0x0f,
    UNSUPPORT_GRP_TYPE = 0x10,
    INSUF_RESOURCE = 0x11,
    DATABASE_OUT_OF_SYNC = 0x12,
    VALUE_NOT_ALLOWED = 0x13,
    
    WRITE_REJECTED = 0xFC,
    CCC_CFG_ERR = 0xFD,
    PRC_IN_PROGRESS = 0xFE,
    OUT_OF_RANGE = 0xFF,
  }

  export enum InvalidStateCode {
    UNKNOWN_BTERROR = 1, // Error is related to BLE but otherwise unknown, not necessarily a bug
    NOT_SUPPORTED = 2, // Feature not available on this platform or device
    CONNECTION_ATTEMPT_FAILED = 3, // Attempt to start a connection but it failed to
    PERIPHERAL_NOT_CONNECTED = 4, // The peripheral is not connected
    PERIPHERAL_DISCONNECTED = 5, // The peripheral was recently connected but lost connection
    PERIPHERAL_NOT_FOUND = 6, // The peripheral is not known, for example it was not found during a connection event
    RESOURCE_NOT_FOUND = 7, // The characteristic, service, descriptor does not exist
    BT_DISABLED = 8, // BLE is disabled
    BT_UNSUPPORTED = 9, // BLE is unsupported on the provided device
    GUI_RESOURCE_UNAVAILABLE = 10, // Failed to get UI resource like the current acitivity, likely b
    CONNECTION_LIMIT_REACHED = 11, // Connection limit reached
  }

  // Error codes in BLE response or driver
  export interface ATTResponseError {
    type: BTErrorType.ATT_RESPONSE;
    status: ATTResponseCode;
  }

  // Error codes for invalid state of device or system
  export interface InvalidStateError {
    type: BTErrorType.INVALID_STATE;
    status: InvalidStateCode;
  }

  // Error codes for invalid arguments to the function which returned this error
  export interface InvalidArgumentError {
    type: BTErrorType.INVALID_ARGUMENT;
    message: string;
  }

  // Errors indicative of a problem with the device, software, ect.  Likely indicates a bug in react-native-ble-manager
  export interface UnexpectedError {
    type: BTErrorType.UNEXPECTED;
    message: string;
  }

  export type BTError = ATTResponseError | InvalidStateError | InvalidArgumentError | UnexpectedError;

  export interface Peripheral {
    id: string;
    rssi: number;
    name?: string;
    advertising: AdvertisingData;
  }

  export interface WritableMap {
    CDVType: string,
    data: string,
    bytes: number[],
  }

  export interface AdvertisingData {
    isConnectable?: boolean;
    localName?: string;
    manufacturerData?: WritableMap;
    serviceUUIDs?: string[];
    serviceData?: {[key: string]: WritableMap};
    txPowerLevel?: number;
  }

  export interface StartOptions {
    showAlert?: boolean;
    restoreIdentifierKey?: string;
    queueIdentifierKey?: string;
    forceLegacy?: boolean;
  }

  export function start(options?: StartOptions): Promise<void>;

  export interface ScanOptions {
    numberOfMatches?: number;
    matchMode?: number;
    scanMode?: number;
    reportDelay?: number;
    phy?: number;
    legacy?: boolean;
  }

  export function scan(
    serviceUUIDs: string[],
    seconds: number,
    allowDuplicates?: boolean,
    options?: ScanOptions
  ): Promise<void>;
  export function stopScan(): Promise<void>;
  export function connect(peripheralID: string): Promise<void>;
  export function disconnect(
    peripheralID: string,
    force?: boolean
  ): Promise<void>;
  export function checkState(): void;
  export function startNotification(
    peripheralID: string,
    serviceUUID: string,
    characteristicUUID: string
  ): Promise<void>;

  /// Android only
  export function startNotificationUseBuffer(
    peripheralID: string,
    serviceUUID: string,
    characteristicUUID: string,
    buffer: number
  ): Promise<void>;

  export function stopNotification(
    peripheralID: string,
    serviceUUID: string,
    characteristicUUID: string
  ): Promise<void>;

  export function read(
    peripheralID: string,
    serviceUUID: string,
    characteristicUUID: string
  ): Promise<any>;
  export function write(
    peripheralID: string,
    serviceUUID: string,
    characteristicUUID: string,
    data: any,
    maxByteSize?: number
  ): Promise<void>;
  export function writeWithoutResponse(
    peripheralID: string,
    serviceUUID: string,
    characteristicUUID: string,
    data: any,
    maxByteSize?: number,
    queueSleepTime?: number
  ): Promise<void>;

  export function readRSSI(peripheralID: string): Promise<void>;

  export function getConnectedPeripherals(
    serviceUUIDs: string[]
  ): Promise<Peripheral[]>;
  export function getDiscoveredPeripherals(): Promise<Peripheral[]>;
  export function isPeripheralConnected(
    peripheralID: string,
    serviceUUIDs: string[]
  ): Promise<boolean>;

  // [Android only API 21+]
  export enum ConnectionPriority {
    balanced = 0,
    high = 1,
    low = 2,
  }
  export function requestConnectionPriority(
    peripheralID: string,
    connectionPriority: ConnectionPriority
  ): Promise<void>;
  export function isBluetoothEnabled(): Promise<boolean>;
  /// Android only
  export function enableBluetooth(): Promise<void>;
  // [Android only]
  export function refreshCache(peripheralID: string): Promise<void>;
  // [Android only API 21+]
  export function requestMTU(peripheralID: string, mtu: number): Promise<number>;

  export function createBond(
    peripheralID: string,
    peripheralPin?: string
  ): Promise<void>;
  export function removeBond(peripheralID: string): Promise<void>;
  export function getBondedPeripherals(): Promise<Peripheral[]>;
  export function removePeripheral(peripheralID: string): Promise<void>;

  // [Android only]
  export function setName(name: string): void;

  export interface Service {
    uuid: string;
  }

  export interface Descriptor {
    value: string;
    uuid: string;
  }

  export enum CharacteristicProperty {
   Broadcast = "Broadcast",
   Read = "Read",
   WriteWithoutResponse = "WriteWithoutResponse",
   Write = "Write",
   Notify = "Notify",
   Indicate = "Indicate",
   AuthenticatedSignedWrites = "AuthenticatedSignedWrites",
   ExtendedProperties = "ExtendedProperties",
   NotifyEncryptionRequired = "NotifyEncryptionRequired",
   IndicateEncryptionRequired = "IndicateEncryptionRequired",
  }

  export interface Characteristic {
    // See https://developer.apple.com/documentation/corebluetooth/cbcharacteristicproperties
    properties: CharacteristicProperty[],
    characteristic: string;
    service: string;
    descriptors?: Descriptor[];

  }

  export interface PeripheralInfo extends Peripheral {
    serviceUUIDs?: string[];
    characteristics?: Characteristic[];
    services?: Service[];
  }

  export function retrieveServices(
    peripheralID: string,
    serviceUUIDs?: string[]
  ): Promise<PeripheralInfo>;
}
