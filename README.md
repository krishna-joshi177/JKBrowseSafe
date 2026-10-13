# JKBrowseSafe

A privacy-focused browser for **Android** and **Windows**, built with Flutter.

## Features
| Area | What it does |
|---|---|
| Tabs | Tab strip (Windows/tablet) or tab switcher (phone). Tabs are restored when you reopen the app. Links that open a new window open in a new tab. |
| Downloads | Download manager with progress, cancel, open/share, delete. Warns before risky files (.apk, .exe, …). |
| Uploads | `<input type="file">` works through the system file picker. |
| Bookmarks | Add, edit, delete and search. Import/export in the HTML format that Chrome, Edge, Brave and Firefox use. |
| History | Grouped by day, searchable, delete single items or everything. Private tabs never save history. |
| Find in page | Match count, next and previous. |
| Desktop site | Android: switch any tab to desktop mode. |
| Share | Android share sheet; Windows copies the link. |
| Clear data | Clear history, cookies, cache, site permissions and the download list separately. |
| Search engines | DuckDuckGo, Google, Bing, Brave Search, Startpage, Ecosia. |
| Site permissions | Camera, microphone, location and notifications: Ask / Allow / Block for each site. |
| Error pages | Offline, site not reachable, certificate error, page crashed, HTTPS not available. |
| External apps | `mailto:`, `tel:`, `intent:`, Play Store and other app links open the right app (asks first for unknown apps). |
| Back button | Android: closes the find bar, goes back, closes pop-up tabs, then "press back again to exit". |
| Accessibility | Labels on all buttons, page text size, light/dark/system theme, dark web pages, tablet layout, keyboard shortcuts. |
| Versioning | Every GitHub build gets a new version (`1.1.<build number>`), shown in Settings > About. |
| Crash logs | Saved only on the device, with web and e-mail addresses removed. Never uploaded; you can view, share or delete them. |

## Keyboard shortcuts (Windows)
Ctrl+T new tab · Ctrl+Shift+N private tab · Ctrl+W close tab · Ctrl+L address bar · Ctrl+F find · Ctrl+R / F5 reload · Ctrl+D bookmark · Ctrl+H history · Ctrl+J downloads

## Build
Push to `main`. GitHub Actions analyzes the code, runs the tests and builds both apps. Download them from the run's **Artifacts**.

## Known limitations
- Android downloads are saved in the app's own Downloads folder. Use **Open with…** in Downloads to open or save them elsewhere.
- On Android, opening a private tab can sign you out of sites in normal tabs (an Android WebView limitation).
- Websites can't send notifications on Android.
- `blob:` downloads are not supported yet.
- The APK is signed with a debug key. Create your own signing key before publishing to the Play Store.
