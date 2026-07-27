# Keep provider authentication in the user's browser

Diduny will reuse the user's normal browser session for authenticated remote media instead of maintaining a separate Google or YouTube session. Diduny may remember the selected browser and profile, but it will not copy or persist provider cookies; this keeps credential storage and session revocation within the browser while allowing later URL transcriptions to run headlessly until that session expires.
