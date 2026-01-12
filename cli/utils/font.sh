
#!/bin/bash
'''required packages to continue'''
# sudo pacman -S unzip
'''installation location'''
# /usr/share/fonts/

echo "🔽Downloading Nerd fonts:
1. Hack 
2. FireCode
3. JetBrainMono\n"

cd ~/Downloads
wget -nc https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/Hack.zip
wget -nc https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/FiraCode.zip
wget -nc https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/JetBrainsMono.zip
echo "Downloades Done ✅"
# Check if unzip is available
if ! command -v unzip &>/dev/null; then
    echo "unzip is not installed. Installing..."
    sudo pacman -S unzip             # Install unzip using pacman
    if [ $? -eq 0 ]; then
        echo "unzip has been successfully installed."
    else
        echo "Failed to install unzip."
        exit 1
    fi
else
    echo "unzip is already installed."
fi

for file in ~/Downloads/*.zip; do
    echo "Processing file: $file"
    echo "Permission required to write into <usr> dir"
    sudo unzip "$file" -d "/usr/local/share/fonts"     # unzip and move to place where it should be
done

echo "updating the fontconfig cache with the fonts available in the system"
sudo fc-cache -f -v

echo "All Done ✨ ENJOY"
# I don't care if files already exit just overwrite
