/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import "CKFlexboxComponent.h"

#import "yoga/Yoga.h"

#import "CKComponentSubclass.h"
#import "CKComponentInternal.h"
#import "CKInternalHelpers.h"
#import "CKComponentLayout.h"
#import "CKComponentLayoutBaseline.h"

const struct CKStackComponentLayoutExtraKeys CKStackComponentLayoutExtraKeys = {
  .hadOverflow = @"hadOverflow"
};

/*
 This class contains information about cached layout for FlexboxComponent child
 */
@interface CKFlexboxChildCachedLayout : NSObject

@property (nonatomic) CKComponent *component;
@property (nonatomic) CKComponentLayout componentLayout;
@property (nonatomic) float width;
@property (nonatomic) float height;
@property (nonatomic) YGMeasureMode widthMode;
@property (nonatomic) YGMeasureMode heightMode;
@property (nonatomic) CGSize parentSize;
@property (nonatomic) CKFlexboxAlignSelf align;
@property (nonatomic) NSInteger zIndex;

@end

template class std::vector<CKFlexboxComponentChild>;

@implementation CKFlexboxChildCachedLayout

@end

@implementation CKFlexboxComponent {
  CKFlexboxComponentStyle _style;
  std::vector<CKFlexboxComponentChild> _children;
}

+ (instancetype)newWithView:(const CKComponentViewConfiguration &)view
                       size:(const CKComponentSize &)size
                      style:(const CKFlexboxComponentStyle &)style
                   children:(CKContainerWrapper<std::vector<CKFlexboxComponentChild>> &&)children
{
  CKFlexboxComponent * const component = [super newWithView:view size:size];
  if (component) {
    component->_style = style;
    component->_children = children.take();
  }
  return component;
}

static YGConfigRef ckYogaDefaultConfig()
{
  static YGConfigRef defaultConfig;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    defaultConfig = YGConfigNew();
    YGConfigSetPointScaleFactor(defaultConfig, [UIScreen mainScreen].scale);
  });
  return defaultConfig;
}

static YGSize measureYGComponent(YGNodeRef node,
                                  float width,
                                  YGMeasureMode widthMode,
                                  float height,
                                  YGMeasureMode heightMode)
{
  CKFlexboxChildCachedLayout *cachedLayout = (__bridge CKFlexboxChildCachedLayout *)YGNodeGetContext(node);
  const CGSize minSize = {
    .width = (widthMode == YGMeasureModeExactly) ? width : 0,
    .height = (heightMode == YGMeasureModeExactly) ? height : 0
  };
  const CGSize maxSize = {
    .width = (widthMode == YGMeasureModeExactly || widthMode == YGMeasureModeAtMost) ? width : INFINITY,
    .height = (heightMode == YGMeasureModeExactly || heightMode == YGMeasureModeAtMost) ? height : INFINITY
  };
  // We cache measurements for the duration of single layout calculation of FlexboxComponent
  // ComponentKit and Yoga handle caching between calculations
  // We don't have any guarantees about when and how this will be called,
  // so we just cache the results to try to reuse them during final layout
  if (!YGNodeCanUseCachedMeasurement(widthMode, width, heightMode, height,
                                     cachedLayout.widthMode, cachedLayout.width, cachedLayout.heightMode, cachedLayout.height,
                                     cachedLayout.componentLayout.size.width, cachedLayout.componentLayout.size.height, 0, 0,
                                     ckYogaDefaultConfig())) {
    CKComponent *component = cachedLayout.component;
    CKComponentLayout componentLayout = CKComputeComponentLayout(component, CKSizeRange(minSize, maxSize), cachedLayout.parentSize);
    cachedLayout.componentLayout = componentLayout;
    cachedLayout.width = width;
    cachedLayout.height = height;
    cachedLayout.widthMode = widthMode;
    cachedLayout.heightMode = heightMode;
  }
  return {static_cast<float>(cachedLayout.componentLayout.size.width), static_cast<float>(cachedLayout.componentLayout.size.height)};
}

