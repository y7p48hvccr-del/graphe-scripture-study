# Session Notes

This file records project-specific behavior decisions and fixes that should persist across coding sessions.

## Working Pattern

- Update this file at the end of a session when a behavior change, architectural rule, or debugging conclusion should be preserved.
- Prefer concise notes about decisions and constraints over full change logs.

## Current Decisions

### Bible navigation and commentary

- Passive passage navigation must not impersonate an intentional verse tap.
- `navigateToPassage` flow must not auto-post `verseSelected`.
- Maps, search, and similar navigation should open the target passage without automatically triggering commentary behavior.

### Verse preview popovers

- Maps and encyclopedia verse links open a verse preview popover first.
- In those popovers, the title opens the Bible reader.
- The tooltip/help text for verse preview popovers should read `Open in Bible`.
- The separate `Open in Bible` button has been removed in favor of the clickable title.

### Devotional behavior

- Devotional links do not navigate directly to the Bible reader.
- Devotional links open a scrollable verse preview popover instead.
- Daily reading content remains its own Bible-reading context and should not be changed by devotional-link behavior.

### Reading plan header

- The far-right passage reference in the daily reading header is plain text only.
- It is not a button and does not open the Bible reader.

### Encyclopedia rendering

- Encyclopedia text should preserve normal paragraph formatting.
- Verse references in encyclopedia content are clickable.
- Strong's-style coding should not appear in the verse preview text.

## Current Known Context

- Commentary instability was traced back to passive navigation posting `verseSelected`.
- Removing that automatic post restored stable behavior.
- Shared verse popover behavior is centered in `LinkedDefinitionView.swift`.
