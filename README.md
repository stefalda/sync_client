# Sync_Client

The **Sync_Client** is a Dart/Flutter library that extends the SQLiteWrapper class by creating the `SQLiteWrapperSync` class. This class implements a series of methods to store database changes, which can later be synchronized across devices.

The goal of the project is to provide a simple solution for syncing database data between multiple platforms, including:
   - iOS
   - Android
   - Web
   - Windows
   - macOS
   - Linux

## Features
Synchronization follows the simple rule that the last change in time wins in case of concurrent updates.

The app is **local-first**, and synchronization is handled through a simple server solution that can be **self-hosted**.

The other repositories related to this project are:
   - [sqlite_wrapper](https://github.com/stefalda/sqlite_wrapper) - The Dart/Flutter library used to interact with the SQLite database.
   - [sync_server_ts](https://github.com/stefalda/sync_server_ts) - The sync server (Node.js + Express) used to store the sync data.

## Getting Started
Below are the minimum dependencies that you should add to your *pubspec.yaml* file:
   - `sync_client` - This already includes `sqlite_wrapper`.
   - `path_provider` - Useful for finding the default directories (e.g., documents).
   - `path` - Useful for handling paths.
   - `sqflite_common_ffi_web` - Required if you plan to deploy on the web. Make sure to run the command `dart run sqflite_common_ffi_web:setup --force` to generate the JS and WASM files for SQLite support in the browser.

## Usage

The `SQLiteWrapperSync` must be instantiated by passing a configuration of all the tables that should be synced. This involves providing specific information in a `Map<String, TableInfo>` where:
   - The key of the `Map` is the table name.
   - `keyField` is the primary key of the table.
   - `encryptedFields` is a list of fields that should be encrypted before sending data to the server.
   - `binaryFields` is a list of fields that should be encoded in base64.

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
     binaryFields: ["data"],
   ),
});
```

Next, you can proceed to open the database:

```dart
await db.openDB(dbPath,
       version: 2,
       onCreate: () async => await _createDB(),
       onUpgrade: (fromVersion, toVersion) =>
           _upgrade(fromVersion, toVersion));
```

The main interface for the synchronization functionality is the `SyncRepository` class, which requires:
   - A reference to the `SQLiteWrapperSync` instance.
   - A remote server URL.
   - A realm, which is needed to differentiate various syncing apps.

```dart
syncRepository = SyncRepository(
   serverUrl: "https://sync-test.babisoft.com",
   sqliteWrapperSync: db,
   realm: "SYNC-TEST");
```

You can check if the sync is configured and whether the current client is registered by calling the `getSyncDetails` method of the `SQLiteWrapperSync` class.

```dart
final syncDetails = await db.getSyncDetails();
```

Before performing a sync, if the sync details are empty, you should register the user with the sync server by calling the `register` method of the `SyncRepository` class:

```dart
syncRepository!.register(
   name: nameController.text.trim(),
   email: userController.text.trim(),
   password: passwordController.text.trim(),
   deviceInfo: await _getDeviceInfo(),
   secretKey: secretKeyController.text.trim(), // Passed only if it's a client registration, not a new registration.
   newRegistration: true);
```

If any fields are listed in the `encryptedFields` of the `TableInfo` object, you must ensure that the **ENCRYPTION SECRET KEY** has been set during the `SyncRepository.register` call. Otherwise, the library will display an error.

All CRUD operations should be done through the `SQLiteWrapperSync` class, which internally logs the information required for the sync process.

```dart
await db.insert(tag.toMap(), Tag.table);
```

If the operation is done in bulk or via a SQL command, you can manually log the operation by calling the `logOperation` method, specifying the table name, operation, and row key.

```dart
db.execute(
       "INSERT INTO notes_tags (guid, note_guid, tag_guid) VALUES(?, ?,?);",
       params: [newGuid, note.guid, tagGuid],
       tables: [Note.table]);
// Manually log the operation
db.logOperation("notes_tags", Operation.insert, newGuid);
```

To trigger a database sync, simply call the `sync()` method of the `SyncRepository`:

```dart
if (await syncRepository!.isConfigured()) {
   await syncRepository!.sync();
}
```

If you want to stop syncing, you can call the `unregister` method of the `SyncRepository`. This will reach out to the sync server and delete the client:

```dart
syncRepository!.unregister(
   email: syncDetails!.useremail,
   password: syncDetails!.userpassword,
   clientId: syncDetails!.clientid);
```

Finally, you can reset the database by clearing all the tables and calling the `SyncRepository.resetDB()` method, which will clear the sync configuration tables.

```dart
resetDB() async {
   // Application-specific tables
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

## Additional Information
Make sure to test the library using the example project, which should work on every platform.
