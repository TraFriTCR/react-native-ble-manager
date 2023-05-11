#import "BleManager.h"
#import "React/RCTBridge.h"
#import "React/RCTConvert.h"
#import "React/RCTEventDispatcher.h"
#import "NSData+Conversion.h"
#import "CBPeripheral+Extensions.h"
#import "BLECommandContext.h"

static CBCentralManager *_sharedManager = nil;
static BleManager * _instance = nil;
static bool commandQueueBusy = false;

@implementation BleManager


RCT_EXPORT_MODULE();

@synthesize manager;
@synthesize peripherals;
@synthesize scanTimer;
@synthesize commandQueue;
@synthesize commandDispatch;
bool hasListeners;

- (instancetype)init
{
    
    if (self = [super init]) {
        peripherals = [NSMutableSet set];
        connectCallback =  nil;
        retrieveServicesLatch = [NSMutableSet new];
        readCallback = nil;
        readCallbackKey = @"";
        readRSSICallback = nil;
        retrieveServicesCallback = nil;
        writeCallback = nil;
        writeQueue = [NSMutableArray array];
        notificationCallback = nil;
        notificationCallbackKey = @"";
        commandQueue = [NSMutableArray new];
        commandDispatch = dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL);
        isBluetoothEnabled = @(NO);
        _instance = self;
        NSLog(@"BleManager created");
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(bridgeReloading) name:RCTBridgeWillReloadNotification object:nil];
    }
    
    return self;
}

-(void)startObserving {
    hasListeners = YES;
}

-(void)stopObserving {
    hasListeners = NO;
}

-(void)bridgeReloading {
    if (manager) {
        if (self.scanTimer) {
            [self.scanTimer invalidate];
            self.scanTimer = nil;
            [manager stopScan];
        }
        
        manager.delegate = nil;
    }
    @synchronized(peripherals) {
        for (CBPeripheral* p in peripherals) {
            p.delegate = nil;
        }
        
        peripherals = [NSMutableSet set];
    }
}

+(BOOL)requiresMainQueueSetup
{
    return YES;
}

- (NSArray<NSString *> *)supportedEvents
{
    return @[@"BleManagerDidUpdateValueForCharacteristic", @"BleManagerStopScan", @"BleManagerDiscoverPeripheral", @"BleManagerConnectPeripheral", @"BleManagerDisconnectPeripheral", @"BleManagerDidUpdateState", @"BleManagerCentralManagerWillRestoreState", @"BleManagerDidUpdateNotificationStateFor"];
}


- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    
    dispatch_async(commandDispatch, ^{
        NSString *key = [self keyForPeripheral: peripheral andCharacteristic:characteristic];
        // Guard against potentially invalid notifiy calls
        bool isCompatibleCallback = readCallback && ([readCallbackKey isEqualToString: key]);
        if (error) {
            NSLog(@"Error %@ :%@", characteristic.UUID, error);
            if (isCompatibleCallback) {
                readCallback(@[error, [NSNull null]]);
                readCallback = nil;
                [self completedCommand];
            }
            return;
        }
        NSLog(@"Read value [%@]: (%lu) %@", characteristic.UUID, [characteristic.value length], characteristic.value);
        
        if (isCompatibleCallback) {
            readCallback(@[[NSNull null], ([characteristic.value length] > 0) ? [characteristic.value toArray] : [NSNull null]]);
            readCallback = nil;
            [self completedCommand];
        } else {
            if (hasListeners) {
                [self sendEventWithName:@"BleManagerDidUpdateValueForCharacteristic" body:@{@"peripheral": peripheral.uuidAsString, @"characteristic":characteristic.UUID.UUIDString, @"service":characteristic.service.UUID.UUIDString, @"value": ([characteristic.value length] > 0) ? [characteristic.value toArray] : [NSNull null]}];
            }
        }
    });
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    
    NSString *key = [self keyForPeripheral: peripheral andCharacteristic:characteristic];
    
    bool isValidCallback = ([notificationCallbackKey isEqualToString:key] && notificationCallback != nil);
    
    dispatch_async(commandDispatch, ^{
        if (error) {
            NSLog(@"Error in didUpdateNotificationStateForCharacteristic: %@", error);
            if (isValidCallback) {
                notificationCallback(@[@"Failed to start / stop notification"]);
                notificationCallback = nil;
                [self completedCommand];
            }
            if (!characteristic){
                return;
            } else if (hasListeners) {
                [self sendEventWithName:@"BleManagerDidUpdateNotificationStateFor" body:@{@"peripheral": peripheral.uuidAsString, @"characteristic": characteristic.UUID.UUIDString, @"isNotifying": @(false), @"domain": [error domain], @"code": @(error.code)}];
            }
        } else {
            if (isValidCallback) {
                NSLog(@"Successfully started / stopped a notification");
                notificationCallback(@[]);
                notificationCallback = nil;
                [self completedCommand];
            }
            if (hasListeners) {
                [self sendEventWithName:@"BleManagerDidUpdateNotificationStateFor" body:@{@"peripheral": peripheral.uuidAsString, @"characteristic": characteristic.UUID.UUIDString, @"isNotifying": @(characteristic.isNotifying)}];
            }
        }
    });
}




