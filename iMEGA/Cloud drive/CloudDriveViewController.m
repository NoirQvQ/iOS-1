#import "CloudDriveViewController.h"

#import <AVFoundation/AVCaptureDevice.h>
#import <AVFoundation/AVMediaFormat.h>
#import <MobileCoreServices/MobileCoreServices.h>

#import "SVProgressHUD.h"
#import "UIScrollView+EmptyDataSet.h"

#import "NSFileManager+MNZCategory.h"
#import "NSString+MNZCategory.h"
#import "UIAlertAction+MNZCategory.h"
#import "UIApplication+MNZCategory.h"
#import "UIImageView+MNZCategory.h"

#import "Helper.h"
#import "MEGACreateFolderRequestDelegate.h"
#import "MEGAMoveRequestDelegate.h"
#import "MEGANode+MNZCategory.h"
#import "MEGANodeList+MNZCategory.h"
#import "MEGAPurchase.h"
#import "MEGAReachabilityManager.h"
#import "MEGARemoveRequestDelegate.h"
#import "MEGASdkManager.h"
#import "MEGASdk+MNZCategory.h"
#import "MEGAShareRequestDelegate.h"
#import "MEGAStore.h"
#import "NSMutableArray+MNZCategory.h"

#import "BrowserViewController.h"
#import "ContactsViewController.h"
#import "CustomActionViewController.h"
#import "CustomModalAlertViewController.h"
#import "MEGAAssetsPickerController.h"
#import "MEGAImagePickerController.h"
#import "MEGANavigationController.h"
#import "MEGAPhotoBrowserViewController.h"
#import "NodeInfoViewController.h"
#import "NodeTableViewCell.h"
#import "PhotosViewController.h"
#import "PreviewDocumentViewController.h"
#import "SortByTableViewController.h"
#import "SharedItemsViewController.h"
#import "UpgradeTableViewController.h"

@interface CloudDriveViewController () <UINavigationControllerDelegate, UIDocumentPickerDelegate, UIDocumentMenuDelegate, UISearchBarDelegate, UISearchResultsUpdating, UIViewControllerPreviewingDelegate, DZNEmptyDataSetSource, DZNEmptyDataSetDelegate, MEGADelegate, MEGARequestDelegate, MGSwipeTableCellDelegate, CustomActionViewControllerDelegate, NodeInfoViewControllerDelegate, UITableViewDelegate, UITableViewDataSource> {
    BOOL allNodesSelected;
    
    MEGAShareType lowShareType; //Control the actions allowed for node/nodes selected
}

@property (weak, nonatomic) IBOutlet UITableView *tableView;

@property (weak, nonatomic) IBOutlet UIBarButtonItem *selectAllBarButtonItem;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *moreBarButtonItem;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *moreMinimizedBarButtonItem;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *editBarButtonItem;

@property (weak, nonatomic) IBOutlet UIToolbar *toolbar;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *downloadBarButtonItem;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *shareBarButtonItem;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *moveBarButtonItem;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *carbonCopyBarButtonItem;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *deleteBarButtonItem;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *restoreBarButtonItem;

@property (strong, nonatomic) UISearchController *searchController;

@property (nonatomic, strong) MEGANodeList *nodes;
@property (nonatomic, strong) NSArray *nodesArray;
@property (nonatomic, strong) NSMutableArray *searchNodesArray;

@property (nonatomic, strong) NSMutableArray *cloudImages;
@property (nonatomic, strong) NSMutableArray *selectedNodesArray;

@property (nonatomic, strong) NSMutableDictionary *nodesIndexPathMutableDictionary;

@property (nonatomic) id<UIViewControllerPreviewing> previewingContext;

@end

@implementation CloudDriveViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.tableView.emptyDataSetSource = self;
    self.tableView.emptyDataSetDelegate = self;
    
    self.tableView.estimatedRowHeight = 60.0;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    
    self.searchController = [Helper customSearchControllerWithSearchResultsUpdaterDelegate:self searchBarDelegate:self];
    self.tableView.tableHeaderView = self.searchController.searchBar;
    self.definesPresentationContext = YES;
    self.tableView.contentOffset = CGPointMake(0, CGRectGetHeight(self.searchController.searchBar.frame));
    
    [self setNavigationBarButtonItems];
    [self.toolbar setFrame:CGRectMake(0, 0, CGRectGetWidth(self.view.frame), 49)];
    self.toolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
    switch (self.displayMode) {
        case DisplayModeCloudDrive: {
            if (!self.parentNode) {
                self.parentNode = [[MEGASdkManager sharedMEGASdk] rootNode];
            }
            break;
        }
            
        case DisplayModeRubbishBin: {
            [self.deleteBarButtonItem setImage:[UIImage imageNamed:@"remove"]];
            break;
        }
            
        default:
            break;
    }
    
    MEGAShareType shareType = [[MEGASdkManager sharedMEGASdk] accessLevelForNode:self.parentNode];
    [self toolbarActionsForShareType:shareType];
    
    NSString *thumbsDirectory = [Helper pathForSharedSandboxCacheDirectory:@"thumbnailsV3"];
    NSError *error;
    if (![[NSFileManager defaultManager] fileExistsAtPath:thumbsDirectory]) {
        if (![[NSFileManager defaultManager] createDirectoryAtPath:thumbsDirectory withIntermediateDirectories:NO attributes:nil error:&error]) {
            MEGALogError(@"Create directory at path failed with error: %@", error);
        }
    }
    
    NSString *previewsDirectory = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"previewsV3"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:previewsDirectory]) {
        if (![[NSFileManager defaultManager] createDirectoryAtPath:previewsDirectory withIntermediateDirectories:NO attributes:nil error:&error]) {
            MEGALogError(@"Create directory at path failed with error: %@", error);
        }
    }
    
    self.nodesIndexPathMutableDictionary = [[NSMutableDictionary alloc] init];
    
    [self.view addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)]];
    
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(internetConnectionChanged) name:kReachabilityChangedNotification object:nil];
    
    [[MEGASdkManager sharedMEGASdk] addMEGADelegate:self];
    [[MEGAReachabilityManager sharedManager] retryPendingConnections];
    
    [self reloadUI];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    [self encourageToUpgrade];
    
    if (self.homeQuickActionSearch) {
        self.homeQuickActionSearch = NO;
        [self activateSearch];
    }
    
    [self requestReview];
    [UIView performWithoutAnimation:^{
        [self.tableView reloadRowsAtIndexPaths:self.tableView.indexPathsForVisibleRows withRowAnimation:UITableViewRowAnimationNone];
    }];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kReachabilityChangedNotification object:nil];
    
    [[MEGASdkManager sharedMEGASdk] removeMEGADelegate:self];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    
    if (self.tableView.isEditing) {
        self.selectedNodesArray = nil;
        [self setTableViewEditing:NO animated:NO];
    }
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if ([[UIDevice currentDevice] iPhone4X] || [[UIDevice currentDevice] iPhone5X]) {
        return UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown;
    }
    
    return UIInterfaceOrientationMaskAll;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return self.searchController.isActive ? UIStatusBarStyleDefault : UIStatusBarStyleLightContent;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self.tableView reloadEmptyDataSet];
    } completion:nil];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    
    if ([self.traitCollection respondsToSelector:@selector(forceTouchCapability)]) {
        if (self.traitCollection.forceTouchCapability == UIForceTouchCapabilityAvailable) {
            if (!self.previewingContext) {
                self.previewingContext = [self registerForPreviewingWithDelegate:self sourceView:self.view];
            }
        } else {
            [self unregisterForPreviewingWithContext:self.previewingContext];
            self.previewingContext = nil;
        }
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger numberOfRows = 0;
    if ([MEGAReachabilityManager isReachable]) {
        if (self.searchController.isActive) {
            numberOfRows = self.searchNodesArray.count;
        } else {
            numberOfRows = [[self.nodes size] integerValue];
        }
    }
    
    return numberOfRows;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    MEGANode *node = self.searchController.isActive ? [self.searchNodesArray objectAtIndex:indexPath.row] : [self.nodes nodeAtIndex:indexPath.row];
    
    [self.nodesIndexPathMutableDictionary setObject:indexPath forKey:node.base64Handle];
    
    BOOL isDownloaded = NO;
    
    NodeTableViewCell *cell;
    if ([[Helper downloadingNodes] objectForKey:node.base64Handle] != nil) {
        cell = [self.tableView dequeueReusableCellWithIdentifier:@"downloadingNodeCell" forIndexPath:indexPath];
        if (cell == nil) {
            cell = [[NodeTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"downloadingNodeCell"];
        }
        
        [cell.downloadingArrowImageView setImage:[UIImage imageNamed:@"downloadQueued"]];
        if (cell.downloadProgressView.progress != 0) {
            [cell.infoLabel setText:AMLocalizedString(@"paused", @"Paused")];
        } else {
            [cell.infoLabel setText:AMLocalizedString(@"queued", @"Queued")];
        }
    } else {
        cell = [self.tableView dequeueReusableCellWithIdentifier:@"nodeCell" forIndexPath:indexPath];
        if (cell == nil) {
            cell = [[NodeTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"nodeCell"];
        }
        
        if (node.type == MEGANodeTypeFile) {
            MOOfflineNode *offlineNode = [[MEGAStore shareInstance] offlineNodeWithNode:node api:[MEGASdkManager sharedMEGASdk]];
            
            if (offlineNode) {
                isDownloaded = YES;
            }
        }
        
        cell.infoLabel.text = [Helper sizeAndDateForNode:node api:[MEGASdkManager sharedMEGASdk]];
    }
    
    if ([node isExported]) {
        if (isDownloaded) {
            [cell.upImageView setImage:[UIImage imageNamed:@"linked"]];
            [cell.middleImageView setImage:nil];
            [cell.downImageView setImage:[Helper downloadedArrowImage]];
        } else {
            [cell.upImageView setImage:nil];
            [cell.middleImageView setImage:[UIImage imageNamed:@"linked"]];
            [cell.downImageView setImage:nil];
        }
    } else {
        [cell.upImageView setImage:nil];
        [cell.downImageView setImage:nil];
        
        if (isDownloaded) {
            [cell.middleImageView setImage:[Helper downloadedArrowImage]];
        } else {
            [cell.middleImageView setImage:nil];
        }
    }
    
    cell.nameLabel.text = [node name];
    
    [cell.thumbnailPlayImageView setHidden:YES];
    
    if ([node type] == MEGANodeTypeFile) {
        if ([node hasThumbnail]) {
            [Helper thumbnailForNode:node api:[MEGASdkManager sharedMEGASdk] cell:cell];
        } else {
            [cell.thumbnailImageView mnz_imageForNode:node];
        }
        
        cell.versionedImageView.hidden = ![[MEGASdkManager sharedMEGASdk] hasVersionsForNode:node];
        
    } else if ([node type] == MEGANodeTypeFolder) {
        [cell.thumbnailImageView mnz_imageForNode:node];
        
        cell.infoLabel.text = [Helper filesAndFoldersInFolderNode:node api:[MEGASdkManager sharedMEGASdk]];
        
        cell.versionedImageView.hidden = YES;
    }
    
    cell.nodeHandle = [node handle];
    
    if (self.tableView.isEditing) {
        // Check if selectedNodesArray contains the current node in the tableView
        for (MEGANode *n in self.selectedNodesArray) {
            if ([n handle] == [node handle]) {
                [self.tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
            }
        }
    }
    
    if (@available(iOS 11.0, *)) {
        cell.thumbnailImageView.accessibilityIgnoresInvertColors = YES;
        cell.thumbnailPlayImageView.accessibilityIgnoresInvertColors = YES;
    } else {
        cell.delegate = self;
    }
    
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    MEGANode *node = self.searchController.isActive ? [self.searchNodesArray objectAtIndex:indexPath.row] : [self.nodes nodeAtIndex:indexPath.row];
    
    if (tableView.isEditing) {
        [self.selectedNodesArray addObject:node];
        
        [self updateNavigationBarTitle];
        
        [self toolbarActionsForNodeArray:self.selectedNodesArray];
        
        [self setToolbarActionsEnabled:YES];
        
        if (self.selectedNodesArray.count == self.nodes.size.integerValue) {
            allNodesSelected = YES;
        } else {
            allNodesSelected = NO;
        }
        
        return;
    }
    
    switch (node.type) {
        case MEGANodeTypeFolder: {
            CloudDriveViewController *cdvc = [self.storyboard instantiateViewControllerWithIdentifier:@"CloudDriveID"];
            [cdvc setParentNode:node];
            
            if (self.displayMode == DisplayModeRubbishBin) {
                [cdvc setDisplayMode:self.displayMode];
            }
            
            [self.navigationController pushViewController:cdvc animated:YES];
            break;
        }
            
        case MEGANodeTypeFile: {
            if (node.name.mnz_isImagePathExtension || node.name.mnz_isVideoPathExtension) {
                [self.navigationController presentViewController:[self photoBrowserForMediaNode:node] animated:YES completion:nil];
            } else {
                [node mnz_openNodeInNavigationController:self.navigationController folderLink:NO];
            }
            break;
        }
            
        default:
            break;
    }
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row > self.nodes.size.integerValue) {
        return;
    }
    MEGANode *node = [self.nodes nodeAtIndex:indexPath.row];
    
    if (tableView.isEditing) {
        
        //tempArray avoid crash: "was mutated while being enumerated."
        NSMutableArray *tempArray = [self.selectedNodesArray copy];
        for (MEGANode *n in tempArray) {
            if (n.handle == node.handle) {
                [self.selectedNodesArray removeObject:n];
            }
        }
        
        [self updateNavigationBarTitle];
        
        [self toolbarActionsForNodeArray:self.selectedNodesArray];
        
        if (self.selectedNodesArray.count == 0) {
            [self setToolbarActionsEnabled:NO];
        } else {
            if ([[MEGASdkManager sharedMEGASdk] isNodeInRubbish:node]) {
                [self setToolbarActionsEnabled:YES];
            }
        }
        
        allNodesSelected = NO;
        
        return;
    }
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    MEGANode *node = self.searchController.isActive ? [self.searchNodesArray objectAtIndex:indexPath.row] : [self.nodes nodeAtIndex:indexPath.row];
    
    if ([[MEGASdkManager sharedMEGASdk] isNodeInRubbish:node]) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }
    
    UIContextualAction *downloadAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:nil handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        if ([node mnz_downloadNodeOverwriting:NO]) {
            [self reloadRowAtIndexPath:[self.nodesIndexPathMutableDictionary objectForKey:node.base64Handle]];
        }
        
        [self setTableViewEditing:NO animated:YES];
    }];
    downloadAction.image = [UIImage imageNamed:@"infoDownload"];
    downloadAction.backgroundColor = [UIColor colorWithRed:0 green:0.75 blue:0.65 alpha:1];
    
    return [UISwipeActionsConfiguration configurationWithActions:@[downloadAction]];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    MEGANode *node = self.searchController.isActive ? [self.searchNodesArray objectAtIndex:indexPath.row] : [self.nodes nodeAtIndex:indexPath.row];
    if ([[MEGASdkManager sharedMEGASdk] accessLevelForNode:node] != MEGAShareTypeAccessOwner) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }
    
    if ([[MEGASdkManager sharedMEGASdk] isNodeInRubbish:node]) {
        MEGANode *restoreNode = [[MEGASdkManager sharedMEGASdk] nodeForHandle:node.restoreHandle];
        if (restoreNode && ![[MEGASdkManager sharedMEGASdk] isNodeInRubbish:restoreNode]) {
            UIContextualAction *restoreAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:nil handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
                [node mnz_restore];
                [self setTableViewEditing:NO animated:YES];
            }];
            restoreAction.image = [UIImage imageNamed:@"restore"];
            restoreAction.backgroundColor = [UIColor colorWithRed:0 green:0.75 blue:0.65 alpha:1];
            
            return [UISwipeActionsConfiguration configurationWithActions:@[restoreAction]];
        }
    } else {
        UIContextualAction *shareAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:nil handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
            UIActivityViewController *activityVC = [Helper activityViewControllerForNodes:@[node] sender:[self.tableView cellForRowAtIndexPath:indexPath]];
            [self presentViewController:activityVC animated:YES completion:nil];
            [self setTableViewEditing:NO animated:YES];
        }];
        shareAction.image = [UIImage imageNamed:@"shareGray"];
        shareAction.backgroundColor = [UIColor colorWithRed:1.0 green:0.64 blue:0 alpha:1];
        
        return [UISwipeActionsConfiguration configurationWithActions:@[shareAction]];
    }
    
    return [UISwipeActionsConfiguration configurationWithActions:@[]];
}

