#import "BookmarkController.h"

@implementation BookmarkController

//const int ITEM_DELETE = 1;
static const int DIALOG_OK		= 128;
static const int DIALOG_CANCEL	= 129;


-(void)awakeFromNib
{
	NSArray *tableRowTypes = [NSArray arrayWithObject:@"row"];
	[bookmarkTableView registerForDraggedTypes:tableRowTypes];

	[bookmarkPanel setFrameAutosaveName:@"Bookmark"];
}

-(void)setPathDic:(NSDictionary*)dic
{
	directoryPath = [dic objectForKey:@"dirPath"];
}


#pragma mark editBookmark
-(void)editBookmark:(NSMutableArray*)array
{
	[bookmarkPanel setTarget:self];
    [bookmarkPanel setAction:@selector(keyDown:)];
	bookName = [[directoryPath lastPathComponent] retain];
	//	bookmarkArray = [[defaults objectForKey:bookName] retain];
	bookmarkArray = [array retain];

    [bookmarkTableView setDataSource:(id)self];
    [bookmarkTableView setDelegate:(id)self];
	[bookmarkTableView reloadData];


	sheetWindow = [NSApp keyWindow];
    [[NSApplication sharedApplication] beginSheet:bookmarkPanel
								   modalForWindow:sheetWindow
									modalDelegate:self
								   didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:)
									  contextInfo:nil];
}


- (void)sheetDidEnd:(NSWindow*)sheet
		 returnCode:(int)returnCode
		contextInfo:(void*)contextInfo
{
    [bookmarkPanel orderOut:self];
	[sheetWindow makeKeyWindow];

    if(returnCode == DIALOG_CANCEL) {
		[bookName release];
		[bookmarkArray release];
		bookmarkArray = nil;
    } else if(returnCode == DIALOG_OK) {
		[bookName release];
		[bookmarkArray release];
		bookmarkArray = nil;
		[controller setBookmarkMenu];
    }
}




/* The per-book panel is always run as a sheet (-beginSheet: above), so
   unlike the All Bookmark browser these end the sheet rather than a modal
   session. */
- (IBAction)ok:(id)sender;
{
	[[NSApplication sharedApplication] endSheet:bookmarkPanel returnCode:DIALOG_OK];
}


- (IBAction)cancel:(id)sender;
{
	[[NSApplication sharedApplication] endSheet:bookmarkPanel returnCode:DIALOG_CANCEL];
}


- (void)keyDown:(NSEvent *)theEvent
{
	int selectedRow;
	selectedRow = (int)[bookmarkTableView selectedRow];
	if (0 <= selectedRow) {
		[bookmarkArray removeObjectAtIndex:selectedRow];
		[bookmarkTableView reloadData];

	} else {
		NSBeep();
	}
}

#pragma mark -
- (IBAction)deleteRow:(id)sender;
{
	int selectedRow;
	selectedRow = (int)[bookmarkTableView selectedRow];
	if (0 <= selectedRow) {
		[bookmarkArray removeObjectAtIndex:selectedRow];
		[bookmarkTableView reloadData];

	}
}

-(IBAction)addNewBookmark:(id)sender
{
	int count = (int)[bookmarkArray count];

	NSString *bookmarkCountName = [NSString stringWithFormat:@"bookmark%i",count + 1];

	int bookmarkPage;
	bookmarkPage = [newBookmarkTextField intValue];
	if (bookmarkPage < 1) {
		NSBeep();
		return;
	}
	NSString *bookmarkNowPageString = [NSString stringWithFormat:@"%i",bookmarkPage];

	NSDictionary *bookmarkDic = [NSDictionary dictionaryWithObjectsAndKeys:
		bookmarkCountName, @"name",
		bookmarkNowPageString, @"page",
		nil];

	[bookmarkArray insertObject:bookmarkDic atIndex:count];
	[bookmarkTableView reloadData];
}

- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
    int selectedRow;
    selectedRow = (int)[bookmarkTableView selectedRow];

    if( [[anItem title] isEqualToString:NSLocalizedString(@"Delete this Bookmark", @"")] == YES){
		if (selectedRow > -1) {
			return YES;
		} else {
			return NO;
		}
    }
	return NO;

}


#pragma mark Table Delegate

- (BOOL)tableView:(NSTableView *)aTableView shouldEditTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
    return YES;
}


- (BOOL)tableView:(NSTableView *)aTableView shouldSelectRow:(int)rowIndex
{
	return YES;
}

#pragma mark tableDataSource

- (int)numberOfRowsInTableView:(NSTableView *)aTableView
{
	if (aTableView == bookmarkTableView) {
		return (int)[bookmarkArray count];
	}
	return 0;
}

