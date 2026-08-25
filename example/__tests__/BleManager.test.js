/**
 * @format
 */

const mockRead = jest.fn();

jest.mock('react-native', () => ({
  NativeModules: {
    BleManager: {
      read: mockRead,
    },
  },
}));

const BleManager = require('../../BleManager');

describe('BleManager.read', () => {
  it.each(['Android WritableArray', 'iOS NSArray'])(
    'normalizes %s bridge values to Uint8Array',
    async () => {
      mockRead.mockImplementation(
        (_peripheralId, _serviceUUID, _characteristicUUID, callback) => {
          callback(null, [48, 49, 50, 51]);
        },
      );

      const result = await BleManager.read(
        'device-id',
        'service-uuid',
        'characteristic-uuid',
      );

      expect(result).toBeInstanceOf(Uint8Array);
      expect(result).toEqual(Uint8Array.from([48, 49, 50, 51]));
    },
  );

  it('preserves an empty characteristic value', async () => {
    mockRead.mockImplementation(
      (_peripheralId, _serviceUUID, _characteristicUUID, callback) => {
        callback(null, []);
      },
    );

    await expect(
      BleManager.read('device-id', 'service-uuid', 'characteristic-uuid'),
    ).resolves.toEqual(new Uint8Array());
  });
});
