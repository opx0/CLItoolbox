# Quiz Automation (Go)

Automated screenshot + click tool for quizzes. Takes screenshots, clicks, and generates a PDF.

## Build

```bash
go build -o automate .
```

## Usage

```bash
./automate <number_of_screenshots>
```

Example:
```bash
./automate 10  # Take 10 screenshots with clicks, output PDF
```

## Requirements

- Go 1.19+
- For Wayland: working display
- For X11: X server running

## Dependencies

- `github.com/go-vgo/robotgo` - Mouse/keyboard automation
- `github.com/kbinani/screenshot` - Screen capture
- `github.com/jung-kurt/gofpdf` - PDF generation
