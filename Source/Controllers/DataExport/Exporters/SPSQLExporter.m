//
//  SPSQLExporter.m
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on August 29, 2009.
//  Copyright (c) 2009 Stuart Connolly. All rights reserved.
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

#import "SPSQLExporter.h"
#import "SPTablesList.h"
#import "SPFileHandle.h"
#import "SPExportUtilities.h"
#import "SPExportFile.h"
#import "SPTableData.h"
#import "RegexKitLite.h"
#import "SPExportController.h"
#import "SPFunctions.h"

#import "SPPostgresConnection.h"
#import "SPPostgresStreamingResultStore.h"
#import "SPPostgresGeometryData.h"
#include <stdlib.h>

@interface SPSQLExporter ()

- (NSString *)_createViewPlaceholderSyntaxForView:(NSString *)viewName;

@end

@implementation SPSQLExporter

@synthesize delegate;
@synthesize sqlExportTables;
@synthesize sqlDatabaseHost;
@synthesize sqlDatabaseName;
@synthesize sqlDatabaseVersion;
@synthesize sqlExportCurrentTable;
@synthesize sqlExportErrors;
@synthesize sqlOutputIncludeUTF8BOM;
@synthesize sqlOutputEncodeBLOBasHex;
@synthesize sqlOutputIncludeErrors;
@synthesize sqlOutputIncludeAutoIncrement;
@synthesize sqlOutputIncludeGeneratedColumns;
@synthesize sqlCurrentTableExportIndex;
@synthesize sqlInsertAfterNValue;
@synthesize sqlInsertDivider;

/**
 * Initialise an instance of SPSQLExporter using the supplied delegate.
 *
 * @param exportDelegate The exporter delegate
 *
 * @return The initialised instance
 */
- (instancetype)initWithDelegate:(NSObject<SPSQLExporterProtocol> *)exportDelegate
{
    if ((self = [super init])) {
        SPExportDelegateConformsToProtocol(exportDelegate, @protocol(SPSQLExporterProtocol));

        [self setDelegate:exportDelegate];
        [self setSqlExportCurrentTable:nil];

        [self setSqlInsertDivider:SPSQLInsertEveryNDataBytes];
        [self setSqlInsertAfterNValue:250000];
    }

    return self;
}

