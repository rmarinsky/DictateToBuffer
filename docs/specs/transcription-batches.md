# Transcription Batches

Status: Agreed for implementation on 2026-07-27.

## Goal

Let a user create a durable batch from new files, YouTube URLs, and existing Library recordings, then return to the grouped results after processing finishes.

## Scope

- Keep Batches in the existing Library sidebar design.
- Create a batch when the user chooses Create and Transcribe.
- Generate `Batch — <date>, <time>` when no name is supplied.
- Allow the name and optional description to be edited later.
- Allow new items while processing; close normal membership editing when processing finishes.
- Accept any existing Library recording and reuse its transcript without retranscription.
- Allow the same recording to belong to multiple batches.
- Treat translation as an artifact and `Has Translation` as a Library filter.
- Search batches by name, description, member title, and member transcript.
- Sort batches by immutable creation date, newest first.
- Copy all member transcripts as Markdown with a heading and source type for each member. Include a status placeholder when a transcript is unavailable.

Projects, folders, and Calendar integration are outside this scope.

## Processing and retry

- Derive batch status from its items: Processing, Completed, or Completed with Issues.
- Keep failed and partial items visible with their failed step and retry action.
- Persist the successful result of each YouTube step: metadata, duplicate check, captions, audio download, preparation, upload, and transcription.
- Retry from the failed step and reuse every valid earlier checkpoint.
- Remove intermediate files after the item succeeds or the batch is deleted.

## Deletion

- Deleting a recording removes it from the Library and every batch that references it.
- Deleting a batch deletes the batch and every recording it references, including recordings shared with other batches.
- Before batch deletion, explicitly show the number of recordings that will be deleted and state that shared recordings will disappear from other batches.
- Batch membership and counts update after deletion.

## Acceptance criteria

1. A user can create one batch containing files, YouTube URLs, and selected Library recordings.
2. A completed Library recording is reused without running transcription again.
3. A failed YouTube item exposes its failed step, and Retry does not repeat successful earlier steps.
4. A completed batch remains available with editable name and description, searchable members, creation date, and computed status.
5. Copy Markdown includes every member in batch order and clearly labels unavailable transcripts.
6. Destructive deletion requires confirmation and leaves no dangling batch references.