static float computeBaseline(YGNodeRef node, const float width, const float height)
{
  CKFlexboxChildCachedLayout *cachedLayout = (__bridge CKFlexboxChildCachedLayout *)YGNodeGetContext(node);

  if (!YGNodeCanUseCachedMeasurement(YGMeasureModeExactly, width, YGMeasureModeExactly, height,
                                    cachedLayout.widthMode, cachedLayout.width,
                                    cachedLayout.heightMode, cachedLayout.height,
                                    cachedLayout.componentLayout.size.width, cachedLayout.componentLayout.size.height, 0, 0,
                                    ckYogaDefaultConfig())) {
    CKComponent *component = cachedLayout.component;
    CGSize fixedSize = {width, height};
    CKComponentLayout componentLayout = CKComputeComponentLayout(component, CKSizeRange(fixedSize, fixedSize), cachedLayout.parentSize);
    cachedLayout.componentLayout = componentLayout;
    cachedLayout.width = width;
    cachedLayout.height = height;
    cachedLayout.widthMode = YGMeasureModeExactly;
    cachedLayout.heightMode = YGMeasureModeExactly;
  }

  if ([cachedLayout.componentLayout.extra objectForKey:kCKComponentLayoutExtraBaselineKey]) {
    CKCAssert([[cachedLayout.componentLayout.extra objectForKey:kCKComponentLayoutExtraBaselineKey] isKindOfClass:[NSNumber class]], @"You must set a NSNumber for kCKComponentLayoutExtraBaselineKey");
    return [[cachedLayout.componentLayout.extra objectForKey:kCKComponentLayoutExtraBaselineKey] floatValue];
  }

  return height;
}

static YGFlexDirection ygDirectionFromStackStyle(const CKFlexboxComponentStyle &style)
{
  switch (style.direction) {
    case CKFlexboxDirectionHorizontal:
      return YGFlexDirectionRow;
    case CKFlexboxDirectionVertical:
      return YGFlexDirectionColumn;
    case CKFlexboxDirectionHorizontalReverse:
      return YGFlexDirectionRowReverse;
    case CKFlexboxDirectionVerticalReverse:
      return YGFlexDirectionColumnReverse;
  }
}

static YGJustify ygJustifyFromStackStyle(const CKFlexboxComponentStyle &style)
{
  switch (style.justifyContent) {
    case CKFlexboxJustifyContentCenter:
      return YGJustifyCenter;
    case CKFlexboxJustifyContentEnd:
      return YGJustifyFlexEnd;
    case CKFlexboxJustifyContentStart:
      return YGJustifyFlexStart;
    case CKFlexboxJustifyContentSpaceBetween:
      return YGJustifySpaceBetween;
    case CKFlexboxJustifyContentSpaceAround:
      return YGJustifySpaceAround;
  }
}

static YGAlign ygAlignItemsFromStackStyle(const CKFlexboxComponentStyle &style)
{
  switch (style.alignItems) {
    case CKFlexboxAlignItemsEnd:
      return YGAlignFlexEnd;
    case CKFlexboxAlignItemsCenter:
      return YGAlignCenter;
    case CKFlexboxAlignItemsStretch:
      return YGAlignStretch;
    case CKFlexboxAlignItemsBaseline:
      return YGAlignBaseline;
    case CKFlexboxAlignItemsStart:
      return YGAlignFlexStart;
  }
}

static YGAlign ygAlignContentFromStackStyle(const CKFlexboxComponentStyle &style)
{
  switch (style.alignContent) {
    case CKFlexboxAlignContentEnd:
      return YGAlignFlexEnd;
    case CKFlexboxAlignContentCenter:
      return YGAlignCenter;
    case CKFlexboxAlignContentStretch:
      return YGAlignStretch;
    case CKFlexboxAlignContentStart:
      return YGAlignFlexStart;
    case CKFlexboxAlignContentSpaceAround:
      return YGAlignSpaceAround;
    case CKFlexboxAlignContentSpaceBetween:
      return YGAlignSpaceBetween;
  }
}

static YGAlign ygAlignFromChild(const CKFlexboxComponentChild &child)
{
  switch (child.alignSelf) {
    case CKFlexboxAlignSelfStart:
      return YGAlignFlexStart;
    case CKFlexboxAlignSelfEnd:
      return YGAlignFlexEnd;
    case CKFlexboxAlignSelfCenter:
      return YGAlignCenter;
    case CKFlexboxAlignSelfBaseline:
      return YGAlignBaseline;
    case CKFlexboxAlignSelfStretch:
      return YGAlignStretch;
    case CKFlexboxAlignSelfAuto:
      return YGAlignAuto;
  }
}

static YGWrap ygWrapFromStackStyle(const CKFlexboxComponentStyle &style)
{
  switch (style.wrap) {
    case CKFlexboxWrapNoWrap:
      return YGWrapNoWrap;
    case CKFlexboxWrapWrap:
      return YGWrapWrap;
    case CKFlexboxWrapWrapReverse:
      return YGWrapWrapReverse;
  }
}