- (void)exportOperation
{
    // used in end_cleanup
    NSMutableString *errors     = [[NSMutableString alloc] init];
    NSMutableString *sqlString  = [[NSMutableString alloc] init];
    NSString *oldSqlMode        = nil;

    // Check that we have all the required info before starting the export
    if ((![self sqlExportTables])     || ([[self sqlExportTables] count] == 0)          ||
        (![self sqlDatabaseHost])     || ([[self sqlDatabaseHost] isEqualToString:@""]) ||
        (![self sqlDatabaseName])     || ([[self sqlDatabaseName] isEqualToString:@""]) ||
        (![self sqlDatabaseVersion]   || ([[self sqlDatabaseName] isEqualToString:@""])))
    {
        [self endCleanup:oldSqlMode];
        return;
    }

    sqlTableDataInstance = [[SPTableData alloc] init];
    [sqlTableDataInstance setConnection:connection];

    // Inform the delegate that the export process is about to begin
    [delegate performSelectorOnMainThread:@selector(sqlExportProcessWillBegin:) withObject:self waitUntilDone:NO];

    // Mark the process as running
    [self setExportProcessIsRunning:YES];

    // Clear errors
    [self setSqlExportErrors:@""];

    NSMutableArray *tables = [NSMutableArray array];
    NSMutableArray *procs  = [NSMutableArray array];
    NSMutableArray *funcs  = [NSMutableArray array];

    // Copy over the selected item names into tables in preparation for iteration
    for (NSArray *item in [self sqlExportTables])
    {
        // Check for cancellation flag
        if ([self isCancelled]) {
            [self endCleanup:oldSqlMode];
            return;
        }

        NSMutableArray *targetArray;
        switch ([[item safeObjectAtIndex:4] intValue]) {
            case SPTableTypeProc:
                targetArray = procs;
                break;
            case SPTableTypeFunc:
                targetArray = funcs;
                break;
            case SPTableTypeTable:
            default:
                targetArray = tables;
                break;
        }

        [targetArray addObject:item];
    }

    NSMutableString *metaString = [NSMutableString string];

    // If required write the UTF-8 Byte Order Mark (BOM)
    if ([self sqlOutputIncludeUTF8BOM]) {
        [metaString appendString:@"\xef\xbb\xbf"];
    }

    // we require UTF8
    [connection setEncoding:@"UTF8"];

    // Add the dump header to the dump file
    [metaString appendString:@"# ************************************************************\n"];
    [metaString appendString:@"# Sequel Ace SQL dump\n"];
    [metaString appendFormat:@"# %@ %@\n#\n", NSLocalizedString(@"Version", @"export header version label"), [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]];
    [metaString appendFormat:@"# %@\n# %@\n#\n", SPLOCALIZEDURL_HOMEPAGE, SPDevURL];
    [metaString appendFormat:@"# %@: %@ (MySQL %@)\n", NSLocalizedString(@"Host", @"export header host label"), [self sqlDatabaseHost], [self sqlDatabaseVersion]];
    [metaString appendFormat:@"# %@: %@\n", NSLocalizedString(@"Database", @"export header database label"), [self sqlDatabaseName]];
    [metaString appendFormat:@"# %@: %@\n", NSLocalizedString(@"Generation Time", @"export header generation time label"), [NSDate date]];
    [metaString appendString:@"# ************************************************************\n\n\n"];

    // PostgreSQL: Set client encoding to UTF8
    [metaString appendString:@"SET client_encoding = 'UTF8';\n"];

    // PostgreSQL: Disable foreign key checks by setting session_replication_role
    // This is the PostgreSQL equivalent of MySQL's FOREIGN_KEY_CHECKS=0
    [metaString appendString:@"SET session_replication_role = 'replica';\n"];

    // PostgreSQL doesn't use SQL_MODE like MySQL
    // No configuration changes needed for PostgreSQL export
    oldSqlMode = nil;
    // For this reason, mysqldump automatically includes in its output a statement that enables NO_AUTO_VALUE_ON_ZERO.
    //
    // so to address issue #865, where creating a table with a trigger discards NO_AUTO_VALUE_ON_ZERO,
    // by setting SESSION SQL_MODE to the mode used when the trigger was created then resetting SQL_MODE to @OLD_SQL_MODE
    // we add NO_AUTO_VALUE_ON_ZERO to @OLD_SQL_MODE here, for the export file to properly work.
    // Postgres doesn't use SQL_MODE like MySQL.
    // [metaString appendString:@"/*!40101 SET @OLD_SQL_MODE='NO_AUTO_VALUE_ON_ZERO', SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;\n"];
    // [metaString appendString:@"/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;\n\n\n"];

    [self writeString:metaString];

    NSMutableDictionary *viewSyntaxes = [NSMutableDictionary dictionary];

    // Loop through the selected tables
    for (NSArray *table in tables) {
        @autoreleasepool {

            if(self.exportOutputFile.fileHandleError != nil){
                SPMainQSync(^{
                    [(SPExportController*)self->delegate cancelExportForFile:self->exportOutputFile.exportFilePath];
                });
                return;
            }

            // Check for cancellation flag
            if ([self isCancelled]) {
                [self endCleanup:oldSqlMode];
                return;
            }

            [self setSqlCurrentTableExportIndex:[self sqlCurrentTableExportIndex]+1];
            NSString *tableName = [table firstObject];

            BOOL sqlOutputIncludeStructure  = [[table safeObjectAtIndex:1] boolValue];
            BOOL sqlOutputIncludeContent    = [[table safeObjectAtIndex:2] boolValue];
            BOOL sqlOutputIncludeDropSyntax = [[table safeObjectAtIndex:3] boolValue];

            // Skip tables if not set to output any detail for them
            if (!sqlOutputIncludeStructure && !sqlOutputIncludeContent && !sqlOutputIncludeDropSyntax) {
                continue;
            }

            // Set the current table
            [self setSqlExportCurrentTable:tableName];

            // Inform the delegate that we are about to start fetcihing data for the current table
            [delegate performSelectorOnMainThread:@selector(sqlExportProcessWillBeginFetchingData:) withObject:self waitUntilDone:NO];

            NSUInteger lastProgressValue = 0;

            id createTableSyntax = nil;
            SPTableType tableType = SPTableTypeTable;
            // Determine whether this table is a table or a view, and generate the CREATE syntax
            {
                // PostgreSQL: First check if this is a view
                SPPostgresResult *viewCheck = [connection queryString:[NSString stringWithFormat:
                    @"SELECT pg_get_viewdef(%@, true) AS view_def FROM pg_views WHERE viewname = %@",
                    [tableName tickQuotedString], [tableName tickQuotedString]]];
                [viewCheck setReturnDataAsStrings:YES];

                if ([viewCheck numberOfRows] > 0) {
                    // This is a view
                    NSDictionary *viewRow = [viewCheck getRowAsDictionary];
                    NSString *viewDef = [viewRow objectForKey:@"view_def"];
                    if (viewDef && ![viewDef isNSNull]) {
                        NSString *createViewSyntax = [NSString stringWithFormat:@"CREATE VIEW %@ AS\n%@", [tableName postgresQuotedIdentifier], viewDef];
                        [viewSyntaxes
                            setValue: [NSString stringWithFormat:@"%@%@",
                                            (sqlOutputIncludeDropSyntax ? [NSString stringWithFormat:@"DROP TABLE IF EXISTS %@; DROP VIEW IF EXISTS %@;\n\n", [tableName postgresQuotedIdentifier], [tableName postgresQuotedIdentifier]] : @""),
                                            createViewSyntax]
                            forKey: tableName
                        ];
                        createTableSyntax = [self _createViewPlaceholderSyntaxForView:tableName];
                        tableType = SPTableTypeView;
                    }
                }
                else {
                    // This is a table - build CREATE TABLE from information_schema
                    NSString *columnsQuery = [NSString stringWithFormat:
                        @"SELECT column_name, data_type, character_maximum_length, numeric_precision, numeric_scale, "
                        @"is_nullable, column_default "
                        @"FROM information_schema.columns "
                        @"WHERE table_schema = 'public' AND table_name = %@ "
                        @"ORDER BY ordinal_position", [tableName tickQuotedString]];

                    SPPostgresResult *columnsResult = [connection queryString:columnsQuery];
                    [columnsResult setReturnDataAsStrings:YES];

                    if ([columnsResult numberOfRows] > 0) {
                        NSMutableString *createStmt = [NSMutableString stringWithFormat:@"CREATE TABLE %@ (\n", [tableName postgresQuotedIdentifier]];
                        NSMutableArray *columnDefs = [NSMutableArray array];

                        for (NSDictionary *row in columnsResult) {
                            NSMutableString *colDef = [NSMutableString stringWithFormat:@"  %@", [[row objectForKey:@"column_name"] postgresQuotedIdentifier]];

                            NSString *dataType = [row objectForKey:@"data_type"];
                            id maxLength = [row objectForKey:@"character_maximum_length"];
                            id numericPrecision = [row objectForKey:@"numeric_precision"];
                            id numericScale = [row objectForKey:@"numeric_scale"];

                            if (maxLength && ![maxLength isKindOfClass:[NSNull class]]) {
                                [colDef appendFormat:@" %@(%@)", dataType, maxLength];
                            } else if (numericPrecision && ![numericPrecision isKindOfClass:[NSNull class]] &&
                                       numericScale && ![numericScale isKindOfClass:[NSNull class]]) {
                                [colDef appendFormat:@" %@(%@,%@)", dataType, numericPrecision, numericScale];
                            } else {
                                [colDef appendFormat:@" %@", dataType];
                            }

                            id isNullable = [row objectForKey:@"is_nullable"];
                            BOOL isNotNullable = NO;
                            if ([isNullable isKindOfClass:[NSString class]]) {
                                isNotNullable = [isNullable isEqualToString:@"NO"];
                            } else if ([isNullable isKindOfClass:[NSNumber class]]) {
                                isNotNullable = ![isNullable boolValue];
                            }
                            if (isNotNullable) {
                                [colDef appendString:@" NOT NULL"];
                            }

                            id defaultValue = [row objectForKey:@"column_default"];
                            if (defaultValue && ![defaultValue isKindOfClass:[NSNull class]] && [defaultValue length]) {
                                [colDef appendFormat:@" DEFAULT %@", defaultValue];
                            }

                            [columnDefs addObject:colDef];
                        }

                        // Add primary key constraint if exists
                        NSString *pkQuery = [NSString stringWithFormat:
                            @"SELECT string_agg(kcu.column_name, ', ') AS pk_columns "
                            @"FROM information_schema.table_constraints tc "
                            @"JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name "
                            @"WHERE tc.table_name = %@ AND tc.constraint_type = 'PRIMARY KEY' "
                            @"GROUP BY tc.constraint_name", [tableName tickQuotedString]];
                        SPPostgresResult *pkResult = [connection queryString:pkQuery];
                        [pkResult setReturnDataAsStrings:YES];
                        if ([pkResult numberOfRows] > 0) {
                            NSDictionary *pkRow = [pkResult getRowAsDictionary];
                            NSString *pkColumns = [pkRow objectForKey:@"pk_columns"];
                            if (pkColumns && ![pkColumns isNSNull]) {
                                [columnDefs addObject:[NSString stringWithFormat:@"  PRIMARY KEY (%@)", pkColumns]];
                            }
                        }

                        [createStmt appendString:[columnDefs componentsJoinedByString:@",\n"]];
                        [createStmt appendString:@"\n)"];

                        createTableSyntax = createStmt;
                        tableType = SPTableTypeTable;
                    }
                }

                if ([connection queryErrored]) {
                    [errors appendFormat:@"%@\n", [connection lastErrorMessage] ?: NSLocalizedString(@"Unknown error", @"unknown error")];

                    [self writeUTF8String:[NSString stringWithFormat:@"-- Error: %@\n\n\n", [connection lastErrorMessage] ?: NSLocalizedString(@"Unknown error", @"unknown error")]];

                    continue;
                }
            }



            if(tableType == SPTableTypeTable) {
                // Add the name of table
                [self writeString:[NSString stringWithFormat:@"# %@ %@\n# ------------------------------------------------------------\n\n", NSLocalizedString(@"Dump of table", @"sql export dump of table label"), tableName]];
            }

            // Add a 'DROP TABLE' command if required
            if (sqlOutputIncludeDropSyntax && tableType == SPTableTypeTable) {
                [self writeString:[NSString stringWithFormat:@"DROP %@ IF EXISTS %@;\n\n", ((tableType == SPTableTypeTable) ? @"TABLE" : @"VIEW"), [tableName postgresQuotedIdentifier]]];
            }

            // Add the create syntax for the table if specified in the export dialog
            if (sqlOutputIncludeStructure && createTableSyntax && tableType == SPTableTypeTable) {

                if ([createTableSyntax isKindOfClass:[NSData class]]) {
#warning This doesn't make sense. If the NSData really contains a string it would be in utf8, UTF8 or a mysql pre-4.1 legacy charset, but not in the export output charset. This whole if() is likely a side effect of the BINARY flag confusion (#2700)
                    createTableSyntax = [[NSString alloc] initWithData:createTableSyntax encoding:[self exportOutputEncoding]];
                }

                // If necessary strip out the AUTO_INCREMENT from the table structure definition
                if (![self sqlOutputIncludeAutoIncrement]) {
                    createTableSyntax = [createTableSyntax stringByReplacingOccurrencesOfRegex:[NSString stringWithFormat:@"AUTO_INCREMENT=[0-9]+ "] withString:@""];
                }

                [self writeUTF8String:createTableSyntax];
                [self writeUTF8String:@";\n\n"];
            }

            // Add the table content if required
            if (sqlOutputIncludeContent && (tableType == SPTableTypeTable)) {
                // Retrieve the table details via the data class, and use it to build an array containing column numeric status
                NSDictionary *tableDetails = [NSDictionary dictionaryWithDictionary:[sqlTableDataInstance informationForTable:tableName fromDatabase:nil]];

                NSUInteger colCount = [[tableDetails objectForKey:@"columns"] count];
                NSUInteger colCountRetained = colCount;

                // Counts the number of GENERATED type fields if columns should be excluded from rows
                if (!sqlOutputIncludeGeneratedColumns) {
                    for (NSUInteger j = 0; j < colCount; j++)
                    {
                        NSDictionary *theColumnDetail = [[tableDetails objectForKey:@"columns"] safeObjectAtIndex:j];
                        NSString *generatedAlways = [theColumnDetail objectForKey:@"generatedalways"];
                        if (generatedAlways) {
                            colCountRetained--;
                        }
                    }
                }

                NSMutableArray *rawColumnNames = [NSMutableArray arrayWithCapacity:(colCountRetained)];
                NSMutableArray *queryColumnDetails = [NSMutableArray arrayWithCapacity:(colCountRetained)];

                BOOL *useRawDataForColumnAtIndex = calloc(colCountRetained, sizeof(BOOL));
                BOOL *useRawHexDataForColumnAtIndex = calloc(colCountRetained, sizeof(BOOL));

                // Determine whether raw data can be used for each column during processing - safe numbers and hex-encoded data.
                NSUInteger jj = 0;
                for (NSUInteger j = 0; j < colCount; j++)
                {
                    NSDictionary *theColumnDetail = [[tableDetails objectForKey:@"columns"] safeObjectAtIndex:j];
                    NSString *theTypeGrouping = [theColumnDetail objectForKey:@"typegrouping"];
                    NSString *generatedAlways = [theColumnDetail objectForKey:@"generatedalways"];

                    if ( sqlOutputIncludeGeneratedColumns || !generatedAlways ) {
                        // Start by setting the column as non-safe
                        useRawDataForColumnAtIndex[jj] = NO;
                        useRawHexDataForColumnAtIndex[jj] = NO;

                        // Determine whether the column should be retrieved as hex data from the server - for binary strings, to
                        // avoid encoding issues when processing
                        if ([self sqlOutputEncodeBLOBasHex]
                            && [theTypeGrouping isEqualToString:@"string"]
                            && ([[theColumnDetail objectForKey:@"binary"] boolValue] || [[theColumnDetail objectForKey:@"collation"] hasSuffix:@"_bin"]))
                        {
                            useRawHexDataForColumnAtIndex[j] = YES;
                        }

                        // Floats, integers can be output directly assuming they're non-binary
                        if (![[theColumnDetail objectForKey:@"binary"] boolValue] && ([@[@"integer",@"float"] containsObject:theTypeGrouping]))
                        {
                            useRawDataForColumnAtIndex[jj] = YES;
                        }

                        // Set up the column query string parts
                        [rawColumnNames addObject:[theColumnDetail objectForKey:@"name"]];

                        if (useRawHexDataForColumnAtIndex[jj]) {
                            [queryColumnDetails addObject:[NSString stringWithFormat:@"HEX(%@)", [[theColumnDetail objectForKey:@"name"] postgresQuotedIdentifier]]];
                        }
                        else {
                            [queryColumnDetails addObject:[[theColumnDetail objectForKey:@"name"] postgresQuotedIdentifier]];
                        }
                        jj++;
                    }
                }

                // Retrieve the number of rows in the table for progress bar drawing
                NSArray *rowArray = [[connection queryString:[NSString stringWithFormat:@"SELECT COUNT(1) FROM %@", [tableName postgresQuotedIdentifier]]] getRowAsArray];

                if ([connection queryErrored] || ![rowArray count]) {
                    [errors appendFormat:@"%@\n", [connection lastErrorMessage] ?: NSLocalizedString(@"Unknown error", @"unknown error")];
                    [self writeUTF8String:[NSString stringWithFormat:@"# Error: %@\n\n\n", [connection lastErrorMessage] ?: NSLocalizedString(@"Unknown error", @"unknown error")]];
                    free(useRawDataForColumnAtIndex);
                    free(useRawHexDataForColumnAtIndex);
                    continue;
                }

                NSUInteger rowCount = [[rowArray firstObject] integerValue];

                if (rowCount) {
                    // Set up a result set in streaming mode
                    SPPostgresStreamingResult *streamingResult = [connection streamingQueryString:[NSString stringWithFormat:@"SELECT %@ FROM %@", [queryColumnDetails componentsJoinedByString:@", "], [tableName postgresQuotedIdentifier]] useLowMemoryBlockingStreaming:([self exportUsingLowMemoryBlockingStreaming])];

                    // Inform the delegate that we are about to start writing data for the current table
                    [delegate performSelectorOnMainThread:@selector(sqlExportProcessWillBeginWritingData:) withObject:self waitUntilDone:NO];

                    NSUInteger queryLength = 0;

                    // Lock the table for writing and disable keys if supported
                    [metaString setString:@""];
                    [metaString appendFormat:@"LOCK TABLE %@ IN EXCLUSIVE MODE;\n", [tableName postgresQuotedIdentifier]];

                    [self writeString:metaString];

                    // Construct the start of the insertion command
                    [self writeUTF8String:[NSString stringWithFormat:@"INSERT INTO %@ (%@)\nVALUES", [tableName postgresQuotedIdentifier], [rawColumnNames componentsJoinedAndBacktickQuoted]]];

                    // Iterate through the rows to construct a VALUES group for each
                    NSUInteger rowsWrittenForTable = 0;
                    NSUInteger rowsWrittenForCurrentStmt = 0;

                    // Inform the delegate that we are about to start writing the data to disk
                    [delegate performSelectorOnMainThread:@selector(sqlExportProcessWillBeginWritingData:) withObject:self waitUntilDone:NO];

                    NSArray *row;
                    while ((row = [streamingResult getRowAsArray]))
                    {

                        if(self.exportOutputFile.fileHandleError != nil){
                            SPMainQSync(^{
                                [(SPExportController*)self->delegate cancelExportForFile:self->exportOutputFile.exportFilePath];
                            });
                            return;
                        }

                        // Check for cancellation flag
                        if ([self isCancelled]) {
                            [connection cancelCurrentQuery];
                            [streamingResult cancelResultLoad];
                            free(useRawDataForColumnAtIndex);
                            free(useRawHexDataForColumnAtIndex);

                            [self endCleanup:oldSqlMode];
                            return;
                        }

                        // Update the progress
                        NSUInteger progress = (NSUInteger)((rowsWrittenForTable + 1) * ([self exportMaxProgress] / rowCount));

                        if (progress > lastProgressValue) {
                            [self setExportProgressValue:progress];
                            lastProgressValue = progress;

                            // Inform the delegate that the export's progress has been updated
                            [delegate performSelectorOnMainThread:@selector(sqlExportProcessProgressUpdated:) withObject:self waitUntilDone:NO];
                        }

                        // Set up the new row as appropriate.  If a new INSERT statement should be created,
                        // set one up; otherwise, set up a new row
                        if ((([self sqlInsertDivider] == SPSQLInsertEveryNDataBytes) && (queryLength >= ([self sqlInsertAfterNValue] * 1024))) ||
                            (([self sqlInsertDivider] == SPSQLInsertEveryNRows) && (rowsWrittenForCurrentStmt == [self sqlInsertAfterNValue])))
                        {
                            [sqlString setString:@";\n\nINSERT INTO "];
                            [sqlString appendString:[tableName postgresQuotedIdentifier]];
                            [sqlString appendString:@" ("];
                            [sqlString appendString:[rawColumnNames componentsJoinedAndBacktickQuoted]];
                            [sqlString appendString:@")\nVALUES\n\t("];

                            queryLength = 0;
                            rowsWrittenForCurrentStmt = 0;
                        }
                        else if (rowsWrittenForTable == 0) {
                            [sqlString setString:@"\n\t("];
                        }
                        else {
                            [sqlString setString:@",\n\t("];
                        }

                        for (NSUInteger t = 0; t < colCountRetained; t++)
                        {
                            id object = [row safeObjectAtIndex:t];
                          	NSDictionary *fieldDetails = [[tableDetails safeObjectForKey:@"columns"] safeObjectAtIndex:t];

                            // Add NULL values directly to the output row; use a pointer comparison to the singleton
                            // instance for speed.
                            if (object == [NSNull null]) {
                                [sqlString appendString:@"NULL"];
                            }

                            // Add trusted raw values directly
                            else if (useRawDataForColumnAtIndex[t]) {
                                [sqlString appendString:object];
                            }

                            // If the field is of type BIT, the values need a binary prefix of b'x'.
                            else if ([[fieldDetails safeObjectForKey:@"type"] isEqualToString:@"BIT"]) {
                                [sqlString appendFormat:@"b'%@'", [object description]];
                            }

                            // Add pre-encoded hex types (binary strings) as enclosed but otherwise trusted data
                            else if (useRawHexDataForColumnAtIndex[t]) {
                                [sqlString appendFormat:@"X'%@'", object];
                            }

                            // GEOMETRY data types directly as hex data
                            else if ([object isKindOfClass:[SPPostgresGeometryData class]]) {
                                [sqlString appendString:[connection escapeAndQuoteData:[object data]]];
                            }

                            // Add zero-length data or strings as an empty string
                            else if ([object length] == 0) {
                                [sqlString appendString:@"''"];
                            }

                            // Add other data types as hex data
                            else if ([object isKindOfClass:[NSData class]]) {

                                if ([self sqlOutputEncodeBLOBasHex]) {
                                    [sqlString appendString:[connection escapeAndQuoteData:object]];
                                }
                                else {
                                    NSString *data = [[NSString alloc] initWithData:object encoding:[self exportOutputEncoding]];

                                    if (data == nil) {
                                    // warning This can corrupt data! Check if this case ever happens and if so, export as hex-string
                                      data = [[NSString alloc] initWithData:object encoding:NSASCIIStringEncoding];
                                    }
                                  
                                    NSString *fieldTypeGroup = [fieldDetails objectForKey:@"typegrouping"];
                                  	if ([fieldTypeGroup isEqualToString:@"textdata"] || [fieldTypeGroup isEqualToString:@"string"]) {
                                      [sqlString appendStringOrNil:[connection escapeAndQuoteString:data]];
                                    } else {
                                      // it's possible that the fieldType could eq to blob
                                      [sqlString appendFormat:@"'%@'", data];
                                    }
                                }
                            }

                            // Otherwise add a quoted string with special characters escaped
                            else {
                                [sqlString appendStringOrNil:[connection escapeAndQuoteString:object]];
                            }

                            // Add the field separator if this isn't the last cell in the row
                            if (t != ([row count] - 1)) [sqlString appendString:@","];
                        }

                        [sqlString appendString:@")"];
                        queryLength += [sqlString length];

                        // Write this row to the file
                        [self writeUTF8String:sqlString];

                        rowsWrittenForTable++;
                        rowsWrittenForCurrentStmt++;
                    }

                    // Complete the command
                    [self writeUTF8String:@";\n\n"];

                    // Unlock the table and re-enable keys if supported
                    [metaString setString:@""];
                    [metaString appendFormat:@"-- UNLOCK TABLE %@;\n", [tableName postgresQuotedIdentifier]];

                    [self writeUTF8String:metaString];

                    // Release the result set
                }

                free(useRawDataForColumnAtIndex);
                free(useRawHexDataForColumnAtIndex);

                if ([connection queryErrored]) {
                    [errors appendFormat:@"%@\n", [connection lastErrorMessage] ?: NSLocalizedString(@"Unknown error", @"unknown error")];

                    if ([self sqlOutputIncludeErrors]) {
                        [self writeUTF8String:[NSString stringWithFormat:@"# Error: %@\n", [connection lastErrorMessage] ?: NSLocalizedString(@"Unknown error", @"unknown error")]];
                    }
                }
            }

            // Add triggers if the structure export was enabled
            if (sqlOutputIncludeStructure) {
                // PostgreSQL: Query triggers from information_schema
                SPPostgresResult *queryResult = [connection queryString:[NSString stringWithFormat:
                    @"SELECT trigger_name, event_manipulation, action_timing, action_statement "
                    @"FROM information_schema.triggers "
                    @"WHERE event_object_table = %@ AND trigger_schema = 'public'",
                    [tableName tickQuotedString]]];

                [queryResult setReturnDataAsStrings:YES];

                if ([queryResult numberOfRows]) {

                    [metaString setString:@"\n"];
                    [metaString appendString:@"-- Triggers\n"];

                    for (NSUInteger s = 0; s < [queryResult numberOfRows]; s++)
                    {

                        if(self.exportOutputFile.fileHandleError != nil){
                            SPMainQSync(^{
                                [(SPExportController*)self->delegate cancelExportForFile:self->exportOutputFile.exportFilePath];
                            });
                            return;
                        }

                        // Check for cancellation flag
                        if ([self isCancelled]) {
                            [self endCleanup:oldSqlMode];
                            return;
                        }

                        NSDictionary *triggers = [[NSDictionary alloc] initWithDictionary:[queryResult getRowAsDictionary]];

                        // PostgreSQL trigger format
                        [metaString appendFormat:@"CREATE TRIGGER %@ %@ %@ ON %@ FOR EACH ROW %@;\n",
                         [[triggers objectForKey:@"trigger_name"] postgresQuotedIdentifier],
                         [triggers objectForKey:@"action_timing"],
                         [triggers objectForKey:@"event_manipulation"],
                         [tableName postgresQuotedIdentifier],
                         [triggers objectForKey:@"action_statement"]];
                    }

                    [metaString appendString:@"\n"];

                    [self writeUTF8String:metaString];
                }

                if ([connection queryErrored]) {
                    [errors appendFormat:@"%@\n", [connection lastErrorMessage] ?: NSLocalizedString(@"Unknown error", @"unknown error")];

                    if ([self sqlOutputIncludeErrors]) {
                        [self writeUTF8String:[NSString stringWithFormat:@"# Error: %@\n", [connection lastErrorMessage] ?: NSLocalizedString(@"Unknown error", @"unknown error")]];
                    }
                }
            }

            // Add an additional separator between tables
            [self writeUTF8String:@"\n\n"];
        }
    }

    // Process any deferred views, adding commands to delete the placeholder tables and add the actual views
    for (NSString *viewName in viewSyntaxes)
    {

        if(self.exportOutputFile.fileHandleError != nil){
            SPMainQSync(^{
                [(SPExportController*)self->delegate cancelExportForFile:self->exportOutputFile.exportFilePath];
            });
            return;
        }

        // Check for cancellation flag
        if ([self isCancelled]) {
            [self endCleanup:oldSqlMode];
            return;
        }

        [metaString setString:@""];

        // Add the name of View
        [self writeString:[NSString stringWithFormat:@"# %@ %@\n# ------------------------------------------------------------\n\n", NSLocalizedString(@"Dump of view", @"sql export dump of view label"), viewName]];

        // Add the View create statement
        [metaString appendFormat:@"%@;\n\n", [viewSyntaxes objectForKey:viewName]];

        [self writeUTF8String:metaString];
    }

    // Export procedures and functions
    for (NSString *procedureType in @[@"PROCEDURE", @"FUNCTION"])
    {

        if(self.exportOutputFile.fileHandleError != nil){
            SPMainQSync(^{
                [(SPExportController*)self->delegate cancelExportForFile:self->exportOutputFile.exportFilePath];
            });
            return;
        }
        // Check for cancellation flag
        if ([self isCancelled]) {
            [self endCleanup:oldSqlMode];
            return;
        }

        // Retrieve the array of selected procedures or functions, and skip export if not selected
        NSMutableArray *items;

        if ([procedureType isEqualToString:@"PROCEDURE"]) items = procs;
        else items = funcs;

        if ([items count] == 0) continue;

        // Retrieve the definitions from PostgreSQL
        // PostgreSQL: Query pg_proc for function/procedure definitions
        NSString *prokind = [procedureType isEqualToString:@"PROCEDURE"] ? @"p" : @"f";
        SPPostgresResult *queryResult = [connection queryString:[NSString stringWithFormat:
            @"SELECT p.proname AS \"Name\", pg_get_functiondef(p.oid) AS definition "
            @"FROM pg_proc p "
            @"JOIN pg_namespace n ON p.pronamespace = n.oid "
            @"WHERE n.nspname = 'public' AND p.prokind = '%@'", prokind]];

        [queryResult setReturnDataAsStrings:YES];

        if ([queryResult numberOfRows]) {

            [metaString setString:@"\n"];
            [metaString appendFormat:@"--\n-- Dumping routines (%@) for database %@\n--\n\n", procedureType,
             [[self sqlDatabaseName] postgresQuotedIdentifier]];

            // Loop through the definitions, exporting if enabled
            for (NSUInteger s = 0; s < [queryResult numberOfRows]; s++) {
                @autoreleasepool {
                    if(self.exportOutputFile.fileHandleError != nil){
                        SPMainQSync(^{
                            [(SPExportController*)self->delegate cancelExportForFile:self->exportOutputFile.exportFilePath];
                        });
                        return;
                    }

                    // Check for cancellation flag
                    if ([self isCancelled]) {
                        [self endCleanup:oldSqlMode];
                        return;
                    }

                    NSDictionary *proceduresList = [[NSDictionary alloc] initWithDictionary:[queryResult getRowAsDictionary]];
                    NSString *procedureName = [NSString stringWithFormat:@"%@", [proceduresList objectForKey:@"Name"]];

                    // Only proceed if the item is in the list of items
                    BOOL itemFound = NO;
                    BOOL sqlOutputIncludeStructure = NO;
                    BOOL sqlOutputIncludeDropSyntax = NO;
                    for (NSArray *item in items)
                    {

                        if(self.exportOutputFile.fileHandleError != nil){
                            SPMainQSync(^{
                                [(SPExportController*)self->delegate cancelExportForFile:self->exportOutputFile.exportFilePath];
                            });
                            return;
                        }

                        // Check for cancellation flag
                        if ([self isCancelled]) {
                            [self endCleanup:oldSqlMode];
                            return;
                        }

                        if ([[item firstObject] isEqualToString:procedureName]) {
                            itemFound = YES;
                            sqlOutputIncludeStructure  = [[item safeObjectAtIndex:1] boolValue];
                            sqlOutputIncludeDropSyntax = [[item safeObjectAtIndex:3] boolValue];
                            break;
                        }
                    }
                    if (!itemFound) {
                        continue;
                    }

                    if (sqlOutputIncludeStructure || sqlOutputIncludeDropSyntax)
                        [metaString appendFormat:@"-- Dump of %@ %@\n-- ------------------------------------------------------------\n\n", procedureType, procedureName];

                    // Add the 'DROP' command if required
                    if (sqlOutputIncludeDropSyntax) {
                        [metaString appendFormat:@"DROP %@ IF EXISTS %@;\n", procedureType,
                         [procedureName postgresQuotedIdentifier]];
                    }

                    // Only continue if the 'CREATE SYNTAX' is required
                    if (!sqlOutputIncludeStructure) {
                        continue;
                    }

                    // Get the function definition directly from the query result
                    NSString *functionDef = [proceduresList objectForKey:@"definition"];
                    if (functionDef && ![functionDef isNSNull]) {
                        [metaString appendFormat:@"%@;\n\n", functionDef];
                    }

                }
            }

            [self writeUTF8String:metaString];
        }

        if ([connection queryErrored]) {
            [errors appendFormat:@"%@\n", [connection lastErrorMessage] ?: NSLocalizedString(@"Unknown error", @"unknown error")];

            if ([self sqlOutputIncludeErrors]) {
                [self writeUTF8String:[NSString stringWithFormat:@"# Error: %@\n", [connection lastErrorMessage] ?: NSLocalizedString(@"Unknown error", @"unknown error")]];
            }
        }
    }

    // PostgreSQL: Restore session settings
    [metaString setString:@"\n"];
    // Re-enable foreign key checks
    [metaString appendString:@"SET session_replication_role = 'origin';\n"];

    // Write footer-type information to the file
    [self writeUTF8String:metaString];

    // Set export errors
    [self setSqlExportErrors:errors];

    // Close the file
    [[self exportOutputFile] close];

    // Mark the process as not running
    [self setExportProcessIsRunning:NO];

    // Inform the delegate that the export process is complete
    [delegate performSelectorOnMainThread:@selector(sqlExportProcessComplete:) withObject:self waitUntilDone:NO];

    [self endCleanup:oldSqlMode];
}