- (NSString *) centralManagerStateToString: (int)state
{
    switch (state) {
        case CBCentralManagerStateUnknown:
            return @"unknown";
        case CBCentralManagerStateResetting:
            return @"resetting";
        case CBCentralManagerStateUnsupported:
            return @"unsupported";
        case CBCentralManagerStateUnauthorized:
            return @"unauthorized";
        case CBCentralManagerStatePoweredOff:
            return @"off";
        case CBCentralManagerStatePoweredOn:
            return @"on";
        default:
            return @"unknown";
    }
    
    return @"unknown";
}

- (NSString *) periphalStateToString: (int)state
{
    switch (state) {
        case CBPeripheralStateDisconnected:
            return @"disconnected";
        case CBPeripheralStateDisconnecting:
            return @"disconnecting";
        case CBPeripheralStateConnected:
            return @"connected";
        case CBPeripheralStateConnecting:
            return @"connecting";
        default:
            return @"unknown";
    }
    
    return @"unknown";
}

- (NSString *) periphalManagerStateToString: (int)state
{
    switch (state) {
        case CBPeripheralManagerStateUnknown:
            return @"Unknown";
        case CBPeripheralManagerStatePoweredOn:
            return @"PoweredOn";
        case CBPeripheralManagerStatePoweredOff:
            return @"PoweredOff";
        default:
            return @"unknown";
    }
    
    return @"unknown";
}

- (CBPeripheral*)findPeripheralByUUID:(NSString*)uuid {
    
    CBPeripheral *peripheral = nil;
    @synchronized(peripherals) {
        for (CBPeripheral *p in peripherals) {
            
            NSString* other = p.identifier.UUIDString;
            
            if ([uuid isEqualToString:other]) {
                peripheral = p;
                break;
            }
        }
    }
    return peripheral;
}

-(CBService *) findServiceFromUUID:(CBUUID *)UUID p:(CBPeripheral *)p
{
    for(int i = 0; i < p.services.count; i++)
    {
        CBService *s = [p.services objectAtIndex:i];
        if ([self compareCBUUID:s.UUID UUID2:UUID])
            return s;
    }
    
    return nil; //Service not found on this peripheral
}

-(int) compareCBUUID:(CBUUID *) UUID1 UUID2:(CBUUID *)UUID2
{
    char b1[16];
    char b2[16];
    [UUID1.data getBytes:b1 length:16];
    [UUID2.data getBytes:b2 length:16];
    
    if (memcmp(b1, b2, UUID1.data.length) == 0)
        return 1;
    else
        return 0;
}

-(void) resetCommandQueue
{
    [commandQueue removeAllObjects];
    commandQueueBusy = false;
}

-(void) completedCommand
{
    @synchronized(commandQueue)
    {
        [commandQueue removeObjectAtIndex:0];
        commandQueueBusy = false;
        [self nextCommand];
    }
}

-(void) nextCommand
{
    @synchronized(commandQueue) {
        if (commandQueueBusy) {
            NSLog(@"Commmand queue busy");
            return;
        }
        
        if ([commandQueue count] == 0) {
            NSLog(@"Command queue empty");
            return;
        }
        
        dispatch_block_t nextCommand = [commandQueue objectAtIndex:0];
        
        commandQueueBusy = true;
        dispatch_async(commandDispatch, nextCommand);
    }
}

-(void) enqueueCommand:(dispatch_block_t) command
{
    @synchronized(commandQueue) {
        [commandQueue addObject:command];
        [self nextCommand];
    }
}

-(bool) handledInvalidState:(RCTResponseSenderBlock) callback
{
    if ([isBluetoothEnabled isEqual:@(YES)]) {
        return false;
    } else {
        NSString *error = @"Bluetooth is not enabled";
        callback(@[error, [NSNull null]]);
        return true;
    }
}

RCT_EXPORT_METHOD(getDiscoveredPeripherals:(nonnull RCTResponseSenderBlock)callback)
{
    NSLog(@"Get discovered peripherals");
    
    if ([self handledInvalidState:callback]) return;
    
    NSMutableArray *discoveredPeripherals = [NSMutableArray array];
    @synchronized(peripherals) {
        for(CBPeripheral *peripheral in peripherals){
            NSDictionary * obj = [peripheral asDictionary];
            [discoveredPeripherals addObject:obj];
        }
    }
    callback(@[[NSNull null], [NSArray arrayWithArray:discoveredPeripherals]]);
}

RCT_EXPORT_METHOD(getConnectedPeripherals:(NSArray *)serviceUUIDStrings callback:(nonnull RCTResponseSenderBlock)callback)
{
    NSLog(@"Get connected peripherals");
    
    if ([self handledInvalidState:callback]) return;
    
    NSMutableArray *serviceUUIDs = [NSMutableArray new];
    for(NSString *uuidString in serviceUUIDStrings){
        CBUUID *serviceUUID =[CBUUID UUIDWithString:uuidString];
        [serviceUUIDs addObject:serviceUUID];
    }
    
    NSMutableArray *foundedPeripherals = [NSMutableArray array];
    if ([serviceUUIDs count] == 0){
        @synchronized(peripherals) {
            for(CBPeripheral *peripheral in peripherals){
                if([peripheral state] == CBPeripheralStateConnected){
                    NSDictionary * obj = [peripheral asDictionary];
                    [foundedPeripherals addObject:obj];
                }
            }
        }
    } else {
        NSArray *connectedPeripherals = [manager retrieveConnectedPeripheralsWithServices:serviceUUIDs];
        for(CBPeripheral *peripheral in connectedPeripherals){
            NSDictionary * obj = [peripheral asDictionary];
            [foundedPeripherals addObject:obj];
            @synchronized(peripherals) {
                [peripherals addObject:peripheral];
            }
        }
    }
    
    callback(@[[NSNull null], [NSArray arrayWithArray:foundedPeripherals]]);
}

