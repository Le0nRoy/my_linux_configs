#!/bin/bash
# Download YouTube playlist as MP3 files
# Uses yt-dlp with archive tracking to avoid re-downloading
#
# This script is called by the yt-mp3.timer systemd service
# See: ~/.config/systemd/user/yt-mp3.timer
#
# Configuration:
#   PLAYLIST_URL:  YouTube playlist to download
#   DOWNLOAD_DIR:  Where to save MP3 files
#   Archive file:  .downloaded.txt tracks processed videos
#
# Dependencies: yt-dlp

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
