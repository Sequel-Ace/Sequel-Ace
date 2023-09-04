//
//  Field Definitions.m
//  SPMySQLFramework
//
//  Created by Rowan Beentje (rowan.beent.je) on February 2, 2012
//  Copyright (c) 2012 Rowan Beentje. All rights reserved.
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

#import "Field Definitions.h"
#import "SPMySQL Private APIs.h"

@interface SPMySQLResult (Field_Definitions_Private_API)

- (NSUInteger)_findCharsetMaxByteLengthPerCharForMySQLNumber:(NSUInteger)charsetnr;
- (NSString *)_charsetNameForMySQLNumber:(NSUInteger)charsetnr;
- (NSString *)_charsetCollationForMySQLNumber:(NSUInteger)charsetnr;
- (NSString *)_mysqlTypeToStringForType:(NSUInteger)type withCharsetNr:(NSUInteger)charsetnr withFlags:(NSUInteger)flags withLength:(unsigned long long)length;
- (NSString *)_mysqlTypeToGroupForType:(NSUInteger)type withCharsetNr:(NSUInteger)charsetnr withFlags:(NSUInteger)flags;

@end

#define MAGIC_BINARY_CHARSET_NR 63


//SELECT CONCAT(
//"{", AA.ID, ",",
//  (CASE WHEN AA.ID < 10 THEN "  " WHEN AA.ID < 100 THEN " " ELSE "" END),
// "\"",
// AA.CHARACTER_SET_NAME,
// "\", \"",
// AA.COLLATION_NAME,
// "\", 1, ",CS.MAXLEN, "},"
// )
//
//FROM information_schema.collations AS AA
//JOIN information_schema.character_sets AS CS ON CS.CHARACTER_SET_NAME=AA.CHARACTER_SET_NAME GROUP BY AA.ID ORDER BY AA.ID
const SPMySQLResultCharset SPMySQLCharsetMap[] =
{
    {1,  "big5", "big5_chinese_ci", 1, 2},
    {2,  "latin2", "latin2_czech_cs", 1, 1},
    {3,  "dec8", "dec8_swedish_ci", 1, 1},
    {4,  "cp850", "cp850_general_ci", 1, 1},
    {5,  "latin1", "latin1_german1_ci", 1, 1},
    {6,  "hp8", "hp8_english_ci", 1, 1},
    {7,  "koi8r", "koi8r_general_ci", 1, 1},
    {8,  "latin1", "latin1_swedish_ci", 1, 1},
    {9,  "latin2", "latin2_general_ci", 1, 1},
    {10, "swe7", "swe7_swedish_ci", 1, 1},
    {11, "ascii", "ascii_general_ci", 1, 1},
    {12, "ujis", "ujis_japanese_ci", 1, 3},
    {13, "sjis", "sjis_japanese_ci", 1, 2},
    {14, "cp1251", "cp1251_bulgarian_ci", 1, 1},
    {15, "latin1", "latin1_danish_ci", 1, 1},
    {16, "hebrew", "hebrew_general_ci", 1, 1},
    {18, "tis620", "tis620_thai_ci", 1, 1},
    {19, "euckr", "euckr_korean_ci", 1, 2},
    {20, "latin7", "latin7_estonian_cs", 1, 1},
    {21, "latin2", "latin2_hungarian_ci", 1, 1},
    {22, "koi8u", "koi8u_general_ci", 1, 1},
    {23, "cp1251", "cp1251_ukrainian_ci", 1, 1},
    {24, "gb2312", "gb2312_chinese_ci", 1, 2},
    {25, "greek", "greek_general_ci", 1, 1},
    {26, "cp1250", "cp1250_general_ci", 1, 1},
    {27, "latin2", "latin2_croatian_ci", 1, 1},
    {28, "gbk", "gbk_chinese_ci", 1, 2},
    {29, "cp1257", "cp1257_lithuanian_ci", 1, 1},
    {30, "latin5", "latin5_turkish_ci", 1, 1},
    {31, "latin1", "latin1_german2_ci", 1, 1},
    {32, "armscii8", "armscii8_general_ci", 1, 1},
    {33, "utf8", "utf8_general_ci", 1, 3},
    {34, "cp1250", "cp1250_czech_cs", 1, 1},
    {35, "ucs2", "ucs2_general_ci", 1, 2},
    {36, "cp866", "cp866_general_ci", 1, 1},
    {37, "keybcs2", "keybcs2_general_ci", 1, 1},
    {38, "macce", "macce_general_ci", 1, 1},
    {39, "macroman", "macroman_general_ci", 1, 1},
    {40, "cp852", "cp852_general_ci", 1, 1},
    {41, "latin7", "latin7_general_ci", 1, 1},
    {42, "latin7", "latin7_general_cs", 1, 1},
    {43, "macce", "macce_bin", 1, 1},
    {44, "cp1250", "cp1250_croatian_ci", 1, 1},
    {45, "utf8mb4", "utf8mb4_general_ci", 1, 4},
    {46, "utf8mb4", "utf8mb4_bin", 1, 4},
    {47, "latin1", "latin1_bin", 1, 1},
    {48, "latin1", "latin1_general_ci", 1, 1},
    {49, "latin1", "latin1_general_cs", 1, 1},
    {50, "cp1251", "cp1251_bin", 1, 1},
    {51, "cp1251", "cp1251_general_ci", 1, 1},
    {52, "cp1251", "cp1251_general_cs", 1, 1},
    {53, "macroman", "macroman_bin", 1, 1},
    {54, "utf16", "utf16_general_ci", 1, 4},
    {55, "utf16", "utf16_bin", 1, 4},
    {56, "utf16le", "utf16le_general_ci", 1, 4},
    {57, "cp1256", "cp1256_general_ci", 1, 1},
    {58, "cp1257", "cp1257_bin", 1, 1},
    {59, "cp1257", "cp1257_general_ci", 1, 1},
    {60, "utf32", "utf32_general_ci", 1, 4},
    {61, "utf32", "utf32_bin", 1, 4},
    {62, "utf16le", "utf16le_bin", 1, 4},
    {63, "binary", "binary", 1, 1},
    {64, "armscii8", "armscii8_bin", 1, 1},
    {65, "ascii", "ascii_bin", 1, 1},
    {66, "cp1250", "cp1250_bin", 1, 1},
    {67, "cp1256", "cp1256_bin", 1, 1},
    {68, "cp866", "cp866_bin", 1, 1},
    {69, "dec8", "dec8_bin", 1, 1},
    {70, "greek", "greek_bin", 1, 1},
    {71, "hebrew", "hebrew_bin", 1, 1},
    {72, "hp8", "hp8_bin", 1, 1},
    {73, "keybcs2", "keybcs2_bin", 1, 1},
    {74, "koi8r", "koi8r_bin", 1, 1},
    {75, "koi8u", "koi8u_bin", 1, 1},
    {76, "utf8", "utf8_tolower_ci", 1, 3},
    {77, "latin2", "latin2_bin", 1, 1},
    {78, "latin5", "latin5_bin", 1, 1},
    {79, "latin7", "latin7_bin", 1, 1},
    {80, "cp850", "cp850_bin", 1, 1},
    {81, "cp852", "cp852_bin", 1, 1},
    {82, "swe7", "swe7_bin", 1, 1},
    {83, "utf8", "utf8_bin", 1, 3},
    {84, "big5", "big5_bin", 1, 2},
    {85, "euckr", "euckr_bin", 1, 2},
    {86, "gb2312", "gb2312_bin", 1, 2},
    {87, "gbk", "gbk_bin", 1, 2},
    {88, "sjis", "sjis_bin", 1, 2},
    {89, "tis620", "tis620_bin", 1, 1},
    {90, "ucs2", "ucs2_bin", 1, 2},
    {91, "ujis", "ujis_bin", 1, 3},
    {92, "geostd8", "geostd8_general_ci", 1, 1},
    {93, "geostd8", "geostd8_bin", 1, 1},
    {94, "latin1", "latin1_spanish_ci", 1, 1},
    {95, "cp932", "cp932_japanese_ci", 1, 2},
    {96, "cp932", "cp932_bin", 1, 2},
    {97, "eucjpms", "eucjpms_japanese_ci", 1, 3},
    {98, "eucjpms", "eucjpms_bin", 1, 3},
    {99, "cp1250", "cp1250_polish_ci", 1, 1},
    {101,"utf16", "utf16_unicode_ci", 1, 4},
    {102,"utf16", "utf16_icelandic_ci", 1, 4},
    {103,"utf16", "utf16_latvian_ci", 1, 4},
    {104,"utf16", "utf16_romanian_ci", 1, 4},
    {105,"utf16", "utf16_slovenian_ci", 1, 4},
    {106,"utf16", "utf16_polish_ci", 1, 4},
    {107,"utf16", "utf16_estonian_ci", 1, 4},
    {108,"utf16", "utf16_spanish_ci", 1, 4},
    {109,"utf16", "utf16_swedish_ci", 1, 4},
    {110,"utf16", "utf16_turkish_ci", 1, 4},
    {111,"utf16", "utf16_czech_ci", 1, 4},
    {112,"utf16", "utf16_danish_ci", 1, 4},
    {113,"utf16", "utf16_lithuanian_ci", 1, 4},
    {114,"utf16", "utf16_slovak_ci", 1, 4},
    {115,"utf16", "utf16_spanish2_ci", 1, 4},
    {116,"utf16", "utf16_roman_ci", 1, 4},
    {117,"utf16", "utf16_persian_ci", 1, 4},
    {118,"utf16", "utf16_esperanto_ci", 1, 4},
    {119,"utf16", "utf16_hungarian_ci", 1, 4},
    {120,"utf16", "utf16_sinhala_ci", 1, 4},
    {121,"utf16", "utf16_german2_ci", 1, 4},
    {122,"utf16", "utf16_croatian_ci", 1, 4},
    {123,"utf16", "utf16_unicode_520_ci", 1, 4},
    {124,"utf16", "utf16_vietnamese_ci", 1, 4},
    {128,"ucs2", "ucs2_unicode_ci", 1, 2},
    {129,"ucs2", "ucs2_icelandic_ci", 1, 2},
    {130,"ucs2", "ucs2_latvian_ci", 1, 2},
    {131,"ucs2", "ucs2_romanian_ci", 1, 2},
    {132,"ucs2", "ucs2_slovenian_ci", 1, 2},
    {133,"ucs2", "ucs2_polish_ci", 1, 2},
    {134,"ucs2", "ucs2_estonian_ci", 1, 2},
    {135,"ucs2", "ucs2_spanish_ci", 1, 2},
    {136,"ucs2", "ucs2_swedish_ci", 1, 2},
    {137,"ucs2", "ucs2_turkish_ci", 1, 2},
    {138,"ucs2", "ucs2_czech_ci", 1, 2},
    {139,"ucs2", "ucs2_danish_ci", 1, 2},
    {140,"ucs2", "ucs2_lithuanian_ci", 1, 2},
    {141,"ucs2", "ucs2_slovak_ci", 1, 2},
    {142,"ucs2", "ucs2_spanish2_ci", 1, 2},
    {143,"ucs2", "ucs2_roman_ci", 1, 2},
    {144,"ucs2", "ucs2_persian_ci", 1, 2},
    {145,"ucs2", "ucs2_esperanto_ci", 1, 2},
    {146,"ucs2", "ucs2_hungarian_ci", 1, 2},
    {147,"ucs2", "ucs2_sinhala_ci", 1, 2},
    {148,"ucs2", "ucs2_german2_ci", 1, 2},
    {149,"ucs2", "ucs2_croatian_ci", 1, 2},
    {150,"ucs2", "ucs2_unicode_520_ci", 1, 2},
    {151,"ucs2", "ucs2_vietnamese_ci", 1, 2},
    {159,"ucs2", "ucs2_general_mysql500_ci", 1, 2},
    {160,"utf32", "utf32_unicode_ci", 1, 4},
    {161,"utf32", "utf32_icelandic_ci", 1, 4},
    {162,"utf32", "utf32_latvian_ci", 1, 4},
    {163,"utf32", "utf32_romanian_ci", 1, 4},
    {164,"utf32", "utf32_slovenian_ci", 1, 4},
    {165,"utf32", "utf32_polish_ci", 1, 4},
    {166,"utf32", "utf32_estonian_ci", 1, 4},
    {167,"utf32", "utf32_spanish_ci", 1, 4},
    {168,"utf32", "utf32_swedish_ci", 1, 4},
    {169,"utf32", "utf32_turkish_ci", 1, 4},
    {170,"utf32", "utf32_czech_ci", 1, 4},
    {171,"utf32", "utf32_danish_ci", 1, 4},
    {172,"utf32", "utf32_lithuanian_ci", 1, 4},
    {173,"utf32", "utf32_slovak_ci", 1, 4},
    {174,"utf32", "utf32_spanish2_ci", 1, 4},
    {175,"utf32", "utf32_roman_ci", 1, 4},
    {176,"utf32", "utf32_persian_ci", 1, 4},
    {177,"utf32", "utf32_esperanto_ci", 1, 4},
    {178,"utf32", "utf32_hungarian_ci", 1, 4},
    {179,"utf32", "utf32_sinhala_ci", 1, 4},
    {180,"utf32", "utf32_german2_ci", 1, 4},
    {181,"utf32", "utf32_croatian_ci", 1, 4},
    {182,"utf32", "utf32_unicode_520_ci", 1, 4},
    {183,"utf32", "utf32_vietnamese_ci", 1, 4},
    {192,"utf8", "utf8_unicode_ci", 1, 3},
    {193,"utf8", "utf8_icelandic_ci", 1, 3},
    {194,"utf8", "utf8_latvian_ci", 1, 3},
    {195,"utf8", "utf8_romanian_ci", 1, 3},
    {196,"utf8", "utf8_slovenian_ci", 1, 3},
    {197,"utf8", "utf8_polish_ci", 1, 3},
    {198,"utf8", "utf8_estonian_ci", 1, 3},
    {199,"utf8", "utf8_spanish_ci", 1, 3},
    {200,"utf8", "utf8_swedish_ci", 1, 3},
    {201,"utf8", "utf8_turkish_ci", 1, 3},
    {202,"utf8", "utf8_czech_ci", 1, 3},
    {203,"utf8", "utf8_danish_ci", 1, 3},
    {204,"utf8", "utf8_lithuanian_ci", 1, 3},
    {205,"utf8", "utf8_slovak_ci", 1, 3},
    {206,"utf8", "utf8_spanish2_ci", 1, 3},
    {207,"utf8", "utf8_roman_ci", 1, 3},
    {208,"utf8", "utf8_persian_ci", 1, 3},
    {209,"utf8", "utf8_esperanto_ci", 1, 3},
    {210,"utf8", "utf8_hungarian_ci", 1, 3},
    {211,"utf8", "utf8_sinhala_ci", 1, 3},
    {212,"utf8", "utf8_german2_ci", 1, 3},
    {213,"utf8", "utf8_croatian_ci", 1, 3},
    {214,"utf8", "utf8_unicode_520_ci", 1, 3},
    {215,"utf8", "utf8_vietnamese_ci", 1, 3},
    {223,"utf8", "utf8_general_mysql500_ci", 1, 3},
    {224,"utf8mb4", "utf8mb4_unicode_ci", 1, 4},
    {225,"utf8mb4", "utf8mb4_icelandic_ci", 1, 4},
    {226,"utf8mb4", "utf8mb4_latvian_ci", 1, 4},
    {227,"utf8mb4", "utf8mb4_romanian_ci", 1, 4},
    {228,"utf8mb4", "utf8mb4_slovenian_ci", 1, 4},
    {229,"utf8mb4", "utf8mb4_polish_ci", 1, 4},
    {230,"utf8mb4", "utf8mb4_estonian_ci", 1, 4},
    {231,"utf8mb4", "utf8mb4_spanish_ci", 1, 4},
    {232,"utf8mb4", "utf8mb4_swedish_ci", 1, 4},
    {233,"utf8mb4", "utf8mb4_turkish_ci", 1, 4},
    {234,"utf8mb4", "utf8mb4_czech_ci", 1, 4},
    {235,"utf8mb4", "utf8mb4_danish_ci", 1, 4},
    {236,"utf8mb4", "utf8mb4_lithuanian_ci", 1, 4},
    {237,"utf8mb4", "utf8mb4_slovak_ci", 1, 4},
    {238,"utf8mb4", "utf8mb4_spanish2_ci", 1, 4},
    {239,"utf8mb4", "utf8mb4_roman_ci", 1, 4},
    {240,"utf8mb4", "utf8mb4_persian_ci", 1, 4},
    {241,"utf8mb4", "utf8mb4_esperanto_ci", 1, 4},
    {242,"utf8mb4", "utf8mb4_hungarian_ci", 1, 4},
    {243,"utf8mb4", "utf8mb4_sinhala_ci", 1, 4},
    {244,"utf8mb4", "utf8mb4_german2_ci", 1, 4},
    {245,"utf8mb4", "utf8mb4_croatian_ci", 1, 4},
    {246,"utf8mb4", "utf8mb4_unicode_520_ci", 1, 4},
    {247,"utf8mb4", "utf8mb4_vietnamese_ci", 1, 4},
    {248,"gb18030", "gb18030_chinese_ci", 1, 4},
    {249,"gb18030", "gb18030_bin", 1, 4},
    {250,"gb18030", "gb18030_unicode_520_ci", 1, 4},
    {255,"utf8mb4", "utf8mb4_0900_ai_ci", 1, 4},
    {256,"utf8mb4", "utf8mb4_de_pb_0900_ai_ci", 1, 4},
    {257,"utf8mb4", "utf8mb4_is_0900_ai_ci", 1, 4},
    {258,"utf8mb4", "utf8mb4_lv_0900_ai_ci", 1, 4},
    {259,"utf8mb4", "utf8mb4_ro_0900_ai_ci", 1, 4},
    {260,"utf8mb4", "utf8mb4_sl_0900_ai_ci", 1, 4},
    {261,"utf8mb4", "utf8mb4_pl_0900_ai_ci", 1, 4},
    {262,"utf8mb4", "utf8mb4_et_0900_ai_ci", 1, 4},
    {263,"utf8mb4", "utf8mb4_es_0900_ai_ci", 1, 4},
    {264,"utf8mb4", "utf8mb4_sv_0900_ai_ci", 1, 4},
    {265,"utf8mb4", "utf8mb4_tr_0900_ai_ci", 1, 4},
    {266,"utf8mb4", "utf8mb4_cs_0900_ai_ci", 1, 4},
    {267,"utf8mb4", "utf8mb4_da_0900_ai_ci", 1, 4},
    {268,"utf8mb4", "utf8mb4_lt_0900_ai_ci", 1, 4},
    {269,"utf8mb4", "utf8mb4_sk_0900_ai_ci", 1, 4},
    {270,"utf8mb4", "utf8mb4_es_trad_0900_ai_ci", 1, 4},
    {271,"utf8mb4", "utf8mb4_la_0900_ai_ci", 1, 4},
    {273,"utf8mb4", "utf8mb4_eo_0900_ai_ci", 1, 4},
    {274,"utf8mb4", "utf8mb4_hu_0900_ai_ci", 1, 4},
    {275,"utf8mb4", "utf8mb4_hr_0900_ai_ci", 1, 4},
    {277,"utf8mb4", "utf8mb4_vi_0900_ai_ci", 1, 4},
    {278,"utf8mb4", "utf8mb4_0900_as_cs", 1, 4},
    {279,"utf8mb4", "utf8mb4_de_pb_0900_as_cs", 1, 4},
    {280,"utf8mb4", "utf8mb4_is_0900_as_cs", 1, 4},
    {281,"utf8mb4", "utf8mb4_lv_0900_as_cs", 1, 4},
    {282,"utf8mb4", "utf8mb4_ro_0900_as_cs", 1, 4},
    {283,"utf8mb4", "utf8mb4_sl_0900_as_cs", 1, 4},
    {284,"utf8mb4", "utf8mb4_pl_0900_as_cs", 1, 4},
    {285,"utf8mb4", "utf8mb4_et_0900_as_cs", 1, 4},
    {286,"utf8mb4", "utf8mb4_es_0900_as_cs", 1, 4},
    {287,"utf8mb4", "utf8mb4_sv_0900_as_cs", 1, 4},
    {288,"utf8mb4", "utf8mb4_tr_0900_as_cs", 1, 4},
    {289,"utf8mb4", "utf8mb4_cs_0900_as_cs", 1, 4},
    {290,"utf8mb4", "utf8mb4_da_0900_as_cs", 1, 4},
    {291,"utf8mb4", "utf8mb4_lt_0900_as_cs", 1, 4},
    {292,"utf8mb4", "utf8mb4_sk_0900_as_cs", 1, 4},
    {293,"utf8mb4", "utf8mb4_es_trad_0900_as_cs", 1, 4},
    {294,"utf8mb4", "utf8mb4_la_0900_as_cs", 1, 4},
    {296,"utf8mb4", "utf8mb4_eo_0900_as_cs", 1, 4},
    {297,"utf8mb4", "utf8mb4_hu_0900_as_cs", 1, 4},
    {298,"utf8mb4", "utf8mb4_hr_0900_as_cs", 1, 4},
    {300,"utf8mb4", "utf8mb4_vi_0900_as_cs", 1, 4},
    {303,"utf8mb4", "utf8mb4_ja_0900_as_cs", 1, 4},
    {304,"utf8mb4", "utf8mb4_ja_0900_as_cs_ks", 1, 4},
    {305,"utf8mb4", "utf8mb4_0900_as_ci", 1, 4},

	{0, NULL, NULL, 0, 0}
};