static YGEdge ygSpacingEdgeFromDirection(const CKFlexboxDirection &direction, BOOL reverse = NO)
{
  switch (direction) {
    case CKFlexboxDirectionVertical:
      return reverse ? YGEdgeBottom : YGEdgeTop;
    case CKFlexboxDirectionVerticalReverse:
      return reverse ? YGEdgeTop : YGEdgeBottom;
    case CKFlexboxDirectionHorizontal:
      return reverse ? YGEdgeEnd : YGEdgeStart;
    case CKFlexboxDirectionHorizontalReverse:
      return reverse ? YGEdgeStart : YGEdgeEnd;
  }
}

static BOOL isHorizontalFlexboxDirection(const CKFlexboxDirection &direction)
{
  switch (direction) {
    case CKFlexboxDirectionVertical:
    case CKFlexboxDirectionVerticalReverse:
      return NO;
    case CKFlexboxDirectionHorizontal:
    case CKFlexboxDirectionHorizontalReverse:
      return YES;
  }
}

/*
 layoutCache is passed by reference so that we are able to allocate it in one thread
 and mutate it within that thread
 Layout cache shouldn't be exposed publicly
 */
- (YGNodeRef)ygStackLayoutNode:(CKSizeRange)constrainedSize
{
  const YGNodeRef stackNode = YGNodeNewWithConfig(ckYogaDefaultConfig());
  YGEdge spacingEdge = ygSpacingEdgeFromDirection(_style.direction);
  CGFloat savedSpacing = 0;
  // We need this to resolve CKRelativeDimension with percentage bases
  CGFloat parentWidth = (constrainedSize.min.width == constrainedSize.max.width) ? constrainedSize.min.width : kCKComponentParentDimensionUndefined;
  CGFloat parentHeight = (constrainedSize.min.height == constrainedSize.max.height) ? constrainedSize.min.height : kCKComponentParentDimensionUndefined;
  CGFloat parentMainDimension = isHorizontalFlexboxDirection(_style.direction) ? parentWidth : parentHeight;
  CGSize parentSize = CGSizeMake(parentWidth, parentHeight);

  const auto children = CK::filter(_children, [](const CKFlexboxComponentChild &child){
    return child.component != nil;
  });

  for (auto iterator = children.begin(); iterator != children.end(); iterator++) {
    const CKFlexboxComponentChild child = *iterator;
    CKComponent *childComponent = child.component;
    const YGNodeRef childNode = YGNodeNewWithConfig(ckYogaDefaultConfig());

    // We add object only if there is actual used element
    CKFlexboxChildCachedLayout *childLayout = [CKFlexboxChildCachedLayout new];
    childLayout.component = child.component;
    childLayout.componentLayout = {child.component, {0, 0}};
    childLayout.widthMode = (YGMeasureMode) -1;
    childLayout.heightMode = (YGMeasureMode) -1;
    childLayout.parentSize = parentSize;
    childLayout.align = child.alignSelf;
    childLayout.zIndex = child.zIndex;
    if (child.aspectRatio.isDefined()) {
      YGNodeStyleSetAspectRatio(childNode, child.aspectRatio.aspectRatio());
    }

    // We pass the pointer ownership to context to release it later.
    // We want cachedLayout to be alive until we've finished calculations
    YGNodeSetContext(childNode, (__bridge_retained void *)childLayout);
    YGNodeSetMeasureFunc(childNode, measureYGComponent);
    YGNodeSetBaselineFunc(childNode, computeBaseline);

    const CKComponentSize childComponentSize = [childComponent size];

    YGNodeStyleSetWidth(childNode, childComponentSize.width.resolve(YGUndefined, parentWidth));
    YGNodeStyleSetHeight(childNode, childComponentSize.height.resolve(YGUndefined, parentHeight));
    YGNodeStyleSetMinWidth(childNode, childComponentSize.minWidth.resolve(YGUndefined, parentWidth));
    YGNodeStyleSetMinHeight(childNode, childComponentSize.minHeight.resolve(YGUndefined, parentHeight));
    YGNodeStyleSetMaxWidth(childNode, childComponentSize.maxWidth.resolve(YGUndefined, parentWidth));
    YGNodeStyleSetMaxHeight(childNode, childComponentSize.maxHeight.resolve(YGUndefined, parentHeight));

    YGNodeStyleSetFlexGrow(childNode, child.flexGrow);
    YGNodeStyleSetFlexShrink(childNode, child.flexShrink);
    YGNodeStyleSetAlignSelf(childNode, ygAlignFromChild(child));
    YGNodeStyleSetFlexBasis(childNode, child.flexBasis.resolve(YGUndefined, parentMainDimension));
    // TODO: t18095186 Remove explicit opt-out when Yoga is going to move to opt-in for text rounding
    YGNodeSetNodeType(childNode, child.useTextRounding ? YGNodeTypeText : YGNodeTypeDefault);

    YGNodeStyleSetPosition(childNode, YGEdgeStart, child.position.start.resolve(YGUndefined, parentMainDimension));
    YGNodeStyleSetPosition(childNode, YGEdgeEnd, child.position.end.resolve(YGUndefined, parentMainDimension));
    YGNodeStyleSetPosition(childNode, YGEdgeTop, child.position.top.resolve(YGUndefined, parentHeight));
    YGNodeStyleSetPosition(childNode, YGEdgeBottom, child.position.bottom.resolve(YGUndefined, parentHeight));
    YGNodeStyleSetPosition(childNode, YGEdgeLeft, child.position.left.resolve(YGUndefined, parentWidth));
    YGNodeStyleSetPosition(childNode, YGEdgeRight, child.position.right.resolve(YGUndefined, parentWidth));

    applyPaddingToEdge(childNode, YGEdgeTop, child.padding.top);
    applyPaddingToEdge(childNode, YGEdgeBottom, child.padding.bottom);
    applyPaddingToEdge(childNode, YGEdgeStart, child.padding.start);
    applyPaddingToEdge(childNode, YGEdgeEnd, child.padding.end);

    YGNodeStyleSetPositionType(childNode, (child.position.type == CKFlexboxPositionTypeAbsolute) ? YGPositionTypeAbsolute : YGPositionTypeRelative);

    if ((fabs(_style.spacing) > FLT_EPSILON || fabs(child.spacingBefore) > FLT_EPSILON || fabs(child.spacingAfter) > FLT_EPSILON)
            && childHasMarginSet(child)) {
      CKFailAssert(@"You shouldn't use both margin and spacing! Ignoring spacing and falling back to margin behavior.");
    }
    // Spacing emulation
    // Stack layout defines spacing in terms of parent Spacing (used only between children) and
    // spacingAfter / spacingBefore for every children
    // Yoga defines spacing in terms of Parent padding and Child margin
    // To avoid confusion for all children spacing is emulated with Start Margin
    // We only use End Margin for the last child to emulate space between it and parent
    if (iterator != children.begin()) {
      // Children in the middle have margin = spacingBefore + spacingAfter of previous + spacing of parent
      YGNodeStyleSetMargin(childNode, spacingEdge, child.spacingBefore + _style.spacing + savedSpacing);
    } else {
      // For the space between parent and first child we just use spacingBefore
      YGNodeStyleSetMargin(childNode, spacingEdge, child.spacingBefore);
    }
    YGNodeInsertChild(stackNode, childNode, YGNodeGetChildCount(stackNode));

    savedSpacing = child.spacingAfter;
    if (next(iterator) == children.end()) {
      // For the space between parent and last child we use only spacingAfter
      YGNodeStyleSetMargin(childNode, ygSpacingEdgeFromDirection(_style.direction, YES), savedSpacing);
    }

    /** The margins will override any spacing we applied earlier */
    applyMarginToEdge(childNode, YGEdgeTop, child.margin.top);
    applyMarginToEdge(childNode, YGEdgeBottom, child.margin.bottom);
    applyMarginToEdge(childNode, YGEdgeStart, child.margin.start);
    applyMarginToEdge(childNode, YGEdgeEnd, child.margin.end);
  }

  YGNodeStyleSetFlexDirection(stackNode, ygDirectionFromStackStyle(_style));
  YGNodeStyleSetJustifyContent(stackNode, ygJustifyFromStackStyle(_style));
  YGNodeStyleSetAlignItems(stackNode, ygAlignItemsFromStackStyle(_style));
  YGNodeStyleSetAlignContent(stackNode, ygAlignContentFromStackStyle(_style));
  YGNodeStyleSetFlexWrap(stackNode, ygWrapFromStackStyle(_style));
  // TODO: t18095186 Remove explicit opt-out when Yoga is going to move to opt-in for text rounding
  YGNodeSetNodeType(stackNode, YGNodeTypeDefault);

  applyPaddingToEdge(stackNode, YGEdgeTop, _style.padding.top);
  applyPaddingToEdge(stackNode, YGEdgeBottom, _style.padding.bottom);
  applyPaddingToEdge(stackNode, YGEdgeStart, _style.padding.start);
  applyPaddingToEdge(stackNode, YGEdgeEnd, _style.padding.end);

  applyMarginToEdge(stackNode, YGEdgeTop, _style.margin.top);
  applyMarginToEdge(stackNode, YGEdgeBottom, _style.margin.bottom);
  applyMarginToEdge(stackNode, YGEdgeStart, _style.margin.start);
  applyMarginToEdge(stackNode, YGEdgeEnd, _style.margin.end);

  return stackNode;
}

