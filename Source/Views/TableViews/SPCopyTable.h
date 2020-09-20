//
//  SPCopyTable.h
//  sequel-pro
//
//  Created by Stuart Glenn on April 21, 2004.
//  Changed by Lorenz Textor on November 13, 2004.
//  Copyright (c) 2004 Stuart Glenn. All rights reserved.
//  Copyright (c) 2012 Sequel Pro Team. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//
//  More info at <https://github.com/sequelpro/sequelpro>

#import "SPTableView.h"

@class SPDataStorage;
@class SPTableContent;

#define SP_MAX_CELL_WIDTH_MULTICOLUMN 200
#define SP_MAX_CELL_WIDTH 400

extern NSInteger SPEditMenuCopy;
extern NSInteger SPEditMenuCopyWithColumns;
extern NSInteger SPEditMenuCopyAsSQL;
extern NSInteger SPEditMenuCopyAsSQLNoAutoInc;

/*!
	@class copyTable
	@abstract   subclassed NSTableView to implement copy & drag-n-drop
	@discussion Allows copying by creating a string with each table row as
		a separate line and each cell then separate via tabs. The drag out
		is in similar format. The values for each cell are obtained via the
		objects description method
*/
@interface SPCopyTable : SPTableView
{
	SPTableContent* tableInstance;    // the table content view instance
	id mySQLConnection;               // current MySQL connection
	NSArray* columnDefinitions;       // array of NSDictionary containing info about columns
	NSString* selectedTable;          // the name of the current selected table
	SPDataStorage* tableStorage;      // the underlying storage array holding the table data

	NSUserDefaults *prefs;

	NSRange fieldEditorSelectedRange;
	NSString *tmpBlobFileDirectory;
}

@property(readwrite,assign) NSString *tmpBlobFileDirectory;

@property(readwrite,assign) NSRange fieldEditorSelectedRange;

/*!
	@method	 copy:
	@abstract   does the work of copying
	@discussion gets selected (if any) row(s) as a string setting it 
	   then into th default pasteboard as a string type and tabular text type.
	@param	  sender who asked for this copy?
*/
- (void)copy:(id)sender;

/*!
	@method	 draggedRowsAsTabString:
	@abstract   getter of the dragged rows of the table for drag
	@discussion For the dragged rows returns a single string with each row
	   separated by a newline and then for each column value separated by a 
	   tab. Values are from the objects description method, so make sure it
	   returns something meaningful. 
	@result	 The above described string, or nil if nothing selected
*/
- (NSString *)draggedRowsAsTabString;

/*!
	@method	 draggingSourceOperationMaskForLocal:
	@discussion Allows for dragging out of the table to other applications
	@param	  isLocal who cares
	@result	 Always calls for a copy type drag operation
*/
- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal;

#ifndef SP_CODA /* method decls */
/*!
	@method	 rowsAsTabStringWithHeaders:onlySelectedRows:
	@abstract   getter of the selected rows or all of the table for copy
	@discussion For the selected rows or all returns a single string with each row
	   separated by a newline and then for each column value separated by a 
	   tab. Values are from the objects description method, so make sure it
	   returns something meaningful. 
	@result	 The above described string, or nil if nothing selected
*/
- (NSString *)rowsAsTabStringWithHeaders:(BOOL)withHeaders onlySelectedRows:(BOOL)onlySelected blobHandling:(NSInteger)withBlobHandling;

/*!
	@method	 rowsAsCsvStringWithHeaders:onlySelectedRows:
	@abstract   getter of the selected rows or all of the table csv formatted
	@discussion For the selected rows or all returns a single string with each row
	   separated by a newline and then for each column value separated by a 
	   , wherby each cell will be wrapped into quotes. Values are from the objects description method, so make sure it
	   returns something meaningful. 
	@result	 The above described string, or nil if nothing selected
*/
- (NSString *)rowsAsCsvStringWithHeaders:(BOOL)withHeaders onlySelectedRows:(BOOL)onlySelected blobHandling:(NSInteger)withBlobHandling;
#endif

