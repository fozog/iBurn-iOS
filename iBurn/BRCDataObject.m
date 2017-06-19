//
//  BRCDataObject.m
//  iBurn
//
//  Created by Christopher Ballinger on 7/28/14.
//  Copyright (c) 2014 Burning Man Earth. All rights reserved.
//

#import "BRCDataObject.h"
#import "BRCDataObject_Private.h"
#import "BRCAppDelegate.h"
#import "BRCArtObject.h"
#import "BRCEventObject.h"
#import "BRCCampObject.h"

@interface BRCDataObject()
@property (nonatomic, readonly) CLLocationDegrees latitude;
@property (nonatomic, readonly) CLLocationDegrees longitude;
@end

@implementation BRCDataObject
@dynamic location;
@dynamic coordinate;

+ (NSDictionary *)JSONKeyPathsByPropertyKey {
    return @{NSStringFromSelector(@selector(title)): @"name",
             NSStringFromSelector(@selector(uniqueID)): @"uid",
             NSStringFromSelector(@selector(detailDescription)): @"description",
             NSStringFromSelector(@selector(email)): @"contact_email",
             NSStringFromSelector(@selector(url)): @"url",
             NSStringFromSelector(@selector(latitude)): @"location.gps_latitude",
             NSStringFromSelector(@selector(longitude)): @"location.gps_longitude",
             NSStringFromSelector(@selector(year)): @"year",
             NSStringFromSelector(@selector(playaLocation)): @"location.string"};
}

- (CLLocation*) location {
    CLLocationCoordinate2D coordinate = self.coordinate;
    if (!CLLocationCoordinate2DIsValid(coordinate)) {
        return nil;
    }
    return [[CLLocation alloc] initWithLatitude:coordinate.latitude longitude:coordinate.longitude];
}

- (CLLocationCoordinate2D) coordinate {
    if (_latitude == 0 || _longitude == 0) {
        return kCLLocationCoordinate2DInvalid;
    }
    return CLLocationCoordinate2DMake(_latitude, _longitude);
}

- (void) setCoordinate:(CLLocationCoordinate2D)coordinate {
    if (!CLLocationCoordinate2DIsValid(coordinate)) {
        return;
    }
    _latitude = coordinate.latitude;
    _longitude = coordinate.longitude;
}

- (void)setNilValueForKey:(NSString *)key {
    if (NSStringFromSelector(@selector(latitude))) {
        _latitude = 0;
    } else if (NSStringFromSelector(@selector(longitude))) {
        _longitude = 0;
    } else {
        [super setNilValueForKey:key];
    }
}

+ (NSValueTransformer *)urlJSONTransformer {
    return [NSValueTransformer valueTransformerForName:MTLURLValueTransformerName];
}

+ (NSString *)yapCollection
{
    return NSStringFromClass(self.class);
}

- (CLLocationDistance) distanceFromLocation:(CLLocation*)location {
    CLLocation *objectLocation = self.location;
    if (!location || !objectLocation) {
        return CLLocationDistanceMax;
    }
    CLLocationDistance distance = [location distanceFromLocation:objectLocation];
    return distance;
}

/// Determines how the +propertyKeys of the class are encoded into an archive.
/// The values of this dictionary should be boxed MTLModelEncodingBehavior
/// values.
///
/// Any keys not present in the dictionary will be excluded from the archive.
///
/// Subclasses overriding this method should combine their values with those of
/// `super`.
///
/// Returns a dictionary mapping the receiver's +propertyKeys to default encoding
/// behaviors. If a property is an object with `weak` semantics, the default
/// behavior is MTLModelEncodingBehaviorConditional; otherwise, the default is
/// MTLModelEncodingBehaviorUnconditional.
+ (NSDictionary *)encodingBehaviorsByPropertyKey {
    NSMutableDictionary *behaviors = [[super encodingBehaviorsByPropertyKey] mutableCopy];
    // these properties are dynamically generated
    [behaviors setObject:@(MTLModelEncodingBehaviorExcluded) forKey:NSStringFromSelector(@selector(coordinate))];
    [behaviors setObject:@(MTLModelEncodingBehaviorExcluded) forKey:NSStringFromSelector(@selector(location))];
    [behaviors setObject:@(MTLModelEncodingBehaviorExcluded) forKey:NSStringFromSelector(@selector(yapKey))];
    [behaviors setObject:@(MTLModelEncodingBehaviorExcluded) forKey:NSStringFromSelector(@selector(brc_markerImage))];
    return behaviors;
}

- (NSString*) yapKey {
    return _uniqueID;
}

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [transaction setObject:self forKey:self.yapKey inCollection:self.class.yapCollection];
}

- (void)removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [transaction removeObjectForKey:self.yapKey inCollection:self.class.yapCollection];
}

- (void)touchWithTransaction:(YapDatabaseReadWriteTransaction *)transaction {
    [transaction touchObjectForKey:self.yapKey inCollection:self.class.yapCollection];
}

/** This will fetch an updated instance of the object */
- (nullable instancetype)refetchWithTransaction:(nonnull YapDatabaseReadTransaction *)transaction {
    id object = [self.class fetchObjectWithYapKey:self.yapKey transaction:transaction];
    return object;
}

+ (nullable instancetype) fetchObjectWithYapKey:(NSString *)yapKey transaction:(YapDatabaseReadTransaction *)transaction {
    NSParameterAssert(yapKey);
    NSParameterAssert(transaction);
    if (!yapKey || !transaction) {
        return nil;
    }
    id object = [transaction objectForKey:yapKey inCollection:self.yapCollection];
    if ([object isKindOfClass:self]) {
        return object;
    }
    return nil;
}

@end

@implementation BRCDataObject (MarkerImage)

- (UIImage*) brc_markerImage {
    UIImage *markerImage = nil;
    Class dataObjectClass = [self class];
    if (dataObjectClass == [BRCArtObject class]) {
        markerImage = [UIImage imageNamed:@"BRCBluePin"];
    } else if (dataObjectClass == [BRCEventObject class]) {
        BRCEventObject *eventObject = (BRCEventObject*)self;
        markerImage = [eventObject markerImageForEventStatus:[NSDate date]];
    } else if (dataObjectClass == [BRCCampObject class]) {
        markerImage = [UIImage imageNamed:@"BRCPurplePin"];
    } else {
        markerImage = [UIImage imageNamed:@"BRCPurplePin"];
    }
    return markerImage;
}

@end
