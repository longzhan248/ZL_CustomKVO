//
//  ZLViewController.m
//  ZLCustomKVO
//
//  Created by os on 2020/10/30.
//

#import "ZLViewController.h"
#import "ZLPerson.h"

#import "NSObject+ZLBlock_KVO.h"

@interface ZLViewController ()

@property (nonatomic, strong) ZLPerson *person;

@end

@implementation ZLViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.person = [[ZLPerson alloc] init];
    self.person.name = @"zl";
    self.person.age = 18;
    
//    [self.person ZL_addObserver:self forKey:@"name" withBlock:^(id observedObject, NSString *observedKey, id oldValue, id newValue) {
//        NSLog(@"Value had changed yet with observing Block");
//        NSLog(@"oldValue---%@",oldValue);
//        NSLog(@"newValue---%@",newValue);
//    }];
    
    [self.person ZL_addObserver:self forKey:@"age" withBlock:^(id observedObject, NSString *observedKey, id oldValue, id newValue) {
        NSLog(@"Value had changed yet with observing Block");
        NSLog(@"oldValue---%@",oldValue);
        NSLog(@"newValue---%@",newValue);
    }];
    
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
//    self.person.name = [NSString stringWithFormat:@"%@+",self.person.name];
    self.person.age = 10;
}

@end
