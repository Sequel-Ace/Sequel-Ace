# Sequel PAce

**Sequel PAce** is a PostgreSQL-focused fork of [Sequel Ace](https://github.com/Sequel-Ace/Sequel-Ace), which itself is a fork of the beloved [Sequel Pro](https://github.com/sequelpro/sequelpro).

## Motivation

I have always loved the UI and UX of Sequel Pro (and subsequently Sequel Ace). However, my primary database needs have shifted to **PostgreSQL**, and I wanted to bring that same delightful user experience to the Postgres world.

This project, **Sequel PAce**, is the result of that desire. It replaces the MySQL backend with a PostgreSQL driver (libpq) while preserving the native macOS interface that makes Sequel Pro/Ace so great.

## Features

- **PostgreSQL Support**: Native connection to PostgreSQL databases.
- **Classic UI**: The familiar Sequel Pro/Ace interface.
- **Table Management**: View, edit, and manage tables and views.
- **Query Editor**: Execute custom SQL queries.
- **Data Export/Import**: Support for CSV, SQL, and XML exports.

## Credits

- **Original Project**: [Sequel Pro](https://github.com/sequelpro/sequelpro)
- **Parent Project**: [Sequel Ace](https://github.com/Sequel-Ace/Sequel-Ace)
- **Sequel PAce Developer**: Mehmet Karabulut <mehmetik@gmail.com>

## License

Sequel PAce is released under the **GPL License**, same as the projects it is derived from.
This is a free and open-source project.


## Building

To build Sequel PAce, you will need:
- Xcode
- CocoaPods (for dependencies)
- PostgreSQL client libraries (`libpq`)

1. Clone the repository.
2. Run `pod install` (if applicable).
3. Open `sequel-pace.xcodeproj`.
4. Build and Run.

---
*Developed with ❤️ by Mehmet Karabulut.*