#pragma clang diagnostic pop

#pragma mark - UIViewControllerPreviewingDelegate

- (UIViewController *)previewingContext:(id<UIViewControllerPreviewing>)previewingContext viewControllerForLocation:(CGPoint)location {
    CGPoint rowPoint = [self.view convertPoint:location toView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:rowPoint];
    if (!indexPath || ![self.tableView numberOfRowsInSection:indexPath.section]) {
        return nil;
    }
    
    MEGANode *node = self.searchController.isActive ? [self.searchNodesArray objectAtIndex:indexPath.row] : [self.nodes nodeAtIndex:indexPath.row];
    previewingContext.sourceRect = [self.tableView convertRect:[self.tableView cellForRowAtIndexPath:indexPath].frame toView:self.view];
    
    if (self.tableView.isEditing) {
        return nil;
    }
    
    switch (node.type) {
        case MEGANodeTypeFolder: {
            CloudDriveViewController *cloudDriveVC = [self.storyboard instantiateViewControllerWithIdentifier:@"CloudDriveID"];
            cloudDriveVC.parentNode = node;
            if (self.displayMode == DisplayModeRubbishBin) {
                cloudDriveVC.displayMode = self.displayMode;
            }
            return cloudDriveVC;
            break;
        }
            
        case MEGANodeTypeFile: {
            if (node.name.mnz_isImagePathExtension || node.name.mnz_isVideoPathExtension) {
                return [self photoBrowserForMediaNode:node];
            } else {
                UIViewController *viewController = [node mnz_viewControllerForNodeInFolderLink:NO];
                return viewController;
            }
            break;
        }
            
        default:
            break;
    }
    
    return nil;
}

- (void)previewingContext:(id<UIViewControllerPreviewing>)previewingContext commitViewController:(UIViewController *)viewControllerToCommit {
    if (viewControllerToCommit.class == CloudDriveViewController.class) {
        [self.navigationController pushViewController:viewControllerToCommit animated:YES];
    } else if (viewControllerToCommit.class == PreviewDocumentViewController.class) {
        MEGANavigationController *navigationController = [[MEGANavigationController alloc] initWithRootViewController:viewControllerToCommit];
        [self.navigationController presentViewController:navigationController animated:YES completion:nil];
    } else {
        [self.navigationController presentViewController:viewControllerToCommit animated:YES completion:nil];
    }
}

