# Diduny onboarding design QA

## Evidence

- Source visual truth:
  - `/var/folders/r8/jjr_k1zd60sdsk3qgw1css680000gp/T/codex-clipboard-a07ce1c3-1fc4-4b2a-af19-73b80e8925f1.png` — 700 × 1012 px, permission states.
  - `/var/folders/r8/jjr_k1zd60sdsk3qgw1css680000gp/T/codex-clipboard-17fef457-d168-468d-a4a4-aad1b8ab46ea.png` — 962 × 844 px, practice states.
  - `/var/folders/r8/jjr_k1zd60sdsk3qgw1css680000gp/T/codex-clipboard-c7402abb-c6f9-4ba8-b1da-68313caecd3b.png` — 290 × 233 px, production capture panel.
- Implementation: `/Applications/Diduny DEV.app`, built from `1ec88a4`; the clean TEST state used for the attempted capture was restored after the blocked run.
- Intended viewport: fixed 760 × 540 pt native macOS onboarding window, dark appearance; expected Retina capture 1520 × 1080 px.
- State: fresh-install welcome, followed by capture-panel, permissions, sign-in, practice, and ready.
- Implementation screenshot: unavailable. Computer Use reported that the Mac is locked and could not capture the running app.
- Density normalization: not performed because no implementation screenshot could be captured.

## Full-view comparison

Blocked. The source images were opened, but Product Design QA requires the implementation screenshot and source to be combined in the same comparison input. A code/build review is not a substitute.

## Focused region comparison

Blocked for the same reason. The production capture-panel component is reused by the second onboarding screen, but its rendered typography, spacing, colours, image/icon fidelity, and copy still require visual comparison.

## Findings

- [P0] Visual evidence is unavailable.
  - Location: all onboarding screens.
  - Evidence: DEV and TEST builds launch, but the Mac is locked, so no implementation screenshot or interaction capture is available.
  - Impact: fonts and typography, spacing and layout rhythm, colours/tokens, SF Symbol rendering, copy/localization, focus, clipping, and window isolation cannot receive a truthful pass.
  - Fix: unlock the Mac, capture the same English/Ukrainian states at 760 × 540 pt, combine each implementation capture with its matching source, and repeat QA.

## Comparison history

- Pass 1: blocked before comparison because the implementation could not be captured from the locked Mac.

## Implementation checklist

- Capture the clean welcome screen and verify that no Diduny main window is visible behind it.
- Test Continue, Back, Set up later, email focus/Enter, OTP focus, and the capture-panel buttons.
- Capture permission and practice states in English and Ukrainian.
- Compare normalized source/implementation pairs and fix all P0/P1/P2 differences.

final result: blocked
