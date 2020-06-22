-   [Getting Connected](get-started/)
-   [Making Queries](queries.html)
-   [Keyboard Shortcuts](shortcuts.html)
-   [Reference](reference/)
-   [Bundles](bundles/)

<hr>

### Query Favorites

Query Favorites are useful for frequently used SQL statements, text chunks, etc. which can be saved globally — accessible from each connection window — or document-based SPF file if the query favorite is connection specific. A query favorite can be static but also dynamic which means it will be evaluated on run-time. Furthermore each query favorite can be inserted by using an user-defined tab trigger — an alphanumeric string which can be typed in the Custom Query Editor and it will be replaced by the corresponding query favorite after pressing the tab `⇥` key.

#### Query Favorites Editor

The Query Favorites Editor allows to:

-   add new query favorites ⌥⌘A
-   duplicate query favorites ⌘D
-   edit query favorites
-   remove selected query favorites ⌫
-   rearrange the order of appearance in the popup menu by dragging it
-   change the storage location (global or document) by dragging it
-   export selected query favorites in a SPF file
-   import saved favorites from a SPF file
-   save the current query as SQL file

#### A concrete step-by-step tutorial

##### Create

A frequently used SQL statement is SELECT FROM WHERE . To create this query favorite you have two options:

1.  via Custom Query Editor

    -   type SELECT FROM WHERE in the Custom Query Editor
    -   select it
    -   holding ⌥ key and click at the **Query Favorites** button, choose **Save Selection to Favorites**
    -   named it (_e.g. Select_)

2.  via Query Favorites Editor

    -   open the Query Favorites Editor by choosing **Edit Favorites…**
    -   click at the + button (⌥⌘A)
    -   name the new favorite (_e.g. Select_)
    -   type in the query field: SELECT FROM WHERE
    -   save it


----------

##### Insert

###### Via Mouse

