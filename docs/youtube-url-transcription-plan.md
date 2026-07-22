# YouTube URL Transcription Plan

## Outcome

Diduny accepts one or many YouTube URLs, reuses the user's selected Google Chrome session, retrieves original-language captions and audio-only media, and feeds the audio into the existing batch transcription workflow. Source video bytes are never downloaded, uploaded, or retained.

This is a fully supported Diduny feature. It has no Homebrew or user-installed runtime requirement.

## Supported sources

- Individual public, unlisted, private, age-restricted YouTube videos and Shorts that the selected Chrome profile can watch.
- The source must expose an audio-only stream.
- The first release does not support playlists, active livestreams, rentals, DRM-protected media, direct media URLs, generic websites, or providers other than YouTube.

## User flow

1. The user chooses `Transcribe YouTube URLs…` from Recordings or the transcription-batch window.
2. A multiline field accepts any number of YouTube URLs through typing or paste.
3. Diduny normalizes URLs and resolves their canonical video IDs, removing repeated IDs from the submitted batch.
4. On first use, Diduny explains that it will read the selected Chrome profile's existing YouTube session and asks the user to select a profile. Diduny remembers only the Chrome profile identifier.
5. Diduny performs one authorization preflight before downloading anything.
6. If authorization is unavailable or expired, the entire batch enters `Authorization Paused`. Diduny opens YouTube in the selected Chrome profile; after signing in, the user clicks `Retry`.
7. Diduny checks for existing recordings, retrieves original-language captions, downloads audio-only media, and transcribes the audio.
8. Each URL remains visible as its own batch row and can finish completely, partially, as a duplicate, or with an error.

Before the first URL import, show a one-time acknowledgement that the user may process only content they own or are permitted to transcribe.

## Acquisition pipeline

The bundled remote-media extractor performs a metadata-only preflight first. It returns the canonical video ID, title, channel, duration, live/DRM status, available audio-only formats, original language, and caption availability.

For an accepted item:

1. Prefer authored captions in the video's original language.
2. If authored captions are absent, retrieve YouTube's automatic captions in the original language.
3. Download only the best compatible audio-only stream into Diduny's private temporary storage.
4. Normalize or extract the downloaded audio locally into the format expected by the existing recording and transcription pipeline.
5. Pass only the derived audio file to `FileTranscriptionBatchService`; cloud transcription remains disk-backed.
6. Delete acquisition temporary files after the recording owns its prepared audio, and also on failure or cancellation.

There is no full-video fallback. Absence of an accessible audio-only stream produces `Unsupported — no audio-only stream available`.

## Authentication and privacy

- Google Chrome is the only supported browser in the first release.
- The user selects a Chrome profile once and can change it later in settings or from an authorization error.
- Chrome owns cookies, refresh, expiry, revocation, and Google authentication. Diduny does not copy or persist cookies or Google credentials.
- Normal processing is headless while the selected Chrome session remains valid.
- Diduny never embeds Google OAuth, automates password or MFA entry, polls for login completion, or stores browser credentials.
- An expired session pauses the batch before acquisition and resumes only after the user explicitly clicks `Retry` and preflight succeeds.

## Duplicate detection and reuse

Duplicate checks happen before audio acquisition whenever possible:

1. An exact provider plus canonical YouTube video ID match is a duplicate.
2. For historical local imports without provider identity, an exact normalized title plus duration within a two-second tolerance is also an automatic duplicate.
3. Raw URL text, filename alone, or filename plus original byte size are not remote-source identities.

A duplicate row is shown in blue and links to the existing recording. Existing generated transcripts and source-caption artifacts are reused independently. If one artifact is missing, Diduny acquires or generates only that artifact.

`Transcribe Again` requires confirmation and replaces the existing recording's generated transcript. It does not create another recording and does not replace source captions or source identity.

## Artifact and recording model

Each YouTube-backed recording stores:

- YouTube title
- channel name
- canonical URL
- video ID
- duration
- selected Chrome profile identifier only at application-settings level, not in recording metadata
- generated-transcript provenance
- source-caption provenance: authored or automatic, original language, and provider

The generated transcript and source captions remain separate persisted artifacts. The generated transcript is primary in the recording UI; source captions are a labeled companion that can be viewed, copied, or exported separately.

