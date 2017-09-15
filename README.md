## speed-transition
This is a lua script for the mpv media player. The purpose of this script is to speed up the video if no subtitles are visible for a certain amount of (user configurable) time. It is inspired by [the speed-between-subs](https://gist.github.com/bitingsock/47c5ba6466c63c68bcf991dd376f1d18) script.

### How it works
The script looks for the next subtitle and if it is ahead by 5 (default) seconds the video gets sped up and resumes normal playback just before the subtitle becomes visible. This is done to prevent audio glitches when speech starts.

### Usage
For the script to work it is necessary to have an appropriate 'text' subtitle selected and visible.

If you want to use it with local files it is necessary to either have `--cache=yes` or `--demuxer-readahead-secs=10` options enabled in your config/cli. A value of `demuxer-readahead-secs>=10` is recommended. The same applies to `--cache-secs` option if it has been set.

The script has sensible defaults, but if you want to change the `lookahead` value take care to not set it larger than what the buffers can provide. This applies to embedded subtitles and not external.

Key Bind|Effect
--------|------
`ctrl + j`|Toggle script on/off
`alt + j`|Toggle sub visibility on/off (non-styled subs)
`alt + '+'`|Increase speedup
`alt + '-'`|Decrease speedup