package bodyprofile

import (
    "bytes"
    "fmt"
    "image"
    "image/color"
    "image/png"
)

func GeneratePreviewPNG(measurements map[string]float64) ([]byte, error) {
    width := 1024
    height := 1536

    img := image.NewRGBA(image.Rect(0, 0, width, height))
    bg := color.RGBA{128, 128, 128, 255}
    for y := 0; y < height; y++ {
        for x := 0; x < width; x++ {
            img.Set(x, y, bg)
        }
    }

    bodyColor := color.RGBA{180, 180, 200, 255}
    bodyX := width/2 - 150
    bodyY := 200
    bodyW := 300
    bodyH := 1000
    for y := bodyY; y < bodyY+bodyH; y++ {
        for x := bodyX; x < bodyX+bodyW; x++ {
            if x >= 0 && x < width && y >= 0 && y < height {
                img.Set(x, y, bodyColor)
            }
        }
    }

    var buf bytes.Buffer
    if err := png.Encode(&buf, img); err != nil {
        return nil, fmt.Errorf("encode png: %w", err)
    }
    return buf.Bytes(), nil
}