- (id)tableView:(NSTableView *)aTableView
    objectValueForTableColumn:(NSTableColumn *)aTableColumn
			row:(int)rowIndex
{
	[[aTableColumn dataCell] setWraps:YES];
	static NSDictionary *info = nil;
	static NSDictionary *pageInfo = nil;
    if (nil == info) {
        NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
        [style setLineBreakMode:NSLineBreakByTruncatingMiddle];
        info = [[NSDictionary alloc] initWithObjectsAndKeys:style, NSParagraphStyleAttributeName, nil];
        [style release];
    }
    if (nil == pageInfo) {
        NSMutableParagraphStyle *pageStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
        [pageStyle setLineBreakMode:NSLineBreakByTruncatingMiddle];
        [pageStyle setAlignment:NSRightTextAlignment];
        pageInfo = [[NSDictionary alloc] initWithObjectsAndKeys:pageStyle, NSParagraphStyleAttributeName, nil];
        [pageStyle release];
    }

	if (aTableView == bookmarkTableView) {
		if([[aTableColumn identifier] isEqualToString:@"name"]) {
			if (bookmarkArray) {
				//return [[bookmarkArray objectAtIndex:rowIndex] objectForKey:@"name"];
				return [[[NSAttributedString alloc] initWithString:[[bookmarkArray objectAtIndex:rowIndex] objectForKey:@"name"]
														attributes:info] autorelease];
			} else {
				return nil;
			}
		} else if([[aTableColumn identifier] isEqualToString:@"page"]) {

			if (bookmarkArray) {
				//return [[bookmarkArray objectAtIndex:rowIndex] objectForKey:@"page"];
				return [[[NSAttributedString alloc] initWithString:[[bookmarkArray objectAtIndex:rowIndex] objectForKey:@"page"]
														attributes:pageInfo] autorelease];
			} else {
				return nil;
			}
		}
	}
	return nil;
}

- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn *)aTableColumn
			  row:(int)rowIndex
{
	if (!anObject) {
		return;
	}
	if (aTableView == bookmarkTableView) {
		if([[aTableColumn identifier] isEqualToString:@"name"]) {
			if (bookmarkArray) {
				NSDictionary *dic = [NSDictionary dictionaryWithObjectsAndKeys:
					anObject,@"name",
					[[bookmarkArray objectAtIndex:rowIndex] objectForKey:@"page"],@"page",
					nil];
				[bookmarkArray insertObject:dic atIndex:rowIndex+1];
				[bookmarkArray removeObjectAtIndex:rowIndex];
			}
		} else if([[aTableColumn identifier] isEqualToString:@"page"]) {
			if (bookmarkArray) {
				NSDictionary *dic = [NSDictionary dictionaryWithObjectsAndKeys:
					[[bookmarkArray objectAtIndex:rowIndex] objectForKey:@"name"],@"name",
					[NSString stringWithFormat:@"%@",anObject],@"page",
					nil];
				[bookmarkArray insertObject:dic atIndex:rowIndex+1];
				[bookmarkArray removeObjectAtIndex:rowIndex];
			}
		}
	}
}


#pragma mark tableDataSource_drag&drop

/*
-(BOOL)tableView:(NSTableView *)tv writeRows:(NSArray*)rows toPasteboard:(NSPasteboard*)pboard
{
	if (tv == bookmarkTableView) {
		[pboard declareTypes:[NSArray arrayWithObject:@"row"] owner:self];
		[pboard setPropertyList:rows forType:@"row"];
		return YES;
	}
	return NO;
}
*/
- (BOOL)tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard
{
    if (tv == bookmarkTableView) {
        NSMutableArray *rows=[NSMutableArray array];
            [rowIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
                [rows addObject:[NSNumber numberWithInteger:idx]];
            }];

        [pboard declareTypes:[NSArray arrayWithObject:@"row"] owner:self];
        [pboard setPropertyList:rows forType:@"row"];
        return YES;
    }
    return NO;
}

-(NSDragOperation)tableView:(NSTableView*)tv validateDrop:(id <NSDraggingInfo>)info proposedRow:(int)row proposedDropOperation:(NSTableViewDropOperation)op
{
	NSPasteboard *pboard=[info draggingPasteboard];

	if (op == NSTableViewDropAbove && [pboard availableTypeFromArray:[NSArray arrayWithObject:@"row"]] != nil) {
		return NSDragOperationGeneric;
	} else {
		return NSDragOperationNone;
	}
}
-(BOOL)tableView:(NSTableView*)tv acceptDrop:(id <NSDraggingInfo>)info row:(int)row dropOperation:(NSTableViewDropOperation)op
{
	NSPasteboard *pboard=[info draggingPasteboard];
	NSEnumerator *e=[[pboard propertyListForType:@"row"] objectEnumerator];
	NSNumber *number;

	if (tv == bookmarkTableView) {
		if (bookmarkArray) {
			NSMutableArray *upperArray=[NSMutableArray arrayWithArray:[bookmarkArray subarrayWithRange:NSMakeRange(0,row)]];
			NSMutableArray *lowerArray=[NSMutableArray arrayWithArray:[bookmarkArray subarrayWithRange:NSMakeRange(row,([bookmarkArray count] - row))]];
			NSMutableArray *middleArray=[NSMutableArray arrayWithCapacity:0];
			id object;
			int i;

			if (op == NSTableViewDropAbove && [pboard availableTypeFromArray:[NSArray arrayWithObject:@"row"]] != nil) {
				while ((number=[e nextObject]) != nil) {
					object=[bookmarkArray objectAtIndex:[number intValue]];
					[middleArray addObject:object];
					[upperArray removeObject:object];
					[lowerArray removeObject:object];
				}

				[bookmarkArray removeAllObjects];

				[bookmarkArray addObjectsFromArray:upperArray];
				[bookmarkArray addObjectsFromArray:middleArray];
				[bookmarkArray addObjectsFromArray:lowerArray];

				[tv reloadData];
				[tv deselectAll:nil];

				for (i=(int)[upperArray count];i<([upperArray count] + [middleArray count]);i++) {
                    [tv selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:[tv allowsMultipleSelection]];
				}

				return YES;
			} else {
				return NO;
			}
		}
	}
	return NO;
}
@end