/*!
 * Generate a string in form of INSERT INTO <table> VALUES () of 
 * currently selected rows or all. Support blob data as well.
 * @param  A bool determining all rows or just selected
 * @param  A bool to skip AUTO_INCREMENT column
 * @result SQL to insert the rows
*/
- (NSString *)rowsAsSqlInsertsOnlySelectedRows:(BOOL)onlySelected skipAutoIncrementColumn:(BOOL)skipAutoIncrementColumn;

/*!
 * Generate a string in form of INSERT INTO <table> VALUES () of
 * currently selected rows or all. Support blob data as well.
 * @param  A bool determining all rows or just selected
 * @result SQL to insert the rows
*/
- (NSString *)rowsAsSqlInsertsOnlySelectedRows:(BOOL)onlySelected;


/*
 * Set all necessary data from the table content view.
 */
- (void)setTableInstance:(id)anInstance withTableData:(SPDataStorage *)theTableStorage withColumns:(NSArray *)columnDefs withTableName:(NSString *)aTableName withConnection:(id)aMySqlConnection;

/*
 * Update the table storage location if necessary.
 */
- (void)setTableData:(SPDataStorage *)theTableStorage;

/*!
	@method  autodetectColumnWidths
	@abstract  Autodetect and return column widths based on contents
	@discussion  Support autocalculating column widths for the represented data.
		This uses the underlying table storage, calculates string widths,
		and eventually returns an array of table column widths.
		Suitable for calling on background threads, but ensure that the
		data storage range in use (currently rows 1-200) won't be altered
		while this accesses it.
	@result A dictionary - mapped by column identifier - of the column widths to use
*/
- (NSDictionary *)autodetectColumnWidths;

/*!
	@method  autodetectWidthForColumnDefinition:maxRows:
	@abstract  Autodetect and return column width based on contents
	@discussion  Support autocalculating column width for the represented data.
		This uses the underlying table storage, and the supplied column definition,
		iterating through the data and returning a reasonable column width to
		display that data.
		Suitable for calling on background threads, but ensure that the data
		storage range in use won't be altered while being accessed.
	@param  A column definition for a represented column; the column to use is derived
	@param  The maximum number of rows to process when looking at string lengths
	@result A reasonable column width to use when displaying data
*/
/**
 * Autodetect the column width for a specified column - derived from the supplied
 * column definition, using the stored data and the specified font.
 */
- (NSUInteger)autodetectWidthForColumnDefinition:(NSDictionary *)columnDefinition maxRows:(NSUInteger)rowsToCheck;

/*!
	@method	 validateMenuItem:
	@abstract   Dynamically enable Copy menu item for the table view
	@discussion Will only enable the Copy item when something is selected in
	  this table view
	@param	  anItem the menu item being validated
	@result	 YES if there is at least one row selected & the menu item is
	  copy, NO otherwise
*/
- (BOOL)validateMenuItem:(NSMenuItem*)anItem;

- (BOOL)isCellEditingMode;
- (BOOL)isCellComplex;

/*!
	@method	 shouldUseFieldEditorForRow:column:useLock:
	@abstract   Determine whether to trigger sheet editing or in-cell editing for a cell
	@discussion Checks the column data type, and the cell contents if necessary, to check
		the most appropriate editing type.
	@param	 rowIndex The row in the table the cell is present in
	@param	 colIndex The *original* column in the table the cell is present in (ie pre-reordering)
	@param	 dataLock An optional pthread_mutex_t lock to use when checking the data
	@result	 YES if sheet editing should be used, NO otherwise.
*/
- (BOOL)shouldUseFieldEditorForRow:(NSUInteger)rowIndex column:(NSUInteger)colIndex checkWithLock:(pthread_mutex_t *)dataLock;

- (IBAction)executeBundleItemForDataTable:(id)sender;

- (void)selectTableRows:(NSArray*)rowIndices;

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command;

@end
