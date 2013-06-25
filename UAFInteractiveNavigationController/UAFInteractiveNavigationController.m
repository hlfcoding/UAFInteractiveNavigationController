//
//  UAFInteractiveNavigationController.m
//  RhymesGesturalNavigationControllerProof
//
//  Created by Peng Wang on 6/7/13.
//  Copyright (c) 2013 Everynone. All rights reserved.
//

#import "UAFInteractiveNavigationController.h"

typedef NS_OPTIONS(NSUInteger, Flag) {
  FlagNone             = 0,
  FlagIsPerforming     = 1 << 0,
  FlagIsResetting      = 1 << 1,
  FlagIsStealingPan    = 1 << 2,
  FlagCanDelegate      = 1 << 3,
  FlagCanHandlePan     = 1 << 4,
};

@interface UAFInteractiveNavigationController ()

@property (nonatomic) NSUInteger currentChildIndex;
@property (nonatomic) Flag flags;

@property (strong, nonatomic, readwrite) UIView *containerView;
@property (strong, nonatomic, readwrite) UIPanGestureRecognizer *panGestureRecognizer;

@property (strong, nonatomic) UIView *previousView;
@property (strong, nonatomic) UIView *currentView;
@property (strong, nonatomic) UIView *nextView;

@property (strong, nonatomic) NSMutableArray *orderedChildViewControllers;

@property (nonatomic, readonly, getter = fetchNavigationDirection) UAFNavigationDirection navigationDirection;
@property (nonatomic, readonly, getter = fetchNavigationDuration) NSTimeInterval navigationDuration;

- (BOOL)hasChildViewController:(id)clue;
- (BOOL)addChildViewController:(UIViewController *)childController animated:(BOOL)animated focused:(BOOL)focused next:(BOOL)isNext;

- (BOOL)cleanChildViewControllers;
- (BOOL)handleRemoveChildViewController:(UIViewController *)childController; //-- Named to avoid conflict with private API.

- (void)handlePan:(UIPanGestureRecognizer *)gesture;

- (BOOL)delegateWillAddViewController:(UIViewController *)viewController;
- (BOOL)delegateWillShowViewController:(UIViewController *)viewController animated:(BOOL)animated;
- (BOOL)delegateDidShowViewController:(UIViewController *)viewController animated:(BOOL)animated;

- (BOOL)updateChildViewControllerTilingIfNeeded;

@end

@implementation UAFInteractiveNavigationController

//-- UAFNavigationController
@synthesize delegate;
@synthesize baseNavigationDirection, onceNavigationDirection;
@synthesize baseNavigationDuration, onceNavigationDuration;
@synthesize pagingDelegate, pagingEnabled;

//-- UAFInertialViewController
@synthesize bounces;

- (void)_commonInit
{
  [super _commonInit];
  //-- Custom initialization.
  self.baseNavigationDirection = UAFNavigationDirectionHorizontal;
  self.baseNavigationDuration = 0.8f;
  self.finishTransitionDurationFactor = 2.0f;
  self.finishTransitionDurationMinimum = 0.4f;
  self.bounces = YES;
  self.pagingEnabled = NO;
  self.flags = FlagCanDelegate|FlagCanHandlePan;
  self.orderedChildViewControllers = [NSMutableArray array];
}

- (void)viewDidLoad
{
  [super viewDidLoad];
  //-- Do any additional setup after loading the view.
  //-- Gestures.
  self.panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
  self.panGestureRecognizer.delegate = self;
  [self.view addGestureRecognizer:self.panGestureRecognizer];
  //-- Container.
  self.containerView = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] currentBounds:NO]];
  [self.view addSubview:self.containerView];
}

- (void)viewWillAppear:(BOOL)animated
{
  [super viewWillAppear:animated];
}

