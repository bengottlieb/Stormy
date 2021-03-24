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

public typealias RecordsAreEqual = (CKRecord, NSManagedObject) -> Bool

public class Reconciller {
    let cloudKitRecordType: String
    let managedObjectRecordType: String

    let context: NSManagedObjectContext
    let database: CKDatabase

    var cloudKitRecords: [CKRecord] = []
    var managedObjects: [NSManagedObject] = []
    var error: Error?
    var unpairedCloudKitRecords: [CKRecord] = []
    var unpairedManagedObjects: [NSManagedObject] = []
    
	var compareRecords: RecordsAreEqual
    

    enum Phase: String { case cloud, compare }
	public init(cloudType: String, entityName name: String, context moc: NSManagedObjectContext, database db: CKDatabase, comparison: @escaping RecordsAreEqual) {
        cloudKitRecordType = cloudType
        managedObjectRecordType = name
        context = moc
        database = db
		compareRecords = comparison
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
        for record in cloudKitRecords {
            if managedObject(matching: record) != nil { continue }
            unpairedCloudKitRecords.append(record)
        }

        for object in managedObjects {
            if cloudRecord(matching: object) != nil { continue }
            unpairedManagedObjects.append(object)
        }
        
        print("Found \(unpairedCloudKitRecords.count) unpaired \(cloudKitRecordType) and \(unpairedManagedObjects.count) unpaired \(managedObjectRecordType)")
    }
    
	func cloudRecord(matching object: NSManagedObject) -> CKRecord? {
        cloudKitRecords.first { record in
			compareRecords(record, object)
        }
    }
     
	func managedObject(matching record: CKRecord) -> NSManagedObject? {
        managedObjects.first { object in
			compareRecords(record, object)
		}
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
