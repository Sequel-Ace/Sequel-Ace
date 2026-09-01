//
//  SPKeychain.h
//  sequel-pro
//
//  Created by Lorenz Textor (lorenz@textor.ch) on December 25, 2002.
//  Copyright (c) 2002-2003 Lorenz Textor. All rights reserved.
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

NS_ASSUME_NONNULL_BEGIN

/**
 * Legacy SecKeychain*-backed keychain store; conforms to SAKeychainProviding
 * (declared in the .m). Being migrated to SecItem* — see
 * docs/development/keychain-secitem-migration-plan.md.
 *
 * The nullability below deliberately mirrors SAKeychainProviding: every
 * argument tolerates nil (rejected internally), every lookup can return nil.
 */
@interface SPKeychain : NSObject

/// Returns nil when keychain access is disabled via
/// LIBMYSQL_ENABLE_CLEARTEXT_PLUGIN (issue #2437). Swift callers should use
/// SAKeychainAccess.make(), which substitutes the SAKeychainDisabled null
/// object instead of handing out nil.
- (nullable instancetype)init;

- (void)addPassword:(nullable NSString *)password forName:(nullable NSString *)name account:(nullable NSString *)account;
- (void)addPassword:(nullable NSString *)password forName:(nullable NSString *)name account:(nullable NSString *)account withLabel:(nullable NSString *)label;
- (nullable NSString *)getPasswordForName:(nullable NSString *)name account:(nullable NSString *)account;
- (void)deletePasswordForName:(nullable NSString *)name account:(nullable NSString *)account;
- (BOOL)passwordExistsForName:(nullable NSString *)name account:(nullable NSString *)account;
- (void)updateItemWithName:(nullable NSString *)name account:(nullable NSString *)account toName:(nullable NSString *)newName account:(nullable NSString *)newAccount password:(nullable NSString *)password;

- (nullable NSString *)nameForFavoriteName:(nullable NSString *)favoriteName id:(nullable NSString *)favoriteId;
- (nullable NSString *)accountForUser:(nullable NSString *)user host:(nullable NSString *)host database:(nullable NSString *)database;
- (nullable NSString *)nameForSSHForFavoriteName:(nullable NSString *)favoriteName id:(nullable NSString *)favoriteId;
- (nullable NSString *)accountForSSHUser:(nullable NSString *)SSHUser sshHost:(nullable NSString *)SSHHost;

@end

NS_ASSUME_NONNULL_END
