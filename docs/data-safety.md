# Play Data safety answers

`dartvel store data-safety` writes the answers for Play Console's Data safety
form from what `pubspec.yaml` declares. `dartvel build android --format aab`
runs it too and writes `data-safety.csv` and `data-safety-worksheet.md` beside
the bundle (`build/app/outputs/bundle/release`).

```
dartvel store data-safety                     # the CSV on stdout
dartvel store data-safety --format json       # derived answers and questions
dartvel store data-safety --format worksheet  # the page to work through
dartvel store data-safety --out store/        # both files
dartvel store data-safety --template exported.csv
```

## What "derived" means

In the form, data is *collected* when it leaves the device. A permission shows
access, and a dependency shows code; neither shows that anything is sent. So
the command derives an answer only for a feature whose data flow Dartvel
defines itself, and turns everything else into a TODO question. Nothing is
guessed: a project with no declarations gets no collected data types and the
full list of questions.

## Every mapping

| Declaration | Data type (form label) | Purposes | User choice | Why |
|---|---|---|---|---|
| `dartvel.crashes.sink: dartvel`, not disabled in `release` | App info and performance > Crash logs | Analytics | Required | Release builds post crash reports (error, stack, breadcrumbs, an install-scoped id) to your backend. `sink: none` keeps them on the device and derives nothing. |
| `dartvel.analytics` | App activity > App interactions | Analytics | Optional with a `consent` policy (events record only for a category the user accepted), otherwise Required | Events go to your backend (`store: database`). |
| `dartvel.purchases` | Financial info > Purchase history | App functionality | Required | Receipts are sent to your backend to be verified. Card details are never seen: Google Play takes the payment. |
| `dartvel.auth` | Personal info > User IDs | Account management, App functionality | Required | Accounts have ids on your backend. |

Collected data from these is never marked *shared*: Dartvel's backend is
yours, not a third party. A vendor you add is a question
(`sharing-with-third-parties`).

### Questions, never answers

| Declaration | Question id | Why it cannot be answered |
|---|---|---|
| `dartvel.auth` | `auth-identifiers` | Which sign-up fields (email, name, phone) are yours. Each is its own Personal info type. |
| `dartvel.auth` | `account-creation-methods`, `account-deletion` | Play asks for the methods and a deletion URL. |
| `dartvel.android.permissions`, and what `dartvel.fileStorage` adds | `permission-<name>` | The manifest names the permissions it holds (for example `android.permission.ACCESS_FINE_LOCATION`, which means precise). Whether the data leaves the device is not in the pubspec. |
| A name Dartvel has no permission for | `permission-unknown-<name>` | Nothing was declared for it; fix the name. |
| Dependencies in `firebase_*`, `google_mobile_ads`, `sentry_flutter`, `onesignal_flutter`, `mixpanel_flutter`, `amplitude_flutter`, `appsflyer_sdk`, `adjust_sdk`, `facebook_app_events`, `flutter_facebook_auth`, `google_sign_in`, `geolocator`, `in_app_purchase` | `sdk-<package>` | The SDK's own disclosure decides, and Dartvel does not know what it sends. |
| `dartvel.android.cleartextHosts` not empty | `encryption-in-transit` | Cleartext is allowed to those hosts. |
| Always | `collects-or-shares-any-data`, `data-deletion`, `ephemeral-processing`, `sharing-with-third-parties`, `app-code-network-calls` | A pubspec cannot show that your own code sends nothing, what is deleted, what is held only in memory, or which vendors you added. |

### Encryption in transit

Derived yes when `dartvel.android.cleartextHosts` is empty (a release build
refuses cleartext through its network security config). It covers what Dartvel
sends; `app-code-network-calls` covers your code. The form's own question id
is not published, so this is in the worksheet, not the CSV.

## The CSV and its identifiers

The columns are the Console's: Question ID, Response, Response value, Answer
requirement, label. Per collected type the command writes the type row, the
collected-or-shared row, the user-control row and one row per purpose, using
the id patterns on Google's help page (`PSL_DATA_USAGE_RESPONSES:<type
response>:PSL_DATA_USAGE_COLLECTION_AND_SHARING`, `DATA_USAGE_USER_CONTROL`,
`DATA_USAGE_COLLECTION_PURPOSE`, the `PSL_*` purposes).

Google's help page publishes only two data type identifiers
(`PSL_DATA_TYPES_PERSONAL`/`PSL_NAME`, `PSL_DATA_TYPES_LOCATION`/
`PSL_APPROX_LOCATION`), and none of the types above. So a derived row is
written under an identifier from, in order:

1. `--template`: the CSV you export from the Data safety page. Rows are matched
   on their label (`Financial info > Purchase history`), so the ids are
   Google's own.
2. The two published identifiers.
3. With `--unverified-ids` only: ids recalled from the Console's template that
   Google does not publish (`PSL_USER_ACCOUNT`, `PSL_PURCHASE_HISTORY`,
   `PSL_USER_INTERACTION`, `PSL_CRASH_LOGS`). They are not confirmed; the
   Console reports any it does not know when you import.

A derived answer with no identifier is left out of the CSV and marked TODO in
the worksheet. "Is this data processed ephemerally" is never written: Dartvel
does not track it.

Importing a CSV overwrites answers already in the form (Google's warning), so
export first and read the worksheet before importing.

## Status

Unit tested against the generator and the command. No CSV has been imported
into a real Play Console, so the import itself is unverified; the id patterns
come from Google's Help page
(support.google.com/googleplay/android-developer/answer/10787469).
