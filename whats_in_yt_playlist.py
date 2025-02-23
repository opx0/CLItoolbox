import os
from pytube import Playlist

def fetch_playlist_links(playlist_url, output_file='YTplaylist_links.txt'):
    try:
        playlist = Playlist(playlist_url)

        os.makedirs(os.path.dirname(output_file) or '.', exist_ok=True)

        with open(output_file, 'w', encoding='utf-8') as f:
            for video_url in playlist.video_urls:
                f.write(f"{video_url}\n")

        print(f"Successfully extracted {len(playlist.video_urls)} video links.")
        return len(playlist.video_urls)

    except Exception as e:
        print(f"An error occurred: {e}")
        return 0

def main():
    playlist_url = input("Enter the YouTube playlist URL: ")
    output_file = input("Enter output filename (press Enter for default 'YTplaylist_links.txt'): ") or 'YTplaylist_links.txt'
    fetch_playlist_links(playlist_url, output_file)

if __name__ == "__main__":
    main()
