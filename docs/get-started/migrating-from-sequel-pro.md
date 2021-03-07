-   [Getting Connected](../get-started/)
-   [Making Queries](../queries.html)
-   [Keyboard Shortcuts](../shortcuts.html)
-   [Reference](../ref/)
-   [Bundles](../bundles/)
-   [Contribute](../contribute/)

<hr>

### Migrating to Sequel Ace from Sequel Pro

#### Migrating Connection Favorites
_The following is based on [this medium article](https://medium.com/@harrybailey/migration-from-sequel-pro-to-sequel-ace-c6a579399c90):_
1. Install Sequel Ace

2. Quit both Sequel Pro and Sequel Ace

3. NB: This process will replace (you will lose) any connections already in Sequel Ace, so you may want to make a note of those details first

4. Copy
~/Library/Preferences/com.sequelpro.SequelPro.plist
to
~/Library/Containers/com.sequel-ace.sequel-ace/Data/Library/Preferences/com.sequel-ace.sequel-ace.plist

5. Copy
~/Library/Application\ Support/Sequel\ Pro/Data/Favorites.plist
to
~/Library/Containers/com.sequel-ace.sequel-ace/Data/Library/Application\ Support/Sequel\ Ace/Data/Favorites.plist

6. Open up the Keychain Access app (/System/Applications/Utilities/Keychain\ Access.app)

7. Search for 'sequel pro' — this should list all your Sequel Pro connections / favorites. You may also note some SSHTunnel items if you use those in Sequel Pro

*Notes:*
- Due to the sandbox, all SSH keys must be re-navigated to and selected in Sequel Ace after migrating connections.
- Additionally, passwords are not migrated as well as they are stored in the Keychain. See the next section for a method to migrate passwords if you have many passwords and do not want to manually re-enter all of them in Sequel Ace.


#### Migrating Passwords

Passwords are _not_ automatically migrated when exporting and importing connections between Sequel Pro and Sequel Ace. If you'd like to migrate passwords, you may use the following bash script provided by @bartdecorte. Please use the script with caution and read the following warnings before attempting.

This small shell script that copies all Sequel Pro passwords from Keychain back to Keychain under Sequel Ace keys. It's not perfect, as you need to authorize each password seperately, and once more when Sequel Ace reads it for the first time, but it still beats looking them all up manually, especially if you have A LOT of connections. You can copy your password to your clipboard once and paste it in every authorization dialog that pops up. You can also temporarily clear the keychain password (press cmd while clicking OK to force an empty password).

It assumes you store your Sequel Pro passwords in the "default" keychain.
Make a backup of your keychain just to be sure. Usually this is located at ~/Library/Keychains/login.keychain-db

```
#!/bin/bash

results=$(security dump-keychain -r | grep "Sequel Pro" | sed -E -e 's/^.*"([^"]+)"$/\1/' | sort | uniq)
IFS=$'\n' read -r -d '' -a items < <(printf '%s\0' "$results")

for key in "${items[@]}"
    do
        newkey=$(echo "$key" | sed -E -e 's/Sequel Pro/Sequel Ace/')
        echo "Migrating: $key --> $newkey"
        account=$(sudo security find-generic-password -l "$key" | grep "acct\"<blob>" | sed -E -e 's/^.*"acct"<blob>="(.+)"$/\1/')
        pwd=$(sudo security find-generic-password -l "$key" -w)
        security add-generic-password -a "$account" -s "$newkey" -w "$pwd" -T "/Applications/Sequel Ace.app" -U
        echo "Done: $key --> $newkey"
done
```
