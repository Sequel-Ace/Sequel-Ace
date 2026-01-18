#  Developing Sequel PAce

## Building Locally

To run Sequel PAce locally from XCode, please:
- download `.zip` archive of this repo/clone locally
- open `sequel-pace.xcodeproj`
- for the `sequel-pace` project, under `Signing & Capabilities`
    - change the Bundle Identifier to be unique to you (e.g. add `.YOUR_USER_NAME`)
    - select a Team that you can create signing certificates for
- change the Team and Bundle Identifier for the `Sequel PAce` and `SequelPAceTunnelAssistant` targets
- run `Sequel PAce Debug` schema

Note: Sequel PAce uses the built-in SPPostgres framework for PostgreSQL connections (located in `Source/PostgresFramework/`).

If you encounter any issues, let us know by [creating a new issue](https://github.com/Sequel-PAce/Sequel-PAce/issues/new/choose).

## Extending Objective-C from Swift

Don't forget to add the header for the Objective-C class you wish to extend to `Sequel-Ace-Bridging-Header` as most of the project is not exposed to the Swift compiler.
