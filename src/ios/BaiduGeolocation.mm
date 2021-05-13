//
//  BaiduMapLocation.mm
//
//  Created by LiuRui on 2017/2/25.
//

#import "BaiduGeolocation.h"
#import <BaiduMapAPI_Base/BMKBaseComponent.h>

#define __NeedReGeocode        @"NeedReGeocode"
#define __LocationDate         @"LocationDate"
#define __LocationInfo         @"LocationInfo"

@interface BaiduGeolocation ()

@property(nonatomic, assign) BOOL locationOnce;
@property(nonatomic, assign) BOOL needReGeocode; // 反编码
@property(nonatomic, assign) BOOL needAltitude; // 海拔
@property(nonatomic, strong) NSString *locationType; // 坐标类型
@property(nonatomic, strong) NSMutableDictionary *locationDic;// 存放
@property(nonatomic, strong) NSMutableArray *watchIDArr;

@end

@implementation BaiduGeolocation

- (void)pluginInitialize
{
    NSString* IOS_API_KEY = [self.commandDelegate settings][@"ios_api_key"];

    [[BMKLocationAuth sharedInstance] checkPermisionWithKey:IOS_API_KEY authDelegate:nil];
    [[[BMKMapManager alloc]init] start:IOS_API_KEY generalDelegate:nil];
    _data = [[NSMutableDictionary alloc] init];

    _geoCodeSerch = [[BMKGeoCodeSearch alloc] init];
    _geoCodeSerch.delegate = self;
    
    _locService = [[BMKLocationManager alloc] init];
    _locService.delegate = self;
    _locService.locationTimeout = 10;
    _locService.reGeocodeTimeout = 10;
}

- (void)dealCommand:(CDVInvokedUrlCommand*)command
{
    NSArray *arguments = command.arguments;
    if (arguments.count > 0) {
        NSDictionary *dic = [NSDictionary dictionaryWithDictionary:[arguments objectAtIndex:0]];
        
        self.needReGeocode = [[dic objectForKey:@"withReGeocode"] boolValue];
        self.needAltitude = [[dic objectForKey:@"altitude"] boolValue];
        
        double timeOut = [[NSString stringWithFormat:@"%@", [dic objectForKey:@"timeout"]] doubleValue]/1000;
        if (timeOut > 0) {
            _locService.locationTimeout = timeOut;
        }
        // 定位类型
        self.locationType = [NSString stringWithFormat:@"%@", [dic objectForKey:@"type"]];
        if ([self.locationType isEqualToString:@"BD09LL"]) {
            _locService.coordinateType = BMKLocationCoordinateTypeBMK09LL;
            [BMKMapManager setCoordinateTypeUsedInBaiduMapSDK:BMK_COORDTYPE_BD09LL];
        } else if ([self.locationType isEqualToString:@"BD09MC"]) {
            _locService.coordinateType = BMKLocationCoordinateTypeBMK09MC;
            [BMKMapManager setCoordinateTypeUsedInBaiduMapSDK:BMK_COORDTYPE_BD09LL];
        } else { // GCJ02
            self.locationType = @"GCJ02";
            _locService.coordinateType = BMKLocationCoordinateTypeGCJ02;
            [BMKMapManager setCoordinateTypeUsedInBaiduMapSDK:BMK_COORDTYPE_COMMON];
        }
        // 缓存过期时间
        NSString *maximumAge = [NSString stringWithFormat:@"%@", [dic objectForKey:@"maximumAge"]];
        NSTimeInterval maxTimeInterval = [maximumAge doubleValue]/1000;
        if (self.locationDic.count > 0 && self.locationOnce) {
            NSDate *locationDate = [self.locationDic objectForKey:[self.locationType stringByAppendingString:__LocationDate]];
            NSTimeInterval timeInterval = [[NSDate date] timeIntervalSinceDate:locationDate];
            if (timeInterval < maxTimeInterval) {
                NSString *dataKey = [self.locationType stringByAppendingString:__LocationInfo];
                if (self.needReGeocode) {
                    dataKey = [dataKey stringByAppendingString:__NeedReGeocode];
                }
                NSDictionary *dataDic = [NSMutableDictionary dictionaryWithDictionary:[self.locationDic objectForKey:dataKey]];
                if (dataDic.count > 0) {
                    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:dataDic];
                    [result setKeepCallbackAsBool:TRUE];
                    [self.commandDelegate sendPluginResult:result callbackId:_execCommand.callbackId];
                    self.locationOnce = NO;
                    return;
                }
            }
        }
        [_locService startUpdatingLocation];
        // 精度
        BOOL accuracy = [[dic objectForKey:@"enableHighAccuracy"] boolValue];
        if (accuracy) {
            _locService.desiredAccuracy = kCLLocationAccuracyBest;
        } else {
            _locService.desiredAccuracy = kCLLocationAccuracyHundredMeters;
        }
    }
}