static void applyPaddingToEdge(YGNodeRef node, YGEdge edge, CKFlexboxDimension value)
{
  CKRelativeDimension dimension = value.dimension();

  switch (dimension.type()) {
    case CKRelativeDimension::Type::PERCENT:
      YGNodeStyleSetPaddingPercent(node, edge, dimension.value() * 100);
      break;
    case CKRelativeDimension::Type::POINTS:
      YGNodeStyleSetPadding(node, edge, dimension.value());
      break;
    case CKRelativeDimension::Type::AUTO:
      // no-op
      break;
  }
}

static void applyMarginToEdge(YGNodeRef node, YGEdge edge, CKFlexboxDimension value)
{
  if (value.isDefined() == false) {
    return;
  }

  CKRelativeDimension relativeDimension = value.dimension();
  switch (relativeDimension.type()) {
    case CKRelativeDimension::Type::PERCENT:
      YGNodeStyleSetMarginPercent(node, edge, relativeDimension.value() * 100);
      break;
    case CKRelativeDimension::Type::POINTS:
      YGNodeStyleSetMargin(node, edge, relativeDimension.value());
      break;
    case CKRelativeDimension::Type::AUTO:
      YGNodeStyleSetMarginAuto(node, edge);
      break;
  }
}

static BOOL childHasMarginSet(CKFlexboxComponentChild child)
{
  return
  marginIsSet(child.margin.top) ||
  marginIsSet(child.margin.bottom) ||
  marginIsSet(child.margin.start) ||
  marginIsSet(child.margin.end);
}