- (NSArray<id<UIPreviewActionItem>> *)previewActions {
    UIViewController *rootViewController = UIApplication.sharedApplication.delegate.window.rootViewController;
    
    UIPreviewAction *saveForOfflineAction =
    [UIPreviewAction actionWithTitle:AMLocalizedString(@"saveForOffline", @"List option shown on the details of a file or folder")
                               style:UIPreviewActionStyleDefault
                             handler:^(UIPreviewAction * _Nonnull action, UIViewController * _Nonnull previewViewController) {
                                 CloudDriveViewController *cloudDriveVC = (CloudDriveViewController *)previewViewController;
                                 self.selectedNodesArray = [NSMutableArray new];
                                 [self.selectedNodesArray addObject:cloudDriveVC.parentNode];
                                 [self downloadAction:nil];
                             }];
    
    UIPreviewAction *copyAction = [UIPreviewAction actionWithTitle:AMLocalizedString(@"copy", @"List option shown on the details of a file or folder")
                                                             style:UIPreviewActionStyleDefault
                                                           handler:^(UIPreviewAction * _Nonnull action, UIViewController * _Nonnull previewViewController) {
                                                               CloudDriveViewController *cloudDriveVC = (CloudDriveViewController *)previewViewController;
                                                               MEGANavigationController *navigationController = [self.storyboard instantiateViewControllerWithIdentifier:@"BrowserNavigationControllerID"];
                                                               BrowserViewController *browserVC = navigationController.viewControllers.firstObject;
                                                               browserVC.selectedNodesArray = @[cloudDriveVC.parentNode];
                                                               browserVC.browserAction = BrowserActionCopy;
                                                               [rootViewController presentViewController:navigationController animated:YES completion:nil];
                                                           }];
    
    NSString *deletePreviewActionTitle;
    UITabBarController *tabBarController = (UITabBarController *)self.presentingViewController;
    UINavigationController *navigationController = tabBarController.selectedViewController;
    if (navigationController.viewControllers.lastObject.class == SharedItemsViewController.class) {
        MEGAShareType shareType = [[MEGASdkManager sharedMEGASdk] accessLevelForNode:self.parentNode];
        if (shareType == MEGAShareTypeAccessOwner) {
            deletePreviewActionTitle = AMLocalizedString(@"removeSharing", @"Alert title shown on the Shared Items section when you want to remove 1 share");
        }
    } else {
        if (self.displayMode == DisplayModeCloudDrive || self.displayMode == DisplayModeSharedItem) {
            deletePreviewActionTitle = AMLocalizedString(@"moveToTheRubbishBin", @"Title for the action that allows you to 'Move to the Rubbish Bin' files or folders");
        } else if (self.displayMode == DisplayModeRubbishBin) {
            deletePreviewActionTitle = AMLocalizedString(@"remove", @"Title for the action that allows to remove a file or folder");
        }
    }
    UIPreviewAction *deleteAction =
    [UIPreviewAction actionWithTitle:deletePreviewActionTitle
                               style:UIPreviewActionStyleDestructive
                             handler:^(UIPreviewAction * _Nonnull action, UIViewController * _Nonnull previewViewController) {
                                 CloudDriveViewController *cloudDriveVC = (CloudDriveViewController *)previewViewController;
                                 MEGANode *parentNode = cloudDriveVC.parentNode;
                                 MEGAShareType accessType = [[MEGASdkManager sharedMEGASdk] accessLevelForNode:parentNode];
                                 if (accessType == MEGAShareTypeAccessOwner) {
                                     if (self.displayMode == DisplayModeCloudDrive) {
                                         if (navigationController.viewControllers.lastObject.class == CloudDriveViewController.class) {
                                             MEGAMoveRequestDelegate *moveRequestDelegate = [[MEGAMoveRequestDelegate alloc] initToMoveToTheRubbishBinWithFiles:(self.parentNode.isFile ? 1 : 0) folders:(self.parentNode.isFolder ? 1 : 0) completion:^{
                                                 [self setTableViewEditing:NO animated:YES];
                                             }];
                                             
                                             [[MEGASdkManager sharedMEGASdk] moveNode:parentNode newParent:[[MEGASdkManager sharedMEGASdk] rubbishNode] delegate:moveRequestDelegate];
                                         } else if (navigationController.viewControllers.lastObject.class == SharedItemsViewController.class) {
                                             NSMutableArray *outSharesForNodeMutableArray = [[NSMutableArray alloc] init];
                                             MEGAShareList *shareList = [[MEGASdkManager sharedMEGASdk] outSharesForNode:self.parentNode];
                                             NSUInteger outSharesForNodeCount = shareList.size.unsignedIntegerValue;
                                             for (NSInteger i = 0; i < outSharesForNodeCount; i++) {
                                                 MEGAShare *share = [shareList shareAtIndex:i];
                                                 if (share.user != nil) {
                                                     [outSharesForNodeMutableArray addObject:share];
                                                 }
                                             }
                                             
                                             MEGAShareRequestDelegate *shareRequestDelegate = [[MEGAShareRequestDelegate alloc] initToChangePermissionsWithNumberOfRequests:outSharesForNodeMutableArray.count completion:nil];
                                             for (MEGAShare *share in outSharesForNodeMutableArray) {
                                                 [[MEGASdkManager sharedMEGASdk] shareNode:self.parentNode withEmail:share.user level:MEGANodeAccessLevelAccessUnknown delegate:shareRequestDelegate];
                                             }
                                         }
                                     } else { //DisplayModeRubbishBin (Remove)
                                         MEGARemoveRequestDelegate *removeRequestDelegate = [[MEGARemoveRequestDelegate alloc] initWithMode:DisplayModeRubbishBin files:(self.parentNode.isFile ? 1 : 0) folders:(self.parentNode.isFolder ? 1 : 0) completion:^{
                                             [self setTableViewEditing:NO animated:YES];
                                         }];
                                         [[MEGASdkManager sharedMEGASdk] removeNode:parentNode delegate:removeRequestDelegate];
                                     }
                                 } if (accessType == MEGAShareTypeAccessFull) { //DisplayModeSharedItem (Move to the Rubbish Bin)
                                     MEGAMoveRequestDelegate *moveRequestDelegate = [[MEGAMoveRequestDelegate alloc] initToMoveToTheRubbishBinWithFiles:(self.parentNode.isFile ? 1 : 0) folders:(self.parentNode.isFolder ? 1 : 0) completion:^{
                                         [self setTableViewEditing:NO animated:YES];
                                     }];
                                     
                                     [[MEGASdkManager sharedMEGASdk] moveNode:parentNode newParent:[[MEGASdkManager sharedMEGASdk] rubbishNode] delegate:moveRequestDelegate];
                                 }
                             }];
    
    MEGAShareType shareType = [[MEGASdkManager sharedMEGASdk] accessLevelForNode:self.parentNode];
    NSArray<id<UIPreviewActionItem>> *previewActions;
    switch (shareType) {
        case MEGAShareTypeAccessRead:
        case MEGAShareTypeAccessReadWrite:
        case MEGAShareTypeAccessFull: {
            if (navigationController.viewControllers.lastObject.class == CloudDriveViewController.class) {
                previewActions = (shareType == MEGAShareTypeAccessFull) ? @[saveForOfflineAction, copyAction, deleteAction] : @[saveForOfflineAction, copyAction];
            } else if (navigationController.viewControllers.lastObject.class == SharedItemsViewController.class) {
                UIPreviewAction *leaveShareAction = [UIPreviewAction actionWithTitle:AMLocalizedString(@"leave", @"A button label. The button allows the user to leave the group conversation.")
                                                                               style:UIPreviewActionStyleDestructive
                                                                             handler:^(UIPreviewAction * _Nonnull action, UIViewController * _Nonnull previewViewController) {
                                                                                 CloudDriveViewController *cloudDriveVC = (CloudDriveViewController *)previewViewController;
                                                                                 
                                                                                 NSString *alertMessage = (cloudDriveVC.selectedNodesArray.count > 1) ? AMLocalizedString(@"leaveSharesAlertMessage", @"Alert message shown when the user tap on the leave share action selecting multipe inshares") : AMLocalizedString(@"leaveShareAlertMessage", @"Alert message shown when the user tap on the leave share action for one inshare");
                                                                                 UIAlertController *leaveAlertController = [UIAlertController alertControllerWithTitle:AMLocalizedString(@"leaveFolder", @"Button title of the action that allows to leave a shared folder") message:alertMessage preferredStyle:UIAlertControllerStyleAlert];
                                                                                 [leaveAlertController addAction:[UIAlertAction actionWithTitle:AMLocalizedString(@"cancel", @"Button title to cancel something") style:UIAlertActionStyleCancel handler:nil]];
                                                                                 
                                                                                 [leaveAlertController addAction:[UIAlertAction actionWithTitle:AMLocalizedString(@"ok", @"Button title to cancel something") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                                                                                     MEGARemoveRequestDelegate *removeRequestDelegate = [[MEGARemoveRequestDelegate alloc] initWithMode:DisplayModeSharedItem files:(self.parentNode.isFile ? 1 : 0) folders:(self.parentNode.isFolder ? 1 : 0) completion:^{
                                                                                         [self setTableViewEditing:NO animated:YES];
                                                                                     }];
                                                                                     [[MEGASdkManager sharedMEGASdk] removeNode:self.parentNode delegate:removeRequestDelegate];
                                                                                 }]];
                                                                                 
                                                                                 [rootViewController presentViewController:leaveAlertController animated:YES completion:nil];
                                                                             }];
                previewActions = @[saveForOfflineAction, copyAction, leaveShareAction];
            }
            break;
        }
            
        case MEGAShareTypeAccessOwner: {
            UIPreviewAction *shareAction = [UIPreviewAction actionWithTitle:AMLocalizedString(@"share", @"Button title which, if tapped, will trigger the action of sharing with the contact or contacts selected ")
                                                                      style:UIPreviewActionStyleDefault
                                                                    handler:^(UIPreviewAction * _Nonnull action, UIViewController * _Nonnull previewViewController) {
                                                                        CloudDriveViewController *cloudDriveVC = (CloudDriveViewController *)previewViewController;
                                                                        UIActivityViewController *activityVC = [Helper activityViewControllerForNodes:@[cloudDriveVC.parentNode] sender:nil];
                                                                        [rootViewController presentViewController:activityVC animated:YES completion:nil];
                                                                    }];
            
            UIPreviewAction *moveAction = [UIPreviewAction actionWithTitle:AMLocalizedString(@"move", @"Title for the action that allows you to move a file or folder")
                                                                     style:UIPreviewActionStyleDefault
                                                                   handler:^(UIPreviewAction * _Nonnull action, UIViewController * _Nonnull previewViewController) {
                                                                       CloudDriveViewController *cloudDriveVC = (CloudDriveViewController *)previewViewController;
                                                                       MEGANavigationController *navigationController = [self.storyboard instantiateViewControllerWithIdentifier:@"BrowserNavigationControllerID"];
                                                                       BrowserViewController *browserVC = navigationController.viewControllers.firstObject;
                                                                       browserVC.selectedNodesArray = @[cloudDriveVC.parentNode];
                                                                       if (lowShareType == MEGAShareTypeAccessOwner) {
                                                                           browserVC.browserAction = BrowserActionMove;
                                                                       }
                                                                       [rootViewController presentViewController:navigationController animated:YES completion:nil];
                                                                   }];
            
            if (self.displayMode == DisplayModeCloudDrive) {
                if (navigationController.viewControllers.lastObject.class == SharedItemsViewController.class) {
                    UIPreviewAction *shareFolderPreviewAction = [UIPreviewAction actionWithTitle:AMLocalizedString(@"shareFolder", @"Button title which, if tapped, will trigger the action of sharing with the contact or contacts selected, the folder you want inside your Cloud Drive")
                                                                                           style:UIPreviewActionStyleDefault
                                                                                         handler:^(UIPreviewAction * _Nonnull action, UIViewController * _Nonnull previewViewController) {
                                                                                             CloudDriveViewController *cloudDriveVC = (CloudDriveViewController *)previewViewController;
                                                                                             MEGANavigationController *navigationController = [[UIStoryboard storyboardWithName:@"Contacts" bundle:nil] instantiateViewControllerWithIdentifier:@"ContactsNavigationControllerID"];
                                                                                             ContactsViewController *contactsVC = navigationController.viewControllers.firstObject;
                                                                                             contactsVC.contactsMode = ContactsModeShareFoldersWith;
                                                                                             contactsVC.nodesArray = @[cloudDriveVC.parentNode];
                                                                                             [rootViewController presentViewController:navigationController animated:YES completion:nil];
                                                                                         }];
                    
                    previewActions = @[shareAction, shareFolderPreviewAction, copyAction, deleteAction];
                } else if (navigationController.viewControllers.lastObject.class == CloudDriveViewController.class) {
                    previewActions = @[saveForOfflineAction, shareAction, moveAction, copyAction, deleteAction];
                }
            } else if (self.displayMode == DisplayModeRubbishBin) {
                previewActions = @[saveForOfflineAction, moveAction, copyAction, deleteAction];
            }
            break;
        }
            
        default:
            break;
    }
    
    return previewActions;
}

#pragma mark - UILongPressGestureRecognizer

- (void)longPress:(UILongPressGestureRecognizer *)longPressGestureRecognizer {
    if (longPressGestureRecognizer.state == UIGestureRecognizerStateBegan) {
        CGPoint touchPoint = [longPressGestureRecognizer locationInView:self.tableView];
        NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:touchPoint];
        
        if (!indexPath || ![self.tableView numberOfRowsInSection:indexPath.section]) {
            return;
        }
        
        if (self.tableView.isEditing) {
            // Only stop editing if long pressed over a cell that is the only one selected or when selected none
            if (self.selectedNodesArray.count == 0) {
                [self setTableViewEditing:NO animated:YES];
            }
            if (self.selectedNodesArray.count == 1) {
                MEGANode *nodeSelected = self.selectedNodesArray.firstObject;
                MEGANode *nodePressed = self.searchController.isActive ? [self.searchNodesArray objectAtIndex:indexPath.row] : [self.nodes nodeAtIndex:indexPath.row];
                if (nodeSelected.handle == nodePressed.handle) {
                    [self setTableViewEditing:NO animated:YES];
                }
            }
        } else {
            [self setTableViewEditing:YES animated:YES];
            [self tableView:self.tableView didSelectRowAtIndexPath:indexPath];
            [self.tableView selectRowAtIndexPath:indexPath animated:YES scrollPosition:UITableViewScrollPositionNone];
        }
    }
}

#pragma mark - DZNEmptyDataSetSource

- (NSAttributedString *)titleForEmptyDataSet:(UIScrollView *)scrollView {
    NSString *text;
    if ([MEGAReachabilityManager isReachable]) {
        if (self.parentNode == nil) {
            return nil;
        }
        
        if (self.searchController.isActive) {
            text = AMLocalizedString(@"noResults", nil);
        } else {
            switch (self.displayMode) {
                case DisplayModeCloudDrive: {
                    if ([self.parentNode type] == MEGANodeTypeRoot) {
                        text = AMLocalizedString(@"cloudDriveEmptyState_title", @"Title shown when your Cloud Drive is empty, when you don't have any files.");
                    } else {
                        text = AMLocalizedString(@"emptyFolder", @"Title shown when a folder doesn't have any files");
                    }
                    break;
                }
                    
                case DisplayModeRubbishBin:
                    if ([self.parentNode type] == MEGANodeTypeRubbish) {
                        text = AMLocalizedString(@"cloudDriveEmptyState_titleRubbishBin", @"Title shown when your Rubbish Bin is empty.");
                    } else {
                        text = AMLocalizedString(@"emptyFolder", @"Title shown when a folder doesn't have any files");
                    }
                    break;
                    
                default:
                    break;
            }
        }
    } else {
        text = AMLocalizedString(@"noInternetConnection",  @"No Internet Connection");
    }
    
    return [[NSAttributedString alloc] initWithString:text attributes:[Helper titleAttributesForEmptyState]];
}

