//
//  MFKeyChain.h
//  MangoFixUtil
//
//  Created by xhg on 2021/9/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MFKeyChain : NSObject

/**
 * 保存数据
 */
+ (void)save:(NSString *)key data:(id)data;

/**
 * 加载数据
 */
+ (id)load:(NSString *)key;

/**
 * 删除数据
 */
+ (void)delete:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