static BOOL marginIsSet(CKFlexboxDimension margin)
{
  if (margin.isDefined() == false) {
    return false;
  }

  switch(margin.dimension().type()) {
    case CKRelativeDimension::Type::PERCENT:
      return fabs(margin.dimension().value()) > FLT_EPSILON;
    case CKRelativeDimension::Type::POINTS:
      return fabs(margin.dimension().value()) > FLT_EPSILON;
    case CKRelativeDimension::Type::AUTO:
      return false;
  }
}

- (CKComponentLayout)computeLayoutThatFits:(CKSizeRange)constrainedSize
{
  // We create cache for the duration of single calculation, so it is used only on one thread
  // The cache is strictly internal and shouldn't be exposed in any way
  // The purpose of the cache is to save calculations done in measure() function in Yoga to reuse
  // for final layout
  YGNodeRef layoutNode = [self ygNode:constrainedSize];

  YGNodeCalculateLayout(layoutNode, YGUndefined, YGUndefined, YGDirectionLTR);

  // Before we finalize layout we want to sort children according to their z-order
  // We want children with higher z-order to be closer to the end of list
  // They should be mounted later and thus shown on top of children with lower z-order  const NSInteger childCount = YGNodeGetChildCount(layoutNode);
  const NSInteger childCount = YGNodeGetChildCount(layoutNode);
  std::vector<YGNodeRef> sortedChildNodes(childCount);
  for (uint32_t i = 0; i < childCount; i++) {
    sortedChildNodes[i] = YGNodeGetChild(layoutNode, i);
  }
  std::sort(sortedChildNodes.begin(), sortedChildNodes.end(),
            [] (YGNodeRef const& a, YGNodeRef const& b) {
              CKFlexboxChildCachedLayout *aCachedContext = (__bridge CKFlexboxChildCachedLayout *)YGNodeGetContext(a);
              CKFlexboxChildCachedLayout *bCachedContext = (__bridge CKFlexboxChildCachedLayout *)YGNodeGetContext(b);
              return aCachedContext.zIndex < bCachedContext.zIndex;
            });

  std::vector<CKComponentLayoutChild> childrenLayout(childCount);
  const float width = YGNodeLayoutGetWidth(layoutNode);
  const float height = YGNodeLayoutGetHeight(layoutNode);
  const CGSize size = {width, height};
  for (NSUInteger i = 0; i < childCount; i++) {
    // Get the layout for every child
    const YGNodeRef childNode = sortedChildNodes[i];
    const CGFloat childX = YGNodeLayoutGetLeft(childNode);
    const CGFloat childY = YGNodeLayoutGetTop(childNode);
    const CGFloat childWidth = YGNodeLayoutGetWidth(childNode);
    const CGFloat childHeight = YGNodeLayoutGetHeight(childNode);
    // Now we take back pointer ownership to be released, as we won't need it anymore
    CKFlexboxChildCachedLayout *childCachedLayout = (__bridge_transfer CKFlexboxChildCachedLayout *)YGNodeGetContext(childNode);

    childrenLayout[i].position = CGPointMake(childX, childY);
    const CGSize childSize = CGSizeMake(childWidth, childHeight);
    // We cache measurements for the duration of single layout calculation of FlexboxComponent
    // ComponentKit and Yoga handle caching between calculations

    // We can reuse caching even if main dimension isn't exact, but we did AtMost measurement previously
    // However we might need to measure anew if child needs to be stretched
    YGMeasureMode verticalReusedMode = YGMeasureModeAtMost;
    YGMeasureMode horizontalReusedMode = YGMeasureModeAtMost;
    if (childCachedLayout.align == CKFlexboxAlignSelfStretch ||
        (childCachedLayout.align == CKFlexboxAlignSelfAuto && _style.alignItems == CKFlexboxAlignItemsStretch)) {
      if (isHorizontalFlexboxDirection(_style.direction)) {
        verticalReusedMode = YGMeasureModeExactly;
      } else {
        horizontalReusedMode = YGMeasureModeExactly;
      }
    }

    if (YGNodeCanUseCachedMeasurement(horizontalReusedMode, childWidth, verticalReusedMode, childHeight,
                                      childCachedLayout.widthMode, childCachedLayout.width,
                                      childCachedLayout.heightMode, childCachedLayout.height,
                                      childCachedLayout.componentLayout.size.width,
                                      childCachedLayout.componentLayout.size.height, 0, 0,
                                      ckYogaDefaultConfig()) ||
        YGNodeCanUseCachedMeasurement(YGMeasureModeExactly, childWidth, YGMeasureModeExactly, childHeight,
                                      childCachedLayout.widthMode, childCachedLayout.width,
                                      childCachedLayout.heightMode, childCachedLayout.height,
                                      childCachedLayout.componentLayout.size.width, childCachedLayout.componentLayout.size.height, 0, 0,
                                      ckYogaDefaultConfig()) ||
        childSize.width == 0 ||
        childSize.height == 0) {
      childrenLayout[i].layout = childCachedLayout.componentLayout;
    } else {
      childrenLayout[i].layout = CKComputeComponentLayout(childCachedLayout.component, {childSize, childSize}, size);
    }
    childrenLayout[i].layout.size = childSize;
  }

  YGNodeFreeRecursive(layoutNode);

  // width/height should already be within constrainedSize, but we're just clamping to correct for roundoff error
  return {self, constrainedSize.clamp({width, height}), childrenLayout};
}

