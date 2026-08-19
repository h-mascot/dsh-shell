# Lessons

- Hero targeting must not use a global accessible-label selector when permanent navigation controls can share that label. Keep explicit markers and bounded structural fallbacks, and put decoys before the target in regression fixtures.
- Build replacement should stage into a unique bundle, preserve any installed bundle with `mv`, and restore it if the install move fails. Failure traps must avoid reserved shell variable names and preserve incomplete staging for diagnosis.
