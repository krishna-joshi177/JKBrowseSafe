"""Adds permissions, link queries and the app name to the Android manifest
that `flutter create` generates. Safe to run more than once."""
import pathlib

p = pathlib.Path("android/app/src/main/AndroidManifest.xml")
x = p.read_text(encoding="utf-8")

perms = ["INTERNET", "ACCESS_NETWORK_STATE", "CAMERA", "RECORD_AUDIO",
         "MODIFY_AUDIO_SETTINGS", "ACCESS_FINE_LOCATION", "ACCESS_COARSE_LOCATION"]
block = "".join(
    f'    <uses-permission android:name="android.permission.{n}"/>\n'
    for n in perms if f'android.permission.{n}"' not in x)
for feat in ["android.hardware.camera", "android.hardware.microphone",
             "android.hardware.location", "android.hardware.location.gps"]:
    if f'"{feat}"' not in x:
        block += f'    <uses-feature android:name="{feat}" android:required="false"/>\n'

queries = (
    '        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>\n'
    '        <intent><action android:name="android.intent.action.SENDTO"/><data android:scheme="mailto"/></intent>\n'
    '        <intent><action android:name="android.intent.action.DIAL"/><data android:scheme="tel"/></intent>\n'
    '        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="market"/></intent>\n'
)
if 'android:scheme="market"' not in x:
    if "</queries>" in x:
        x = x.replace("</queries>", queries + "    </queries>", 1)
    else:
        block += "    <queries>\n" + queries + "    </queries>\n"

if "usesCleartextTraffic" not in x:
    # Needed only when the user chooses "Continue to site (not secure)".
    x = x.replace("<application", block + '    <application android:usesCleartextTraffic="true"', 1)
else:
    x = x.replace("<application", block + "    <application", 1)

x = x.replace('android:label="safe_browser"', 'android:label="JKBrowseSafe"')
p.write_text(x, encoding="utf-8")
print(x)