#pragma mark -

@implementation SPMySQLResult (Field_Definitions)

/**
 * Return an array of NSDictionaries, each containing information about one of
 * the columns in the result set.
 * MySQL returns non-valid details as empty strings - these are converted to
 * unset entries in the dictionary.
 */
- (NSArray *)fieldDefinitions
{
	NSUInteger i;
	NSMutableArray *theFieldDefinitions = [NSMutableArray array];
	NSMutableDictionary *eachField;
	MYSQL_FIELD mysqlField;

	for (i = 0; i < numberOfFields; i++) {
		eachField = [NSMutableDictionary dictionary];
		mysqlField = fieldDefinitions[i];

		// Record the original column position within the result set
		[eachField setObject:[NSString stringWithFormat:@"%llu", (unsigned long long)i] forKey:@"datacolumnindex"];

		// mysqlField.name might point to an empty string or NULL (theoretically).
		// _stringWithBytes:... will return @"" if either bytes is NULL or length is 0.
		// For now let's interpret (bytes != NULL) as a valid string (possibly empty)
		// and otherwise as 'value not set'.
		
		// Record the column name, or alias if one is being used
		if (mysqlField.name) {
			[eachField setObject:[self _lossyStringWithBytes:mysqlField.name length:mysqlField.name_length wasLossy:NULL] forKey:@"name"];
		}
		
		// Record the original column name if using an alias
		if (mysqlField.org_name) {
			[eachField setObject:[self _stringWithBytes:mysqlField.org_name length:mysqlField.org_name_length] forKey:@"org_name"];
		}
		
		// If the column had an underlying table, record the table name, respecting aliases
		if (mysqlField.table) {
			[eachField setObject:[self _stringWithBytes:mysqlField.table length:mysqlField.table_length] forKey:@"table"];
		}

		// If the column had an underlying table, record the original table name, ignoring aliases
		if (mysqlField.org_table) {
			[eachField setObject:[self _stringWithBytes:mysqlField.org_table length:mysqlField.org_table_length] forKey:@"org_table"];
		}

		// If the column had an underlying database, record the database name
		if (mysqlField.db) {
			[eachField setObject:[self _stringWithBytes:mysqlField.db length:mysqlField.db_length] forKey:@"db"];
		}

		// Width of column (minimum real length in bytes)
		[eachField setObject:[NSNumber numberWithUnsignedLongLong:mysqlField.length] forKey:@"byte_length"];

		// Width of column (as in create)
		// TODO: Discuss the logic of this with Hans-Jörg Bibiko; is this related to max_byte_length?
		[eachField setObject:[NSNumber numberWithUnsignedLongLong:(mysqlField.length/[self _findCharsetMaxByteLengthPerCharForMySQLNumber:mysqlField.charsetnr])] forKey:@"char_length"];

		// Max width (bytes) for selected set.  Note that this will be 0 for streaming results.
		[eachField setObject:[NSNumber numberWithUnsignedLongLong:mysqlField.max_length] forKey:@"max_byte_length"];

		// Bit-flags that describe the field, in entirety and split out
		[eachField setObject:[NSNumber numberWithUnsignedInt:mysqlField.flags] forKey:@"flags"];
		[eachField setObject:[NSNumber numberWithBool:(mysqlField.flags & NOT_NULL_FLAG) ? YES : NO] forKey:@"null"];
		[eachField setObject:[NSNumber numberWithBool:(mysqlField.flags & PRI_KEY_FLAG) ? YES : NO] forKey:@"PRI_KEY_FLAG"];
		[eachField setObject:[NSNumber numberWithBool:(mysqlField.flags & UNIQUE_KEY_FLAG) ? YES : NO] forKey:@"UNIQUE_KEY_FLAG"];
		[eachField setObject:[NSNumber numberWithBool:(mysqlField.flags & MULTIPLE_KEY_FLAG) ? YES : NO] forKey:@"MULTIPLE_KEY_FLAG"];
		[eachField setObject:[NSNumber numberWithBool:(mysqlField.flags & BLOB_FLAG) ? YES : NO] forKey:@"BLOB_FLAG"];
		[eachField setObject:[NSNumber numberWithBool:(mysqlField.flags & UNSIGNED_FLAG) ? YES : NO] forKey:@"UNSIGNED_FLAG"];
		[eachField setObject:[NSNumber numberWithBool:(mysqlField.flags & ZEROFILL_FLAG) ? YES : NO] forKey:@"ZEROFILL_FLAG"];
		[eachField setObject:[NSNumber numberWithBool:(mysqlField.flags & BINARY_FLAG) ? YES : NO] forKey:@"BINARY_FLAG"];
		[eachField setObject:[NSNumber numberWithBool:(mysqlField.flags & ENUM_FLAG) ? YES : NO] forKey:@"ENUM_FLAG"];
		[eachField setObject:[NSNumber numberWithBool:(mysqlField.flags & AUTO_INCREMENT_FLAG) ? YES : NO] forKey:@"AUTO_INCREMENT_FLAG"];
		[eachField setObject:[NSNumber numberWithBool:(mysqlField.flags & SET_FLAG) ? YES : NO] forKey:@"SET_FLAG"];
		[eachField setObject:[NSNumber numberWithBool:(mysqlField.flags & NUM_FLAG) ? YES : NO] forKey:@"NUM_FLAG"];
		[eachField setObject:[NSNumber numberWithBool:(mysqlField.flags & PART_KEY_FLAG) ? YES : NO] forKey:@"PART_KEY_FLAG"];

		// For numeric fields, record the number of decimals
		[eachField setObject:[NSNumber numberWithUnsignedInteger:mysqlField.decimals] forKey:@"decimals"];

		// Character set details
		[eachField setObject:[NSNumber numberWithUnsignedInteger:mysqlField.charsetnr] forKey:@"charsetnr"];
		[eachField setObject:[self _charsetNameForMySQLNumber:mysqlField.charsetnr] forKey:@"charset_name"];
		[eachField setObject:[self _charsetCollationForMySQLNumber:mysqlField.charsetnr] forKey:@"charset_collation"];

		// Table type
		[eachField setObject:[self _mysqlTypeToStringForType:mysqlField.type
		                                       withCharsetNr:mysqlField.charsetnr
		                                           withFlags:mysqlField.flags
		                                          withLength:mysqlField.length]
		              forKey:@"type"];

		// Table type group
		[eachField setObject:[self _mysqlTypeToGroupForType:mysqlField.type
		                                      withCharsetNr:mysqlField.charsetnr
		                                          withFlags:mysqlField.flags]
		              forKey:@"typegrouping"];

		[theFieldDefinitions addObject:eachField];
	}

	return theFieldDefinitions;
}

