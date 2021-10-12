//
//  MangoFixUtil.m
//  Easyder
//
//  Created by xuhonggui on 2020/4/9.
//  Copyright © 2020 xuhonggui. All rights reserved.
//

#import "MangoFixUtil.h"
#import "PHKeyChainUtil.h"
#import "PHNetworkDefine.h"
#import "PHCacroDefine.h"
#import <objc/message.h>

typedef void(^Succ)(NSDictionary *dict);

typedef void(^Fail)(NSString *msg);

@interface MangoFixUtil ()

/**
 * 应用id
 */
@property (nonatomic, copy) NSString *appId;

/**
 * 规则 YES 开发预览 NO 全量下发
 */
@property (nonatomic, assign) BOOL debug;

/**
 * 私钥
 */
@property (nonatomic, copy) NSString *privateKey;

/**
 * 公共参数
 */
@property (nonatomic, strong) NSDictionary *baseParams;

@end

@implementation MangoFixUtil

+ (instancetype)sharedUtil {
    static MangoFixUtil *util = nil;
    static dispatch_once_t predicate;
    dispatch_once(&predicate, ^{
        util = [[self alloc] init];
    });
    return util;
}

- (instancetype)init {
    if (self = [super init]) {
        _statusCode = 201;
        _url = PH_Url_GetMangoFile;
    }
    return self;
}

- (void)startWithAppId:(NSString*)appId privateKey:(NSString*)privateKey {
    [self startWithAppId:appId privateKey:privateKey debug:NO];
}

- (void)startWithAppId:(NSString*)appId privateKey:(NSString*)privateKey debug:(BOOL)debug {
    _appId = appId;
    _debug = debug;
    _privateKey = privateKey;
    if (!_debug) [self activateDevice];
}

- (void)evalRemoteMangoScript {
    
    NSAssert(!MFStringIsEmpty(_privateKey), @"The private key is nil or empty!");
    @try {
        [self evalLastPatch];
    }
    @catch (NSException *exception) {
        MFLog(@"%@", exception);
    }
    @finally {
        [self requestCheckRemotePatch];
    }
}

- (void)evalLocalMangoScript {
        
    NSAssert(!MFStringIsEmpty(_privateKey), @"The private key is nil or empty!");
    NSString *filePath = [[NSBundle mainBundle] pathForResource:@"encrypted_demo" ofType:@"mg"];
    NSString *script = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
    if (!MFStringIsEmpty(script)) {
        [self evalMangoScriptWithRSAEncryptedBase64String:script context:[self context]];
        MFLog(@"The local patch is successfully executed!");
    }
    else {
        MFLog(@"The local patch content is empty!");
    }
}

- (void)evalLocalUnEncryptedMangoScriptWithPublicKey:(NSString*)publicKey {
        
    NSAssert(!MFStringIsEmpty(_privateKey), @"The private key is nil or empty!");
    NSString *script = [self encryptScirptWithPublicKey:publicKey];
    if (!MFStringIsEmpty(script)) {
        [self evalMangoScriptWithRSAEncryptedBase64String:script context:[self context]];
        MFLog(@"The local unencrypted patch is successfully executed!");
    }
    else {
        MFLog(@"The local unencrypted patch content is empty!");
    }
}

- (void)deleteLocalMangoScript {
    
    NSError *outErr = nil;
    NSString *filePath= [(NSString *)[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"encrypted_demo.mg"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:filePath]) {
        [fileManager removeItemAtPath:filePath error:&outErr];
    }
    if (outErr) goto err;
    {
        MFLog(@"The local patch was successfully deleted!");
    }
    err:
    if (outErr) MFLog(@"%@",outErr);
}

- (void)evalLastPatch {
    
    NSString *filePath = [[self cachesDirectory] stringByAppendingPathComponent:@"demo.mg"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSString *script = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
        if (script && script.length > 0) {
            [self evalMangoScriptWithRSAEncryptedBase64String:script context:[self context]];
            MFLog(@"The last patch is successfully executed!");
        }
        else {
            MFLog(@"The last patch content is empty!");
        }
    }
    else {
        MFLog(@"The last patch does not exist!");
    }
}

