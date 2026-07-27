# Transcription Batches Design

## Model

Persist a `TranscriptionBatch` with an identifier, editable name and description, immutable creation date, processing-closed flag, and ordered recording identifiers. Derive counts and status from referenced recordings instead of storing duplicate summary values.

Each in-progress recording persists its latest completed processing checkpoint and the artifact needed by the next step. Existing completed recordings enter a batch by identifier and do not enter the processing queue.

## Flow

1. The composer collects files, YouTube URLs, and existing recording identifiers.
2. Create the batch and recording rows together, then start only work that lacks a completed transcript.
3. Persist each successful pipeline artifact before advancing the item state.
4. On failure, keep the item and checkpoint. Retry schedules the failed step.
5. When no work remains, derive Completed or Completed with Issues and close normal membership editing.

## Deletion integrity

Batch deletion is one destructive operation: resolve all referenced recording identifiers, show their count in confirmation, delete the recordings, remove their references from other batches, then delete the selected batch. Recording deletion uses the same shared reference cleanup. The operation must not leave a batch pointing to a missing recording.

## Reuse

Extend the existing recording storage, duplicate matching, transcript artifact provenance, and file/remote transcription pipeline. Do not introduce Project, Folder, or Calendar models in this slice.