- (UIImage *)imageForEmptyDataSet:(UIScrollView *)scrollView {
    UIImage *image = nil;
    if ([MEGAReachabilityManager isReachable]) {
        if (self.parentNode == nil) {
            return nil;
        }
        
        if (self.searchController.isActive) {
            image = [UIImage imageNamed:@"searchEmptyState"];
        } else {
            switch (self.displayMode) {
                case DisplayModeCloudDrive: {
                    if ([self.parentNode type] == MEGANodeTypeRoot) {
                        image = [UIImage imageNamed:@"cloudEmptyState"];
                    } else {
                        image = [UIImage imageNamed:@"folderEmptyState"];
                    }
                    break;
                }
                    
                case DisplayModeRubbishBin: {
                    if ([self.parentNode type] == MEGANodeTypeRubbish) {
                        image = [UIImage imageNamed:@"rubbishEmptyState"];
                    } else {
                        image = [UIImage imageNamed:@"folderEmptyState"];
                    }
                    break;
                }
                    
                default:
                    break;
            }
        }
    } else {
        image = [UIImage imageNamed:@"noInternetEmptyState"];
    }
    
    return image;
}

- (NSAttributedString *)buttonTitleForEmptyDataSet:(UIScrollView *)scrollView forState:(UIControlState)state {
    MEGAShareType parentShareType = [[MEGASdkManager sharedMEGASdk] accessLevelForNode:self.parentNode];
    if (parentShareType == MEGAShareTypeAccessRead) {
        return nil;
    }
    
    NSString *text = @"";
    if ([MEGAReachabilityManager isReachable]) {
        if (self.parentNode == nil) {
            return nil;
        }
        
        switch (self.displayMode) {
            case DisplayModeCloudDrive: {
                if (!self.searchController.isActive) {
                    text = AMLocalizedString(@"addFiles", nil);
                }
                break;
            }
                
            default:
                text = @"";
                break;
        }
        
    }
    
    return [[NSAttributedString alloc] initWithString:text attributes:[Helper buttonTextAttributesForEmptyState]];
}

- (UIImage *)buttonBackgroundImageForEmptyDataSet:(UIScrollView *)scrollView forState:(UIControlState)state {
    MEGAShareType parentShareType = [[MEGASdkManager sharedMEGASdk] accessLevelForNode:self.parentNode];
    if (parentShareType == MEGAShareTypeAccessRead) {
        return nil;
    }
    
    UIEdgeInsets capInsets = [Helper capInsetsForEmptyStateButton];
    UIEdgeInsets rectInsets = [Helper rectInsetsForEmptyStateButton];
    
    return [[[UIImage imageNamed:@"emptyStateButton"] resizableImageWithCapInsets:capInsets resizingMode:UIImageResizingModeStretch] imageWithAlignmentRectInsets:rectInsets];
}

- (UIColor *)backgroundColorForEmptyDataSet:(UIScrollView *)scrollView {
    return [UIColor whiteColor];
}

- (CGFloat)verticalOffsetForEmptyDataSet:(UIScrollView *)scrollView {
    return [Helper verticalOffsetForEmptyStateWithNavigationBarSize:self.navigationController.navigationBar.frame.size searchBarActive:self.searchController.isActive];
}

- (CGFloat)spaceHeightForEmptyDataSet:(UIScrollView *)scrollView {
    return [Helper spaceHeightForEmptyState];
}

#pragma mark - DZNEmptyDataSetDelegate

- (void)emptyDataSet:(UIScrollView *)scrollView didTapButton:(UIButton *)button {
    switch (self.displayMode) {
        case DisplayModeCloudDrive: {
            [self presentUploadAlertController];
            break;
        }
            
        default:
            break;
    }
}

#pragma mark - Private

- (void)reloadUI {
    switch (self.displayMode) {
        case DisplayModeCloudDrive: {
            if (!self.parentNode) {
                self.parentNode = [[MEGASdkManager sharedMEGASdk] rootNode];
            }
            
            [self updateNavigationBarTitle];
            
            //Sort configuration by default is "default ascending"
            if (![[NSUserDefaults standardUserDefaults] integerForKey:@"SortOrderType"]) {
                [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"SortOrderType"];
                [[NSUserDefaults standardUserDefaults] synchronize];
            }
            
            MEGASortOrderType sortOrderType = [[NSUserDefaults standardUserDefaults] integerForKey:@"SortOrderType"];
            
            self.nodes = [[MEGASdkManager sharedMEGASdk] childrenForParent:self.parentNode order:sortOrderType];
            
            break;
        }
            
        case DisplayModeRubbishBin: {
            [self updateNavigationBarTitle];
            
            self.nodes = [[MEGASdkManager sharedMEGASdk] childrenForParent:self.parentNode];
            
            break;
        }
            
        default:
            break;
    }
    
    if ([[self.nodes size] unsignedIntegerValue] == 0) {
        [self setNavigationBarButtonItemsEnabled:[MEGAReachabilityManager isReachable]];
        
        [self.tableView setTableHeaderView:nil];
    } else {
        [self setNavigationBarButtonItemsEnabled:[MEGAReachabilityManager isReachable]];
        if (!self.tableView.tableHeaderView) {
            self.tableView.tableHeaderView = self.searchController.searchBar;
        }
    }
    
    NSMutableArray *tempArray = [[NSMutableArray alloc] initWithCapacity:self.nodes.size.integerValue];
    for (NSUInteger i = 0; i < self.nodes.size.integerValue ; i++) {
        [tempArray addObject:[self.nodes nodeAtIndex:i]];
    }
    
    self.nodesArray = tempArray;
    
    [self.tableView reloadData];
}

- (void)showImagePickerForSourceType:(UIImagePickerControllerSourceType)sourceType {
    if (sourceType == UIImagePickerControllerSourceTypeCamera) {
        MEGAImagePickerController *imagePickerController = [[MEGAImagePickerController alloc] initToUploadWithParentNode:self.parentNode sourceType:sourceType];
        [self presentViewController:imagePickerController animated:YES completion:nil];
    } else {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            dispatch_async(dispatch_get_main_queue(), ^{
                MEGAAssetsPickerController *pickerViewController = [[MEGAAssetsPickerController alloc] initToUploadToCloudDriveWithParentNode:self.parentNode];
                [self presentViewController:pickerViewController animated:YES completion:nil];
            });
        }];
    }
}

- (void)toolbarActionsForShareType:(MEGAShareType )shareType {
    UIBarButtonItem *flexibleItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    lowShareType = shareType;
    
    switch (shareType) {
        case MEGAShareTypeAccessRead:
        case MEGAShareTypeAccessReadWrite: {
            [self.moveBarButtonItem setImage:[UIImage imageNamed:@"copy"]];
            [self.toolbar setItems:@[self.downloadBarButtonItem, flexibleItem, self.moveBarButtonItem]];
            break;
        }
            
        case MEGAShareTypeAccessFull: {
            [self.moveBarButtonItem setImage:[UIImage imageNamed:@"copy"]];
            [self.toolbar setItems:@[self.downloadBarButtonItem, flexibleItem, self.moveBarButtonItem, flexibleItem, self.deleteBarButtonItem]];
            break;
        }
            
        case MEGAShareTypeAccessOwner: {
            if (self.displayMode == DisplayModeCloudDrive) {
                [self.toolbar setItems:@[self.downloadBarButtonItem, flexibleItem, self.shareBarButtonItem, flexibleItem, self.moveBarButtonItem, flexibleItem, self.carbonCopyBarButtonItem, flexibleItem, self.deleteBarButtonItem]];
            } else { //Rubbish Bin
                [self.toolbar setItems:@[self.restoreBarButtonItem, flexibleItem, self.moveBarButtonItem, flexibleItem, self.carbonCopyBarButtonItem, flexibleItem, self.deleteBarButtonItem]];
            }
            
            break;
        }
            
        default:
            break;
    }
}

- (void)setToolbarActionsEnabled:(BOOL)boolValue {
    self.downloadBarButtonItem.enabled = boolValue;
    [self.shareBarButtonItem setEnabled:((self.selectedNodesArray.count < 100) ? boolValue : NO)];
    self.moveBarButtonItem.enabled = boolValue;
    self.carbonCopyBarButtonItem.enabled = boolValue;
    self.deleteBarButtonItem.enabled = boolValue;
    self.restoreBarButtonItem.enabled = boolValue;
    
    if ((self.displayMode == DisplayModeRubbishBin) && boolValue) {
        for (MEGANode *n in self.selectedNodesArray) {
            if (!n.mnz_isRestorable) {
                self.restoreBarButtonItem.enabled = NO;
                break;
            }
        }
    }
}

- (void)toolbarActionsForNodeArray:(NSArray *)nodeArray {
    if (nodeArray.count == 0) {
        return;
    }
    
    MEGAShareType shareType;
    lowShareType = MEGAShareTypeAccessOwner;
    
    for (MEGANode *n in nodeArray) {
        shareType = [[MEGASdkManager sharedMEGASdk] accessLevelForNode:n];
        
        if (shareType == MEGAShareTypeAccessRead  && shareType < lowShareType) {
            lowShareType = shareType;
            break;
        }
        
        if (shareType == MEGAShareTypeAccessReadWrite && shareType < lowShareType) {
            lowShareType = shareType;
        }
        
        if (shareType == MEGAShareTypeAccessFull && shareType < lowShareType) {
            lowShareType = shareType;
            
        }
    }
    
    [self toolbarActionsForShareType:lowShareType];
}

- (void)internetConnectionChanged {
    BOOL boolValue = [MEGAReachabilityManager isReachable];
    [self setNavigationBarButtonItemsEnabled:boolValue];
    
    [self.tableView reloadData];
}

- (void)setNavigationBarButtonItems {
    switch (self.displayMode) {
        case DisplayModeCloudDrive: {
            if ([[MEGASdkManager sharedMEGASdk] accessLevelForNode:self.parentNode] == MEGAShareTypeAccessRead) {
                self.navigationItem.rightBarButtonItems = @[self.moreMinimizedBarButtonItem];
            } else {
                self.navigationItem.rightBarButtonItems = @[self.moreBarButtonItem];
            }
            break;
        }
            
        case DisplayModeRubbishBin:
            self.navigationItem.rightBarButtonItems = @[self.moreMinimizedBarButtonItem];
            break;
            
        default:
            break;
    }
}

- (void)setNavigationBarButtonItemsEnabled:(BOOL)boolValue {
    switch (self.displayMode) {
        case DisplayModeCloudDrive: {
            self.moreBarButtonItem.enabled = boolValue;
            break;
        }
            
        case DisplayModeRubbishBin: {
            self.editBarButtonItem.enabled = boolValue;
            break;
        }
            
        default:
            break;
    }
}

- (void)presentSortByViewController {
    SortByTableViewController *sortByTableViewController = [[UIStoryboard storyboardWithName:@"Cloud" bundle:nil] instantiateViewControllerWithIdentifier:@"sortByTableViewControllerID"];
    sortByTableViewController.offline = NO;
    MEGANavigationController *navigationController = [[MEGANavigationController alloc] initWithRootViewController:sortByTableViewController];
    
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)presentFromMoreBarButtonItemTheAlertController:(UIAlertController *)alertController {
    if ([[UIDevice currentDevice] iPadDevice]) {
        alertController.modalPresentationStyle = UIModalPresentationPopover;
        UIPopoverPresentationController *popoverPresentationController = [alertController popoverPresentationController];
        popoverPresentationController.barButtonItem = self.moreBarButtonItem;
        popoverPresentationController.sourceView = self.view;
    }
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)newFolderAlertTextFieldDidChange:(UITextField *)sender {
    UIAlertController *newFolderAlertController = (UIAlertController *)self.presentedViewController;
    if (newFolderAlertController) {
        UITextField *textField = newFolderAlertController.textFields.firstObject;
        UIAlertAction *rightButtonAction = newFolderAlertController.actions.lastObject;
        BOOL containsInvalidChars = [sender.text rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"|*/:<>?\"\\"]].length;
        sender.textColor = containsInvalidChars ? UIColor.mnz_redMain : UIColor.darkTextColor;
        rightButtonAction.enabled = (textField.text.length > 0 && !containsInvalidChars);
    }
}

