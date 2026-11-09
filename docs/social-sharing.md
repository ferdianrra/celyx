# Social sharing

The selected card layout renders once at 1080 × 1920 and is passed to the selected destination. No send or post is automatic.

## Instagram Stories

1. Register Asterra in [Meta for Developers](https://developers.facebook.com/apps/), following the current [Sharing to Stories setup](https://developers.facebook.com/docs/instagram-platform/sharing-to-stories/).
2. Set the `celyx` target's `ASTERRA_META_APP_ID` build setting to the numeric **Facebook/Meta App ID** for both Debug and Release, then rebuild. This is a public application identifier, not the App Secret, an access token, or the iOS bundle identifier. Never add an App Secret to the app.
3. `Config/Info.plist` expands that setting into `FacebookAppID`. The service passes it as `source_application` on `instagram-stories://share`.
4. The rendered PNG is placed under `com.instagram.sharedSticker.backgroundImage` on the local-only pasteboard, expiring after five minutes. Instagram opens its Story composer and the user confirms posting.

The project currently has no Meta App ID. Until one is supplied, the button explains that Stories sharing is not configured; More and Save remain available. An empty or malformed ID never launches a knowingly incomplete handoff. A syntactically valid ID still needs to be registered/configured correctly in Meta.

## WhatsApp

The button writes the selected card as a JPEG in a unique temporary `.jpg` file and presents `UIActivityViewController`. Select WhatsApp (or WhatsApp Business) in the system share sheet, then confirm the recipient/send in its extension. iOS does not provide a public API to preselect a third-party share extension. This follows [WhatsApp's preferred image-sharing route](https://faq.whatsapp.com/425247423114725/?locale=en_US&cms_platform=iphone).

The sheet retains its file while sharing. Completion and dismissal remove it; abandoned files older than a day are removed on the next handoff. The footer is disabled only while rendering, not while waiting for an external app callback. Cancellation allows immediate retry. There is no hidden document controller or `.wai` handler dependency.

Both query schemes are declared as an array in `Config/Info.plist`, merged with Xcode's generated Info.plist. The new plist is outside the source folder so it is not copied as a bundle resource.

## Verification

Simulator tests cover URL/configuration validation, a decodable JPEG handoff, unique temporary files and cleanup, built Info.plist schemes, missing Instagram configuration and cancelling/retrying the actual native share sheet, and the existing card/copy flow. Simulator results cannot verify Instagram/WhatsApp's receiving apps.

On an iPhone, check each layout with Instagram and WhatsApp installed: verify the correct image arrives, cancel and retry, complete a handoff, and confirm Copy/More still work afterward. If WhatsApp is absent, the system simply does not offer its extension. Instagram requires the Meta App ID first.