- (void)didReceiveMemoryWarning
{
  [super didReceiveMemoryWarning];
  //-- Dispose of any resources that can be recreated.
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
  CGSize size = [UIScreen mainScreen].bounds.size;
  BOOL isLandscape = UIInterfaceOrientationIsLandscape(toInterfaceOrientation);
  BOOL isHorizontal = self.baseNavigationDirection == UAFNavigationDirectionHorizontal;
  CGFloat newWidth  = isLandscape ? size.height : size.width;
  CGFloat newHeight = isLandscape ? size.width : size.height;
  CGFloat side = isHorizontal ? newWidth : newHeight;
  NSInteger indexOffset = -self.currentChildIndex;
  [self.containerView.subviews enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
    UIView *subview = obj;
    CGFloat offset = (idx + indexOffset) * side;
    subview.frame = CGRectMake(isHorizontal ? offset : 0.0f,
                               isHorizontal ? 0.0f : offset,
                               newWidth, newHeight);
  }];
  if (self.shouldDebugLog) {
    DLog(@"%f, %f", newWidth, newHeight);
  }
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
  
}

- (BOOL)shouldAutorotate
{
  return !(self.flags & FlagIsPerforming || self.flags & FlagIsResetting);
}

#pragma mark - UAFNavigationController

- (BOOL)pushViewController:(UIViewController *)viewController animated:(BOOL)animated
{
  return [self pushViewController:viewController animated:animated focused:YES];
}
- (BOOL)pushViewController:(UIViewController *)viewController animated:(BOOL)animated focused:(BOOL)focused
{
  return [self addChildViewController:viewController animated:animated focused:focused next:YES];
}

- (BOOL)popViewControllerAnimated:(BOOL)animated
{
  return [self popViewControllerAnimated:animated focused:YES];
}
- (BOOL)popViewControllerAnimated:(BOOL)animated focused:(BOOL)focused
{
  //-- Guards.
  if (self.flags & FlagIsPerforming || self.currentChildIndex == 0) {
    NSLog(@"Guarded.");
    return NO;
  }
  //-- /Guards.
  UIViewController *currentViewController = self.orderedChildViewControllers[self.currentChildIndex];
  self.currentChildIndex--;
  UIViewController *viewController = self.orderedChildViewControllers[self.currentChildIndex];
  //-- State.
  self.flags |= FlagIsPerforming;
  void (^tearDown)(BOOL) = ^(BOOL finished) {
    self.flags &= ~FlagIsPerforming;
    BOOL shouldRemove = YES;
    if ([viewController respondsToSelector:@selector(nextNavigationItemIdentifier)]
        && [(id)viewController nextNavigationItemIdentifier].length
        ) {
      //-- Don't remove VC if it's specified as a sibling item.
      shouldRemove = currentViewController.class != [[self.storyboard instantiateViewControllerWithIdentifier:
                                                      [(id)viewController nextNavigationItemIdentifier]] class];
    }
    if (shouldRemove) {
      //NSLog(@"Removing...");
      [self handleRemoveChildViewController:currentViewController];
    }
    if (focused) {
      [self delegateDidShowViewController:viewController animated:animated];
      [self updateChildViewControllerTilingIfNeeded];
    }
  };
  //-- /State.
  //-- Layout.
  UAFNavigationDirection direction = self.navigationDirection;
  void (^layout)(void) = ^{
    CGRect frame = self.containerView.bounds;
    viewController.view.frame = frame;
    if (direction == UAFNavigationDirectionHorizontal) {
      frame.origin.x += frame.size.width;
    } else if (direction == UAFNavigationDirectionVertical) {
      frame.origin.y += frame.size.height;
    }
    currentViewController.view.frame = frame;
  };
  //-- /Layout.
  if (focused) {
    [self delegateWillShowViewController:viewController animated:animated];
  }
  if (animated) {
    [UIView animateWithDuration:self.navigationDuration delay:0.0f options:UIViewAnimationOptionCurveEaseInOut
                     animations:layout completion:tearDown];
  } else {
    layout();
    tearDown(YES);
  }
  return YES;
}