@end

#pragma mark -
#pragma mark Field defintion internals

@implementation SPMySQLResult (Field_Definitions_Private_API)

/**
 * Return the maximum byte length to store a char by using
 * a specific mysql_charsetnr
 */
- (NSUInteger)_findCharsetMaxByteLengthPerCharForMySQLNumber:(NSUInteger)charsetnr
{
	const SPMySQLResultCharset *c = SPMySQLCharsetMap;

	do {
		if (c->nr == charsetnr) return c->char_maxlen;
		++c;
	} while (c[0].nr != 0);

	return 1;
}

/**
 * Convert a mysql_charsetnr into a charset name as string
 */
- (NSString *)_charsetNameForMySQLNumber:(NSUInteger)charsetnr
{
	const SPMySQLResultCharset *c = SPMySQLCharsetMap;

	do {
		if (c->nr == charsetnr) return [NSString stringWithCString:c->name encoding:NSUTF8StringEncoding];
		++c;
	} while (c[0].nr != 0);

	return @"UNKNOWN";
}

/**
 * Convert a mysql_charsetnr into a collation name as string
 */
- (NSString *)_charsetCollationForMySQLNumber:(NSUInteger)charsetnr
{
	const SPMySQLResultCharset *c = SPMySQLCharsetMap;

	do {
		if (c->nr == charsetnr) return [NSString stringWithCString:c->collation encoding:NSUTF8StringEncoding];
		++c;
	} while (c[0].nr != 0);

	return @"UNKNOWN";
}