After creating it you can click at the **Query Favorites** button and choose **Select**. The query favorite SELECT FROM WHERE will be inserted into the Custom Query Editor — according to the setting of **Favorite Replaces Editor Content** (settable in Custom Query Editor's gear menu).

> **Tip:** If _Favorite Replaces Editor Content_ is checked and you want to insert the chosen query favorite into the Custom Query Editor at the current cursor position instead you can hold any of these keys `⇧ ⌥ ⌘` while choosing the desired favorite via mouse to toggle _Favorite Replaces Editor Content_ setting temporarily (or visa versa).

###### Via Keyboard (Tab Trigger)

If you want to insert a query favorite without using the mouse you have the chance to assign a tab trigger to it. To do so:

-   open the Query Favorites Editor
-   select the desired query on the left list
-   type e.g. **sel** into the **Tab Trigger** field
-   save

After doing this type in the Custom Query Editor sel and press the tab ⇥ key. sel will be replaced by the query favorite SELECT FROM WHERE. A valid tab trigger can contain any alphanumeric character but no space or other punctuation signs for instance.

----------

#### Insertion Point Navigation (Tab Snippets)

After insertion of the query favorite SELECT FROM WHERE you have to locate the cursor in between SELECT and FROM to enter a field name for instance. To simplify the navigation of the insertion point (cursor) you can make usage of such called **tab snippets**.

In our example SELECT FROM WHERE we need to specify three insertion points SELECT ① FROM ② WHERE ③. To insert such a insertion point placeholder (tab snippet) there is a defined tab snippet template string **${x:}**. **x** represents the tab key order which can be any number between 0 and 18. The third insertion point is nothing else as the end of the query favorite and it will be added automatically thus you have to insert only two tab snippets for ① and ②. We change our query favorite into:

```sql
SELECT ${0:} FROM ${1:} WHERE
```

After insertion that query favorite the Custom Query Editor runs in the tab snippet mode i.e. each tab snippet (insertion point) is highlighted. The first tab snippet is selected and you can start to type. To navigate through the defined tab snippets:

-   press the tab `⇥` key to select next tab snippet _or_ if the current tab snippet is last one leave the tab snippet mode and locate the insertion point (cursor) at the end of the query favorite
-   press `⇧⇥` to select the previous tab snippet (to edit it for instance)

It is also possible to use the mouse by clicking into a defined tab snippet to set the focus on it.

If you click, enter a character, or move the insertion point by the cursor keys outside of a defined tab snippet you will leave the tab snippet mode.

A mirrored tab snippet is not allowed inside of a `${x:}` tab snippet and causes mismatches.

##### Nested Tab Snippets

By means of tab snippets you can generalize the query favorite SELECT FROM WHEREdue to the fact that the WHERE clause is optional. This can be achieved by using nested tab snippets. You can change the query favorite into:

```sql
SELECT ${0:field} FROM ${2:${1:table} WHERE }
```

If you change the tab snippet `${2:}` the tab snippet `${1:}` will be deleted automatically.

----------

#### Tab Snippet with Default Value

##### One Default Value

It could be the case that you want use the query favorite mostly for one table but not always. The tab snippet template supports the declaration of a **default value**. The following syntax is used **${x:default_value}**. Given that your preferred table name is _table01_ we can change the query favorite into:

```sql
SELECT ${0:} FROM ${1:table01} WHERE
```

After insertion of that query favorite and selecting the second tab snippet table01 will be selected entirely thus you can assume the suggested default value or you can edit it.

##### Several Fixed Default Values as Completion List

It could be the case that you want use the query favorite mostly for a set of fixed table. The tab snippet template supports the declaration of a **list** of **default value**. The following syntax is used **${x:¦a¦b¦}**. Given that your preferred table names are _table01_, _table02_, and _table03_ we can change the query favorite into:

```sql
SELECT ${0:} FROM ${1:¦table01¦table02¦table03¦} WHERE
```

After insertion of that query favorite and selecting the second tab snippet a narrow-down completion list window appears thus choose your desired item or start to type to narrow-down the list (or press ⌫ to expand the list again).

> _Tip:_ If you use the default list template **¦¦a¦b¦¦** the narrow-down completion list switches to the fuzzy search mode which means that if you have e.g. the list items _reference_ and _ref_base_ you can type simply r_ to narrow-down the list to _ref_base_due to the fuzzy regular expression search strategy .*r.*_.* If you want to switch to the fuzzy search mode coming from the normal list template **¦a¦b¦** simply press ⌃⎋.

##### Dynamic Default Value Due to Current Selected Table

This kind of query favorite SELECT FROM WHERE could be used frequently to select something based on the current selected table for instance. To insert the name of the current selected table you can make usage of the placeholder string **$SP_SELECTED_TABLE**. In addition there are also the placeholders for the current selected database name **$SP_SELECTED_DATABASE** and as a comma separated list the names of the current selected tables **$SP_SELECTED_TABLES** available. Thus we change our query favorite into:

```sql
SELECT ${0:} FROM ${1:$SP_SELECTED_TABLE} WHERE
```

or to allow to invoke the completion easier in order to insert one or more field names in the first tab snippet:

```sql
SELECT ${0:$SP_SELECTED_TABLE.} FROM ${1:$SP_SELECTED_TABLE} WHERE
```

> _Tip:_ You can combine the default list template **¦a¦b¦** with $SP_SELECTED_TABLE for instance as ${1:¦table01¦$SP_SELECTED_TABLE¦}. _See also:_ mirrored tab snippet

##### Usage of Pre-defined Dynamic Lists as Default Value

There are three default lists available:

`¦$SP_ASLIST_ALL_FIELDS¦`

shows a completion list of all field names of the currently selected table

`¦$SP_ASLIST_ALL_TABLES¦`

shows a completion list of all table names (incl. views) of the currently selected database

`¦$SP_ASLIST_ALL_DATABASES¦`

shows a completion list of all database names of the current connection

So you can create e.g. a query favorite to select a new database:

```sql
USE ${1:¦$SP_ASLIST_ALL_DATABASES¦};
```

##### Default Value as Result of a Bash Shell Command

This is an advanced option to run any bash shell command whose result string (must be UTF-8 encoded) will be taken as default value before the query favorite will be inserted into the Custom Query Editor. The placeholder syntax is: **${x:$(shell_command)}**

_Example_ The query favorite:

```sql
`date_field` = '${1:$(date "+%Y-%m-%d" | perl -pe 'chomp')}'
```

will execute the shell command **date "+%Y-%m-%d" | perl -pe 'chomp'** and insert e.g. `date_field` = '2010-03-15'. It is recommended to save the shell command as script on the hard disk and invoke it inside $() due to some escaping issues of } etc. The shell script will be executed via /bin/bash -c shell_command. This allows not only to insert the result of such shell commands like **curl** etc. but also to open other applications like **open -a Preview**, or **open sequelpro.com**, or to use an AppleScript to display a list, a dialog etc. **Each shell command** can be **terminated** by the keystroke **⌘.**