RCT_EXPORT_METHOD(start:(NSDictionary *)options callback:(nonnull RCTResponseSenderBlock)callback)
{
    NSLog(@"BleManager initialized");
    NSMutableDictionary *initOptions = [[NSMutableDictionary alloc] init];
    
    if ([[options allKeys] containsObject:@"showAlert"]){
        [initOptions setObject:[NSNumber numberWithBool:[[options valueForKey:@"showAlert"] boolValue]]
                        forKey:CBCentralManagerOptionShowPowerAlertKey];
    }
    
    dispatch_queue_t queue;
    if ([[options allKeys] containsObject:@"queueIdentifierKey"]) {
	dispatch_queue_attr_t queueAttributes = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_BACKGROUND, 0);
        queue = dispatch_queue_create([[options valueForKey:@"queueIdentifierKey"] UTF8String], queueAttributes);
    } else {
        queue = dispatch_get_main_queue();
    }
    
    if ([[options allKeys] containsObject:@"restoreIdentifierKey"]) {
        
        [initOptions setObject:[options valueForKey:@"restoreIdentifierKey"]
                        forKey:CBCentralManagerOptionRestoreIdentifierKey];
        
        // Despite resulting in an API Misuse message invoking initWithDelegate does
        // bind this delegate, as a result this method functions regardless of bluetooth state.
        if (_sharedManager) {
            manager = _sharedManager;
            manager.delegate = self;
        } else {
            manager = [[CBCentralManager alloc] initWithDelegate:self queue:queue options:initOptions];
            _sharedManager = manager;
        }
    } else {
        manager = [[CBCentralManager alloc] initWithDelegate:self queue:queue options:initOptions];
        _sharedManager = manager;
    }
    
    [self resetCommandQueue];
    
    callback(@[]);
}

RCT_EXPORT_METHOD(scan:(NSArray *)serviceUUIDStrings timeoutSeconds:(nonnull NSNumber *)timeoutSeconds allowDuplicates:(BOOL)allowDuplicates options:(nonnull NSDictionary*)scanningOptions callback:(nonnull RCTResponseSenderBlock)callback)
{
    NSLog(@"scan with timeout %@", timeoutSeconds);
    
    if ([self handledInvalidState:callback]) return;
    
    // Clear the peripherals before scanning again, otherwise cannot connect again after disconnection
    // Only clear peripherals that are not connected - otherwise connections fail silently (without any
    // onDisconnect* callback).
    @synchronized(peripherals) {
        NSMutableArray *connectedPeripherals = [NSMutableArray array];
        for (CBPeripheral *peripheral in peripherals) {
            if (([peripheral state] != CBPeripheralStateConnected) &&
                ([peripheral state] != CBPeripheralStateConnecting)) {
                [connectedPeripherals addObject:peripheral];
            }
        }
        for (CBPeripheral *p in connectedPeripherals) {
            [peripherals removeObject:p];
        }
    }
    
    NSArray * services = [RCTConvert NSArray:serviceUUIDStrings];
    NSMutableArray *serviceUUIDs = [NSMutableArray new];
    NSDictionary *options = nil;
    if (allowDuplicates){
        options = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:CBCentralManagerScanOptionAllowDuplicatesKey];
    }
    
    for (int i = 0; i < [services count]; i++) {
        CBUUID *serviceUUID =[CBUUID UUIDWithString:[serviceUUIDStrings objectAtIndex: i]];
        [serviceUUIDs addObject:serviceUUID];
    }
    [manager scanForPeripheralsWithServices:serviceUUIDs options:options];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.scanTimer = [NSTimer scheduledTimerWithTimeInterval:[timeoutSeconds floatValue] target:self selector:@selector(stopScanTimer:) userInfo: nil repeats:NO];
    });
    callback(@[]);
}

RCT_EXPORT_METHOD(stopScan:(nonnull RCTResponseSenderBlock)callback)
{
    if ([self handledInvalidState:callback]) return;
    
    if (self.scanTimer) {
        [self.scanTimer invalidate];
        self.scanTimer = nil;
    }
    [manager stopScan];
    if (hasListeners) {
				[self sendEventWithName:@"BleManagerStopScan" body:@{@"status": @0}];
    }
    callback(@[[NSNull null]]);
}


-(void)stopScanTimer:(NSTimer *)timer {
    NSLog(@"Stop scan");
    self.scanTimer = nil;
    [manager stopScan];
    if (hasListeners) {
        if (self.bridge) {
            [self sendEventWithName:@"BleManagerStopScan" body:@{@"status": @10}];
        }
    }
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary *)advertisementData
                  RSSI:(NSNumber *)RSSI
{
    @synchronized(peripherals) {
        [peripherals addObject:peripheral];
    }
    [peripheral setAdvertisementData:advertisementData RSSI:RSSI];
    
    NSLog(@"Discover peripheral: %@", [peripheral name]);
    if (hasListeners) {
        [self sendEventWithName:@"BleManagerDiscoverPeripheral" body:[peripheral asDictionary]];
    }
}