/**
 * Convert a mysql_type to a string
 */
- (NSString *)_mysqlTypeToStringForType:(NSUInteger)type withCharsetNr:(NSUInteger)charsetnr withFlags:(NSUInteger)flags withLength:(unsigned long long)length
{
	switch (type) {

		case MYSQL_TYPE_BIT:
			return @"BIT";

		case MYSQL_TYPE_DECIMAL:
		case MYSQL_TYPE_NEWDECIMAL:
			return @"DECIMAL";

		case MYSQL_TYPE_TINY:
			return @"TINYINT";

		case MYSQL_TYPE_SHORT:
			return @"SMALLINT";

		case MYSQL_TYPE_LONG:
			return @"INT";

		case MYSQL_TYPE_FLOAT:
			return @"FLOAT";

		case MYSQL_TYPE_DOUBLE:
			return @"DOUBLE";

		case MYSQL_TYPE_NULL:
			return @"NULL";

		case MYSQL_TYPE_TIMESTAMP:
			return @"TIMESTAMP";

		case MYSQL_TYPE_LONGLONG:
			return @"BIGINT";

		case MYSQL_TYPE_INT24:
			return @"MEDIUMINT";

		case MYSQL_TYPE_DATE:
			return @"DATE";

		case MYSQL_TYPE_TIME:
			return @"TIME";

		case MYSQL_TYPE_DATETIME:
			return @"DATETIME";

		case MYSQL_TYPE_TINY_BLOB:// should no appear over the wire
		case MYSQL_TYPE_MEDIUM_BLOB:// should no appear over the wire
		case MYSQL_TYPE_LONG_BLOB:// should no appear over the wire
		case MYSQL_TYPE_BLOB:
		{
			BOOL isBlob = (charsetnr == MAGIC_BINARY_CHARSET_NR);
			switch (length/[self _findCharsetMaxByteLengthPerCharForMySQLNumber:charsetnr]) {
				case 255: return isBlob? @"TINYBLOB":@"TINYTEXT";
				case 65535: return isBlob? @"BLOB":@"TEXT";
				case 16777215: return isBlob? @"MEDIUMBLOB":@"MEDIUMTEXT";
				case 4294967295: return isBlob? @"LONGBLOB":@"LONGTEXT";
				default:
					switch (length) {
						case 255: return isBlob? @"TINYBLOB":@"TINYTEXT";
						case 65535: return isBlob? @"BLOB":@"TEXT";
						case 16777215: return isBlob? @"MEDIUMBLOB":@"MEDIUMTEXT";
						case 4294967295: return isBlob? @"LONGBLOB":@"LONGTEXT";
						default:
							return @"UNKNOWN";
					}
			}
		}

		case MYSQL_TYPE_VAR_STRING:
			if (flags & ENUM_FLAG) {
				return @"ENUM";
			}
			if (flags & SET_FLAG) {
				return @"SET";
			}
			if (charsetnr == MAGIC_BINARY_CHARSET_NR) {
				return @"VARBINARY";
			}
			return @"VARCHAR";

		case MYSQL_TYPE_STRING:
			if (flags & ENUM_FLAG) {
				return @"ENUM";
			}
			if (flags & SET_FLAG) {
				return @"SET";
			}
			if ((flags & BINARY_FLAG) && charsetnr == MAGIC_BINARY_CHARSET_NR) {
				return @"BINARY";
			}
			return @"CHAR";

		case MYSQL_TYPE_ENUM:
			/* This should never happen */
			return @"ENUM";

		case MYSQL_TYPE_YEAR:
			return @"YEAR";

		case MYSQL_TYPE_SET:
			/* This should never happen */
			return @"SET";

		case MYSQL_TYPE_GEOMETRY:
			return @"GEOMETRY";
			
		case MYSQL_TYPE_JSON:
			return @"JSON";

		default:
			return @"UNKNOWN";
	}
}

