#import "OfflineTableViewCell.h"

@implementation OfflineTableViewCell

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    if (editing) {
        [self setSeparatorInset:UIEdgeInsetsMake(0, 102, 0, 0)];
    } else {
        [self setSeparatorInset:UIEdgeInsetsMake(0, 62, 0, 0)];
    }
}

@end
