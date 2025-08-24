#!/bin/bash

PLAYLIST_URL="https://youtube.com/playlist?list=PLKTPMmFEcp5kFtDV05yiYC1iOeHF2UL_1&si=UVFcTr5LD2kDUvMH"
DOWNLOAD_DIR="/Data/Downloads/DownloadedMusic"
LOG_FILE="/tmp/yt_playlist_mp3.log"

mkdir -p "$DOWNLOAD_DIR"

yt-dlp \
    --extract-audio \
    --audio-format mp3 \
    --audio-quality 0 \
    -o "$DOWNLOAD_DIR/%(title)s.%(ext)s" \
    --download-archive "$DOWNLOAD_DIR/.downloaded.txt" \
    "$PLAYLIST_URL"
