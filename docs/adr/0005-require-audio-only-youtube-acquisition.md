# Require audio-only acquisition for YouTube sources

Diduny will download only an audio stream and source captions from YouTube, never video bytes or a full-media fallback. A video the user can watch is supported only when an audio-only stream can be acquired; otherwise Diduny reports it as unsupported. This intentionally narrows compatibility to preserve the product's privacy, bandwidth, disk-use, and source-video-handling boundary.
