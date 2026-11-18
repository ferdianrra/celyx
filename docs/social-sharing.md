# Social sharing

The selected card layout renders once at 1080 × 1920 and is passed to the selected destination. No send or post is automatic.

## Instagram Stories

With no Meta App ID, Asterra passes its iOS bundle identifier as `source_application` to `instagram-stories://share`. It hands off the rendered PNG as a movable sticker with a dark blue Story background. Verify the sticker handoff on an iPhone with Instagram installed.

If a numeric `ASTERRA_META_APP_ID` is configured, the app passes that identifier instead and uses the image as a full Story background. Both routes use the local pasteboard with a five-minute expiry. The user confirms posting in Instagram.

## More

More shares the rendered card as a temporary PNG file, preserving transparent corners. Choose WhatsApp or another compatible destination in the iOS share sheet. Completion and dismissal clean up the temporary file.

## Verification

Simulator tests cover URL/configuration validation, a decodable PNG handoff, unique temporary files and cleanup, built Info.plist schemes, bundle identifier and Meta ID payloads and cancelling/retrying the actual native share sheet, and the existing card/copy flow. Simulator results cannot verify Instagram/WhatsApp's receiving apps.

On an iPhone, check each layout with Instagram and WhatsApp installed: verify the correct image arrives, cancel and retry, complete a handoff, and confirm Copy/More still work afterward. If WhatsApp is absent, the system simply does not offer its extension. Test the Instagram sticker handoff with the Meta App ID left blank.