- (void)evalRemotePatchWithFileId:(NSString*)fileId {
    
    __weak typeof(self) weakSelf = self;
    [self requestRemotePatch:^(NSDictionary *dict) {
        NSString *filePath = [[weakSelf cachesDirectory] stringByAppendingPathComponent:@"demo.mg"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
            NSString *script = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
            if (script && script.length > 0) {
                [weakSelf evalMangoScriptWithRSAEncryptedBase64String:script context:[weakSelf context]];
                MFLog(@"The latest patch is successfully executed!");
                if (!MFStringIsEmpty(fileId)) {
                    NSString *patchKey = MFPatchKey(fileId);
                    NSString *patchValue = [PHKeyChainUtil load:patchKey];
                    if (!MFStringIsEmpty(patchValue)) {
                        NSArray *values = [patchValue componentsSeparatedByString:@":"];
                        NSString *isActivated = [values lastObject];
                        if (!isActivated.boolValue) {
                            MFLog(@"Patch not activated!");
                            if (!weakSelf.debug) [weakSelf activatePatchWithFileId:fileId];
                        }
                    }
                }
            }
            else {
                MFLog(@"The latest patch content is empty!");
            }
        }
        else {
            MFLog(@"No new patch was detected!");
        }
    }];
}

- (NSString*)encryptScirptWithPublicKey:(NSString*)publicKey {
    
    NSString *result = nil;
    NSError *outErr = nil;
    
    NSURL *scriptUrl = [[NSBundle mainBundle] URLForResource:@"demo" withExtension:@"mg"];
    NSString *planScriptString = [NSString stringWithContentsOfURL:scriptUrl encoding:NSUTF8StringEncoding error:&outErr];
    if (outErr) goto err;
    {
        NSString *encodePublicKey = [NSString stringWithCString:[publicKey UTF8String] encoding:NSUTF8StringEncoding];
        if (outErr) goto err;
        result = [self encryptString:planScriptString publicKey:encodePublicKey];
    }
    
    err:
    if (outErr) MFLog(@"%@",outErr);
    return result;
}

- (NSString*)encryptPlainScirptToDocumentWithPublicKey:(NSString*)publicKey {
    
    NSError *outErr = nil;
    BOOL writeResult = NO;
    NSString * encryptedPath = nil;
    
    NSURL *scriptUrl = [[NSBundle mainBundle] URLForResource:@"demo" withExtension:@"mg"];
    NSString *planScriptString = [NSString stringWithContentsOfURL:scriptUrl encoding:NSUTF8StringEncoding error:&outErr];
    if (outErr) goto err;
    
    {
        NSString *encodePublicKey = [NSString stringWithCString:[publicKey UTF8String] encoding:NSUTF8StringEncoding];
        if (outErr) goto err;
        NSString *encryptedScriptString = [self encryptString:planScriptString publicKey:encodePublicKey];;
        
        encryptedPath= [(NSString *)[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"encrypted_demo.mg"];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:encryptedPath]) {
            [fileManager createFileAtPath:encryptedPath contents:nil attributes:nil];
        }
        MFLog(@"The encrypted patch path: %@", encryptedPath);
        writeResult = [encryptedScriptString writeToFile:encryptedPath atomically:YES encoding:NSUTF8StringEncoding error:&outErr];
    }
    
    err:
    if (outErr) MFLog(@"%@",outErr);
    return encryptedPath;
}

