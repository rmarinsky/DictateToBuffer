# Transcription Batches Design

## Model

Persist a `TranscriptionBatch` with an identifier, editable name and description, immutable creation date, processing-closed flag, and ordered recording identifiers. Derive counts and status from referenced recordings instead of storing duplicate summary values.

Persist optional recording title, description, and transcript history. Keep the existing scalar transcript fields as the current projection for compatible consumers; legacy scalar transcripts surface as one history entry.

Each in-progress recording persists its latest completed processing checkpoint and the artifact needed by the next step. Existing completed recordings enter a batch by identifier and do not enter the processing queue.

## Flow

1. Recordings exposes a Batches filter. Its compact composer collects files, YouTube URLs, and existing recording identifiers in one selected-sources list.
2. Create the batch and recording rows together, then start only work that lacks a completed transcript.
3. Persist each successful pipeline artifact before advancing the item state.
4. On failure, keep the item and checkpoint. Retry schedules the failed step.
5. When no work remains, derive Completed or Completed with Issues and close normal membership editing.

Selecting either a recording or a batch opens the native right inspector. A recording opened from a batch retains the batch identifier so `Back to Batch` restores the parent inspector; a directly opened recording has no back action.

Each successful cloud transcription, local transcription, or translation appends a transcript-history entry and updates the scalar current projection. Failures preserve earlier entries. YouTube captions remain separate source artifacts.

## Deletion integrity

Batch deletion is one destructive operation: resolve all referenced recording identifiers, show their count in confirmation, delete the recordings, remove their references from other batches, then delete the selected batch. Recording deletion uses the same shared reference cleanup. The operation must not leave a batch pointing to a missing recording.

## Reuse

Extend the existing recording storage, duplicate matching, transcript artifact provenance, and file/remote transcription pipeline. Do not introduce Project, Folder, or Calendar models in this slice.
