# UI refinement workflow

- For UI work, use the installed `frontend-design` and `impeccable` skills as applicable. Read their instructions before applying them. This project is a Windows PowerShell/WPF application, not a web app: translate design principles to WPF and do not introduce browser frameworks just to use a skill.
- Preserve the user's approved pale-blue background, white rounded gallery panel, custom application artwork and Chinese interface. Refinement must not silently redesign the product.
- Before changing UI, identify all affected states: default, hover, pressed, selected, disabled, empty, loading, error, long labels, pagination boundaries and rapid repeated input.
- Review rendered results at 1440x840 and 900x525. Check alignment, clipping, consistent spacing, icon meaning, contrast, keyboard focus and control hit areas. Do not call an animation visually verified based only on a passing unit test.
- Motion should explain the user's action, respect Windows animation settings, handle interruption, release temporary images, and leave controls usable after completion.
- Keep wallpaper order and explicit user filter choices stable. Default is mixed media with no filter thumb; selecting the same type again clears the filter.
- Do not build or publish a release until the user explicitly requests it. Preview rendering and targeted tests are allowed.
- Native desktop interaction must use Cua Driver in background mode with foreground fallback disabled, per the user's workspace instructions.
## Workspace baseline

Read ../PROJECT_STATE.md and SOURCE_PROVENANCE.md before edits. This is the local unreleased 1.2.0 development version, based on the reconstructed 1.1.1 baseline from the 1.1.0 source candidate and verified 1.1.1 package files. The user wants it uploaded together with other changes later; do not build, upload or release it separately. The parent root sources remain historical 0.2.3. Public release is 1.1.1 and installed version remains 1.1.0 on 2026-10-21; recheck before reporting or releasing. Do not treat the independent Studio preview as the formal product UI. Update parent state records after intentional version changes.