- (void)endCleanup:(NSString *)oldSqlMode {
    // PostgreSQL doesn't use SQL_MODE, nothing to restore
}

/**
 * Returns whether or not any export errors occurred by examing the length of the errors string.
 *
 * @return A BOOL indicating the occurrence of errors
 */
- (BOOL)didExportErrorsOccur
{
    return ([[self sqlExportErrors] length] != 0);
}

/**
 * Retrieve information for a view and use that to construct a CREATE TABLE string for an equivalent basic
 * table. Allows the construction of placeholder tables to resolve view interdependencies within dumps.
 *
 * @param viewName The name of the view for which the placeholder is to be created for.
 *
 * @return The CREATE TABLE placeholder syntax
 */
- (NSString *)_createViewPlaceholderSyntaxForView:(NSString *)viewName
{
    NSUInteger i, j;
    NSMutableString *placeholderSyntax;

    // Get structured information for the view via the SPTableData parsers
    NSDictionary *viewInformation = [sqlTableDataInstance informationForView:viewName];

    if (!viewInformation) return nil;

    NSArray *viewColumns = [viewInformation objectForKey:@"columns"];

    // Set up the start of the placeholder string and initialise an empty field string
    placeholderSyntax = [[NSMutableString alloc] initWithFormat:@"CREATE TABLE %@ (\n", [viewName postgresQuotedIdentifier]];


    // Loop through the columns, creating an appropriate column definition for each and appending it to the syntax string
    for (i = 0; i < [viewColumns count]; i++) {
        @autoreleasepool {
            NSDictionary *column = [viewColumns safeObjectAtIndex:i];

            NSMutableString *fieldString = [[NSMutableString alloc] initWithString:[[column objectForKey:@"name"] postgresQuotedIdentifier]];

            // Add the type and length information as appropriate
            if ([column objectForKey:@"length"]) {
                NSString *length = [column objectForKey:@"length"];
                NSString *decimals = [column objectForKey:@"decimals"];
                if([decimals length]) {
                    length = [length stringByAppendingFormat:@",%@", decimals];
                }
                [fieldString appendFormat:@" %@(%@)", [column objectForKey:@"type"], length];
            }
            else if ([column objectForKey:@"values"]) {
                [fieldString appendFormat:@" %@(", [column objectForKey:@"type"]];

                for (j = 0; j < [[column objectForKey:@"values"] count]; j++)
                {
                    [fieldString appendString:[connection escapeAndQuoteString:[[column safeObjectForKey:@"values"] safeObjectAtIndex:j]]];
                    if ((j + 1) != [[column objectForKey:@"values"] count]) {
                        [fieldString appendString:@","];
                    }
                }

                [fieldString appendString:@")"];
            }
            else {
                [fieldString appendFormat:@" %@", [column objectForKey:@"type"]];
            }

            // PostgreSQL doesn't support UNSIGNED, ZEROFILL, or BINARY column modifiers
            // These MySQL-specific attributes are intentionally not exported for PostgreSQL compatibility
            if ([[column objectForKey:@"null"] integerValue] == 0) {
                [fieldString appendString:@" NOT NULL"];
            } else {
                [fieldString appendString:@" NULL"];
            }

            // Provide the field default if appropriate
            if ([column objectForKey:@"default"]) {

                // Some MySQL server versions show a default of NULL for NOT NULL columns - don't export those.
                // Check against the NSNull singleton instance for speed.
                if ([column objectForKey:@"default"] == [NSNull null]) {
                    if ([[column objectForKey:@"null"] integerValue]) {
                        [fieldString appendString:@" DEFAULT NULL"];
                    }
                }
                else if (([[column objectForKey:@"type"] isInArray:@[@"TIMESTAMP",@"DATETIME"]]) && [[column objectForKey:@"default"] isMatchedByRegex:SPCurrentTimestampPattern]) {
                    [fieldString appendFormat:@" DEFAULT %@",[column objectForKey:@"default"]];
                }
                else {
                    [fieldString appendFormat:@" DEFAULT %@", [connection escapeAndQuoteString:[column objectForKey:@"default"]]];
                }
            }

            // Extras aren't required for the temp table
            // Add the field string to the syntax string
            [placeholderSyntax appendFormat:@"   %@%@\n", fieldString, (i == [viewColumns count] - 1) ? @"" : @","];
        }
    }

    // Append the remainder of the table string
    [placeholderSyntax appendString:@") ENGINE=MyISAM"];

    // Clean up and return

    return placeholderSyntax;
}

@end
