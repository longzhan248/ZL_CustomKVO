//
//  NSObject+ZLBlock_KVO.m
//  ZLCustomKVO
//
//  Created by os on 2020/10/30.
//

#import "NSObject+ZLBlock_KVO.h"
#import <objc/runtime.h>
#import <objc/message.h>

//as prefix string of kvo class
static NSString * const kZLkvoClassPrefix_for_Block = @"ZLObserver_";
static NSString * const kZLkvoAssiociateObserver_for_Block = @"ZLAssiociateObserver";

@interface ZL_ObserverInfo_for_Block : NSObject

@property (nonatomic, weak) NSObject *observer;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) ZL_ObservingHandler handler;

@end

@implementation ZL_ObserverInfo_for_Block

- (instancetype)initWithObserver:(NSObject *)observer forKey:(NSString *)key observeHandler:(ZL_ObservingHandler)handler
{
    if (self = [super init]) {
        _observer = observer;
        self.key = key;
        self.handler = handler;
    }
    return self;
}

@end

#pragma mark -- Transform setter or getter to each other Methods
static NSString *setterForGetter(NSString * getter)
{
    if (getter.length <= 0) { return nil; }
    NSString *firstString = [[getter substringToIndex:1] uppercaseString];
    NSString *leaveString = [getter substringFromIndex:1];
    
    return [NSString stringWithFormat: @"set%@%@:", firstString, leaveString];
}

static NSString *getterForSetter(NSString * setter)
{
    if (setter.length <= 0 || ![setter hasPrefix: @"set"] || ![setter hasSuffix: @":"]) { return nil; }
    
    NSRange range = NSMakeRange(3, setter.length - 4);
    NSString *getter = [setter substringWithRange: range];
    
    NSString *firstString = [[getter substringToIndex: 1] lowercaseString];
    getter = [getter stringByReplacingCharactersInRange: NSMakeRange(0, 1) withString: firstString];
    
    return getter;
}

#pragma mark -- Override setter and getter Methods
static void KVO_setter(id self, SEL _cmd, id newValue)
{
    NSString *setterName = NSStringFromSelector(_cmd);
    NSString *getterName = getterForSetter(setterName);
    if (!getterName) {
        @throw [NSException exceptionWithName: NSInvalidArgumentException reason: [NSString stringWithFormat: @"unrecognized selector sent to instance %p", self] userInfo: nil];
        return;
    }
    
    // 判断是否开启自动监听
    if (![[self class] automaticallyNotifiesObserversForKey:getterName]) { return; }
    
    id oldValue = [self valueForKey: getterName];
    struct objc_super superClass = {
        .receiver = self,
        .super_class = [self class],
    };
    
    [self willChangeValueForKey: getterName];
    void (*objc_msgSendSuperKVO)(void *, SEL, id) = (void *)objc_msgSendSuper;
    objc_msgSendSuperKVO(&superClass, _cmd, newValue);
    [self didChangeValueForKey: getterName];
    
    //获取所有监听回调对象进行回调
    NSMutableArray * observers = objc_getAssociatedObject(self, (__bridge const void *)kZLkvoAssiociateObserver_for_Block);
    for (ZL_ObserverInfo_for_Block * info in observers) {
        if ([info.key isEqualToString: getterName]) {
            dispatch_async(dispatch_queue_create(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                info.handler(self, getterName, oldValue, newValue);
            });
        }
    }
}

static Class kvo_Class(id self, SEL _cmd)
{
    return class_getSuperclass(object_getClass(self));
}

static void kvo_Dealloc(id self, SEL _cmd)
{
    Class superClass = [self class];
    object_setClass(self, superClass);
}

#pragma mark -- NSObject Category(KVO Reconstruct)
@implementation NSObject (ZLBlock_KVO)

