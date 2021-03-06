/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import <Foundation/Foundation.h>

#import <ComponentKit/CKComponentInternal.h>

@protocol CKTreeNodeProtocol;
@protocol CKTreeNodeWithChildrenProtocol;

namespace CKRender {
  auto buildComponentTreeWithPrecomputedChild(CKComponent *component,
                                              CKComponent *childComponent,
                                              id<CKTreeNodeWithChildrenProtocol> parent,
                                              id<CKTreeNodeWithChildrenProtocol> previousParent,
                                              const CKBuildComponentTreeParams &params,
                                              const CKBuildComponentConfig &config,
                                              BOOL hasDirtyParent) -> void;
  
  auto hasDirtyParent(id<CKTreeNodeProtocol> node,
                      id<CKTreeNodeWithChildrenProtocol> previousParent,
                      const CKBuildComponentTreeParams &params,
                      const CKBuildComponentConfig &config) -> BOOL;
}
