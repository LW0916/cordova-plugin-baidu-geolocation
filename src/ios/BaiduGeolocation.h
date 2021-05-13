//
//  BaiduMapLocation.h
//
//  Created by LiuRui on 2017/2/25.
//

#import <Cordova/CDV.h>

#import <BMKLocationkit/BMKLocationComponent.h>
#import <BaiduMapAPI_Search/BMKGeocodeSearch.h>


@interface BaiduGeolocation : CDVPlugin<BMKLocationManagerDelegate, BMKGeoCodeSearchDelegate> {
    BMKLocationManager* _locService;
    BMKGeoCodeSearch* _geoCodeSerch;
    CDVInvokedUrlCommand* _execCommand;
    NSMutableDictionary* _data;
}


- (void)getCurrentPosition:(CDVInvokedUrlCommand*)command;
- (void)watchPosition:(CDVInvokedUrlCommand*)command;
- (void)clearWatch:(CDVInvokedUrlCommand*)command;

@end