If caption retrieval succeeds but transcription fails, captions remain available. If transcription succeeds but captions fail, the generated transcript remains available. Retry targets only the failed artifact.

## Parallel execution

Use a bounded pipeline rather than processing every URL strictly sequentially:

- Resolve metadata and duplicates concurrently with a small fixed limit.
- Allow at most two simultaneous caption/audio acquisitions.
- Feed prepared audio into the existing transcription scheduler: up to its current cloud concurrency, or one local-model job.
- Continue acquiring the next items while an earlier prepared item is being transcribed, subject to disk-space limits and cancellation.
- A failure or partial success never blocks unrelated items. An authorization pause is the exception because the shared Chrome session is a batch precondition.

New URLs pasted while processing are normalized and appended to the same bounded pipeline.

## Progress and controls

Extend existing per-file rows with these phases:

- Checking link
- Checking duplicate
- Retrieving captions
- Downloading audio
- Preparing audio
- Uploading
- Transcribing
- Finalizing
- Completed
- Partial result
- Duplicate reused
- Authorization paused
- Failed
- Cancelled

Show determinate percentage and transferred bytes for audio acquisition when the extractor reports totals. Keep the active spinner beside the current phase in the concrete item row. Do not add a second current-item preloader. Transcription progress continues using the existing provider progress behavior.

`Stop Batch` cancels active acquisition and transcription tasks, deletes temporary acquisition files, and marks pending items cancelled. Completed and partially completed artifacts remain retriable or reusable.

## Persistence and restart

- Completed recordings and prepared audio follow the existing history-retention setting.
- With history retention set to `Never`, results exist only in the current batch session.
- Closing the batch window does not cancel processing.
- On app restart, completed and prepared recordings remain available; interrupted work is reset to a retriable state.
- Diduny never automatically resumes interrupted URL jobs after restart.

## Bundled runtime and updates

Ship the complete extraction runtime inside the signed and notarized Diduny application. Include required third-party license notices and verify the runtime under hardened-runtime distribution builds.

Runtime compatibility fixes ship through Diduny's existing signed Sparkle application updates. Do not add an independent executable downloader or self-update channel in the first release.

## Failure states

Provide specific, actionable messages for:

- unsupported or malformed YouTube URL
- playlist or livestream URL
- private video unavailable to the selected Chrome profile
- expired Chrome session
- no audio-only stream
- removed, regional, age, rental, or DRM restriction
- caption unavailable, while allowing transcription to continue
- extractor incompatibility requiring a Diduny update
- insufficient disk space
- cancellation
- transcription-provider failure

Do not present provider or extractor stderr directly to the user; retain sanitized diagnostic logs for support.

## Verification

### Unit and service tests

- URL normalization and canonical ID extraction across watch, share, Shorts, and parameterized URLs.
- Duplicate filtering within an active batch.
- Duplicate reuse by video ID and by normalized title plus duration tolerance.
- Authored-caption preference and automatic-caption fallback for original language only.
- Artifact-level partial success and retry.
- Authorization pause and explicit retry without item failure.
- Bounded acquisition and existing transcription concurrency.
- Cancellation and temporary-file cleanup.
- Recording metadata migration remains backward-compatible.

### Bundled-runtime integration tests

- Public, unlisted, private, age-restricted, and Shorts fixtures accessible to a dedicated test Chrome profile.
- Captioned and uncaptioned videos.
- Audio-only output inspection proving that no video track is present.
- No source-video file created and no video bytes sent to the transcription provider.
- Expired-session recovery through Chrome and `Retry`.
- Interrupted jobs remain retriable but do not auto-resume after restart.
- Signed, hardened-runtime, notarized DEV/release builds can execute the bundled runtime.

### UI verification

- Paste many links and append more while processing.
- Per-item acquisition and transcription progress.
- Blue duplicate rows open the reused recording.
- Partial-result presentation and artifact-specific retry.
- Profile selection, one-time Chrome disclosure, authorization pause, and one-time content-rights acknowledgement.
- Closing and reopening the batch window while background processing continues.

## Non-goals

- Google OAuth or an embedded Google login
- Safari, Firefox, Edge, or Brave session integration
- playlists and active livestreams
- downloading or retaining source video
- translated caption tracks
- caption/transcript merging
- transcript version history
- server-side URL fetching
- a separate extractor updater
- providers other than YouTube