- (BOOL)popToViewController:(UIViewController *)viewController animated:(BOOL)animated
{
  //-- Guards.
  NSAssert(viewController, @"Avoid passing in nothing for child-controller.");
  if (!viewController) {
    return NO;
  }
  //-- /Guards.
  NSMutableArray *viewControllers = [NSMutableArray array];
  for (UIViewController *childViewController in self.orderedChildViewControllers) {
    [viewControllers addObject:childViewController];
    if (childViewController.class == viewController.class) {
      break;
    }
  }
  [viewControllers addObject:self.visibleViewController];
  BOOL shouldSilence = self.flags & FlagCanDelegate;
  if (shouldSilence) {
    self.flags &= ~FlagCanDelegate;
  }
  BOOL didReset = [self setViewControllers:viewControllers animated:NO focused:YES];
  if (shouldSilence) {
    self.flags |= FlagCanDelegate;
  }
  if (!didReset) {
    return NO;
  }
  return [self popViewControllerAnimated:animated];
}

- (BOOL)setViewControllers:(NSArray *)viewControllers animated:(BOOL)animated
{
  return [self setViewControllers:viewControllers animated:animated focused:YES];
}
- (BOOL)setViewControllers:(NSArray *)viewControllers animated:(BOOL)animated focused:(BOOL)focused
{
  NSAssert(viewControllers, @"Avoid passing in nothing for child-controllers.");
  if (!viewControllers) {
    return NO;
  }
  if (self.flags & FlagIsResetting) {
    NSLog(@"Guarded.");
    return NO;
  }
  //-- State.
  self.flags |= FlagIsResetting;
  void (^tearDown)(BOOL) = ^(BOOL finished) {
    self.flags &= ~FlagIsResetting;
  };
  //-- /State.
  void (^addAndLayout)(void) = ^{
    [viewControllers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
      UIViewController *viewController = [obj isKindOfClass:[NSString class]]
      ? [self.storyboard instantiateViewControllerWithIdentifier:obj] : (UIViewController *)obj;
      BOOL didPush = [self pushViewController:viewController animated:NO focused:focused];
      NSAssert(didPush, @"Pushing failed! Inadequate view-controller: %@", viewController);
    }];
  };
  //-- Reset.
  for (UIViewController *viewController in self.orderedChildViewControllers) {
    [self handleRemoveChildViewController:viewController];
  }
  self.currentChildIndex = 0;
  //-- /Reset.
  if (animated) {
    NSTimeInterval duration = self.navigationDuration;
    [UIView animateWithDuration:duration delay:0.0f options:UIViewAnimationOptionCurveEaseInOut animations:^{
      self.containerView.alpha = 0.0f;
    } completion:^(BOOL finished) {
      addAndLayout();
      [UIView animateWithDuration:duration delay:0.0f options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.containerView.alpha = 1.0f;
      } completion:tearDown];
    }];
  } else {
    addAndLayout();
    tearDown(YES);
  }
  return YES;
}

- (BOOL)pushViewControllerWithIdentifier:(NSString *)identifier animated:(BOOL)animated
{
  return [self pushViewControllerWithIdentifier:identifier animated:animated focused:YES];
}
- (BOOL)pushViewControllerWithIdentifier:(NSString *)identifier animated:(BOOL)animated focused:(BOOL)focused
{
  return [self pushViewController:[self.storyboard instantiateViewControllerWithIdentifier:identifier]
                         animated:animated focused:focused];
}

- (BOOL)popToViewControllerWithIdentifier:(NSString *)identifier animated:(BOOL)animated
{
  return [self popToViewController:[self.storyboard instantiateViewControllerWithIdentifier:identifier]
                          animated:animated];
}

- (BOOL)handleRemovalRequestForViewController:(UIViewController *)viewController
{
  if (![self hasChildViewController:viewController]) {
    NSLog(@"Guarded.");
    return NO;
  }
  BOOL didRemove = [self handleRemoveChildViewController:viewController];
  return didRemove;
}

- (UIViewController *)topViewController
{
  return self.orderedChildViewControllers.lastObject;
}

- (UIViewController *)visibleViewController
{
  if (!self.orderedChildViewControllers.count) {
    return nil;
  }
  return self.orderedChildViewControllers[self.currentChildIndex];
}