RCT_EXPORT_METHOD(connect:(NSString *)peripheralUUID callback:(nonnull RCTResponseSenderBlock)callback)
{
    NSLog(@"Connect");
    
    [self enqueueCommand:^{
        if ([self handledInvalidState:callback]) {
            [self completedCommand];
            return;
        }
        
        CBPeripheral *peripheral = [self findPeripheralByUUID:peripheralUUID];
        if (peripheral == nil) {
            // Try to retrieve the peripheral
            NSLog(@"Retrieving peripheral with UUID : %@", peripheralUUID);
            NSUUID *uuid = [[NSUUID alloc]initWithUUIDString:peripheralUUID];
            if (uuid != nil) {
                NSArray<CBPeripheral *> *peripheralArray = [manager retrievePeripheralsWithIdentifiers:@[uuid]];
                if([peripheralArray count] > 0){
                    peripheral = [peripheralArray objectAtIndex:0];
                    @synchronized(peripherals) {
                        [peripherals addObject:peripheral];
                    }
                    NSLog(@"Successfull retrieved peripheral with UUID : %@", peripheralUUID);
                }
            } else {
                NSString *error = [NSString stringWithFormat:@"Wrong UUID format %@", peripheralUUID];
                callback(@[error, [NSNull null]]);
                [self completedCommand];
                return;
            }
        }
        if (peripheral) {
            NSLog(@"Connecting to peripheral with UUID : %@", peripheralUUID);
            
            connectCallback = callback;
            [manager connectPeripheral:peripheral options:nil];
            
        } else {
            NSString *error = [NSString stringWithFormat:@"Could not find peripheral %@.", peripheralUUID];
            NSLog(@"%@", error);
            callback(@[error, [NSNull null]]);
            [self completedCommand];
        }
    }];
}

RCT_EXPORT_METHOD(disconnect:(NSString *)peripheralUUID force:(BOOL)force callback:(nonnull RCTResponseSenderBlock)callback)
{
    if ([self handledInvalidState:callback]) return;
    
    CBPeripheral *peripheral = [self findPeripheralByUUID:peripheralUUID];
    if (peripheral) {
        NSLog(@"Disconnecting from peripheral with UUID : %@", peripheralUUID);
        
        if (peripheral.services != nil) {
            for (CBService *service in peripheral.services) {
                if (service.characteristics != nil) {
                    for (CBCharacteristic *characteristic in service.characteristics) {
                        if (characteristic.isNotifying) {
                            NSLog(@"Remove notification from: %@", characteristic.UUID);
                            [peripheral setNotifyValue:NO forCharacteristic:characteristic];
                        }
                    }
                }
            }
        }
        
        [manager cancelPeripheralConnection:peripheral];
        callback(@[]);
        
    } else {
        NSString *error = [NSString stringWithFormat:@"Could not find peripheral %@.", peripheralUUID];
        NSLog(@"%@", error);
        callback(@[error]);
    }
}

RCT_EXPORT_METHOD(checkState)
{
    if (manager != nil){
        [self centralManagerDidUpdateState:self.manager];
    }
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    NSString *errorStr = [NSString stringWithFormat:@"Peripheral connection failure: %@. (%@)", peripheral, [error localizedDescription]];
    NSLog(@"%@", errorStr);

    dispatch_async(commandDispatch, ^{
        if (connectCallback) {
            connectCallback(@[errorStr]);
            connectCallback = nil;
            [self completedCommand];
        }
    });
}

RCT_EXPORT_METHOD(write:(NSString *)deviceUUID serviceUUID:(NSString*)serviceUUID  characteristicUUID:(NSString*)characteristicUUID message:(NSArray*)message maxByteSize:(NSInteger)maxByteSize callback:(nonnull RCTResponseSenderBlock)callback)
{
    NSLog(@"Write");
    
    [self enqueueCommand:^{
        if ([self handledInvalidState:callback]) {
            [self completedCommand];
            return;
        }
        
        BLECommandContext *context = [self getData:deviceUUID serviceUUIDString:serviceUUID characteristicUUIDString:characteristicUUID prop:CBCharacteristicPropertyWrite callback:callback];
        
        unsigned long c = [message count];
        uint8_t *bytes = malloc(sizeof(*bytes) * c);
        
        unsigned i;
        for (i = 0; i < c; i++)
        {
            NSNumber *number = [message objectAtIndex:i];
            int byte = [number intValue];
            bytes[i] = byte;
        }
        NSData *dataMessage = [NSData dataWithBytesNoCopy:bytes length:c freeWhenDone:YES];
        
        if (context) {
            RCTLogInfo(@"Message to write(%lu): %@ ", (unsigned long)[message count], message);
            CBPeripheral *peripheral = [context peripheral];
            CBCharacteristic *characteristic = [context characteristic];
            
            writeCallback = callback;
            
            RCTLogInfo(@"Message to write(%lu): %@ ", (unsigned long)[dataMessage length], [dataMessage hexadecimalString]);
            if ([dataMessage length] > maxByteSize) {
                int dataLength = (int)dataMessage.length;
                int count = 0;
                NSData* firstMessage;
                while(count < dataLength && (dataLength - count > maxByteSize)){
                    if (count == 0){
                        firstMessage = [dataMessage subdataWithRange:NSMakeRange(count, maxByteSize)];
                    }else{
                        NSData* splitMessage = [dataMessage subdataWithRange:NSMakeRange(count, maxByteSize)];
                        [writeQueue addObject:splitMessage];
                    }
                    count += maxByteSize;
                }
                if (count < dataLength) {
                    NSData* splitMessage = [dataMessage subdataWithRange:NSMakeRange(count, dataLength - count)];
                    [writeQueue addObject:splitMessage];
                }
                NSLog(@"Queued splitted message: %lu", (unsigned long)[writeQueue count]);
                [peripheral writeValue:firstMessage forCharacteristic:characteristic type:CBCharacteristicWriteWithResponse];
            } else {
                [peripheral writeValue:dataMessage forCharacteristic:characteristic type:CBCharacteristicWriteWithResponse];
            }
        } else {
            [self completedCommand];
        }
    }];
}


