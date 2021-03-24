//
//  Reconciller.swift
//  
//
//  Created by Ben Gottlieb on 3/23/21.
//

import Foundation
import CloudKit
import CoreData
import Suite

public class Reconciller {
    let cloudKitRecordType: String
    let cloudKitFieldName: String

    let managedObjectRecordType: String
    let managedObjectFieldName: String

    let context: NSManagedObjectContext
    let database: CKDatabase

    var cloudKitRecords: [CKRecord] = []
    var managedObjects: [NSManagedObject] = []
    var error: Error?

    enum Phase: String { case cloud, compare }
    public init(cloudType: String, cloudIDField: String, entityName name: String, localIDField: String, context moc: NSManagedObjectContext, database db: CKDatabase) {
        cloudKitRecordType = cloudType
        managedObjectRecordType = name
        context = moc
        database = db
        cloudKitFieldName = cloudIDField
        managedObjectFieldName = localIDField
    }
    
    public func start() {
        managedObjects = context.fetchAll(named: managedObjectRecordType)
        fetchRemoteRecords()
    }
    
    func fetchRemoteRecords(continuing cursor: CKQueryOperation.Cursor? = nil) {
        let query = CKQuery(recordType: cloudKitRecordType, predicate: NSPredicate(value: true))
        let op = cursor == nil ? CKQueryOperation(query: query) : CKQueryOperation(query: query)
        
        op.recordFetchedBlock = { record in
            self.cloudKitRecords.append(record)
        }
        op.queryCompletionBlock = { cursor, error in
            if let err = error {
                self.finish(phase: .cloud, with: err)
            } else if let cursor = cursor {
                self.fetchRemoteRecords(continuing: cursor)
            } else {
                self.finish(phase: .cloud)
            }
        }
        
        database.add(op)
    }
    
    func findMismatches() {
        
    }
    
    
    
    func finish(phase: Phase, with error: Error? = nil) {
        self.error = error
        if let err = error {
            print("Found an error in phase \(phase.rawValue): \(err)")
        }
        switch phase {
        case .cloud:
            print("Fetched \(cloudKitRecords.count) cloud records, \(managedObjects.count) local")
            findMismatches()
            
        case .compare:
            print("Done")
        }
    }
}
