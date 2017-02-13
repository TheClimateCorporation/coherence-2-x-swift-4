///
///  WriteAheadLog.swift
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
///  Created by Tony Stone on 12/9/15.
///
import Foundation
import CoreData
import TraceLog

internal let MetaLogEntryName    = "MetaLogEntry"
internal let persistentStoreType = NSSQLiteStoreType

internal class WriteAheadLog {

    internal enum Errors: Error {
        case failedToCreateLogEntry(String)
        case failedToObtainPermanentIDs(String)
        case transactionWriteFailed(String)
        case nilEntityName(String)
    }

    internal typealias TransactionContextType = NSManagedObjectContext
    internal typealias MetadataContextType    = NSManagedObjectContext

    internal typealias CoreDataStackType = GenericCoreDataStack<NSPersistentStoreCoordinator, MetadataContextType>
    
    fileprivate let coreDataStack: CoreDataStackType
    
    var nextSequenceNumber = 0

    init(coreDataStack: CoreDataStackType) throws {
        
        logInfo {
            "Initializing instance..."
        }
        
        self.coreDataStack = coreDataStack
        
        nextSequenceNumber = try self.lastLogEntrySequenceNumber() + 1
        
        logInfo {
            "Starting Transaction ID: \(self.nextSequenceNumber)"
        }
        
        logInfo {
            "Instance initialized."
        }
    }
    
    fileprivate func lastLogEntrySequenceNumber () throws -> Int {
        
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        let metadataContext = coreDataStack.newBackgroundContext()
        
        //
        // We need to find the last log entry and get it's
        // sequenceNumber value to calculate the next number
        // in the database.
        //
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: MetaLogEntryName)
        