- (void)presentUploadAlertController {
    UIAlertController *uploadAlertController = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [uploadAlertController addAction:[UIAlertAction actionWithTitle:AMLocalizedString(@"cancel", @"Button title to cancel something") style:UIAlertActionStyleCancel handler:nil]];
    
    UIAlertAction *fromPhotosAlertAction = [UIAlertAction actionWithTitle:AMLocalizedString(@"choosePhotoVideo", @"Menu option from the `Add` section that allows the user to choose a photo or video to upload it to MEGA") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self showImagePickerForSourceType:UIImagePickerControllerSourceTypePhotoLibrary];
    }];
    [fromPhotosAlertAction mnz_setTitleTextColor:[UIColor mnz_black333333]];
    [uploadAlertController addAction:fromPhotosAlertAction];
    
    UIAlertAction *captureAlertAction = [UIAlertAction actionWithTitle:AMLocalizedString(@"capturePhotoVideo", @"Menu option from the `Add` section that allows the user to capture a video or a photo and upload it directly to MEGA.") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if ([AVCaptureDevice respondsToSelector:@selector(requestAccessForMediaType:completionHandler:)]) {
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL permissionGranted) {
                if (permissionGranted) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
                            switch (status) {
                                case PHAuthorizationStatusAuthorized: {
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        [self showImagePickerForSourceType:UIImagePickerControllerSourceTypeCamera];
                                    });
                                    break;
                                }
                                
                                case PHAuthorizationStatusNotDetermined:
                                case PHAuthorizationStatusRestricted:
                                case PHAuthorizationStatusDenied:{
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"isSaveMediaCapturedToGalleryEnabled"];
                                        [[NSUserDefaults standardUserDefaults] synchronize];
                                        [self showImagePickerForSourceType:UIImagePickerControllerSourceTypeCamera];
                                    });
                                    break;
                                }
                                
                                default:
                                    break;
                            }
                        }];
                    });
                } else {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        UIAlertController *permissionsAlertController = [UIAlertController alertControllerWithTitle:AMLocalizedString(@"attention", @"Alert title to attract attention") message:AMLocalizedString(@"cameraPermissions", @"Alert message to remember that MEGA app needs permission to use the Camera to take a photo or video and it doesn't have it") preferredStyle:UIAlertControllerStyleAlert];
                        
                        [permissionsAlertController addAction:[UIAlertAction actionWithTitle:AMLocalizedString(@"cancel", @"Button title to cancel something") style:UIAlertActionStyleCancel handler:nil]];
                        
                        [permissionsAlertController addAction:[UIAlertAction actionWithTitle:AMLocalizedString(@"ok", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
                        }]];
                        
                        [self presentViewController:permissionsAlertController animated:YES completion:nil];
                    });
                }
            }];
        }
    }];
    [captureAlertAction mnz_setTitleTextColor:[UIColor mnz_black333333]];
    [uploadAlertController addAction:captureAlertAction];
    
    UIAlertAction *importFromAlertAction = [UIAlertAction actionWithTitle:AMLocalizedString(@"uploadFrom", @"Option given on the `Add` section to allow the user upload something from another cloud storage provider.") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIDocumentMenuViewController *documentMenuViewController = [[UIDocumentMenuViewController alloc] initWithDocumentTypes:@[(__bridge NSString *) kUTTypeContent, (__bridge NSString *) kUTTypeData,(__bridge NSString *) kUTTypePackage, (@"com.apple.iwork.pages.pages"), (@"com.apple.iwork.numbers.numbers"), (@"com.apple.iwork.keynote.key")] inMode:UIDocumentPickerModeImport];
        documentMenuViewController.delegate = self;
        documentMenuViewController.popoverPresentationController.barButtonItem = self.moreBarButtonItem;
        
        [self presentViewController:documentMenuViewController animated:YES completion:nil];
    }];
    [importFromAlertAction mnz_setTitleTextColor:[UIColor mnz_black333333]];
    [uploadAlertController addAction:importFromAlertAction];
    
    [self presentFromMoreBarButtonItemTheAlertController:uploadAlertController];
}

- (void)updateNavigationBarTitle {
    NSString *navigationTitle;
    if (self.tableView.isEditing) {
        if (self.selectedNodesArray.count == 0) {
            navigationTitle = AMLocalizedString(@"selectTitle", @"Title shown on the Camera Uploads section when the edit mode is enabled. On this mode you can select photos");
        } else {
            navigationTitle = (self.selectedNodesArray.count == 1) ? [NSString stringWithFormat:AMLocalizedString(@"oneItemSelected", @"Title shown on the Camera Uploads section when the edit mode is enabled and you have selected one photo"), self.selectedNodesArray.count] : [NSString stringWithFormat:AMLocalizedString(@"itemsSelected", @"Title shown on the Camera Uploads section when the edit mode is enabled and you have selected more than one photo"), self.selectedNodesArray.count];
        }
    } else {
        switch (self.displayMode) {
            case DisplayModeCloudDrive: {
                if ([self.parentNode type] == MEGANodeTypeRoot) {
                    navigationTitle = AMLocalizedString(@"cloudDrive", @"Title of the Cloud Drive section");
                } else {
                    if (!self.parentNode) {
                        navigationTitle = AMLocalizedString(@"cloudDrive", @"Title of the Cloud Drive section");
                    } else {
                        navigationTitle = [self.parentNode name];
                    }
                }
                break;
            }
                
            case DisplayModeRubbishBin: {
                if ([self.parentNode type] == MEGANodeTypeRubbish) {
                    navigationTitle = AMLocalizedString(@"rubbishBinLabel", @"Title of one of the Settings sections where you can see your MEGA 'Rubbish Bin'");
                } else {
                    navigationTitle = [self.parentNode name];
                }
                break;
            }
                
            default:
                break;
        }
    }
    
    self.navigationItem.title = navigationTitle;
}

- (void)encourageToUpgrade {
    if (self.tabBarController == nil) { //Avoid presenting Upgrade view when peeking
        return;
    }
    
    static BOOL alreadyPresented = NO;
    if (!alreadyPresented && ![[MEGASdkManager sharedMEGASdk] mnz_isProAccount]) {
        MEGAAccountDetails *accountDetails = [[MEGASdkManager sharedMEGASdk] mnz_accountDetails];
        double percentage = accountDetails.storageUsed.doubleValue / accountDetails.storageMax.doubleValue;
        if (accountDetails && percentage > 0.95) { // +95% used storage
            NSString *alertMessage = percentage < 1 ? AMLocalizedString(@"cloudDriveIsAlmostFull", @"Informs the user that they’ve almost reached the full capacity of their Cloud Drive for a Free account. Please leave the [S], [/S], [A], [/A] placeholders as they are.") : AMLocalizedString(@"cloudDriveIsFull", @"A message informing the user that they've reached the full capacity of their accounts. Please leave [S], [/S] as it is which is used to bolden the text.");
            alertMessage = [alertMessage mnz_removeWebclientFormatters];
            NSString *maxStorage = [NSString stringWithFormat:@"%ld", (long)[[MEGAPurchase sharedInstance].pricing storageGBAtProductIndex:7]];
            NSString *maxStorageTB = [NSString stringWithFormat:@"%ld", (long)[[MEGAPurchase sharedInstance].pricing storageGBAtProductIndex:7] / 1024];
            alertMessage = [alertMessage stringByReplacingOccurrencesOfString:@"4096" withString:maxStorage];
            alertMessage = [alertMessage stringByReplacingOccurrencesOfString:@"4" withString:maxStorageTB];
            
            CustomModalAlertViewController *customModalAlertVC = [[CustomModalAlertViewController alloc] init];
            customModalAlertVC.modalPresentationStyle = UIModalPresentationOverCurrentContext;
            customModalAlertVC.image = [UIImage imageNamed:@"storage_almost_full"];
            customModalAlertVC.viewTitle = AMLocalizedString(@"upgradeAccount", @"Button title which triggers the action to upgrade your MEGA account level");
            customModalAlertVC.detail = alertMessage;
            customModalAlertVC.action = AMLocalizedString(@"seePlans", @"Button title to see the available pro plans in MEGA");
            if ([[MEGASdkManager sharedMEGASdk] isAchievementsEnabled]) {
                customModalAlertVC.bonus = AMLocalizedString(@"getBonus", @"Button title to see the available bonus");
            }
            customModalAlertVC.dismiss = AMLocalizedString(@"dismiss", @"Label for any 'Dismiss' button, link, text, title, etc. - (String as short as possible).");
            __weak typeof(CustomModalAlertViewController) *weakCustom = customModalAlertVC;
            customModalAlertVC.completion = ^{
                [weakCustom dismissViewControllerAnimated:YES completion:^{
                    [self showUpgradeTVC];
                }];
            };
            
            [UIApplication.mnz_visibleViewController presentViewController:customModalAlertVC animated:YES completion:nil];
            
            alreadyPresented = YES;
        } else {
            if (accountDetails && (arc4random_uniform(20) == 0)) { // 5 % of the times
                [self showUpgradeTVC];
                alreadyPresented = YES;
            }
        }
    }
}

- (void)showUpgradeTVC {
    if ([MEGAPurchase sharedInstance].products.count > 0) {
        UpgradeTableViewController *upgradeTVC = [[UIStoryboard storyboardWithName:@"MyAccount" bundle:nil] instantiateViewControllerWithIdentifier:@"UpgradeID"];
        MEGANavigationController *navigationController = [[MEGANavigationController alloc] initWithRootViewController:upgradeTVC];
        
        [self presentViewController:navigationController animated:YES completion:nil];
    }
}

- (void)activateSearch {
    [self.searchController.searchBar becomeFirstResponder];
    self.searchController.active = YES;
}

- (void)requestReview {
    if (@available(iOS 10.3, *)) {
        static BOOL alreadyPresented = NO;
        if (!alreadyPresented && [[MEGASdkManager sharedMEGASdk] mnz_accountDetails] && [[MEGASdkManager sharedMEGASdk] mnz_isProAccount]) {
            alreadyPresented = YES;
            NSUserDefaults *sharedUserDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"group.mega.ios"];
            NSDate *rateUsDate = [sharedUserDefaults objectForKey:@"rateUsDate"];
            if (rateUsDate) {
                NSInteger weeks = [[NSCalendar currentCalendar] components:NSCalendarUnitWeekOfYear
                                                                  fromDate:rateUsDate
                                                                    toDate:[NSDate date]
                                                                   options:NSCalendarWrapComponents].weekOfYear;
                if (weeks < 17) {
                    return;
                }
            } else {
                NSTimeInterval sixteenWeeksAgo = -16 * 7 * 24 * 60 * 60;
                rateUsDate = [NSDate dateWithTimeIntervalSinceNow:sixteenWeeksAgo];
                [sharedUserDefaults setObject:rateUsDate forKey:@"rateUsDate"];
                return;
            }
            [SKStoreReviewController requestReview];
            rateUsDate = [NSDate date];
            [sharedUserDefaults setObject:rateUsDate forKey:@"rateUsDate"];
        }
    }
}

- (void)showNodeInfo:(MEGANode *)node {
    UINavigationController *nodeInfoNavigation = [self.storyboard instantiateViewControllerWithIdentifier:@"NodeInfoNavigationControllerID"];
    NodeInfoViewController *nodeInfoVC = nodeInfoNavigation.viewControllers.firstObject;
    nodeInfoVC.node = node;
    nodeInfoVC.nodeInfoDelegate = self;
    nodeInfoVC.incomingShareChildView = self.incomingShareChildView;
    
    [self presentViewController:nodeInfoNavigation animated:YES completion:nil];
}