RCT_EXPORT_METHOD(writeWithoutResponse:(NSString *)deviceUUID serviceUUID:(NSString*)serviceUUID  characteristicUUID:(NSString*)characteristicUUID message:(NSArray*)message maxByteSize:(NSInteger)maxByteSize queueSleepTime:(NSInteger)queueSleepTime callback:(nonnull RCTResponseSenderBlock)callback)
{
    NSLog(@"writeWithoutResponse");
    
    if ([self handledInvalidState:callback]) return;
    
    BLECommandContext *context = [self getData:deviceUUID serviceUUIDString:serviceUUID characteristicUUIDString:characteristicUUID prop:CBCharacteristicPropertyWriteWithoutResponse callback:callback];
    unsigned long c = [message count];
    uint8_t *bytes = malloc(sizeof(*bytes) * c);
    
    unsigned i;
    for (i = 0; i < c; i++)
    {
        NSNumber *number = [message objectAtIndex:i];
        int byte = [number intValue];
        bytes[i] = byte;
    }
    NSData *dataMessage = [NSData dataWithBytesNoCopy:bytes length:c freeWhenDone:YES];
    if (context) {
        if ([dataMessage length] > maxByteSize) {
            NSUInteger length = [dataMessage length];
            NSUInteger offset = 0;
            CBPeripheral *peripheral = [context peripheral];
            CBCharacteristic *characteristic = [context characteristic];
            
            do {
                NSUInteger thisChunkSize = length - offset > maxByteSize ? maxByteSize : length - offset;
                NSData* chunk = [NSData dataWithBytesNoCopy:(char *)[dataMessage bytes] + offset length:thisChunkSize freeWhenDone:NO];
                
                offset += thisChunkSize;
                [peripheral writeValue:chunk forCharacteristic:characteristic type:CBCharacteristicWriteWithoutResponse];
		NSTimeInterval sleepTimeSeconds = (NSTimeInterval) queueSleepTime / 1000;
                [NSThread sleepForTimeInterval: sleepTimeSeconds];
            } while (offset < length);
            
            NSLog(@"Message to write(%lu): %@ ", (unsigned long)[dataMessage length], [dataMessage hexadecimalString]);
            callback(@[]);
        } else {
            
            CBPeripheral *peripheral = [context peripheral];
            CBCharacteristic *characteristic = [context characteristic];
            
            NSLog(@"Message to write(%lu): %@ ", (unsigned long)[dataMessage length], [dataMessage hexadecimalString]);
            [peripheral writeValue:dataMessage forCharacteristic:characteristic type:CBCharacteristicWriteWithoutResponse];
            callback(@[]);
        }
    }
}


RCT_EXPORT_METHOD(read:(NSString *)deviceUUID serviceUUID:(NSString*)serviceUUID  characteristicUUID:(NSString*)characteristicUUID callback:(nonnull RCTResponseSenderBlock)callback)
{
    NSLog(@"read");
    
    [self enqueueCommand:^{
        if ([self handledInvalidState:callback]) {
            [self completedCommand];
            return;
        }
        
        BLECommandContext *context = [self getData:deviceUUID serviceUUIDString:serviceUUID characteristicUUIDString:characteristicUUID prop:CBCharacteristicPropertyRead callback:callback];
        if (context) {
            
            CBPeripheral *peripheral = [context peripheral];
            CBCharacteristic *characteristic = [context characteristic];
                    
            NSString *key = [self keyForPeripheral: peripheral andCharacteristic:characteristic];
            
            readCallback = callback;
            readCallbackKey = key;
            [peripheral readValueForCharacteristic:characteristic];  // callback sends value
        } else {
            [self completedCommand];
        }
    }];
}

RCT_EXPORT_METHOD(readRSSI:(NSString *)deviceUUID callback:(nonnull RCTResponseSenderBlock)callback)
{
    NSLog(@"readRSSI");
    
    [self enqueueCommand: ^{
        if ([self handledInvalidState:callback]) {
            [self completedCommand];
            return;
        }
        
        CBPeripheral *peripheral = [self findPeripheralByUUID:deviceUUID];
        
        if (peripheral && peripheral.state == CBPeripheralStateConnected) {
            readRSSICallback = callback;
            [peripheral readRSSI];
        } else {
            callback(@[@"Peripheral not found or not connected"]);
            [self completedCommand];
        }
    }];
}