- (NSArray *)viewControllers
{
  return self.orderedChildViewControllers;
}

#pragma mark - Private

- (NSTimeInterval)fetchNavigationDuration
{
  NSTimeInterval duration = self.baseNavigationDuration;
  if (self.onceNavigationDuration != kUAFNavigationDurationNone) {
    duration = self.onceNavigationDuration;
    self.onceNavigationDuration = kUAFNavigationDurationNone;
  }
  return duration;
}

- (UAFNavigationDirection)fetchNavigationDirection
{
  UAFNavigationDirection direction = self.baseNavigationDirection;
  if (self.onceNavigationDirection != UAFNavigationDirectionNone) {
    direction = self.onceNavigationDirection;
    self.onceNavigationDirection = UAFNavigationDirectionNone;
  }
  return direction;
}

- (BOOL)hasChildViewController:(id)clue
{
  UIViewController *viewController = nil;
  if ([clue isKindOfClass:[UIViewController class]]) {
    viewController = clue;
  } else if ([clue isKindOfClass:[NSString class]]) {
    viewController = [self.storyboard instantiateViewControllerWithIdentifier:clue];
  }
  //-- Guard.
  NSAssert(viewController, @"Can't find child-controller for given clue: %@", clue);
  if (!viewController) {
    return NO;
  }
  BOOL result = !([self.orderedChildViewControllers indexOfObject:viewController] == NSNotFound);
  return result;
}

- (BOOL)addChildViewController:(UIViewController *)childController animated:(BOOL)animated focused:(BOOL)focused next:(BOOL)isNext
{
  //-- Guards.
  NSAssert(childController, @"Avoid passing in nothing for child-controller.");
  if (!childController) {
    return NO;
  }
  if (self.flags & FlagIsPerforming) {
    NSLog(@"Guarded.");
    return NO;
  }
  //-- /Guards.
  NSInteger siblingModifier = isNext ? 1 : -1;
  //-- State.
  self.flags |= FlagIsPerforming;
  void (^tearDown)(BOOL) = ^(BOOL finished) {
    self.flags &= ~FlagIsPerforming;
    if (focused) {
      [self delegateDidShowViewController:childController animated:animated];
      [self updateChildViewControllerTilingIfNeeded];
    }
    //-- TODO: Eventually: Support previous, although no real use case (unless we flip directions).
    if (isNext
        && [childController respondsToSelector:@selector(nextNavigationItemIdentifier)]
        && [(id)childController nextNavigationItemIdentifier].length
        ) {
      [self pushViewControllerWithIdentifier:[(id)childController nextNavigationItemIdentifier] animated:NO focused:NO];
    }
  };
  //-- /State.
  UIViewController *currentViewController = nil;
  if (self.orderedChildViewControllers.count) {
    currentViewController = self.orderedChildViewControllers[self.currentChildIndex];
  }
  //-- Layout.
  CGRect frame = self.containerView.bounds;
  //-- Guard.
  NSAssert(!CGRectEqualToRect(frame, CGRectZero), @"No layout yet for container-view.");
  if (CGRectEqualToRect(frame, CGRectZero)) {
    return NO;
  }
  UAFNavigationDirection direction = self.navigationDirection;
  if (direction == UAFNavigationDirectionHorizontal) {
    frame.origin.x += siblingModifier * frame.size.width;
  } else if (direction == UAFNavigationDirectionVertical) {
    frame.origin.y += siblingModifier * frame.size.height;
  }
  [self delegateWillAddViewController:childController];
  childController.view.frame = frame;
  void (^finishLayout)(void) = !focused ? nil
  : ^{
    CGRect frame = self.containerView.bounds;
    childController.view.frame = frame;
    if (direction == UAFNavigationDirectionHorizontal) {
      frame.origin.x -= siblingModifier * frame.size.width;
    } else if (direction == UAFNavigationDirectionVertical) {
      frame.origin.y -= siblingModifier * frame.size.height;
    }
    if (currentViewController) {
      currentViewController.view.frame = frame;
    }
  };
  //-- /Layout.
  //-- Add.
  if (focused) {
    [self cleanChildViewControllers];
  }
  [self addChildViewController:childController];
  if (isNext) {
    [self.orderedChildViewControllers addObject:childController];
  } else {
    [self.orderedChildViewControllers insertObject:childController atIndex:0];
  }
  if ([childController respondsToSelector:@selector(setCustomNavigationController:)]) {
    [(id)childController setCustomNavigationController:self];
  }
  //-- TODO: Finally: Detect more scroll-views.
  if ([childController isKindOfClass:[UICollectionViewController class]]) {
    UIScrollView *scrollView = [(UICollectionViewController *)childController collectionView];
    [scrollView.panGestureRecognizer addTarget:self action:@selector(handlePan:)];
  }
  [self.containerView addSubview:childController.view];
  [childController didMoveToParentViewController:self];
  //-- /Add.
  if (focused) {
    [self delegateWillShowViewController:childController animated:animated];
  }
  if (animated) {
    [UIView animateWithDuration:self.navigationDuration delay:0.0f options:UIViewAnimationOptionCurveEaseInOut
                     animations:finishLayout completion:tearDown];
  } else {
    if (finishLayout) {
      finishLayout();
    }
    tearDown(YES);
  }
  if (currentViewController && focused) {
    self.currentChildIndex += siblingModifier;
  }
  return YES;
}

