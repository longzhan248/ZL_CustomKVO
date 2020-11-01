//
//  NSObject+ZLBlock_KVO.h
//  ZLCustomKVO
//
//  Created by os on 2020/10/30.
//

#import <Foundation/Foundation.h>

typedef void (^ZL_ObservingHandler) (id observedObject, NSString * observedKey, id oldValue, id newValue);

@interface NSObject (ZLBlock_KVO)

/**
 *  method stead of traditional addObserver API
 *
 *  @param object          object as observer
 *  @param key             attribute of object to be observed
 *  @param observedHandler method to be invoked when notification be observed has changed
 */
- (void)ZL_addObserver: (NSObject *)object forKey: (NSString *)key withBlock: (ZL_ObservingHandler)observedHandler;

@end