- (void)ZL_addObserver:(NSObject *)observer forKey:(NSString *)key withBlock:(ZL_ObservingHandler)observedHandler
{
    //step 1 get setter method, if not, throw exception
    SEL setterSelector = NSSelectorFromString(setterForGetter(key));
    Method setterMethod = class_getInstanceMethod([self class], setterSelector);
    if (!setterMethod) {
        @throw [NSException exceptionWithName: NSInvalidArgumentException reason: [NSString stringWithFormat: @"unrecognized selector sent to instance %@", self] userInfo: nil];
        return;
    }
    
    //自己的类作为被观察者类
    Class observedClass = object_getClass(self);
    NSString *className = NSStringFromClass(observedClass);
    
    //如果被监听者没有ZLObserver_，那么判断是否需要创建新类
    if (![className hasPrefix: kZLkvoClassPrefix_for_Block]) {
        // 被观察的类如果是被观察对象本来的类，那么，就要专门依据本来的类新建一个新的子类，区分是否这个子类的标记是带有kZLkvoClassPrefix_for_Block的前缀
        observedClass = [self createKVOClassWithOriginalClassName: className];
        // 将被观察类的isa指向新创建的subclass
        object_setClass(self, observedClass);
    }
    
    //add kvo setter method if its class(or superclass)hasn't implement setter
    if (![self hasSelector: setterSelector]) {
        const char *types = method_getTypeEncoding(setterMethod);
        // 将原来的setter方法替换一个新的 setter 方法
        class_addMethod(observedClass, setterSelector, (IMP)KVO_setter, types);
    }
    
    //add this observation info to saved new observer
    // 新建一个观察者类
    ZL_ObserverInfo_for_Block *newInfo = [[ZL_ObserverInfo_for_Block alloc] initWithObserver: observer forKey: key observeHandler: observedHandler];
    
    // 观察者数组
    NSMutableArray *observers = objc_getAssociatedObject(self, (__bridge void *)kZLkvoAssiociateObserver_for_Block);
    
    if (!observers) {
        observers = [NSMutableArray array];
        objc_setAssociatedObject(self, (__bridge void *)kZLkvoAssiociateObserver_for_Block, observers, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [observers addObject: newInfo];
}

- (Class)createKVOClassWithOriginalClassName:(NSString *)className
{
    NSString *kvoClassName = [kZLkvoClassPrefix_for_Block stringByAppendingString: className];
    Class observedClass = NSClassFromString(kvoClassName);
    
    if (observedClass) { return observedClass; }
    
    // 创建新类，并且添加ZLObserver_为类名新前缀
    Class originalClass = object_getClass(self);
    Class kvoClass = objc_allocateClassPair(originalClass, kvoClassName.UTF8String, 0);
    
    // 获取监听对象的 class 方法实现代码，然后替换新建类的 class 实现
    Method classMethod = class_getInstanceMethod(originalClass, @selector(class));
    const char *types = method_getTypeEncoding(classMethod);
    class_addMethod(kvoClass, @selector(class), (IMP)kvo_Class, types);
    
    // 获取监听对象的 dealloc 方法实现代码，然后替换新建类的 class 实现
    Method deallocMethod = class_getInstanceMethod(originalClass, NSSelectorFromString(@"dealloc"));
    const char *deallocTypes = method_getTypeEncoding(deallocMethod);
    class_addMethod(kvoClass, NSSelectorFromString(@"dealloc"), (IMP)kvo_Dealloc, deallocTypes);
    
    objc_registerClassPair(kvoClass);
    
    return kvoClass;
}

- (BOOL)hasSelector:(SEL)selector
{
    Class observedClass = object_getClass(self);
    unsigned int methodCount = 0;
    Method *methodList = class_copyMethodList(observedClass, &methodCount);
    for (int i = 0; i < methodCount; i++) {
        
        SEL thisSelector = method_getName(methodList[i]);
        if (thisSelector == selector) {
            
            free(methodList);
            return YES;
        }
    }
    
    free(methodList);
    return NO;
}

@end
