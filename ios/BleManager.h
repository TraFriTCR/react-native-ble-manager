#import "React/RCTBridgeModule.h"
#import "React/RCTEventEmitter.h"
#import <CoreBluetooth/CoreBluetooth.h>


@interface BleManager : RCTEventEmitter <RCTBridgeModule, CBCentralManagerDelegate, CBPeripheralDelegate>{
    RCTResponseSenderBlock connectCallback;
    RCTResponseSenderBlock readCallback;
    NSString *readCallbackKey; // needed due to possible collisions with notifies
    RCTResponseSenderBlock writeCallback;
    RCTResponseSenderBlock readRSSICallback;
    RCTResponseSenderBlock retrieveServicesCallback;
    NSMutableArray *writeQueue;
    NSMutableDictionary *notificationCallbacks;
    NSMutableDictionary *stopNotificationCallbacks;
    NSMutableSet *retrieveServicesLatch;
}

@property (strong, nonatomic) NSMutableSet *peripherals;
@property (strong, nonatomic) CBCentralManager *manager;
@property (weak, nonatomic) NSTimer *scanTimer;
@property (strong, nonatomic) NSMutableArray *commandQueue;
@property (strong, nonatomic) dispatch_queue_t commandDispatch;

// Returns the static CBCentralManager instance used by this library.
// May have unexpected behavior when using multiple instances of CBCentralManager.
// For integration with external libraries, advanced use only.
+(CBCentralManager *)getCentralManager;

// Returns the singleton instance of this class initiated by RN.
// For integration with external libraries, advanced use only.
+(BleManager *)getInstance;

@end
