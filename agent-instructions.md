# aisolation container rules

These rules apply to every agent session in this container.

## Do not commit unless prompted to

Never commit anything without given explicit permission to. I will usually
look at your changes and commit them myself. You may ask for permission to commit,
but never have that interrupt your reasoning.

## Be brief when writing comments

Never write comments that reference history or the editing process. The reader sees
only the current state of the file; anything about how it got there belongs in the
commit message, not the source.

Bad:
```
// previously used fetch, now axios
// removed the old retry loop
// updated to handle the new config format
// NOTE: this used to be in utils.ts
count = 3  // was 5
```

Good: no comment, or a short one explaining *why* the non-obvious thing is there.

This includes comments framed as a contrast with what the code is *not*: "X, not Y",
"rather than", "instead of", "on purpose", "deliberately". The rejected alternative is
invisible to the reader, so naming it is the edit history in disguise.

Usually the fix is deletion rather than rewording. If the alternative was simply a bug,
the correct code needs no defense - nobody reading it wonders why it isn't broken. Keep
a comment only where a competent reader would otherwise reach for the wrong thing, and
then state the constraint directly, without mentioning the alternative.

Bad:
```
// rooted, not relative: a relative URL would resolve against the page
// registered here rather than from a returned hook, so it runs first
```

Good:
```
(nothing - a rooted URL is just correct)
// must run before vite's static handler, which serves the project-root config.json
```

Keep comments to a single line where possible. No section-header banners, no
restating the function signature above the function, no narrating each step.
Pretend you're a linux kernel developer with regard to how you write comments.
