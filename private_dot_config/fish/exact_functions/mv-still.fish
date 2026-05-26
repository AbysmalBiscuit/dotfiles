function mv-still
    set video_exts mp4 mov webm m4v mkv
    set img_exts jpg jpeg png webp

    set videos

    mkdir -p still-videos

    for ext in $video_exts
        set videos $videos *".$ext"
    end

    for vid in $videos
        set images (fd -t f "$vid.+")
        if test -n "$images"
            mv $vid still-videos/
        end
    end
end
