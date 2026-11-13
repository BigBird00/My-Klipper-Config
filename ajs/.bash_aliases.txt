

#############################################
#              Home Detection               #
#############################################

# Always resolve to real user home, even under sudo
REALHOME="/home/${SUDO_USER:-$USER}"

#############################################
#     Alias Listers/Inspectors.Contents     #
#############################################

showalias() {
    alias "$1" 2>/dev/null || "Alias not found: $1"
}

#-----------------------------------------------------
# combined alias/function inspector
inspect() {
    if alias "$1" &>/dev/null; then
        echo "Alias:"
        alias "$1"
        return
    fi

    if declare -f "$1" &>/dev/null; then
        echo "Function:"
        declare -f "$1"
        return
    fi

    echo "Not an alias or function: $1"
}

#-----------------------------------------------------
# Searchable Alias/Function Browser

browse() {
    local term="$1"

    # Collect aliases and functions with type tags
    {
        alias | sed -E "s/^alias ([^=]+)=.*/A:\1/"
        declare -F | awk '{print "F:" $3}'
    } \
    | sort \
    | awk -v t="$term" '
        BEGIN {
            CYAN = "\033[1;36m"
            BLUE = "\033[1;34m"
            RESET = "\033[0m"
        }
        {
            name = substr($0, 3)
            if (!t || name ~ t) {
                if ($0 ~ /^A:/)
                    print CYAN "alias:   " RESET name
                else
                    print BLUE "func:    " RESET name
            }
        }
    ' \
    | column -t
}

# Usage
#    browse			Lists all aliases and functions.
#    browse ll		Searches for anything containing “ll”.
#    browse git		Searches for git‑related aliases/functions.



#-----------------------------------------------------
# COLORIZED & SEARCHABLE ALIASES
aliases() {
  local search_term="$1"

  awk -v search="$search_term" '
    { sub(/^[ \t]+/, "") }

    /^alias / {
      sub(/^alias /, "")
      split($0, a, "=")
      name = a[1]
      if (!search || name ~ search)
        print "A:" name
    }

    /^[a-zA-Z0-9_]+\(\)/ {
      split($0, a, "(")
      name = a[1]
      if (!search || name ~ search)
        print "F:" name
    }
  ' "$REALHOME/.bash_aliases" \
  | sort \
  | column -x -c "$(tput cols)" \
  | awk '
      BEGIN {
        CYAN = "\033[1;36m"
        BLUE = "\033[1;34m"
        RESET = "\033[0m"
      }

      {
        line = $0
        gsub(/A:/, CYAN "A:" RESET, line)
        gsub(/F:/, BLUE "F:" RESET, line)
        print line
      }
  '
}




#############################################
#              Simple Shortcuts             #
#############################################

alias ll='ls -alh'
alias dir='ls -la'

dfh() { df -h "$@"; }
freeh() { free -h "$@"; }

alias up='cd ..'
alias up2='cd ../..'
alias home='cd'
alias cd..='cd ..'

alias cdlogs='cd /home/ajs/printer_data/logs'
alias cdcfg='cd /home/ajs/printer_data/config'
alias cdconfig='cd /home/ajs/printer_data/config'
alias cdconfigs='cd /home/ajs/printer_data/config'
alias cdgcode='cd /home/ajs/printer_data/gcode'
alias cdlogs='cd /home/ajs/printer_data/logs'

gs() { git status "$@"; }
ping5() { ping -c 5 "$@"; }
ipinfo() { ip -c a; }
ipconfig() { ip a; }

update() { sudo apt update && sudo apt upgrade; }
rebootnow() { sudo reboot now; }
restartnow() { sudo reboot now; }
poweroffnow() { sudo shutdown -h now; }

bashchk() { bash -n "$REALHOME/.bash_aliases"; }