- (void)reloadRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath != nil) {
        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (MEGAPhotoBrowserViewController *)photoBrowserForMediaNode:(MEGANode *)node {
    NSArray *nodesArray = (self.searchController.isActive ? self.searchNodesArray : [self.nodes mnz_nodesArrayFromNodeList]);
    NSMutableArray<MEGANode *> *mediaNodesArray = [[NSMutableArray alloc] initWithCapacity:nodesArray.count];
    for (MEGANode *n in nodesArray) {
        if (n.name.mnz_isImagePathExtension || n.name.mnz_isVideoPathExtension) {
            [mediaNodesArray addObject:n];
        }
    }
    
    MEGAPhotoBrowserViewController *photoBrowserVC = [MEGAPhotoBrowserViewController photoBrowserWithMediaNodes:mediaNodesArray api:[MEGASdkManager sharedMEGASdk] displayMode:self.displayMode presentingNode:node preferredIndex:0];
    
    return photoBrowserVC;
}

#pragma mark - IBActions

- (IBAction)selectAllAction:(UIBarButtonItem *)sender {
    [self.selectedNodesArray removeAllObjects];
    
    if (!allNodesSelected) {
        MEGANode *n = nil;
        NSInteger nodeListSize = [[self.nodes size] integerValue];
        
        for (NSInteger i = 0; i < nodeListSize; i++) {
            n = [self.nodes nodeAtIndex:i];
            [self.selectedNodesArray addObject:n];
        }
        
        allNodesSelected = YES;
        
        [self toolbarActionsForNodeArray:self.selectedNodesArray];
    } else {
        allNodesSelected = NO;
    }
    
    if (self.displayMode == DisplayModeCloudDrive || self.displayMode == DisplayModeRubbishBin) {
        [self updateNavigationBarTitle];
    }
    
    if (self.selectedNodesArray.count == 0) {
        [self setToolbarActionsEnabled:NO];
    } else if (self.selectedNodesArray.count >= 1) {
        [self setToolbarActionsEnabled:YES];
    }
    
    [self.tableView reloadData];
}

- (IBAction)moreAction:(UIBarButtonItem *)sender {
    UIAlertController *moreAlertController = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [moreAlertController addAction:[UIAlertAction actionWithTitle:AMLocalizedString(@"cancel", @"Button title to cancel something") style:UIAlertActionStyleCancel handler:nil]];
    
    UIAlertAction *uploadAlertAction = [UIAlertAction actionWithTitle:AMLocalizedString(@"upload", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self presentUploadAlertController];
    }];
    [uploadAlertAction mnz_setTitleTextColor:[UIColor mnz_black333333]];
    [moreAlertController addAction:uploadAlertAction];
    
    UIAlertAction *newFolderAlertAction = [UIAlertAction actionWithTitle:AMLocalizedString(@"newFolder", @"Menu option from the `Add` section that allows you to create a 'New Folder'") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIAlertController *newFolderAlertController = [UIAlertController alertControllerWithTitle:AMLocalizedString(@"newFolder", @"Menu option from the `Add` section that allows you to create a 'New Folder'") message:nil preferredStyle:UIAlertControllerStyleAlert];
        
        [newFolderAlertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.placeholder = AMLocalizedString(@"newFolderMessage", @"Hint text shown on the create folder alert.");
            [textField addTarget:self action:@selector(newFolderAlertTextFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
        }];
        
        [newFolderAlertController addAction:[UIAlertAction actionWithTitle:AMLocalizedString(@"cancel", @"Button title to cancel something") style:UIAlertActionStyleCancel handler:nil]];
        
        UIAlertAction *createFolderAlertAction = [UIAlertAction actionWithTitle:AMLocalizedString(@"createFolderButton", @"Title button for the create folder alert.") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            if ([MEGAReachabilityManager isReachableHUDIfNot]) {
                UITextField *textField = [[newFolderAlertController textFields] firstObject];
                MEGANodeList *childrenNodeList = [[MEGASdkManager sharedMEGASdk] nodeListSearchForNode:self.parentNode searchString:textField.text];
                if ([childrenNodeList mnz_existsFolderWithName:textField.text]) {
                    [SVProgressHUD showErrorWithStatus:AMLocalizedString(@"There is already a folder with the same name", @"A tooltip message which is shown when a folder name is duplicated during renaming or creation.")];
                } else {
                    MEGACreateFolderRequestDelegate *createFolderRequestDelegate = [[MEGACreateFolderRequestDelegate alloc] initWithCompletion:nil];
                    [[MEGASdkManager sharedMEGASdk] createFolderWithName:textField.text parent:self.parentNode delegate:createFolderRequestDelegate];
                }
            }
        }];
        createFolderAlertAction.enabled = NO;
        [newFolderAlertController addAction:createFolderAlertAction];
        
        [self presentViewController:newFolderAlertController animated:YES completion:nil];
    }];
    [newFolderAlertAction mnz_setTitleTextColor:[UIColor mnz_black333333]];
    [moreAlertController addAction:newFolderAlertAction];
    
    UIAlertAction *sortByAlertAction = [UIAlertAction actionWithTitle:AMLocalizedString(@"sortTitle", @"Section title of the 'Sort by'") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self presentSortByViewController];
    }];
    [sortByAlertAction mnz_setTitleTextColor:[UIColor mnz_black333333]];
    [moreAlertController addAction:sortByAlertAction];
    
    UIAlertAction *selectAlertAction = [UIAlertAction actionWithTitle:AMLocalizedString(@"select", @"Button that allows you to select a given folder") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        BOOL enableEditing = !self.tableView.isEditing;
        [self setTableViewEditing:enableEditing animated:YES];
    }];
    [selectAlertAction mnz_setTitleTextColor:[UIColor mnz_black333333]];
    [moreAlertController addAction:selectAlertAction];
    
    UIAlertAction *rubbishBinAlertAction = [UIAlertAction actionWithTitle:AMLocalizedString(@"rubbishBinLabel", @"Title of one of the Settings sections where you can see your MEGA 'Rubbish Bin'") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        CloudDriveViewController *cloudDriveVC = [[UIStoryboard storyboardWithName:@"Cloud" bundle:nil] instantiateViewControllerWithIdentifier:@"CloudDriveID"];
        cloudDriveVC.parentNode = [[MEGASdkManager sharedMEGASdk] rubbishNode];
        cloudDriveVC.displayMode = DisplayModeRubbishBin;
        cloudDriveVC.title = AMLocalizedString(@"rubbishBinLabel", @"Title of one of the Settings sections where you can see your MEGA 'Rubbish Bin'");
        [self.navigationController pushViewController:cloudDriveVC animated:YES];
    }];
    [rubbishBinAlertAction mnz_setTitleTextColor:[UIColor mnz_black333333]];
    [moreAlertController addAction:rubbishBinAlertAction];
    
    [self presentFromMoreBarButtonItemTheAlertController:moreAlertController];
}

- (IBAction)moreMinimizedAction:(UIBarButtonItem *)sender {
    UIAlertController *moreMinimizedAlertController = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [moreMinimizedAlertController addAction:[UIAlertAction actionWithTitle:AMLocalizedString(@"cancel", @"Button title to cancel something") style:UIAlertActionStyleCancel handler:nil]];
    
    UIAlertAction *sortByAlertAction = [UIAlertAction actionWithTitle:AMLocalizedString(@"sortTitle", @"Section title of the 'Sort by'") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self presentSortByViewController];
    }];
    [sortByAlertAction mnz_setTitleTextColor:[UIColor mnz_black333333]];
    [moreMinimizedAlertController addAction:sortByAlertAction];
    
    UIAlertAction *selectAlertAction = [UIAlertAction actionWithTitle:AMLocalizedString(@"select", @"Button that allows you to select a given folder") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        BOOL enableEditing = !self.tableView.isEditing;
        [self setTableViewEditing:enableEditing animated:YES];
    }];
    [selectAlertAction mnz_setTitleTextColor:[UIColor mnz_black333333]];
    [moreMinimizedAlertController addAction:selectAlertAction];
    
    if ([[UIDevice currentDevice] iPadDevice]) {
        moreMinimizedAlertController.modalPresentationStyle = UIModalPresentationPopover;
        moreMinimizedAlertController.popoverPresentationController.barButtonItem = self.moreMinimizedBarButtonItem;
        moreMinimizedAlertController.popoverPresentationController.sourceView = self.view;
    }
    
    [self presentViewController:moreMinimizedAlertController animated:YES completion:nil];
}

- (IBAction)editTapped:(UIBarButtonItem *)sender {
    BOOL enableEditing = !self.tableView.isEditing;
    [self setTableViewEditing:enableEditing animated:YES];
}

- (void)setTableViewEditing:(BOOL)editing animated:(BOOL)animated {
    [self.tableView setEditing:editing animated:animated];

    [self updateNavigationBarTitle];
    
    if (editing) {
        self.editBarButtonItem.title = AMLocalizedString(@"cancel", @"Button title to cancel something");
        self.navigationItem.rightBarButtonItems = @[self.editBarButtonItem];
        self.navigationItem.leftBarButtonItems = @[self.selectAllBarButtonItem];
        [self.toolbar setAlpha:0.0];
        [self.tabBarController.tabBar addSubview:self.toolbar];
        [UIView animateWithDuration:0.33f animations:^ {
            [self.toolbar setAlpha:1.0];
        }];
    } else {
        self.editBarButtonItem.title = AMLocalizedString(@"edit", @"Caption of a button to edit the files that are selected");
        [self setNavigationBarButtonItems];
        allNodesSelected = NO;
        self.selectedNodesArray = nil;
        self.navigationItem.leftBarButtonItems = @[];
        
        [UIView animateWithDuration:0.33f animations:^ {
            [self.toolbar setAlpha:0.0];
        } completion:^(BOOL finished) {
            if (finished) {
                [self.toolbar removeFromSuperview];
            }
        }];
    }
    
    if (!self.selectedNodesArray) {
        self.selectedNodesArray = [NSMutableArray new];
        
        [self setToolbarActionsEnabled:NO];
    }
}

- (IBAction)downloadAction:(UIBarButtonItem *)sender {
    [SVProgressHUD showImage:[UIImage imageNamed:@"hudDownload"] status:AMLocalizedString(@"downloadStarted", nil)];
    
    for (MEGANode *node in self.selectedNodesArray) {
        if ([node mnz_downloadNodeOverwriting:NO]) {
            [self reloadRowAtIndexPath:[self.nodesIndexPathMutableDictionary objectForKey:node.base64Handle]];
        } else {
            return;
        }
    }
    
    [self setTableViewEditing:NO animated:YES];
    
    [self.tableView reloadData];
}

- (IBAction)shareAction:(UIBarButtonItem *)sender {
    UIActivityViewController *activityVC = [Helper activityViewControllerForNodes:self.selectedNodesArray sender:self.shareBarButtonItem];
    [self presentViewController:activityVC animated:YES completion:nil];
}

- (IBAction)moveAction:(UIBarButtonItem *)sender {
    MEGANavigationController *navigationController = [self.storyboard instantiateViewControllerWithIdentifier:@"BrowserNavigationControllerID"];
    [self presentViewController:navigationController animated:YES completion:nil];
    
    BrowserViewController *browserVC = navigationController.viewControllers.firstObject;
    browserVC.selectedNodesArray = [NSArray arrayWithArray:self.selectedNodesArray];
    if (lowShareType == MEGAShareTypeAccessOwner) {
        [browserVC setBrowserAction:BrowserActionMove];
    }
}

