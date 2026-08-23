# yt-dlp presets, file conversions and media housekeeping.

const YT_COOKIES = "~/.cache/cookies/yt.txt"
const YTP_COOKIES = "~/.cache/cookies/ytp.txt"
const DATED = "%(upload_date>%Y-%m-%d)s %(title)s-%(id)s.%(ext)s"
const STAMPED = "%(upload_date)s-%(title)s-%(id)s.%(ext)s"
const PLAYLIST = "%(playlist)s-%(playlist_index)s_%(upload_date)s-%(title)s-%(id)s.%(ext)s"

alias yt = yt-dlp -ciw --restrict-filename --add-metadata --progress --cookies ~/.cache/cookies/yt.txt -o "%(upload_date>%Y-%m-%d)s %(title)s-%(id)s.%(ext)s"
alias yta = yt-dlp -ciw --restrict-filename --add-metadata --progress --cookies ~/.cache/cookies/yt.txt --download-archive archive.txt -o "%(upload_date)s-%(title)s-%(id)s.%(ext)s"
alias ytp = yt-dlp -ciw --restrict-filename --add-metadata --progress --cookies ~/.cache/cookies/ytp.txt -o "%(upload_date>%Y-%m-%d)s %(title)s-%(id)s.%(ext)s"
alias ytp2 = yt-dlp -ciw --restrict-filename --add-metadata --cookies ~/.cache/cookies/ytp.txt -o "%(upload_date)s-%(title)s-%(id)s.%(ext)s"
alias ytpa = yt-dlp -ciw --restrict-filename --add-metadata --progress --cookies ~/.cache/cookies/ytp.txt --download-archive archive.txt -o "%(upload_date)s-%(title)s-%(id)s.%(ext)s"
alias yt-pl = yt-dlp -ciw --restrict-filename --add-metadata --cookies ~/.cache/cookies/yt.txt -o "%(playlist)s-%(playlist_index)s_%(upload_date)s-%(title)s-%(id)s.%(ext)s"
alias yt-mp3 = yt-dlp -ciw -f bestaudio --embed-thumbnail --extract-audio --audio-format mp3 --restrict-filename --add-metadata --cookies ~/.cache/cookies/yt.txt -o "%(upload_date)s-%(title)s-%(id)s.%(ext)s"
alias yt-pl-mp3 = yt-dlp -ciw -f bestaudio --embed-thumbnail --extract-audio --audio-format mp3 --restrict-filename --add-metadata --cookies ~/.cache/cookies/yt.txt -o "%(playlist)s-%(playlist_index)s_%(upload_date)s-%(title)s-%(id)s.%(ext)s"

# Download every URL listed in `file`, one per line, stopping at the first one
# already in archive.txt.
def ytl [file: path] { yt-from-file $file ($YT_COOKIES | path expand) }
def ytpl [file: path] { yt-from-file $file ($YTP_COOKIES | path expand) }

# Shared body for the list-of-URLs downloaders: read one URL per line, skip
# blanks, and stop at the first entry already recorded in archive.txt.
def yt-from-file [file: path, cookies: path] {
    let urls = (open --raw $file | lines | where {|l| ($l | str trim) != "" })
    ^yt-dlp -ciw --restrict-filename --add-metadata --progress --break-on-existing --cookies $cookies --download-archive archive.txt -o $DATED ...$urls
}

# Convert an html file to Obsidian-flavoured markdown, extracting images
# alongside it into <name>_media/.
def html2md [source: path, out?: path] {
    let target = ($out | default ($source | str replace --regex '\.html?$' '') | str replace --regex '(?:\.md)?$' '.md')
    let media = $"($target | str replace --regex '\.md$' '')_media"
    ^pandoc -f html -t gfm-raw_html --wrap=none --strip-comments --extract-media $media $source -o $target
    print $"Wrote '($target)'"
}

# Strip inline SVG geometry out of the HTML currently on the clipboard.
def strip-svg [] {
    paste
        | ^htmlq --remove-nodes path,circle,rect
        | str replace --all --regex '<svg (id=".+?" )?(class=".+?" )?.+?>' '<svg $1$2>'
}

const VIDEO_EXTS = [mp4 mov webm m4v mkv]

# Move every video in the cwd into vid/.
def mv-vid [] {
    mkdir vid
    ls | where type == file | where {|f| ($f.name | path parse | get extension) in $VIDEO_EXTS }
        | each {|f| ^mv -n -t vid -- $f.name }
    null
}

# Move videos that have a matching still image next to them into still-videos/.
def mv-still [] {
    mkdir still-videos
    let videos = (ls | where type == file
        | where {|f| ($f.name | path parse | get extension) in $VIDEO_EXTS }
        | get name)
    for vid in $videos {
        let stills = (ls | where type == file | get name | where {|n| $n starts-with $"($vid)." and $n != $vid })
        if ($stills | is-not-empty) { ^mv $vid still-videos/ }
    }
}

# yt-dlp's %(upload_date)s is YYYYMMDD; rewrite it to `YYYY-MM-DD ` in place.
def fix-yt-fnames [dir?: path] {
    let target = ($dir | default $env.PWD)
    ls $target | where type == file | each {|f|
        let renamed = ($f.name | str replace --regex '(\d{4})(\d{2})(\d{2})-(.+)$' '$1-$2-$3 $4')
        if $renamed != $f.name { ^mv $f.name $renamed }
    }
    null
}

def cbz2zip [...files: path] { $files | each {|f| rename-ext $f cbz zip } | ignore }
def zip2cbz [...files: path] { $files | each {|f| rename-ext $f zip cbz } | ignore }

def rename-ext [file: path, from: string, to: string] {
    if ($file | path parse | get extension) != $from { return }
    let renamed = ($file | str replace --regex $"\\.($from)$" $".($to)")
    if ($renamed | path exists) {
        print --stderr $"($renamed) already exists, skipping ($file)"
        return
    }
    ^mv $file $renamed
}
