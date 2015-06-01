//
// Created by Tony Stone on 5/15/15.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@protocol CCAction;

@interface CCCache : NSObject

    - (instancetype)initWithManagedObjectModel:(NSManagedObjectModel *)model;

    - (void) start;
    - (void) stop;

    - (NSManagedObjectContext *) mainThreadContext;
    - (NSManagedObjectContext *) editContext;

@end