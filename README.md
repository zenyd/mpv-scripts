## speed-transition
This is a lua script for the mpv media player. The purpose of this script is to speed up the video if no subtitles are visible for a certain amount of (user configurable) time. It is inspired by the [speed-between-subs](https://gist.github.com/bitingsock/47c5ba6466c63c68bcf991dd376f1d18) script.

### How it works
The script looks for the next subtitle and if it is ahead by 5 (default) seconds the video gets sped up and resumes normal playback just before the subtitle becomes visible. This is done to prevent audio glitches when speech starts.

### Usage
For the script to work it is necessary to have an appropriate 'text' subtitle selected and visible.

If you want to use it with local files it is necessary to either have `--cache=yes` or `--demuxer-readahead-secs=10` options enabled in your config/cli. A value of `demuxer-readahead-secs>=10` is recommended. The same applies to `--cache-secs` option if it has been set.

The script works best in `video-sync=audio` mode (the default in mpv), because it will then be able to minimize frame drops on speed transition from high->normal. Stutter-free playback is the result.

Sensible defaults have been set, but if you want to change the `lookahead` value take care to not set it larger than what the buffers can provide. This applies to embedded subtitles and not external.

Key Bind|Effect
--------|------
`ctrl + j`|Toggle script on/off
`ctrl + alt+ j`|Toggle skip mode
`alt + j`|Toggle sub visibility on/off (non-styled subs)
`alt + '+'`|Increase speedup
`alt + '-'`|Decrease speedup

## subselect
A lua script for downloading subtitles using a GUI and automatically loading them in mpv. It lets you input the name of the video but mainly tries to guess it based on the video title. Uses subliminal for subtitle download and Python tkinter for GUI. Works both on Windows and Linux (possibly macOS too?).

Right now it only lists subtitles from OpenSubtitles, but has the ability to search for the best subtitle which searches all subtitle providers.

### Prerequisits
1. Install Python 3
2. Make sure Python is in your PATH
3. Linux: Depending on the used distribution installation of `pip` and `tk` may be necessary
3. Install subliminal:  `python -m pip install subliminal` should do the trick

### Installation
Copy subselect.lua and subselect.py into your script folder

### Configuration
Changing the configuration is optional. Options:
* *down_dir*: set the download path for the subtitles
* *subselect_path*: set the subselect.py path
* *sub_language*: set language for subtitles [default english]; value is a 3-letter ISO-639-3 language code

Per default the script tries to download the subtitles into the folder from where the video is being played. Is that not possible it downloads them into your HOME folder, or in Windows into your Downloads folder. You may have to set the subselect.py path manually if the script guesses the wrong mpv configuration directory. If the script is somehow not working as expected, it is recommended to set both *down_dir* and *subselect_path* and make sure they are absolute paths and do exist.

The option to be changed can be put inside a `subselect.conf` file in the lua-settings folder. Create them if they don't exist.
Sample `subselect.conf` if you want to change all options:
```
down_dir=C:\Users\<me>\subtitles
subselect_path=C:\Users\<me>\python_scripts\subselect.py
sub_language=deu
```

### Usage
First invoke the script using `alt + u`, input a movie name, or use the one provided by the script, search and download subtitles. If you want to change the language for the subtitles append `;[3-letter ISO-639-3 code]`. So if you want to search for e.g. german subtitles append `;deu`.
