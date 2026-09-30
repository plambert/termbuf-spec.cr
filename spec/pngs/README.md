# PNG fixtures

Eight PNG files, six pixels across and four down, one for each shape a PNG comes
in. They are here because the decoder the harness installs is a claim about real
files, and a file this suite wrote itself would only show that it agrees with
itself. Every one is under 110 bytes.

`spec/graphics_spec.cr` asserts what the decoder makes of each, and the pixel
values below are what those examples expect.

| file | colour type | depth | what is in it |
| --- | --- | --- | --- |
| `rgb8.png` | truecolour | 8 | solid red |
| `rgba8.png` | RGBA | 8 | red at half alpha |
| `rgb16.png` | truecolour | 16 | solid red |
| `palette.png` | indexed | 8 | solid green |
| `gray8.png` | greyscale | 8 | mid grey, which decodes to 127 |
| `gray1.png` | greyscale | 1 | black, to exercise a depth under a byte |
| `interlaced.png` | truecolour | 8 | solid blue, Adam7 |
| `keyed.png` | indexed | 8 | a red rectangle from 2,1 to 4,2 on a ground made transparent by a `tRNS` chunk |

`keyed.png` is the one that does not come back as it went in: stumpy_png skips
`tRNS`, so the ground decodes opaque. That is asserted rather than only written
down, so a decoder that grows the chunk fails the example and says so.

Written with ImageMagick 7. `-strip` is what keeps them this small — without it
each carries a few hundred bytes of date and software chunks, which would also
change every time they were regenerated.

```console
magick -size 6x4 xc:'#ff0000' -strip PNG24:rgb8.png
magick -size 6x4 xc:'#ff000080' -strip PNG32:rgba8.png
magick -size 6x4 xc:'#00ff00' -strip PNG8:palette.png
magick -size 6x4 xc:gray50 -colorspace Gray -depth 8 -strip \
  -define png:color-type=0 png:gray8.png
magick -size 6x4 xc:black -colorspace Gray -depth 1 -strip \
  -define png:color-type=0 -define png:bit-depth=1 png:gray1.png
magick -size 6x4 xc:'#ff0000' -strip PNG48:rgb16.png
magick -size 6x4 xc:'#0000ff' -interlace PNG -strip PNG24:interlaced.png
magick -size 6x4 xc:none -fill '#ff0000' -draw 'rectangle 2,1 4,2' -strip \
  PNG8:keyed.png
```
