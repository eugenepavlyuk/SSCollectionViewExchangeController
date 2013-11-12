//
//  SSCollectionViewExchangeFlowLayout.m
//  Exchanger
//
//  Created by Murray Sagal on 2012-10-31.
//  Copyright (c) 2012 Signature Software. All rights reserved.
//

#import "SSCollectionViewExchangeFlowLayout.h"
#import <QuartzCore/QuartzCore.h>



@interface SSCollectionViewExchangeFlowLayout ()

// This is the view that gets dragged around...
@property (strong, nonatomic) UIView *viewForItemBeingDragged;

// These contain the offset to the view's center...
@property (nonatomic) float xOffsetForViewBeingDragged;
@property (nonatomic) float yOffsetForViewBeingDragged;

// These manage the state of the swap process...
@property (strong, nonatomic) NSIndexPath *originalIndexPathForItemBeingDragged;
@property (strong, nonatomic) NSIndexPath *indexPathOfItemLastSwapped;
@property (nonatomic) BOOL mustUndoPriorSwap;

// This helps safeguard against the documented behaviour regarding items that are hidden.
// As an optimization, the collection view might not create the corresponding view
// if the hidden property (UICollectionViewLayoutAttributes) is set to YES. In the
// gesture recognizer's recognized state we always need the cell for the item that
// was hidden so we can animate to its center. So we use this property to hold the
// center of the cell at indexPathOfItemLastSwapped and we capture it just before
// it is hidden.
@property (nonatomic) CGPoint centerOfCellForLastItemSwapped;

// These readonly properties just make the code a bit more readable...
@property (strong, nonatomic, readonly) NSIndexPath *indexPathOfItemToHide;
@property (strong, nonatomic, readonly) NSIndexPath *indexPathOfItemToDim;

- (void)longPress:(UILongPressGestureRecognizer *)sender;

@end




@implementation SSCollectionViewExchangeFlowLayout


//-----------------------
#pragma mark - Accessors...

- (NSIndexPath *)indexPathOfItemToHide
{
    return self.indexPathOfItemLastSwapped;
//    return nil;
    
    // Return nil if you don't want to hide.
    // This can be useful during testing to ensure that the item you're dragging around is properly following.
}

- (NSIndexPath *)indexPathOfItemToDim
{
    return self.originalIndexPathForItemBeingDragged;  // Return nil if you don't want to dim
}



//--------------------------------
#pragma mark - Layout attributes...

// There is one item that needs hiding and one that needs dimming. As the user drags the item being moved over
// another item, that item moves to the original location of the item being dragged. That cell is dimmed, marking
// the original location of the item being moved. The cell at the position of the displaced item is hidden giving
// the user the sense that the item being dragged will land there if their finger is released.

// It can happen that the item to hide and the item to dim will be the same. This happens when the user drags back
// to the starting location. This collision is irrelevant because there are two separate properties: one tracking
// the item to hide and one tracking the item to dim. In layoutAttributesForItem: the hidden property is set first
// then the alpha. If the items are the same setting the alpha for an item that is hidden has no effect.