- (void)getCurrentPosition:(CDVInvokedUrlCommand*)command
{
    self.locationOnce = YES;
    _execCommand = command;
    [self dealCommand:command];
}

- (void)watchPosition:(CDVInvokedUrlCommand *)command
{
    self.locationOnce = NO;
    _execCommand = command;
    NSArray *arguments = command.arguments;
    NSString *tmpWatchId = [NSString stringWithFormat:@"%@", [arguments objectAtIndex:1]];
    [self.watchIDArr addObject:tmpWatchId];
    [self dealCommand:command];
}

- (void)clearWatch:(CDVInvokedUrlCommand *)command
{
    NSArray *arguments = command.arguments;
    if (arguments.count > 1) {
        NSString *tmpWatchId = [NSString stringWithFormat:@"%@", [arguments objectAtIndex:1]];
        if (tmpWatchId.length > 0) {
            [self.watchIDArr removeObject:tmpWatchId];
            if (self.watchIDArr.count == 0) {
                self.locationOnce = NO;
                _execCommand = nil;
                [_locService stopUpdatingLocation];
            }
            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:nil];
            [result setKeepCallbackAsBool:TRUE];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
            return;
        }
    }
    NSMutableDictionary* json = [[NSMutableDictionary alloc] init];
    [json setValue:@"100105" forKey:@"code"];
    [json setValue:@"定位关闭失败" forKey:@"message"];
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:json];
    [result setKeepCallbackAsBool:TRUE];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

#pragma mark - BMKLocationManagerDelegate
- (void)BMKLocationManager:(BMKLocationManager * _Nonnull)manager didFailWithError:(NSError * _Nullable)error
{
    if (error) {
        [self didFailToLocateUserWithError:error];
    }
}
// 用户位置更新后，会调用此函数
- (void)BMKLocationManager:(BMKLocationManager *)manager didUpdateLocation:(BMKLocation * _Nullable)location orError:(NSError * _Nullable)error
{
    if (error) {
        [self didFailToLocateUserWithError:error];
        if (self.locationOnce) {
            [_locService stopUpdatingLocation];
            _execCommand = nil;
        }
    } else {
        if(_execCommand != nil)
        {
            NSDate* time = location.location.timestamp;
            NSNumber* latitude = [NSNumber numberWithDouble:location.location.coordinate.latitude];
            NSNumber* longitude = [NSNumber numberWithDouble:location.location.coordinate.longitude];
            NSNumber* accuracy = [NSNumber numberWithDouble:location.location.horizontalAccuracy];

            NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
            [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
            
            [_data setValue:[dateFormatter stringFromDate:time] forKey:@"timestamp"];
            [_data setValue:latitude forKey:@"latitude"];
            [_data setValue:longitude forKey:@"longitude"];
            [_data setValue:accuracy forKey:@"accuracy"];

            CLLocationCoordinate2D pt = (CLLocationCoordinate2D){0, 0};
            if (latitude!= 0  && longitude!= 0){
                pt = (CLLocationCoordinate2D){
                    location.location.coordinate.latitude,
                    location.location.coordinate.longitude
                };
            }
            if (self.needReGeocode) {
                BMKReverseGeoCodeSearchOption *reverseGeoCodeOption = [[BMKReverseGeoCodeSearchOption alloc] init];
                if ([self.locationType isEqualToString:@"BD09MC"]) { // 墨卡托坐标转换
                    //设置一个目标经纬度
                    CLLocationCoordinate2D coodinate = location.location.coordinate;
                    BMKLocationCoordinateType srctype = BMKLocationCoordinateTypeBMK09MC;
                    BMKLocationCoordinateType destype = BMKLocationCoordinateTypeBMK09LL;
                    CLLocationCoordinate2D cood=[BMKLocationManager BMKLocationCoordinateConvert:coodinate SrcType:srctype DesType:destype];
                    reverseGeoCodeOption.location = cood;
                } else {
                    reverseGeoCodeOption.location = location.location.coordinate;
                }
                //是否访问最新版行政区划数据（仅对中国数据生效）
                reverseGeoCodeOption.isLatestAdmin = YES;
                [_geoCodeSerch reverseGeoCode:reverseGeoCodeOption];
            } else {
                CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:_data];
                [result setKeepCallbackAsBool:TRUE];
                [self.commandDelegate sendPluginResult:result callbackId:_execCommand.callbackId];
                [self saveLocationInfo:_data];
                if (self.locationOnce) {
                    [_locService stopUpdatingLocation];
                    _execCommand = nil;
                }
            }
        }
    }
}

