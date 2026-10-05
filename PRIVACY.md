# Privacy policy

Effective October 5, 2026.

Apple Home Observer reads the Apple Home configuration you authorize. It stores Home names, room and accessory identifiers, scene and supported automation definitions, reported blind positions and diagnostic events locally on your device. Backups use authenticated encryption; the recovery key is held in the device Keychain. An exported key must be stored separately and securely.

The app has no developer-operated account service, advertising, tracking or analytics SDK. The developer does not receive your Home data, backups or diagnostic logs through the app.

You may explicitly select a monitoring export folder. That export contains private Home metadata and diagnostic events. Any monitoring, synchronization or backup service you configure outside the app may receive those files according to your configuration and that service's policies. Encrypted backup archives can also be transferred to a destination you control; never include the recovery key in that destination.

Removing the app's folder access stops future exports, but does not delete files already exported. To remove stored data, delete the app's local archives and diagnostic files, exported copies and separately stored recovery keys. Deleting a key may make remaining backups permanently unrecoverable. Removing local app data does not remove accessories or change your Apple Home.

HomeKit access and user-selected folder access are optional permissions that you control. The app stores its own preferences and uses file metadata to protect and manage its local and explicitly selected files. It does not use those APIs to fingerprint users.

For privacy questions, use [the project support page](https://github.com/eslutz/Apple-Home-Observer/issues). Do not post recovery keys, private Home exports or household logs in public issues.
