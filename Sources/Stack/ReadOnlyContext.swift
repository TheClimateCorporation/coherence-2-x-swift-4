///
///  ReadOnlyContext.swift
///
///  Copyright 2017 Tony Stone
///
///  Licensed under the Apache License, Version 2.0 (the "License");
///  you may not use this file except in compliance with the License.
///  You may obtain a copy of the License at
///
///  http://www.apache.org/licenses/LICENSE-2.0
///
///  Unless required by applicable law or agreed to in writing, software
///  distributed under the License is distributed on an "AS IS" BASIS,
///  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
///  See the License for the specific language governing permissions and
///  limitations under the License.
///
///  Created by Tony Stone on 2/5/17.
///
import CoreData

public enum ReadOnlyContextErrors: Error {
    case readOnlyContext(String)
}

internal class ReadOnlyContext: NSManagedObjectContext {

    public override func save() throws {
        try self.save(override: false)
    }

    internal func save(override: Bool) throws {
        if override {
            try super.save()
        } else {
            throw ReadOnlyContextErrors.readOnlyContext("Cannot save, context is read only.")
        }
    }
}
