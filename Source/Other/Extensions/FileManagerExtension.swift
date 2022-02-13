//
//  FileManagerExtension.swift
//  Sequel Ace
//
//  Created by James on 28/2/2021.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import Foundation

extension FileManager {

    var userHomeDirectoryPath : String {
        guard
            let pw = getpwuid(getuid()),
            let home = pw.pointee.pw_dir
        else {
            return ""
        }
        return FileManager.default.string(withFileSystemRepresentation: home, length: Int(strlen(home)))
    }
}