- (void)saveLocationInfo:(NSMutableDictionary *)dic
{
    NSDictionary *infoDic = [NSDictionary dictionaryWithDictionary:dic];
    [_data removeAllObjects];
    NSString *dataKey = [self.locationType stringByAppendingString:__LocationInfo];
    if (self.needReGeocode) {
        dataKey = [dataKey stringByAppendingString:__NeedReGeocode];
    }
    [self.locationDic setValue:infoDic forKey:dataKey];
    [self.locationDic setValue:[NSDate date] forKey:[self.locationType stringByAppendingString:__LocationDate]];
    
}

- (void)BMKLocationManager:(BMKLocationManager * _Nonnull)manager
didUpdateNetworkState:(BMKLocationNetworkState)state orError:(NSError * _Nullable)error
{
    if (error) {
        [self didFailToLocateUserWithError:error];
    }
}

- (void)onGetReverseGeoCodeResult:(BMKGeoCodeSearch *)searcher result:(BMKReverseGeoCodeSearchResult *)result errorCode:(BMKSearchErrorCode)error
{
    if (error == 0) {
         BMKAddressComponent *component=[[BMKAddressComponent alloc]init];
         component=result.addressDetail;
                  
         NSString* countryCode = component.countryCode;
         NSString* country = component.country;
         //NSString* adCode = component.adCode;
         NSString* city = component.city;
         NSString* district = component.district;
         NSString* streetName = component.streetName;
         NSString* province = component.province;
         NSString* addr = result.address;
         NSString* sematicDescription = result.sematicDescription;
 
        [_data setValue:countryCode forKey:@"countryCode"];
        [_data setValue:country forKey:@"country"];
        [_data setValue:city forKey:@"city"];
        [_data setValue:district forKey:@"district"];
        [_data setValue:streetName forKey:@"street"];
        [_data setValue:province forKey:@"province"];
        [_data setValue:addr forKey:@"addr"];
        [_data setValue:sematicDescription forKey:@"locationDescribe"];

        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:_data];
        [result setKeepCallbackAsBool:TRUE];
        [self.commandDelegate sendPluginResult:result callbackId:_execCommand.callbackId];
        [self saveLocationInfo:_data];
    } else {
        [self didFailToLocateUserWithError:nil];
    }
    if (self.locationOnce) {
        [_locService stopUpdatingLocation];
        _execCommand = nil;
    }
}

- (void)didFailToLocateUserWithError:(NSError *)error
{
    if(_execCommand != nil)
    {
        NSMutableDictionary* json = [[NSMutableDictionary alloc] init];
        [json setValue:@"100204" forKey:@"code"];//[NSNumber numberWithInt:167]
        [json setValue:@"定位失败" forKey:@"message"];
        if (error.code == 2) {
            [json setValue:@"100106" forKey:@"code"];//[NSNumber numberWithInt:167]
            [json setValue:@"定位权限未开启" forKey:@"message"];
        }
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:json];
        [result setKeepCallbackAsBool:TRUE];
        [self.commandDelegate sendPluginResult:result callbackId:_execCommand.callbackId];
    }
}

- (NSMutableArray *)watchIDArr
{
    if (!_watchIDArr) {
        _watchIDArr = [NSMutableArray array];
    }
    return _watchIDArr;
}

- (NSMutableDictionary *)locationDic
{
    if (!_locationDic) {
        _locationDic = [NSMutableDictionary dictionary];
    }
    return _locationDic;;
}

- (void)onReset
{
    [self.watchIDArr removeAllObjects];
    [_locService stopUpdatingLocation];
    _execCommand = nil;
}

@end
