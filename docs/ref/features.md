{% capture menu %}{% include ../_includes/menu.md %}{% endcapture %}
{{ menu | markdownify }}

### Core Features

In the articles below we take you through the important screens that make up Sequel Pro and allow you to manage your databases and tables.

#### Frequently Asked Questions

**Is there a shortcut for running a Query?**

Yes.
If you press `⌘ + R` it will run all the commands in the Query view.
If you press `⌘ + ⌥ + R` it will run either the currently selected text as a query OR the entire query in which you are currently positioned.

**How do I create an enum field in a table?**

To create an _enum_ field follow the same procedure as you would for any other field, choose _enum_ in the _Type_column of the Table Structure form, and then in the _Length_ column enter the enum values as comma separated quoted strings. If you wish to use a default value, you should enter it without quotes in the _Default_ column.

**Where does Sequel Pro store the connections?**

The connections strings are stored in the following preference file:

~/Library/Preferences/com.sequelpro.SequelPro.plist

The passwords are stored in the Mac OSX Keychain, which is stored here:

~/Library/Keychains/login.keychain

Find more info about the Keychain here: [http://nevali.net/post/122592107/managing-the-mac-os-x-keychain](http://nevali.net/post/122592107/managing-the-mac-os-x-keychain "http://nevali.net/post/122592107/managing-the-mac-os-x-keychain").

The ~/Library folder is invisible in Lion, to open it choose "Go To Folder…" (`⌘ + ⇧ + G`) and type "~/Library/Preferences/" to open the preference folder.

<!--
## Articles

-   [Structure View](https://sequelpro.com/docs/ref/docs/ref/core-features/structure)
-   [Content View](https://sequelpro.com/docs/ref/docs/ref/core-features/content)
-   [Relations View](https://sequelpro.com/docs/ref/docs/ref/core-features/relations)
-   [Table Info View](https://sequelpro.com/docs/ref/docs/ref/core-features/table-info)
-   [Query View](https://sequelpro.com/docs/ref/docs/ref/core-features/query)
-   [Navigator](https://sequelpro.com/docs/ref/docs/ref/core-features/navigator)
-   [Working with Query Favorites](https://sequelpro.com/docs/ref/docs/ref/core-features/query-favourites)
-   [URL Scheme](https://sequelpro.com/docs/ref/docs/url-scheme)
-->