- (void)activateDevice {
    
    NSString *deviceKey = MFDeviceKey(_appId, [self bundleShortVersion]);
    __block NSString *deviceValue = [PHKeyChainUtil load:deviceKey];
    if (MFStringIsEmpty(deviceValue)) {
        deviceValue = MFStringWithFormat(@"%@%@", MFDevicePrefix, _appId);
        deviceValue = MFStringWithFormat(@"%@:%@", deviceValue, [self bundleShortVersion]);
        deviceValue = MFStringWithFormat(@"%@:%@", deviceValue, @"0");
        [PHKeyChainUtil save:deviceKey data:deviceValue];
    }
    NSArray *values = [deviceValue componentsSeparatedByString:@":"];
    NSString *isActivated = [values lastObject];
    if (!isActivated.boolValue) {
        MFLog(@"Device not activated!");
        [self requestPostWithUrl:PH_Url_ActivateDevice params:nil succ:^(NSDictionary *dict) {
            NSMutableArray *array = [NSMutableArray arrayWithArray:values];
            [array replaceObjectAtIndex:array.count-1 withObject:@"1"];
            deviceValue = [array componentsJoinedByString:@":"];
            [PHKeyChainUtil save:deviceKey data:deviceValue];
            MFLog(@"Device is activate successfully!");
        } fail:nil];
    }
}

- (void)activatePatchWithFileId:(NSString*)fileId {
    
    if (MFStringIsEmpty(fileId)) {
        return;
    }
    [self requestPostWithUrl:PH_Url_ActivatePatch params:@{@"fileid": fileId} succ:^(NSDictionary *dict) {
        NSString *patchKey = MFPatchKey(fileId);
        NSString *patchValue = [PHKeyChainUtil load:patchKey];
        if (!MFStringIsEmpty(patchValue)) {
            NSArray *values = [patchValue componentsSeparatedByString:@":"];
            NSString *isActivated = [values lastObject];
            if (!isActivated.boolValue) {
                NSMutableArray *array = [NSMutableArray arrayWithArray:values];
                [array replaceObjectAtIndex:array.count-1 withObject:@"1"];
                patchValue = [array componentsJoinedByString:@":"];
                [PHKeyChainUtil save:patchKey data:patchValue];
                MFLog(@"Patch is activate successfully!");
            }
        }
    } fail:nil];
}

