Before MW-3, check whether the compose-cache screen bug you found for MW-7
already reproduces in the current single-window build: move the window
between two displays of different sizes/scale factors without resizing it,
and see whether a stale composed image (from the previous screen) is served.
MW-2 only added recompose triggers for fullscreen transitions and live
resize, so a plain screen-to-screen move may not invalidate anything.

If it reproduces, it is a pre-existing v1.5.2 bug, not a multi-window one —
log it in docs/KNOWN_ISSUES.md and assess whether adding screen to the cache
key is worth doing now as a standalone fix rather than waiting for MW-7.

While you have a second display connected, also clear the MW-2 follow-up item
verifying the mainScreen → per-window screen change.

If no secondary display is available, say so and skip both — do not simulate.

Then proceed to MW-3 (AppController extraction) per the plan.