        fetchRequest.fetchLimit = 1
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "sequenceNumber", ascending:false)]
        
        if let lastLogRecord = try (metadataContext.fetch(fetchRequest).last) as? MetaLogEntry {
            
            return Int(lastLogRecord.sequenceNumber)
        }
        return 0
    }
    
    internal func nextSequenceNumberBlock(_ size: Int) -> ClosedRange<Int> {
        
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        let sequenceNumberBlockStart = nextSequenceNumber
        let sequenceNumberBlockEnd   = nextSequenceNumber + size - 1

        nextSequenceNumber = sequenceNumberBlockEnd + 1

        return sequenceNumberBlockStart...sequenceNumberBlockEnd
    }

    internal func logTransactionForContextChanges(_ transactionContext: TransactionContextType) throws -> TransactionID {

        var transactionID: TransactionID = "temp"

        try transactionContext.performAndWait {
            ///
            /// NOTE: This method must be reentrent.  Be sure to use only stack variables asside from
            ///       the protected access method nextSequenceNumberBlock
            ///
            let inserted = transactionContext.insertedObjects
            let updated  = transactionContext.updatedObjects
            let deleted  = transactionContext.deletedObjects

            ///
            /// Get a block of sequence numbers to use for the records
            /// that need recording.
            ///
            /// Sequence number = begin + end + inserted + updated + deleted
            ///
            let sequenceNumberBlock = self.nextSequenceNumberBlock(2 + inserted.count + updated.count + deleted.count)
            var sequenceNumber = sequenceNumberBlock.lowerBound

            let metadataContext = self.coreDataStack.newBackgroundContext()

            transactionID = try self.logBeginTransactionEntry(metadataContext, sequenceNumber: &sequenceNumber)

            try self.logInsertEntries(inserted, transactionID: transactionID, metadataContext: metadataContext, sequenceNumber: &sequenceNumber)
            try self.logUpdateEntries(updated,  transactionID: transactionID, metadataContext: metadataContext, sequenceNumber: &sequenceNumber)
            try self.logDeleteEntries(deleted,  transactionID: transactionID, metadataContext: metadataContext, sequenceNumber: &sequenceNumber)

            try self.logEndTransactionEntry(transactionID, metadataContext: metadataContext, sequenceNumber:  &sequenceNumber)

            try metadataContext.performAndWait {

                if metadataContext.hasChanges {
                    try metadataContext.save()
                }
            }
        }
        return transactionID
    }

    internal func removeTransaction(_ transactionID: TransactionID) {
    }

    internal func transactionLogEntriesForTransaction(_ transactionID: TransactionID) -> [MetaLogEntry] {
        return []
    }

    internal func transactionLogRecordsForEntity(_ entityDescription: NSEntityDescription) throws -> [MetaLogEntry] {

        let context = self.coreDataStack.newBackgroundContext()
        let fetchRequest = NSFetchRequest<MetaLogEntry>()

        fetchRequest.entity = NSEntityDescription.entity(forEntityName: MetaLogEntryName, in: context)
        fetchRequest.predicate = NSPredicate(format: "updateEntityName == %@", entityDescription.name!)

        var results: [MetaLogEntry] = []

        try context.performAndWait {
            results = try context.fetch(fetchRequest)
        }
        return results
    }

    fileprivate func logBeginTransactionEntry(_ metadataContext: MetadataContextType, sequenceNumber: inout Int) throws -> TransactionID {

        var transactionID = "tmp"
        let sequence      = Int32(sequenceNumber)

        try metadataContext.performAndWait {

            guard let metaLogEntry = NSEntityDescription.insertNewObject(forEntityName: MetaLogEntryName, into: metadataContext) as? MetaLogEntry else {
                throw Errors.failedToCreateLogEntry("Failed to create login entry for transaction begin marker.")
            }

            do {
                try metadataContext.obtainPermanentIDs(for: [metaLogEntry])

            } catch let error as NSError {
                throw  Errors.failedToObtainPermanentIDs("Failed to obtain perminent id for transaction log record: \(error.localizedDescription)")
            }

            ///
            /// We use the URI representation of the object id as the transactionID
            ///
            transactionID = metaLogEntry.objectID.uriRepresentation().absoluteString

            metaLogEntry.transactionID = transactionID
            metaLogEntry.sequenceNumber = sequence
            metaLogEntry.previousSequenceNumber = sequence - 1
            metaLogEntry.type = MetaLogEntryType.beginMarker
            metaLogEntry.timestamp = Date().timeIntervalSinceNow

            logTrace(4) {
                var message: String = ""

                ///
                /// Note: TraceLog blocks are exscaping closures so
                /// if we are to bring an NSManagedObject in it, you
                /// must wrap it in a context.perform which is
                /// eecuted when the closure is evaluated
                ///
                metadataContext.performAndWait { () -> Void in
                    message = "Log entry created: \(metaLogEntry)"
                }
                return message
            }
        }
        ///
        /// Increment the sequence for this record
        ///
        sequenceNumber = sequenceNumber + 1

        return transactionID
    }

    fileprivate func logEndTransactionEntry(_ transactionID: TransactionID, metadataContext: MetadataContextType, sequenceNumber: inout Int) throws {

        let sequence = Int32(sequenceNumber)

        try metadataContext.performAndWait {

            guard let metaLogEntry = NSEntityDescription.insertNewObject(forEntityName: MetaLogEntryName, into: metadataContext) as? MetaLogEntry else {
                throw Errors.failedToCreateLogEntry("Failed to create login entry for transaction end marker.")
            }

            metaLogEntry.transactionID = transactionID
            metaLogEntry.sequenceNumber = sequence
            metaLogEntry.previousSequenceNumber = sequence
            metaLogEntry.type = MetaLogEntryType.endMarker
            metaLogEntry.timestamp = Date().timeIntervalSinceNow

            logTrace(4) {
                var message: String = ""

                ///
                /// Note: TraceLog blocks are exscaping closures so
                /// if we are to bring an NSManagedObject in it, you
                /// must wrap it in a context.perform which is
                /// eecuted when the closure is evaluated
                ///
                metadataContext.performAndWait { () -> Void in
                    message = "Log entry created: \(metaLogEntry)"
                }
                return message
            }
        }
        ///
        /// Increment the sequence for this record
        ///
        sequenceNumber += 1
    }

    fileprivate func logInsertEntries(_ insertedRecords: Set<NSManagedObject>, transactionID: TransactionID, metadataContext: MetadataContextType, sequenceNumber: inout Int) throws {
        
        for object in insertedRecords {

            ///
            /// Only log entities when enabled for the entity type.
            ///
            if object.entity.logTransactions {
                //
                // Get the object attribute change data
                //
                let data = MetaLogEntry.InsertData()

                let attributes = [String](object.entity.attributesByName.keys)

                data.attributesAndValues = object.dictionaryWithValues(forKeys: attributes) as [String : AnyObject]

                try self.insertTransactionLogEntry(entity: object.entity,
                                        objectID: object.objectID.uriRepresentation().absoluteString,
                                        updateData: data,
                                        type: .insert,
                                        transactionID: transactionID,
                                        metadataContext: metadataContext,
                                        sequenceNumber: sequenceNumber)
                ///
                /// Increment the sequence for this record
                ///
                sequenceNumber += 1
            }
        }
    }

    fileprivate func logUpdateEntries(_ updatedRecords: Set<NSManagedObject>, transactionID: TransactionID, metadataContext: MetadataContextType, sequenceNumber: inout Int) throws {
        
        for object in updatedRecords {

            ///
            /// Only log entities when enabled for the entity type.
            ///
            if object.entity.logTransactions {
                //
                // Get the object attribute change data
                //
                let data = MetaLogEntry.UpdateData()

                let attributes = [String](object.entity.attributesByName.keys)

                data.attributesAndValues = object.dictionaryWithValues(forKeys: attributes) as [String : AnyObject]
                data.updatedAttributes   = [String](object.changedValues().keys)

                try self.insertTransactionLogEntry(entity: object.entity,
                                                   objectID: object.objectID.uriRepresentation().absoluteString,
                                                   updateData: data,
                                                   type: .update,
                                                   transactionID: transactionID,
                                                   metadataContext: metadataContext,
                                                   sequenceNumber: sequenceNumber)
                ///
                /// Increment the sequence for this record
                ///
                sequenceNumber += 1
            }
        }
    }

    fileprivate func logDeleteEntries(_ deletedRecords: Set<NSManagedObject>, transactionID: TransactionID, metadataContext: MetadataContextType, sequenceNumber: inout Int) throws {
        
        for object in deletedRecords {

            ///
            /// Only log entities when enabled for the entity type.
            ///
            if object.entity.logTransactions {

                try self.insertTransactionLogEntry(entity: object.entity,
                                                   objectID: object.objectID.uriRepresentation().absoluteString,
                                                   updateData: nil,
                                                   type: .update,
                                                   transactionID: transactionID,
                                                   metadataContext: metadataContext,
                                                   sequenceNumber: sequenceNumber)
                //
                // Increment the sequence for this record
                //
                sequenceNumber += 1
            }
        }
    }

    fileprivate func insertTransactionLogEntry(entity: NSEntityDescription, objectID: String, updateData: MetaLogEntry.ChangeData?, type: MetaLogEntryType, transactionID: TransactionID, metadataContext: MetadataContextType, sequenceNumber: Int) throws {

        let sequence = Int32(sequenceNumber)

        try metadataContext.performAndWait {

            guard let entityName = entity.name else {
                throw Errors.nilEntityName("Nil entity name for logged entity.")
            }

            guard let metaLogEntry = NSEntityDescription.insertNewObject(forEntityName: MetaLogEntryName, into: metadataContext) as? MetaLogEntry else {
                throw Errors.failedToCreateLogEntry("Failed to create login entry for '\(type)' record.")
            }

            metaLogEntry.transactionID = transactionID
            metaLogEntry.sequenceNumber = sequence
            metaLogEntry.previousSequenceNumber = sequence - 1
            metaLogEntry.type = type
            metaLogEntry.timestamp = Date().timeIntervalSinceNow

            //
            // Update the object identification data
            //
            metaLogEntry.updateObjectID = objectID
            metaLogEntry.updateEntityName = entityName

            logTrace(4) {
                var message: String = ""

                ///
                /// Note: TraceLog blocks are exscaping closures so
                /// if we are to bring an NSManagedObject in it, you
                /// must wrap it in a context.perform which is 
                /// eecuted when the closure is evaluated
                ///
                metadataContext.performAndWait { () -> Void in
                    message = "Log entry created: \(metaLogEntry)"
                }
                return message
            }
        }
    }
}