- (NSString*)cachesDirectory {
    return [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
}

- (NSString*)bundleShortVersion {
    return [[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleShortVersionString"];
}

- (NSDictionary *)dictionaryWithJsonString:(NSString *)jsonString {
    if (jsonString == nil) {
        return nil;
    }
    NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    NSError *err;
    NSDictionary *dic = [NSJSONSerialization JSONObjectWithData:jsonData
                                                        options:NSJSONReadingMutableContainers
                                                          error:&err];
    if(err) {
        return nil;
    }
    return dic;
}

#pragma mark - objc

- (id)context {
    id context = ((id (*) (id, SEL))objc_msgSend)(objc_getClass("MFContext"), sel_registerName("alloc"));
    if (!context) {
        return nil;
    }
    ((void (*) (id, SEL, id))objc_msgSend)(context, sel_registerName("initWithRSAPrivateKey:"), _privateKey);
    return context;
}

- (void)evalMangoScriptWithRSAEncryptedBase64String:(NSString*)script context:(id)context {
    if (!context) {
        return;
    }
    ((void (*) (id, SEL, id))objc_msgSend)(context, sel_registerName("evalMangoScriptWithRSAEncryptedBase64String:"), script);
}

- (id)encryptString:(NSString*)string publicKey:(NSString*)publicKey {
    return ((id (*)(id, SEL, id, id))objc_msgSend)(objc_getClass("MFRSA"), sel_registerName("encryptString:publicKey:"), string, publicKey);
}

- (void)requestCheckRemotePatch {
    
    __weak typeof(self) weakSelf = self;
    [self requestPostWithUrl:PH_Url_CheckMangoFile params:nil succ:^(NSDictionary *dict) {
        NSDictionary *rows = dict[@"rows"];
        NSString *fileId = MFStringWithFormat(@"%@", rows[@"fileid"]);
        if (MFStringIsEmpty(fileId)) {
            MFLog(@"No new patch was detected!");
            [weakSelf evalRemotePatchWithFileId:nil];
        }
        else {
            MFLog(@"A new patch was detected!");
            NSString *patchKey = MFPatchKey(fileId);
            NSString *patchValue = [PHKeyChainUtil load:patchKey];
            if (MFStringIsEmpty(patchValue)) {
                patchValue = MFStringWithFormat(@"%@%@", MFPatchPrefix, fileId);
                patchValue = MFStringWithFormat(@"%@:%@", patchValue, [weakSelf bundleShortVersion]);
                patchValue = MFStringWithFormat(@"%@:%@", patchValue, @"0");
                [PHKeyChainUtil save:patchKey data:patchValue];
            }
            [weakSelf evalRemotePatchWithFileId:fileId];
        }
    } fail:^(NSString *msg) {
        [weakSelf evalRemotePatchWithFileId:nil];
    }];
}

- (void)requestRemotePatch:(Succ)succ {
    
    __weak typeof(self) weakSelf = self;
    NSURL *url = [NSURL URLWithString:_url];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    NSString *bodyString = @"";
    for (NSString *key in self.baseParams.allKeys) {
        NSString *value = [self.baseParams valueForKey:key];
        bodyString = [NSString stringWithFormat:@"%@%@=%@&", bodyString, key, value];
    }
    if ([bodyString hasSuffix:@"&"]) {
        bodyString = [bodyString substringWithRange:NSMakeRange(0, bodyString.length-1)];
    }
    request.HTTPBody = [bodyString dataUsingEncoding:NSUTF8StringEncoding];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    NSURLSessionTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*)response;
        if (data && httpResponse.statusCode == weakSelf.statusCode) {
            NSString *cachesPath = [weakSelf cachesDirectory];
            NSString *filePath = [cachesPath stringByAppendingPathComponent:@"demo.mg"];
            if ([data writeToFile:filePath atomically:YES]) {
                if (data.length == 0) {
                    MFLog(@"The empty patch is saved successfully!");
                }
                else {
                    MFLog(@"The latest patch is saved successfully!");
                }
                if (succ) {
                    succ(nil);
                }
            }
            else {
                MFLog(@"Failed to save the latest patch!");
            }
        }
        if (error) {
            MFLog(@"Failed to download the latest patch, error:%@", error);
        }
    }];
    [task resume];
}

- (void)requestPostWithUrl:(NSString*)url params:(NSDictionary*)params succ:(Succ)succ fail:(Fail)fail {
    
    __weak typeof(self) weakSelf = self;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    request.HTTPMethod = @"POST";
    NSString *bodyString = @"";
    for (NSString *key in self.baseParams.allKeys) {
        NSString *value = [self.baseParams valueForKey:key];
        bodyString = [NSString stringWithFormat:@"%@%@=%@&", bodyString, key, value];
    }
    if (params.count > 0) {
        for (NSString *key in params.allKeys) {
            NSString *value = [params valueForKey:key];
            bodyString = [NSString stringWithFormat:@"%@%@=%@&", bodyString, key, value];
        }
    }
    if ([bodyString hasSuffix:@"&"]) {
        bodyString = [bodyString substringWithRange:NSMakeRange(0, bodyString.length-1)];
    }
    request.HTTPBody = [bodyString dataUsingEncoding:NSUTF8StringEncoding];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    NSURLSessionTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*)response;
        if (httpResponse.statusCode == 200) {
            NSString *resultStr = [[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
            NSDictionary *dict = [weakSelf dictionaryWithJsonString:resultStr];
            NSInteger code = [dict[@"code"] intValue];
            NSString *msg = dict[@"msg"];
            if (code == 500) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (fail) fail(msg);
                });
                MFLog(@"%@", msg);
            }
            else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (succ) succ(dict);
                });
            }
        }
        else {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (fail) fail(error.localizedDescription);
            });
            MFLog(@"%@", error.localizedDescription);
        }
    }];
    [task resume];
}

- (NSDictionary*)baseParams {
    if (!_baseParams) {
        _baseParams = @{@"appid": _appId, @"version": [self bundleShortVersion], @"debug": @(_debug)};
    }
    return _baseParams;
}

@end
