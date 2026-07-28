# Re-transcribe an existing recording in place

Status: Superseded by ADR 0009.

`Transcribe Again` will update the existing recording's generated transcript after explicit confirmation instead of creating a second recording or retaining transcript versions. Source captions, source identity, and recording metadata remain attached to the same recording. This keeps the recordings list deduplicated while accepting that the previous generated transcript is replaced.