RCT_EXPORT_METHOD(retrieveServices:(NSString *)deviceUUID services:(NSArray<NSString *> *)services callback:(nonnull RCTResponseSenderBlock)callback)
{
    NSLog(@"retrieveServices %@", services);
    
    [self enqueueCommand:^{
        if ([self handledInvalidState:callback]) {
            [self completedCommand];
            return;
        }
        
        CBPeripheral *peripheral = [self findPeripheralByUUID:deviceUUID];
        
        if (peripheral && peripheral.state == CBPeripheralStateConnected) {
            retrieveServicesCallback = callback;

            NSMutableArray<CBUUID *> *uuids = [NSMutableArray new];
            for ( NSString *string in services ) {
                CBUUID *uuid = [CBUUID UUIDWithString:string];
                [uuids addObject:uuid];
            }
            
            if ( uuids.count > 0 ) {
                [peripheral discoverServices:uuids];
            } else {
                [peripheral discoverServices:nil];
            }
            
        } else {
            callback(@[@"Peripheral not found or not connected"]);
            [self completedCommand];
        }
    }];
}

RCT_EXPORT_METHOD(startNotification:(NSString *)deviceUUID serviceUUID:(NSString*)serviceUUID  characteristicUUID:(NSString*)characteristicUUID callback:(nonnull RCTResponseSenderBlock)callback)
{
    NSLog(@"startNotification");
    
    [self enqueueCommand: ^{
        if ([self handledInvalidState:callback]) {
            [self completedCommand];
            return;
        }
        
        BLECommandContext *context = [self getData:deviceUUID serviceUUIDString:serviceUUID characteristicUUIDString:characteristicUUID prop:CBCharacteristicPropertyNotify callback:callback];
        
        if (context) {
            CBPeripheral *peripheral = [context peripheral];
            CBCharacteristic *characteristic = [context characteristic];
            
            NSString *key = [self keyForPeripheral: peripheral andCharacteristic:characteristic];
            notificationCallbackKey = key;
            notificationCallback = callback;
            
            [peripheral setNotifyValue:YES forCharacteristic:characteristic];
        } else {
            [self completedCommand];
        }
    }];
}

RCT_EXPORT_METHOD(stopNotification:(NSString *)deviceUUID serviceUUID:(NSString*)serviceUUID  characteristicUUID:(NSString*)characteristicUUID callback:(nonnull RCTResponseSenderBlock)callback)
{
    NSLog(@"stopNotification");
    
    [self enqueueCommand: ^{
        if ([self handledInvalidState:callback]) {
            [self completedCommand];
            return;
        }
        
        BLECommandContext *context = [self getData:deviceUUID serviceUUIDString:serviceUUID characteristicUUIDString:characteristicUUID prop:CBCharacteristicPropertyNotify callback:callback];
        
        if (context) {
            CBPeripheral *peripheral = [context peripheral];
            CBCharacteristic *characteristic = [context characteristic];
            
            if ([characteristic isNotifying]){
                NSString *key = [self keyForPeripheral: peripheral andCharacteristic:characteristic];
                
                notificationCallbackKey = key;
                notificationCallback = callback;
                [peripheral setNotifyValue:NO forCharacteristic:characteristic];
                NSLog(@"Characteristic stopped notifying");
            } else {
                NSLog(@"Characteristic is not notifying");
                callback(@[]);
                [self completedCommand];
            }
            
        } else {
            [self completedCommand];
        }
    }];
    
}

RCT_EXPORT_METHOD(enableBluetooth:(nonnull RCTResponseSenderBlock)callback)
{
    callback(@[@"Not supported"]);
}

RCT_EXPORT_METHOD(getBondedPeripherals:(nonnull RCTResponseSenderBlock)callback)
{
    callback(@[@"Not supported"]);
}

RCT_EXPORT_METHOD(createBond:(NSString *)deviceUUID devicePin:(NSString *)devicePin callback:(nonnull RCTResponseSenderBlock)callback)
{
    callback(@[@"Not supported"]);
}

RCT_EXPORT_METHOD(removeBond:(NSString *)deviceUUID callback:(nonnull RCTResponseSenderBlock)callback)
{
    callback(@[@"Not supported"]);
}

RCT_EXPORT_METHOD(removePeripheral:(NSString *)deviceUUID callback:(nonnull RCTResponseSenderBlock)callback)
{
    callback(@[@"Not supported"]);
}

RCT_EXPORT_METHOD(requestMTU:(NSString *)deviceUUID mtu:(NSInteger)mtu callback:(nonnull RCTResponseSenderBlock)callback)
{
    callback(@[@"Not supported"]);
}

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    NSLog(@"didWrite");
    
    dispatch_async(commandDispatch, ^{
        if (writeCallback) {
            if (error) {
                NSLog(@"%@", error);
                [writeQueue removeAllObjects];
                writeCallback(@[error.localizedDescription]);
                writeCallback = nil;
                [self completedCommand];
            } else {
                if ([writeQueue count] == 0) {
                    writeCallback(@[]);
                    writeCallback = nil;
                    [self completedCommand];
                } else {
                    // Remove and write the queud message
                    NSData *message = [writeQueue objectAtIndex:0];
                    [writeQueue removeObjectAtIndex:0];
                    [peripheral writeValue:message forCharacteristic:characteristic type:CBCharacteristicWriteWithResponse];
                }
                
            }
        }
    });
}