- (IBAction)deleteAction:(UIBarButtonItem *)sender {
    NSArray *numberOfFilesAndFoldersArray = self.selectedNodesArray.mnz_numberOfFilesAndFolders;
    NSUInteger numFilesAction = [[numberOfFilesAndFoldersArray objectAtIndex:0] unsignedIntegerValue];
    NSUInteger numFoldersAction = [[numberOfFilesAndFoldersArray objectAtIndex:1] unsignedIntegerValue];
    
    NSString *alertTitle;
    NSString *message;
    void (^handler)(UIAlertAction *action);
    void (^completion)(void) = ^{
        [self setTableViewEditing:NO animated:YES];
    };
    if (self.displayMode == DisplayModeCloudDrive) {
        if (numFilesAction == 0) {
            if (numFoldersAction == 1) {
                message = AMLocalizedString(@"moveFolderToRubbishBinMessage", nil);
            } else { //folders > 1
                message = [NSString stringWithFormat:AMLocalizedString(@"moveFoldersToRubbishBinMessage", nil), numFoldersAction];
            }
        } else if (numFilesAction == 1) {
            if (numFoldersAction == 0) {
                message = AMLocalizedString(@"moveFileToRubbishBinMessage", nil);
            } else if (numFoldersAction == 1) {
                message = AMLocalizedString(@"moveFileFolderToRubbishBinMessage", nil);
            } else {
                message = [NSString stringWithFormat:AMLocalizedString(@"moveFileFoldersToRubbishBinMessage", nil), numFoldersAction];
            }
        } else {
            if (numFoldersAction == 0) {
                message = [NSString stringWithFormat:AMLocalizedString(@"moveFilesToRubbishBinMessage", nil), numFilesAction];
            } else if (numFoldersAction == 1) {
                message = [NSString stringWithFormat:AMLocalizedString(@"moveFilesFolderToRubbishBinMessage", nil), numFilesAction];
            } else {
                message = AMLocalizedString(@"moveFilesFoldersToRubbishBinMessage", nil);
                NSString *filesString = [NSString stringWithFormat:@"%ld", (long)numFilesAction];
                NSString *foldersString = [NSString stringWithFormat:@"%ld", (long)numFoldersAction];
                message = [message stringByReplacingOccurrencesOfString:@"[A]" withString:filesString];
                message = [message stringByReplacingOccurrencesOfString:@"[B]" withString:foldersString];
            }
        }
        
        alertTitle = AMLocalizedString(@"moveToTheRubbishBin", @"Title for the action that allows you to 'Move to the Rubbish Bin' files or folders");
        
        handler = ^(UIAlertAction *action) {
            MEGAMoveRequestDelegate *moveRequestDelegate = [[MEGAMoveRequestDelegate alloc] initToMoveToTheRubbishBinWithFiles:numFilesAction folders:numFoldersAction completion:completion];
            MEGANode *rubbishBinNode = [[MEGASdkManager sharedMEGASdk] rubbishNode];
            for (MEGANode *node in self.selectedNodesArray) {
                [[MEGASdkManager sharedMEGASdk] moveNode:node newParent:rubbishBinNode delegate:moveRequestDelegate];
            }
        };
    } else {
        if (numFilesAction == 0) {
            if (numFoldersAction == 1) {
                message = AMLocalizedString(@"removeFolderToRubbishBinMessage", nil);
            } else { //folders > 1
                message = [NSString stringWithFormat:AMLocalizedString(@"removeFoldersToRubbishBinMessage", nil), numFoldersAction];
            }
        } else if (numFilesAction == 1) {
            if (numFoldersAction == 0) {
                message = AMLocalizedString(@"removeFileToRubbishBinMessage", nil);
            } else if (numFoldersAction == 1) {
                message = AMLocalizedString(@"removeFileFolderToRubbishBinMessage", nil);
            } else {
                message = [NSString stringWithFormat:AMLocalizedString(@"removeFileFoldersToRubbishBinMessage", nil), numFoldersAction];
            }
        } else {
            if (numFoldersAction == 0) {
                message = [NSString stringWithFormat:AMLocalizedString(@"removeFilesToRubbishBinMessage", nil), numFilesAction];
            } else if (numFoldersAction == 1) {
                message = [NSString stringWithFormat:AMLocalizedString(@"removeFilesFolderToRubbishBinMessage", nil), numFilesAction];
            } else {
                message = AMLocalizedString(@"removeFilesFoldersToRubbishBinMessage", nil);
                NSString *filesString = [NSString stringWithFormat:@"%ld", (long)numFilesAction];
                NSString *foldersString = [NSString stringWithFormat:@"%ld", (long)numFoldersAction];
                message = [message stringByReplacingOccurrencesOfString:@"[A]" withString:filesString];
                message = [message stringByReplacingOccurrencesOfString:@"[B]" withString:foldersString];
            }
        }
        
        alertTitle = AMLocalizedString(@"removeNodeFromRubbishBinTitle", @"Alert title shown on the Rubbish Bin when you want to remove some files and folders of your MEGA account");
        
        handler = ^(UIAlertAction *action) {
            MEGARemoveRequestDelegate *removeRequestDelegate = [[MEGARemoveRequestDelegate alloc] initWithMode:DisplayModeRubbishBin files:numFilesAction folders:numFoldersAction completion:completion];
            for (MEGANode *node in self.selectedNodesArray) {
                [[MEGASdkManager sharedMEGASdk] removeNode:node delegate:removeRequestDelegate];
            }
        };
    }
    
    UIAlertController *removeAlertController = [UIAlertController alertControllerWithTitle:alertTitle message:message preferredStyle:UIAlertControllerStyleAlert];
    [removeAlertController addAction:[UIAlertAction actionWithTitle:AMLocalizedString(@"cancel", @"Button title to cancel something") style:UIAlertActionStyleCancel handler:nil]];
    
    [removeAlertController addAction:[UIAlertAction actionWithTitle:AMLocalizedString(@"ok", @"Button title to cancel something") style:UIAlertActionStyleDefault handler:handler]];
    
    [self presentViewController:removeAlertController animated:YES completion:nil];
}

- (IBAction)copyAction:(UIBarButtonItem *)sender {
    if ([MEGAReachabilityManager isReachableHUDIfNot]) {
        MEGANavigationController *navigationController = [self.storyboard instantiateViewControllerWithIdentifier:@"BrowserNavigationControllerID"];
        [self presentViewController:navigationController animated:YES completion:nil];
        
        BrowserViewController *browserVC = navigationController.viewControllers.firstObject;
        browserVC.selectedNodesArray = self.selectedNodesArray;
        [browserVC setBrowserAction:BrowserActionCopy];
    }
}

- (IBAction)sortByAction:(UIBarButtonItem *)sender {
    [self presentSortByViewController];
}

- (IBAction)infoTouchUpInside:(UIButton *)sender {
    if (self.tableView.isEditing) {
        return;
    }
    
    CGPoint buttonPosition = [sender convertPoint:CGPointZero toView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:buttonPosition];
    
    MEGANode *node = self.searchController.isActive ? [self.searchNodesArray objectAtIndex:indexPath.row] : [self.nodes nodeAtIndex:indexPath.row];
    
    CustomActionViewController *actionController = [[CustomActionViewController alloc] init];
    actionController.node = node;
    actionController.displayMode = self.displayMode;
    actionController.incomingShareChildView = self.isIncomingShareChildView;
    actionController.actionDelegate = self;
    actionController.actionSender = sender;
    
    if ([[UIDevice currentDevice] iPadDevice]) {
        actionController.modalPresentationStyle = UIModalPresentationPopover;
        actionController.popoverPresentationController.delegate = actionController;
        actionController.popoverPresentationController.sourceView = sender;
        actionController.popoverPresentationController.sourceRect = CGRectMake(0, 0, sender.frame.size.width/2, sender.frame.size.height/2);
    } else {
        actionController.modalPresentationStyle = UIModalPresentationOverFullScreen;
    }
    [self presentViewController:actionController animated:YES completion:nil];
}

- (IBAction)restoreTouchUpInside:(UIBarButtonItem *)sender {
    for (MEGANode *node in self.selectedNodesArray) {        
        [node mnz_restore];
    }
    
    [self setTableViewEditing:NO animated:YES];
}

#pragma mark - UISearchBarDelegate

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    self.searchNodesArray = nil;
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *searchString = searchController.searchBar.text;
    [self.searchNodesArray removeAllObjects];
    if ([searchString isEqualToString:@""]) {
        self.searchNodesArray = [NSMutableArray arrayWithArray:self.nodesArray];
    } else {
        MEGANodeList *allNodeList = [[MEGASdkManager sharedMEGASdk] nodeListSearchForNode:self.parentNode searchString:searchString recursive:YES];
        
        for (NSInteger i = 0; i < [allNodeList.size integerValue]; i++) {
            MEGANode *n = [allNodeList nodeAtIndex:i];
            [self.searchNodesArray addObject:n];
        }
    }
    [self.tableView reloadData];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    if (controller.documentPickerMode == UIDocumentPickerModeImport) {
        NSError *error = nil;
        NSString *localFilePath = [[[NSFileManager defaultManager] uploadsDirectory] stringByAppendingPathComponent:url.lastPathComponent];
        if (![[NSFileManager defaultManager] moveItemAtPath:[url path] toPath:localFilePath error:&error]) {
            MEGALogError(@"Move item at path failed with error: %@", error);
        }
        
        NSString *fingerprint = [[MEGASdkManager sharedMEGASdk] fingerprintForFilePath:localFilePath];
        MEGANode *node = [[MEGASdkManager sharedMEGASdk] nodeForFingerprint:fingerprint parent:self.parentNode];
        
        // If file doesn't exist in MEGA then upload it
        if (node == nil) {
            [SVProgressHUD showSuccessWithStatus:AMLocalizedString(@"uploadStarted_Message", nil)];
            
            NSString *appData = [[NSString new] mnz_appDataToSaveCoordinates:localFilePath.mnz_coordinatesOfPhotoOrVideo];
            [[MEGASdkManager sharedMEGASdk] startUploadWithLocalPath:[localFilePath stringByReplacingOccurrencesOfString:[NSHomeDirectory() stringByAppendingString:@"/"] withString:@""] parent:self.parentNode appData:appData isSourceTemporary:YES];
        } else {
            if ([node parentHandle] == [self.parentNode handle]) {
                NSError *error = nil;
                if (![[NSFileManager defaultManager] removeItemAtPath:localFilePath error:&error]) {
                    MEGALogError(@"Remove item at path failed with error: %@", error);
                }
                
                NSString *alertMessage = AMLocalizedString(@"fileExistAlertController_Message", nil);
                
                NSString *localNameString = [NSString stringWithFormat:@"%@", [url lastPathComponent]];
                NSString *megaNameString = [NSString stringWithFormat:@"%@", [node name]];
                alertMessage = [alertMessage stringByReplacingOccurrencesOfString:@"[A]" withString:localNameString];
                alertMessage = [alertMessage stringByReplacingOccurrencesOfString:@"[B]" withString:megaNameString];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIAlertController *alertController = [UIAlertController
                                                          alertControllerWithTitle:nil
                                                          message:alertMessage
                                                          preferredStyle:UIAlertControllerStyleAlert];
                    [alertController addAction:[UIAlertAction actionWithTitle:AMLocalizedString(@"ok", nil) style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:alertController animated:YES completion:nil];
                });
            } else {
                [[MEGASdkManager sharedMEGASdk] copyNode:node newParent:self.parentNode newName:url.lastPathComponent];
            }
        }
    }
}

#pragma mark - UIDocumentMenuDelegate

- (void)documentMenu:(UIDocumentMenuViewController *)documentMenu didPickDocumentPicker:(UIDocumentPickerViewController *)documentPicker {
    documentPicker.delegate = self;
    [self presentViewController:documentPicker animated:YES completion:nil];
}

#pragma mark - MEGARequestDelegate

