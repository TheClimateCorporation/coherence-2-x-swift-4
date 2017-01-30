///
///  MetaLogEntry+CoreDataProperties.swift
///
///  Copyright 2015 Tony Stone
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
///  Created by Tony Stone on 12/10/15.
///
import Foundation
import CoreData

internal extension MetaLogEntry {

    @NSManaged var sequenceNumber: Int32
    @NSManaged var previousSequenceNumber: Int32
    @NSManaged var transactionID: TransactionID?
    @NSManaged var timestamp: TimeInterval
    @NSManaged var type: MetaLogEntryType
    @NSManaged var updateEntityName: String?
    @NSManaged var updateObjectID: String?
    @NSManaged var updateUniqueID: String?
    @NSManaged var updateData: ChangeData?

}
