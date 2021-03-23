# Stormy
A wrapper for iCloud

# Quick Start

- for each core data entity in your model that syncs, add:
    cloudKitRecordID_ (String)
    cloudKitSyncState_ (Integer 32)
    
- create a cloud kit container identifier, `cloudKitIdentifier = icloud.com.yourcompany.appName`
- select a zone name to contain your records
- set up your SyncedContainer:

```
let fileName = "name_for_your_database"
let appGroupIdentifier = "optional_app_group_name"
SyncedContainer.setup(name: fileName, managedObjectModel: nil, bundle: Bundle.main, appGroupIdentifier: appGroupIdentifier)
```

- register your entities:
```
let zoneName = "YOUR_ZONE_NAME"
SyncedContainer.instance.register(entity: ENTITY_CLASS_NAME.self, zoneName: zoneName, database: .private)
```

- Setup Stormy
```
Stormy.instance.setup(identifier: cloudKitIdentifier, zones: [YOUR_ZONE_NAME], andContainer: true) { success in }
```

- Optionally, listen for new records:
```
NotificationCenter.default.publisher(for: Stormy.Notifications.recordsModifiedOrCreatedViaPush)
    .eraseToAnyPublisher()
    .sink { records in
        print("Found new records: \(records)")
    }
```