In addition the following shell variables will passed:

-   SP_ALL_DATABASES
-   SP_ALL_FUNCTIONS
-   SP_ALL_PROCEDURES
-   SP_ALL_TABLES
-   SP_ALL_VIEWS
-   SP_APP_RESOURCES_DIRECTORY
-   SP_CURRENT_HOST
-   SP_CURRENT_PORT
-   SP_CURRENT_USER
-   SP_DATABASE_ENCODING
-   SP_ICON_FILE
-   SP_PROCESS_ID
-   SP_QUERY_FILE
-   SP_QUERY_RESULT_FILE
-   SP_QUERY_RESULT_META
-   SP_QUERY_RESULT_STATUS_FILE
-   SP_RDBMS_TYPE
-   SP_RDBMS_VERSION
-   SP_SELECTED_DATABASE
-   SP_SELECTED_TABLE
-   SP_SELECTED_TABLES

#### Mirrored Tab Snippet

The example SELECT ${0:$SP_SELECTED_TABLE.} FROM ${1:$SP_SELECTED_TABLE} WHERE to place the insertion point for invoking the completion has one disadvantage if you want e.g. select the table from a list. To abolish it you can make usage of the mirrored tab snippet placeholder **$x** whereby **x** represents the to be mirrored tab snippet content. It is allowed to specify 20 mirrored tab snippet placeholders. Such a placeholder may **not** be used inside of a ${x:} tab snippet and will cause mismatches. An example:

SELECT $1.${2:} FROM ${1:¦$SP_ASLIST_ALL_TABLES¦} WHERE $1.${3:} = ${4:value} AND $1.$2 =

Each instance of $1 will be replaced by the current content of ${1:} which is still changeable, after choosing a table from the list you press the tab ⇥ key to move the insertion point to ${2:} where you can press ⎋ to open the completion list which will come up with all field names of the chosen table, and so on.

#### EXAMPLES

Here are a few examples you might like to try out:

-   Select Dynamic Fields

    ```sql
    SELECT ${1:DISTINCT }${2:*} FROM ${3:¦$SP_ASLIST_ALL_TABLES¦} ${4:WHERE ${5:clause}}
    ```

-   Use a Database

    ```sql
    USE ${0:¦$SP_ASLIST_ALL_DATABASES¦};
    ```

-   A Standard Query

    ```sql
    SELECT $1.${2:} FROM ${1:¦$SP_ASLIST_ALL_TABLES¦} WHERE $1.${3:} = ${4:value} AND $1.$2 =
    ```


#### Appendix

List of tab snippet placeholders

${x:default_value}

**x** tab index 0…18

${x:$(shell_command)}

**x** tab index 0…18; executes _shell_command_ in the bash interpreter and inserts the result (must be UTF-8 encoded) as default value

$x

**x** tab index 0…18 of the to be mirrored tab snippet; not allowed inside of a tab snippet placeholder ${x:}

List of placeholders for a default value

$SP_SELECTED_TABLE

inserts currently selected table name

$SP_SELECTED_TABLES

inserts a comma separated list of currently selected table names

$SP_SELECTED_DATABASE

inserts currently selected database name

¦$SP_ASLIST_ALL_FIELDS¦

shows a completion list of all field names of the currently selected table

¦$SP_ASLIST_ALL_TABLES¦

shows a completion list of all table names (incl. views) of the currently selected database

¦$SP_ASLIST_ALL_DATABASES¦

shows a completion list of all database names of the current connection
