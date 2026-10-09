# Balance retained editor cleanup

Successful main-thread editor destruction now clears the numerical pointer, cached host callbacks/context and both slider targets. A retained view can receive hint, changed and refresh calls without reaching ended plugin storage. Worker destruction preserves an attached editor for retry on the main thread. Direct editor cleanup owns the view; the caller continues to own its numerical processor.

The independently written fixture uses two live native instances, real AppKit views and all three lifetime routes. Each normal, fatal sanitizer and unoptimized run checks 144 instances, 72 attached worker refusals, 432 retained actions and 216 live peer actions. It verifies empty callback/context and target fields before retained actions, so the three broken variants are rejected before accessing ended Instance storage. Every executable is explicitly signed and strictly verified.

This is source lifetime and retained-view safety evidence. Original GUI behavior, original extra destructor callbacks, native allocator/class layout, arbitrary reentrancy/concurrency, application hosting and complete plugin equivalence remain unproved.

Run `python3 verify_retained_editor.py ../../../../.tools/plugin-work/effects/balance-retained-editor-public` from this directory, using a new output directory each time. It requires macOS, Xcode command-line tools and Python 3. No installed original plugin is needed for this own-source fixture. The adjacent production source closure is verified before and after execution.