- (void)peripheral:(CBPeripheral*)peripheral didReadRSSI:(NSNumber*)rssi error:(NSError*)error {
    NSLog(@"didReadRSSI %@", rssi);
    
    dispatch_async(commandDispatch, ^{
        if (readRSSICallback) {
            readRSSICallback(@[[NSNull null], [NSNumber numberWithInteger:[rssi integerValue]]]);
            readRSSICallback = nil;
            [self completedCommand];
        }
    });
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    NSLog(@"Peripheral Connected: %@", [peripheral uuidAsString]);
    peripheral.delegate = self;
    
    // The state of the peripheral isn't necessarily updated until a small delay after didConnectPeripheral is called
    // and in the meantime didFailToConnectPeripheral may be called
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.002 * NSEC_PER_SEC),
                   commandDispatch, ^(void){
        [writeQueue removeAllObjects];
        [retrieveServicesLatch removeAllObjects];
        
        // didFailToConnectPeripheral should have been called already if not connected by now
        
        if (connectCallback) {
            connectCallback(@[[NSNull null], [peripheral asDictionary]]);
            connectCallback = nil;
            [self completedCommand];
        }
        
        if (hasListeners) {
            [self sendEventWithName:@"BleManagerConnectPeripheral" body:@{@"peripheral": [peripheral uuidAsString]}];
        }
    });

}

- (void)cancelAllCommands:(NSString*) errorStr
{
    bool canceledCommand = false;

    if (connectCallback) {
        connectCallback(@[errorStr]);
        connectCallback = nil;
        canceledCommand = true;
    }
    
    if (readRSSICallback) {
        readRSSICallback(@[errorStr]);
        readRSSICallback = nil;
        canceledCommand = true;
    }
    
    if (retrieveServicesCallback) {
        retrieveServicesCallback(@[errorStr]);
        retrieveServicesCallback = nil;
        canceledCommand = true;
    }
    
    if (readCallback) {
        readCallback(@[errorStr]);
        readCallback = nil;
        canceledCommand = true;
    }
    
    if (writeCallback) {
        writeCallback(@[errorStr]);
        writeCallback = nil;
        canceledCommand = true;
    }
    
    if (notificationCallback) {
        notificationCallback(@[errorStr]);
        notificationCallback = nil;
        canceledCommand = true;
    }
    
    if (canceledCommand) {
        [self completedCommand];
    }
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    NSLog(@"Peripheral Disconnected: %@", [peripheral uuidAsString]);
    
    if (error) {
        NSLog(@"Error: %@", error);
    }
    
    dispatch_async(commandDispatch, ^{
        NSString *peripheralUUIDString = [peripheral uuidAsString];
           
        NSString *errorStr = [NSString stringWithFormat:@"Peripheral did disconnect: %@", peripheralUUIDString];
        
        [self cancelAllCommands:errorStr];
        
        if (hasListeners) {
            if (error) {
                [self sendEventWithName:@"BleManagerDisconnectPeripheral" body:@{@"peripheral": [peripheral uuidAsString], @"domain": [error domain], @"code": @(error.code)}];
            } else {
                [self sendEventWithName:@"BleManagerDisconnectPeripheral" body:@{@"peripheral": [peripheral uuidAsString]}];
            }
        }
    });
}