# RELOAD + AUTO-BACKUP
rebash() {
    if bash -n "$REALHOME/.bash_aliases"; then
        # Create a timestamped backup before reloading
        cp "$REALHOME/.bash_aliases" "$REALHOME/.bash_aliases.bak"
        echo "Backup created (~/.bash_aliases.bak)"
        echo "Syntax OK - reloading..."
        source "$REALHOME/.bash_aliases"
    else
        echo "Syntax error - NOT reloading."
    fi
}

# add switch -m to nano so we can use the mouse
alias nano='nano -m'


#############################################
#                   KLIPPER                 #
#############################################
alias klipperports='ls /dev/serial/by-id'
klipperstatus3() { sudo bash "$HOME/printerstatus3.sh"; }
alias klipperrestart='sudo systemctl restart klipper'
alias klipperrestartall='klipper-full-restart'
alias klippernewlog='/home/ajs/printer_data/logs/rotate_klippy_log.sh'
alias klipperplr='rm /home/ajs/klipper/klippy/extras/__pycache__/power_loss_recovery*.pyc && \
truncate -s 0 ~/printer_data/logs/klippy.log && \
sudo systemctl restart klipper'


# Reload systemd safely
alias klipperRestart='sudo systemctl restart klipper'
alias klipperRestartDaemon='sudo systemctl daemon-reload'
alias klipperreload='sudo systemctl daemon-reload'
alias klipperstart='sudo systemctl start klipper'
alias klipperstartall="sudo systemctl start klipper moonraker mainsail"
alias klipperstatus='systemctl status klipper'
alias klipperstop='sudo systemctl stop klipper'
alias klipperstopall='sudo systemctl stop mainsail moonraker klipper'
alias klipperjournal='sudo journalctl -xeu klipper.service --no-pager | tail -n 50'



### moonraker
alias moonrakerrestart='sudo systemctl restart moonraker'
alias moonrakerstatus='systemctl status moonraker'
alias moonrakerstart='sudo systemctl start moonraker'
alias moonrakerstop='sudo systemctl stop moonraker'
alias moonrakerShowGCODEDir='grep -R "gcode_path" -n /home/ajs/moonraker/moonraker.conf'

### mainsail

alias mainsailrestart='sudo systemctl restart mainsail'
alias mainsailstatus='systemctl status mainsail'
alias mainsailstart='sudo systemctl start mainsail'
alias mainsailstop='sudo systemctl stop mainsail'

### nginx
alias nginxStatus='sudo systemctl status nginx'
alias nginxRestart='sudo systemctl restart nginx'


kiauh() { "$REALHOME/kiauh/kiauh.sh" "$@"; }
alias kiauhinstall='kiauhinstall'
alias kiauhupdate='kiauhinstall'
printerstatus() { "$REALHOME/printerstatus.sh" "$@"; }
printerstatus2() { "$REALHOME/printerstatus2.sh"; } # "$@"; }

printerstatus3() { sudo bash "$HOME/printerstatus3.sh"; }
##safer version
##alias printerstatus3a='sudo /home/ajs/printerstatus3.sh'


#############################################
#   Klipper Full Safe Restart + Status      #
#############################################


newklippylog ()
{    truncate -s 0 /home/ajs/printer_data/logs/klippy.log
     sudo systemctl restart klipper
     echo " klippy.log truncated, and klipper was restarted"
}


klipper-full-restart() {
    echo "========================================="
    echo "     Klipper / Moonraker / Mainsail      "
    echo "         Safe Restart + Status           "
    echo "========================================="

    echo
    echo "[STOPPING SERVICES]"
    sudo systemctl stop mainsail
    sudo systemctl stop moonraker
    sudo systemctl stop klipper

    echo
    echo "[RELOADING SYSTEMD]"
    sudo systemctl daemon-reload

    echo
    echo "[STARTING SERVICES]"
    sudo systemctl start klipper
    sudo systemctl start moonraker
    sudo systemctl start mainsail

    echo
    echo "[WAITING 2 SECONDS]"
    sleep 2

    echo
    echo "========================================="
    echo "            SERVICE STATES               "
    echo "========================================="

    for svc in klipper moonraker mainsail; do
        state=$(systemctl is-active "$svc" 2>/dev/null)
        echo "  $svc: $state"
    done

    echo
    echo "========================================="
    echo "               DONE                      "
    echo "========================================="
}