- (BOOL)cleanChildViewControllers
{
  if (!self.orderedChildViewControllers.count || self.flags & FlagIsResetting) {
    return NO;
  }
  //NSLog(@"Visible index: %d", self.currentChildIndex);
  for (NSInteger index = self.orderedChildViewControllers.count - 1; index >= 0; index--) {
    BOOL isOfSharedRoot   = index <= self.currentChildIndex;
    BOOL isWithinTileset  = index <= self.currentChildIndex + 1 && index >= self.currentChildIndex - 1;
    BOOL isTilesetReady   = self.orderedChildViewControllers.count <= 2;
    if ((!self.pagingEnabled && isOfSharedRoot)
        || (self.pagingEnabled && (isWithinTileset || isTilesetReady))
        ) {
      continue;
    }
    [self handleRemoveChildViewController:self.orderedChildViewControllers[index]];
  }
  return YES;
}

- (BOOL)handleRemoveChildViewController:(UIViewController *)childController
{
  NSAssert(childController, @"Avoid passing in nothing for child-controller.");
  if (!childController) {
    return NO;
  }
  [childController willMoveToParentViewController:nil];
  [childController.view removeFromSuperview];
  [childController removeFromParentViewController];
  NSUInteger index = [self.orderedChildViewControllers indexOfObject:childController]; //-- Save index beforehand.
  [self.orderedChildViewControllers removeObject:childController];
  if ([childController isKindOfClass:[UICollectionViewController class]]) {
    [[(UICollectionViewController *)childController collectionView].panGestureRecognizer removeTarget:self action:NULL];
  }
  if (index < self.currentChildIndex && self.currentChildIndex > 0) {
    self.currentChildIndex--;
  }
  //NSLog(@"Cleared index: %d", index);
  return YES;
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture
{
  //-- TODO: Finally: Consider how to split this up.
  BOOL isHorizontal = self.baseNavigationDirection == UAFNavigationDirectionHorizontal;
  BOOL shouldCancel = NO;
  CGPoint translation = [gesture translationInView:gesture.view];
  CGPoint velocity    = [gesture velocityInView:gesture.view];
  CGFloat translationValue = isHorizontal ? translation.x : translation.y;
  CGFloat velocityValue    = isHorizontal ? velocity.x : velocity.y;
  //-- Start.
  if (gesture.state == UIGestureRecognizerStateBegan) {
    self.flags |= FlagCanHandlePan;
    //-- Identify as needed.
    self.previousView = (self.currentChildIndex > 0)
    ? [self.orderedChildViewControllers[self.currentChildIndex - 1] view] : nil;
    self.nextView = (self.currentChildIndex < self.orderedChildViewControllers.count - 1)
    ? [self.orderedChildViewControllers[self.currentChildIndex + 1] view] : nil;
    self.currentView = [self.orderedChildViewControllers[self.currentChildIndex] view];
  }
  //-- /Start.
  //-- Guards.
  //-- Scrolling conflict resolution.
  //-- TODO: Also: Try alternative with `requireGestureRecognizerToFail:`.
  //-- TODO: Finally: Handle `nextView`.
  if ([gesture.view isKindOfClass:[UIScrollView class]]) {
    if (self.previousView) {
      UIScrollView *scrollView = (id)gesture.view;
      CGPoint velocity = [gesture velocityInView:gesture.view];
      void (^togglePanStealing)(BOOL) = ^(BOOL on) {
        if (on) {
          self.flags |= FlagIsStealingPan;
        } else {
          self.flags &= ~FlagIsStealingPan;
        }
        if (isHorizontal) {
          scrollView.showsHorizontalScrollIndicator = !on; //-- TODO: Finally: Don't be assumptive about previous value.
        } else {
          scrollView.showsVerticalScrollIndicator = !on;
        }
      };
      //NSLog(@"%f", [gesture velocityInView:gesture.view].y);
      BOOL shouldDismiss = ((isHorizontal ? scrollView.contentOffset.x : scrollView.contentOffset.y) <= 0.0f
                            && (isHorizontal ? velocity.x : velocity.y) > 0.0f); //-- NOTE: Refactor with `velocityValue` as needed.
      if (!shouldDismiss && !(self.flags & FlagIsStealingPan)) {
        return;
      } else if (gesture.state == UIGestureRecognizerStateBegan) {
        togglePanStealing(YES);
      }
      if (!(self.flags & FlagIsStealingPan)) {
        return;
      } else if (self.flags & FlagIsStealingPan && gesture.state != UIGestureRecognizerStateEnded) {
        scrollView.contentOffset = CGPointZero; //-- TODO: Also: Account for content-insets?
      } else if (gesture.state == UIGestureRecognizerStateEnded) {
        togglePanStealing(NO);
      }
    } else {
      return;
    }
  }
  //-- Only handle supported directions.
  if (!(self.flags & FlagCanHandlePan)) {
    return;
  } else if ((isHorizontal && ABS(velocity.x) < ABS(velocity.y))
             || (!isHorizontal && ABS(velocity.y) < ABS(velocity.x))
             ) {
    //NSLog(@"Can't handle gesture (%@).", NSStringFromClass(self.class));
    self.flags &= ~FlagCanHandlePan;
    shouldCancel = YES;
  }
  //-- Only continue if `bounces` option is on when at a boundary.
  if (!self.bounces) {
    BOOL isNextBoundary     = translationValue < 0 && !self.nextView;
    BOOL isPreviousBoundary = translationValue > 0 && !self.previousView;
    if (isNextBoundary || isPreviousBoundary) {
      return;
    }
  }
  //-- /Guards.
  //-- Update.
  CGAffineTransform transform =
  CGAffineTransformMakeTranslation(isHorizontal ? translation.x : 0.0f,
                                   isHorizontal ? 0.0f : translation.y);
  //-- Set transforms.
  self.previousView.transform = self.currentView.transform = self.nextView.transform = transform;
  //-- /Update.
  //-- Finalize.
  if (gesture.state == UIGestureRecognizerStateEnded
      || gesture.state == UIGestureRecognizerStateCancelled
      || gesture.state == UIGestureRecognizerStateFailed
      || shouldCancel
      ) {
    //-- Layout.
    CGPoint initialCenter = self.currentView.center;
    CGPoint currentCenter = CGPointMake(isHorizontal ? (initialCenter.x + translation.x) : initialCenter.x,
                                        isHorizontal ? initialCenter.y : (initialCenter.y + translation.y));
    CGFloat currentSide   = isHorizontal ? self.currentView.width : self.currentView.height;
    CGFloat containerSide = isHorizontal ? self.containerView.width : self.containerView.height;
    CGPoint (^makeFinalCenter)(UIView *) = ^(UIView *view) {
      return CGPointMake(isHorizontal ? (view.center.x + translation.x) : view.center.x,
                         isHorizontal ? view.center.y : (view.center.y + translation.y));
    };
    CGPoint (^makeFinalOffsetForCurrentView)(NSInteger) = ^(NSInteger direction) {
      return CGPointMake(isHorizontal ? (initialCenter.x - direction * self.currentView.width) : initialCenter.x,
                         isHorizontal ? initialCenter.y : (initialCenter.y - direction * self.currentView.height));
    };
    NSTimeInterval (^makeFinalFinishDuration)(NSTimeInterval) = ^(NSTimeInterval duration) {
      return MIN(MAX(duration, self.finishTransitionDurationMinimum), self.baseNavigationDuration);
    };
    void (^resetTransforms)(void) = ^{
      self.previousView.transform = self.currentView.transform = self.nextView.transform = CGAffineTransformIdentity;
    };
    //-- /Layout.
    NSTimeInterval finishDuration = self.baseNavigationDuration;
    BOOL finishedPanToNext      = !shouldCancel && (self.nextView && translationValue + (velocityValue / 2.0f) < -containerSide / 2.0f);
    BOOL finishedPanToPrevious  = !shouldCancel && (self.previousView && translationValue + (velocityValue / 2.0f) > containerSide / 2.0f);
    void (^handleDidShow)(BOOL) = nil;
    if (finishedPanToNext || finishedPanToPrevious) {
      //-- Reset transforms.
      resetTransforms();
      finishDuration *= (currentSide / 2.0f) / ABS((translationValue + (velocityValue / 2.0f)) / self.finishTransitionDurationFactor);
      finishDuration = makeFinalFinishDuration(finishDuration);
      UIViewController *newViewController = self.orderedChildViewControllers[self.currentChildIndex + (finishedPanToNext ? 1 : -1)];
      [self delegateWillShowViewController:newViewController animated:YES];
      handleDidShow = ^(BOOL finished) {
        [self delegateDidShowViewController:newViewController animated:YES];
        [self updateChildViewControllerTilingIfNeeded];
      };
    }
    UIViewAnimationOptions easingOptions = (ABS(translationValue) > 300.0f && (finishedPanToNext || finishedPanToPrevious))
    ? UIViewAnimationOptionCurveEaseOut : UIViewAnimationOptionCurveEaseInOut;
    if (finishedPanToNext) {
      //-- Layout and animate from midway.
      CGPoint previousOffset = makeFinalOffsetForCurrentView(1);
      CGPoint nextCenter = makeFinalCenter(self.nextView);
      self.currentView.center = currentCenter;
      self.nextView.center = nextCenter;
      void (^finishLayout)(void) = ^{
        self.currentView.center = previousOffset;
        self.nextView.center = initialCenter;
      };
      self.currentChildIndex++;
      [UIView animateWithDuration:finishDuration delay:0.0f options:easingOptions
                       animations:finishLayout completion:handleDidShow];
    } else if (finishedPanToPrevious) {
      //-- Layout and animate from midway.
      CGPoint nextOffset = makeFinalOffsetForCurrentView(-1);
      CGPoint previousCenter = makeFinalCenter(self.previousView);
      self.currentView.center = currentCenter;
      self.previousView.center = previousCenter;
      void (^finishLayout)(void) = ^{
        self.currentView.center = nextOffset;
        self.previousView.center = initialCenter;
      };
      self.currentChildIndex--;
      [UIView animateWithDuration:finishDuration delay:0.0f options:easingOptions
                       animations:finishLayout completion:handleDidShow];
    } else {
      //-- Just update animated.
      finishDuration *= ABS((translationValue + (velocityValue / 2.0f)) / (currentSide / 2.0f) / self.finishTransitionDurationFactor);
      finishDuration = makeFinalFinishDuration(finishDuration);
      [UIView animateWithDuration:finishDuration delay:0.0f options:easingOptions
                       animations:resetTransforms completion:handleDidShow];
    }
    //NSLog(@"%f", velocityValue);
    //NSLog(@"%f", translationValue);
    //NSLog(@"%f", finishDuration);
  }
}

- (BOOL)delegateWillAddViewController:(UIViewController *)viewController
{
  if (!(self.flags & FlagCanDelegate)) {
    return NO;
  }
  SEL selector = @selector(customNavigationController:willAddViewController:);
  if ([self.delegate respondsToSelector:selector]) {
    [self.delegate customNavigationController:self willAddViewController:viewController];
  }
  if (self.visibleViewController && [self.visibleViewController respondsToSelector:selector]) {
    [(id)self.visibleViewController customNavigationController:self willAddViewController:viewController];
  }
  return YES;
}
- (BOOL)delegateWillShowViewController:(UIViewController *)viewController animated:(BOOL)animated
{
  if (!(self.flags & FlagCanDelegate)) {
    return NO;
  }
  BOOL dismissed = [self.orderedChildViewControllers indexOfObject:viewController] < self.currentChildIndex;
  SEL selector = @selector(customNavigationController:willShowViewController:animated:dismissed:);
  if ([self.delegate respondsToSelector:selector]) {
    [self.delegate customNavigationController:self willShowViewController:viewController animated:animated dismissed:dismissed];
  }
  if (self.visibleViewController) {
    [self.visibleViewController viewWillDisappear:animated];
    if ([self.visibleViewController respondsToSelector:selector]) {
      [(id)self.visibleViewController customNavigationController:self willShowViewController:viewController animated:animated dismissed:dismissed];
    }
  }
  [viewController viewWillAppear:animated];
  return YES;
}

- (BOOL)delegateDidShowViewController:(UIViewController *)viewController animated:(BOOL)animated
{
  if (!(self.flags & FlagCanDelegate)) {
    return NO;
  }
  BOOL dismissed = [self.orderedChildViewControllers indexOfObject:viewController] < self.currentChildIndex;
  SEL selector = @selector(customNavigationController:didShowViewController:animated:dismissed:);
  if ([self.delegate respondsToSelector:selector]) {
    [self.delegate customNavigationController:self didShowViewController:viewController animated:animated dismissed:dismissed];
  }
  if (self.visibleViewController) {
    [self.visibleViewController viewDidDisappear:animated];
    if ([self.visibleViewController respondsToSelector:selector]) {
      [(id)self.visibleViewController customNavigationController:self didShowViewController:viewController animated:animated dismissed:dismissed];
    }
  }
  [viewController viewDidAppear:animated];
  return YES;
}

- (BOOL)updateChildViewControllerTilingIfNeeded
{
  if (!self.pagingEnabled || !self.pagingDelegate) {
    return NO;
  }
  [self cleanChildViewControllers];
  BOOL didUpdate = NO;
  UIViewController *nextViewController = [self.pagingDelegate customNavigationController:self viewControllerAfterViewController:self.visibleViewController];
  UIViewController *previousViewController = [self.pagingDelegate customNavigationController:self viewControllerBeforeViewController:self.visibleViewController];
  if (nextViewController && self.currentChildIndex == self.orderedChildViewControllers.count - 1) {
    didUpdate = [self pushViewController:nextViewController animated:NO focused:NO];
  }
  if (previousViewController && self.currentChildIndex == 0) {
    didUpdate = [self addChildViewController:previousViewController animated:NO focused:NO next:NO];
    if (didUpdate) {
      self.currentChildIndex++;
    }
  }
  if (didUpdate) {
    NSAssert(self.orderedChildViewControllers.count == 3
             || (!(previousViewController && nextViewController) && self.orderedChildViewControllers.count == 2),
             @"Tiling had errors. %@", self.orderedChildViewControllers);
  }
  return didUpdate;
}

#pragma mark - UIGestureRecognizerDelegate

//-- NOTE: Subclassing the gesture-recognizer can allow setting recognizer priority / prevention.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
  return ([otherGestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]
          && ![otherGestureRecognizer.view isKindOfClass:[UIScrollView class]]);
}

@end