- (void) handleDiscoverServiceError:(NSError *)error
{
    NSLog(@"Error: %@", error);
    [retrieveServicesLatch removeAllObjects];
    dispatch_async(commandQueue, ^{
        if (retrieveServicesCallback != nil) {
            retrieveServicesCallback(@[error, [NSNull null]]);
            retrieveServicesCallback = nil;
            [self completedCommand];
        }
    });
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    if (error) {
        [self handleDiscoverServiceError:error];
        return;
    }
    NSLog(@"Services Discover");
    
    [retrieveServicesLatch addObjectsFromArray:peripheral.services];
    for (CBService *service in peripheral.services) {
        NSLog(@"Service %@ %@", service.UUID, service.description);
        [peripheral discoverIncludedServices:nil forService:service]; // discover included services
        [peripheral discoverCharacteristics:nil forService:service]; // discover characteristics for service
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverIncludedServicesForService:(CBService *)service error:(NSError *)error {
    if (error) {
        [self handleDiscoverServiceError:error];
        return;
    }
    [peripheral discoverCharacteristics:nil forService:service]; // discover characteristics for included service
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    if (error) {
        [self handleDiscoverServiceError:error];
        return;
    }
    NSLog(@"Characteristics For Service Discover");
    
    NSString *peripheralUUIDString = [peripheral uuidAsString];
    [retrieveServicesLatch removeObject:service];
    
    if ([retrieveServicesLatch count] == 0) {
        dispatch_async(commandDispatch, ^{
            
            // Call success callback for connect
            if (retrieveServicesCallback) {
                retrieveServicesCallback(@[[NSNull null], [peripheral asDictionary]]);
                NSLog(@"Finished retrieveServices");
                retrieveServicesCallback = nil;
                [self completedCommand];
            }
            
        });
    }
}

// Find a characteristic in service with a specific property
-(CBCharacteristic *) findCharacteristicFromUUID:(CBUUID *)UUID service:(CBService*)service prop:(CBCharacteristicProperties)prop
{
    NSLog(@"Looking for %@ with properties %lu", UUID, (unsigned long)prop);
    for(int i=0; i < service.characteristics.count; i++)
    {
        CBCharacteristic *c = [service.characteristics objectAtIndex:i];
        if ((c.properties & prop) != 0x0 && [c.UUID.UUIDString isEqualToString: UUID.UUIDString]) {
            NSLog(@"Found %@", UUID);
            return c;
        }
    }
    return nil; //Characteristic with prop not found on this service
}

// Find a characteristic in service by UUID
-(CBCharacteristic *) findCharacteristicFromUUID:(CBUUID *)UUID service:(CBService*)service
{
    NSLog(@"Looking for %@", UUID);
    for(int i=0; i < service.characteristics.count; i++)
    {
        CBCharacteristic *c = [service.characteristics objectAtIndex:i];
        if ([c.UUID.UUIDString isEqualToString: UUID.UUIDString]) {
            NSLog(@"Found %@", UUID);
            return c;
        }
    }
    return nil; //Characteristic not found on this service
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    // Make sure we transition in the commandDispatch
    dispatch_async(commandDispatch, ^{
        // Change blueooth state, future commands should then give a result based on this if disabling
        NSString *stateName = [self centralManagerStateToString:central.state];
        isBluetoothEnabled = @(central.state == CBManagerStatePoweredOn);
        if (hasListeners) {
            [self sendEventWithName:@"BleManagerDidUpdateState" body:@{@"state":stateName}];
        }
        // Invoke all callbacks to handle in-flight commands
        NSString *errorStr = @"Bluetooth has been disabled!";
        [self cancelAllCommands:errorStr];
    });
}

// expecting deviceUUID, serviceUUID, characteristicUUID in command.arguments
-(BLECommandContext*) getData:(NSString*)deviceUUIDString  serviceUUIDString:(NSString*)serviceUUIDString characteristicUUIDString:(NSString*)characteristicUUIDString prop:(CBCharacteristicProperties)prop callback:(nonnull RCTResponseSenderBlock)callback
{
    CBUUID *serviceUUID = [CBUUID UUIDWithString:serviceUUIDString];
    CBUUID *characteristicUUID = [CBUUID UUIDWithString:characteristicUUIDString];
    
    CBPeripheral *peripheral = [self findPeripheralByUUID:deviceUUIDString];
    
    if (!peripheral) {
        NSString* err = [NSString stringWithFormat:@"Could not find peripherial with UUID %@", deviceUUIDString];
        NSLog(@"Could not find peripherial with UUID %@", deviceUUIDString);
        callback(@[err]);
        
        return nil;
    }
    
    CBService *service = [self findServiceFromUUID:serviceUUID p:peripheral];
    
    if (!service)
    {
        NSString* err = [NSString stringWithFormat:@"Could not find service with UUID %@ on peripheral with UUID %@",
                         serviceUUIDString,
                         peripheral.identifier.UUIDString];
        NSLog(@"Could not find service with UUID %@ on peripheral with UUID %@",
              serviceUUIDString,
              peripheral.identifier.UUIDString);
        callback(@[err]);
        return nil;
    }
    
    CBCharacteristic *characteristic = [self findCharacteristicFromUUID:characteristicUUID service:service prop:prop];
    
    // Special handling for INDICATE. If charateristic with notify is not found, check for indicate.
    if (prop == CBCharacteristicPropertyNotify && !characteristic) {
        characteristic = [self findCharacteristicFromUUID:characteristicUUID service:service prop:CBCharacteristicPropertyIndicate];
    }
    
    // As a last resort, try and find ANY characteristic with this UUID, even if it doesn't have the correct properties
    if (!characteristic) {
        characteristic = [self findCharacteristicFromUUID:characteristicUUID service:service];
    }
    
    if (!characteristic)
    {
        NSString* err = [NSString stringWithFormat:@"Could not find characteristic with UUID %@ on service with UUID %@ on peripheral with UUID %@", characteristicUUIDString,serviceUUIDString, peripheral.identifier.UUIDString];
        NSLog(@"Could not find characteristic with UUID %@ on service with UUID %@ on peripheral with UUID %@",
              characteristicUUIDString,
              serviceUUIDString,
              peripheral.identifier.UUIDString);
        callback(@[err]);
        return nil;
    }
    
    BLECommandContext *context = [[BLECommandContext alloc] init];
    [context setPeripheral:peripheral];
    [context setService:service];
    [context setCharacteristic:characteristic];
    return context;
    
}

-(NSString *) keyForPeripheral: (CBPeripheral *)peripheral andCharacteristic:(CBCharacteristic *)characteristic {
    return [NSString stringWithFormat:@"%@|%@", [peripheral uuidAsString], [characteristic UUID]];
}

-(void)centralManager:(CBCentralManager *)central willRestoreState:(NSDictionary<NSString *,id> *)dict
{
    NSArray<CBPeripheral *> *restoredPeripherals = dict[CBCentralManagerRestoredStatePeripheralsKey];

    if (restoredPeripherals.count > 0) {
        @synchronized(peripherals) {
            peripherals = [restoredPeripherals mutableCopy];

            NSMutableArray *data = [NSMutableArray new];
            for (CBPeripheral *peripheral in peripherals) {
                [data addObject:[peripheral asDictionary]];
            }

            [self sendEventWithName:@"BleManagerCentralManagerWillRestoreState" body:@{@"peripherals": data}];
        }
    }
}

+(CBCentralManager *)getCentralManager
{
    return _sharedManager;
}

+(BleManager *)getInstance
{
    return _instance;
}

@end