/**
 * Merge mysql_types into type groups
 */
- (NSString *)_mysqlTypeToGroupForType:(NSUInteger)type withCharsetNr:(NSUInteger)charsetnr withFlags:(NSUInteger)flags
{
	switch(type){

		case MYSQL_TYPE_BIT:
			return @"bit";

		case MYSQL_TYPE_TINY:
		case MYSQL_TYPE_SHORT:
		case MYSQL_TYPE_LONG:
		case MYSQL_TYPE_LONGLONG:
		case MYSQL_TYPE_INT24:
			return @"integer";

		case MYSQL_TYPE_FLOAT:
		case MYSQL_TYPE_DOUBLE:
		case MYSQL_TYPE_DECIMAL:
		case MYSQL_TYPE_NEWDECIMAL:
			return @"float";

		case MYSQL_TYPE_YEAR:
		case MYSQL_TYPE_DATETIME:
		case MYSQL_TYPE_TIME:
		case MYSQL_TYPE_DATE:
		case MYSQL_TYPE_TIMESTAMP:
			return @"date";

		case MYSQL_TYPE_VAR_STRING:
			if (flags & ENUM_FLAG) {
				return @"enum";
			}
			if (flags & SET_FLAG) {
				return @"enum";
			}
			if (charsetnr == MAGIC_BINARY_CHARSET_NR) {
				return @"binary";
			}
			return @"string";

		case MYSQL_TYPE_STRING:
			if (flags & ENUM_FLAG) {
				return @"enum";
			}
			if (flags & SET_FLAG) {
				return @"enum";
			}
			if ((flags & BINARY_FLAG) && charsetnr == MAGIC_BINARY_CHARSET_NR) {
				return @"binary";
			}
			return @"string";

		case MYSQL_TYPE_TINY_BLOB:   // should no appear over the wire
		case MYSQL_TYPE_MEDIUM_BLOB: // should no appear over the wire
		case MYSQL_TYPE_LONG_BLOB:   // should no appear over the wire
		case MYSQL_TYPE_BLOB:
		{
			if (charsetnr == MAGIC_BINARY_CHARSET_NR) {
				return @"blobdata";
			} else {
				return @"textdata";
			}
		}

		case MYSQL_TYPE_GEOMETRY:
			return @"geometry";

		default:
			return @"blobdata";
	}
}

@end