- (void)onRequestFinish:(MEGASdk *)api request:(MEGARequest *)request error:(MEGAError *)error {
    if ([error type]) {
        if ([error type] == MEGAErrorTypeApiEAccess) {
            if (request.type == MEGARequestTypeUpload) {
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:AMLocalizedString(@"permissionTitle", @"Error title shown when you are trying to do an action with a file or folder and you don't have the necessary permissions") message:AMLocalizedString(@"permissionMessage", @"Error message shown when you are trying to do an action with a file or folder and you don't have the necessary permissions") preferredStyle:UIAlertControllerStyleActionSheet];
                [self presentViewController:alertController animated:YES completion:nil];
            }
        }
        return;
    }
    
    switch ([request type]) {
        case MEGARequestTypeGetAttrFile: {
            for (NodeTableViewCell *nodeTableViewCell in [self.tableView visibleCells]) {
                if ([request nodeHandle] == [nodeTableViewCell nodeHandle]) {
                    MEGANode *node = [api nodeForHandle:request.nodeHandle];
                    [Helper setThumbnailForNode:node api:api cell:nodeTableViewCell reindexNode:YES];
                }
            }
            break;
        }
            
        case MEGARequestTypeCancelTransfer:
            break;
            
        default:
            break;
    }
}

#pragma mark - MEGAGlobalDelegate

- (void)onNodesUpdate:(MEGASdk *)api nodeList:(MEGANodeList *)nodeList {
    [self.nodesIndexPathMutableDictionary removeAllObjects];
    [self reloadUI];
}

#pragma mark - MEGATransferDelegate

- (void)onTransferStart:(MEGASdk *)api transfer:(MEGATransfer *)transfer {
    if (transfer.isStreamingTransfer) {
        return;
    }
    
    if (transfer.type == MEGATransferTypeDownload) {
        NSString *base64Handle = [MEGASdk base64HandleForHandle:transfer.nodeHandle];
        [self reloadRowAtIndexPath:[self.nodesIndexPathMutableDictionary objectForKey:base64Handle]];
    }
}

- (void)onTransferUpdate:(MEGASdk *)api transfer:(MEGATransfer *)transfer {
    if (transfer.isStreamingTransfer) {
        return;
    }
    
    NSString *base64Handle = [MEGASdk base64HandleForHandle:transfer.nodeHandle];
    
    if (transfer.type == MEGATransferTypeDownload && [[Helper downloadingNodes] objectForKey:base64Handle]) {
        float percentage = ([[transfer transferredBytes] floatValue] / [[transfer totalBytes] floatValue] * 100);
        NSString *percentageCompleted = [NSString stringWithFormat:@"%.f%%", percentage];
        NSString *speed = [NSString stringWithFormat:@"%@/s", [NSByteCountFormatter stringFromByteCount:[[transfer speed] longLongValue]  countStyle:NSByteCountFormatterCountStyleMemory]];
        
        NSIndexPath *indexPath = [self.nodesIndexPathMutableDictionary objectForKey:base64Handle];
        if (indexPath != nil) {
            NodeTableViewCell *cell = (NodeTableViewCell *)[self.tableView cellForRowAtIndexPath:indexPath];
            [cell.infoLabel setText:[NSString stringWithFormat:@"%@ • %@", percentageCompleted, speed]];
            cell.downloadProgressView.progress = [[transfer transferredBytes] floatValue] / [[transfer totalBytes] floatValue];
        }
    }
}

- (void)onTransferFinish:(MEGASdk *)api transfer:(MEGATransfer *)transfer error:(MEGAError *)error {
    if (transfer.isStreamingTransfer) {
        return;
    }
    
    if ([error type]) {
        if ([error type] == MEGAErrorTypeApiEAccess) {
            if ([transfer type] ==  MEGATransferTypeUpload) {
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:AMLocalizedString(@"permissionTitle", nil) message:AMLocalizedString(@"permissionMessage", nil) preferredStyle:UIAlertControllerStyleAlert];
                [alertController addAction:[UIAlertAction actionWithTitle:AMLocalizedString(@"ok", nil) style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:alertController animated:YES completion:nil];
            }
        } else if ([error type] == MEGAErrorTypeApiEIncomplete) {
            [SVProgressHUD showImage:[UIImage imageNamed:@"hudMinus"] status:AMLocalizedString(@"transferCancelled", nil)];
            NSString *base64Handle = [MEGASdk base64HandleForHandle:transfer.nodeHandle];
            [self reloadRowAtIndexPath:[self.nodesIndexPathMutableDictionary objectForKey:base64Handle]];
        }
        return;
    }
    
    if ([transfer type] == MEGATransferTypeDownload) {
        NSString *base64Handle = [MEGASdk base64HandleForHandle:transfer.nodeHandle];
        [self reloadRowAtIndexPath:[self.nodesIndexPathMutableDictionary objectForKey:base64Handle]];
    }
}

#pragma mark - MGSwipeTableCellDelegate

- (BOOL)swipeTableCell:(MGSwipeTableCell *)cell canSwipe:(MGSwipeDirection)direction fromPoint:(CGPoint)point {
    return !self.tableView.isEditing;
}

- (void)swipeTableCellWillBeginSwiping:(nonnull MGSwipeTableCell *)cell {
    NodeTableViewCell *nodeCell = (NodeTableViewCell *)cell;
    nodeCell.moreButton.hidden = YES;
}

- (void)swipeTableCellWillEndSwiping:(nonnull MGSwipeTableCell *)cell {
    NodeTableViewCell *nodeCell = (NodeTableViewCell *)cell;
    nodeCell.moreButton.hidden = NO;
}

- (NSArray *)swipeTableCell:(MGSwipeTableCell *)cell swipeButtonsForDirection:(MGSwipeDirection)direction
              swipeSettings:(MGSwipeSettings *)swipeSettings expansionSettings:(MGSwipeExpansionSettings *)expansionSettings {
    
    swipeSettings.transition = MGSwipeTransitionDrag;
    expansionSettings.buttonIndex = 0;
    expansionSettings.expansionLayout = MGSwipeExpansionLayoutCenter;
    expansionSettings.fillOnTrigger = NO;
    expansionSettings.threshold = 2;
    
    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    MEGANode *node = self.searchController.isActive ? [self.searchNodesArray objectAtIndex:indexPath.row] : [self.nodes nodeAtIndex:indexPath.row];
    
    if (direction == MGSwipeDirectionLeftToRight && [[Helper downloadingNodes] objectForKey:node.base64Handle] == nil) {
        if ([[MEGASdkManager sharedMEGASdk] isNodeInRubbish:node]) {
            return nil;
        } else {
            MGSwipeButton *downloadButton = [MGSwipeButton buttonWithTitle:@"" icon:[UIImage imageNamed:@"infoDownload"] backgroundColor:[UIColor colorWithRed:0.0 green:0.75 blue:0.65 alpha:1.0] padding:25 callback:^BOOL(MGSwipeTableCell *sender) {
                [node mnz_downloadNodeOverwriting:NO];
                return YES;
            }];
            [downloadButton iconTintColor:[UIColor whiteColor]];
            
            return @[downloadButton];
        }
    } else if (direction == MGSwipeDirectionRightToLeft) {
        if ([[MEGASdkManager sharedMEGASdk] accessLevelForNode:node] != MEGAShareTypeAccessOwner) {
            return nil;
        }
        
        if ([[MEGASdkManager sharedMEGASdk] isNodeInRubbish:node]) {
            MEGANode *restoreNode = [[MEGASdkManager sharedMEGASdk] nodeForHandle:node.restoreHandle];
            if (restoreNode && ![[MEGASdkManager sharedMEGASdk] isNodeInRubbish:restoreNode]) {
                MGSwipeButton *restoreButton = [MGSwipeButton buttonWithTitle:@"" icon:[UIImage imageNamed:@"restore"] backgroundColor:[UIColor colorWithRed:0.0 green:0.75 blue:0.65 alpha:1.0] padding:25 callback:^BOOL(MGSwipeTableCell *sender) {
                    [node mnz_restore];
                    return YES;
                }];
                [restoreButton iconTintColor:[UIColor whiteColor]];
                
                return @[restoreButton];
            }
        } else {
            MGSwipeButton *shareButton = [MGSwipeButton buttonWithTitle:@"" icon:[UIImage imageNamed:@"shareGray"] backgroundColor:[UIColor colorWithRed:1.0 green:0.64 blue:0 alpha:1.0] padding:25 callback:^BOOL(MGSwipeTableCell *sender) {
                UIActivityViewController *activityVC = [Helper activityViewControllerForNodes:@[node] sender:[self.tableView cellForRowAtIndexPath:indexPath]];
                [self presentViewController:activityVC animated:YES completion:nil];
                return YES;
            }];
            [shareButton iconTintColor:[UIColor whiteColor]];
            
            return @[shareButton];
        }
    }
    
    return nil;
}

#pragma mark - CustomActionViewControllerDelegate

- (void)performAction:(MegaNodeActionType)action inNode:(MEGANode *)node fromSender:(id)sender{
    switch (action) {
        case MegaNodeActionTypeDownload:
            [SVProgressHUD showImage:[UIImage imageNamed:@"hudDownload"] status:AMLocalizedString(@"downloadStarted", @"Message shown when a download starts")];
            if ([node mnz_downloadNodeOverwriting:NO]) {
                [self reloadRowAtIndexPath:[self.nodesIndexPathMutableDictionary objectForKey:node.base64Handle]];
            }
            break;
            
        case MegaNodeActionTypeCopy:
            self.selectedNodesArray = [[NSMutableArray alloc] initWithObjects:node, nil];
            [self copyAction:nil];
            break;
            
        case MegaNodeActionTypeMove:
            self.selectedNodesArray = [[NSMutableArray alloc] initWithObjects:node, nil];
            [self moveAction:nil];
            break;
            
        case MegaNodeActionTypeRename:
            [node mnz_renameNodeInViewController:self];
            break;
            
        case MegaNodeActionTypeShare: {
            UIActivityViewController *activityVC = [Helper activityViewControllerForNodes:@[node] sender:sender];
            [self presentViewController:activityVC animated:YES completion:nil];
        }
            break;
            
        case MegaNodeActionTypeFileInfo:
            [self showNodeInfo:node];
            break;
            
        case MegaNodeActionTypeLeaveSharing:
            [node mnz_leaveSharingInViewController:self];
            break;
            
        case MegaNodeActionTypeRemoveLink:
            break;
            
        case MegaNodeActionTypeMoveToRubbishBin:
            [node mnz_moveToTheRubbishBinInViewController:self];
            break;
            
        case MegaNodeActionTypeRemove:
            [node mnz_removeInViewController:self];
            break;
            
        case MegaNodeActionTypeRemoveSharing:
            [node mnz_removeSharing];
            break;
            
        case MegaNodeActionTypeRestore:
            [node mnz_restore];
            break;
            
        default:
            break;
    }
}

#pragma mark - NodeInfoViewControllerDelegate

- (void)presentParentNode:(MEGANode *)node {
    
    if (self.searchController.isActive) {
        NSArray *parentTreeArray = node.mnz_parentTreeArray;
        
        //Created a reference to self.navigationController because if the presented view is not the root controller and search is active, the 'popToRootViewControllerAnimated' makes nil the self.navigationController and therefore the parentTreeArray nodes can't be pushed
        UINavigationController *navigation = self.navigationController;
        [navigation popToRootViewControllerAnimated:NO];
        
        for (MEGANode *node in parentTreeArray) {
            CloudDriveViewController *cloudDriveVC = [self.storyboard instantiateViewControllerWithIdentifier:@"CloudDriveID"];
            cloudDriveVC.parentNode = node;
            [navigation pushViewController:cloudDriveVC animated:NO];
        }
        
        switch (node.type) {
            case MEGANodeTypeFolder:
            case MEGANodeTypeRubbish: {
                CloudDriveViewController *cloudDriveVC = [self.storyboard instantiateViewControllerWithIdentifier:@"CloudDriveID"];
                cloudDriveVC.parentNode = node;
                [navigation pushViewController:cloudDriveVC animated:NO];
                break;
            }
                
            default:
                break;
        }
    }
}

@end