#############################################
#              Script Launchers             #
#############################################

backup() { sudo "$REALHOME/backup.sh" "$@"; }

cleandisk() { "$REALHOME/cleandisk.sh" "$@"; }
clean() { "$REALHOME/cleandisk.sh" "$@"; }
nginxlogfix() { sudo "$REALHOME/nginxlogsfix.sh"; }
klippertryfixnginx() { sudo "$REALHOME/nginxlogsfix.sh"; }

timeshiftclean() { sudo bash "$REALHOME/timeshiftclean.sh" "$@"; }
wifi() { sudo bash "$REALHOME/wifi.sh" "$@"; }
wificonnect() { sudo bash "$REALHOME/wifi.sh" "$@"; }
klippertryfixnginx


shortcuts() { nano "$REALHOME/.bash_aliases"; }

#############################################
#              Search & History             #
#############################################

f() { find . -iname "$@"; }
sf() { sudo find / -iname "$@"; }
sudof() { sudo find / -iname "$@"; }
h() { history | grep "$@"; }
please() { sudo $(history -p !!); }


# Search recursively for a string in files
#  fsearch "string" → searches current directory
#  fsearchrecursive "string" → searches current directory and recurses into sub directories
#  fsearch "string" /path/to/dir → searches a specific directory

fsearchrecursive() {
    local needle="$1"
    local dir="${2:-.}"
    /bin/grep -RIn --color=auto "$needle" "$dir"
}

fsearch() {
    local needle="$1"
    local dir="${2:-.}"
    command grep -In --color=auto "$needle" "$dir"/* 2>/dev/null
}




#############################################
#                listfuncs                  #
#############################################

listfuncs() {
    local file="$1"

    if [[ -z "$file" ]]; then
        echo "Usage: listfuncs <script.sh>"
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        echo "Error: file not found: $file"
        return 1
    fi

    grep -Eo '^[[:space:]]*(function[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*(?=[[:space:]]*\(\)?[[:space:]]*\{)' "$file" \
        | sed -E 's/^[[:space:]]*(function[[:space:]]+)?//' \
        | sort -u
}
#############################################
#              Disk Usage Tools             #
#############################################

duh() { du -sh ./* 2>/dev/null | sort -h; }

topdirs() {
    local NUM="${1:-10}"
    local TARGET="${2:-.}"
    sudo du -xh --max-depth=1 "$TARGET" 2>/dev/null | sort -h | tail -n "$NUM"
}
#############################################
#               KIAUH Install               #
#############################################
kiauhinstall() {
    echo "=== Updating apt and installing git ==="
    sudo apt-get update && sudo apt-get install -y git || {
        echo "Failed during apt operations."
        return 1
    }

    echo "=== Cloning KIAUH into ~/kiauh ==="
    cd "$HOME" || return 1

    if [ -d "$HOME/kiauh" ]; then
        echo "Directory ~/kiauh already exists. Not cloning."
    else
        git clone https://github.com/dw-0/kiauh.git
    fi
}

#############################################
#            Custom Environment             #
#############################################

export EDITOR=nano
export VISUAL=nano

#############################################
#            Custom Environment             #
#   Disable Msgs Like:  Lines 1-7/7 (END)   #
#############################################
# Disable paging for all commands that use less
export PAGER=cat
# disable systemd’s pager explicitly
export SYSTEMD_PAGER=
export SYSTEMD_LESS=
###### also, to prevent the line 
# Tell sudo to preserve the pager variables
#    sudo visudo
#    Add this line:
#         Defaults env_keep += "SYSTEMD_PAGER SYSTEMD_LESS PAGER"
#    Save
