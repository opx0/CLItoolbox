package main

import (
	"fmt"
	"image"
	_ "image/jpeg"
	"image/png"
	"os"
	"path/filepath"
	"strconv"
	"time"

	"github.com/go-vgo/robotgo"
	"github.com/jung-kurt/gofpdf"
	"github.com/kbinani/screenshot"
)

const (
	screenshotDirPrefix = "Pictures"
	screenshotPrefix    = "Q"
	screenshotExt       = ".png"
)

func captureScreenshot(filePath string) error {
	oldStderr := os.Stderr
	devNull, err := os.OpenFile(os.DevNull, os.O_WRONLY, 0)
	if err == nil {
		os.Stderr = devNull
	}

	bounds := screenshot.GetDisplayBounds(0)
	img, captureErr := screenshot.CaptureRect(bounds)

	if devNull != nil {
		os.Stderr = oldStderr
		devNull.Close()
	}

	err = captureErr

	if err != nil {
		return fmt.Errorf("screenshot capture failed: %w", err)
	}

	file, err := os.Create(filePath)
	if err != nil {
		return fmt.Errorf("failed to create file: %w", err)
	}
	defer file.Close()

	if err := png.Encode(file, img); err != nil {
		return fmt.Errorf("failed to encode PNG: %w", err)
	}

	return nil
}

func getImageDimensions(filePath string) (int, int, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return 0, 0, err
	}
	defer file.Close()

	img, _, err := image.DecodeConfig(file)
	if err != nil {
		return 0, 0, err
	}

	return img.Width, img.Height, nil
}

func main() {
	if len(os.Args) != 2 {
		fmt.Println("Usage: go run main.go <number_of_repetitions>")
		os.Exit(1)
	}
	repetitions, err := strconv.Atoi(os.Args[1])
	if err != nil || repetitions < 1 {
		fmt.Println("Error: Please provide a valid positive number")
		os.Exit(1)
	}

	homeDir, err := os.UserHomeDir()
	if err != nil {
		fmt.Printf("Error getting home directory: %v\n", err)
		os.Exit(1)
	}
	screenshotDir := filepath.Join(homeDir, screenshotDirPrefix)
	if err := os.MkdirAll(screenshotDir, 0755); err != nil {
		fmt.Printf("Error creating screenshot directory: %v\n", err)
		os.Exit(1)
	}

	fmt.Println("Position cursor now! Starting in 5 seconds...")
	for i := 5; i > 0; i-- {
		fmt.Printf("%d... ", i)
		time.Sleep(1 * time.Second)
	}
	fmt.Println("\nStarting automation...")

	var screenshotFiles []string
	for i := 1; i <= repetitions; i++ {
		fmt.Printf("[%d/%d]\n", i, repetitions)

		fileName := fmt.Sprintf("%s_%d%s", screenshotPrefix, i, screenshotExt)
		filePath := filepath.Join(screenshotDir, fileName)

		if err := captureScreenshot(filePath); err != nil {
			fmt.Printf("Error taking screenshot: %v\n", err)
			continue
		}

		fmt.Printf("Screenshot saved: %s\n", filePath)
		screenshotFiles = append(screenshotFiles, filePath)

		time.Sleep(500 * time.Millisecond)
		robotgo.Click("left")
		time.Sleep(500 * time.Millisecond)
	}

	pdfTime := time.Now().Format("150405")
	pdfName := fmt.Sprintf("Qz_%s.pdf", pdfTime)
	pdfPath := filepath.Join(screenshotDir, pdfName)
	fmt.Println("Converting to PDF with original image dimensions...")

	pdf := gofpdf.New("P", "pt", "", "")
	pdf.SetAutoPageBreak(false, 0)

	for _, file := range screenshotFiles {
		imgWidth, imgHeight, err := getImageDimensions(file)
		if err != nil {
			fmt.Printf("Error reading image dimensions for %s: %v\n", file, err)
			continue
		}

		pdf.AddPageFormat("P", gofpdf.SizeType{Wd: float64(imgWidth), Ht: float64(imgHeight)})
		pdf.Image(file, 0, 0, float64(imgWidth), float64(imgHeight), false, "", 0, "")
	}

	if err := pdf.OutputFileAndClose(pdfPath); err != nil {
		fmt.Printf("Error creating PDF: %v\n", err)
		os.Exit(1)
	}

	for _, file := range screenshotFiles {
		if err := os.Remove(file); err != nil {
			fmt.Printf("Error deleting file %s: %v\n", file, err)
		}
	}

	fmt.Printf("✓ Done: %s\n", pdfPath)
}
