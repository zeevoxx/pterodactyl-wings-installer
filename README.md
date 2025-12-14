# Pterodactyl + Wings Easy Installer
An interactive Bash script to automate the installation of Pterodactyl Panel and Wings daemon on Ubuntu.

This project was created as my first real deep dive into Bash scripting. The goal was simple, to automate a setup process that normally takes me a significant amount of time when done manually, while also learning how Bash behaves in real world server scenarios. The script went through multiple iterations and fixes as I tested it on fresh VMs and resolved issues along the way.

## Features
- Interactive menu (Panel or Wings)
- Automated dependency installation
- MariaDB database setup
- Pterodactyl Panel configuration
- Crontab and queue worker setup
- Automatic Wings binary detection (amd64 / arm64)

## Requirements
- Ubuntu Server 24.04 (tested, could work on previous versions)
- Fresh VM or VPS recommended
- User with sudo privileges

## Notes
- This was my **first ever Bash script** and took a lot of time to build through trial, error and testing.
- A **small portion** of the script (initial menu structure and random password generation) was assisted by AI.
- The remaining script was implemented by reading official documentation, testing on fresh VMs and fixing issues as they appeared.
- **Wings will NOT start** until a valid config.yml file is placed at: /etc/pterodactyl/
