This Dart/Flutter library uses the SQLiteWrapper but extends its main class by creating the SQLiteWrapperSync class that implements a serie of methods to store all the database changes that later can be sync.

The goal of the project is to have a simple solution to sync database data between every platform:
    - iOS
    - Android
    - Web
    - Windows
    - MacOS
    - Linux

## Features
The syncronization is based on the simple rule that last change in time wins on concurrent changes.

The app is **local first** and the syncronization is done through a simple server solution that can be **self hosted**.

The other repositories linked to this project are:
    # [sqlite_wrapper](https://github.com/stefalda/sqlite_wrapper) - the dart/flutter library used to interact with the SQLite database
    # [sync_server_ts](https://github.com/stefalda/sync_server_ts) - the sync server (Node Express) used to store the sync data

## Getting started
These are the minimun dependencies that you should add to your *pubspec.yaml* file.
    # sync_client - it already includes sqlite_wrapper
    # path_provider - useful to find the default directories (es. documents)
    # path - useful to compute paths
    # sqflite_common_ffi_web - a must have if you plan to deploy on the web (be sure to execute the dart run sqflite_common_ffi_web:setup --force command to generate js and wasm files to add sqlite support to the browser)

## Usage

The SQLiteWrapperSync MUST be instantiated by passing the configuration of all the tables that should be sync with a serie of specific information (a Map of <String,TableInfo>) like:
	- table name - the key of the Map
	- keyField - the table key 
	- encryptedFields - a list of field name that should be encrypted before sending the data to the server
	- binaryFields - a list of fields that should be encoded to base64 

```dart
 SQLiteWrapperSync db = SQLiteWrapperSync(tableInfos: {
    "notes": TableInfo(
        keyField: "guid",
        binaryFields: [],
        encryptedFields: ['title', 'description', 'sourceLink']),
    "items": TableInfo(
        keyField: "guid", encryptedFields: ['title', 'link', 'uom']
        ),
    "tags": TableInfo(
        keyField: "guid", binaryFields: [], encryptedFields: ['title']),
    "notes_tags": TableInfo(keyField: "guid", binaryFields: []
        ),
    "attachments": TableInfo(
      keyField: "guid",
      binaryFields: [
        "data"
      ],
    ),
  }); 
```

Then you can proceed to opening the DB:

```dart
 await db.openDB(dbPath,
        version: 2,
        onCreate: () async => await _createDB(),
        onUpgrade: (fromVersion, toVersion) =>
            _upgrade(fromVersion, toVersion));
```

The main interface to the sync functionality is the SyncRepositry class that needs a reference to the sqliteWrapperSync instance, a remote server url, and a realm that is needed to differentiate various syncing apps .

```dart
    syncRepository = SyncRepository(
        serverUrl: "https://sync-test.babisoft.com",
        sqliteWrapperSync: db,
        realm: "SYNC-TEST");
```

You can check if the sync is configured and the current client is registered by calling the syncDetails method of the SQLiteWrapperSync class.

```dart
final syncDetails = await db.getSyncDetails();
```

Before performing a sync, if the sync details are empty, you should register the user to the sync server by calling the register method of the SyncRepository class:

```dart
syncRepository!.register(
          name: nameController.text.trim(),
          email: userController.text.trim(),
          password: passwordController.text.trim(),
          deviceInfo: await _getDeviceInfo(),
          secretKey: secretKeyController.text
              .trim(), // Should be passed only if it's a client registration and NOT a new registration
          newRegistration: true);
```

When some fields are in the encryptedFields list of the tableInfo object you should ensure that the ENCRYPTION SECRET KEY has been set in the syncRepository register call, otherwise the library will display an error.


All the CRUD operations should be done through the SQLiteWrapperSync class that internally log the information needed by the sync process.

```dart
 await db.insert(tag.toMap(), Tag.table);
```

If the operation is done massively or by executing a SQL command yoy can manually log the information by calling the logOperation method specyfing the tableName, the operation and the row key.

```dart
 db.execute(
        "INSERT INTO notes_tags (guid, note_guid, tag_guid) VALUES(?, ?,?);",
        params: [newGuid, note.guid, tagGuid],
        tables: [Note.table]);
    // Manually log the operation
    db.logOperation("notes_tags", Operation.insert, newGuid);
```

When you want the db to sync you can simply call the method sync() of SyncRepository:

```dart
if (await syncRepository!.isConfigured()) {
        await syncRepository!.sync();
}
```

If you want to stop syncing you can perform a call to the unregister method of the syncRepository, that reach out to the sync server to delete the client:

```dart 
    syncRepository!.unregister(
          email: syncDetails!.useremail,
          password: syncDetails!.userpassword,
          clientId: syncDetails!.clientid);
```

Then you can call a reset function, that clears all the tables, and then call the syncRepository's resetDB() method that clear the sync configuration tables. 

```dart
  resetDB() async {
  	// Specific application tables
    const String sql = """
        DELETE FROM notes_tags;
        DELETE FROM tags;
        DELETE FROM attachments;
        DELETE FROM items;
        DELETE FROM notes;
    """;
    await db.execute(sql);
    await syncRepository!.resetDB();
  }
```  

## Additional information
Be sure to test the library using the Example project that should work on every platform.