/*
 layoutCache is passed by reference so that we are able to allocate it in one thread
 and mutate it within that thread
 Layout cache shouldn't be exposed publicly
 */
- (YGNodeRef)ygNode:(CKSizeRange)constrainedSize
{
  const YGNodeRef node = [self ygStackLayoutNode:constrainedSize];

  // At the moment Yoga does not optimise minWidth == maxWidth, so we want to do it here
  // ComponentKit and Yoga use different constants for +Inf, so we need to make sure the don't interfere
  if (constrainedSize.min.width == constrainedSize.max.width) {
    YGNodeStyleSetWidth(node, constrainedSize.min.width);
  } else {
    YGNodeStyleSetMinWidth(node, constrainedSize.min.width);
    if (constrainedSize.max.width == INFINITY) {
      YGNodeStyleSetMaxWidth(node, YGUndefined);
    } else {
      YGNodeStyleSetMaxWidth(node, constrainedSize.max.width);
    }
  }

  if (constrainedSize.min.height == constrainedSize.max.height) {
    YGNodeStyleSetHeight(node, constrainedSize.min.height);
  } else {
    YGNodeStyleSetMinHeight(node, constrainedSize.min.height);
    if (constrainedSize.max.height == INFINITY) {
      YGNodeStyleSetMaxHeight(node, YGUndefined);
    } else {
      YGNodeStyleSetMaxHeight(node, constrainedSize.max.height);
    }
  }
  return node;
}

@end