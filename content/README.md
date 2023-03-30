# Content Prep

Make sure that source content that you want to loop is created without b-frames
and try to cut it just before an iframe. Here is an example command:


```
$> ffmpeg -y -i inout.mp4 -vcodec libx264 -r 30 -g 30 -sc_threshold 0 \
  -keyint_min 30 -frames:v 1170 -bf 0 \
  -refs 6 -an -f mpegts content.ts
```
