### Making Your Scripts Easily Executable from Anywhere

#### **Why Do This?**

- Saves time—no need to navigate to the script’s folder.
- Lets you run scripts like built-in commands.
- Only affects **your user**, keeping system settings untouched.

#### **How to Add a Folder to `$PATH`**

1. **Choose a folder** where you keep your scripts, e.g., `~/my-scripts/`.
2. **Add it to your `$PATH`** by editing your shell config file:
   - For **Zsh** (`~/.zshrc`):
     ```sh
     echo 'export PATH="$HOME/my-scripts:$PATH"' >> ~/.zshrc
     source ~/.zshrc
     ```
3. **Make sure your scripts are executable:**

   ```sh
   chmod +x ~/my-scripts/myscript.sh
   ```

4. **Now, run your script from anywhere:**

   ```sh
   myscript.sh
   ```

5. **if want not to write `script.sh` just create symbolic link in same directory**

   ```sh
   myscript
   ```

### Adding Keybindings in Hyprland

1. **Edit Hyprland config:**
   ```sh
   nvim ~/.config/hypr/hyprland.conf
   ```
2. **Add keybindings:**
   ```ini
   bind = $mainMod+CTRL,W,exec,~/projects/CLItoolbox/paramWifi.sh --watch
   bind = $mainMod+CTRL,S,exec,~/projects/CLItoolbox/paramWifi.sh --switch
   ```
3. **Reload config:**
   ```sh
   hyprctl reload
   ```
   Done! 🚀