- (NSArray *)layoutAttributesForElementsInRect:(CGRect)rect
{
    NSArray *layoutAttributes = [super layoutAttributesForElementsInRect:rect];
    
    for (UICollectionViewLayoutAttributes *attributesForItem in layoutAttributes)
    {
        (void) [self layoutAttributesForItem:attributesForItem];
    }
    
    return layoutAttributes;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath
{
    UICollectionViewLayoutAttributes *attributesForItem = [super layoutAttributesForItemAtIndexPath:indexPath];
    
    return [self layoutAttributesForItem:attributesForItem];
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItem:(UICollectionViewLayoutAttributes *)attributesForItem
{
    attributesForItem.hidden = ([attributesForItem.indexPath isEqual:self.indexPathOfItemToHide])? YES : NO;
    attributesForItem.alpha =  ([attributesForItem.indexPath isEqual:self.indexPathOfItemToDim])?  0.6 : 1.0;

    return attributesForItem;
}



//--------------------------------
#pragma mark - Instance methods...

- (void)cancelGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
{
    gestureRecognizer.enabled = NO;
    gestureRecognizer.enabled = YES;
    // As per the docs, this triggers a cancel.
}

- (void)setUpForExchangeTransaction:(UIGestureRecognizer *)gestureRecognizer
{
    NSLog(@"[<%@ %p> %@ line= %d]", [self class], self, NSStringFromSelector(_cmd), __LINE__);
    
    if ([self.delegate allowsExchange] == NO)
    {
        [self cancelGestureRecognizer:gestureRecognizer];
        return;
    }
    
    // Get the indexPath from the location...
    CGPoint locationInCollectionView = [gestureRecognizer locationInView:self.collectionView];
    NSIndexPath *indexPath = [self.collectionView indexPathForItemAtPoint:locationInCollectionView];
    
    if (indexPath == nil)
    {
        // The user is not on a cell. There's nothing to do so exit stage left...
        [self cancelGestureRecognizer:gestureRecognizer];
        return;
    }
    
    // Later in the exchange process it is necessary to know where this started. Hang on to the indexPath...
    self.originalIndexPathForItemBeingDragged = indexPath;
    
    // Get the cell from the indexPath...
    UICollectionViewCell *itemCell = [self.collectionView cellForItemAtIndexPath:indexPath];
    
    // See the comments in the interface block above...
    self.centerOfCellForLastItemSwapped = itemCell.center;
    
    // Create an image of the cell. This is what will follow the user's finger...
    UIGraphicsBeginImageContextWithOptions(itemCell.bounds.size, itemCell.opaque, 0.0f);
    [itemCell.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *itemCellImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    UIImageView *itemCellImageView = [[UIImageView alloc] initWithImage:itemCellImage];
    
    // Create a view and add the image...
    self.viewForItemBeingDragged = [[UIView alloc] initWithFrame:CGRectMake(CGRectGetMinX(itemCell.frame), CGRectGetMinY(itemCell.frame), CGRectGetWidth(itemCellImageView.frame), CGRectGetHeight(itemCellImageView.frame))];
    [self.viewForItemBeingDragged addSubview:itemCellImageView];
    
    // Add this view to the collection view...
    [self.collectionView addSubview:self.viewForItemBeingDragged];
    
    // Hide the item being dragged...
    // invalidateLayout kicks of the process of redrawing the layout. This class intervenes in that process
    // by overriding layoutAttributesForElementsInRect: and layoutAttributesForItemAtIndexPath: to hide
    // and dim items as required.
    [self.collectionView.collectionViewLayout invalidateLayout];
    
    // Calculate and keep the offsets from the location of the user's finger to the center of view being dragged...
    CGPoint locationInCellImageView = [gestureRecognizer locationInView:self.viewForItemBeingDragged];
    CGPoint imageViewCenter = CGPointMake(self.viewForItemBeingDragged.frame.size.width/2, self.viewForItemBeingDragged.frame.size.height/2);
    self.xOffsetForViewBeingDragged = locationInCellImageView.x - imageViewCenter.x;
    self.yOffsetForViewBeingDragged = locationInCellImageView.y - imageViewCenter.y;
    
    // Blink...
    [UIView animateWithDuration:0.05 animations:^
     {
         self.viewForItemBeingDragged.transform = CGAffineTransformMakeScale(1.2f, 1.2f);
     }
                     completion:^(BOOL finished)
     {
         [UIView animateWithDuration:0.25 animations:^
          {
              self.viewForItemBeingDragged.transform = CGAffineTransformMakeScale(1.00f, 1.00f);
          }];
     }];
    
    // Managing the values in these properties is critical to tracking the state of the exchange process.
    self.indexPathOfItemLastSwapped = self.originalIndexPathForItemBeingDragged;
    self.mustUndoPriorSwap = NO;
}

- (void)manageExchangeEvent:(UIGestureRecognizer *)gestureRecognizer
{
    // Control reaches here because the user is dragging, still in the long press...
    NSLog(@"[<%@ %p> %@ line= %d]", [self class], self, NSStringFromSelector(_cmd), __LINE__);
    
    // Update the location of the view the user is dragging around...
    CGPoint locationInCollectionView = [gestureRecognizer locationInView:self.collectionView]; //this is where the finger is in the collection view's coordinate system
    CGPoint offsetLocationInCollectionView = CGPointMake(locationInCollectionView.x - self.xOffsetForViewBeingDragged, locationInCollectionView.y - self.yOffsetForViewBeingDragged);
    self.viewForItemBeingDragged.center = offsetLocationInCollectionView;
    
    // Where has the user dragged on the collection view? What indexPath...
    NSIndexPath *currentIndexPath = [self.collectionView indexPathForItemAtPoint:locationInCollectionView];
    
    if (currentIndexPath == nil)
    {
        // The user is not over a cell. There's nothing to do so exit stage left...
        NSLog(@"not over a cell");
        return;
    }
    
    // The user has moved and is over a cell. There are two cases:
    //  1. The user has moved but not very far and is over the same cell. In this case there's nothing to do.
    //  2. The user has moved over a different cell. In other words currentIndexPath does not equal self.indexPathOfItemLastSwapped
    
    if ([self isOverNewItemAtIndexPath:currentIndexPath] == YES)  //if the item we're over is not the same as the one we last swapped...
    {
        NSLog(@"over a new cell");
        
        // The user has dragged over a new cell.
        // First, determine if there was a prior exchange that must be undone.
        
        if (self.mustUndoPriorSwap)
        {
            // When undoing a prior swap there are two subcases:
            //  1. The user has dragged back to the starting item
            //  2. The user is over any other item
            // Both require different actions and different state settings.
            
            if ([self isBackToStartingItemAtIndexPath:currentIndexPath] == YES)
            {
                // The user has dragged back to the starting position...
                NSLog(@"dragged back home");
                
                [self.collectionView performBatchUpdates:^ {
                    
                    // Put the previously swapped item back to its original location...
                    [self.collectionView moveItemAtIndexPath:self.originalIndexPathForItemBeingDragged toIndexPath:self.indexPathOfItemLastSwapped];
                    
                    // Put the item we're dragging back into its origingal location...
                    [self.collectionView moveItemAtIndexPath:self.indexPathOfItemLastSwapped toIndexPath:self.originalIndexPathForItemBeingDragged];
                    
                    // Let the delegate know.
                    [self.delegate exchangeItemAtIndexPath:self.originalIndexPathForItemBeingDragged withItemAtIndexPath:self.indexPathOfItemLastSwapped];
                    [self.delegate didFinishExchangeEvent];
                    
                    // Set state. This is the same state as when the gesture began.
                    self.indexPathOfItemLastSwapped = self.originalIndexPathForItemBeingDragged;
                    self.mustUndoPriorSwap = NO;
                    
                    // Grab the center of the cell...
                    UICollectionViewCell *itemCell = [self.collectionView cellForItemAtIndexPath:currentIndexPath];
                    self.centerOfCellForLastItemSwapped = itemCell.center;
                }
                                              completion:nil];
                
            } else {
                
                // The user has dragged over a new item and it's not where the process started...
                NSLog(@"dragged over a new item.");
                
                [self.collectionView performBatchUpdates:^ {
                    
                    // Put the previously swapped item back to its original location...
                    [self.collectionView moveItemAtIndexPath:self.originalIndexPathForItemBeingDragged toIndexPath:self.indexPathOfItemLastSwapped];
                    
                    // Move the item being dragged to the current postion...
                    [self.collectionView moveItemAtIndexPath:self.indexPathOfItemLastSwapped toIndexPath:currentIndexPath];
                    
                    // Move the item we're over to the original location of the item being dragged...
                    [self.collectionView moveItemAtIndexPath:currentIndexPath toIndexPath:self.originalIndexPathForItemBeingDragged];
                    
                    // Let the delegate know. First undo the prior exchange then do the new exchange...
                    [self.delegate exchangeItemAtIndexPath:self.originalIndexPathForItemBeingDragged withItemAtIndexPath:self.indexPathOfItemLastSwapped];
                    [self.delegate exchangeItemAtIndexPath:currentIndexPath withItemAtIndexPath:self.originalIndexPathForItemBeingDragged];
                    [self.delegate didFinishExchangeEvent];
                    
                    // Set state.
                    self.indexPathOfItemLastSwapped = currentIndexPath;
                    self.mustUndoPriorSwap = YES;
                    
                    // Grab the center of the cell...
                    UICollectionViewCell *itemCell = [self.collectionView cellForItemAtIndexPath:currentIndexPath];
                    self.centerOfCellForLastItemSwapped = itemCell.center;
                }
                                              completion:nil];
            }
                 
        } else {
            
            // There is not a prior swap to undo (it might be the first time through or it might be
            // that the user recently dragged back to the starting position...
            NSLog(@"dragged from home to new item.");
            
            [self.collectionView performBatchUpdates:^
             {
                 // Move the item being dragged to the current postion...
                 [self.collectionView moveItemAtIndexPath:self.originalIndexPathForItemBeingDragged toIndexPath:currentIndexPath];
                 
                 // Move the item in the current postion to the original location of the item being moved...
                 [self.collectionView moveItemAtIndexPath:currentIndexPath toIndexPath:self.originalIndexPathForItemBeingDragged];
                 
                 // Let the delegate know.
                 [self.delegate exchangeItemAtIndexPath:currentIndexPath withItemAtIndexPath:self.originalIndexPathForItemBeingDragged];
                 [self.delegate didFinishExchangeEvent];
                 
                 // Set state.
                 self.indexPathOfItemLastSwapped = currentIndexPath;
                 self.mustUndoPriorSwap = YES;
                 
                 // Grab the center of the cell...
                 UICollectionViewCell *itemCell = [self.collectionView cellForItemAtIndexPath:currentIndexPath];
                 self.centerOfCellForLastItemSwapped = itemCell.center;
             }
                                          completion:nil];
        }
    }
}

- (void)finishExchangeTransaction
{
    // Control reaches here when the user lifts his/her finger...
    NSLog(@"[<%@ %p> %@ line= %d]", [self class], self, NSStringFromSelector(_cmd), __LINE__);
    
    if ([self isBackToStartingItemAtIndexPath:self.indexPathOfItemLastSwapped] == YES) {
        
        // The user released after dragging back to the starting location.
        // So, in the end, nothing was exchanged.
        // Let the delegate know by passing nil in the indexPaths.
        [self.delegate didFinishExchangeTransactionWithItemAtIndexPath:nil andItemAtIndexPath:nil];
        
    } else {
        
        // There was an exchange. Let the delegate know that the transaction is finished.
        [self.delegate didFinishExchangeTransactionWithItemAtIndexPath:self.indexPathOfItemLastSwapped andItemAtIndexPath:self.originalIndexPathForItemBeingDragged];
        
        // Get the cell...
        UICollectionViewCell *cellForOriginalLocation = [self.collectionView cellForItemAtIndexPath:self.originalIndexPathForItemBeingDragged];
        
        // Animate the undimming...
        [UIView animateWithDuration:0.4 animations:^
         {
             cellForOriginalLocation.alpha = 0.1;
             cellForOriginalLocation.alpha = 1.0;
         }];
    }
    
    // Animate the release...
    [UIView animateWithDuration:0.15 animations:^
     {
         self.viewForItemBeingDragged.center = self.centerOfCellForLastItemSwapped;
     }
                     completion:^(BOOL finished)
     {
         // Blink...
         [UIView animateWithDuration:0.3 animations:^
          {
              self.viewForItemBeingDragged.transform = CGAffineTransformMakeScale(1.08f, 1.08f);
          }
                          completion:^(BOOL finished)
          {
              // Clean up...
              [self.viewForItemBeingDragged removeFromSuperview];
              
              // Set state so nothing is hidden or dimmed now...
              self.indexPathOfItemLastSwapped = nil;
              self.originalIndexPathForItemBeingDragged = nil;
              [self.collectionView.collectionViewLayout invalidateLayout];
              
          }];
     }];
}

- (BOOL)isOverNewItemAtIndexPath:(NSIndexPath *)indexPath
{
    return ![indexPath isEqual:self.indexPathOfItemLastSwapped];
}

- (BOOL)isBackToStartingItemAtIndexPath:(NSIndexPath *)indexPath
{
    return [indexPath isEqual:self.originalIndexPathForItemBeingDragged];
}



//-------------------------------------------------
#pragma mark - UIGestureRecognizer action method...

- (void)longPress:(UILongPressGestureRecognizer *)sender
{
    switch (sender.state) {
            
        case UIGestureRecognizerStateBegan:
            [self setUpForExchangeTransaction:sender];
            break;
            
        case UIGestureRecognizerStateChanged:
            [self manageExchangeEvent:sender];
            break;
            
        case UIGestureRecognizerStateEnded:
            [self finishExchangeTransaction];
            break;
            
        case UIGestureRecognizerStatePossible:
            NSLog(@"UIGestureRecognizerStatePossible");
            break;
            
        case UIGestureRecognizerStateCancelled:
            NSLog(@"UIGestureRecognizerStateCancelled");
            break;
            
        case UIGestureRecognizerStateFailed:
            NSLog(@"UIGestureRecognizerStateFailed");
            break;
    }
}

@end