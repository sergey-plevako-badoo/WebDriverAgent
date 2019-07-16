//
//  Media.m
//  WebDriverAgentLib
//
//  Created by Sergey Plevako on 16/07/2019.
//  Copyright © 2019 Facebook. All rights reserved.
//

#import "Media.h"
#import "FBLogger.h"

@implementation Media
+ (void) delete {
 
  [FBLogger log:@"Deleting the assets"];
  
  // PHFetchResult *fetchedAssets = [PHAsset fetchAssetsWithMediaType: PHAssetMediaTypeImage options:nil];
  PHFetchResult *fetchedAssets = [PHAsset fetchAssetsWithOptions:nil];
  
  [FBLogger log: [NSString stringWithFormat:@"%lu", fetchedAssets.count]];
  
    [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
      
      [PHAssetChangeRequest deleteAssets:fetchedAssets];
    } error:nil];
 
   
  
//  [assets enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
//    NSLog(@"%@",[obj class]);
//    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
//      BOOL req = [obj canPerformEditOperation:PHAssetEditOperationDelete];
//      if (req) {
//        NSLog(@"the file is deleted");
//        [PHAssetChangeRequest deleteAssets:@[obj]];
//      }
//    } completionHandler:^(BOOL success, NSError *error) {
//      NSLog(@"Finished Delete asset. %@", (success ? @"Success." : error));
//      if (success) {
//        NSLog(@"Deleted successfully");
//      }
//      else {
//        NSLog(@"Unable to delete media %@", error);
//      }
//    }];
//  }];
}
@end
