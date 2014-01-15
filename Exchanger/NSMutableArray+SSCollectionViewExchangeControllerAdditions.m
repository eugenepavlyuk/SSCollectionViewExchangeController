//
//  NSMutableArray+SSCollectionViewExchangeControllerAdditions.m
//  Exchanger
//
//  Created by Murray Sagal on 1/10/2014.
//  Copyright (c) 2014 Signature Software. All rights reserved.
//

#import "NSMutableArray+SSCollectionViewExchangeControllerAdditions.h"

@implementation NSMutableArray (SSCollectionViewExchangeControllerAdditions)

+ (void)exchangeItemInArray:(NSMutableArray *)array1 atIndex:(NSUInteger)index1
            withItemInArray:(NSMutableArray *)array2 atIndex:(NSUInteger)index2 {
    
    // Exchanges two items that can be in different arrays.
    
    if ([array1 isEqual:array2]) {
        
        [array1 exchangeObjectAtIndex:index1 withObjectAtIndex:index2];
        
    } else {
        
        id itemFromArray1 = array1[ index1 ];
        
        [array1 replaceObjectAtIndex:index1 withObject:array2[ index2 ]];
        [array2 replaceObjectAtIndex:index2 withObject:itemFromArray1];
    }
}

@end