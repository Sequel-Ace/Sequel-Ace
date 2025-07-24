#  Developing Sequel Ace

## Building Locally

To run Sequel Ace locally from XCode, please:
- download `.zip` archive of this repo/clone locally
- open `sequel-ace.xcodeproj` 
- for the `sequel-ace` and `SPMySQLFramework`  (located in `Source/Frameworks/SPMySQLFramework`) projects, under `Signing & Capibilities`
    - change the Bundle Identifier to be unique to you (e.g. add `.YOUR_USER_NAME`)
    - select a Team that you can create signing certificates for
- open the `sequel-ace` project and, under `Signing & Capabilities` change the Team and Bundle Identifier for the `Sequel Ace` and `SequelAceTunnelAssistant` targets
- open the `Source/Frameworks/SPMySQLFramework` project 
- run `Sequel Ace Debug` schema

If you encounter any issues, let us know by [creating a new issue](https://github.com/Sequel-Ace/Sequel-Ace/issues/new/choose).

## Extending Objective-C from Swift

Don't forget to add the header for the Objective-C class you wish to extend to `Sequel-Ace-Bridging-Header` as most of the project is not exposed to the Swift compiler.
