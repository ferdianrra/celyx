# Sky event reminders

The bell on a Sky Events list card or event detail opens a native centered confirmation alert before enabling or disabling a reminder. Cancel leaves the saved state unchanged. The card's navigation button and reminder button are siblings, so the bell does not open event details.

Enabling requests iPhone Reminders access through EventKit, then saves an EKReminder in the user's default writable reminder list. The reminder contains the event title, viewing window, direction, description and viewing tips. Its due date and absolute alarm use the viewing-window start. For an ongoing event, the alarm is scheduled immediately; ended events are rejected. Alarm delivery follows the user's Reminders notification and Focus settings.

A result alert confirms a successful save or removal. Permission denial, a missing writable list, and EventKit save/remove errors display an error and preserve the previous bell state. Buttons are disabled while an update is in progress. Turning off removes only the reminder identified by the ID previously saved for that event; an already deleted reminder is treated as removed.

`SkyEventStore` persists event-to-EventKit identifiers under `skyEventReminderIdentifiers` and keeps the existing `skyEventReminders` key for compatibility. Old bell-only flags never created system reminders, so they no longer count as enabled; the user must confirm a real reminder once. Collected event IDs and catalog IDs are unchanged. System reminder IDs are local to the device; this is not a cross-device synchronization layer, and bell state is not continuously reconciled with edits in Reminders.

Views own confirmation/result presentation. `SkyEventStore` owns update state and persistence, while `SkyEventReminderService` owns EventKit authorization and mutations. Its injectable scheduling protocol lets unit tests cover successful saves, denied/failed operations, retries, restoration, deletion scope, and legacy state without modifying a user's reminders.

## Verification

See PROJECT.md for the latest build and test results. Physical iPhone checks should cover granting/denying Reminders permission, finding the saved item in the default list, observing its alert at the viewing-window start, and confirming that disabling removes it. No Calendar event or duplicate Asterra local notification is created.
